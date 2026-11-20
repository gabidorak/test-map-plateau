extends RefCounted
## A police car's driving off the lanes (police_driver.gd hands it the wheel on an urgent job near a player, with the
## physics): towards a point it is given (`aim`, with the speed wanted there), as fast as the grip allows, wherever there
## is room: the other lane, the pavement, the grass. It comes into contact when asked (`target`: the vehicle it means to
## hit is not in its way).
## - What is in the way (every LOOK_EVERY s), along the ways fanned round the aim's (ANGLES), nearest the aim's first:
##   the path it would take, turning as tightly as it can at its speed (the grip, the wheel's lock) from where it heads
##   onto that way (the arc in chords of ARC_STEP rad at most, then along the way), swept with a box as wide as the car and
##   SIDE_ROOM more each side (more the faster: SIDE_PER_SPEED), from the kerbs' height to above its roof (low branches),
##   NEAR m on; further, rays along its middle and both sides. Against what it must not hit: buildings, walls, fences,
##   posts, trees, hedges, vehicles, people, the map's edge; water too. The way picked is the one free furthest (as far
##   as it takes to stop: more room is worth no more), weighed with how far it turns from the aim and against changing
##   sides. Straight on is swept too: where it goes while it
##   turns.
## - The speed: the car's top speed (TOP of it), `limit` (the route's bends ahead), what the grip holds in the turn it
##   makes (GRIP; not on a `sharp` swerve, a PIT, which slides a little), what it can stop in (BRAKE, MARGIN short)
##   before what is in the way it picked, and before what is straight on while it still turns to that way (a crawl,
##   CRAWL, is left to turn while there is room); a way more than TIGHT rad off where it goes (turning round, a corner):
##   TIGHT_SPEED at most, turned tightly rather than swung wide into what stands there; the aim's:
##   `aim_speed` there, braking for it from where it is. GRIP and BRAKE are well under what the police car does (13 m/s²
##   sideways, 15.7 braking: measured).
## - The wheel: pure pursuit (police_driver.gd's, bus_bot.gd _pursue) of a point along the way picked; never over
##   towards something already beside its front (a tree, a post, a wall within SIDE_PROBE m of a flank, felt each look):
##   it goes on straight past it first, then turns (its corner would swing into it).
## - No way on (wanting on at a standstill for STUCK s: a wall, a tree, a car before it, no room to turn; not pressed
##   against the vehicle it means to hit, which is what it wants): it backs out
##   up to REVERSE s, the wheel over to swing its nose towards the aim (straight back with something beside its rear),
##   while there is room behind it (swept as it goes), then on again: a turn in three goes, or more.
## Cheap: 10 looks a second (5 when slow), only for the cars on a call near a player; a look stops sweeping once no way
## left could do better (on a clear road, one or two sweeps), and after SWEEPS_MAX sweeps whatever (thick woods). The
## arc's chords after the first start where the one before ended free: no test of what touches their start.
## - Detail (GTA's levels of detail): with no player nor camera within DETAIL m, no quarry, under way (SLOW m/s or
##   more) and not turning tightly, its looks LIGHT_EVERY s apart. Every look weighs every way all the same: one with
##   fewer ways leaves a car round a building, off the lanes, stuck.
## - A budget: LOOKS_PER_TICK looks a physics tick for all the pilots together; one over it keeps the way it picked one
##   tick more (DEFER_MAX at most): the looks spread over the ticks, never all on one.

const Layers = preload("res://scripts/physics_layers.gd")
const Water = preload("res://scripts/water.gd")

const LOOK_EVERY := 0.1                     # s between two looks at the way...
const LOOK_SLOW := 0.18                     # ...slower than SLOW m/s
const SLOW := 5.0
const SWEEPS_MAX := 12                      # sweeps a look at the way makes at most
const ANGLES := [0.0, 0.25, -0.25, 0.55, -0.55, 0.9, -0.9, 1.35, -1.35]     # rad either side of the aim's direction
const IN_THE_WAY := Layers.BUILDINGS | Layers.BOUNDARY | Layers.PROPS | Layers.VEGETATION | Layers.VEHICLES \
		| Layers.PLAYER | Layers.REMOTE_PLAYER
const SWEEP_LOW := 0.25                     # m above the ground under its front the swept box starts (kerbs pass)...
const HEAD_ROOM := 0.5                      # ...and how far above its body's box it goes (the light bar, low branches)
const SIDE_ROOM := 0.3                      # m swept beyond each side of the car...
const SIDE_PER_SPEED := 0.012               # ...and this many more per m/s of its speed (a lane and its verge at most)
const SIDE_PROBE := 0.6                     # m out from each flank it feels for what is beside it...
const BESIDE_SPEED := 8.0                   # ...slower than this (m/s), or turning more than BESIDE_TURN rad
const BESIDE_TURN := 0.3
const NEAR := 20.0                          # m swept with the box; further, rays
const TOP := 1.0                            # of the car's top speed at most
const GRIP := 11.0                          # m/s² sideways it takes the turns at
const BRAKE := 9.0                          # m/s² it plans to stop at
const MARGIN := 3.0                         # m it keeps from what is in the way
const REACH := Vector2(10.0, 80.0)          # m looked ahead, at least and at most
const STRAIGHT := 0.12                      # rad: a way this near its heading needs no turn first
const ARC_STEP := 0.4                       # rad of a turn swept along one chord at most
const SIDE_KEEP := 0.25                     # score kept for the side of the last way picked (no dithering)
const CRAWL := 3.0                          # m/s it may still go to turn, straight on blocked...
const CRAWL_ROOM := 1.2                     # ...while this much room is left there
const TIGHT := 1.3                          # rad between where it goes and its way: a tight turn...
const TIGHT_SPEED := 7.0                    # ...taken this fast at most (m/s)
const STUCK := 0.8                          # s wanting on at a standstill before backing out...
const REVERSE := 2.0                        # ...for this long at most...
const REVERSE_ROOM := 1.5                   # ...when there is this much room behind...
const REVERSE_STOP := 0.6                   # ...stopping with this much left, and REVERSE_STOP_TIME s of its speed
const REVERSE_STOP_TIME := 0.4
const REVERSE_THROTTLE := 0.7
const DETAIL := 110.0                       # m: no player nor camera this near, no quarry, under way: looks...
const LIGHT_EVERY := 0.25                   # ...this many s apart
const LOOKS_PER_TICK := 3                   # looks a physics tick, all the pilots together...
const DEFER_MAX := 3                        # ...one put off this many ticks at most

var driver: Object:                         # police_driver.gd (its _pursue, its reference point): held weakly, it
	get:                                    # holds this pilot (a cycle of references is never freed)
		return _driver.get_ref() if _driver else null
var _driver: WeakRef
var car: Node3D                             # car.gd
## what it is asked (police_driver.gd, each tick)
var aim := Vector3.ZERO                     # global point it heads for
var aim_speed := INF                        # m/s wanted at the aim (INF: as fast as it may; 0: stopped there)
var stop_short := 0.0                       # m short of the aim it stops (with aim_speed 0)
var limit := INF                            # m/s at most now (its route's bends ahead)
var target: Node3D = null                   # the vehicle it means to hit: not in its way
var sharp := false                          # a sharp swerve at speed (a PIT): the grip and the turn hold nothing back
## what it does (tests, debugging)
var way := Vector3.ZERO                     # the way picked (flat, unit)
var room := INF                             # m free along it...
var room_on := INF                          # ...and straight on
var target_speed := 0.0
var held_by := ""                           # what holds its speed down now: top, limit, grip, room, turn, aim (tests)
var reversing := false
static var spent_us := 0                    # µs every pilot spent driving since the last read (profiling, tests)
static var worst_us := 0                    # µs the most every pilot spent on one physics tick since the last read
static var _tick_frame := -1                # the physics tick the budget counts...
static var _tick_looks := 0                 # ...the looks on it...
static var _tick_us := 0                    # ...and the µs spent on it

var light := false                          # its last look a light one (tests)
var _look_t := 0.0
var _deferred := 0                          # ticks its look has been put off (the budget)
var _side := 0.0                            # sign of the last way's angle
var _stuck_t := 0.0
var _reverse_t := 0.0
var _reverse_steer := 0.0
var _steer := 0.0
var _exclude: Array[RID] = []
var _exclude_with: Array[RID] = []          # its own bodies and those of the vehicle it means to hit...
var _exclude_for: Node3D = null             # ...that one
var _box := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _box_mid := 0.0                         # m above the ground the box's middle is
var _sweeps := 0                            # made in this look
var _beside := [false, false, false, false] # something beside it: front left, front right, rear left, rear right
var _side_box := BoxShape3D.new()
var _side_query := PhysicsShapeQueryParameters3D.new()
var _start_box := BoxShape3D.new()          # right before a sweep's start, as wide as the car: what touches it already
var _start_query := PhysicsShapeQueryParameters3D.new()


func setup(d: Object, c: Node3D) -> void:
	_driver = weakref(d)
	car = c
	for b: Node in car.bodies():
		_exclude.append((b as CollisionObject3D).get_rid())
	var high: float = 2.0 * car.half_extents.y + HEAD_ROOM
	_box.size = Vector3(2.0 * (car.half_extents.x + SIDE_ROOM), high - SWEEP_LOW, 0.5)
	_box_mid = (SWEEP_LOW + high) * 0.5
	_query.shape = _box
	_query.collision_mask = IN_THE_WAY
	_ray.collision_mask = IN_THE_WAY
	_side_box.size = Vector3(SIDE_PROBE, high - SWEEP_LOW, car.half_extents.z + 0.4)
	_side_query.shape = _side_box
	_side_query.collision_mask = IN_THE_WAY
	_side_query.exclude = _exclude
	_start_box.size = Vector3(2.0 * car.half_extents.x + 0.1, high - SWEEP_LOW, 0.6)
	_start_query.shape = _start_box
	_start_query.collision_mask = IN_THE_WAY


## Back to its first look (the car just put out of the pool).
func reset() -> void:
	way = Vector3.ZERO
	room = INF
	room_on = INF
	reversing = false
	_reverse_t = 0.0
	_stuck_t = 0.0
	_side = 0.0
	_deferred = 0
	_look_t = 0.0
	_beside = [false, false, false, false]


## [throttle (-1..1, below 0 in reverse), brake (0..1), steering (-1..1, left positive)] for car.gd.
func drive(delta: float) -> Array:
	var t0 := Time.get_ticks_usec()
	_tick_budget()
	var out := _drive(delta)
	var us := Time.get_ticks_usec() - t0
	spent_us += us
	_tick_us += us
	worst_us = maxi(worst_us, _tick_us)
	return out


## The budget's count, afresh on each physics tick.
static func _tick_budget() -> void:
	var f := Engine.get_physics_frames()
	if f != _tick_frame:
		_tick_frame = f
		_tick_looks = 0
		_tick_us = 0


## Whether it looks this tick: due, and within the budget (or put off long enough, or no way yet).
func _may_look() -> bool:
	if _tick_looks < LOOKS_PER_TICK or _deferred >= DEFER_MAX or way == Vector3.ZERO:
		_tick_looks += 1
		_deferred = 0
		return true
	_deferred += 1
	return false


func _drive(delta: float) -> Array:
	var v: float = car.speed()
	if _reverse_t > 0.0:
		return _back_out(delta)
	var front := _front()
	var to_aim := aim - front
	to_aim.y = 0.0
	var dist := to_aim.length()
	_look_t -= delta
	if (_look_t <= 0.0 or way == Vector3.ZERO) and _may_look():
		light = _light()
		_look_t = LIGHT_EVERY if light else (LOOK_EVERY if absf(v) >= SLOW else LOOK_SLOW)
		_feel(front, to_aim / maxf(dist, 0.01), v)
	# the wheel: a point along the way picked, no further than the aim
	var ahead := clampf(4.0 + 0.8 * absf(v), 6.0, 45.0)    # (further at speed: a gentle line)
	var p := front + way * minf(ahead, maxf(dist, 2.0))
	var angle: float = driver._pursue(Vector2(p.x, -p.z))
	_steer = clampf(angle / car.steer_limit(v), -1.0, 1.0)
	if (_steer > 0.05 and _beside[0]) or (_steer < -0.05 and _beside[1]):
		_steer = 0.0                        # (its corner would swing into what is beside it: straight on past it first)
		angle = 0.0
	# the speed
	var t: float = car.max_speed * TOP
	held_by = "top"
	if limit < t:
		t = limit
		held_by = "limit"
	if absf(angle) > 0.01 and not sharp:
		var radius: float = driver.wheelbase / tan(absf(angle))
		if sqrt(GRIP * radius) < t:
			t = sqrt(GRIP * radius)
			held_by = "grip"
	if _stopping(room) < t:
		t = _stopping(room)
		held_by = "room"
	var turning := _heading().angle_to(way)
	if turning > STRAIGHT and not sharp:    # still turning: able to stop before what is straight on
		var on := maxf(_stopping(room_on), CRAWL if room_on > CRAWL_ROOM else 0.0)
		if on < t:
			t = on
			held_by = "turn"
	if turning > TIGHT and not sharp and TIGHT_SPEED < t:
		t = TIGHT_SPEED
		held_by = "tight"
	if aim_speed < INF:
		var at := sqrt(aim_speed * aim_speed + 2.0 * BRAKE * maxf(dist - stop_short, 0.0))
		if at < t:
			t = at
			held_by = "aim"
	target_speed = t
	# the pedals
	var throttle := 0.0
	var brake := 0.0
	var err := t - v
	if t < 0.3:
		brake = 1.0 if v < 2.0 else clampf(0.4 + v * 0.08, 0.0, 1.0)
	elif err > -0.3:
		throttle = clampf(0.3 + err * 0.5, 0.0, 1.0)
	elif err < -0.6:
		brake = clampf(-err * 0.25, 0.1, 1.0)
	# no way on (still short of where it stops, at a standstill): back out
	var wants_on := dist > stop_short + 4.0
	if absf(v) < 0.8 and (throttle > 0.5 or (wants_on and t < 0.5)) and not _pressing():
		_stuck_t += delta
		if _stuck_t > STUCK:
			_stuck_t = 0.0
			if _room_behind() > REVERSE_ROOM:
				_reverse_t = REVERSE
				var turn := _nose().signed_angle_to(to_aim, Vector3.UP)
				_reverse_steer = -signf(turn) if absf(turn) > 0.2 else 0.0   # (the nose swings towards the aim)
				if _beside[2] or _beside[3]:
					_reverse_steer = 0.0    # (its rear would swing into what is beside it: straight back)
			else:
				_side = -_side              # (no room behind either: the other way round)
			way = Vector3.ZERO
	else:
		_stuck_t = 0.0
	return [throttle, brake, _steer]


## Whether its next look may come later (LIGHT_EVERY): no quarry, under way (SLOW m/s or more) on a way it need not
## turn tightly onto, no player nor camera within DETAIL m.
func _light() -> bool:
	if is_instance_valid(target) or not driver.quarry.is_empty() or absf(car.speed()) < SLOW:
		return false
	if way != Vector3.ZERO and _heading().angle_to(way) > BESIDE_TURN:
		return false
	return driver.traffic.eye_distance_squared(car.global_position) > DETAIL * DETAIL


## Whether it touches the vehicle it means to hit (`target`).
func _pressing() -> bool:
	return is_instance_valid(target) and car.get_colliding_bodies().has(target)


## Backing out: on while there is room behind it (looked at every LOOK_EVERY s, room to stop from its speed kept) and
## time left, then braked.
func _back_out(delta: float) -> Array:
	_reverse_t -= delta
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		if _room_behind() < REVERSE_STOP + absf(car.speed()) * REVERSE_STOP_TIME:
			_reverse_t = 0.0
		_feel_beside(car.get_world_3d().direct_space_state)
		if _beside[2] or _beside[3]:
			_reverse_steer = 0.0            # (straight back past what is beside its rear)
	reversing = _reverse_t > 0.0
	if not reversing:
		way = Vector3.ZERO                  # (a fresh look on the next tick)
	return [-REVERSE_THROTTLE, 0.0, _reverse_steer] if reversing else [0.0, 1.0, 0.0]


## The most speed from which it stops MARGIN short of `f` m on.
static func _stopping(f: float) -> float:
	return sqrt(2.0 * BRAKE * maxf(f - MARGIN, 0.0)) if f < INF else INF


## How far it may back out (its rear swept back, REVERSE_ROOM and a little at most).
func _room_behind() -> float:
	var back := car.to_global(car.extents_center + Vector3(0.0, -car.half_extents.y, -car.half_extents.z))
	_query.exclude = _exclude
	_start_query.exclude = _exclude
	return _sweep(car.get_world_3d().direct_space_state, back, -_nose(), REVERSE_ROOM + 1.0)


## Its front bumper's middle, on the ground under it (global).
func _front() -> Vector3:
	return car.to_global(car.extents_center + Vector3(0.0, -car.half_extents.y, car.half_extents.z))


## Where its nose points (flat, unit).
func _nose() -> Vector3:
	var d: Vector3 = car.global_basis.z
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.FORWARD


## Where it is going now (flat, unit): along its speed going forward, else its nose.
func _heading() -> Vector3:
	if car.speed() < 2.0:
		return _nose()
	var d: Vector3 = car.linear_velocity
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else _nose()


## Picks the way: of those fanned round `dir` (flat, unit), the one free furthest weighed with the turn and the side
## (each swept along the turn it takes to get onto it); sweeps straight on too.
func _feel(front: Vector3, dir: Vector3, v: float) -> void:
	var reach := clampf(v * v / (2.0 * BRAKE) + absf(v) * 0.6 + 8.0, REACH.x, REACH.y)
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var them: Node3D = target if is_instance_valid(target) else null
	if them != _exclude_for or _exclude_with.is_empty():  # (made afresh only when the vehicle it means to hit changes)
		_exclude_for = them
		_exclude_with = _exclude.duplicate()
		if them:
			for b: Node in them.bodies():
				_exclude_with.append((b as CollisionObject3D).get_rid())
	var exclude := _exclude_with
	_query.exclude = exclude
	_ray.exclude = exclude
	_start_query.exclude = exclude
	_side_query.exclude = exclude           # (the vehicle it means to hit may be beside it: a PIT turns into it)
	_box.size.x = 2.0 * (car.half_extents.x + SIDE_ROOM + SIDE_PER_SPEED * absf(v))
	var heading := _heading()
	if dir == Vector3.ZERO:
		dir = heading
	var radius := maxf(v * v / GRIP, driver.wheelbase / tan(car.steer_limit(v)))   # its tightest turn now
	var needed := minf(v * v / (2.0 * BRAKE) + MARGIN + absf(v) * 0.5, reach)      # room it takes to stop: enough
	var best := -INF
	_sweeps = 0
	for a: float in ANGLES:                 # (nearest the aim's first)
		if 2.0 + cos(a) + SIDE_KEEP <= best or (_sweeps >= SWEEPS_MAX and best > -INF):
			break                           # (none left could do better; or enough looking)
		var d := dir.rotated(Vector3.UP, a)
		var f := _path_room(space, front, heading, d, radius, reach)
		var score := 2.0 * minf(f, needed) / needed + cos(a) + (SIDE_KEEP if signf(a) == _side else 0.0)
		if score > best:
			best = score
			way = d
			room = f if f < reach else INF
			_side = signf(a)
	if heading.angle_to(way) <= STRAIGHT:
		room_on = room                      # (the way picked is straight on)
	else:
		var on := _sweep(space, front, heading, reach)
		room_on = on if on < reach else INF
	if absf(v) < BESIDE_SPEED or heading.angle_to(way) > BESIDE_TURN:
		_feel_beside(space)
	else:
		_beside = [false, false, false, false]   # (fast and nearly straight: the sweeps' side room is enough)


## What is beside it (SIDE_PROBE m out from each flank, its front half and its rear half): `_beside`.
func _feel_beside(space: PhysicsDirectSpaceState3D) -> void:
	var b: Basis = Basis(Vector3.UP, atan2(_nose().x, _nose().z))
	var y: float = car.extents_center.y - car.half_extents.y + _box_mid
	var k := 0
	for z: float in [1.0, -1.0]:            # front half, rear half
		for x: float in [1.0, -1.0]:        # left (+X), right
			var local := Vector3(car.extents_center.x + x * (car.half_extents.x + SIDE_PROBE * 0.5), y,
					car.extents_center.z + z * (_side_box.size.z * 0.5))
			_side_query.transform = Transform3D(b, car.to_global(local))
			_beside[k] = not space.intersect_shape(_side_query, 1).is_empty()
			k += 1


## How far it goes free turning from `heading` onto `d` (both flat, unit), as tightly as `radius` m, then along `d`:
## swept along the arc's chords (ARC_STEP rad each at most), then along `d` (`reach` m in all at most).
func _path_room(space: PhysicsDirectSpaceState3D, front: Vector3, heading: Vector3, d: Vector3, radius: float,
		reach: float) -> float:
	var turn := heading.signed_angle_to(d, Vector3.UP)
	if absf(turn) <= STRAIGHT or 2.0 * radius * sin(absf(turn) * 0.5) < 2.0:
		return _sweep(space, front, d, reach)
	var steps := ceili(absf(turn) / ARC_STEP)
	var step := turn / steps
	var chord := 2.0 * radius * sin(absf(step) * 0.5)
	var at := front
	var gone := 0.0
	for k in steps:
		var c := heading.rotated(Vector3.UP, step * (k + 0.5))
		var len := minf(chord, reach - gone)
		var f := _sweep(space, at, c, len, k == 0)    # (the next chords start where this one ended free)
		if f < len:
			return gone + f
		gone += len
		at += c * len
		if gone >= reach:
			return gone
	return gone + _sweep(space, at, d, reach - gone, false)


## How far its front, swept along `d` (flat, unit) from `front`, goes free (`reach` at most), out of the water: a box
## NEAR m on, rays further. What touches its start already (which a cast passes over) stops it there, when `fresh` (a
## sweep from the bumper; not one that goes on from where another ended free).
func _sweep(space: PhysicsDirectSpaceState3D, front: Vector3, d: Vector3, reach: float, fresh := true) -> float:
	_sweeps += 1
	var start := front + d * (_box.size.z * 0.5 + 0.02) + Vector3.UP * _box_mid    # (from the bumper on)
	var b := Basis(Vector3.UP, atan2(d.x, d.z))
	if fresh:
		_start_query.transform = Transform3D(b, front + d * (_start_box.size.z * 0.5 - 0.1) + Vector3.UP * _box_mid)
		if not space.intersect_shape(_start_query, 1).is_empty():
			return 0.0
	var near := minf(reach, NEAR)
	_query.transform = Transform3D(b, start)
	_query.motion = d * near
	var f := space.cast_motion(_query)[0] * near
	if f >= near and reach > near:
		var side := d.cross(Vector3.UP).normalized() * (_box.size.x * 0.5)
		var from := start + d * near
		var far := reach - near
		for o: Vector3 in [Vector3.ZERO, side, -side]:
			_ray.from = from + o
			_ray.to = from + o + d * far
			var hit := space.intersect_ray(_ray)
			if hit:
				far = minf(far, _ray.from.distance_to(hit["position"]))
		f = near + far
	return minf(f, _dry(start, d, f))


## How far along `d` from `from` it stays out of the water (looked at 6 m on, halfway and at `f`; water well under
## the way, a bridge over it, does not count).
static func _dry(from: Vector3, d: Vector3, f: float) -> float:
	for k: float in [6.0, f * 0.5, f]:
		var p := from + d * k
		var level := Water.surface_at(p)
		if not is_nan(level) and level > p.y - 3.0:
			return maxf(k - 6.0, 0.0)
	return f
