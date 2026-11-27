extends "res://tools/test_base.gd"
## PTA Online's phone (scripts/online/phone.gd), played solo: P opens it, the Jobs app's lift to the bus depot waits
## STILL s standing still then puts us by the depot's terminal; moving calls it off.
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_phone.gd -- --online-test
## Exit code 1 on failure.

var _main: Node
var _mode: Node
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
	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_CARS", "0")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 60.0)
	_mode = _main.game_mode
	await _frames(5)
	var phone: Node = _mode.phone
	_press_action("phone")
	await _frames(2)
	_check(phone.is_open() and _main.ui_open(), "P opens the phone")
	phone._open_app("jobs")
	_mode.to_garage(_main.spawn_xy)
	await _frames(10)
	var depot: Dictionary = _mode.garages.get_garage("bus-depot")
	phone._ask_lift("bus-depot", "the bus depot")
	await _frames(60)
	_main.player.teleport(_main.player.global_position + Vector3(3, 0, 0))
	await _frames(5)
	_check(phone._going.is_empty(), "moving calls the lift off")
	phone._ask_lift("bus-depot", "the bus depot")
	await _frames(13 * 60)
	_check(not phone._going.is_empty(), "13 s still: not there yet")
	await _frames(3 * 60)
	var tp: Vector3 = depot["terminal"]
	var p: Vector3 = _main.player.global_position
	var d := Vector2(tp.x - p.x, tp.z - p.z).length()
	_check(phone._going.is_empty() and d < 10.0, "16 s still: by the depot's terminal (%.1f m)" % d)
	_check(not phone.is_open(), "and the phone closed")
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
