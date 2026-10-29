extends SceneTree
## PTA Online's shop, repairs and colours (ONLINE_MILESTONES.md O4, scripts/online/shop.gd). The role is the first
## argument after `--`:
## - `--check`: played solo (PLATEAU_MODE=online, an empty garage, PLATEAU_ONLINE_MONEY): the price list, the online
##   prices on Prestige Motors' stands, E by a stand (the catalogue), buying the cheapest car with the starting money
##   (out on the shop's bays) and not the next one, crash damage (none from plain driving), a wreck towed back and
##   marked, its repair, paint (the vehicle out repainted, the palette's materials), buying a bus at the depot, forged
##   purchases (from afar, a model not sold there, an armed one);
## and the clients of tools/test_online_shop.sh (an official server, two accounts; `--sync=DIR` holds the files they
## wait on each other with):
## - `--buyer=TOKEN`: buys the cheapest car with the 5 000 € a new account starts with, is refused the next one, forges
##   purchases (from afar, a model not sold there), wrecks the car, earns money (the internal API, PLATEAU_TEST_SECRET),
##   pays its repair, gets it out and paints it;
## - `--watcher=TOKEN`: sees the buyer's car in its new colour;
## - `--forger`: a client with no valid login asking to buy before it is kicked.
## Exit code 1 on failure.

const Accounts = preload("res://scripts/accounts.gd")
const Prices = preload("res://scripts/online/prices.gd")
const Paint = preload("res://scripts/paint.gd")
const Economy = preload("res://scripts/economy.gd")

var Shop: GDScript                          # scripts/online/shop.gd, loaded once the autoloads are there (it uses Settings)

var _main: Node
var _mode: Node
var _what := ""
var _arg := ""
var _sync := ""
var _failures: PackedStringArray = []
var _toasts: Array = []                     # every toast shown (lambdas capture by value: an Array)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["check", "buyer", "watcher", "forger"]:
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


func _await_mark(name: String, timeout := 180.0) -> String:
	var path := _sync.path_join(name)
	var there := await _until(func() -> bool: return FileAccess.file_exists(path), timeout)
	_check(there, "the other side got to '%s'" % name)
	return FileAccess.get_file_as_string(path) if there else ""


func _run() -> void:
	Shop = load("res://scripts/online/shop.gd")
	match _what:
		"check":
			await _solo()
		"buyer":
			await _buyer()
		"watcher":
			await _watcher()
		"forger":
			await _forger()
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


## Calls shop `method` on the host as the panel would, and waits for its answer [ok, text].
func _ask(method: StringName, args: Array) -> Array:
	var shop: Node = _mode.shop
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	shop.answered.connect(take)
	_mode.to_host(shop, method, args)
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	shop.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


## Presses the button `button` of the panel's row `row`, and waits for the shop's answer [ok, text].
func _click(row: String, button: String) -> Array:
	var shop: Node = _mode.shop
	var node: Node = _mode._panel.rows.get_node_or_null(row)
	if node == null or node.get_node_or_null(button) == null:
		_check(false, "the panel has %s/%s (rows: %s)" % [row, button, _rows()])
		return [false, "no button"]
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	shop.answered.connect(take)
	(node.get_node(button) as Button).pressed.emit()
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	shop.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


func _rows() -> String:
	return str(_mode._panel.rows.get_children().map(func(r: Node) -> String: return str(r.name)))


func _stand_at(gid: String) -> void:
	var spot: Array = _mode.garages.stand_spot(_mode.garages.get_garage(gid))
	_main.player.set_carrier(null)
	_main.player.teleport(spot[0], spot[1])
	for i in 10:
		await physics_frame


## Puts the player in front of Prestige Motors' first price stand, facing it.
func _stand_at_shop() -> void:
	var s: Node = root.get_tree().get_nodes_in_group("showroom")[0]
	var xf: Transform3D = s.cars[0]["xf"]
	var p: Vector3 = xf * Vector3(0.0, 0.0, Shop.STAND_OUT + 0.9)
	p.y = s.floor_y + 0.2
	_main.player.set_carrier(null)
	_main.player.teleport(p, xf.basis.get_euler().y)
	for i in 10:
		await physics_frame


## Opens garage `gid`'s panel with E and waits for its list.
func _open_garage(gid: String) -> bool:
	await _stand_at(gid)
	_press("interact")
	return await _until(func() -> bool: return _mode.ui_open() and _mode._panel.kind == "garage" \
			and _mode._panel.rows.get_child_count() > 0, 10.0)


func _close() -> void:
	if _mode.ui_open():
		_mode.close_ui()
	await process_frame


## Our garage vehicle of `model`: {"id", "model", "colour", "wrecked"} as the garage list or the solo account has it.
func _owned(model: String) -> Dictionary:
	if not _main.net.active:
		for v: Dictionary in _mode.test_garage:
			if v["model"] == model:
				return v
		return {}
	for e: Dictionary in _mode._panel.entries:
		if e["model"] == model and int(e["vehicle"]) > 0:
			return {"id": int(e["vehicle"]), "model": model, "colour": e.get("colour", ""), "wrecked":
					str(e["note"]).begins_with("Wrecked"), "repair": int(e.get("repair", 0))}
	return {}


func _surface_paint(car: Node) -> Variant:
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(k) != null:
				return mi.get_surface_override_material(k)
	return null


# ---------------------------------------------------------------- solo

func _solo() -> void:
	var Car = load("res://scripts/car.gd")
	# the price list
	var cheapest := ["", 1 << 30]
	for m: String in Prices.catalogue("prestige"):
		_check(Car.SPECS.has(m) and not Car.is_armed(m), "%s: a real, unarmed model at %s" % [m, Economy.money(Prices.price(m))])
		if Prices.price(m) < cheapest[1]:
			cheapest = [m, Prices.price(m)]
	_check(cheapest == ["kaykit-hatchback", 5000] and Prices.start_money() == 5000,
			"the cheapest car costs the 5 000 € a new account starts with: %s" % str(cheapest))
	_check(Prices.catalogue("depot") == ["bus-idfm", "bus-idfm-artic"] and Prices.catalogue("fire") == ["fire-truck"],
			"the depot sells the buses, the fire station the fire truck")
	_check(Prices.repair("audi-r8") == 4500 and Prices.repair("kaykit-hatchback") == 150, "a repair costs 3 % of the price")
	_check(Prices.repaint("kaykit-hatchback") == 200 and Prices.repaint("audi-r8") == 3000, "a coat: 2 %, at least 200 €")
	for m: String in ["bus-idfm", "fire-truck", "mercedes-1928", "gaz-tiger"]:
		_check(not Paint.can_paint(m), "%s keeps its colours" % m)
	_check(Paint.palette("horse") == Paint.COATS and Paint.can_paint("audi-r8") and Paint.can_paint("jet-ski"),
			"horses get coats, cars paint")

	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_ONLINE_VEHICLES", "")
	OS.set_environment("PLATEAU_ONLINE_TOW", "2")
	OS.set_environment("PLATEAU_SHOWROOM", "1")
	await _start(false)
	var m: Node = _mode
	_check(m.test_money == 5000 and _main.economy.balance == 5000 and m._wallet.text == "5 000 €",
			"we start with %s" % m._wallet.text)

	# Prestige Motors
	var s: Node = root.get_tree().get_nodes_in_group("showroom")[0]
	var stand_text := "%s\n%s" % [Car.display_name("bmw-m4"), Economy.money(Prices.price("bmw-m4"))]
	var labels: Array = s.find_children("*", "Label3D", false, false).map(func(l: Label3D) -> String: return l.text)
	_check(stand_text in labels, "the stands show the online prices (%s)" % stand_text.replace("\n", " "))
	_check(s.cars[0]["price"] == Economy.money(Prices.price(s.cars[0]["model"])), "Jean-Claude quotes them")
	await _stand_at("telecom")
	_check(not m.shop.catalogue_at_hand(), "no catalogue away from Prestige Motors")
	await _stand_at_shop()
	_check(s.is_inside(_main.player.global_position) and m.shop.catalogue_at_hand(), "E by a price stand: the catalogue")
	_check(m.prompt_text().contains("catalogue"), "the prompt says so: %s" % m.prompt_text())
	_press("interact")
	var shown := await _until(func() -> bool: return m.ui_open() and m._panel.kind == "catalogue" \
			and m._panel.rows.get_child_count() > 0, 5.0)
	_check(shown and m._panel.rows.has_node("Buy_kaykit-hatchback") and m._panel.rows.has_node("Buy_audi-r8") \
			and not m._panel.rows.has_node("Buy_gaz-tiger") and not m._panel.rows.has_node("Buy_bus-idfm"),
			"the catalogue lists the cars, not the armed nor the work ones: %s" % _rows())
	var r := await _click("Buy_kaykit-hatchback", "Buy")
	_check(r[0] and m.test_money == 0 and m._wallet.text == "0 €", "bought the hatchback with our 5 000 €: %s" % r[1])
	_check(not m.ui_open(), "the catalogue closed")
	var car: Node = m.car_of(m.mine)
	var delivery: Dictionary = m.garages.get_garage(Shop.DELIVERY)
	_check(car != null and car.model_name == "kaykit-hatchback" and _in_bay(car, delivery),
			"it came out on Prestige Motors' bays")
	r = await _ask("_h_buy", [Shop.PRESTIGE, "horse"])
	_check(not r[0] and r[1].contains("Not enough money") and m.test_money == 0, "too poor for the next one: %s" % r[1])

	# crash damage, the wreck
	for i in 30:
		await physics_frame
	_check(car.crash_damage and not car.repairs_itself and car.health == car.max_health,
			"our car takes crash damage, won't repair itself, and was parked unhurt")
	_main.enter_car(car)
	Input.action_press("throttle")
	await _wait(1.2)
	Input.action_release("throttle")
	Input.action_press("brake")
	await _wait(1.5)
	Input.action_release("brake")
	_check(car.health == car.max_health, "driving and braking hard don't hurt it (%.0f/%.0f)" % [car.health, car.max_health])
	_main.exit_car()
	car._crash_v = Vector3(14.0, 0.0, 0.0)
	car._crash_frame = Engine.get_physics_frames() - 1
	car.linear_velocity = Vector3.ZERO
	car._check_crash()
	_check(car.health < car.max_health and not car.broken, "a knock at 14 m/s hurts (%.0f/%.0f)" % [car.health, car.max_health])
	car.damage(1000.0)
	_check(car.broken, "a big one breaks it")
	var towed := await _until(func() -> bool: return m.mine == "" and not is_instance_valid(car), 6.0)
	_check(towed and _owned("kaykit-hatchback").get("wrecked", false), "towed back, wrecked in our garage")
	_check(_toasted("is wrecked"), "we were told it's wrecked")

	# the repair
	_check(await _open_garage(Shop.DELIVERY), "the delivery bays' terminal opens")
	var id := int(_owned("kaykit-hatchback")["id"])
	var row := "Vehicle_%d_kaykit-hatchback" % id
	_check(m._panel.rows.has_node(row) and (m._panel.rows.get_node(row).get_node("Get") as Button).disabled \
			and m._panel.rows.get_node(row).has_node("Repair"), "wrecked: greyed, with a repair button")
	r = await _click(row, "Repair")
	_check(not r[0] and r[1].contains("Not enough money"), "no repair without money: %s" % r[1])
	m.test_money = 20000
	r = await _click(row, "Repair")
	_check(r[0] and m.test_money == 20000 - 150 and not _owned("kaykit-hatchback")["wrecked"],
			"repaired for 150 €: %s" % r[1])
	await process_frame
	_check(m.ui_open() and m._panel.rows.has_node(row) and not (m._panel.rows.get_node(row).get_node("Get") as Button).disabled,
			"the list shows it ready again")

	# paint
	(m._panel.rows.get_node(row).get_node("Get") as Button).pressed.emit()
	await _until(func() -> bool: return m.mine != "", 5.0)
	car = m.car_of(m.mine)
	var plain: Variant = _surface_paint(car)
	await _open_garage(Shop.DELIVERY)
	(m._panel.rows.get_node(row).get_node("Paint") as Button).pressed.emit()
	await process_frame
	_check(m._panel.view == "paint" and m._panel.swatches.has_node("Colour_red") \
			and (m._panel.swatches.get_node("Colour_own") as Button).disabled, "Paint: the palette, its own colour greyed")
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	m.shop.answered.connect(take)
	(m._panel.swatches.get_node("Colour_red") as Button).pressed.emit()
	await _until(func() -> bool: return not got.is_empty(), 5.0)
	m.shop.answered.disconnect(take)
	await process_frame
	var red: Variant = _surface_paint(car)
	_check(not got.is_empty() and got[0][0] and m.test_money == 20000 - 150 - 200 and car.paint == "red",
			"painted racing red for 200 €: %s" % str(got))
	_check(plain == null and red is BaseMaterial3D and (red as BaseMaterial3D).albedo_texture != null,
			"its body's palette swatch repainted")
	_check(m._panel.view == "list" and _owned("kaykit-hatchback")["colour"] == "red", "back to the list, in red")
	r = await _ask("_h_paint", [Shop.DELIVERY, id, "red"])
	_check(not r[0], "the same colour again: refused (%s)" % r[1])
	r = await _ask("_h_paint", [Shop.DELIVERY, id, "chartreuse"])
	_check(not r[0], "a colour not in the palette: refused (%s)" % r[1])
	await _close()

	# the depot, forged purchases
	await _stand_at("bus-depot")
	r = await _ask("_h_buy", [Shop.PRESTIGE, "audi-r8"])
	_check(not r[0] and r[1].contains("Walk into"), "buying at Prestige Motors from the bus depot: refused (%s)" % r[1])
	r = await _ask("_h_buy", ["bus-depot", "kaykit-hatchback"])
	_check(not r[0] and r[1].contains("isn't sold here"), "a car at the bus depot: refused (%s)" % r[1])
	r = await _ask("_h_buy", ["fire-station", "fire-truck"])
	_check(not r[0] and r[1].contains("Walk up"), "the fire station's truck from the bus depot: refused (%s)" % r[1])
	await _stand_at_shop()
	r = await _ask("_h_buy", [Shop.PRESTIGE, "gaz-tiger"])
	_check(not r[0], "an armed car: refused (%s)" % r[1])
	_check(m.test_money == 19650, "the money didn't move")
	m.test_money = 100000
	_check(await _open_garage("bus-depot") and m._panel.rows.has_node("Buy_bus-idfm"), "the depot's terminal sells buses")
	r = await _click("Buy_bus-idfm", "Buy")
	var bus: Node = m.car_of(m.mine)
	_check(r[0] and m.test_money == 60000 and bus != null and bus.model_name == "bus-idfm" \
			and _in_bay(bus, m.garages.get_garage("bus-depot")), "bought a bus for 40 000 €, out at the depot: %s" % r[1])
	await process_frame
	_check(not is_instance_valid(car), "our car went back")


func _in_bay(car: Node3D, g: Dictionary) -> bool:
	for bay: Dictionary in g["bays"]:
		var l: Vector3 = (bay["xf"] as Transform3D).affine_inverse() * car.global_position
		if absf(l.x) < bay["w"] * 0.5 and absf(l.z) < bay["l"] * 0.5 + 4.0:
			return true
	return false


# ---------------------------------------------------------------- official server

func _join(token: String, username: String) -> void:
	Accounts.keep(token, username, false)
	await _start(true)


## The accounts service's internal API, as the official server (the test's secret).
func _internal(path: String, body: Dictionary) -> Dictionary:
	var secret := OS.get_environment("PLATEAU_TEST_SECRET")
	var a: Node = _main.economy.accounts
	if body.is_empty():
		return await a.server_get(path, secret)
	return await a.server_post(path, body, secret)


func _server_balance() -> int:
	var r := await _internal("/v1/server/who?token=" + _arg.uri_encode(), {})
	return int(r["data"].get("balance", -1)) if r["ok"] else -1


func _buyer() -> void:
	await _join(_arg, "Buyer_1")
	if _mode == null:
		return
	var m: Node = _mode
	await _until(func() -> bool: return m._wallet.visible, 5.0)
	_check(m._wallet.text == "5 000 €", "a new account: %s" % m._wallet.text)
	# forged purchases first, from the garage we start at
	var r := await _ask("_h_buy", [Shop.PRESTIGE, "kaykit-hatchback"])
	_check(not r[0] and r[1].contains("Walk into"), "buying from afar: refused (%s)" % r[1])
	r = await _ask("_h_buy", ["bus-depot", "bus-idfm"])
	_check(not r[0], "a bus from afar: refused (%s)" % r[1])
	await _stand_at_shop()
	r = await _ask("_h_buy", [Shop.PRESTIGE, "police-hatchback"])
	_check(not r[0] and r[1].contains("isn't sold here"), "a model not on sale: refused (%s)" % r[1])
	_check(await _server_balance() == 5000, "the server's wallet didn't move")

	# the catalogue, the cheapest car
	_check(m.shop.catalogue_at_hand(), "E by a price stand: the catalogue")
	_press("interact")
	var shown := await _until(func() -> bool: return m.ui_open() and m._panel.kind == "catalogue" \
			and m._panel.rows.get_child_count() > 0, 10.0)
	_check(shown and m._panel.rows.has_node("Buy_kaykit-hatchback"), "the catalogue came: %s" % _rows())
	r = await _click("Buy_kaykit-hatchback", "Buy")
	_check(r[0] and m._wallet.text == "0 €", "bought the hatchback, %s left: %s (we stand at %s)" % [m._wallet.text, r[1],
			_main.player.global_position])
	var car_ok := await _until(func() -> bool: return m.car_of(m.mine) != null, 10.0)
	var car: Node = m.car_of(m.mine)
	_check(car_ok and car.model_name == "kaykit-hatchback" and _in_bay(car, m.garages.get_garage(Shop.DELIVERY)),
			"out on Prestige Motors' bays")
	r = await _ask("_h_buy", [Shop.PRESTIGE, "horse"])
	_check(not r[0] and r[1].contains("Not enough money"), "too poor for the next one: %s" % r[1])
	_check(await _server_balance() == 0, "the server's wallet: 0 €")

	# the wreck
	_main.player.teleport(car.to_global(car.extents_center + Vector3(car.half_extents.x + 1.0, 0.0, 0.0)))
	await physics_frame
	_main.net.request_drive(car)
	var driving := await _until(func() -> bool: return _main.driving == car \
			and _main.net.owner_of.get(car.net_id, 0) == _main.net.me(), 10.0)
	_check(driving, "got in: we simulate it")
	_check(car.crash_damage and not car.repairs_itself, "our car takes crash damage, won't repair itself")
	car.damage(1000.0)
	_check(car.broken, "wrecked it")
	var told := await _until(func() -> bool: return _toasted("is wrecked"), 10.0)
	_check(told, "the server says it's wrecked")
	var towed := await _until(func() -> bool: return m.mine == "" and not is_instance_valid(car), 15.0)
	_check(towed, "towed back")

	# the repair, with money earned (the internal API stands for a job's pay)
	var who := await _internal("/v1/server/who?token=" + _arg.uri_encode(), {})
	var paid := await _internal("/v1/server/pay", {"account": int(who["data"].get("account", 0)), "amount": 10000,
			"reason": "test pay", "job": "test"})
	_check(paid["ok"], "earned 10 000 €")
	_check(await _open_garage(Shop.DELIVERY), "the delivery bays' terminal")
	await _until(func() -> bool: return m._wallet.text == "10 000 €", 5.0)
	_check(m._wallet.text == "10 000 €", "the wallet followed: %s" % m._wallet.text)
	var v := _owned("kaykit-hatchback")
	_check(v.get("wrecked", false) and v.get("repair", 0) == 150, "listed wrecked, repair 150 €: %s" % str(v))
	var row := "Vehicle_%d_kaykit-hatchback" % int(v.get("id", 0))
	r = await _click(row, "Repair")
	_check(r[0] and await _server_balance() == 9850, "repair charged: %s" % r[1])
	await _until(func() -> bool: return m._panel.rows.has_node(row) \
			and not (m._panel.rows.get_node(row).get_node("Get") as Button).disabled, 5.0)
	(m._panel.rows.get_node(row).get_node("Get") as Button).pressed.emit()
	await _until(func() -> bool: return m.car_of(m.mine) != null, 10.0)
	car = m.car_of(m.mine)
	_check(car != null and car.paint == "", "out again in its own colour")
	await _close()

	# paint it
	await _open_garage(Shop.DELIVERY)
	(m._panel.rows.get_node(row).get_node("Paint") as Button).pressed.emit()
	await process_frame
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	m.shop.answered.connect(take)
	(m._panel.swatches.get_node("Colour_red") as Button).pressed.emit()
	await _until(func() -> bool: return not got.is_empty(), 10.0)
	m.shop.answered.disconnect(take)
	_check(not got.is_empty() and got[0][0], "painted it: %s" % str(got))
	await _until(func() -> bool: return car.paint == "red", 5.0)
	_check(car.paint == "red" and await _server_balance() == 9650, "red here, 200 € charged")
	_mark("painted", car.net_id)
	await _await_mark("seen")
	await _close()


func _watcher() -> void:
	await _join(_arg, "Watcher_1")
	if _mode == null:
		return
	var id := await _await_mark("painted", 300.0)
	var seen := await _until(func() -> bool:
		var c: Node = _mode.car_of(id)
		return c != null and c.paint == "red", 10.0)
	_check(seen, "the buyer's car is red here too")
	_check(seen and _surface_paint(_mode.car_of(id)) != null, "...its body repainted")
	_mark("seen")


func _forger() -> void:
	Accounts.keep("not-a-real-token", "Forger_1", false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var joined := await _until(func() -> bool: return _main.mode == "client" and _main.game_mode != null, 60.0)
	_check(joined, "joined the official server")
	if not joined:
		return
	_mode = _main.game_mode
	var kicked := []
	_main.economy.kicked.connect(func(message: String) -> void: kicked.append(message))
	_mode.to_host(_mode.shop, "_h_buy", [Shop.PRESTIGE, "kaykit-hatchback"])
	_mode.to_host(_mode.shop, "_h_repair", [Shop.DELIVERY, 1])
	_mode.to_host(_mode.shop, "_h_paint", [Shop.DELIVERY, 1, "red"])
	_check(await _until(func() -> bool: return not kicked.is_empty(), 15.0), "kicked: %s" % str(kicked))
