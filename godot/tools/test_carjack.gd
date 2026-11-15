extends "res://tools/test_base.gd"
## Headless checks for stealing a bot car (scripts/carjack/), solo in Sandbox:
## - E at the driver's door of a bot car on the move: not now (it's moving);
## - a bot car standing still in a jam (the car ahead held there): E at its driver's door holds it (its driver frozen)
##   and shows SEQUENCE arrow keys; a wrong one ends it: the driver comes to, the car is still the bot's, and it cannot be
##   tried again at once (COOLDOWN);
## - after the cooldown, the right keys in order: the player at its wheel, its bot gone from the traffic and a new bot
##   car in its place (as many bot cars), its driver out and running off, a walker for the bots;
## - the player out of it and back in with E like any car;
## - Esc gives up, waiting too long fails (the car is the bot's again);
## - E by a bus: a bot drives it, nothing to steal;
## - a stolen car left ABANDON s with nobody near leaves the map.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_carjack.gd

const Carjack = preload("res://scripts/carjack/carjack.gd")
const Hud = preload("res://scripts/carjack/carjack_hud.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")

var _main: Node
var _failures: PackedStringArray = []
var _toast := ""


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "4")
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


func _seconds(t: float) -> void:
	await _frames(roundi(t * 60.0))


func _cars() -> Array:
	var traffic: Node = _main.traffic
	return traffic.bots.filter(func(b: Object) -> bool: return is_same(b.line, traffic.car_line))


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	await _frames(30)
	_main.toast_shown.connect(func(text: String) -> void: _toast = text)
	var traffic: Node = _main.traffic
	traffic.send_cars = false
	traffic.departures.clear()
	for b: Object in traffic.bots:
		if not b.idle:
			b._stow()
	await _frames(2)
	var cars := _cars()
	var a: Object = cars[0]
	var b: Object = cars[1]
	var spot := _stretch(a)
	if spot.is_empty():
		_check(false, "a straight stretch to test on")
	else:
		await _moving(a, spot)
		await _jam(a, b, spot)
	await _bus()
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## E at the driver's door of a bot car on the move: refused.
func _moving(a: Object, spot: Array) -> void:
	a.may_glide = false
	a.put(spot[0], spot[1] - 60.0, 8.0)
	await _seconds(1.0)
	_toast = ""
	_main.player.teleport(_door(a.car))
	_press_action("interact")
	await _frames(3)
	_check(not _main.carjack.busy() and "moving" in _toast and a.car.is_bot(),
			"a bot car on the move (%.1f m/s): not now (\"%s\")" % [a.car.speed(), _toast])
	a._stow()
	await _frames(2)


func _jam(a: Object, b: Object, spot: Array) -> void:
	var carjack: Carjack = _main.carjack
	var traffic: Node = _main.traffic
	var player: Node3D = _main.player
	var count := _cars().size()
	# b held standing, a coming up behind it: a jam
	a.may_glide = false
	b.may_glide = false
	b.put(spot[0], spot[1], 0.0)
	b.seized = true
	a.put(spot[0], spot[1] - 50.0, 8.0)
	var still := 0
	for f in 60 * 20:
		await physics_frame
		still = still + 1 if absf(a.car.speed()) < 0.3 else 0
		if still > 60:
			break
	_check(still > 60 and a.reason == "vehicle ahead", "a bot car standing in a jam (%s)" % a.reason)
	var key: String = carjack.key_of(a.car)

	# a wrong key
	player.teleport(_door(a.car))
	await _frames(2)
	_press_action("interact")
	var shown := await _keys_shown()
	var seq: Array = carjack._hud.sequence
	_check(shown and a.seized and seq.size() == carjack.SEQUENCE and not player.active,
			"E at its driver's door: %d arrow keys shown, the car held, the player still" % seq.size())
	_toast = ""
	_tap(Hud.ARROWS[(int(seq[0]) + 1) % 4])
	await _frames(3)
	_check(not carjack.busy() and "Wrong key" in _toast and not a.seized and a.car.is_bot() and traffic.bots.has(a),
			"a wrong key: over (\"%s\"), the car is still the bot's" % _toast)
	_toast = ""
	_press_action("interact")
	await _frames(3)
	_check(not carjack.busy() and "guard" in _toast, "and it can't be tried again at once (\"%s\")" % _toast)

	# the right keys, once the cooldown is over (a still behind b)
	await _seconds(carjack.COOLDOWN + 0.5)
	player.teleport(_door(a.car))
	await _frames(2)
	_press_action("interact")
	shown = await _keys_shown()
	seq = carjack._hud.sequence
	for k: int in seq:
		_tap(Hud.ARROWS[k])
		await _frames(2)
	await _frames(3)
	var car: Node3D = a.car
	_check(shown and _main.driving == car and car.pilot == null and not car.is_bot() and not traffic.bots.has(a)
			and carjack.is_stolen(key), "the right keys in order: the car is the player's, at its wheel, its bot gone")
	_check(_cars().size() == count, "a new bot car in the traffic in its place (%d bot cars, as before)" % _cars().size())
	var driver: Node3D = null
	for n: Node in _main.get_children():
		if n.name.begins_with("EjectedDriver"):
			driver = n
	var from: Vector3 = driver.global_position if driver else Vector3.ZERO
	await _seconds(3.0)
	var ran: float = driver.global_position.distance_to(from) if is_instance_valid(driver) else 0.0
	_check(driver != null and ran > 5.0 and driver in traffic.seen.walkers,
			"its driver gets out and runs off (%.1f m in 3 s), a walker for the bots" % ran)

	# out of it and back in like any car
	_main.exit_car()
	await _frames(10)
	_press_action("interact")
	await _frames(3)
	_check(_main.driving == car, "out of it, and back in with E like any car")
	_main.exit_car()
	await _frames(5)

	# Esc gives up; too slow fails (b, held there by the test)
	player.teleport(_door(b.car))
	await _frames(2)
	_press_action("interact")
	shown = await _keys_shown()
	_toast = ""
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check(shown and not carjack.busy() and "gave up" in _toast and b.car.is_bot() and not pause_open(),
			"Esc gives up (\"%s\"), the car still the bot's" % _toast)
	b.seized = true                         # (the test's jam again)
	await _seconds(carjack.COOLDOWN + 0.5)
	player.teleport(_door(b.car))
	await _frames(2)
	_press_action("interact")
	shown = await _keys_shown()
	_toast = ""
	await _seconds(carjack.TIME + 0.5)
	_check(shown and not carjack.busy() and "Too slow" in _toast and b.car.is_bot(),
			"waiting too long fails (\"%s\")" % _toast)
	b._stow()

	# abandoned
	carjack.stolen[key] = carjack.ABANDON + 1.0
	player.teleport(car.global_position + Vector3(400.0, 60.0, 0.0))
	await _seconds(1.5)
	_check(not is_instance_valid(car) or car.is_queued_for_deletion() or not _main.cars.has(car),
			"a stolen car left with nobody near leaves the map")


## E by a bus: a bot drives it, nothing to steal.
func _bus() -> void:
	var bus: Object = null
	for b: Object in _main.traffic.bots:
		if b.line["ref"] == "4606":
			bus = b
			break
	if bus == null:
		_check(false, "a bus of the 4606")
		return
	bus.may_glide = false
	bus.put(bus.route_index, 300.0, 0.0)
	await _frames(30)
	_main.player.teleport(_door(bus.car))
	await _frames(2)
	_toast = ""
	_press_action("interact")
	await _frames(3)
	_check(not _main.carjack.busy() and "bus" in _toast and bus.car.is_bot(), "E by a bus: \"%s\"" % _toast)
	bus._stow()


# ---------------------------------------------------------------- helpers

## Waits for the keys to be shown and wanted (the HUD past its popping in); false if they never are.
func _keys_shown() -> bool:
	for f in 60 * 3:
		await physics_frame
		var hud: Hud = _main.carjack._hud
		if hud != null and hud.state == "input":
			return true
	return false


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func pause_open() -> bool:
	return _main.pause.visible


## On the ground by `car`'s driver's door (its left side), global.
func _door(car: Node3D) -> Vector3:
	var seat: Vector3 = car.driver_seat if car.driver_seat != Vector3.ZERO else car.extents_center
	var p: Vector3 = car.to_global(Vector3(car.extents_center.x + car.half_extents.x + 0.7, 0.0, seat.z))
	var y := WorldQuery.ground_y(car.get_world_3d(), p.x, p.z, Layers.SOLID, car.global_position.y + 3.0)
	return Vector3(p.x, (y if not is_nan(y) else p.y) + 0.05, p.z)


## [route index, s] of a straight stretch of `a`'s routes with nothing to stop at (no light, give-way) for 150 m
## around; [] if none (as tools/test_car_bots.gd).
func _stretch(a: Object) -> Array:
	var ids: Array = a.line["routes"]
	for r in ids.size():
		var rt: Dictionary = _main.traffic.routes[ids[r]]
		a._set_route(r)
		var d := 200.0
		while d < float(rt["length"]) - 200.0:
			var ok := true
			for k in range(-60, 61, 10):
				ok = ok and a._room_at(d + k) > 2.6 and a._room_at(d + k) < 4.5
			for key in ["lights", "yields"]:
				for e: Dictionary in rt[key]:
					ok = ok and absf(float(e["s"]) - d) > 150.0
			if ok and (a.at(d + 60.0) - a.at(d - 60.0)).length() > 119.0:
				return [r, d]
			d += 20.0
	return []
