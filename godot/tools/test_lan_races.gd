extends SceneTree
## Headless check of the races in a LAN game (scripts/races.gd): run as a host and a client at once
## (tools/test_lan_races.sh, port 7792):
## - before the client joins, the host races the campus lap alone (into the records file); the client joining gets the
##   leaderboard with that time;
## - both park a car in the lap's start circle and drive it; the host sees the client driving in the circle and invites
##   it (the invite key); the client is invited (its prompt says by whom) and joins (the race key); both count down to
##   the same GO and race; the client gets round first, the host second; both see the results in that order, both chats
##   say "Guest won the Campus lap…", and both leaderboards have both times.
## The race clock is the host's real clock: the host moves it on SHIFT s after GO (a lap in a few seconds would be
## refused as too quick), which the client's clock follows.
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

const GroundMap = preload("res://scripts/ground_map.gd")
## the host's solo lap is done: start the client (the temporary folder: /tmp, or the Windows one Git Bash calls /tmp,
## where test_lan_races.sh looks)
var _ready_file := OS.get_temp_dir().path_join("test_lan_races_ready")
const SHIFT := 70.0                         # s the host's clock jumps on during each race

var _main: Node
var _races: Node
var _failures: PackedStringArray = []
var _hosting := false


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	if _hosting:
		DirAccess.remove_absolute(_ready_file)
		for f: String in [OS.get_temp_dir().path_join("test_lan_races/records.json"),
				OS.get_temp_dir().path_join("test_lan_races/records.json.tmp")]:
			DirAccess.remove_absolute(f)
		DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join("test_lan_races"))
		OS.set_environment("PLATEAU_RECORDS", OS.get_temp_dir().path_join("test_lan_races/records.json"))
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + ("[host] " if _hosting else "[client] ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await physics_frame
	return true


func _place(car: Node3D, x: float, y: float, dir: Vector2) -> void:
	var map: GroundMap = GroundMap.get_map()
	var b := Basis.looking_at(-Vector3(dir.x, 0.0, -dir.y).normalized())
	car.place(Transform3D(b, Vector3(x, map.height(x, y) + 0.4, -y)).translated_local(-car.extents_center))


func _dir(c: Dictionary) -> Vector2:
	return Vector2(float(c["dir"][0]), float(c["dir"][1])) if c.has("dir") else Vector2.RIGHT


## A sedan of ours in the lap's start circle, `side` m left of its centre, driven (asked of the host in a LAN game).
func _car_in_circle(lap: Dictionary, side: float) -> Node3D:
	var s: Dictionary = lap["start"]
	var d := _dir(s)
	var p := Vector2(s["x"], s["y"]) + Vector2(-d.y, d.x) * side
	var car: Node3D = _main.new_vehicle("sedan")
	_main.add_child(car)
	_place(car, p.x, p.y, d)
	_main._add_car(car)
	_main.net.car_parked(car)
	await _frames(3)
	if _main.net.active:
		_main.net.request_drive(car)
		await _until(func() -> bool: return _main.driving == car, 5.0)
	else:
		_main.enter_car(car)
	await _frames(3)
	return car


## Round the lap from the start (racing already): every checkpoint, then the finish.
func _lap(car: Node3D, lap: Dictionary) -> void:
	for g: Dictionary in lap["checkpoints"]:
		_place(car, g["x"], g["y"], _dir(g))
		await _frames(3)
	var f: Dictionary = lap["finish"]
	_place(car, f["x"], f["y"], _dir(lap["start"]))
	await _frames(4)


func _results_text() -> String:
	var out := PackedStringArray()
	for n: Node in _races.hud._results_box.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return " | ".join(out)


func _run() -> void:
	await _until(func() -> bool: return _main.mode in ["host", "client"], 30.0)
	_races = _main.races
	var lap: Dictionary = _races.defs[0]
	if _hosting:
		await _host(lap)
	else:
		await _client(lap)
	await _frames(30)
	print("%s: %d failure(s)" % ["host" if _hosting else "client", _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _host(lap: Dictionary) -> void:
	var car := await _car_in_circle(lap, 3.0)
	await process_frame
	_races.race_key()
	var went := await _until(func() -> bool: return _races.state == _races.RACING, 10.0)
	_main.net.clock_shift += SHIFT
	await _lap(car, lap)
	await _until(func() -> bool: return _races.state == _races.IDLE, 5.0)
	var rows: Array = _races.boards.get("lap", [])
	_check(went and rows.size() == 1 and rows[0][0] == "Host", "a lap alone before anyone joins: %s" % str(rows))
	FileAccess.open(_ready_file, FileAccess.WRITE).store_string("ready")
	var joined := await _until(func() -> bool: return _main.net.players.size() == 2, 30.0)
	_check(joined, "the client joined")
	if not joined:
		return
	var guest: int = _main.net.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	# the prompt follows in races.gd's next _process, which may come after this physics frame
	var seen := await _until(func() -> bool: return guest in _races._drivers_in_circle(0) \
			and "race with Guest" in _races.hud.prompt_text(), 20.0)
	var prompt: String = _races.hud.prompt_text()
	_check(seen and "race with Guest" in prompt, "the client drives in the start circle: '%s'" % prompt.replace("\n", " / "))
	_races.invite_key()
	var started := await _until(func() -> bool: return _races.state == _races.COUNTDOWN, 20.0)
	_check(started and _races.racers.size() == 2, "the client joined the race: counting down with %d racers" %
			_races.racers.size())
	var go: float = _races.go_at
	FileAccess.open(_ready_file, FileAccess.WRITE).store_string("go %f" % go)
	went = await _until(func() -> bool: return _races.state == _races.RACING, 10.0)
	_check(went, "GO")
	_main.net.clock_shift += SHIFT
	await _until(func() -> bool: return _races._results.has(guest), 20.0)   # the client gets round first
	await _frames(30)
	await _lap(car, lap)
	await _common_end()


func _client(lap: Dictionary) -> void:
	await _frames(30)
	var rows: Array = _races.boards.get("lap", [])
	_check(rows.size() == 1 and rows[0][0] == "Host", "joining: the leaderboard has the host's lap: %s" % str(rows))
	var left: String = (_races._boards3d["lap"].get_node("Left0") as Label3D).text
	_check("Host" in left, "...on the 3D board too: '%s'" % left.replace("\n", " / "))
	var car := await _car_in_circle(lap, -3.0)
	var invited := await _until(func() -> bool: return _races.state == _races.INVITED \
			and "Host invites you" in _races.hud.prompt_text(), 30.0)
	var prompt: String = _races.hud.prompt_text()
	_check(invited and "Host invites you" in prompt, "invited: '%s'" % prompt.replace("\n", " / "))
	_races.race_key()
	var started := await _until(func() -> bool: return _races.state == _races.COUNTDOWN, 10.0)
	_check(started and _races.racers.size() == 2, "joined: counting down with %d racers" % _races.racers.size())
	await _until(func() -> bool: return FileAccess.get_file_as_string(_ready_file).begins_with("go"), 5.0)
	var host_go := float(FileAccess.get_file_as_string(_ready_file).get_slice(" ", 1))
	_check(absf(_races.go_at - host_go) < 0.001, "the same GO as the host's (%.3f, %.3f)" % [_races.go_at, host_go])
	var went := await _until(func() -> bool: return _races.state == _races.RACING, 10.0)
	_check(went, "GO")
	await _until(func() -> bool: return _main.net.clock() - _races.go_at > SHIFT * 0.9, 5.0)
	await _lap(car, lap)
	await _common_end()


func _common_end() -> void:
	var over := await _until(func() -> bool: return _races.state == _races.IDLE and _races.hud.results_visible(), 30.0)
	var text := _results_text()
	_check(over and text.find("Guest") >= 0 and text.find("Guest") < text.find("Host") and "1st" in text and "2nd" in text,
			"the results: '%s'" % text)
	var lines: Array = _main.chat._lines
	var said: String = lines[-1][2] if not lines.is_empty() else ""
	_check("Guest won the Campus lap in" in said and "Host 2nd in" in said, "the chat says it: '%s'" % said)
	await _until(func() -> bool: return _races.boards.get("lap", []).size() == 2, 5.0)
	var rows: Array = _races.boards.get("lap", [])
	_check(rows.size() == 2 and rows.any(func(r: Array) -> bool: return r[0] == "Guest"),
			"the leaderboard has both: %s" % str(rows))
