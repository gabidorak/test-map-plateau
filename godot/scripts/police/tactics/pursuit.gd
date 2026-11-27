extends RefCounted
## How the cars chasing someone seen close in on them (police.gd runs it on the host every LOOK_EVERY s for each case
## seen; its chasers: unit.gd's CHASE cars on the case, PACK at most).
## - A chaser with the physics (the pursuit pilot: near a player), within DIRECT m of them and in sight, drives straight
##   at them in its role; the others go to where they were last seen (unit.gd go: along the lanes, then off them up to
##   them), sent afresh once that is REPLOT m off (REPLOT_EVERY s apart at most).
## - On foot: they drive up and STOP by them (the officers get out: foot/arrest.gd).
## - In a vehicle, a role each, nearest first:
##   - the first (PITTER) comes up alongside their rear (FOLLOW) and, there at speed (PIT_SPEED; PIT_ALONG m behind
##     their middle, PIT_SIDE m aside), turns into their rear axle (PIT), PIT_HOLD s at most, then falls back PIT_REST s;
##   - the second (PASSER) overtakes them on the other side (PASS) and, PASS_DONE m ahead of them, cuts in front of them
##     and brakes (CUT), until it is back under PASS_BACK m;
##   - the others press on behind (FOLLOW); slower than RAM_SPEED, those behind them and facing them push into them (RAM).
##   Stopped (under STILL m/s; on the move again over MOVING m/s): boxed in without a touch, the passer STOPs ahead of
##   them (their way out), the others by them on the side they come from, and the officers get out (foot/arrest.gd).
## - Not seen any more (release): those straight at them back on their ways.
## Positions are pipeline x/y (x east, y north) unless global.

const Unit = preload("res://scripts/police/unit.gd")
const Driver = preload("res://scripts/police/driving/police_driver.gd")

enum { PITTER, PASSER, PRESSER }

const DIRECT := 150.0                       # m: within this and in sight, a chaser drives straight at them
const REPLOT := 12.0                        # m their last seen spot moves before a chaser's way there is plotted afresh...
const LEAD := 2.0                           # s ahead of them at their speed the others' way goes (not where they were)
const REPLOT_EVERY := 1.0                  # ...at most this often (s)
const STILL := 1.5                          # m/s: their vehicle slower than this, they are stopped...
const MOVING := 3.0                         # ...faster than this, on the move again
const RAM_SPEED := 8.0                      # m/s: slower than this, those behind push into them...
const RAM_REACH := 25.0                     # ...from this near, facing them (cos of the angle, at least):
const RAM_FACING := 0.5
const PIT_SPEED := Vector2(7.0, 50.0)       # m/s: a PIT on them this fast
const PIT_ALONG := Vector2(2.0, 5.0)        # m behind their middle (its nose about their rear axle)...
const PIT_SIDE := Vector2(1.4, 3.2)         # ...and aside a chaser starts a PIT
const PIT_HOLD := 1.5                       # s a PIT goes on at most...
const PIT_REST := 3.0                       # ...and before the next
const PASS_DONE := 6.0                      # m ahead of their middle the passer cuts in front of them...
const PASS_BACK := 1.0                      # ...and passes again once back under this

var police: Node                            # police.gd
var _stopped := {}                          # peer -> whether their vehicle is stopped (STILL, MOVING)
var _cars := {}                             # unit index -> {"how", "pit_t", "rest_t", "asked_at"}


func _init(p: Node) -> void:
	police = p


## Who player `peer`'s case `c` is after, as quarry (`s`: police.gd suspect): {"pos" (global), "car" (or null), "vel"
## (global m/s, flat), "dir" (global, flat, unit), "speed", "xy" (map), "dir_xy" (map)}.
static func quarry_of(c: RefCounted, s: Dictionary) -> Dictionary:
	var car: Node3D = s["car"]
	var vel := Vector3(c.vel.x, 0.0, -c.vel.y)
	if car and not car.remote:
		vel = car.linear_velocity
		vel.y = 0.0
	var dir := vel.normalized() if vel.length() > 1.0 else Vector3.ZERO
	if dir == Vector3.ZERO and car:
		dir = Vector3(car.global_basis.z.x, 0.0, car.global_basis.z.z).normalized()
	var pos: Vector3 = s["pos"]
	return {"pos": pos, "car": car, "vel": vel, "dir": dir, "speed": vel.length(), "xy": Vector2(pos.x, -pos.z),
			"dir_xy": Vector2(dir.x, -dir.z)}


## Every LOOK_EVERY s, case `c` seen, its quarry `q` (quarry_of): each chaser straight at them in its role, or on its
## way to where they were last seen.
func update(c: RefCounted, q: Dictionary) -> void:
	var near: Array = []                    # [m from them, unit index]
	for u: Unit in police.units:
		if u.job != Unit.CHASE or u.case != c.peer:
			continue
		var here: Vector3 = u.car.global_position
		var d := Vector2(here.x - q["pos"].x, here.z - q["pos"].z).length()
		if u.driver.pursuing() and d < DIRECT and police.in_sight(here + Vector3.UP * 1.2,
				(q["pos"] as Vector3) + Vector3.UP, [u.car.get_rid()] + ([q["car"].get_rid()] if q["car"] else [])):
			near.append([d, u.index])
		else:
			_off(u)
			_approach(u, c)
	near.sort()
	var stopped := _is_stopped(c.peer, q)
	var roles := _roles(near, q)
	var pit_side := 0.0
	for k in near.size():
		if roles[k] == PITTER:
			pit_side = _side_of(police.units[near[k][1]], q)
	for k in near.size():
		var u: Unit = police.units[near[k][1]]
		var rel: Vector3 = u.car.global_position - q["pos"]
		rel.y = 0.0
		var how := _how(u, roles[k], rel, q, stopped)
		var order := {"car": q["car"], "pos": q["pos"], "vel": q["vel"], "how": how}
		if how in [Driver.PASS, Driver.CUT] and pit_side != 0.0:
			order["side"] = -pit_side       # (it passes on the other side from the one at their rear)
		if how == Driver.STOP and roles[k] == PASSER:
			order["ahead"] = true
		_state(u)["how"] = how
		u.close_in(order)
	_tidy()


## Case `c` not seen any more: those straight at them back on their ways.
func release(c: RefCounted) -> void:
	for u: Unit in police.units:
		if u.job == Unit.CHASE and u.case == c.peer:
			_off(u)
	_stopped.erase(c.peer)


## Whether chaser `u` drives straight at them now, and how (police_driver.gd FOLLOW...; -1 not).
func how_of(u: Unit) -> int:
	return int(_cars.get(u.index, {}).get("how", -1))


## Chaser `u` not straight at them (any more).
func _off(u: Unit) -> void:
	u.close_in({})
	if _cars.has(u.index):
		_cars[u.index]["how"] = -1


## Chaser `u` on its way to where case `c`'s quarry will be LEAD s on (at their speed when last seen), plotted afresh
## once that moved REPLOT m, or once it is at its way's end still REPLOT m from there. (Its way's end no stop: unit.gd
## CHASE, police_driver.gd keep_going.)
func _approach(u: Unit, c: RefCounted) -> void:
	var st := _state(u)
	var aim: Vector2 = c.last + c.vel * LEAD
	if (is_nan(u.spot.x) or u.spot.distance_to(aim) > REPLOT or (u.there() and u.where().distance_to(aim) > REPLOT)) \
			and police.time - float(st["asked_at"]) > REPLOT_EVERY:
		st["asked_at"] = police.time
		u.go(aim, true, aim)


## Whether player `peer`'s vehicle is stopped (under STILL m/s, till over MOVING); someone on foot: no.
func _is_stopped(peer: int, q: Dictionary) -> bool:
	if q["car"] == null:
		return false
	var was: bool = _stopped.get(peer, false)
	_stopped[peer] = float(q["speed"]) < (MOVING if was else STILL)
	return _stopped[peer]


## The role of each chaser straight at them (`near`: [m, unit index], nearest first): one passing them or ahead of them
## goes on (the passer); else the nearest comes up for a PIT, the next passes them, the rest press on behind.
func _roles(near: Array, q: Dictionary) -> Array[int]:
	var passer := -1
	for k in near.size():
		var u: Unit = police.units[near[k][1]]
		var rel: Vector3 = u.car.global_position - q["pos"]
		if how_of(u) in [Driver.PASS, Driver.CUT] or rel.dot(q["dir"]) > PASS_BACK:
			passer = k
			break
	var pitter := -1
	for k in near.size():
		if k != passer:
			pitter = k
			break
	if passer < 0:
		for k in near.size():
			if k != pitter:
				passer = k
				break
	var roles: Array[int] = []
	for k in near.size():
		roles.append(PITTER if k == pitter else (PASSER if k == passer else PRESSER))
	return roles


## Which side of them chaser `u` is on (1 their left, -1 their right).
static func _side_of(u: Unit, q: Dictionary) -> float:
	var rel: Vector3 = u.car.global_position - q["pos"]
	var x := rel.dot(Vector3.UP.cross(q["dir"]))
	return signf(x) if x != 0.0 else 1.0


## How chaser `u` in role `role` (at `rel` from them) closes in on them now; `stopped`: their vehicle is.
func _how(u: Unit, role: int, rel: Vector3, q: Dictionary, stopped: bool) -> int:
	if q["car"] == null or stopped:
		return Driver.STOP
	var st := _state(u)
	var speed: float = q["speed"]
	var along := rel.dot(q["dir"])
	if role == PASSER:
		if along > PASS_DONE or (int(st["how"]) == Driver.CUT and along > PASS_BACK):
			return Driver.CUT
		return Driver.PASS
	var facing: Vector3 = u.car.global_basis.z
	if speed < RAM_SPEED and rel.length() < RAM_REACH and facing.dot(-rel.normalized()) > RAM_FACING:
		return Driver.RAM                   # (only straight ahead of it: no turning round on the spot to hit them)
	if role != PITTER:
		return Driver.FOLLOW
	st["rest_t"] = float(st["rest_t"]) - police.LOOK_EVERY
	if int(st["how"]) == Driver.PIT:
		st["pit_t"] = float(st["pit_t"]) + police.LOOK_EVERY
		if float(st["pit_t"]) < PIT_HOLD:
			return Driver.PIT
		st["rest_t"] = PIT_REST
	var side := absf(rel.dot((q["dir"] as Vector3).cross(Vector3.UP)))
	if float(st["rest_t"]) <= 0.0 and speed > PIT_SPEED.x and speed < PIT_SPEED.y and along < -PIT_ALONG.x \
			and along > -PIT_ALONG.y and side > PIT_SIDE.x and side < PIT_SIDE.y:
		st["pit_t"] = 0.0
		return Driver.PIT
	return Driver.FOLLOW


## What it keeps of chaser `u` (made the first time).
func _state(u: Unit) -> Dictionary:
	if not _cars.has(u.index):
		_cars[u.index] = {"how": -1, "pit_t": 0.0, "rest_t": 0.0, "asked_at": -INF}
	return _cars[u.index]


## What it kept of the cars no longer chasing dropped.
func _tidy() -> void:
	for i: int in _cars.keys():
		if police.units[i].job != Unit.CHASE:
			_cars.erase(i)
