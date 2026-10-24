extends Node3D
## An RER B train (the MI 79 R of blender/vehicles/build_train.py, assets/cars/mi79.glb and its layout mi79.json):
## eight cars, two units of four (cab, intermediate, intermediate, cab turned round), locked to the rails of its
## service (world/rail.json services: the route of its track every metre, with the rail level and the cant). Nothing
## here is a VehicleBody3D: the whole state is the distance of the front coupler along the route (`front`), the
## speed, the doors and the lamps, and every physics tick each car is posed from it: each bogie on the rail curve
## (turned to it, canted), the car body between its two bogie pivots. A bot (scripts/train_bot.gd) drives it on the
## peer that simulates it (solo, the host, a dedicated server); the others pose it from its states (net.gd), from the
## same route, so it is where the host has it on every screen.
## Each car is a TrainCar: the model's car (body, interior, far shell, bogies, door leaves, lamps, display), a walkable
## hull (StaticBody3D on the VEHICLE_INSIDE layer: floor, walls with the door openings, seats, end walls with the
## gangway doorways, the cab partition; the door boxes are solid while the doors are shut) and an outer box on the
## VEHICLES layer for the world (the player passes through it to its hull, as with the bus). A car carries the player
## standing in it (carries(), carrier_at(), as car.gd: game.gd and player.gd use the same calls); the gangways between
## the cars of a unit are walkable (their floor plates and walls are boxes posed between the cars), the units are not
## joined (MI 79: cabs at both ends of a unit).
## Doors: both leaves of every door on one side slide open along the outside of the body (DOOR_TIME); while a player
## stands in a doorway (door_blocked) the bot keeps them open, like the bus's door hold. Lamps: the white head lamps
## of the leading cab and the red tail lamps of the trailing one (the others off), a head lamp beam and the cabin
## lights at night, the destination on both end cabs' displays. Far from the camera each car draws only its light
## shell (FAR) and its interior only near (INSIDE): eight cars cost about two buses in the distance.
## Sounds (scripts/vehicle_audio.gd, kind "train"), from the car nearest the camera: the traction motors' whine and the
## rails' rumble with the speed, the horn, the door warning and the doors, the brakes' squeal at a stop, the flanges'
## squeal through curves tighter than FLANGE_RADIUS, the wheels over the insulated joints at the block signals, the air
## compressor while it stands.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const MODEL := "res://assets/cars/mi79.glb"
const LAYOUT := "res://assets/cars/mi79.json"
const UNITS := 2                            # units of four cars (an 8-car train, the RER B's standard)
const DOOR_TIME := 3.0                      # s for the leaves to open or close (RER doors: about 3 s; assumed)
const DOOR_OUT := 0.07                      # m the leaves move out before sliding
const FAR := 160.0                          # m: beyond this only the cars' light shells are drawn
const INSIDE := 70.0                        # m: interiors (seats, poles) drawn within this
const HOLD := 0.35                          # m around a doorway in which a player holds its doors open
const BEAM_RANGE := 120.0                   # m, the head lamp beam at night
const BEAM_ENERGY := 10.0
const CABIN_RANGE := 7.0                    # m, each car's cabin light at night
const CABIN_LIGHTS_NEAR := 150.0            # m: cars farther from the camera have no cabin light
const DESTINATIONS := {"eastbound": "Aéroport CDG 2", "westbound": "St-Rémy-lès-Chevreuse"}   # the B4 branch's
const DISPLAY_AMBER := Color(1.0, 0.62, 0.15)
const FLANGE_RADIUS := 400.0                # m: tighter curves make the flanges squeal at speed
const COMPRESSOR_AFTER := 6.0               # s standing before the air compressor starts

static var night := false                   # scripts/night.gd: head lamp beams and cabin lights
static var _scene: PackedScene
static var _layout: Dictionary

var service: Dictionary                     # rail.json services entry
var net_id := ""
var front := 0.0                            # m along the route: the front coupler
var speed := 0.0                            # m/s along the route (never negative)
var doors_side := 0                         # the side the doors are on: 1 left, -1 right (seen by the train), 0 none
var doors_open := false                     # wanted open (door_t runs towards it)
var door_t := 0.0                           # 0 shut .. 1 open
var horn := false
var braking := 0.0                          # 0 .. 1, the brakes' share (sound, net)
var traction := 0.0                         # 0 .. 1, the motors' share (sound, net)
var stowed := false                         # waiting off the map: hidden, no collision
var remote := false                         # posed from another peer's states (net.gd)
var pilot: Object                           # scripts/train_bot.gd on the peer simulating it, or null
var cars: Array = []                        # TrainCar, from the front
var car_length := 26.0
var length := 208.0                         # m over the couplers
var audio: VehicleAudio

var _pts := PackedVector3Array()            # route, Godot positions every `_step` m (rail level at the track centre)
var _roll := PackedFloat32Array()           # cant angle, positive: the left rail (seen by the train) higher
var _step := 1.0
var _gangways: Array = []                   # [StaticBody3D, car in front, car behind]
var _beam: SpotLight3D
var _posed_front := NAN                     # front when last posed: a standing train is not posed again
var pose_every := 1                         # ticks between poses while it moves (train_traffic.gd: far from everyone)
var _pose_wait := 0
var _squealed := false
var _heading := PackedFloat32Array()        # route heading per point, unwrapped (curvature for the flange squeal)
var _joints := PackedFloat32Array()         # route distances of the insulated rail joints (the block signals)
var _rail_fx: AudioStreamPlayer3D
var _flanged := false
var _bogie_last := {}
var _stood := 0.0
var _compressed := false


## The cars of a train, from its layout: [kind, turned round] from the front.
static func formation() -> Array:
	var out := []
	for u in UNITS:
		out.append_array([["cab", false], ["mid", false], ["mid", false], ["cab", true]])
	return out


static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	return _layout


## Builds the train for `svc` (rail.json services entry). Call before adding it to the tree.
func setup(svc: Dictionary, id: String) -> void:
	service = svc
	net_id = id
	name = id.replace(":", "_")
	_step = svc["step"]
	for p: Array in svc["pts"]:
		_pts.append(Vector3(p[0], p[2], -p[1]))
	for r in svc["roll"]:
		_roll.append(r)
	var prev := 0.0
	for h in svc["heading"]:
		var hv := float(h)
		if not _heading.is_empty():
			hv = prev + wrapf(hv - prev, -PI, PI)
		_heading.append(hv)
		prev = hv
	for b in svc.get("blocks", []):
		_joints.append(b)
	if _scene == null:
		_scene = load(MODEL)
	var lay := layout()
	car_length = lay["car_length"]
	var f := formation()
	length = car_length * f.size()
	for k in f.size():
		var car := TrainCar.new()
		car.setup(self, k, f[k][0], f[k][1], lay[f[k][0]], _scene)
		add_child(car)
		cars.append(car)
	# gangways between the cars of a unit (not between the units: cabs there)
	for k in f.size() - 1:
		if f[k][0] == "cab" and f[k][1]:
			continue
		_gangways.append([_gangway_body(lay), cars[k], cars[k + 1]])
	cars[0].set_lamps(true, false)
	cars[-1].set_lamps(false, true)
	for k in range(1, cars.size() - 1):
		cars[k].set_lamps(false, false)
	var dest: String = DESTINATIONS.get(svc.get("direction", ""), "")
	cars[0].set_display(dest)
	cars[-1].set_display(dest)
	audio = VehicleAudio.new()
	audio.setup("train")
	audio.engine_on = true
	add_child(audio)
	_rail_fx = AudioStreamPlayer3D.new()
	_rail_fx.unit_size = 12.0
	_rail_fx.max_distance = 120.0
	add_child(_rail_fx)
	_beam = SpotLight3D.new()
	_beam.spot_range = BEAM_RANGE
	_beam.spot_angle = 18.0
	_beam.light_energy = BEAM_ENERGY
	_beam.light_color = Color(1.0, 0.95, 0.85)
	_beam.distance_fade_enabled = true
	_beam.distance_fade_begin = 250.0
	_beam.visible = false
	cars[0].add_child(_beam)
	_beam.position = Vector3(0.0, 1.6, car_length * 0.5)
	_beam.rotation = Vector3(0.0, PI, 0.0)          # its -Z forwards (the car's +Z)


func _gangway_body(lay: Dictionary) -> StaticBody3D:
	var g: Dictionary = lay["mid"]["gangways"]
	var w: float = g["width"]
	var h: float = g["height"]
	var floor_y: float = lay["mid"]["floor_y"]
	var gap := car_length - (float(lay["mid"]["body"][1]) - float(lay["mid"]["body"][0])) + 0.3
	var body := StaticBody3D.new()
	body.collision_layer = Layers.VEHICLE_INSIDE
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "train", "id": net_id, "part": "gangway"})
	for b: Array in [[Vector3(0.0, floor_y - 0.1, 0.0), Vector3(w + 0.4, 0.2, gap)],
			[Vector3(w * 0.5 + 0.05, floor_y + h * 0.5, 0.0), Vector3(0.1, h, gap)],
			[Vector3(-w * 0.5 - 0.05, floor_y + h * 0.5, 0.0), Vector3(0.1, h, gap)],
			[Vector3(0.0, floor_y + h + 0.05, 0.0), Vector3(w + 0.2, 0.1, gap)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[1]
		cs.shape = box
		cs.position = b[0]
		body.add_child(cs)
	add_child(body)
	return body


# ---------------------------------------------------------------- the route

## Godot position on the route at distance d (clamped to it).
func route_point(d: float) -> Vector3:
	var f := clampf(d / _step, 0.0, _pts.size() - 1.000001)
	var i := floori(f)
	return _pts[i].lerp(_pts[i + 1], f - i)


func route_roll(d: float) -> float:
	var f := clampf(d / _step, 0.0, _roll.size() - 1.000001)
	var i := floori(f)
	return lerpf(_roll[i], _roll[i + 1], f - i)


func route_length() -> float:
	return (_pts.size() - 1) * _step


## A frame on the route between distances a (behind) and b (ahead): origin midway at rail level, +Z towards b, +X to the
## left, tilted by the cant; turned round when `back`.
func span_frame(a: float, b: float, back := false) -> Transform3D:
	var pa := route_point(a)
	var pb := route_point(b)
	var z := pb - pa
	if z.length_squared() < 1e-8:
		z = Vector3.FORWARD
	z = z.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var basis := Basis(x, y, z).rotated(z, route_roll((a + b) * 0.5))
	if back:
		basis = basis.rotated(basis.y, PI)
	return Transform3D(basis.orthonormalized(), (pa + pb) * 0.5)


## Poses every car, bogie and gangway from `front`.
func pose() -> void:
	var b: float = cars[0].bogie_offset
	for car: TrainCar in cars:
		var c := front - car_length * (car.index + 0.5)
		car.global_transform = span_frame(c - b, c + b, car.turned)
		car.pose_bogies(c)
	for g: Array in _gangways:
		var ahead: TrainCar = g[1]
		var behind: TrainCar = g[2]
		var d := front - car_length * (ahead.index + 1)
		(g[0] as StaticBody3D).global_transform = span_frame(d - 0.5, d + 0.5)
	_posed_front = front


## Moves the train to put its front at d.
func place(d: float) -> void:
	front = d
	pose()


# ---------------------------------------------------------------- doors, lamps, carrying

## Opens (on `side`: 1 left, -1 right, seen by the train) or shuts the doors.
func set_doors(open: bool, side := 0) -> void:
	if open and side != 0:
		doors_side = side
	if open and not doors_open and audio:
		audio.play("train_open")
	doors_open = open


## The door warning before they shut (the bot calls it CHIME s before closing).
func chime() -> void:
	if audio:
		audio.play("train_doors")


## True while a player (this peer's or another's, `bodies`: global positions) stands in a doorway of the open side.
func door_blocked(bodies: Array) -> bool:
	if doors_side == 0 or door_t <= 0.0:
		return false
	for car: TrainCar in cars:
		for p: Vector3 in bodies:
			if car.in_doorway(p, doors_side * (-1 if car.turned else 1)):
				return true
	return false


## The car whose walkable interior contains `p` (global), or null.
func carrier_at(p: Vector3, margin := 0.0) -> Node3D:
	if stowed:
		return null
	if cars.is_empty() or p.distance_to((cars[0].global_position + cars[-1].global_position) * 0.5) > length * 0.5 + 30.0:
		return null
	for car: TrainCar in cars:
		if car.carries(p, margin):
			return car
	return null


## Riders standing in it (global positions in `bodies`).
func carries_any(bodies: Array) -> bool:
	for p: Vector3 in bodies:
		if carrier_at(p, 0.2):
			return true
	return false


func velocity() -> Vector3:
	return cars[0].global_basis.z * speed if not cars.is_empty() else Vector3.ZERO


func set_stowed(on: bool) -> void:
	stowed = on
	visible = not on
	_posed_front = NAN
	for car: TrainCar in cars:
		car.set_solid(not on)
	for g: Array in _gangways:
		(g[0] as StaticBody3D).collision_layer = 0 if on else Layers.VEHICLE_INSIDE
	if on:
		speed = 0.0
		horn = false
		set_doors(false)
		door_t = 0.0
		for car: TrainCar in cars:
			car.pose_doors(0.0, 0)


## The destination on the end cabs' displays.
func set_destination(text: String) -> void:
	cars[0].set_display(text)
	cars[-1].set_display(text)


# ---------------------------------------------------------------- LAN

## [front, speed, doors (side + 1, + 4 while wanted open), door_t, flags (1 horn, 2 stowed), braking, traction]
func net_state() -> Array:
	var doors := doors_side + 1 + (4 if doors_open else 0)
	return [snappedf(front, 0.001), snappedf(speed, 0.001), doors, snappedf(door_t, 0.01),
			(1 if horn else 0) | (2 if stowed else 0), snappedf(braking, 0.01), snappedf(traction, 0.01)]


## A state from the peer simulating it (net.gd), `late` s old on its clock: the front carried on at the speed.
func apply_net_state(s: Array, late: float) -> void:
	var was_stowed := stowed
	var st: bool = int(s[4]) & 2 != 0
	if st != was_stowed:
		set_stowed(st)
	speed = s[1]
	front = float(s[0]) + speed * maxf(late, 0.0)
	doors_side = (int(s[2]) & 3) - 1
	doors_open = int(s[2]) & 4 != 0
	door_t = s[3]
	horn = int(s[4]) & 1 != 0
	braking = s[5]
	traction = s[6]


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	if stowed:
		return
	if remote:
		front += speed * delta              # between two states: on at the speed (net.gd snaps it back)
	var target := 1.0 if doors_open else 0.0
	if door_t != target:
		door_t = move_toward(door_t, target, delta / DOOR_TIME)
		for car: TrainCar in cars:
			car.pose_doors(door_t, doors_side * (-1 if car.turned else 1))
	if front != _posed_front:
		_pose_wait += 1
		if _pose_wait >= pose_every:
			_pose_wait = 0
			pose()


func _process(delta: float) -> void:
	if stowed or cars.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# the sound comes from the car nearest the camera, the cabin lights only near
	var p := cam.global_position
	var nearest: TrainCar = cars[0]
	var best := INF
	for car: TrainCar in cars:
		var d := car.global_position.distance_squared_to(p)
		if d < best:
			best = d
			nearest = car
	audio.global_position = nearest.global_position + Vector3.UP * 1.5
	audio.horn = horn
	audio.update(speed, traction, 25.0, delta)
	if speed < 2.5 and speed > 0.3 and braking > 0.1 and not _squealed:
		_squealed = true                    # the shoes squeal in the last metres of a stop
		audio.play("train_brake")
	elif speed > 4.0:
		_squealed = false
	_rail_sounds(nearest, delta, best < VehicleAudio.HEARD * VehicleAudio.HEARD)
	_beam.visible = night
	for car: TrainCar in cars:
		car.set_cabin_light(night and car.global_position.distance_to(p) < CABIN_LIGHTS_NEAR)


## The rails' own sounds, from the car nearest the camera: the flanges squealing through a curve tighter than
## FLANGE_RADIUS at speed, the wheels knocking over the insulated rail joints at the block signals, the compressor
## once a stop.
func _rail_sounds(car: TrainCar, delta: float, heard: bool) -> void:
	if not heard:
		return
	var curve := absf(route_heading(front + 1.0) - route_heading(front - 1.0)) / 2.0     # 1/m at the front
	if curve > 1.0 / FLANGE_RADIUS and speed > 6.0 and not _flanged:
		_flanged = true
		_play_rail("train_flange")
	elif curve < 1.0 / (FLANGE_RADIUS * 1.5):
		_flanged = false
	var c := front - car_length * (car.index + 0.5)
	for side: float in [-1.0, 1.0]:
		var d := c + side * car.bogie_offset
		var was: float = _bogie_last.get(side, d)
		for j in _joints:
			if (was < j and d >= j) or (was > j and d <= j):
				_play_rail("train_joint")
		_bogie_last[side] = d
	if speed < 0.01:
		_stood += delta
		if _stood > COMPRESSOR_AFTER and not _compressed:
			_compressed = true
			_play_rail("train_compressor")
	else:
		_stood = 0.0
		_compressed = false


func _play_rail(sound: String) -> void:
	_rail_fx.global_position = audio.global_position + Vector3.DOWN * 1.2
	_rail_fx.stream = VehicleAudio.one_shot(sound)
	_rail_fx.play()


## Route heading at d (radians, unwrapped along the route).
func route_heading(d: float) -> float:
	var f := clampf(d / _step, 0.0, _heading.size() - 1.000001)
	var i := floori(f)
	return lerpf(_heading[i], _heading[i + 1], f - i)


# ---------------------------------------------------------------- one car

class TrainCar extends Node3D:
	var train: Node3D                       # the train (train.gd)
	var index := 0                          # from the front
	var kind := "mid"
	var turned := false                     # its front (+Z) towards the train's rear
	var bogie_offset := 9.55                # m from the middle to each bogie pivot
	var interior := AABB()                  # walkable volume, car frame
	var hull: StaticBody3D
	var shell: AnimatableBody3D
	var _bogies: Array = []                 # [Node3D, z in the car frame]
	var _doors := {"left": [], "right": []} # side -> [{leaves: [Node3D], closed: [Vector3], dirs: [z sign], key, shape}]
	var _door_boxes := {}                   # door key ("0_l") -> CollisionShape3D
	var _head: Node3D
	var _tail: Node3D
	var _display: Label3D
	var _light: OmniLight3D
	var _floor_y := 1.19

	func setup(t: Node3D, k: int, car_kind: String, back: bool, lay: Dictionary, scene: PackedScene) -> void:
		train = t
		index = k
		kind = car_kind
		turned = back
		name = "Car%d" % k
		_floor_y = lay["floor_y"]
		bogie_offset = absf(float(lay["bogies"][0]))
		var model := scene.instantiate()
		var nodes: Dictionary = lay["nodes"]
		var keep := {}
		for n in model.get_children():
			if String(n.name).begins_with(kind + "_"):
				keep[String(n.name)] = n
		for n: Node in keep.values():
			n.owner = null
			model.remove_child(n)
			add_child(n)
		model.free()
		for key: String in ["body", "interior", "far", "cabin_lights", "pantograph", "display", "head_lamps", "tail_lamps"]:
			var n := get_node_or_null(String(nodes.get(key, ""))) as GeometryInstance3D
			if n == null:
				continue
			match key:
				"far":
					n.visibility_range_begin = FAR
				"interior":
					n.visibility_range_end = INSIDE
					n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_:
					n.visibility_range_end = FAR
		for key: String in ["bogie_front", "bogie_rear"]:
			var b := get_node_or_null(String(nodes.get(key, ""))) as Node3D
			if b:
				(b as GeometryInstance3D).visibility_range_end = FAR
				_bogies.append([b, b.position.z])
		_head = get_node_or_null(String(nodes.get("head_lamps", ""))) as Node3D
		_tail = get_node_or_null(String(nodes.get("tail_lamps", ""))) as Node3D
		var lo: Array = lay["interior"][0]
		var hi: Array = lay["interior"][1]
		var a := Vector3(lo[0], lo[1], lo[2])
		var b2 := Vector3(hi[0], hi[1], hi[2])
		interior = AABB(a.min(b2), (b2 - a).abs())
		# the gangway ends reach into the gangway (walkable between the cars of a unit)
		var g: Dictionary = lay["gangways"]
		if g.get("rear", false):
			interior = interior.merge(AABB(Vector3(-0.45, interior.position.y, interior.position.z - 0.45), Vector3(0.9, interior.size.y, 0.5)))
		if g.get("front", false):
			interior = interior.merge(AABB(Vector3(-0.45, interior.position.y, interior.end.z - 0.05), Vector3(0.9, interior.size.y, 0.5)))
		hull = StaticBody3D.new()
		hull.name = "Hull"
		hull.collision_layer = Layers.VEHICLE_INSIDE
		hull.collision_mask = 0
		hull.set_meta("plateau", {"type": "train", "id": train.net_id, "car": k})
		add_child(hull)
		for c: Dictionary in lay["colliders"]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var sz: Array = c["size"]
			box.size = Vector3(sz[0], sz[1], sz[2]).max(Vector3.ONE * 0.02)
			cs.shape = box
			var ce: Array = c["center"]
			cs.position = Vector3(ce[0], ce[1], ce[2])
			hull.add_child(cs)
			if c.has("door"):
				_door_boxes[c["door"]] = cs
		var h0: Array = lay["hull"][0]
		var h1: Array = lay["hull"][1]
		var ha := Vector3(h0[0], h0[1], h0[2])
		var hb := Vector3(h1[0], h1[1], h1[2])
		shell = AnimatableBody3D.new()
		shell.name = "Shell"
		shell.sync_to_physics = false
		shell.collision_layer = Layers.VEHICLES
		shell.collision_mask = 0
		shell.set_meta("plateau", {"type": "train", "id": train.net_id, "car": k, "kind": kind})
		var scs := CollisionShape3D.new()
		var sbox := BoxShape3D.new()
		sbox.size = (hb - ha).abs()
		scs.shape = sbox
		scs.position = (ha + hb) * 0.5
		shell.add_child(scs)
		add_child(shell)
		for side: String in ["left", "right"]:
			for d: Dictionary in lay["doors"][side]:
				var leaves: Array = []
				var closed: Array = []
				var dirs: Array = []
				for ln: String in d["leaves"]:
					var leaf := get_node_or_null(ln) as Node3D
					if leaf == null:
						continue
					(leaf as GeometryInstance3D).visibility_range_end = FAR
					leaves.append(leaf)
					closed.append(leaf.position)
					dirs.append(1.0 if ln.ends_with("_a") else -1.0)      # leaf a is the front one (+Z)
				_doors[side].append({"leaves": leaves, "closed": closed, "dirs": dirs, "key": d["key"],
						"center": Vector3(d["center"][0], d["center"][1], d["center"][2]), "width": float(d["width"])})
		if lay.has("cab"):
			var disp: Array = lay["cab"]["display"]
			_display = Label3D.new()
			_display.pixel_size = 0.0025
			_display.font_size = 48
			_display.modulate = DISPLAY_AMBER
			_display.outline_size = 0
			_display.shaded = false
			_display.double_sided = false
			_display.position = Vector3(disp[0], disp[1], float(disp[2]) + 0.03)
			_display.visibility_range_end = 90.0
			add_child(_display)
		_light = OmniLight3D.new()
		_light.omni_range = CABIN_RANGE
		_light.light_energy = 1.2
		_light.light_color = Color(0.9, 0.95, 1.0)
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, _floor_y + 1.9, 0.0)
		_light.visible = false
		add_child(_light)

	## Poses this car's bogies for its middle at route distance c: each pivot on the route, turned to it.
	func pose_bogies(c: float) -> void:
		for b: Array in _bogies:
			var z: float = b[1]
			var d := c + (-z if turned else z)
			(b[0] as Node3D).global_transform = train.span_frame(d - 1.2, d + 1.2, turned)

	## Door leaves at opening t on car side `side` (1 left, -1 right: this car's own sides).
	func pose_doors(t: float, side: int) -> void:
		var out_t := clampf(t / 0.25, 0.0, 1.0)
		var slide_t := clampf((t - 0.2) / 0.8, 0.0, 1.0)
		for s: String in ["left", "right"]:
			var sx := 1.0 if s == "left" else -1.0
			var open_here := (side == 1 and s == "left") or (side == -1 and s == "right")
			for d: Dictionary in _doors[s]:
				var leaves: Array = d["leaves"]
				for i in leaves.size():
					var leaf: Node3D = leaves[i]
					var p: Vector3 = d["closed"][i]
					if open_here:
						p += Vector3(sx * DOOR_OUT * out_t, 0.0, float(d["dirs"][i]) * float(d["width"]) * 0.5 * slide_t)
					leaf.position = p
				var cs: CollisionShape3D = _door_boxes.get(d["key"])
				if cs:
					cs.disabled = open_here and t > 0.4

	## True when global p is in a doorway of car side `side` (1 left, -1 right), within HOLD.
	func in_doorway(p: Vector3, side: int) -> bool:
		var l := to_local(p)
		var s := "left" if side == 1 else "right"
		for d: Dictionary in _doors[s]:
			var c: Vector3 = d["center"]
			if absf(l.z - c.z) < float(d["width"]) * 0.5 + HOLD and absf(l.x - c.x) < 0.45 + HOLD and l.y > c.y - 0.6 and l.y < c.y + 2.2:
				return true
		return false

	func carries(p: Vector3, margin := 0.0) -> bool:
		return not train.stowed and interior.grow(margin).has_point(to_local(p))

	func velocity_at(_p: Vector3) -> Vector3:
		return train.velocity()

	func set_lamps(head: bool, tail: bool) -> void:
		if _head:
			_head.visible = head
		if _tail:
			_tail.visible = tail

	func set_display(text: String) -> void:
		if _display:
			_display.text = text
			_display.visible = text != ""

	func set_cabin_light(on: bool) -> void:
		_light.visible = on

	func set_solid(on: bool) -> void:
		hull.collision_layer = Layers.VEHICLE_INSIDE if on else 0
		shell.collision_layer = Layers.VEHICLES if on else 0
