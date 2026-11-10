extends "res://tools/test_base.gd"
## The PTA Online test (game.gd online_test, online_mode.gd testing): played solo with --online-test, the mode is PTA
## Online with its rules, plus TEST_MONEY € and a refill, every unarmed vehicle in the garage, the fly camera and the
## in-game menu's trips to the bus depot, the fire station and Prestige Motors. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_online_test.gd -- --online-test

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _action(m: Node, prefix: String) -> Callable:
	for a: Array in m.player_actions():
		if str(a[0]).begins_with(prefix):
			return a[1]
	return Callable()


func _run() -> void:
	_check("online-test" in OS.get_cmdline_user_args() or "--online-test" in OS.get_cmdline_user_args(),
			"run with -- --online-test")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started, "started solo")
	if not started:
		quit(1)
		return
	for i in 5:
		await physics_frame
	var m: Node = _main.game_mode
	_check(_main.online_test and _main.mode_id == "online" and m.testing, "playing the PTA Online test")
	_check(_main.allows("fly_camera"), "the fly camera is allowed")
	for f: String in ["vehicle_menu", "park_car", "clear_vehicles", "debug_cars", "armed_vehicles"]:
		_check(not _main.allows(f), "still no %s" % f)
	_check(_main.economy.balance == m.TEST_MONEY, "the wallet holds %d €" % _main.economy.balance)

	var Car = load("res://scripts/car.gd")
	var models: Array = m.test_garage.map(func(v: Dictionary) -> String: return v["model"])
	var unarmed: Array = Car.MODELS.filter(func(model: String) -> bool: return model not in m.ARMED)
	_check(models == unarmed, "the garage holds every unarmed vehicle (%d)" % models.size())

	# the trips of the in-game menu, and a job's terminal at hand there
	for trip: Array in [["the bus depot", "depot"], ["the fire station", "fire"], ["Prestige Motors", "shop"]]:
		var go := _action(m, "Test: go to %s" % trip[0])
		_check(go.is_valid(), "the in-game menu goes to %s" % trip[0])
		if not go.is_valid():
			continue
		if trip[1] == "fire":
			_main.set_flying(true)
		go.call()
		for i in 5:
			await physics_frame
		var g: Dictionary = m.terminal_at_hand()
		_check(g.get("kind", "") == trip[1] and not _main.flying, "at %s's terminal (%s)" % [trip[0], g.get("id", "none")])

	# a lent fire truck out at the fire station, a bus bought at the depot
	_action(m, "Test: go to the fire station").call()
	for i in 5:
		await physics_frame
	var problem: String = m.spawn_for(m.me(), "fire-station", 0, "fire-truck")
	_check(problem == "", "a fire truck lent at the fire station (%s)" % problem)
	_action(m, "Test: go to the bus depot").call()
	for i in 5:
		await physics_frame
	var before: int = _main.economy.balance
	var bought: Array = await m.shop.buy_for(m.me(), "bus-depot", "bus-idfm")
	_check(bought[0] and _main.economy.balance < before, "a bus bought at the depot: %s (%d € left)" % [bought[1],
			_main.economy.balance])

	# the refill
	m.test_money = 12
	_main.economy.balance = 12
	var refill := _action(m, "Test: refill")
	_check(refill.is_valid(), "the in-game menu refills the wallet")
	if refill.is_valid():
		refill.call()
	_check(_main.economy.balance == m.TEST_MONEY and m.test_money == m.TEST_MONEY, "refilled: %d €" % _main.economy.balance)

	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
