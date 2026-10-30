extends SceneTree
## PTA Online's fires and firefighter job (ONLINE_MILESTONES.md O7, scripts/online/fires.gd + fire_job.gd), played solo
## (PLATEAU_MODE=online). The role is the first argument after `--`:
## - `--check`: the fire spots (world/fires.json, every kind); no fire while nobody is on duty; duty at the fire station
##   (a lent truck comes out); an alarm comes and is on the maps and the HUD; a fire at full heat spreads to the spot next
##   to it; the truck's real jet (aimed by a camera, the fire button held) puts a building fire out and pays, the wallet
##   follows; a fire hosed by two firefighters pays each their share; their own truck pays ×1.5 and a quick answer +50 %;
##   a teleported truck's water doesn't count; off duty, the fires die down. ~1.5 min.
## - `--client=TOKEN` (tools/test_fires.sh: an official server lighting its alarms at the building spot nearest the fire
##   station, PLATEAU_FIRE_SPOT=building, the accounts service): Firefighter_1 goes on duty at the fire station, sees the
##   alarm's fire, drives the lent truck to it (put there), hoses it out with the real jet (flown again on the server
##   from the truck's state) and is paid.
## Exit code 1 on failure.

const Layers = preload("res://scripts/physics_layers.gd")
const STATION := "fire-station"

var _main: Node
var _mode: Node
var _fires: Node
var _job: Node
var _what := ""
var _arg := ""
var _failures: PackedStringArray = []
var _truck: Node
var _eye: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["check", "client"]:
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


func _trigger(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _run() -> void:
	if _what == "client":
		await _client()
	else:
		OS.set_environment("PLATEAU_MODE", "online")
		OS.set_environment("PLATEAU_CARS", "0")
		OS.set_environment("PLATEAU_BUSES", "0")
		OS.set_environment("PLATEAU_ONLINE_TOW", "100000")
		OS.set_environment("PLATEAU_FIRE_FIRST", "2")
		OS.set_environment("PLATEAU_FIRE_SPREAD", "3")
		_main = load("res://scenes/main.tscn").instantiate()
		_main.debug_cars = false
		root.add_child(_main)
		await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 60.0)
		_mode = _main.game_mode
		_fires = _mode.fires
		_job = _mode.fire_job
		await _frames(5)
		await _solo()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


# ---------------------------------------------------------------- helpers

## The ground's height (Godot y) under map point (x, y), from the physics, the truck left out.
func _ground(x: float, y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, -y), Vector3(x, -300.0, -y), Layers.SOLID)
	q.exclude = _truck.bodies().map(func(b: Node) -> RID: return b.get_rid()) if _truck else []
	var hit: Dictionary = _main.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


## Where the truck can stand to hose fire `f` (fires.gd Fire): 14-34 m from it (buildings: in front of the facade),
## level ground, nothing in its footprint, a clear line from its cannon to the flames. Transform or null.
func _hose_spot(f: Object) -> Variant:
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var out := Vector3(sin(f.yaw), 0.0, -cos(f.yaw)) if f.kind == "building" else Vector3.FORWARD
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.6, 10.0)
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = box
	shape.collision_mask = Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	shape.exclude = _truck.bodies().map(func(b: Node) -> RID: return b.get_rid())
	var turns := [0.0, 0.35, -0.35, 0.7, -0.7] if f.kind == "building" else range(12).map(func(k: int) -> float:
			return k * TAU / 12.0)
	for d: float in [20.0, 16.0, 26.0, 32.0]:
		for a: float in turns:
			var dir := out.rotated(Vector3.UP, a)
			var p: Vector3 = f.pos + dir * d
			var g := _ground(p.x, -p.z)
			var side := dir.cross(Vector3.UP).normalized()   # the truck stands across the line to the fire
			var level := absf(_ground(p.x + side.x * 4.0, -(p.z + side.z * 4.0)) - g) < 0.6 \
					and absf(_ground(p.x - side.x * 4.0, -(p.z - side.z * 4.0)) - g) < 0.6
			if not level:
				continue
			var xf := Transform3D(Basis.looking_at(side, Vector3.UP), Vector3(p.x, g, p.z))
			shape.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 2.0)
			if not space.intersect_shape(shape, 1).is_empty():
				continue
			var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 3.5, f.pos + Vector3.UP * 1.2,
					Layers.SOLID | Layers.VEGETATION | Layers.PROPS)
			q.exclude = shape.exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(f.pos + Vector3.UP * 1.2) < 2.5:
				return xf.translated(Vector3.UP * 0.3)
	return null


## Puts the truck at `xf` (not a patched game: the judge's teleport check is reset).
func _put_truck(xf: Transform3D) -> void:
	for b in _truck.bodies():
		b.freeze = false
	_truck.place(xf)
	var d: Object = _job.duties.get(_mode.me())
	if d:
		d.has_last = false
		d.void_t = 0.0


## Aims the truck's cannon at `f` (a camera behind the truck looking at the flames) and holds the fire button until the
## fire is out or `timeout` s. Whether it went out.
func _hose(f: Object, timeout: float) -> bool:
	if _eye == null:
		_eye = Camera3D.new()
		root.add_child(_eye)
	_eye.global_position = _truck.to_global(Vector3(0.0, 4.5, 0.0))
	_eye.look_at(f.pos + Vector3.UP * 1.0)
	_eye.make_current()
	await _frames(150)                      # the turret turns
	_trigger(true)
	var hints := {}
	var out := await _until(func() -> bool:
		if not _job.hint_text().is_empty():
			hints[_job.hint_text().get_slice(":", 0)] = true
		return f.out, timeout)
	_trigger(false)
	await _frames(30)
	print("     hints seen: %s" % ", ".join(hints.keys()))
	return out


# ---------------------------------------------------------------- solo

func _solo() -> void:
	var kinds := {}
	for s: Dictionary in _fires.spots:
		kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
	_check(_fires.spots.size() > 1000 and kinds.size() == 5, "fire spots: %s" % str(kinds))
	await _frames(240)
	_check(_fires.fires.is_empty(), "nobody on duty: no fire")

	# duty
	var g: Dictionary = _mode.garages.get_garage(STATION)
	var stand: Array = _mode.garages.stand_spot(g)
	_main.player.teleport(stand[0], stand[1])
	await _frames(10)
	var rows: Array = _job.offer(_mode.me(), STATION)
	_check(rows.size() == 1 and rows[0]["duty"] == "fire" and "lent fire truck" in str(rows[0]["note"]),
			"the fire station offers firefighter duty: %s" % str(rows))
	var r: Array = _job.duty_for(_mode.me(), STATION)
	_truck = _mode.car_of(_mode.mine)
	_check(r[0] and _truck != null and _truck.model_name == "fire-truck" and _job.duties.has(_mode.me()),
			"on duty, a lent fire truck is out: %s" % r[1])
	if _truck == null:
		return
	await _frames(5)
	_check("FIREFIGHTER" in _job.hud_text(), "the HUD says so: %s" % _job.hud_text().replace("\n", " | "))

	# the first alarm
	var lit := await _until(func() -> bool: return not _fires.burning().is_empty(), 10.0)
	_check(lit, "an alarm comes")
	if lit:
		var f: Object = _fires.burning()[0]
		var d: float = f.xy().distance_to(Vector2(_truck.global_position.x, -_truck.global_position.z))
		_check(d >= _job.ALARM_MIN - 1.0 and d <= _job.ALARM_MAX + 1.0, "%s, %d m away" % [f.label(), roundi(d)])
		_check(f.fx != null and is_instance_valid(f.fx) and f.fx.kind == f.kind, "it is drawn")
		await _frames(70)
		_check(_mode.map_places().any(func(p: Array) -> bool: return p[1] == "blaze"), "it is on the maps")
		_check(f.label() in _job.hud_text() and _main.waypoint == f.xy(),
				"the HUD names it, the waypoint is on it: %s" % _job.hud_text().replace("\n", " | "))
	_job.alarm_gap = 1e9                    # no more alarms: the tests light their own
	_job._alarm_t = 1e9
	_fires.clear()
	await _frames(10)

	# spreading: the car park next to the station, a car with another beside it
	var pair := []
	for s: Dictionary in _fires.spots:
		if s["kind"] != "car":
			continue
		for t: Dictionary in _fires.spots:
			if t["kind"] == "car" and t != s and Vector2(s["x"], s["y"]).distance_to(Vector2(t["x"], t["y"])) < 8.0:
				pair = [s, t]
				break
		if not pair.is_empty():
			break
	_check(not pair.is_empty(), "two cars side by side in a car park")
	if not pair.is_empty():
		var f: Object = _job.alarm(pair[0])
		_check(f != null and f.kind == "car" and f.fx and f.fx.get_node_or_null("BurntCar") != null,
				"a car fire (a burnt-out car stands there)")
		if f:
			f.heat = 1.0
			var spread := await _until(func() -> bool: return _fires.of_alarm(f.alarm).size() >= 2, 8.0)
			var others: Array = _fires.of_alarm(f.alarm).filter(func(o: Object) -> bool: return o != f)
			_check(spread and others[0].kind == "car" and others[0].xy().distance_to(f.xy()) < 9.5,
					"at full heat it spreads to a car beside it (%.1f m)" % (others[0].xy().distance_to(f.xy()) if spread
					else -1.0))
	_fires.clear()
	# a grass fire spreads over the grass
	var lawn := {}
	for s: Dictionary in _fires.spots:
		if s["kind"] == "grass":
			lawn = s
			break
	if not lawn.is_empty():
		await _frames(10)
		var f: Object = _job.alarm(lawn)
		if f:
			f.heat = 1.0
			var spread := await _until(func() -> bool: return _fires.of_alarm(f.alarm).size() >= 2, 8.0)
			var o: Array = _fires.of_alarm(f.alarm).filter(func(x: Object) -> bool: return x != f)
			_check(spread and o[0].kind == "grass" and o[0].xy().distance_to(f.xy()) < 12.0,
					"a grass fire spreads over the grass (%.1f m)" % (o[0].xy().distance_to(f.xy()) if spread else -1.0))
	_fires.clear()
	_fires.spread_every = 1e9
	await _frames(10)

	# the real jet on a building fire
	var target: Dictionary = _job.nearest_spot("building")
	var f: Object = _job.alarm(target) if not target.is_empty() else null
	_check(f != null, "a building fire by the fire station: %s" % (f.label() if f else "none"))
	if f == null:
		return
	var xf: Variant = _hose_spot(f)
	_check(xf != null, "a place for the truck in front of it")
	if xf == null:
		return
	_put_truck(xf)
	_main.enter_car(_truck)
	await _frames(60)
	var money: int = _mode.test_money
	var out := await _hose(f, 40.0)
	_check(out, "the water cannon puts it out (%.0f s of fire)" % f.t)
	var mine: Array = _job.events.filter(func(e: Array) -> bool: return e[1] == f.id)
	var base := float(_job.pay["building"])
	_check(mine.size() == 1 and mine[0][2] >= roundi(base) and mine[0][2] <= roundi(base * 1.5) + 1,
			"paid for it: %s" % str(mine))
	_check(mine.size() == 1 and _mode.test_money == money + int(mine[0][2]) and _main.economy.balance == _mode.test_money,
			"the wallet follows (%d €)" % _mode.test_money)

	# two firefighters share a fire (the second on duty, its water given here)
	var d2: Object = load("res://scripts/online/fire_job.gd").Duty.new()
	d2.peer = 2
	d2.account = 99
	d2.username = "Second"
	d2.car_id = _mode.mine
	_job.duties[2] = d2
	var bins: Array = _fires.spots.filter(func(s: Dictionary) -> bool: return s["kind"] == "bin")
	var b := _fires.light(bins[0], 1000.0) as Object
	var need := ceili(float(_fires.KINDS["bin"]["water"]) * 30.0)   # packets that put out a fire at full heat
	b.heat = 1.0
	_fires.water(b, 2, false, need / 3)
	_fires.water(b, _mode.me(), false, need)
	var shares: Array = _job.events.filter(func(e: Array) -> bool: return e[1] == b.id)
	var full := float(_job.pay["bin"]) * (1.0 + float(_job.pay["quick_bonus"]))
	var got := {}
	for e: Array in shares:
		got[e[0]] = e[2]
	var mine_share := float(need) / (need + need / 3)
	_check(b.out and got.size() == 2 and absi(int(got.get(_mode.me(), 0)) - roundi(full * mine_share)) <= 2
			and absi(int(got.get(2, 0)) - roundi(full * (1.0 - mine_share))) <= 2,
			"two sprayers share it as their water: %s of %d €" % [str(got), roundi(full)])
	_job.duties.erase(2)

	# their own truck pays more
	var own := _fires.light(bins[1], 1000.0) as Object
	_fires.water(own, _mode.me(), true, need)
	var e2: Array = _job.events.filter(func(e: Array) -> bool: return e[1] == own.id)
	_check(e2.size() == 1 and e2[0][2] == roundi(full * float(_job.pay["owned"])),
			"their own truck ×%s, a quick answer +%d %%: %s" % [str(_job.pay["owned"]), roundi(float(_job.pay["quick_bonus"])
			* 100.0), str(e2)])

	# a teleported truck's water counts for nothing
	var late := _fires.light(bins[2], 1000.0) as Object
	_truck.place(_truck.global_transform.translated(Vector3(120.0, 0.0, 0.0)))
	await _frames(3)
	_check(not _job.counts(_mode.me()), "a teleport: the truck's water won't count")
	var heat: float = late.heat
	_fires._splashed(late.pos + Vector3.UP * 0.5, _truck)
	_check(late.heat == heat, "its water on a fire does nothing")

	# off duty: no alarms, the fires die down
	_job.end_duty(_mode.me(), "test")
	_check(_job.hud_text() == "", "off duty: the HUD goes")
	var calm := await _until(func() -> bool: return _fires.burning().is_empty(), _fires.CALM + 5.0)
	_check(calm and late.out, "nobody on duty: the fires die down")


# ---------------------------------------------------------------- client of an official server

func _client() -> void:
	load("res://scripts/accounts.gd").keep(_arg, "Firefighter_1", false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var joined := await _until(func() -> bool: return _main.mode == "client", 60.0)
	_check(joined and _main.mode_id == "online", "joined PTA Online")
	if not joined or not await _until(func() -> bool: return _main.economy.username != "", 15.0):
		_check(false, "logged in")
		return
	_mode = _main.game_mode
	_fires = _mode.fires
	_job = _mode.fire_job
	await _frames(5)
	var got := []
	_job.answered.connect(func(ok: bool, text: String) -> void: got.append([ok, text]))
	var g: Dictionary = _mode.garages.get_garage(STATION)
	var stand: Array = _mode.garages.stand_spot(g)
	_main.player.teleport(stand[0], stand[1])
	await _frames(30)
	_mode.to_host(_job, "_h_duty", [STATION])
	await _until(func() -> bool: return not got.is_empty(), 15.0)
	_check(not got.is_empty() and got[0][0], "on duty at the fire station: %s" % str(got))
	await _until(func() -> bool: return _mode.mine != "" and _mode.car_of(_mode.mine) != null, 10.0)
	_truck = _mode.car_of(_mode.mine)
	_check(_truck != null and _truck.model_name == "fire-truck" and _job.on_duty(), "a lent fire truck is out, on duty")
	if _truck == null:
		return
	var lit := await _until(func() -> bool: return not _fires.burning().is_empty(), 20.0)
	_check(lit, "the server's alarm: a fire shows here")
	if not lit:
		return
	var f: Object = _fires.burning()[0]
	_check(f.fx != null and f.kind == "building", "%s, drawn" % f.label())
	await _frames(70)
	_check(_mode.map_places().any(func(p: Array) -> bool: return p[1] == "blaze"), "on the maps (firefighters)")
	_main.player.teleport(_truck.to_global(_truck.extents_center + Vector3(_truck.half_extents.x + 1.0, 0.0, 0.0)))
	await physics_frame
	_main.net.request_drive(_truck)
	var driving := await _until(func() -> bool: return _main.driving == _truck \
			and _main.net.owner_of.get(_truck.net_id, 0) == _main.net.me(), 10.0)
	_check(driving, "in the truck: we simulate it")
	var xf: Variant = _hose_spot(f)
	_check(xf != null, "a place for the truck in front of the fire")
	if xf == null:
		return
	for b in _truck.bodies():
		b.freeze = false
	_truck.place(xf)                        # (a teleport to the server: its water counts again VOID s later)
	await _until(func() -> bool: return false, _job.VOID + 2.0)
	var money: int = _main.economy.balance
	var out := await _hose(f, 45.0)
	_check(out, "hosed it out (as the server saw the water)")
	var paid := await _until(func() -> bool: return _main.economy.balance > money, 10.0)
	_check(paid, "paid: %d € → %d €" % [money, _main.economy.balance])
