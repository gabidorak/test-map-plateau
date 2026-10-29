# Dedicated server for the game (godot/scripts/game.gd --dedicated). The image holds no game: entrypoint.sh downloads
# the latest GitHub release at each start, and the server quits when a newer one is out (restart: unless-stopped).
# Builds as is on x86_64 and ARM64 hosts (multi-arch base image; entrypoint.sh picks the matching release asset).
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --home-dir /data plateau
COPY entrypoint.sh /entrypoint.sh
USER plateau
WORKDIR /data
VOLUME /data
EXPOSE 7777/udp
ENTRYPOINT ["/entrypoint.sh"]
