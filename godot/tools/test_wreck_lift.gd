extends "res://tools/test_base.gd"
## PTA Online: a lent work vehicle wrecked on a job (scripts/online/wreck_hud.gd, online_mode.gd _offer_lift), played
## solo (PLATEAU_MODE=online, PLATEAU_ONLINE_TOW=2 for a short bar): on duty on the 4606 with a lent bus, the bus
## wrecked far from the depot: the bar fills (no "is wrecked" toast over it), then the lift is offered, E takes it (on
## foot by the depot's terminal); the fire station's lent truck wrecked: Esc turns the lift down (we stay put); our own
## car wrecked: no bar, the usual toast.
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_wreck_lift.gd
## Exit code 1 on failure.

var _main: Node
var _mode: Node
var _failures: PackedStringArray = []
var _toasts: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _toasted(part: String) -> bool:
	return _toasts.any(func(t: String) -> bool: return t.contains(part))


func _stand_at(gid: String) -> void:
	var spot: Array = _mode.garages.stand_spot(_mode.garages.get_garage(gid))
	_main.player.set_carrier(null)
	_main.player.teleport(spot[0], spot[1])
	await _frames(10)


func _ask_duty(job: Node, gid: String, ref: String) -> Array:
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	job.answered.connect(take)
	job.ask_duty(gid, ref)
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	job.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


func _to_terminal(gid: String) -> float:
	var t: Vector3 = _mode.garages.get_garage(gid)["terminal"]
	var p: Vector3 = _main.player.global_position
	return Vector2(t.x - p.x, t.z - p.z).length()


func _run() -> void:
	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_ONLINE_VEHICLES", "kaykit-hatchback")
	OS.set_environment("PLATEAU_ONLINE_TOW", "2")
	OS.set_environment("PLATEAU_CARS", "0")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 60.0)
	_mode = _main.game_mode
	_main.toast_shown.connect(func(text: String) -> void: _toasts.append(text))
	await _frames(5)
	var hud: Node = _mode._wreck
	_check(hud != null and not hud.visible, "the wreck HUD is there, hidden")

	# the bus job: a lent bus wrecked far away, the bar, then E: the lift back to the depot
	await _stand_at("bus-depot")
	var r := await _ask_duty(_mode.bus_job, "bus-depot", "4606")
	var bus: Node = _mode.car_of(_mode.mine)
	_check(r[0] and bus != null and _mode.bus_job.on_duty(), "on duty on the 4606 with a lent bus (%s)" % r[1])
	if bus == null:
		return _end()
	_mode.to_garage(_main.spawn_xy)          # far from the depot
	await _frames(10)
	var far := _to_terminal("bus-depot")
	_check(far > 200.0, "away from the depot (%d m)" % roundi(far))
	_toasts.clear()
	bus.damage(100000.0)
	_check(await _until(func() -> bool: return hud.state == "wait", 3.0) and hud.garage_id == "bus-depot",
			"the bus wrecked: the bar shows (%s, %s)" % [hud.state, hud.garage_id])
	_check(hud.title.contains("lent") and hud.title.contains("wrecked"), "it says so: %s" % hud.title)
	_check(not _toasted("The lent"), "no toast over the bar: %s" % str(_toasts))
	await _frames(30)
	var p0: float = hud.progress()
	await _frames(30)
	_check(hud.progress() > p0 and p0 > 0.0 and hud.progress() < 1.0, "the bar fills (%.2f → %.2f)" % [p0, hud.progress()])
	_press_action("interact")                # too early: nothing
	await _frames(5)
	_check(hud.state == "wait" and _to_terminal("bus-depot") > 200.0, "no lift before the bar is full")
	_mode.close_ui()                         # (that E opened the garage terminal we stand at)
	_check(await _until(func() -> bool: return hud.offering(), 4.0), "the bar full: the lift is offered")
	_check(await _until(func() -> bool: return _mode.mine == "", 3.0) and not is_instance_valid(bus),
			"the bus was towed away")
	_check(not _mode.bus_job.on_duty() and _toasted("Off duty"), "off duty: %s" % str(_toasts))
	_press_action("interact")
	await _frames(10)
	var near := _to_terminal("bus-depot")
	_check(not hud.visible and near < 5.0 and _main.driving == null, "E: on foot by the depot's terminal (%.1f m)" % near)
	_check(_toasted("Back at the bus depot"), "told where we are: %s" % str(_toasts))

	# the fire job: Esc turns the lift down
	await _stand_at("fire-station")
	r = await _ask_duty(_mode.fire_job, "fire-station", "fire")
	var truck: Node = _mode.car_of(_mode.mine)
	_check(r[0] and truck != null and truck.model_name == "fire-truck", "on duty with a lent fire truck (%s)" % r[1])
	if truck == null:
		return _end()
	_mode.to_garage(_main.spawn_xy)
	await _frames(10)
	var here: Vector3 = _main.player.global_position
	truck.damage(100000.0)
	_check(await _until(func() -> bool: return hud.offering(), 6.0) and hud.garage_id == "fire-station",
			"the truck wrecked: the lift to the fire station is offered")
	_check(_mode.close_ui() and not hud.visible, "Esc turns it down")
	_check(not _mode.close_ui(), "and Esc goes on to the menu after that")
	await _frames(10)
	_check(_main.player.global_position.distance_to(here) < 1.0, "we stayed where we were")

	# our own car wrecked: no bar
	var g: Dictionary = _mode.garages.nearest(_main.player.global_position)
	await _stand_at(g["id"])
	_toasts.clear()
	var problem: String = _mode.spawn_for(_mode.me(), g["id"], 1, "kaykit-hatchback")
	var car: Node = _mode.car_of(_mode.mine)
	_check(problem == "" and car != null, "our own car out at %s (%s)" % [g["id"], problem])
	if car:
		car.damage(100000.0)
		_check(await _until(func() -> bool: return _toasted("is wrecked"), 3.0), "our car wrecked: the usual toast")
		await _frames(10)
		_check(not hud.visible, "and no lift bar")
	_end()


func _end() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
