extends Node3D
## A bot driver pulled out of their car by a carjacker (scripts/carjack/carjack.gd makes one on every peer that shows the
## game when a car is stolen): a toy figure in the bots' uniform (car.gd BOT_COLOR) who gets out of the driver's door
## (OUT s), runs off back along the road for RUN_TIME s crying out (a speech bubble), then stands there; once STAY s
## have gone by and no player or camera is within LEAVE_SEEN m (or after GONE s whatever), they leave the map.
## A walker for the bots (scripts/traffic/perception.gd): they stop for them, run them over if they run out too close.
## Nothing collides with them; they follow the ground (WorldQuery, the terrain and the buildings' roofs under them).
## A person (scripts/people/person.gd) ("n:<seed>", the same on every peer): stunned, they lie on the ground, their
## running and crying held until they are up again; carried, over the carrier's shoulders.

const Car = preload("res://scripts/car.gd")
const Figure = preload("res://scripts/people/figure.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Perception = preload("res://scripts/traffic/perception.gd")
const Person = preload("res://scripts/people/person.gd")

const OUT := 0.8                            # s getting out (stepping 1.2 m out from the door)
const RUN := 4.5                            # m/s
const RUN_TIME := 5.0                       # s running off
const STAY := 15.0                          # s at least on the map...
const LEAVE_SEEN := 60.0                    # ...then gone once no player or camera is this close
const GONE := 120.0                         # s, gone whatever
const CRIES := ["Au voleur !", "Ma voiture !", "Hé ! Revenez !", "Police ! Police !", "Arrêtez-le !"]

var game: Node3D                            # game.gd

var _t := 0.0
var _from := Vector3.ZERO                   # by the driver's door
var _out := Vector3.ZERO                    # the step out
var _dir := Vector3.ZERO                    # running off (flat, unit)
var _speed := 0.0
var _phase := 0.0
var _body: Node3D
var _fig := {}                              # figure.gd's joints
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _bubble: Label3D
var person_id := ""                         # people.gd: "n:<seed>"
var _down := false
var _carry_body: Node3D


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
	add_to_group(Person.GROUP)
	person_id = "n:%d" % seed
	set_meta("plateau", {"type": "npc", "id": "driver of a stolen %s" % car.model_name})


func _ready() -> void:
	global_position = _ground(_from)
	_body.rotation.y = atan2(_out.x, _out.z)


## For the bots (perception.gd): always on foot.
func walking() -> bool:
	return true


func _process(delta: float) -> void:
	if _carry_body:
		_follow_carry_body()
		return
	if _down:
		_body.position.y = 0.16
		return                              # (lying there: the time stands still for them)
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


# ---------------------------------------------------------------- a person (scripts/people/person.gd)

## Out of the car, standing: a shot may stun them.
func person_up() -> bool:
	return _t > OUT and not _down and _carry_body == null and is_inside_tree()


func person_body() -> Node3D:
	return _body


func person_name() -> String:
	return "the driver"


func person_carried() -> bool:
	return _carry_body != null


func set_down(on: bool) -> void:
	_down = on
	_bubble.visible = false
	_lie(on)


func carry_on(body: Node3D) -> void:
	_carry_body = body
	if body == null:
		_lie(_down)
	else:
		_follow_carry_body()


func put_at(pos: Vector3) -> void:
	global_position = _ground(pos)


func _lie(on: bool) -> void:
	_body.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) if on else Basis(Vector3.UP, _body.rotation.y),
			Vector3(0.0, 0.16 if on else 0.0, 0.0))


func _follow_carry_body() -> void:
	if not is_instance_valid(_carry_body) or not _carry_body.is_inside_tree():
		carry_on(null)
		return
	global_position = _carry_body.global_position
	_body.global_transform = _carry_body.global_transform * Person.CARRY_POSE


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
	var crying := _t < OUT + RUN_TIME and _t > OUT
	_phase = Figure.walk(_fig, _phase, _speed, delta, crying)
	if crying:                              # arms up, waving, crying out
		for k in 2:
			_arms[k].rotation.x = lerpf(_arms[k].rotation.x, -2.6 + sin(_phase * 1.3 + k) * 0.35, minf(8.0 * delta, 1.0))


# ---------------------------------------------------------------- body

## Front +Z, feet on y = 0, 1.8 m tall: the bots' uniform (trousers, jacket, cap) of car.gd's BOT_COLOR
## (scripts/people/figure.gd); a speech bubble over it.
func _build_body() -> void:
	var dark := Car.BOT_COLOR.darkened(0.35)
	_fig = Figure.build(self, Car.BOT_COLOR, dark, Color(0.92, 0.94, 0.97), dark)
	_body = _fig["body"]
	_legs.assign(_fig["legs"])
	_arms.assign(_fig["arms"])
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
