extends Node3D
## A bot driver pulled out of their car by a carjacker (scripts/carjack/carjack.gd makes one on every peer that shows the
## game when a car is stolen): a toy figure in the bots' uniform (car.gd BOT_COLOR) who gets out of the driver's door
## (OUT s), runs off back along the road for RUN_TIME s crying out (a speech bubble), then stands there; once STAY s
## have gone by and no player or camera is within LEAVE_SEEN m (or after GONE s whatever), they leave the map.
## A walker for the bots (scripts/traffic/perception.gd): they stop for them, run them over if they run out too close.
## Nothing collides with them; they follow the ground (WorldQuery, the terrain and the buildings' roofs under them).

const Car = preload("res://scripts/car.gd")
const Kit = preload("res://scripts/build_kit.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Perception = preload("res://scripts/traffic/perception.gd")

const OUT := 0.8                            # s getting out (stepping 1.2 m out from the door)
const RUN := 4.5                            # m/s
const RUN_TIME := 5.0                       # s running off
const STAY := 15.0                          # s at least on the map...
const LEAVE_SEEN := 60.0                    # ...then gone once no player or camera is this close
const GONE := 120.0                         # s, gone whatever
const SKIN := Color(0.93, 0.74, 0.6)
const CRIES := ["Au voleur !", "Ma voiture !", "Hé ! Revenez !", "Police ! Police !", "Arrêtez-le !"]

var game: Node3D                            # game.gd

var _t := 0.0
var _from := Vector3.ZERO                   # by the driver's door
var _out := Vector3.ZERO                    # the step out
var _dir := Vector3.ZERO                    # running off (flat, unit)
var _speed := 0.0
var _phase := 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _bubble: Label3D


## Out of `car`'s driver's door (its left, +X); `seed` the same on every peer (where they run, what they cry).
func setup(game_node: Node3D, car: Node3D, seed: int) -> void:
	game = game_node
	name = "EjectedDriver"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var seat: Vector3 = car.driver_seat if car.driver_seat != Vector3.ZERO else car.extents_center
	_from = car.to_global(Vector3(car.half_extents.x + 0.3, 0.0, seat.z))
	var left: Vector3 = car.global_basis.x
	var back: Vector3 = -car.global_basis.z
	left.y = 0.0
	back.y = 0.0
	_out = left.normalized() * 1.2
	_dir = (back.normalized() * 0.8 + left.normalized() * rng.randf_range(0.3, 0.7)).normalized()
	_build_body()
	_bubble.text = CRIES[rng.randi() % CRIES.size()]
	add_to_group(Perception.GROUP)
	set_meta("plateau", {"type": "npc", "id": "driver of a stolen %s" % car.model_name})


func _ready() -> void:
	global_position = _ground(_from)
	_body.rotation.y = atan2(_out.x, _out.z)


## For the bots (perception.gd): always on foot.
func walking() -> bool:
	return true


func _process(delta: float) -> void:
	_t += delta
	var p := global_position
	if _t < OUT:
		p = _from + _out * (_t / OUT)
		_speed = 1.5
		_face(_out)
	elif _t < OUT + RUN_TIME:
		p += _dir * RUN * delta
		_speed = RUN
		_face(_dir)
		_bubble.visible = true
	else:
		_speed = 0.0
		_bubble.visible = _t < OUT + RUN_TIME + 2.0
	global_position = _ground(p) if _speed > 0.0 else global_position
	_animate(delta)
	if _t > GONE or (_t > STAY and not _seen()):
		queue_free()


## `p` put on the ground under it (as it is where there is none).
func _ground(p: Vector3) -> Vector3:
	var y := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, p.y + 2.0) if is_inside_tree() else NAN
	return Vector3(p.x, y, p.z) if not is_nan(y) else p


func _seen() -> bool:
	var eyes: Array = game.player_spots() if game else []
	var cam := get_viewport().get_camera_3d()
	if cam:
		eyes.append(cam.global_position)
	for q: Vector3 in eyes:
		if Vector2(q.x - global_position.x, q.z - global_position.z).length() < LEAVE_SEEN:
			return true
	return false


func _face(d: Vector3) -> void:
	if d.length_squared() > 1e-4:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(d.x, d.z), 0.25)


func _animate(delta: float) -> void:
	var swing := clampf(_speed / 2.0, 0.0, 1.6)
	_phase += delta * (2.0 + 4.0 * swing) if swing > 0.0 else 0.0
	var s := sin(_phase) * 0.55 * minf(swing, 1.0)
	_legs[0].rotation.x = s
	_legs[1].rotation.x = -s
	if _t < OUT + RUN_TIME and _t > OUT:
		# arms up, waving, crying out
		for k in 2:
			_arms[k].rotation.x = lerpf(_arms[k].rotation.x, -2.6 + sin(_phase * 1.3 + k) * 0.35, minf(8.0 * delta, 1.0))
	else:
		_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -s * 0.8, minf(8.0 * delta, 1.0))
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, s * 0.8, minf(8.0 * delta, 1.0))
	_body.position.y = absf(cos(_phase)) * 0.05 * minf(swing, 1.0)


# ---------------------------------------------------------------- body

## Front +Z, feet on y = 0, 1.8 m tall: the bots' uniform (trousers, jacket, cap) of car.gd's BOT_COLOR.
func _build_body() -> void:
	var uniform := Kit.plain(Car.BOT_COLOR, 0.5)
	var dark := Kit.plain(Car.BOT_COLOR.darkened(0.35), 0.5)
	var skin := Kit.plain(SKIN, 0.55)
	var shoe := Kit.plain(Color(0.03, 0.03, 0.03), 0.2)
	var shirt := Kit.plain(Color(0.92, 0.94, 0.97), 0.5)
	_body = Node3D.new()
	add_child(_body)
	for side: float in [1.0, -1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0.93, 0.0)
		_body.add_child(hip)
		_part(hip, _cylinder(0.075, 0.09, 0.84), dark, Vector3(0.0, -0.44, 0.0))
		_part(hip, _box(Vector3(0.11, 0.07, 0.26)), shoe, Vector3(0.0, -0.88, 0.05))
		_legs.append(hip)
	_part(_body, _cylinder(0.23, 0.2, 0.62), uniform, Vector3(0.0, 1.25, 0.0), Vector3(1.0, 1.0, 0.62))
	_part(_body, _box(Vector3(0.11, 0.22, 0.02)), shirt, Vector3(0.0, 1.46, 0.135))
	for side: float in [1.0, -1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.26, 1.53, 0.0)
		_body.add_child(shoulder)
		_part(shoulder, _capsule(0.06, 0.62), uniform, Vector3(0.0, -0.28, 0.0))
		_part(shoulder, _sphere(0.055), skin, Vector3(0.0, -0.62, 0.0))
		_arms.append(shoulder)
	_part(_body, _capsule(0.055, 0.15), skin, Vector3(0.0, 1.64, 0.0))
	_part(_body, _sphere(0.135), skin, Vector3(0.0, 1.77, 0.0), Vector3(1.0, 1.08, 1.0))
	_part(_body, _cylinder(0.14, 0.145, 0.07), uniform, Vector3(0.0, 1.88, 0.0))        # the cap
	_part(_body, _box(Vector3(0.2, 0.02, 0.1)), dark, Vector3(0.0, 1.85, 0.15))         # its peak
	_bubble = Label3D.new()
	_bubble.position = Vector3(0.0, 2.3, 0.0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 34
	_bubble.pixel_size = 0.0042
	_bubble.outline_size = 12
	_bubble.outline_modulate = Color(0.05, 0.03, 0.0)
	_bubble.modulate = Color(1.0, 0.95, 0.82)
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale_ := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 3
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
