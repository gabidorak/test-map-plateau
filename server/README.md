# Dedicated server

Runs the game 24/7 as a headless server (`godot/scripts/game.gd --dedicated`): no player of its own, LAN-style
ENet over **UDP 7777**. The image holds no game: at each start `entrypoint.sh` downloads the latest GitHub release
(skipped when it already has it). The server checks for a new release every 5 minutes and quits once one is out and
nobody plays (or after 30 minutes regardless); Docker restarts it on the new build.

## On the VPS

```sh
git clone https://github.com/gabidorak/test-map-plateau.git   # or copy just this folder
cd test-map-plateau/server
docker compose up -d --build
docker compose logs -f                                        # "Dedicated server on UDP port 7777 (build-N)"
```

- DNS: an `A` record for your domain pointing to the VPS (if it is on Cloudflare: **DNS only**, grey cloud; their
  proxy does not carry UDP).
- Firewall: open UDP 7777 (`sudo ufw allow 7777/udp`, plus the VPS provider's firewall if it has one). Docker's
  port mapping usually bypasses ufw anyway.
- Caddy is not involved: it serves HTTP, the game speaks raw UDP straight to the container.
- Players: Join a game → address `your.domain`, port `7777`.
- x86_64 VPS only (the release has no ARM build). It takes ~450 MB of RAM and a few % of a CPU core.

Settings in `compose.yaml`: `SERVER_NAME`, and `PORT` (then change the port mapping to match). To force an update
right away: `docker compose restart`.
