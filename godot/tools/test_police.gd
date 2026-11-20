extends "res://tools/test_base.gd"
## The police (scripts/police/), in the PTA Online test (solo, offline), with a little bot traffic:
## - the road network (road_graph.gd) is built on a worker thread; ways are found between random places;
## - the fleet: UNITS cars made into the pool; AMBIENT patrols put out round the player, out of their sight; they patrol
##   (they move on) and stay round them;
## - a car sent on a call (urgent) has its siren on and gets nearer its destination;
## - wanted: a car stolen, the calls (none from a driver tased first), one star, the cars on a call; seen fleeing, two
##   stars, a chase and a search; unseen long enough, lost;
## - the helicopter: parked, takes off for someone on the run, flies there high enough, keeps above them, follows them;
##   under a tree's crown, it does not see them (in its range and line of sight); out in the open again, it does;
##   out of fuel, it flies home and sees nobody; REFUEL s later, back after them; lost, back to its base and down.
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_police.gd -- --online-test

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "10")
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
	var police: Node = _main.game_mode.police
	var made := await _until(func() -> bool: return police.units.size() == police.UNITS, 90.0)
	_check(made, "the fleet is made: %d cars (road network: %d nodes in %d ms)" % [police.units.size(),
			police.graph.node_route.size(), police.graph.build_ms])
	if not made:
		return _finish()
	# the patrols put out round the player, never in their sight
	var me: Vector3 = _main.player.global_position
	var starts := {}                        # unit index -> where it was put out
	var near := [0]
	await _until(func() -> bool:
		for u: RefCounted in police.units:
			if u.on_map() and not starts.has(u.index):
				starts[u.index] = u.where()
				if Vector2(me.x, -me.z).distance_to(u.where()) < police.HIDDEN - 10.0:
					near[0] += 1
		return starts.size() >= police.AMBIENT, 30.0)
	_check(starts.size() >= police.AMBIENT, "%d patrols put out round the player (%d wanted)" % [starts.size(),
			police.AMBIENT])
	_check(near[0] == 0, "none put out within %d m of the player" % police.HIDDEN)
	var stowed: int = police.units.filter(func(u: RefCounted) -> bool: return not u.on_map()).size()
	_check(stowed >= police.UNITS - police.AMBIENT - 2, "the rest in the pool, off the map (%d)" % stowed)

	var graph: RefCounted = police.graph
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var found := 0
	var t0 := Time.get_ticks_usec()
	for k in 40:
		var a: Vector2i = graph.random_point(rng)
		var b: Vector2i = graph.random_point(rng)
		var pieces: Array = graph.path(a, b)
		if not pieces.is_empty():
			found += 1
			var r: Dictionary = graph.make_route(pieces)
			if k == 0:
				print("     a way of %d m in %d pieces, %d lights" % [r["length"], pieces.size(), r["lights"].size()])
	var per := (Time.get_ticks_usec() - t0) / 40.0 / 1000.0
	_check(found >= 34, "ways found between random places: %d / 40 (%.1f ms each)" % [found, per])

	await _frames(60 * 40)
	var moved := 0
	var round_me := 0
	me = _main.player.global_position
	for i: int in starts:
		var u: RefCounted = police.units[i]
		if u.on_map() and u.where().distance_to(starts[i]) > 40.0:
			moved += 1
	for u: RefCounted in police.units:
		if u.on_map() and u.where().distance_to(Vector2(me.x, -me.z)) < police.AMBIENT_RANGE:
			round_me += 1
	_check(moved >= starts.size() - 1, "they patrol: %d / %d moved on in 40 s" % [moved, starts.size()])
	_check(round_me >= police.AMBIENT, "...and stay round the player (%d within %d m)" % [round_me,
			police.AMBIENT_RANGE])

	# a call: a patrol to a place ~300 m away (no case: once there, it patrols on)
	var unit: RefCounted = null
	for u: RefCounted in police.units:
		if u.on_map() and u.job == police.Unit.PATROL:
			unit = u
			break
	var bot: Object = unit.driver
	var target := Vector2.ZERO
	for k in 2000:
		var at: Vector2i = graph.random_point(rng)
		var d: float = graph.point(at).distance_to(bot.where())
		if d > 250.0 and d < 600.0:
			target = graph.point(at)
			break
	unit.set_job(police.Unit.CALL)
	unit.go(target, true)
	var d0: float = bot.where().distance_to(target)
	await _frames(10)
	_check(bot.car.siren and bot.urgent and not bot.arrived, "on a call: siren on, on its way")
	var t_call := Time.get_ticks_msec()
	var there := await _until(func() -> bool: return unit.job == police.Unit.PATROL, 240.0)
	var d1: float = bot.where().distance_to(target)
	_check(there and d1 < 40.0, "it gets there: %d m -> %d m (%.0f s of game)" % [d0, d1,
			(Time.get_ticks_msec() - t_call) / 1000.0])
	await _wanted(police)
	await _heli(police)
	_finish()


## A car stolen (the player in it): the witnesses, the call, the chase, the run, lost.
func _wanted(police: Node) -> void:
	var car: Node = _main.spawn_car_near_player("sedan")
	_main.enter_car(car)
	var key: String = _main.carjack.key_of(car)
	# its driver tased before calling: nobody calls (no bot near the spawn point to see it)
	police._on_car_stolen(1, key, "n:777")
	# (only the robbed driver's call: a bot or a police car passing by may have seen it too)
	police._calls = police._calls.filter(func(c: Dictionary) -> bool: return c["who"] == "n:777")
	if police.cases.has(1):
		police.close_case(1)
	_check(police._calls.size() == 1, "the driver robbed is about to call")
	_main.people.hit("n:777", "tased", 3.0, 1)
	await _frames(60 * 7)
	_check(police.level == 0 and police.cases.is_empty(), "tased before calling: no call")
	# reported: level 1, the nearest cars on a call to the place
	police._on_car_stolen(1, key, "n:778")
	await _frames(60 * 6)
	# (on a call; chasing already, one may see the player from where it is; searching, one there already)
	var calls: Array = police.units.filter(func(u: RefCounted) -> bool:
		return u.case == 1 and u.job in [police.Unit.CALL, police.Unit.CHASE, police.Unit.SEARCH])
	_check(police.level == 1 and calls.size() == police.DISPATCH, "reported: one star, %d cars on their way" % calls.size())
	_check(calls.all(func(u: RefCounted) -> bool: return u.car.siren), "...sirens on")
	# seen fleeing by a police car: two stars, a chase, a search
	var bot: Object = calls[0].driver
	var ahead: Vector2 = bot.at(minf(bot.s + 25.0, bot._length))  # (on its way 25 m on: in its sight, not round a bend)
	var on: Vector2 = (bot.at(minf(bot.s + 27.0, bot._length + 2.0)) - ahead).normalized()
	var f := Vector3(on.x, 0.0, -on.y)
	car.place(Transform3D(Basis(Vector3.UP, atan2(on.x, -on.y)), _ground(ahead) + Vector3.UP * 0.5))
	for k in 30:
		car.linear_velocity = f * 12.0
		await physics_frame
	_check(police.level == 2, "seen fleeing: two stars")
	var jobs: Array = police.units.map(func(u: RefCounted) -> int: return u.job)
	_check(jobs.count(police.Unit.CHASE) >= 1 and jobs.count(police.Unit.SEARCH) >= 1,
			"a chase (%d cars), a search (%d)" % [jobs.count(police.Unit.CHASE), jobs.count(police.Unit.SEARCH)])
	# their vision cones: right behind a car (beyond SIGHT_BACK) it does not see them; in front of it, from far, it does
	var seer: Object = calls[0].driver
	var cone: RefCounted = calls[0]
	var eye: Vector3 = seer.car.global_position
	var fwd: Vector3 = seer.car.global_basis.z
	_check(not police._sees(seer.car, eye - fwd * (police.SIGHT_BACK + 10.0) + Vector3.UP, []),
			"a police car does not see behind it past %d m" % police.SIGHT_BACK)
	_check(police._sees(seer.car, eye + fwd * 6.0 + Vector3.UP * 1.4, []) and cone.on_map(),
			"...and sees in front of it")
	# far away, unseen long enough: lost (no patrol put out meanwhile: one might see them from 300 m)
	police.spawning = false
	var far := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	for k in 400:
		var p: Vector2 = police.graph.point(police.graph.random_point(rng))
		if police.units.all(func(u: RefCounted) -> bool:
				return not u.on_map() or u.where().distance_to(p) > police.SIGHT_FRONT + 100.0):
			far = Vector3(p.x, 2.0, -p.y)
			break
	car.place(Transform3D(Basis(), far))
	await _frames(30)
	_check(not police.cases[1].seen, "far away: unseen (the stars blink)")
	police.cases[1].since = police.LOSE[2] - 1.0
	await _frames(120)
	var busy: Array = police.units.filter(func(u: RefCounted) -> bool:
		return u.job != police.Unit.PATROL and u.job != police.Unit.STOWED)
	_check(police.level == 0 and police.cases.is_empty() and busy.is_empty(), "lost: no star, all back on patrol")
	police.spawning = true


## The helicopter: parked on its base; someone on the run: it takes off, flies there, keeps above them; lost: back to
## its base and down, the rotor winding down. No damage on the way, never low but taking off and landing.
func _heli(police: Node) -> void:
	var heli: Node = police.heli
	_check(heli != null, "the helicopter is there")
	if heli == null:
		return
	var pilot: RefCounted = police.heli_pilot
	var base: Vector2 = pilot.base
	police.spawning = false                 # (the cars kept out of it, in the pool: the helicopter alone after them)
	for u: RefCounted in police.units:
		if u.on_map():
			u.vanish()
	# (it may be just back from the run before: its rotor winding down)
	await _until(func() -> bool: return heli.pilot == null and heli.rotor < 0.01, 60.0)
	_check(heli.on_ground and heli.rotor < 0.01 and _xy(heli).distance_to(base) < 3.0 and heli.pilot == null,
			"parked on its base, rotor still (on the ground %s, %.1f m up, %.1f m off, rotor %.2f)" % [heli.on_ground,
			heli.height, _xy(heli).distance_to(base), heli.rotor])
	var car: Node = _main.driving
	var key: String = _main.carjack.key_of(car)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spot := Vector2.ZERO
	for k in 400:
		var p: Vector2 = police.graph.point(police.graph.random_point(rng))
		if p.distance_to(base) > 400.0 and p.distance_to(base) < 700.0 \
				and police.units.all(func(u: RefCounted) -> bool: return u.where().distance_to(p) > 200.0):
			spot = p
			break
	car.place(Transform3D(Basis(), _ground(spot) + Vector3.UP * 0.5))
	await _frames(30)
	police.report(1, spot, key)
	police.set_level(1, 2)
	var health: float = heli.health
	var t0 := Time.get_ticks_msec()
	var up := await _until(func() -> bool: return heli.height > 15.0, 60.0)
	_check(up and heli.pilot != null, "on the run: it takes off (%d m up in %.0f s)" % [heli.height,
			(Time.get_ticks_msec() - t0) / 1000.0])
	var low := [INF, false]                 # the lowest once up at its height, whether it got there
	var fast := [0.0]
	var watch := func() -> bool:
		low[1] = low[1] or heli.height > 40.0
		if low[1] and pilot.order in [pilot.SEARCH, pilot.FOLLOW, pilot.HOME]:
			low[0] = minf(low[0], heli.height)
		fast[0] = maxf(fast[0], heli.linear_velocity.length())
		return pilot.order == pilot.FOLLOW and _xy(heli).distance_to(_xy(car)) < 50.0
	t0 = Time.get_ticks_msec()
	var over := await _until(watch, 120.0)
	_check(over, "it gets there and keeps above them: %d m away, %d m up (%.0f s, at most %d km/h)" % [
			_xy(heli).distance_to(_xy(car)), heli.height, (Time.get_ticks_msec() - t0) / 1000.0, fast[0] * 3.6])
	# they drive on 150 m, out in the open (no crown over them: under the trees it does not see them): it follows
	var on := Vector2.ZERO
	for k in 24:
		on = _xy(car) + Vector2(150.0, 0.0).rotated(rng.randf() * TAU)
		var at: Vector2i = police.graph.nearest(on, Vector2.ZERO, 80.0)
		if at.x >= 0:
			on = police.graph.point(at)
		if police.canopy == null or not police.canopy.hides(_ground(on) + Vector3.UP * 60.0, _ground(on) + Vector3.UP):
			break
	car.place(Transform3D(Basis(), _ground(on) + Vector3.UP * 0.5))
	var follows := await _until(func() -> bool:
		watch.call()
		return _xy(heli).distance_to(on) < 50.0, 60.0)
	_check(follows, "it follows them (%d m from where they went)" % _xy(heli).distance_to(on))
	await _canopy(police, car, on)
	await _fuel(police, car)
	# lost: back home and down
	var far := Vector2.ZERO
	for k in 400:
		var p: Vector2 = police.graph.point(police.graph.random_point(rng))
		if p.distance_to(_xy(heli)) > 900.0 \
				and police.units.all(func(u: RefCounted) -> bool: return u.where().distance_to(p) > 300.0):
			far = p
			break
	car.place(Transform3D(Basis(), _ground(far) + Vector3.UP * 0.5))
	await _frames(30)
	police.cases[1].since = police.LOSE[2] - 1.0
	t0 = Time.get_ticks_msec()
	var trace_t := [0]
	var back := await _until(func() -> bool:
		watch.call()
		if Time.get_ticks_msec() - trace_t[0] > 2000:
			trace_t[0] = Time.get_ticks_msec()
			print("     heli: order %d, %.1f m off its base, %.1f m up, on the ground %s, %.1f m/s, rotor %.2f" % [
					pilot.order, _xy(heli).distance_to(base), heli.height, heli.on_ground,
					heli.linear_velocity.length(), heli.rotor])
		return heli.pilot == null, 180.0)
	_check(back and heli.on_ground and _xy(heli).distance_to(base) < 8.0,
			"lost: back on its base (%.1f m off, %.0f s)" % [_xy(heli).distance_to(base),
			(Time.get_ticks_msec() - t0) / 1000.0])
	_check(low[0] > 25.0, "never low on the way: %d m at the lowest" % low[0])
	_check(heli.health >= health and not heli.broken, "no damage")
	await _frames(60 * 16)
	_check(heli.rotor < 0.05, "the rotor winds down")
	police.spawning = true


## Under the trees (police.gd heli_sees, air/canopy.gd): the car under a big crown near the helicopter, it does not
## see them though they are in its range and line of sight; back out in the open at `open`, it sees them again.
func _canopy(police: Node, car: Node, open: Vector2) -> void:
	var canopy: RefCounted = police.canopy
	_check(canopy != null and canopy.trees > 0, "the crowns: %d trees (%d ms)" % [canopy.trees if canopy else 0,
			canopy.build_ms if canopy else 0])
	if canopy == null or not police.cases.has(1):
		return
	var data: Resource = _main.world_root.get_node("TreeCollision").data
	var best := [-1, INF]                    # a big crown, high enough for the car, the nearest the helicopter
	for k in data.size():
		var r: Vector2 = data.crown_radii[k]
		var c: Vector3 = data.crown_center[k]
		var b: Vector3 = data.base[k]
		var d := Vector2(c.x, -c.z).distance_to(open)
		if r.x >= 4.5 and c.y - r.y > b.y + 2.5 and d < best[1] and d > 30.0:
			best = [k, d]
	_check(best[0] >= 0 and best[1] < 150.0, "a big tree %d m from them" % best[1])
	if best[0] < 0 or best[1] >= 150.0:
		return
	var k: int = best[0]
	var foot: Vector3 = data.base[k]
	var under := Vector2(foot.x, -foot.z) + (open - Vector2(foot.x, -foot.z)).normalized() \
			* (maxf(data.trunk[k].x, 0.3) + 2.2)
	car.place(Transform3D(Basis(), _ground(under) + Vector3.UP * 0.5))
	await _frames(60)
	var target: Vector3 = car.global_position + Vector3.UP
	var never := [true, false, 0]          # never seen; once in range and in its line of sight; hides() µs at most
	for i in 60 * 15:                       # (15 s of game: _until counts real time, the headless game runs faster)
		await physics_frame
		if not police.cases.has(1):
			never[0] = false
			break
		never[0] = never[0] and not police.cases[1].seen
		var eye: Vector3 = police.heli.global_position + Vector3.UP * 0.2
		if eye.distance_to(target) < police.HELI_SEE and police.in_sight(eye, target,
				[car.get_rid(), police.heli.get_rid()]):
			never[1] = true
		var t0 := Time.get_ticks_usec()
		canopy.hides(eye, target)
		never[2] = maxi(never[2], Time.get_ticks_usec() - t0)
	_check(never[0] and never[1], "under a tree: unseen by the helicopter for 15 s (in its range and line of sight: %s;"
			% never[1] + " hides() %d µs at most)" % never[2])
	car.place(Transform3D(Basis(), _ground(open) + Vector3.UP * 0.5))
	var again := await _until(func() -> bool: return police.cases.has(1) and police.cases[1].seen, 30.0)
	_check(again, "out in the open: seen again")


## Out of fuel (police.gd FUEL, REFUEL): it gives up, flies home and sees nobody; REFUEL s after it left, back after
## them. Its tank put near empty, then its time away cut short (not to wait minutes).
func _fuel(police: Node, car: Node) -> void:
	if not police.cases.has(1) or police.heli_case != 1:
		_check(false, "fuel: the helicopter after them first (case %s, after %d)" % [police.cases.has(1),
				police.heli_case])
		return
	var heli: Node = police.heli
	var pilot: RefCounted = police.heli_pilot
	police.heli_flown = police.FUEL - 1.0
	var gone := await _until(func() -> bool: return police.heli_away > 0.0, 5.0)
	_check(gone and police.heli_case == 0 and pilot.order == pilot.HOME,
			"out of fuel: it gives up and flies home (back in %.0f s)" % (police.heli_away - police.time))
	var seen := false
	var d0: float = _xy(heli).distance_to(_xy(car))
	for i in 60 * 10:                       # (10 s of game)
		await physics_frame
		seen = seen or police.heli_case != 0
	_check(not seen and _xy(heli).distance_to(_xy(car)) > d0 + 50.0,
			"...away for now: %d m -> %d m from them" % [d0, _xy(heli).distance_to(_xy(car))])
	police.heli_away = police.time + 1.0
	var back := await _until(func() -> bool: return police.heli_case == 1 and pilot.order != pilot.HOME, 5.0)
	_check(back and police.heli_flown < 5.0, "refuelled, back after them (order %d)" % pilot.order)
	var over := await _until(func() -> bool: return _xy(heli).distance_to(_xy(car)) < 60.0, 90.0)
	_check(over, "...over them again (%d m)" % _xy(heli).distance_to(_xy(car)))


## The ground at map point `p` (Godot).
func _ground(p: Vector2) -> Vector3:
	return load("res://scripts/online/garages.gd")._at(p.x, p.y)


func _xy(n: Node3D) -> Vector2:
	return Vector2(n.global_position.x, -n.global_position.z)


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
