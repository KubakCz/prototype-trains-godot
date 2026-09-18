#!/usr/bin/env bash
# Runs the test suites under tests/. The same thing as run.ps1, for a POSIX shell
# (Git Bash on Windows included).
#
#   tests/run.sh                       # everything, headless
#   tests/run.sh driving passage       # matching suites only
#   tests/run.sh --windowed click      # keep a window, so the click tests run
#   tests/run.sh --window visible click  # ... and leave it where you can see it
#
# A windowed run opens its window on a private Windows desktop, so nothing of it
# reaches the screen - see tests/private_desktop.ps1, which this hands the launch
# to. --window minimized / offscreen / visible put it on your own desktop instead.
#   tests/run.sh --json results.json
#   tests/run.sh --color always        # colour even when piped
#
# Exits 0 when everything passed or skipped, 1 on any failure, 2 on a bad argument
# or a missing Godot. Set GODOT to point at another binary.
set -u

GODOT="${GODOT:-C:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" > /dev/null 2>&1; then
	echo "Godot not found at $GODOT - set GODOT to its path." >&2
	exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

absolute() {
	case "$1" in
		/* | ?:[/\\]*) printf '%s' "$1" ;;
		*) printf '%s/%s' "$(pwd)" "$1" ;;
	esac
}

windowed=0
window_where=""
coloured=0
runner_args=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--windowed) windowed=1 ;;
		# Where the window goes is the runner's business; that there has to be
		# one is ours. minimized (the default), offscreen or visible.
		--window)
			windowed=1
			shift
			window_where="${1:-minimized}"
			runner_args+=(--window "$window_where")
			;;
		--window=*)
			windowed=1
			window_where="${1#--window=}"
			runner_args+=(--window "$window_where")
			;;
		--color | --color=* | --colour | --colour=* | --no-color | --no-colour)
			coloured=1
			runner_args+=("$1")
			;;
		--json)
			shift
			runner_args+=(--json "$(absolute "${1:-report.json}")")
			;;
		--json=*) runner_args+=(--json "$(absolute "${1#--json=}")") ;;
		*) runner_args+=("$1") ;;
	esac
	shift
done

# Godot prints its colour escapes into a pipe as happily as into a terminal, so
# whether anything is watching is ours to say.
if [ "$coloured" -eq 0 ] && [ ! -t 1 ]; then
	runner_args+=(--color never)
fi

# A windowed run gets a desktop of its own unless it was told otherwise.
if [ "$windowed" -eq 1 ] && [ -z "$window_where" ]; then
	window_where=desktop
	runner_args+=(--window desktop)
fi

engine_args=(--path "$root" --script res://tests/framework/test_runner.gd)
if [ "$windowed" -eq 0 ]; then
	engine_args=(--headless "${engine_args[@]}")
elif [ "$window_where" = "minimized" ] || [ "$window_where" = "offscreen" ]; then
	# Born too small to see, resized by the runner before the first frame - Godot
	# clamps --position back onto the screen, so shrinking it is all that is left.
	engine_args=(--resolution 1x1 --position 0,99999 "${engine_args[@]}")
fi

# The suites reach each other through class_name, which only resolves once the
# import cache has seen them. Costs a few seconds on a fresh checkout and nothing
# afterwards.
if ! grep -q '"TestCase"' "$root/.godot/global_script_class_cache.cfg" 2> /dev/null; then
	echo "building the script class cache..."
	"$GODOT" --headless --path "$root" --import > /dev/null
fi

run_engine() {
	"$GODOT" "${engine_args[@]}" -- ${runner_args[@]+"${runner_args[@]}"}
}

# The private desktop is a Windows API and PowerShell is what reaches it, so the
# launch goes through the same helper run.ps1 uses. 200 back from it means this
# machine would not give us one; anything else is the runner's own verdict.
if [ "$window_where" = "desktop" ]; then
	powershell="$(command -v powershell.exe || command -v pwsh.exe || true)"
	if [ -z "$powershell" ]; then
		echo "no powershell.exe for a private desktop - minimizing instead." >&2
		window_where=minimized
	else
		quote() {
			case "$1" in
				*[[:space:]\"]*) printf '"%s"' "$(printf '%s' "$1" | sed 's/"/\\"/g')" ;;
				*) printf '%s' "$1" ;;
			esac
		}
		# Git Bash would otherwise hand PowerShell a POSIX path, and /c/Godot is
		# not C:\Godot as far as CreateProcess is concerned.
		windows_path() {
			if command -v cygpath > /dev/null 2>&1; then
				cygpath -w "$1"
			else
				printf '%s' "$1" | tr '/' '\\'
			fi
		}
		line="$(quote "$(windows_path "$GODOT")")"
		# Running a Windows binary from Git Bash normally rewrites the paths among
		# its arguments; going through CreateProcess ourselves, nobody does.
		for arg in "${engine_args[@]}" -- ${runner_args[@]+"${runner_args[@]}"}; do
			case "$arg" in
				/*) arg="$(windows_path "$arg")" ;;
			esac
			line="$line $(quote "$arg")"
		done
		helper="$(windows_path "$root/tests/private_desktop.ps1")"
		"$powershell" -NoProfile -ExecutionPolicy Bypass -File "$helper" -CommandLine "$line"
		status=$?
		if [ "$status" -ne 200 ]; then
			exit "$status"
		fi
		# Fall back to the next best hiding place, which wants the small window
		# the desktop run had no use for.
		engine_args=(--resolution 1x1 --position 0,99999 "${engine_args[@]}")
		runner_args=("${runner_args[@]/#desktop/minimized}")
	fi
fi

run_engine
