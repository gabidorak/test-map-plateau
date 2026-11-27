extends CharacterBody3D
## A police officer out of their car (scripts/police/foot/arrest.gd makes one on every peer when they get out, and takes it
## away when they are back in): a toy figure in the police's navy blue (scripts/people/figure.gd), their weapon in the
## right hand (the taser yellow, the net gun orange), raised while they aim.
## - The host moves them (go_to: towards a point, running or walking; stop) as Escape from Plateau's zombies go
##   (scripts/escape/zombie.gd): a body sliding along what stands in the way (the walls, the cars, the hedges, the street
##   furniture), turned aside a moment (AVOID) when it stops them; how long since they last got nearer where they go
##   (stuck_time) tells arrest.gd when it cannot be reached. Nothing collides with them. The others follow the host's
##   states (state / apply_state), eased.
## - A person (scripts/people/person.gd) "o:<unit>": a player may stun them (they lie down); they carry people
##   (people.gd register_carrier, as handle -1 - unit). A walker for the bots (scripts/traffic/perception.gd).

const Figure = preload("res://scripts/people/figure.gd")
const Person = preload("res://scripts/people/person.gd")
const Perception = preload("res://scripts/traffic/perception.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Layers = preload("res://scripts/physics_layers.gd")

const RUN := 5.0                            # m/s
const WALK := 1.6
const NAVY := Color(0.08, 0.13, 0.28)
const TROUSERS := Color(0.06, 0.09, 0.2)
const SHIRT := Color(0.62, 0.74, 0.9)
const PEAK := Color(0.03, 0.03, 0.05)
const WEAPON_COLOR := {"taser": Color(0.95, 0.76, 0.19), "net_gun": Color(0.88, 0.48, 0.16)}
const ACCEL := 14.0                         # m/s² towards the speed they want
const AVOID := Vector2(0.8, 1.6)            # s turned aside (AVOID_ANGLE rad) once something stops them
const AVOID_ANGLE := 1.15
const NEARER := 0.4                         # m nearer where they go that counts as headway
const STEP_UP := 0.55                       # m above their feet the ground they are put on may be
const TURN := 12.0                          # /s their body turns to their way
const EASE := 12.0                          # /s the others' copies close on the host's states

var unit := 0
var person_id := ""
var weapon := "taser":                      # in hand ("": none)
	set(k):
		weapon = k
		_show_weapon()
var aiming := false
var hosting := true                         # the host moves them; the others follow its states
var speed := 0.0                            # m/s now (the stride)
var yaw := 0.0                              # their facing (rad about Y)

var _down := false
var _carry_body: Node3D
var _fig := {}
var _phase := 0.0
var _goal := Vector3.ZERO
var _goal_speed := 0.0
var _stop_at := 0.0                         # m short of the goal they stop
var _going := false
var _avoid_t := 0.0                         # s still turned aside...
var _avoid_side := 1.0                      # ...this way (1 left)
var _slow_t := 0.0                          # s going much slower than they want
var _best := INF                            # m: the nearest they got to where they go...
var _best_t := 0.0                          # ...this many s ago
var _rng := RandomNumberGenerator.new()
var _net_pos := Vector3.ZERO                # the others: where the host has them
var _net_yaw := 0.0
var _net_seen := false
var _gun: MeshInstance3D
var _gun_mat: StandardMaterial3D


func setup(n: int, pos: Vector3, facing: float, host: bool) -> void:
	unit = n
	hosting = host
	person_id = "o:%d" % n
	name = "Officer%d" % n
	_rng.seed = n
	collision_layer = 0                     # (nothing collides with them)
	collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.PROPS | Layers.VEGETATION | Layers.VEHICLES if host else 0
	floor_max_angle = 0.9
	floor_snap_length = 0.6
	safe_margin = 0.02
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0.0, 0.875, 0.0)
	add_child(shape)
	_fig = Figure.build(self, NAVY, TROUSERS, SHIRT, PEAK)
	var band := Figure.part(_fig["body"], Figure.cylinder(0.146, 0.146, 0.025), _plain(Color(0.85, 0.85, 0.88)),
			Vector3(0.0, 1.86, 0.0))
	band.name = "CapBand"
	_gun_mat = _plain(WEAPON_COLOR["taser"])
	_gun = Figure.part(_fig["arms"][1], Figure.box(Vector3(0.05, 0.2, 0.09)), _gun_mat, Vector3(0.0, -0.7, 0.04))
	_show_weapon()
	yaw = facing
	position = pos
	_net_pos = pos
	_net_yaw = facing
	add_to_group(Perception.GROUP)
	add_to_group(Person.GROUP)
	set_meta("plateau", {"type": "npc", "id": "police officer %d" % n})


func _ready() -> void:
	global_position = _ground(global_position)
	_fig["body"].rotation.y = yaw


## For the bots (perception.gd): always on foot.
func walking() -> bool:
	return true


# ---------------------------------------------------------------- the host moves them

## Towards `p` at `pace` m/s, stopping `short` m from it.
func go_to(p: Vector3, pace: float, short := 0.3) -> void:
	if p.distance_to(_goal) > 2.0 or not _going:
		_best = INF                         # (somewhere else: the headway counts afresh)
		_best_t = 0.0
	_goal = p
	_goal_speed = pace
	_stop_at = short
	_going = true


func stop() -> void:
	_going = false
	_best_t = 0.0


## s since they last got nearer where they go (0 standing).
func stuck_time() -> float:
	return _best_t if _going else 0.0


## Faces `p` (standing).
func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length_squared() > 0.01:
		yaw = atan2(d.x, d.z)


## Whether they stand within `d` m of where they go.
func there(d := 0.5) -> bool:
	var to := _goal - global_position
	return Vector2(to.x, to.z).length() <= _stop_at + d


## Where their shot leaves from: the weapon's muzzle.
func muzzle() -> Vector3:
	return _gun.to_global(Vector3(0.0, -0.1, 0.0)) if _gun else global_position + Vector3.UP * 1.4


func _physics_process(delta: float) -> void:
	if not hosting:
		return
	var want := Vector3.ZERO
	if _going and not _down and _carry_body == null:
		var to := _goal - global_position
		to.y = 0.0
		var d := to.length()
		if d > _stop_at:
			want = to / d * minf(_goal_speed, (d - _stop_at) / maxf(delta, 0.001))
			if _avoid_t > 0.0:
				_avoid_t -= delta
				want = want.rotated(Vector3.UP, _avoid_side * AVOID_ANGLE)
		if d < _best - NEARER:
			_best = d
			_best_t = 0.0
		else:
			_best_t += delta
	if _down or _carry_body:
		velocity = Vector3.ZERO
		speed = 0.0
		return
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2(want.x, want.z), ACCEL * delta)
	velocity.x = h.x
	velocity.z = h.y
	velocity.y = -1.0 if is_on_floor() else velocity.y - 9.8 * delta
	var start := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - start.x, global_position.z - start.z).length() / maxf(delta, 0.001)
	speed = moved
	if want.length() > 0.5 and moved < want.length() * 0.3:
		_slow_t += delta
		if _slow_t > 0.5:                   # something stops them: aside a moment
			_slow_t = 0.0
			_avoid_t = _rng.randf_range(AVOID.x, AVOID.y)
			_avoid_side = -_avoid_side if _rng.randf() < 0.6 else _avoid_side
	else:
		_slow_t = maxf(_slow_t - delta, 0.0)
	if Vector2(velocity.x, velocity.z).length_squared() > 0.04:
		yaw = atan2(velocity.x, velocity.z)


# ---------------------------------------------------------------- the others follow the host

## The host's state of them: [x, y, z, yaw, speed, flags (1 aiming, 2 the net gun in hand, 4 nothing in hand)].
func state() -> Array:
	var p := global_position
	return [p.x, p.y, p.z, yaw, speed, (1 if aiming else 0) | (2 if weapon == "net_gun" else 0) | (4 if weapon == "" else 0)]


func apply_state(a: Array) -> void:
	_net_pos = Vector3(a[0], a[1], a[2])
	_net_yaw = a[3]
	speed = a[4]
	var flags: int = a[5]
	aiming = flags & 1 != 0
	var k := "" if flags & 4 else ("net_gun" if flags & 2 else "taser")
	if k != weapon:
		weapon = k
	if not _net_seen:
		_net_seen = true
		global_position = _net_pos


# ---------------------------------------------------------------- looks

func _process(delta: float) -> void:
	if _carry_body:
		_follow_carry_body()
		return
	if not hosting:
		var k := 1.0 - exp(-EASE * delta)
		global_position = global_position.lerp(_net_pos, k)
		yaw = lerp_angle(yaw, _net_yaw, k)
	if _down:
		return
	var body: Node3D = _fig["body"]
	body.rotation.y = lerp_angle(body.rotation.y, yaw, minf(TURN * delta, 1.0))
	_phase = Figure.walk(_fig, _phase, speed, delta, aiming)
	if aiming:                              # the weapon at arm's length, the other hand under it
		var k := minf(10.0 * delta, 1.0)
		_fig["arms"][1].rotation.x = lerpf(_fig["arms"][1].rotation.x, -PI * 0.5, k)
		_fig["arms"][0].rotation.x = lerpf(_fig["arms"][0].rotation.x, -1.25, k)
		_fig["arms"][0].rotation.z = lerpf(_fig["arms"][0].rotation.z, -0.45, k)
	else:
		_fig["arms"][0].rotation.z = lerpf(_fig["arms"][0].rotation.z, 0.0, minf(10.0 * delta, 1.0))


func _show_weapon() -> void:
	if _gun:
		_gun.visible = weapon != ""
		_gun_mat.albedo_color = WEAPON_COLOR.get(weapon, WEAPON_COLOR["taser"])


static func _plain(c: Color) -> StandardMaterial3D:
	return Figure.Kit.plain(c, 0.5)


# ---------------------------------------------------------------- a person (scripts/people/person.gd)

func person_up() -> bool:
	return is_inside_tree() and visible and not _down and _carry_body == null


func person_body() -> Node3D:
	return _fig["body"]


func person_name() -> String:
	return "a police officer"


func person_carried() -> bool:
	return _carry_body != null


func set_down(on: bool) -> void:
	_down = on
	aiming = false
	_lie(on)


func carry_on(body: Node3D) -> void:
	_carry_body = body
	if body == null:
		_lie(_down)
	else:
		_follow_carry_body()


func put_at(pos: Vector3) -> void:
	global_position = _ground(pos)
	velocity = Vector3.ZERO
	_net_pos = global_position


func _lie(on: bool) -> void:
	var body: Node3D = _fig["body"]
	body.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5) if on
			else Basis(Vector3.UP, yaw), Vector3(0.0, 0.16 if on else 0.0, 0.0))


func _follow_carry_body() -> void:
	if not is_instance_valid(_carry_body) or not _carry_body.is_inside_tree():
		carry_on(null)
		return
	global_position = _carry_body.global_position
	(_fig["body"] as Node3D).global_transform = _carry_body.global_transform * Person.CARRY_POSE


## `p` put on the ground under it (as it is where there is none).
func _ground(p: Vector3) -> Vector3:
	var y := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, p.y + STEP_UP + 0.3) if is_inside_tree() \
			else NAN
	return Vector3(p.x, y, p.z) if not is_nan(y) else p
