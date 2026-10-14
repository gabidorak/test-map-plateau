# Plateau map

Real map of the Saclay plateau (2.1 × 1.74 km: Télécom Paris → École Polytechnique and its lake → ENSTA Paris and its Centre de l'Yvette, and south down the Lozère hillside to the Yvette valley) turned into a cartoon 3D scene for Godot 4.7.

## Play

Install [Godot 4.7](https://godotengine.org/download), then:

```
cd godot
godot --headless --path . --import   # once after cloning: imports the models (the import cache is not in the repo)
godot --path .                       # play
```

Opening `godot/project.godot` in the editor and pressing F5 works too.

The game opens on a welcome menu over a flight around the campus: pick a nickname and a colour, then
- **Explore solo**: the map on your own, as before.
- **Host a game on LAN**: starts a server on this computer (UDP port 7777, or the next free one) and joins it; its address
  (`IP:port`) shows at the top right of the host's screen. The game is announced on the local network.
- **Join a game**: lists the games announced on the network (click one), or type the host's address and port.

In a LAN game everyone sees the other players (with their nickname and colour) and the vehicles they park and drive,
and can walk in a bus someone else drives; vehicles stop against the other players. Trees bent and poles knocked down
by one player bend and fall for all, also for those joining later. Esc
opens the in-game menu (resume, back to the main menu, quit; it lists the players). The host's firewall must let UDP
7777 in (Windows asks the first time); LAN discovery uses UDP broadcasts on port 7775. Command line options skip the
menu: `godot --path . -- --host` / `-- --join=192.168.1.42[:7777]` / `-- --solo`, plus `--name=NICK --color=0..7`.

Bot buses drive real lines: the 4606 across the plateau (18 m buses) and the 4619, L and Z on the Lozère hillside
(12 m buses), a bus every minute in each direction of each line (`headway` in `pipeline/buses.toml`). They keep to
their lane, stop at every stop of the line (right indicator in, doors open, left indicator out), signal their turns,
wait at red lights, give way at junctions and stop behind other vehicles. Get on at a stop while the doors are open and
ride along; nobody can take a bot's wheel. At the map edge a bus vanishes (once its passengers are off) and waits for
the next departure of its line. About 70 bot cars (`[cars]` in `pipeline/buses.toml`) drive routes across the map
from edge to edge on the roads open to traffic, with the same driver as the buses; one that leaves the map comes back
on another route, out of the players' sight. Bots pass vehicles coming the other way without slowing down, overtake a
vehicle parked in their lane when there is room on the left, and two bots stuck face to face in one lane sort it out
(one drives past the other). Far from every player they glide along their routes without the physics. In LAN games the host (or the dedicated server) drives them for everyone, and the traffic lights show
the same colour on every screen (they run on the host's clock).

The builds on the [releases page](https://github.com/gabidorak/test-map-plateau/releases) update themselves: at start
they ask GitHub for the latest release and, when it is another build, download it next to the game on a full-screen
progress page, then restart on it by themselves. Esc skips: the download carries on in the background (the bottom of
the welcome menu shows the progress), **Restart now** installs it, otherwise it is installed at the next start. When the game's folder is not writable (or on a macOS app still in Downloads), the menu links to the
releases page instead. Runs from the editor and local exports never update (the release workflow stamps the build
tag into `application/config/version`).

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
blender -b --factory-startup -P blender/building_kit/build_kit.py  # building kit -> godot/assets/building_kit/kit.glb (~1 s)

cd godot
godot --headless --path . --import
godot --headless --path . --script res://tools/build_world.gd     # godot/world/ -> scenes/generated/neighborhood.tscn
godot --headless --path . --script res://tools/check_world.gd   # no satellite image, no hole in the ground mesh
godot --headless --fixed-fps 60 --path . --script res://tools/test_play.gd  # picker, walking, walls, boundary, kerbs
godot --headless --fixed-fps 60 --path . --script res://tools/test_cars.gd  # debug cars: park, get in, drive, get out; bus doors, signals, walking inside while it moves; articulated bus turning, reversing, walking through the joint
godot --headless --fixed-fps 60 --path . --script res://tools/test_breakables.gd  # a car bends a thin tree and knocks over a sign pole, lamp, gate, hydrant, bench, bike rack; a hydrant geyser and its repair
godot --headless --fixed-fps 60 --path . --script res://tools/test_plane.gd  # biplane: parks nose up on its tail wheel, holds level flight hands off, pitches, rolls, levels, wing tip trails, takes off, LAN state
godot --headless --fixed-fps 60 --path . --script res://tools/test_guns.gd  # armed biplane: G fires both guns, rounds break a car (grey then black smoke, engine dead), repair, LAN state, a round knocks a prop over
godot --headless --fixed-fps 60 --path . --script res://tools/test_fire_truck.gd  # fire truck: drives, the cannon aims where you look, the jet lands on a car and puts a burning one out, siren and beacons, props knocked over, players shoved, LAN state, cab view with a turning steering wheel, passenger seat
godot --headless --fixed-fps 60 --path . --script res://tools/test_horse.gd  # horse: stands at leg height, canters, gallops, stops, turns on the spot, hops; a fence holds it, jumped it clears 1.6 m and 2 m fences but not a 3.5 m one; neigh, LAN state, down and up again, gets off
godot --headless --fixed-fps 60 --path . --script res://tools/test_bus_bots.gd  # bot buses: both directions out, a departure every headway, indicators and doors at a stop, a turn, a red light, overtaking a parked car (or waiting and honking where there is no room), giving way, not slowing for oncoming traffic in a junction, riding to the map edge, vanishing and coming back, gliding far away (PLATEAU_TEST_ONLY=check,... runs some)
godot --headless --fixed-fps 60 --path . --script res://tools/test_car_bots.gd  # bot cars: spawned and moving, sent out again, passing an oncoming car without slowing, a head-on in one lane sorted out
godot --headless --fixed-fps 60 --path . --script res://tools/probe_traffic.gd -- 10  # not a test: 10 simulated minutes of traffic, buses per direction, stalls and what held them, tick cost
tools/test_lan.sh   # LAN game: a host and a client on this machine; riding in the host's bus, taking over a car, breakables, damage, leaving
tools/test_lan_buses.sh   # LAN game with bot buses: the client gets them (no wheel for anyone), the lights on the host's clock, riding one from a stop
godot --path . --script res://tools/screenshots_all.gd -- --milestone=M2  # viewpoints -> data/review/shots/M2/
godot --path . --script res://tools/screenshot.gd -- --pos=-90,-130,70 --look=0,0,0 --out=/tmp/shot.png
godot --path . --script res://tools/ground_swatches.gd            # every ground material -> data/review/<area>/ground_swatches.png
godot --path . --display-driver x11 --script res://tools/perf.gd  # frame time per viewpoint (vsync off; x11: a covered Wayland window stops drawing and gives bogus times)
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json godot --path . --display-driver x11 --script res://tools/perf.gd  # same on the Intel iGPU
```

## Controls

Keys are physical positions, so ZQSD on AZERTY. They can all be changed in **Settings** (welcome menu or Esc menu,
kept in `user://settings.cfg`), which also has the display mode, graphics quality, 3D resolution, vsync, interface size,
day or night and mouse sensitivity; the help lines show the current keys. The keys below are the defaults. F11 switches between a
window and borderless fullscreen. The interface scales with the window (designed for 1600 × 900), so it keeps its size
on a 4K screen; the first window fills 80 % of the screen.
- Walk: click to capture the mouse, Esc opens the menu (and frees it). WASD to move, Shift to run, Space to jump. The mouse wheel zooms the camera; zooming all the way in goes first person and zooming out comes back (like Roblox), V also switches first/third person. The body fades out when the camera comes close to it.
- Debug cars: 4 cars are parked next to the spawn point (on road or asphalt when there is some within ~20 m). C parks another one next to the player; Tab opens the vehicle menu, which parks any model you pick (click, or arrows + Enter; Tab or Esc closes it). E gets into the nearest car (within 3 m). Drive with W (throttle), S (brake, then reverse), A/D (steer; full lock at walking pace, fading with speed), Q/E turn signals (A/E on AZERTY; they cancel themselves after the turn), G (held) the horn (heard by the other players in LAN games too), X (held) drifts (a handbrake: the rear wheels lose grip so the tail slides out under power; countersteer with A/D), B rings a bus's city bell (LAN too), and the mouse to look around (the chase camera glides back behind the car while moving, and swings in front of it looking back once reversing for a moment; hold the right mouse button to keep the view where you put it); the mouse wheel zooms the chase camera. R puts the car back on its wheels, Space gets out. Engine (toy automatic gearbox), horn, bus bell, indicator, door and air-brake sounds are synthesized at runtime by `scripts/vehicle_audio.gd` (no audio files).
- The bus is walkable: O (driver) opens and closes its three sliding doors, V (or the mouse wheel zoomed all the way in) switches to the cab view, where the driver's arms hold the steering wheel and it turns with the steering. First person and the cab view carry over when taking and leaving the driver seat. Space leaves the driver seat into the aisle (the bus rolls on and sets its handbrake once slow). The player standing in it is carried along, also while it moves, and steps up onto its 36 cm floor through an open door; E near the driver seat takes the wheel again. Interior, doors, lamps and steering wheel come from `build_bus.py`, which also writes `godot/assets/cars/bus_idfm.json` (collision boxes, doors, interior, driver seat) for `scripts/car.gd`. Models: an Île-de-France Mobilités bus (Iveco Urbanway, built by `blender/vehicles/build_bus.py`, livery after `ref/`), KayKit hatchback by Kay Lousberg + Kenney Car Kit (both CC0, see `godot/assets/cars/CREDITS.md`), built into a `VehicleBody3D` by `scripts/car.gd` (per-model specs and handling exports at the top). Set `debug_cars` on Main to false to start without cars.
- The articulated bus (18 m Iveco Urbanway, same livery, parked at start next to the 12 m one) drives the same way and is walkable from end to end: two `VehicleBody3D` sections (`scripts/car.gd` + `scripts/car_trailer.gd`) hinged under a turntable by a joint (±52°, damped; it stiffens in reverse so backing up straight does not fold it), with a bellows rebuilt as the joint bends. O opens its four doors. Walking through the bellows hands the player over from one section to the other. `build_bus.py --model=artic` describes it as two sections and writes the rear section's objects, colliders and doors, the hitch and the bellows profile into `bus_idfm_artic.json`.
- Biplane (vehicle menu): a small toy taildragger built from primitive shapes by `scripts/plane.gd` (a `VehicleBody3D` like the cars, so it parks, is got in and out of with E / Space, and syncs in LAN games the same way), with arcade flight on top: lift with a stall, drag, propeller thrust fading with speed, and controls that hold the attitude when you let go (the nose follows the airflow, a shallow bank levels itself). Shift / Ctrl move the throttle lever, W / S nose down / up (S pulls, like a stick), A / D roll (steer on the ground), Q / E rudder (A / E on AZERTY), Ctrl at idle brakes on the ground, R levels the wings in the air (back on the wheels on the ground), V or the mouse wheel all the way in for the cockpit view. Full throttle lifts it off after ~50 m at ~65 km/h; it cruises at ~130 km/h, tops out near 160 km/h, and the engine fades out towards y = 190 m so it stays inside the map's boundary walls. The upper wing tips leave thin white trails at speed (seen by every player); the dash shows speed, height above the ground, throttle and STALL / PULL UP warnings. Getting out in the air drops you on the ground below while the empty plane glides on.
- Armed biplane (vehicle menu): the same plane in khaki with French roundels, two WWII-style machine guns under the lower wing and a ring sight (`scripts/plane_guns.gd`). Hold the left mouse button to fire: 24 rounds a second, every one a glowing tracer, converging 200 m ahead where an orange ring on the screen shows. Rounds hit what they meet: sparks and a ping on vehicles, a puff of dust elsewhere, and breakable props (lamps, sign poles, hydrants…) fall over. Every vehicle has health (5 per round; 100 for a car, about 300 for a bus, 60 for a biplane): past half of it the engine smokes grey; at 0 it breaks with a boom and a ball of fire, its engine dies (a shot-down plane glides down), its body is scorched and it pours black smoke (`scripts/wreck_smoke.gd`, trailing behind it if it still moves) until it is repaired a minute later. In LAN games the hits count on the shooter's peer and the damage on the peer simulating the vehicle hit; everyone sees the tracers, the smoke and the wrecks.
- Fire truck (vehicle menu): a red 6x6 airport crash tender after `ref/fire_truck.png` (built by `blender/vehicles/build_fire_truck.py`; 9 m, 16 t, all six wheels drive, the front two steer), with a working roof water cannon (`scripts/fire_truck.gd`, `scripts/water_cannon.gd`). The cannon aims where you look: the turret turns and the barrel rises to drop the jet on the point in the middle of the screen, allowing for gravity and air drag (about 80 m of reach), and a dashed blue ring shows where it lands. Hold the left mouse button to spray: the jet is simulated packet by packet, splashes where it lands and leaves wet patches that dry out. It nudges vehicles (a braked car's tyres hold it), shoves players, pushes debris, knocks light props (bins, sign poles, bollards…) over and holds against heavy ones, and 2 s of water on a burning wreck puts the fire out and the vehicle runs again. B switches the French two-tone siren and the flashing blue beacons on and off. In LAN games the water counts on the peer simulating the truck and acts on the peer simulating what it hits; everyone sees the turret, the jet and the beacons and hears the siren. Its cab is fitted out inside (dashboard and gauges, two seats, the cannon's joystick) behind see-through tinted glass: V or the mouse wheel zoomed all the way in gives the cab view, where the driver's hands hold the steering wheel and it turns with the steering. E from the truck's right side (or while another player drives it) sits you in the passenger seat: look around with the mouse, V for the passenger's view out of the cab, E to slide over to the wheel if nobody has it, Space to get out on the right. Other players see you seated there in your colour.
- Horse (vehicle menu): a toy chestnut horse with a black mane and tail, a white blaze and socks, saddle, stirrups and reins, built from primitive shapes by `scripts/horse.gd` and ridden by your look-alike in your colour. E gets on and off; W canters (27 km/h), W with Shift gallops (47 km/h), S stops then backs up slowly, A / D turn (on the spot too), G neighs, V or the mouse wheel zoomed all the way in gives the rider's view. Space jumps, the higher the faster it goes: from a canter it clears the map's 1.6 m bar fences and 2 m mesh fences (take off a few metres before), while the 3.5 m fences around pitches and high walls stop it. Its legs move in the gait of its speed (walk, trot, canter, gallop), step round on the spot as it turns, tuck over a jump and fold under it when it is down; the hooves clop on every footfall. It steps up kerbs and low steps, goes round street furniture instead of knocking it over, and in LAN games syncs like the other vehicles (everyone sees it jump). Shot by the armed biplane it lies down for a minute, or until the fire truck hoses it.
- Bot buses and cars (`scripts/traffic.gd`, `scripts/bus_bot.gd`): walk in through an open door at a stop and the bus carries you to the next stops; at the end of its route at the map edge it waits for you to get off. E next to one tells you a bot drives it. The tools leave them off unless `PLATEAU_BUSES=1`; `PLATEAU_CARS=n` sets the number of bot cars.
- Like in Euro Truck Simulator 2, vehicles bend thin trees (trunk up to 10 cm, up to 8 m tall: ~1,500 of them) and knock over sign poles, bus stop poles, route markers, guideposts, bollards, bin poles, lamps, traffic lights, light barriers, bike racks, benches, picnic tables, wheelie bins, parking meters, post boxes, info boards and fire hydrants (`scripts/breakables.gd`; kiosks, shelters, concrete blocks and masts hold). A tree bends away from the bumper, stays flat while the vehicle is over it and springs back up behind it; a pole snaps off and flies on as debris, and comes back 20 s later once the camera is 60 m away. Faster than 7 km/h for props (0.5 m/s for trees); slower they hold like any other obstacle. The vehicle loses the momentum it gives them, and they make a sound (a metal clang, a swish of leaves). A knocked-over fire hydrant (or water tap) leaves a 10 m geyser of water (3 m for taps, `scripts/geyser.gd`) that roars and lifts whatever is parked over it; the pipe is repaired a minute later, in view or not, the water easing off over the last 3 s.
- F1: fly camera (hold right mouse to look, WASD + Q/E, Shift faster, wheel for speed). F1 again drops the player below the camera.
- F2: graphics low/high (also in Settings). Low (no SSIL, SSAO or glow, FXAA instead of MSAA) is the default ("Auto") on an integrated GPU, high elsewhere; `PLATEAU_QUALITY=low|high` overrides until the quality is changed in the game. With the low settings, "Auto" 3D resolution renders at most 1920 pixels wide (FSR upscaling), for 4K laptops on an integrated GPU.
- N: night / day (also in Settings, kept between sessions; `PLATEAU_NIGHT=1|0` overrides until it is switched in the game). At night (`scripts/night.gd`) the sun becomes a pale blue moonlight that still casts shadows, the sky turns dark blue with stars and a moon (`shaders/night_sky.gdshader`) over a faint glow of the towns around, about 40 % of the buildings' rooms are lit, the street and path lamps glow and light the ground under them (not while knocked over), and the bot buses and cars drive with their headlights on. L switches the headlights of the vehicle you drive (the biplanes' landing lights): a beam that lights the road ahead (and casts shadows for your own vehicle), glowing lamps, dim red tail lamps and the buses' cabin lights; they switch on by themselves when you get in at night. Other players see your headlights; each player chooses day or night for themselves.
- F: identify what is under the crosshair: a building (number, OSM id, name, kind, height and source), a tree, a prop (kind, model, source, OSM id, bus stop lines, sign codes), a fence or the ground (piece kind, material, OSM source). The text is copied to the clipboard. X closes it, H hides the help.

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
it along its path far from the players (moving every third tick: about 6 ms a tick for 100 bots, headless).

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

[[landmark.module]]               # a kit module: model, facade, along, z, out, scale, tint, repeat = [step, n]
[[landmark.sign]]                 # a name sign: text, facade, along, z, width, color, plate
[[landmark.photo]]                # a reference photo: file, eye = [x, y, h above ground], target, fov (horizontal)
```

`world.json` buildings of a landmark carry `landmark` (its name), `toy.styles` (per-facade and volume styles;
`toy.runs[k][3]` and volume tiers index it) and `toy.columns` (schema 9). If a shape cannot be expressed with the
kit, the milestone plans a dedicated Blender script `blender/landmarks/<name>.py` whose model replaces the mass
(not needed yet). The reference photos never reach the game.

Milestones: see [MILESTONES.md](MILESTONES.md).

In the editor the world can also be rebuilt from Project > Tools > Rebuild Plateau world.
Coordinates everywhere in the pipeline: metres, x east, y north, z up, origin at Télécom Paris
(Lambert-93 641117.6, 6846184.3). Godot position = (x, z, -y).

Data: © OpenStreetMap contributors (ODbL), IGN (Licence Ouverte 2.0), Île-de-France Mobilités
(Licence Ouverte 2.0), Panoramax contributors (CC-BY-SA 4.0), Mapillary contributors (CC-BY-SA 4.0).
The orthophoto and street photos were only used to derive the map; none of them is in the game. Car models: Kenney Car Kit (CC0, www.kenney.nl), KayKit by Kay Lousberg (CC0).
