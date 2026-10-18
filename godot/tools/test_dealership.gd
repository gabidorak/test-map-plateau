extends SceneTree
## Headless checks for the car dealership in the Institut d'Optique (world/interiors.json, builder/interior_builder.gd,
## scripts/dealership.gd, scripts/salesman.gd): its display cars stand still and upright on their podiums; the showroom
## floor, glass walls and ceiling collide; the player walks in up the main door's ramp; the salesman greets them, walks
## up to them and pitches the car they stand by; a display car drives off its podium and out of the main door (the
## salesman protests); clearing the map puts the display cars back.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_dealership.gd

const Layers = preload("res://scripts/physics_layers.gd")
const Salesman = preload("res://scripts/salesman.gd")

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_SHOWROOM", "1")
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


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	return _main.get_world_3d().direct_space_state.intersect_ray(q)


## Spots on display cars (dealership.gd parked): the vehicle near each podium, or null.
func _on_podiums(shop: Node) -> int:
	var n := 0
	for k in shop.cars.size():
		if shop.car_on_spot(k) != null:
			n += 1
	return n


func _run() -> void:
	await _frames(30)
	var shops := get_nodes_in_group("showroom")
	_check(shops.size() == 1, "one showroom in the world")
	if shops.is_empty():
		return _finish()
	var shop: Node = shops[0]
	_check(shop.game == _main and shop.cars.size() >= 10, "it knows the game and has %d display cars" % shop.cars.size())
	await _frames(150)

	# the display cars on their podiums
	var still := 0
	for k in shop.cars.size():
		var car: Node3D = shop.car_on_spot(k)
		var spot: Transform3D = shop.cars[k]["xf"]
		if car == null:
			print("  no car on spot %d (%s)" % [k, shop.cars[k]["model"]])
			continue
		var dy: float = car.global_position.y - spot.origin.y
		if absf(dy) < 0.25 and car.global_basis.y.y > 0.995 and (car as RigidBody3D).linear_velocity.length() < 0.15:
			still += 1
		else:
			print("  %s: %.2f m above its podium, up %.3f, %.2f m/s" % [shop.cars[k]["model"], dy, car.global_basis.y.y,
					(car as RigidBody3D).linear_velocity.length()])
	_check(still == shop.cars.size(), "%d/%d display cars stand still and upright on their podiums" % [still, shop.cars.size()])

	# the showroom collides: floor, glass, ceiling
	var spot0: Transform3D = shop.cars[0]["xf"]
	var mid := spot0.origin + spot0.basis.x * 4.5        # beside the first podium, off it
	var down := _ray(mid + Vector3.UP * 1.5, mid + Vector3.DOWN * 3.0)
	_check(not down.is_empty() and absf(down.position.y - shop.floor_y) < 0.03,
			"the floor is at %.2f (hit %.2f)" % [shop.floor_y, down.position.y if down else NAN])
	var up := _ray(mid + Vector3.UP * 1.5, mid + Vector3.UP * 10.0)
	_check(not up.is_empty() and absf(up.position.y - shop.ceiling_y) < 0.05, "the ceiling is at %.2f" % shop.ceiling_y)
	var out := _ray(mid + Vector3.UP * 1.5, mid + Vector3.UP * 1.5 + spot0.basis.z.slide(Vector3.UP).normalized() * -80.0)
	_check(not out.is_empty() and not shop.is_inside(out.position + (out.position - mid).normalized() * 0.5),
			"a ray out of the showroom stops at its glass wall")

	# the player walks in up the main door's ramp
	var player: CharacterBody3D = _main.player
	var door := _main_door(shop)
	var inward: Vector3 = door[1]
	player.teleport(door[0] - inward * 7.0 + Vector3.UP * 1.0, atan2(-inward.x, -inward.z))
	await _frames(30)
	_check(not shop.is_inside(player.global_position), "the player starts outside")
	player.scripted_input = Vector2(0.0, 1.0)
	var t := 0
	while t < 360 and not shop.is_inside(player.global_position):
		await _frames(1)
		t += 1
	await _frames(40)
	player.scripted_input = null
	_check(shop.is_inside(player.global_position) and absf(player.global_position.y - shop.floor_y) < 0.3,
			"walks in through the main door in %.1f s, on the floor (feet %.2f)" % [t / 60.0, player.global_position.y])

	# the salesman
	var man: Salesman = shop.salesman
	var d0 := man.global_position.distance_to(player.global_position)
	var greeted := false
	for i in 240:
		await _frames(1)
		if man._bubble.visible and shop.dealer in man._bubble.text:
			greeted = true
	_check(greeted, "the salesman greets the player: \"%s\"" % man._bubble.text)
	var d1 := man.global_position.distance_to(player.global_position)
	_check(d1 < d0 - 1.0 or d1 < Salesman.KEEP + 0.6, "walks up to the player (%.1f m -> %.1f m)" % [d0, d1])
	# by a display car (in the south hall: he finds his way through the slot)
	var k := 1
	var spot: Transform3D = shop.cars[k]["xf"]
	player.teleport(spot.origin + spot.basis.z * 4.2 + Vector3.UP * 0.3)
	var pitched := false
	for i in 2400:
		await _frames(1)
		if man._bubble.visible and String(shop.cars[k]["label"]) in man._bubble.text:
			pitched = true
			break
	_check(pitched, "pitches the %s the player stands by: \"%s\"" % [shop.cars[k]["label"], man._bubble.text])
	for i in 2400:
		await _frames(1)
		if man.global_position.distance_to(player.global_position) < Salesman.KEEP + 1.0:
			break
	_check(man.global_position.distance_to(player.global_position) < Salesman.KEEP + 1.0,
			"follows the player into the south hall (%.1f m away)" % man.global_position.distance_to(player.global_position))

	# a test drive: off the podium, out of the main door
	var car: Node3D = shop.car_on_spot(k)
	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(5)
	_check(_main.driving == car, "E gets into the %s" % shop.cars[k]["label"])
	if _main.driving != car:
		return _finish()
	await _frames(30)
	_check(man._drove, "the salesman sees the test drive: \"%s\"" % man._bubble.text)
	car.place(Transform3D(Basis.looking_at(inward, Vector3.UP), door[0] + inward * 6.0 + Vector3.UP * 0.4))
	await _frames(60)
	_key(KEY_W, true)
	var left := false
	var lowest := INF
	for i in 400:
		await _frames(1)
		lowest = minf(lowest, car.global_position.y)
		if not shop.is_inside(car.global_position) and car.global_position.distance_to(door[0]) > 8.0:
			left = true
			break
	_key(KEY_W, false)
	_check(left, "drives out of the main door down its ramp")
	_check(lowest > shop.floor_y - 1.5, "stays on the floor and the ramp (lowest %.2f)" % lowest)
	var cried := false
	for i in 120:
		await _frames(1)
		if man._bubble.visible and man._bubble.text in Salesman.DRIVE_OFF:
			cried = true
	_check(cried, "the salesman cries after the car: \"%s\"" % man._bubble.text)
	_main.exit_car()
	await _frames(10)

	# clearing the map restocks the showroom
	_main.clear_vehicles()
	await _frames(150)
	_check(_on_podiums(shop) == shop.cars.size(), "after clearing the map, %d/%d display cars are back on their podiums" % [
			_on_podiums(shop), shop.cars.size()])
	_finish()


## The main door (the first in interiors.json, the widest here): a point on the floor in the doorway and the
## inward direction, from the outline edge nearest the turntable's south.
func _main_door(shop: Node) -> Array:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/interiors.json"))["osm:w140538734"]
	var at: Array = spec["doors"][0]["at"]
	var p := Vector2(float(at[0]), float(at[1]))
	var o: PackedVector2Array = shop.outline
	var best := 0
	var best_d := INF
	for i in o.size():
		var d := Geometry2D.get_closest_point_to_segment(p, o[i], o[(i + 1) % o.size()]).distance_to(p)
		if d < best_d and o[i].distance_to(o[(i + 1) % o.size()]) > 1.0:
			best_d = d
			best = i
	var e := (o[(best + 1) % o.size()] - o[best]).normalized()
	var inward := Vector2(-e.y, e.x)                    # left of a counter-clockwise ring
	var q := Geometry2D.get_closest_point_to_segment(p, o[best], o[(best + 1) % o.size()])
	return [Vector3(q.x, shop.floor_y, -q.y), Vector3(inward.x, 0.0, -inward.y)]


func _finish() -> void:
	if _failures.is_empty():
		print("ALL DEALERSHIP CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
