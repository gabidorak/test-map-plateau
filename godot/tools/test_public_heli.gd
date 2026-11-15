extends "res://tools/test_base.gd"
## PTA Online's public vehicles (scripts/online/public_vehicles.gd), in the PTA Online test (solo, offline):
## - the police helicopter stands at its place on Polytechnique's car park by the lake (data/public_vehicles.json),
##   on its skids;
## - by it, the screen says anyone may take it; E gets in, and it flies (its rotor spooled up, Shift).
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_public_heli.gd -- --online-test

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
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
		quit(1)
		return
	await _frames(120)
	var m: Node = _main.game_mode
	var pub: Node = m.public_vehicles
	_check(pub.spots.size() == 1 and pub.spots[0]["model"] == "helicopter-police", "one public vehicle: the police helicopter")
	var spot: Transform3D = pub.spots[0]["xf"]
	var heli: Node = pub._cars.get("x-police-heli")
	_check(heli != null and heli.global_position.distance_to(spot.origin) < 1.0 and heli.on_ground,
			"it stands at its place, on its skids")
	if heli == null:
		return _finish()

	_main.player.teleport(heli.to_global(Vector3(2.6, 0.3, 1.0)))
	await _frames(5)
	_check(m.prompt_text().contains("free for anyone"), "by it: anyone may take it (%s)" % m.prompt_text())
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	_check(_main.driving == heli, "E gets in")
	Input.action_press("plane_throttle_up")
	await _until(func() -> bool: return heli.height > 8.0, 20.0)
	Input.action_release("plane_throttle_up")
	_check(heli.height > 8.0, "it flies (%d m up)" % roundi(heli.height))
	_finish()


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
