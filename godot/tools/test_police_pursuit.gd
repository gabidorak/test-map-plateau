extends "res://tools/test_base.gd"
## The police cars' driving on a call (scripts/police/driving/), in the PTA Online test (solo, offline):
## - on a call near the player (the physics), pursuit_pilot.gd drives: fast (over FAST m/s on the way), and it gets there;
## - a car parked in its lane ahead: it goes round it, without waiting;
## - its nose against a wall, sent behind it: it backs out and goes;
## - a chase (tactics/pursuit.gd): the player at the wheel of a car they stole (driven here by the keys' actions along a long
##   way), two stars, a police car starting behind them, the others put out of the pool by the police (as in the game):
##   it drives straight at them, comes into contact (a PIT, a push), a roadblock set further on; the physics' cost
##   meanwhile, the pilots' worst tick (their looks spread over the ticks);
## The other scenarios put out the cars they want (police.gd deploy) with the police's own putting out off (spawning).
## - stopped in the car they stole: a chaser stops by them without a touch, its officer gets out; off again: back in,
##   after them (_stopped);
## - lost (their stars blinking): the search, block by block (_lost);
## - on a car park off the lanes (CAR_PARK, Thomas's), the helicopter above them: cars come after them (guided by it,
##   or seeing them first: their cones reach 300 m), off the lanes up to them or stopped by them (_guided).
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_police_pursuit.gd -- --online-test

const FAST := 22.0                          # m/s (80 km/h)
const HIDE := 700.0                         # m off the way they went a player lost hides (lost)
const CAR_PARK := Vector2(1048.0, 21.0)     # map xy: a car park 73 m from the police's lanes (guided)

var _main: Node
var _police: Node
var _failures: PackedStringArray = []
var _rng := RandomNumberGenerator.new()
var _touching := {}                         # police car -> {obstacle body: when it last touched it (ms)}
var _hits: Array = []                       # [what, km/h] each time a police car hit an obstacle
var _driven := 0.0                          # m the police cars drove off the lanes (pursuit_pilot.gd)
var _scene := ""                            # the scenario under way


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "0")
	OS.set_environment("PLATEAU_CARS", "0")
	_rng.seed = 21
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started and _main.mode_id == "online", "the PTA Online test started")
	if not started:
		return _finish()
	_police = _main.game_mode.police
	if not await _until(func() -> bool: return _police.units.size() == _police.UNITS, 90.0):
		_check(false, "the fleet is out")
		return _finish()
	for u: RefCounted in _police.units:
		u.driver.car.contact_monitor = true
		u.driver.car.max_contacts_reported = 6
	_police.spawning = false                # (the scenarios put out the cars they want; chase, lost, guide: the police do)
	var only := OS.get_environment("POLICE_TEST_ONLY").split(",", false)     # (some scenarios alone: call,overtake...)
	if only.is_empty() or "call" in only:
		await _fast_call()
	if only.is_empty() or "overtake" in only:
		await _overtake()
	if only.is_empty() or "wall" in only:
		await _back_out()
	if only.is_empty() or "chase" in only:
		await _chase()
	if only.is_empty() or "pit" in only:
		await _pit()
	if only.is_empty() or "catch" in only:
		await _catch_up()
	if only.is_empty() or "box" in only:
		await _box_in()
	if only.is_empty() or "stop" in only:
		await _stopped()
	if only.is_empty() or "lost" in only:
		await _lost()
	if only.is_empty() or "guide" in only:
		await _guided()
	var km := maxf(_driven / 1000.0, 0.001)
	var fast := _hits.filter(func(h: Array) -> bool: return int(h[1]) > 30)
	print("     obstacles hit: %s" % str(_hits))
	_check(_hits.size() / km < 1.5, "the police cars hit few obstacles: %d in %.1f km (%.1f a km)" % [_hits.size(), km,
			_hits.size() / km])
	_check(fast.size() / km < 0.4, "...hardly any crash (over 30 km/h): %d" % fast.size())
	_finish()


## Every frame of the drives: the police cars driving off the lanes, what they hit (buildings, walls, props, trees,
## hedges, the map's edge: not the ground, nor a vehicle), how far they drove.
func _watch_hits() -> void:
	for u: RefCounted in _police.units:
		var bot: Object = u.driver
		if not bot.pursuing():
			continue
		var car: RigidBody3D = bot.car
		_driven += absf(car.speed()) / 60.0
		var seen: Dictionary = _touching.get(car, {})
		var ms := Time.get_ticks_msec()
		for b: Node in car.get_colliding_bodies():
			if b is CollisionObject3D and (b as CollisionObject3D).collision_layer & (2 | 4 | 16 | 32) != 0:
				var fresh: bool = ms - int(seen.get(b, -100000)) > 3000     # (one hit for a while of touching)
				seen[b] = ms
				if fresh:
					var meta: Dictionary = b.get_meta("plateau", {}) if b.has_meta("plateau") else {}
					var pl: RefCounted = bot.pursuit
					_hits.append([str(meta.get("id", b.name)).left(24), roundi(absf(car.speed()) * 3.6)])
					print("     HIT %s: %s unit %d job %d how %d, %.1f m/s (wanted %.1f), room %s on %s, turn %.2f, rev %s, aim %.0f m" % [
							_scene, str(meta.get("id", b.name)).left(24), u.index, u.job, _police.pursuit.how_of(u), car.speed(),
							pl.target_speed, str(roundi(pl.room)) if pl.room < INF else "-",
							str(roundi(pl.room_on)) if pl.room_on < INF else "-", pl._heading().angle_to(pl.way), pl.reversing,
							pl.aim.distance_to(car.global_position)])
					var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
					var where := PackedStringArray()
					for c in st.get_contact_count():
						if st.get_contact_collider_id(c) == b.get_instance_id():
							var l: Vector3 = car.to_local(st.get_contact_collider_position(c))
							where.append("(x %.1f y %.1f z %.1f)" % [l.x, l.y, l.z])
					print("         touching at %s (half size %s)" % [", ".join(where), str(car.half_extents)])
		_touching[car] = seen


## The player on foot `side` m beside the road where car `i` is (it then drives with the physics); out of the pool
## first if it is in it.
func _beside(i: int, side := 25.0) -> void:
	var bot: Object = _police.units[i].driver
	bot.may_glide = false
	if not _police.units[i].on_map():
		_put_out(_police.units[i])
	var f: Vector3 = bot.car.global_basis.z
	var p: Vector3 = bot.car.global_position + Vector3(f.z, 0.0, -f.x).normalized() * side
	_main.player.teleport(_ground(Vector2(p.x, -p.z)) + Vector3.UP * 0.5)
	await _frames(30)


func _fast_call() -> void:
	_scene = "call"
	var i := 0
	var bot: Object = _police.units[i].driver
	await _beside(i)
	var target := Vector2.ZERO
	var from: Vector2i = _police.graph.nearest(bot.where(), bot.facing(), 30.0)
	for k in 400:                           # (a place 500 to 900 m away the lanes lead to)
		var to: Vector2i = _police.graph.random_point(_rng)
		var p: Vector2 = _police.graph.point(to)
		var d: float = p.distance_to(bot.where())
		if d > 500.0 and d < 900.0 and not _police.graph.path(from, to).is_empty():
			target = p
			break
	_police.units[i].set_job(_police.Unit.CALL)
	_police.units[i].go(target, true, target)
	var top := [0.0, false]
	var t0 := Time.get_ticks_msec()
	var there := await _until(func() -> bool:
		_watch_hits()
		_trace_pilot(bot)
		top[0] = maxf(top[0], absf(bot.car.speed()))
		top[1] = top[1] or bot.pursuing()
		return _police.units[i].job == _police.Unit.PATROL, 150.0)     # (there, no case: on patrol again)
	_check(top[1], "on a call, with the physics: the pursuit pilot drives")
	_check(top[0] > FAST, "fast: %d km/h at the most" % roundi(top[0] * 3.6))
	_check(there and bot.where().distance_to(target) < 40.0, "it gets there: %d m off (%.0f s)" % [
			bot.where().distance_to(target), (Time.get_ticks_msec() - t0) / 1000.0])
	# what a look at the way costs (pursuit_pilot.gd _feel: its sweeps), at speed
	var pilot: RefCounted = bot.pursuit
	var front: Vector3 = pilot._front()
	var dir: Vector3 = bot.car.global_basis.z
	var t1 := Time.get_ticks_usec()
	for k in 200:
		pilot._feel(front, dir, 30.0)
	var us := (Time.get_ticks_usec() - t1) / 200.0
	print("     a look at the way: %.0f us (%d sweeps), %.2f ms a second a car" % [us, pilot.ANGLES.size() + 1,
			us * 10.0 / 1000.0])
	_check(us < 600.0, "a look at the way is cheap: %.0f us" % us)
	_police.patrol(_police.units[i])


## A sedan parked in the lane ahead of car `i`'s way on a call: it goes round, never waiting long.
func _overtake() -> void:
	_scene = "overtake"
	var i := 1
	var bot: Object = _police.units[i].driver
	await _beside(i)
	var at: Vector2i = _police.graph.nearest(bot.where(), bot.facing(), 30.0)
	var far: Vector2i = _police.graph.ahead(at, 300.0)
	_police.units[i].set_job(_police.Unit.CALL)
	_police.units[i].go(_police.graph.point(far), true)
	await _until(func() -> bool: return not _police.units[i].plotting(), 10.0)
	var bp: Vector2 = bot.at(bot.s + 70.0)          # (on the way plotted, 70 m on)
	var bh: Vector2 = (bot.at(bot.s + 72.0) - bp).normalized()
	var parked: Node = _main.park_vehicle("sedan", Transform3D(Basis(Vector3.UP, atan2(bh.x, -bh.y)),
			_ground(bp) + Vector3.UP * 0.3), true)
	var waited := [0.0]
	var passed := await _until(func() -> bool:
		_watch_hits()
		if absf(bot.car.speed()) < 1.0 and bot.pursuing():
			waited[0] += 1.0 / 60.0         # (--fixed-fps 60: a frame is 1/60 s of the game)
		var rel: Vector3 = bot.car.global_position - parked.global_position
		_trace_pilot(bot)
		return rel.dot(Vector3(bh.x, 0.0, -bh.y)) > 15.0, 60.0)
	_check(passed, "a car parked in its lane: it goes round it (%.1f s at a standstill)" % waited[0])
	_check(passed and waited[0] < 3.0, "...without waiting behind it")
	_main.remove_vehicles([parked])
	_police.patrol(_police.units[i])


## Car `i` with its nose against a building's wall, sent to a place behind it: it backs out and goes.
func _back_out() -> void:
	_scene = "wall"
	var i := 2
	var bot: Object = _police.units[i].driver
	var wall := _wall_spot()
	_check(wall.size() == 2, "a wall to drive at")
	if wall.size() != 2:
		return
	var at: Vector3 = wall[0]
	var into: Vector3 = wall[1]
	bot.may_glide = false
	await _frames(2)
	_police.deploy(_police.units[i], Transform3D(Basis(Vector3.UP, atan2(into.x, into.z)),
			at - into * (bot.car.half_extents.z + 0.3) + Vector3.UP * 0.4))
	_main.player.teleport(at - into * 25.0 + into.cross(Vector3.UP) * 10.0 + Vector3.UP * 0.5)
	await _frames(30)
	var behind: Vector3 = at - into * 60.0
	var dest := Vector2(behind.x, -behind.z)
	_police.units[i].set_job(_police.Unit.CALL)
	_police.units[i].go(dest, true, dest)
	var start: Vector3 = bot.car.global_position
	var reversed := [false]
	var away := await _until(func() -> bool:
		_trace_pilot(bot)
		reversed[0] = reversed[0] or bot.pursuit.reversing
		return bot.car.global_position.distance_to(start) > 15.0, 40.0)
	_check(reversed[0], "against the wall: it backs out")
	_check(away, "...and goes (%.0f m away)" % bot.car.global_position.distance_to(start))
	_police.patrol(_police.units[i])


## The player drives a car they stole along a long way, two stars on them, police car `i` starting behind them.
func _chase() -> void:
	_scene = "chase"
	await _reset_police()
	var i := 3
	var bot: Object = _police.units[i].driver
	bot.may_glide = false
	var at: Vector2i = _police.graph.random_point(_rng, 200.0)     # (it is in the pool: from a lane somewhere)
	var a: Vector2i = _police.graph.ahead(at, 70.0)
	var way: PackedVector2Array = PackedVector2Array()
	for k in 400:
		var b: Vector2i = _police.graph.random_point(_rng)
		if _police.graph.point(b).distance_to(_police.graph.point(a)) < 1500.0:
			continue
		var r: Dictionary = _police.graph.make_route(_police.graph.path(a, b))
		if float(r.get("length", 0.0)) > 1500.0:
			for q: Array in r["pts"]:
				way.append(Vector2(q[0], q[1]))
			break
	_check(way.size() > 100, "a long way to drive (%d m)" % (way.size() * 2))
	if way.size() < 100:
		return
	var h: Vector2 = (way[3] - way[0]).normalized()
	var car: Node = _main.park_vehicle("sedan", Transform3D(Basis(Vector3.UP, atan2(h.x, -h.y)),
			_ground(way[0]) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	car.contact_monitor = true
	car.max_contacts_reported = 8
	var behind: Vector2 = way[0] - h * 25.0  # (the police car 25 m behind them, in sight)
	_police.deploy(_police.units[i], Transform3D(Basis(Vector3.UP, atan2(h.x, -h.y)), _ground(behind) + Vector3.UP * 0.4))
	_police.spawning = true                 # (the police put out the others: the pursuit as it goes in the game)
	await _frames(10)
	var key: String = _main.carjack.key_of(car)
	var base := [0.0, 0]                    # (the physics' cost before the chase)
	var k := [0]
	await _until(func() -> bool:
		base[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		base[1] += 1
		return base[1] > 120, 10.0)
	_police.arrest.set_physics_process(false)  # (nobody gets out: the driving alone here; the arrests are tested apart)
	_police.report(1, Vector2(car.global_position.x, -car.global_position.z), key)     # (the police car right behind)
	_police.set_level(1, 2)
	var police_bodies := {}
	for u: RefCounted in _police.units:
		police_bodies[u.driver.car] = true
	var seen := {"direct": false, "pit": false, "contact": 0, "cut": false, "roadblock": false, "phys": 0.0, "n": 0,
			"police_us": 0, "pilots_us": 0, "pursuing": 0}
	_pilot_script().spent_us = 0
	_pilot_script().worst_us = 0
	var police_worst := [0]
	var drove := await _until(func() -> bool:
		police_worst[0] = maxi(police_worst[0], _police.tick_us)
		k[0] = _steer_along(car, way, k[0])
		for u: RefCounted in _police.units:
			seen["direct"] = seen["direct"] or (u.case == 1 and (_police.pursuit.how_of(u) >= 0))
			seen["pit"] = seen["pit"] or _police.pursuit.how_of(u) == bot.PIT
		for u: RefCounted in _police.units:
			seen["cut"] = seen["cut"] or _police.pursuit.how_of(u) == bot.CUT
		seen["roadblock"] = seen["roadblock"] or _police.roadblock.active.has(1)
		for b: Node in car.get_colliding_bodies():
			if police_bodies.has(b):
				seen["contact"] += 1
		seen["phys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		seen["n"] += 1
		seen["police_us"] += _police.tick_us
		for u: RefCounted in _police.units:
			seen["pursuing"] += 1 if u.driver.pursuing() else 0
		_watch_hits()
		if seen["n"] % 120 == 0:
			_trace(car)
		return k[0] >= way.size() - 10 or seen["n"] > 60 * 60, 120.0)
	_release_keys()
	var n: int = maxi(seen["n"], 1)
	print("     chase: %s, physics %.2f ms a frame (%.2f before); police %.3f ms (worst %.2f), pilots %.3f ms a frame (worst %.2f), %.1f cars off the lanes" % [
			seen, seen["phys"] * 1000.0 / n, base[0] * 1000.0 / maxi(base[1], 1), seen["police_us"] / 1000.0 / n,
			police_worst[0] / 1000.0, _pilot_script().spent_us / 1000.0 / n, _pilot_script().worst_us / 1000.0,
			float(seen["pursuing"]) / n])
	_check(_pilot_script().worst_us < 6000, "the pilots' looks spread over the ticks: %.2f ms at worst on one" % (
			_pilot_script().worst_us / 1000.0))
	_check(seen["direct"], "a police car near them drives straight at them")
	print("     (in contact %d ticks in this chase; the contact has its own scenarios: pit, box)" % seen["contact"])
	print("     (a PIT tried in this chase: %s; the PIT has its own scenario)" % seen["pit"])
	print("     (a car passed them and cut in: %s; boxing in has its own scenario)" % seen["cut"])
	_check(seen["roadblock"], "a roadblock set further on")
	_check(drove, "(the drive went on)")
	# the roadblock: its cars get there and stop across the road (the others held meanwhile: no arrest)
	# (the one of the chase may stand where they drove, knocked aside: a fresh one, as if they were back at the start of
	# their way, far from where they stand: 400 m on from where they stand may be in their sight, a winding road, the
	# map's edge, where none is set; no room, no car at a try: tried again, as the police do RETRY s later)
	_police.roadblock.lift(1)
	var rb: Dictionary = {}
	for attempt in 8:
		if not _police.cases.has(1):
			break
		var w := mini(attempt * 20, way.size() / 3)    # (from a little further on at each try: another place)
		var hw: Vector2 = (way[w + 3] - way[w]).normalized()
		var f := Vector3(hw.x, 0.0, -hw.y)
		var p: Vector3 = _ground(way[w])
		_police.roadblock._rest.erase(1)
		_police.roadblock.set_up(_police.cases[1], {"pos": p, "car": car, "vel": f * 15.0, "dir": f, "speed": 15.0,
				"xy": Vector2(p.x, -p.z), "dir_xy": Vector2(f.x, -f.z)})
		rb = _police.roadblock.active.get(1, {})
		if not rb.is_empty():
			break
		await _frames(30)
	_check(not rb.is_empty(), "a roadblock ahead of them%s" % (" (" + _police.roadblock.refused + ")"
			if rb.is_empty() else ""))
	if rb.is_empty():
		return
	_police.spawning = false
	_hold_all_but(rb["units"])
	var units: Array = rb["units"]
	var set := await _until(func() -> bool:
		return units.all(func(n: int) -> bool:
			var u: RefCounted = _police.units[n]
			return u.driver.braked and u.where().distance_to(u.dest) < 30.0), 150.0)
	_check(set, "the roadblock's %d cars there, stopped across the road" % units.size())
	var placed: Array = units.filter(func(n: int) -> bool:   # (where it was put: its lane's spot, not moved off it)
		var it: Node3D = _police.units[n].driver.car
		return Vector2(it.global_position.x, -it.global_position.z).distance_to(_police.units[n].dest) < 2.0)
	var apart: float = (_police.units[units[0]].driver.where() as Vector2).distance_to(
			_police.units[units[-1]].driver.where())
	var first_on_lane: bool = _police.graph.nearest(_police.units[units[0]].dest, Vector2.ZERO, 2.0).x >= 0
	_check(units.size() == 2 and placed.size() == 2 and first_on_lane and apart > 2.5 and apart < 6.0,
			"...one on each lane, side by side (%d of %d in place, the first on its lane %s, %.1f m apart)" % [
			placed.size(), units.size(), first_on_lane, apart])
	var frozen: Array = units.filter(func(n: int) -> bool: return _police.units[n].driver.car.freeze)
	_check(frozen.is_empty(), "...cars like any other (none frozen)")
	_police.arrest.set_physics_process(true)


var _pilot_t := 0


## Every 2 s: police car `bot`'s driving (pursuit_pilot.gd).
func _trace_pilot(bot: Object) -> void:
	if Time.get_ticks_msec() - _pilot_t < 2000:
		return
	_pilot_t = Time.get_ticks_msec()
	var p: RefCounted = bot.pursuit
	print("     pilot %s: %s v %.1f ts %.1f free %s on %s rev %s stuck %.1f aim %.0f m (speed %s) s %.0f/%.0f arrived %s" % [
			bot.route_key, "P" if bot.pursuing() else ("G" if bot.gliding else "L"), bot.car.speed(), p.target_speed,
			str(roundi(p.room)) if p.room < INF else "-", str(roundi(p.room_on)) if p.room_on < INF else "-", p.reversing,
			p._stuck_t, p.aim.distance_to(bot.car.global_position), str(p.aim_speed), bot.s, bot._length, bot.arrived])


## Every 2 s of the chase: the case, and each car on it.
func _trace(car: Node) -> void:
	var c: RefCounted = _police.cases.get(1)
	var line := "     t %3d: suspect %3d km/h, seen %s since %.1f |" % [Time.get_ticks_msec() / 1000, roundi(car.speed() * 3.6),
			c.seen if c else "-", c.since if c else -1.0]
	for u: RefCounted in _police.units:
		if u.case != 1:
			continue
		var b: Object = u.driver
		line += " [%d j%d h%d %s%s d%d v%d ts%d f%s]" % [u.index, u.job, _police.pursuit.how_of(u), "P" if b.pursuing() else ("G" if b.gliding else "L"),
				"D" if (_police.pursuit.how_of(u) >= 0) else "", b.car.global_position.distance_to(car.global_position), roundi(b.car.speed()),
				roundi(b.pursuit.target_speed), str(roundi(b.pursuit.room)) if b.pursuit.room < INF else "-"]
	print(line)


## A PIT: the player drives along a long straight (a car with them at 16 m/s), one police car alongside their rear (the others
## held), two stars: it hits their rear corner, they spin.
func _pit() -> void:
	_scene = "pit"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	var way := PackedVector2Array()
	var rng := RandomNumberGenerator.new()  # (the same straight each time)
	rng.seed = 7
	for k in 3000:                          # a straight 300 m
		var at: Vector2i = _police.graph.random_point(rng)
		var r: PackedVector2Array = _police.graph.pts[at.x]
		var d: PackedVector2Array = _police.graph.dirs[at.x]
		if at.y + 150 >= r.size() or d[at.y].dot(d[at.y + 150]) < 0.995 or d[at.y].dot(d[at.y + 75]) < 0.995:
			continue
		way = r.slice(at.y, at.y + 150)
		break
	_check(way.size() > 100, "a straight 300 m")
	if way.size() < 100:
		return
	var i := 4
	_hold_all_but([i])
	_clear_way(way, [i])
	var h: Vector2 = (way[5] - way[0]).normalized()
	var f := Vector3(h.x, 0.0, -h.y)
	var basis := Basis(Vector3.UP, atan2(h.x, -h.y))
	var car: Node = _main.park_vehicle("sedan", Transform3D(basis, _ground(way[10]) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	var bot: Object = _police.units[i].driver
	bot.may_glide = false
	await _frames(5)
	var left := f.cross(Vector3.DOWN)       # (+X, the car's left)
	var start: Vector3 = car.global_position - f * 8.0 + left * 2.8
	_police.deploy(_police.units[i], Transform3D(basis, Vector3(start.x, _ground(Vector2(start.x, -start.z)).y + 0.4,
			start.z)))
	bot._held = false
	bot._freeze(false, 16.0)                # (not held still any more: under way with them)
	car.linear_velocity = f * 16.0
	_police.arrest.set_physics_process(false)
	_police.report(1, Vector2(car.global_position.x, -car.global_position.z), _main.carjack.key_of(car))
	_police.set_level(1, 2)
	_police.units[i].set_job(_police.Unit.CHASE, 1)
	_police.units[i].go(Vector2(car.global_position.x, -car.global_position.z), true)
	var seen := {"pit": false, "spin": 0.0, "contact": false, "slowest": INF}
	var k := [0]
	await _until(func() -> bool:
		k[0] = _steer_along(car, way, k[0])
		_watch_hits()
		seen["pit"] = seen["pit"] or _police.pursuit.how_of(_police.units[i]) == bot.PIT
		if Engine.get_physics_frames() % 60 == 0:
			var rel: Vector3 = bot.car.global_position - car.global_position
			print("     pit t: k %d, suspect %.1f m/s, police %.1f m/s job %d how %d %s braked %s direct %s, along %.1f side %.1f, aim %s, ts %.1f" % [
					k[0], car.speed(), bot.car.speed(), _police.units[i].job, _police.pursuit.how_of(_police.units[i]),
					"P" if bot.pursuing() else ("G" if bot.gliding else "L"), bot.braked, (_police.pursuit.how_of(_police.units[i]) >= 0),
					rel.dot(f), rel.dot(left), str(bot.pursuit.aim - car.global_position), bot.pursuit.target_speed])
		seen["spin"] = maxf(seen["spin"], absf(car.angular_velocity.y))
		if seen["contact"]:
			seen["slowest"] = minf(seen["slowest"], car.speed())
		for b: Node in bot.car.get_colliding_bodies():
			seen["contact"] = seen["contact"] or b == car
		return k[0] >= way.size() - 10 or seen["spin"] > 1.5, 25.0)
	_release_keys()
	print("     pit: %s" % seen)
	_check(seen["pit"], "alongside their rear at speed: a PIT")
	_check(seen["contact"] and (seen["spin"] > 0.7 or seen["slowest"] < 8.0),
			"...it hits them: they spin (%.1f rad/s), slowed down to %.0f km/h" % [seen["spin"], seen["slowest"] * 3.6])
	_police.arrest.set_physics_process(true)


## Catching up: the player flat out along a long straight in a bot car (a sedan), a police car 50 m behind: it closes
## in (the gap halved, at least) within the straight.
func _catch_up() -> void:
	_scene = "catch"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	var way := _straight(500.0)
	_check(way.size() > 200, "a straight %d m" % (way.size() * 2))
	if way.size() < 200:
		return
	var i := 5
	_hold_all_but([i])
	_clear_way(way, [i])
	var h: Vector2 = (way[5] - way[0]).normalized()
	var f := Vector3(h.x, 0.0, -h.y)
	var basis := Basis(Vector3.UP, atan2(h.x, -h.y))
	var car: Node = _main.park_vehicle("sedan", Transform3D(basis, _ground(way[30]) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	var bot: Object = _police.units[i].driver
	bot.may_glide = false
	await _frames(5)
	_police.deploy(_police.units[i], Transform3D(basis, _ground(way[5]) + Vector3.UP * 0.4))
	bot._held = false
	bot._freeze(false, 25.0)
	car.linear_velocity = f * 25.0
	_police.arrest.set_physics_process(false)
	_police.report(1, Vector2(car.global_position.x, -car.global_position.z), _main.carjack.key_of(car))
	_police.set_level(1, 2)
	_police.units[i].set_job(_police.Unit.CHASE, 1)
	var gap0: float = bot.car.global_position.distance_to(car.global_position)
	var k := [30]
	var best := [gap0, 0.0, {}]             # (the smallest gap, the police car's top speed, what held it back)
	await _until(func() -> bool:
		k[0] = _flat_out(car, way, k[0])
		var gap: float = bot.car.global_position.distance_to(car.global_position)
		best[0] = minf(best[0], gap)
		best[1] = maxf(best[1], bot.car.speed())
		var why: String = bot.pursuit.held_by
		best[2][why] = int(best[2].get(why, 0)) + 1
		if Engine.get_physics_frames() % 60 == 0:
			print("     catch: suspect %.1f m/s, police %.1f m/s (wants %.1f, held by %s), gap %.0f m, how %d" % [
					car.speed(), bot.car.speed(), bot.pursuit.target_speed, why, gap, _police.pursuit.how_of(_police.units[i])])
		return k[0] >= way.size() - 20 or gap < 6.0, 60.0)
	_release_keys()
	print("     catch: %s" % str(best))
	_check(best[0] < gap0 * 0.5, "flat out in a sedan, a police car 50 m behind closes in: %.0f m -> %.0f m (%d km/h at most)" % [
			gap0, best[0], best[1] * 3.6])
	_police.arrest.set_physics_process(true)


## Boxing in: the player along a straight in a sedan at 20 m/s, two police cars behind them (the others held): one
## comes up for a PIT, the other passes them and cuts in front of them, braking (or, they stopped meanwhile, stops ahead
## of them: boxed in): they are slowed down.
func _box_in() -> void:
	_scene = "box"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	var way := _straight(500.0)
	if way.size() < 200:
		_check(false, "a straight 500 m")
		return
	var ours: Array[int] = [4, 6]
	_hold_all_but(ours)
	_clear_way(way, ours)
	var h: Vector2 = (way[5] - way[0]).normalized()
	var f := Vector3(h.x, 0.0, -h.y)
	var basis := Basis(Vector3.UP, atan2(h.x, -h.y))
	var car: Node = _main.park_vehicle("sedan", Transform3D(basis, _ground(way[20]) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	await _frames(5)
	var left := f.cross(Vector3.DOWN)
	for k in ours.size():                   # (one 14 m behind them, the other already up by their rear, other side)
		var bot: Object = _police.units[ours[k]].driver
		bot.may_glide = false
		var at: Vector3 = car.global_position - f * (14.0 if k == 0 else 6.0) + left * (2.6 if k == 0 else -2.6)
		_police.deploy(_police.units[ours[k]], Transform3D(basis, Vector3(at.x, _ground(Vector2(at.x, -at.z)).y + 0.4,
				at.z)))
		bot._held = false
		bot._freeze(false, 18.0)
	car.linear_velocity = f * 18.0
	_police.arrest.set_physics_process(false)
	_police.report(1, Vector2(car.global_position.x, -car.global_position.z), _main.carjack.key_of(car))
	_police.set_level(1, 2)
	for i: int in ours:
		_police.units[i].set_job(_police.Unit.CHASE, 1)
	var seen := {"pass": false, "cut": false, "ahead": false, "slowest": INF}
	var k := [20]
	await _until(func() -> bool:
		k[0] = _steer_along(car, way, k[0])
		_watch_hits()
		for i: int in ours:
			var u: RefCounted = _police.units[i]
			var bot: Object = u.driver
			seen["pass"] = seen["pass"] or _police.pursuit.how_of(u) == bot.PASS
			var how: int = _police.pursuit.how_of(u)
			if how == bot.CUT or (how == bot.STOP and seen["pass"]):    # (in front of them; stopped: boxed in)
				seen["cut"] = true
				seen["ahead"] = seen["ahead"] or (bot.car.global_position - car.global_position).dot(f) > 3.0
		if seen["cut"]:
			seen["slowest"] = minf(seen["slowest"], car.speed())
		if Engine.get_physics_frames() % 60 == 0:
			var line := "     box t: suspect %.1f m/s |" % car.speed()
			for i: int in ours:
				var u: RefCounted = _police.units[i]
				var b: Object = u.driver
				var rel: Vector3 = b.car.global_position - car.global_position
				line += " [%d how %d along %.1f side %.1f v %.1f ts %.1f %s]" % [i, _police.pursuit.how_of(u), rel.dot(f), rel.dot(left),
						b.car.speed(), b.pursuit.target_speed, b.pursuit.held_by]
			print(line)
		return k[0] >= way.size() - 10, 30.0)
	_release_keys()
	print("     box: %s" % seen)
	_check(seen["pass"] and seen["cut"] and seen["ahead"], "one car passes them and cuts in front of them")
	_check(seen["slowest"] < 12.0, "...braking them: down to %.0f km/h" % (seen["slowest"] * 3.6))
	_police.arrest.set_physics_process(true)


## Stopped: the player at the wheel of a car they stole, standing on a straight, two stars, a police car chasing them
## from 40 m behind: it comes up and stops by them without touching them nor backing out, and its officer gets out;
## they drive off: the officer back in, the car after them again, straight at them.
func _stopped() -> void:
	_scene = "stop"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	var way := _straight(300.0)
	if way.size() < 100:
		_check(false, "a straight 300 m")
		return
	var i := 4
	_hold_all_but([i])
	_clear_way(way, [i])
	var h: Vector2 = (way[5] - way[0]).normalized()
	var basis := Basis(Vector3.UP, atan2(h.x, -h.y))
	var car: Node = _main.park_vehicle("sedan", Transform3D(basis, _ground(way[40]) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	var u: RefCounted = _police.units[i]
	var bot: Object = u.driver
	bot.may_glide = false
	await _frames(5)
	_police.deploy(u, Transform3D(basis, _ground(way[20]) + Vector3.UP * 0.4))
	bot._held = false
	bot._freeze(false, 0.0)
	_police.report(1, Vector2(car.global_position.x, -car.global_position.z), _main.carjack.key_of(car))
	_police.set_level(1, 2)
	u.set_job(_police.Unit.CHASE, 1)
	var reversed := false
	var touched := false
	var out_at := -1.0
	for f in 60 * 30:                       # (game time; they stand still)
		await physics_frame
		reversed = reversed or bot.pursuit.reversing
		touched = touched or bot.car.get_colliding_bodies().has(car)
		if not _police.arrest.officers.is_empty():
			out_at = f / 60.0
			break
	var gap: float = bot.car.global_position.distance_to(car.global_position)
	print("     stop: officer out at %.1f s, %.1f m from them, backed out %s, touched %s" % [out_at, gap, reversed, touched])
	_check(out_at >= 0.0 and gap < 15.0, "they stop: a chaser stops by them, its officer gets out (%.0f s, %.0f m)" % [
			out_at, gap])
	_check(not reversed and not touched, "...without backing out nor touching them")
	if out_at < 0.0:
		return
	var k := [40]
	var back := -1.0
	var after := -1.0
	for f in 60 * 20:                       # (they drive off along the straight)
		await physics_frame
		k[0] = _flat_out(car, way, k[0])
		if back < 0.0 and _police.arrest.officers.is_empty():
			back = f / 60.0
		if back >= 0.0 and u.job == _police.Unit.CHASE and _police.pursuit.how_of(u) >= 0:
			after = f / 60.0
			break
		if k[0] >= way.size() - 10:
			break
	var top := 0.0                          # (not only its orders: it drives, its engine pulling, after them)
	for f in 60 * 4:
		await physics_frame
		k[0] = _flat_out(car, way, k[0])
		top = maxf(top, absf(bot.car.speed()))
		if k[0] >= way.size() - 10:
			break
	_release_keys()
	print("     stop: off again, the officer back in at %.1f s, the car straight at them at %.1f s, %.0f km/h at most" % [
			back, after, top * 3.6])
	_check(back >= 0.0, "they drive off: the officer gets back in (%.0f s)" % back)
	_check(after >= 0.0, "...and the car is after them again (%.0f s)" % after)
	_check(top > 8.0, "...driving off after them (%.0f km/h at most)" % (top * 3.6))


## Lost: a case not seen (last seen going one way at 20 m/s), the player hidden HIDE m off to the side of that way, by
## a lane: the searchers comb the blocks round the zone's middle, each its own; the middle drifts toward the player and
## the blocks the searchers are sent to with it (the cars themselves follow as the ways there allow); the helicopter
## goes from block to block; the police's ticks stay cheap meanwhile (no main-thread spikes); nearest() is quick.
func _lost() -> void:
	_scene = "lost"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	_police.spawning = true                 # (the searchers put out by the police, as in the game)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var last := Vector2.ZERO
	var heading := Vector2.ZERO
	var hide := Vector2.ZERO
	for k in 200:                           # (where they hide by a lane: somewhere the cars may get to)
		var at: Vector2i = _police.graph.random_point(rng, 400.0)
		last = _police.graph.point(at)
		heading = _police.graph.heading(at)
		var hide_at: Vector2i = _police.graph.nearest(last + heading.orthogonal() * HIDE, Vector2.ZERO, 40.0)
		if hide_at.x >= 0:
			hide = _police.graph.point(hide_at)
			break
	_main.player.teleport(_ground(hide) + Vector3.UP * 0.5)
	var pad := last - heading.orthogonal() * 150.0     # (the helicopter parked nearby: no flight from its base first)
	_police.heli.place(Transform3D(Basis(), _ground(pad) + Vector3.UP * 0.2))
	var lost: RefCounted = _police.Case.new(1, last, "")
	lost.level = 1
	lost.since = 2.0
	lost.vel = heading * 20.0
	_police.cases[1] = lost
	_police.set_level(1, 2)
	var plans: Dictionary = _police.search.plans
	var ready := await _until(func() -> bool:            # (two searchers' blocks chosen: their ways plotted)
		return plans.has(1) and _sent_from(plans[1], hide) < INF and (plans[1]["claims"] as Dictionary).size() >= 2, 10.0)
	_check(ready, "a search under way")
	if not ready:
		return
	var d0: float = (plans[1]["mid"] as Vector2).distance_to(hide)
	var near0 := _searchers_from(hide)
	var sent0 := _sent_from(plans[1], hide)
	var heli_blocks := {}
	var own := 0                            # looks where every searcher had a block of its own...
	var looks := 0                          # ...of these
	var worst := 0
	var sum := 0
	var n := 0
	var found := false
	for f in 60 * 40:                       # (game time, not the clock's)
		await physics_frame
		worst = maxi(worst, _police.tick_us)
		sum += _police.tick_us
		n += 1
		if _police.cases[1].seen or not plans.has(1):
			found = true
			break
		var plan: Dictionary = plans[1]
		if plan["heli"] != _police.search.NONE:
			heli_blocks[plan["heli"]] = true
		if f % 60 == 59:
			var blocks := {}
			var chosen := 0
			for claim: Array in (plan["claims"] as Dictionary).values():
				if claim[0] != _police.search.NONE:
					blocks[claim[0]] = true
					chosen += 1
			looks += 1
			own += 1 if blocks.size() == chosen else 0
	var t := n / 60.0
	if found:
		print("     lost: found after %.0f s" % t)
		_check(true, "the search found them (after %.0f s)" % t)
	else:
		var plan: Dictionary = plans[1]
		var d1: float = (plan["mid"] as Vector2).distance_to(hide)
		var near1 := _searchers_from(hide)
		var sent1 := _sent_from(plan, hide)
		var radius := minf(_police.search.ZONE + _police.search.ZONE_GROW * float(_police.cases[1].since),
				_police.search.ZONE_MAX)
		var combed := 0
		for b: Vector2i in plan["done"]:
			combed += 1 if _police.graph.block_middle(b).distance_to(plan["mid"]) < radius else 0
		print("     lost (%.0f s): the middle %d -> %d m from them; the blocks the searchers go to %d -> %d m, the searchers %d -> %d m (on average); %d blocks combed in the zone; heli over %d blocks" % [
				t, d0, d1, sent0, sent1, near0, near1, combed, heli_blocks.size()])
		_check(d1 < d0 - 250.0 or d1 < 150.0, "the zone's middle drifts toward them (%d -> %d m)" % [d0, d1])
		_check(sent1 < sent0 * 0.75 or sent1 < 250.0, "...the searchers sent there (their blocks %d -> %d m on average)" % [
				sent0, sent1])
		_check(combed >= 6, "the zone combed block by block (%d blocks)" % combed)
		_check(heli_blocks.size() >= 3, "the helicopter from block to block (%d)" % heli_blocks.size())
	_check(looks == 0 or own * 10 >= looks * 9, "each searcher its own block (%d of %d looks)" % [own, looks])
	print("     lost: police tick worst %.2f ms, mean %.3f ms" % [worst / 1000.0, sum / 1000.0 / maxi(n, 1)])
	_check(worst < 8000, "no spike in the police's ticks while they search (worst %.2f ms)" % (worst / 1000.0))
	_police.close_case(1)
	# nearest(), off the lanes too: quick
	var t0 := Time.get_ticks_usec()
	var slowest := 0
	for k in 200:
		var t1 := Time.get_ticks_usec()
		_police.graph.nearest(Vector2(rng.randf_range(-1500.0, 2500.0), rng.randf_range(-1500.0, 1500.0)),
				Vector2.ZERO, 80.0)
		slowest = maxi(slowest, Time.get_ticks_usec() - t1)
	var mean := (Time.get_ticks_usec() - t0) / 200.0
	print("     nearest (80 m): mean %.3f ms, worst %.3f ms" % [mean / 1000.0, slowest / 1000.0])
	_check(mean < 300.0 and slowest < 4000, "the lane nearest a place found quickly (%.3f ms on average, %.2f at worst)" % [
			mean / 1000.0, slowest / 1000.0])


## Guided: the player at the wheel of a car they stole, standing on a car park off the lanes (CAR_PARK), two stars, the
## helicopter parked 300 m away: once it sees them it guides cars after them (chasing), and one comes off the lanes up
## to them.
func _guided() -> void:
	_scene = "guide"
	if _main.driving:
		_main.exit_car()
	await _reset_police()
	_police.spawning = true                 # (the cars on the case put out by the police, as in the game)
	var car: Node = _main.park_vehicle("sedan", Transform3D(Basis(), _ground(CAR_PARK) + Vector3.UP * 0.4), true)
	_main.enter_car(car)
	_police.heli.place(Transform3D(Basis(), _ground(CAR_PARK + Vector2(300.0, 0.0)) + Vector3.UP * 0.2))
	await _frames(30)
	var guided: RefCounted = _police.Case.new(1, CAR_PARK, _main.carjack.key_of(car))
	guided.level = 1
	_police.cases[1] = guided
	_police.set_level(1, 2)
	var seen_at := -1.0
	var chasing := 0
	var came := -1.0
	for f in 60 * 80:                       # (game time)
		await physics_frame
		_watch_hits()
		var t := f / 60.0
		if not _police.cases.has(1):
			came = t                        # (arrested: they came)
			break
		if seen_at < 0.0 and _police.cases[1].seen and _police.heli_case == 1:
			seen_at = t
		if seen_at >= 0.0 and t < seen_at + 2.0:
			chasing = maxi(chasing, _police.pack(1))
		for u: RefCounted in _police.units:     # (there: up to them, or stopped by them, its officer out)
			if u.case == 1 and came < 0.0 and ((u.driver.where() as Vector2).distance_to(CAR_PARK) < 15.0
					or _police.arrest.out.has(u.index)):
				came = t
		if came >= 0.0:
			break
	print("     guided: seen at %.0f s, %d chasing then, a car there at %.0f s" % [seen_at, chasing, came])
	if came < 0.0:                          # (none came: where each car of the case is, and what it does)
		for u: RefCounted in _police.units:
			if u.case == 1:
				var b: Object = u.driver
				print("     guided: car %d job %d %d m off, %s, %.1f m/s, s %.0f/%.0f, arrived %s, plotting %s, stuck %.1f, rev %s" % [
						u.index, u.job, (b.where() as Vector2).distance_to(CAR_PARK),
						"P" if b.pursuing() else ("G" if b.gliding else "L"), b.car.speed(), b.s, b._length, b.arrived,
						u.plotting(), b.pursuit._stuck_t, b.pursuit.reversing])
	_check(seen_at >= 0.0, "the helicopter sees them on the car park")
	# (a car's vision cone, 300 m, may see them before the helicopter does: one chasing then, guided or not)
	_check(chasing >= 1, "...and cars are after them (%d chasing)" % chasing)
	_check(came >= 0.0 and came - seen_at < 40.0, "a police car comes off the lanes up to them (%.0f s after)" % (
			came - seen_at))
	if _police.cases.has(1):
		_police.close_case(1)
	if _main.driving:
		_main.exit_car()
	_main.remove_vehicles([car])


## The m from `p` to the blocks the searchers of `plan` (search.gd) go to, on average (INF none chosen yet).
func _sent_from(plan: Dictionary, p: Vector2) -> float:
	var sum := 0.0
	var n := 0
	for claim: Array in (plan["claims"] as Dictionary).values():
		if claim[0] != _police.search.NONE:
			sum += _police.graph.block_middle(claim[0]).distance_to(p)
			n += 1
	return sum / n if n > 0 else INF


## The m from `p` to the searchers on the case, on average (INF none).
func _searchers_from(p: Vector2) -> float:
	var sum := 0.0
	var n := 0
	for u: RefCounted in _police.units:
		if u.case == 1 and u.job == _police.Unit.SEARCH:
			sum += (u.driver.where() as Vector2).distance_to(p)
			n += 1
	return sum / n if n > 0 else INF


## A straight lane `length` m long or more (the same each run): its points (map xy, 2 m apart), [] none found.
func _straight(length: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var n := roundi(length / 2.0)
	for k in 6000:
		var at: Vector2i = _police.graph.random_point(rng)
		var r: PackedVector2Array = _police.graph.pts[at.x]
		var d: PackedVector2Array = _police.graph.dirs[at.x]
		if at.y + n >= r.size():
			continue
		var straight := true
		for j in range(at.y, at.y + n, 25):
			straight = straight and d[at.y].dot(d[j]) > 0.995
		if straight:
			return r.slice(at.y, at.y + n)
	return PackedVector2Array()


## The keys' actions driving `car` along `way` flat out (the throttle held): returns the point reached.
func _flat_out(car: Node, way: PackedVector2Array, k: int) -> int:
	k = _steer_along(car, way, k)
	_press("throttle", 1.0)
	_press("brake", 0.0)
	return k


## The keys' actions that drive `car` along `way` (map xy points, 2 m apart) from point `k` on: the wheel towards a
## point 14 m on, the throttle up to SUSPECT_SPEED (less in the bends). Returns the point reached.
func _steer_along(car: Node, way: PackedVector2Array, k: int) -> int:
	var here := Vector2(car.global_position.x, -car.global_position.z)
	while k < way.size() - 1 and way[k + 1].distance_to(here) < way[k].distance_to(here) + 0.5:
		k += 1
	var aim: Vector2 = way[mini(k + 7, way.size() - 1)]
	var local: Vector3 = car.to_local(Vector3(aim.x, car.global_position.y, -aim.y))
	var angle := atan2(local.x, local.z)
	var bend := absf((way[mini(k + 12, way.size() - 1)] - way[mini(k + 6, way.size() - 1)]).angle_to(
			way[mini(k + 6, way.size() - 1)] - way[k]))
	var want := 20.0 if bend < 0.25 else 9.0
	_press("steer_left", clampf(angle * 2.5, 0.0, 1.0))
	_press("steer_right", clampf(-angle * 2.5, 0.0, 1.0))
	_press("throttle", 1.0 if car.speed() < want else 0.0)
	_press("brake", 0.6 if car.speed() > want + 4.0 else 0.0)
	return k


func _press(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_keys() -> void:
	for a: String in ["steer_left", "steer_right", "throttle", "brake"]:
		Input.action_release(a)


## A building's wall by a lane: [a point on the lane 6 m from it, the way into it (flat, unit)], [] none.
func _wall_spot() -> Array:
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for k in 3000:
		var p: Vector2 = _police.graph.point(_police.graph.random_point(_rng))
		var g := _ground(p) + Vector3.UP * 1.0
		for a in 8:
			var d := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 8.0)
			var q := PhysicsRayQueryParameters3D.create(g, g + d * 12.0, 2)     # (the buildings)
			var hit := space.intersect_ray(q)
			if hit and absf((hit["normal"] as Vector3).dot(d)) > 0.9:
				return [hit["position"], d]
	return []


## The police cars but `keep` (their numbers) kept out of the scenario: back in the pool (one whose officer is out:
## braked where it stands, on no case).
func _hold_all_but(keep: Array) -> void:
	for u: RefCounted in _police.units:
		if u.index in keep:
			continue
		if _police.arrest.out.has(u.index):
			u.set_job(_police.Unit.OUT)
		elif u.on_map():
			u.vanish()


## The police cars held (all but `keep`) still on the map within 40 m of `way` (an officer out) put out of it, 600 m
## aside.
func _clear_way(way: PackedVector2Array, keep: Array[int]) -> void:
	var side: Vector2 = (way[5] - way[0]).normalized().orthogonal()
	for i in _police.units.size():
		if i in keep or not _police.units[i].on_map():
			continue
		var bot: Object = _police.units[i].driver
		var at: Vector2 = bot.where()
		for k in range(0, way.size(), 10):
			if way[k].distance_to(at) < 40.0:
				bot.car.place(Transform3D(Basis(), _ground(at + side * 600.0) + Vector3.UP * 0.4))
				break


## The police as after a case: none open (its roadblock lifted), every car back in the pool (but one whose officer is
## out), nothing put out by itself, the arrests on.
func _reset_police() -> void:
	_police.spawning = false
	for peer: int in _police.cases.keys():
		_police.close_case(peer)
	await _frames(2)
	_police.roadblock._rest.clear()
	for u: RefCounted in _police.units:
		u.driver.may_glide = true
		if u.on_map() and not _police.arrest.out.has(u.index):
			u.vanish()
	_police.arrest.set_physics_process(true)
	await _frames(10)


## Unit `u` out of the pool on a lane somewhere (away from the routes' ends), on patrol.
func _put_out(u: RefCounted) -> void:
	var at: Vector2i = _police.graph.random_point(_rng, 200.0)
	var p: Vector2 = _police.graph.point(at)
	var h: Vector2 = _police.graph.heading(at)
	_police.deploy(u, Transform3D(Basis(Vector3.UP, atan2(h.x, -h.y)), _ground(p) + Vector3.UP * 0.4))
	_police.patrol(u)


func _pilot_script() -> Script:
	return load("res://scripts/police/driving/pursuit_pilot.gd")


func _ground(p: Vector2) -> Vector3:
	return load("res://scripts/online/garages.gd")._at(p.x, p.y)


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
