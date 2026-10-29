#!/bin/sh
# Fetches the latest release's Linux build into /data (unless it is already there), then runs it as a dedicated server.
# Keeps the build it has when GitHub can't be reached.
REPO="${REPO:-gabidorak/test-map-plateau}"
case "$(uname -m)" in
    aarch64|arm64) ASSET=plateau-map-linux.arm64 ;;   # ARM VMs (Oracle Ampere, Graviton...)
    *) ASSET=plateau-map-linux.x86_64 ;;
esac
PORT="${PORT:-7777}"
NAME="${SERVER_NAME:-Plateau server}"
MODE="${GAME_MODE:-sandbox}"   # sandbox or escape (Escape from Plateau)
# OFFICIAL=1: the PTA Online server, players log in (PLATEAU_ACCOUNTS_URL and PLATEAU_SERVER_SECRET, from compose.yaml)
OFFICIAL_FLAG=$([ -n "$OFFICIAL" ] && [ "$OFFICIAL" != 0 ] && echo --official)
cd /data || exit 1
DATA="/data/.local/share/godot/app_userdata/Plateau Map/data"   # unpacked game packs (godot/scripts/delta.gd)

# Each build unpacks its own 1-2 GB pack, and the game only deletes the packs no data/current-<launcher>.json points
# to: a new launcher id (boot scripts changed) leaves the old pointer and pack behind. One executable here, so keep only
# the pointer of build $1 and its pack ("": none, the new build unpacks its own) and drop the rest.
prune() {
    keep=$([ -n "$1" ] && grep -l "\"tag\": *\"$1\"" "$DATA"/current-*.json 2>/dev/null | head -n 1)
    pack=$([ -n "$keep" ] && grep -o '"file": *"[^"]*"' "$keep" | sed 's/.*"\([^"]*\)"$/\1/')
    for f in "$DATA"/current-* "$DATA"/game-*; do
        [ -e "$f" ] && [ "$f" != "$keep" ] && [ "$(basename "$f")" != "$pack" ] && rm -f "$f"
    done
    rm -rf "$DATA/patches"
}
prune "$(cat tag 2>/dev/null)"

# grep, not line matching: the API answers pretty-printed or compact JSON depending on the client
tag=$(curl -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: plateau-server" \
    "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$tag" ] && [ "$tag" != "$(cat tag 2>/dev/null)" -o ! -x "$ASSET" ]; then
    echo "Downloading $tag"
    if curl -fL --retry 3 -o "$ASSET.part" "https://github.com/$REPO/releases/download/$tag/$ASSET"; then
        chmod +x "$ASSET.part" && mv "$ASSET.part" "$ASSET" && echo "$tag" > tag && prune ""
    else
        rm -f "$ASSET.part"
        echo "Download failed"
    fi
elif [ -z "$tag" ]; then
    echo "Could not reach GitHub, keeping $(cat tag 2>/dev/null || echo nothing)"
fi
# not updated: the server would quit for the same release at once, wait so as not to loop on GitHub's rate limit
if [ "$tag" != "$(cat tag 2>/dev/null)" ]; then
    echo "Running an outdated build, retrying in 10 minutes"
    sleep 600
fi
[ -x "$ASSET" ] || { echo "No build to run"; sleep 60; exit 1; }

exec "./$ASSET" --headless -- --dedicated --port="$PORT" --name="$NAME" --mode="$MODE" $OFFICIAL_FLAG
