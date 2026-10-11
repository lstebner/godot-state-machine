#!/usr/bin/env bash
# Runs the test suite headless.
# Set GODOT to your Godot 4 executable if it isn't on your PATH as `godot`.
set -euo pipefail

cd "$(dirname "$0")"

if [[ -n "${GODOT:-}" ]]; then
	godot_cmd=($GODOT)
elif command -v godot >/dev/null; then
	godot_cmd=(godot)
elif flatpak info org.godotengine.Godot >/dev/null 2>&1; then
	godot_cmd=(flatpak run --filesystem=home org.godotengine.Godot)
else
	echo "Godot not found. Set GODOT to your Godot 4 executable." >&2
	exit 1
fi

# make sure the import cache exists (needed on a fresh checkout)
if [[ ! -d .godot ]]; then
	"${godot_cmd[@]}" --headless --path . --import >/dev/null 2>&1
fi

"${godot_cmd[@]}" --headless --path . -s res://tests/run_tests.gd
