extends SceneTree
## Headless checks for the two-seat biplane with a gunner (scripts/plane.gd "biplane-gunner"): the vehicle menu parks it
## with a belly turret and no wing guns; E from its right side sits the player in the gunner's seat (help, dash); the
## turret never points more than TURRET_CONE off the nose nor above TURRET_UP (clamp_aim, the mouse in the turret view);
## held in the air, the turret view (V) on a car below and ahead turns the barrel onto it and the left mouse button hits
## it; a car behind is out of reach (the dash says so) and is not hit; V again: the chase camera and the gunner's
## look-alike; E takes the controls. LAN: the gunner's player state carries the turret, and a remote copy of the plane
## fires from it without its hits counting.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_turret.gd
## Without --headless it also saves shots to /tmp/turret_*.png.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Car = preload("res://scripts/car.gd")
const Biplane = preload("res://scripts/plane.gd")

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


func _trigger(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


func _deg(d: Vector3) -> float:
	return rad_to_deg(d.angle_to(Vector3.BACK))


## Puts `car`'s body box centre at `p` (global), frozen.
func _put(car: VehicleBody3D, p: Vector3, b: Basis) -> void:
	var box: Vector3 = (car.find_children("*", "CollisionShape3D", false, false)[0] as Node3D).position
	car.global_transform = Transform3D(b, p - b * box)
	car.freeze = true


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	_check(Car.MODELS.has("biplane-gunner") and _main._menu_buttons.has_node("biplane-gunner"),
			"the vehicle menu has the biplane with gunner")
	var plane: VehicleBody3D = _main.spawn_car_near_player("biplane-gunner")
	_check(plane != null and plane.turret and plane.turret_guns != null and plane.guns == null and plane.has_passenger_seat,
			"it has a belly turret, a gunner's seat and no wing guns")
	var target: VehicleBody3D = _main.spawn_car_near_player("sedan")
	if plane == null or target == null:
		return _finish()

	# the reach
	var cone := rad_to_deg(Biplane.TURRET_CONE)
	_check(Biplane.clamp_aim(Vector3.BACK).is_equal_approx(Vector3.BACK)
			and Biplane.clamp_aim(Vector3(0.4, -0.3, 1.0).normalized()).is_equal_approx(Vector3(0.4, -0.3, 1.0).normalized()),
			"straight ahead and 30° off the nose are within reach")
	var worst := 0.0
	var highest := -1.0
	for d: Vector3 in [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3(1, 1, -1).normalized(),
			Vector3(-1, -2, 0.3).normalized(), Vector3(0.0, 0.7, 0.7).normalized()]:
		var c := Biplane.clamp_aim(d)
		worst = maxf(worst, _deg(c))
		highest = maxf(highest, c.y)
		if not is_equal_approx(c.length(), 1.0):
			worst = 999.0
	_check(worst <= cone + 0.01 and highest <= sin(Biplane.TURRET_UP) + 1e-4,
			"anything else is brought within %.0f° of the nose (%.2f° at most) and %.0f° above it" % [cone, worst,
			rad_to_deg(Biplane.TURRET_UP)])

	# E from the right side: the gunner's seat
	player.teleport(plane.to_global(Vector3(-plane.half_extents.x - 1.0, 0.3, 0.0)))
	await _frames(5)
	_key(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.riding == plane and _main.driving == null and plane.riding and plane.turret_guns.live
			and "GUNNER" in _main._help.text and _main._dash.visible, "E from the right side: the gunner's seat (help, dash)")

	# held still high up, a car below and ahead within reach
	var p0: Vector3 = plane.global_position
	var g := WorldQuery.ground_y(plane.get_world_3d(), p0.x, p0.z, Layers.SOLID)
	plane.place(Transform3D(Basis(Vector3.UP, plane.global_rotation.y), Vector3(p0.x, g + 130.0, p0.z)))
	plane.freeze = true
	await _frames(2)
	var want := Vector3(0.35, -0.5, 1.0).normalized()
	_put(target, plane.to_global(Biplane.TURRET + want * 110.0), plane.global_basis.orthonormalized())
	_key(KEY_V)
	await process_frame
	_check(root.get_camera_3d() == plane._turret_camera and plane.cab_view, "V: the turret view")
	plane.look_turret(Vector2(-5.0, 0.0))
	var edge: Vector2 = plane.gun_look
	var d_edge := Vector3(sin(edge.x) * cos(edge.y), sin(edge.y), cos(edge.x) * cos(edge.y))
	plane.look_turret(Vector2(0.0, -3.0))
	_check(absf(_deg(d_edge) - cone) < 0.1 and plane.gun_look.y <= Biplane.TURRET_UP + 1e-4,
			"the mouse turns the turret view %.1f° left at most, %.1f° up at most" % [_deg(d_edge), rad_to_deg(plane.gun_look.y)])
	plane.gun_look = Vector2(atan2(want.x, want.z), asin(want.y))
	await _frames(30)
	await process_frame
	_check(plane.turret_dir.angle_to(want) < 0.02 and not plane._out_of_arc,
			"looking at the car, the barrel turns onto it (%.1f° off)" % rad_to_deg(plane.turret_dir.angle_to(want)))
	await process_frame
	_check(_main._gunsight.visible, "the ring shows where the turret is aimed")
	await _shot("turret_view.png")
	var hits := [0]
	plane.turret_guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: hits[0] += 1)
	var health: float = target.health
	_trigger(true)
	await _frames(30)
	await _shot("turret_firing.png")
	await _frames(30)
	_trigger(false)
	var fired: int = plane.turret_guns.rounds_fired
	_check(fired >= 20 and hits[0] > 0 and target.health < health,
			"left click fires (%d rounds in 1 s) and hits the car (%d hits, health %.0f -> %.0f)" % [fired, hits[0], health,
			target.health])
	await _frames(20)
	_check(plane.turret_guns.rounds_fired == fired, "releasing the button stops the turret")

	# V: chase camera; a car behind is out of reach
	_key(KEY_V)
	await process_frame
	_check(root.get_camera_3d() == plane.camera and plane._passenger.visible, "V again: the chase camera, the gunner seated")
	_put(target, plane.to_global(Vector3(0.0, -40.0, -60.0)), plane.global_basis.orthonormalized())
	plane._look_yaw = PI
	plane._look_pitch = -0.5
	await _frames(40)
	await process_frame
	_check(plane._out_of_arc and "REACH" in _main._dash.text and absf(_deg(plane.turret_dir) - cone) < 0.5,
			"looking back: out of reach, the turret stays %.1f° off the nose" % _deg(plane.turret_dir))
	await _shot("turret_chase_back.png")
	health = target.health
	_trigger(true)
	await _frames(40)
	_trigger(false)
	_check(target.health == health, "the car behind is not hit")
	plane._look_yaw = 0.0
	plane._look_pitch = -0.22
	await _frames(20)
	await _shot("turret_chase.png")

	if DisplayServer.get_name() != "headless":     # the turret from the side, below the wing
		var side := Camera3D.new()
		root.add_child(side)
		side.look_at_from_position(plane.to_global(Vector3(-2.2, -1.3, 2.6)), plane.to_global(Biplane.TURRET))
		side.make_current()
		await _shot("turret_side.png")
		side.queue_free()
		plane.camera.make_current()

	# LAN: the gunner's state, fired from by a remote copy
	var s: Array = _main.net_player_state()
	_check(s.size() == 7 and s[4] & 2 != 0 and s[5] is Vector3 and (s[5] as Vector3).normalized().is_equal_approx(plane.turret_dir),
			"the gunner's player state carries the turret")
	var copy: VehicleBody3D = _main.add_net_car("biplane-gunner", plane.global_transform.translated(Vector3.UP * 40.0))
	copy.set_remote(true)
	var copy_hits := [0]
	copy.turret_guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: copy_hits[0] += 1)
	copy.show_passenger(true, Color.RED)
	var aim := Vector3(-0.3, -0.6, 1.0).normalized()
	copy.set_gunner_state(aim * 150.0, true)
	await _frames(40)
	_check(copy._passenger.visible and copy.turret_dir.is_equal_approx(aim) and copy.turret_guns.rounds_fired > 10
			and not copy.turret_guns.live and copy_hits[0] == 0,
			"a remote copy shows the gunner and fires (%d rounds) where they aim, its hits not counting here" % \
			copy.turret_guns.rounds_fired)
	copy.show_passenger(false)
	var n: int = copy.turret_guns.rounds_fired
	await _frames(20)
	_check(copy.turret_guns.rounds_fired == n, "the gunner gone, it stops")
	_main.cars.erase(copy)
	copy.queue_free()

	# E: the controls
	plane.freeze = false
	_key(KEY_E)
	await _frames(2)
	_check(_main.driving == plane and _main.riding == null and not plane.riding and not plane.turret_guns.live
			and "gunner boards" in _main._help.text, "E in the gunner's seat takes the controls")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ALL TURRET CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
