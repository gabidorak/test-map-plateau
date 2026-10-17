extends SceneTree
## Headless checks for the Volvo FH16 with its semi-trailer (Car.SPECS "volvo-fh16-trailer", converted by
## blender/vehicles/import_truck.py; the tractor alone is in tools/test_real_cars.gd): the vehicle menu parks it as two
## sections, the semi-trailer (car_trailer.gd, from the cab file's "trailer") on its six twin wheels behind the tractor's
## four, ~17.6 m in all, resting level; the trailer is towed (its wheels never drive) and not walkable; E gets in, V
## gives the cab view; W pulls the trailer along, held at the fifth wheel; A turns, the trailer following at an angle;
## S lights the trailer's brake lamps too and backs it up, the joint straightening, with its reversing lamps lit; L
## lights its tail lamps; Space gets out.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_truck_trailer.gd
## Without --headless (add --disable-vsync) it also saves shots to /tmp/truck_trailer_*.png.

const Car = preload("res://scripts/car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const MODEL := "volvo-fh16-trailer"

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


func _look(car: VehicleBody3D, eye: Vector3, at: Vector3, file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	cam.global_position = car.to_global(eye)
	cam.look_at(car.to_global(at))
	cam.make_current()
	await _shot(file)
	cam.queue_free()


## How far apart the two sections' hitch points are (m): the joint holds them together.
func _hitch_gap(car: Car) -> float:
	var front := car.to_global(car.hitch())
	var rear := car.trailer.to_global(car.hitch() - car.rear_offset)
	return front.distance_to(rear)


func _lit(lamp: MeshInstance3D, car: Car, kind: String) -> bool:
	return lamp.material_override == car._lamp_mats[kind][1] if kind != "reverse" \
			else lamp.material_override == car._lamp_mats["reverse"]


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	_check(Car.MODELS.has(MODEL) and _main._menu_buttons.has_node(MODEL), "the vehicle menu has the %s" % Car.display_name(MODEL))
	var car: Car = _main.spawn_car_near_player(MODEL)
	_check(car != null and car.trailer != null, "it parks as a tractor and a semi-trailer")
	if car == null or car.trailer == null:
		_finish()
		return
	var front_wheels := car.get_children().filter(func(n: Node) -> bool: return n is VehicleWheel3D)
	var rear_wheels := car.trailer.get_children().filter(func(n: Node) -> bool: return n is VehicleWheel3D)
	_check(front_wheels.size() == 4 and rear_wheels.size() == 6, "4 wheels on the tractor, 6 on the trailer")
	var length := car.half_extents.z * 2.0
	_check(length > 17.0 and length < 18.2 and car.half_extents.x * 2.0 < 2.7 and car.trailer.mass == 7000.0,
			"%.1f m long, %.2f m wide, trailer %d kg" % [length, car.half_extents.x * 2.0, car.trailer.mass])
	_check(car._towed and car.trailer.interior.size == Vector3.ZERO and car._bellows.is_empty(),
			"the trailer is towed, not walkable, no bellows")
	_face_open_ground(car)
	await _frames(120)
	var level := car.global_basis.y.angle_to(Vector3.UP) < 0.1 and car.trailer.global_basis.y.angle_to(Vector3.UP) < 0.1
	_check(level and car.linear_velocity.length() < 0.3 and absf(car.articulation()) < 0.05 and _hitch_gap(car) < 0.1,
			"it rests level and straight, held at the fifth wheel (gap %.2f m, %.1f°)" % [_hitch_gap(car),
			rad_to_deg(car.articulation())])
	var trailer_lamps := ["trailer_indicator_left", "trailer_brake_lights", "trailer_reverse_lights"]
	var found := 0
	for lamp: MeshInstance3D in car._lamps[1] + car._brake_lamps + car._reverse_lamps:
		if lamp and lamp.name in trailer_lamps and car.trailer.is_ancestor_of(lamp):
			found += 1
	_check(found == 3, "the trailer's own indicator, brake and reversing lamps are switched (%d of 3)" % found)
	var trailer_lit := car._lit_surfaces.filter(func(e: Array) -> bool: return car.trailer.is_ancestor_of(e[0]))
	_check(not trailer_lit.is_empty(), "the trailer's tail lamps light up at night (%d surfaces)" % trailer_lit.size())
	await _look(car, Vector3(7.0, 3.5, 12.0), Vector3(0.0, 1.5, -3.0), "truck_trailer_front.png")
	await _look(car, Vector3(-7.0, 4.0, -24.0), Vector3(0.0, 1.5, -8.0), "truck_trailer_rear.png")

	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 1.5)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(3)
	await process_frame
	_check(_main.driving == car, "E from the cab's left side takes the wheel")
	if _main.driving != car:
		_finish()
		return
	if not car.cab_view:
		_tap(KEY_V)
	await process_frame
	_check(car.cab_view and root.get_camera_3d() == car._cab_camera, "V: the cab view")
	await _shot("truck_trailer_cab.png")
	_tap(KEY_V)
	var start := car.global_position
	_key(KEY_W, true)
	await _frames(150)
	var v := car.speed()
	var trailer_v := car.trailer.linear_velocity.dot(car.trailer.global_basis.z)
	_check(v > 6.0 and absf(trailer_v - v) < 1.0 and _hitch_gap(car) < 0.15 and car.trailer.engine_force == 0.0,
			"W pulls the trailer (%.1f m/s, trailer %.1f m/s, gap %.2f m, its engine force %.0f)" % [v, trailer_v,
			_hitch_gap(car), car.trailer.engine_force])
	_key(KEY_A, true)
	await _frames(70)
	var bent := car.articulation()
	await _shot("truck_trailer_turn.png")
	_key(KEY_A, false)
	_key(KEY_W, false)
	# turning left, the trailer still points to the right of the tractor's heading (articulation < 0)
	_check(bent < -0.08 and _hitch_gap(car) < 0.15, "A turns left, the trailer following at an angle (%.0f°)" % rad_to_deg(bent))
	_key(KEY_S, true)
	await _frames(10)
	var brake_lit := car._brake_lamps.all(func(l: MeshInstance3D) -> bool: return _lit(l, car, "brake"))
	_check(brake_lit and car._brake_lamps.size() == 2, "S lights the brake lamps, the trailer's too")
	for i in 400:
		await physics_frame
		if absf(car.speed()) < 0.3:
			break
	var art0 := absf(car.articulation())
	await _frames(150)
	var reversing := car.speed() < -0.5
	var rev_lit := car._reverse_lamps.all(func(l: MeshInstance3D) -> bool: return _lit(l, car, "reverse"))
	_key(KEY_S, false)
	_check(reversing and rev_lit and absf(car.articulation()) < maxf(art0, 0.1) and _hitch_gap(car) < 0.15,
			"S held backs it up, the reversing lamps lit, the joint straightening (%.0f° to %.0f°)" % [rad_to_deg(art0),
			rad_to_deg(car.articulation())])
	for i in 200:
		await physics_frame
		if absf(car.speed()) < 0.3:
			break
	_tap(KEY_L)
	await _frames(2)
	_check(car.headlights and trailer_lit.all(func(e: Array) -> bool:
			return (e[0] as MeshInstance3D).get_surface_override_material(e[1]) == e[2]), "L lights the trailer's tail lamps")
	_tap(KEY_L)
	await _frames(2)
	_main.exit_car()
	await _frames(5)
	_check(_main.driving == null and player.visible and car.global_position.distance_to(start) > 5.0, "Space gets out")
	_finish()


## (as tools/test_real_cars.gd) turns the parked vehicle to the heading with the most room ahead
func _face_open_ground(car: Car) -> void:
	var space := car.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(car.half_extents.x * 2.0 + 0.6, 1.0, car.half_extents.z * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.BREAKABLE \
			| Layers.VEHICLES
	q.exclude = [car.get_rid(), car.trailer.get_rid()]
	var best := [-1.0, 0.0]
	var centre := car.to_global(car.extents_center)
	for k in 24:
		var yaw := TAU * k / 24.0
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		q.transform = Transform3D(Basis(Vector3.UP, yaw), centre + Vector3.UP * 0.65)
		q.motion = dir * 40.0
		var room: float = space.cast_motion(q)[0] * 40.0
		if room > best[0]:
			best = [room, yaw]
	var b := Basis(Vector3.UP, best[1])
	car.place(Transform3D(b, centre - b * car.extents_center + Vector3.UP * 0.1))


func _finish() -> void:
	if _failures.is_empty():
		print("ALL TRUCK TRAILER CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
