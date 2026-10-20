extends SceneTree
## Headless checks for the GAZ Tiger's roof gun (Car.SPECS "gaz-tiger", scripts/armored_car.gd; its driver's cab view,
## steering wheel, lamps and drive: tools/test_real_cars.gd): the vehicle menu parks it with its gun; E from its right
## side stands the player in the roof hatch as the gunner (help, dash); the gun's reach is all round, PITCH_DOWN below
## level to PITCH_UP above (clamp_aim, the mouse in the turret view); the turret view (V) from the gunner's eye over the
## gun, turned onto a car ahead, turns the ring and the gun onto it and the left mouse button hits it, the armour taking
## two thirds of the damage it does to the car; a car behind is reached too (the ring turns round, the gun with it);
## looking down at the ground beside the car is out of reach (the dash says so); V again: the chase camera and the
## gunner standing in the hatch, turning with the ring; E takes the wheel. LAN: the gunner's player state carries the
## gun, and a remote copy fires from it without its hits counting. Getting on, the chase view's middle is within reach.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_tiger.gd
## Without --headless it also saves shots to /tmp/tiger_*.png.

const Car = preload("res://scripts/car.gd")
const ArmoredCar = preload("res://scripts/armored_car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")

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
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


## Looks at the car from `eye` (car frame) towards `at` with a free camera, for a shot; back to `back` after.
func _look(car: VehicleBody3D, eye: Vector3, at: Vector3, file: String, back: Camera3D) -> void:
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
	back.make_current()


## Puts `car`'s body box centre at `p` (global), frozen.
func _put(car: VehicleBody3D, p: Vector3, b: Basis) -> void:
	var box: Vector3 = (car.find_children("*", "CollisionShape3D", false, false)[0] as Node3D).position
	car.global_transform = Transform3D(b, p - b * box)
	car.freeze = true


## A spot on the ground (global) 25 to 70 m from the gun with a clear line of fire from its muzzle, at a bearing
## within `arc` (rad) of `bearing` (car frame, rad: 0 ahead, + to the left); INF if none.
func _clear_spot(tiger: ArmoredCar, bearing: float, arc: float) -> Vector3:
	var space := tiger.get_world_3d().direct_space_state
	var muzzle: Vector3 = tiger.to_global(tiger._muzzle_point())
	for dist: float in [60.0, 45.0, 35.0, 25.0, 70.0]:
		for k in 25:
			var yaw := bearing + arc * (k / 12.0 - 1.0)
			var p := tiger.to_global(Vector3(sin(yaw), 0.0, cos(yaw)) * dist)
			var g := WorldQuery.ground_y(tiger.get_world_3d(), p.x, p.z, Layers.TERRAIN, p.y + 20.0)
			if is_nan(g) or absf(g - tiger.global_position.y) > 4.0:
				continue
			var spot := Vector3(p.x, g, p.z)
			var q := PhysicsRayQueryParameters3D.create(muzzle, spot + Vector3.UP * 0.8, ArmoredCar.Guns.MASK,
					[tiger.get_rid()])
			var room := PhysicsShapeQueryParameters3D.new()     # and room for the car
			var box := BoxShape3D.new()
			box.size = Vector3(3.0, 1.2, 5.5)
			room.shape = box
			room.transform = Transform3D(Basis(), spot + Vector3.UP * 1.0)
			room.collision_mask = Layers.BUILDINGS | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
			room.exclude = [tiger.get_rid()]
			if space.intersect_ray(q).is_empty() and space.intersect_shape(room, 1).is_empty():
				return spot
	return Vector3.INF


## The middle of `car`'s body box (global).
func _middle(car: VehicleBody3D) -> Vector3:
	return car.global_transform * (car.find_children("*", "CollisionShape3D", false, false)[0] as Node3D).position


## Turns the gunner's eye (turret view) onto the middle of `car`.
func _look_at(tiger: ArmoredCar, car: VehicleBody3D) -> void:
	var d: Vector3 = (tiger.to_local(_middle(car)) - tiger._turret_camera.position).normalized()
	tiger.gun_look = Vector2(atan2(d.x, d.z), asin(d.y))


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	_check(Car.MODELS.has("gaz-tiger") and _main._menu_buttons.has_node("gaz-tiger"), "the vehicle menu has the GAZ Tiger")
	var tiger: VehicleBody3D = _main.spawn_car_near_player("gaz-tiger")
	_check(tiger is ArmoredCar and tiger.turret_guns != null and tiger.has_passenger_seat and tiger.has_cab(),
			"it parks as an armoured car with a roof gun and a gunner's place")
	var target: VehicleBody3D = _main.spawn_car_near_player("sedan")
	if not tiger is ArmoredCar or target == null:
		return _finish()
	await _frames(60)

	# the reach: all round, from PITCH_DOWN below level to PITCH_UP above
	var worst := 0.0
	for d: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3(1, 0.3, -1).normalized()]:
		worst = maxf(worst, ArmoredCar.clamp_aim(d).angle_to(d))
	var down := ArmoredCar.clamp_aim(Vector3(0.3, -1.0, 0.2).normalized())
	var up := ArmoredCar.clamp_aim(Vector3(0.0, 1.0, 0.1).normalized())
	_check(worst < 1e-4 and is_equal_approx(asin(down.y), -ArmoredCar.PITCH_DOWN)
			and is_equal_approx(asin(up.y), ArmoredCar.PITCH_UP) and is_equal_approx(down.length(), 1.0),
			"it reaches all round, %.0f° down to %.0f° up" % [rad_to_deg(ArmoredCar.PITCH_DOWN), rad_to_deg(ArmoredCar.PITCH_UP)])

	# E from the right side: the gunner, standing in the hatch
	player.teleport(tiger.to_global(Vector3(-tiger.half_extents.x - 1.0, 0.3, 0.0)))
	await _frames(5)
	_key(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.riding == tiger and _main.driving == null and tiger.riding and tiger.turret_guns.live
			and "GUNNER" in _main._help.text and _main._dash.visible and "GUNNER" in _main._dash.text,
			"E from the right side: the gunner's place (help, dash)")
	if _main.riding != tiger:
		return _finish()
	if tiger.cab_view:
		_key(KEY_V)
		await process_frame
	var head: Vector3 = tiger._passenger.global_position + Vector3.UP * (tiger._passenger.mesh as CapsuleMesh).height * 0.5
	var body := tiger.find_child("body", true, false) as MeshInstance3D
	var roof: float = (tiger._in_car(body) * body.get_aabb()).end.y
	_check(root.get_camera_3d() == tiger.camera and tiger._passenger.visible and tiger.to_local(head).y > roof + 0.3,
			"the chase camera shows the gunner standing out of the hatch (head %.2f m, roof %.2f m)" % [
			tiger.to_local(head).y, roof])
	await _frames(30)
	await process_frame
	_check(not tiger._out_of_arc and not "REACH" in _main._dash.text,
			"getting on, the middle of the chase view is within the gun's reach")
	await _look(tiger, Vector3(-3.5, 3.6, 4.5), Vector3(0.0, 2.2, -0.6), "tiger_gunner.png", tiger.camera)

	# held still, a car ahead: the turret view onto it
	tiger.freeze = true
	var spot := _clear_spot(tiger, 0.0, 1.2)
	_check(spot.is_finite(), "a spot ahead with a clear line of fire")
	if not spot.is_finite():
		return _finish()
	_put(target, spot + Vector3.UP * 0.8, tiger.global_basis.orthonormalized())
	await _frames(2)
	_key(KEY_V)
	await process_frame
	var eye: Vector3 = tiger.to_local(tiger._turret_camera.global_position)
	_check(root.get_camera_3d() == tiger._turret_camera and tiger.cab_view and not tiger._passenger.visible
			and eye.y > roof, "V: the turret view from the gunner's eye over the roof (%.2f m)" % eye.y)
	tiger.look_turret(Vector2(0.0, 5.0))
	_check(is_equal_approx(tiger.gun_look.y, -ArmoredCar.PITCH_DOWN), "the mouse turns the view no lower than the gun goes")
	_look_at(tiger, target)
	await _frames(120)
	await process_frame
	var want: Vector3 = (tiger.to_local(_middle(target)) - tiger._in_car(tiger._gun).origin).normalized()
	var barrel: Vector3 = tiger._in_car(tiger._gun).basis.z.normalized()
	_check(tiger.turret_dir.angle_to(want) < 0.03 and barrel.angle_to(tiger.turret_dir) < 0.01 and not tiger._out_of_arc,
			"looking at the car, the ring and the gun turn onto it (%.1f° off, the barrel along the aim)" % \
			rad_to_deg(tiger.turret_dir.angle_to(want)))
	_check(_main._gunsight.visible, "the ring shows where the gun is aimed")
	await _shot("tiger_turret_view.png")
	var hits := [0]
	tiger.turret_guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: hits[0] += 1)
	var health: float = target.health
	_trigger(true)
	await _frames(30)
	await _shot("tiger_firing.png")
	await _frames(30)
	_trigger(false)
	var fired: int = tiger.turret_guns.rounds_fired
	_check(fired >= 20 and hits[0] > 0 and target.health < health,
			"left click fires (%d rounds in 1 s) and hits the car (%d hits, health %.0f -> %.0f)" % [fired, hits[0], health,
			target.health])
	await _frames(20)
	_check(tiger.turret_guns.rounds_fired == fired, "releasing the button stops the gun")

	# behind: the ring turns round
	spot = _clear_spot(tiger, PI, 0.6)
	_check(spot.is_finite(), "a spot behind with a clear line of fire")
	if not spot.is_finite():
		return _finish()
	_put(target, spot + Vector3.UP * 0.8, tiger.global_basis.orthonormalized())
	await _frames(2)
	_look_at(tiger, target)
	await _frames(150)
	want = (tiger.to_local(_middle(target)) - tiger._in_car(tiger._gun).origin).normalized()
	_check(tiger.turret_dir.angle_to(want) < 0.03 and tiger.turret_dir.z < -0.8,
			"a car behind: the ring turns round onto it (%.1f° off)" % rad_to_deg(tiger.turret_dir.angle_to(want)))
	await _shot("tiger_turret_back.png")
	target.set_health(target.max_health, false)            # (the first burst wrecked it)
	health = target.health
	hits[0] = 0
	_trigger(true)
	await _frames(60)
	_trigger(false)
	_check(hits[0] > 0 and target.health < health, "and hits it (%d hits)" % hits[0])

	# the armour
	var h0: float = tiger.health
	tiger.damage(30.0)
	_check(is_equal_approx(h0 - tiger.health, 30.0 / ArmoredCar.ARMOUR), "its armour takes 2/3 of the damage")
	tiger.set_health(tiger.max_health, false)

	# the ground right beside it: out of reach
	tiger.gun_look = Vector2(PI * 0.5, -1.2)
	_key(KEY_V)
	await process_frame
	_check(root.get_camera_3d() == tiger.camera and tiger._passenger.visible, "V again: the chase camera, the gunner shows")
	tiger._look_yaw = PI * 0.5
	tiger._look_pitch = -1.15
	await _frames(60)
	await process_frame
	_check(tiger._out_of_arc and "REACH" in _main._dash.text
			and absf(asin(tiger.turret_dir.y) + ArmoredCar.PITCH_DOWN) < 0.01,
			"looking down beside it: out of reach, the gun stays at %.0f°" % rad_to_deg(asin(tiger.turret_dir.y)))
	var ring_yaw: float = tiger._ring.rotation.y
	_check(absf(angle_difference(ring_yaw, atan2(tiger.turret_dir.x, tiger.turret_dir.z))) < 0.01
			and absf(angle_difference(tiger._passenger.get_parent().rotation.y, ring_yaw)) < 1e-4,
			"the gunner turns with the ring")
	await _shot("tiger_chase_side.png")
	tiger._look_yaw = 0.0
	tiger._look_pitch = -0.22
	await _frames(30)

	# LAN: the gunner's state, fired from by a remote copy
	var s: Array = _main.net_player_state()
	_check(s.size() == 7 and s[4] & 2 != 0 and s[5] is Vector3
			and (s[5] as Vector3).normalized().is_equal_approx(tiger.turret_dir), "the gunner's player state carries the gun")
	var copy: VehicleBody3D = _main.add_net_car("gaz-tiger", tiger.global_transform.translated(Vector3(0.0, 0.0, 0.0)))
	copy.set_remote(true)
	copy.global_position += copy.global_basis.x * 6.0
	var copy_hits := [0]
	copy.turret_guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: copy_hits[0] += 1)
	copy.show_passenger(true, Color.RED)
	var aim := Vector3(-0.6, 0.2, 0.7).normalized()
	copy.set_gunner_state(aim * 150.0, true)
	await _frames(40)
	_check(copy._passenger.visible and copy.turret_dir.is_equal_approx(aim) and copy.turret_guns.rounds_fired > 10
			and not copy.turret_guns.live and copy_hits[0] == 0,
			"a remote copy shows the gunner and fires (%d rounds) where they aim, its hits not counting here" % \
			copy.turret_guns.rounds_fired)
	copy.show_passenger(false)
	var n: int = copy.turret_guns.rounds_fired
	await _frames(20)
	_check(copy.turret_guns.rounds_fired == n and not copy._passenger.visible, "the gunner gone, it stops")
	_main.cars.erase(copy)
	copy.queue_free()

	# E: the wheel
	tiger.freeze = false
	_key(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.driving == tiger and _main.riding == null and not tiger.riding and not tiger.turret_guns.live
			and "gunner boards" in _main._help.text, "E at the gun takes the wheel")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ALL TIGER CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
