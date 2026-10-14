extends SceneTree
## Headless checks for the bot buses (scripts/traffic.gd, scripts/bus_bot.gd; world/bus_routes.json): they spawn on
## their lines with a driver, nobody can take their wheel (E), the traffic lights run on the shared clock (shader
## global), and, driving with the physics:
## - a stop: the right indicator on the way in, the doors open at the pole, closed, the left indicator on the way out;
## - a turn: its indicator while turning; the path is followed within LATERAL m, upright;
## - a red light: waits before the line, goes on the green;
## - a vehicle parked in its lane: stops behind it without touching it, sounds the horn, goes on once it is gone;
## - a give-way junction: waits while a vehicle comes from a conflicting arm, goes once it has passed;
## - the end of its route at the map edge: waits there with its doors open while the player rides it, vanishes once
##   they are off (stowed: hidden, no collision), and comes back in on the other direction;
## - far from the player it glides along its path.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_bus_bots.gd

const LATERAL := 2.5                        # m off its path at most while driving the checks

var _main: Node
var _failures: PackedStringArray = []
var _max_lat := 0.0
var _min_up := 1.0


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
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
func _track(b: Object) -> void:
	var c: Node3D = b.car
	var p: Vector2 = b.project(b.flat(c.to_global(Vector3(0.0, 0.0, b._ref_z))), b.s - 6.0, b.s + 6.0)
	_max_lat = maxf(_max_lat, absf(p.y))
	_min_up = minf(_min_up, c.global_basis.y.y)


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	await _frames(30)
	var traffic: Node = _main.traffic
	var expected := 0
	for line: Dictionary in traffic.lines:
		expected += int(line["buses"])
	_check(traffic.bots.size() == expected and expected > 0, "%d bot buses spawned on %d lines" % [traffic.bots.size(),
			traffic.lines.size()])
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

	await _glide()
	await _stop()
	await _turn()
	await _red_light()
	await _vehicle_ahead()
	await _give_way()
	await _no_wheel()
	await _ride_to_the_edge()
	_check(_max_lat < LATERAL and _min_up > 0.9, "followed its path within %.1f m (worst %.2f), upright (worst up %.2f)" % [
			LATERAL, _max_lat, _min_up])
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## A bus far from the player glides on.
func _glide() -> void:
	var b: Object = _bot("4606")
	var s0: float = b.s
	await _frames(300)
	_check(b.gliding and (b.s > s0 + 5.0 or b.state != 0), "far from the player it glides along (%.0f -> %.0f m)" % [s0, b.s])


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
	_check(opened and at_pole < b.STOP_REACH + 0.5, "doors open at the stop, front %.1f m from the pole" % at_pole)
	_check(left and _front(b) > float(stop["s"]) + 20.0, "left indicator pulling out, then on its way")


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


## Stops behind a vehicle parked in its lane, sounds the horn, goes on once it is gone.
func _vehicle_ahead() -> void:
	var b: Object = _bot("4606")
	b.may_glide = false
	var at: float = b.s + 120.0
	var car: Node3D = _main.new_vehicle("sedan")
	_main.add_child(car)
	car.place(b.pose_at(at))
	_main._add_car(car)
	var gap := INF
	var honked := false
	var still := 0
	for f in 60 * 60:
		await physics_frame
		_track(b)
		var tail: float = b.project(b.flat(car.to_global(Vector3(0.0, 0.0, -car.half_extents.z))), at - 20.0, at + 5.0).x
		gap = minf(gap, tail - _front(b))
		honked = honked or b.horn
		still = still + 1 if absf(b.car.speed()) < 0.2 else 0
		if still > 60 * 10 and honked:
			break
	_check(gap > 0.5 and gap < 10.0, "stops behind a car parked in its lane (gap %.1f m)" % gap)
	_check(honked, "sounds the horn when kept waiting")
	_main.cars.erase(car)
	car.queue_free()
	var moved := false
	var s0: float = b.s
	for f in 60 * 15:
		await physics_frame
		if b.s > s0 + 15.0:
			moved = true
			break
	_check(moved, "goes on once the car is gone")


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
	_check(waiting > 180, "waits at the edge, doors open, while the player is aboard")
	_main.player.teleport(c.to_global(Vector3(c.half_extents.x + 6.0, 0.5, 0.0)))
	var stowed := false
	for f in 60 * 15:
		await physics_frame
		if c.stowed:
			stowed = true
			break
	_check(stowed and not c.visible and c.collision_layer == 0 and c.net_state()[4] & 64 != 0,
			"vanishes once the player is off (hidden, no collision)")
	var back := false
	for f in 60 * 60:
		await physics_frame
		if not c.stowed and b.state == 0:
			back = true
			break
	_check(back and b.route_index != edge and c.visible, "comes back in on the other direction")
