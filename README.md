# Plateau map

Real map of the Saclay plateau (5.2 × 1.74 km: from Moulon and the Paris-Saclay campus in the west, 48°42'43.8"N 2°09'17.1"E, past Le Guichet, Télécom Paris → École Polytechnique and its lake → ENSTA Paris and its Centre de l'Yvette, and south down the hillsides to the Yvette valley) turned into a cartoon 3D scene for Godot 4.7, with two corridors east to Massy-Palaiseau station: along the 4606 bus (through Palaiseau) and along the RER B (through Palaiseau-Villebon and Palaiseau), 150 m walkable either side of the bus route and of the tracks (`meta.playable_area` in `godot/world/world.json`: the invisible walls follow it).

## Play

Install [Godot 4.7](https://godotengine.org/download), then:

```
cd godot
godot --headless --path . --import   # once after cloning: imports the models (the import cache is not in the repo)
godot --path .                       # play
```

Opening `godot/project.godot` in the editor and pressing F5 works too.

The game opens on a welcome menu over a flight around the campus: pick a nickname, a colour and a **game mode**
(**Sandbox**: the plateau to explore, everything below; **Escape from Plateau**: a co-op survival night, see its section
below), then
- **Explore solo** (**Play solo** in Escape from Plateau): the map on your own.
- **Host a game on LAN**: starts a server on this computer (UDP port 7777, or the next free one) and joins it; its address
  (`IP:port`) shows at the top right of the host's screen. The game is announced on the local network.
- **Join a game**: lists the games announced on the network with their game mode (click one), or type the host's
  address and port. You play the host's mode.

A loading screen covers the start of the game, the moment a LAN game is hosted or joined, and the return to the main
menu: the generated world is large, and the vehicles, bots, trains and the host's snapshot take a moment to set up,
which used to freeze the window with nothing on it. It shows the game's name, what is happening, a progress bar where
the loader can report one, and a changing tip; the orbit keeps moving while a long read reports no new progress. A
failed start leaves its error and a Try again button on it; a host that cannot be reached returns to the menu with the
reason.

In a LAN game everyone sees the other players (with their nickname and colour) and the vehicles they park and drive,
and can walk in a bus someone else drives; vehicles stop against the other players. Trees bent and poles knocked down
by one player bend and fall for all, also for those joining later. Esc
opens the in-game menu (resume, back to the main menu, quit; it lists the players). The host's firewall must let UDP
7777 in (Windows asks the first time); LAN discovery uses UDP broadcasts on port 7775. Command line options skip the
menu: `godot --path . -- --host` / `-- --join=192.168.1.42[:7777]` / `-- --solo`, plus `--name=NICK --color=0..7`
and `--mode=sandbox|escape` (solo, hosting, `--dedicated` too).

Bot buses drive real lines: the 4606 across the plateau and down to the Massy-Palaiseau bus station (18 m buses; its
TCSP busway crosses the RER B on a bridge) and the 4619, L and Z on the Lozère hillside
(12 m buses), a bus every minute in each direction of each line (`headway` in `pipeline/buses.toml`). They keep to
their lane, stop at every stop of the line (right indicator in, doors open, left indicator out), signal their turns,
wait at red lights, give way at junctions and stop behind other vehicles. Get on at a stop while the doors are open and
ride along; nobody can take a bot's wheel. At the map edge a bus vanishes (once its passengers are off) and waits for
the next departure of its line. About 70 bot cars (`[cars]` in `pipeline/buses.toml`) drive routes across the map
from edge to edge on the roads open to traffic, with the same driver as the buses; one that leaves the map comes back
on another route, out of the players' sight. Bots pass vehicles coming the other way without slowing down, overtake a
vehicle parked in their lane when there is room on the left, and two bots stuck face to face in one lane sort it out
(one drives past the other). Far from every player they glide along their routes without the physics, moving less
often the farther they are; beyond 120 m from the camera every vehicle is drawn as one merged mesh. When the computer
cannot keep up (a laptop on battery or in power saving mode), the traffic thins out by itself: the far bots move half
as often, then fewer bot cars drive, and it fills up again once there is room (F3 shows the bots' share of the tick).
In LAN games the host (or the dedicated server) drives them for everyone, and the traffic lights show
the same colour on every screen (they run on the host's clock).

Two races (`scripts/races.gd`, routes and checkpoints in `godot/world/races.json`), each starting in a glowing circle
with its leaderboard next to it:
- **Campus lap**: from the big parking of Polytechnique by the lake, round the campus (Avenue René Descartes, the
  Boulevard des Maréchaux past ENSTA and along the south of the campus, back north through it) and back into the
  circle, 3.5 km, in any vehicle but the planes. Stop in the circle and press T to race alone, or Y to race with the
  other drivers in the circle: they get an invitation (T joins, Y declines) and the race starts once they have all
  answered, after 15 s, or when you press T.
- **Bus race**: from the stop ENSTA - Les Joncherettes (towards Polytechnique) to Place Marguerite Perey along the
  4606's way, 1.7 km, alone, in the 12 m or the 18 m bus (one leaderboard each). Stay on the road: a wheel may stray a
  few metres off it, or further for up to 3 s; longer than that, or over 12 m off, and you are out.

A 3-2-1 countdown holds the vehicles, then the clock runs from the same GO on every screen. Only the racer sees their
checkpoints (the next one bright, the one after dim, an arrow at the top of the screen pointing to the next); getting
out of the vehicle, or T twice, gives up. At the end the racers see the results, and every player's chat says who won
in what time. The host (the solo game, or the dedicated server) keeps each player's best time per leaderboard, by
nickname, in `user://race_records.json`, and sends the top 10 to every player.

## Escape from Plateau

Night on the plateau, and something got out of the labs: the campus is cut off and the dead walk it. A few survivors
are hiding in front of the doors of the campus's buildings (four or five a night, picked from twenty: a barista at the
GUS, a nanotech researcher at the C2N, the night guard of Polytechnique, the agent of Lozère station, Jean-Claude
locked in his showroom…). Find them, carry them to **Dragon 91**, the Sécurité Civile helicopter waiting on one of the
fields (its column of light shows from afar), and get out before dawn (30 min). Co-op, 1 to 8 players
(`scripts/escape/`, the spots in `godot/world/escape.json` from `tools/escape/escape_spots.py`).
- The night: thick murky fog, a dim moon, a power cut (most street lamps dead, some flickering, few windows lit), and
  scary sounds out in the fog: screams, a dog howling, the church bell of Lozère, glass breaking, a far siren, groans,
  now and then a whisper behind you; a low drone swells as the zombies close in. All synthesized at runtime
  (`scripts/escape/escape_audio.gd`). Day/night, the vehicle menu, bots, trains, races and the showroom are off.
- Zombies (`scripts/escape/zombies.gd`, `zombie.gd`): toy figures with glowing red eyes, shamblers, fast runners and
  big brutes. Some guard each hideout, more climb out of the ground round the players as dawn comes (and the more
  players there are), hordes come for the helicopter. They sense you within ~30 m, further with your flashlight on,
  running or driving, come to gunshots, chase, and swing at you.
- Weapons and kit (`scripts/escape/arsenal.gd`): the crowbar and a pistol to start with; a shotgun and a submachine
  gun lie about with ammunition, shells, bandages, medkits and flashlight batteries (`scripts/escape/loot.gd`: walk
  over them). Head shots count double. The safehouse (in front of Télécom Paris, where you start and come back) tops
  your 9 mm rounds up.
- Survivors (`scripts/escape/survivors.gd`) cannot walk: E picks one up onto your shoulders (slower, no running, the
  pistol only), G puts them down, or sits them in the vehicle next to you (3 in a car, 6 in a van or truck, 14 in the
  bus; G there takes one out). Carried, or driven, into the helicopter's circle, they are rescued.
- About fifteen abandoned vehicles (some damaged, the keys in them, a bus, the fire truck and the GAZ Tiger further
  out): fast, they run zombies over, but the zombies batter them, and you once they are broken. The Tiger's roof gun
  kills zombies too.
- Down at 0 health: crawl, pistol only, 40 s to bleed out unless a teammate holds E by you, or you get up with a
  medkit (Q held; Space held gives up). Dead: you watch a teammate and come back at the safehouse 15 s later while the
  team has lives (2 plus one per player). Everyone dead with no life left: the mission is lost.
- When everyone is rescued (or someone holds E in the circle to leave with fewer), Dragon 91 lifts off 60 s later
  with whoever is in its circle, hordes coming. Dawn takes it away too. The host (or solo player) starts a new mission
  from the Esc menu; a dedicated server starts one by itself.
- In LAN games the host (or the dedicated server) runs the mission, the zombies, the survivors and the supplies; each
  player's peer their health and weapons. Everyone sees the others' flashlight beams, guns, shots and knocked-down
  players.

Other game modes can be added: a script extending `scripts/modes/game_mode.gd` (which features of the game it keeps,
its keys, help lines, in-game menu buttons; game.gd makes it as `Main/Mode` on every peer) and a row in
`scripts/modes/modes.gd`. Sandbox is `scripts/modes/sandbox_mode.gd`.

The builds on the [releases page](https://github.com/gabidorak/test-map-plateau/releases) update themselves: at start
they ask GitHub for the latest release and, when it is another build, download it next to the game on a full-screen
progress page, then restart on it by themselves. Esc skips: the download carries on in the background (the bottom of
the welcome menu shows the progress), **Restart now** installs it, otherwise it is installed at the next start. When the game's folder is not writable (or on a macOS app still in Downloads), the menu links to the
releases page instead. Runs from the editor and local exports never update (the release workflow stamps the build
tag into `application/config/version`). Windows on ARM laptops (Snapdragon X) take `plateau-map-windows-arm64.exe`,
which runs natively, renders with Direct3D 12 (the `windows_arm64` feature of its export preset: Adreno's Vulkan
driver fails to submit frames, the screen stays on the last boot frame) and updates to the next ARM64 build. The x86_64
build hits that Vulkan failure there; `--rendering-driver d3d12` gets it going.

To keep the download small, the release executables carry the game data as zstd chunks (the `... Packed` export
presets, built by `.github/workflows/build.yml` with `godot/tools/prepare_packed.gd` and `godot/tools/pack_game.sh`):
the first start of each build unpacks them (~570 MB) into the cache folder (`%LOCALAPPDATA%\plateau-map`,
`~/.cache/plateau-map`, `~/Library/Caches/plateau-map`) and deletes the previous build's. The plain presets still
export a self-contained game.

## What is in this repository

The game (`godot/`), the generated map it loads (`godot/world/` and `godot/scenes/generated/`) and the Blender
scripts that build the models (`blender/`). The map-generation pipeline (the Python package that downloads OSM,
IGN LiDAR and orthophotos, Mapillary and Panoramax photos and turns them into `godot/world/`, its rules, the
overrides file and the downloaded data) is **not published**, so the map cannot be regenerated from this repository.
The sections below on the ground, trees, props, buildings, facade colours and landmarks describe how it was made;
the files they mention under `pipeline/`, `overrides/`, `references/` and `data/` are not included.

Models and Godot tools (the generated scene can be rebuilt from `godot/world/`):

```
blender -b --factory-startup -P blender/trees/build_trees.py   # tree models -> godot/assets/trees/*.glb (~15 s)
blender -b --factory-startup -P blender/props/build_props.py   # street furniture -> godot/assets/props/*.glb (~3 s)
blender -b --factory-startup -P blender/vehicles/build_bus.py -- --preview=data/review/bus_idfm   # IDFM bus -> godot/assets/cars/bus_idfm.glb + .json layout (~35 s with the preview, then godot --headless --import)
blender -b --factory-startup -P blender/vehicles/build_bus.py -- --model=artic --preview=data/review/bus_idfm_artic   # 18 m articulated bus -> bus_idfm_artic.glb + .json (~30 s with the preview)
blender -b --factory-startup -P blender/vehicles/build_fire_truck.py -- --preview=data/review/fire_truck   # fire truck -> fire_truck.glb + .json (~10 s with the preview)
blender -b --factory-startup -P blender/vehicles/build_car.py -- --preview=data/review/cars   # realistic cars -> compact_hatchback.glb, family_suv.glb, police_hatchback.glb + .json (~11 s, previews ~2 min a car on the CPU; --car=police_hatchback builds one)
blender -b --factory-startup -P blender/vehicles/import_textured.py   # 1928 Mercedes from ref/mercedes_1928 (a textured OBJ) -> godot/assets/cars/mercedes_1928/: .gltf + .bin, textures (downscaled by car_textures.py in .venv: Pillow, numpy), .json (~10 s, then godot --headless --import)
blender -b --factory-startup -P blender/building_kit/build_kit.py  # building kit -> godot/assets/building_kit/kit.glb (~1 s)
blender -b --factory-startup -P blender/vehicles/build_train.py -- --preview=$PWD/data/review/mi79/mi79   # RER B MI 79 R cars -> mi79.glb + .json (~10 s, previews ~40 s; an absolute --preview path)
.venv/Scripts/python tools/escape/escape_spots.py --plot=/tmp/escape.png   # Escape from Plateau's survivor hideouts, helicopter fields and supply spots -> godot/world/escape.json (~3 s; shapely, Pillow)

# RER B (see "RER B" below): python venv with numpy, shapely and Pillow
.venv/Scripts/python tools/rail/fetch_osm.py      # optional: refetch the OSM extract tools/rail/osm_rail.json (Overpass)
.venv/Scripts/python tools/rail/fetch_osm.py --massy   # optional: the same for the line on to Massy-Palaiseau (osm_rail_massy.json)
.venv/Scripts/python tools/rail/fetch_osm.py --west    # optional: the same for the line on through Le Guichet (osm_rail_west.json)
.venv/Scripts/python tools/rail/build_rail.py     # OSM + LiDAR -> godot/world/rail.json, tools/rail/review/*.png (~1 min)
.venv/Scripts/python tools/rail/patch_world.py    # godot/world/base/ + rail.json -> godot/world/ (~25 min, ~6 GB RAM), then build_world.gd

cd godot
godot --headless --path . --import
godot --headless --path . --script res://tools/build_world.gd     # godot/world/ -> scenes/generated/neighborhood.tscn
godot --headless --path . --script res://tools/check_world.gd   # no satellite image, no hole in the ground mesh
godot --headless --path . --script res://tools/test_loading.gd  # the loading screen: status, progress, error and Try again, close
godot --headless --fixed-fps 60 --path . --script res://tools/test_play.gd  # picker, walking, walls, boundary, kerbs
godot --headless --fixed-fps 60 --path . --script res://tools/test_cars.gd  # debug cars: park, get in, drive, get out; bus doors, signals, walking inside while it moves; articulated bus turning, reversing, walking through the joint
godot --headless --fixed-fps 60 --path . --script res://tools/test_breakables.gd  # a car bends a thin tree and knocks over a sign pole, lamp, gate, hydrant, bench, bike rack; a hydrant geyser and its repair
godot --headless --fixed-fps 60 --path . --script res://tools/test_plane.gd  # biplane: parks nose up on its tail wheel, holds level flight hands off, pitches, rolls, levels, wing tip trails, takes off, LAN state
godot --headless --fixed-fps 60 --path . --script res://tools/test_guns.gd  # armed biplane: G fires both guns, rounds break a car (grey then black smoke, engine dead), repair, LAN state, a round knocks a prop over
godot --headless --fixed-fps 60 --path . --script res://tools/test_fire_truck.gd  # fire truck: drives, the cannon aims where you look, the jet lands on a car and puts a burning one out, siren (its notes, cadence and harmonics) and beacons, props knocked over, players shoved, LAN state, cab view with a turning steering wheel, passenger seat
godot --headless --fixed-fps 60 --path . --script res://tools/test_real_cars.gd  # realistic cars (the police car too): size, own lamps and headlights, clear coat, cab view inside the cabin, turning steering wheel, drives, passenger seat
godot --headless --fixed-fps 60 --path . --script res://tools/test_tiger.gd  # GAZ Tiger's roof gun (its driver: test_real_cars.gd): E from the right side stands the gunner in the hatch, the gun reaches all round within its pitch limits, the turret view turns the ring and the gun onto a car ahead and behind and hits it, armour, out-of-reach warning, LAN state
godot --headless --fixed-fps 60 --path . --script res://tools/test_truck_trailer.gd  # Volvo FH16 with its semi-trailer: two sections on 4 + 6 wheels, towed trailer held at the fifth wheel, its own lamps, pulls, turns, reverses straight
godot --headless --fixed-fps 60 --path . --script res://tools/test_police_car.gd  # police car: livery and light bar (out of the collision box), B siren and blue lights (three flashes a side in turn), the siren's notes, cadence and harmonics, LAN state
godot --headless --fixed-fps 60 --path . --script res://tools/test_camera.gd  # vehicle cameras: auto (holds a look 2 s, then eases back, no turning round in reverse), look back (Z, W on AZERTY), right click free camera (held: only while held), the fire truck's view held while spraying, the cab view looking the chase camera's way, the plane's calmer bank, no jump through rolls and loops
godot --headless --fixed-fps 60 --path . --script res://tools/test_horse.gd  # horse: stands at leg height, canters, gallops, stops, turns on the spot, hops; a fence holds it, jumped it clears 1.6 m and 2 m fences but not a 3.5 m one; neigh, LAN state, down and up again, gets off
godot --headless --fixed-fps 60 --path . --script res://tools/test_dealership.gd  # car dealership (Institut d'Optique): display cars still on their podiums, floor/glass/ceiling collide, walk in up the ramp, the salesman greets, follows and pitches, a test drive out of the main door, clearing the map restocks
godot --headless --fixed-fps 60 --path . --script res://tools/test_water.gd  # water and jet-ski: the lake's level and dug-out bed, the player swims; the jet-ski parked on the lake floats level, E on, W past 15 m/s upright, turns, coasts, Space off into the water; parked on land far from water it only crawls; a car floats then sinks, the horse swims
godot --headless --fixed-fps 60 --path . --script res://tools/test_bus_bots.gd  # bot buses: both directions out, a departure every headway, indicators and doors at a stop, a turn, a red light, overtaking a parked car (or waiting and honking where there is no room), giving way, not slowing for oncoming traffic in a junction, riding to the map edge, vanishing and coming back, gliding far away (PLATEAU_TEST_ONLY=check,... runs some)
godot --headless --fixed-fps 60 --path . --script res://tools/test_car_bots.gd  # bot cars: spawned and moving, sent out again, thinning out under load and back, passing an oncoming car without slowing, a head-on in one lane sorted out
godot --headless --fixed-fps 60 --path . --script res://tools/test_host_options.gd  # host options: bot traffic off/on, clear all vehicles (the player out first)
godot --headless --fixed-fps 60 --path . --script res://tools/test_escape.gd  # Escape from Plateau, solo: dread night, the mission (survivors, helicopter, supplies, vehicles, guards), zombies rising, pistol, crowbar, run-over, supplies, blows, down/dead/respawn, carrying and rescuing, extraction and win, dawn and wipe-out losses, back to Sandbox
tools/test_lan_escape.sh   # Escape from Plateau in a LAN game: the client gets the mission, shoots a zombie dead, is hurt, carries a survivor to the helicopter, is knocked down and helped up by the host
godot --headless --fixed-fps 60 --path . --script res://tools/probe_traffic.gd -- 10  # not a test: 10 simulated minutes of traffic, buses per direction, stalls and what held them, tick cost
tools/test_lan.sh   # LAN game: a host and a client on this machine; riding in the host's bus, taking over a car, breakables, damage, leaving
tools/test_lan_buses.sh   # LAN game with bot buses: the client gets them (no wheel for anyone), the lights on the host's clock, riding one from a stop, the host's bot traffic off/on and clear all vehicles
godot --headless --fixed-fps 60 --path . --script res://tools/test_races.gd  # races, solo: offered in the start circle (not to a plane, the bus race only to buses), countdown hold, checkpoints in order, finish, results, chat, leaderboard and records file; off the road in the bus race; a bot drives each route to the finish (PLATEAU_TEST_ONLY=lap,bus,bot_bus,bot_lap)
tools/test_lan_races.sh   # races in a LAN game: the leaderboard for a newcomer, inviting the other driver in the circle, the same GO, results and chat on both
tools/test_server_records.sh   # a dedicated server's race records outlive a restart (~1 min)
godot --headless --fixed-fps 60 --path . --script res://tools/test_trains.gd  # RER B: departures, entering the map, the stop at Lozère (±1 m, doors on the platform side), door hold, a ride to the map edge, signals, a car on the track, LODs, tick cost (PLATEAU_TEST_ONLY=stop,hold,ride,signals,obstacle,...)
tools/test_lan_trains.sh   # RER B in a LAN game: the client gets the host's trains, sees one stop at Lozère when the host does, rides it
godot --path . --script res://tools/train_shots.gd -- --milestone=rerb_E [--night]   # trains standing at Lozère, from the station and on board -> data/review/shots/rerb_E/train_*.png
godot --path . --script res://tools/screenshots_all.gd -- --milestone=M2  # viewpoints -> data/review/shots/M2/
godot --path . --script res://tools/screenshot.gd -- --pos=-90,-130,70 --look=0,0,0 --out=/tmp/shot.png
godot --path . --script res://tools/ground_swatches.gd            # every ground material -> data/review/<area>/ground_swatches.png
godot --path . --display-driver x11 --script res://tools/perf.gd  # frame time per viewpoint (vsync off; x11: a covered Wayland window stops drawing and gives bogus times)
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json godot --path . --display-driver x11 --script res://tools/perf.gd  # same on the Intel iGPU
```

## Controls

Keys are physical positions, so ZQSD on AZERTY. They can all be changed in **Settings** (welcome menu or Esc menu,
kept in `user://settings.cfg`), which also has the display mode, graphics quality, resolution, vsync, interface size,
day or night and mouse sensitivity; the help lines show the current keys. The keys below are the defaults. F11 switches between a
window and borderless fullscreen. The interface scales with the window (designed for 1600 × 900), so it keeps its size
on a 4K screen; the first window fills 80 % of the screen.
- Walk: click to capture the mouse, Esc opens the menu (and frees it). WASD to move, Shift to run, Space to jump. The mouse wheel zooms the camera; zooming all the way in goes first person and zooming out comes back (like Roblox), V also switches first/third person. The body fades out when the camera comes close to it.
- Debug cars: 4 cars are parked next to the spawn point (on road or asphalt when there is some within ~20 m). C parks another one next to the player; Tab opens the vehicle menu, which parks any model you pick (click, or arrows + Enter; Tab or Esc closes it). E gets into the nearest car (within 3 m). Drive with W (throttle), S (brake, then reverse), A/D (steer; full lock at walking pace, fading with speed), Q/E turn signals (A/E on AZERTY; they cancel themselves after the turn), G (held) the horn (heard by the other players in LAN games too), X (held) drifts (a handbrake: the rear wheels lose grip so the tail slides out under power; countersteer with A/D), B rings a bus's city bell (LAN too), and the mouse to look around (auto camera: the view stays where you put it, and glides back behind the car once the mouse has rested 2 s, the faster the faster you go; reversing never turns it round). Z (W on AZERTY, held) looks back at once. A right click switches to the free camera, which keeps its direction in the world whatever the car does, and back (held, it is free only while held). The fire truck's view holds while its cannon sprays, so the jet stays on target as you drive; the cab view always looks where the chase camera looks; the plane's chase camera shows only part of its bank. The mouse wheel zooms the chase camera. R puts the car back on its wheels, Space gets out. Engine (toy automatic gearbox), horn, bus bell, indicator, door and air-brake sounds are synthesized at runtime by `scripts/vehicle_audio.gd` (no audio files).
- The bus is walkable: O (driver) opens and closes its three sliding doors, V (or the mouse wheel zoomed all the way in) switches to the cab view, where the driver's arms hold the steering wheel and it turns with the steering. First person and the cab view carry over when taking and leaving the driver seat. Space leaves the driver seat into the aisle (the bus rolls on and sets its handbrake once slow). The player standing in it is carried along, also while it moves, and steps up onto its 36 cm floor through an open door; E near the driver seat takes the wheel again. Interior, doors, lamps and steering wheel come from `build_bus.py`, which also writes `godot/assets/cars/bus_idfm.json` (collision boxes, doors, interior, driver seat) for `scripts/car.gd`. Models: an Île-de-France Mobilités bus (Iveco Urbanway, built by `blender/vehicles/build_bus.py`, livery after `ref/`), KayKit hatchback by Kay Lousberg + Kenney Car Kit (both CC0, see `godot/assets/cars/CREDITS.md`), built into a `VehicleBody3D` by `scripts/car.gd` (per-model specs and handling exports at the top). Set `debug_cars` on Main to false to start without cars.
- The articulated bus (18 m Iveco Urbanway, same livery, parked at start next to the 12 m one) drives the same way and is walkable from end to end: two `VehicleBody3D` sections (`scripts/car.gd` + `scripts/car_trailer.gd`) hinged under a turntable by a joint (±52°, damped; it stiffens in reverse so backing up straight does not fold it), with a bellows rebuilt as the joint bends. O opens its four doors. Walking through the bellows hands the player over from one section to the other. `build_bus.py --model=artic` describes it as two sections and writes the rear section's objects, colliders and doors, the hitch and the bellows profile into `bus_idfm_artic.json`.
- Biplane (vehicle menu): a small toy taildragger built from primitive shapes by `scripts/plane.gd` (a `VehicleBody3D` like the cars, so it parks, is got in and out of with E / Space, and syncs in LAN games the same way), with arcade flight on top: lift with a stall, drag, propeller thrust fading with speed, and controls that hold the attitude when you let go (the nose follows the airflow, a shallow bank levels itself). Shift / Ctrl move the throttle lever, W / S nose down / up (S pulls, like a stick), A / D roll (steer on the ground), Q / E rudder (A / E on AZERTY), Ctrl at idle brakes on the ground, R levels the wings in the air (back on the wheels on the ground), V or the mouse wheel all the way in for the cockpit view. Full throttle lifts it off after ~50 m at ~65 km/h; it cruises at ~130 km/h, tops out near 160 km/h, and the engine fades out towards y = 190 m so it stays inside the map's boundary walls. The upper wing tips leave thin white trails at speed (seen by every player); the dash shows speed, height above the ground, throttle and STALL / PULL UP warnings. Getting out in the air drops you on the ground below while the empty plane glides on.
- Armed biplane (vehicle menu): the same plane in khaki with French roundels, two WWII-style machine guns under the lower wing and a ring sight (`scripts/plane_guns.gd`). Hold the left mouse button to fire: 24 rounds a second, every one a glowing tracer, converging 200 m ahead where an orange ring on the screen shows. Rounds hit what they meet: sparks and a ping on vehicles, a puff of dust elsewhere, and breakable props (lamps, sign poles, hydrants…) fall over. Every vehicle has health (5 per round; 100 for a car, about 300 for a bus, 60 for a biplane): past half of it the engine smokes grey; at 0 it breaks with a boom and a ball of fire, its engine dies (a shot-down plane glides down), its body is scorched and it pours black smoke (`scripts/wreck_smoke.gd`, trailing behind it if it still moves) until it is repaired a minute later. In LAN games the hits count on the shooter's peer and the damage on the peer simulating the vehicle hit; everyone sees the tracers, the smoke and the wrecks.
- Fire truck (vehicle menu): a red 6x6 airport crash tender after `ref/fire_truck.png` (built by `blender/vehicles/build_fire_truck.py`; 9 m, 16 t, all six wheels drive, the front two steer), with a working roof water cannon (`scripts/fire_truck.gd`, `scripts/water_cannon.gd`). The cannon aims where you look: the turret turns and the barrel rises to drop the jet on the point in the middle of the screen, allowing for gravity and air drag (about 80 m of reach), and a dashed blue ring shows where it lands. Hold the left mouse button to spray: the jet is simulated packet by packet, splashes where it lands and leaves wet patches that dry out. It nudges vehicles (a braked car's tyres hold it), shoves players, pushes debris, knocks light props (bins, sign poles, bollards…) over and holds against heavy ones, and 2 s of water on a burning wreck puts the fire out and the vehicle runs again. B switches the fire brigade's two-tone siren (la 435 Hz – si 488 Hz, 27.5 cycles a minute as the 1987 rules ask, the brassy sound of compressor horns) and the flashing blue beacons on and off. In LAN games the water counts on the peer simulating the truck and acts on the peer simulating what it hits; everyone sees the turret, the jet and the beacons and hears the siren. Its cab is fitted out inside (dashboard and gauges, two seats, the cannon's joystick) behind see-through tinted glass: V or the mouse wheel zoomed all the way in gives the cab view, where the driver's hands hold the steering wheel and it turns with the steering. E from the truck's right side (or while another player drives it) sits you in the passenger seat: look around with the mouse, V for the passenger's view out of the cab, E to slide over to the wheel if nobody has it, Space to get out on the right. Other players see you seated there in your colour.
- Realistic cars (vehicle menu): a red compact hatchback (Clio-sized, 4.05 m) and a blue family SUV with a black roof (3008-sized, 4.45 m), built from code by `blender/vehicles/build_car.py` with real materials (clear-coated paint, chrome, glass) and no badges. Their cabins are fitted out (dashboard with a digital cluster and a centre touchscreen, vents, console and gear selector, door cards, front seats and a rear bench) and seen through see-through glass. V or the mouse wheel zoomed all the way in gives the driver's view from inside, with the hands on a steering wheel that turns. E from the right side sits you in the passenger seat, like the fire truck. Their indicators, brake lamps, headlights and tail lamps are the model's own, lit at night.
- Police car (vehicle menu, "Police nationale car"): the compact hatchback in the Police nationale's grey livery of 2021 on (after photos of its Peugeot 5008, Renault Scénic and Dacia Duster): a blue band sweeping over the wheel arch on the left of each side and a red one on the right (so each side reads blue-white-red), POLICE NATIONALE with the tricolour mark across the doors, on the bonnet (read from the front) and on the tailgate, a dotted reflective line under the windows, blue, white and red reflective squares across the rear bumper. A blue LED light bar sits on the roof and two blue flashers in the grille (`scripts/police_car.gd`). B switches the French police two-tone siren (la 435 Hz – ré 580 Hz, 55 cycles a minute, as the 1987 rules ask: an electronic siren's square wave through a horn loudspeaker, synthesized in `scripts/vehicle_audio.gd`) and the blue lights: three quick flashes on one side, then the other, lighting the street in blue at night. They keep going when you get out. It drives like the compact hatchback, with the same cab view and passenger seat; in LAN games everyone sees the lights and hears the siren.
- 1928 Mercedes (vehicle menu, "Mercedes 1928"): a yellow SSK-type tourer with its hood up, from a ready-made model with its own textures (`blender/vehicles/import_textured.py`): slow (100 km/h, four long gears, a lazy old straight six), a cab view behind the big steering wheel, head, wing and scuttle lamps lit at night (L), rear amber and red lenses as indicators and brake lamps.
- Horse (vehicle menu): a toy chestnut horse with a black mane and tail, a white blaze and socks, saddle, stirrups and reins, built from primitive shapes by `scripts/horse.gd` and ridden by your look-alike in your colour. E gets on and off; W canters (27 km/h), W with Shift gallops (47 km/h), S stops then backs up slowly, A / D turn (on the spot too), G neighs, V or the mouse wheel zoomed all the way in gives the rider's view. Space jumps, the higher the faster it goes: from a canter it clears the map's 1.6 m bar fences and 2 m mesh fences (take off a few metres before), while the 3.5 m fences around pitches and high walls stop it. Its legs move in the gait of its speed (walk, trot, canter, gallop), step round on the spot as it turns, tuck over a jump and fold under it when it is down; the hooves clop on every footfall. It steps up kerbs and low steps, goes round street furniture instead of knocking it over, and in LAN games syncs like the other vehicles (everyone sees it jump). Shot by the armed biplane it lies down for a minute, or until the fire truck hoses it.
- Water: the Lac de l'X, the ponds and fountain basins are real water (`scripts/water.gd`, `shaders/water.gdshader`). When the scene is built, the ground under each one is dug out into a bed sloping from the shore (up to 2.5 m deep in the lake, shallower in small ponds: OSM gives no depths, so it goes by size) and a see-through surface is laid at the water's level: rippling, refracting the bed (silt, pebbles, weed patches, sun caustics), turquoise in the shallows and darker as it deepens, with foam along the shore and around whatever stands in it. You wade slower as it gets deeper, then swim with your head out (Shift a bit faster, Space kicks up to climb a bank). A car driven in splashes, floats nose down for a few seconds, then fills and settles on the bed with its engine drowned; a plane ditched in the lake does the same; the horse swims.
- Jet-ski (vehicle menu): a toy sit-down jet-ski (white hull, yellow deck, `scripts/jet_ski.gd`) parked on the nearest lake or pond within 200 m (on land beside you when there is none: there it only crawls). E gets on, Space gets off into the water. W throttle (about 80 km/h flat out), S slows then reverses, A / D steer with the jet (more with speed, a little at idle), G horn, R rights it, V or the mouse wheel zoomed all the way in gives the rider's view. It bobs on the swell, squats and lifts its bow as it pulls away, carves and leans into turns, and throws a rooster tail of spray; its supercharged three-cylinder is synthesized like the other engines.
- Races: drive into a race's start circle (the big parking by the lake: the campus lap; the stop ENSTA - Les Joncherettes towards Polytechnique, in a bus: the bus race) and press T to race alone, Y to race with the other drivers in the circle (campus lap; T joins an invitation, Y declines it). T twice gives up during a race.
- Bot buses and cars (`scripts/traffic.gd`, `scripts/bus_bot.gd`): walk in through an open door at a stop and the bus carries you to the next stops; at the end of its route at the map edge it waits for you to get off. E next to one tells you a bot drives it. The tools leave them off unless `PLATEAU_BUSES=1`; `PLATEAU_CARS=n` sets the number of bot cars; `PLATEAU_ADAPTIVE=1|0` turns the thinning out under load on or off (on in the game, off in the tools).
- Host options (Esc menu, solo or hosting): **Bot traffic: on/off** takes every bot bus and car off the map (for the other players too) or brings them back, and is remembered for the next game (`--no-bots` on the command line, also for `--dedicated`). **Clear all vehicles** (press twice) takes every vehicle off the map, the other players' too; anyone in one is put out first, and the bots come straight back when bot traffic is on.
- RER B trains (see "RER B" below): get on at Lozère while a train's doors are open (standing in a doorway keeps them open), walk through the four cars of a unit, and you are carried along; riding one off the map puts you down by the line at that end. E next to a train tells you a bot drives it. The tools leave them off unless `PLATEAU_TRAINS=1`; `PLATEAU_TRAIN_HEADWAY=s` sets the time between trains (120 s).
- Like in Euro Truck Simulator 2, vehicles bend thin trees (trunk up to 10 cm, up to 8 m tall: ~1,500 of them) and knock over sign poles, bus stop poles, route markers, guideposts, bollards, bin poles, lamps, traffic lights, light barriers, bike racks, benches, picnic tables, wheelie bins, parking meters, post boxes, info boards and fire hydrants (`scripts/breakables.gd`; kiosks, shelters, concrete blocks and masts hold). A tree bends away from the bumper, stays flat while the vehicle is over it and springs back up behind it; a pole snaps off and flies on as debris, and comes back 20 s later once the camera is 60 m away. Faster than 7 km/h for props (0.5 m/s for trees); slower they hold like any other obstacle. The vehicle loses the momentum it gives them, and they make a sound (a metal clang, a swish of leaves). A knocked-over fire hydrant (or water tap) leaves a 10 m geyser of water (3 m for taps, `scripts/geyser.gd`) that roars and lifts whatever is parked over it; the pipe is repaired a minute later, in view or not, the water easing off over the last 3 s.
- F1: fly camera (hold right mouse to look, WASD + Q/E, Shift faster, wheel for speed). F1 again drops the player below the camera.
- F2: graphics low / medium / high (also in Settings). Low (no SSIL, SSAO or glow, FXAA instead of MSAA) is the default ("Auto") on an integrated GPU, high elsewhere; medium keeps the SSAO, glow and shadows but drops the SSIL and MSAA (FXAA), about a third less GPU time at 4K. `PLATEAU_QUALITY=low|medium|high` overrides until the quality is changed in the game.
- Resolution (Settings): Auto, Native, 2160p, 1440p, 1080p, 900p or 720p, the height the 3D is drawn at, upscaled to the window with FSR 1 (the interface stays sharp; Godot cannot switch the screen's own mode). "Auto" draws at most 1080p: on a 4K laptop native 4K pulls the processor's clock down within minutes (the GPU and CPU share one power budget) and the bot traffic then drops to 25-40 fps, where 1080p holds 60. F3 shows the physics, scripts, render and GPU times, whether the frame waits on the CPU or the GPU, the 3D size, and with bot traffic the share of each physics tick its scripts take (and the traffic level when it has thinned out).
- N: night / day (also in Settings, kept between sessions; `PLATEAU_NIGHT=1|0` overrides until it is switched in the game). At night (`scripts/night.gd`) the sun becomes a pale blue moonlight that still casts shadows, the sky turns dark blue with stars and a moon (`shaders/night_sky.gdshader`) over a faint glow of the towns around, about 40 % of the buildings' rooms are lit, the street and path lamps glow and light the ground under them (not while knocked over), and the bot buses and cars drive with their headlights on. L switches the headlights of the vehicle you drive (the biplanes' landing lights): a beam that lights the road ahead (and casts shadows for your own vehicle), glowing lamps, dim red tail lamps and the buses' cabin lights; they switch on by themselves when you get in at night. Other players see your headlights; each player chooses day or night for themselves.
- Escape from Plateau (see its section): left mouse fires, right mouse (held) aims, 1-4 crowbar / pistol / shotgun /
  submachine gun, R reloads, F flashlight, Q bandage or medkit, E picks a survivor up (or helps a teammate up, held),
  G puts them down or in a vehicle. The keys are in Settings, under Escape from Plateau.
- F: identify what is under the crosshair (Sandbox): a building (number, OSM id, name, kind, height and source), a tree, a prop (kind, model, source, OSM id, bus stop lines, sign codes), a fence, the ground (piece kind, material, OSM source), or the RER B: a track (number, direction, kilometre point, speed limit, cant), a platform, a signal (type, ref, aspects), a structure, the catenary. The text is copied to the clipboard. X closes it, H hides the help.

Chunk streaming: `scripts/builder/far_builder.gd` splits the world into 192 m cells and gives each a cheap far version
(ground on an 8 m grid with the ground shader, its buildings merged and simplified into one mesh, its trees as
20-triangle crowns in one MultiMesh). At runtime `scripts/world_streamer.gd` (node `Neighborhood/Streamer`) shows the
full-detail nodes of the cells within 180 m of the camera and the far version of the others. Hidden nodes stay in the
tree, so collision, the picker and the tools are unaffected. `PLATEAU_STREAMING=0` shows full detail everywhere.

Building numbers: `data/review/<area>/buildings_index.md` and `buildings_map.png`. Viewpoints: `godot/tools/viewpoints.json`.

Ground (M3): `world.json` holds `ground[]` (a gap-free partition of the box into polygons with a kind and a
material), `kerbs[]` and `markings[]`. Review: `ground.png` (toy map above the orthophoto),
`ground_closeups/<viewpoint>.png` (10 cm/px, partition edges over the photo: red = OSM, yellow = land cover),
`landcover.png` and `ground_stats.md` (areas, sources, alignment with the photo). Land-cover rules are in
`pipeline/landcover.toml`, toy colours in `pipeline/palette.toml`.

Ground in Godot (M4): `plateau/ground_mesh.py` cuts the partition on a 2 m grid aligned with the heightmap and drapes
it (planar per grid triangle, so neighbours share exact vertices), lifts sidewalks/islands/platforms 0.12 m with
skirts, rounded kerb stones and ramps behind lowered kerbs, drapes the markings, and writes `godot/world/ground.bin`
(64 m chunks) plus `ground_ids.bin`/`ground_index.json` for runtime lookups. Godot draws it with one procedural shader
(`shaders/toy_ground.gdshader`, colours from the palette baked per vertex); grass tufts are scattered at runtime around
the camera (`scripts/grass_field.gd`). The terrain collision follows the drawn ground, raised surfaces collide too.
The orthophoto never reaches the game: `tools/check_world.gd` fails on any image or texture in the generated world.
Review: `ground_mesh_stats.md`, `ground_swatches.png`.

Trees and hedges (M5): `plateau/trees.py` finds tree tops in the LiDAR canopy (surface minus ground, without buildings,
kept only where the infrared photo is green), measures each crown along 8 directions (x1.2: the LiDAR was flown
leaf-off), matches OSM trees and tree rows within 3 m (unmatched OSM trees and row gaps become staked saplings) and
keeps unmatched tops in woods and parks, or elsewhere when they are clearly trees. Archetypes (round, oval, columnar,
weeping, sapling; conifer only from OSM `leaf_type=needleleaved` or overrides) and tints (crown colour relative to all
crowns of the photo, snapped to `palette.toml [foliage]`) follow `pipeline/trees.toml`. Hedges come from BD TOPO and
OSM `barrier=hedge`, with LiDAR height and width. `world.json` gets `trees[]` and `hedges[]` (schema 5).
Models: `blender/trees/*.py` (one recipe per archetype, 2-3 variants, metaballs -> remesh -> smooth, 3 LODs, baked
vertex AO) -> `godot/assets/trees/<archetype>.glb` + `models.json`. Godot draws one MultiMesh per model, LOD and 96 m
chunk (`builder/vegetation_builder.gd`, `shaders/toy_foliage.gdshader` with wind); trunks and hedges collide (layer
`vegetation`), and F identifies trees (trunk or crown) and hedges.
Corrections go in `overrides/overrides.toml`:

```toml
[[tree]]
at = [120.5, -40.2]       # the nearest tree within 3 m
archetype = "conifer"     # round | oval | columnar | conifer | weeping | sapling (optional)
tint = "conifer"          # a palette.toml [foliage] name (optional); also height, radius, variant
# remove = true           # deletes it; with no tree within 3 m and a height, a new tree is added
```

Review: `trees.png` (tops, kept trees, OSM trees and rows, hedges over the orthophoto), `trees_closeups/<viewpoint>.png`
(game vegetation in toy colours | the same over the photo), `trees_stats.md`.

Street furniture (M6): `plateau/props.py` turns OSM nodes into props with the rules of `pipeline/props_catalog.toml`
(OSM tags -> model + placement: snap to the kerb or the path edge, benches face the path, lamps stand back from the
kerb, gates span the way, boxes go against walls; indoor nodes are skipped). Bus stops: IDFM stops matched to OSM
platforms (`ref:FR:STIF`, else name), lines from IDFM, colours from the OSM route relations (`[bus_lines]` otherwise),
a shelter only where OSM says `shelter=yes`, parallel to the kerb of the road the buses use and open towards it, the
pole downstream with the stop name and line badges. Traffic lights at each approach of `highway=traffic_signals`,
pedestrian lights at signalled crossings (a 30 s toy cycle in the shader). Signs: OSM stop / give-way / `traffic_sign`
nodes, plus Panoramax sign detections placed from photo position, heading and box size, clustered per type (two photos
at least), confirming OSM signs nearby; Mapillary map features when fetched with a token. Fences and walls from OSM
barrier lines (wall heights from the LiDAR). `world.json` gets `props[]` and `fences[]` (schema 6).
Models: `blender/toylib.py` (bevelled parts, weighted normals, baked vertex AO; COLOR = toy colour + AO) and
`blender/props/*.py` (66 models, 43 French sign faces built from code) -> `godot/assets/props/*.glb` + `props.json`
(sizes, colliders, anchors). Godot: one MultiMesh per model and 96 m chunk (`builder/prop_placer.gd`,
`shaders/toy_prop*.gdshader`), Label3D names and line badges on bus stops, collision shapes created at runtime
(layer `props`). Corrections in `overrides/overrides.toml`:

```toml
[[prop]]
at = [141.7, -155.0]      # the nearest prop within 3 m
yaw = 90                  # where its front looks, degrees counter-clockwise from east (optional)
# move_to = [x, y]; model = "bench_flat"; remove = true
# with no prop within 3 m and a model, a new prop is added
```

Review: `props.png` (every prop as an icon with a tick towards its front, fences, over the faded orthophoto),
`props_closeups/<viewpoint>.png` (10 cm/px, model footprints, sign codes and bus lines), `props_stats.md` (outcome of
every OSM street-furniture node, bus stops, signs, fences), `prop_models.png` (contact sheet of the models).

Bot bus routes: `plateau/transit.py` (`python -m plateau buses`, also run by `build` and `props`) writes
`godot/world/bus_routes.json` for the lines of `pipeline/buses.toml`: each line's two directions are its OSM route
relations (the longest run in the map and the one coming back), their ways chained into the fitted carriageway
centrelines, cut 25 m inside the playable box, moved into the right-hand lane and eased to the kerb at each stop of the
line, then relaxed like an elastic band: corners eased to an 8 m radius with room for the bus's front swinging out and
its rear wheels cutting in, pushed off kerbs, roadside props, trunks, walls and the bumps of the LiDAR ground (parked
vans it kept, hillside banks), pulled back towards the lane. Each route has a planned speed per metre (limits,
curves, braking ahead), its stops (the line's poles), the traffic lights facing it (with their phase), the junctions
where it gives way (a stop or give-way sign facing it, entering a roundabout, coming from a lesser road, priority to the
right, turning left; with the arms traffic comes from) and its indicator stretches. Review: `buses.png`. In Godot,
`scripts/traffic.gd` sends the buses out every headway from the start of each direction (filling the lines at the
start as if they had been running), sends the bot cars out, and runs the lights' clock (shader global `signal_clock`,
the same cycle as `shaders/toy_prop.gdshader`); `scripts/bus_bot.gd` drives each one through `car.gd`'s pedals and
steering (pure pursuit from the middle of the vehicle, stops, lights, give-ways, vehicles ahead, overtaking), and glides
it along its path far from the players (static bodies, moved by `traffic.gd` every 3, 6 or 12 ticks with the distance
from the players and the camera: about 2.2 ms a tick for ~125 bots and the RER B, headless; see `PERFORMANCE.md`).

Bot car routes: `plateau/car_traffic.py` (run with the bus routes) writes `godot/world/car_routes.json`: 60 routes from
a road crossing into the map to another, each through a waypoint by the longest roads no route drives yet, as quickest
paths that never turn back (round a block rather than a U-turn); private campus roads, service roads and two-way roads
too narrow for two cars cost more, parking aisles, driveways, busways and `access=no` roads are left out. Each route is
then built like a bus route with car sizes and speeds (`[cars.path]`, `[cars.speed]`). Every route (buses too) carries
the room on the left of its path to the kerb, for overtaking. Review: `car_routes.png`.

Toy buildings (M7): every mass becomes a stack of tiers (`plateau/massing.py`): the footprint with rounded free
corners, a quarter-round bevel along the top edge and, on flat roofs from 5 m, a parapet around a lowered deck (both
only along edges no taller neighbour leans on). `plateau/roofs.py` reads the LiDAR roof inside each footprint: roof
levels at least one floor apart become set-back tiers (taller wings and set-back top floors), blobs standing out of a
deck become plant rooms (or AC-unit modules when small), and textured dark grey-blue areas of the orthophoto become
solar panel rows. Building passages (`tunnel=building_passage`) cut the ground floor: a bridge tier spans them and the
ground stays open. Wall-less masses (`wall=no`, roofs) are slabs on round pilotis with a lit soffit.
`plateau/facades.py` picks per building (parts of one building share it) a style by usage group from
`pipeline/buildings.toml`: typical floors (punched, ribbon, curtain wall, slats, balconies, loggias, high band, grid,
blind), ground floor (plain, shopfront, lobby, plinth), material (render, brick, wood, metal, concrete) and top
(plain, accent band, railing), wall and accent colours from `palette.toml [building]`; floors follow
`building:levels`. Facades are runs of ring edges without a sharp turn (curved walls stay one facade). OSM
`entrance=*` nodes put doors on the facades; a building with none gets one on the facade nearest a path. Kit modules
(balconies, loggia railings, slats, entrance canopies, pilotis, rooftop railings, AC units, solar panels) and name
signs over the main entrances are placed there too. `world.json` gets `buildings[].toy`, `building_modules[]` and
`building_signs[]` (schema 7). Godot: `builder/building_builder.gd` extrudes the tiers with per-vertex facade data
(UV, UV2 and four custom channels) and one shared material, `shaders/toy_building.gdshader` (windows with fake
recesses, frames and sky-reflecting glass, doors, materials, roof membranes, soffits, louvres); the kit
(`blender/building_kit/`, toy prop shader with the accent tint) is drawn with one MultiMesh per module and 96 m chunk.
Houses (`plateau/houses.py`, rules in `buildings.toml [house]`): OSM `building=house|detached|semidetached_house|
terrace|bungalow`, or an untyped building BD TOPO calls residential with 1-2 dwellings, small and low. The footprint
is covered by up to 4 rectangles on the grid of its wall lines; each gets a gabled or hipped roof with a shared eave
height and pitch, and wings reach into the main block so L and T roofs meet in valleys. Gable or hip, the ridge
direction of square-ish blocks, the pitch and the eaves come from a fit of the LiDAR surface (over ±1 m shifts of the
outline); a clearly flat LiDAR roof stays flat, and a house the LiDAR cannot explain (trees, built after the flight)
gets a default roof (eaves from BD TOPO `hauteur`, which is about the gutter height). Walls stop at the eaves; the
house style draws punched windows with shutters and one panelled front door (`tiers[].house` in world.json;
`building_builder.gd` draws tiles, overhang soffits, fascias, gable walls and a chimney on ~60% of them).
Review: `buildings_toy.png` (tiers, facade styles, doors, modules over the faded orthophoto),
`buildings_closeups/<viewpoint>.png` (10 cm/px with the style of each building), `buildings_stats.md`.

Facade colours from street photos (M8): `plateau/photos.py` reads the Panoramax search results (and Mapillary
images with a token: positions and headings from its reconstruction) and `fetch` downloads the ~2,100 photos with a
building in view, 1024 px wide, into `data/raw/<area>/photos/`. Compass headings are converted to grid north
(declination when `GPSImgDirectionRef=M`, Lambert-93 convergence); car sequences whose compass is noise use the
direction of travel instead. `plateau/poses.py` corrects each pose by fitting the photo's skyline (sky found column
by column from the top) to the one the LiDAR surface model predicts: heading, pitch, roll, focal length when
unknown, then position ±4 m; fits that disagree with their sequence are dropped and photos without a fit get their
sequence's median correction (cached in `data/interim/<area>/photo_poses.json`). `plateau/facade_colours.py` lays
sample points on every exposed wall, projects them into the photos, drops points hidden by buildings, low objects or,
from April to November, tree crowns (LiDAR and OSM trees), normalizes each photo's exposure and balances it on the
asphalt ahead, and gates sky, blown, dark, textured, vegetation and glass pixels. Per building, a weighted median in
OKLab gives the wall colour, a 2-means split the accent, the glass share a glazing hint (curtain wall / punched
windows); the confidence grows with photo quality, pixel count and agreement between photos. Confident colours are
stylized (lightness lift, colour cast removed, chroma boost with a grey dead zone) and snapped to `palette.toml
[facade]`, and replace the M7 palette colour; brick and wood colours set the facade material. Rules:
`pipeline/facades.toml`. Corrections in `overrides/overrides.toml`:

```toml
[[facade]]
building = 73             # number from buildings_map.png, or an OSM id ("osm:r9903423" covers all its parts); numbers change with the area, so prefer ids
color = "cream"           # a palette.toml [facade] name or "#rrggbb"; also accent = "white"
# photo = false           # keep the M7 palette colour instead
```

Review: `facades/<num>_<id>.jpg` (per building: the photo crops with the sample points by pixel class, each photo's
median and whether it agrees, swatches from the M7 palette colour to the toy colour), `facades.png` (walls in their
final colour, thick outline = photo colour, camera positions and headings: green = skyline fit),
`facades_stats.md` (poses, pixel classes, coverage, every building). The photos never reach the game.

Landmarks (M9): the important buildings get a hand-written spec in `overrides/overrides.toml`, built from your
photos in `references/<name>/` (copy `references/_template/notes.md`). The loop:

1. `python -m plateau edges <num>` draws the building's numbered facades (`data/review/<area>/edges/<num>.png`):
   the outside clockwise from the westmost wall facing north, then each courtyard; along each facade, `along` runs
   from its left end (dot) to its right end (arrow) as seen from outside, ticks every 5 m.
2. Write the `[[landmark]]` spec (below), then `python -m plateau buildings` and `build_world.gd`. The build also
   writes `data/review/<area>/landmarks/<name>_edges.png` (facades plus what the spec adds: volumes, arcades,
   columns, doors, signs, photo cameras).
3. `python -m plateau landmark <name>`: `<name>_photos.jpg` (the street photos with a fitted pose that see the
   building, numbered facades projected in: tells which facade a photo shows and where things sit along it) and
   `<name>.jpg` (each reference photo next to the game rendered from its `[[landmark.photo]]` pose by
   `godot/tools/landmark_shots.gd`). Adjust the spec and repeat.

```toml
[[landmark]]
name = "telecom-paris"            # = references/telecom-paris/
buildings = ["osm:r9903423"]      # OSM ids (stable) or numbers; all get the spec
label = "Télécom Paris"           # name shown by the picker
height = 24.5                     # optional corrections: height (m), levels; lidar_tiers / roof_boxes / solar /
levels = 6                        # auto_door / pilotis = false switch automatic parts off
green_roof = true                 # planted sedum roofs (green with rust drifts; a volume may say false)
floors = "grid"                   # M7 styles: blind punched ribbon curtain slats balconies loggias high_band grid
ground = "lobby"                  # plain shopfront lobby plinth podium
material = "concrete"             # render brick wood metal concrete panels shingles
windows = "plain"                 # plain framed pairs framed_staggered
wall = "#e3c9a6"                  # palette.toml [facade] names or #rrggbb; also accent, ground_wall
ground_height = 4.6               # m; floor_height, bay (window rhythm, m)
fins = { spacing = 1.6, depth = 0.9, width = 0.3, ledges = true }   # also color, from, ledge_depth/_thickness

[[landmark.facade]]               # some facades differ: any style key above (fins = false), plus
facades = [23, 24]                # arcade = 2.5 (ground floor set back, m), arcade_height, columns = spacing,
arcade = 2.5                      # door = along (m)
columns = 6.0

[[landmark.volume]]               # a box added to the mass (cantilevers, bay windows): facade + along + depth
facade = 23                       # (m out of the facade, negative = into it) or polygon = [[x, y], ...];
along = [0.0, 12.6]               # z = [bottom] or [bottom, top] in m above the base; style keys; columns
depth = [-0.3, 1.3]
z = [8.2]
floors = "blind"

[[landmark.module]]               # a kit module: model, facade, along, z, out, scale, tint, repeat = [step, n];
                                  # landmark-only models: fin, green_wall (V of climbers, 3 x 7 m), x_bars (8 m)
[[landmark.sign]]                 # a name sign: text, facade, along, z, width, color, plate
[[landmark.photo]]                # a reference photo: file, eye = [x, y, h above ground], target, fov (horizontal)
```

`world.json` buildings of a landmark carry `landmark` (its name), `toy.styles` (per-facade and volume styles;
`toy.runs[k][3]` and volume tiers index it) and `toy.columns` (schema 9). If a shape cannot be expressed with the
kit, the milestone plans a dedicated Blender script `blender/landmarks/<name>.py` whose model replaces the mass
(not needed yet). The reference photos never reach the game. Landmarks so far: `telecom-paris`, `hacker-house`,
`alice-milliat`, `ensta-paris` (white panels, sedum roofs, green wall on the road side, crossed bars on the east
block, glazed hall with a canopy) and `ensta-residences` (white panels, brick ends, concrete gables, roof plant).

## RER B

The RER B (Ligne de Sceaux, RATP, 1,500 V DC) crosses the south of the map where it really runs, from the map's
south-west edge through Le Guichet and Gare de Lozère, and runs on east along its corridor through Palaiseau-Villebon
and Palaiseau to Massy-Palaiseau; trains run on it both ways all the time and stop at all five stations. Since the map pipeline is not published, the railway is added after it by
committed scripts that regenerate everything from data (commands above).

- Data, `tools/rail/` (Python: numpy, shapely, Pillow in `.venv`): `fetch_osm.py` keeps the Overpass extract
  (`osm_rail.json`: the two tracks named "Ligne de Sceaux", the platforms, signals, kilometre posts, and the roads,
  buildings, barriers and bridges around them); `build_rail.py` writes `godot/world/rail.json` (its schema is the
  script's docstring) and `tools/rail/review/` (`rail.png` over the toy ground map, `station.png`, `profile.png`: the
  long section against the LiDAR, `sections.png`). The alignment is a least-squares fit of straights, clothoids and
  arcs to both OSM tracks at once (one track spacing, 3.55 m; within 0.10 m rms and 0.33 m at worst of OSM in the map;
  tightest radius 345 m), cant and speed per curve (line speed 90 km/h, OSM speed boards), a vertical profile through
  robust LiDAR samples of the trackbed (grades up to 9 ‰, parabolic vertical curves), the earthworks each metre and side
  (formation 0.70 m under the rail: UIC 60 rails, M450 sleepers, 0.30 m of ballast; a 3:2 slope to the ground, or a
  retaining wall where it would reach a building or a road), the platforms (1.15 m above the rail: RATP's RER platforms;
  edge 1.65 m from the track centre), the footbridges and pedestrian underpasses (OSM, their steps' heights), the
  covered road (OSM `tunnel=yes` from Place de la Gare under the tracks to Rue Charles Péguy, 3.6 m headroom, open
  trenches at its ends), the signals (with the track and direction they face), kilometre posts, the catenary (portals
  by rule, contact wire 5.25 m above the rail), the station's furniture by rule from the OSM tags and entrances, the
  services (per direction: the route every metre, the planned speed, the stop at Lozère per train length, the block
  signals, the headway) and the trees and props the railway clears.
- The line on to Massy-Palaiseau (2026-10-18): `fetch_osm.py --massy` keeps `osm_rail_massy.json` (read under
  `osm_rail.json`, whose elements win, so the first stretch is built from exactly what it was). The alignment is fitted
  in sections (`X_SECTIONS`): the first stretch's clothoid fit as before, then a smoothing spline through OSM's
  centreline (the line has compound curves there; within 0.31 m rms of OSM), pinned to the first one's end and
  heading. Palaiseau-Villebon and Palaiseau have OSM platform outlines (side platforms; where a station had only nodes,
  `rule_platforms` lays side platforms over both directions' 8-car trains). Short bridges carrying the line over a
  road (`rail_bridges`) leave the ground under them alone and get a concrete deck. Roads and paths over the line are
  the map's bridge decks (`world.json` `bridges`): no catenary portal under them, the contact wire lowered where they
  leave less room. Beyond the alignment (x 4030) `tools/rail/yard.py` builds the station yard of Massy-Palaiseau:
  every OSM track (the RER B's four platform tracks, the terminus tracks, the depot, the TGV line, the RER C) is a
  line of its own with its rail level from the LiDAR (humps such as the concourse over the tracks left out), drawn
  with rails and sleepers on ballast ground (`yard` zones: the ground kept); the two islands between tracks 1 and A
  and between B and 2 are raised platforms (`island` zones) with their copings and furniture; tracks 1 and 2 carry the
  trains on out of the map. A building standing over a track trains run on, its roof well above them (Palaiseau's
  station hall over the cutting, Massy's footbridge halls), keeps only what is above 6.2 m over the rail.
- The line on through Le Guichet (2026-10-21, the map's west box): `fetch_osm.py --west` keeps `osm_rail_west.json`
  (read under the other two). A west section (`X_FAR_WEST` to `X_WEST`) is fitted backwards from the first stretch's
  start (`ReversedSection`: the smoothing spline pinned to its start and heading), so the first stretch keeps its fit;
  it runs ~500 m on beyond the map's south edge, where the trains start and end hidden. Le Guichet has only stop
  positions in OSM: `rule_platforms` lays its side platforms, which run over the line's bridge across the N118 (as
  in reality): `rail_builder.gd` lays the platform floor on that bridge's deck (the patch leaves the road's ground
  under it). The line's bridges are left out of the LiDAR profile (the samples there are the road below), and
  the right-of-way fences stop at them. The builder draws the bridges and platforms one mesh each, and the station
  furniture, signal masts, kilometre posts and wall copings one mesh per far cell: a mesh along the whole line was
  culled where it is drawn (Godot measures a visibility range from the mesh's centre).
- The map, `patch_world.py`: from the pipeline's files kept in `godot/world/base/` (never from patched ones: running
  it twice gives the same bytes; `world.json` `meta.rail` holds the version and the inputs' SHA-1) it draws the
  railway's ground into the heightmap and the ground mesh (cliff cells keep each side's plane, with skirts; the mesh
  stays watertight), adds the ground pieces (trackbed, platforms, steps, the covered road), removes the 110 trees and
  moves the 10 props in the way, adds the right-of-way fences and restyles the station building after the photos
  (`tools/rail/review/patch.md` lists it all). The bus and car routes are unchanged; the bot cars do not use the
  covered road (their routes cannot be regenerated without the pipeline), the players can drive through it.
- Godot: `scripts/builder/rail_builder.gd` draws the track (ballast bed, rails, sleepers per 96 m chunk, streamed with
  a far strip), the platforms (copings, edge slabs, tactile strip), the furniture (lamps lit at night, seats, bins,
  "Lozère" boards, departure screens listing the next trains, Navigo validators, canopies), signals with their lamps,
  posts, the catenary, the structures and the station roof; `scripts/rail_map.gd` answers where things are along the
  line (the picker names tracks, platforms, signals). `tools/check_world.gd` checks the patch stamp, the trackbed along
  both tracks, nothing in the kinematic gauge and the platforms' edge and height.
- Trains: MI 79 R units (the renovated MI 79 of the B4 branch), two units of four cars, from
  `blender/vehicles/build_train.py` (26.00 m cars, 2.80 m wide, floor 1.19 m above the rail, four double doors a side;
  the MI 79 drawings, Wikipedia, photos for the livery and interior). `scripts/train.gd` locks them to the rails: the
  state is the front's distance along its route, the speed, the doors and the lamps, and every car is posed from it
  between its bogies on the rail curve, canted. `scripts/train_bot.gd` drives them (1.0 m/s² from rest, 0.7 m/s²
  service braking, 1.1 when it must, 1.15 m/s² emergency: en.wikipedia "MI 79"), stops them on the 8-car mark at
  every station (Le Guichet, Lozère, Palaiseau-Villebon, Palaiseau, Massy-Palaiseau), opens the platform-side doors for 40 s (longer while someone stands in a doorway), sounds the door warning,
  obeys the block signals, and sounds the horn and brakes, at the emergency rate if it must, for people and vehicles
  on the track (a train that cannot stop in time knocks a car aside and damages it). `scripts/train_traffic.gd` sends
  a train each way every 120 s (`PLATEAU_TRAIN_HEADWAY`; the real B4 service is every 10-15 min), eastbound in at line
  speed from beyond the map's south-west edge, westbound in at line speed from beyond Massy-Palaiseau, fills the line at the start, sets the
  signals' aspects and the departure screens, and puts a player riding off the map down by the line. Sounds are
  synthesized (`vehicle_audio.gd`: traction whine, rail rumble, horn, door warning, brake squeal). In LAN games the
  host runs the trains and sends their states on the shared clock; the others pose them from the same routes.
- Known differences from the real stations: at Massy-Palaiseau only the RER B's two islands are platforms (the RER C
  and TGV platforms are the map's ground), the terminus, depot and TGV tracks have no catenary and no trains, and the
  station's concourse is the map's footbridge decks and halls; the new stations have the rule-made furniture (lamps,
  name boards, benches, bins, screens) rather than their own.
- Known differences from the real Lozère station: the station building is a toy approximation of the real one (cream render
  with brick under a slate gable, after the photos); the entrances have validator pillars (as in the photos) rather
  than gates; the footbridges are open steel decks with bar railings; the south platform's long stone-clad wall
  building is the pipeline's generic box; the covered road's trench walls follow the LiDAR's banks and look rough at
  their ends; the trains do not change between MI 79 and MI 84.

Milestones: see [MILESTONES.md](MILESTONES.md).

In the editor the world can also be rebuilt from Project > Tools > Rebuild Plateau world.
Coordinates everywhere in the pipeline: metres, x east, y north, z up, origin at Télécom Paris
(Lambert-93 641117.6, 6846184.3). Godot position = (x, z, -y).

Data: © OpenStreetMap contributors (ODbL), IGN (Licence Ouverte 2.0), Île-de-France Mobilités
(Licence Ouverte 2.0), Panoramax contributors (CC-BY-SA 4.0), Mapillary contributors (CC-BY-SA 4.0).
The orthophoto and street photos were only used to derive the map, and the photos of Gare de Lozère and MI 79 trains (Wikimedia Commons) as references for the RER B; none of them is in the game. Car models: Kenney Car Kit (CC0, www.kenney.nl), KayKit by Kay Lousberg (CC0).
