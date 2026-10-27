extends RefCounted
## A bot driver: scripts/traffic.gd makes one per bot bus or bot car and car.gd asks it for the pedals and the steering
## every physics tick (drive). It drives the route traffic.gd sends it on (put), and its line's next routes after it
## (world/bus_routes.json, pipeline/plateau/transit.py; a bot car's "line" is every car route, world/car_routes.json,
## car_traffic.py, and it has no stops):
## - Path: pure pursuit of the route's path (the right-hand lane, eased to the kerb at stops) from the middle of the
##   front section (between its axles: in a bend its front swings out and its rear wheels cut in about as much,
##   which transit.py leaves room for); the speed follows the route's planned speed (limits, curves) and brakes for what
##   is ahead.
## - Stops: every stop of the line: the right indicator on the way in, a stop with the front at the stop's "s" (the pole;
##   the articulated bus's bellows at the pole, transit.py), the doors open for DWELL_TIME s (longer while a player is at
##   a door, outside or in the doorway), closed, the left indicator, and off.
## - Traffic lights: waits at the red (and at the amber when it can stop), on the shared light clock (traffic.gd).
## - Junctions where it gives way (transit.py): waits at the line while a vehicle comes from a conflicting arm or moves
##   in the junction; a stop sign is a full stop first. It does not wait more than YIELD_PATIENCE s for nothing.
## - Vehicles ahead on its path (any vehicle, the players' too): follows them, stops GAP m behind, sounds the horn when
##   kept waiting. Players on foot are not looked for. Vehicles coming the other way on their side of the road are
##   passed by, even close on a narrow road (gliding, they are passed through). Two bots each waiting for the other
##   (noses in a junction, head-on in a lane too narrow for both) settle it after DEADLOCK s: one of them drives on as if
##   the other were not there for PASS_TIME s, the two not colliding meanwhile. Kept waiting GIVE_UP s with no player
##   within GIVE_UP_SEEN m (a vehicle parked in its lane), it vanishes.
## - A vehicle no bot drives (a player's, or a wreck) standing in its lane for PASS_AFTER s: it overtakes it on the left
##   when the room there (route "room": to the kerb) is enough and the way is free (nothing coming in the lane it takes
##   for PASS_CLEAR m, no light, give-way or stop just past it); gliding, it passes through it.
## - At a stop, a bus waiting right behind another one there opens its doors where it is (a terminus with buses
##   arriving every minute serves two at a time).
## - Indicators: before the turns of its route, into and out of the stops.
## - Far from every player (FAR m) it glides along its path instead (frozen, posed on the ground: cheap, and it can
##   not get stuck where nobody sees it); a player coming within NEAR m hands it back to the physics. Gliding, its
##   bodies are static (no wheel or contact physics) and traffic.gd moves it (glide_step) every GLIDE_TICKS ticks,
##   fewer the farther it is from every player and the camera (GLIDE_MID, GLIDE_FAR; more again when the computer
##   does not keep up, traffic.gd glide_scale); a step never runs past where it has to stop. Driving with the physics,
##   car.gd asks it every tick (drive).
## - Ends of routes: at a terminus inside the map it lays over (shorter with a bus waiting behind) and sets off on the
##   next route when that one starts where it stands; else it vanishes (car.gd set_stowed): at the map edge, or at a
##   terminus once no player is within WATCHED m (at once with a bus waiting behind). It first waits, doors open, while
##   players ride it. Stowed, it waits for traffic.gd to send it out again (`idle`).
## - Held still (at a stop, a light, behind a vehicle) it is frozen in place after HOLD s, like a parking brake: braked
##   wheels let a VehicleBody3D creep sideways on the hillside's cross slopes.
## - Stalled (no progress for ASSIST_AFTER s with nothing in the way: a pit in the LiDAR ground, a kerb, a prop it
##   brushed) it glides over the next ASSIST m, then drives on with the physics.
## Positions on the path are pipeline x/y (x east, y north; Godot = (x, -z)); `s` is the distance along the path of
## the middle of the front section (the reference point), `s + nose` that of the front of the bus.

const GroundMap = preload("res://scripts/ground_map.gd")

enum { DRIVE, DWELL, TERMINUS, STOWED }

const LOOK_EVERY := 0.1                     # s between looks around (vehicles ahead, give-ways)...
const GLIDE_LOOK_EVERY := 0.25              # ...gliding
const NEAR := 200.0                         # m: a player this close and the bus drives with the physics...
const FAR := 240.0                          # ...none this close and it glides
const BRAKE := 1.3                          # m/s², planned braking (stops, lights, give-ways, end of route)
const HARD_BRAKE := 3.0                     # m/s², for vehicles ahead
const GLIDE_ACCEL := 0.9                    # m/s², gliding
const GLIDE_TICKS := 3                      # gliding, it moves every this many physics ticks...
const GLIDE_MID := 450.0                    # ...every GLIDE_TICKS_MID farther than this from every player and camera...
const GLIDE_TICKS_MID := 6
const GLIDE_FAR := 900.0                    # ...and every GLIDE_TICKS_FAR farther than this
const GLIDE_TICKS_FAR := 12
const GAP := 3.5                            # m left to a vehicle ahead
const SIDE_MARGIN := 0.5                    # m beyond half the vehicle's width another one counts as in the way
const STOP_REACH := 5.0                     # m short of its stop the bus may stop and open its doors
const DWELL_TIME := Vector2(9.0, 14.0)      # s, doors open at a stop (random between)
const LAYOVER := 20.0                       # s, doors open at a terminus (halved, like the stops, far from the players)
const DOOR_HOLD := 25.0                     # s more at most while a player stands at a door
const DOOR_REACH := 3.5                     # m from a doorway
const DOORWAY := 1.2                        # m from a doorway (level) a player already inside still holds the doors
const PULL_OUT := 1.5                       # s of left indicator before pulling out
const LEAVE_SIGNAL := 14.0                  # m after its stop the left indicator stays on (at most)
const SIGNAL_STOP := 55.0                   # m before a stop the right indicator goes on
const WATCHED := 60.0                       # m: a player this close and the bus does not vanish at a terminus...
const WATCH_MAX := 90.0                     # ...for this many seconds at most
const YIELD_PATIENCE := 15.0                # s waiting at a give-way line before going anyway
const HORN_AFTER := 6.0                     # s behind a vehicle that does not move before the horn
const ASSIST_AFTER := 2.0                   # s stalled before gliding on
const ASSIST := 15.0                        # m glided
const AMBER_DECEL := 2.5                    # m/s²: at the amber it stops if it can at this braking
const HOLD := 0.6                           # s stopped before the bus is frozen in place
const DEADLOCK := 3.0                       # s two bots wait for each other before one goes...
const PASS_TIME := 8.0                      # ...driving past the other for this long
const GIVE_UP := 45.0                       # s behind a vehicle that does not move before vanishing...
const GIVE_UP_SEEN := 120.0                 # ...when no player is this close
const QUEUE_REACH := 30.0                   # m behind the bus a bus waiting makes it cut its layover short
const ONCOMING_SIDE := 0.6                  # m left of the path the middle of a vehicle facing the other way passes by
const PASS_AFTER := 5.0                     # s behind a parked vehicle before overtaking it
const PASS_ROOM := 0.6                      # m kept from it
const PASS_IN := 10.0                       # m over which it moves out (and back in after)
const PASS_CLEAR := 80.0                    # m of the lane it takes that must be free ahead
const PASS_SPEED := 6.0                     # m/s at most while overtaking
const BERTH := 20.0                         # m behind its stop a bus queued behind one there may serve it
const JUNCTION_REACH := 120.0               # m from a junction traffic is watched (6 s away at 70 km/h)

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
var may_glide := true:                      # false: always the physics (tests)
	set(on):
		may_glide = on
		if not on and gliding:
			_update_glide(true)             # at once, not at its next glide step
var assists := 0                            # times it glided on from a stall (tests)
var served := 0                             # stops served (tests)
var idle := false                           # stowed, waiting for traffic.gd to send it out again
var half_width := 1.3                       # m, half the vehicle's width
var obstacle_car: Node3D                    # the vehicle in the way, or null

var _pts := PackedVector2Array()
var _deck_z := PackedFloat32Array()         # per path point: the bridge deck's height (route "decks"), NAN on the ground
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
var _obstacle_parked := false               # still, no bot drives it, and room to overtake it: stop further back
var _blocked_t := 0.0
var _horn_t := 0.0
var _yield := -1                            # index into route["yields"] of the next give-way line, -1 none
var _conflict := false
var _stopped_at := -1                       # give-way line the bus has come to a full stop at (stop signs)
var _yield_wait := 0.0
var _stuck_t := 0.0
var _assist_to := -INF                      # glides until its reference point is this far along the path
var _held := false                          # frozen in place while stopped
var _still_t := 0.0                         # s stopped with nowhere to go
var _rng := RandomNumberGenerator.new()
var _last_tick := 0                         # physics frame it last moved on (drive, glide_step)
var _due := -1                              # gliding: physics frame of its next glide step (traffic.gd), -1 none
var _hold_at := INF                         # m from the front to where it has to stop (_plan): a glide step stops there
var _pedals := [0.0, 1.0, 0.0]              # last drive()
var _ignored := {}                          # vehicle -> s left driving past it as if it were not there (DEADLOCK)
var _pass := {}                             # overtaking: "car", "lat" (m right of the path: < 0), "from", "to" (s), or {}
var _room := PackedFloat32Array()           # m it may move left of the path, per path point


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
	half_width = car.half_extents.x
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
	_deck_z = PackedFloat32Array()
	if route.has("decks"):
		_deck_z.resize(_pts.size())
		_deck_z.fill(NAN)
		for span: Array in route["decks"]:
			var zs: Array = span[1]
			for k in zs.size():
				if int(span[0]) + k < _deck_z.size():
					_deck_z[int(span[0]) + k] = zs[k]
	_room = PackedFloat32Array()
	for run: Array in route.get("room", []):
		for k in int(run[0]):
			_room.append(float(run[1]))
	_pass = {}
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


## The surface the path runs on `d` m along it, at `p`: a bridge deck there (route "decks"), else the ground.
func _surface(d: float, p: Vector2) -> float:
	if not _deck_z.is_empty():
		var f := d / _step
		var i := clampi(int(f), 0, _deck_z.size() - 1)
		var j := mini(i + 1, _deck_z.size() - 1)
		var za := _deck_z[i]
		var zb := _deck_z[j]
		if not is_nan(za) and not is_nan(zb):
			return lerpf(za, zb, clampf(f - i, 0.0, 1.0))
		if not is_nan(za) or not is_nan(zb):
			return za if not is_nan(za) else zb
	return _ground(p)


## Car transform (origin on the ground) with the reference point at `d` along the path, its axles on the path.
func pose_at(d: float) -> Transform3D:
	var a := at(d - wheelbase * 0.5)
	var b := at(d + wheelbase * 0.5)
	var ha := _surface(d - wheelbase * 0.5, a)
	var hb := _surface(d + wheelbase * 0.5, b)
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
	var ha := _surface(st, a)
	var f := (hitch - Vector3(a.x, ha + _ride, -a.y)).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var basis := Basis(x, f.cross(x), f)
	return Transform3D(basis, Vector3(a.x, ha + _ride, -a.y) - basis * Vector3(0.0, 0.0, _trailer_axle))


# ---------------------------------------------------------------- driving

## car.gd, each physics tick while it drives with the physics: [throttle 0..1, brake 0..1, steering -1..1 (left
## positive)] (and `horn`). Gliding or stowed car.gd does not ask (_sync_ticks): traffic.gd moves it on (glide_step).
func drive(delta: float) -> Array:
	if not gliding:
		_pedals = _drive(delta)
		_last_tick = Engine.get_physics_frames()
	return _pedals


## traffic.gd, on the physics frame it is due while gliding (_due): moves it on by the time since it last moved
## (`tick`: s per physics tick).
func glide_step(tick: float) -> void:
	var now := Engine.get_physics_frames()
	_due = -1
	_pedals = _drive(tick * (now - _last_tick))
	_last_tick = now
	_schedule(false)


## Who moves it on: car.gd every tick with the physics (drive), traffic.gd every few ticks gliding (glide_step),
## nobody while stowed.
func _sync_ticks() -> void:
	var physics := not gliding and state != STOWED
	if car.is_physics_processing() != physics:
		car.set_physics_process(physics)
	if gliding and state != STOWED:
		if _due < 0:
			_last_tick = Engine.get_physics_frames()
			_schedule(true)
	else:
		_due = -1                           # (its entry in traffic.gd's slots is passed over)


## Its next glide step: GLIDE_TICKS ticks on, more the farther it is from every player and the camera (times
## traffic.gd glide_scale); the first one at a random tick within that, the bots spreading over the ticks.
func _schedule(first: bool) -> void:
	if not gliding or state == STOWED or _due >= 0:
		return
	var d2: float = traffic.eye_distance_squared(car.global_position)
	var n := GLIDE_TICKS_FAR if d2 > GLIDE_FAR * GLIDE_FAR else GLIDE_TICKS_MID if d2 > GLIDE_MID * GLIDE_MID \
			else GLIDE_TICKS
	n *= traffic.glide_scale
	_due = Engine.get_physics_frames() + (1 + _rng.randi() % n if first else n)
	traffic.schedule_glide(self, _due)


func _drive(delta: float) -> Array:
	_timer += delta
	horn = false
	if state == STOWED:
		return [0.0, 1.0, 0.0]
	_tick_ignored(delta)
	_update_glide()
	var v: float = _speed if gliding else car.speed()
	if not gliding:
		var p := project(flat(car.to_global(Vector3(0.0, 0.0, _ref_z))), s - 6.0, s + 20.0)
		s = p.x
		_ride = lerpf(_ride, car.global_position.y - _surface(s, flat(car.global_position)), 0.02)
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = GLIDE_LOOK_EVERY if gliding else LOOK_EVERY
		_look(v)
	var target := _plan(v, delta)
	if state == STOWED:
		return [0.0, 1.0, 0.0]
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
	return [throttle, brake, _pursue(_lane(s + ld)) / car.steer_limit(v)]


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
	_hold_at = INF
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
		target = _stop_within(target, d, "stop")
		if v < 0.4 and (d < STOP_REACH or (d < BERTH and _behind_dwelling())):
			_arrive()
			return 0.0
	# traffic lights
	for l: Dictionary in route["lights"]:
		var d := float(l["s"]) - front
		if d < -0.5:
			continue
		if d > maxf(90.0, v * v / (2.0 * BRAKE) + 20.0):
			break
		var c: int = traffic.light(traffic.clock(), l["phase"])
		if c == 2 or (c == 1 and d > v * v / (2.0 * AMBER_DECEL) + 1.0):
			target = _stop_within(target, d, "light")
		break
	# give way
	if _yield >= 0:
		var y: Dictionary = route["yields"][_yield]
		var d := float(y["s"]) - front
		if y["stop"] and _stopped_at != _yield:
			target = _stop_within(target, d, "stop sign")
			if d < 3.0 and v < 0.3:
				_stopped_at = _yield
		if _conflict and _yield_wait < YIELD_PATIENCE:
			target = _stop_within(target, d, "give way")
		if d < 3.0 and v < 0.3:
			_yield_wait += delta
	# vehicles ahead
	if _obstacle < INF:
		# (room behind a parked vehicle to pull out round it)
		var gap := GAP + PASS_IN + 2.0 if _obstacle_parked and _pass.is_empty() else GAP
		target = _limit(target, sqrt(_obstacle_v * _obstacle_v + 2.0 * HARD_BRAKE * maxf(_obstacle - gap, 0.0)) \
				if _obstacle > gap else 0.0, "vehicle ahead")
		_hold_at = minf(_hold_at, _obstacle - gap)
		_blocked_t = _blocked_t + delta if _obstacle_still and v < 0.3 else 0.0
		if _blocked_t > DEADLOCK and _deadlocked():
			_ignore_for(obstacle_car, PASS_TIME)
		if _blocked_t > PASS_AFTER and _pass.is_empty():
			_overtake(front)
		if _blocked_t > GIVE_UP and not _player_within(car.global_position, GIVE_UP_SEEN):
			_stow()
			return 0.0
		if _blocked_t > HORN_AFTER:
			_horn_t += delta
			horn = fmod(_horn_t, 8.0) < 0.5
	else:
		_blocked_t = 0.0
		_horn_t = 0.0
	if not _pass.is_empty():
		target = _limit(target, PASS_SPEED, "overtaking")
		if s > float(_pass["to"]) + PASS_IN:
			_pass = {}
	# end of the route
	var left := _length - front
	if route["then"] == "continue":
		if left < 1.0 and _next_stop >= stops.size():
			_next_route()
	else:
		target = _stop_within(target, left - 1.0, "end")
		if left < 3.0 and v < 0.4:
			_end_of_route()
			return 0.0
	return target


func _limit(target: float, v: float, why: String) -> float:
	if v < target:
		reason = why
		return v
	return target


## The speed from which it stops within `d` m at the planned braking (_limit); a glide step does not run past that point
## either (_glide).
func _stop_within(target: float, d: float, why: String) -> float:
	_hold_at = minf(_hold_at, d)
	return _limit(target, _reach(d, BRAKE), why)


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
	if gliding:
		_dwell *= 0.5                       # nobody sees it: the line keeps moving


func _dwell_at_stop() -> void:
	if _dwell > DWELL_TIME.y and _timer > DWELL_TIME.x * (0.5 if gliding else 1.0) and _timer < _dwell and _queued_behind():
		_dwell = _timer                     # a layover: the next bus is there
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
	if traffic.riders(car) > 0:
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
	if route["end"] != "terminus" or _timer > WATCH_MAX or _queued_behind() \
			or not _player_within(car.global_position, WATCHED):
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


## Off the map (hidden, out of the physics) until traffic.gd sends it out again (put).
func _stow() -> void:
	state = STOWED
	idle = true
	_timer = 0.0
	car.set_indicator(0)
	car.set_doors(false)
	car.set_stowed(true)
	gliding = false
	_held = false
	_speed = 0.0
	obstacle_car = null
	_pass = {}
	_forget_ignored()
	_sync_ticks()


## True when a bus of this line waits right behind this one (at a terminus: it takes the place).
func _queued_behind() -> bool:
	var back := s - tail
	for b: Object in traffic.bots:
		if b == self or b.state == STOWED or not is_same(b.line, line):
			continue
		var q := project(flat(b.car.to_global(b.car.extents_center)), back - QUEUE_REACH, back)
		if q.x > back - QUEUE_REACH and q.x < back and absf(q.y) < 2.0:
			return true
	return false


func _place(xf: Transform3D) -> void:
	car.place(xf.translated(Vector3.UP * 0.05))
	if car.trailer:
		car.trailer.global_transform = _trailer_pose(xf, s).translated(Vector3.UP * 0.05)


## Puts the bus on route `index` (into line["routes"]) with its reference point `d` m along it, driving at `speed`
## (traffic.gd sends it out with it; tests).
func put(index: int, d: float, speed := 0.0) -> void:
	_set_route(index)
	s = d
	state = DRIVE
	idle = false
	_timer = 0.0
	_leaving_s = -INF
	_stuck_t = 0.0
	_blocked_t = 0.0
	_still_t = 0.0
	_held = false
	_forget_ignored()
	_pass = {}
	obstacle_car = null
	_obstacle = INF
	_look_t = 0.0
	car.set_indicator(0)
	car.set_doors(false)
	car.set_stowed(false)
	_speed = speed
	_place(pose_at(s))
	_update_glide(true)
	_speed = speed                          # (a body just moved by hand reports wild speeds)


# ---------------------------------------------------------------- looking around

## Vehicles in the way on the path ahead, and whether to wait at the next give-way line.
func _look(v: float) -> void:
	var front := s + nose
	var reach := 10.0 + v * v / (2.0 * BRAKE) + 15.0
	_obstacle = INF
	_obstacle_still = false
	var tip := at(front)
	obstacle_car = null
	var cars: Array = traffic.snap_cars
	var pos: PackedVector2Array = traffic.snap_pos
	var reaches: PackedFloat32Array = traffic.snap_reach
	for k: int in traffic.near(tip, reach + traffic.snap_reach_max + 5.0):
		var c: Node3D = cars[k]
		if c == car or _ignored.has(c):
			continue
		var centre := pos[k]
		if centre.distance_to(tip) > reach + reaches[k] + 5.0:
			continue
		# facing the other way in the other lane (moving or waiting): its corners may come close on a narrow road, but
		# it passes by; both waiting for each other would never end. Gliding (nobody sees it): any facing the other way.
		var cq := project(centre, front - 5.0, front + reach + 10.0)
		var path_dir := (at(cq.x + 1.0) - at(cq.x)).normalized()
		if (cq.y - _shift(cq.x - nose) < -ONCOMING_SIDE or gliding) and traffic.snap_fwd[k].dot(path_dir) < -0.5:
			continue
		# its footprint, looked for about its middle along the path: none of it is in the way when that is out of reach
		var rk := reaches[k] + 4.0
		if cq.x + rk < front - 0.5 or cq.x - rk > front + reach \
				or absf(cq.y - _shift(cq.x - nose)) > half_width + SIDE_MARGIN + rk:
			continue
		var lo := maxf(front - 1.0, cq.x - rk)
		var hi := minf(front + reach, cq.x + rk)
		var hit := INF
		for p in traffic.snap_footprint(k):
			var q := project(p, lo, hi)
			if q.x > front - 0.5 and q.x < front + reach and absf(q.y - _shift(q.x - nose)) < half_width + SIDE_MARGIN:
				hit = minf(hit, q.x - front)
		if hit < _obstacle:
			_obstacle = maxf(hit, 0.0)
			obstacle_car = c
			var dir := (at(front + hit + 1.0) - at(front + hit)).normalized()
			var vel: Vector2 = traffic.snap_vel[k]
			_obstacle_v = maxf(vel.dot(dir), 0.0)
			_obstacle_still = vel.length() < 0.5
			_obstacle_parked = _obstacle_still and (not c.is_bot() or c.broken) \
					and _room_at(front + hit) > c.half_extents.x + half_width + PASS_ROOM
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
	if _yield >= 0 and float(yields[_yield]["s"]) - front < maxf(60.0, v * v / (2.0 * BRAKE) + 15.0):
		_conflict = _junction_busy(yields[_yield], front)


## Velocity (pipeline x/y) of vehicle `c`: a bot gliding along its path is frozen (no physics velocity), yet it moves.
static func velocity_of(c: Node3D) -> Vector2:
	var b: Object = c.pilot
	if b != null and b.gliding:
		return flat(c.global_basis.z) * float(b._speed)
	return flat(c.linear_velocity)


## Drives on as if `c` were not there for `t` s, the two not colliding meanwhile.
func _ignore_for(c: Node3D, t: float) -> void:
	_ignored[c] = t
	_ghost(c, true)
	_look_t = 0.0                           # what else is in the way


## Overtakes the vehicle in the way when no bot drives it, there is room on the left and the way is free. Gliding, it
## passes through it instead.
func _overtake(front: float) -> void:
	var c := obstacle_car
	if c == null or (c.is_bot() and not c.broken):
		return
	if gliding:
		_ignore_for(c, PASS_TIME)
		return
	# its extent along the path, and how far left the bus must go
	var x0 := INF
	var x1 := -INF
	var leftmost := INF
	for p in footprint(c):
		var q := project(p, front - 2.0, front + _obstacle + 30.0)
		x0 = minf(x0, q.x)
		x1 = maxf(x1, q.x)
		leftmost = minf(leftmost, q.y)
	var lat := minf(leftmost - half_width - PASS_ROOM, 0.0)
	var from := x0 - nose - 2.0
	var to := x1 + tail + 2.0
	if s > from - PASS_IN * 0.7:
		return                              # too close behind it to pull out
	# room on the left all along, and nothing that holds the traffic just past it
	for d in range(int(from - PASS_IN), int(to + PASS_IN), int(_step)):
		if _room_at(float(d)) < -lat:
			return
	var past := x1 + 25.0
	for l: Dictionary in route["lights"]:
		if float(l["s"]) > front and float(l["s"]) < past:
			return
	for y: Dictionary in route["yields"]:
		if float(y["s"]) > front and float(y["s"]) < past:
			return
	if _next_stop < route["stops"].size() and float(route["stops"][_next_stop]["s"]) < past:
		return
	# the lane it takes free: nothing in it for PASS_CLEAR m past the vehicle, nothing just past it in its own
	var cars: Array = traffic.snap_cars
	var tip := at(front)
	for k in cars.size():
		var o: Node3D = cars[k]
		if o == car or o == c or traffic.snap_pos[k].distance_to(tip) > x1 - front + PASS_CLEAR + 20.0:
			continue
		var q := project(traffic.snap_pos[k], front - 10.0, x1 + PASS_CLEAR)
		if q.x < front - 10.0 or q.x > x1 + PASS_CLEAR:
			continue
		if q.y < 1.5 and q.y > lat - half_width - 2.0 and (q.y < -1.5 or q.x < x1 + 15.0):
			return
	_pass = {"car": c, "lat": lat, "from": from, "to": to}


## How far left of the path (m) it may move `d` m along it.
func _room_at(d: float) -> float:
	if _room.is_empty():
		return 0.0
	return _room[clampi(roundi(d / _step), 0, _room.size() - 1)]


## Offset (m right of the path) of the reference point `d` m along it: 0 but while overtaking.
func _shift(d: float) -> float:
	if _pass.is_empty():
		return 0.0
	var w := clampf(minf((d - (float(_pass["from"]) - PASS_IN)) / PASS_IN, (float(_pass["to"]) + PASS_IN - d) / PASS_IN),
			0.0, 1.0)
	return float(_pass["lat"]) * w * w * (3.0 - 2.0 * w)


## Where the reference point heads for `d` m along the path: on it, or beside it while overtaking.
func _lane(d: float) -> Vector2:
	var p := at(d)
	var sh := _shift(d)
	if sh == 0.0:
		return p
	var t := (at(d + 1.0) - p).normalized()
	return p + Vector2(t.y, -t.x) * sh


## Stopped right behind a bus with its doors open at a stop.
func _behind_dwelling() -> bool:
	var c := obstacle_car
	return c != null and c.pilot != null and c.pilot.state == DWELL and _obstacle < GAP + 2.0


func _tick_ignored(delta: float) -> void:
	for c: Node3D in _ignored.keys():
		_ignored[c] -= delta
		if _ignored[c] <= 0.0:
			_ghost(c, false)
			_ignored.erase(c)


func _forget_ignored() -> void:
	for c: Node3D in _ignored:
		_ghost(c, false)
	_ignored.clear()


## No collisions between this vehicle and `c` (on), or back (off).
func _ghost(c: Node3D, on: bool) -> void:
	if not is_instance_valid(c):
		return
	for a: VehicleBody3D in car.bodies():
		for b: VehicleBody3D in c.bodies():
			if on:
				a.add_collision_exception_with(b)
			else:
				a.remove_collision_exception_with(b)


## Waiting for a bot that waits for this one, longer than DEADLOCK s: true for one of the two (it drives on).
func _deadlocked() -> bool:
	var c := obstacle_car
	if c == null or c.pilot == null or c.pilot.obstacle_car != car:
		return false
	return c.pilot._blocked_t > DEADLOCK and car.get_instance_id() < c.get_instance_id()


## Footprint points (pipeline x/y) of a vehicle: the corners and middle of each section's body box.
static func footprint(c: Node3D) -> PackedVector2Array:
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
	var cars: Array = traffic.snap_cars
	var pos: PackedVector2Array = traffic.snap_pos
	for k: int in traffic.near(j, JUNCTION_REACH):
		var c: Node3D = cars[k]
		if c == car:
			continue
		var p := pos[k]
		var d := p.distance_to(j)
		if d > JUNCTION_REACH:
			continue
		var vel: Vector2 = traffic.snap_vel[k]
		# behind the bus or beside it in its lane: not crossing its way
		var q := project(p, front - 40.0, front + 2.0)
		if absf(q.y) < 3.0 and q.x < front + 1.0:
			continue
		var out := (p - j) / maxf(d, 0.1)
		if d < r:
			# moving in the junction: in the way when it came from a conflicting arm and has not left yet (one on its
			# way out, or passing by on its side, is the vehicles-ahead look's business)
			var v := vel.length()
			if v < 0.7 or vel.dot(out) > 0.5 * v * minf(d / 3.0, 1.0):
				continue
			for a: Array in y["arms"]:
				if -vel.dot(Vector2(a[0], a[1])) > 0.6 * v:
					return true
			continue
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
	return traffic.player_within(p, d)


## A player stands by one of the open doorways outside, about to get in, or inside in the doorway itself (one who got
## in and walks on does not keep the doors open: the bus leaves after its usual dwell).
func _player_at_door() -> bool:
	var spots: Array = traffic.game.player_spots(true)
	for b: Node3D in car.bodies():
		for dc: Vector3 in b.door_centres:
			var g: Vector3 = b.to_global(dc)
			for q: Vector3 in spots:
				if car.carrier_at(q) == null:
					if q.distance_to(g) < DOOR_REACH:
						return true
				elif Vector2(q.x - g.x, q.z - g.z).length() < DOORWAY:
					return true
	return false


# ---------------------------------------------------------------- gliding far from the players

## Glides when no player is within FAR m (NEAR m to stop gliding) and nobody rides it; `force` decides afresh.
func _update_glide(force := false) -> void:
	var p: Vector3 = car.to_global(car.extents_center)
	var near: bool = not may_glide or _player_within(p, NEAR if gliding else FAR) or traffic.riders(car) > 0
	var want: bool = not near or s < _assist_to
	if want == gliding and not force:
		return
	if want and not gliding:
		_speed = clampf(car.speed(), 0.0, car.max_speed)     # (a body just moved by hand reports wild speeds)
		if not _pass.is_empty():
			_ignore_for(_pass["car"], PASS_TIME)    # back on its path: through what it was overtaking
			_pass = {}
	gliding = want
	_held = false
	_freeze(want, _speed)
	_sync_ticks()


## Freezes the bodies in place (gliding: static, out of the wheel and contact physics; held: kinematic) or lets them
## go at `speed` along the bus.
func _freeze(on: bool, speed := 0.0) -> void:
	for b: VehicleBody3D in car.bodies():
		b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC if on and gliding else RigidBody3D.FREEZE_MODE_KINEMATIC
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


## Moves the bus along its path at up to `target` m/s, never past where it has to stop (a step far from everyone is
## long); returns the steering angle that shows for it.
func _glide(target: float, delta: float) -> float:
	_speed = move_toward(_speed, target, (GLIDE_ACCEL if target > _speed else HARD_BRAKE) * delta)
	var ds := _speed * delta
	if ds > _hold_at:
		ds = maxf(_hold_at, 0.0)
		_speed = ds / delta if delta > 0.0 else 0.0
	s += ds
	if _obstacle < INF:
		_obstacle += _obstacle_v * delta - ds     # until the next look
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
