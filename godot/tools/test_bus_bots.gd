extends SceneTree
## Headless checks for the bot buses (scripts/traffic.gd, scripts/bus_bot.gd; world/bus_routes.json), the bot cars
## off (tools/test_car_bots.gd): they spawn on both directions of each line with a driver, a bus sets off from the
## start of each direction every headway, nobody can take their wheel (E), the traffic lights run on the shared clock
## (shader global), and, one bus per line left (the others stowed, no more departures), driving with the physics:
## - a stop: the right indicator on the way in, the doors open at the pole, closed, the left indicator on the way out;
## - boarding: the doors held for a player by one outside, closed once they are in, out of the doorway;
## - a turn: its indicator while turning; the path is followed within LATERAL m, upright;
## - a red light: waits before the line, goes on the green;
## - a vehicle parked in its lane: stops behind it without touching it, then overtakes it where there is room on the
##   left; where there is none, sounds the horn and goes on once it is gone;
## - a give-way junction: waits while a vehicle comes from a conflicting arm, goes once it has passed; does not wait for
##   one coming the other way through the junction on its own side of the road, going straight on;
## - the end of its route at the map edge: waits there with its doors open while the player rides it, vanishes once
##   they are off (stowed: hidden, no collision), and comes back in at a departure of its line;
## - far from the player it glides along its path.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_bus_bots.gd
## PLATEAU_TEST_ONLY=vehicle_ahead,ride_to_the_edge,... runs some of the checks after the first ones (departures too).

const LATERAL := 2.5                        # m off its path at most while driving the checks

var _main: Node
var _failures: PackedStringArray = []
var _max_lat := 0.0
var _min_up := 1.0


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "0")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _bot(ref: String) -> Object:
	for b: Object in _main.traffic.bots:
		if b.line["ref"] == ref:
			return b
	return null


## Distance along the path of the front of the bus.
func _front(b: Object) -> float:
	return b.s + b.nose


## Off the path (m) of the bus's reference point, and the worst so far.
func _track(b: Object, overtaking := false) -> void:
	if overtaking:
		return                              # off its path on purpose
	var c: Node3D = b.car
	var p: Vector2 = b.project(b.flat(c.to_global(Vector3(0.0, 0.0, b._ref_z))), b.s - 6.0, b.s + 6.0)
	_max_lat = maxf(_max_lat, absf(p.y))
	_min_up = minf(_min_up, c.global_basis.y.y)


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	await _frames(30)
	var traffic: Node = _main.traffic
	# both directions of every line have buses out
	var out := {}
	for b: Object in traffic.bots:
		if not b.idle:
			var rid: String = b.line["routes"][b.route_index]
			out[rid] = out.get(rid, 0) + 1
	var missing := []
	for line: Dictionary in traffic.lines:
		for rid: String in line["routes"]:
			if out.get(rid, 0) == 0:
				missing.append(rid)
	_check(traffic.lines.size() > 0 and missing.is_empty(), "buses out on both directions of the %d lines (%s; none on %s)" % [
			traffic.lines.size(), out, missing])
	var all_bots := true
	for b: Object in traffic.bots:
		all_bots = all_bots and b.car.is_bot() and b.car._driver_dummy.visible and b.car.net_state()[4] & 32 != 0
	_check(all_bots, "each has a bot at the wheel (driver shown, net flag)")

	# the lights' shared clock
	var c0: float = traffic.signal_clock
	await _frames(30)
	await process_frame
	var c1: float = traffic.signal_clock
	var shader: Variant = RenderingServer.global_shader_parameter_get("signal_clock")     # null with no renderer
	_check(c1 != c0 and absf(c1 - fposmod(traffic.clock(), traffic.CYCLE)) < 0.1 and (shader == null or absf(float(shader) - c1) < 0.01),
			"the signal shader runs on the game clock (%.2f -> %.2f)" % [c0, c1])

	var only := OS.get_environment("PLATEAU_TEST_ONLY").split(",", false)    # (some of the checks below)
	if only.is_empty() or "departures" in only:
		await _departures()
	await _glide()
	# one bus per line from here on
	traffic.departures.clear()
	var kept := {}
	for b: Object in traffic.bots:
		if kept.has(b.line["ref"]) or b.idle:
			if not b.idle:
				b._stow()
		else:
			kept[b.line["ref"]] = b
	await _frames(2)
	for check: Callable in [_stop, _board, _turn, _red_light, _vehicle_ahead, _give_way, _oncoming_at_junction, _no_wheel,
			_ride_to_the_edge]:
		if only.is_empty() or check.get_method().trim_prefix("_") in only:
			await check.call()
	_check(_max_lat < LATERAL and _min_up > 0.9, "followed its path within %.1f m (worst %.2f), upright (worst up %.2f)" % [
			LATERAL, _max_lat, _min_up])
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## A bus sets off from the start of each direction every headway (the ones fed by a terminus run on into from the one
## before).
func _departures() -> void:
	var traffic: Node = _main.traffic
	var h := 0.0
	for line: Dictionary in traffic.lines:
		h = maxf(h, float(line["headway"]))
	var before: Dictionary = traffic.departed.duplicate()
	var t0: float = traffic.time
	var net: Node = _main.net
	var c0: float = net.clock()
	while traffic.time < t0 + 2.0 * h + 1.0:
		await physics_frame
		net.clock_shift = c0 + traffic.time - t0 - (net.clock() - net.clock_shift)   # lights at the simulated pace
	net.clock_shift = 0.0
	var short := []
	for d: Array in traffic.departures:
		var rid: String = d[0]["routes"][d[1]]
		if traffic.departed.get(rid, 0) - before.get(rid, 0) < 2:
			short.append("%s: %d" % [rid, traffic.departed.get(rid, 0) - before.get(rid, 0)])
	_check(not traffic.departures.is_empty() and short.is_empty(), "a bus sets off every headway from the start of each of the %d directions fed from the edge or a terminus (short: %s)" % [
			traffic.departures.size(), short])


## The buses far from the player glide on (most of them: some wait at a light, a stop, behind another).
func _glide() -> void:
	var s0 := {}
	for b: Object in _main.traffic.bots:
		s0[b] = [b.s, b.route_index]
	await _frames(300)
	var on := 0
	var gliding := 0
	for b: Object in _main.traffic.bots:
		if b.gliding and not b.idle:
			gliding += 1
			if b.s > s0[b][0] + 5.0 or b.route_index != s0[b][1] or b.state != 0:
				on += 1
	_check(gliding > 0 and on >= gliding * 0.6, "far from the player they glide along (%d of %d gliding moved on)" % [on, gliding])


## Right indicator in, doors at the pole, left indicator out.
func _stop() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var stop: Dictionary = b.route["stops"][1]
	b.put(b.route_index, float(stop["s"]) - b.nose - 90.0)
	var right := false
	var opened := false
	var at_pole := INF
	var left := false
	for f in 60 * 60:
		await physics_frame
		_track(b)
		var c: Node3D = b.car
		if b.state == 0 and _front(b) < float(stop["s"]) and c.indicator == -1:
			right = true
		if c.doors_open and b.state == 1:
			opened = true
			at_pole = minf(at_pole, absf(_front(b) - float(stop["s"])))
		if opened and b.state == 0 and c.indicator == 1:
			left = true
		if left and _front(b) > float(stop["s"]) + 20.0:
			break
	_check(right, "right indicator on the way into the stop %s" % stop["name"])
	_check(opened and at_pole < b.STOP_REACH + 0.5, "doors open at the stop, front %.1f m from its stopping point" % at_pole)
	_check(left and _front(b) > float(stop["s"]) + 20.0, "left indicator pulling out, then on its way")


## At a stop with the player by a door outside it waits for them; once they are in and out of the doorway, it closes its
## doors (no longer than with nobody there).
func _board() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var stop: Dictionary = b.route["stops"][2]
	b.put(b.route_index, float(stop["s"]) - b.nose - 60.0)
	var c: Node3D = b.car
	var opened := false
	for f in 60 * 60:
		await physics_frame
		if b.state == 1 and c.doors_open:
			opened = true
			break
	var dc: Vector3 = c.door_centres[0]
	_main.player.teleport(c.to_global(dc + Vector3(signf(dc.x) * 1.5, 0.3, 0.0)))
	var held := false
	for f in 60 * 30:
		await physics_frame
		if not c.doors_open:
			break
		if b._timer > b._dwell + 3.0:
			held = true
			break
	_check(opened and held, "doors held open past its dwell (%.1f s) while the player stands by one outside" % b._dwell)
	# in, a couple of metres down the aisle from that door (still within DOOR_REACH of it)
	var box: AABB = c.interior
	var z: float = dc.z + 1.8 if dc.z + 1.8 < box.end.z - 0.4 else dc.z - 1.8
	_main.player.teleport(c.to_global(Vector3(box.get_center().x, box.position.y + 0.05, z)))
	var closed_after := INF                 # s (it is past its dwell already)
	for f in 60 * 30:
		await physics_frame
		if not c.doors_open:
			closed_after = f / 60.0
			break
	_check(is_instance_valid(_main.player.carrier) and closed_after < 1.0,
			"the player in, out of the doorway, it closes them (%.1f s later)" % closed_after)
	var left := false
	for f in 60 * 30:
		await physics_frame
		if b.state == 0:
			left = true
			break
	_check(left, "and sets off with them aboard")
	_main.player.teleport(c.to_global(Vector3(c.half_extents.x + 6.0, 0.5, 0.0)))
	await _frames(30)


## Its indicator while it turns.
func _turn() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var turn: Array = []
	for t: Array in b.route["turns"]:
		var clear := true
		for st: Dictionary in b.route["stops"]:
			clear = clear and absf(float(st["s"]) - float(t[0])) > 80.0
		if clear:
			turn = t
			break
	b.put(b.route_index, float(turn[0]) - b.nose - 40.0)
	var frames := 0
	var right_side := 0
	for f in 60 * 60:
		await physics_frame
		_track(b)
		var front := _front(b)
		if front > float(turn[0]) + 3.0 and front < float(turn[1]) - 3.0:
			frames += 1
			right_side += 1 if b.car.indicator == int(turn[2]) else 0
		if front > float(turn[1]) + 5.0:
			break
	_check(frames > 0 and right_side >= frames * 0.9, "%s indicator through the turn (%d/%d frames)" % [
			"left" if int(turn[2]) == 1 else "right", right_side, frames])


## Waits at a red light, goes on the green.
func _red_light() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var light: Dictionary = {}
	for r in b.line["routes"].size():
		var rt: Dictionary = _main.traffic.routes[b.line["routes"][r]]
		for l: Dictionary in rt["lights"]:
			if float(l["s"]) > 150.0:
				light = l
				b.put(r, float(l["s"]) - b.nose - 80.0)
				break
		if not light.is_empty():
			break
	var net: Node = _main.net
	var phase: float = light["phase"]
	var held := 0
	var front_at_red := -INF
	for f in 60 * 60:
		net.clock_shift = 0.0
		net.clock_shift = (0.75 - phase) * _main.traffic.CYCLE - net.clock()   # red, for as long as the check needs
		await physics_frame
		_track(b)
		front_at_red = maxf(front_at_red, _front(b))
		if absf(b.car.speed()) < 0.2 and float(light["s"]) - _front(b) < 8.0:
			held += 1
			if held > 300:
				break
	_check(held > 300 and front_at_red <= float(light["s"]) + 0.5, "waits at the red light (front %.1f m before the line, %d frames, v %.2f, %s)" % [
			float(light["s"]) - front_at_red, held, b.car.speed(), b.reason])
	var passed := false
	for f in 60 * 20:
		net.clock_shift = 0.0
		net.clock_shift = (0.1 - phase) * _main.traffic.CYCLE - net.clock()    # green
		await physics_frame
		if _front(b) > float(light["s"]) + 5.0:
			passed = true
			break
	_check(passed, "goes on the green")
	net.clock_shift = 0.0


## Stops behind a vehicle parked in its lane; overtakes it where there is room on the left, without touching it, and
## gets back in its lane; where there is none, sounds the horn and goes on once the vehicle is gone.
func _vehicle_ahead() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	for room in [true, false]:
		var spot := _parking_spot(b, room)
		if spot.is_empty():
			_check(false, "a stretch of the 4606 with%s room to overtake" % ("" if room else "out"))
			continue
		b.put(spot[0], spot[1] - b.nose - 100.0)
		var at: float = spot[1]
		var car: Node3D = _main.new_vehicle("sedan")
		_main.add_child(car)
		car.place(b.pose_at(at))
		_main._add_car(car)
		var gap := INF
		var shove := 0.0                    # fastest the parked car moved while the bus was by it
		var honked := false
		var still := 0
		var past := false
		var lat_after := 0.0
		for f in 60 * 60:
			await physics_frame
			_track(b, b.s > at - 40.0 and b.s < at + 40.0)
			var tail: float = b.project(b.flat(car.to_global(Vector3(0.0, 0.0, -car.half_extents.z))), at - 20.0, at + 5.0).x
			if absf(b.car.speed()) < 0.2 and _front(b) < tail:
				gap = minf(gap, tail - _front(b))
			if _front(b) > tail - 3.0 and b.s - b.tail < at + 5.0:
				shove = maxf(shove, car.linear_velocity.length())
			honked = honked or b.horn
			still = still + 1 if absf(b.car.speed()) < 0.2 else 0
			if room and b.s - b.tail > at + 30.0:
				past = true
				var p: Vector2 = b.project(b.flat(b.car.to_global(Vector3(0.0, 0.0, b._ref_z))), b.s - 6.0, b.s + 6.0)
				lat_after = absf(p.y)
				if b.s - b.tail > at + 50.0:
					break
			# (its own blocked timer: on a slope the body creeps, which resets `still`, and at GIVE_UP it vanishes)
			if not room and honked and (still > 60 * 10 or b._blocked_t > b.HORN_AFTER + 4.0):
				break
		if room:
			_check(gap > b.GAP and gap < b.GAP + b.PASS_IN + 5.0, "stops behind a car parked in its lane, room to pull out (gap %.1f m)" % gap)
			_check(past and shove < 0.5 and lat_after < 1.0, "overtakes it on the left without touching it (pushed at %.2f m/s), back in its lane (%.1f m off)" % [
					shove, lat_after])
		else:
			_check(gap > 0.5 and gap < 10.0 and b.s < at, "stops behind a car parked where it cannot overtake (gap %.1f m, %s)" % [
					gap, b.reason])
			_check(honked, "sounds the horn when kept waiting")
		_main.cars.erase(car)
		car.queue_free()
		if not room:
			var moved := false
			var s0: float = b.s
			for f in 60 * 15:
				await physics_frame
				if b.s > s0 + 15.0:
					moved = true
					break
			_check(moved, "goes on once the car is gone")


## [route index, s] of a straight stretch of `b`'s routes 200 m in, where the room on the left is (`room`) or is not
## enough to overtake a car, with no light, give-way or stop near; [] if none.
func _parking_spot(b: Object, room: bool) -> Array:
	for r in b.line["routes"].size():
		var rt: Dictionary = _main.traffic.routes[b.line["routes"][r]]
		b._set_route(r)
		var d := 200.0
		while d < float(rt["length"]) - 200.0:
			var ok := true
			for k in range(-60, 61, 5):
				var m: float = b._room_at(d + k)
				ok = ok and (m > 3.0 if room else m < 1.0)
			for key in ["lights", "yields", "stops"]:
				for e: Dictionary in rt[key]:
					ok = ok and (float(e["s"]) < d - 140.0 or float(e["s"]) > d + 90.0)     # (the bus comes from 100 m back)
			if ok and (b.at(d + 40.0) - b.at(d - 40.0)).length() > 79.0:
				return [r, d]
			d += 10.0
	return []


## Waits at a give-way line while a vehicle comes from a conflicting arm.
func _give_way() -> void:
	var b: Object = _bot("4606")
	var found := false
	var y: Dictionary = {}
	for bot: Object in _main.traffic.bots:
		for r in bot.line["routes"].size():
			var rt: Dictionary = _main.traffic.routes[bot.line["routes"][r]]
			for yy: Dictionary in rt["yields"]:
				if not yy["stop"] and not yy["arms"].is_empty() and float(yy["s"]) > 100.0:
					b = bot
					y = yy
					b.may_glide = false
					b.put(r, float(yy["s"]) - b.nose - 3.0)
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		_check(false, "a give-way junction to test")
		return
	var j := Vector2(y["x"], y["y"])
	var arm := Vector2(y["arms"][0][0], y["arms"][0][1])
	var car: Node3D = _main.new_vehicle("sedan")
	_main.add_child(car)
	_main._add_car(car)
	for body: RigidBody3D in car.bodies():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	var map: RefCounted = load("res://scripts/ground_map.gd").get_map()
	var start := j + arm * 30.0
	var dir := -arm
	var front_max := -INF
	var waited := false
	var crossed_after := false
	var d := 0.0
	var line_s: float = y["s"]
	for f in 60 * 40:
		# the car drives in at 5 m/s, through the junction and away, while the bus waits at the line
		var go := true
		d += 5.0 / 60.0
		var p := start + dir * d
		var g := Vector3(p.x, map.height(p.x, p.y) + 0.3, -p.y)
		car.global_transform = Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, -dir.y), Vector3.UP, true), g)
		await physics_frame
		_track(b)
		var car_past: bool = (p - j).dot(dir) > float(y["r"])        # through the junction
		if not car_past:
			front_max = maxf(front_max, _front(b))
			if go and absf(b.car.speed()) < 0.3 and line_s - _front(b) < 6.0:
				waited = true
		elif _front(b) > line_s + 3.0:
			crossed_after = true
			break
	_check(waited and front_max < line_s + 1.0, "gives way at %s (%s) while a car comes (front %.1f m from the line)" % [
			Vector2(y["x"], y["y"]), y["why"], line_s - front_max])
	_check(crossed_after, "goes once the car has passed")
	_main.cars.erase(car)
	car.queue_free()


## Going straight on over a give-way junction, it does not wait for a car coming the other way through it in the other
## lane.
func _oncoming_at_junction() -> void:
	var b: Object = null
	var y: Dictionary = {}
	var r := -1
	for bot: Object in _main.traffic.bots:
		if bot.line["ref"] == "car":
			continue
		for k in bot.line["routes"].size():
			bot._set_route(k)
			for yy: Dictionary in bot.route["yields"]:
				var j: float = yy["s"]
				var turn: float = (bot.at(j) - bot.at(j - 15.0)).angle_to(bot.at(j + 30.0) - bot.at(j + 10.0))
				var calm := true                # nothing else to stop for on the way in
				for e: Dictionary in bot.route["stops"] + bot.route["lights"]:
					calm = calm and (float(e["s"]) < j - 140.0 or float(e["s"]) > j + 20.0)
				if not yy["stop"] and j > 150.0 and absf(turn) < 0.25 and bot._room_at(j + 10.0) > 2.5 and calm:
					b = bot
					y = yy
					r = k
					break
			if b:
				break
		if b:
			break
	if b == null:
		_check(false, "a give-way junction crossed straight on, to meet a car at")
		return
	var line_s: float = y["s"]
	b.may_glide = false
	b.put(r, line_s - b.nose - 120.0, 8.0)
	while _front(b) < line_s - 30.0:
		await physics_frame
	var car: Node3D = _main.new_vehicle("sedan")
	_main.add_child(car)
	_main._add_car(car)
	for body: RigidBody3D in car.bodies():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	var map: RefCounted = load("res://scripts/ground_map.gd").get_map()
	var lane := -minf(b._room_at(line_s + 10.0), 3.0)
	var slowest := INF
	var d := line_s + float(y["r"]) + 8.0       # the car's place along the bus's path, crawling back down it (in the
												# junction as the bus comes)
	var met := false
	for f in 60 * 30:
		d -= 3.0 / 60.0
		var p: Vector2 = b.at(d)
		var t: Vector2 = (b.at(d + 1.0) - p).normalized()
		var q := p + Vector2(t.y, -t.x) * lane
		var g := Vector3(q.x, map.height(q.x, q.y) + 0.3, -q.y)
		car.global_transform = Transform3D(Basis.looking_at(Vector3(t.x, 0.0, -t.y), Vector3.UP, false), g)
		car.linear_velocity = Vector3(-t.x, 0.0, t.y) * 3.0
		await physics_frame
		# from the car entering the junction until it has passed the bus's line
		if d < line_s + float(y["r"]) + 20.0 and d > line_s - 5.0:
			met = true
			slowest = minf(slowest, b.car.speed())
		if d < line_s - 30.0:
			break
	_check(met and slowest > 3.0, "does not slow down at %s (%s) for a car coming the other way through it (slowest %.1f m/s)" % [
			Vector2(y["x"], y["y"]), y["why"], slowest])
	_main.cars.erase(car)
	car.queue_free()


## E next to a bot bus does not take its wheel.
func _no_wheel() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var c: Node3D = b.car
	await _frames(10)
	_main.player.teleport(c.to_global(Vector3(c.half_extents.x + 1.2, 0.3, c.extents_center.z)))
	await _frames(20)
	_key(KEY_E, true)
	await _frames(2)
	_key(KEY_E, false)
	await _frames(10)
	_check(_main.driving == null and _main._toast.text.contains("bot"), "E next to it does not take the wheel (\"%s\")" % [
			_main._toast.text])


## The end of its route at the edge with the player aboard, then off; it vanishes and comes back on the other direction.
func _ride_to_the_edge() -> void:
	var b: Object = _bot("4619")
	b.may_glide = false
	var edge := -1
	for r in b.line["routes"].size():
		if _main.traffic.routes[b.line["routes"][r]]["end"] == "edge":
			edge = r
	b.put(edge, float(_main.traffic.routes[b.line["routes"][edge]]["length"]) - b.nose - 40.0)
	await _frames(30)
	var c: Node3D = b.car
	var aisle: Vector3 = c.interior.get_center()
	_main.player.teleport(c.to_global(Vector3(aisle.x, c.interior.position.y + 0.05, aisle.z)))
	await _frames(30)
	_check(is_instance_valid(_main.player.carrier) and _main.riders(c) == 1, "the player standing in it rides it")
	var waiting := 0
	for f in 60 * 60:
		await physics_frame
		if b.state == 2 and c.doors_open and not c.stowed:
			waiting += 1
			if waiting > 180:
				break
	_check(waiting > 180, "waits at the edge, doors open, while the player is aboard (state %d, %s, front %.0f / %.0f m, %d riders)" % [
			b.state, b.reason, _front(b), b._length, _main.riders(c)])
	_main.player.teleport(c.to_global(Vector3(c.half_extents.x + 6.0, 0.5, 0.0)))
	var stowed := false
	for f in 60 * 15:
		await physics_frame
		if c.stowed:
			stowed = true
			break
	_check(stowed and not c.visible and c.collision_layer == 0 and c.net_state()[4] & 64 != 0,
			"vanishes once the player is off (hidden, no collision)")
	var traffic: Node = _main.traffic
	traffic._start_line(b.line, false)      # its departures again (the other lines' stay off)
	var back: Object = null
	for f in 60 * 60 * 3:
		await physics_frame
		for o: Object in traffic.bots:
			if o.line == b.line and not o.idle and o.route_index != edge and o.car.visible:
				back = o
		if back:
			break
	_check(back != null and (back != b or c.visible), "a bus of the line comes back in on the other direction")
