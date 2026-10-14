extends VehicleBody3D
## Drivable toy car built at runtime from a downloaded model (assets/cars, see CREDITS.md): the
## model's four wheel nodes become VehicleWheel3D, the body gets a box collider. Call setup() before
## adding it to the tree. While `driving` (keys: the Settings actions, scripts/settings.gd; defaults on physical
## positions): W/S throttle and brake/reverse, A/D steer, Q/E turn signals (A/E on AZERTY), G (held) sounds the horn,
## X (held) drifts, B sounds a bus's RATP gong, R puts the car back on its wheels, the mouse orbits the chase camera
## (it eases back behind the car while moving, in front of it while reversing; hold the right button to keep it).
## game.gd handles getting in (E) and out (Space). The models face +Z, which is also VehicleBody3D's
## forward; their left side is +X.
## Models with a layout file (the bus: assets/cars/bus_idfm.json, written by blender/vehicles/build_bus.py)
## are walkable: a child StaticBody3D `inside` on the VEHICLE_INSIDE layer (only the player scans it) holds
## the floor, walls, seats and door openings, while the rigid body keeps its plain box from the wheel centres
## up for the world (kerbs pass under it; game.gd makes the player ignore that box). Sliding doors the driver
## opens and closes with O, an interior that carries the player (carries()), a driver seat and a cab view (V, or
## the mouse wheel zoomed all the way in, like Roblox). The driver's arms reach to hands on the steering wheel, which
## turns with the steering (STEERING_RATIO); the hands follow it up to HAND_TURN, then let it slide.
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
## (carrier_at). Move the vehicle with place(), which puts the rear section straight behind.
## LAN games (scripts/net.gd): a vehicle another peer simulates is `remote`, its bodies frozen kinematic and posed from
## that peer's states (apply_net_state); the wheels still turn and steer, and lamps, doors, horn and sound follow the
## states.
## Damage (the armed biplane's rounds, scripts/plane_guns.gd): each vehicle has `health` (HEALTH for a 1,200 kg car,
## more for heavier ones); hits only count on the peer simulating it (damage), the others follow its states. Under
## half of it, grey smoke comes out of the engine; at 0 it is `broken`: a boom and a ball of fire, the engine dies, the
## body is scorched and black smoke billows out of it (scripts/wreck_smoke.gd) until it is repaired REPAIR_AFTER s
## later, or until the fire truck's water cannon has hosed it for EXTINGUISH s (douse), which puts the fire out.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const Trailer = preload("res://scripts/car_trailer.gd")
const WreckSmoke = preload("res://scripts/wreck_smoke.gd")
const Prefs = preload("res://scripts/settings.gd")
const KENNEY_WHEELS := ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]
## Per model: file in assets/cars, scale, body mesh node, wheel nodes (front left, front right, back
## left, back right), credit, mass (kg; engine, brakes and suspension scale with it), power (engine
## factor), max_speed (m/s), max_steer (rad at walking pace), layout (json next to the model), sound
## (vehicle_audio kind), traction_from (index of the first driven wheel; all drive by default), trailer_mass (kg,
## rear section of an articulated vehicle), label (name in the vehicle menu, see display_name), plane (built and flown
## by scripts/plane.gd, which extends this script, instead), guns (a plane's machine guns), fittings (the fire truck's
## lamps and water cannon, json next to the model: scripts/fire_truck.gd, which extends this script, drives it). Missing
## keys take the Kenney Car Kit values (scale 1.5: ~2.8 m -> ~4.2 m); the wheels beyond the first four are a third axle.
const SPECS := {
	"bus-idfm": {"label": "IDFM bus (12 m)", "file": "bus_idfm.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"],
			"mass": 12000.0, "power": 0.6, "max_speed": 38.0, "max_steer": 0.8, "layout": "bus_idfm.json",
			"sound": "bus", "credit": "Iveco Urbanway, IDFM livery, built by blender/vehicles/build_bus.py"},
	"bus-idfm-artic": {"label": "Articulated bus (18 m)", "file": "bus_idfm_artic.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_middle_left", "wheel_middle_right"],
			"traction_from": 2, "mass": 10000.0, "trailer_mass": 7000.0, "power": 0.6, "max_speed": 36.0,
			"max_steer": 0.8, "layout": "bus_idfm_artic.json", "sound": "bus",
			"credit": "Iveco Urbanway 18 m articulated, IDFM livery, built by blender/vehicles/build_bus.py"},
	"kaykit-hatchback": {"label": "Hatchback", "file": "kaykit_hatchback.glb", "scale": 5.0, "body": "car_hatchback",
			"wheels": ["car_hatchback_wheel_front_left", "car_hatchback_wheel_front_right",
				"car_hatchback_wheel_rear_left", "car_hatchback_wheel_rear_right"],
			"credit": "Kay Lousberg (KayKit), CC0"},
	"sedan": {}, "taxi": {}, "suv": {"label": "SUV"}, "police": {}, "hatchback-sports": {"label": "Sports hatchback"},
	"van": {}, "sedan-sports": {"label": "Sports sedan"}, "suv-luxury": {"label": "Luxury SUV"}, "delivery": {"label": "Delivery van"},
	"ambulance": {},
	"fire-truck": {"label": "Fire truck", "file": "fire_truck.glb", "scale": 1.0,
			"wheels": ["wheel_front_left", "wheel_front_right", "wheel_middle_left", "wheel_middle_right",
				"wheel_rear_left", "wheel_rear_right"],
			"mass": 16000.0, "power": 0.32, "max_speed": 28.0, "max_steer": 0.6, "fittings": "fire_truck.json",
			"sound": "truck", "credit": "6x6 airport crash tender, built by blender/vehicles/build_fire_truck.py"},
	"biplane": {"label": "Biplane", "plane": true, "credit": "toy biplane built by scripts/plane.gd"},
	"biplane-armed": {"label": "Armed biplane", "plane": true, "guns": true,
			"credit": "toy fighter biplane built by scripts/plane.gd"},
}
const MODELS := ["bus-idfm", "bus-idfm-artic", "kaykit-hatchback", "sedan", "taxi", "suv", "police", "hatchback-sports", "van",
		"sedan-sports", "suv-luxury", "delivery", "ambulance", "fire-truck", "biplane", "biplane-armed"]
const REST_LENGTH := 0.2
const BLINK := 0.75                         # s, indicator period
const DOOR_TIME := 1.6                      # s to open or close
const DOOR_OUT := 0.1                       # plug doors: leaves first swing out this far, then slide
const STEERING_RATIO := 3.5                 # steering wheel turn per road wheel angle: full lock stays under half a
											# turn, so a still frame never reads as the opposite way
const HAND_TURN := 1.6                      # rad: the driver's hands turn with the wheel this far, then slide on it
const GRIPS := [150.0, 30.0]                # left and right hand on the rim, degrees from 3 o'clock (10 and 2 o'clock)
const JOINT_YAW := 0.9                      # rad, articulation limit either way (~52°)
const JOINT_PITCH := 0.12                   # rad, the sections fold this much over crests and dips
const JOINT_DAMP := 3.0                     # torque per rad/s of relative yaw, per kg of rear section (calms the joint)
const JOINT_REVERSE_SPRING := 100.0         # rolling backwards the joint stiffens: torque per rad, per kg of rear section
const DRIFT_GRIP := 0.35                    # rear wheel grip while drifting, fraction of `grip`
const DRIFT_BRAKE := 0.12                   # rear handbrake while drifting, fraction of max_brake
const DRIFT_STEER := 0.45                   # steering lock kept while drifting, fraction of max_steer
const DRIFT_RECOVER := 2.0                  # /s, the rear grip coming back once X is released
const BELLOWS_SEGMENTS := 4                 # wall boxes along the bellows (walkable articulation)
const HEALTH := 100.0                       # a 1,200 kg car's; heavier vehicles have more (with the square root of the mass)
const DAMAGED := 0.5                        # share of the health under which the engine smokes grey
const REPAIR_AFTER := 60.0                  # s a broken vehicle smokes before it is repaired
const EXTINGUISH := 2.0                     # s of the fire truck's water on a broken vehicle that put its fire out

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
var audio: VehicleAudio
var inside: StaticBody3D                    # walkable hull, only with a layout
var door_centres: Array[Vector3] = []       # car frame, doorway centre on the floor
var cab_view := false                       # driver's eye view instead of the chase camera
var trailer: Trailer                        # rear section of an articulated vehicle, or null
var rear_offset := Vector3.ZERO             # the rear section's origin in the car frame while straight
var extents_center := Vector3.ZERO          # centre of the half_extents box in the car frame (x, z)
var net_id := ""                            # LAN games: the vehicle's id on every peer
var remote := false                         # LAN games: simulated by another peer (set_remote)
var bells := 0                              # bell strikes so far (LAN: its parity tells the peers to ring)
var controls := true                        # false while a menu is open: the driver's keys do nothing
var health := HEALTH
var max_health := HEALTH
var broken := false                         # health 0: engine dead, black smoke
var smoke_spot := Vector3.ZERO              # car frame: where the smoke comes out (the engine)
var smoke_size := 1.0

var _cam_pivot: Node3D
var _arm: SpringArm3D
var _cab_camera: Camera3D                   # driver's eye view (V), only with a layout
var _cam_zoom := 7.5                        # chase camera distance the arm eases to
var _zoom_range := Vector2(3.0, 20.0)       # closest (zooming in past it: cab view) and furthest
var _follow_yaw := 0.0
var _look_yaw := 0.0                        # mouse offset around the car, eases back while moving
var _look_pitch := -0.22
var _reverse_view := false                  # chase camera in front of the car, looking back while reversing
var _reverse_t := 0.0                       # time the speed has been past the flip threshold
var _force_scale := 1.0                     # engine and brakes, from the mass and the model's power
var _cam_height := 2.2                      # camera pivot above the car origin
var _blink_t := 0.0
var _signal_armed := false                  # the wheel has turned the signalled way: cancel when back
var _lamps := {1: [], -1: []}               # indicator meshes per side
var _brake_lamps: Array[MeshInstance3D] = []
var _lamp_mats := {}                        # "indicator"/"brake" -> [off, on]
var _steering_wheel: Node3D
var _steering_rest := Transform3D.IDENTITY
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
var _joint: Generic6DOFJoint3D
var _bellows := {}                          # profile, in the car frame (layout "bellows")
var _bellows_profiles := []                 # ridge and valley: [points, normals] (PackedVector2Array)
var _bellows_mesh: ArrayMesh
var _bellows_arrays := []                   # mesh arrays; vertices and normals rewritten when the joint bends
var _bellows_rel := Transform3D()           # rear section in the car frame when the bellows was last built
var _joint_walls: Array[CollisionShape3D] = []    # per segment: left wall, right wall, roof
var _bellows_hull: StaticBody3D             # walls of the walkable passage through the bellows
var _skin: StandardMaterial3D               # the driver look-alike's colour
var _remote_braking := false
var _smoke: WreckSmoke                      # made at the first smoke
var _broken_t := 0.0                        # s since it broke
var _doused := 0.0                          # s of water on it since it broke
var _net_seen := false                      # LAN, remote vehicle: a state came already (no boom for a wreck on joining)

static var _soot: StandardMaterial3D        # drawn over a broken vehicle's meshes


## Name of `model` for menus: its spec's label, else the model name capitalized ("sedan" -> "Sedan").
static func display_name(model: String) -> String:
	return SPECS[model].get("label", model.replace("-", " ").capitalize())


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "Car_" + model.replace("-", "_")
	mass = float(spec.get("mass", 1200.0))
	max_speed = float(spec.get("max_speed", max_speed))
	max_steer = float(spec.get("max_steer", max_steer))
	_configure_body(self)
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "Kenney Car Kit, CC0")]})
	var layout: Dictionary = {}
	if spec.has("layout"):
		layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cars/" + spec["layout"]))

	var m: Node3D = load("res://assets/cars/" + spec.get("file", model + ".glb")).instantiate()
	m.scale = Vector3.ONE * float(spec.get("scale", 1.5))
	add_child(m)
	var body := m.find_child(spec.get("body", "body"), true, false) as MeshInstance3D
	var wheels := _find_meshes(m, spec.get("wheels", KENNEY_WHEELS))
	var rear_wheels: Array[MeshInstance3D] = []
	if layout.has("trailer"):
		rear_wheels = _find_meshes(m, layout["trailer"]["wheels"])
	# put the bottom of the wheels on y = 0
	var ground := INF
	for w in wheels + rear_wheels:
		ground = minf(ground, (_in_car(w) * w.get_aabb()).position.y)
	m.position.y -= ground
	var rear_off := Vector3.ZERO
	if layout.has("trailer"):
		# VehicleBody3D takes the body origin for the centre of mass in its tyre maths (contact velocity =
		# linear_velocity + ω × (contact - origin)), so each section's origin goes on its centre of mass: else
		# every turn makes the tyres fight a phantom sideways slip of ω × the offset. Front section: midway
		# between its axles, so the middle axle carries its share. Rear section: a quarter of the way from its axle
		# to the hitch, so the hitch presses on the middle axle too.
		m.position.z -= _mean_z(wheels)
		var hitch: Vector3 = Vector3(layout["hitch"][0], layout["hitch"][1], layout["hitch"][2]) * m.scale + m.position
		rear_off = Vector3(0.0, 0.0, lerpf(_mean_z(rear_wheels), hitch.z, 0.25))
	var box: AABB = _in_car(body) * body.get_aabb()
	var wheel_y := _add_wheels(self, wheels, 2, int(spec.get("traction_from", 0)))
	half_extents = box.size * 0.5
	# box from the wheel centres up, so kerbs pass under it
	_add_box(self, Vector3(box.get_center().x, (box.end.y + wheel_y) * 0.5, box.get_center().z),
			Vector3(box.size.x, box.end.y - wheel_y, box.size.z))
	_total_mass = mass
	_wheel_count = wheels.size()
	if layout.has("trailer"):
		var rear_box := _build_trailer(m, layout["trailer"], rear_wheels, float(spec.get("trailer_mass", mass * 0.6)), rear_off)
		rear_box.position += rear_off
		# the whole vehicle, straight (spawning, getting in, chase camera)
		var whole := box.merge(rear_box)
		half_extents = whole.size * 0.5
		extents_center = Vector3(whole.get_center().x, 0.0, whole.get_center().z)
	_force_scale = _total_mass / 1200.0 * float(spec.get("power", 1.0))
	_set_max_health()
	# the engine: under the bonnet, at the back of a bus
	smoke_spot = Vector3(box.get_center().x, box.end.y - 0.3, box.position.z + 1.2) if spec.has("layout") \
			else Vector3(box.get_center().x, box.position.y + box.size.y * 0.55, box.end.z - box.size.z * 0.22)
	if not layout.is_empty():
		_build_layout(m, layout)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, wheel_y - com_drop, 0.0 if trailer else box.get_center().z)
	_build_lamps(m, box, layout)

	audio = VehicleAudio.new()
	audio.position = Vector3(0.0, 1.0, box.end.z - 1.0 if spec.has("layout") else box.get_center().z)
	audio.setup(spec.get("sound", "car"))
	add_child(audio)

	_cam_pivot = Node3D.new()
	_cam_pivot.top_level = true
	add_child(_cam_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = maxf(camera_distance, half_extents.z * 2.1)
	_cam_zoom = _arm.spring_length
	_zoom_range = Vector2(0.45, 2.5) * _cam_zoom
	_cam_height = box.end.y + 0.5
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


## Collision boxes, doors, interior and driver positions from the model's layout file (glTF frame, so
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
	driver_seat = v.call(layout["driver_seat"])
	driver_exit = v.call(layout["driver_exit"])
	_steering_wheel = m.find_child(layout.get("steering_wheel", ""), true, false) as Node3D
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
	_cab_camera.position = v.call(layout["driver_eye"])
	_cab_camera.rotation = Vector3(-0.27, PI, 0.0)
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
	var rel := global_transform.affine_inverse() * trailer.global_transform
	if rel.origin.distance_to(_bellows_rel.origin) + (rel.basis.z - _bellows_rel.basis.z).length() < 0.001:
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
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.25
	capsule.material = skin
	_driver_body = MeshInstance3D.new()
	_driver_body.mesh = capsule
	_driver_body.position = driver_seat + Vector3(0.0, 0.62, 0.0)
	_driver_dummy.add_child(_driver_body)
	if _steering_wheel == null:
		return
	var arm := CylinderMesh.new()               # along +Y from the shoulder (bottom) to the hand (top)
	arm.top_radius = 0.042
	arm.bottom_radius = 0.055
	arm.height = 1.0
	arm.radial_segments = 12
	arm.rings = 1
	arm.material = skin
	var hand := SphereMesh.new()
	hand.radius = 0.05
	hand.height = 0.09
	hand.radial_segments = 12
	hand.rings = 6
	hand.material = skin
	for side: float in [1.0, -1.0]:             # left (+X), right
		_shoulders.append(driver_seat + Vector3(side * 0.21, 0.72, -0.04))
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = arm if k == 0 else hand
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_driver_dummy.add_child(mi)
			(_arms if k == 0 else _hands).append(mi)


## Indicator and brake lamps: the model's named meshes when its layout lists them, else small boxes at the
## corners of the body box.
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
	else:
		var y := box.position.y + box.size.y * 0.45
		for side in [1, -1]:
			for z: float in [box.end.z, box.position.z]:
				_lamps[side].append(_lamp_box(Vector3(side * (box.size.x * 0.5 - 0.12), y, z), Vector3(0.14, 0.07, 0.04)))
			_brake_lamps.append(_lamp_box(Vector3(side * (box.size.x * 0.5 - 0.3), y, box.position.z), Vector3(0.2, 0.08, 0.04)))
	for side in [1, -1]:
		for lamp: MeshInstance3D in _lamps[side]:
			lamp.material_override = _lamp_mats["indicator"][0]
	for lamp in _brake_lamps:
		lamp.material_override = _lamp_mats["brake"][0]


func _lamp_box(p: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = p + Vector3(0.0, 0.0, signf(p.z) * 0.01)
	add_child(mi)
	return mi


## Transform of `n` in the car's frame (the car is not in the tree yet, so no global transforms).
func _in_car(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p and p != self:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
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


## The rigid bodies: this one and the rear section of an articulated vehicle.
func bodies() -> Array[VehicleBody3D]:
	var out: Array[VehicleBody3D] = [self]
	if trailer:
		out.append(trailer)
	return out


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
	if _driver_dummy:
		_driver_dummy.visible = on
	if on:
		audio.engine_on = not broken
		_follow_yaw = _heading()
		_look_yaw = 0.0
		_reverse_view = false
		_reverse_t = 0.0
		_update_camera(1.0)
		set_cab_view(cab_view)
		_update_steering()
	else:
		audio.engine_on = has_doors and not broken      # a bus keeps idling for its passengers
		audio.horn = false
		set_indicator(0)


## LAN games: someone on another peer drives (on) or nobody does: shows the driver look-alike in `color`.
func show_driver(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	set_driver_color(color)
	if _driver_dummy:
		_driver_dummy.visible = on or driving


func set_driver_color(color: Color) -> void:
	if _skin:
		_skin.albedo_color = color


## LAN games: simulated by another peer (true: the bodies turn kinematic and follow apply_net_state) or here (false:
## dynamic again, keeping the speed they were last moved at).
func set_remote(on: bool) -> void:
	if on == remote:
		return
	remote = on
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


## LAN games: this vehicle's state for the other peers: [pose, rear section pose, steering, pedal, flags (1 doors
## open, 2 someone drives, 4 braking, 8 horn, 16 bell strikes are odd), indicator, health].
func net_state() -> Array:
	var flags := (1 if doors_open else 0) | (2 if driving else 0) | (4 if driving and _throttle < 0.0 else 0) \
			| (8 if audio.horn else 0) | (16 if bells & 1 else 0)
	return [global_transform, trailer.global_transform if trailer else Transform3D(), steering, _throttle, flags, indicator,
			health]


## LAN games, remote vehicle: the pose between states `a` and `b` (net_state()) at weight `w`, the switches of `b`.
## A weight over 1 carries on from `b` as it moved from `a` (net.gd Track.at), turned as `b`.
func apply_net_state(a: Array, b: Array, w: float) -> void:
	global_transform = _net_pose(a[0], b[0], w)
	if trailer:
		trailer.global_transform = _net_pose(a[1], b[1], w)
		_update_bellows()
	# a moved node's children reach the physics server only once this tick's physics callbacks are over: the player
	# following the vehicle (posed here first, net.gd) would walk against its walkable hulls a step behind
	for hull: StaticBody3D in [inside, trailer.inside if trailer else null, _bellows_hull]:
		if hull:
			hull.force_update_transform()
	steering = lerpf(a[2], b[2], minf(w, 1.0))
	_throttle = b[3]
	var flags: int = b[4]
	_remote_braking = flags & 4 != 0
	set_doors(flags & 1 != 0)
	if b[5] != indicator:
		set_indicator(b[5])
	if b.size() > 6:
		set_health(b[6], _net_seen)
	_net_seen = true
	audio.engine_on = (flags & 2 != 0 or has_doors) and not broken
	audio.horn = flags & 8 != 0
	var bell := 1 if flags & 16 else 0
	if _net_bell >= 0 and bell != _net_bell:
		ring_bell()
	_net_bell = bell


static func _net_pose(a: Transform3D, b: Transform3D, w: float) -> Transform3D:
	if w <= 1.0:
		return a.interpolate_with(b, w)
	return Transform3D(b.basis, b.origin + (b.origin - a.origin) * (w - 1.0))


## Driver's eye view (true) or chase camera; only vehicles with a layout have a cab.
func set_cab_view(on: bool) -> void:
	cab_view = on and _cab_camera != null
	if _driver_body:
		_driver_body.visible = not cab_view
	if driving:
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


## True when `p` (global) is inside the walkable interior (of the front section, for an articulated vehicle).
func carries(p: Vector3, margin := 0.0) -> bool:
	return interior.size != Vector3.ZERO and interior.grow(margin).has_point(to_local(p))


## The section (this car or its rear section) whose walkable interior contains `p` (global), or null.
func carrier_at(p: Vector3, margin := 0.0) -> Node3D:
	if carries(p, margin):
		return self
	if trailer and trailer.carries(p, margin):
		return trailer
	return null


## A hit (scripts/plane_guns.gd: game.gd, through net.gd on the peer simulating the vehicle) taking `amount` of health.
func damage(amount: float) -> void:
	if not broken:
		set_health(health - amount)


## The fire truck's water cannon (scripts/water_cannon.gd: game.gd, through net.gd on the peer simulating the vehicle)
## hosed it for `seconds`: a broken vehicle's fire is out after EXTINGUISH s of it, and it runs again.
func douse(seconds: float) -> void:
	if not broken:
		return
	_doused += seconds
	if _doused >= EXTINGUISH:
		set_health(max_health)


## The fire truck's water hit `body` (this car or its rear section) at `point` (global): pushed by `impulse` (N·s) and
## hosed for `seconds` (douse). Only on the peer simulating it (net.gd water_vehicle).
func hose(body: RigidBody3D, impulse: Vector3, point: Vector3, seconds: float) -> void:
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
				or (_driver_dummy and _driver_dummy.is_ancestor_of(mi)):
			continue
		mi.material_overlay = _soot if on else null


## Broken vehicle simulated here: repaired once REPAIR_AFTER s have gone by (the others follow its health).
func _update_damage(delta: float) -> void:
	if broken:
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
	if not driving or not controls:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look: Vector2 = event.screen_relative * sensitivity * Prefs.mouse_scale
		_look_yaw -= look.x
		_look_pitch = clampf(_look_pitch - look.y, -1.2, 0.4)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom((1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * (event.factor if event.factor > 0.0 else 1.0))
		get_viewport().set_input_as_handled()
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
	elif event.is_action_pressed("toggle_view"):
		set_cab_view(not cab_view)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bell") and audio.kind == "bus":
		ring_bell()
		get_viewport().set_input_as_handled()


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
	var throttle := 0.0
	var steer_in := 0.0
	if driving and controls:
		throttle = Input.get_axis("brake", "throttle")
		steer_in = Input.get_axis("steer_right", "steer_left")
	var drifting := driving and controls and Input.is_action_pressed("drift")
	audio.horn = driving and controls and Input.is_action_pressed("horn")
	var v := speed()
	engine_force = 0.0
	brake = 0.0
	if not driving:
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
	if broken:
		engine_force = 0.0                      # it still brakes
	engine_force *= _force_scale
	brake *= _total_mass / 300.0 / _wheel_count     # per wheel: a 4-wheel car's share of its mass / 1200
	# full lock at walking pace, fading with the speed
	var steer_max := maxf(max_steer / (1.0 + pow(absf(v) / steer_fade_speed, 1.5)), 0.08)
	if _drift > 0.0:
		steer_max = lerpf(steer_max, maxf(steer_max, max_steer * DRIFT_STEER), _drift)
	var back := steer_in == 0.0 or steer_in * steering < 0.0
	var rate := steer_speed * (1.5 if absf(v) < 5.0 else 1.0) * (2.0 if back else 1.0)
	steering = move_toward(steering, steer_in * steer_max, rate * delta)
	_throttle = throttle
	if trailer:
		# forward, the middle and the rear axle drive (the real Urbanway 18 is a pusher); in reverse only the
		# rear one, with the force of both, which then pulls the front section. All wheels brake.
		trailer.engine_force = engine_force * 2.0 if engine_force < 0.0 else engine_force
		if engine_force < 0.0:
			engine_force = 0.0
		trailer.brake = brake
		_damp_joint()
		_update_bellows()
	_update_drift(drifting, v, delta)

	_update_indicator(delta)
	var braking := driving and throttle < 0.0
	for lamp in _brake_lamps:
		lamp.material_override = _lamp_mats["brake"][1 if braking else 0]
	_update_steering()
	_update_doors(delta)
	_update_damage(delta)
	audio.update(v, throttle, max_speed, delta)


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
	_update_indicator(delta)
	for lamp in _brake_lamps:
		lamp.material_override = _lamp_mats["brake"][1 if _remote_braking else 0]
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
	_steering_wheel.transform = _steering_rest * Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
	if not _driver_dummy.visible or _hands.is_empty():
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
	if remote:
		pass
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
	if driving:
		_update_camera(delta)


## Chase camera behind the car, or in front of it looking back while reversing: the flip waits for the speed to stay
## past REVERSE_VIEW_SPEED for REVERSE_VIEW_DELAY, so it does not flicker around 0 km/h. Holding the right mouse
## button keeps the view where the mouse puts it (no easing back, no flip).
const REVERSE_VIEW_SPEED := 1.0             # m/s
const REVERSE_VIEW_DELAY := 0.6             # s

func _update_camera(delta: float) -> void:
	var v := speed()
	var user_look := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not user_look and (v < -REVERSE_VIEW_SPEED if not _reverse_view else v > REVERSE_VIEW_SPEED):
		_reverse_t += delta
		if _reverse_t >= REVERSE_VIEW_DELAY:
			_reverse_view = not _reverse_view
			_reverse_t = 0.0
	else:
		_reverse_t = 0.0
	_follow_yaw = lerp_angle(_follow_yaw, _heading() + (PI if _reverse_view else 0.0), 1.0 - exp(-4.0 * delta))
	if absf(v) > 2.0 and not user_look:
		_look_yaw = lerp_angle(_look_yaw, 0.0, 1.0 - exp(-1.5 * delta))
	_arm.spring_length = lerpf(_arm.spring_length, _cam_zoom, 1.0 - exp(-10.0 * delta))
	_cam_pivot.global_position = to_global(Vector3(0.0, 0.0, extents_center.z)) + Vector3.UP * _cam_height
	_cam_pivot.global_rotation = Vector3(_look_pitch, _follow_yaw + _look_yaw, 0.0)
	if _cab_camera:
		_cab_camera.rotation = Vector3(clampf(_look_pitch - 0.1, -1.0, 0.6), PI + _look_yaw, 0.0)
