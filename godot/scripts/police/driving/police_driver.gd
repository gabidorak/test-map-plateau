extends "res://scripts/traffic/bus_bot.gd"
## A police car's driver (unit.gd's, one per car of the fleet). It does one thing at a time, as its unit says:
## - Its way (follow: a route of road_graph.gd make_route), stopping at its end (`arrived`) instead of vanishing. Siren
##   off (`urgent` false): the traffic's bot driver (bus_bot.gd: its lane, the lights, the give-ways, what is ahead,
##   gliding far from the players). Siren on: the urgent speeds of its route (road_graph.gd "vu": the grip in the bends
##   only), through the red lights and the give-ways, pulling over for nobody; far from every player it glides along at
##   those speeds (GLIDE_ACCEL_URGENT), near one the pursuit pilot drives (pursuit_pilot.gd: off the lanes wherever
##   there is room), heading for its route a point LOOK ahead.
## - A quarry (set_quarry, tactics/pursuit.gd; siren on, near a player): the pursuit pilot drives at them as `how` says:
##   FOLLOW (up alongside their rear when near), RAM their back, PIT (from alongside, a sharp turn into their rear axle:
##   `knocked`, and police.gd breaks their rear tyres loose), PASS them (up beside their front and on), CUT in front of
##   them and brake, STOP by them without touching them (someone on foot: STOP_BY_GAP m short of them; a vehicle:
##   STOP_GAP m off it, on the side it comes from, or ahead of it, its way out, when told `ahead`). It keeps to one side of them (SIDE_SWITCH; or the side it is told).
## - Braked (`braked`: its officer out, a roadblock): it stops where it is, then lies asleep as a parked car (never
##   frozen: a knock wakes it and moves it).
## - Its levels of detail, as GTA's: stowed (in police.gd's pool: nothing at all), gliding (no player within bus_bot.gd
##   FAR m: posed along its way, no physics), the pursuit pilot looking light (no player or camera within
##   PursuitPilot.DETAIL m, no quarry: fewer looks, fewer ways weighed), the pursuit pilot in full.

const PursuitPilot = preload("res://scripts/police/driving/pursuit_pilot.gd")

signal knocked(them: Node3D, seconds: float)    # its PIT hit them: their rear tyres loose for that long

enum { FOLLOW, RAM, PIT, PASS, CUT, STOP }

const GLIDE_ACCEL_URGENT := 3.5             # m/s², gliding with its siren on
const LOOK := Vector2(8.0, 25.0)            # m ahead along its route it heads for, at least and at most (no corner
											# cut through what stands inside a bend)...
const LOOK_PER_SPEED := 0.5                 # ...plus this many s of its speed
const ARRIVE := 6.0                         # m from its route's end: there (once slow)
const FOLLOW_GAP := 25.0                    # m from its quarry it comes up alongside their rear (FOLLOW)...
const CLOSING := 4.0                        # ...faster than them by this (m/s, a quarter of it alongside); RAM too
const LEAD_MAX := 1.2                       # s ahead of its quarry it aims at most (FOLLOW, further)
const PIT_GAP := 0.6                        # m between the two cars alongside (FOLLOW)
const PIT_LEAD := 0.15                      # s ahead along their way a PIT aims into their rear...
const PIT_CLOSING := 1.5                    # ...this much faster than them (m/s)
const PIT_LOOSE := 1.2                      # s their rear tyres stay loose once hit
const PASS_GAP := 0.8                       # m between the two cars passing (PASS)...
const PASS_AHEAD := 5.0                     # ...its nose this far ahead of theirs...
const PASS_CLOSING := 6.0                   # ...faster than them by this (m/s)
const CUT_AHEAD := 5.0                      # m ahead of their nose it cuts in (CUT)...
const CUT_SLOW := 0.75                      # ...going this much of their speed (braking them)
const STOP_GAP := 3.0                       # m off their vehicle it stops (STOP)...
const STOP_BY_GAP := 6.0                    # ...short of someone on foot
const SIDE_SWITCH := 1.5                    # m to the other side of its quarry before it keeps to that side
const EXTRAPOLATE := 1.0                    # s at most someone on foot is carried on from where they were last known
const KEEP_GOING := 40.0                    # m past its way's end a chaser goes on at full speed at most

var urgent := false
var arrived := true                         # at the end of its route, waiting for the next
var braked := false:                        # stopped where it is (its officer out, a roadblock)...
	set(on):
		if braked and not on and car:       # (...asleep as a parked car meanwhile: woken, or its engine pulls nothing)
			_still_t = 0.0
			for b: VehicleBody3D in car.bodies():
				b.sleeping = false
		braked = on
var keep_going := false                     # its way's end no place to stop at (a chaser's: plotted afresh before)
var route_key := ""                         # its route's id in traffic.gd routes (its own, replaced at each follow)
var pursuit := PursuitPilot.new()           # its driving off the lanes
## what it drives at instead of its route ({} none): {"car" (or null: on foot), "pos" (global), "vel" (global m/s),
## "how", "side" (1 their left, -1 their right; optional), "ahead" (STOP by a vehicle ahead of it; optional), "at"
## (its clock then)}
var quarry := {}
var _knocked_at := -INF                     # its clock when its PIT last knocked them
var _side := 0.0                            # the side of its quarry it keeps to (1 their left), 0 none yet


func setup(t: Node, vehicle: Node3D, bus_line: Dictionary, index: int) -> void:
	super(t, vehicle, bus_line, index)
	pursuit.setup(self, vehicle)


## Drives route `r` (road_graph.gd make_route) from where it is now (on it, near its start).
func follow(r: Dictionary) -> void:
	traffic.routes[route_key] = r
	line = {"ref": "police", "routes": [route_key]}
	_set_route(0)
	s = maxf(project(where(), 0.0, 40.0).x, 0.0)
	state = DRIVE
	arrived = false
	_timer = 0.0
	_blocked_t = 0.0
	_stuck_t = 0.0


## Out of the pool (police.gd: where nobody sees) onto route `r`, at its start, or at `xf` (Transform3D) when given (on
## it, near its start); gliding or not as the players' distance says.
func appear(r: Dictionary, xf: Variant = null) -> void:
	traffic.routes[route_key] = r
	line = {"ref": "police", "routes": [route_key]}
	set_quarry({})
	braked = false
	put(0, minf(tail + 1.0, float(r["length"])), 0.0)
	if xf != null:
		car.place(xf)
		s = maxf(project(where(), 0.0, 40.0).x, 0.0)
		_update_glide(true)
	arrived = false
	pursuit.reset()


## Back into the pool: siren off, off the map (hidden, out of the physics: bus_bot.gd _stow).
func vanish() -> void:
	set_quarry({})
	braked = false
	arrived = true
	set_urgent(false)
	may_glide = true
	_stow()


## Siren and blue lights on or off, the route's speeds with them.
func set_urgent(on: bool) -> void:
	urgent = on
	car.siren = on
	if route.has("vu"):
		_v = PackedFloat32Array(route["vu" if on else "v"])


## Drives at `q` (see `quarry`); {} back to its route.
func set_quarry(q: Dictionary) -> void:
	quarry = q
	if q.is_empty():
		_side = 0.0
	else:
		quarry["at"] = _clock


## Where it is on the map (its reference point), pipeline x/y.
func where() -> Vector2:
	return flat(car.to_global(Vector3(0.0, 0.0, _ref_z)))


## Its heading on the map (unit).
func facing() -> Vector2:
	var f: Vector3 = car.global_basis.z
	return Vector2(f.x, -f.z).normalized()


## Whether the pursuit pilot has the wheel (siren on, with the physics).
func pursuing() -> bool:
	return urgent and not gliding and state != STOWED and not seized


## m of its way left to drive.
func left() -> float:
	return _length - s


## s it has been blocked by a vehicle in its way (the lanes' driving).
func blocked_time() -> float:
	return _blocked_t


# ---------------------------------------------------------------- driving

func drive(delta: float) -> Array:
	if not urgent or gliding or state == STOWED or seized:
		return super(delta)
	_update_glide()                         # (no player near any more: it glides on)
	if gliding:
		return super(delta)
	_timer += delta
	_clock += delta
	horn = false
	_last_tick = Engine.get_physics_frames()
	s = project(where(), s - 10.0, s + 60.0).x
	if _held:                               # (frozen still by the lanes' driving: let go, a car like any other)
		_held = false
		_freeze(false)
	if braked:                              # (still HOLD s: asleep as a parked car, no creeping down a slope)
		_still_t = _still_t + delta if absf(car.speed()) < 0.3 else 0.0
		if _still_t > HOLD and not car.sleeping:
			for b: VehicleBody3D in car.bodies():
				b.sleeping = true
		_pedals = [0.0, 1.0, 0.0]
		return _pedals
	if quarry.is_empty():
		_along_route(car.speed())
	else:
		_at_quarry()
	_pedals = pursuit.drive(delta)
	return _pedals


## Heads for a point along its route, LOOK ahead, at the route's urgent speeds; stops at its end (arrived).
func _along_route(v: float) -> void:
	pursuit.target = null
	pursuit.sharp = false
	pursuit.stop_short = 0.0
	pursuit.limit = _planned(s + 2.0)
	var ahead := clampf(LOOK.x + LOOK_PER_SPEED * absf(v), LOOK.x, LOOK.y)
	var left := _length - s
	if left > ahead or (keep_going and left > -KEEP_GOING):
		pursuit.aim = _global(at(s + ahead))    # (past its end: on straight, at full speed, till its next way)
		pursuit.aim_speed = INF
		return
	pursuit.aim = _global(at(_length))
	pursuit.aim_speed = 0.0
	if left < ARRIVE and absf(v) < 2.0 and not arrived:
		_end_of_route()


## Heads for its quarry as it is to close in (`how`): their vehicle where it is now (here, the host), someone on foot
## where they were last known, carried on at their speed.
func _at_quarry() -> void:
	var them: Node3D = quarry["car"] if is_instance_valid(quarry["car"]) else null
	var vel: Vector3 = quarry["vel"]
	var p: Vector3 = them.global_position if them \
			else (quarry["pos"] as Vector3) + vel * minf(_clock - float(quarry["at"]), EXTRAPOLATE)
	var speed := Vector2(vel.x, vel.z).length()
	var how: int = quarry["how"]
	pursuit.limit = INF
	pursuit.stop_short = 0.0
	pursuit.aim_speed = INF
	pursuit.sharp = how == PIT
	pursuit.target = them if how in [FOLLOW, RAM, PIT, PASS, CUT] else null     # (STOP: no contact)
	var side := _keep_side(them) if them else 1.0
	var nose: float = car.extents_center.z + car.half_extents.z - _ref_z         # (the pilot aims its front)
	match how:
		FOLLOW:
			var here := car.global_position
			if them and Vector2(p.x - here.x, p.z - here.z).length() < FOLLOW_GAP:
				pursuit.aim = _beside(them, side, -(them.half_extents.z * 0.6 + car.half_extents.z), PIT_GAP) \
						+ _ahead_of(them) * nose
				pursuit.aim_speed = speed + CLOSING * 0.25
			else:
				var dist := Vector2(p.x - here.x, p.z - here.z).length()
				pursuit.aim = p + vel * clampf(dist / 25.0, 0.2, LEAD_MAX)
		RAM:
			pursuit.aim = p + vel * 0.3
			pursuit.aim_speed = speed + CLOSING
		PIT:
			pursuit.aim = (_rear_axle(them) if them else p) + vel * PIT_LEAD
			pursuit.aim_speed = speed + PIT_CLOSING
			if them and _clock > _knocked_at + PIT_LOOSE and car.get_colliding_bodies().has(them):
				_knocked_at = _clock
				knocked.emit(them, PIT_LOOSE)
		PASS:
			pursuit.aim = (_beside(them, side, them.half_extents.z + PASS_AHEAD, PASS_GAP) if them else p) + vel * 0.3
			pursuit.aim_speed = speed + PASS_CLOSING
		CUT:
			var way: Vector3 = _ahead_of(them) if them else vel.normalized()
			var front: float = them.half_extents.z if them else 2.0
			pursuit.aim = p + way * (CUT_AHEAD + front) + vel * 0.2
			pursuit.limit = speed * CUT_SLOW
		STOP:
			pursuit.aim_speed = 0.0
			if them and quarry.get("ahead", false):     # (ahead of them, its rear STOP_GAP m off their nose)
				var off: float = them.half_extents.z + STOP_GAP + 2.0 * car.half_extents.z
				pursuit.aim = them.to_global(them.extents_center + Vector3(0.0, 0.0, off))
			elif them:                      # (on the side of them it comes from, its nose STOP_GAP m off them)
				var out: Vector3 = car.global_position - them.global_position
				out.y = 0.0
				pursuit.aim = them.global_position + out.normalized() * (them.half_extents.z + STOP_GAP)
			else:
				pursuit.aim = p
				pursuit.stop_short = STOP_BY_GAP


## The side of vehicle `them` it keeps to (1 their left, -1 their right): the one it is told, else where it is, changed
## only once SIDE_SWITCH m on the other side.
func _keep_side(them: Node3D) -> float:
	if quarry.has("side"):
		_side = float(quarry["side"])
		return _side
	var x: float = them.to_local(car.global_position).x
	if _side == 0.0 or (absf(x) > SIDE_SWITCH and signf(x) != _side):
		_side = signf(x) if x != 0.0 else 1.0
	return _side


## Beside vehicle `them` on side `side` (1 their left), `along` m from its middle (forward), `gap` m out from it: where
## its own middle goes alongside them.
func _beside(them: Node3D, side: float, along: float, gap: float) -> Vector3:
	return them.to_global(them.extents_center + Vector3(side * (them.half_extents.x + car.half_extents.x + gap), 0.0,
			along))


## Where vehicle `them` heads (flat, unit).
static func _ahead_of(them: Node3D) -> Vector3:
	var f: Vector3 = them.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


## On the middle line of vehicle `them`, at its rear axle: where a PIT steers into it from alongside.
static func _rear_axle(them: Node3D) -> Vector3:
	return them.to_global(them.extents_center + Vector3(0.0, 0.0, -them.half_extents.z * 0.55))


func _global(q: Vector2) -> Vector3:
	return Vector3(q.x, car.global_position.y, -q.y)


# ---------------------------------------------------------------- bus_bot.gd's hooks

func _set_route(index: int) -> void:
	super(index)
	if urgent and route.has("vu"):
		_v = PackedFloat32Array(route["vu"])


func _end_of_route() -> void:
	state = TERMINUS
	_timer = 0.0
	arrived = true


func _wait_at_terminus() -> void:
	pass                                    # (stays there until its unit sends it on)


func _minds_lights() -> bool:
	return not urgent


func _minds_yields() -> bool:
	return not urgent


func _makes_way() -> bool:
	return not urgent


func _speed_scale() -> float:
	return 0.0 if braked else 1.0


func _glide_accel() -> float:
	return GLIDE_ACCEL_URGENT if urgent else GLIDE_ACCEL


func _may_vanish() -> bool:
	return false
