extends SceneTree
## PTA Online's stunts (ONLINE_MILESTONES.md O6, scripts/online/stunts.gd), played solo (PLATEAU_MODE=online, a sedan in
## the garage). The role is the first argument after `--`:
## - `--check`: the stunt spots (world/stunts.json: tried in the game, on the maps); a sedan driven off the best spot
##   (real physics) pays the spot's first-time reward, then a small one; jumping it again and again (scripted flights)
##   pays less each time; a scripted backflip and barrel roll pay, a landing on the roof doesn't, nor a flight with a
##   teleport in it; a jump away from the spots pays its air time only; the wallet follows. ~1.5 min.
## - `--trial`: drives a sedan off every spot of world/stunts.json as tools/online/stunts.py wrote them (candidates
##   found on the map's ground) at its speed, and faster when it doesn't fly; keeps those it flies off at least
##   TRIAL_AIR s (landing on its wheels, unhurt, out of the water, not far longer than found: TRIAL_MORE) (the BEST of them, the longest flights first) with what it measured, and writes the file back.
## - `--client=TOKEN` (tools/test_stunts.sh: an official server, the accounts service): Stunter_1 gets their sedan out at
##   Télécom Paris, jumps the best spot (scripted flights, the car simulated here, judged on the server): the first-time
##   reward lands in the wallet with its popup, then a small one.
## Exit code 1 on failure.

const Layers = preload("res://scripts/physics_layers.gd")
const Water = preload("res://scripts/water.gd")
const SPOTS := "res://world/stunts.json"
const RUN_UP := 45.0                        # m before the take-off the car starts
const TRIAL_AIR := 0.7                      # s in the air a spot must give
const TRIAL_FASTER := [0.0, 20.0, 40.0]     # km/h over the spot's speed tried in turn
const TRIAL_MORE := 2.5                     # times the flight tools/online/stunts.py found at most (longer: it fell into
											# something the heightmap doesn't have, a lake...)
const BEST := 12


var _main: Node
var _mode: Node
var _stunts: Node
var Stunts: GDScript                        # scripts/online/stunts.gd (loaded at run time: preloaded, it would compile
											# before the Settings autoload exists and stay broken)
var _what := ""
var _arg := ""
var _failures: PackedStringArray = []
var _car: Node
var _ride := 0.0                            # m from the car's origin down to the ground, at rest


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["check", "trial", "client"]:
			_what = kv[0]
			_arg = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
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


func _run() -> void:
	if _what == "client":
		await _client()
		print("%d failure(s)" % _failures.size())
		quit(1 if _failures.size() > 0 else 0)
		return
	OS.set_environment("PLATEAU_MODE", "online")
	OS.set_environment("PLATEAU_ONLINE_VEHICLES", "sedan")
	OS.set_environment("PLATEAU_CARS", "0")
	OS.set_environment("PLATEAU_BUSES", "0")
	OS.set_environment("PLATEAU_ONLINE_TOW", "100000")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 60.0)
	_mode = _main.game_mode
	_stunts = _mode.stunts
	Stunts = _stunts.get_script()
	await _frames(5)
	var problem: String = _mode.spawn_for(_mode.me(), "telecom", 1, "sedan", false)
	_car = _mode.car_of(_mode.mine)
	_check(problem == "" and _car != null, "the garage's sedan comes out (%s)" % problem)
	if _car:
		_main.driving = _car                # the judge counts it as ours; the tests drive it
		await _frames(90)
		_ride = _car.global_position.y - _ground(_car.global_position.x, -_car.global_position.z)
		match _what:
			"check":
				await _solo()
			"trial":
				await _trial()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


# ---------------------------------------------------------------- driving

## The ground's height (Godot y) under map point (x, y), from the physics (a client's GroundMap may not be there yet
## when it joins), the car left out.
func _ground(x: float, y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, -y), Vector3(x, -300.0, -y), Layers.SOLID)
	q.exclude = _car.bodies().map(func(b: Node) -> RID: return b.get_rid()) if _car else []
	var hit: Dictionary = _main.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0

static func _dir(spot: Dictionary) -> Vector3:
	var a := deg_to_rad(float(spot["yaw"]))
	return Vector3(sin(a), 0.0, -cos(a))


## Where the car stands, facing `dir` (Godot), its origin over map point (x, y) at its resting height.
func _xf(x: float, y: float, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3(x, _ground(x, y) + _ride + 0.05, -y))


## Puts the car at `xf` as new (full health, not frozen); the judge starts afresh with it (the tests' hand moves it, not
## a patched game: no teleport).
func _put_car(xf: Transform3D) -> void:
	for b in _car.bodies():
		b.freeze = false
	_car.set_health(_car.max_health, false)
	_car.place(xf)
	_stunts.rides.erase(_mode.me())


## Drives the car off `spot` for real: it starts RUN_UP m before the take-off, held at `kmh` straight on until the
## take-off, then flies as the physics wants. The s its first flight lasted (all of its underside in the air, as the judge
## sees it), 0 when it didn't fly or didn't land on its wheels unhurt (as the judge wants: Stunts.UPRIGHT, CRASH).
func _drive_jump(spot: Dictionary, kmh: float) -> float:
	var dir := _dir(spot)
	var lip := Vector3(spot["x"], 0.0, -float(spot["y"]))
	var start := lip - dir * RUN_UP
	_put_car(_xf(start.x, -start.z, dir))
	_main.player.teleport(start + Vector3.UP * 3.0, 0.0)
	await _frames(20)
	var v := kmh / 3.6
	var base := NAN
	var air := 0.0
	var landed := -1.0                      # s since the first flight ended
	for i in 60 * 12:
		await physics_frame
		var along: float = (_car.global_position - lip).dot(dir)
		var gap: float = Stunts.ground_gap(_car)
		if along < -1.0 and air == 0.0:
			var lv: Vector3 = _car.linear_velocity
			_car.linear_velocity = dir * v + Vector3(0.0, lv.y, 0.0)
			_car.angular_velocity = Vector3(_car.angular_velocity.x, 0.0, _car.angular_velocity.z)
			_car.set_health(_car.max_health, false)   # (held at speed by hand: the jolts aren't crashes)
			if along > -RUN_UP + 10.0 and gap < INF:
				base = gap if is_nan(base) else lerpf(base, gap, 0.1)
			continue
		if landed < 0.0:
			if not is_nan(base) and gap < INF and gap > base + Stunts.AIR_LIFT:
				air += 1.0 / 60.0
			elif air > 0.0 or along > 30.0:
				landed = 0.0
		else:
			landed += 1.0 / 60.0
			if landed > Stunts.LAND_CHECK + 0.4:
				break
	var upright: bool = _car.global_basis.y.normalized().y >= Stunts.UPRIGHT
	var unhurt: bool = _car.health >= _car.max_health * (1.0 - Stunts.CRASH)
	var wet := not is_nan(Water.surface_at(_car.global_position))
	return air if upright and unhurt and not wet else 0.0


## A scripted flight (the car frozen, moved by hand): from map point `from` (on the ground) along `dir` (Godot) at `speed`
## m/s, up at `up` m/s, turning `pitch` and `roll` whole turns (signed: nose over / side over) on the way, until it comes
## down on the ground; then let go (`land_turned`: the last half turn of roll left out: it lands upside down). `jump`: m
## it jumps sideways for a tick halfway (a teleport there and back).
func _fly(from: Vector2, dir: Vector3, speed: float, up: float, pitch := 0.0, roll := 0.0, land_turned := false,
		jump := 0.0, settle := 15) -> void:
	var base := Basis.looking_at(-dir, Vector3.UP)
	var start := Vector3(from.x, _ground(from.x, from.y) + _ride, -from.y)
	_put_car(Transform3D(base, start))
	await _frames(settle)
	for b in _car.bodies():
		b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC   # (kinematic, as a taken-over car's, moving it would crash it)
		b.freeze = true
	var g := 9.8
	var t_end := 2.0 * up / g
	var side := Vector3.ZERO
	var jumped := false
	var t := 0.0
	var turned := roll * TAU - (PI if land_turned else 0.0)
	while true:
		await physics_frame
		t += 1.0 / 60.0
		var k := minf(t / t_end, 1.0)
		side = Vector3.ZERO
		if jump != 0.0 and not jumped and k > 0.5:
			side = base.x * jump
			jumped = true
		var p := start + side + dir * speed * t + Vector3.UP * (up * t - 0.5 * g * t * t)
		var ground := _ground(p.x, -p.z) + _ride
		var b := base * Basis(Vector3.RIGHT, pitch * TAU * k) * Basis(Vector3.BACK, turned * k)
		if t > 0.3 and p.y <= ground:
			p.y = ground + (1.2 if land_turned else 0.0)
			_car.global_transform = Transform3D(b, p)
			break
		_car.global_transform = Transform3D(b, p)
	for body in _car.bodies():
		body.freeze = false
	await _frames(int(60 * (Stunts.LAND_CHECK + 0.6)))


func _events_since(n: int) -> Array:
	return _stunts.events.slice(n)


# ---------------------------------------------------------------- --check

func _solo() -> void:
	var spots: Array = _stunts.spots
	var ids := {}
	for s: Dictionary in spots:
		ids[s["id"]] = true
	_check(spots.size() >= 6 and ids.size() == spots.size(), "%d stunt spots, ids unique" % spots.size())
	_check(spots.all(func(s: Dictionary) -> bool: return str(s["name"]) != "" and s.get("tried", false)),
			"every spot named and tried in the game (tools/test_stunts.gd --trial)")
	var places: Array = _main.map_places().filter(func(p: Array) -> bool: return p[1] == "stunt")
	_check(places.size() == spots.size(), "the spots are on the maps (%d)" % places.size())
	var pay: Dictionary = _stunts.pay
	var money0: int = _mode.test_money

	# the best spot for real: big the first time, small after
	var spot: Dictionary = spots[0]
	var n: int = _stunts.events.size()
	var air := await _drive_jump(spot, float(spot["speed"]))
	await _frames(30)
	var got := _events_since(n)
	print("     %s at %d km/h: %.2f s in the air, %s" % [spot["name"], spot["speed"], air, str(got)])
	_check(got.size() == 1 and got[0][2] == spot["name"] and got[0][4] and int(got[0][3]) >= int(pay["spot_first"]),
			"driven off %s (%.1f s in the air): its first-time reward (%s)" % [spot["name"], air, str(got)])
	var hud: String = _stunts.hud_text()
	_check(hud.contains(str(spot["name"]).to_upper()) and hud.contains("FIRST TIME"), "the popup: %s" % hud.replace("\n", " / "))
	n = _stunts.events.size()
	air = await _drive_jump(spot, float(spot["speed"]))
	await _frames(30)
	got = _events_since(n)
	var second := int(got[0][3]) if got.size() == 1 else -1
	_check(got.size() == 1 and got[0][2] == spot["name"] and not got[0][4] and second > 0 \
			and second < int(pay["spot_first"]) / 3, "again (%.1f s): a small reward (%s)" % [air, str(got)])

	# farming it: less each time
	var amounts := []
	var dir := _dir(spot)
	var lip := Vector2(spot["x"], spot["y"])
	for i in 5:
		n = _stunts.events.size()
		await _fly(lip - Vector2(dir.x, -dir.z) * 3.0, dir, float(spot["speed"]) / 3.6, 9.0)
		got = _events_since(n)
		amounts.append(int(got[0][3]) if got.size() == 1 and got[0][2] == spot["name"] else -1)
	print("     farming %s: %s €" % [spot["name"], str(amounts)])
	var falling := amounts.all(func(a: int) -> bool: return a >= 0)
	for i in range(1, amounts.size()):
		falling = falling and (amounts[i] < amounts[i - 1] or amounts[i] == 0)
	_check(falling and amounts[-1] < second * 0.3, "jumping it again and again pays less each time: %s €" % str(amounts))

	# flips, on the Télécom car park (away from the spots)
	var bay: Transform3D = _mode.garages.get_garage("telecom")["bays"][1]["xf"]
	var along := bay.basis.z.normalized()
	var park := Vector2(bay.origin.x, -bay.origin.z)
	n = _stunts.events.size()
	await _fly(park, along, 4.5, 8.0, -1.0)
	got = _events_since(n)
	_check(got.size() == 1 and str(got[0][2]).contains("Backflip") and int(got[0][3]) > 0,
			"a backflip, landed on its wheels, pays (%s)" % str(got))
	n = _stunts.events.size()
	await _fly(park, along, 4.5, 8.0, 0.0, 1.0)
	got = _events_since(n)
	_check(got.size() == 1 and str(got[0][2]).contains("Barrel roll") and int(got[0][3]) > 0,
			"a barrel roll pays (%s)" % str(got))
	n = _stunts.events.size()
	await _fly(park, along, 4.5, 8.0, 0.0, 1.0, true)
	got = _events_since(n)
	_check(got.is_empty() and _stunts.hud_text().contains("roof"), "landed on its roof: nothing (%s; %s)" % [str(got),
			_stunts.hud_text().replace("\n", " / ")])
	n = _stunts.events.size()
	await _fly(park, along, 4.5, 8.0, 0.0, 0.0, false, 30.0)
	got = _events_since(n)
	_check(got.is_empty(), "a flight with a 30 m jump in it pays nothing (%s)" % str(got))
	await _frames(int(60 * Stunts.VOID))
	n = _stunts.events.size()
	await _fly(park, along, 4.5, 8.0)
	got = _events_since(n)
	_check(got.size() == 1 and str(got[0][2]).begins_with("Air") and int(got[0][3]) > 0,
			"a jump away from the spots pays its air time (%s)" % str(got))
	var total := 0
	for e: Array in _stunts.events:
		total += int(e[3])
	_check(_mode.test_money == money0 + total and _main.economy.balance == _mode.test_money,
			"the wallet follows: %d € (+%d €)" % [_mode.test_money, total])


# ---------------------------------------------------------------- --trial

## Names numbered by tools/online/stunts.py ("Path jump, ENSTA Paris 3") numbered again among those kept (no number
## when one is left).
static func _renumber(spots: Array) -> void:
	var re := RegEx.create_from_string("^(.*) \\d+$")
	var bases := {}
	for s: Dictionary in spots:
		var m := re.search(str(s["name"]))
		s["base"] = m.get_string(1) if m and s["src"] == "terrain" else str(s["name"])
		bases[s["base"]] = bases.get(s["base"], 0) + 1
	var count := {}
	for s: Dictionary in spots:
		var b: String = s["base"]
		count[b] = count.get(b, 0) + 1
		s["name"] = b if bases[b] == 1 else "%s %d" % [b, count[b]]
		s.erase("base")


func _trial() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPOTS))
	var kept := []
	for s: Dictionary in data["spots"]:
		var best := 0.0
		var at := 0.0
		for more: float in TRIAL_FASTER:
			var air := await _drive_jump(s, float(s["speed"]) + more)
			if air > maxf(2.0, float(s["air"]) * TRIAL_MORE):
				print("     %s: %.2f s at %d km/h, more than it should (%.2f s): not a jump" % [s["name"], air,
						float(s["speed"]) + more, s["air"]])
				air = 0.0
			if air > best:
				best = air
				at = float(s["speed"]) + more
			if air >= TRIAL_AIR:
				break
		print("%s %-50s %.2f s at %d km/h" % ["keep" if best >= TRIAL_AIR else "    ", s["name"], best, at])
		if best >= TRIAL_AIR:
			s["speed"] = roundi(at)
			s["air"] = snappedf(best, 0.01)
			s["air_min"] = snappedf(clampf(best * 0.5, 0.4, 0.8), 0.01)
			s["tried"] = true
			kept.append(s)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["air"] > b["air"])
	data["spots"] = kept.slice(0, BEST)
	data["schema"] = int(data["schema"])
	_renumber(data["spots"])
	_check(not kept.is_empty(), "%d spots fly, %d kept" % [kept.size(), data["spots"].size()])
	if kept.is_empty():
		return                              # (the candidates stay for another try)
	var f := FileAccess.open(ProjectSettings.globalize_path(SPOTS), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " ", false) + "\n")
	f.close()
	print("-> %s" % SPOTS)


# ---------------------------------------------------------------- LAN (tools/test_stunts.sh)

func _client() -> void:
	load("res://scripts/accounts.gd").keep(_arg, "Stunter_1", false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var joined := await _until(func() -> bool: return _main.mode == "client", 60.0)
	_check(joined and _main.mode_id == "online", "joined PTA Online")
	if not joined or not await _until(func() -> bool: return _main.economy.username != "", 15.0):
		_check(false, "logged in")
		return
	_mode = _main.game_mode
	_stunts = _mode.stunts
	Stunts = _stunts.get_script()
	await _frames(5)
	var got := []
	_mode.answered.connect(func(ok: bool, text: String) -> void: got.append([ok, text]))
	var garage: Dictionary = _mode.garages.get_garage("telecom")
	var spot: Dictionary = _stunts.spots[0]   # (the --check's: its scripted hops clear its ground there)
	var stand: Array = _mode.garages.stand_spot(garage)
	_main.player.teleport(stand[0], stand[1])
	await _frames(30)
	_mode.to_host(_mode, "_h_spawn", ["telecom", 1, "sedan"])   # (the only vehicle of a fresh database)
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	_car = _mode.car_of(_mode.mine)
	_check(not got.is_empty() and got[0][0] and _car != null, "the sedan is out: %s" % str(got))
	if _car == null:
		return
	_main.player.teleport(_car.to_global(_car.extents_center + Vector3(_car.half_extents.x + 1.0, 0.0, 0.0)))
	await physics_frame
	_main.net.request_drive(_car)
	_check(await _until(func() -> bool: return _main.driving == _car \
			and _main.net.owner_of.get(_car.net_id, 0) == _main.net.me(), 10.0), "got in: we simulate it")
	var dir := _dir(spot)
	var from: Vector2 = Vector2(spot["x"], spot["y"]) - Vector2(dir.x, -dir.z) * 3.0
	_ride = 0.6                             # (to drop it there; then measured)
	_put_car(_xf(from.x, from.y, dir))
	await _frames(90)
	_ride = _car.global_position.y - _ground(_car.global_position.x, -_car.global_position.z)
	var pay: Dictionary = _stunts.pay
	for first: bool in [true, false]:
		var before: int = _main.economy.balance
		for p in _stunts._hud.get_children() if _stunts._hud else []:
			p.free()
		# (the car moved there by hand: the server sees a teleport and judges nothing for Stunts.VOID s)
		await _fly(from, dir, float(spot["speed"]) / 3.6, 9.0, 0.0, 0.0, false, 0.0, int(60 * (Stunts.VOID + 1.5)))
		var popped := await _until(func() -> bool: return _stunts.hud_text().contains(str(spot["name"]).to_upper()), 10.0)
		await _until(func() -> bool: return _main.economy.balance != before, 5.0)
		var gain: int = _main.economy.balance - before
		var hud: String = _stunts.hud_text().replace("\n", " / ")
		if first:
			_check(popped and hud.contains("FIRST TIME") and gain >= int(pay["spot_first"]),
					"jumped %s: the first-time reward, +%d € in the wallet (%s)" % [spot["name"], gain, hud])
		else:
			_check(popped and not hud.contains("FIRST TIME") and gain > 0 and gain < int(pay["spot_first"]) / 3,
					"again: a small reward, +%d € (%s)" % [gain, hud])

