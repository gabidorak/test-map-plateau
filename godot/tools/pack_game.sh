#!/usr/bin/env bash
# tools/pack_game.sh <game.pck> <output folder>
#
# Compresses an exported game pack for the packed release builds (.github/workflows/build.yml): 32 MB chunks, each
# compressed with zstd -19 (separate chunks keep the memory used by scripts/boot.gd, which unpacks them, small), and a
# manifest.json listing them with their plain sizes. The id is the data id (tools/pck_tool.py content-id): it names the
# unpacked file in the players' data folder and the delta patches lead from one id to another (scripts/delta.gd). The
# release's tag, run number and commit come from the TAG, RUN and COMMIT environment variables (CI); without TAG the
# build has no version and never looks for updates. Needs zstd and python3.
set -euo pipefail

pck=$1
out=$2
chunk=$((32 * 1024 * 1024))
here=$(dirname "$0")

rm -rf "$out"
mkdir -p "$out"
split -b "$chunk" -d -a 3 "$pck" "$out/game_"

{
	printf '{"id": "%s", "size": %d, "tag": "%s", "run": %d, "commit": "%s", "chunks": [' \
		"$(python3 -I "$here/pck_tool.py" content-id "$pck")" "$(stat -c %s "$pck")" "${TAG:-}" "${RUN:-0}" "${COMMIT:-}"
	sep=""
	for f in "$out"/game_*; do
		printf '%s{"file": "%s.zst", "size": %d}' "$sep" "$(basename "$f")" "$(stat -c %s "$f")"
		sep=", "
	done
	printf ']}\n'
} > "$out/manifest.json.tmp"

ls "$out"/game_* | xargs -P "$(nproc)" -n 1 zstd -q -19 --long=27 --rm
mv "$out/manifest.json.tmp" "$out/manifest.json"
du -ch "$out"/*.zst | tail -1
