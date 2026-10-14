extends SceneTree
## Headless checks for the horse (scripts/horse.gd): parked from the vehicle code, it stands on its hooves at leg height;
## E gets on. On a flat open strip W canters, Shift gallops, letting go stops it, A turns it on the spot, Space hops.
## Test fences like the map's (prop_placer.gd: 0.12 m boxes on the PROPS layer): one it runs into without jumping
## holds it; jumped from a canter it clears a 1.6 m bar fence and a 2 m mesh fence, not a 3.5 m pitch fence even from a
## gallop. G neighs, its LAN state carries the jump to a remote copy (which animates from its moving pose), shot down
## it lies down and gets up when hosed, E gets off.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_horse.gd
## Without --headless it also saves shots to /tmp/horse_*.png.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const FENCE_AT := 25.0                      # m along the strip from the start

var _main: Node
var _failures: PackedStringArray = []
var _fence_top := 0.0                       # Godot y of the top of the last fence put up


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
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


func _ground(p: Vector3) -> float:
	return WorldQuery.ground_y(_main.get_world_3d(), p.x, p.z, Layers.SOLID, p.y + 2.0)


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	var horse: VehicleBody3D = _main.spawn_car_near_player("horse")
	_check(horse != null and horse.get_script() == _main.Horse, "the vehicle code parks a horse next to the player")
	if horse == null:
		return _finish()
	await _frames(120)
	var gap: float = horse.global_position.y - _ground(horse.global_position)
	_check(absf(gap) < 0.06 and horse.linear_velocity.length() < 0.1 and horse.global_basis.y.y > 0.999 and horse.on_ground,
			"stands on its hooves, upright and still (hooves %.3f m off the ground, %.2f m/s)" % [gap, horse.linear_velocity.length()])
	await _shot("horse_parked.png")
	player.teleport(horse.to_global(Vector3(horse.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	_check(_main.driving == horse and horse._rider.visible, "E gets on the horse, the rider shows")
	if _main.driving != horse:
		return _finish()
	_check(_main._dash.visible and "km/h" in _main._dash.text, "the dash shows its speed and gait")

	var strip := _strip(horse)
	var dir := strip.basis.z
	horse.place(strip)
	await _frames(60)
	# gaits
	_key(KEY_W, true)
	await _frames(180)
	_check(absf(horse.speed() - horse.CANTER) < 0.5 and horse.gait == "canter",
			"W canters (%.1f m/s, %s)" % [horse.speed(), horse.gait])
	await _shot("horse_canter.png")
	_key(KEY_SHIFT, true)
	await _frames(120)
	_check(horse.speed() > horse.GALLOP - 1.0 and horse.gait == "gallop", "Shift gallops (%.1f m/s, %s)" % [horse.speed(), horse.gait])
	await _shot("horse_gallop.png")
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	await _frames(150)
	_check(absf(horse.speed()) < 0.2, "letting go stops it (%.2f m/s after 2.5 s)" % horse.speed())
	var yaw0: float = horse.global_rotation.y
	_key(KEY_A, true)
	await _frames(60)
	_key(KEY_A, false)
	var turned := rad_to_deg(wrapf(horse.global_rotation.y - yaw0, -PI, PI))
	_check(turned > 60.0, "A turns it left on the spot (%.0f° in 1 s)" % turned)
	horse.place(strip)
	await _frames(30)
	var y0: float = horse.global_position.y
	_tap(KEY_SPACE)
	var top := 0.0
	for i in 60:
		await physics_frame
		top = maxf(top, horse.global_position.y - y0)
	await _frames(30)
	_check(top > 0.35 and horse.on_ground and _main.driving == horse,
			"Space hops standing (%.2f m up) and it lands, still ridden" % top)

	# fences (centre FENCE_AT ahead): run into one, jump them
	var bars := _fence(strip, 1.6)
	var r := await _ride_at(horse, strip, false, false)
	_check(r[0] < FENCE_AT - 1.0 and absf(horse.speed()) < 0.5, "without a jump the 1.6 m fence holds it (stopped %.1f m short)" % [
			FENCE_AT - r[0]])
	r = await _ride_at(horse, strip, false, true)
	_check(r[0] > FENCE_AT + 3.0 and r[1] and horse.on_ground and horse.global_basis.y.y > 0.999,
			"jumped from a canter it clears the 1.6 m bar fence (belly %.2f m up over it, %.1f m past it)" % [r[2], r[0] - FENCE_AT])
	bars.free()
	var mesh := _fence(strip, 2.0)
	r = await _ride_at(horse, strip, false, true, "horse_jump.png")
	_check(r[0] > FENCE_AT + 3.0 and r[1], "and the 2 m mesh fence (belly %.2f m up over it, %.1f m past it)" % [r[2], r[0] - FENCE_AT])
	mesh.free()
	var pitch := _fence(strip, 3.5)
	r = await _ride_at(horse, strip, true, true)
	_check(r[0] < FENCE_AT, "a 3.5 m pitch fence holds it even jumped from a gallop (%.1f m short)" % [FENCE_AT - r[0]])
	pitch.free()
	await _frames(2)

	_tap(KEY_G)
	await _frames(2)
	_check(horse.bells == 1, "G neighs")

	# LAN: a remote copy follows the state and animates from its moving pose
	var copy: VehicleBody3D = _main.add_net_car("horse", strip.translated(Vector3(0.0, 0.0, 4.0)))
	copy.set_remote(true)
	horse._airborne = true
	var s: Array = horse.net_state()
	horse._airborne = false
	copy.apply_net_state(s, s, 0.0)
	_check(copy._airborne and copy.global_transform.is_equal_approx(horse.global_transform),
			"a remote copy takes its pose and the jump from its LAN state")
	var at := strip.translated(Vector3(3.0, 0.0, 0.0))
	for i in 90:
		var t0 := at.translated(dir * 7.5 * i / 60.0)
		var st: Array = s.duplicate()
		st[0] = t0
		st[7] = false
		copy.apply_net_state(st, st, 0.0)
		await physics_frame
	_check(copy.gait == "canter" and copy._moving_w > 0.9, "posed moving at 7.5 m/s, the copy canters (%s)" % copy.gait)
	_main.cars.erase(copy)
	copy.queue_free()

	# shot down: lies down, cannot go; hosed: gets up
	horse.place(strip)
	await _frames(30)
	horse.damage(10000.0)
	_key(KEY_W, true)
	await _frames(90)
	_check(horse.broken and horse._down_w > 0.99 and absf(horse.speed()) < 0.2 and "DOWN" in _main._dash.text,
			"shot down it lies down and W does nothing (%.2f m/s)" % horse.speed())
	await _shot("horse_down.png")
	horse.douse(2.1)
	await _frames(60)
	_key(KEY_W, false)
	_check(not horse.broken and horse.speed() > 1.0, "hosed it gets up and goes again (%.1f m/s)" % horse.speed())
	await _frames(60)

	_tap(KEY_E)
	await _frames(5)
	_check(_main.driving == null and player.visible and not horse._rider.visible
			and player.global_position.distance_to(horse.global_position) < 3.0, "E gets off beside it")
	_finish()


## Rides at the fence from the strip start for 6 s: a gallop (Shift) or a canter, jumping (Space) 4 m before it. Returns
## [how far along the strip it got, whether it landed beyond, the belly's lowest height above the fence top while over
## it (NAN when it never was)].
func _ride_at(horse: VehicleBody3D, strip: Transform3D, gallop: bool, jump: bool, shot := "") -> Array:
	horse.place(strip)
	await _frames(30)
	_key(KEY_W, true)
	_key(KEY_SHIFT, gallop)
	var jumped := false
	var clear := INF
	for i in 360:
		await physics_frame
		var along: float = (horse.global_position - strip.origin).dot(strip.basis.z)
		if jump and not jumped and along > FENCE_AT - 4.0:
			_tap(KEY_SPACE)
			jumped = true
		if jumped and absf(along - FENCE_AT) < 1.0:
			clear = minf(clear, horse.global_position.y + 0.84 - _fence_top)
		if shot != "" and jumped and absf(along - FENCE_AT) < 0.3:
			await _shot(shot)
			shot = ""
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	var got: float = (horse.global_position - strip.origin).dot(strip.basis.z)
	await _frames(60)
	return [got, got > FENCE_AT + 1.0 and horse.on_ground, clear if clear < INF else NAN]



## A fence like the map's across the strip, FENCE_AT ahead: `h` tall, 8 m wide, 0.12 m thick, on the PROPS layer.
func _fence(strip: Transform3D, h: float) -> StaticBody3D:
	var p := strip.origin + strip.basis.z * FENCE_AT
	var g := _ground(p)
	_fence_top = g + h
	var body := StaticBody3D.new()
	body.collision_layer = Layers.PROPS
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, h + 0.5, 0.12)
	var cs := CollisionShape3D.new()
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	body.add_child(mi)
	_main.add_child(body)
	body.global_transform = Transform3D(strip.basis, Vector3(p.x, g + h - box.size.y * 0.5, p.z))
	return body


## A strip near the player 50 m long and 3 m wide with nothing on it and flat ground (no step over 0.12 m, within
## 0.5 m of the start): the horse frame at its start.
func _strip(horse: VehicleBody3D) -> Transform3D:
	var world := horse.get_world_3d()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 1.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	q.exclude = [horse.get_rid()]
	var space := world.direct_space_state
	var origin: Vector3 = _main.player.global_position
	var spots := []
	for gx in range(-12, 13):
		for gz in range(-12, 13):
			spots.append(Vector2(gx, gz) * 25.0)
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	for o: Vector2 in spots:
		var g := WorldQuery.ground_y(world, origin.x + o.x, origin.z + o.y, Layers.SOLID)
		if is_nan(g) or not is_nan(WorldQuery.ground_y(world, origin.x + o.x, origin.z + o.y, Layers.BUILDINGS)):
			continue
		var p := Vector3(origin.x + o.x, g, origin.z + o.y)
		for i in 16:
			var a := TAU * i / 16.0
			var d := Vector3(sin(a), 0.0, cos(a))
			q.transform = Transform3D(Basis(Vector3.UP, a), p + Vector3.UP * 1.8)
			q.motion = d * 50.0
			if space.cast_motion(q)[0] < 1.0:
				continue
			var ok := true
			var last := g
			for k in range(1, 26):
				var h := WorldQuery.ground_y(world, p.x + d.x * 2.0 * k, p.z + d.z * 2.0 * k, Layers.SOLID, g + 5.0)
				if is_nan(h) or absf(h - last) > 0.12 or absf(h - g) > 0.5:
					ok = false
					break
				last = h
			if ok:
				print("strip: 50 m from (%.0f, %.0f) at %.0f°" % [p.x, -p.z, rad_to_deg(a)])
				return Transform3D(Basis(Vector3.UP, a), p + Vector3.UP * 0.05)
	_check(false, "a flat open strip near the spawn")
	return Transform3D(Basis(), origin)


func _finish() -> void:
	if _failures.is_empty():
		print("ALL HORSE CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
