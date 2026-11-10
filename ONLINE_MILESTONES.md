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
   (host = `--official` server + client) for anything networked, on its own port: 7796-7800 (7790-7795 are taken by
   the existing tests; 7800 is O6's). Tests start a local accounts service with a throwaway SQLite file.
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
- [x] `tools/test_stunts.gd`: scripted jump pays once big then small, flip detected, farming one ramp decays.
- [x] `tools/test_stunts.sh` (port 7800): the same spot jumped on an official server: first-time reward then a small
      one, paid by the accounts service (`firsts` table), with the popup.

## O7 — Fires + firefighter job

**Goal:** fight fires the server lights.

- Fire system: flames + smoke (cheap particles, LOD by distance), fire on building fronts, parked cars, bins,
  grass and woods; slow spread; put out by the water cannon (existing water RPCs).
- Spawner on the server: number of fires grows with firefighters on duty; none when nobody is on duty.
- Duty at the fire station (#1289): lent fire truck or your own (×1.5).
- Pay per fire, shared by the people who sprayed it, response-time bonus.
- Map/minimap markers for active fires (firefighters only).

**Done when:**
- [x] `tools/test_fires.gd`: fire spawns, spreads, water puts it out, pay shared between two sprayers.
- [x] LAN test: client on duty sees fires, hoses one, gets paid (`tools/test_fires.sh`, port 7801: 7796-7800 were taken).
- [x] Perf: 5 fires at once cost < 1 ms per frame on the Iris Xe (PERFORMANCE.md method): 0.3-0.8 ms, PERFORMANCE.md 3.3.

## O8 — Balance + admin

**Goal:** run the economy from real numbers.

- `plateau-admin report`: earnings per hour per job and per account, top earners, accounts above the cap.
- Ban/kick also from the game server's console (`--official` reads admin commands from stdin, `docker attach`).
- Tune prices/pay from the payment log; announce resets if needed.

**Done when:**
- [ ] Report runs on a test database with generated payments.

## O9 — Properties *(proposal: Thomas's choices of 2026-11-09, not agreed with Gabriel yet)*

**Goal:** homes to buy, with an interior the owner is teleported into, a spawn point and a private garage.

- **Addresses:** a hand-picked list in `world/properties.json` (written by `tools/online/properties.py`, like
  `garages.json`): id, address, tier (`standard`, `apartment`, `luxury`), price, the real building (OSM id), its front
  door (a point on the facade and the way it faces), the private parking bays in front (1 / 2 / 4 by tier).
- **Shared ownership:** an address is not exclusive. Every player who buys it owns their own copy of the interior
  behind the same door (like flats in a block), so no address ever runs out.
- **Several per player, one main home:** a player may own several properties and picks the main one, where they
  appear when they log in.
- **Prices:** studio ~50 000 €, apartment ~250 000 €, luxury ~1 000 000 € (in `data/prices.json`).
- **Buying:** a "For sale" sign at the door; E shows the price and what comes with it (panel like Prestige Motors'
  catalogue). Charged by the server, like a vehicle.
- **Interiors:** built where the flat really is, behind the building's real windows (the view out is the real one),
  one instance per owned (address, owner) pair, made only on the machine of a player inside it (never on the server,
  nor for the others). All the instances of an address are at the same place: the host keeps which one each player
  is in and every peer shows only the players in the same one as itself (`net.gd hidden_peers`). E at the front door: in (teleport); E at the inside door: back out in front of the
  building. Three templates: a plain studio, a finished apartment, a refined luxury interior (glass, noble
  materials, a view).
- **Home:** log in at the main home (inside it); the in-game menu adds "Go home".
- **Private garage:** the bays in front of the property are the owner's; a terminal there gets their vehicles out
  (the public garages' rules, scripts/online/garages.gd, with an owner check). For a residence (step 1, the Logements
  de l'X): a residents' terminal and purple bays at its car park (garage kind `residence`, any owner of a flat
  there), and the **garage option** (+10 000 €): a private lift in the flat's hall (a hidden garage of kind `private`)
  that takes the owner straight to the wheel of the vehicle they pick, on a residents' bay.
- **Prestige:** the front door locks (the door panel): locked (the default), only the owner enters; open, while the
  owner is in the game, other players may visit their flat from the entrance's panel ("Visit X's flat") and they
  see each other there.
- **Server:** an accounts table `properties (id, account, property, main, locked, bought)` and
  `/v1/server/property` (buy, set main, lock), like `/v1/server/vehicle`; the account data sent to the game server
  lists them. Admin: `plateau-admin add-property` / `remove-property`.
- **Test mode** (`--online-test`): buying works with the test wallet; the in-game menu adds "Test: go to a property".

**Steps:**
1. Data, doors, buy / enter / leave, the standard interior: all of it in the offline test mode.
2. Server: accounts table + API, LAN and official server (PROTOCOL bump).
3. Main home spawn + "Go home", private garage.
4. Apartment and luxury interiors, door lock and visits.

**Done when:**
- [ ] `tools/test_properties.gd`: buy, enter, leave, main home spawn, private garage spawn, refused when too poor
      (step 1 done: buy, refused when too poor, enter, leave, the view out of the windows, the residents' car park,
      the garage option's lift).
- [ ] pytest: property routes (buy twice, set main, lock, someone else's property refused).
- [x] Online test (`tools/test_properties_online.sh`: accounts service, official server, owners from
      PLATEAU_ONLINE_HOMES until step 2): out of sight between flats, a visitor refused a locked flat, visiting an
      open one, the owner leaving by the lift at the wheel.
- [x] Perf: an interior costs nothing while nobody is inside it (built only on the machine of a player inside).

## O10 — Losplatos Custom *(Thomas's idea of 2026-11-09)*

**Goal:** a repair and paint shop to drive into, in place of building #758 (the LadHyX), after Thomas's references
(ref/LosPalaisosCustom/, corrections.png): grey blocks under anthracite ribbed steel cladding, a sawtooth roof of four
teeth glazed to the north, a roll-up door in the west facade facing the road that rolls up when someone comes near, two
shop windows (the workshop's, the customers' lounge's), two neon signs on poles at the facade's ends, a paved sidewalk
along the road with a lowered kerb and a concrete ramp to the door; inside, the workshop (cream blocks over a yellow
band, blue steel, fluorescent tubes, benches, tyres, posters of made-up brands, its own logo) and the lounge (counter,
leather sofa, coffee, a rack of rims in the window).

- `scripts/losplatos/`: the shop drawn at runtime on #758's footprint in every mode (`losplatos.gd`: door, service bay;
  `losplatos_builder.gd`: its geometry); `builder/world_builder.gd` leaves #758 out of the world (map rebuilt).
- PTA Online (`scripts/online/custom_shop.gd`, `custom_panel.gd`): one's own vehicle stopped in the yellow bay, U (E is
  a turn signal at the wheel):
  repair the bodywork (paid by the damage: the wreck repair's price times the health lost, 50 € at least) and paint it
  (a coat at the repaint price), charged by the host like the garage terminals' (accounts server: no change).
- Round it (Thomas's plan vueDessus.png): straight paved sidewalks (level with the floor at the doors), granite kerbs as
  at Massy-Palaiseau, new asphalt to the road, along the north end and over the yard behind.
- The tow truck job (`scripts/online/tow_job.gd`, `scripts/tow_truck.gd`): duty at the tow terminal in the yard, a lent
  tow truck (the Volvo FH16 tractor made a wrecker: boom, cable, hook, light bar); breakdowns on the bot car routes
  (250 m to 1.4 km away, the waypoint); O hooks one by its front or back (lifted, pinned, rolling on its other wheels;
  online the host hands its simulation to the driver), O sets it down; in the yard it pays base + per_km of the way
  (data/jobs.json "tow").
- Tests: `tools/test_losplatos.gd` (the roof in place of #758's, the paving, the door, the bay, repair, paint),
  `tools/test_tow.gd` (duty, a breakdown, hooked and towed, delivered and paid, the next one, off duty).

## O11 — Villa de charme *(Thomas's plan of 2026-11-09)*

**Goal:** a luxury property of its own: a stone manor in walled grounds in place of buildings #628, #659, #671, #672
(and the shed #620), after Thomas's plan (ref/proprietes/Villa Luxe/: planjeu.png his drawing on the map, the
exterior, gate, fountain, plan and room photos) and the plan he approved (40 × 22 m on two floors, the brown block a
grotto fountain, an outdoor and an indoor pool, 5 M € with per-owner instances like the flats).

- `scripts/villaEnPierreCoteaux/`: drawn at runtime in every mode (`villaEnPierreCoteaux.gd`: the gate, the garage doors, the rooms built only near,
  passers-by put back outside; `villaEnPierreCoteaux_site.gd`: the rubble wall along his red line, the pillars and wrought-iron gate,
  the white gravel drive, forecourt and lane, the perron, patio and terrace, the raised pool deck, the grotto fountain;
  `villaEnPierreCoteaux_house.gd`: the limestone manor, its windows and shutters, the hipped tile roof with dormers and chimneys, the
  floors, the grand stair (a 4 m flight to a landing, two flights on) and the U gallery round the hall's void (no
  floor over the hall), the indoor pool, the garage doors; `villaEnPierreCoteaux_interior.gd`: the rooms' furniture and lights after
  his photos; `scripts/build_kit.gd`, the shared building kit: meshes, materials and procedural textures; `villaEnPierreCoteaux_data.gd`: its place on the map).
  `builder/world_builder.gd` leaves the map's buildings, props and the trees but a belt along the wall out of its
  grounds and plants new ones (cypresses, olives, planes, magnolias); `builder/ground_builder.gd` paints its ground
  lawn; `grass_field.gd` grows lawn tufts there (map rebuilt).
- PTA Online (`scripts/online/properties.gd`, a property whose site is `villa`): the panel at the plaque by the gate
  (buy, open the gate, open it to visitors, visit), its owners let in as they come to the gate (instances: those in
  another owner's villa unseen), out once they have left the grounds; its garage's terminal by the utility room gets
  their vehicles out on its three bays (a hidden garage of kind `private`).
- Test: `tools/test_villaEnPierreCoteaux.gd` (the grounds cleared, a passer-by kept out, bought, let in and the gate opening, the
  grand stair walked up to the first floor, the hall's void, a car out in the garage, out of the grounds).

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
| O6 Stunts | ✅ | `online/stunts.gd` (Main/Mode/Stunts), 10 spots in `world/stunts.json` (`tools/online/stunts.py` + `test_stunts.gd --trial`), accounts `pay` `once` + `firsts`, PROTOCOL 16. test_stunts.sh green. Fixed: a taken-over car could keep a snap's velocity. |
| O7 Fires + firefighter job | ✅ | `online/fires.gd` + `fire_job.gd` (Main/Mode/Fires, FireJob), `fire_fx.gd`, 2 417 spots in `world/fires.json` (`tools/online/fires.py`), jobs.json "fire", water judged from the server's own flight of each jet, PROTOCOL 17. test_fires.sh green. 5 fires 0.3-0.8 ms on the Iris Xe. |
| O8 Balance + admin | ⬜ | |
| O9 Properties | 🟡 | Proposal (branch `proprietesOnline`). Step 1 under way: the studio of the Logements de l'X 19 (3rd floor, north face, ~50 m²) in the offline test: `online/properties.gd`, `studio_builder.gd`, `property_panel.gd`, `data/properties.json`, open window frames in `logements_x_builder.gd`; the residents' car park and the garage option's lift (garage kinds `residence` and `private` in `garages.gd`); instances (players seen only in the same flat) and visits (doors open / locked). test_properties.gd green, test_properties_online.sh green (2 players). Online owners come from PLATEAU_ONLINE_HOMES until step 2. |
| O10 Losplatos Custom | 🟡 | Branch `losplatosCustom`: the shop in place of #758, its door, repairs and paint, its paved site, the tow truck job. test_losplatos.gd and test_tow.gd green. Needs the map rebuilt (#758 left out). |
| O11 Villa de charme | 🟡 | Branch `villaLuxe`: the estate in place of #628, #659, #671, #672 (and #620), its house, rooms, pools, fountain, gate and garage; buying and entering it in PTA Online (offline test; online owners from PLATEAU_ONLINE_HOMES). test_villaEnPierreCoteaux.gd green. Needs the map rebuilt. |
