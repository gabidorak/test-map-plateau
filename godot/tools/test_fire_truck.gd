extends SceneTree
## Headless checks for the fire truck (scripts/fire_truck.gd, scripts/water_cannon.gd): the vehicle menu parks it with its
## six wheels and its cannon; E gets in, it drives and turns; the turret turns and the barrel rises to drop the jet on
## the point the driver looks at, and the jet reaches tens of metres; the left mouse button sprays (RATE packets a
## second) and the water lands on a car there, nudging it; a broken (burning) car is put out by the water and runs
## again; B switches the siren and the flashing beacons; light breakable props fall over under the water, heavy ones
## hold; debris and players are pushed; a remote copy turns its turret and sprays from the LAN state without its hits
## counting. The cab: V gives the cab view from the driver's eye inside it, the steering wheel turns with the steering
## and the driver's hands stay on it; E from the right side sits the player in the passenger seat (the cab view from
## the passenger's eye, a look-alike in the chase view), E there takes the wheel, Space gets out on the right; another
## player in the passenger seat (LAN) keeps it.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_fire_truck.gd
## Without --headless it also saves shots to /tmp/fire_truck_*.png.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const WaterCannon = preload("res://scripts/water_cannon.gd")
const FireTruck = preload("res://scripts/fire_truck.gd")
const Car = preload("res://scripts/car.gd")

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
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	_check(Car.MODELS.has("fire-truck") and _main._menu_buttons.has_node("fire-truck"), "the vehicle menu has the fire truck")
	var truck: VehicleBody3D = _main.spawn_car_near_player("fire-truck")
	_check(truck is FireTruck and truck.cannon != null and truck.find_children("*", "VehicleWheel3D", true, false).size() == 6,
			"it parks as a fire truck with six wheels and a water cannon")
	if truck == null:
		return _finish()
	_check(truck.half_extents.z > 4.2 and truck.half_extents.x < 1.4 and truck.mass == 16000.0,
			"%.1f m long, %.2f m wide, 16 t" % [truck.half_extents.z * 2.0, truck.half_extents.x * 2.0])
	await _frames(60)
	_check(absf(truck.global_basis.y.angle_to(Vector3.UP)) < 0.1 and truck.linear_velocity.length() < 0.3,
			"it rests level on its wheels")
	player.teleport(truck.to_global(Vector3(truck.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.driving == truck and "water cannon" in _main._help.text, "E gets in; the help says how to spray")

	# the cab view, from the driver's eye inside the cab
	_check(truck.has_cab() and truck.has_passenger_seat and truck._steering_wheel != null, "it has a cab with a steering wheel and a passenger seat")
	var was_cab: bool = truck.cab_view
	if not was_cab:
		_tap(KEY_V)
	await process_frame
	var cam := root.get_camera_3d()
	var eye_local: Vector3 = truck.to_local(cam.global_position)
	_check(truck.cab_view and cam == truck._cab_camera and eye_local.x > 0.2 and eye_local.z > 2.0
			and eye_local.y > 2.3 and eye_local.y < 3.1, "V: the cab view from the driver seat (%s)" % eye_local)
	_check(not truck._driver_body.visible and truck._hands[0].visible, "the driver's body is hidden there, the hands on the wheel show")
	await _shot("fire_truck_cab.png")

	# drives and turns
	var yaw0: float = truck.global_rotation.y
	_key(KEY_W, true)
	await _frames(150)
	var v: float = truck.speed()
	_key(KEY_A, true)
	await _frames(60)
	var rest: Transform3D = truck._steering_rest
	var turned: float = (rest.basis.inverse() * truck._steering_wheel.transform.basis).get_euler().y
	var hand_on := absf(truck._hands[0].position.distance_to(truck._wheel_centre) - truck._grip_radius) < 0.03
	await _shot("fire_truck_cab_turn.png")
	_key(KEY_A, false)
	_key(KEY_W, false)
	_check(turned > 0.3 and absf(turned - truck.steering * Car.STEERING_RATIO) < 0.01 and hand_on,
			"A turns the steering wheel left (%.0f°), a hand on its rim" % rad_to_deg(turned))
	_check(v > 4.0, "W drives it (%.1f m/s after 2.5 s)" % v)
	_check(absf(angle_difference(yaw0, truck.global_rotation.y)) > 0.1, "A turns it (%.0f°)" % rad_to_deg(angle_difference(yaw0, truck.global_rotation.y)))
	_key(KEY_S, true)
	for i in 300:
		await physics_frame
		if truck.speed() < 0.3:
			break
	_key(KEY_S, false)
	await _frames(30)

	# the jet's reach: the barrel at its longest throw, on the flat
	var far: float = truck.solve_pitch(1000.0, 0.0)
	var near: float = truck.solve_pitch(25.0, -2.0)
	_check(is_equal_approx(far, FireTruck.LONGEST) and near > FireTruck.PITCH_LIMITS.x and near < FireTruck.LONGEST,
			"out of reach the barrel throws furthest (%.0f°), 25 m away lower (%.0f°)" % [rad_to_deg(far), rad_to_deg(near)])
	var reach := 0.0
	for d in range(10, 200, 2):
		if truck._height_at(FireTruck.LONGEST, d) > -3.0:
			reach = d
	_check(reach > 45.0 and reach < 90.0, "the jet reaches ~%d m" % reach)

	# a car ~22 m away, off to one side, in clear view of the cannon; the driver looks at it
	truck.freeze = true
	var spot := _clear_spot(truck)
	_check(spot != Vector3.INF, "a clear spot ~22 m from the truck for the target car")
	if spot == Vector3.INF:
		return _finish()
	var target: VehicleBody3D = _main.add_net_car("sedan", Transform3D.IDENTITY)
	target.place(Transform3D(truck.global_basis.orthonormalized(), spot))
	await _frames(60)
	var eye := Camera3D.new()
	root.add_child(eye)
	eye.global_position = truck.to_global(Vector3(0.0, 4.5, 0.0))
	eye.look_at(target.global_transform * Vector3(0.0, 0.8, 0.0))
	eye.make_current()
	await _frames(150)
	var want: Vector2 = truck._want
	var bearing := atan2(truck.to_local(target.global_position).x, truck.to_local(target.global_position).z - truck._pivot.z)
	_check(truck.aim.distance_to(want) < 0.01 and absf(angle_difference(want.x, bearing)) < 0.15 and absf(want.x) > 0.15,
			"the turret turns to the car (%.0f°, the car at %.0f°), the barrel at %.0f°" % [rad_to_deg(truck.aim.x),
			rad_to_deg(bearing), rad_to_deg(truck.aim.y)])
	var sight: Variant = truck.sight_point()
	_check(sight != null and (sight as Vector3).distance_to(target.global_position) < 3.0,
			"the jet as aimed lands on it (%.1f m off)" % ((sight as Vector3).distance_to(target.global_position) if sight != null else INF))
	await process_frame
	_check(_main._water_sight.visible, "a ring shows where on the screen")

	# spray it
	var hits := [0, 0]                      # packets, packets on the car
	truck.cannon.hit.connect(func(c: Object, _s: int, _p: Vector3, _i: Vector3) -> void:
		hits[0] += 1
		if c == target:
			hits[1] += 1)
	var p0: Vector3 = target.global_position
	_trigger(true)
	await _frames(30)
	var fired: int = truck.cannon.packets_fired
	_check(fired >= 14 and fired <= 16 and truck.cannon.packets_in_flight() > 0 and "WATER" in _main._dash.text,
			"left click sprays %d packets in 0.5 s, water in the air, the dash says so" % fired)
	await _frames(90)
	await _shot("fire_truck_spray.png")
	_check(hits[1] > 20, "the water lands on the car (%d of %d packets)" % [hits[1], hits[0]])
	var moved := target.global_position.distance_to(p0)
	_check(moved > 0.1, "and nudges it, braked as it is (%.1f m in 2 s)" % moved)
	_check(truck.cannon._wet.size() > 0 or hits[0] == hits[1], "the ground around gets wet patches")

	# a burning car is put out
	target.place(Transform3D(truck.global_basis.orthonormalized(), spot))
	target.set_health(0.0)
	_check(target.broken and target.smoking_black(), "a broken car burns (black smoke)")
	for i in 300:
		await physics_frame
		if not target.broken:
			break
	_check(not target.broken and target.health == target.max_health and not target.smoking_black(),
			"hosed for %.0f s its fire is out and it runs again" % Car.EXTINGUISH)
	_trigger(false)
	await _frames(10)
	fired = truck.cannon.packets_fired
	await _frames(30)
	_check(truck.cannon.packets_fired == fired, "releasing the button stops the water")
	await _frames(240)
	_check(truck.cannon.packets_in_flight() == 0, "the last water lands")

	# siren and beacons
	_tap(KEY_B)
	var lit := false
	for i in 60:
		await process_frame
		lit = lit or truck._beacon_lights[0].visible or truck._beacon_lights[1].visible
	_check(truck.siren and truck.audio.siren and lit and "SIREN" in _main._dash.text,
			"B sounds the siren and the blue beacons flash")
	await _shot("fire_truck_beacons.png")
	_tap(KEY_B)
	await process_frame
	await process_frame
	_check(not truck.siren and not truck._beacon_lights[0].visible and not truck._beacon_lights[1].visible,
			"B again switches them off")

	# LAN: a remote copy turns its turret and sprays for show
	truck.cannon.firing = true
	truck.siren = true
	var s: Array = truck.net_state()
	truck.cannon.firing = false
	truck.siren = false
	var copy: VehicleBody3D = _main.add_net_car("fire-truck", truck.global_transform.translated(Vector3(0.0, 0.0, 0.0)))
	copy.place(truck.global_transform.translated_local(Vector3(-6.0, 0.0, 0.0)))
	copy.set_remote(true)
	var copy_hits := [0]
	copy.cannon.hit.connect(func(_c: Object, _s: int, _p: Vector3, _i: Vector3) -> void: copy_hits[0] += 1)
	s[0] = copy.global_transform
	copy.apply_net_state(s, s, 1.0)
	_check(copy.cannon.firing and not copy.cannon.live and copy.siren and copy.aim.distance_to(truck.aim) < 0.001,
			"a remote copy takes the aim, the spray and the siren from the LAN state")
	await _frames(120)
	_check(copy.cannon.packets_fired > 50 and copy.cannon.hits > 0 and copy_hits[0] == 0,
			"it sprays (%d packets, %d landed) but its hits do not count here" % [copy.cannon.packets_fired, copy.cannon.hits])
	_main.cars.erase(copy)
	copy.queue_free()
	_main.exit_car()
	truck.freeze = false

	# light props fall over under the water, heavy ones hold; debris is pushed
	var props: Node = _main.breakables._props
	if props == null:
		_check(false, "breakable props are in the world")
	else:
		var light := -1
		var heavy := -1
		for shape in mini(PhysicsServer3D.body_get_shape_count(props.get_rid()), 4000):
			var k: int = props.record_for_shape(shape)
			var mass: float = _main.breakables.BREAKABLE_PROPS.get(props.data.describe(k).get("model", ""), 0.0)
			if mass > 0.0 and mass <= 20.0 and light < 0:
				light = shape
			elif mass > 40.0 and heavy < 0:
				heavy = shape
		var push := Vector3(WaterCannon.PUSH, -20.0, 0.0)
		if light >= 0:
			var k: int = props.record_for_shape(light)
			_main._on_water_hit(props, light, Vector3.ZERO, push)
			_check(not _main.breakables._broken.has(k), "one packet does not knock a light prop over")
			var debris: int = _main.breakables.debris.size()
			for i in 30:
				_main._on_water_hit(props, light, Vector3.ZERO, push)
			_check(_main.breakables._broken.has(k) and _main.breakables.debris.size() == debris + 1,
					"a light prop (%s) falls over under the water" % props.data.describe(k).get("model", "?"))
			if _main.breakables.debris.size() > debris:
				var rb: RigidBody3D = _main.breakables.debris[-1]["body"]
				await _frames(2)
				var v0 := rb.linear_velocity
				_main._on_water_hit(rb, 0, rb.global_position, push)
				await physics_frame
				_check((rb.linear_velocity - v0).length() > 0.5, "the water pushes its debris")
		else:
			_check(false, "found a light breakable prop")
		if heavy >= 0:
			var k: int = props.record_for_shape(heavy)
			for i in 60:
				_main._on_water_hit(props, heavy, Vector3.ZERO, push)
			_check(not _main.breakables._broken.has(k), "a heavy prop (%s) holds" % props.data.describe(k).get("model", "?"))

	# a player in the way is shoved
	await _frames(30)
	var pv: Vector3 = player.velocity
	_main.water_push(_main.water_shove(Vector3(WaterCannon.PUSH, 0.0, 0.0)))
	_check(player.velocity.x - pv.x > 0.5, "a player hit by the jet is shoved")
	await _passenger_seat(truck)
	_finish()


## E from the truck's right side: the passenger seat; V, E (takes the wheel), Space; a LAN player seated there.
func _passenger_seat(truck: VehicleBody3D) -> void:
	var player: CharacterBody3D = _main.player
	await _frames(30)
	player.teleport(truck.to_global(Vector3(-truck.half_extents.x - 1.0, 0.3, 1.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.riding == truck and _main.driving == null and truck.riding and not player.visible
			and "PASSENGER" in _main._help.text, "E from the right side sits the player in the passenger seat")
	if _main.riding != truck:
		return
	if not truck.cab_view:
		_tap(KEY_V)
	await process_frame
	var eye: Vector3 = truck.to_local(root.get_camera_3d().global_position)
	_check(root.get_camera_3d() == truck._cab_camera and eye.x < -0.2 and eye.z > 2.0, "V: the cab view from the passenger's eye")
	await _shot("fire_truck_passenger.png")
	_tap(KEY_V)
	await process_frame
	_check(root.get_camera_3d() == truck.camera and truck._passenger.visible, "V again: the chase camera, the passenger seated in the cab")
	if DisplayServer.get_name() != "headless":     # the cab from the front, the passenger seated
		var front := Camera3D.new()
		root.add_child(front)
		front.global_position = truck.to_global(Vector3(-2.5, 2.6, 8.0))
		front.look_at(truck.to_global(Vector3(0.0, 2.3, 3.4)))
		front.make_current()
		await _shot("fire_truck_passenger_front.png")
		front.queue_free()
		truck.camera.make_current()
	_key(KEY_W, true)
	await _frames(30)
	_key(KEY_W, false)
	_check(absf(truck.speed()) < 0.2, "the passenger's keys do not drive it")
	_tap(KEY_SPACE)
	await _frames(3)
	var out: Vector3 = truck.to_local(player.global_position)
	_check(_main.riding == null and not truck.riding and player.visible and out.x < -truck.half_extents.x
			and not truck._passenger.visible, "Space gets out on the right (%.1f m off the side)" % (-out.x - truck.half_extents.x))
	await _frames(20)
	_tap(KEY_E)
	await _frames(2)
	_tap(KEY_E)
	await _frames(2)
	_check(_main.driving == truck and _main.riding == null and not truck.riding, "E in the passenger seat takes the wheel")
	_main.exit_car()
	await _frames(5)
	truck.show_passenger(true, Color.RED)
	player.teleport(truck.to_global(Vector3(-truck.half_extents.x - 1.0, 0.3, 1.0)))
	await _frames(5)
	_check(truck._passenger.visible and not _main.wants_passenger_seat(truck), "another player seated there: shown, and E does not take the seat")
	truck.show_passenger(false)


## A spot on the ground ~22 m from the truck, 15-50° off to either side, that the nozzle sees clearly (and a car
## fits there), or INF.
func _clear_spot(truck: VehicleBody3D) -> Vector3:
	var space := truck.get_world_3d().direct_space_state
	var nozzle: Vector3 = truck.cannon.nozzle.global_position
	for deg: float in [25.0, -25.0, 15.0, -15.0, 40.0, -40.0, 50.0, -50.0]:
		for d: float in [22.0, 18.0, 26.0]:
			var a := deg_to_rad(deg)
			var p: Vector3 = truck.to_global(truck._pivot + Vector3(sin(a) * d, 0.0, cos(a) * d))
			var g := WorldQuery.ground_y(truck.get_world_3d(), p.x, p.z, Layers.SOLID, p.y + 10.0)
			if is_nan(g):
				continue
			var spot := Vector3(p.x, g + 0.05, p.z)
			var clear := true
			for off: Vector3 in [Vector3(0.0, 0.8, 0.0), Vector3(0.0, 1.5, 0.0)]:
				var q := PhysicsRayQueryParameters3D.create(nozzle, spot + off,
						Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES, [truck.get_rid()])
				clear = clear and space.intersect_ray(q).is_empty()
			var box := PhysicsShapeQueryParameters3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.4, 1.2, 5.0)
			box.shape = shape
			box.transform = Transform3D(truck.global_basis.orthonormalized(), spot + Vector3.UP * 1.0)
			box.collision_mask = Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
			if clear and space.intersect_shape(box, 1).is_empty():
				return spot
	return Vector3.INF


func _finish() -> void:
	if _failures.is_empty():
		print("ALL FIRE TRUCK CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
