extends "res://tools/test_base.gd"
## The police's arrests (scripts/police/foot/arrest.gd), in the PTA Online test (solo, offline), with a little bot traffic:
## - on foot: reported next to a police car, it stops, its officer gets out, tases the player, carries them to the
##   car: arrested: let go by the sous-préfecture, no star, the weapons seized, the fine paid; the officer back in, the
##   car on its way again;
## - in a car: stopped, an officer at the door pulls: the right keys, they hold on (the officer staggers back); the
##   wrong ones, dragged out, tased, carried, arrested.
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_police_arrest.gd -- --online-test

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "6")
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started and _main.mode_id == "online", "the PTA Online test started")
	if not started:
		return _finish()
	var police: Node = _main.game_mode.police
	var out := await _until(func() -> bool: return police.units.size() == police.UNITS and _patrol_unit(police) >= 0,
			90.0)
	_check(out, "the fleet is made, a patrol out round the player")
	if not out:
		return _finish()
	await _on_foot(police)
	await _in_car(police)
	_finish()


## A police car on patrol, on the map, whose officer is in: its number, -1 none.
func _patrol_unit(police: Node) -> int:
	for u: RefCounted in police.units:
		if u.on_map() and u.job == police.Unit.PATROL and not police.arrest.out.has(u.index):
			return u.index
	return -1


## The player on foot `ahead` m in front of police car `i` (on its lane), with a car they stole beside them: its key.
func _stage(police: Node, i: int, ahead: float, drive: bool) -> String:
	var bot: Object = police.units[i].driver
	var f: Vector3 = bot.car.global_basis.z
	f.y = 0.0
	var at: Vector3 = bot.car.global_position + f.normalized() * ahead
	var ground: Vector3 = load("res://scripts/online/garages.gd")._at(at.x, -at.z)
	if _main.driving:
		_main.exit_car()
	_main.player.teleport(ground + Vector3.UP * 0.3)
	await _frames(20)
	var car: Node = _main.spawn_car_near_player("sedan")
	_main.enter_car(car)
	await _frames(10)
	var key: String = _main.carjack.key_of(car)
	if not drive:                           # (the car stolen out of the police car's way)
		_main.exit_car()
		_main.player.teleport(ground + Vector3.UP * 0.3)
		car.place(Transform3D(Basis(), bot.car.global_position - f.normalized() * 40.0 + Vector3.UP * 3.0))
	await _frames(10)
	return key


func _on_foot(police: Node) -> void:
	var arrest: Node = police.arrest
	var people: Node = _main.people
	var me: String = people.my_id()
	var items: Node = _main.items
	_check(items.inventory.has("taser") and items.inventory.has("net_gun"), "the player has a taser and a net gun")
	var money: int = _main.game_mode.test_money
	var i := _patrol_unit(police)
	var key := await _stage(police, i, 14.0, false)
	police.report(1, Vector2(_main.player.global_position.x, -_main.player.global_position.z), key)
	var t0 := Time.get_ticks_msec()
	var got_out := await _until(func() -> bool:
		_trace(police, i)
		return not arrest.officers.is_empty(), 120.0)
	_check(got_out, "a car stops by them, its officer gets out (%.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not got_out:
		return
	var unit: int = arrest.officers.keys()[0]
	var car: Node = police.units[unit].car
	_check(car.driver_away and police.units[unit].driver.braked, "...the car halted, nobody at its wheel")
	# the player may stun an officer (no more stars for it): they drop, get up, go on
	var officer: Node3D = arrest.officers[unit]
	people.hit(officer.person_id, "tased", 2.0, 1)
	await _frames(2)
	_check(not officer.person_up() and police.level == 1, "an officer tased by the player drops (still one star)")
	var up := await _until(func() -> bool: return officer.person_up(), 8.0)
	_check(up, "...gets up and goes on")
	var down := await _until(func() -> bool: return people.is_down(me), 60.0)
	_check(down, "they stun the player (%s)" % people.effect_of(me)[0])
	var carried := await _until(func() -> bool: return people.is_carried(me), 60.0)
	_check(carried, "...pick them up")
	var done := await _until(func() -> bool: return arrest.arrests >= 1, 90.0)
	_check(done, "...and put them in the car: arrested")
	await _frames(30)
	var at: Vector3 = _main.player.global_position
	var release: Vector3 = police.release.origin
	_check(Vector2(at.x - release.x, at.z - release.z).length() < 3.0 and not people.is_down(me),
			"let go by the sous-préfecture, standing (%.1f m off)" % Vector2(at.x - release.x, at.z - release.z).length())
	_check(police.level == 0 and police.cases.is_empty(), "no star any more")
	_check(not items.inventory.has("taser") and not items.inventory.has("net_gun")
			and not items.inventory.has("taser_cartridge"), "the weapons and their ammunition seized")
	var fine: int = money - int(_main.game_mode.test_money)
	_check(fine == 1000, "the fine paid: %d €" % fine)
	var back := await _until(func() -> bool: return arrest.officers.is_empty(), 60.0)
	_check(back and not car.driver_away and not police.units[unit].driver.braked,
			"the officer back in, the car on its way again")
	var u: RefCounted = police.units[unit]  # (not only on its way: it drives off, its engine pulling; still on the map)
	var top := [0.0]                        # (gliding far from us, let go by the sous-préfecture: its driver's speed)
	await _until(func() -> bool:
		if u.on_map() and not car.stowed:
			top[0] = maxf(top[0], u.driver._speed if u.driver.gliding else absf(car.speed()))
		return top[0] > 4.0, 20.0)
	_check(top[0] > 4.0, "...and it drives off (%.0f km/h)" % (top[0] * 3.6))


func _in_car(police: Node) -> void:
	var arrest: Node = police.arrest
	var people: Node = _main.people
	var me: String = people.my_id()
	var found := await _until(func() -> bool: return _patrol_unit(police) >= 0, 30.0)
	_check(found, "a car on patrol")
	var i := _patrol_unit(police)
	var arrests_before: int = arrest.arrests
	var key := await _stage(police, i, 14.0, true)
	var car: Node = _main.driving
	police.report(1, Vector2(car.global_position.x, -car.global_position.z), key)
	var pull := await _until(func() -> bool:
		_trace(police, i)
		return arrest._pulls.has(1), 150.0)
	_check(pull, "stopped in the stolen car: an officer at the door pulls")
	if not pull:
		return
	_check(arrest.struggling(), "...the keys to press on the screen")
	arrest._h_pull(arrest._pulls[1]["seq"])
	await _frames(5)
	_check(_main.driving == car and not people.is_down(me), "the right keys: they hold on, still at the wheel")
	var staggers: bool = arrest.out.values().any(func(o: Dictionary) -> bool: return o["state"] == arrest.STAGGER)
	_check(staggers, "...the officer staggers back")
	var again := await _until(func() -> bool: return arrest._pulls.has(1), 30.0)
	_check(again, "it pulls again")
	if not again:
		return
	var seq: Array = arrest._pulls[1]["seq"]
	arrest._h_pull([(int(seq[0]) + 1) % 4])
	await _frames(5)
	_check(_main.driving == null and people.is_down(me), "a wrong key: dragged out, tased")
	var done := await _until(func() -> bool:
		_trace(police, -1)
		return arrest.arrests > arrests_before, 90.0)
	_check(done, "...carried to the car: arrested")


var _trace_t := 0


## Every second: car `i` (or the officers out, -1) and the case.
func _trace(police: Node, i: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _trace_t < 1000:
		return
	_trace_t = now
	var me: Vector3 = _main.player.global_position
	var c: RefCounted = police.cases.get(1)
	var line := "     case %s seen %s |" % [c.level if c else "-", c.seen if c else "-"]
	if i >= 0:
		var u: RefCounted = police.units[i]
		var bot: Object = u.driver
		line += " car %d job %d d %.1f state %d reason %s arrived %s braked %s" % [i, u.job,
				bot.car.global_position.distance_to(me), bot.state, bot.reason, bot.arrived, bot.braked]
	for unit: int in police.arrest.out:
		var o: Dictionary = police.arrest.out[unit]
		var n: Node3D = police.arrest.officers.get(unit)
		line += " | officer %d state %d d %.1f" % [unit, o["state"], n.global_position.distance_to(me) if n else -1.0]
		if n:
			line += " speed %.1f goal %.1f pos %s goal %s" % [n.speed, n.global_position.distance_to(n._goal), n.global_position.snapped(Vector3.ONE * 0.1), n._goal.snapped(Vector3.ONE * 0.1)]
	line += " | me down %s carried %s" % [_main.people.is_down(_main.people.my_id()), _main.people.is_carried(_main.people.my_id())]
	print(line)


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
