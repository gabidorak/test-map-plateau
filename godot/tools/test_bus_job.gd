extends SceneTree
## PTA Online's bus job (ONLINE_MILESTONES.md O5, scripts/online/bus_job.gd). The role is the first argument after `--`:
## - `--check`: played solo (PLATEAU_MODE=online, an empty garage): the depot's lines, going on duty (a lent 18 m bus
##   comes out), duty refused away from the depot; a bot drives the whole 4606 to Le Guichet on duty: every stop served,
##   no penalty, the pay per hour within PAY_BAND; then skipped stops, off the route, a teleport (the stretch pays
##   nothing), the hourly cap; off duty; with the bot buses running, duty holds one of them off the map and off duty
##   brings it back. ~4 min.
## and the clients of tools/test_bus_job.sh (an official server with its bot traffic, `--sync=DIR` for the files they
## wait on each other with):
## - `--driver=TOKEN`: gets the depot's lent 18 m bus out, drives it to the 4606's first stop, goes on duty (a bot bus
##   of the 4606 leaves the map on its screen), serves the stop (paid by the accounts service), and leaves;
## - `--watcher=TOKEN`: sees that bot bus leave the map, and come back once the driver has left.
## Exit code 1 on failure.

const BusBot = preload("res://scripts/bus_bot.gd")
const ROUTES := "res://world/bus_routes.json"
const PAY_BAND := Vector2(12000.0, 18000.0)    # € an hour a bot driving the line on duty earns (ONLINE_MILESTONES.md O5)


## Lights on simulated time (headless fixed-fps runs faster than the real clock: tools/test_races.gd).
class SimClock extends Node:
	var net: Node
	var t := 0.0

	func _init() -> void:
		process_physics_priority = -1000

	func _physics_process(delta: float) -> void:
		t += delta
		net.clock_shift = t - Time.get_ticks_usec() / 1e6


var _main: Node
var _mode: Node
var _job: Node
var _what := ""
var _arg := ""
var _sync := ""
var _failures: PackedStringArray = []
var _routes := {}
var _lines := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["check", "driver", "watcher"]:
			_what = kv[0]
			_arg = kv[1] if kv.size() > 1 else ""
		elif kv[0] == "sync":
			_sync = kv[1]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTES))
	_routes = data["routes"]
	for line: Dictionary in data["lines"]:
		_lines[line["ref"]] = line
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


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


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
	match _what:
		"check":
			await _solo()
		"driver":
			await _driver()
		"watcher":
			await _watcher()
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
	_job = _mode.bus_job
	await _frames(5)


func _stand_at(gid: String) -> void:
	var spot: Array = _mode.garages.stand_spot(_mode.garages.get_garage(gid))
	_main.player.set_carrier(null)
	_main.player.teleport(spot[0], spot[1])
	await _frames(10)


## Opens garage `gid`'s panel with E and waits for its list.
func _open_garage(gid: String) -> bool:
	await _stand_at(gid)
	_press("interact")
	return await _until(func() -> bool: return _mode.ui_open() and _mode._panel.kind == "garage" \
			and _mode._panel.rows.get_child_count() > 0, 10.0)


func _rows() -> Array:
	return _mode._panel.rows.get_children().map(func(r: Node) -> String: return str(r.name))


## Presses the button `button` of the panel's row `row`, and waits for `node`'s `answered` [ok, text].
func _click(node: Node, row: String, button: String) -> Array:
	var r: Node = _mode._panel.rows.get_node_or_null(row)
	if r == null or r.get_node_or_null(button) == null:
		_check(false, "the panel has %s/%s (rows: %s)" % [row, button, _rows()])
		return [false, "no button"]
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	node.answered.connect(take)
	(r.get_node(button) as Button).pressed.emit()
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	node.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


## Asks the host for duty on `ref` at `gid` as the panel would ("" ref: off duty), and waits for its answer.
func _ask_duty(gid: String, ref: String) -> Array:
	var got := []
	var take := func(ok: bool, text: String) -> void: got.append([ok, text])
	_job.answered.connect(take)
	_job.ask_duty(gid, ref)
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	_job.answered.disconnect(take)
	return got[0] if not got.is_empty() else [false, "no answer"]


## A bot driver for `car` on `line` (its routes in the main traffic's table), on the physics all along.
func _bot(car: Node, line: Dictionary) -> Object:
	var traffic: Node = _main.traffic
	for rid: String in line["routes"]:
		if not traffic.routes.has(rid):
			traffic.routes[rid] = _routes[rid] if _routes.has(rid) else traffic.routes[rid]
	var bot := BusBot.new()
	bot.setup(traffic, car, line, 0)
	bot.may_glide = false
	return bot


## Puts the duty's bus on route `r` of `bot`'s line, its front at `front` m, driven by `bot`; `fresh`: the job doesn't
## see the move (the tests' hand, not the driver's).
func _put(car: Node, bot: Object, r: int, front: float, fresh := true) -> void:
	car.set_pilot(bot)
	bot.put(r, front - bot.nose)
	if fresh:
		var d: Object = _job.duties[_mode.me()]
		d.has_last = false
		d.vel = Vector2.ZERO


func _events(d: Object, kind: String) -> Array:
	return d.events.filter(func(e: Array) -> bool: return e[0] == kind)


## Drives on (`bot` at the wheel) until `done` or `minutes` of simulated time.
func _drive_until(done: Callable, minutes: float) -> bool:
	for i in int(minutes * 3600.0):
		await physics_frame
		if done.call():
			return true
	return false


# ---------------------------------------------------------------- solo

func _solo() -> void:
	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_ONLINE_VEHICLES", "")
	OS.set_environment("PLATEAU_CARS", "0")
	await _start(false)
	var clock := SimClock.new()
	clock.net = _main.net
	root.add_child(clock)
	var me: int = _mode.me()

	# the depot's lines
	_check(await _open_garage("bus-depot"), "E at the bus depot's terminal opens its list")
	var rows := _rows()
	for ref: String in _lines:
		_check(("Duty_" + ref) in rows, "the depot offers duty on line %s" % ref)
	var r := await _click(_job, "Duty_4606", "Duty")
	var d: Object = _job.duties.get(me)
	var car: Node = _mode.car_of(_mode.mine)
	_check(r[0] and d != null and car != null and car.model_name == "bus-idfm-artic" and not d.owned,
			"on duty on the 4606 with nothing out: a lent 18 m bus comes out (%s)" % r[1])
	if d == null or car == null:
		return
	await process_frame
	_check(_job.hud_text().contains("4606") and _job.hud_text().contains("Drive to the line"),
			"the HUD shows the line: %s" % _job.hud_text().replace("\n", " | "))
	_check(_main.waypoint != null, "the waypoint is on the line")
	await _stand_at("fire-station")
	r = await _ask_duty("bus-depot", "Z")
	_check(not r[0] and r[1].contains("Walk up"), "duty refused away from the depot: %s" % r[1])
	r = await _ask_duty("fire-station", "Z")
	_check(not r[0] and r[1].contains("bus depot"), "duty refused at the fire station: %s" % r[1])
	await _stand_at("bus-depot")
	r = await _ask_duty("bus-depot", "9999")
	_check(not r[0], "no duty on a line that doesn't exist: %s" % r[1])

	# a bot drives the whole 4606 to Le Guichet
	var line: Dictionary = _lines["4606"]
	var bot := _bot(car, line)
	_put(car, bot, 0, bot.nose + bot.tail + 1.0)
	_main.driving = car                     # the job counts it as ours; the bot keeps the wheel
	await _frames(2)
	var t0: float = _job.time
	var route0: Dictionary = _routes[line["routes"][0]]
	var t_real := Time.get_ticks_msec()
	var through := await _drive_until(func() -> bool: return d.r == 1 or d.served >= route0["stops"].size() and \
			bot.state != BusBot.DRIVE and bot.state != BusBot.DWELL, 40.0)
	var hours: float = (_job.time - t0) / 3600.0
	var rate: float = d.earned / maxf(hours, 1e-6)
	var bonuses := {}
	for e: Array in d.events:
		bonuses[e[0]] = bonuses.get(e[0], 0) + 1
	print("     the 4606 on duty: %d stops, %d € in %.1f min (%d s real): %d €/h; events %s; money %d €" % [d.served, d.earned,
			hours * 60.0, (Time.get_ticks_msec() - t_real) / 1000, roundi(rate), bonuses, _mode.test_money])
	_check(through and d.served == route0["stops"].size(), "a bot drives the whole 4606 on duty: %d/%d stops served" % [
			d.served, route0["stops"].size()])
	_check(_events(d, "skip").is_empty() and _events(d, "off_route").is_empty() and _events(d, "crash").is_empty()
			and _events(d, "void").is_empty(), "no penalty, nothing refused: %s" % str(d.events.filter(func(e: Array) \
			-> bool: return e[1] <= 0 and e[0] != "info")))
	_check(rate >= PAY_BAND.x and rate <= PAY_BAND.y, "pays %d €/h, within %d-%d €/h" % [roundi(rate), PAY_BAND.x,
			PAY_BAND.y])
	_check(_mode.test_money == 5000 + d.earned and _main.economy.balance == _mode.test_money,
			"the wallet follows: %d €" % _mode.test_money)
	_check(d.combo > 1.5, "the combo grew stop after stop: ×%.1f" % d.combo)
	_check(d.r == 1 and d.state == "start", "on to the line's other way at Le Guichet (%d, %s)" % [d.r, d.state])
	for e: Array in d.events:
		if e[0] != "stop":
			print("     %s" % str(e))
	if OS.get_environment("PLATEAU_TEST_ONLY") == "line":
		return

	# skipped stops: a bot that doesn't stop drives the other way's first stops
	var route1: Dictionary = _routes[line["routes"][1]].duplicate()
	route1["stops"] = []
	route1["then"] = "respawn"
	_main.traffic.routes["test:no-stops"] = route1
	var through_bot := _bot(car, {"ref": "test", "model": line["model"], "routes": ["test:no-stops"], "headway": 9999.0})
	_put(car, through_bot, 0, through_bot.nose + through_bot.tail + 1.0)
	var skipped := await _drive_until(func() -> bool: return d.s > 600.0, 4.0)
	var skips := _events(d, "skip")
	_check(skipped and skips.size() == 2 and d.combo == 1.0 and d.debt == 2 * int(_job.pay["skip_fine"]),
			"driving past Gare du Guichet and Versailles: 2 skipped stops fined, combo back to ×1 (%s, debt %d €)" % [
			str(skips), d.debt])
	car.set_pilot(null)
	car.hold = true
	await _until(func() -> bool: return car.speed() < 0.3, 20.0)

	# off the route: slid sideways off it
	for b in car.bodies():
		b.freeze = true
	var side: Vector3 = car.global_transform.basis.x
	for i in 400:
		for b in car.bodies():
			b.global_position += side * 0.12
		await physics_frame
		if d.state == "lost":
			break
	_check(d.state == "lost" and _events(d, "off_route").size() == 1, "slid sideways off the route: off it, fined (%s)" %
			str(_events(d, "off_route")))
	for b in car.bodies():
		b.freeze = false
	car.hold = false

	# a teleport ahead on the route: refused, the stops jumped over skipped, the next stop pays nothing
	var real := _bot(car, line)
	var debt: int = d.debt
	_put(car, real, 1, 1500.0, false)
	var back := await _drive_until(func() -> bool: return d.state == "route", 1.0)
	await _frames(2)
	_check(back and _events(d, "void").size() == 1 and d.void_why == "teleport",
			"a jump of 1.5 km along the route is refused (%s)" % str(_events(d, "void")))
	_check(_events(d, "skip").size() == 3 and d.debt == debt + int(_job.pay["skip_fine"]),
			"the stop jumped over (Mûriers) is skipped: %s" % str(_events(d, "skip").back()))
	var served: int = d.served
	var reached := await _drive_until(func() -> bool: return d.served > served, 6.0)
	var last: Array = _events(d, "stop").back()
	_check(reached and last[1] == 0 and str(last[2]).contains("not paid"), "Université Paris-Saclay served, not paid: %s" % str(last))

	# the hourly cap (no fines due, to see it alone)
	d.debt = 0
	var hour := 0
	for e: Array in _job._solo_paid:
		hour += int(e[1])
	_job.cap = hour + 50
	var money: int = _mode.test_money
	served = d.served
	reached = await _drive_until(func() -> bool: return d.served >= served + 2, 10.0)
	var paid: Array = _events(d, "stop").slice(-2).map(func(e: Array) -> int: return e[1])
	_check(reached and paid.size() == 2 and paid[0] <= 50 and paid[1] == 0 and _mode.test_money - money <= 50
			and str(_events(d, "stop").back()[2]).contains("hourly cap"),
			"the hourly cap (%d €) holds: the next stops pay %s" % [_job.cap, str(paid)])
	_job.cap = 30000

	# off duty
	car.set_pilot(null)
	_main.driving = null
	await _stand_at("bus-depot")
	r = await _ask_duty("bus-depot", "")
	await process_frame
	_check(r[0] and _job.duties.is_empty() and not _job.on_duty() and _job.hud_text() == "" and _main.waypoint == null,
			"off duty: the HUD and the waypoint go (%s)" % r[1])

	# with the bot buses: duty holds one of the line's off the map, off duty brings it back
	await _main.traffic.start_bots()
	await _frames(120)
	r = await _ask_duty("bus-depot", "4606")
	d = _job.duties.get(me)
	var held: Object = d.held if d else null
	_check(r[0] and held != null and held.car.stowed and _main.traffic.held(held) and is_same(held.line,
			_main.traffic.line_of("4606")), "on duty, one of the 4606's bot buses left the map (%s)" % ("route %d, %d m" % [
			held.route_index, held.s] if held else "none"))
	var departed: int = _main.traffic.departed.get(line["routes"][0], 0) + _main.traffic.departed.get(line["routes"][1], 0)
	await _frames(300)
	_check(held != null and held.car.stowed and held.idle, "it stays off the map while we are on duty")
	await _stand_at("fire-station")             # out of sight of where it comes back
	_job.end_duty(me, "test")
	await _frames(3)
	_check(held != null and not _main.traffic.held(held) and not held.car.stowed and not held.idle,
			"off duty, it is back on its route where its timetable has it")
	print("     departures meanwhile: %d" % (_main.traffic.departed.get(line["routes"][0], 0)
			+ _main.traffic.departed.get(line["routes"][1], 0) - departed))


# ---------------------------------------------------------------- LAN (tools/test_bus_job.sh)

func _join(token: String, username: String) -> void:
	load("res://scripts/accounts.gd").keep(token, username, false)
	await _start(true)


func _driver() -> void:
	await _join(_arg, "Driver_1")
	if _mode == null:
		return
	_check(await _open_garage("bus-depot"), "the depot's list came")
	_check("Duty_4606" in _rows(), "the depot offers duty on the 4606: %s" % str(_rows()))
	var r := await _click(_mode, "Vehicle_0_bus-idfm-artic", "Get")
	var car: Node = _mode.car_of(_mode.mine)
	_check(r[0] and car != null, "the lent 18 m bus is out: %s" % r[1])
	if car == null:
		return
	_main.player.teleport(car.to_global(car.extents_center + Vector3(car.half_extents.x + 1.0, 0.0, 0.0)))
	await physics_frame
	_main.net.request_drive(car)
	var driving := await _until(func() -> bool: return _main.driving == car \
			and _main.net.owner_of.get(car.net_id, 0) == _main.net.me(), 10.0)
	_check(driving, "got in: we simulate it")
	var line: Dictionary = _lines["4606"]
	var place := _bot(car, line)          # only for the pose at the first stop
	var stop := float(_routes[line["routes"][0]]["stops"][0]["s"])
	car.place(place.pose_at(stop - place.nose).translated(Vector3.UP * 0.05))
	await _frames(60)
	await _stand_beside_and_back(car)
	var balance: int = _main.economy.balance
	r = await _ask_duty("bus-depot", "4606")
	_check(r[0] and await _until(func() -> bool: return _job.on_duty(), 5.0), "on duty on the 4606 in that bus: %s" % r[1])
	var held: String = _job.info.get("held", "")
	_check(held != "", "a bot bus of the 4606 is held off the map: %s" % held)
	var gone := held != "" and await _until(func() -> bool:
		var c: Node = _main.net.cars.get(held)
		return c != null and c.stowed, 10.0)
	_check(gone, "...gone from our screen")
	_mark("held", held)
	var joined := await _until(func() -> bool: return _job.info.get("state", "") == "route", 10.0)
	_check(joined and str(_job.info.get("stop", "")).begins_with("Gare de Massy"), "at the line's first stop: next %s" %
			_job.info.get("stop", "?"))
	car.set_doors(true)
	var paid := await _until(func() -> bool: return _main.economy.balance > balance, 20.0)
	_check(paid and int(_job.info.get("served", 0)) == 1, "doors open at Gare de Massy - Palaiseau: served, paid %d €" % (
			_main.economy.balance - balance))
	_check(_job.hud_text().contains("Palaiseau Ville"), "the HUD shows the next stop: %s" % _job.hud_text().replace("\n", " | "))
	await _await_mark("seen_gone", 60.0)
	_mark("leaving")


## A remote copy may still be settling: the server sees our states once we simulate the bus.
func _stand_beside_and_back(car: Node) -> void:
	for i in 30:
		await physics_frame
	car.set_doors(false)


func _watcher() -> void:
	await _join(_arg, "Watcher_1")
	if _mode == null:
		return
	await _stand_at("fire-station")
	var held := await _await_mark("held", 240.0)
	var gone := await _until(func() -> bool:
		var c: Node = _main.net.cars.get(held)
		return c != null and c.stowed, 10.0)
	_check(gone, "the held bot bus %s is off the map here too" % held)
	_mark("seen_gone")
	await _await_mark("leaving", 120.0)
	var back := await _until(func() -> bool:
		var c: Node = _main.net.cars.get(held)
		return c != null and not c.stowed, 20.0)
	print("     back on the map here: %s" % ("yes" if back else "no"))
	_mark("watcher_back", "yes" if back else "no")
