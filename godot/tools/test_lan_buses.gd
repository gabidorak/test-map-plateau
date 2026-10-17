extends SceneTree
## Headless check of the bot buses in a LAN game (scripts/traffic.gd, scripts/bus_bot.gd, scripts/net.gd): run it twice
## at once, as the host (which drives the bots) and as a client, with tools/test_lan_buses.sh (port 7791).
## The client gets the host's bot buses as remote vehicles that say a bot drives them (driver shown), cannot take the
## wheel (E refused here, a request refused by the host), runs the traffic lights on the host's clock, stops showing a
## bus the host stows, and rides a bot bus: it steps in at a stop while the doors are open and stays standing in it as
## the bot drives on (the host's bot keeps the physics and does not vanish with them aboard). Then the host switches
## the bot traffic off (the bots leave the client's map too, the client's own car stays), clears every vehicle (the
## client's car too) and switches the traffic back on (the bots are back on the client).
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

## the host's game clock against the system clock, the net id of the bus the client is to ride (the temporary
## folder: /tmp, or the Windows one Git Bash calls /tmp)
var _clock_file := OS.get_temp_dir().path_join("test_lan_buses_clock.txt")
var _ride_file := OS.get_temp_dir().path_join("test_lan_buses_ride.txt")

var _main: Node
var _failures: PackedStringArray = []
var _hosting := false


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	OS.set_environment("PLATEAU_BUSES", "1" if _hosting else "0")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + ("[host] " if _hosting else "[client] ") + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await physics_frame
	return true


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _run() -> void:
	if _hosting:
		await _run_host()
	else:
		await _run_client()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _run_host() -> void:
	DirAccess.remove_absolute(_ride_file)
	var net: Node = _main.net
	_check(await _until(func() -> bool: return _main.mode == "host" and _main.traffic.bots.size() > 0, 60.0),
			"hosting with %d bot buses" % _main.traffic.bots.size())
	_check(await _until(func() -> bool: return net.players.size() == 2, 90.0), "the client joined")
	# the clock, for the client to compare with
	var stop_clock := false
	var write_clock := func() -> void:
		var f := FileAccess.open(_clock_file, FileAccess.WRITE)
		f.store_string("%f %f" % [Time.get_unix_time_from_system(), net.clock()])
		f.close()
	# a bot the client rides: on its way into a stop, with the physics
	var bot: Object = null
	for b: Object in _main.traffic.bots:
		if b.line["ref"] == "Z" and not b.idle:
			bot = b
	bot.may_glide = false
	# a stop with road enough after it to see it drive on
	var at := []
	for r in bot.line["routes"].size():
		var rt: Dictionary = _main.traffic.routes[bot.line["routes"][r]]
		for st: Dictionary in rt["stops"]:
			if at.is_empty() and float(st["s"]) > 60.0 and float(st["s"]) < float(rt["length"]) - 80.0:
				at = [r, float(st["s"])]
	bot.put(at[0], at[1] - bot.nose - 40.0)
	var f := FileAccess.open(_ride_file, FileAccess.WRITE)
	f.store_string(bot.car.net_id)
	f.close()
	var aboard := false
	var t0 := Time.get_ticks_msec()
	var s_aboard := 0.0
	var stayed := true
	while Time.get_ticks_msec() - t0 < 90000:
		write_clock.call()
		await physics_frame
		if not aboard and _main.riders(bot.car) == 1:
			aboard = true
			s_aboard = bot.s
		if aboard:
			stayed = stayed and not bot.car.stowed and not bot.gliding
			if bot.s > s_aboard + 25.0:
				break
	_check(aboard, "the client's player rides the bot bus (seen in it here)")
	_check(aboard and bot.s > s_aboard + 25.0 and stayed, "the bot drives on with them aboard, with the physics (%.0f m)" % [
			bot.s - s_aboard])
	# a stowed bus disappears there too
	var other: Object = _main.traffic.bots[0]
	other._stow()
	# the host's options: once the client parked a car of its own
	var theirs := func() -> bool: return net.owner_of.values().any(func(o: int) -> bool: return o != net.me())
	_check(await _until(theirs, 60.0), "the client parked a car")
	_main.set_bot_traffic(false)
	_check(_main.traffic.bots.is_empty() and not _main.cars.any(func(c: Node) -> bool: return c.is_bot()) \
			and theirs.call(), "bot traffic off: no bots left here, the client's car stays")
	await _until(func() -> bool: return false, 3.0)
	_main.clear_vehicles()
	_check(_main.cars.is_empty() and net.cars.is_empty(), "every vehicle cleared here")
	await _until(func() -> bool: return false, 3.0)
	_main.set_bot_traffic(true)
	_check(_main.traffic.bots.size() > 0, "bot traffic back on (%d bots)" % _main.traffic.bots.size())
	_check(await _until(func() -> bool: return net.players.size() == 1, 60.0), "the client left")


func _run_client() -> void:
	var net: Node = _main.net
	_check(await _until(func() -> bool: return _main.mode == "client", 90.0), "joined the host")
	_check(await _until(func() -> bool: return _main.cars.filter(func(c: Node) -> bool: return c.is_bot()).size() >= 5, 30.0),
			"the host's bot buses are here, a bot driving each")
	var bots: Array = _main.cars.filter(func(c: Node) -> bool: return c.is_bot())
	_check(bots.all(func(c: Node) -> bool: return c.remote and c.freeze and (c._driver_dummy == null or c._driver_dummy.visible)),
			"remote copies, the driver shown (in the vehicles that have one)")
	# the shared clock
	_check(await _until(func() -> bool: return FileAccess.file_exists(_clock_file), 30.0), "the host writes its clock")
	await _until(func() -> bool: return not is_nan(net._clock_offset), 10.0)
	await _until(func() -> bool: return false, 4.0)     # a few clock messages past the loading
	var worst := 0.0
	for k in 20:
		await physics_frame
		var parts := FileAccess.get_file_as_string(_clock_file).split(" ")
		if parts.size() == 2:
			var host_now := float(parts[1]) + (Time.get_unix_time_from_system() - float(parts[0]))
			worst = maxf(worst, absf(net.clock() - host_now))
	_check(worst < 0.1, "the traffic lights run on the host's clock (off by %d ms at most)" % roundi(worst * 1000.0))
	# the bus to ride
	_check(await _until(func() -> bool: return FileAccess.file_exists(_ride_file), 30.0), "the host picked a bus to ride")
	var bus: Node = net.cars.get(FileAccess.get_file_as_string(_ride_file))
	_check(bus != null and bus.is_bot(), "it is here")
	# E beside it does nothing; asking the host anyway is refused
	var player: CharacterBody3D = _main.player
	player.teleport(bus.to_global(Vector3(bus.half_extents.x + 1.2, 0.3, bus.extents_center.z)))
	await _until(func() -> bool: return false, 0.3)
	_check(_main.car_to_enter() == null, "E next to it does not pick it")
	var refused := [false]
	net.message.connect(func(text: String) -> void: refused[0] = refused[0] or text.contains("bot"))
	net.request_drive(bus)
	_check(await _until(func() -> bool: return refused[0], 10.0) and _main.driving == null,
			"the host refuses anyone its wheel")
	# in at the stop
	_check(await _until(func() -> bool: return bus.doors_open, 60.0), "its doors open at the stop")
	var aisle: Vector3 = bus.interior.get_center()
	player.teleport(bus.to_global(Vector3(aisle.x, bus.interior.position.y + 0.05, aisle.z)))
	_check(await _until(func() -> bool: return player.carrier == bus, 5.0), "standing in it")
	var p0: Vector3 = bus.global_position
	var inside := 0
	var frames := 0
	while bus.global_position.distance_to(p0) < 25.0 and frames < 60 * 60:
		await physics_frame
		frames += 1
		inside += 1 if player.carrier == bus and bus.carries(player.global_position, 0.3) else 0
	_check(bus.global_position.distance_to(p0) >= 25.0 and inside == frames,
			"rides along as the bot drives on (%.0f m, inside %d/%d frames)" % [bus.global_position.distance_to(p0), inside, frames])
	# a bus the host stows disappears here
	var gone := await _until(func() -> bool: return bots.any(func(c: Node) -> bool: return c.stowed and not c.visible), 20.0)
	_check(gone, "a bus the host stows is hidden here")
	player.teleport(bus.to_global(Vector3(bus.half_extents.x + 4.0, 0.5, 0.0)))
	await _until(func() -> bool: return false, 1.0)
	# the host's options
	var mine: Node = _main.spawn_car_near_player("sedan")
	_check(mine != null, "parked a car of our own")
	var no_bots := func() -> bool: return not _main.cars.any(func(c: Node) -> bool: return c.is_bot())
	_check(await _until(no_bots, 20.0) and is_instance_valid(mine) and mine in _main.cars,
			"the host switched bot traffic off: no bots here, our car stays")
	_check(await _until(func() -> bool: return _main.cars.is_empty(), 20.0) and net.cars.is_empty()
			and not is_instance_valid(mine), "the host cleared every vehicle: ours too")
	_check(await _until(func() -> bool: return _main.cars.filter(func(c: Node) -> bool: return c.is_bot()).size() >= 5, 30.0),
			"the host switched bot traffic back on: its bots are here again")
	await _until(func() -> bool: return false, 1.0)
	net.leave()
