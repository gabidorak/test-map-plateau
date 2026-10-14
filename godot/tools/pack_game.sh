#!/usr/bin/env bash
# tools/pack_game.sh <game.pck> <output folder>
#
# Compresses an exported game pack for the packed release builds (.github/workflows/build.yml): 32 MB chunks, each
# compressed with zstd -19 (separate chunks keep the memory used by scripts/boot.gd, which unpacks them, small), and a
# manifest.json listing them with their plain sizes. The id (start of the pack's sha256) names the unpacked file in
# the players' cache folder, so every build unpacks its own. Needs zstd.
set -euo pipefail

pck=$1
out=$2
chunk=$((32 * 1024 * 1024))

rm -rf "$out"
mkdir -p "$out"
split -b "$chunk" -d -a 3 "$pck" "$out/game_"

{
	printf '{"id": "%s", "size": %d, "chunks": [' "$(sha256sum "$pck" | cut -c1-16)" "$(stat -c %s "$pck")"
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
