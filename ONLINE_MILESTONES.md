# PTA Online milestones

Say **"implement OX"** to run one. The design and every decision behind it are in [ONLINE_MODE.md](ONLINE_MODE.md);
this file is only the build plan. Each milestone is self-contained: goal, steps, files, and a "done when" checklist
checked before calling it finished.

## Ground rules (apply to every milestone)

1. **The server decides money.** The client asks (buy, repair, go on duty); the game server judges and the accounts
   service stores. No RPC ever carries "I earned X" from a client.
2. **Solo and LAN don't change.** Sandbox and Escape from Plateau behave exactly as before; the existing test suite
   stays green (see the test-suite notes for the known pre-existing failures).
3. **RPC ids:** new RPCs live in their own nodes (`Main/Economy`, `Main/Jobs/*`), like `Main/Races`, so net.gd's
   RPC ids don't shift. Bump `PROTOCOL` whenever the wire format changes.
4. **Tests:** pytest for the accounts service, a headless `tools/test_<x>.gd` per milestone, and a LAN shell test
   (host = `--official` server + client) for anything networked, on its own port: 7796-7799 (7790-7795 are taken by
   the existing tests). Tests start a local accounts service with a throwaway SQLite file.
5. **Data keyed by OSM ids** (garages, depots, shop), so it survives map rebuilds, like `interiors.json`.
6. **Status notes stay short** (3 lines max). Details go in the milestone's section.
7. When a decision changes, update [ONLINE_MODE.md](ONLINE_MODE.md) first.

---

## O1 — Accounts service

**Goal:** a small HTTPS service on the VPS that holds accounts, wallets and garages.

- `server/accounts/`: Python (FastAPI + uvicorn) + SQLite (`/data/accounts.db`, WAL mode). Runs on aarch64.
- Tables: `accounts` (id, username, display case, password hash, created, renamed_at, banned), `tokens` (hash of
  the token, account, created, last used), `wallet` (balance), `vehicles` (account, model, colour, wrecked,
  upgrades json), `payments` (account, amount, reason, job, time), `reserved_names` (old names for 30 days).
- Public API (through Caddy, `https://<domain>/accounts`): `POST /v1/signup`, `POST /v1/login`, `POST /v1/logout`,
  `POST /v1/logout-all`, `GET /v1/me` (username, balance, vehicles), `POST /v1/rename`.
- Internal API (Docker network only, header with the server secret from an env var): `GET /v1/server/who?token=`,
  `POST /v1/server/pay`, `POST /v1/server/charge` (fails if the balance is too low), `POST /v1/server/vehicle`
  (add, repair, wreck, colour). Every change writes a `payments` row.
- Rules from ONLINE_MODE.md 3.4: username format, case-insensitive + look-alike uniqueness, reserved names, banned
  words (`banned_words.txt`), rename every 30 days, password length + common list (`common_passwords.txt`),
  argon2id hashes, lockout (5 tries → 1 min, doubling), 3 sign-ups per IP per day.
- New accounts start with **5 000 €**.
- Admin CLI (`docker compose exec accounts plateau-admin …`): `reset-password`, `rename`, `ban`/`unban`,
  `give`/`take`, `show <user>` (balance, vehicles, last 50 payments).
- Daily backup: SQLite `.backup` to a host folder **outside** the Docker volume, 14 kept.
- `server/compose.yaml`: `accounts` service, `Caddyfile` route, `server/README.md` section.

**Done when:**
- [x] pytest: every API route, each username/password rule (accepted and refused examples), look-alikes,
      lockout timing, IP limit, rename + reservation, internal API refused without the secret, charge below 0 refused.
- [x] `docker compose up` locally: sign up, log in, `me`, a backup file appears.
- [x] Image builds for linux/arm64 (buildx).

## O2 — Login screen + menu

**Goal:** the menu has Solo / LAN / PTA Online, and PTA Online logs in and joins the official server.

- `main_menu.gd`: three entries. Solo and LAN keep the mode toggle (Sandbox / Escape). PTA Online opens the
  account page: log in / sign up / log out, with the rules checked while typing (same rules as the service, shared
  test vectors).
- `scripts/accounts.gd` (client): HTTPS calls (HTTPRequest), token saved in `user://account.cfg` (never the
  password), "remember me" on by default.
- Game server flag `--official` (+ `PLATEAU_ACCOUNTS_URL`, `PLATEAU_SERVER_SECRET`): only official servers check
  tokens. The client sends its token in a `Main/Economy` RPC right after `_welcome`; the server resolves it, then
  the player's name is their username. No valid token within 10 s → kicked with a message.
- Clear messages: accounts service down, server down, outdated build, banned.
- Official server address in the build (`godot/data/online.json`, not project.godot: see ONLINE_MODE.md 3.2), so PTA
  Online needs no address field.

**Done when:**
- [x] `tools/test_online_login.sh` (port 7796): sign up, join, name = username; bad token kicked; service down →
      message; remembered token joins without typing.
- [x] Solo and LAN unchanged (menu tests, test_lan.sh, test_escape).
- [x] Shots of the menu and account page.

## O3 — PTA Online rules + garages

**Goal:** on the official server, vehicles only come from your garage, at garages, one at a time.

- `scripts/modes/online_mode.gd` ("PTA Online"): `allows("vehicle_menu")` false, no park-car, no clear-vehicles,
  no armed models (`biplane-armed`, `biplane-gunner`, `gaz-tiger`), no Escape, bot traffic on.
- `godot/world/garages.json` from `tools/online/garages.py`: ~8 public garages on OSM car parks (one ≤ ~500 m
  away on the campus), the **bus depot** at Massy-Palaiseau station (bus drivers only), the **fire station** at
  Polytechnique: building #1289 "SPIS" (osm:w1063984911, local ≈ (830, −151); an open canopy with 2.9 m clearance,
  so the fire truck's bays go beside it if the truck doesn't fit under), firefighters only. Each garage: a terminal
  spot + 2-4 spawn bays.
- Garage terminal (E): list of your vehicles, spawn on a free bay. Spawning stows your previous vehicle.
- Locked by default: others can ride as passengers, not drive; a toggle in the vehicle's menu unlocks it for everyone.
- Disconnect: your vehicle is removed after **30 s** (reconnecting in time gets it back).
- Join / respawn on foot next to the nearest garage.
- HUD: wallet (top right), updated by the server.
- M map + minimap: icons and labels for the garages, depots and Prestige Motors.

**Done when:**
- [x] `tools/test_online_rules.gd` + `tools/test_online_rules.sh` (port 7797): U menu closed, terminal spawns only
      owned vehicles, second spawn stows the first, locked car refuses another driver, unlock works, 30 s removal
      and reconnect, armed models refused even with a forged RPC.
- [x] Shots of a garage, the bus depot, the fire station, the map icons.

## O4 — Shop, repairs, colours

**Goal:** buy vehicles in person, repair them, paint them.

- `godot/data/prices.json` (not TOML: see ONLINE_MODE.md 4): price per model (tiers of ONLINE_MODE.md 4.1), repair =
  3 % of the price.
- **Prestige Motors** (existing dealership): talk to Jean-Claude (E) or use a podium terminal → catalogue of cars,
  planes, horse, jet-ski; buying adds the vehicle and spawns it outside.
- **Bus depot / fire station** terminals sell their work vehicles.
- **Repairs:** a wrecked owned vehicle is marked wrecked; the garage terminal offers "repair (X €)". Lent job
  vehicles are repaired for free.
- **Colours:** a palette per vehicle at any garage terminal (price per repaint, small); synced to other players.
- All purchases go through `charge` (server side); the client only shows the result.

**Done when:**
- [x] `tools/test_online_shop.sh` (port 7798): buy the cheapest car with the starting 5 000 €, too poor for the next
      one, wreck → repair charged, repaint visible on the other client, forged buy RPC from a non-official client
      refused.
- [x] Shots of the catalogue, a repainted car.

## O5 — Bus job

**Goal:** earn money driving real lines.

- Duty at the bus depot: take a lent bus or spawn your own there, pick a line (the lines `transit` already builds).
- Going on duty **stows one bot bus** of the line; off duty / leaving / disconnect brings it back.
- Each stop served (in the bay, below 1 m/s, doors open ≥ 3 s) pays; bonuses: fast segment, air time, near misses /
  close overtakes, drift, combo multiplier; penalties: skipped stop, hard crash, off route (bus race rule).
- Owned bus ×1.5. Real players riding on board add a bonus.
- Server-side checks: max speed per model, no teleport, distance vs. time, stop duration; **hourly pay cap** per
  account.
- HUD: line, next stop, timer, combo, money popping in.
- Tune to ~15 000 €/h for a decent run with a lent bus (measure with a bot driving the line).

**Done when:**
- [x] `tools/test_bus_job.gd`: a bot drives a full line on duty → pay within the target band; skipped stop and
      off-route penalised; teleport refused; cap holds.
- [x] `tools/test_bus_job.sh` (port 7799): duty stows a bot bus on the client's view, disconnect brings it back.
- [x] Shots of the HUD at a stop.

## O6 — Stunts

**Goal:** a bonus layer on any vehicle.

- Air time, flips, near misses, top speed, judged on the server from vehicle states.
- `godot/world/stunts.json` (tool picks jumps from the terrain + hand-placed spots): named stunt spots, big reward
  the first time, small after; diminishing returns per spot per hour.
- HUD popup with the stunt's name and reward.

**Done when:**
- [ ] `tools/test_stunts.gd`: scripted jump pays once big then small, flip detected, farming one ramp decays.

## O7 — Fires + firefighter job

**Goal:** fight fires the server lights.

- Fire system: flames + smoke (cheap particles, LOD by distance), fire on building fronts, parked cars, bins,
  grass and woods; slow spread; put out by the water cannon (existing water RPCs).
- Spawner on the server: number of fires grows with firefighters on duty; none when nobody is on duty.
- Duty at the fire station (#1289): lent fire truck or your own (×1.5).
- Pay per fire, shared by the people who sprayed it, response-time bonus.
- Map/minimap markers for active fires (firefighters only).

**Done when:**
- [ ] `tools/test_fires.gd`: fire spawns, spreads, water puts it out, pay shared between two sprayers.
- [ ] LAN test: client on duty sees fires, hoses one, gets paid.
- [ ] Perf: 5 fires at once cost < 1 ms per frame on the Iris Xe (PERFORMANCE.md method).

## O8 — Balance + admin

**Goal:** run the economy from real numbers.

- `plateau-admin report`: earnings per hour per job and per account, top earners, accounts above the cap.
- Ban/kick also from the game server's console (`--official` reads admin commands from stdin, `docker attach`).
- Tune prices/pay from the payment log; announce resets if needed.

**Done when:**
- [ ] Report runs on a test database with generated payments.

## Later

Bus upgrades and liveries, bot passengers at stops, more jobs (race prizes, taxi, delivery, police, ambulance),
a real fire station building at #1289.

---

## Status
| Milestone | State | Notes |
|---|---|---|
| O1 Accounts service | ✅ | `server/accounts/` (71 pytest), compose + Caddyfile, arm64 cross-build without emulation. |
| O2 Login + menu | ✅ | Account page, `accounts.gd`, `economy.gd` (`--official`), test_online_login.sh green. Addresses in `data/online.json`. |
| O3 Rules + garages | ✅ | `online_mode.gd`, `online/garages.gd` + panel, `garages.json` (9 public + depot + fire station), map badges, `add-vehicle` admin. test_online_rules.sh green. |
| O4 Shop, repairs, colours | ✅ | `online/shop.gd` + `prices.gd`, `paint.gd` (`car.gd` set_paint, crash damage online), delivery bays `prestige-motors`, PROTOCOL 14. test_online_shop.sh green (107 checks). |
| O5 Bus job | ✅ | `online/bus_job.gd` (Main/Mode/BusJob), `data/jobs.json`, traffic.gd hold/release, accounts `pay` hourly `cap`, PROTOCOL 15. Bot on the 4606: 14 stops, ~15 200 €/h. test_bus_job.sh green (49 checks). |
| O6 Stunts | ⬜ | |
| O7 Fires + firefighter job | ⬜ | |
| O8 Balance + admin | ⬜ | |
