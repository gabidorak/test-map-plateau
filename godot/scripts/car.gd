extends VehicleBody3D
## Drivable toy car built at runtime from a downloaded model (assets/cars, see CREDITS.md): the
## model's four wheel nodes become VehicleWheel3D, the body gets a box collider. Call setup() before
## adding it to the tree. While `driving` (keys: the Settings actions, scripts/settings.gd; defaults on physical
## positions): W/S throttle and brake/reverse, A/D steer, Q/E turn signals (A/E on AZERTY), G (held) sounds the horn,
## X (held) drifts, B sounds a bus's RATP gong, R puts the car back on its wheels, the mouse orbits the chase camera
## (auto camera: it eases back behind the car once the mouse rests; the right button switches to the free camera, which
## keeps its direction; Z, W on AZERTY, held looks back; see _update_camera).
## game.gd handles getting in (E) and out (Space). The models face +Z, which is also VehicleBody3D's
## forward; their left side is +X.
## Models with a layout file (the bus: assets/cars/bus_idfm.json, written by blender/vehicles/build_bus.py)
## are walkable: a child StaticBody3D `inside` on the VEHICLE_INSIDE layer (only the player scans it) holds
## the floor, walls, seats and door openings, while the rigid body keeps its plain box from the wheel centres
## up for the world (kerbs pass under it; game.gd makes the player ignore that box). Sliding doors the driver
## opens and closes with O, an interior that carries the player (carries()), a driver seat and a cab view (V, or
## the mouse wheel zoomed all the way in, like Roblox). The driver's arms reach to hands on the steering wheel, which
## turns with the steering (STEERING_RATIO); the hands follow it up to HAND_TURN, then let it slide.
## A cab without a walkable interior (the fire truck: its fittings file's "cab"; the realistic cars: their cab file, see
## _cab_layout) has the same driver
## seat, steering wheel and cab view, and can have a passenger seat: the player sitting there (set_riding, game.gd)
## looks around with the car's cameras (the cab view from the passenger's eye); another player of a LAN game sitting
## there shows as a look-alike in their colour (show_passenger).
## Steering lock is large at low speed and fades with the speed. Drifting (X held) is a handbrake: the rear wheels (the
## non-steering ones, the rear section's too) lose most of their grip and drag a little, so the tail swings out under
## power; the steering keeps more lock for countersteering, and the grip comes back gradually on release. Engine, indicator and door sounds come
## from scripts/vehicle_audio.gd.
## Articulated vehicles (the 18 m bus: its layout has a "trailer") are two VehicleBody3D: this one, the front section
## that steers, and the rear section (`trailer`, scripts/car_trailer.gd) hinged to it by a joint at the hitch (yaw
## up to JOINT_YAW, a little pitch for crests), lightly damped. The middle and rear axles drive (only the rear one
## in reverse). Each section's origin is on its centre of mass (VehicleBody3D's tyre maths assumes it), so the
## rear section's frame is the car's shifted by rear_offset. The
## bellows mesh is rebuilt from the layout's profile whenever the joint bends, and boxes along it keep the player
## walking through it inside (over the turntable floor disc); each section carries the player standing in it
## (carrier_at). Move the vehicle with place(), which puts the rear section straight behind. A cab file can have a
## "trailer" and "hitch" too (the truck's semi-trailer, at the fifth wheel): not walkable, no bellows, and towed (_towed:
## its wheels only roll and brake; the truck's own driven wheels push in reverse too).
## LAN games (scripts/net.gd): a vehicle another peer simulates is `remote`, its bodies frozen kinematic and posed from
## that peer's states (apply_net_state); the wheels still turn and steer, and lamps, doors, horn and sound follow the
## states.
## Bot drivers (scripts/bus_bot.gd, the bot buses of scripts/traffic.gd): a vehicle with a `pilot` takes its pedals,
## steering, horn and indicators from it instead of the keys (pilot.drive), on the peer simulating it; its states tell
## the others (bot_driven: the driver look-alike shows, nobody can take the wheel). A bot bus waiting to come back in
## at the map edge is `stowed`: hidden, out of the physics, everywhere. A parked vehicle at rest sleeps (out of the
## solver, its script idle) until something touches or pushes it, or someone gets in (_sleep_parked).
## Damage (the armed biplane's rounds, scripts/plane_guns.gd): each vehicle has `health` (HEALTH for a 1,200 kg car,
## more for heavier ones); hits only count on the peer simulating it (damage), the others follow its states. Under
## half of it, grey smoke comes out of the engine; at 0 it is `broken`: a boom and a ball of fire, the engine dies, the
## body is scorched and black smoke billows out of it (scripts/wreck_smoke.gd) until it is repaired REPAIR_AFTER s
## later, or until the fire truck's water cannon has hosed it for EXTINGUISH s (douse), which puts the fire out.
## PTA Online's player vehicles (scripts/modes/online_mode.gd) take `crash_damage` (a sudden change of speed of CRASH_FROM
## m/s and more in a tick hurts, CRASH_WRECK m/s breaks it from full health) and don't repair themselves
## (`repairs_itself`: they are repaired at a garage, paid). Paint (`paint`, set_paint; scripts/paint.gd): PTA Online's
## repaints, the far mesh made again in the new colour.
## Headlights (set_headlights; L for the driver, game.gd): a spot light for the beam (casting shadows from the vehicle
## the player drives), glowing lamps, the tail lamps dimly lit and a walkable vehicle's cabin lights. Bots drive with
## them on at night (`night`, scripts/night.gd).
## Far from the camera (FAR_DETAIL m) each section is drawn as one mesh of one material instead of its dozens of
## surfaces (_build_far): the doors shut and the wheels still, the head and tail lamps glowing with the headlights.
## Water (scripts/water.gd, _water_physics): a vehicle driven or fallen into a lake splashes, floats nose down a moment
## (its hull's buoyancy is more than its weight while dry), fills over FLOOD_TIME and settles on the bed; the water drags
## on it, and its engine drowns (no drive) once the water is half way up its body. It drains again on land.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const Trailer = preload("res://scripts/car_trailer.gd")
const WreckSmoke = preload("res://scripts/wreck_smoke.gd")
const Paint = preload("res://scripts/paint.gd")
const Water = preload("res://scripts/water.gd")
const Prefs = preload("res://scripts/settings.gd")
const KENNEY_WHEELS := ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]
## Per model: file in assets/cars, scale, body mesh node, wheel nodes (front left, front right, back
## left, back right), credit, mass (kg; engine, brakes and suspension scale with it), power (engine
## factor), max_speed (m/s), max_steer (rad at walking pace), steer_fade_speed (m/s, the lock is halved there),
## grip (the tyres' wheel_friction_slip), engine_at (where a damaged engine smokes: share of the length from the front,
## 0.22 by default; a mid-engined car's is behind the seats), layout (json next to the model), sound (vehicle_audio kind), traction_from (index of the first driven wheel; all drive by default), trailer_mass (kg,
## rear section of an articulated vehicle), label (name in the vehicle menu, see display_name), plane (built and flown
## by scripts/plane.gd, which extends this script, instead), guns (a plane's machine guns), turret (a two-seat plane's
## belly turret, worked from the passenger seat), roof_gun (an armoured car's machine gun on its roof hatch, worked from
## the passenger seat: scripts/armored_car.gd, which extends this script, from the cab file's "turret"), cab (a car with a fitted-out cabin and real materials, built by
## blender/vehicles/build_car.py or converted from a ready-made model by import_car.py, or import_textured.py when it
## comes with its own textures: json next to the model with
## its wheels, lamps and cab, see _cab_layout), fittings (the fire truck's lamps and water cannon, json next to the
## model: scripts/fire_truck.gd, which extends this script, drives it), police
## (a police car with a light bar and a siren, the "beacons" of its cab file: scripts/police_car.gd, which extends this
## script), horse (ridden instead: scripts/horse.gd, which extends this script), jet_ski (on the lakes: scripts/jet_ski.gd,
## which extends this script). Missing
## keys take the Kenney Car Kit values (scale 1.5: ~2.8 m -> ~4.2 m); the wheels beyond the first four are a third axle.
const SPECS := {
	"bus-idfm": {"label": "IDFM bus (12 m)", "file": "bus_idfm.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 12000.0, "power": 0.6, "max_speed": 38.0, "max_steer": 0.8, "steer_fade_speed": 11.0,
			"layout": "bus_idfm.json",
			"sound": "bus", "credit": "Iveco Urbanway, IDFM livery, built by blender/vehicles/build_bus.py"},
	"bus-idfm-artic": {"label": "Articulated bus (18 m)", "file": "bus_idfm_artic.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_middle_left", "wheel_middle_right"],
			"traction_from": 2, "mass": 10000.0, "trailer_mass": 7000.0, "power": 0.6, "max_speed": 36.0,
			"max_steer": 0.8, "steer_fade_speed": 11.0, "layout": "bus_idfm_artic.json", "sound": "bus",
			"credit": "Iveco Urbanway 18 m articulated, IDFM livery, built by blender/vehicles/build_bus.py"},
	"kaykit-hatchback": {"label": "Hatchback", "file": "kaykit_hatchback.glb", "scale": 5.0, "body": "car_hatchback",
			"wheels": ["car_hatchback_wheel_front_left", "car_hatchback_wheel_front_right",
				"car_hatchback_wheel_rear_left", "car_hatchback_wheel_rear_right"],
			"credit": "Kay Lousberg (KayKit), CC0"},
	"compact-hatchback": {"label": "Compact hatchback", "file": "compact_hatchback.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1180.0, "power": 0.95, "max_speed": 50.0, "cab": "compact_hatchback.json",
			"credit": "five-door city car, built by blender/vehicles/build_car.py"},
	"family-suv": {"label": "Family SUV", "file": "family_suv.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1500.0, "power": 1.0, "max_speed": 52.0, "cab": "family_suv.json",
			"credit": "compact crossover with a black roof, built by blender/vehicles/build_car.py"},
	"police-hatchback": {"label": "Police nationale car", "file": "police_hatchback.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1180.0, "power": 0.95, "max_speed": 50.0, "cab": "police_hatchback.json", "police": true,
			"credit": "the compact hatchback in the Police nationale livery, built by blender/vehicles/build_car.py"},
	"renault-zoe": {"label": "Renault Zoe", "file": "renault_zoe.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1470.0, "power": 0.85, "max_speed": 37.5, "cab": "renault_zoe.json", "sound": "electric",
			"credit": "Renault Zoe (2013), a ready-made model converted by blender/vehicles/import_car.py"},
	"audi-r8": {"label": "Audi R8", "file": "audi_r8.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1600.0, "power": 1.3, "max_speed": 70.0, "steer_fade_speed": 10.0, "grip": 1.8,
			"cab": "audi_r8.json", "sound": "v10", "engine_at": 0.7,
			"credit": "Audi R8 V10 (2016), a ready-made model converted by blender/vehicles/import_car.py"},
	"mercedes-1928": {"label": "Mercedes 1928", "file": "mercedes_1928/mercedes_1928.gltf", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1600.0, "power": 0.5, "max_speed": 27.8, "max_steer": 0.6, "grip": 1.25,
			"cab": "mercedes_1928/mercedes_1928.json", "sound": "vintage",
			"credit": "1928 Mercedes tourer, a ready-made textured model converted by blender/vehicles/import_textured.py"},
	"bmw-m4": {"label": "BMW M4", "file": "bmw_m4.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 1570.0, "power": 1.25, "max_speed": 69.0, "steer_fade_speed": 10.0, "grip": 1.7,
			"cab": "bmw_m4.json", "sound": "straight6",
			"credit": "BMW M4 coupé (2015), a ready-made model converted by blender/vehicles/import_car.py"},
	"audi-rs6": {"label": "Audi RS6 Avant", "file": "audi_rs6.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 2075.0, "power": 1.28, "max_speed": 69.4, "steer_fade_speed": 10.0, "grip": 1.7,
			"cab": "audi_rs6.json", "sound": "v8",
			"credit": "Audi RS6 Avant \"Starwars Hycade\" (2016), a ready-made model converted by blender/vehicles/import_car.py"},
	"sedan": {}, "taxi": {}, "suv": {"label": "SUV"}, "police": {}, "hatchback-sports": {"label": "Sports hatchback"},
	"van": {}, "sedan-sports": {"label": "Sports sedan"}, "suv-luxury": {"label": "Luxury SUV"}, "delivery": {"label": "Delivery van"},
	"ambulance": {},
	"fire-truck": {"label": "Fire truck", "file": "fire_truck.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_middle_left", "wheel_middle_right",
				"wheel_rear_left", "wheel_rear_right"],
			"mass": 16000.0, "power": 0.32, "max_speed": 28.0, "max_steer": 0.8, "steer_fade_speed": 11.0,
			"fittings": "fire_truck.json",
			"sound": "truck", "credit": "6x6 airport crash tender, built by blender/vehicles/build_fire_truck.py"},
	# 4x2 tractor unit, unladen: rear-wheel drive, 750 hp, the EU limiter's 90 km/h, a truck's lock
	"volvo-fh16": {"label": "Volvo FH16 truck", "file": "volvo_fh16/volvo_fh16.gltf", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"traction_from": 2, "mass": 8500.0, "power": 0.9, "max_speed": 25.0, "max_steer": 0.75,
			"steer_fade_speed": 10.0, "cab": "volvo_fh16/volvo_fh16.json", "sound": "diesel6",
			"credit": "Volvo FH16 750 tractor unit (Globetrotter cab), a ready-made model converted by blender/vehicles/import_truck.py"},
	# the same with its three-axle curtain-sider semi-trailer, empty (the cab file's "trailer": towed, ~17.6 m long)
	"volvo-fh16-trailer": {"label": "Volvo FH16 + trailer", "file": "volvo_fh16/volvo_fh16_trailer.gltf", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"traction_from": 2, "mass": 8500.0, "trailer_mass": 7000.0, "power": 0.75, "max_speed": 25.0,
			"max_steer": 0.75, "steer_fade_speed": 10.0, "cab": "volvo_fh16/volvo_fh16_trailer.json", "sound": "diesel6",
			"credit": "Volvo FH16 750 with a curtain-sider semi-trailer, a ready-made model converted by blender/vehicles/import_truck.py"},
	# armoured 4x4 (GAZ-233115 "SPM-2", ~7.2 t, 215 hp turbo diesel, four-wheel drive), a machine gun on its roof hatch
	# worked from the passenger seat (scripts/armored_car.gd)
	"gaz-tiger": {"label": "GAZ Tiger (roof gun)", "file": "gaz_tiger.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 7200.0, "power": 0.7, "max_speed": 33.0, "max_steer": 0.65, "steer_fade_speed": 10.0,
			"cab": "gaz_tiger.json", "sound": "diesel4", "roof_gun": true,
			"credit": "GAZ Tiger-M armoured car with a PKM on its roof hatch, a ready-made model converted by blender/vehicles/import_car.py"},
	"biplane": {"label": "Biplane", "plane": true, "credit": "toy biplane built by scripts/plane.gd"},
	"biplane-armed": {"label": "Armed biplane", "plane": true, "guns": true,
			"credit": "toy fighter biplane built by scripts/plane.gd"},
	"biplane-gunner": {"label": "Biplane with gunner", "plane": true, "turret": true,
			"credit": "toy two-seat biplane built by scripts/plane.gd"},
	"horse": {"label": "Horse", "horse": true, "credit": "toy horse built by scripts/horse.gd"},
	"jet-ski": {"label": "Jet-ski", "jet_ski": true, "credit": "toy jet-ski built by scripts/jet_ski.gd"},
}
const MODELS := ["bus-idfm", "bus-idfm-artic", "kaykit-hatchback", "sedan", "taxi", "suv", "police", "hatchback-sports", "van",
		"sedan-sports", "suv-luxury", "delivery", "ambulance", "compact-hatchback", "family-suv", "police-hatchback", "renault-zoe", "fire-truck", "biplane", "biplane-armed", "biplane-gunner",
		"horse", "audi-r8", "mercedes-1928", "bmw-m4", "audi-rs6", "volvo-fh16", "volvo-fh16-trailer", "gaz-tiger", "jet-ski"]
const REST_LENGTH := 0.2
const BLINK := 0.75                         # s, indicator period
const LAMP_DEPTH := 0.45                    # m, furthest a corner lamp sits behind its body box's face (_on_body)
const KENNEY_HEAD := Vector2i(3, 3)         # the Kenney Car Kit palette's swatch (16 x 4) of the headlights (_own_lamps)
const KENNEY_TAIL := Vector2i(5, 3)         # and of the tail lamps
const DOOR_TIME := 1.6                      # s to open or close
const DOOR_OUT := 0.1                       # plug doors: leaves first swing out this far, then slide
const STEERING_RATIO := 3.5                 # steering wheel turn per road wheel angle: full lock stays under half a
											# turn, so a still frame never reads as the opposite way
const HAND_TURN := 1.6                      # rad: the driver's hands turn with the wheel this far, then slide on it
const GRIPS := [150.0, 30.0]                # left and right hand on the rim, degrees from 3 o'clock (10 and 2 o'clock)
const STEERING_SEEN := 60.0                 # m: farther from the camera, the steering wheel and hands are not turned
const JOINT_YAW := 0.9                      # rad, articulation limit either way (~52°)
const JOINT_PITCH := 0.12                   # rad, the sections fold this much over crests and dips
const JOINT_DAMP := 3.0                     # torque per rad/s of relative yaw, per kg of rear section (calms the joint)
const JOINT_REVERSE_SPRING := 100.0         # rolling backwards the joint stiffens: torque per rad, per kg of rear section
const DRIFT_GRIP := 0.35                    # rear wheel grip while drifting, fraction of `grip`
const DRIFT_BRAKE := 0.12                   # rear handbrake while drifting, fraction of max_brake
const DRIFT_STEER := 0.45                   # steering lock kept while drifting, fraction of max_steer
const DRIFT_RECOVER := 2.0                  # /s, the rear grip coming back once X is released
const BELLOWS_SEGMENTS := 4                 # wall boxes along the bellows (walkable articulation)
const BELLOWS_SEEN := 100.0                 # m: farther from the camera, the bellows is not bent
const HEALTH := 100.0                       # a 1,200 kg car's; heavier vehicles have more (with the square root of the mass)
const DAMAGED := 0.5                        # share of the health under which the engine smokes grey
const REPAIR_AFTER := 60.0                  # s a broken vehicle smokes before it is repaired
const PARK_SLEEP := 3.0                     # s parked at rest before its bodies sleep (_sleep_parked)
const EXTINGUISH := 2.0                     # s of the fire truck's water on a broken vehicle that put its fire out
const CRASH_FROM := 8.0                     # m/s of speed lost or gained in a tick from which a knock hurts (crash_damage)
const CRASH_WRECK := 22.0                   # m/s in a tick that breaks a vehicle from full health (~80 km/h into a wall)
const HEADLIGHT := Color(1.0, 0.93, 0.8)    # beam colour, warm white
const BEAM_RANGE := 60.0                    # m
const BEAM_ANGLE := 32.0                    # degrees from the axis to the edge of the cone
const BEAM_TILT := 0.04                     # rad down
const BEAM_ENERGY := 14.0
const BEAM_FADE := 140.0                    # m from the camera beyond which the beams fade out
const FAR_DETAIL := 120.0                   # m from the camera beyond which a section is drawn as one mesh (_build_far)
const REMOTE_SLEEP := 180.0                 # m from the eye beyond which a remote copy is frozen STATIC, runs nothing
const REMOTE_WAKE := 140.0                  # m it must come back within to wake (hysteresis: no toggling at the edge)
const CABIN_LIGHT := Color(0.88, 0.93, 1.0)      # a bus's cabin lights, cool white
const FLOAT_BUOYANCY := 1.6                 # a dry hull's buoyancy fully under water, times its weight...
const SUNK_BUOYANCY := 0.3                  # ...and once full of water
const FLOOD_TIME := 12.0                    # s in the water to fill up
const DRAIN_TIME := 30.0                    # s on land to drain again
const WATER_DRAG := 1.2                     # /s of the velocity, fully under water
const DROWN_DEPTH := 0.45                   # share of the body's height under water that stops the engine

@export var engine_per_wheel := 2800.0      # N on each of the four driven wheels, more when starting
@export var max_brake := 80.0
@export var max_speed := 44.0               # m/s (~160 km/h)
@export var max_reverse_speed := 12.0
@export var max_steer := 0.75               # rad at walking pace...
@export var steer_fade_speed := 8.0         # ...halved around this speed (m/s), ~0.1 rad at top speed
@export var steer_speed := 2.5              # rad/s towards the target, twice that back to straight
@export var grip := 1.5                     # wheel_friction_slip: ~ tyre friction coefficient
@export var com_drop := 0.35                # centre of mass this far below the wheel centres (less roll)
@export var sensitivity := 0.0025
@export var camera_distance := 7.5
@export var zoom_step := 1.2                # chase camera distance factor per mouse wheel notch

## The free camera (true) or the auto one, for every vehicle, until the game quits (the camera mode button switches it).
static var free_camera := false

var driving := false
var model_name := ""
var half_extents := Vector3.ONE             # of the body box, in the car frame (for getting out)
var camera: Camera3D
var indicator := 0                          # 1 left, -1 right (same sign as steering), 0 off
var doors_open := false
var has_doors := false
var interior := AABB()                      # walkable volume in the car frame (size 0: not walkable)
var driver_seat := Vector3.ZERO             # car frame
var driver_exit := Vector3.ZERO             # car frame, in the aisle beside the driver seat
var passenger_seat := Vector3.ZERO          # car frame, only when has_passenger_seat
var has_passenger_seat := false
var riding := false                         # the player sits in the passenger seat (set_riding)
var audio: VehicleAudio
var inside: StaticBody3D                    # walkable hull, only with a layout
var door_centres: Array[Vector3] = []       # car frame, doorway centre on the floor
var cab_view := false                       # driver's eye view instead of the chase camera
var trailer: Trailer                        # rear section of an articulated vehicle, or null
var rear_offset := Vector3.ZERO             # the rear section's origin in the car frame while straight
var extents_center := Vector3.ZERO          # centre of the half_extents box in the car frame (x, z)
var net_id := ""                            # LAN games: the vehicle's id on every peer
var remote := false                         # LAN games: simulated by another peer (set_remote)
var _remote_asleep := false                 # LAN, remote: far from the eye, frozen STATIC and not ticked (update_remote_lod)
var pose_asleep := false                    # LAN, remote: posed every tick even asleep (net.gd _play_back)
var bells := 0                              # bell strikes so far (LAN: its parity tells the peers to ring)
var controls := true                        # false while a menu is open: the driver's keys do nothing
var hold := false                           # held still at a race start (scripts/races.gd): brakes on, no throttle
var health := HEALTH
var max_health := HEALTH
var broken := false                         # health 0: engine dead, black smoke
var crash_damage := false                   # hard knocks take health (PTA Online's player vehicles)
var repairs_itself := true                  # broken: repaired REPAIR_AFTER s later or by the water cannon
var paint := ""                             # its colour (scripts/paint.gd id; "" its own: set_paint)
var _crash_v := Vector3.ZERO                # velocity at the last tick's crash check (_check_crash)
var _crash_frame := -2                      # physics frame of that check
var smoke_spot := Vector3.ZERO              # car frame: where the smoke comes out (the engine)
var smoke_size := 1.0

var _cam_pivot: Node3D
var _arm: SpringArm3D
var _cab_camera: Camera3D                   # driver's (or passenger's) eye view (V), only with a cab
var _driver_eye := Vector3.ZERO             # car frame
var _passenger_eye := Vector3.ZERO
var _cab_pitch := 0.0                       # added to the cab view's pitch (a car's eye is low: it looks less down)
var _figure := 1.0                          # size of the seated look-alikes (a car's seats are low under its roof)
var _cab_file := {}                         # the spec's "cab" file: wheels, lamps and cab of a realistic car
var _cam_zoom := 7.5                        # chase camera distance the arm eases to
var _zoom_range := Vector2(3.0, 20.0)       # closest (zooming in past it: cab view) and furthest
var _follow_yaw := 0.0
var _look_yaw := 0.0                        # mouse offset from _follow_yaw (auto camera: eases back once the mouse rests)
var _look_pitch := -0.22
var _look_idle := 0.0                       # s since the mouse last turned the view
var _looking_back := false                  # the look back key held: the view turned half round
var _mode_held := -1.0                      # s the camera mode button has been down (-1: up)
var _was_free := false                      # the view kept its direction in the world last frame
var _was_aim := false                       # ...because the vehicle aimed with it (holds_aim)
var _force_scale := 1.0                     # engine and brakes, from the mass and the model's power
var _cam_height := 2.2                      # camera pivot above the car origin
var _blink_t := 0.0
var _signal_armed := false                  # the wheel has turned the signalled way: cancel when back
var _lamps := {1: [], -1: []}               # indicator meshes per side
var _brake_lamps: Array[MeshInstance3D] = []
var _brake_mat: Material                    # on the brake lamps now
var _reverse_lamps: Array[MeshInstance3D] = []   # a cab file's "reverse_lights", lit while backing up
var _reversing := false
var _net_pos := Vector3.ZERO                # LAN, remote: the last tick's position (which way it moves)
var _lamp_mats := {}                        # "indicator"/"brake" -> [off, on]
var _steering_wheel: Node3D
var _steering_rest := Transform3D.IDENTITY
var _posed_turn := NAN                      # steering wheel turn when last posed (and whether the hands were)
var _posed_hands := false
var _doors: Array[Dictionary] = []          # {leaves, closed (positions), dirs (slide sign), slide, shape}
var _door_t := 0.0                          # 0 closed .. 1 open
var _driver_dummy: Node3D                   # driver body, arms and hands, in the car frame
var _driver_body: MeshInstance3D            # hidden in the cab view (the eye is inside it)
var _arms: Array[MeshInstance3D] = []       # left, right
var _hands: Array[MeshInstance3D] = []
var _shoulders: Array[Vector3] = []         # car frame
var _wheel_centre := Vector3.ZERO           # steering wheel in the car frame: centre, axis (towards the driver),
var _wheel_axis := Vector3.UP               # driver's right and 12 o'clock directions, grip radius
var _wheel_right := Vector3.LEFT
var _wheel_up := Vector3.BACK
var _grip_radius := 0.2
var _throttle := 0.0
var _rear_wheels: Array[VehicleWheel3D] = []    # non-steering wheels, the rear section's included (drift)
var _drift := 0.0                           # 0 full grip .. 1 drifting
var _net_bell := -1                         # LAN, remote vehicle: bell parity last received (-1: none yet)
var _total_mass := 1200.0                   # both sections
var _wheel_count := 4
var _rear_model: Node3D                     # the rear section's part of the model (under the trailer)
var _hitch := Vector3.ZERO                  # car frame
var _body_faces := PackedVector3Array()     # the model's triangles but the wheels' (car frame), for _on_body
static var _lamp_spots := {}                # "<model> <point>" -> the point on the body (_on_body)
static var _own_lamp_meshes := {}           # model -> [body without its lamps, head lamps, tail lamps] (_own_lamps)
var _own_head: MeshInstance3D               # a toy car's own headlights, split out of its body (_own_lamps)
var _towed := false                         # the rear section is a semi-trailer (from the cab file): it does not drive
var _joint: Generic6DOFJoint3D
var _bellows := {}                          # profile, in the car frame (layout "bellows")
var _bellows_profiles := []                 # ridge and valley: [points, normals] (PackedVector2Array)
var _bellows_mesh: ArrayMesh
var _bellows_arrays := []                   # mesh arrays; vertices and normals rewritten when the joint bends
var _bellows_rel := Transform3D()           # rear section in the car frame when the bellows was last built
var _joint_walls: Array[CollisionShape3D] = []    # per segment: left wall, right wall, roof
var _bellows_hull: StaticBody3D             # walls of the walkable passage through the bellows
var _skin: StandardMaterial3D               # the driver look-alike's colour
var _passenger: MeshInstance3D              # look-alike in the passenger seat
var _passenger_skin: StandardMaterial3D
var _passenger_taken := false               # LAN games: another player sits in the passenger seat
var _remote_braking := false
var _smoke: WreckSmoke                      # made at the first smoke
var _broken_t := 0.0                        # s since it broke
var _doused := 0.0                          # s of water on it since it broke
var _net_seen := false                      # LAN, remote vehicle: a state came already (no boom for a wreck on joining)
var pilot: Object                           # bot driver (scripts/bus_bot.gd) on the peer simulating it, or null
var bot_driven := false                     # LAN, remote vehicle: a bot drives it (its states say so)
var stowed := false                         # hidden and out of the physics (a bot bus off the map, set_stowed)
var flooded := 0.0                          # 0 dry .. 1 full of water (_water_physics)
var in_water := 0.0                         # share of the body's height under water now
var _rest_t := 0.0                          # s parked at rest (_sleep_parked)
var _braking := false                       # brake lamps on (the driver's or the pilot's pedal)
var _stowed_layers := Vector2i.ZERO         # collision layer and mask of the bodies before stowing
var headlights := false
var _beam: SpotLight3D                      # null: no headlights (the horse)
var _head_lamps: Array[MeshInstance3D] = [] # lamp boxes (models without their own)
var _lit_surfaces: Array = []               # [MeshInstance3D, surface, material when lit]: the model's own lamps
var _cabin_lights: Array[OmniLight3D] = []
const BOT_COLOR := Color(0.16, 0.3, 0.55)   # the bot drivers' uniform

static var _soot: StandardMaterial3D        # drawn over a broken vehicle's meshes
static var night := false                   # scripts/night.gd: bots drive with their headlights on
static var _lamp_shader: Shader             # the model's own lamp surfaces, lit (_build_headlights)
static var _far_meshes := {}                # model (+ "/rear", + "#" paint) -> its sections' far mesh, shared (null: none)
static var _far_material: ShaderMaterial
static var _far_images := {}                # albedo texture -> its Image, decompressed, while merging (_far_colours)
var _far: Array[MeshInstance3D] = []        # the sections' far meshes (_build_far)


## Name of `model` for menus: its spec's label, else the model name capitalized ("sedan" -> "Sedan").
## Whether `model` carries a weapon (the armed biplane's guns, the two-seater's turret, the GAZ Tiger's roof gun).
static func is_armed(model: String) -> bool:
	var spec: Dictionary = SPECS.get(model, {})
	return spec.get("guns", false) or spec.get("turret", false) or spec.get("roof_gun", false)


static func display_name(model: String) -> String:
	return SPECS[model].get("label", model.replace("-", " ").capitalize())


## Name of `model` inside a sentence ("your taxi", "your Audi R8"): display_name in lower case, unless it holds a name
## (a maker's, or a word with a capital past its first letter: "BMW M4", "IDFM bus (12 m)").
static func common_name(model: String) -> String:
	var label := display_name(model)
	for w: String in label.split(" "):
		if w.substr(1) != w.substr(1).to_lower() or w in ["Audi", "Mercedes", "Renault", "Volvo"]:
			return label
	return label.to_lower()


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "Car_" + model.replace("-", "_")
	mass = float(spec.get("mass", 1200.0))
	max_speed = float(spec.get("max_speed", max_speed))
	max_steer = float(spec.get("max_steer", max_steer))
	grip = float(spec.get("grip", grip))
	steer_fade_speed = float(spec.get("steer_fade_speed", steer_fade_speed))
	_configure_body(self)
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "Kenney Car Kit, CC0")]})
	var layout: Dictionary = {}
	if spec.has("layout"):
		layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cars/" + spec["layout"]))
	if spec.has("cab"):
		_cab_file = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cars/" + spec["cab"]))
	# an articulated vehicle's rear section and hitch: a walkable layout's, or a cab file's (a semi-trailer)
	var art: Dictionary = layout if layout.has("trailer") else _cab_file

	var m: Node3D = load("res://assets/cars/" + spec.get("file", model + ".glb")).instantiate()
	m.scale = Vector3.ONE * float(spec.get("scale", 1.5))
	add_child(m)
	var body := m.find_child(spec.get("body", "body"), true, false) as MeshInstance3D
	var wheels := _find_meshes(m, spec.get("wheels", KENNEY_WHEELS))
	var rear_wheels: Array[MeshInstance3D] = []
	if art.has("trailer"):
		rear_wheels = _find_meshes(m, art["trailer"]["wheels"])
	# put the bottom of the wheels on y = 0
	var ground := INF
	for w in wheels + rear_wheels:
		ground = minf(ground, (_in_car(w) * w.get_aabb()).position.y)
	m.position.y -= ground
	var rear_off := Vector3.ZERO
	if art.has("trailer"):
		# VehicleBody3D takes the body origin for the centre of mass in its tyre maths (contact velocity =
		# linear_velocity + ω × (contact - origin)), so each section's origin goes on its centre of mass: else
		# every turn makes the tyres fight a phantom sideways slip of ω × the offset. Front section: midway
		# between its axles, so the middle axle carries its share. Rear section: a quarter of the way from its axle
		# to the hitch, so the hitch presses on the middle axle too.
		m.position.z -= _mean_z(wheels)
		var hitch: Vector3 = Vector3(art["hitch"][0], art["hitch"][1], art["hitch"][2]) * m.scale + m.position
		rear_off = Vector3(0.0, 0.0, lerpf(_mean_z(rear_wheels), hitch.z, 0.25))
		_hitch = hitch
		_towed = not layout.has("trailer")      # a cab file's rear section: a semi-trailer, towed
	var box: AABB = _in_car(body) * body.get_aabb()
	var wheel_y := _add_wheels(self, wheels, 2, int(spec.get("traction_from", 0)))
	half_extents = box.size * 0.5
	# box from the wheel centres up, so kerbs pass under it
	_add_box(self, Vector3(box.get_center().x, (box.end.y + wheel_y) * 0.5, box.get_center().z),
			Vector3(box.size.x, box.end.y - wheel_y, box.size.z))
	_total_mass = mass
	_wheel_count = wheels.size()
	if art.has("trailer"):
		var rear_box := _build_trailer(m, art["trailer"], rear_wheels, float(spec.get("trailer_mass", mass * 0.6)), rear_off)
		rear_box.position += rear_off
		# the whole vehicle, straight (spawning, getting in, chase camera)
		var whole := box.merge(rear_box)
		half_extents = whole.size * 0.5
		extents_center = Vector3(whole.get_center().x, 0.0, whole.get_center().z)
	_force_scale = _total_mass / 1200.0 * float(spec.get("power", 1.0))
	_set_max_health()
	# the engine: under the bonnet (or behind the seats: the spec's "engine_at", share of the length from the front), at
	# the back of a bus
	smoke_spot = Vector3(box.get_center().x, box.end.y - 0.3, box.position.z + 1.2) if spec.has("layout") \
			else Vector3(box.get_center().x, box.position.y + box.size.y * 0.55,
				box.end.z - box.size.z * float(spec.get("engine_at", 0.22)))
	if not layout.is_empty():
		_build_layout(m, layout)
	var cab := _cab_layout(layout)
	if cab.has("driver_seat"):
		_build_cab(m, cab)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, wheel_y - com_drop, 0.0 if trailer else box.get_center().z)
	_build_lamps(m, box, layout if not layout.is_empty() else _cab_file)
	if not _cab_file.is_empty():
		_gloss_paint(m)

	audio = VehicleAudio.new()
	audio.position = Vector3(0.0, 1.0, box.end.z - 1.0 if spec.has("layout") else box.get_center().z)
	audio.setup(spec.get("sound", "car"))
	add_child(audio)

	_build_chase_camera(maxf(camera_distance, half_extents.z * 2.1), box.end.y + 0.5)
	_build_far()


## Chase camera: a top-level pivot `height` above the car origin, with a spring arm `length` long (the mouse wheel
## zooms it from 0.45 to 2.5 times that) holding `camera`.
func _build_chase_camera(length: float, height: float) -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.top_level = true
	add_child(_cam_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = length
	_cam_zoom = length
	_zoom_range = Vector2(0.45, 2.5) * length
	_cam_height = height
	_arm.collision_mask = Layers.SOLID
	var arm_shape := SphereShape3D.new()
	arm_shape.radius = 0.2
	_arm.shape = arm_shape
	_arm.margin = 0.1
	_cam_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 1500.0
	camera.position = Vector3(0.0, 0.0, length)  # where the arm puts it without a hit (it only runs in use)
	_arm.add_child(camera)


## Health from the mass of the whole vehicle (_total_mass), full.
func _set_max_health() -> void:
	var k := clampf(sqrt(_total_mass / 1200.0), 0.6, 3.0)
	max_health = HEALTH * k
	health = max_health
	smoke_size = clampf(k, 0.8, 1.8)


## Physics settings shared by the car and its rear section.
func _configure_body(b: VehicleBody3D) -> void:
	b.angular_damp = 1.0                    # calms wobbles and spins after knocks
	var mat := PhysicsMaterial.new()
	mat.friction = 0.3                      # body against walls: slide along them instead of snagging
	mat.bounce = 0.0
	b.physics_material_override = mat
	b.collision_layer = Layers.VEHICLES
	# not PLAYER: the player never pushes or stops a car (its own move_and_slide keeps it out), so walking
	# inside a moving bus does not disturb it. The other players of a LAN game stop it (remote_player.gd: their
	# own move_and_slide is on another computer), except in or at the open doors of a bus.
	b.collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.DEBRIS \
			| Layers.REMOTE_PLAYER
	b.add_to_group("vehicles")              # thin trees bend and light props break in front of it (breakables.gd)


## Mean z of the wheel centres, car frame.
func _mean_z(wheels: Array[MeshInstance3D]) -> float:
	var z := 0.0
	for w in wheels:
		z += (_in_car(w) * w.get_aabb()).get_center().z / wheels.size()
	return z


func _find_meshes(root: Node, names: Array) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: String in names:
		out.append(root.find_child(n, true, false) as MeshInstance3D)
	return out


## The model node called `n`, in the front or the rear section.
func _find_node(m: Node3D, n: String) -> Node:
	var node := m.find_child(n, true, false)
	if node == null and _rear_model:
		node = _rear_model.find_child(n, true, false)
	return node


## A VehicleWheel3D on `body` for each wheel mesh (taken in the car frame, which is also the rear section's during
## setup); the first `steer` steer, those from `traction_from` on drive. Returns the mean wheel centre height.
func _add_wheels(body: VehicleBody3D, wheels: Array[MeshInstance3D], steer: int, traction_from: int) -> float:
	var wheel_y := 0.0
	for k in wheels.size():
		var w := wheels[k]
		var t := _in_car(w)
		var wheel_box: AABB = t * w.get_aabb()
		var centre := wheel_box.get_center()
		wheel_y += centre.y / wheels.size()
		var vw := VehicleWheel3D.new()
		vw.name = "Wheel%d" % k
		vw.position = centre + Vector3.UP * REST_LENGTH
		vw.wheel_radius = wheel_box.size.y * 0.5
		vw.wheel_rest_length = REST_LENGTH
		vw.suspension_travel = 0.25
		vw.suspension_stiffness = 50.0
		vw.suspension_max_force = 40.0 * body.mass
		vw.damping_compression = 4.0
		vw.damping_relaxation = 6.0
		vw.wheel_friction_slip = grip
		vw.wheel_roll_influence = 0.1
		vw.use_as_steering = k < steer
		vw.use_as_traction = k >= traction_from
		if not vw.use_as_steering:
			_rear_wheels.append(vw)
		body.add_child(vw)
		w.owner = null
		w.reparent(vw, false)
		# the wheel node sits at the wheel centre (it spins and steers about it)
		w.transform = Transform3D(Basis.IDENTITY, -centre) * t
		if _cab_file.get("unmirror_wheels", false):
			# VehicleBody3D poses its wheels with a mirrored basis (right, up, up × right: their Z flipped) from the first
			# physics tick on, so a print on a wheel (a centre cap's badge, tyre lettering) would read backwards: the
			# mesh is mirrored back
			w.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, -1.0)), Vector3.ZERO) * w.transform
	return wheel_y


## Rear section of an articulated vehicle: a VehicleBody3D that takes the model's rear objects, with its wheels,
## body box and centre of mass (at its origin, which is `offset` from the car's while straight). Returns its body
## box in its own frame.
func _build_trailer(m: Node3D, section: Dictionary, wheels: Array[MeshInstance3D], trailer_mass: float,
		offset: Vector3) -> AABB:
	trailer = Trailer.new()
	trailer.name = "RearSection"
	trailer.head = self
	trailer.top_level = true                # its own rigid body, not dragged by this node's transform
	trailer.mass = trailer_mass
	rear_offset = offset
	_configure_body(trailer)
	trailer.set_meta("plateau", get_meta("plateau"))
	add_child(trailer)
	_rear_model = Node3D.new()
	_rear_model.name = "Model"
	_rear_model.transform = Transform3D(Basis.IDENTITY, -offset) * m.transform
	trailer.add_child(_rear_model)
	# same place under the rear model as under the model; while the trailer node is at the identity during setup,
	# _in_car() then gives the rear section's frame
	for n: String in section["nodes"]:
		var node := m.find_child(n, true, false) as Node3D
		var t := node.transform
		node.owner = null
		node.reparent(_rear_model, false)
		node.transform = t
	var body := _rear_model.find_child(section["body"], true, false) as MeshInstance3D
	var box: AABB = _in_car(body) * body.get_aabb()
	var wheel_y := _add_wheels(trailer, wheels, 0, 0)
	_add_box(trailer, Vector3(box.get_center().x, (box.end.y + wheel_y) * 0.5, box.get_center().z),
			Vector3(box.size.x, box.end.y - wheel_y, box.size.z))
	trailer.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	trailer.center_of_mass = Vector3(0.0, wheel_y - com_drop, 0.0)
	_total_mass += trailer_mass
	_wheel_count += wheels.size()
	return box


func _add_box(to: Node3D, centre: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = centre
	to.add_child(cs)
	return cs


## Collision boxes, doors, interior and the driver's way out of the seat from the model's layout file (glTF frame, so
## shifted like the model); for an articulated vehicle also the rear section's, the hitch, the turntable floor and
## the bellows.
func _build_layout(m: Node3D, layout: Dictionary) -> void:
	var off := m.position
	var v := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2]) * m.scale + off
	var floor_y := float(layout["floor_y"]) + off.y
	inside = _build_inside(self, layout, v, m, floor_y, door_centres)
	interior = AABB(v.call(layout["interior"][0]), Vector3.ZERO).expand(v.call(layout["interior"][1]))
	if trailer:
		var section: Dictionary = layout["trailer"]
		var vr := func(a: Array) -> Vector3: return v.call(a) - rear_offset      # rear section frame
		trailer.inside = _build_inside(trailer, section, vr, _rear_model, floor_y, trailer.door_centres)
		trailer.interior = AABB(vr.call(section["interior"][0]), Vector3.ZERO).expand(vr.call(section["interior"][1]))
		_hitch = v.call(layout["hitch"])
		# floor disc over the hitch: it covers the ends of both floors at any articulation angle
		var tt: Dictionary = layout["turntable"]
		var disc := CylinderShape3D.new()
		disc.radius = float(tt["radius"]) * m.scale.x
		disc.height = float(tt["height"]) * m.scale.y
		var cs := CollisionShape3D.new()
		cs.shape = disc
		cs.position = v.call(tt["center"])
		inside.add_child(cs)
		_build_bellows(layout["bellows"], m.scale.x, off, floor_y)
	has_doors = not _doors.is_empty()
	driver_exit = v.call(layout["driver_exit"])


## The model's cab (driver seat and eye, steering wheel, passenger seat and eye; see _build_cab): a walkable vehicle's
## layout has them, a realistic car's cab file too.
func _cab_layout(layout: Dictionary) -> Dictionary:
	return layout if not layout.is_empty() else _cab_file.get("cab", {})


static var _glossed := {}                   # paint materials already given their clear coat

## Clear coat on the car paint of a realistic car's model (its "paint*" materials; glTF does not bring it into Godot).
func _gloss_paint(m: Node3D) -> void:
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		for k in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(k) as StandardMaterial3D
			if mat and mat.resource_name.begins_with("paint") and not _glossed.has(mat):
				_glossed[mat] = true
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.05


## Driver seat and eye, steering wheel and passenger seat from `cab` (glTF frame, so shifted like the model `m`): the cab
## camera and the look-alikes of the driver and the passenger.
func _build_cab(m: Node3D, cab: Dictionary) -> void:
	var v := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2]) * m.scale + m.position
	driver_seat = v.call(cab["driver_seat"])
	_driver_eye = v.call(cab["driver_eye"])
	has_passenger_seat = cab.has("passenger_seat")
	if has_passenger_seat:
		passenger_seat = v.call(cab["passenger_seat"])
		_passenger_eye = v.call(cab["passenger_eye"])
	_cab_pitch = float(cab.get("eye_pitch", 0.0))
	_figure = float(cab.get("figure", 1.0))
	_steering_wheel = m.find_child(cab.get("steering_wheel", ""), true, false) as Node3D
	if _steering_wheel:
		_steering_rest = _steering_wheel.transform
		var t := _in_car(_steering_wheel)
		_wheel_centre = t.origin
		_wheel_axis = t.basis.y.normalized()
		_wheel_right = Vector3.LEFT.slide(_wheel_axis).normalized()     # the driver's right (the car's left is +X)
		_wheel_up = _wheel_axis.cross(_wheel_right)
		if _steering_wheel is MeshInstance3D:
			# rim in the local XZ plane: half the box minus the tube radius
			_grip_radius = (_steering_wheel as MeshInstance3D).get_aabb().size.x * 0.5 * t.basis.x.length() - 0.024
	_cab_camera = Camera3D.new()
	_cab_camera.fov = 75.0
	_cab_camera.near = 0.05
	_cab_camera.far = 1500.0
	_cab_camera.position = _driver_eye
	_cab_camera.rotation = Vector3(-0.27 + _cab_pitch, PI, 0.0)
	add_child(_cab_camera)
	_build_driver()


## Walkable hull of one section (`body`: this car or its rear section) from its layout entry: a StaticBody3D on the
## VEHICLE_INSIDE layer (only the player scans it) with the collision boxes; adds the section's doors to _doors and
## their doorway centres (on the floor, `body` frame) to `centres`.
func _build_inside(body: VehicleBody3D, section: Dictionary, v: Callable, model: Node3D, floor_y: float,
		centres: Array[Vector3]) -> StaticBody3D:
	var hull := StaticBody3D.new()
	hull.name = "Inside"
	hull.collision_layer = Layers.VEHICLE_INSIDE
	hull.collision_mask = 0
	hull.set_meta("plateau", get_meta("plateau"))
	body.add_child(hull)
	var door_shapes := {}
	for c: Dictionary in section["colliders"]:
		var cs := _add_box(hull, v.call(c["center"]), Vector3(c["size"][0], c["size"][1], c["size"][2]) * model.scale)
		if c.has("door"):
			door_shapes[int(c["door"])] = cs
	for i in section["doors"].size():
		var d: Dictionary = section["doors"][i]
		var centre: Vector3 = v.call(d["center"])
		centres.append(Vector3(centre.x, floor_y, centre.z))
		var door := {"leaves": [], "closed": [], "dirs": [], "slide": float(d["width"]) * 0.5 * 0.92,
				"shape": door_shapes.get(i)}
		for leaf_name: String in d["leaves"]:
			var leaf := model.find_child(leaf_name, true, false) as Node3D
			door["leaves"].append(leaf)
			door["closed"].append(leaf.position)
			door["dirs"].append(signf(_in_car(leaf).origin.z - centre.z))
		_doors.append(door)
	return hull


## Bellows between the sections (its mesh is rebuilt by _update_bellows when the joint bends) and the walls the
## player meets inside it, from the layout profile `b` (glTF frame: scaled by `s`, shifted by `off`).
func _build_bellows(b: Dictionary, s: float, off: Vector3, floor_y: float) -> void:
	_bellows = {"front": float(b["front"]) * s + off.z, "rear": float(b["rear"]) * s + off.z,
			"wall_x": float(b["wall_x"]) * s, "floor": floor_y, "ceiling": float(b["ceiling"]) * s + off.y}
	for inset: float in [0.0, float(b["depth"])]:    # ridges, valleys
		_bellows_profiles.append(_rounded_rect((float(b["half_width"]) - inset) * s, (float(b["bottom"]) + inset) * s + off.y,
				(float(b["top"]) - inset) * s + off.y, (float(b["radius"]) - inset) * s))
	var rings := 2 * int(b["folds"]) + 1
	var per: int = _bellows_profiles[0][0].size()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for k in rings:
		var c := Color(0.16, 0.17, 0.18) if k % 2 == 0 else Color(0.05, 0.05, 0.055)
		for j in per:
			colors.append(c)
	for k in rings - 1:
		for j in per:
			var a := k * per + j
			var n := k * per + (j + 1) % per
			indices.append_array([a, n, n + per, a, n + per, a + per])
	_bellows_arrays.resize(Mesh.ARRAY_MAX)
	_bellows_arrays[Mesh.ARRAY_COLOR] = colors
	_bellows_arrays[Mesh.ARRAY_INDEX] = indices
	_bellows_mesh = ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "Bellows"
	mi.mesh = _bellows_mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED     # also seen from inside
	mi.material_override = mat
	add_child(mi)
	_bellows_rel = Transform3D(Basis.IDENTITY, Vector3.INF)     # not built yet

	var hull := StaticBody3D.new()
	_bellows_hull = hull
	hull.name = "InsideBellows"
	hull.collision_layer = Layers.VEHICLE_INSIDE
	hull.collision_mask = 0
	hull.set_meta("plateau", get_meta("plateau"))
	add_child(hull)
	# segments overlap each other and the sections' own walls, so no gap opens on the outside of a bend
	var seg := absf(_bellows["front"] - _bellows["rear"]) / BELLOWS_SEGMENTS + 0.4
	var h: float = _bellows["ceiling"] - floor_y
	for k in BELLOWS_SEGMENTS:
		for size: Vector3 in [Vector3(0.2, h, seg), Vector3(0.2, h, seg), Vector3(2.0 * _bellows["wall_x"] + 0.4, 0.3, seg)]:
			_joint_walls.append(_add_box(hull, Vector3.ZERO, size))


## Rounded rectangle across the bus (x, y): [points, outward normals], counter-clockwise from the bottom right.
func _rounded_rect(hw: float, bottom: float, top: float, r: float, n := 6) -> Array:
	var pts := PackedVector2Array()
	var normals := PackedVector2Array()
	var centres := [Vector2(hw - r, bottom + r), Vector2(hw - r, top - r), Vector2(r - hw, top - r), Vector2(r - hw, bottom + r)]
	for c in 4:
		for i in n + 1:
			var a := PI * 0.5 * (c - 1 + float(i) / n)
			var d := Vector2(cos(a), sin(a))
			pts.append(centres[c] + d * r)
			normals.append(d)
	return [pts, normals]


## Frame across the bellows at `t` (0 front flange .. 1 rear flange) in the car frame, with the rear section's frame
## at `rel`: turned by the share t of the articulation about the hitch; origin at the car frame's floor of the bus
## (ground level), so profile points (x, height, 0) map straight into it.
func _bellows_frame(rel: Transform3D, t: float) -> Transform3D:
	var b := Basis.IDENTITY.slerp(rel.basis.orthonormalized(), t)
	var pivot := _hitch.lerp(rel * (_hitch - rear_offset), t)
	return Transform3D(b, pivot + b * Vector3(0.0, -_hitch.y, lerpf(_bellows["front"], _bellows["rear"], t) - _hitch.z))


## Bends the bellows mesh and its walls to the current articulation (nothing to do while it holds still).
func _update_bellows() -> void:
	if _bellows.is_empty():
		return                                  # a semi-trailer has none
	var rel := global_transform.affine_inverse() * trailer.global_transform
	# below the physics jitter (1 cm, 0.3°) or out of sight: kept as it is (each rebuild is a new GPU buffer)
	if _bellows_rel.origin.is_finite() and (rel.origin.distance_to(_bellows_rel.origin) < 0.008 \
			and (rel.basis.z - _bellows_rel.basis.z).length() < 0.005 or not _near_camera(BELLOWS_SEEN)):
		return
	_bellows_rel = rel
	var per: int = _bellows_profiles[0][0].size()
	var rings: int = _bellows_arrays[Mesh.ARRAY_COLOR].size() / per
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(rings * per)
	normals.resize(rings * per)
	for k in rings:
		var f := _bellows_frame(rel, float(k) / (rings - 1))
		var pts: PackedVector2Array = _bellows_profiles[k % 2][0]
		var ns: PackedVector2Array = _bellows_profiles[k % 2][1]
		for j in per:
			verts[k * per + j] = f * Vector3(pts[j].x, pts[j].y, 0.0)
			normals[k * per + j] = f.basis * Vector3(ns[j].x, ns[j].y, 0.0)
	_bellows_arrays[Mesh.ARRAY_VERTEX] = verts
	_bellows_arrays[Mesh.ARRAY_NORMAL] = normals
	_bellows_mesh.clear_surfaces()
	_bellows_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _bellows_arrays)
	var x: float = _bellows["wall_x"] + 0.1
	var yc: float = (_bellows["floor"] + _bellows["ceiling"]) * 0.5
	for k in BELLOWS_SEGMENTS:
		var f := _bellows_frame(rel, (k + 0.5) / BELLOWS_SEGMENTS)
		_joint_walls[3 * k].transform = f * Transform3D(Basis.IDENTITY, Vector3(x, yc, 0.0))
		_joint_walls[3 * k + 1].transform = f * Transform3D(Basis.IDENTITY, Vector3(-x, yc, 0.0))
		_joint_walls[3 * k + 2].transform = f * Transform3D(Basis.IDENTITY, Vector3(0.0, _bellows["ceiling"] + 0.15, 0.0))


## The player's look-alike in the driver seat while someone drives: a body, and arms reaching to hands on the
## steering wheel rim (placed by _update_steering).
func _build_driver() -> void:
	_driver_dummy = Node3D.new()
	_driver_dummy.visible = false
	add_child(_driver_dummy)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(1, 0.55, 0.2)
	skin.roughness = 0.6
	_skin = skin
	var f := _figure
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3 * f
	capsule.height = 1.25 * f
	capsule.material = skin
	_driver_body = MeshInstance3D.new()
	_driver_body.mesh = capsule
	_driver_body.position = driver_seat + Vector3(0.0, 0.62 * f, 0.0)
	_driver_dummy.add_child(_driver_body)
	if has_passenger_seat:
		_passenger_skin = skin.duplicate()
		var seated := capsule.duplicate() as CapsuleMesh
		seated.material = _passenger_skin
		_passenger = MeshInstance3D.new()
		_passenger.name = "Passenger"
		_passenger.mesh = seated
		_passenger.position = passenger_seat + Vector3(0.0, 0.62 * f, 0.0)
		_passenger.visible = false
		add_child(_passenger)
	if _steering_wheel == null:
		return
	var arm := CylinderMesh.new()               # along +Y from the shoulder (bottom) to the hand (top)
	arm.top_radius = 0.042 * f
	arm.bottom_radius = 0.055 * f
	arm.height = 1.0
	arm.radial_segments = 12
	arm.rings = 1
	arm.material = skin
	var hand := SphereMesh.new()
	hand.radius = 0.05 * f
	hand.height = 0.09 * f
	hand.radial_segments = 12
	hand.rings = 6
	hand.material = skin
	for side: float in [1.0, -1.0]:             # left (+X), right
		_shoulders.append(driver_seat + Vector3(side * 0.21 * f, 0.72 * f, -0.04))
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = arm if k == 0 else hand
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_driver_dummy.add_child(mi)
			(_arms if k == 0 else _hands).append(mi)


## Indicator and brake lamps: the model's named meshes when its layout lists them (and its reversing lamps, if it
## lists any), else small boxes at the corners of the body box, at the height of a toy car's own head and tail lamps
## (_own_lamps), which then light up instead of brake lamp boxes.
func _build_lamps(m: Node3D, box: AABB, layout: Dictionary) -> void:
	for k: String in ["indicator", "brake"]:
		var off := StandardMaterial3D.new()
		var on := StandardMaterial3D.new()
		var c := Color(1.0, 0.54, 0.0) if k == "indicator" else Color(0.9, 0.05, 0.05)
		off.albedo_color = c.darkened(0.45)
		on.albedo_color = c
		on.emission_enabled = true
		on.emission = c
		on.emission_energy_multiplier = 6.0
		_lamp_mats[k] = [off, on]
	if not layout.is_empty():
		for side in [1, -1]:
			for n: String in layout["indicators"]["left" if side == 1 else "right"]:
				_lamps[side].append(_find_node(m, n))
		for n: String in layout["brake_lights"]:
			_brake_lamps.append(_find_node(m, n))
		for n: String in layout.get("reverse_lights", []):
			_reverse_lamps.append(_find_node(m, n))
		if not _reverse_lamps.is_empty():
			var rev := StandardMaterial3D.new()
			rev.albedo_color = Color(0.95, 0.95, 0.92)
			rev.emission_enabled = true
			rev.emission = Color(1.0, 0.97, 0.9)
			rev.emission_energy_multiplier = 4.0
			_lamp_mats["reverse"] = rev
	else:
		var own := _own_lamps(m, box)
		var heights := {}                   # face z -> lamp height
		for e: Array in [["head", box.end.z], ["tail", box.position.z]]:
			var mi: MeshInstance3D = own.get(e[0])
			heights[e[1]] = (_in_car(mi) * (mi.mesh as ArrayMesh).custom_aabb).get_center().y if mi else box.position.y + box.size.y * 0.45
		for side in [1, -1]:
			for z: float in heights:
				_lamps[side].append(_lamp_box(_on_body(m, Vector3(side * (box.size.x * 0.5 - 0.12), heights[z], z)),
						Vector3(0.14, 0.07, 0.04)))
			if not own.has("tail"):
				_brake_lamps.append(_lamp_box(_on_body(m, Vector3(side * (box.size.x * 0.5 - 0.3),
						heights[box.position.z], box.position.z)), Vector3(0.2, 0.08, 0.04)))
		if own.has("tail"):
			_brake_lamps.append(own["tail"])
			_lamp_mats["brake"][0] = null   # off: its own material
		_own_head = own.get("head")
	for side in [1, -1]:
		for lamp: MeshInstance3D in _lamps[side]:
			lamp.material_override = _lamp_mats["indicator"][0]
	for lamp in _brake_lamps:
		lamp.material_override = _lamp_mats["brake"][0]
	_build_headlights(m, box, layout)
	_body_faces = PackedVector3Array()


## Headlights: on a model with a layout or fittings file (the buses, the fire truck), its "headlight" surfaces (only
## their front half lights up: the fire truck's reversing lamps share them) and "taillight" ones glow, and each
## walkable section gets a light over its aisle; else a toy car's own headlights (_own_lamps) glow, or lamp boxes go
## inboard of the front indicators. The beam starts between the headlights.
func _build_headlights(m: Node3D, box: AABB, layout: Dictionary) -> void:
	if _own_head:
		_headlight_mats()
		_lamp_mats["head"][0] = null        # off: its own material
		_head_lamps.append(_own_head)
		var lens := _in_car(_own_head) * (_own_head.mesh as ArrayMesh).custom_aabb
		_add_beam(Vector3(lens.get_center().x, lens.get_center().y, maxf(lens.end.z, box.end.z)))
		return
	if layout.is_empty():
		var y := box.position.y + box.size.y * 0.45
		var lamps: Array[Vector3] = []
		for side in [1, -1]:
			lamps.append(_on_body(m, Vector3(side * (box.size.x * 0.5 - 0.42), y, box.end.z)))
		add_headlights(lamps, Vector3(0.3, 0.1, 0.04))
		return
	if _lamp_shader == null:
		_lamp_shader = Shader.new()
		_lamp_shader.code = """shader_type spatial;
uniform vec4 albedo : source_color;
uniform vec4 glow : source_color;
uniform float energy = 4.0;
uniform bool front_only = false;
varying float z;
void vertex() { z = VERTEX.z; }
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.25;
	EMISSION = z > 0.0 || !front_only ? glow.rgb * energy : vec3(0.0);
}
"""
	var lens := AABB()
	var lenses := 0
	var models: Array[Node] = [m]
	if _rear_model:
		models.append(_rear_model)
	for root in models:
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for k in mi.mesh.get_surface_count():
				var original := mi.mesh.surface_get_material(k) as BaseMaterial3D
				var kind := original.resource_name if original else ""
				if kind not in ["headlight", "taillight"]:
					continue
				var lit := ShaderMaterial.new()
				lit.shader = _lamp_shader
				lit.set_shader_parameter("albedo", original.albedo_color)
				lit.set_shader_parameter("glow", HEADLIGHT if kind == "headlight" else Color(0.9, 0.05, 0.05))
				lit.set_shader_parameter("energy", 5.0 if kind == "headlight" else 1.5)
				lit.set_shader_parameter("front_only", kind == "headlight")
				_lit_surfaces.append([mi, k, lit])
				if kind == "headlight" and root == m:
					var xf := _in_car(mi)
					for v: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
						if v.z > 0.0:
							lens = AABB(xf * v, Vector3.ZERO) if lenses == 0 else lens.expand(xf * v)
							lenses += 1
	if lenses > 0:
		# ahead of the whole body, not just of the lenses: the beam's shadow (the driver's) would be cast by a badge or
		# grille sticking out between them (the Zoe, the R8) and hide all of it
		_add_beam(Vector3(lens.get_center().x, lens.get_center().y, maxf(lens.end.z, box.end.z)))
	if interior.size != Vector3.ZERO:
		_add_cabin_light(self, interior)
	if trailer and trailer.interior.size != Vector3.ZERO:
		_add_cabin_light(trailer, trailer.interior)


## Glowing headlight boxes of `size` at `lamps` (car frame, on the front face), and the beam between them.
func add_headlights(lamps: Array[Vector3], size: Vector3) -> void:
	_headlight_mats()
	var centre := Vector3.ZERO
	for p in lamps:
		var lamp := _lamp_box(p, size)
		lamp.material_override = _lamp_mats["head"][0]
		_head_lamps.append(lamp)
		centre += p / lamps.size()
	_add_beam(centre)


## The head lamps' materials (off, lit) and the tail lamps' (lit with the headlights).
func _headlight_mats() -> void:
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.85, 0.87, 0.82)
	off.roughness = 0.25
	var on := off.duplicate() as StandardMaterial3D
	on.emission_enabled = true
	on.emission = HEADLIGHT
	on.emission_energy_multiplier = 5.0
	_lamp_mats["head"] = [off, on]
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.9, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = tail.albedo_color
	tail.emission_energy_multiplier = 1.5
	_lamp_mats["tail"] = tail


## The headlight beam from `p` (car frame, the front of the lamps), along +Z and a little down.
func _add_beam(p: Vector3) -> void:
	_beam = SpotLight3D.new()
	_beam.name = "Headlights"
	_beam.light_color = HEADLIGHT
	_beam.light_energy = BEAM_ENERGY
	_beam.light_specular = 0.3
	_beam.spot_range = BEAM_RANGE
	_beam.spot_angle = BEAM_ANGLE
	_beam.spot_angle_attenuation = 0.6
	_beam.spot_attenuation = 0.7                        # reaches further than the inverse square
	_beam.distance_fade_enabled = true
	_beam.distance_fade_begin = BEAM_FADE
	_beam.distance_fade_length = 20.0
	_beam.position = p + Vector3(0.0, 0.0, 0.15)
	_beam.rotation = Vector3(-BEAM_TILT, PI, 0.0)        # a spot light shines along its -Z
	_beam.visible = false
	add_child(_beam)


## A light under the ceiling of the walkable `interior` (frame of `body`), on with the headlights.
func _add_cabin_light(body: Node3D, box: AABB) -> void:
	var light := OmniLight3D.new()
	light.name = "CabinLight"
	light.light_color = CABIN_LIGHT
	light.light_energy = 1.2
	light.light_specular = 0.2
	light.omni_range = maxf(box.size.z * 0.6, 4.0)
	light.omni_attenuation = 0.8
	light.distance_fade_enabled = true
	light.distance_fade_begin = BEAM_FADE * 0.5
	light.distance_fade_length = 20.0
	light.position = Vector3(box.get_center().x, box.end.y - 0.15, box.get_center().z)
	light.visible = false
	body.add_child(light)
	_cabin_lights.append(light)


## Headlights on or off: the beam, the lamps, the tail lamps (dimly red) and the cabin lights. Vehicles without any
## (the horse) stay off.
func set_headlights(on: bool) -> void:
	if _beam == null or on == headlights:
		return
	headlights = on
	_beam.visible = on
	for light in _cabin_lights:
		light.visible = on
	for lamp in _head_lamps:
		lamp.material_override = _lamp_mats["head"][1 if on else 0]
	for e: Array in _lit_surfaces:
		(e[0] as MeshInstance3D).set_surface_override_material(e[1], e[2] if on else null)
	for far in _far:
		far.set_instance_shader_parameter("lit", on)
	_set_brake_lamps(_braking or _remote_braking)


## The brake lamps: bright red while braking, dimly with the headlights on.
func _set_brake_lamps(braking: bool) -> void:
	if _brake_lamps.is_empty():
		return
	var mat: Material = _lamp_mats["brake"][1] if braking \
			else _lamp_mats.get("tail", _lamp_mats["brake"][0]) if headlights else _lamp_mats["brake"][0]
	if mat == _brake_mat:
		return
	_brake_mat = mat
	for lamp in _brake_lamps:
		lamp.material_override = mat


## The reversing lamps (white, the model's own material when off), on while backing up.
func _set_reverse_lamps(on: bool) -> void:
	if on == _reversing or _reverse_lamps.is_empty():
		return
	_reversing = on
	for lamp in _reverse_lamps:
		lamp.material_override = _lamp_mats["reverse"] if on else null


## `p` (car frame, on the front or back face of the body box) moved along Z onto the body of model `m` (its meshes but
## the wheels): the bumpers stick out past the panels the lamps go on, so the box's face is in the air there. Where the
## rounded corners miss the ray, or it only meets the body deep inside (a wheel arch's flare), it moves inboard; where
## it passes over a van's bonnet to the windscreen, down to the bonnet's front.
## Cached per model (_lamp_spots): the bots spawn many of each.
func _on_body(m: Node3D, p: Vector3) -> Vector3:
	var key := "%s %v" % [model_name, p]
	if not _lamp_spots.has(key):
		_lamp_spots[key] = _ray_to_body(m, p)
	return _lamp_spots[key]


func _ray_to_body(m: Node3D, p: Vector3) -> Vector3:
	if _body_faces.is_empty():
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			if "wheel" not in String(mi.name).to_lower():
				var xf := _in_car(mi)
				for v in mi.mesh.get_faces():
					_body_faces.append(xf * v)
	var dir := Vector3(0.0, 0.0, -signf(p.z))
	for down in 8:
		for step in 12:
			var from := Vector3(p.x - signf(p.x) * 0.05 * step, p.y - 0.1 * down, p.z - dir.z * 1.0)
			var best := INF
			for i in range(0, _body_faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, _body_faces[i], _body_faces[i + 1],
						_body_faces[i + 2])
				if hit != null:
					best = minf(best, from.distance_to(hit))
			if best < 1.0 + LAMP_DEPTH:
				return from + dir * best
	return p


## A Kenney Car Kit body's own head and tail lamps: its body is one mesh on the "colormap" palette, so they are its
## triangles on the lamp swatches (KENNEY_HEAD, KENNEY_TAIL) in the front and back fifths of the car (not the police
## car's light bar), split out into meshes of their own under it (cached per model, _own_lamp_meshes).
## {"head": MeshInstance3D, "tail": ...}, either missing when the model has none (the ambulance's tail lamps).
func _own_lamps(m: Node3D, box: AABB) -> Dictionary:
	var body := m.find_child(SPECS[model_name].get("body", "body"), true, false) as MeshInstance3D
	if body == null or body.mesh == null or body.mesh.get_surface_count() != 1:
		return {}
	var mat := body.mesh.surface_get_material(0)
	if mat == null or mat.resource_name != "colormap":
		return {}
	if not _own_lamp_meshes.has(model_name):
		_own_lamp_meshes[model_name] = _split_lamps(body, box)
	var meshes: Array = _own_lamp_meshes[model_name]
	var out := {}
	if meshes.is_empty():
		return out
	body.mesh = meshes[0]
	for i in [1, 2]:
		if meshes[i] != null:
			var lamp := MeshInstance3D.new()
			lamp.name = "HeadLamps" if i == 1 else "TailLamps"
			lamp.mesh = meshes[i]
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(lamp)
			out["head" if i == 1 else "tail"] = lamp
	return out


## [`body`'s mesh without its lamps, its head lamps, its tail lamps] (see _own_lamps; null for none), [] if it has none.
func _split_lamps(body: MeshInstance3D, box: AABB) -> Array:
	var arrays := body.mesh.surface_get_arrays(0)
	var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var ind: Variant = arrays[Mesh.ARRAY_INDEX]
	if not uv is PackedVector2Array or not ind is PackedInt32Array or (ind as PackedInt32Array).is_empty():
		return []
	var v: PackedVector3Array = _in_car(body) * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var reach := box.size.z * 0.2
	var parts := [[], [], []]               # triangle indices: the rest, the head lamps, the tail lamps
	for t in range(0, ind.size() - 2, 3):
		var a: int = ind[t]
		var b: int = ind[t + 1]
		var c: int = ind[t + 2]
		var cell := Vector2i(((uv[a] + uv[b] + uv[c]) / 3.0 * Vector2(16.0, 4.0)).floor())
		var z := (v[a].z + v[b].z + v[c].z) / 3.0
		var part := 1 if cell == KENNEY_HEAD and z > box.end.z - reach \
				else 2 if cell == KENNEY_TAIL and z < box.position.z + reach else 0
		parts[part].append_array([a, b, c])
	if parts[1].is_empty() and parts[2].is_empty():
		return []
	var out := []
	for p: Array in parts:
		if p.is_empty():
			out.append(null)
			continue
		var a := arrays.duplicate()
		a[Mesh.ARRAY_INDEX] = PackedInt32Array(p)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		if out.size() > 0:                  # a lamp: the bounds of its own triangles (get_aabb: of all the vertices)
			var own := AABB(arrays[Mesh.ARRAY_VERTEX][p[0]], Vector3.ZERO)
			for i: int in p:
				own = own.expand(arrays[Mesh.ARRAY_VERTEX][i])
			mesh.custom_aabb = own
		mesh.surface_set_material(0, body.mesh.surface_get_material(0))   # the same: paint.gd repaints it
		out.append(mesh)
	return out


func _lamp_box(p: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = p + Vector3(0.0, 0.0, signf(p.z) * 0.01)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # flush with the body
	add_child(mi)
	return mi


## Transform of `n` in the car's frame (the car is not in the tree yet, so no global transforms).
func _in_car(n: Node3D) -> Transform3D:
	return _in_frame(n, self)


## Transform of `n` in the frame of its ancestor `root`.
static func _in_frame(n: Node3D, root: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p and p != root:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t


## Each section's far mesh: shown from FAR_DETAIL m from the camera, where the section's own meshes (its `details`:
## their visibility parent) hide. One surface and one material (a draw, and one per shadow split) instead of up to
## ~100 for a bus: every visible mesh of the section merged as it is posed now (doors shut, wheels at rest), coloured
## per vertex from its surfaces' materials and textures; the head and tail lamps glow with the headlights (the
## instance uniform `lit`). Made once per model. Not on a headless peer, which draws nothing. Meshes added after setup
## (a subclass's beacons) stay as they are.
func _build_far() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for body in bodies():
		var details := _far_details(body)
		var key := model_name + ("/rear" if body != self else "") + ("#" + paint if paint != "" else "")
		if not _far_meshes.has(key):
			_far_meshes[key] = _merge_far(body, details)
		if _far_meshes[key] == null:
			continue
		var far := MeshInstance3D.new()
		far.name = "Far"
		far.mesh = _far_meshes[key]
		far.material_override = _far_shader()
		far.visibility_range_begin = FAR_DETAIL
		far.visibility_range_begin_margin = 5.0
		body.add_child(far)
		_far.append(far)
		for g in details:
			g.visibility_parent = g.get_path_to(far)
	_far_images.clear()                     # (decompressed textures: only needed while merging)


## The meshes of section `body` that the far mesh stands in for: all but the bellows (it bends) and those of the other
## section or under a top-level node.
func _far_details(body: VehicleBody3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for g: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
		if not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == _bellows_mesh:
			continue
		var n: Node = g
		while n != body and not (n as Node3D).top_level:
			n = n.get_parent()
		if n == body:
			out.append(g)
	return out


## The far mesh of section `body` from its `details` (see _build_far): the visible ones but the driver and passenger
## look-alikes, the steering wheel and the indicators; null when no mesh could be read. The vertex colour's alpha tells
## the surface: 1 paint, 0 a headlight, 0.5 a tail or brake lamp.
func _merge_far(body: VehicleBody3D, details: Array[GeometryInstance3D]) -> ArrayMesh:
	var skip := {}
	for n in [_driver_dummy, _passenger, _steering_wheel]:
		if n:
			skip[n] = true
	for lamp in _lamps[1] + _lamps[-1]:
		skip[lamp] = true
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for g in details:
		var mi := g as MeshInstance3D
		if mi.mesh == null or not _shown_in(mi, body, skip):
			continue
		var xf := _in_frame(mi, body)
		var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		for k in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(k) != Mesh.PRIMITIVE_TRIANGLES:
				continue                    # (a PrimitiveMesh: triangles)
			var arrays := mi.mesh.surface_get_arrays(k)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var base := verts.size()
			verts.append_array(xf * v)
			var n: Variant = arrays[Mesh.ARRAY_NORMAL]
			if n is PackedVector3Array and (n as PackedVector3Array).size() == v.size():
				normals.append_array(nxf * (n as PackedVector3Array))
			else:
				var up := PackedVector3Array()
				up.resize(v.size())
				up.fill(Vector3.UP)
				normals.append_array(up)
			var mat := mi.get_active_material(k)
			var kind := 1.0
			if mi in _head_lamps or (mat and mat.resource_name == "headlight"):
				kind = 0.0
			elif mi in _brake_lamps or (mat and mat.resource_name == "taillight"):
				kind = 0.5
			colours.append_array(_far_colours(mat, arrays[Mesh.ARRAY_TEX_UV], v.size(), kind))
			var ind: Variant = arrays[Mesh.ARRAY_INDEX]
			if ind is PackedInt32Array and not (ind as PackedInt32Array).is_empty():
				for i: int in ind:
					indices.append(base + i)
			else:
				for i in v.size():
					indices.append(base + i)
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## True when `mi` shows in section `body` (it and its parents visible, none of them in `skip`).
static func _shown_in(mi: Node3D, body: Node3D, skip: Dictionary) -> bool:
	var n: Node = mi
	while n != body:
		if skip.has(n) or not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## Linear vertex colours for a surface of `count` vertices with material `mat` and texture coordinates `uv`: its albedo
## colour times its texture there (the toy models' colours are in their palette textures), glass darkened; alpha `kind`.
static func _far_colours(mat: Material, uv: Variant, count: int, kind: float) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(count)
	var c := Color(0.6, 0.6, 0.6)
	var img: Image = null
	var bm := mat as BaseMaterial3D
	if bm:
		c = bm.albedo_color
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			c = c.darkened(0.5)
		if bm.albedo_texture and uv is PackedVector2Array and (uv as PackedVector2Array).size() == count:
			img = _far_image(bm.albedo_texture)
	elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("albedo") is Color:
		c = (mat as ShaderMaterial).get_shader_parameter("albedo")
	c.a = 1.0
	if img == null:
		var lin := c.srgb_to_linear()
		lin.a = kind
		out.fill(lin)
		return out
	var size := Vector2(img.get_size())
	var uvs: PackedVector2Array = uv
	for i in count:
		var t := uvs[i]
		var px := Vector2i(int(fposmod(t.x, 1.0) * size.x), int(fposmod(t.y, 1.0) * size.y)).clamp(Vector2i.ZERO,
				Vector2i(size) - Vector2i.ONE)
		var lin := (img.get_pixelv(px) * c).srgb_to_linear()
		lin.a = kind
		out[i] = lin
	return out


## The image of texture `tex`, decompressed, for sampling colours (null when it can not be read).
static func _far_image(tex: Texture2D) -> Image:
	if not _far_images.has(tex):
		var img := tex.get_image()
		if img and img.is_compressed() and img.decompress() != OK:
			img = null
		if img and img.has_mipmaps():
			img.clear_mipmaps()
		_far_images[tex] = img
	return _far_images[tex]


## The far meshes' material: vertex colours, the lamps glowing when the instance's `lit` is on.
static func _far_shader() -> ShaderMaterial:
	if _far_material == null:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 head : source_color;
uniform vec4 tail : source_color;
instance uniform bool lit = false;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.55;
	if (lit && COLOR.a < 0.75) {
		EMISSION = COLOR.a < 0.25 ? head.rgb * 5.0 : tail.rgb * 1.5;
	}
}
"""
		_far_material = ShaderMaterial.new()
		_far_material.shader = shader
		_far_material.set_shader_parameter("head", HEADLIGHT)
		_far_material.set_shader_parameter("tail", Color(0.9, 0.05, 0.05))
	return _far_material


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
	_arm.set_physics_process_internal(false)    # a shape cast per tick: only while its camera is in use (_process)
	if trailer:
		_arm.add_excluded_object(trailer.get_rid())
		_build_joint()


## Hinges the rear section at the hitch: no linear play, yaw up to JOINT_YAW, a little pitch, no roll (joint frame:
## X across, Y up, Z along the bus). The two sections do not collide with each other.
func _build_joint() -> void:
	trailer.global_transform = global_transform.translated_local(rear_offset)
	_joint = Generic6DOFJoint3D.new()
	_joint.name = "Joint"
	_joint.position = _hitch
	_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -JOINT_PITCH)
	_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, JOINT_PITCH)
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -JOINT_YAW)
	_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, JOINT_YAW)
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_joint.exclude_nodes_from_collision = true
	add_child(_joint)
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(trailer)
	_update_bellows()


## Puts the vehicle at `t` (car frame: origin on the ground, +Z forward), at rest, its rear section straight behind.
func place(t: Transform3D) -> void:
	for b in bodies():
		b.global_transform = t if b == self else t.translated_local(rear_offset)
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	_crash_frame = -2


## The rigid bodies: this one and the rear section of an articulated vehicle.
func bodies() -> Array[VehicleBody3D]:
	var out: Array[VehicleBody3D] = [self]
	if trailer:
		out.append(trailer)
	return out


## Where the rear section is hinged, in the car frame (articulated vehicles).
func hitch() -> Vector3:
	return _hitch


## Articulation angle in radians (the rear section's yaw relative to this one; 0 straight or not articulated).
func articulation() -> float:
	if trailer == null:
		return 0.0
	var f := global_basis.inverse() * trailer.global_basis.z
	return atan2(f.x, f.z)


func set_driving(on: bool) -> void:
	driving = on
	for b in bodies():
		b.sleeping = false
	if _beam:
		_beam.shadow_enabled = on               # only the player's own beam: shadows cost
	if _driver_dummy:
		_driver_dummy.visible = on
	if on:
		audio.engine_on = not broken
		_reset_camera()
		_update_steering()
	else:
		audio.engine_on = has_doors and not broken      # a bus keeps idling for its passengers
		audio.horn = false
		set_indicator(0)


## The player sits in the passenger seat (on, their look-alike in `color` while the chase camera shows the car) or gets
## up: the car's cameras show them the ride, the cab view from the passenger's eye.
func set_riding(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	riding = on
	_cab_camera.position = _passenger_eye if on else _driver_eye
	if on:
		_passenger_skin.albedo_color = color
		_reset_camera()
	_update_passenger()


## LAN games: another player sits in the passenger seat (on: their look-alike in `color`) or nobody does.
func show_passenger(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	if not has_passenger_seat:
		return
	_passenger_taken = on
	if on:
		_passenger_skin.albedo_color = color
	_update_passenger()


## True while another player sits in the passenger seat.
func passenger_taken() -> bool:
	return _passenger_taken


func _update_passenger() -> void:
	if _passenger:
		_passenger.visible = _passenger_taken or (riding and not cab_view)


## Chase camera behind the car, the mouse look reset, and this car's camera (chase or cab) current.
func _reset_camera() -> void:
	_follow_yaw = _heading()
	_look_yaw = 0.0
	_look_idle = 0.0
	_mode_held = -1.0
	_was_free = _free_view()
	_update_camera(1.0)
	set_cab_view(cab_view)


## LAN games: someone on another peer drives (on) or nobody does: shows the driver look-alike in `color`.
func show_driver(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	set_driver_color(BOT_COLOR if is_bot() else color)
	if _driver_dummy:
		_driver_dummy.visible = on or driving or is_bot()


## True when a bot drives it (here or, for a remote vehicle, on the peer simulating it).
func is_bot() -> bool:
	return pilot != null or bot_driven


## A bot takes the wheel (`p`: scripts/bus_bot.gd) or leaves it (null).
func set_pilot(p: Object) -> void:
	pilot = p
	for b in bodies():
		b.sleeping = false
	show_driver(false)
	if p:
		set_headlights(night)
	audio.engine_on = (p != null or driving or has_doors) and not broken


## Hidden and out of the physics (on), or back (off). Frozen while stowed; a remote copy stays frozen afterwards.
func set_stowed(on: bool) -> void:
	if on == stowed:
		return
	stowed = on
	visible = not on
	for b in bodies():
		if on:
			_stowed_layers = Vector2i(b.collision_layer, b.collision_mask)
			b.collision_layer = 0
			b.collision_mask = 0
		else:
			b.collision_layer = _stowed_layers.x
			b.collision_mask = _stowed_layers.y
		b.visible = not on
	_apply_remote_freeze()
	# the walkable hulls too (a stowed bot stays where it vanished, where the next bus pulls up)
	for hull: StaticBody3D in [inside, trailer.inside if trailer else null, _bellows_hull]:
		if hull:
			hull.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	audio.engine_on = not on and (is_bot() or driving or has_doors) and not broken
	if on:
		audio.hush()                            # it gets no audio.update() while stowed


func set_driver_color(color: Color) -> void:
	if _skin:
		_skin.albedo_color = color


## LAN games: simulated by another peer (true: the bodies turn kinematic and follow apply_net_state) or here (false:
## dynamic again, keeping the speed they were last moved at).
func set_remote(on: bool) -> void:
	if on == remote:
		return
	remote = on
	_remote_asleep = false
	_net_bell = bells & 1 if on else -1
	for b in bodies():
		var lv := b.linear_velocity
		var av := b.angular_velocity
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = on
		b.sleeping = false
		if not on:
			b.linear_velocity = lv
			b.angular_velocity = av


## LAN games, remote vehicle: puts it to sleep beyond REMOTE_SLEEP m of the eye (`d`: the square of the distance to
## it, net.gd _play_back), wakes it under REMOTE_WAKE m. Asleep: frozen STATIC (no wheel or contact callbacks), no
## cosmetic tick, no hull transform forcing; apply_net_state still moves it, so it does not pop when it wakes. Called
## each tick before posing it.
func update_remote_lod(d: float) -> void:
	if not remote:
		return
	if _remote_asleep:
		if d < REMOTE_WAKE * REMOTE_WAKE:
			_set_remote_asleep(false)
	elif d > REMOTE_SLEEP * REMOTE_SLEEP:
		_set_remote_asleep(true)


func _set_remote_asleep(on: bool) -> void:
	if on == _remote_asleep:
		return
	_remote_asleep = on
	_net_pos = global_position                  # no speed spike from the gap the sleep left
	_apply_remote_freeze()
	if on:
		audio.hush()


## True while a remote copy is asleep (far from the eye: see update_remote_lod).
func is_remote_asleep() -> bool:
	return _remote_asleep


## The bodies' freeze the way this copy needs it: STATIC asleep (cheap), KINEMATIC awake (posed by apply_net_state),
## unfrozen when we simulate it (stowed still freezes it).
func _apply_remote_freeze() -> void:
	var mode := RigidBody3D.FREEZE_MODE_STATIC if _remote_asleep else RigidBody3D.FREEZE_MODE_KINEMATIC
	for b in bodies():
		b.freeze_mode = mode
		b.freeze = remote or stowed
		b.sleeping = false


## LAN games: this vehicle's state for the other peers: [pose, rear section pose, steering, pedal, flags (1 doors
## open, 2 someone drives, 4 braking, 8 horn, 16 bell strikes are odd, 32 a bot drives, 64 stowed, 128 headlights; the
## fire truck adds its own above), indicator, health]. A bot's headlights follow each peer's own night instead.
func net_state() -> Array:
	var flags := (1 if doors_open else 0) | (2 if driving or pilot else 0) | (4 if _braking else 0) \
			| (8 if audio.horn else 0) | (16 if bells & 1 else 0) | (32 if pilot else 0) | (64 if stowed else 0) \
			| (128 if headlights else 0)
	return [global_transform, trailer.global_transform if trailer else Transform3D(), steering, _throttle, flags, indicator,
			health]


## LAN games, remote vehicle: the pose between states `a` and `b` (net_state()) at weight `w`, the switches of `b`.
## A weight over 1 carries on from `b` as it moved from `a` (net.gd Track.at), turned as `b`.
func apply_net_state(a: Array, b: Array, w: float) -> void:
	global_transform = _net_pose(a[0], b[0], w)
	if trailer:
		trailer.global_transform = _net_pose(a[1], b[1], w)
		if not _remote_asleep:
			_update_bellows()
	# a moved node's children reach the physics server only once this tick's physics callbacks are over: the player
	# following the vehicle (posed here first, net.gd) would walk against its walkable hulls a step behind (nothing
	# stands in a copy asleep far from every camera)
	if not _remote_asleep:
		for hull: StaticBody3D in [inside, trailer.inside if trailer else null, _bellows_hull]:
			if hull:
				hull.force_update_transform()
	steering = lerpf(a[2], b[2], minf(w, 1.0))
	_throttle = b[3]
	var flags: int = b[4]
	_remote_braking = flags & 4 != 0
	if bot_driven != (flags & 32 != 0):
		bot_driven = flags & 32 != 0
		show_driver(false)
	set_stowed(flags & 64 != 0)
	set_headlights(night if bot_driven else flags & 128 != 0)
	set_doors(flags & 1 != 0)
	if b[5] != indicator:
		set_indicator(b[5])
	if b.size() > 6:
		set_health(b[6], _net_seen)
	_net_seen = true
	audio.engine_on = (flags & 2 != 0 or has_doors) and not broken and not stowed
	audio.horn = flags & 8 != 0
	var bell := 1 if flags & 16 else 0
	if _net_bell >= 0 and bell != _net_bell:
		ring_bell()
	_net_bell = bell


static func _net_pose(a: Transform3D, b: Transform3D, w: float) -> Transform3D:
	if w <= 1.0:
		return a.interpolate_with(b, w)
	return Transform3D(b.basis, b.origin + (b.origin - a.origin) * (w - 1.0))


## Driver's (or passenger's) eye view (true) or chase camera; only vehicles with a cab have one.
func set_cab_view(on: bool) -> void:
	cab_view = on and _cab_camera != null
	if _driver_body:
		_driver_body.visible = not (cab_view and driving)
	_update_passenger()
	if driving or riding:
		(_cab_camera if cab_view else camera).make_current()


func has_cab() -> bool:
	return _cab_camera != null


## Mouse wheel: `notches` > 0 zooms the chase camera out, < 0 in. Zooming in past the closest distance goes to
## the cab view (when there is one), zooming out of it comes back to the chase camera (like Roblox).
func zoom(notches: float) -> void:
	if cab_view:
		if notches > 0.0:
			_cam_zoom = _zoom_range.x
			set_cab_view(false)
		return
	_cam_zoom *= pow(zoom_step, notches)
	if _cam_zoom < _zoom_range.x and has_cab():
		set_cab_view(true)
	_cam_zoom = clampf(_cam_zoom, _zoom_range.x, _zoom_range.y)


## True when `p` (global) is inside the walkable interior (of the front section, for an articulated vehicle); never
## while stowed (a bot bus off the map stays hidden where it vanished).
func carries(p: Vector3, margin := 0.0) -> bool:
	return not stowed and interior.size != Vector3.ZERO and interior.grow(margin).has_point(to_local(p))


## The section (this car or its rear section) whose walkable interior contains `p` (global), or null.
func carrier_at(p: Vector3, margin := 0.0) -> Node3D:
	if carries(p, margin):
		return self
	if trailer and trailer.carries(p, margin):
		return trailer
	return null


## A hit (scripts/plane_guns.gd: game.gd, through net.gd on the peer simulating the vehicle) taking `amount` of health.
func damage(amount: float) -> void:
	wake()
	if not broken:
		set_health(health - amount)


## The fire truck's water cannon (scripts/water_cannon.gd: game.gd, through net.gd on the peer simulating the vehicle)
## hosed it for `seconds`: a broken vehicle's fire is out after EXTINGUISH s of it, and it runs again.
func douse(seconds: float) -> void:
	if not broken or not repairs_itself:
		return
	_doused += seconds
	if _doused >= EXTINGUISH:
		set_health(max_health)


## The fire truck's water hit `body` (this car or its rear section) at `point` (global): pushed by `impulse` (N·s) and
## hosed for `seconds` (douse). Only on the peer simulating it (net.gd water_vehicle).
func hose(body: RigidBody3D, impulse: Vector3, point: Vector3, seconds: float) -> void:
	wake()
	body.apply_impulse(impulse, point - body.global_position)
	douse(seconds)


## Health `h` (clamped to 0..max_health): grey smoke under DAMAGED of max_health; at 0 broken (with a boom and a ball
## of fire when `effects`): engine dead, scorched, black smoke; above 0 again, repaired.
func set_health(h: float, effects := true) -> void:
	h = clampf(h, 0.0, max_health)
	if h == health:
		return
	health = h
	var was_broken := broken
	broken = h <= 0.0
	var level := 2 if broken else (1 if h < max_health * DAMAGED else 0)
	if level > 0 and _smoke == null:
		_smoke = WreckSmoke.new()
		_smoke.name = "Smoke"
		_smoke.size = smoke_size
		_smoke.position = smoke_spot
		add_child(_smoke)
	if _smoke:
		_smoke.set_level(level)
	if broken == was_broken:
		return
	_set_scorched(broken)
	if broken:
		_broken_t = 0.0
		_doused = 0.0
		audio.engine_on = false
		if effects:
			audio.play("boom")
			_smoke.burst()
	else:
		audio.engine_on = driving or has_doors


## Seconds until a broken vehicle is repaired.
func repair_in() -> float:
	return maxf(REPAIR_AFTER - _broken_t, 0.0)


## True while black smoke comes out of it.
func smoking_black() -> bool:
	return _smoke != null and _smoke.emitting_black()


## Soot over the meshes of a broken vehicle (not over glass, trails, flashes and the driver).
func _set_scorched(on: bool) -> void:
	if _soot == null:
		_soot = StandardMaterial3D.new()
		_soot.albedo_color = Color(0.05, 0.045, 0.04, 0.6)
		_soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_soot.roughness = 1.0
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as BaseMaterial3D
		if mi.top_level or (m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) \
				or (_driver_dummy and _driver_dummy.is_ancestor_of(mi)) or mi == _passenger:
			continue
		mi.material_overlay = _soot if on else null


## A hard knock (crash_damage, simulated here): the change of velocity since the last tick, beyond CRASH_FROM m/s,
## takes health, all of it at CRASH_WRECK m/s. Only from one tick to the next (not across a sleep, a teleport or a time
## simulated by another peer).
func _check_crash() -> void:
	var frame := Engine.get_physics_frames()
	var dv := (linear_velocity - _crash_v).length()
	if crash_damage and not broken and frame == _crash_frame + 1 and dv > CRASH_FROM:
		set_health(health - max_health * (dv - CRASH_FROM) / (CRASH_WRECK - CRASH_FROM))
	_crash_v = linear_velocity
	_crash_frame = frame


## Paints it in paint `id` (scripts/paint.gd; "" its own colours) and makes its far mesh again in that colour.
func set_paint(id: String) -> void:
	if id == paint:
		return
	paint = id
	_repaint(Paint.colour(model_name, id))
	if not _far.is_empty():
		for f in _far:
			f.get_parent().remove_child(f)
			f.queue_free()
		_far.clear()
		_build_far()


## Its meshes in colour `c` (null: their own). The biplane, the horse and the jet-ski recolour their own materials.
func _repaint(c: Variant) -> void:
	Paint.repaint(self, c)


## Broken vehicle simulated here: repaired once REPAIR_AFTER s have gone by (the others follow its health).
func _update_damage(delta: float) -> void:
	if broken and repairs_itself:
		_broken_t += delta
		if _broken_t >= REPAIR_AFTER:
			set_health(max_health)


## Velocity of the car body at global point `p`.
func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_transform * center_of_mass)


func set_indicator(side: int) -> void:
	indicator = side
	_signal_armed = false
	_blink_t = 0.0
	if side != 0 and driving:
		audio.play("tick")
	_light_indicators(side != 0)


func set_doors(open: bool) -> void:
	if not has_doors or open == doors_open:
		return
	doors_open = open
	audio.play("door_open" if open else "door_close")


## Forward speed in m/s (negative when reversing).
func speed() -> float:
	return linear_velocity.dot(global_basis.z)


func _heading() -> float:
	var f := global_basis.z
	return atan2(-f.x, -f.z)


func _unhandled_input(event: InputEvent) -> void:
	if not (driving or riding) or not controls:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look: Vector2 = event.screen_relative * sensitivity * Prefs.mouse_scale
		_look_yaw -= look.x
		_look_pitch = clampf(_look_pitch - look.y, -1.2, 0.4)
		if look != Vector2.ZERO:
			_look_idle = 0.0
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom((1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * (event.factor if event.factor > 0.0 else 1.0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_mode"):
		_switch_camera()
		_mode_held = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("camera_mode"):
		if _mode_held > MODE_HOLD:
			_switch_camera()                    # held: switched only while held
		_mode_held = -1.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		set_cab_view(not cab_view)
		get_viewport().set_input_as_handled()
	elif not driving:
		return                                  # the passenger only looks around
	elif event.is_action_pressed("reset_vehicle"):
		_put_back_on_wheels()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("signal_left"):
		set_indicator(0 if indicator == 1 else 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("signal_right"):
		set_indicator(0 if indicator == -1 else -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("doors"):
		set_doors(not doors_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bell") and audio.kind == "bus":
		ring_bell()
		get_viewport().set_input_as_handled()


## Extra line on the dashboard (the fire truck's water cannon and siren, the police car's siren); none by default.
func dash_line() -> String:
	return ""


## One RATP gong of the bus (counted in `bells` for the other peers).
func ring_bell() -> void:
	bells += 1
	audio.ring()


func _put_back_on_wheels() -> void:
	var yaw := atan2(global_basis.z.x, global_basis.z.z)
	place(Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.5))


func _physics_process(delta: float) -> void:
	if remote:
		_remote_process(delta)
		return
	if _rest_t > PARK_SLEEP and pilot == null and not driving:
		if _asleep():
			return                              # parked: nothing moves until something wakes it
		_rest_t = 0.0
	var throttle := 0.0
	var steer_in := 0.0
	var piloted := pilot != null and not driving
	var pedals := [0.0, 0.0]                # the pilot's throttle and brake, 0..1 each
	if driving and controls:
		throttle = Input.get_axis("brake", "throttle")
		steer_in = Input.get_axis("steer_right", "steer_left")
	elif piloted:
		# [throttle, brake, steering (-1..1, left positive)] and pilot.horn: a bot never reverses
		var c: Array = pilot.drive(delta)
		if pilot.gliding or stowed:
			return                              # posed by the bot far from every player, or off the map: nothing to run
		pedals = [clampf(c[0], 0.0, 1.0), clampf(c[1], 0.0, 1.0)]
		steer_in = clampf(c[2], -1.0, 1.0)
		throttle = pedals[0] - pedals[1]
	var drowned := _water_physics(delta)
	var drifting := driving and controls and Input.is_action_pressed("drift")
	audio.horn = (driving and controls and Input.is_action_pressed("horn")) or (piloted and pilot.horn)
	var v := speed()
	engine_force = 0.0
	brake = 0.0
	if piloted:
		if pedals[0] > 0.0 and v < max_speed:
			engine_force = engine_per_wheel * pedals[0]
		brake = maxf(max_brake * pedals[1], 1.5 if pedals[0] == 0.0 else 0.0)
	elif not driving:
		# nobody at the wheel: roll on (passengers may be walking inside), handbrake once slow
		brake = 1.5 if absf(v) > 1.0 else max_brake * 0.5
	elif throttle > 0.0:
		if v < -0.5:
			brake = max_brake
		elif v < max_speed:
			engine_force = engine_per_wheel
	elif throttle < 0.0:
		if v > 0.5:
			brake = max_brake
		elif v > -max_reverse_speed:
			engine_force = -engine_per_wheel * 0.6
	else:
		brake = 1.5                             # rolling resistance
	if engine_force != 0.0 and absf(v) < 5.0:
		engine_force *= 1.6                     # quicker start, like a low gear
	if broken or drowned:
		engine_force = 0.0                      # it still brakes
	if hold:
		engine_force = 0.0
		brake = max_brake
	engine_force *= _force_scale
	brake *= _total_mass / 300.0 / _wheel_count     # per wheel: a 4-wheel car's share of its mass / 1200
	# full lock at walking pace, fading with the speed
	var steer_max := steer_limit(v)
	if _drift > 0.0:
		steer_max = lerpf(steer_max, maxf(steer_max, max_steer * DRIFT_STEER), _drift)
	var back := steer_in == 0.0 or steer_in * steering < 0.0
	var rate := steer_speed * (1.5 if absf(v) < 5.0 else 1.0) * (2.0 if back else 1.0)
	steering = move_toward(steering, steer_in * steer_max, rate * delta)
	_throttle = throttle
	if trailer:
		# forward, the middle and the rear axle drive (the real Urbanway 18 is a pusher); in reverse only the
		# rear one, with the force of both, which then pulls the front section. All wheels brake. A towed
		# semi-trailer's wheels only roll.
		trailer.engine_force = 0.0 if _towed else engine_force * 2.0 if engine_force < 0.0 else engine_force
		if engine_force < 0.0 and not _towed:
			engine_force = 0.0
		trailer.brake = brake
		_damp_joint()
		_update_bellows()
	_update_drift(drifting, v, delta)

	_update_indicator(delta)
	_braking = (driving and throttle < 0.0) or (piloted and pedals[1] > 0.05)
	_set_brake_lamps(_braking)
	_set_reverse_lamps(driving and throttle < 0.0 and v <= 0.5)
	_update_steering()
	_update_doors(delta)
	_check_crash()
	_update_damage(delta)
	audio.update(v, throttle, max_speed, delta)
	_sleep_parked(v, delta)


## Parked (nobody at the wheel, no bot, engine off, dry, whole) at rest PARK_SLEEP s: its bodies sleep, out of the
## solver and the wheels' ray casts, and _physics_process idles until something wakes them: a contact, a push
## (wake: a hit, the water cannon), someone getting in (set_driving).
func _sleep_parked(v: float, delta: float) -> void:
	var idle := pilot == null and not driving and not riding and not broken and not audio.engine_on and indicator == 0 			and in_water == 0.0 and flooded == 0.0 and _door_t == (1.0 if doors_open else 0.0) and absf(v) < 0.1 			and angular_velocity.length_squared() < 0.01
	_rest_t = _rest_t + delta if idle else 0.0
	if _rest_t > PARK_SLEEP:
		for b in bodies():
			b.sleeping = true


func _asleep() -> bool:
	for b in bodies():
		if not b.sleeping:
			return false
	return true


## Out of its parked sleep (_sleep_parked).
func wake() -> void:
	_rest_t = 0.0
	for b in bodies():
		b.sleeping = false


## Buoyancy, drag and flooding in a lake (scripts/water.gd) for each section; true when the engine is drowned. Nothing
## to do (one grid lookup) out of the water.
func _water_physics(delta: float) -> bool:
	var deepest := 0.0
	for b in bodies():
		var lvl := Water.surface_at(b.global_position)
		if is_nan(lvl):
			continue
		var height := maxf(half_extents.y * 2.0, 0.5)
		var sub := clampf((lvl - b.global_position.y) / height, 0.0, 1.0)
		if sub <= 0.0:
			continue
		if b == self and in_water == 0.0 and Water.current:
			Water.current.splash(global_position, maxf(-linear_velocity.y, Vector2(linear_velocity.x, linear_velocity.z).length()),
					half_extents.x * 2.0)
		deepest = maxf(deepest, sub)
		var g: float = b.get_gravity().length()
		var lift := sub * b.mass * g * lerpf(FLOAT_BUOYANCY, SUNK_BUOYANCY, flooded)
		# lifting behind the centre of mass: the heavy engine end goes down first
		var at := b.global_basis * (b.center_of_mass + Vector3(0.0, 0.0, -0.25 * half_extents.z))
		b.apply_force(Vector3.UP * lift, at)
		b.apply_central_force(-b.linear_velocity * b.mass * WATER_DRAG * sub)
		b.apply_torque(-b.angular_velocity * b.mass * half_extents.length_squared() * 0.3 * sub)
	in_water = deepest
	if deepest > 0.15:
		flooded = minf(flooded + delta / FLOOD_TIME, 1.0)
	elif deepest == 0.0 and flooded > 0.0:
		flooded = maxf(flooded - delta / DRAIN_TIME, 0.0)
	return deepest > DROWN_DEPTH


## Steering lock (rad) at speed `v` (m/s): full at walking pace, fading with the speed.
func steer_limit(v: float) -> float:
	return maxf(max_steer / (1.0 + pow(absf(v) / steer_fade_speed, 1.5)), 0.08)


## Handbrake drift: eases the rear wheels' grip down while `drifting` (quickly) and back up after (DRIFT_RECOVER), and
## drags them a little while moving so the tail breaks loose. Runs after the body brakes are set (they set every wheel's).
func _update_drift(drifting: bool, v: float, delta: float) -> void:
	_drift = move_toward(_drift, 1.0 if drifting else 0.0, (8.0 if drifting else DRIFT_RECOVER) * delta)
	if _rear_wheels.is_empty() or _drift == 0.0 and _rear_wheels[0].wheel_friction_slip == grip:
		return
	for w in _rear_wheels:
		w.wheel_friction_slip = grip * lerpf(1.0, DRIFT_GRIP, _drift)
		if drifting and absf(v) > 2.0:
			w.brake = maxf(w.brake, max_brake * DRIFT_BRAKE * _total_mass / 300.0 / _wheel_count)


## Remote vehicle (net.gd poses it, bellows included): lamps, steering wheel, doors and engine sound from its states.
func _remote_process(delta: float) -> void:
	if _remote_asleep:
		return                              # far from every camera: lamps, doors and sound can wait
	_update_indicator(delta)
	_set_brake_lamps(_remote_braking)
	var along := (global_position - _net_pos).dot(global_basis.z)     # the pedal back and not rolling forwards
	_net_pos = global_position
	_set_reverse_lamps(_throttle < 0.0 and along <= 0.0)
	_update_steering()
	_update_doors(delta)
	audio.update(speed(), _throttle, max_speed, delta)


## Damps the articulation (relative yaw rate) lightly, as the hydraulic joint dampers of real articulated buses do;
## more would fight every turn-in. Rolling backwards it also pulls the joint straight (real joints stiffen in
## reverse): the front section's axles fix the hitch's path, so the rear section ahead of it would fold like a
## reversing trailer.
func _damp_joint() -> void:
	var up := global_basis.y
	var rate := (trailer.angular_velocity - angular_velocity).dot(up)
	var torque := up * rate * JOINT_DAMP * trailer.mass
	if speed() < -0.5:
		torque += up * articulation() * JOINT_REVERSE_SPRING * trailer.mass
	apply_torque(torque)
	trailer.apply_torque(-torque)


## Turns the steering wheel with the steering and puts the driver's hands on its rim, arms reaching to them.
func _update_steering() -> void:
	if _steering_wheel == null:
		return
	var turn := steering * STEERING_RATIO
	var hands := _driver_dummy.visible and not _hands.is_empty()
	if (turn == _posed_turn and hands == _posed_hands) or not _near_camera(STEERING_SEEN):
		return
	_posed_turn = turn
	_posed_hands = hands
	_steering_wheel.transform = _steering_rest * Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
	if not hands:
		return
	var grip := Basis(_wheel_axis, clampf(turn, -HAND_TURN, HAND_TURN))
	for k in 2:
		var a := deg_to_rad(GRIPS[k])
		var hand := _wheel_centre + grip * ((_wheel_right * cos(a) + _wheel_up * sin(a)) * _grip_radius) \
				+ _wheel_axis * 0.01
		_hands[k].position = hand
		var d := hand - _shoulders[k]
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		_arms[k].transform = Transform3D(Basis(x, d, x.cross(y)), (hand + _shoulders[k]) * 0.5)


func _update_indicator(delta: float) -> void:
	if indicator == 0:
		return
	# self-cancel once the wheel has turned the signalled way and come back (the driver's peer does it for remote ones)
	if remote or pilot:
		pass                                # the bot switches them off itself
	elif steering * indicator > 0.25:
		_signal_armed = true
	elif _signal_armed and steering * indicator < 0.04:
		set_indicator(0)
		return
	var was_on := fmod(_blink_t, BLINK) < BLINK * 0.5
	_blink_t += delta
	var on := fmod(_blink_t, BLINK) < BLINK * 0.5
	if on != was_on:
		_light_indicators(on)
		if driving:
			audio.play("tick" if on else "tock")


func _light_indicators(on: bool) -> void:
	for side in [1, -1]:
		for lamp: MeshInstance3D in _lamps[side]:
			lamp.material_override = _lamp_mats["indicator"][1 if on and side == indicator else 0]


func _update_doors(delta: float) -> void:
	if not has_doors:
		return
	var target := 1.0 if doors_open else 0.0
	if _door_t == target:
		return
	_door_t = move_toward(_door_t, target, delta / DOOR_TIME)
	# swing out during the first quarter, then slide along the side
	var out := DOOR_OUT * smoothstep(0.0, 0.25, _door_t)
	var slide := smoothstep(0.2, 1.0, _door_t)
	for door in _doors:
		for k in door["leaves"].size():
			var leaf: Node3D = door["leaves"][k]
			leaf.position = door["closed"][k] + Vector3(-out, 0.0, door["dirs"][k] * door["slide"] * slide)
		if door["shape"]:
			door["shape"].disabled = _door_t > 0.3


func _process(delta: float) -> void:
	var in_use := driving or riding
	if in_use != _arm.is_physics_processing_internal():
		_arm.set_physics_process_internal(in_use)
	if in_use:
		_update_camera(delta)


## True when the camera is within `d` m (or there is none: tools without one see everything).
func _near_camera(d: float) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam == null or cam.global_position.distance_squared_to(global_position) < d * d


## Chase camera. Auto (the default): behind the car, the mouse turning the view around it; once the mouse has rested
## LOOK_HOLD s the view eases back behind, the faster the faster the car goes (not at all at a walking pace), and
## reversing never turns it round. Free (free_camera; the camera mode button, the right one: a click switches, held
## longer than MODE_HOLD it switches only while held), and while the vehicle aims where the driver looks (holds_aim:
## the fire truck spraying): the view keeps its direction in the world whatever the car does; back to auto it eases
## back behind at once (switched by the button) or once the mouse has rested (done aiming). The look back key (held) turns the view half round at once, and back on
## release. The cab view looks the same way as the chase camera.
const LOOK_HOLD := 2.0                      # s the mouse rests before the auto camera eases back
const LOOK_EASE := 0.6                      # s the easing back takes to reach its pace
const RECENTRE_RATE := 1.5                  # 1/s, at full pace
const RECENTRE_SPEEDS := Vector2(2.0, 10.0) # m/s: no easing back under the first, full pace over the second
const MODE_HOLD := 0.35                     # s: the camera mode button held longer switches only while held

func _update_camera(delta: float) -> void:
	_update_view_state(delta)
	var free := _free_view()
	var h := _heading()
	if _was_free and not free:              # the view stays where it is, now an offset from behind the car
		_look_yaw = wrapf(_follow_yaw + _look_yaw - h, -PI, PI)
		_follow_yaw = h
		if _was_aim:                        # done aiming: eased back once the mouse has rested
			_look_idle = 0.0
	_was_free = free
	_was_aim = holds_aim()
	if not free:
		_follow_yaw = lerp_angle(_follow_yaw, h, 1.0 - exp(-4.0 * delta))
		_look_yaw = lerp_angle(_look_yaw, 0.0, 1.0 - exp(-_recentre_rate(absf(speed())) * delta))
	var back := PI if _looking_back else 0.0
	_arm.spring_length = lerpf(_arm.spring_length, _cam_zoom, 1.0 - exp(-10.0 * delta))
	_cam_pivot.global_position = to_global(Vector3(0.0, 0.0, extents_center.z)) + Vector3.UP * _cam_height
	_cam_pivot.global_rotation = Vector3(_look_pitch, _follow_yaw + _look_yaw + back, 0.0)
	if _cab_camera:
		# auto: the mouse offset from straight ahead (not the chase camera's lag in a turn); free: the same world direction
		var yaw := wrapf(_follow_yaw + _look_yaw - h, -PI, PI) if free else _look_yaw
		_cab_camera.rotation = Vector3(clampf(_look_pitch - 0.1 + _cab_pitch, -1.0, 0.6), PI + yaw + back, 0.0)


## The camera mode button: free camera on or off; back to auto, the view eases back behind at once (no LOOK_HOLD wait).
func _switch_camera() -> void:
	free_camera = not free_camera
	if not free_camera:
		_look_idle = maxf(_look_idle, LOOK_HOLD)


## The timers and switches of the view, every frame the camera is updated (the plane's too).
func _update_view_state(delta: float) -> void:
	_look_idle += delta
	if _mode_held >= 0.0:
		_mode_held += delta
	_looking_back = controls and Input.is_action_pressed("look_back")


## Easing back pace of the auto camera (1/s) at `v` m/s: none until the mouse has rested LOOK_HOLD s, then rising over
## LOOK_EASE s.
func _recentre_rate(v: float) -> float:
	var ramp := clampf((_look_idle - LOOK_HOLD) / LOOK_EASE, 0.0, 1.0)
	return RECENTRE_RATE * ramp * smoothstep(RECENTRE_SPEEDS.x, RECENTRE_SPEEDS.y, v)


## True while the view keeps its direction in the world: the free camera, or the vehicle aiming with it.
func _free_view() -> bool:
	return free_camera or holds_aim()


## True while the vehicle aims where the driver looks (the fire truck spraying); none by default.
func holds_aim() -> bool:
	return false


## The camera mode for the dashboard: "" for the auto camera.
func camera_label() -> String:
	if free_camera:
		return "FREE CAMERA"
	return "CAMERA HELD (aiming)" if holds_aim() else ""
