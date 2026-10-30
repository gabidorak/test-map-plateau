# PTA Online: an economy on the official server

Status: **being built**: accounts service and login (O1, O2), rules and garages (O3), shop (O4), bus job (O5), stunts (O6) and the firefighter job (O7) done, see the status table in ONLINE_MILESTONES.md. "Decided" = agreed with Gabriel; *(proposal)* = mine and
not agreed yet. Open questions are at the end (Q…).

## 1. Vision

Today the game has two modes: **Sandbox** (all 30 vehicles free from the U menu; races are the only goal) and
**Escape from Plateau** (co-op zombie missions). The new online mode, **PTA Online**, is inspired by GTA Online and
Altis Life: players earn money doing jobs on the **official server** and spend it on vehicles, repairs and upgrades.

Decided:
- Main menu: **Solo**, **LAN**, **PTA Online**.
  - Solo and LAN stay as they are: **Sandbox** (unlimited, every vehicle free) or **Escape from Plateau**.
  - PTA Online joins the official server (the Oracle Ampere VM, aarch64 minimal Ubuntu, 2 vCPU / 12 GB). Everyone
    shares it. It only runs PTA Online: no Escape from Plateau there.
- Money and bought vehicles exist **only online**. Solo and LAN never earn or spend anything.
- **Accounts**: username + password, no email verification. The game remembers the login so players don't retype it.
- The official server is open to **anyone who downloads the game** (a small local audience, not a popular game).
- **1 spawned vehicle per player** online: spawning a new one removes the old one. That's the whole rule.
- Vehicles spawn **only at garages**.
- **No armed vehicles online**: no armed biplane, no gunner biplane, no GAZ Tiger.
- **Paid repairs** online.
- The super cool sports cars cost **5 to 10 hours** of play.
- **Work vehicles** (buses, fire truck…) are lent by their job, and can also be **bought**: an owned one pays more
  and can be customised.
- Bus job on **real lines only**; each player on duty **removes one bot bus** from that line.
- **No money transfers** between players (for now).
- **Ramming / griefing:** nothing special at first; wait and see.

Since solo stays unlimited, there is **no offline garage**: no local cache to protect, no signed unlocks, no trust
in LAN hosts. The garage only matters on the server, which keeps it.

## 2. What already exists to build on

| Need | Already in the game |
|---|---|
| Modes | `scripts/modes/` framework (`allows(feature)`, `host_actions`, HUD hooks), mode carried in `_welcome` + LAN beacon |
| Server | `--dedicated` in Docker on the VPS, auto-update loop, `HOME=/data` volume for saves, Caddy already in front (HTTPS) |
| Persistence | race records in `user://race_records.json` (tmp + rename), survives restarts |
| Shop | Prestige Motors dealership with Jean-Claude the salesman and 13 display cars |
| Bus job | 12 m + 18 m buses, real IDFM routes and stops, `transit.build_route`, bot buses drive them; the bus race already checks "stay on the road" |
| Fire job | fire truck with water cannon; vehicles already catch fire (black smoke) and water puts it out |
| Stunts | races/checkpoints, planes, jumps, vehicle health |
| Social | chat, player list, passengers riding another player's bus |

## 3. Accounts

### 3.1 Service (built in O1: FastAPI + SQLite, `server/accounts/`)

A small **accounts service** next to the game server on the VPS, in the same `compose.yaml`:

- Python (FastAPI or plain `http.server`) + **SQLite** in the `/data` volume. Postgres is overkill for a few hundred
  accounts, and SQLite is one file to back up. Both run fine on aarch64.
- Exposed over **HTTPS through Caddy** (under `https://<domain>/accounts`, Caddy's `handle_path` strips the prefix:
  `server/Caddyfile`), so passwords never travel in clear. ENet game
  traffic is not encrypted, so the password must never go through it.
- Passwords hashed with **argon2** (or bcrypt).
- It owns all persistent player data: accounts, wallet, garage, upgrades, stats.

### 3.2 Login flow (built in O2)

```
game client ──HTTPS──> accounts service : sign up / log in → session token (random, long-lived)
game client ──ENet───> game server     : join with the token
game server ──HTTP (docker network only, server secret)──> accounts service : who is this token? / pay 120 € / buy R8
```

- The game server is the only thing allowed to change money (it calls the service with a server secret on the
  internal Docker network). The client can only log in and read its own data.
- **Remembering the login:** store the **session token** in `user://`, not the password. Same convenience (no
  retyping), but a stolen file can be revoked ("log out everywhere"), and the user's password, which they may
  reuse elsewhere, is never on disk.
- The in-game nickname online is the **username** (unique), so nobody can impersonate someone else.
- Built details (my choices): the game sends its token in `Main/Economy` as soon as the server's welcome arrives, and
  only to the official address; the server kicks with a message after 10 s without a valid login. Logging in to the
  server again from another computer kicks the older connection of that account. The game sends `Plateau-Api: 1`
  with each call; the service answers 426 "please update" below its `MIN_CLIENT_API`. The official addresses live in
  `godot/data/online.json` (not project.godot: its changes alter the launcher id and cost a launcher update).

### 3.3 Consequences of "no email"

- Forgotten password = no self-service reset. The admin resets it by hand (a CLI command in the container,
  `docker compose exec accounts reset-password <user>`).
- Sign-ups need a limit per IP (e.g. 3 per day) so nobody floods the database or farms alt accounts.

### 3.4 Username and password rules

The service checks these rules. The game checks them too, before sending, so the player sees the problem while
typing.

**Usernames**
1. 3 to 16 characters.
2. Only ASCII letters, digits, `_`, `-` and `.`. No spaces, no accents (`é` vs. `e` would make look-alike names).
3. Starts with a letter or a digit; no two separators in a row (`a__b`, `a.-b`); doesn't end with a separator.
4. Unique **without regard to case**: `Gabriel` blocks `gabriel` and `GABRIEL`. The case typed at sign-up is how
   the name is shown.
5. Look-alike names are blocked as well: names are compared after lowercasing and mapping `0→o`, `1→i`, `l→i`,
   `3→e`, `4→a`, `5→s`, `7→t` and dropping `_ - .`. So if `Gabriel` exists, `Gabr1el` and `ga-briel` are refused.
6. Reserved names (in any case and look-alike form): `admin`, `administrator`, `mod`, `moderator`, `server`,
   `system`, `host`, `official`, `pta`, `ptaonline`, `plateau`, `support`, `staff`, `jeanclaude`, `dragon91`,
   `bot`, `null`, `undefined`.
7. Banned words: a short list of French and English insults, slurs and sexual words, kept in
   `server/accounts/banned_words.txt`. A name is refused if its normalised form (rule 5) **contains** one of them.
   Very short entries (≤ 3 letters) only match the whole name, so normal names that happen to contain them still pass.
8. **Renaming:** allowed once every **30 days**, from the account screen. The old name stays reserved for that
   account for 30 days (nobody can take it right away to impersonate the old owner). The admin can rename anyone at
   any time, which is how an offensive name that got past the list is fixed.

**Passwords**
1. 8 to 128 characters, anything allowed (spaces and accents too).
2. Not the username, and not one of the ~1 000 most common passwords (list shipped with the service).
3. No other rules (no forced digits or symbols): length matters more.
4. Five wrong tries on an account → 1 minute lockout, doubling each time (stops guessing without a captcha).

## 4. Vehicles online

- **Spawn rule:** one spawned vehicle per player; spawning another removes the first (stowed, not sold).
- **Job vehicles are lent:** you can always take a bus or a fire truck from the job for free, so a player with
  0 € can still earn. A lent vehicle is your one spawned vehicle like any other.
- **Owned work vehicles earn more** (decided) than lent ones, *(proposal)* ×1.5, and can be customised. Engine
  upgrades and liveries for owned buses, fire trucks and cars are also money sinks.
- **Excluded online:** `biplane-armed`, `biplane-gunner`, `gaz-tiger`. The plain biplane, the horse and the jet-ski
  are fine.
- **Repairs:** a wrecked owned vehicle can't be spawned until repaired. Cost = 3 % of its price,
  paid at a garage or from the menu. Lent job vehicles are repaired free (the job pays), so nobody gets stuck broke.
- **Garages** (decided: the only places to spawn). A garage is a marked parking spot with a terminal (walk up,
  press E, pick a vehicle from your garage, it appears on the free bay):
  - ~8 public garages spread over the map, so one is never more than ~400-500 m away on the campus (fewer in the long
    Massy and west corridors, where the bus and RER B get you around). Picked among the OSM car parks.
  - **Bus depot** at **Massy-Palaiseau station**: a garage reserved for bus drivers (lent buses + your own buses).
  - **Fire station** at **École Polytechnique**: building #1289 "SPIS" (osm:w1063984911, local ≈ (830, −151)), the
    open canopy where the real fire vehicles are kept (not tagged as a fire station in OSM). A garage reserved for
    firefighters (lent fire truck + yours); firefighters on duty spawn there. The canopy has 2.9 m clearance, so the
    bays go beside it if the truck doesn't fit under. A real fire station building may come later.
  - Prestige Motors: a bought vehicle appears outside, ready to drive.
  - New players and players who reconnect appear on foot next to a garage.
- **Buying only in person** (decided): at **Prestige Motors** (the dealership already built in SupOptique) for cars,
  planes, horse and jet-ski, and at the bus depot / fire station for work vehicles. No buying from menus.
- **Map:** Prestige Motors, the garages, the bus depot and the fire station get icons and labels on the M map and
  the minimap.
- **Starting money:** **5 000 €**, enough for the cheapest car.
- **Locks:** your spawned vehicle is **locked by default**: other players can ride as passengers but not drive. A
  toggle unlocks it for everyone.
- **Leaving the server:** your spawned vehicle disappears **30 s** after you disconnect (time to reconnect after a
  dropped connection, and it is still there).
- **Customising** (owned vehicles): **colours** in the first version; liveries and engine upgrades later. For work
  vehicles, the pay bonus can grow with the upgrades.
- Built in O3 (my choices): 9 public garages (Télécom Paris, ENSAE - C2N, Polytechnique - Lac, Polytechnique - Grand
  Hall, ENSTA Paris, Le Guichet, CentraleSupélec, Massy - Les Champarts, Massy-Palaiseau), placed by
  `tools/online/garages.py` clear of obstacles and of the bot buses' and cars' paths; three of them have a big bay (truck
  + trailer, biplane), the jet-ski comes out on a lake within 200 m (the Polytechnique - Lac garage). Work vehicles only
  come out at their garage (owned buses at the depot, not at public garages). The depot and fire station lend their
  vehicles to anyone for now (duty comes with the jobs, O5/O7). Prestige Motors' display cars are never driven online,
  and its armed display car (GAZ Tiger) isn't shown there. No fly camera online (it puts the player down anywhere). U
  opens your vehicle's panel (lock/unlock, send it back); the in-game menu has "Back to the nearest garage". The
  terminal range is judged on the server from the player's newest state. A new account has an empty garage until the
  shop (O4): `plateau-admin add-vehicle <user> <model>` fills it.
- Built in O4 (my choices): prices in `godot/data/prices.json` (JSON, not TOML: a `.toml` file needs an export filter,
  and editing `export_presets.cfg` changes the launcher id, so every player would download a whole new launcher). The
  price list is in 4.1 below. A repaint costs 2 % of the price, at least 200 €. Prestige Motors: E by Jean-Claude or at a
  podium's gold price stand opens the catalogue; the stands and Jean-Claude quote the online prices. A vehicle bought
  comes out on 3 delivery bays by the showroom's door (garage `prestige-motors`, kind "shop": it works as a public
  garage, with no map badge of its own), or waits in the garage when it can't (bays taken, the jet-ski: get it out at
  Polytechnique - Lac). Paint: 14 car colours, 6 coats for the horse, "its own colour" to go back; the body paint only
  (a black roof or carbon bonnet stays), the toy cars' palette swatch recoloured; not for buses, the fire truck, police
  cars and the 1928 Mercedes (collector's piece, painted textures). **Wrecks:** online, a player's vehicle takes crash
  damage (a speed change of 8 m/s in one tick starts to hurt, 22 m/s wrecks it from full health, ~80 km/h into a wall;
  plain driving and hard braking don't) and never repairs itself; once broken it is towed back 15 s later, and an owned
  one is marked wrecked until its repair is paid (a lent one: take another). Crash damage only exists online (solo and
  LAN unchanged).

### 4.1 Prices (decided)

Base the prices on what a regular player earns per hour. Target: **~15 000 € / h** with a lent bus doing a decent job,
so 5-10 h = 75 000-150 000 €.

| Tier | Examples | Price | Hours at 15 k€/h |
|---|---|---|---|
| Starter | kaykit hatchback, compact hatchback, sedan, horse | 5 000-8 000 € (cheapest = the 5 000 € you start with) | 0-30 min |
| Everyday | Zoe, family SUV, SUV, van, taxi, delivery | 12 000-25 000 € | 1-2 h |
| Fun | jet-ski, biplane, Mercedes 1928, Volvo FH16 + trailer | 30 000-60 000 € | 2-4 h |
| Sports | hatchback-sports, sedan-sports, SUV luxury | 75 000-100 000 € | 5-7 h |
| Super | BMW M4, Audi RS6, Audi R8 | 120 000-150 000 € | 8-10 h |
| Work | 12 m bus, 18 m bus, fire truck | 40 000-80 000 € | 2.5-5 h (pays for itself: +50 % on that job) |

Set in O4 (`godot/data/prices.json`): hatchback (KayKit) 5 000, horse 6 000, compact hatchback 6 500, sedan 7 500;
taxi 12 000, van 14 000, delivery van 15 000, SUV 16 000, Renault Zoe 18 000, family SUV 22 000; jet-ski 30 000,
Mercedes 1928 45 000, Volvo FH16 50 000 (58 000 with its trailer), biplane 60 000; sports hatchback 75 000, sports sedan
85 000, luxury SUV 100 000; BMW M4 120 000, Audi RS6 135 000, Audi R8 150 000; 12 m bus 40 000, 18 m bus 60 000 (bus
depot), fire truck 80 000 (fire station). Not sold: police cars, ambulance, armed vehicles.
| Later | ambulance, police cars | with their jobs | |

## 5. Jobs (ways to earn)

**Bus driver** (first job to build, most of the content already exists)
- Take a lent bus at the Massy-Palaiseau depot (or spawn your own there), pick a **real line** (4606, …), serve each stop: stop in the
  bay, doors open N s.
- Going on duty on a line **stows one bot bus** of that line (decided); going off duty, leaving or disconnecting
  brings it back. If every bot of the line is already replaced, the extra drivers just add buses.
- Pay per stop served, plus bonuses: fast segment, air time, near misses / close overtakes, drift, combo multiplier.
  Arcade style (Crazy Taxi), not a simulator.
- Penalties: skipping a stop, crashing hard, leaving the route for too long (the bus race's off-road rule).
- Real players riding as passengers give a bonus: a reason to ride a friend's bus.
- Bot passengers later (people waiting at stops, boarding, a satisfaction meter).
- Built in O5 (my choices): `scripts/online/bus_job.gd`, pay in `godot/data/jobs.json` (JSON like prices.json). At
  the depot's terminal, one row per line the bots run (4606, 4619, L, Z): picking one puts the player on duty in their
  bus out if it is a bus (any bus does any line), else one of their own buses (the line's model first), else a lent bus
  of the line's model comes out (18 m for the 4606, 12 m for the others). Refined 2026-10-29 (Gabriel: the depot was
  unclear): the depot's list comes in parts (bus job with a how-to line / just take a bus out, no pay / for sale), each
  line's row says which bus comes with it, and the terminal's prompt says "bus job: pick a line". A
  line = its routes in turn, both ways; the job waits for the bus on one of them, facing its way (the 4606 starts at
  the depot's door), and puts the waypoint on the next stop. **Stop served:** front of the bus in the bay (14 m short
  of the bots' stop mark to 12 m past it, so a 12 m and an 18 m bus both fit), under 1 m/s, doors open 3 s on end.
  **Pay per stop:** 90 € + 210 €/km of route since the last stop; +25 % when that stretch took at most 1.2× the bots'
  planned driving time; + the stretch's bonuses (air time 100 €/s from 0.4 s, near miss 40 €, overtake 60 €, drift
  80 €/s from 0.6 s); × combo (+0.1 per stop served up to ×2, back to ×1 at a penalty); ×1.5 own bus; +20 % per other
  player riding (3 at most). A bot driving the whole 4606 (14 stops, ~22 min, no other traffic) earns ~15 200 €/h.
  **Penalties** (taken from the next stops' pay, never from the wallet): skipped stop 150 €, hard crash (15 % of the
  health at once) 300 €, off the route (over 12 m from its path for 4 s, or 40 m at once) 200 €: the job then waits
  for the bus back on the route, the stops missed are skipped, and a shortcut's distance pays nothing; a red light
  10 € (asked by Gabriel: really small; the front 3 m past a route light while red; the combo is kept; not a light the
  bus served a stop over, as at Versailles where the bots leave the stop on red too). **Checks:**
  a jump over 25 m in a tick, or over 1.2× the model's top speed (+3 m/s) for 0.5 s, or a stretch faster than that on
  average: the stretch pays nothing. **Hourly cap:** 30 000 €/h per account over all jobs (2× the target), kept by
  the accounts service (`/v1/server/pay` `cap`: the last hour's job payments, the admin's gifts excluded; a cut
  payment says "(cap)" in the log), so it holds across server restarts. **Bot bus held:** going on duty takes the
  line's nearest gliding bot bus off the map; it still runs its timetable unseen (it takes the departure it would
  have made after its trip), so the line runs one bus fewer for the whole duty; off duty (asked at the depot or with
  U, another vehicle taken out, the bus wrecked or sent back, leaving the game) it comes back where its timetable has
  it, or at its next departure when that spot is within 150 m of a player. The HUD (top right, under the wallet):
  line → destination, next stop and how far, the stretch's time, combo, bonuses pending, fines due, money paid this
  duty, and the money/bonuses/fines popping in. **Hints** (asked by Gabriel) over the bottom of the screen: get in the
  bus / follow the waypoint / "<stop> ahead: pull into its bay and stop" / stop the bus / open the doors / passengers
  boarding (countdown) / close the doors and drive on / off the route; from the host's `bay` flag in the duty info and
  the bus's own speed and doors.

**Firefighter**
- Take a lent fire truck at the Polytechnique fire station (or spawn your own there, which pays more).
- The server spawns fires at random spots (building fronts, parked cars, bins, grass, the forest). The number of
  fires grows with the number of firefighters on duty, so 1 player isn't flooded and 10 aren't bored.
- Pay per fire put out, shared by the people who sprayed it, plus a response-time bonus.
- Needs a new fire system: flames + smoke, spreading, hit by the water cannon. The vehicle fire is a start.
- Built in O7 (my choices): `scripts/online/fires.gd` (the fires, run by the server), `scripts/online/fire_job.gd` (duty,
  alarms, pay), `scripts/fire_fx.gd` (how a fire looks), pay in `godot/data/jobs.json` "fire". **Spots:**
  `godot/world/fires.json` from `tools/online/fires.py`: ~2 400 places within 2 km of the fire station that a truck can
  hose from a road (within 45 m of a bot path, nothing built in between): building fronts facing the road, parked cars
  in OSM car parks (a burnt-out car shell stands there; off the bots' paths and away from the garages), street bins,
  lawns and woods. **Duty:** "Firefighter duty" at the fire station's terminal; the truck that comes with it is the
  fire truck they have out, else their own, else a lent one (as the bus job). Off duty at the terminal, with U, by
  taking another vehicle out, a wrecked truck, or leaving. **Alarms:** one burning per firefighter on duty (6 at most);
  the first 10 s after the first goes on duty, then one 45 s after the last one was lit or ended; a spot 120-1 500 m
  from the nearest firefighter, its kind drawn (buildings 30 %, cars, bins, grass 20 % each, woods 10 %). Nobody on
  duty: no alarms, and the fires die down in 20 s. **Fires:** start at 35 % heat and grow to full in 30-90 s (by kind,
  not while hosed); at full heat for 45 s one spreads to the nearest free spot within 9-14 m (the next car in the car
  park, the same building's next facade), grass and woods over the same ground 6-9 m on; 5 fires an alarm at most; a fire
  burning 15 min burns out (nothing paid). **Water:** the server flies every fire truck's jet itself, from the truck's
  state (its position, turret aim and spray switch), so no player says where their water went; a packet landing in a
  fire takes its heat down: 3 s of a whole jet put out a bin at full heat, 4 s grass, 7 s a car or a wood, 11 s a
  building front. **Pay** (data/jobs.json "fire"): bin 300 €, grass 380, car 480, wood 480, building 650; a spread fire
  half; +50 % when the first water came within 40 s + 1 s per 10 m from the nearest firefighter when it was lit (down to
  nothing at twice that; not for spread fires); shared by the firefighters on duty who sprayed it as their water on it
  (under 5 %: nothing), ×1.5 for the water from their own truck. Water from players off duty helps and pays nobody.
  Estimate: an alarm every ~2.5 min (drive, hose, next) at ~620 € on average ≈ 15 000 €/h, inside the jobs' 30 000 €/h
  cap. **Checks:** a jump of over 25 m in a tick or a speed over the truck's top speed: the player's water counts for
  nothing 10 s. **HUD:** top right (the nearest fire, how far, how long it has burnt, fires burning and put out, money
  this duty), the money popping in, the waypoint on the nearest fire, hints (get in the truck, drive to the fire, aim
  and hold the fire button, how much is left); the fires are on the M map and the minimap for firefighters on duty.
  **Looks:** flames and smoke (GPU particles), steam once out, a crackling roar, an orange glow at night (a sprite, not
  a light: one more light at night cost ~1 ms on an Iris Xe); 5 fires at once cost 0.3-0.8 ms a frame on the Iris Xe
  (PERFORMANCE.md 3.3).

**Stunts** *(built in O6: a bonus layer on any vehicle, not a job; `scripts/online/stunts.gd`)*
- Air time, flips (front flip, backflip, barrel roll, landed on the wheels), a plane's loops and rolls, near misses,
  top speed, plus fixed **stunt spots** (`godot/world/stunts.json`: named jumps found on the map's own ground by
  `tools/online/stunts.py`, kept only when a car really flies off them in the game; a big reward the first time,
  small after that). Pay in `godot/data/jobs.json` "stunts", inside the jobs' hourly cap.
- Diminishing returns per hour: each stunt kind pays ×0.85 per time it already paid this hour, each spot ×0.6, so one
  ramp can't be farmed. A crash landing, a landing on the roof or a flight with a teleport in it pays nothing.
- "The first time" is for good: the accounts service remembers which spots an account has done (`firsts` table,
  `/v1/server/pay` `once`), so it survives server restarts. Players on bus duty get the bus job's bonuses instead.
- Horses (they jump at a key) and planes (they fly) don't earn air time, only spots and loops/rolls.

**Later:** race prizes (races are already built), taxi, delivery (van, or truck + trailer, A to B), police vs.
speeders, ambulance, plane courier.

## 6. Flaws and risks still standing

### 6.1 The client decides what happened, and the code is public

Each vehicle is **simulated by its owner**, so speed, air time and "stopped at the stop" come from the player's
machine, and the protocol is readable on GitHub. Agreed approach:
- Money and garage live only in the accounts service; the client never reports "I earned X".
- The game server judges each job from the states it already receives, with plausibility checks: max speed per
  model, no teleports, distance vs. time, stop duration, max pay per hour per account (a hard cap catches anything
  the other checks miss).
- Accept the rest: a determined cheater with a patched client can still fake driving. For a small local audience,
  the answer is admin tools (look at an account's earnings per hour, reset, ban).

### 6.2 Other dedicated servers

The Docker image is public. Other servers can run, but only the official one talks to the accounts service (server
secret), so they have no economy: they're just Sandbox or Escape over the internet.

### 6.3 Griefing without weapons

Removing the armed vehicles leaves ramming, blocking bus stops, and the fire truck's water jet (it pushes cars and
players). Decided: **wait and see**. If it becomes a problem, options are ghost mode for job vehicles on duty (other
players pass through) or a ramming fine. Kick and ban in the admin tools cover the worst cases.

### 6.4 Low player count

Usually 2-5 players online, so every job must work **alone**. Anything that needs other players (passengers,
police vs. speeders) is a bonus, never a requirement.

### 6.5 Balance and wipes

Prices and pay will be wrong at first. Announce a **beta** with possible resets, and log every payment (job, amount,
time) so the numbers can be tuned from real play instead of guesses.

### 6.6 Server load and backups

- The VM already simulates the bot buses, ~70 bot cars and trains. Jobs add fire simulation and per-player checks;
  the accounts service is tiny. Set a player cap and measure.
- Back up the SQLite file every day **outside** the Docker volume (it filled up on 2026-10-29 and took the server
  down). SQLite's `.backup` command is safe on a live database.
- If the accounts service is down, online is down too (the game server refuses joins with a clear message); solo and
  LAN don't care.

### 6.7 Bot buses vs. player buses

Bot buses run the same lines every 60 s. Decided: a player on duty replaces one bot on their line (section 5). Once
bot passengers exist, bots still pick up passengers too, so the player wants to stay ahead of the next bot.

### 6.8 Vehicle models and licences

Several vehicles are imported models of real brands (Audi, BMW, Mercedes, Volvo, Renault). An official server that
sells an "Audi R8" makes the game more visible. Check the licence of each downloaded model (some forbid
redistribution, which the GitHub releases already do).

### 6.9 Updates

The server refuses other builds (`build_id`), so online players must update first. The accounts service has its
own versioned API, so an old client gets a clear "please update" instead of a broken login.

## 7. Architecture sketch *(proposal)*

- `server/accounts/` (Python + SQLite), added to `server/compose.yaml`, exposed through Caddy.
- Game server flag `--official` (+ the server secret from an env var): enables the online mode and the economy.
- `scripts/modes/online_mode.gd` (title "PTA Online"): free roam + economy rules (`allows("vehicle_menu")` false,
  spawning only from garage terminals, armed models hidden, one spawned vehicle).
- Garage and depot spots in a data file (`godot/world/garages.json`, from a small tool like `escape.json`'s), keyed
  by OSM ids so they survive map rebuilds.
- `scripts/accounts.gd` on the client: login/sign-up screen, HTTPS calls, remembered token.
- `Main/Economy` node with its own RPCs (like `Main/Races`, so net.gd's RPC ids don't move): wallet display,
  purchase/repair requests, payouts announced to the player.
- Jobs as nodes under `Main/Jobs` (`bus_job.gd`, `fire_job.gd`, `stunts.gd`), judged on the server.
- The dealership becomes the shop: walk in, talk to Jean-Claude, buy.

## 8. Build order

See [ONLINE_MILESTONES.md](ONLINE_MILESTONES.md) (O1-O8).

## 9. Open questions

Answered so far: spawning only at garages (~8 public + bus depot at Massy-Palaiseau + fire station at
Polytechnique), buying only in person, no money transfers for now, work vehicles lent and buyable, real bus lines
with one bot removed per driver, wait and see on ramming, no Escape on the official server, name "PTA Online",
username rules written (3.4), 5 000 € to start, locked vehicles with an unlock toggle, vehicle gone 30 s after a
disconnect, colours first, fire station = #1289, price tiers + 3 % repairs OK.

No open questions left. The build plan is in [ONLINE_MILESTONES.md](ONLINE_MILESTONES.md).
