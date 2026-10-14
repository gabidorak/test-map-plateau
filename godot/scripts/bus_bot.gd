extends RefCounted
## A bot bus driver: scripts/traffic.gd makes one per bot bus and car.gd asks it for the pedals and the steering every
## physics tick (drive). It drives its line's routes in turn (world/bus_routes.json, pipeline/plateau/transit.py):
## - Path: pure pursuit of the route's path (the right-hand lane, eased to the kerb at stops) from the middle of the
##   front section (between its axles: in a bend its front swings out and its rear wheels cut in about as much,
##   which transit.py leaves room for); the speed follows the route's planned speed (limits, curves) and brakes for what
##   is ahead.
## - Stops: every stop of the line: the right indicator on the way in, a stop with the front at the pole, the doors open
##   for DWELL_TIME s (longer while a player is at a door), closed, the left indicator, and off.
## - Traffic lights: waits at the red (and at the amber when it can stop), on the shared light clock (traffic.gd).
## - Junctions where it gives way (transit.py): waits at the line while a vehicle comes from a conflicting arm or moves
##   in the junction; a stop sign is a full stop first. It does not wait more than YIELD_PATIENCE s for nothing.
## - Vehicles ahead on its path (any vehicle, the players' too): follows them, stops GAP m behind, sounds the horn when
##   kept waiting. Players on foot are not looked for.
## - Indicators: before the turns of its route, into and out of the stops.
## - Far from every player (FAR m) it glides along its path instead (frozen, posed on the ground: cheap, and it can
##   not get stuck where nobody sees it); a player coming within NEAR m hands it back to the physics.
## - Ends of routes: at a terminus inside the map it lays over and sets off on the next route when that one starts
##   where it stands; else it vanishes (car.gd set_stowed): at the map edge, or at a terminus once no player is within
##   WATCHED m. It first waits, doors open, while players ride it. It comes back in at the start of the next route
##   RESPAWN s later, once the way in is clear.
## - Held still (at a stop, a light, behind a vehicle) it is frozen in place after HOLD s, like a parking brake: braked
##   wheels let a VehicleBody3D creep sideways on the hillside's cross slopes.
## - Stalled (no progress for ASSIST_AFTER s with nothing in the way: a pit in the LiDAR ground, a kerb, a prop it
##   brushed) it glides over the next ASSIST m, then drives on with the physics.
## Positions on the path are pipeline x/y (x east, y north; Godot = (x, -z)); `s` is the distance along the path of
## the middle of the front section (the reference point), `s + nose` that of the front of the bus.

const GroundMap = preload("res://scripts/ground_map.gd")

enum { DRIVE, DWELL, TERMINUS, STOWED }

const LOOK_EVERY := 0.1                     # s between looks around (vehicles ahead, give-ways)
const NEAR := 200.0                         # m: a player this close and the bus drives with the physics...
const FAR := 240.0                          # ...none this close and it glides
const BRAKE := 1.3                          # m/s², planned braking (stops, lights, give-ways, end of route)
const HARD_BRAKE := 3.0                     # m/s², for vehicles ahead
const GLIDE_ACCEL := 0.9                    # m/s², gliding
const GAP := 3.5                            # m left to a vehicle ahead
const HALF_WIDTH := 1.3                     # m, half the bus width
const SIDE_MARGIN := 0.5                    # m beyond it a vehicle counts as in the way
const STOP_REACH := 5.0                     # m short of its stop the bus may stop and open its doors
const DWELL_TIME := Vector2(9.0, 14.0)      # s, doors open at a stop (random between)
const LAYOVER := 30.0                       # s, doors open at a terminus
const DOOR_HOLD := 25.0                     # s more at most while a player stands at a door
const DOOR_REACH := 3.5                     # m from a doorway
const PULL_OUT := 1.5                       # s of left indicator before pulling out
const LEAVE_SIGNAL := 14.0                  # m after its stop the left indicator stays on (at most)
const SIGNAL_STOP := 55.0                   # m before a stop the right indicator goes on
const RESPAWN := Vector2(15.0, 35.0)        # s off the map before coming back in (random between)
const WATCHED := 60.0                       # m: a player this close and the bus does not vanish at a terminus...
const WATCH_MAX := 90.0                     # ...for this many seconds at most
const YIELD_PATIENCE := 15.0                # s waiting at a give-way line before going anyway
const HORN_AFTER := 6.0                     # s behind a vehicle that does not move before the horn
const ASSIST_AFTER := 2.0                   # s stalled before gliding on
const ASSIST := 15.0                        # m glided
const AMBER_DECEL := 2.5                    # m/s²: at the amber it stops if it can at this braking
const HOLD := 0.6                           # s stopped before the bus is frozen in place

var traffic: Node                           # traffic.gd
var car: Node3D                             # car.gd
var line: Dictionary
var route_index := 0
var route: Dictionary
var s := 0.0
var horn := false                           # car.gd reads it
var state := DRIVE
var gliding := false
var nose := 0.0                             # m from the reference point to the front of the bus
var tail := 0.0                             # m from it to the back of the bus (straight)
var wheelbase := 6.0                        # m, front section's
var target_speed := 0.0                     # m/s, last planned (tests)
var reason := ""                            # what holds the speed down (tests, debugging)
var may_glide := true                       # false: always the physics (tests)
var assists := 0                            # times it glided on from a stall (tests)
var served := 0                             # stops served (tests)

var _pts := PackedVector2Array()
var _v := PackedFloat32Array()
var _step := 1.0
var _length := 0.0
var _rear_z := 0.0                          # car frame z of the front section's rear axle
var _ref_z := 0.0                           # car frame z of the reference point, midway between the axles
var _hitch := Vector3.ZERO                  # car frame
var _trailer_axle := 0.0                    # rear section's axle: z in its frame
var _trailer_reach := 0.0                   # m from the hitch to the rear section's axle
var _ride := 0.0                            # car origin above the ground
var _speed := 0.0                           # m/s while gliding
var _next_stop := 0                         # index into route["stops"]
var _timer := 0.0                           # s in the current state
var _dwell := 0.0                           # s the doors stay open at this stop
var _leaving_s := -INF                      # s (front) of the stop just left: left indicator until past it
var _leave_t := 0.0
var _look_t := 0.0
var _obstacle := INF                        # m from the front to the nearest vehicle in the way
var _obstacle_v := 0.0                      # its speed along the path
var _obstacle_still := false
var _blocked_t := 0.0
var _horn_t := 0.0
var _yield := -1                            # index into route["yields"] of the next give-way line, -1 none
var _conflict := false
var _stopped_at := -1                       # give-way line the bus has come to a full stop at (stop signs)
var _yield_wait := 0.0
var _stuck_t := 0.0
var _assist_to := -INF                      # glides until its reference point is this far along the path
var _respawn_t := 0.0
var _held := false                          # frozen in place while stopped
var _still_t := 0.0                         # s stopped with nowhere to go
var _rng := RandomNumberGenerator.new()


func setup(t: Node, vehicle: Node3D, bus_line: Dictionary, index: int) -> void:
	traffic = t
	car = vehicle
	line = bus_line
	_rng.randomize()
	_measure()
	_set_route(index)


## Axles and extents from the vehicle (built by car.gd setup).
func _measure() -> void:
	var steer := []
	var fixed := []
	for w in car.get_children():
		if w is VehicleWheel3D:
			(steer if w.use_as_steering else fixed).append(w.position.z)
	var front_axle: float = _mean(steer)
	_rear_z = _mean(fixed)
	wheelbase = maxf(front_axle - _rear_z, 1.0)
	_ref_z = _rear_z + wheelbase * 0.5
	nose = car.extents_center.z + car.half_extents.z - _ref_z
	tail = _ref_z - (car.extents_center.z - car.half_extents.z)
	if car.trailer:
		_hitch = car.hitch()
		var tz := []
		for w in car.trailer.get_children():
			if w is VehicleWheel3D:
				tz.append(w.position.z)
		_trailer_axle = _mean(tz)
		_trailer_reach = _hitch.z - (car.rear_offset.z + _trailer_axle)


static func _mean(a: Array) -> float:
	var m := 0.0
	for x: float in a:
		m += x / a.size()
	return m


func _set_route(index: int) -> void:
	route_index = index
	route = traffic.routes[line["routes"][index]]
	_step = float(route["step"])
	_length = float(route["length"])
	_pts = PackedVector2Array()
	for p: Array in route["pts"]:
		_pts.append(Vector2(p[0], p[1]))
	_v = PackedFloat32Array(route["v"])
	_next_stop = 0
	_yield = -1
	_stopped_at = -1
	_assist_to = -INF


# ---------------------------------------------------------------- path

## Point of the path `d` m along it (clamped to its ends; beyond them, carried on straight).
func at(d: float) -> Vector2:
	var n := _pts.size()
	if d <= 0.0:
		return _pts[0] + (_pts[1] - _pts[0]).normalized() * d
	if d >= (n - 1) * _step:
		return _pts[n - 1] + (_pts[n - 1] - _pts[n - 2]).normalized() * (d - (n - 1) * _step)
	var f := d / _step
	var i := int(f)
	return _pts[i].lerp(_pts[i + 1], f - i)


func _planned(d: float) -> float:
	return _v[clampi(roundi(d / _step), 0, _v.size() - 1)]


## (distance along the path, offset to its right) of `p` (pipeline x/y), nearest within [from, to].
func project(p: Vector2, from: float, to: float) -> Vector2:
	var n := _pts.size()
	var i0 := clampi(floori(from / _step), 0, n - 2)
	var i1 := clampi(ceili(to / _step), 0, n - 2)
	var best := INF
	var out := Vector2(from, INF)
	for i in range(i0, i1 + 1):
		var a := _pts[i]
		var ab := _pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best:
			best = d2
			out = Vector2((i + t) * _step, -ab.cross(p - a) / maxf(ab.length(), 1e-6))
	return out


static func flat(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)


func _ground(p: Vector2) -> float:
	var map: GroundMap = GroundMap.get_map()
	return map.height(p.x, p.y) if map else 0.0


## Car transform (origin on the ground) with the reference point at `d` along the path, its axles on the path.
func pose_at(d: float) -> Transform3D:
	var a := at(d - wheelbase * 0.5)
	var b := at(d + wheelbase * 0.5)
	var ha := _ground(a)
	var hb := _ground(b)
	var f := Vector3(b.x - a.x, hb - ha, -(b.y - a.y)).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var basis := Basis(x, f.cross(x), f)
	var m := (a + b) * 0.5
	return Transform3D(basis, Vector3(m.x, (ha + hb) * 0.5 + _ride, -m.y) - basis * Vector3(0.0, 0.0, _ref_z))


## The rear section's transform behind the front section at `front` (gliding): its axle on the path, facing the hitch.
func _trailer_pose(front: Transform3D, d: float) -> Transform3D:
	var hitch := front * _hitch
	var h2 := flat(hitch)
	var st := d - (_ref_z - _hitch.z) - _trailer_reach
	for k in 3:
		st += h2.distance_to(at(st)) - _trailer_reach
	var a := at(st)
	var ha := _ground(a)
	var f := (hitch - Vector3(a.x, ha + _ride, -a.y)).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var basis := Basis(x, f.cross(x), f)
	return Transform3D(basis, Vector3(a.x, ha + _ride, -a.y) - basis * Vector3(0.0, 0.0, _trailer_axle))


# ---------------------------------------------------------------- driving

## car.gd, each physics tick: [throttle 0..1, brake 0..1, steering -1..1 (left positive)] (and `horn`).
func drive(delta: float) -> Array:
	_timer += delta
	horn = false
	if state == STOWED:
		_stowed(delta)
		return [0.0, 1.0, 0.0]
	_update_glide()
	var v: float = _speed if gliding else car.speed()
	if not gliding:
		var p := project(flat(car.to_global(Vector3(0.0, 0.0, _ref_z))), s - 6.0, s + 20.0)
		s = p.x
		_ride = lerpf(_ride, car.global_position.y - _ground(flat(car.global_position)), 0.02)
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		_look(v)
	var target := _plan(v, delta)
	target_speed = target
	_indicators(delta)
	_watch_stuck(v, target, delta)
	if gliding:
		return [0.0, 0.0, _glide(target, delta) / car.steer_limit(v)]
	_hold(target < 0.2 and absf(v) < 0.25, target, delta)
	# pedals
	var throttle := 0.0
	var brake := 0.0
	var err := target - v
	if target < 0.2:
		brake = 1.0 if v < 2.0 else clampf(0.3 + v * 0.1, 0.0, 1.0)
	elif err > -0.15:
		throttle = clampf(0.1 + err * 0.6, 0.0, 1.0)
	elif err < -0.5:
		brake = clampf(-err * 0.3, 0.05, 1.0)
	var ld := clampf(4.0 + 0.7 * maxf(v, 0.0), 6.0, 16.0)
	return [throttle, brake, _pursue(at(s + ld)) / car.steer_limit(v)]


## Steering angle (left positive) that brings the reference point onto `target` (pipeline x/y) along an arc.
func _pursue(target: Vector2) -> float:
	var local: Vector3 = car.to_local(Vector3(target.x, car.global_position.y, -target.y)) - Vector3(0.0, 0.0, _ref_z)
	var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
	var k := 2.0 * local.x / (dist * dist)  # curvature of the reference point's arc (2 sin(alpha) / dist)
	if absf(k) < 1e-5:
		return 0.0
	# the rear axle turns about the same centre on a smaller circle
	var half := wheelbase * 0.5
	var rear := sqrt(maxf(1.0 / (k * k) - half * half, 0.01))
	return signf(k) * atan(wheelbase / rear)


## The speed to drive at now; moves between the states (stops, ends of routes).
func _plan(v: float, delta: float) -> float:
	var front := s + nose
	var stops: Array = route["stops"]
	while _next_stop < stops.size() and float(stops[_next_stop]["s"]) < front - 3.0:
		_next_stop += 1
	if state == DWELL:
		reason = "dwell"
		_dwell_at_stop()
		return 0.0
	if state == TERMINUS:
		reason = "terminus"
		_wait_at_terminus()
		return 0.0
	var target := minf(_planned(front + 1.0), _planned(s))
	reason = "route"
	# the stop
	if _next_stop < stops.size():
		var d := float(stops[_next_stop]["s"]) - front
		target = _limit(target, _reach(d, BRAKE), "stop")
		if d < STOP_REACH and v < 0.4:
			_arrive()
			return 0.0
	# traffic lights
	for l: Dictionary in route["lights"]:
		var d := float(l["s"]) - front
		if d < -0.5:
			continue
		if d > 90.0:
			break
		var c: int = traffic.light(traffic.clock(), l["phase"])
		if c == 2 or (c == 1 and d > v * v / (2.0 * AMBER_DECEL) + 1.0):
			target = _limit(target, _reach(d, BRAKE), "light")
		break
	# give way
	if _yield >= 0:
		var y: Dictionary = route["yields"][_yield]
		var d := float(y["s"]) - front
		if y["stop"] and _stopped_at != _yield:
			target = _limit(target, _reach(d, BRAKE), "stop sign")
			if d < 3.0 and v < 0.3:
				_stopped_at = _yield
		if _conflict and _yield_wait < YIELD_PATIENCE:
			target = _limit(target, _reach(d, BRAKE), "give way")
		if d < 3.0 and v < 0.3:
			_yield_wait += delta
	# vehicles ahead
	if _obstacle < INF:
		target = _limit(target, sqrt(_obstacle_v * _obstacle_v + 2.0 * HARD_BRAKE * maxf(_obstacle - GAP, 0.0)) \
				if _obstacle > GAP else 0.0, "vehicle ahead")
		_blocked_t = _blocked_t + delta if _obstacle_still and v < 0.3 else 0.0
		if _blocked_t > HORN_AFTER:
			_horn_t += delta
			horn = fmod(_horn_t, 8.0) < 0.5
	else:
		_blocked_t = 0.0
		_horn_t = 0.0
	# end of the route
	var left := _length - front
	if route["then"] == "continue":
		if left < 1.0 and _next_stop >= stops.size():
			_next_route()
	else:
		target = _limit(target, _reach(left - 1.0, BRAKE), "end")
		if left < 3.0 and v < 0.4:
			_end_of_route()
			return 0.0
	return target


func _limit(target: float, v: float, why: String) -> float:
	if v < target:
		reason = why
		return v
	return target


## Highest speed from which the bus stops within `d` m braking at `a`.
static func _reach(d: float, a: float) -> float:
	return sqrt(2.0 * a * d) if d > 0.3 else 0.0


## At the stop: doors open after a moment, for longer at the last one before a terminus.
func _arrive() -> void:
	state = DWELL
	_timer = 0.0
	var stops: Array = route["stops"]
	var last: bool = _next_stop >= stops.size() - 1 and route["end"] == "terminus" \
			and _length - float(stops[mini(_next_stop, stops.size() - 1)]["s"]) < 40.0
	_dwell = LAYOVER if last else _rng.randf_range(DWELL_TIME.x, DWELL_TIME.y)


func _dwell_at_stop() -> void:
	if _timer > 0.6 and _timer < _dwell and not car.doors_open:
		car.set_doors(true)
	if _timer >= _dwell and car.doors_open:
		if _timer < _dwell + DOOR_HOLD and _player_at_door():
			return
		car.set_doors(false)
		_timer = _dwell                     # the doors take car.DOOR_TIME to close from here
	if _timer >= _dwell + car.DOOR_TIME + PULL_OUT and not car.doors_open:
		served += 1
		var stops: Array = route["stops"]
		_leaving_s = float(stops[_next_stop]["s"]) if _next_stop < stops.size() else s + nose
		_leave_t = 0.0
		_next_stop += 1
		state = DRIVE


## End of a route that does not run on into the next: the bus is about to vanish (_wait_at_terminus).
func _end_of_route() -> void:
	state = TERMINUS
	_timer = 0.0


## Doors open while players ride it; then, doors closed, it vanishes (at a terminus in the map, once no player is near).
func _wait_at_terminus() -> void:
	if traffic.game.riders(car) > 0:
		_timer = 0.0
		if not car.doors_open:
			car.set_doors(true)
		return
	if car.doors_open:
		car.set_doors(false)
		_timer = 0.0
		return
	if _timer < car.DOOR_TIME + 0.5:
		return
	if route["end"] != "terminus" or _timer > WATCH_MAX or not _player_within(car.global_position, WATCHED):
		_stow()


## On into the next route (from a terminus where it starts): on its path where the bus already is.
func _next_route() -> void:
	_set_route((route_index + 1) % line["routes"].size())
	var p := project(flat(car.to_global(Vector3(0.0, 0.0, _ref_z))), 0.0, 80.0)
	s = p.x
	var stops: Array = route["stops"]
	_next_stop = 0
	while _next_stop < stops.size() and float(stops[_next_stop]["s"]) < s + nose + 8.0:
		_next_stop += 1


func _stow() -> void:
	state = STOWED
	_timer = 0.0
	_respawn_t = _rng.randf_range(RESPAWN.x, RESPAWN.y)
	car.set_indicator(0)
	car.set_doors(false)
	_set_route((route_index + 1) % line["routes"].size())
	s = tail + 1.0
	car.set_stowed(true)
	var xf := pose_at(s)
	_place(xf)
	gliding = false
	_held = false
	_speed = 0.0


func _stowed(_delta: float) -> void:
	if _timer < _respawn_t:
		return
	var xf := pose_at(s)
	if not traffic.is_clear(xf.origin, car) or _player_within(xf.origin, 15.0):
		_timer = _respawn_t - 2.0           # look again in 2 s
		return
	_place(xf)
	car.set_stowed(false)
	state = DRIVE
	_timer = 0.0
	_stuck_t = 0.0
	_update_glide(true)


func _place(xf: Transform3D) -> void:
	car.place(xf.translated(Vector3.UP * 0.05))
	if car.trailer:
		car.trailer.global_transform = _trailer_pose(xf, s).translated(Vector3.UP * 0.05)


## Puts the bus on route `index` (into line["routes"]) with its reference point `d` m along it, driving (tests).
func put(index: int, d: float) -> void:
	_set_route(index)
	s = d
	state = DRIVE
	_timer = 0.0
	_leaving_s = -INF
	_stuck_t = 0.0
	car.set_doors(false)
	car.set_stowed(false)
	_speed = 0.0
	_place(pose_at(s))
	_update_glide(true)


# ---------------------------------------------------------------- looking around

## Vehicles in the way on the path ahead, and whether to wait at the next give-way line.
func _look(v: float) -> void:
	var front := s + nose
	var reach := 10.0 + v * v / (2.0 * BRAKE) + 15.0
	_obstacle = INF
	_obstacle_still = false
	var tip := at(front)
	for c: Node3D in traffic.game.cars:
		if c == car or c.stowed:
			continue
		var centre := flat(c.to_global(c.extents_center))
		if centre.distance_to(tip) > reach + c.half_extents.z + 5.0:
			continue
		# facing the other way in the other lane (moving or waiting): its corners may come close on a narrow road, but
		# it passes by; both waiting for each other would never end
		var cq := project(centre, front - 5.0, front + reach + 10.0)
		var path_dir := (at(cq.x + 1.0) - at(cq.x)).normalized()
		if cq.y < -0.6 and flat(c.global_basis.z).normalized().dot(path_dir) < -0.5:
			continue
		var hit := INF
		for p in _footprint(c):
			var q := project(p, front - 1.0, front + reach)
			if q.x > front - 0.5 and q.x < front + reach and absf(q.y) < HALF_WIDTH + SIDE_MARGIN:
				hit = minf(hit, q.x - front)
		if hit < _obstacle:
			_obstacle = maxf(hit, 0.0)
			var dir := (at(front + hit + 1.0) - at(front + hit)).normalized()
			_obstacle_v = maxf(flat(c.linear_velocity).dot(dir), 0.0)
			_obstacle_still = c.linear_velocity.length() < 0.5
	# the next give-way line ahead
	var yields: Array = route["yields"]
	var nxt := -1
	for k in yields.size():
		if float(yields[k]["s"]) > front - 1.0:
			nxt = k
			break
	if nxt != _yield:
		_yield = nxt
		_yield_wait = 0.0
	_conflict = false
	if _yield >= 0 and float(yields[_yield]["s"]) - front < 60.0:
		_conflict = _junction_busy(yields[_yield], front)


## Footprint points (pipeline x/y) of a vehicle: the corners and middle of each section's body box.
func _footprint(c: Node3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for b: Node3D in c.bodies():
		for cs in b.get_children():
			if cs is CollisionShape3D and cs.shape is BoxShape3D and not cs.disabled:
				var h: Vector3 = cs.shape.size * 0.5
				for k in [Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z), Vector3(h.x, 0, -h.z), Vector3(-h.x, 0, -h.z),
						Vector3(0, 0, h.z), Vector3(0, 0, -h.z), Vector3.ZERO]:
					out.append(flat(b.global_transform * (cs.transform * k)))
	if out.is_empty():
		out.append(flat(c.to_global(c.extents_center)))
	return out


## True when a vehicle comes towards the junction of give-way `y` from one of its conflicting arms, soon, or moves in it.
func _junction_busy(y: Dictionary, front: float) -> bool:
	var j := Vector2(y["x"], y["y"])
	var r: float = y["r"]
	for c: Node3D in traffic.game.cars:
		if c == car or c.stowed:
			continue
		var p := flat(c.to_global(c.extents_center))
		var d := p.distance_to(j)
		if d > 60.0:
			continue
		var vel := flat(c.linear_velocity)
		# behind the bus or beside it in its lane: not crossing its way
		var q := project(p, front - 40.0, front + 2.0)
		if absf(q.y) < 3.0 and q.x < front + 1.0:
			continue
		if d < r:
			if vel.length() > 0.7:
				return true
			continue
		var out := (p - j) / d
		var closing := -vel.dot(out)
		if closing < 1.0 or (d - r) / closing > 6.0:
			continue
		for a: Array in y["arms"]:
			if out.dot(Vector2(a[0], a[1])) > 0.82:
				return true
	return false


# ---------------------------------------------------------------- indicators, players

func _indicators(delta: float) -> void:
	var front := s + nose
	var side := 0
	for t: Array in route["turns"]:
		if front >= t[0] and front <= t[1]:
			side = int(t[2])
			break
	_leave_t += delta
	if side == 0:
		if state == DWELL:
			side = 1 if _timer >= _dwell + car.DOOR_TIME * 0.5 and not car.doors_open else 0
		elif front < _leaving_s + LEAVE_SIGNAL and _leave_t < 6.0:
			side = 1
		elif state == DRIVE and _next_stop < route["stops"].size():
			var d := float(route["stops"][_next_stop]["s"]) - front
			side = -1 if d < SIGNAL_STOP and d > -2.0 else 0
	if side != car.indicator:
		car.set_indicator(side)


func _player_within(p: Vector3, d: float) -> bool:
	for q: Vector3 in traffic.game.player_spots():
		if Vector2(q.x - p.x, q.z - p.z).length() < d:
			return true
	return false


## A player stands by one of the open doorways (inside or out).
func _player_at_door() -> bool:
	var spots: Array = traffic.game.player_spots(true)
	for b: Node3D in car.bodies():
		for dc: Vector3 in b.door_centres:
			var g: Vector3 = b.to_global(dc)
			for q: Vector3 in spots:
				if q.distance_to(g) < DOOR_REACH:
					return true
	return false


# ---------------------------------------------------------------- gliding far from the players

## Glides when no player is within FAR m (NEAR m to stop gliding) and nobody rides it; `force` decides afresh.
func _update_glide(force := false) -> void:
	var p: Vector3 = car.to_global(car.extents_center)
	var near: bool = not may_glide or _player_within(p, NEAR if gliding else FAR) or traffic.game.riders(car) > 0
	var want: bool = not near or s < _assist_to
	if want == gliding and not force:
		return
	if want and not gliding:
		_speed = clampf(car.speed(), 0.0, car.max_speed)     # (a body just moved by hand reports wild speeds)
	gliding = want
	_held = false
	_freeze(want, _speed)


## Freezes the bodies in place (gliding, held) or lets them go at `speed` along the bus.
func _freeze(on: bool, speed := 0.0) -> void:
	for b: VehicleBody3D in car.bodies():
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = on
		b.sleeping = false
	if not on:
		var f: Vector3 = car.global_basis.z
		for b: VehicleBody3D in car.bodies():
			b.linear_velocity = f * speed
			b.angular_velocity = Vector3.ZERO


## Stopped with nowhere to go for HOLD s: frozen in place; let go as soon as it may move.
func _hold(still: bool, target: float, delta: float) -> void:
	_still_t = _still_t + delta if still else 0.0
	if not _held and _still_t > HOLD:
		_held = true
		_freeze(true)
	elif _held and target >= 0.2:
		_held = false
		_freeze(false)


## Moves the bus along its path at up to `target` m/s; returns the steering angle that shows for it.
func _glide(target: float, delta: float) -> float:
	_speed = move_toward(_speed, target, (GLIDE_ACCEL if target > _speed else HARD_BRAKE) * delta)
	s += _speed * delta
	var xf := pose_at(s)
	car.global_transform = xf
	if car.trailer:
		car.trailer.global_transform = _trailer_pose(xf, s)
	return _pursue(at(s + wheelbase))


## No progress for ASSIST_AFTER s although nothing holds it: glides on over the next ASSIST m.
func _watch_stuck(v: float, target: float, delta: float) -> void:
	var held: bool = target < 1.0 or car.broken or state != DRIVE
	if held or v > 0.5 or gliding:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t > ASSIST_AFTER:
		_stuck_t = 0.0
		_assist_to = s + ASSIST
		assists += 1
		_update_glide(true)
		_speed = maxf(_speed, 2.0)
