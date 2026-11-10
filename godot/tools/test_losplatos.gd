extends "res://tools/test_base.gd"
## Losplatos Custom (scripts/losplatos/, scripts/online/custom_shop.gd), played in the PTA Online test (--online-test):
## building #758 makes way for it (its roof, not the LadHyX's, over its footprint), its roll-up door stays shut with no
## one about and opens for a car coming up (its collision gone), our own car stopped in the service bay gets the
## panel (U), a damaged bodywork is repaired (paid by the damage), a coat of paint is paid and worn, a lent or wrong car
## is refused; the maps mark it. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_losplatos.gd -- --online-test

const Layers = preload("res://scripts/physics_layers.gd")
const Builder = preload("res://scripts/losplatos/losplatos_builder.gd")
const Prices = preload("res://scripts/online/prices.gd")
const Paint = preload("res://scripts/paint.gd")

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started and _main.online_test, "the PTA Online test started")
	if not started:
		quit(1)
		return
	await _frames(5)
	var m: Node = _main.game_mode
	var lp: Node = _main.losplatos
	var custom: Node = m.custom
	_check(lp != null and custom != null, "Losplatos Custom is in the world and in PTA Online")
	var f: Transform3D = lp.frame

	# in place of #758: from above, its own roof
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for c: Vector3 in [Vector3(8, 0, 8), Vector3(21.5, 0, 8), Vector3(29, 0, 3)]:
		var q := PhysicsRayQueryParameters3D.create(f * (c + Vector3(0, 30, 0)), f * (c + Vector3(0, -2, 0)), Layers.SOLID)
		var hit := space.intersect_ray(q)
		var info: Dictionary = hit["collider"].get_meta("plateau", {}) if not hit.is_empty() and hit["collider"] else {}
		_check(info.get("type", "") == "custom_garage", "its roof over %s (%s)" % [c, info.get("type", info.get("name", "nothing"))])
	_check(lp.floor_z >= 1.0, "its floor over the ground: %.2f m" % lp.floor_z)
	# the sidewalk and the ramp: solid, from the road's edge up to the facade
	for c: Vector3 in [Vector3(6.2, 0, -1.3), Vector3(21.3, 0, -1.6), Vector3(21.3, 0, -0.3), Vector3(29.2, 0, -2.4)]:   # (off the paving grid's vertices)
		var q := PhysicsRayQueryParameters3D.create(f * (c + Vector3(0, 5, 0)), f * (c + Vector3(0, -3, 0)), Layers.SOLID)
		var hit := space.intersect_ray(q)
		var info: Dictionary = hit["collider"].get_meta("plateau", {}) if not hit.is_empty() and hit["collider"] else {}
		_check(info.get("type", "") == "custom_garage", "paved at %s (%s)" % [c, hit.get("collider", "nothing")])

	# the door: shut with no one about, open for a car coming up
	m.to_garage(Vector2(764, -333))
	await _frames(40)
	_check(lp.opening < 0.01 and not lp._door_shape.disabled, "the door shut with no one about")
	var res: Dictionary = m.garages.get_garage("telecom") if not m.garages.get_garage("telecom").is_empty() else {}
	m.to_garage(lp.map_xy())
	await _frames(5)
	var car_entry := {}
	for v: Dictionary in m.test_garage:
		if v["model"] == "sedan":
			car_entry = v
	var g: Dictionary = m.garages.nearest(_main.player.global_position)
	m.to_garage(g["xy"])
	await _frames(5)
	var problem: String = m.spawn_for(m.me(), g["id"], car_entry["id"], "sedan")
	_check(problem == "", "our sedan out (%s)" % problem)
	await _frames(10)
	var car: Node3D = m.car_of(m.mine)
	if car == null:
		quit(1)
		return
	car.place(f * Transform3D(Basis.IDENTITY, Vector3(21.5, 0.4, -6.0)).translated_local(-car.extents_center))
	_main.enter_car(car)
	var opened := await _until(func() -> bool: return lp.opening >= 1.0, 6.0)
	_check(opened and lp._door_shape.disabled, "a car coming up: the door rolls up, its collision gone")

	# in the bay
	_check(not custom.at_hand(), "outside: no panel")
	car.place(f * Transform3D(Basis.IDENTITY, Builder.BAY + Vector3(0, 0.4, 0)).translated_local(-car.extents_center))
	await _frames(90)
	_check(lp.in_bay(car.global_position), "the car in the service bay")
	_check(custom.at_hand() and m.prompt_text().contains("repair"), "the prompt: %s" % m.prompt_text())
	var u := InputEventAction.new()
	u.action = "vehicle_menu"
	u.pressed = true
	_check(m.handle_input(u) and custom.ui_open() and m.ui_open(), "U (not E, a turn signal at the wheel): the panel")
	# repair
	_check(custom.fix_price("sedan", car.max_health, car.max_health) == 0, "like new: nothing to repair")
	car.set_health(car.max_health * 0.6)
	var price: int = custom.fix_price("sedan", car.health, car.max_health)
	_check(price >= custom.FIX_MIN and price <= Prices.repair("sedan"), "40 %% damage: %d € (a wreck: %d €)" % [price,
			Prices.repair("sedan")])
	var before: int = m.test_money
	custom.request_fix()
	await _frames(5)
	_check(is_equal_approx(car.health, car.max_health) and m.test_money == before - price,
			"repaired: health %.0f / %.0f, %d € paid" % [car.health, car.max_health, before - m.test_money])
	# paint
	var pal: Array = Paint.palette("sedan")
	var id: String = pal[1][0]
	before = m.test_money
	custom.request_paint(id)
	var painted := await _until(func() -> bool: return car.paint == id, 3.0)
	_check(painted and m.test_money == before - Prices.repaint("sedan"), "painted %s: %d € (a coat %d €)" % [id,
			before - m.test_money, Prices.repaint("sedan")])
	before = m.test_money
	custom.request_paint(id)
	await _frames(5)
	_check(m.test_money == before, "the same colour again: nothing paid")
	custom.close()
	_check(not custom.ui_open(), "closed")

	# out of the bay: refused
	car.place(f * Transform3D(Basis.IDENTITY, Vector3(16.0, 0.4, 12.0)).translated_local(-car.extents_center))
	await _frames(30)
	car.set_health(car.max_health * 0.5)
	before = m.test_money
	var r: Array = await custom.fix_for(m.me(), m.mine)
	_check(not r[0] and m.test_money == before, "out of the bay: refused (%s)" % r[1])

	# on the maps
	var marked := false
	for p: Array in _main.map_places():
		marked = marked or (p[0] == "Losplatos Custom" and p[1] == "custom")
	_check(marked, "on the maps")
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
