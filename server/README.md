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
docker compose logs -f                                        # "Dedicated server on UDP port 7777, Sandbox (build-N)"
```

- DNS: an `A` record for your domain pointing to the VPS (if it is on Cloudflare: **DNS only**, grey cloud; their
  proxy does not carry UDP).
- Firewall: open UDP 7777 (`sudo ufw allow 7777/udp`, plus the VPS provider's firewall if it has one). Docker's
  port mapping usually bypasses ufw anyway.
- Caddy is not involved: it serves HTTP, the game speaks raw UDP straight to the container.
- Players: Join a game → address `your.domain`, port `7777`.
- x86_64 or ARM64 (`entrypoint.sh` downloads `plateau-map-linux.x86_64` or `plateau-map-linux.arm64` by
  `uname -m`). It takes ~450 MB of RAM and a few % of a CPU core.

## On an Oracle Cloud Ampere (ARM64) VM, Ubuntu

1. Docker (official repository, it has arm64 packages):

   ```sh
   sudo apt-get update && sudo apt-get install -y ca-certificates curl git
   sudo install -m 0755 -d /etc/apt/keyrings
   sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
   sudo chmod a+r /etc/apt/keyrings/docker.asc
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
   https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
       | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt-get update
   sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   sudo usermod -aG docker "$USER"     # then log out and back in, to run docker without sudo
   ```

2. Oracle's firewall, in the web console: Networking → Virtual cloud networks → the instance's VCN → its subnet →
   Security list (or the instance's network security group) → Add ingress rule: source CIDR `0.0.0.0/0`,
   IP protocol **UDP**, destination port range `7777`. Without it, no packet reaches the VM.

3. The VM's own firewall: Oracle's Ubuntu images ship iptables rules that reject everything but SSH (leave `ufw` off,
   it fights them). Docker's port mapping goes through the FORWARD chain, which Docker puts its rules in front of, but
   opening the port in INPUT as well keeps it working if the rules are reloaded after Docker starts:

   ```sh
   sudo iptables -I INPUT 6 -p udp --dport 7777 -j ACCEPT
   sudo netfilter-persistent save
   ```

4. Start it as above (`git clone`, `docker compose up -d --build`). The log should show it downloading
   `plateau-map-linux.arm64` (only releases built since ARM64 support was added have it).

5. DNS: point the domain's `A` record to the instance's public IP (reserve it under Networking → Reserved public IPs,
   or it changes if the instance is recreated), and stop the old server.

6. To keep the race records, copy them over from the old server (see Race records below: `docker compose cp` out on
   the old one, `docker compose stop` / `cp` in / `start` on the new one).

Always Free instances that stay idle (CPU, network and memory use under 20 % over a week, as with this server) can be
reclaimed by Oracle; a Pay As You Go account keeps the free allowance without that rule.

Settings in `compose.yaml`: `SERVER_NAME`, `GAME_MODE` (`sandbox`, or `escape` for Escape from Plateau: the server
starts a mission for the first player to join it, and the next one 25 s after a mission ends), and `PORT` (then change
the port mapping to match). To force an update right away: `docker compose restart`.

## Race records

The leaderboards of the races are the server's: it keeps every player's best times in
`/data/.local/share/godot/app_userdata/Plateau Map/race_records.json`, inside the `plateau-data` volume (`/data` is the
container user's home), so they outlive restarts, updates and image rebuilds. The file is rewritten at each new best
time (through a temporary file, so a crash never leaves half of it). To back it up:

```sh
docker compose cp "plateau:/data/.local/share/godot/app_userdata/Plateau Map/race_records.json" .
```

To edit it (remove a time, rename a player), stop the server first (it reads the file only when it starts), copy the
file back, start it again:

```sh
docker compose stop
docker compose cp race_records.json "plateau:/data/.local/share/godot/app_userdata/Plateau Map/race_records.json"
docker compose start
```

Only `docker compose down -v` (which deletes the volume) loses them.
