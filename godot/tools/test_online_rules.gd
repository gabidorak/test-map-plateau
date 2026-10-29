extends SceneTree
## PTA Online's rules and garages (ONLINE_MILESTONES.md O3, scripts/modes/online_mode.gd). The role is the first
## argument after `--`:
## - `--check`: played solo (PLATEAU_MODE=online, the player's garage PLATEAU_ONLINE_VEHICLES): the mode's rules, every
##   garage's bays (flat, clear, the big vehicles fit somewhere), the player put by a terminal, U not opening the
##   vehicle menu, the terminal's list, getting vehicles out (one at a time, the right garages only, never an armed one,
##   not from afar, not into a taken bay), the jet-ski on the lake, the drive refusals, the map places;
## and the clients of tools/test_online_rules.sh (an official server, two accounts; `--sync=DIR` holds the files they
## wait on each other with):
## - `--owner=TOKEN`: joins, U closed, forges parks of armed vehicles, gets two vehicles out (the second sends the first
##   back), unlocks the second once the other player was refused it, then leaves;
## - `--other=TOKEN`: never sees the forged planes, is refused the locked car, drives it once unlocked, sees it stay
##   while its owner comes back, and leave the map KEEP s after they leave for good;
## - `--back=TOKEN`: the owner again, within KEEP s: the car is theirs again and they stand beside it.
## Exit code 1 on failure.

const Accounts = preload("res://scripts/accounts.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const Marks = preload("res://scripts/race_marks.gd")
const Water = preload("res://scripts/water.gd")
const SOLO_GARAGE := "sedan,taxi,gaz-tiger,bus-idfm,jet-ski,volvo-fh16-trailer,biplane"

var _main: Node
var _mode: Node
var _what := ""
var _arg := ""
var _sync := ""
var _failures: PackedStringArray = []
var _toasts: Array = []                     # every toast shown (lambdas capture by value: an Array)
var _ids := {}                              # a client's garage: model -> vehicle id (from the terminal's list)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["check", "owner", "other", "back"]:
			_what = kv[0]
			_arg = kv[1] if kv.size() > 1 else ""
		elif kv[0] == "sync":
			_sync = kv[1]
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + "[%s] " % _what + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await process_frame
	return true


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _mark(name: String, text := "") -> void:
	var f := FileAccess.open(_sync.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Waits for the other client's file `name`; its text.
func _await_mark(name: String, timeout := 180.0) -> String:
	var path := _sync.path_join(name)
	var there := await _until(func() -> bool: return FileAccess.file_exists(path), timeout)
	_check(there, "the other side got to '%s'" % name)
	return FileAccess.get_file_as_string(path) if there else ""


func _run() -> void:
	match _what:
		"check":
			await _solo()
		"owner":
			await _owner()
		"other":
			await _other()
		"back":
			await _back()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _start(online: bool) -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	if online:
		var joined := await _until(func() -> bool: return _main.mode == "client", 60.0)
		_check(joined and _main.online and _main.mode_id == "online", "joined PTA Online (mode %s)" % _main.mode_id)
		if not joined:
			return
		var logged := await _until(func() -> bool: return _main.economy.username != "", 15.0)
		_check(logged, "logged in as %s" % _main.economy.username)
	else:
		await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 60.0)
	_mode = _main.game_mode
	_main.toast_shown.connect(func(text: String) -> void: _toasts.append(text))
	for i in 5:
		await physics_frame


func _toasted(part: String) -> bool:
	for t: String in _toasts:
		if t.contains(part):
			return true
	return false


## The request at the terminal (online_mode.gd _h_spawn) and the host's answer [ok, text].
func _get_out(gid: String, vehicle: int, model: String) -> Array:
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	_mode.answered.connect(take)
	_mode.to_host(_mode, "_h_spawn", [gid, vehicle, model])
	await _until(func() -> bool: return not got.is_empty(), 10.0)
	_mode.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


func _stand_at(gid: String) -> void:
	var spot: Array = _mode.garages.stand_spot(_mode.garages.get_garage(gid))
	_main.player.set_carrier(null)
	_main.player.teleport(spot[0], spot[1])
	for i in 10:
		await physics_frame


## The id of our `model` in our garage (solo: the made-up account; a client: what the terminal listed), or -1.
func _vehicle_id(model: String) -> int:
	if _main.net.active:
		return _ids.get(model, -1)
	for v: Dictionary in _mode.account(1).get("vehicles", []):
		if v["model"] == model:
			return int(v["id"])
	return -1


func _in_bay(car: Node3D, g: Dictionary) -> bool:
	for bay: Dictionary in g["bays"]:
		var l: Vector3 = (bay["xf"] as Transform3D).affine_inverse() * car.global_position
		if absf(l.x) < bay["w"] * 0.5 and absf(l.z) < bay["l"] * 0.5 + 4.0:
			return true
	return false


# ---------------------------------------------------------------- solo

func _solo() -> void:
	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_ONLINE_VEHICLES", SOLO_GARAGE)
	OS.set_environment("PLATEAU_SHOWROOM", "1")
	await _start(false)
	var m: Node = _mode
	_check(_main.mode_id == "online" and m.has_method("offer"), "playing PTA Online solo")
	for f: String in ["vehicle_menu", "park_car", "clear_vehicles", "debug_cars", "fly_camera", "armed_vehicles"]:
		_check(not _main.allows(f), "no %s" % f)
	for f: String in ["bot_traffic", "trains", "races", "showrooms", "map", "night_toggle"]:
		_check(_main.allows(f), "keeps %s" % f)
	_check(m.KEEP == 30.0, "a left player's vehicle waits 30 s")
	var Car = load("res://scripts/car.gd")
	var armed: Array = Car.MODELS.filter(func(model: String) -> bool: return Car.is_armed(model))
	armed.sort()
	_check(armed == m.ARMED, "the armed models: %s" % str(armed))
	var on_show: Array = []
	for c: Node in _main.cars:
		on_show.append(c.model_name)
	_check(not on_show.is_empty() and not on_show.any(func(model: String) -> bool: return Car.is_armed(model)),
			"Prestige Motors shows no armed vehicle (%d display cars)" % on_show.size())
	_check(not "online" in load("res://scripts/modes/modes.gd").pickable(), "the welcome menu doesn't offer it for solo/LAN")

	# the garages
	var gs: Array = m.garages.list
	var kinds := {}
	for g: Dictionary in gs:
		kinds[g["kind"]] = kinds.get(g["kind"], 0) + 1
	_check(kinds.get("public", 0) >= 8 and kinds.get("depot", 0) == 1 and kinds.get("fire", 0) == 1,
			"garages: %s" % str(kinds))
	var fire: Dictionary = m.garages.get_garage("fire-station")
	_check((fire["terminal"] as Vector3).distance_to(Vector3(830, fire["terminal"].y, 151)) < 40.0,
			"the fire station is by building #1289 (SPIS, (830, −151))")
	var depot: Dictionary = m.garages.get_garage("bus-depot")
	_check(Vector2(depot["xy"]).distance_to(Vector2(4381, 1189)) < 150.0, "the bus depot is by Massy-Palaiseau's bus stop")
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for g: Dictionary in gs:
		var steep := 0.0
		var clear := true
		for bay: Dictionary in g["bays"]:
			var xf: Transform3D = bay["xf"]
			var h0 := xf.origin.y
			for c: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
				var p: Vector3 = xf * (c * Vector3(bay["w"] * 0.5, 0.0, bay["l"] * 0.5))
				steep = maxf(steep, absf(Marks.ground(p.x, -p.z) - h0))
			clear = clear and m.garages.bay_free(bay, [], [])
		_check(steep < 1.0 and clear, "%s: %d bays clear, ground within %.2f m" % [g["id"], g["bays"].size(), steep])
		var t: Vector3 = g["terminal"]
		var q := PhysicsRayQueryParameters3D.create(t + Vector3.UP * 30.0, t + Vector3.UP * 0.2, Layers.BUILDINGS)
		_check(space.intersect_ray(q).is_empty(), "%s: its terminal stands in the open" % g["id"])
	var G = load("res://scripts/online/garages.gd")
	_check(G.any_fits(fire, "fire-truck") and not G.any_fits(fire, "bus-idfm"), "the fire station's bays take the fire truck")
	_check(G.any_fits(depot, "bus-idfm-artic") and G.any_fits(depot, "bus-idfm"), "the depot's bays take both buses")
	var big := 0
	for g: Dictionary in gs:
		if g["kind"] == "public" and G.any_fits(g, "volvo-fh16-trailer") and G.any_fits(g, "biplane"):
			big += 1
	_check(big >= 3, "%d public garages take the truck with its trailer and the biplane" % big)

	# where the player starts
	var near: Dictionary = m.garages.terminal_near(_main.player.global_position, m.REACH)
	_check(not near.is_empty(), "the player starts at a garage terminal (%s)" % near.get("name", "none"))
	var start := Vector2(_main.spawn_xy)
	_check(Vector2(near.get("xy", Vector2.INF)).distance_to(start) < 500.0, "...within 500 m of the spawn point")

	# U: no vehicle menu
	_press("vehicle_menu")
	await process_frame
	await process_frame
	_check(not _main._menu.visible, "U doesn't open the vehicle menu")
	_check(m.ui_open() and _main.ui_open() and not _main.player.active, "U opens our vehicle's panel (the player stands still)")
	_press("vehicle_menu")
	await process_frame
	_check(not m.ui_open() and _main.player.active, "U again closes it")

	# the terminal's list
	_press("interact")
	await _until(func() -> bool: return m._panel.rows.get_child_count() > 0, 5.0)
	var shown := {}
	for row in m._panel.rows.get_children():
		shown[row.name] = not (row.get_node("Get") as Button).disabled
	_check(shown.get("Vehicle_%d_sedan" % _vehicle_id("sedan"), false), "E at the terminal lists the sedan, ready")
	_check(shown.has("Vehicle_%d_gaz-tiger" % _vehicle_id("gaz-tiger")) \
			and not shown["Vehicle_%d_gaz-tiger" % _vehicle_id("gaz-tiger")], "the GAZ Tiger listed but greyed (armed)")
	_check(not shown.get("Vehicle_%d_bus-idfm" % _vehicle_id("bus-idfm"), true), "the bus greyed (bus depot)")
	_check(not shown.has("Vehicle_0_bus-idfm"), "a public garage lends no bus")

	# getting vehicles out
	var gid: String = near["id"]
	(m._panel.rows.get_node("Vehicle_%d_sedan" % _vehicle_id("sedan")).get_node("Get") as Button).pressed.emit()
	await _until(func() -> bool: return m.mine != "", 5.0)
	var sedan: Node3D = m.car_of(m.mine)
	_check(sedan != null and sedan.model_name == "sedan" and _in_bay(sedan, near), "the sedan comes out on a bay")
	_check(not m.ui_open(), "the panel closes once it's out")
	_check(m.vehicles.get(m.mine, {}).get("locked", false), "it comes out locked")
	var r: Array = await _get_out(gid, _vehicle_id("taxi"), "taxi")
	var taxi: Node3D = m.car_of(m.mine)
	_check(r[0] and taxi != null and taxi.model_name == "taxi", "the taxi comes out (%s)" % r[1])
	await process_frame
	_check(not is_instance_valid(sedan) or not sedan in _main.cars, "...and the sedan went back")
	r = await _get_out(gid, _vehicle_id("gaz-tiger"), "gaz-tiger")
	_check(not r[0] and r[1].contains("Armed"), "the GAZ Tiger refused: %s" % r[1])
	r = await _get_out(gid, 0, "biplane-armed")
	_check(not r[0] and r[1].contains("Armed"), "a lent armed biplane refused: %s" % r[1])
	r = await _get_out(gid, 99, "audi-r8")
	_check(not r[0] and r[1].contains("isn't in your garage"), "an R8 we don't own refused: %s" % r[1])
	r = await _get_out(gid, 0, "bus-idfm")
	_check(not r[0], "no lent bus at a public garage: %s" % r[1])
	r = await _get_out(gid, _vehicle_id("bus-idfm"), "bus-idfm")
	_check(not r[0] and r[1].contains("bus depot"), "our bus only at the bus depot: %s" % r[1])
	_main.player.teleport(_main.player.global_position + Vector3(40, 0, 0))
	await physics_frame
	r = await _get_out(gid, _vehicle_id("sedan"), "sedan")
	_check(not r[0] and r[1].contains("Walk up"), "not from 40 m away: %s" % r[1])
	_check(m.car_of(m.mine) == taxi, "...and the taxi stays out")

	# a full garage
	await _stand_at(gid)
	var parked := []
	for bay: Dictionary in near["bays"]:
		parked.append(_main.park_vehicle("van", bay["xf"]))
	for i in 3:
		await physics_frame
	r = await _get_out(gid, _vehicle_id("sedan"), "sedan")
	_check(not r[0] and r[1].contains("taken"), "every bay taken: %s" % r[1])
	_main.remove_vehicles(parked)

	# the bus depot and the fire station
	await _stand_at("bus-depot")
	r = await _get_out("bus-depot", 0, "bus-idfm-artic")
	var bus: Node3D = m.car_of(m.mine)
	_check(r[0] and bus != null and bus.model_name == "bus-idfm-artic" and _in_bay(bus, depot),
			"the depot lends an articulated bus (%s)" % r[1])
	_check(not is_instance_valid(taxi) or not taxi in _main.cars, "...and the taxi went back")
	r = await _get_out("bus-depot", _vehicle_id("sedan"), "sedan")
	_check(not r[0], "no sedan at the depot: %s" % r[1])
	await _stand_at("fire-station")
	r = await _get_out("fire-station", 0, "fire-truck")
	var truck: Node3D = m.car_of(m.mine)
	_check(r[0] and truck != null and truck.model_name == "fire-truck" and _in_bay(truck, fire),
			"the fire station lends a fire truck (%s)" % r[1])

	# the jet-ski on the lake, the big ones in the big bay
	await _stand_at("x-lake")
	r = await _get_out("x-lake", _vehicle_id("jet-ski"), "jet-ski")
	var ski: Node3D = m.car_of(m.mine)
	_check(r[0] and ski != null and absf(Water.depth_at(ski.global_position)) < 1.0, "the jet-ski comes out on the lake (%s)" % r[1])
	r = await _get_out("x-lake", _vehicle_id("volvo-fh16-trailer"), "volvo-fh16-trailer")
	var lorry: Node3D = m.car_of(m.mine)
	_check(r[0] and lorry != null and _in_bay(lorry, m.garages.get_garage("x-lake")), "the truck with its trailer fits the big bay (%s)" % r[1])
	await _stand_at("telecom")
	r = await _get_out("telecom", _vehicle_id("biplane"), "biplane")
	_check(not r[0] and r[1].contains("Too big"), "no biplane at a garage without a big bay: %s" % r[1])

	# drive refusals (the host's: net.gd _ask_drive asks the mode)
	var id: String = m.mine
	_check(not m.refuse_drive(id, 1), "we may drive our own")
	m.vehicles[id]["account"] = 77
	m.vehicles[id]["owner"] = "Someone"
	_check(m.refuse_drive(id, 1) and _toasted("Someone's"), "someone else's locked one: refused")
	m.vehicles[id]["locked"] = false
	_check(not m.refuse_drive(id, 1), "...unlocked: allowed")
	m.vehicles[id]["account"] = 0
	var display: Node3D = null
	for s in root.get_tree().get_nodes_in_group("showroom"):
		for c in s.parked:
			if is_instance_valid(c):
				display = c
	_check(display != null and m.refuse_drive(display.net_id, 1) or display == null, "Prestige Motors' display cars: refused")

	# maps, the in-game menu
	var places: Array = _main.map_places()
	var by_kind := {}
	for p: Array in places:
		by_kind[p[1]] = by_kind.get(p[1], 0) + 1
	_check(by_kind.get("garage", 0) == kinds["public"] and by_kind.get("depot", 0) == 1 and by_kind.get("fire", 0) == 1 \
			and by_kind.get("shop", 0) == 1, "map places: %s" % str(by_kind))
	_main.player.teleport(Vector3(500, 30, 100))
	var back: Array = m.player_actions()
	_check(back.size() == 1, "the in-game menu: %s" % (back[0][0] if back.size() > 0 else "nothing"))
	if back.size() > 0:
		back[0][1].call()
		await physics_frame
		_check(not m.garages.terminal_near(_main.player.global_position, m.REACH).is_empty(), "...takes us to a garage terminal")


# ---------------------------------------------------------------- official server

func _join(token: String, username: String) -> void:
	Accounts.keep(token, username, false)
	await _start(true)


func _owner() -> void:
	await _join(_arg, "Owner_1")
	if _mode == null:
		return
	var m: Node = _mode
	await _until(func() -> bool: return m._wallet.visible, 5.0)
	_check(m._wallet.text == "5 000 €", "the wallet shows %s" % m._wallet.text)
	_check(not m.garages.terminal_near(_main.player.global_position, m.REACH).is_empty(), "we start at a garage terminal")
	# the terminal's list
	_press("interact")
	await _until(func() -> bool: return m._panel.rows.get_child_count() > 0, 10.0)
	for row in m._panel.rows.get_children():
		var parts: PackedStringArray = str(row.name).split("_", true, 2)
		if parts[1] != "0":
			_ids[parts[2]] = int(parts[1])
	_check(_ids.has("sedan") and _ids.has("taxi") and _ids.has("gaz-tiger") and _ids.has("bus-idfm"),
			"the terminal lists our garage: %s" % str(_ids))
	_press("interact")
	await process_frame
	_check(not m.ui_open(), "E again closes it")
	_press("vehicle_menu")
	await process_frame
	await process_frame
	_check(not _main._menu.visible and m.ui_open(), "U: our vehicle's panel, not the vehicle menu")
	_press("vehicle_menu")
	await process_frame
	# forged parks: a patched client parking armed vehicles itself, and asking the server for them
	var state: Array = _main.cars[0].net_state() if not _main.cars.is_empty() else []
	_check(not state.is_empty(), "a vehicle to copy a state from")
	if not state.is_empty():
		_main.net._spawn_car.rpc("%d:900" % _main.net.me(), "biplane-armed", state)
		_main.net._spawn_car.rpc("%d:901" % _main.net.me(), "gaz-tiger", state)
	_mark("forged")
	var r: Array = await _get_out("telecom", 0, "biplane-armed")
	_check(not r[0] and r[1].contains("Armed"), "the server refuses a lent armed biplane: %s" % r[1])
	r = await _get_out("telecom", _vehicle_id("gaz-tiger"), "gaz-tiger")
	_check(not r[0] and r[1].contains("Armed"), "...and our own GAZ Tiger: %s" % r[1])
	# from afar
	var home: Vector3 = _main.player.global_position
	_main.player.teleport(home + Vector3(40, 0, 0))
	await _wait(1.0)
	r = await _get_out("telecom", _vehicle_id("sedan"), "sedan")
	_check(not r[0] and r[1].contains("Walk up"), "not from 40 m away: %s" % r[1])
	await _stand_at("telecom")
	await _wait(1.0)
	r = await _get_out("telecom", _vehicle_id("sedan"), "sedan")
	await _until(func() -> bool: return m.car_of(m.mine) != null, 5.0)
	var sedan: Node3D = m.car_of(m.mine)
	_check(r[0] and sedan != null and sedan.model_name == "sedan" and _in_bay(sedan, m.garages.get_garage("telecom")),
			"the sedan comes out on a bay (%s)" % r[1])
	var sedan_id: String = m.mine
	r = await _get_out("telecom", _vehicle_id("taxi"), "taxi")
	await _until(func() -> bool: return m.mine != sedan_id and m.car_of(m.mine) != null, 5.0)
	var gone := await _until(func() -> bool: return not _main.net.cars.has(sedan_id), 5.0)
	_check(r[0] and m.car_of(m.mine).model_name == "taxi" and gone, "the taxi comes out, the sedan went back")
	_check(m.vehicles.get(m.mine, {}).get("locked", false), "it is locked")
	_mark("taxi", m.mine)
	await _await_mark("refused")
	m.set_locked(false)
	var open := await _until(func() -> bool: return not m.vehicles.get(m.mine, {}).get("locked", true), 5.0)
	_check(open, "unlocked")
	_mark("unlocked")
	await _await_mark("drove")
	_mark("left")


func _other() -> void:
	await _join(_arg, "Other_1")
	if _mode == null:
		return
	var m: Node = _mode
	await _await_mark("forged")
	await _wait(3.0)
	var armed: Array = _main.cars.filter(func(c: Node) -> bool: return c.model_name in ["biplane-armed", "gaz-tiger"])
	_check(armed.is_empty(), "the forged armed vehicles never appear here")
	var id: String = await _await_mark("taxi")
	await _until(func() -> bool: return _main.net.cars.has(id) and m.vehicles.has(id), 10.0)
	var taxi: Node3D = _main.net.cars.get(id)
	_check(taxi != null and m.vehicles.get(id, {}).get("owner", "") == "Owner_1" and m.vehicles[id]["locked"],
			"we see Owner_1's locked taxi")
	if taxi == null:
		return
	# beside its driver's door, E
	var p: Vector3 = taxi.to_global(Vector3(taxi.half_extents.x + 0.8, 0.0, 0.3))
	_main.player.teleport(Vector3(p.x, Marks.ground(p.x, -p.z) + 0.1, p.z))
	for i in 5:
		await physics_frame
	_check(m.prompt_text().contains("locked"), "the prompt says so: %s" % m.prompt_text())
	_press("interact")
	await _wait(2.0)
	_check(_main.driving == null and _toasted("is locked"), "E: refused, it's locked (%s)" % str(_toasts))
	_mark("refused")
	await _await_mark("unlocked")
	await _until(func() -> bool: return not m.vehicles[id]["locked"], 5.0)
	_press("interact")
	var drove := await _until(func() -> bool: return _main.driving == taxi, 5.0)
	_check(drove, "unlocked: we drive it")
	if drove:
		_main.exit_car()
	await _wait(0.5)
	_mark("drove")
	await _await_mark("left")
	await _wait(3.0)
	_check(_main.net.cars.has(id), "its owner left: the taxi stays meanwhile")
	await _await_mark("back", 120.0)
	_check(_main.net.cars.has(id), "its owner came back: it's still there")
	await _await_mark("left2", 120.0)
	var t0 := Time.get_ticks_msec()
	var gone: bool = await _until(func() -> bool: return not _main.net.cars.has(id), m.KEEP + 15.0)
	var after := (Time.get_ticks_msec() - t0) / 1000.0
	_check(gone and after > m.KEEP - 8.0, "its owner gone for good: it leaves the map %.0f s on" % after)


func _back() -> void:
	var id := FileAccess.get_file_as_string(_sync.path_join("taxi"))
	await _join(_arg, "Owner_1")
	if _mode == null:
		return
	var m: Node = _mode
	var mine := await _until(func() -> bool: return m.mine == id, 15.0)
	_check(mine, "back within %d s: the taxi is ours again" % roundi(m.KEEP))
	var beside := await _until(func() -> bool:
		var c: Node3D = _main.net.cars.get(id)
		return c != null and c.global_position.distance_to(_main.player.global_position) < 6.0, 20.0)
	_check(beside and _toasted("waited for you"), "we stand beside it")
	_mark("back")
	await _wait(1.0)
	_mark("left2")
