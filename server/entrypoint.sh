#!/bin/sh
# Fetches the latest release's Linux build into /data (unless it is already there), then runs it as a dedicated server.
# Keeps the build it has when GitHub can't be reached.
REPO="${REPO:-gabidorak/test-map-plateau}"
ASSET=plateau-map-linux.x86_64
PORT="${PORT:-7777}"
NAME="${SERVER_NAME:-Plateau server}"
cd /data || exit 1

# grep, not line matching: the API answers pretty-printed or compact JSON depending on the client
tag=$(curl -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: plateau-server" \
    "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
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
# not updated: the server would quit for the same release at once, wait so as not to loop on GitHub's rate limit
if [ "$tag" != "$(cat tag 2>/dev/null)" ]; then
    echo "Running an outdated build, retrying in 10 minutes"
    sleep 600
fi
[ -x "$ASSET" ] || { echo "No build to run"; sleep 60; exit 1; }

exec "./$ASSET" --headless -- --dedicated --port="$PORT" --name="$NAME"
