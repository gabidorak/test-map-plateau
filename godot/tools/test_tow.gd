extends SceneTree
## PTA Online's tow truck job (scripts/online/tow_job.gd, scripts/tow_truck.gd), played in the PTA Online test
## (--online-test): the tow terminal at Losplatos Custom's yard, on duty a lent tow truck on its bay, a breakdown
## (grey smoke, hazards) on the access lane, hooked from the truck's hook (lifted, pinned), towed a few seconds (it
## follows), set down in the yard: paid by the way, taken away; the next breakdown drawn on a bot car route at the
## right distance; off duty. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_tow.gd -- --online-test

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started, "the PTA Online test started")
	if not started:
		quit(1)
		return
	await _frames(5)
	var m: Node = _main.game_mode
	var tj: Node = m.tow_job
	var g: Dictionary = m.garages.get_garage(tj.GID)
	_check(not g.is_empty() and g["kind"] == "tow", "the tow terminal at Losplatos Custom's yard")
	var lp: Node = _main.losplatos
	_check(g["terminal"].distance_to(lp.frame.origin) < 40.0, "by the shop")

	# on duty: a lent tow truck on the bay
	m.to_garage(g["xy"], ["tow"])
	await _frames(5)
	_check(m.terminal_at_hand().get("id", "") == tj.GID, "by the terminal: %s" % m.prompt_text())
	var r: Array = tj.duty_for(m.me(), tj.GID)
	_check(r[0], "on duty (%s)" % r[1])
	await _frames(10)
	var truck: Node3D = m.car_of(m.mine)
	_check(truck != null and truck.model_name == "tow-truck" and tj.on_duty(), "a tow truck out")
	if truck == null:
		quit(1)
		return
	var d = tj.duties[m.me()]

	# a breakdown on the access lane, the truck before it
	var f: Transform3D = lp.frame
	var spot := f * Vector3(40.0, 0.0, -1.0)
	var fwd: Vector3 = f.basis.z                  # (east along the access lane, to the yard)
	var at := Vector3(spot.x, load("res://scripts/race_marks.gd").ground(spot.x, -spot.z) + 0.4, spot.z)
	_check(tj.breakdown(d, Transform3D(Basis.looking_at(-fwd, Vector3.UP), at)), "a breakdown called in")
	await _frames(30)
	var car: Node3D = d.target
	_check(car != null and car.indicator == 2 and car.health < car.max_health * 0.5, "hazards on, smoking")
	_check(tj.info.get("target") != null and _main.waypoint != null, "the waypoint on it")
	truck.global_transform = Transform3D(car.global_basis, car.global_position + fwd * (car.half_extents.z
			+ truck.half_extents.z + 0.7) + Vector3(0, 0.3, 0))
	truck.linear_velocity = Vector3.ZERO
	await _frames(40)
	_main.enter_car(truck)
	await _frames(5)
	_check(m.prompt_text().contains("hook"), "the hint: %s" % m.prompt_text())
	_check(truck.toggle_hook(_main.cars) == "hooked" and truck.towing == car and car.towed, "hooked")
	await _frames(5)
	_check(d.hooked, "the host knows")
	# tow it a few seconds
	Input.action_press("throttle")
	var gap := 0.0
	for i in 180:
		await physics_frame
		gap = maxf(gap, truck.hook_point().distance_to(car.global_position) - car.half_extents.z)
	Input.action_release("throttle")
	_check(car.linear_velocity.length() > 2.0 and car.global_basis.y.y > 0.8, "it follows on its wheels (%.1f m/s)" %
			car.linear_velocity.length())
	_check(_main.waypoint != null and (_main.waypoint as Vector2).distance_to(Vector2(tj.yard().x, -tj.yard().z)) < 4.0,
			"towing: the waypoint on the yard")
	# set down in the yard
	var before: int = m.test_money
	truck.unhook()
	await _frames(5)
	_check(not d.hooked and not car.towed, "set down")
	car.global_transform = Transform3D(car.global_basis, tj.yard() + Vector3(0, 0.6, 0))
	car.linear_velocity = Vector3.ZERO
	var paid := await _until(func() -> bool: return tj.events.size() == 1, 5.0)
	_check(paid and m.test_money > before, "delivered: +%d €" % (m.test_money - before))
	await _frames(5)
	_check(not is_instance_valid(car) and d.target == null, "the car taken away")
	# the next one, drawn on a bot car route
	d.wait = 0.0
	var next := await _until(func() -> bool: return d.target != null, 5.0)
	_check(next, "the next breakdown called in")
	if next:
		var dist: float = d.target.global_position.distance_to(tj.yard())
		_check(dist >= tj.pay["min_m"] - 1.0 and dist <= tj.pay["max_m"] + 1.0, "%d m from the yard" % roundi(dist))
	# off duty
	_main.exit_car()
	tj._h_off()
	await _frames(5)
	_check(not tj.on_duty() and tj.duties.is_empty(), "off duty")
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
