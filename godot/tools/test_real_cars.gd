extends SceneTree
## Headless checks for the realistic cars (Car.SPECS "compact-hatchback", "family-suv" and the police car
## "police-hatchback", built by blender/vehicles/build_car.py; its siren and lights: tools/test_police_car.gd; and
## "renault-zoe", converted by blender/vehicles/import_car.py): the vehicle menu parks each with its four wheels at its real size and mass, it rests
## level; E gets in; V gives the cab view from the driver's eye, inside the cabin under the roof, the driver's body hidden
## and the hands on the steering wheel, which turns with the steering; W drives it and A turns it; the indicators, brake
## lamps and headlights are the model's own (its lamp meshes, its "headlight" and "taillight" surfaces lit, a beam); the
## paint has a clear coat; E from the right side sits the player in the passenger seat (the cab view from the
## passenger's eye, a look-alike that fits under the roof in the chase view; back at its parking spot first if the drive
## ended on a bank), Space gets out on the right. "mercedes-1928" comes from blender/vehicles/import_textured.py. The Zoe is
## electric: silent at rest, its pedestrian warning hum moving off, its motor's whine pitched up with the speed, "gear D".
## A car with reversing lamps ("bmw-m4") backs up on S held with them lit, off on release. The Volvo FH16 tractor
## ("volvo-fh16", blender/vehicles/import_truck.py) is checked the same way; with its semi-trailer: tools/test_truck_trailer.gd.
## So is the GAZ Tiger's driver ("gaz-tiger", a roof gun: matt paint, and its passenger seat is the gunner's, checked by
## tools/test_tiger.gd).
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_real_cars.gd [-- <model> ...]
## Without --headless (add --disable-vsync) it also saves shots to /tmp/real_car_<model>_*.png.

const Car = preload("res://scripts/car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const MODELS := {"compact-hatchback": [3.9, 4.2, 1180.0], "family-suv": [4.3, 4.6, 1500.0],    # length range, mass
		"police-hatchback": [3.9, 4.2, 1180.0], "renault-zoe": [4.0, 4.2, 1470.0], "audi-r8": [4.3, 4.5, 1600.0],
		"mercedes-1928": [4.7, 4.9, 1600.0, 0.8],   # (and how far the driver's eye may be from the middle: 0.6 m)
		"bmw-m4": [4.55, 4.75, 1570.0],
		"audi-rs6": [4.95, 5.2, 2075.0, 0.6, 2.1],  # (and how wide it may be: 2 m; this one has a wide-body kit)
		"volvo-fh16": [6.0, 6.4, 8500.0, 2.0, 2.6],     # truck: the cab is over the front axle, 2.5 m wide
		"gaz-tiger": [5.6, 6.0, 7200.0, 0.6, 2.6]}      # armoured car, 2.5 m wide (its gunner: tools/test_tiger.gd)

var _main: Node
var _failures: PackedStringArray = []
var _start: Vector3                         # the player's spawn: each car is parked from there


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


## The engine speed heard (times idle): the highest of its playing layers, as pitched.
func _whine(car: Car) -> float:
	var top := 0.0
	for p: AudioStreamPlayer3D in car.audio._engines:
		if p.playing:
			top = maxf(top, p.pitch_scale * VehicleAudio.layer_ratio(car.audio.kind, car.audio._layers.find(p.stream)))
	return top


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
	_start = _main.player.global_position
	var only := OS.get_cmdline_user_args()          # "-- renault-zoe": just those
	for model: String in MODELS:
		if only.is_empty() or model in only:
			await _car(model)
	_finish()


func _car(model: String) -> void:
	var player: CharacterBody3D = _main.player
	var tag := model.replace("-", "_")
	print("-- ", model)
	player.teleport(_start)                 # not where the last car's checks left the player (a bank, maybe)
	await _frames(10)
	_check(Car.MODELS.has(model) and _main._menu_buttons.has_node(model), "the vehicle menu has the %s" % Car.display_name(model))
	var car: VehicleBody3D = _main.spawn_car_near_player(model)
	_check(car != null and car.find_children("*", "VehicleWheel3D", true, false).size() == 4, "it parks with four wheels")
	if car == null:
		return
	var spec: Array = MODELS[model]
	var length: float = car.half_extents.z * 2.0
	_check(length > spec[0] and length < spec[1] and car.half_extents.x * 2.0 < (spec[4] if spec.size() > 4 else 2.0)
			and car.mass == spec[2],
			"%.2f m long, %.2f m wide, %d kg" % [length, car.half_extents.x * 2.0, car.mass])
	_face_open_ground(car)
	await _frames(90)
	_check(absf(car.global_basis.y.angle_to(Vector3.UP)) < 0.1 and car.linear_velocity.length() < 0.3,
			"it rests level on its wheels (%.1f°, %.2f m/s)" % [rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)),
			car.linear_velocity.length()])
	var parked: Transform3D = car.global_transform
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
	if not Car.SPECS[model].get("roof_gun", false):     # (the armoured car's paint is matt)
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
	_check(car.cab_view and cam == car._cab_camera and eye.x > 0.25 and absf(eye.z) < (spec[3] if spec.size() > 3 else 0.6)
			and eye.y > 1.0 and eye.y < roof - 0.15, "V: the cab view from the driver's eye, under the roof (%s, roof %.2f)" % [eye, roof])
	var pitch: float = cam.global_rotation.x
	_check(pitch < -0.05 and pitch > -0.3, "looking ahead and a little down (%.0f°)" % rad_to_deg(pitch))
	_check(not car._driver_body.visible and car._hands[0].visible, "the driver's body is hidden there, the hands on the wheel show")
	await _shot("real_car_%s_cab.png" % tag)

	var yaw0: float = car.global_rotation.y
	var electric: bool = car.audio.kind == "electric"
	_check(electric == (model == "renault-zoe"), "its sound is %s" % ("electric" if electric else "an engine's"))
	var until := Time.get_ticks_msec() + 5000
	while electric and car.audio._layers.is_empty() and Time.get_ticks_msec() < until:   # synthesized on a worker thread, slower
		await _frames(1)                                                    # than headless frames
	var hushed: bool = electric and not car.audio._avas.playing
	_key(KEY_W, true)
	await _frames(20)
	var hum: bool = electric and car.audio._avas.playing
	var pitch_low := _whine(car)
	await _frames(100)
	var v: float = car.speed()
	if electric:
		var top := _whine(car)
		_check(hushed and hum and not car.audio._avas.playing,
				"electric: silent at rest, the warning hum moving off, gone at %.0f km/h" % (v * 3.6))
		_check(top > pitch_low * 3.0, "the motor's whine climbs with the speed (x%.1f to x%.1f idle)" % [pitch_low, top])
		_check("gear D" in _main._dash.text, "the HUD shows gear D")
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
	if not car._reverse_lamps.is_empty():           # a model with reversing lamps: S held backs it up, lit
		await _frames(40)
		var lit: bool = car.speed() < -0.3 and car._reverse_lamps.all(func(l: MeshInstance3D) -> bool:
				return l.material_override == car._lamp_mats["reverse"])
		_key(KEY_S, false)
		await _frames(3)
		_check(lit and car._reverse_lamps[0].material_override == null,
				"S held backs it up with the reversing lamps lit, off on release")
		for i in 120:
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
	if car.global_basis.y.angle_to(Vector3.UP) > 0.15:     # stopped on a bank: back where it was parked, level
		car.place(parked)
		await _frames(60)
	if not Car.SPECS[model].get("roof_gun", false):     # (its passenger is the gunner: tools/test_tiger.gd)
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


## Turns the parked car towards the direction with the most room ahead (a box cast of its footprint, a little wider,
## from just above the ground: a thin pole between rays would be knocked over under the car, which flies off it) on
## ground with no kerb, drop or bank on the way (a car flying off one cannot steer, as in tools/test_cars.gd), so it
## can drive off; preferably level under its wheels where it stands.
func _face_open_ground(car: VehicleBody3D) -> void:
	var space := car.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(car.half_extents.x * 2.0 + 0.6, 1.0, car.half_extents.z * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.BREAKABLE \
			| Layers.VEHICLES
	q.exclude = [car.get_rid()]
	var best := [-1.0, 0.0]
	for k in 24:
		var yaw := TAU * k / 24.0
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		q.transform = Transform3D(Basis(Vector3.UP, yaw), car.global_position + Vector3.UP * 0.65)
		q.motion = dir * 40.0
		var room: float = space.cast_motion(q)[0] * 40.0
		var start := car.global_position
		var prev := WorldQuery.ground_y(car.get_world_3d(), start.x, start.z, Layers.TERRAIN, start.y + 3.0)
		for m in range(1, int(room)):
			var w := start + dir * float(m)
			var g := WorldQuery.ground_y(car.get_world_3d(), w.x, w.z, Layers.TERRAIN, start.y + 30.0)
			if is_nan(g) or absf(g - prev) > 0.1:   # a kerb is 0.12 m
				room = float(m)
				break
			prev = g
		# where it stands, turned: level under its four wheels (not across a kerb or a bank)
		var corners: Array[float] = []
		for c: Vector3 in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			var w: Vector3 = start + Basis(Vector3.UP, yaw) * (c * (car.half_extents - Vector3(0.2, 0.0, 0.7)))
			corners.append(WorldQuery.ground_y(car.get_world_3d(), w.x, w.z, Layers.TERRAIN, start.y + 3.0))
		if corners.max() - corners.min() > 0.1:
			room *= 0.1
		if room > best[0]:
			best = [room, yaw]
	car.place(Transform3D(Basis(Vector3.UP, best[1]), car.global_position + Vector3.UP * 0.1))


func _finish() -> void:
	if _failures.is_empty():
		print("ALL REAL CAR CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
