extends SceneTree
## Headless checks for the debug cars (scripts/car.gd): four cars are parked next to the player at
## start and settle on their wheels; E gets into the nearest one; W drives it forward, A turns it;
## S stops it; Space gets out next to it, standing on the ground, without jumping. C parks another car; Tab opens
## the vehicle menu, whose buttons park the chosen model.
## Mouse wheel: zoomed all the way in the player goes first person and back out of it.
## Bus: a passenger is not shoved by a pole a remote (LAN) copy of the bus drives through, and holds still against
## its front wall as it moves; E near the driver seat from inside takes the wheel, in the cab view when the player was in first person;
## the steering wheel turns with the steering, the driver's hands on its rim; the wheel zooms out of the cab view
## and back into it, and first person carries over when leaving the seat; Q/E turn signals (self-cancel after a turn);
## full steering lock at a standstill; O opens the doors (door colliders off); Space while moving leaves
## the seat into the aisle and the player keeps standing and walking inside the rolling bus; once it has
## stopped, the player walks out of the front door onto the ground and back in over the step.
## Articulated bus: parked straight on its 6 wheels, it drives and turns with the rear section following (the joint
## bends within its limit, the hitch holds, both sections stay upright); O opens its 4 doors; the player walks from
## the front section through the bellows into the rear section, which then carries them.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_cars.gd
## Without --headless it also saves shots to data/review/shots/cars/.

const Layers = preload("res://scripts/physics_layers.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
## Straight stretch of Nouvelle Voie (pipeline x, y) and its direction, for the bus checks.
const BUS_ROAD := Vector2(165.0, -215.0)
const BUS_ROAD_DIR := Vector2(120.0, -59.0)

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
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


## Turns `car` in place towards the heading with the longest free run for a car-sized box.
func _face_open_road(car: VehicleBody3D) -> void:
	var box := BoxShape3D.new()
	# the car's own footprint: a longer box would start inside a car parked just ahead, and a cast
	# ignores what it starts in
	box.size = Vector3(car.half_extents.x * 2.0 + 0.2, 1.2, car.half_extents.z * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	q.exclude = [car.get_rid()]
	var space := car.get_world_3d().direct_space_state
	var best_a := 0.0
	var best_d := -1.0
	for i in 72:
		var a := TAU * i / 72.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		q.transform = Transform3D(Basis(Vector3.UP, a), car.to_global(car.extents_center) + Vector3.UP * 1.0)
		q.motion = dir * 40.0
		var d: float = space.cast_motion(q)[0] * 40.0
		if d > best_d:
			best_d = d
			best_a = a
	var b := Basis(Vector3.UP, best_a)
	car.place(Transform3D(b, car.to_global(car.extents_center) - b * car.extents_center + Vector3.UP * 0.2))
	print("test car turned to the most open heading (%.0f m free)" % best_d)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../data/review/shots/cars")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(file))
	print("saved ", file)


func _run() -> void:
	await _frames(150)                      # spawn + let the cars settle
	var player: CharacterBody3D = _main.player
	var cars: Array = _main.cars
	_check(cars.size() == 4, "4 cars parked next to the player (got %d)" % cars.size())
	var map := GroundMap.get_map()
	for car: VehicleBody3D in cars:
		var d := _box_distance(car, player.global_position)
		print("%s on %s" % [car.model_name, map.describe(car.global_position.x, -car.global_position.z)])
		var wheels := _wheels_on_ground(car)
		_check(car.global_basis.y.y > 0.95 and wheels.x == wheels.y and car.linear_velocity.length() < 0.3 and d < 18.0,
				"%s parked upright on its %d wheels, %.1f m from the player (up %.2f, %d on the ground, %.2f m/s)" % [
				car.model_name, wheels.y, d, car.global_basis.y.y, wheels.x, car.linear_velocity.length()])
	await _shot("parked.png")

	var nearest = _main.nearest_car()
	if nearest == null:
		# none parked within reach: step up to the closest ordinary car (turning a bus could put the player inside)
		var closest: VehicleBody3D = null
		for car: VehicleBody3D in cars:
			if car.has_doors:
				continue
			if closest == null or _box_distance(car, player.global_position) < _box_distance(closest, player.global_position):
				closest = car
		var p: Vector3 = closest.to_local(player.global_position)
		var side := signf(p.x) if p.x != 0.0 else 1.0
		player.teleport(closest.to_global(Vector3(side * (closest.half_extents.x + 1.0), 0.3, 0.0)))
		await _frames(20)
		nearest = _main.nearest_car()
		print("stepped up to the %s" % (nearest.model_name if nearest else "none"))
	if nearest:
		_face_open_road(nearest)
		await _frames(60)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(2)
	_check(_main.driving != null and _main.driving == nearest and not player.visible, "E gets into the nearest car")
	if _main.driving == null:
		return _finish()
	var car: VehicleBody3D = _main.driving
	var start := car.global_position
	var yaw0 := car.global_rotation.y
	_key(KEY_W, true)
	await _frames(180)
	var v: float = car.speed()
	_check(v > 6.0, "W drives forward (%.1f m/s after 3 s, %.1f m)" % [v, car.global_position.distance_to(start)])
	await _shot("driving.png")
	_key(KEY_A, true)
	await _frames(60)
	_key(KEY_A, false)
	var turned := absf(angle_difference(yaw0, car.global_rotation.y))
	_check(turned > 0.3, "A turns the car (%.0f° in 1 s)" % rad_to_deg(turned))
	_key(KEY_W, false)
	_key(KEY_S, true)
	await _frames(150)
	_key(KEY_S, false)
	_check(car.global_basis.y.y > 0.9, "still on its wheels after driving (up %.2f)" % car.global_basis.y.y)
	await _frames(60)

	_key(KEY_SPACE, true)
	await _frames(2)
	_check(_main.driving == null and player.visible and player.active, "Space gets out")
	var side_d := player.global_position.distance_to(car.global_position)
	await _frames(40)
	var y_after := player.global_position.y
	await _frames(20)
	_check(player.is_on_floor() and absf(player.global_position.y - y_after) < 0.05 and side_d < 4.0,
			"standing beside the car without jumping (%.1f m from it, on floor %s)" % [side_d, player.is_on_floor()])
	_key(KEY_SPACE, false)
	await _frames(2)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _frames(2)
	_check(cars.size() == 5, "C parks one more car")
	_press(KEY_U)
	await _frames(2)
	var menu: Control = _main.hud.get_node("VehicleMenu")
	_check(menu.visible and not player.active and _main._menu_buttons.get_child_count() == _main.Car.MODELS.size(),
			"U opens the vehicle menu, a button per model, the player stands still")
	_main._menu_buttons.get_node("police").pressed.emit()
	await _frames(2)
	_check(cars.size() == 6 and cars[-1].model_name == "police" and not menu.visible and player.active,
			"the menu parks the chosen vehicle (police) and closes")
	await _bus_checks()
	await _artic_checks()
	_finish()


## Horizontal distance from `p` (global) to the body box of `car` (straight, for an articulated one).
func _box_distance(car: VehicleBody3D, p: Vector3) -> float:
	var l: Vector3 = car.to_local(p) - car.extents_center
	return Vector2(maxf(absf(l.x) - car.half_extents.x, 0.0), maxf(absf(l.z) - car.half_extents.z, 0.0)).length()


## Vector2i(wheels touching the ground, wheels) over all the sections of `car`.
func _wheels_on_ground(car: VehicleBody3D) -> Vector2i:
	var n := Vector2i.ZERO
	for b: VehicleBody3D in car.bodies():
		for w in b.get_children():
			if w is VehicleWheel3D:
				n.y += 1
				if w.is_in_contact():
					n.x += 1
	return n


## `n` mouse wheel notches, up (zoom in) or down.
func _wheel(up: bool, n: int) -> void:
	for i in n:
		for pressed: bool in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = pressed
			e.factor = 1.0
			Input.parse_input_event(e)
			Input.flush_buffered_events()
	await process_frame


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


## Scripted walk towards `dir_car` (in the bus frame) for `frames`.
func _walk(bus: VehicleBody3D, dir_car: Vector3, frames: int) -> void:
	var player = _main.player
	var d: Vector3 = bus.global_basis * dir_car
	player.teleport(player.global_position, atan2(-d.x, -d.z))
	player.scripted_input = Vector2(0.0, 1.0)
	await _frames(frames)
	player.scripted_input = Vector2.ZERO
	await _frames(10)
	player.scripted_input = null


func _bus_checks() -> void:
	var player = _main.player
	var bus: VehicleBody3D = null
	for car in _main.cars:
		if car.model_name == "bus-idfm":
			bus = car
	_check(bus != null and bus.has_doors, "the bus is walkable (layout loaded)")
	if bus == null:
		return
	var g := WorldQuery.ground_y(bus.get_world_3d(), BUS_ROAD.x, -BUS_ROAD.y, Layers.SOLID)
	bus.place(Transform3D(Basis(Vector3.UP, atan2(BUS_ROAD_DIR.x, -BUS_ROAD_DIR.y)),
			Vector3(BUS_ROAD.x, g + 0.3, -BUS_ROAD.y)))
	await _frames(90)
	player.teleport(bus.to_global(bus.driver_exit))
	await _frames(30)
	_check(player.carrier == bus and player.is_on_floor(), "standing inside the parked bus is carried by it (on floor %s)" % player.is_on_floor())
	# a copy of the bus posed from a LAN peer's states goes through what it hits there (a pole it knocked down, a
	# tree it bent) until that news arrives: driven 4 m past a pole standing in the aisle and back, the passenger
	# stays put
	var parked: Transform3D = bus.global_transform
	var rest_local: Vector3 = bus.to_local(player.global_position)
	var pole := StaticBody3D.new()
	pole.collision_layer = Layers.PROPS
	pole.collision_mask = 0
	var pole_shape := CollisionShape3D.new()
	pole_shape.shape = BoxShape3D.new()
	(pole_shape.shape as BoxShape3D).size = Vector3(0.3, 4.0, 0.3)
	pole.add_child(pole_shape)
	_main.add_child(pole)
	pole.global_position = bus.to_global(rest_local + Vector3(0.0, 1.0, 2.0))
	bus.set_remote(true)
	for i in 120:
		bus.global_transform = parked.translated(parked.basis.z * 4.0 * sin(PI * i / 119.0))
		await physics_frame
	pole.queue_free()
	await _frames(10)
	var drift: float = bus.to_local(player.global_position).distance_to(rest_local)
	_check(drift < 0.02 and player.carrier == bus, "a pole a remote bus drives through does not shove its passenger (%.2f m)" % drift)
	# pressed against its front wall while it moves in jerky steps (up to ~0.6 m a tick, forward and back), the
	# passenger holds still in it: its walls move with it, not a step behind, and a step back does not seem to leave
	# them outside it
	player.teleport(player.global_position, bus.global_rotation.y + PI)
	player.scripted_input = Vector2(0.0, 1.0)
	await _frames(90)
	var st: Array = bus.net_state()
	var zs := PackedFloat64Array()
	for i in 120:
		st[0] = parked.translated(parked.basis.z * 6.0 * sin(PI * i / 119.0) * (1.0 + 0.1 * sin(i * 2.3)))
		bus.apply_net_state(st, st, 0.0)
		await physics_frame
		zs.append(bus.to_local(player.global_position).z)
	player.scripted_input = null
	var shake := 0.0
	for i in range(1, zs.size()):
		shake = maxf(shake, absf(zs[i] - zs[i - 1]))
	_check(shake < 0.01, "against a remote bus's front wall the passenger holds still as it moves (%.3f m shake)" % shake)
	player.teleport(bus.to_global(bus.driver_exit))
	await _frames(30)
	bus.set_remote(false)
	await _wheel(true, 12)
	var fp_in: bool = player.first_person
	await _wheel(false, 1)
	var fp_out: bool = player.first_person
	await _wheel(true, 1)
	_check(fp_in and not fp_out and player.first_person, "the mouse wheel zooms into first person and back out")
	_press(KEY_E)
	await _frames(2)
	_check(_main.driving == bus, "E near the driver seat takes the wheel")
	if _main.driving != bus:
		return
	_check(bus.cab_view and get_root().get_camera_3d() != bus.camera, "first person carries over to the cab view")
	_key(KEY_A, true)
	await _frames(40)
	_check(bus.steering > 0.7, "full lock at a standstill (%.2f rad)" % bus.steering)
	var turned: float = bus._steering_rest.basis.x.angle_to(bus._steering_wheel.transform.basis.x)
	var off_rim := 0.0
	for hand: Node3D in bus._hands:
		var p: Vector3 = bus._steering_wheel.global_transform.affine_inverse() * hand.global_position
		off_rim = maxf(off_rim, Vector2(absf(Vector2(p.x, p.z).length() - 0.24), p.y).length())
	_check(turned > 2.0 and bus._hands.size() == 2 and off_rim < 0.03,
			"the steering wheel turns (%.0f°) with the driver's hands on its rim (%.3f m off)" % [rad_to_deg(turned), off_rim])
	await _shot("bus_cab.png")
	_key(KEY_A, false)
	await _wheel(false, 1)
	var chase: bool = not bus.cab_view and get_root().get_camera_3d() == bus.camera
	await _wheel(true, 8)
	_check(chase and bus.cab_view, "the mouse wheel zooms out of the cab view and back into it")
	await _frames(40)
	_press(KEY_Q)
	await _frames(2)
	_check(bus.indicator == 1, "Q (A on AZERTY) signals left")
	_press(KEY_E)
	await _frames(2)
	_check(bus.indicator == -1, "E signals right")
	_key(KEY_D, true)
	await _frames(40)
	_key(KEY_D, false)
	await _frames(60)
	_check(bus.indicator == 0, "the signal cancels itself once the wheel is back")

	_press(KEY_O)
	await _frames(120)
	var shapes_off := 0
	for c in bus.inside.get_children():
		if c is CollisionShape3D and c.disabled:
			shapes_off += 1
	_check(bus.doors_open and shapes_off == 3, "O opens the 3 doors (%d door colliders off)" % shapes_off)
	await _shot("bus_doors.png")
	_press(KEY_O)
	await _frames(120)

	_key(KEY_W, true)
	await _frames(150)
	_key(KEY_W, false)
	var v0: float = bus.speed()
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	_check(_main.driving == null and player.carrier == bus and bus.speed() > 4.0,
			"Space while moving leaves the seat into the aisle (bus at %.1f m/s)" % bus.speed())
	_check(player.first_person, "the cab view carries over to first person")
	var local0: Vector3 = bus.to_local(player.global_position)
	await _walk(bus, Vector3(0, 0, -1), 90)  # towards the back
	var local1: Vector3 = bus.to_local(player.global_position)
	_check(player.carrier == bus and player.is_on_floor() and local0.z - local1.z > 2.0 and bus.carries(player.global_position),
			"walking inside the rolling bus (%.1f m back along the aisle, bus %.1f -> %.1f m/s)" % [
			local0.z - local1.z, v0, bus.speed()])
	await _shot("bus_inside_moving.png")
	for i in 600:
		if absf(bus.speed()) < 0.2:
			break
		await physics_frame
	await _frames(30)
	_check(bus.carries(player.global_position) and absf(bus.to_local(player.global_position).y - 0.36) < 0.1,
			"still standing on the floor when the bus has stopped (%.2f m above the bus origin)" % bus.to_local(player.global_position).y)

	# out of the front door and back in
	player.teleport(bus.to_global(bus.driver_exit))
	await _frames(5)
	_press(KEY_E)
	await _frames(2)
	_press(KEY_O)
	await _frames(110)
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	await _frames(10)
	player.teleport(bus.to_global(bus.door_centres[0] + Vector3(1.0, 0.05, 0.0)))
	await _frames(5)
	await _walk(bus, Vector3(-1, 0, 0), 70)
	var out_local: Vector3 = bus.to_local(player.global_position)
	_check(player.carrier == null and out_local.x < -1.5 and player.is_on_floor(),
			"walks out of the front door onto the ground (%.1f m right of the axis)" % -out_local.x)
	await _walk(bus, Vector3(1, 0, 0), 70)
	_check(player.carrier == bus and absf(bus.to_local(player.global_position).y - 0.36) < 0.1,
			"walks back in over the step (%.2f m)" % bus.to_local(player.global_position).y)


func _finish() -> void:
	if _failures.is_empty():
		print("ALL CAR CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _artic_checks() -> void:
	var player = _main.player
	var bus: VehicleBody3D = null
	for car in _main.cars:
		if car.model_name == "bus-idfm-artic":
			bus = car
	_check(bus != null and bus.trailer != null and bus.has_doors, "the articulated bus has its rear section (layout loaded)")
	if bus == null or bus.trailer == null:
		return
	# the 12 m bus leaves the test road to it
	player.teleport(player.global_position + Vector3.UP * 4.0)
	player.set_carrier(null)
	for car in _main.cars.duplicate():
		if car.model_name == "bus-idfm":
			_main.cars.erase(car)
			car.queue_free()
	var rear: VehicleBody3D = bus.trailer
	var g := WorldQuery.ground_y(bus.get_world_3d(), BUS_ROAD.x, -BUS_ROAD.y, Layers.SOLID)
	bus.place(Transform3D(Basis(Vector3.UP, atan2(BUS_ROAD_DIR.x, -BUS_ROAD_DIR.y)), Vector3(BUS_ROAD.x, g + 0.3, -BUS_ROAD.y)))
	await _frames(120)
	var wheels := _wheels_on_ground(bus)
	_check(wheels == Vector2i(6, 6) and absf(bus.articulation()) < 0.03 and _hitch_gap(bus) < 0.03 and rear.global_basis.y.y > 0.98,
			"parked straight on its 6 wheels (%d on the ground, articulation %.1f°, hitch gap %.3f m)" % [
			wheels.x, rad_to_deg(bus.articulation()), _hitch_gap(bus)])
	player.teleport(bus.to_global(bus.driver_exit))
	await _frames(20)
	_press(KEY_E)
	await _frames(2)
	_check(_main.driving == bus, "E near the driver seat takes the wheel")
	if _main.driving != bus:
		return
	await _wheel(false, 3)                  # chase camera, for the shots
	_key(KEY_W, true)
	await _frames(120)
	var v: float = bus.speed()
	_key(KEY_A, true)
	var max_angle := 0.0
	var max_gap := 0.0
	var min_up := 1.0
	for i in 100:
		await physics_frame
		max_angle = maxf(max_angle, absf(bus.articulation()))
		max_gap = maxf(max_gap, _hitch_gap(bus))
		min_up = minf(min_up, minf(bus.global_basis.y.y, rear.global_basis.y.y))
	await _shot("artic_turn.png")
	_key(KEY_W, false)
	_key(KEY_A, false)
	_key(KEY_S, true)
	for i in 300:
		await physics_frame
		if bus.speed() < 0.3:
			break
	_key(KEY_S, false)
	# bend it at walking pace, full lock
	_key(KEY_A, true)
	for i in 600:
		_key(KEY_W, bus.speed() < 3.0)
		await physics_frame
		if absf(bus.articulation()) > 0.4:
			break
	_key(KEY_W, false)
	_key(KEY_A, false)
	var steps := [[KEY_S, func() -> bool: return bus.speed() < 0.3], [KEY_S, func() -> bool: return bus.speed() < -2.0],
			[KEY_W, func() -> bool: return bus.speed() > -0.3]]          # stop, reverse straight, stop
	var reverse_angles := []
	for step: Array in steps:
		_key(step[0], true)
		for i in 300:
			await physics_frame
			max_gap = maxf(max_gap, _hitch_gap(bus))
			min_up = minf(min_up, minf(bus.global_basis.y.y, rear.global_basis.y.y))
			if step[1].call():
				break
		if step == steps[1]:
			reverse_angles.append(absf(bus.articulation()))
			await _frames(90)               # keep reversing
			reverse_angles.append(absf(bus.articulation()))
		_key(step[0], false)
		if step == steps[0]:
			reverse_angles.append(absf(bus.articulation()))
	await _frames(30)
	_check(v > 4.0 and max_angle > 0.12 and max_angle < bus.JOINT_YAW + 0.05,
			"drives (%.1f m/s) and the joint bends in the turn (up to %.0f°, limit %.0f°)" % [v, rad_to_deg(max_angle), rad_to_deg(bus.JOINT_YAW)])
	_check(reverse_angles[0] > 0.3 and reverse_angles[2] <= reverse_angles[0] + 0.02,
			"reversing straight does not fold it (joint %.0f° stopped, %.0f° then %.0f° reversing)" % [
			rad_to_deg(reverse_angles[0]), rad_to_deg(reverse_angles[1]), rad_to_deg(reverse_angles[2])])
	_check(max_gap < 0.08 and min_up > 0.9, "the hitch holds and both sections stay upright (gap up to %.3f m, up %.2f)" % [max_gap, min_up])
	var rel: Transform3D = bus.global_transform.affine_inverse() * rear.global_transform
	_check(bus._bellows_mesh.get_surface_count() == 1 and bus._bellows_rel.origin.distance_to(rel.origin) < 0.01
			and absf(bus.articulation()) > 0.0 and bus._bellows_rel.basis.z.distance_to(rel.basis.z) < 0.01,
			"the bellows follows the joint")

	_press(KEY_O)
	await _frames(120)
	var shapes_off := 0
	for hull: StaticBody3D in [bus.inside, rear.inside]:
		for c in hull.get_children():
			if c is CollisionShape3D and c.disabled:
				shapes_off += 1
	_check(bus.doors_open and shapes_off == 4, "O opens the 4 doors (%d door colliders off)" % shapes_off)
	_press(KEY_O)
	await _frames(120)

	# bend it again, stop, leave the seat, walk down the aisle through the bent bellows into the rear section
	_key(KEY_A, true)
	_key(KEY_W, true)
	await _frames(100)
	_key(KEY_W, false)
	_key(KEY_S, true)
	for i in 300:
		await physics_frame
		if bus.speed() < 0.3:
			break
	_key(KEY_S, false)
	_key(KEY_A, false)
	await _frames(30)
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	var floor_y: float = bus.door_centres[0].y
	var hitch: Vector3 = bus._hitch
	player.teleport(bus.to_global(Vector3(-0.2, floor_y + 0.05, hitch.z + 3.0)))
	await _frames(10)
	_check(player.carrier == bus and player.is_on_floor(), "standing in the front section's aisle")
	await _walk(bus, Vector3(0, 0, -1), 50)
	await _walk(rear, Vector3(0, 0, -1), 40)
	var local: Vector3 = rear.to_local(player.global_position) + bus.rear_offset     # in the car frame, straight
	_check(player.carrier == rear and player.is_on_floor() and local.z < hitch.z - 1.5 and absf(local.y - floor_y) < 0.1,
			"walks through the bellows into the rear section, which carries them (%.1f m behind the hitch, %.2f m up, joint at %.0f°)" % [
			hitch.z - local.z, local.y, rad_to_deg(bus.articulation())])
	player.teleport(rear.to_global(Vector3(-0.2, floor_y + 0.05, hitch.z - 3.0) - bus.rear_offset), rear.global_rotation.y + PI)  # facing forward
	player.set_first_person(true)
	await _frames(5)
	await _shot("artic_joint.png")


## Distance between the hitch points of the two sections of an articulated bus.
func _hitch_gap(bus: VehicleBody3D) -> float:
	return bus.to_global(bus._hitch).distance_to(bus.trailer.to_global(bus._hitch - bus.rear_offset))
