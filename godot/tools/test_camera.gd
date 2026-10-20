extends SceneTree
## Headless checks for the vehicle cameras (car.gd _update_camera, plane.gd _update_camera): the look back (Z, W on
## AZERTY) and camera mode (right click) bindings; the auto camera keeps a look offset at a standstill, keeps it
## LOOK_HOLD s at speed then eases back behind, never turns round when reversing; the look back key turns the view half
## round at once and back on release; a right click switches to the free camera (the view keeps its world direction
## while the car turns; the dash says so) and back (the view stays, then eases back), held it switches only while
## held; the fire truck holds the view (and the cannon's aim) while it sprays, then eases back; the cab view looks the
## same way as the chase camera (auto, free, looking back); the plane's chase camera shows only part of the bank, no
## jump through a roll or a loop, and follows the plane over the top of a loop.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_camera.gd

const Car = preload("res://scripts/car.gd")
const Biplane = preload("res://scripts/plane.gd")
const FireTruck = preload("res://scripts/fire_truck.gd")

var _main: Node
var _failures: PackedStringArray = []


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


## Two frames: process_frame comes before the nodes' _process, so the cameras have moved after the second.
func _settle() -> void:
	await process_frame
	await process_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _right_button(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Horizontal angle (degrees) between two directions.
func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))


## Where `cam` looks, global.
func _dir(cam: Camera3D) -> Vector3:
	return -cam.global_basis.z


## Frozen where it stands, `car` reports `v` m/s forward for `n` frames (the camera only reads the speed).
func _hold_speed(car: VehicleBody3D, v: float, n: int) -> void:
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	for i in n:
		car.linear_velocity = car.global_basis.z * v
		await physics_frame


func _turn(car: VehicleBody3D, angle: float) -> void:
	car.global_transform = Transform3D(Basis(Vector3.UP, angle) * car.global_basis, car.global_position)


func _get_in(car: VehicleBody3D) -> bool:
	var player: CharacterBody3D = _main.player
	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	return _main.driving == car


func _get_out() -> void:
	_tap(KEY_SPACE)
	await _frames(5)


func _run() -> void:
	await _frames(60)
	var settings := root.get_node("Settings")
	_check(settings.bindings("look_back") == [KEY_Z] and settings.bindings("camera_mode") == [-MOUSE_BUTTON_RIGHT],
			"look back on Z (W on AZERTY), camera mode on the right button")
	_check(settings.conflicts("look_back", KEY_Z).is_empty() and settings.conflicts("camera_mode", -MOUSE_BUTTON_RIGHT).is_empty(),
			"neither clashes with another vehicle key")
	await _car_checks()
	await _truck_checks()
	await _plane_checks()
	_finish()


func _car_checks() -> void:
	Car.free_camera = false
	var car: VehicleBody3D = _main.spawn_car_near_player("sedan")
	if car == null or not await _get_in(car):
		_check(false, "gets in a sedan")
		return
	var cam: Camera3D = car.camera

	# reversing while looking back still steers both ways (S, A and Z held: S, Q and W on AZERTY)
	_key(KEY_S, true)
	await _frames(90)
	_key(KEY_Z, true)
	_key(KEY_A, true)
	await _frames(30)
	var left: float = car.steering
	var looking: bool = car._looking_back
	_key(KEY_A, false)
	_key(KEY_D, true)
	await _frames(40)
	var right: float = car.steering
	_key(KEY_D, false)
	_key(KEY_Z, false)
	_key(KEY_S, false)
	_check(car.speed() < -1.0 and looking and left > 0.2 and right < -0.2,
			"reversing (%.1f m/s) while looking back: steers left (%.2f) and right (%.2f)" % [car.speed(), left, right])

	car._look_yaw = 1.2
	car._look_idle = 0.0
	await _hold_speed(car, 0.0, 240)
	_check(absf(car._look_yaw - 1.2) < 0.01, "at a standstill the look offset stays (%.2f after 4 s)" % car._look_yaw)

	car._look_yaw = 1.2
	car._look_idle = 0.0
	await _hold_speed(car, 15.0, 90)
	var held: float = car._look_yaw
	await _hold_speed(car, 15.0, 180)
	_check(held > 1.15 and car._look_yaw < 0.5,
			"at 54 km/h the offset holds while the mouse rests (%.2f after 1.5 s), then eases back (%.2f 3 s later)" % [
			held, car._look_yaw])

	car._look_yaw = 0.0
	await _hold_speed(car, -5.0, 180)
	_check(_deg(_dir(cam), car.global_basis.z) < 10.0,
			"reversing 3 s, the view stays behind the car (%.0f° off ahead)" % _deg(_dir(cam), car.global_basis.z))

	Input.action_press("look_back")
	await process_frame
	await process_frame
	var back := _deg(_dir(cam), car.global_basis.z)
	Input.action_release("look_back")
	await process_frame
	await process_frame
	_check(back > 170.0 and _deg(_dir(cam), car.global_basis.z) < 10.0,
			"look back held: the view turns round at once (%.0f°), and back on release" % back)

	_right_button(true)
	_right_button(false)
	await _hold_speed(car, 15.0, 2)
	await process_frame
	_check(Car.free_camera and "FREE CAMERA" in _main._dash.text, "a right click: the free camera (the dash says so)")
	var fixed := _dir(cam)
	_turn(car, 1.2)
	await _hold_speed(car, 15.0, 30)
	_check(_deg(_dir(cam), fixed) < 3.0, "free: the car turns 69°, the view keeps its direction (%.1f° off)" % _deg(_dir(cam), fixed))

	_right_button(true)
	_right_button(false)
	await _hold_speed(car, 15.0, 2)
	await process_frame
	var stayed := _deg(_dir(cam), fixed)
	await _hold_speed(car, 15.0, 120)
	_check(not Car.free_camera and stayed < 8.0 and _deg(_dir(cam), car.global_basis.z) < 25.0,
			"another click: auto, the view starts from where it was (%.1f° off) and is back behind within 2 s, no wait (%.0f° off)" % [
			stayed, _deg(_dir(cam), car.global_basis.z)])

	_right_button(true)
	await _hold_speed(car, 0.0, 40)
	var during: bool = Car.free_camera
	_right_button(false)
	await process_frame
	_check(during and not Car.free_camera, "held 0.7 s: free only while held")
	await _get_out()


func _truck_checks() -> void:
	Car.free_camera = false
	var truck: VehicleBody3D = _main.spawn_car_near_player("fire-truck")
	if truck == null or not await _get_in(truck):
		_check(false, "gets in the fire truck")
		return
	if truck.cab_view:
		truck.set_cab_view(false)
	var cam: Camera3D = truck.camera

	truck._look_yaw = 0.8
	truck._look_idle = 0.0
	Input.action_press("fire")
	await _hold_speed(truck, 8.0, 5)
	var fixed := _dir(cam)
	var bearing: Vector3 = truck.aim_target - truck.global_position
	_turn(truck, 1.0)
	await _hold_speed(truck, 8.0, 30)
	await process_frame
	var bearing2: Vector3 = truck.aim_target - truck.global_position
	_check(truck.holds_aim() and _deg(_dir(cam), fixed) < 3.0 and _deg(bearing, bearing2) < 5.0
			and "CAMERA HELD" in _main._dash.text,
			"spraying, the truck turns 57°: the view (%.1f° off) and the cannon's target (%.1f° off) hold" % [
			_deg(_dir(cam), fixed), _deg(bearing, bearing2)])
	Input.action_release("fire")
	await _hold_speed(truck, 8.0, roundi((FireTruck.AIM_HOLD + 0.5) * 60.0))
	var stayed := _deg(_dir(cam), fixed)
	var still_held: bool = truck.holds_aim()
	await _hold_speed(truck, 8.0, roundi((Car.LOOK_HOLD + 4.0) * 60.0))
	_check(not still_held and stayed < 3.0 and _deg(_dir(cam), truck.global_basis.z) < 15.0,
			"after spraying the view stays (%.1f° off), then eases back behind (%.0f° off)" % [stayed,
			_deg(_dir(cam), truck.global_basis.z)])

	# the cab view looks where the chase camera looks
	await _hold_speed(truck, 0.0, 30)
	truck._look_yaw = 1.0
	truck._look_idle = 0.0
	await _settle()
	var chase := _dir(cam)
	truck.set_cab_view(true)
	await _settle()
	_check(root.get_camera_3d() == truck._cab_camera and _deg(_dir(truck._cab_camera), chase) < 3.0,
			"auto: zoomed in, the cab view looks the way the chase camera did, 57° left (%.1f° off)" % \
			_deg(_dir(truck._cab_camera), chase))
	Car.free_camera = true
	_turn(truck, -0.8)
	await _hold_speed(truck, 0.0, 5)         # the frozen body takes its new pose at the next physics step
	await _settle()
	_check(_deg(_dir(truck._cab_camera), chase) < 3.0 and _deg(_dir(truck._cab_camera), _dir(cam)) < 3.0,
			"free: the truck turns, the cab view keeps its direction like the chase camera (%.1f° off)" % \
			_deg(_dir(truck._cab_camera), chase))
	Input.action_press("look_back")
	await _settle()
	var behind := _deg(_dir(truck._cab_camera), -chase)
	Input.action_release("look_back")
	await _settle()
	_check(behind < 3.0, "looking back from the cab: the opposite way (%.1f° off)" % behind)
	truck.set_cab_view(false)
	await _settle()
	_check(_deg(_dir(cam), chase) < 3.0, "zoomed out, the chase camera still looks that way")
	Car.free_camera = false
	await _get_out()


func _bank(b: Basis) -> float:
	var up := Vector3.UP - b.z * b.z.dot(Vector3.UP)
	return rad_to_deg((up.normalized()).signed_angle_to(b.y, b.z))


func _plane_checks() -> void:
	var level := Basis(Vector3.UP, 0.4)
	var banked := Basis(level.z, deg_to_rad(60.0)) * level
	var shown := _bank(Biplane.horizon_basis(banked))
	_check(shown > 20.0 and shown < 30.0 and Biplane.horizon_basis(banked).z.is_equal_approx(banked.z),
			"banked 60°, the chase camera shows %.0f° and keeps the plane's heading" % shown)
	var worst := 0.0
	var prev := Biplane.horizon_basis(Basis(level.z, -PI) * level)
	for d in range(-179, 181):                   # a roll
		var c := Biplane.horizon_basis(Basis(level.z, deg_to_rad(d)) * level)
		worst = maxf(worst, rad_to_deg(c.y.angle_to(prev.y)))
		prev = c
	var loop_worst := 0.0
	for bank: float in [0.0, 30.0]:              # loops, wings level and banked
		var start := Basis(level.z, deg_to_rad(bank)) * level
		prev = Biplane.horizon_basis(start)
		for d in range(1, 361):
			var c := Biplane.horizon_basis(Basis(start.x, -deg_to_rad(d)) * start)
			loop_worst = maxf(loop_worst, rad_to_deg(c.y.angle_to(prev.y)))
			prev = c
	var top := Basis(level.x, -PI) * level       # over the top of a loop: upside down, nose back
	_check(worst < 3.0 and loop_worst < 3.0 and Biplane.horizon_basis(top).y.dot(top.y) > 0.999,
			"no jump through a roll (%.1f°/° at most) or a loop (%.1f°/°); over the top it follows the plane" % [worst,
			loop_worst])

	Car.free_camera = false
	var plane: VehicleBody3D = _main.spawn_car_near_player("biplane")
	if plane == null or not await _get_in(plane):
		_check(false, "gets in the biplane")
		return
	await _frames(10)
	Input.action_press("look_back")
	await process_frame
	await process_frame
	var back := _deg(_dir(plane.camera), plane.global_basis.z)
	Input.action_release("look_back")
	await process_frame
	_check(back > 170.0, "the plane: look back held turns the view round (%.0f°)" % back)
	_right_button(true)
	_right_button(false)
	await process_frame
	_check(Car.free_camera, "the plane: a right click switches the camera too")
	Car.free_camera = false
	await _get_out()


func _finish() -> void:
	if _failures.is_empty():
		print("ALL CAMERA CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
