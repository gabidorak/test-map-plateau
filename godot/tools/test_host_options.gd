extends SceneTree
## Headless checks of the host's options (game.gd set_bot_traffic, clear_vehicles; scripts/pause_menu.gd), solo:
## - the in-game menu shows them; its Bot traffic button switches the bots off: none left on the map, the parked cars
##   stay, the car the player drives too, with the player in it;
## - back on, the lines and the bot cars are there again;
## - Clear all vehicles (pressed twice) takes every vehicle off the map, the player out of the one driven first, and the
##   bots come back at once; a few seconds on nothing has broken.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_host_options.gd

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "10")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _bots() -> int:
	return _main.cars.filter(func(c: Node) -> bool: return c.is_bot()).size()


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	await _frames(30)
	var parked: Array = _main.cars.filter(func(c: Node) -> bool: return not c.is_bot())
	_check(parked.size() == 4 and _bots() > 10, "solo: %d parked cars, %d bots" % [parked.size(), _bots()])
	var car: Node = parked[2]
	_main.player.teleport(car.global_position + car.global_basis.x * 2.5)
	await _frames(2)
	_main.enter_car(car)
	await _frames(5)
	_check(_main.driving == car, "driving a parked car")

	# the menu's Bot traffic button
	var pause: Node = _main.pause
	_main.set_pause_open(true)
	await process_frame
	_check(pause._host_box.visible and pause._traffic.text.ends_with("on"), "the in-game menu shows the host's options")
	pause._traffic.pressed.emit()
	await _frames(5)
	_check(not _main.bus_bots and _main.traffic.bots.is_empty() and _bots() == 0, "Bot traffic off: no bots on the map")
	_check(_main.cars.size() == 4 and _main.driving == car, "the parked cars stay, the player still drives")
	_main.set_pause_open(false)
	await _frames(120)
	_check(_bots() == 0, "still none 2 s on")
	_main.set_pause_open(true)
	await process_frame
	_check(pause._traffic.text.ends_with("off"), "the button says it is off")
	pause._traffic.pressed.emit()
	await _frames(30)
	_check(_main.bus_bots and _bots() > 10, "Bot traffic on again: %d bots" % _bots())

	# Clear all vehicles
	pause._clear.pressed.emit()
	await _frames(2)
	_check(_main.cars.size() > 4, "one press only asks again")
	pause._clear.pressed.emit()
	await _frames(2)
	_check(_main.driving == null and not is_instance_valid(car),
			"cleared: the player got out first, the car is gone")
	_check(_main.cars.all(func(c: Node) -> bool: return c.is_bot()) and _bots() > 10,
			"only the bots, back at once (%d)" % _bots())
	_main.set_pause_open(false)
	_main.set_bot_traffic(false)
	_main.clear_vehicles()
	await _frames(2)
	_check(_main.cars.is_empty(), "traffic off and cleared: the map is empty")
	_main.spawn_car_near_player()
	await _frames(240)
	_check(_main.cars.size() == 1 and _main.player.active, "a car parked again, all quiet 4 s on")
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
