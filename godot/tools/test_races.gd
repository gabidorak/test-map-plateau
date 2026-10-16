extends SceneTree
## Headless checks for the races (scripts/races.gd, world/races.json), solo:
## - races.json has the campus lap and the bus race with their checkpoints; their start circles and leaderboards stand;
## - campus lap: a car stopped in its start circle is offered to race (a plane is not); the race key starts a countdown
##   that holds the car (throttle pressed, it stays put), then GO; checkpoints count in order only (skipping one does
##   not count), the finish circle stops the clock, the results show, the chat says it, the time is on the leaderboard
##   and in the records file; a slower time does not replace it, a faster one does; the records read back from the
##   file (and from the temporary file a crash between writing and renaming would leave);
## - bus race: a 12 m bus in its start circle is offered it alone, a car is not; a few metres off the road for under
##   OFF_TIME s it races on, for over that it is out; far off the road it is out at once;
## - a bot drives each route through every checkpoint to the finish (the 18 m bus the bus race, never off the road over
##   OFF_DIST m for long; a car the lap), and the times go on the boards.
## The records go to a file in the system's temporary folder (PLATEAU_RECORDS), not the player's. The game's clock
## (net.gd clock(), real time: races are timed on it) follows the simulation instead (SimClock), which runs much faster
## than real time here.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_races.gd
## PLATEAU_TEST_ONLY=lap,bus,bot_bus,bot_lap runs some of them.

var _records := OS.get_temp_dir().path_join("plateau_test_races/records.json")   # (no /tmp on Windows)
const BusBot = preload("res://scripts/bus_bot.gd")
const GroundMap = preload("res://scripts/ground_map.gd")

var _main: Node
var _races: Node
var _clock: SimClock
var _failures: PackedStringArray = []
var _only: PackedStringArray = []


## Keeps the game's clock on the simulation's time (plus `skip`, the time a check jumps ahead), before anything reads it.
class SimClock extends Node:
	var net: Node
	var t := 0.0
	var skip := 0.0

	func _init() -> void:
		process_physics_priority = -1000

	func _physics_process(delta: float) -> void:
		t += delta
		net.clock_shift = t + skip - Time.get_ticks_usec() / 1e6


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(_records.get_base_dir())
	for f: String in [_records, _records + ".tmp"]:
		DirAccess.remove_absolute(f)
	OS.set_environment("PLATEAU_RECORDS", _records)
	var only := OS.get_environment("PLATEAU_TEST_ONLY")
	_only = only.split(",", false) if only != "" else PackedStringArray()
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


func _wants(name: String) -> bool:
	return _only.is_empty() or name in _only


## A vehicle of `model` on the ground with its footprint centre at pipeline (x, y), facing pipeline direction `dir`.
func _vehicle(model: String, x: float, y: float, dir: Vector2) -> Node3D:
	var car: Node3D = _main.new_vehicle(model)
	_main.add_child(car)
	_place(car, x, y, dir)
	_main._add_car(car)
	return car


func _place(car: Node3D, x: float, y: float, dir: Vector2) -> void:
	var map: GroundMap = GroundMap.get_map()
	var f := Vector3(dir.x, 0.0, -dir.y).normalized()
	var b := Basis.looking_at(-f)
	var xf := Transform3D(b, Vector3(x, map.height(x, y) + 0.4, -y))
	car.place(xf.translated_local(-car.extents_center))


func _drive(car: Node3D) -> void:
	if _main.driving:
		_main.exit_car()
		await _frames(2)
	_main.enter_car(car)
	await _frames(2)


func _def(id: String) -> Dictionary:
	for d: Dictionary in _races.defs:
		if d["id"] == id:
			return d
	return {}


func _dir(c: Dictionary) -> Vector2:
	return Vector2(float(c["dir"][0]), float(c["dir"][1])) if c.has("dir") else Vector2.RIGHT


func _wait_state(states: Array, max_frames: int) -> bool:
	for i in max_frames:
		if _races.state in states:
			return true
		await physics_frame
	return _races.state in states


func _run() -> void:
	while _main.mode != "solo":
		await physics_frame
	_clock = SimClock.new()
	_clock.net = _main.net
	_clock.t = _main.net.clock()
	root.add_child(_clock)
	await _frames(3)
	_races = _main.races
	var lap := _def("lap")
	var bus := _def("bus")
	_check(_races.defs.size() == 2 and not lap.is_empty() and not bus.is_empty()
			and lap["checkpoints"].size() >= 8 and bus["checkpoints"].size() >= 4,
			"races.json: the campus lap (%d checkpoints, %d m) and the bus race (%d checkpoints, %d m)" % [
			lap.get("checkpoints", []).size(), lap.get("length", 0), bus.get("checkpoints", []).size(), bus.get("length", 0)])
	_check(_races._boards3d.size() == 2 and _races._circles.size() == 2, "two start circles and two leaderboards")
	_check(_races.records_path == _records, "records go to %s" % _races.records_path)
	if _wants("lap"):
		await _lap_checks(lap)
	if _wants("bus"):
		await _bus_checks(bus)
	if _wants("bot_bus"):
		await _bot_run(bus, "bus-idfm-artic")
	if _wants("bot_lap"):
		await _bot_run(lap, "compact-hatchback")
	print("\n%d failure(s)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	quit(1 if not _failures.is_empty() else 0)


# ---------------------------------------------------------------- campus lap

func _lap_checks(lap: Dictionary) -> void:
	var s: Dictionary = lap["start"]
	var plane: Node3D = _vehicle("biplane", s["x"], s["y"], _dir(s))
	await _drive(plane)
	await process_frame
	await process_frame
	_check(_races._circle_here() == -1 and _races.hud.prompt_text() == "", "a plane in the lap's start circle: no race")
	_main.exit_car()
	plane.queue_free()
	_main.cars.erase(plane)
	await _frames(2)

	var car: Node3D = _vehicle("sedan", s["x"], s["y"], _dir(s))
	await _drive(car)
	await process_frame
	await process_frame
	var prompt: String = _races.hud.prompt_text()
	_check(_races._circle_here() == 0 and "race alone" in prompt, "a car in the lap's start circle is offered to race: '%s'"
			% prompt.replace("\n", " / "))
	await _frames(30)
	_races.race_key()
	_check(_races.state == _races.COUNTDOWN, "the race key starts the countdown (solo)")
	Input.action_press("throttle")
	var p0: Vector3 = car.global_position
	await _frames(150)
	await process_frame
	var moved := Vector2(car.global_position.x - p0.x, car.global_position.z - p0.z).length()
	_check(car.hold and moved < 0.3 and absf(car.speed()) < 0.3,
			"held during the countdown, throttle pressed (moved %.2f m, %.1f m/s)" % [moved, car.speed()])
	var went := await _wait_state([_races.RACING], 240)
	await _frames(60)
	_check(went and not car.hold and car.speed() > 1.0, "GO: racing, the car drives off (%.1f m/s)" % car.speed())
	Input.action_release("throttle")
	_check(_races._gates.size() == 4, "the next checkpoint and the one after show (%d marks)" % _races._gates.size())
	var cps: Array = lap["checkpoints"]
	_place(car, cps[1]["x"], cps[1]["y"], _dir(cps[1]))
	await _frames(4)
	_check(_races.next_cp == 0, "skipping the first checkpoint: the second does not count")
	var in_order := true
	for k in cps.size():
		_place(car, cps[k]["x"], cps[k]["y"], _dir(cps[k]))
		await _frames(4)
		in_order = in_order and _races.next_cp == k + 1
	_check(in_order, "each checkpoint counts in turn (%d/%d)" % [_races.next_cp, cps.size()])
	var t1 := await _finish_lap(car, lap, 100.0)
	_check(t1 >= 100.0 and t1 < 104.0 and _races.state == _races.IDLE and _races.hud.results_visible(),
			"the finish circle stops the clock (%s), the results show" % _races.format_time(t1))
	var rows: Array = _races.boards.get("lap", [])
	_check(rows.size() == 1 and rows[0][0] == _main.nickname and absf(rows[0][1] - t1) < 0.01 and rows[0][2] == "sedan",
			"the time is on the lap's leaderboard: %s" % str(rows))
	var lines: Array = _main.chat._lines
	var said: String = lines[-1][2] if not lines.is_empty() else ""
	_check("finished the Campus lap in %s" % _races.format_time(t1) in said and "New record" in said,
			"the chat says it: '%s'" % said)
	var file := FileAccess.get_file_as_string(_records)
	_check(_races.format_time(t1) != "" and _main.nickname in file and "sedan" in file, "the records file has it")

	# a slower lap keeps the best, a faster one replaces it
	await _lap_again(car, lap, 200.0)
	rows = _races.boards.get("lap", [])
	_check(rows.size() == 1 and absf(rows[0][1] - t1) < 0.01, "a slower lap does not replace the best")
	var t3 := await _lap_again(car, lap, 60.0)
	rows = _races.boards.get("lap", [])
	_check(rows.size() == 1 and absf(rows[0][1] - t3) < 0.01 and t3 < t1, "a faster lap replaces it (%s)" %
			_races.format_time(t3))
	# read back: from the file, and from the temporary file a crash would leave
	_races._records = {}
	_races.boards = {}
	_races.start_hosting()
	rows = _races.boards.get("lap", [])
	_check(rows.size() == 1 and absf(rows[0][1] - t3) < 0.01, "the records read back from the file")
	DirAccess.rename_absolute(_records, _records + ".tmp")
	_races.start_hosting()
	rows = _races.boards.get("lap", [])
	_check(rows.size() == 1 and absf(rows[0][1] - t3) < 0.01, "...and from the temporary file")
	DirAccess.rename_absolute(_records + ".tmp", _records)
	var board: Node3D = _races._boards3d["lap"]
	var left: String = (board.get_node("Left0") as Label3D).text
	_check(_main.nickname in left, "the leaderboard shows it: '%s'" % left.replace("\n", " / "))
	_main.exit_car()
	await _frames(2)


## Into the finish after every checkpoint, the clock `shift` s on; returns the time taken (or -1).
func _finish_lap(car: Node3D, lap: Dictionary, shift: float) -> float:
	_clock.skip += shift
	var f: Dictionary = lap["finish"]
	_place(car, f["x"], f["y"], _dir(lap["start"]))
	await _frames(4)
	await process_frame
	return _races.finish_time if _races.state == _races.IDLE else -1.0


## A whole lap (start, countdown, every checkpoint, finish) taking `shift` s more than it does; returns the time.
func _lap_again(car: Node3D, lap: Dictionary, shift: float) -> float:
	var s: Dictionary = lap["start"]
	_place(car, s["x"], s["y"], _dir(s))
	await _frames(3)
	_races.race_key()
	await _wait_state([_races.RACING], 400)
	for g: Dictionary in lap["checkpoints"]:
		_place(car, g["x"], g["y"], _dir(g))
		await _frames(3)
	return await _finish_lap(car, lap, shift)


# ---------------------------------------------------------------- bus race

func _bus_checks(bus: Dictionary) -> void:
	var s: Dictionary = bus["start"]
	var car: Node3D = _vehicle("sedan", s["x"], s["y"], _dir(s))
	await _drive(car)
	await process_frame
	await process_frame
	_check(_races._circle_here() == -1, "a car in the bus race's start circle: no race")
	_main.exit_car()
	car.queue_free()
	_main.cars.erase(car)
	await _frames(2)

	var b: Node3D = _vehicle("bus-idfm", s["x"], s["y"], _dir(s))
	await _drive(b)
	await process_frame
	await process_frame
	var prompt: String = _races.hud.prompt_text()
	_check(_races._circle_here() == 1 and "race alone" in prompt and not "race with" in prompt,
			"a 12 m bus in the bus race's start circle is offered it, alone: '%s'" % prompt.replace("\n", " / "))
	_check(_races.road_distance(b) == 0.0, "on the road at the start (%.1f m off)" % _races.road_distance(b))
	# a spot a few metres off the road (3 < d < 12), beside the start
	var side := Vector2(-_dir(s).y, _dir(s).x)          # left of the way, the stop's pavement and beyond
	var off := Vector2.INF
	for k in range(4, 30):
		for sgn: float in [1.0, -1.0]:
			var q := Vector2(s["x"], s["y"]) + side * sgn * k
			_place(b, q.x, q.y, _dir(s))
			await _frames(1)
			var d: float = _races.road_distance(b)
			if d > _races.OFF_DIST + 0.5 and d < _races.OFF_FAR - 1.0:
				off = q
				break
		if off != Vector2.INF:
			break
	var far := Vector2.INF
	for k in range(10, 60, 2):
		for sgn: float in [1.0, -1.0]:
			var q := Vector2(s["x"], s["y"]) + side * sgn * k
			_place(b, q.x, q.y, _dir(s))
			await _frames(1)
			if _races.road_distance(b) > _races.OFF_FAR + 1.0:
				far = q
				break
		if far != Vector2.INF:
			break
	_check(off != Vector2.INF and far != Vector2.INF, "found spots a few metres and far off the road (%s, %s)" % [off, far])
	if off == Vector2.INF or far == Vector2.INF:
		return
	_place(b, s["x"], s["y"], _dir(s))
	await _frames(3)
	_races.race_key()
	await _wait_state([_races.RACING], 400)
	_place(b, off.x, off.y, _dir(s))
	await _frames(int(60 * (_races.OFF_TIME - 1.0)))
	var warned: String = _races.hud._banner_warn.text
	_check(_races.state == _races.RACING and _races.off_road > 1.0 and "BACK ON THE ROAD" in warned,
			"%.1f m off the road for %.1f s: still racing, warned ('%s')" % [_races.off_dist, _races.off_road, warned])
	_place(b, s["x"], s["y"], _dir(s))
	await _frames(12)
	_check(_races.state == _races.RACING and _races.off_road == 0.0, "back on the road: the count starts over")
	_place(b, off.x, off.y, _dir(s))
	await _frames(int(60 * (_races.OFF_TIME + 0.6)))
	await process_frame
	var title := _results_title()
	_check(_races.state == _races.IDLE and _races.hud.results_visible() and "left the road" in _results_text(),
			"over %d s off the road: out, the results say so ('%s')" % [int(_races.OFF_TIME), _results_text()])
	_check(_races.boards.get("bus:bus-idfm", []).is_empty(), "no time on the board for it (%s)" % title)
	_place(b, s["x"], s["y"], _dir(s))
	await _frames(3)
	_races.race_key()
	await _wait_state([_races.RACING], 400)
	_place(b, far.x, far.y, _dir(s))
	await _frames(12)
	await process_frame
	_check(_races.state == _races.IDLE and "left the road" in _results_text(), "far off the road: out at once")
	_main.exit_car()
	await _frames(2)


func _results_text() -> String:
	var out := PackedStringArray()
	for n: Node in _races.hud._results_box.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return " | ".join(out)


func _results_title() -> String:
	var labels: Array = _races.hud._results_box.find_children("*", "Label", true, false)
	return (labels[0] as Label).text if not labels.is_empty() else ""


# ---------------------------------------------------------------- a bot drives a race

## A bot drives race `d`'s route in a `model`, the race running for it as if it were the player's vehicle.
func _bot_run(d: Dictionary, model: String) -> void:
	var traffic: Node = _main.traffic
	var route: Dictionary = d["route"].duplicate(true)
	route["then"] = "respawn"
	var rid: String = "race:" + d["id"]
	traffic.routes[rid] = route
	var line := {"ref": "race", "model": model, "routes": [rid], "headway": 9999.0, "phase": 0.0}
	var car: Node3D = _main.new_vehicle(model)
	var bot := BusBot.new()
	bot.setup(traffic, car, line, 0)
	bot.may_glide = false
	_main.add_bot_bus(car, bot.pose_at(bot.tail + 1.0), bot)
	bot.put(0, bot.tail + 1.0)
	await _frames(5)
	if _main.driving:
		_main.exit_car()
		await _frames(2)
	_main.driving = car                     # the race runs for it; the bot keeps the wheel (car.driving stays false)
	_races._start(_races.defs.find(d), [])
	var started: bool = _races.state == _races.COUNTDOWN
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var longest := 0.0
	var passed := 0
	var t0 := Time.get_ticks_msec()
	for i in 60 * 900:
		await physics_frame
		passed = maxi(passed, _races.next_cp)
		if _races.state != _races.RACING and _races.state != _races.COUNTDOWN:
			break
		if _races.off_dist > worst:
			worst = _races.off_dist
			var c: Vector3 = car.global_position
			worst_at = Vector2(c.x, -c.z)
		longest = maxf(longest, _races.off_road)
	await process_frame
	var key: String = _races.board_key(d, model)
	var rows: Array = _races.boards.get(key, [])
	var c: Vector3 = car.global_position
	_check(started and passed == d["checkpoints"].size() and _races.state == _races.IDLE and _races.finish_time > 0.0
			and not rows.is_empty()
			and "finished" in str(_main.chat._lines[-1][2]),
			"a bot drives the %s in a %s through %d/%d checkpoints to the finish: %s (%d s real; stopped at (%d, %d), %s)" % [
			d["name"], model, passed, d["checkpoints"].size(), _races.format_time(_races.finish_time),
			(Time.get_ticks_msec() - t0) / 1000, c.x, -c.z, _results_text()])
	if d["vehicles"] == "bus":
		_check(longest < 1.0, "the bus never strays over %.0f m off the road for long (furthest %.1f m at (%d, %d), %.1f s on end)" % [
				_races.OFF_DIST, worst, worst_at.x, worst_at.y, longest])
	_main.driving = null
	car.set_pilot(null)
	traffic.routes.erase(rid)
	await _frames(2)
