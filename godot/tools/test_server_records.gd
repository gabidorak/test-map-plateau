extends SceneTree
## Client side of tools/test_server_records.sh (a dedicated server's race records outlive its restarts):
## - `--race`: joins, races the bus race alone in a 12 m bus (through its checkpoints, into the finish once the shortest
##   time the server accepts is up), and sees its time on the board;
## - `--check`: joins (the server restarted meanwhile) and sees that time on the board.

const GroundMap = preload("res://scripts/ground_map.gd")

var _main: Node
var _races: Node
var _failures: PackedStringArray = []
var _racing := false


func _initialize() -> void:
	_racing = "--race" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + ("[race] " if _racing else "[check] ") + what)
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


func _run() -> void:
	var joined := await _until(func() -> bool: return _main.mode == "client", 30.0)
	_check(joined, "joined the dedicated server")
	if joined:
		_races = _main.races
		await _frames(30)
		if _racing:
			await _race()
		else:
			var rows: Array = _races.boards.get("bus:bus-idfm", [])
			_check(rows.size() == 1 and rows[0][0] == "Racer", "after the restart, the board still has the time: %s" % str(rows))
	print("%d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)


func _race() -> void:
	var d: Dictionary = _races.defs[1]
	var s: Dictionary = d["start"]
	var dir := Vector2(float(s["dir"][0]), float(s["dir"][1]))
	var bus: Node3D = _main.new_vehicle("bus-idfm")
	_main.add_child(bus)
	_place(bus, s["x"], s["y"], dir)
	_main._add_car(bus)
	_main.net.car_parked(bus)
	await _frames(3)
	_main.net.request_drive(bus)
	await _until(func() -> bool: return _main.driving == bus, 5.0)
	await _frames(3)
	_races.race_key()
	var went := await _until(func() -> bool: return _races.state == _races.RACING, 10.0)
	_check(went, "racing the bus race on the dedicated server")
	for g: Dictionary in d["checkpoints"]:
		_place(bus, g["x"], g["y"], Vector2(float(g["dir"][0]), float(g["dir"][1])))
		await _frames(4)
	var shortest: float = float(d["length"]) / _races.MIN_TIME_SPEED + 1.0
	await _until(func() -> bool: return _main.net.clock() - _races.go_at > shortest, shortest + 10.0)
	var f: Dictionary = d["finish"]
	var last: Dictionary = d["checkpoints"][-1]
	_place(bus, f["x"], f["y"], Vector2(float(last["dir"][0]), float(last["dir"][1])))
	var over := await _until(func() -> bool: return _races.state == _races.IDLE, 10.0)
	await _frames(10)
	var rows: Array = _races.boards.get("bus:bus-idfm", [])
	_check(over and rows.size() == 1 and rows[0][0] == "Racer", "the time is on the board: %s" % str(rows))
