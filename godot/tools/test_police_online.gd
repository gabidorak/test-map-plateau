extends "res://tools/test_base.gd"
## PTA Online's police between the official server and a player (tools/test_police_online.sh runs the server and the
## accounts service): the player (`--client=TOKEN`, Thief_1) sees the patrols round them and the helicopter, steals a bot car standing
## still at its driver's door (the carjack's keys), stays in it: one star (the driver's call); a police car comes, its
## officer gets out and pulls at the door: a wrong key, dragged out, tased, carried to the car over the officer's
## shoulders: arrested: let go by the sous-préfecture, no star, the fine taken from the wallet; the officer back in.
##   godot --headless --path godot --script res://tools/test_police_online.gd -- --client=TOKEN --online

const Car = preload("res://scripts/car.gd")

var _main: Node
var _mode: Node
var _token := ""
var _failures: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "client" and kv.size() > 1:
			_token = kv[1]
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	load("res://scripts/accounts.gd").keep(_token, "Thief_1", false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var joined := await _until(func() -> bool: return _main.mode == "client", 60.0)
	_check(joined and _main.mode_id == "online", "joined PTA Online")
	if not joined or not await _until(func() -> bool: return _main.economy.username != "", 15.0):
		_check(false, "logged in")
		return _finish()
	_mode = _main.game_mode
	var police: Node = _mode.police
	var fleet := await _until(func() -> bool: return _count("police-hatchback") >= police.AMBIENT, 90.0)
	_check(fleet, "police patrols round us: %d cars (the rest of the fleet in its pool, unseen)" % _count(
			"police-hatchback"))
	_check(_count("helicopter-police") >= 2, "the police helicopter and the public one")
	var money: int = _main.economy.balance
	var stolen := await _steal()
	_check(stolen, "a bot car stolen at its door, at its wheel")
	if not stolen:
		return _finish()
	var car: Car = _main.driving
	var reported := await _until(func() -> bool: return police.level == 1, 20.0)
	_check(reported, "the driver called the police: one star")
	var t0 := Time.get_ticks_msec()
	var out := await _until(func() -> bool: return not police.arrest.officers.is_empty(), 240.0)
	_check(out, "a police car came, siren on, its officer out (%.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not out:
		return _finish()
	var pull := await _until(func() -> bool: return police.arrest.struggling(), 60.0)
	_check(pull, "it pulls at our door: the keys on the screen")
	if not pull:
		return _finish()
	var seq: Array = police.arrest._hud.sequence
	police.arrest._hud.finished.emit([(int(seq[0]) + 1) % 4])
	var people: Node = _main.people
	var me: String = people.my_id()
	var dragged := await _until(func() -> bool: return _main.driving == null and people.is_down(me), 10.0)
	_check(dragged and car != null, "a wrong key: dragged out, tased")
	var carried := await _until(func() -> bool: return people.is_carried(me), 30.0)
	var officer: Node3D = police.arrest.officers.values()[0] if not police.arrest.officers.is_empty() else null
	_check(carried and officer != null, "picked up by the officer")
	if carried and officer:
		await _frames(30)
		_check(_main.player.global_position.distance_to(officer.global_position) < 1.5,
				"...over their shoulders, going where they go")
	var release: Vector3 = _release_spot()
	var free := await _until(func() -> bool:
		var p: Vector3 = _main.player.global_position
		return police.level == 0 and Vector2(p.x - release.x, p.z - release.z).length() < 4.0, 90.0)
	_check(free, "arrested: let go by the sous-préfecture, no star")
	var fined := await _until(func() -> bool: return money - int(_main.economy.balance) == 1000, 15.0)
	_check(fined, "the fine taken: %d €" % (money - int(_main.economy.balance)))
	var back := await _until(func() -> bool: return police.arrest.officers.is_empty(), 60.0)
	_check(back, "the officer back in their car")
	_finish()


func _count(model: String) -> int:
	var n := 0
	for c: Car in _main.cars:
		if is_instance_valid(c) and c.model_name == model and not c.stowed:
			n += 1
	return n


## Steals a bot car standing still (a red light, a jam): at its driver's door, E, the keys right. Tries those standing
## still nearest first, again and again (the light turns green...).
func _steal() -> bool:
	var t0 := Time.get_ticks_msec()
	var tried := {}
	while Time.get_ticks_msec() - t0 < 180000:
		var car := await _still_bot_car(tried)
		if car == null:
			await _frames(30)
			continue
		tried[car] = true
		var seat: Vector3 = car.driver_seat if car.driver_seat != Vector3.ZERO else car.extents_center
		var door: Vector3 = car.to_global(Vector3(car.extents_center.x + car.half_extents.x + 0.7, 0.3, seat.z))
		_main.player.teleport(door)
		await _frames(20)                   # (our place gets to the server)
		if not _main.carjack.request(car):
			continue
		var started := await _until(func() -> bool: return _main.carjack._key != "", 3.0)
		if not started:
			continue
		var seq: Array = _main.carjack._hud.sequence
		_main.carjack._on_typed(seq, false)
		if await _until(func() -> bool: return _main.driving == car, 5.0):
			return true
	return false


## A bot car (not a bus, a police car, a truck with a cabin to walk in) within 200 m, standing still for a second here:
## the nearest, or null.
func _still_bot_car(tried: Dictionary) -> Car:
	var me: Vector3 = _main.player.global_position
	var was := {}
	for c: Car in _main.cars:
		if is_instance_valid(c) and c.is_bot() and not c.stowed and not tried.has(c) and not c.has_doors \
				and c.interior.size == Vector3.ZERO and c.model_name != "police-hatchback" \
				and c.global_position.distance_to(me) < 200.0:
			was[c] = c.global_position
	await _frames(60)
	var best: Car = null
	var best_d := INF
	for c: Car in was:
		if not is_instance_valid(c) or c.global_position.distance_to(was[c]) > 0.2:
			continue
		var d := c.global_position.distance_to(me)
		if d < best_d:
			best = c
			best_d = d
	return best


## Where the police let the arrested go (data/police.json release), on the ground.
func _release_spot() -> Vector3:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/police.json"))["release"]
	return load("res://scripts/online/garages.gd")._at(float(d["x"]), float(d["y"]))


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
