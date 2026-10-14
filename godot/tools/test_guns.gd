extends SceneTree
## Headless checks for the armed biplane (scripts/plane.gd "biplane-armed", scripts/plane_guns.gd) and vehicle damage
## (car.gd health, scripts/wreck_smoke.gd): the vehicle menu parks it with its two guns; held in the air with a car
## held AIM_DISTANCE ahead on its gunsight, the left mouse button fires both guns in turn at RATE, the rounds hit the car, which smokes grey
## past half its health, then breaks (black smoke, scorched, engine dead: W no longer moves it) and is repaired
## REPAIR_AFTER s later. Releasing it stops the guns. A broken plane has no thrust. A remote copy of the plane fires from
## its LAN state without its hits counting, and takes its health from it. A round hitting a breakable prop knocks it
## over.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_guns.gd
## Without --headless it also saves shots to /tmp/guns_*.png.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Guns = preload("res://scripts/plane_guns.gd")
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


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


func _scorched(car: Node) -> bool:
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mi.material_overlay != null:
			return true
	return false


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	var plain: Node = _main.spawn_car_near_player("biplane")
	_check(plain != null and plain.guns == null and not plain.armed, "the plain biplane has no guns")
	if plain:
		_main.cars.erase(plain)
		plain.free()
	var plane: VehicleBody3D = _main.spawn_car_near_player("biplane-armed")
	_check(plane != null and plane.armed and plane.guns != null and plane.guns.muzzles.size() == 2,
			"the vehicle menu's armed biplane has two guns")
	var target: VehicleBody3D = _main.spawn_car_near_player("sedan")
	if plane == null or target == null:
		return _finish()
	await _frames(60)
	var parked: Transform3D = target.global_transform
	player.teleport(plane.to_global(Vector3(plane.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(2)
	_check(_main.driving == plane and "fire" in _main._help.text, "E gets into it; the help says how to fire")

	# held still high up, the car held on the gunsight AIM_DISTANCE ahead
	var p0: Vector3 = plane.global_position
	var g := WorldQuery.ground_y(plane.get_world_3d(), p0.x, p0.z, Layers.SOLID)
	plane.place(Transform3D(Basis(Vector3.UP, plane.global_rotation.y), Vector3(p0.x, g + 130.0, p0.z)))
	plane.freeze = true
	await _frames(2)
	var aim: Vector3 = plane.aim_point()
	var body_box: Vector3 = (target.find_children("*", "CollisionShape3D", false, false)[0] as Node3D).position
	var tb := plane.global_basis.orthonormalized()
	target.global_transform = Transform3D(tb, aim - tb * body_box)
	target.freeze = true
	await process_frame
	await process_frame
	_check(_main._gunsight.visible, "the gunsight shows on the screen")
	await _shot("guns_aim.png")
	var hits := [0]
	plane.guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: hits[0] += 1)
	var max_health: float = target.max_health
	_trigger(true)
	await _frames(30)
	var fired_half: int = plane.guns.rounds_fired
	_check(fired_half >= 11 and fired_half <= 14 and plane.guns.rounds_in_flight() > 0,
			"left click fires %d rounds in 0.5 s (%.0f a second), tracers in flight" % [fired_half, Guns.RATE])
	await _shot("guns_firing.png")
	var grey_seen := false
	for i in 240:
		await physics_frame
		grey_seen = grey_seen or (target._smoke != null and target._smoke.level == 1)
		if target.broken:
			break
	_trigger(false)
	_check(hits[0] > 0 and plane.guns.vehicle_hits > 0, "rounds hit the car (%d)" % hits[0])
	_check(grey_seen, "past half its health (%.0f) it smokes grey" % max_health)
	_check(target.broken and target.health == 0.0 and target.smoking_black(),
			"then it breaks and smokes black (%d hits of %.0f)" % [hits[0], Guns.DAMAGE])
	_check(_scorched(target) and not target.audio.engine_on, "a broken car is scorched and its engine is off")
	await _frames(10)
	var fired: int = plane.guns.rounds_fired
	await _frames(30)
	_check(plane.guns.rounds_fired == fired, "releasing the button stops the guns")
	await _frames(60)
	await _shot("guns_wreck.png")

	# a broken plane has no thrust
	plane.lever = 1.0
	_check(plane.thrust(10.0) > 1000.0, "the plane pulls at full throttle (%.0f N)" % plane.thrust(10.0))
	plane.set_health(0.0)
	_check(plane.broken and plane.thrust(10.0) == 0.0 and "ENGINE DEAD" in plane.dash_text(),
			"shot down, its engine is dead (no thrust, the dash says so)")
	plane.set_health(plane.max_health)

	# the broken car does not drive
	_main.exit_car()
	plane.freeze = false
	target.freeze = false
	target.place(parked)
	await _frames(60)
	_main.enter_car(target)
	_key(KEY_W, true)
	await _frames(90)
	_key(KEY_W, false)
	_check(target.linear_velocity.length() < 0.5, "W does not move a broken car (%.2f m/s)" % target.linear_velocity.length())
	_check(_main._dash.text.contains("BROKEN"), "the dash says it is broken")
	target._broken_t = Car.REPAIR_AFTER - 0.05
	await _frames(10)
	_check(not target.broken and target.health == target.max_health and not target.smoking_black()
			and not _scorched(target) and target.audio.engine_on, "%.0f s later it is repaired" % Car.REPAIR_AFTER)
	_key(KEY_W, true)
	await _frames(60)
	_key(KEY_W, false)
	_check(target.speed() > 2.0, "and drives again (%.1f m/s)" % target.speed())
	_main.exit_car()

	# LAN: a remote copy fires for show and follows the health
	var copy: VehicleBody3D = _main.add_net_car("biplane-armed", plane.global_transform.translated(Vector3.UP * 60.0))
	copy.set_remote(true)
	var copy_hits := [0]
	copy.guns.hit.connect(func(_c: Object, _s: int, _p: Vector3, _v: Vector3) -> void: copy_hits[0] += 1)
	plane.guns.firing = true
	plane.health = 20.0
	var s: Array = plane.net_state()
	plane.guns.firing = false
	plane.health = plane.max_health
	copy.apply_net_state(s, s, 1.0)
	_check(copy.guns.firing and not copy.guns.live and copy.health == 20.0 and copy._smoke and copy._smoke.level == 1,
			"a remote copy takes the trigger and the health from the LAN state")
	# rounds from the copy into the ground below it
	copy.global_transform = Transform3D(Basis(Vector3.RIGHT, 1.2) * copy.global_basis, copy.global_position)
	await _frames(40)
	_check(copy.guns.rounds_fired > 10 and copy_hits[0] == 0, "it fires (%d rounds) but its hits do not count here" % copy.guns.rounds_fired)
	_main.cars.erase(copy)
	copy.queue_free()

	# a round on a breakable prop
	var props: Node = _main.breakables._props
	if props == null:
		_check(false, "breakable props are in the world")
	else:
		var k: int = props.record_for_shape(0)
		var debris: int = _main.breakables.debris.size()
		_main._on_round_hit(props, 0, Vector3.ZERO, Vector3(500.0, -40.0, 100.0))
		_check(_main.breakables.debris.size() == debris + 1 and _main.breakables._broken.has(k),
				"a round knocks a breakable prop over (%s)" % props.data.describe(k).get("model", "?"))
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("ALL GUN CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
