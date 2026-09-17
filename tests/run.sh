#!/usr/bin/env bash
# Runs the test suites under tests/. The same thing as run.ps1, for a POSIX shell
# (Git Bash on Windows included).
#
#   tests/run.sh                       # everything, headless
#   tests/run.sh driving passage       # matching suites only
#   tests/run.sh --windowed click      # keep a window, so the click tests run
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
coloured=0
runner_args=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--windowed) windowed=1 ;;
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

engine_args=(--path "$root" --script res://tests/framework/test_runner.gd)
if [ "$windowed" -eq 0 ]; then
	engine_args=(--headless "${engine_args[@]}")
fi

# The suites reach each other through class_name, which only resolves once the
# import cache has seen them. Costs a few seconds on a fresh checkout and nothing
# afterwards.
if ! grep -q '"TestCase"' "$root/.godot/global_script_class_cache.cfg" 2> /dev/null; then
	echo "building the script class cache..."
	"$GODOT" --headless --path "$root" --import > /dev/null
fi

"$GODOT" "${engine_args[@]}" -- ${runner_args[@]+"${runner_args[@]}"}
