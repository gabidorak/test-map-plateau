#!/bin/sh
# Fetches the latest release's Linux build into /data (unless it is already there), then runs it as a dedicated server.
# Keeps the build it has when GitHub can't be reached.
REPO="${REPO:-gabidorak/test-map-plateau}"
ASSET=plateau-map-linux.x86_64
PORT="${PORT:-7777}"
NAME="${SERVER_NAME:-Plateau server}"
cd /data || exit 1

tag=$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/^  "tag_name": "\(.*\)",$/\1/p')
if [ -n "$tag" ] && [ "$tag" != "$(cat tag 2>/dev/null)" -o ! -x "$ASSET" ]; then
    echo "Downloading $tag"
    if curl -fL --retry 3 -o "$ASSET.part" "https://github.com/$REPO/releases/download/$tag/$ASSET"; then
        chmod +x "$ASSET.part" && mv "$ASSET.part" "$ASSET" && echo "$tag" > tag
    else
        rm -f "$ASSET.part"
        echo "Download failed"
    fi
elif [ -z "$tag" ]; then
    echo "Could not reach GitHub, keeping $(cat tag 2>/dev/null || echo nothing)"
fi
[ -x "$ASSET" ] || { echo "No build to run"; sleep 60; exit 1; }

exec "./$ASSET" --headless -- --dedicated --port="$PORT" --name="$NAME"
