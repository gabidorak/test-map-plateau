extends SceneTree
## Headless check of the RER B trains in a LAN game (scripts/train_traffic.gd, scripts/train.gd, scripts/net.gd): run it
## twice at once, as the host (which runs the trains) and as a client, with tools/test_lan_trains.sh (port 7793).
## The client gets the host's trains (made on first sight, posed from their states), sees the train the host picked
## stop at Lozère at the same moment on the shared clock (within ARRIVAL), steps in while its doors are open and stays
## standing in it as it leaves; the host sees the client's player in the train.
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

const CLOCK_FILE := "user://test_lan_trains_clock.txt"  # the host's game clock against the system clock
const RIDE_FILE := "user://test_lan_trains_ride.txt"    # the net id of the train to ride
const ARRIVAL_FILE := "user://test_lan_trains_arrival.txt"   # when it stopped at Lozère, on the host's clock
const ARRIVAL := 0.3                        # s

var _main: Node
var _failures: PackedStringArray = []
var _hosting := false


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	OS.set_environment("PLATEAU_BUSES", "0")
	OS.set_environment("PLATEAU_CARS", "0")
	OS.set_environment("PLATEAU_TRAINS", "1" if _hosting else "0")
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


func _run() -> void:
	if _hosting:
		await _run_host()
	else:
		await _run_client()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run_host() -> void:
	for p in [RIDE_FILE, ARRIVAL_FILE, CLOCK_FILE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var net: Node = _main.net
	var tt: Node = _main.traffic.trains
	_check(await _until(func() -> bool: return _main.mode == "host" and tt.running, 60.0),
			"hosting with %d trains" % tt.trains.size())
	_check(await _until(func() -> bool: return net.players.size() == 2, 90.0), "the client joined")
	await _until(func() -> bool: return false, 3.0)
	# an eastbound train 500 m before Lozère, the others stowed, no more departures
	for k in tt.services.size():
		tt.departures[k] = INF
	for tr: Node3D in tt.trains:
		tt._stow(tr)
	var k := 0
	for i in tt.services.size():
		if tt.services[i]["direction"] == "eastbound":
			k = i
	var mark: float = _lozere(tt.services[k])["s"]["8"]
	var tr: Node3D = tt._new_train(k)
	var bot: Object = tt.bots[tr]
	bot.start()
	tr.front = mark - 500.0
	tr.speed = 18.0
	while bot.stop_k < bot._stops.size() and bot._stops[bot.stop_k]["s"] < tr.front - 1.0:
		bot.stop_k += 1                 # past Le Guichet's stop (a station before Lozère since the west box)
	_write(RIDE_FILE, tr.net_id)
	var arrived := false
	var aboard := false
	var front_aboard := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000:
		_write(CLOCK_FILE, "%f %f" % [Time.get_unix_time_from_system(), net.clock()])
		await physics_frame
		if not arrived and bot.state == "stopped":
			arrived = true
			_write(ARRIVAL_FILE, "%f" % net.clock())
		if not aboard:
			for r: Node3D in net.avatars():
				if r.visible and tr.carrier_at(r.global_position, 0.3):
					aboard = true
					front_aboard = tr.front
		if aboard and tr.front > front_aboard + 40.0:
			break
	_check(arrived, "the train stopped at Lozère")
	_check(aboard, "the client's player is seen in the train here")
	_check(aboard and tr.front > front_aboard + 40.0, "it leaves with them aboard (%.0f m)" % (tr.front - front_aboard))
	_check(await _until(func() -> bool: return net.players.size() == 1, 60.0), "the client left")


func _run_client() -> void:
	var net: Node = _main.net
	var tt: Node = _main.traffic.trains
	_check(await _until(func() -> bool: return _main.mode == "client", 90.0), "joined the host")
	_check(await _until(func() -> bool: return tt.trains.size() >= 2, 30.0), "the host's trains are here (%d)" % tt.trains.size())
	_check(tt.trains.all(func(t: Node) -> bool: return t.remote) and not tt.running, "posed from the host's states, run there")
	_check(await _until(func() -> bool: return FileAccess.file_exists(RIDE_FILE), 60.0), "the host picked a train")
	var id := FileAccess.get_file_as_string(RIDE_FILE)
	var tr: Node3D = null
	await _until(func() -> bool:
		for t: Node3D in tt.trains:
			if t.net_id == id and not t.stowed:
				return true
		return false, 20.0)
	for t: Node3D in tt.trains:
		if t.net_id == id:
			tr = t
	_check(tr != null, "it is here")
	if tr == null:
		return
	# its arrival on the shared clock
	var mark: float = _lozere(tr.service)["s"]["8"]
	var arrived_at := [NAN]                 # (a lambda captures locals by value: an array to write into)
	await _until(func() -> bool: return tr.speed > 1.0, 20.0)     # under way to Lozère (not a state from before)
	await _until(func() -> bool:
		if tr.speed < 0.01 and absf(tr.front - mark) < 1.5:
			arrived_at[0] = net.clock()
			return true
		return false, 120.0)
	await _until(func() -> bool: return FileAccess.file_exists(ARRIVAL_FILE), 10.0)
	var host_arrival := float(FileAccess.get_file_as_string(ARRIVAL_FILE)) if FileAccess.file_exists(ARRIVAL_FILE) else NAN
	var apart: float = absf(arrived_at[0] - host_arrival)
	_check(apart < ARRIVAL, "it stops at Lozère when it does at the host (%s ms apart)" % (str(roundi(apart * 1000.0))
			if not is_nan(apart) else "?"))
	# in through an open door
	_check(await _until(func() -> bool: return tr.door_t >= 1.0, 20.0), "its doors open on this screen too")
	var car: Node3D = tr.cars[3]
	var player: CharacterBody3D = _main.player
	player.teleport(car.to_global(Vector3(0.0, float(car._floor_y) + 0.05, -2.0)))
	_check(await _until(func() -> bool: return player.carrier == car, 5.0), "standing in it")
	var f0: float = tr.front
	var inside := 0
	var frames := 0
	while tr.front < f0 + 40.0 and frames < 60 * 120:
		await physics_frame
		frames += 1
		inside += 1 if player.carrier == car and car.carries(player.global_position, 0.3) else 0
	_check(tr.front >= f0 + 40.0 and inside == frames, "rides along as it leaves (%.0f m, inside %d/%d frames)" % [
			tr.front - f0, inside, frames])
	player.set_carrier(null)
	await _until(func() -> bool: return false, 1.0)
	net.leave()


## The service's stop at Lozère (the line runs on to Massy-Palaiseau: westbound trains stop elsewhere first).
static func _lozere(svc: Dictionary) -> Dictionary:
	for st: Dictionary in svc["stops"]:
		if st["name"] == "Lozère":
			return st
	return svc["stops"][0]
