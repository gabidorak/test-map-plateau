extends RefCounted
## The police helicopter's pilot (scripts/police/police.gd gives the orders, on the host): it flies
## scripts/helicopter.gd by the player's own controls (fly: the cyclic, the tail rotor, the collective), the way
## car.gd's bot drivers drive (the vehicle's `pilot`).
## - Orders: search(p, r) circles round map point p (r m out, ORBIT by default), follow(p, v) keeps above someone (p,
##   going at v),
##   home() flies back to its base and puts it down there; `done` once it stands on it again (the police then let the
##   rotor wind down).
## - Down on its base: over it (OVER_PAD m) and slow, it sinks, holding its place; down once its skids stand on
##   something (or it barely moves a hand's breadth over it: a kerb under a skid), LAND_MAX s at most.
## - Flight: up from the base straight (CLEAR m) before it goes anywhere; then at CRUISE m above whatever is under it or
##   LOOK_AHEAD s ahead (roofs, trees, the hills), at most CRUISE_SPEED; it slows down to stop where it goes (BRAKE m/s²).
##   Each tick the speed it wants is turned into the tilt of the rotor (the cyclic: the nose down to go, a bank to
##   slide), its heading into the tail rotor's turn, its height into the collective.
## Positions are pipeline x/y (x east, y north; Godot = (x, -z)).

const Heli = preload("res://scripts/helicopter.gd")
const Layers = preload("res://scripts/physics_layers.gd")

enum { PARKED, TAKE_OFF, SEARCH, FOLLOW, HOME, LANDING }

const CRUISE := 60.0                        # m above the ground, the roofs and the trees, flying somewhere...
const FOLLOW_HEIGHT := 45.0                 # ...above someone it follows
const CLEAR := 22.0                         # m up from its base before it leaves it
const CRUISE_SPEED := 40.0                  # m/s (144 km/h)
const ORBIT := 90.0                         # m: the circle it searches round a place...
const ORBIT_SPEED := 18.0                   # ...at this speed
const BRAKE := 3.0                          # m/s²: the braking it plans for
const LOOK_AHEAD := 4.0                     # s ahead it measures the ground too
const SPEED_GAIN := 0.12                    # cyclic per m/s off the speed it wants
const TURN_GAIN := 1.6                      # tail rotor per rad off its heading
const HEIGHT_GAIN := 0.15                   # collective per m off its height
const OVER_PAD := 6.0                       # m from its base's spot it starts down...
const LAND_MAX := 30.0                      # ...and is down at the latest this many s later
const SETTLED := 1.0                        # m over what is under it, barely moving: down
const TOP_Y := Heli.CEILING - 45.0          # m (Godot y): it flies no higher (the lift fades above)
const PROBE_EVERY := 0.1                    # s between two looks at what is under it ahead

var heli: Heli
var order := PARKED
var done := false                           # back on its base (HOME)
var base := Vector2.ZERO                    # map xy of its base...
var base_yaw := 0.0                         # ...and its heading there (rad, Godot's: atan2(forward x, forward z))
var goal := Vector2.ZERO                    # map xy: where it searches round, whom it follows
var goal_v := Vector2.ZERO                  # the speed of whom it follows (map xy)
var _floor := -INF                          # Godot y of the highest thing under it or ahead, smoothed
var _sense := 1.0                           # the way it circles (1 anticlockwise)
var orbit := ORBIT                          # m out it circles (search)
var _next := SEARCH                         # what it does once up from its base
var _land_t := 0.0                          # s coming down
var _probe_t := 0.0                         # s before the next look at what is under it ahead...
var _ahead_y := -INF                        # ...what it found (Godot y, -INF nothing)
var _ray := PhysicsRayQueryParameters3D.new()

## what car.gd's and the bots' code reads of a pilot (scripts/traffic/bus_bot.gd, net.gd)
var gliding := false
var horn := false
var state := -1
var obstacle_car: Node3D = null
var _blocked_t := 0.0
var _speed := 0.0


func setup(h: Heli, base_xy: Vector2, yaw: float) -> void:
	heli = h
	base = base_xy
	base_yaw = yaw


## Circles round `p`; from its base, once up.
func search(p: Vector2, radius := ORBIT) -> void:
	orbit = radius
	goal = p
	goal_v = Vector2.ZERO
	_order(SEARCH)


## Keeps above `p`, going at `v`.
func follow(p: Vector2, v: Vector2) -> void:
	goal = p
	goal_v = v
	_order(FOLLOW)


## Back to its base and down on it.
func home() -> void:
	goal = base
	goal_v = Vector2.ZERO
	_order(HOME)


func flying() -> bool:
	return order != PARKED


func _order(o: int) -> void:
	done = order == PARKED and o == HOME
	if order == PARKED or order == TAKE_OFF:
		if order == PARKED and o != HOME:
			order = TAKE_OFF
			_floor = -INF
		_next = o
		return
	if o != order:
		if o == SEARCH:
			_sense = 1.0 if randf() < 0.5 else -1.0
		order = o


## The controls this tick (helicopter.gd): [nose up, bank left, turn left, collective], each -1..1.
func fly(delta: float) -> Array:
	var pos := Vector2(heli.global_position.x, -heli.global_position.z)
	var v := Vector2(heli.linear_velocity.x, -heli.linear_velocity.z)
	_speed = v.length()
	var ground_y := heli.global_position.y - heli.height
	match order:
		PARKED:
			return [0.0, 0.0, 0.0, -1.0]
		TAKE_OFF:
			if heli.rotor < 0.92:
				return [0.0, 0.0, 0.0, -1.0]    # (spooling up)
			if _floor == -INF:
				_floor = ground_y
			if heli.height < CLEAR:
				var hold := _steer(Vector2.ZERO, _fwd(), v)
				return [hold.x, hold.y, hold.z, 1.0]
			order = _next
			if order == SEARCH:
				_sense = 1.0 if randf() < 0.5 else -1.0
	var want := Vector2.ZERO
	var face := _fwd()
	var height := CRUISE
	match order:
		SEARCH:
			var rel := pos - goal
			var d := rel.length()
			if d > orbit * 1.6:
				want = _toward(goal, pos, CRUISE_SPEED, orbit)
			else:
				var out := rel / maxf(d, 0.1)
				var tangent := out.orthogonal() * -_sense
				want = tangent * ORBIT_SPEED * orbit / ORBIT + out * clampf((orbit - d) * 0.3, -12.0, 12.0)
		FOLLOW:
			height = FOLLOW_HEIGHT
			var lead := goal + goal_v * 1.0
			want = goal_v + (lead - pos) * 0.35
			want = want.limit_length(CRUISE_SPEED + 10.0)
			if want.length() < 4.0 and pos.distance_to(goal) > 3.0:
				face = (goal - pos).normalized()
		HOME:
			want = _toward(base, pos, CRUISE_SPEED, 0.0)
			if pos.distance_to(base) < OVER_PAD and _speed < 2.5:
				order = LANDING
				_land_t = 0.0
		LANDING:
			want = ((base - pos) * 0.9).limit_length(5.0)
			face = Vector2(sin(base_yaw), -cos(base_yaw))
	if want.length() > 3.0 and order != LANDING:
		face = want.normalized()
	var keys := _steer(want, face, v)
	var lift := 0.0
	if order == LANDING:
		lift = -1.0 if heli.height > 15.0 else (-0.5 if heli.height > 5.0 else -0.25)
		_land_t += delta
		if heli.on_ground or (heli.height < SETTLED and heli.linear_velocity.length() < 0.3) or _land_t > LAND_MAX:
			order = PARKED
			done = true
			return [0.0, 0.0, 0.0, -1.0]
	else:
		lift = clampf((_height_y(ground_y, pos, v, height, delta) - heli.global_position.y) * HEIGHT_GAIN, -1.0, 1.0)
	return [keys.x, keys.y, keys.z, lift]


## Its heading (map xy).
func _fwd() -> Vector2:
	var z := heli.global_basis.z
	var f := Vector2(z.x, -z.z)
	return f.normalized() if f.length_squared() > 0.0001 else Vector2.UP


## The speed (map xy) to go to `p` from `pos`, at most `top`, slowing down to stop `stop` m short of it.
func _toward(p: Vector2, pos: Vector2, top: float, stop: float) -> Vector2:
	var to := p - pos
	var d := maxf(to.length() - stop, 0.0)
	if to.length() < 0.5:
		return Vector2.ZERO
	return to.normalized() * minf(top, sqrt(2.0 * BRAKE * d))


## The cyclic and the tail rotor to fly at `want` (map xy, m/s) facing `face`, at `v` now: [nose up, bank left, turn
## left] (the nose down drives it forward, a bank sideways; +X is its left).
func _steer(want: Vector2, face: Vector2, v: Vector2) -> Vector3:
	var b := heli.global_basis
	var fwd := _fwd()
	var left := Vector2(b.x.x, -b.x.z).normalized()
	var dv := want - v
	return Vector3(clampf(-dv.dot(fwd) * SPEED_GAIN, -1.0, 1.0), clampf(dv.dot(left) * SPEED_GAIN, -1.0, 1.0),
			clampf(fwd.angle_to(face) * TURN_GAIN, -1.0, 1.0))


## The Godot y it should fly at: `above` m over the highest thing under it and LOOK_AHEAD s ahead (risen to at once,
## let down slowly), no higher than TOP_Y.
func _height_y(ground_y: float, pos: Vector2, v: Vector2, above: float, delta: float) -> float:
	_probe_t -= delta
	if _probe_t <= 0.0:                     # (what is ahead, PROBE_EVERY s apart: the smoothing below covers between)
		_probe_t = PROBE_EVERY
		var ahead := pos + v * LOOK_AHEAD
		var top := heli.global_position.y + 20.0
		_ray.from = Vector3(ahead.x, top + 200.0, -ahead.y)
		_ray.to = Vector3(ahead.x, -500.0, -ahead.y)
		_ray.collision_mask = Layers.SOLID | Layers.VEGETATION
		_ray.exclude = [heli.get_rid()]
		var hit := heli.get_world_3d().direct_space_state.intersect_ray(_ray)
		_ahead_y = float(hit["position"].y) if hit else -INF
	var high := maxf(ground_y, _ahead_y)
	_floor = high if high > _floor else move_toward(_floor, high, 4.0 * delta)
	return minf(_floor + above, TOP_Y)
