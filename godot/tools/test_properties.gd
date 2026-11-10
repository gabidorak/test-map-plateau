extends "res://tools/test_base.gd"
## PTA Online's properties, step 1 (ONLINE_MILESTONES.md O9; scripts/online/properties.gd): played in the offline test
## (--online-test). The studio of the Logements de l'X 19 is where its building's windows are; at its entrance the
## panel sells it (refused when too poor), then the player goes in: the interior is built behind the two windows, the
## player stands in its hall and stays on its floor; nothing solid between the room and the outside through the
## windows, nor through the wide doorway between the room and the hall; E by the flat's door takes them back to the
## entrance and the interior goes. The residents' car park lets only residents get a vehicle out; the garage option
## (+10 000 €) puts a lift in the hall: E by it, a vehicle picked comes out at the residents' car park with the player
## at the wheel. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_properties.gd -- --online-test

const LogX = preload("res://scripts/builder/logements_x_builder.gd")
const Studio = preload("res://scripts/online/studio_builder.gd")
const Layers = preload("res://scripts/physics_layers.gd")

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


## Whether `car` stands on one of garage `g`'s bays.
func _on_a_bay(car: Node3D, g: Dictionary) -> bool:
	for bay: Dictionary in g["bays"]:
		var l: Vector3 = (bay["xf"] as Transform3D).affine_inverse() * car.global_position
		if absf(l.x) < bay["w"] * 0.5 and absf(l.z) < bay["l"] * 0.5 and absf(l.y) < 2.0:
			return true
	return false


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
	_check(props.list.size() == 2, "two properties: the studio, the villa (%d)" % props.list.size())
	var p: Dictionary = props.get_property("logx-19-studio")
	_check(p["id"] == "logx-19-studio" and p["price"] == 50000 and p["garage_price"] == 10000,
			"the studio of the Logements de l'X 19, 50 000 €, its garage 10 000 €")

	# where it is: the windows are the building's, the flat inside the building's upper body; twice the first one
	var rail: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/rail.json"))
	var pl: Dictionary = {}
	for q: Dictionary in rail["logements_x"]["plots"]:
		if q["num"] == "19":
			pl = q
	var lv := LogX.floor_levels(pl, rail["logements_x"]["dims"], 3)
	var frame: Transform3D = p["frame"]
	_check(absf(frame.origin.y - float(lv[0])) < 0.01, "on the 3rd floor (y %.2f)" % frame.origin.y)
	var wins: Array = p["windows"]
	_check(wins.size() == 2, "behind a pair of windows")
	for w: Array in wins:
		_check(absf(float(w[1]) - float(w[0]) - LogX.WIN_W) < 0.01 and float(w[0]) > 0.3 and float(w[1]) < Studio.ROOM_W - 0.3,
				"a window %.2f-%.2f m along the room's front wall" % [w[0], w[1]])
	var ring: Array = pl["ring"]
	var poly := PackedVector2Array()
	for q: Array in ring:
		poly.append(Vector2(q[0], q[1]))
	var inside_body := true
	var far := Vector3(Studio.END_X + 0.1, 0, Studio.BACK + 0.1)
	for c: Vector3 in [Vector3(-0.12, 0, 0.3), Vector3(far.x, 0, 0.3), Vector3(-0.12, 0, far.z), far]:
		var g := frame * c
		inside_body = inside_body and Geometry2D.is_point_in_polygon(Vector2(g.x, -g.z), poly)
	_check(inside_body, "the flat lies inside the building")
	var area := Studio.END_X * (Studio.BACK - Studio.WALL_IN)
	_check(area > 45.0, "a roomy flat: %.0f m²" % area)

	# the residents' car park: a terminal and bays, residents only
	var res: Dictionary = m.garages.get_garage(props.RESIDENTS_ID)
	_check(not res.is_empty() and res["bays"].size() == 4, "the residents' car park: a terminal, 4 bays")
	var car_entry := {}
	for v: Dictionary in m.test_garage:
		if v["model"] == "sedan":
			car_entry = v
	m.to_garage(res["xy"], ["residence"])
	await _frames(5)
	_check(m.terminal_at_hand().get("id", "") == props.RESIDENTS_ID, "by its terminal")
	_check(m.prompt_text().contains("residents only"), "the prompt: %s" % m.prompt_text())
	_check(m.spawn_for(m.me(), props.RESIDENTS_ID, car_entry["id"], "sedan").begins_with("Residents only"),
			"no vehicle out for a non-resident")

	# the entrance and the panel
	props.go_to(p["id"])
	await _frames(5)
	_check(not props.door_at_hand().is_empty(), "by the building's entrance")
	_check(props.prompt().contains("for sale"), "the prompt: %s" % props.prompt())
	_check(not props.enter(p["id"]), "not let in before buying it")
	props.open_panel(p["id"])
	_check(props.ui_open() and m.ui_open(), "E: the panel")
	m.test_money = 1000
	_main.economy.balance = 1000
	props.buy(p["id"])
	_check(not props.is_owned(p["id"]) and m.test_money == 1000, "refused with 1 000 €")
	m.refill()
	props.buy(p["id"])
	_check(props.is_owned(p["id"]) and not props.has_garage(p["id"]) and m.test_money == m.TEST_MONEY - 50000,
			"bought without the garage: %d € left" % m.test_money)
	_check(props.prompt().contains("your home"), "the prompt now: %s" % props.prompt())

	# in
	_check(props.enter(p["id"]), "goes in")
	_check(not props.ui_open(), "the panel closed")
	await _frames(60)
	var flat: Node3D = props.interior
	_check(flat != null and props.inside == p["id"], "the interior is built")
	if flat == null:
		quit(1)
		return
	var local: Vector3 = flat.transform.affine_inverse() * _main.player.global_position
	_check(local.y > -0.05 and local.y < 0.3 and local.x > Studio.HALL_X and local.x < Studio.END_X,
			"standing in the hall (%s)" % local)
	_check(props.exit_at_hand(), "by the flat's door")
	_check(not flat.has_meta("lift") and not props.lift_at_hand(), "no garage lift without the option")
	_check(props.where.get(m.me(), "") == props.instance(p["id"], props.my_name()), "the host knows we're in our flat")
	# nothing solid between the room and the outside through each window
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for w: Array in wins:
		var mid := Vector3((float(w[0]) + float(w[1])) * 0.5, 1.5, 0)
		var q := PhysicsRayQueryParameters3D.create(frame * (mid + Vector3(0, 0, 1.0)), frame * (mid + Vector3(0, 0, -8.0)),
				Layers.SOLID)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		_check(hit.is_empty() or (frame.affine_inverse() * (hit["position"] as Vector3)).z < -1.0,
				"a clear view out of the window at x %.1f" % mid.x)
	# the doorway between the room and the hall: wide open
	for z: float in [Studio.DOORWAY.x + 0.25, Studio.DOORWAY.y - 0.25]:
		var q := PhysicsRayQueryParameters3D.create(frame * Vector3(Studio.ROOM_W - 1.0, 1.0, z),
				frame * Vector3(Studio.HALL_X + 1.0, 1.0, z), Layers.SOLID)
		_check(space.intersect_ray(q).is_empty(), "walk through the doorway to the hall at z %.2f" % z)
	# the walls hold: a ray from the room to the side wall stops on it
	var q2 := PhysicsRayQueryParameters3D.create(frame * Vector3(1.0, 1.5, 2.0), frame * Vector3(-3.0, 1.5, 2.0), Layers.SOLID)
	_check(not space.intersect_ray(q2).is_empty(), "the left wall is solid")
	_check(flat.get_node_or_null("Daylight") != null, "daylight in from the windows")

	# out
	_main.player.teleport(frame * (Studio.EXIT + Vector3(-0.3, -0.95, 0.0)))
	await _frames(3)
	_check(props.exit_at_hand(), "E by the flat's door")
	_check(props.interact(), "E: out")
	await _frames(5)
	_check(props.inside == "" and not is_instance_valid(flat), "the interior is gone")
	_check(not props.where.has(m.me()), "the host knows we're out")
	props.set_door(p["id"], true)
	_check(props.door_open(p["id"]) and props.visits(p["id"]).is_empty(), "our door open to visitors (no one else's)")
	props.set_door(p["id"], false)
	_check(not props.door_open(p["id"]), "locked again")
	_check(not props.door_at_hand().is_empty(), "back at the entrance")

	# a resident now: a vehicle out at the residents' car park
	m.to_garage(res["xy"], ["residence"])
	await _frames(5)
	_check(m.prompt_text().contains("your vehicles"), "the residents' terminal: %s" % m.prompt_text())
	var problem: String = m.spawn_for(m.me(), props.RESIDENTS_ID, car_entry["id"], "sedan")
	_check(problem == "", "a resident's car out (%s)" % problem)
	await _frames(10)
	var first: Node3D = m.car_of(m.mine)
	_check(first != null and _on_a_bay(first, res), "on a residents' bay")

	# the garage option: a lift in the hall, leaving by car
	props.go_to(p["id"])
	await _frames(5)
	props.open_panel(p["id"])
	props.buy(p["id"], true)
	_check(props.has_garage(p["id"]) and m.test_money == m.TEST_MONEY - 60000,
			"the garage added: %d € left" % m.test_money)
	props.close_panel()
	_check(props.enter(p["id"]), "in again")
	await _frames(30)
	flat = props.interior
	_check(flat != null and flat.has_meta("lift"), "the lift in the hall")
	_main.player.teleport(frame * (Studio.LIFT + Vector3(-0.3, -0.95, 0.0)))
	await _frames(3)
	_check(props.lift_at_hand() and props.prompt().contains("leave by car"), "by the lift: %s" % props.prompt())
	_check(props.interact() and m.ui_open(), "E: the garage's vehicles")
	m._h_spawn(props.garage_id(p["id"]), int(car_entry["id"]), "sedan")
	var drove := await _until(func() -> bool: return _main.driving != null, 5.0)
	_check(drove and props.inside == "" and not m.ui_open(), "down the lift, at the wheel")
	if drove:
		_check(_on_a_bay(_main.driving, res), "at the residents' car park")
		_check(_main.driving.net_id == m.mine, "in one's own car")

	# taken away by the in-game menu: the interior goes too
	props.enter(p["id"])
	await _frames(5)
	m.to_garage(Vector2(764, -333))
	await _frames(5)
	_check(props.inside == "", "taken to a garage: out of the flat")

	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
