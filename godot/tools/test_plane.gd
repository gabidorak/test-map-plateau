extends SceneTree
## Headless checks for the biplane (scripts/plane.gd): parked from the vehicle code, it rests on its three wheels nose
## up; E gets in. Put in the air at cruise speed it holds its height with the keys released, S pulls the nose up, D
## rolls it right, R levels the wings; both upper wing tips leave trails at speed and none once it stops. Shift opens
## the throttle; from the most open heading around it, full throttle takes it off the ground. Its LAN state carries
## the throttle and the control surfaces to a remote copy. Space in the air puts the player on the ground.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_plane.gd
## Without --headless it also saves shots to /tmp/plane_*.png.

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


## Nose-up angle in degrees.
func _pitch(plane: Node3D) -> float:
	return rad_to_deg(asin(clampf(plane.global_basis.z.normalized().y, -1.0, 1.0)))


## Bank to the right in degrees.
func _bank(plane: Node3D) -> float:
	var b: Basis = plane.global_basis.orthonormalized()
	return rad_to_deg(atan2(b.x.y, b.y.y))


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	var plane: VehicleBody3D = _main.spawn_car_near_player("biplane")
	_check(plane != null and plane.get_script() == _main.Biplane, "the vehicle code parks a biplane next to the player")
	if plane == null:
		return _finish()
	await _frames(150)
	var wheels := 0
	for w in plane.find_children("*", "VehicleWheel3D", false, false):
		wheels += int((w as VehicleWheel3D).is_in_contact())
	_check(wheels == 3 and plane.on_ground and _pitch(plane) > 7.0 and _pitch(plane) < 15.0 and absf(_bank(plane)) < 3.0
			and plane.linear_velocity.length() < 0.2, "parked on its 3 wheels, resting on its tail (nose up %.1f°, bank %.1f°, %d wheels down, %.2f m/s)" % [
			_pitch(plane), _bank(plane), wheels, plane.linear_velocity.length()])
	await _shot("plane_parked.png")
	player.teleport(plane.to_global(Vector3(plane.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(2)
	_check(_main.driving == plane, "E gets into the biplane")
	if _main.driving != plane:
		return _finish()
	_key(KEY_SHIFT, true)
	await _frames(90)
	_key(KEY_SHIFT, false)
	_check(plane.lever > 0.95, "Shift opens the throttle (%.2f after 1.5 s)" % plane.lever)
	_check(_main._dash.visible and "km/h" in _main._dash.text and "alt" in _main._dash.text, "the dash shows speed and height")

	# in the air at cruise speed, hands off
	var p0: Vector3 = plane.global_position
	var g := WorldQuery.ground_y(plane.get_world_3d(), p0.x, p0.z, Layers.SOLID)
	var start := Transform3D(Basis(Vector3.UP, plane.global_rotation.y), Vector3(p0.x, g + 120.0, p0.z))
	plane.place(start)
	plane.lever = 0.55
	plane.linear_velocity = start.basis.z * 35.0
	await _frames(240)
	var dy: float = plane.global_position.y - start.origin.y
	var v: float = plane.linear_velocity.length()
	_check(absf(dy) < 25.0 and v > 25.0 and v < 50.0 and absf(_bank(plane)) < 10.0 and not plane.on_ground,
			"hands off at cruise it flies on (%+.1f m in 4 s at %.0f km/h, bank %.1f°, nose %.1f°)" % [dy, v * 3.6, _bank(plane), _pitch(plane)])
	var counts: Array = plane._trails.map(func(t) -> int: return t.point_count())
	_check(counts[0] > 10 and counts[1] > 10, "both upper wing tips leave trails (%s points)" % [counts])
	await _shot("plane_flying.png")
	var nose0 := _pitch(plane)
	_key(KEY_S, true)
	await _frames(40)
	_key(KEY_S, false)
	_check(_pitch(plane) > nose0 + 15.0, "S pulls the nose up (%.1f° -> %.1f°)" % [nose0, _pitch(plane)])
	await _frames(60)
	plane._put_back_on_wheels()
	await _frames(5)
	_key(KEY_D, true)
	await _frames(25)
	_key(KEY_D, false)
	var bank := _bank(plane)
	_check(bank > 30.0, "D rolls it right (bank %.1f°)" % bank)
	await _frames(30)
	await _shot("plane_bank.png")
	_key(KEY_R, true)
	_key(KEY_R, false)
	await _frames(2)
	_check(absf(_bank(plane)) < 2.0 and plane.linear_velocity.length() > 20.0, "R levels the wings (bank %.1f°)" % _bank(plane))

	# from the ground: the most open heading around, full throttle, a little back pressure once rolling
	plane.place(_runway(plane))
	plane.lever = 0.0
	await _frames(120)
	var counts_still: Array = plane._trails.map(func(t) -> int: return t.point_count())
	_check(counts_still[0] == 0 and counts_still[1] == 0, "no trails once stopped (%s points)" % [counts_still])
	var ground0: Vector3 = plane.global_position
	_key(KEY_SHIFT, true)
	var took_off := -1.0
	var climbed := 0.0
	for i in 900:
		await physics_frame
		if took_off < 0.0:
			_key(KEY_S, plane.speed() > 16.0 and plane.on_ground)    # lift the nose, then let it fly
			if plane.height > 2.0 and not plane.on_ground:
				took_off = i / 60.0
				print("  off the ground after %.1f s, %.0f m, at %.0f km/h" % [took_off, plane.global_position.distance_to(ground0),
						plane.speed() * 3.6])
		elif i / 60.0 > took_off + 3.0:
			climbed = plane.height
			break
	_key(KEY_SHIFT, false)
	_key(KEY_S, false)
	_check(took_off > 0.0 and climbed > 10.0, "full throttle takes it off and it climbs on its own (%.1f m up 3 s later, %.0f km/h)" % [
			climbed, plane.speed() * 3.6])
	await _shot("plane_takeoff.png")

	# LAN: a remote copy follows the state
	var copy: VehicleBody3D = _main.add_net_car("biplane", plane.global_transform.translated(Vector3.UP * 50.0))
	copy.set_remote(true)
	plane.surfaces = Vector3(0.5, -0.25, 1.0)
	var s: Array = plane.net_state()
	copy.apply_net_state(s, s, 1.0)
	_check(copy.surfaces == plane.surfaces and copy.lever == plane.lever and copy.global_transform.is_equal_approx(plane.global_transform),
			"a remote copy takes its pose, throttle and control surfaces from its LAN state")
	_main.cars.erase(copy)
	copy.queue_free()

	# out in the air: down to the ground
	plane.place(start)
	plane.linear_velocity = start.basis.z * 35.0
	await _frames(5)
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	await _frames(30)
	var pg := WorldQuery.ground_y(player.get_world_3d(), player.global_position.x, player.global_position.z, Layers.SOLID,
			player.global_position.y + 1.0)
	_check(_main.driving == null and player.visible and absf(player.global_position.y - pg) < 0.5 and plane.lever == 0.0,
			"Space in the air puts the player on the ground below and cuts the engine (%.1f m above it)" % (player.global_position.y - pg))
	_finish()


## A take-off spot: the grid point and heading with the longest free run for the wingspan (nothing above the ground in
## the way, the ground no steeper than 1.5 % on average, no step over 0.3 m). Placed there, plane frame.
func _runway(plane: VehicleBody3D) -> Transform3D:
	var world := plane.get_world_3d()
	var box := BoxShape3D.new()
	box.size = Vector3(plane.half_extents.x * 2.0 + 1.0, 2.3, 1.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	q.exclude = [plane.get_rid()]
	var space := world.direct_space_state
	var best := [-1.0, Transform3D()]
	for gx in range(-200, 1800, 50):
		for gy in range(-700, 620, 50):
			var g := WorldQuery.ground_y(world, gx, -gy, Layers.SOLID)
			if is_nan(g) or not is_nan(WorldQuery.ground_y(world, gx, -gy, Layers.BUILDINGS)):
				continue
			var p := Vector3(gx, g, -gy)
			for i in 24:
				var a := TAU * i / 24.0
				var dir := Vector3(sin(a), 0.0, cos(a))
				q.transform = Transform3D(Basis(Vector3.UP, a), p + Vector3.UP * 1.5)
				q.motion = dir * 300.0
				var d: float = space.cast_motion(q)[0] * 300.0
				if d <= best[0]:
					continue
				var ok := true
				var last := g
				for k in range(1, int(d / 5.0)):
					var s := p + dir * 5.0 * k
					var h := WorldQuery.ground_y(world, s.x, s.z, Layers.SOLID, g + 30.0)
					if is_nan(h) or absf(h - last) > 0.3 or absf(h - g) > 0.015 * 5.0 * k + 0.3:
						d = 5.0 * (k - 1)
						break
					last = h
				if d > best[0]:
					best = [d, Transform3D(Basis(Vector3.UP, a), p + Vector3.UP * 0.3)]
	print("take-off run: %.0f m free from (%.0f, %.0f) at %.0f°" % [best[0], best[1].origin.x, -best[1].origin.z,
			rad_to_deg(best[1].basis.get_euler().y)])
	return best[1]


func _finish() -> void:
	if _failures.is_empty():
		print("ALL PLANE CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
