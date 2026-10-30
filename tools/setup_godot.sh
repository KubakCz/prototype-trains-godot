#!/usr/bin/env bash
# Installs the pinned Godot for Linux (x86_64 or arm64) under ~/.local and links it
# as ~/.local/bin/godot. The same script serves a Fedora desktop and the Ubuntu
# agent sandbox; running it again is a no-op once the version is in place.
#
#   tools/setup_godot.sh
#
# Needs curl and unzip. The pin lives here and in project.godot's config/features;
# keep them together when the project moves to another engine release.
set -eu

VERSION="4.7.2-stable"
PREFIX="${GODOT_PREFIX:-$HOME/.local}"

case "$(uname -m)" in
	x86_64) arch=x86_64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) echo "no official Godot build for $(uname -m)" >&2; exit 1 ;;
esac

name="Godot_v${VERSION}_linux.${arch}"
dir="$PREFIX/opt/godot/$VERSION"
bin="$dir/$name"

if [ ! -x "$bin" ]; then
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	echo "downloading $name ..."
	curl -fL --progress-bar -o "$tmp/godot.zip" \
		"https://github.com/godotengine/godot-builds/releases/download/${VERSION}/${name}.zip"
	mkdir -p "$dir"
	unzip -q -o "$tmp/godot.zip" -d "$dir"
	chmod +x "$bin"
fi

mkdir -p "$PREFIX/bin"
ln -sfn "$bin" "$PREFIX/bin/godot"
echo "godot -> $bin"

case ":$PATH:" in
	*":$PREFIX/bin:"*) ;;
	*) echo "note: $PREFIX/bin is not on PATH" >&2 ;;
esac

"$PREFIX/bin/godot" --headless --version
