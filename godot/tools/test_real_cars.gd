extends SceneTree
## Headless checks for the realistic cars (Car.SPECS "compact-hatchback" and "family-suv", built by
## blender/vehicles/build_car.py): the vehicle menu parks each with its four wheels at its real size and mass, it rests
## level; E gets in; V gives the cab view from the driver's eye, inside the cabin under the roof, the driver's body hidden
## and the hands on the steering wheel, which turns with the steering; W drives it and A turns it; the indicators, brake
## lamps and headlights are the model's own (its lamp meshes, its "headlight" and "taillight" surfaces lit, a beam); the
## paint has a clear coat; E from the right side sits the player in the passenger seat (the cab view from the
## passenger's eye, a look-alike that fits under the roof in the chase view), Space gets out on the right.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_real_cars.gd
## Without --headless (add --disable-vsync) it also saves shots to /tmp/real_car_<model>_*.png.

const Car = preload("res://scripts/car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const MODELS := {"compact-hatchback": [3.9, 4.2, 1180.0], "family-suv": [4.3, 4.6, 1500.0]}    # length range, mass

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


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


## Looks at the car from `eye` (car frame) towards `at` with a free camera, for a shot.
func _look(car: VehicleBody3D, eye: Vector3, at: Vector3, file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.global_position = car.to_global(eye)
	cam.look_at(car.to_global(at))
	cam.make_current()
	await _shot(file)
	cam.queue_free()


func _run() -> void:
	await _frames(60)
	for model: String in MODELS:
		await _car(model)
	_finish()


func _car(model: String) -> void:
	var player: CharacterBody3D = _main.player
	var tag := model.replace("-", "_")
	print("-- ", model)
	_check(Car.MODELS.has(model) and _main._menu_buttons.has_node(model), "the vehicle menu has the %s" % Car.display_name(model))
	var car: VehicleBody3D = _main.spawn_car_near_player(model)
	_check(car != null and car.find_children("*", "VehicleWheel3D", true, false).size() == 4, "it parks with four wheels")
	if car == null:
		return
	var spec: Array = MODELS[model]
	var length: float = car.half_extents.z * 2.0
	_check(length > spec[0] and length < spec[1] and car.half_extents.x * 2.0 < 1.9 and car.mass == spec[2],
			"%.2f m long, %.2f m wide, %d kg" % [length, car.half_extents.x * 2.0, car.mass])
	_face_open_ground(car)
	await _frames(90)
	_check(absf(car.global_basis.y.angle_to(Vector3.UP)) < 0.1 and car.linear_velocity.length() < 0.3,
			"it rests level on its wheels")
	await _look(car, Vector3(3.2, 1.5, 4.6), Vector3(0.0, 0.6, 0.3), "real_car_%s_front.png" % tag)
	await _look(car, Vector3(-3.0, 1.7, -4.8), Vector3(0.0, 0.7, -0.3), "real_car_%s_rear.png" % tag)
	_check(car._lit_surfaces.size() >= 2 and car._beam != null and car._head_lamps.is_empty(),
			"its own headlight and tail lamp surfaces light up, with a beam (%d surfaces)" % car._lit_surfaces.size())
	_check(car._lamps[1].size() == 1 and car._lamps[1][0].name == "indicator_left" and car._brake_lamps.size() == 1
			and car._brake_lamps[0].name == "brake_lights", "its indicators and brake lamps are the model's")
	var glossed := false
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		for k in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(k) as StandardMaterial3D
			glossed = glossed or (mat != null and mat.resource_name.begins_with("paint") and mat.clearcoat_enabled)
	_check(glossed, "the paint has a clear coat")

	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.driving == car, "E from the left side takes the wheel")
	if _main.driving != car:
		return
	_check(car.has_cab() and car.has_passenger_seat and car._steering_wheel != null,
			"it has a cab with a steering wheel and a passenger seat")
	if not car.cab_view:
		_tap(KEY_V)
	await process_frame
	var cam := root.get_camera_3d()
	var eye: Vector3 = car.to_local(cam.global_position)
	var body := car.find_child("body", true, false) as MeshInstance3D
	var roof: float = (car._in_car(body) * body.get_aabb()).end.y
	_check(car.cab_view and cam == car._cab_camera and eye.x > 0.25 and absf(eye.z) < 0.6 and eye.y > 1.0
			and eye.y < roof - 0.15, "V: the cab view from the driver's eye, under the roof (%s, roof %.2f)" % [eye, roof])
	var pitch: float = cam.global_rotation.x
	_check(pitch < -0.05 and pitch > -0.3, "looking ahead and a little down (%.0f°)" % rad_to_deg(pitch))
	_check(not car._driver_body.visible and car._hands[0].visible, "the driver's body is hidden there, the hands on the wheel show")
	await _shot("real_car_%s_cab.png" % tag)

	var yaw0: float = car.global_rotation.y
	_key(KEY_W, true)
	await _frames(120)
	var v: float = car.speed()
	_key(KEY_A, true)
	await _frames(45)
	var rest: Transform3D = car._steering_rest
	var turned: float = (rest.basis.inverse() * car._steering_wheel.transform.basis).get_euler().y
	var hand_on := absf(car._hands[0].position.distance_to(car._wheel_centre) - car._grip_radius) < 0.03
	await _shot("real_car_%s_cab_turn.png" % tag)
	_key(KEY_A, false)
	_key(KEY_W, false)
	_check(turned > 0.2 and absf(turned - car.steering * Car.STEERING_RATIO) < 0.01 and hand_on,
			"A turns the steering wheel left (%.0f°), a hand on its rim" % rad_to_deg(turned))
	_check(v > 8.0, "W drives it (%.1f m/s after 2 s)" % v)
	_check(absf(angle_difference(yaw0, car.global_rotation.y)) > 0.1,
			"A turns it (%.0f°)" % rad_to_deg(angle_difference(yaw0, car.global_rotation.y)))
	_key(KEY_S, true)
	await _frames(10)
	_check(car._brake_lamps[0].material_override == car._lamp_mats["brake"][1], "S lights the brake lamps")
	for i in 300:
		await physics_frame
		if absf(car.speed()) < 0.3:
			break
	_key(KEY_S, false)
	_tap(KEY_L)
	await _frames(2)
	_check(car.headlights and car._beam.visible and car._lit_surfaces.all(func(e: Array) -> bool:
			return (e[0] as MeshInstance3D).get_surface_override_material(e[1]) == e[2]), "L switches the headlights on")
	_tap(KEY_L)
	await _frames(2)
	_main.exit_car()
	await _frames(5)
	_check(_main.driving == null and player.visible, "Space gets out")
	await _passenger_seat(car, tag, roof)
	_main.cars.erase(car)
	car.queue_free()
	await _frames(5)


## E from the right side: the passenger seat, its cab view, the look-alike in the chase view; Space gets out on the right.
func _passenger_seat(car: VehicleBody3D, tag: String, roof: float) -> void:
	var player: CharacterBody3D = _main.player
	await _frames(20)
	player.teleport(car.to_global(Vector3(-car.half_extents.x - 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.riding == car and _main.driving == null and car.riding, "E from the right side sits the player in the passenger seat")
	if _main.riding != car:
		return
	if not car.cab_view:
		_tap(KEY_V)
	await process_frame
	var eye: Vector3 = car.to_local(root.get_camera_3d().global_position)
	_check(root.get_camera_3d() == car._cab_camera and eye.x < -0.25, "V: the cab view from the passenger's eye")
	await _shot("real_car_%s_passenger.png" % tag)
	_tap(KEY_V)
	await process_frame
	var p: MeshInstance3D = car._passenger
	var top: float = p.position.y + (p.mesh as CapsuleMesh).height * 0.5
	_check(root.get_camera_3d() == car.camera and p.visible and top < roof - 0.03,
			"V again: the chase camera, the passenger seated under the roof (head %.2f, roof %.2f)" % [top, roof])
	await _look(car, Vector3(-2.6, 1.5, 3.0), Vector3(-0.3, 0.9, 0.0), "real_car_%s_passenger_front.png" % tag)
	_tap(KEY_SPACE)
	await _frames(3)
	var out: Vector3 = car.to_local(player.global_position)
	_check(_main.riding == null and not car.riding and player.visible and out.x < -car.half_extents.x,
			"Space gets out on the right (%.1f m off the side)" % (-out.x - car.half_extents.x))


## Turns the parked car towards the direction with the most room ahead (rays at bumper height), so it can drive off.
func _face_open_ground(car: VehicleBody3D) -> void:
	var space := car.get_world_3d().direct_space_state
	var from := car.global_position + Vector3.UP * 0.6
	var best := [-1.0, 0.0]
	for k in 24:
		var yaw := TAU * k / 24.0
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0, Layers.SOLID | Layers.PROPS | Layers.VEGETATION
				| Layers.VEHICLES)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		var room: float = 40.0 if hit.is_empty() else from.distance_to(hit["position"])
		if room > best[0]:
			best = [room, yaw]
	car.place(Transform3D(Basis(Vector3.UP, best[1]), car.global_position + Vector3.UP * 0.1))


func _finish() -> void:
	if _failures.is_empty():
		print("ALL REAL CAR CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
