extends "res://tools/test_base.gd"
## Headless checks for the police helicopter (scripts/helicopter.gd, Car.SPECS "helicopter-police"), solo in Sandbox:
## - the vehicle menu parks it; its model has the rotors and the searchlight; standing, it rests on its skids;
## - E gets in (the pilot's seat: the left one); held Shift does nothing until the rotor has spooled up, then it climbs;
##   released, it holds its height, flying (the bots' perception leaves it out);
## - Space in the air: not out ("land first");
## - W: forward, nose down; released: it slows down and levels; Q turns it;
## - Ctrl: down to the ground, and it sits there; Space gets out; the rotor winds down;
## - L the searchlight; its network state carries the rotor's speed.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_helicopter.gd

const Perception = preload("res://scripts/traffic/perception.gd")

var _main: Node
var _failures: PackedStringArray = []
var _toast := ""


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(t: float) -> void:
	await _frames(roundi(t * 60.0))


func _hold(action: String, t: float) -> void:
	Input.action_press(action)
	await _seconds(t)
	Input.action_release(action)


func _run() -> void:
	await _frames(60)
	_main.toast_shown.connect(func(text: String) -> void: _toast = text)
	var player: CharacterBody3D = _main.player
	var heli: Node = _main.spawn_car_near_player("helicopter-police")
	_check(heli != null, "the vehicle menu parks the police helicopter")
	if heli == null:
		return _finish()
	_check(heli._rotor_main != null and heli._rotor_tail != null and heli._search != null,
			"its model has its main and tail rotors, a searchlight")
	await _seconds(2.0)
	_check(heli.on_ground and heli.height < 0.35 and heli.linear_velocity.length() < 0.2,
			"it rests on its skids (%.2f m)" % heli.height)

	player.teleport(heli.to_global(Vector3(2.6, 0.3, 1.0)))
	await _frames(5)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	_check(_main.driving == heli and _main._help.text.contains("FLY"), "E gets in; the help says how to fly")
	var ground_y: float = heli.global_position.y
	await _hold("plane_throttle_up", 1.0)
	_check(heli.rotor > 0.1 and heli.rotor < 0.2 and heli.global_position.y - ground_y < 0.3,
			"the rotor spools up first: still on the ground (rotor %d%%)" % roundi(heli.rotor * 100.0))
	Input.action_press("plane_throttle_up")
	await _seconds(12.0)                    # (~50 m: over the roofs, for the blind flight forward below)
	Input.action_release("plane_throttle_up")
	_check(heli.height > 15.0, "spooled up, Shift climbs (%d m up)" % roundi(heli.height))
	await _seconds(1.0)
	var y0: float = heli.global_position.y
	await _seconds(3.0)
	_check(absf(heli.global_position.y - y0) < 2.0 and absf(heli.linear_velocity.y) < 1.0,
			"released, it holds its height (%.1f m in 3 s)" % (heli.global_position.y - y0))
	_check(heli.flying(), "it is flying")
	var p := Perception.new()
	p.update(_main.get_tree(), [heli], 1.0 / 60.0)
	_check(p.cars.is_empty(), "the bots' perception leaves it out up there")

	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames(3)
	_check(_main.driving == heli and _toast.begins_with("Land first"), "Space in the air: not out (%s)" % _toast)

	var fwd: Vector3 = heli.global_basis.z
	var above_start: Vector3 = heli.global_position      # (clear: it took off from there)
	await _hold("plane_nose_down", 4.0)
	var along: float = heli.linear_velocity.dot(Vector3(fwd.x, 0.0, fwd.z).normalized())
	_check(along > 15.0, "W: forward (%d km/h)" % roundi(along * 3.6))
	await _seconds(5.0)
	var slowed: float = Vector2(heli.linear_velocity.x, heli.linear_velocity.z).length()
	var b: Basis = heli.global_basis
	_check(slowed < along * 0.6 and b.y.dot(Vector3.UP) > 0.98,
			"released: it slows down (%d km/h) and levels" % roundi(slowed * 3.6))
	var yaw0: float = heli.global_rotation.y
	await _hold("plane_rudder_left", 2.0)
	_check(absf(wrapf(heli.global_rotation.y - yaw0, -PI, PI)) > 1.0, "Q turns it")

	heli.set_headlights(true)
	_check(heli._search.visible and heli.headlights, "L: the searchlight")
	var s: Array = heli.net_state()
	_check(s.size() == 8 and is_equal_approx(float(s[7]), heli.rotor), "its network state carries the rotor's speed")

	heli.place(Transform3D(heli.global_basis, above_start))   # (back over where it took off: the flight was blind)
	Input.action_press("plane_throttle_down")
	var landed := await _until(func() -> bool: return heli.on_ground, 30.0)
	Input.action_release("plane_throttle_down")
	_check(landed, "Ctrl: down to the ground")
	await _seconds(2.0)
	_check(heli.on_ground and absf(heli.linear_velocity.y) < 0.3, "it sits there, collective down")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames(5)
	_check(_main.driving == null and player.visible, "Space gets out once landed")
	await _seconds(3.0)
	_check(heli.rotor < 0.85, "the rotor winds down (%d%%)" % roundi(heli.rotor * 100.0))
	_check(heli.audio.engine_on and heli.audio.level > 0.5, "...still heard as it winds down")
	await _until(func() -> bool: return heli.rotor == 0.0, 20.0)
	_check(not heli.audio.engine_on and heli.audio.level == 0.0, "silent once the blades stand still")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ALL HELICOPTER CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
