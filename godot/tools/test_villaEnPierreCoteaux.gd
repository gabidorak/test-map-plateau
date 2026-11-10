extends SceneTree
## Villa de charme (scripts/villaEnPierreCoteaux/, scripts/online/properties.gd) in the PTA Online test (--online-test): the map's
## buildings gone from its grounds, its gate shut to a passer-by (put back outside when found in), the plaque for
## sale; bought (5 M €, its garage with it); its owner let in at the gate, which opens; walking the grand stair up to
## the landing and on to the first floor, the hall's void (no floor over it); a car out in its garage on a bay, the
## garage's doors rising; the owner out once they have left the grounds. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_villaEnPierreCoteaux.gd -- --online-test

const House = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_house.gd")
const Layers = preload("res://scripts/physics_layers.gd")

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Walks the player `frames` physics frames towards `facing` (the villa's frame): its height then.
func _walk(v: Node, from: Vector3, facing: Vector3, frames: int) -> float:
	var f: Transform3D = v.frame
	var dir := f.basis * facing
	_main.player.teleport(f * from, atan2(-dir.x, -dir.z))
	await _frames(5)
	Input.action_press("move_forward")
	var top := -INF
	for i in frames:
		await physics_frame
		top = maxf(top, (f.affine_inverse() * _main.player.global_position).y)
	Input.action_release("move_forward")
	return top


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
	var props: Node = m.properties
	var v: Node = _main.villaEnPierreCoteaux
	_check(v != null and v.site != null, "the villa is there")
	var p: Dictionary = props.get_villa()
	_check(not p.is_empty() and int(p["price"]) == 5000000, "for sale: %s" % str(p.get("price", "?")))
	_check(str(v._plaque.text).contains("FOR SALE"), "its plaque: %s" % v._plaque.text.replace("\n", " "))
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	# the map's buildings gone from the grounds
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(v.frame * Vector3(5.0, 30.0, 45.0),
			v.frame * Vector3(5.0, -10.0, 45.0)))
	var what: Dictionary = hit.get("collider").get_meta("plateau", {}) if not hit.is_empty() and hit.get("collider") else {}
	_check(not hit.is_empty() and str(what.get("type", "")) != "building", "no old building on the lawn (%s)" % str(what.get("type", "ground")))

	# a passer-by: the gate stays shut, inside the wall they are put back outside
	props.go_to(p["id"])
	await _frames(60)
	_check(not props.door_at_hand().is_empty(), "by the plaque: %s" % m.prompt_text())
	_check(v.gate_open < 0.05, "the gate stays shut")
	_main.player.teleport(v.frame * Vector3(20.0, 0.3, -6.0))
	await _frames(90)
	_check(not v.in_grounds(_main.player.global_position), "a passer-by put back outside the gate")

	# bought: the owner let in at the gate, which opens
	var before: int = m.test_money
	props.open_panel(p["id"])
	props.buy(p["id"])
	props.close_panel()
	_check(props.is_owned(p["id"]) and props.has_garage(p["id"]) and m.test_money == before - 5000000,
			"bought, its garage with it: %d € left" % m.test_money)
	_check(str(v._plaque.text).contains("YOUR HOME"), "the plaque: %s" % v._plaque.text.replace("\n", " "))
	await _frames(30)
	_check(props.inside == p["id"], "let in at the gate")
	var opened := await _until(func() -> bool: return v.gate_open > 0.95, 6.0)
	_check(opened, "the gate opened (%.2f)" % v.gate_open)
	_check(v._gate_shape.disabled, "open: one can go through")
	# walked in from the road through the gate, onto the drive (no step)
	var gl: Array = v.gate_local()
	var outside: Vector2 = (gl[0] as Vector2) - (gl[2] as Vector2) * 4.0
	var inward: Vector2 = gl[2]
	var gy: float = (v.frame.affine_inverse() * v.gate_point()).y
	await _walk(v, Vector3(outside.x, gy + 0.3, outside.y), Vector3(inward.x, 0, inward.y), 150)
	var through: Vector3 = v.frame.affine_inverse() * _main.player.global_position
	_check((Vector2(through.x, through.z) - (gl[0] as Vector2)).dot(inward) > 4.0,
			"walked in through the gate onto the drive (%.1f m in)" % (Vector2(through.x, through.z) - (gl[0] as Vector2)).dot(inward))

	# the grand stair: up the central flight to the landing, then the west flight to the first floor
	var landing := await _walk(v, Vector3(20.0, 0.2, 3.2), Vector3(0, 0, 1), 200)
	_check(landing > House.LANDING - 0.3, "up the central flight to the landing (%.2f m)" % landing)
	var up := await _walk(v, Vector3(20.0, House.LANDING + 0.2, 10.7), Vector3(-1, 0, 0), 180)
	_check(up > House.F1 - 0.2, "up the west flight to the first floor (%.2f m)" % up)
	_check(v.in_grounds(_main.player.global_position), "the owner stays in")
	# out of the pools by their steps
	var water: float = v.site.get_meta("pool_water")
	var pool_out := await _walk(v, Vector3(23.5, water - 1.2, 66.0), Vector3(0, 0, -1), 240)
	_check(pool_out > water, "out of the pool by its steps (%.2f m, the water at %.2f)" % [pool_out, water])
	var indoor_out := await _walk(v, Vector3(6.5, -0.6, 17.2), Vector3(1, 0, 0), 200)
	_check(indoor_out > -0.05, "out of the indoor pool by its steps (%.2f m)" % indoor_out)
	# the hall's void: nothing between its floor and its ceiling over the middle
	var void_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(v.frame * Vector3(20.0, House.CEIL1 - 0.3, 3.0),
			v.frame * Vector3(20.0, 0.5, 3.0), Layers.BUILDINGS))
	_check(void_hit.is_empty(), "no floor over the hall")
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(v.frame * Vector3(5.0, House.CEIL1 - 0.3, 5.0),
			v.frame * Vector3(5.0, 0.5, 5.0), Layers.BUILDINGS))
	_check(not floor_hit.is_empty() and absf((v.frame.affine_inverse() * (floor_hit["position"] as Vector3)).y - House.F1) < 0.05,
			"a first floor over the salon")

	# the garage: a car out on a bay, its doors rising
	_main.player.teleport(v.frame * (House.GARAGE_TERMINAL + Vector3(0.6, 0.2, 0.0)))
	await _frames(10)
	_check(props.villa_garage_at_hand(), "by the garage's terminal: %s" % m.prompt_text())
	var car_entry := {}
	for e: Dictionary in m.test_garage:
		if e["model"] == "sedan":
			car_entry = e
	var gid: String = props.garage_id(p["id"])
	var problem: String = m.spawn_for(m.me(), gid, car_entry["id"], "sedan")
	_check(problem == "", "a car out in the garage (%s)" % problem)
	await _frames(20)
	var car: Node3D = m.car_of(m.mine)
	var on_bay := false
	if car:
		for xf: Transform3D in v.garage_bays():
			var l: Vector3 = xf.affine_inverse() * car.global_position
			on_bay = on_bay or (absf(l.x) < 1.5 and absf(l.z) < 2.8 and absf(l.y) < 2.0)
	_check(on_bay, "on one of its bays")
	var rose := await _until(func() -> bool: return v.garage_open > 0.9, 5.0)
	_check(rose, "the garage's doors rise")

	# out of the grounds: out of the villa
	props.go_to(p["id"])
	_main.player.teleport(_main.player.global_position + v.road_out() * 20.0)
	var out := await _until(func() -> bool: return props.inside == "", 5.0)
	_check(out, "out once gone from the grounds")
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
