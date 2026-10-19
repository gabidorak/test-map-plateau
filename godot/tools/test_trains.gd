extends SceneTree
## Headless checks for the RER B trains (scripts/train.gd, scripts/train_bot.gd, scripts/train_traffic.gd;
## world/rail.json services), the bot buses and cars off:
## - departures: a train sets off in each direction every headway, both directions are out;
## - entering the map: at the planned speed (westbound: the line speed; eastbound: still accelerating out of Le Guichet,
##   the station just west of the map);
## - the stop at Lozère: the front within STOP of the 8-car mark, the doors open on the platform side only (the leaves
##   and the doorway boxes), shut again before it leaves;
## - the door hold: a player in a doorway keeps them open past the dwell, they shut once the player is in;
## - walking in from the platform through an open door (over the gap and the step up), carried by the car;
## - a ride: the player in a car while it leaves, carried through the station at speed (never below the floor, always
##   inside), and put down by the line when it leaves the map;
## - signals: a train behind one standing at the platform stops short of the red signal and never closer than the
##   margin to its tail; the signal shows red;
## - a car on the track: far enough ahead the train sounds its horn and stops short of it; too close it brakes at the
##   emergency rate, knocks it aside (damage, a capped push) and stops;
## - far from the camera only the cars' light shells are drawn;
## - the frame time the trains cost (like probe_traffic.gd).
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_trains.gd
## PLATEAU_TEST_ONLY=stop,hold,ride,signals,obstacle,... runs some of the checks after the departures.

const Car = preload("res://scripts/car.gd")
const STOP := 1.0                           # m around the stopping mark
const FLOOR_SLACK := 0.25                   # m a rider may dip under the car floor (steps, the physics' skin)

var _main: Node
var _tt: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_TRAINS", "1")
	OS.set_environment("PLATEAU_BUSES", "0")
	OS.set_environment("PLATEAU_CARS", "0")
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


func _run() -> void:
	_tt = _main.traffic.trains
	while not _tt.running:
		await physics_frame
	await _frames(10)
	var only := OS.get_environment("PLATEAU_TEST_ONLY").split(",", false)
	await _departures()
	# from here on the checks place the trains themselves: no more departures, all stowed
	for k in _tt.services.size():
		_tt.departures[k] = INF
	for tr: Node3D in _tt.trains:
		_tt._stow(tr)
	for check: Callable in [_entering, _stop, _hold, _walk_in, _ride, _signals, _obstacle, _far, _cost]:
		if only.is_empty() or check.get_method().trim_prefix("_") in only:
			await check.call()
			for tr: Node3D in _tt.trains:
				_tt._stow(tr)
			_main.player.set_carrier(null)
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## A train of service k put at `front` with `speed`, its bot started there.
func _put(k: int, front: float, speed: float) -> Node3D:
	var tr: Node3D = _tt._new_train(k)
	var bot: Object = _tt.bots[tr]
	bot.start()
	tr.front = front
	tr.speed = speed
	bot.stop_k = 0
	while bot.stop_k < bot._stops.size() and bot._stops[bot.stop_k]["s"] < front - 1.0:
		bot.stop_k += 1
	tr.pose()
	return tr


func _service(direction: String) -> int:
	for k in _tt.services.size():
		if _tt.services[k]["direction"] == direction:
			return k
	return -1


# ---------------------------------------------------------------- checks

## A train sets off in each direction every headway.
func _departures() -> void:
	var before: PackedInt32Array = _tt.departed.duplicate()
	var out := {}
	for tr: Node3D in _tt.trains:
		if not tr.stowed:
			out[tr.service["direction"]] = out.get(tr.service["direction"], 0) + 1
	_check(out.get("eastbound", 0) > 0 and out.get("westbound", 0) > 0,
			"the line filled at the start, both directions out (%s, headway %.0f s)" % [out, _tt.headway])
	var t0: float = _tt.time
	while _tt.time < t0 + _tt.headway + 2.0:
		await physics_frame
	var sent := []
	for k in _tt.services.size():
		sent.append(_tt.departed[k] - before[k])
	_check(sent.min() >= 1 and sent.max() <= 2, "a departure per direction in a headway (%s)" % [sent])


## At the planned speed where they come into the map, or (eastbound, from rest at Le Guichet) as fast as the
## traction gets it there.
func _entering() -> void:
	for dir: String in ["westbound", "eastbound"]:
		var k := _service(dir)
		var svc: Dictionary = _tt.services[k]
		var tr := _put(k, float(svc["start"]), float(svc["start_speed"]))
		var enter: float = svc["enter"]
		var v_in := -1.0
		for f in 60 * 120:
			await physics_frame
			if tr.front >= enter:
				v_in = tr.speed
				break
		var planned: float = _tt.bots[tr].planned(enter)
		var reach := sqrt(2.0 * float(_tt.spec["accel"]) * (enter - float(svc["start"])) + pow(float(svc["start_speed"]), 2.0))
		var expect := minf(planned, reach)
		_check(v_in > 0.0 and absf(v_in - expect) < 0.12 * expect, "%s comes into the map at %.0f km/h (planned %.0f, %s %.0f km/h)" % [
				dir, v_in * 3.6, planned * 3.6, "the most it can reach from rest at Le Guichet" if svc["start_speed"] == 0.0
				else "entering at speed:", expect * 3.6])
		_tt._stow(tr)


## Stops on the mark, doors on the platform side only, shut before leaving.
func _stop() -> void:
	for dir: String in ["eastbound", "westbound"]:
		var k := _service(dir)
		var mark: float = _lozere(_tt.services[k])["s"]["8"]
		var tr := _put(k, mark - 700.0, 22.0)
		var bot: Object = _tt.bots[tr]
		var stopped_at := INF
		var sides_ok := true
		var opened := false
		var shut_before_leaving := true
		for f in 60 * 200:
			await physics_frame
			if bot.state == "stopped" and is_inf(stopped_at):
				stopped_at = tr.front
			if bot.state == "dwell" and tr.door_t >= 1.0 and not opened:
				opened = true
				sides_ok = _doors_on_platform_side(tr, k)
			if bot.state == "run" and opened:
				shut_before_leaving = shut_before_leaving and (tr.speed < 0.01 or tr.door_t <= 0.0)
				if tr.front > mark + 30.0:
					break
		_check(absf(stopped_at - mark) <= STOP, "%s stops %.2f m from the 8-car mark" % [dir, stopped_at - mark])
		_check(opened and sides_ok, "%s opens its doors on the platform side only (leaves and doorways)" % dir)
		_check(shut_before_leaving, "%s shuts them before it moves" % dir)
		_tt._stow(tr)


## Each car: its doors open on the side the platform is on (the doorway's outside over the platform), shut on the other.
func _doors_on_platform_side(tr: Node3D, k: int) -> bool:
	var pf_side := 0.0
	for pf: Dictionary in _tt._rm.data["platforms"]:
		if pf["id"] == _lozere(_tt.services[k])["platform"]:
			pf_side = pf["side"]
	for car: Node3D in tr.cars:
		for s: String in ["left", "right"]:
			for d: Dictionary in car._doors[s]:
				var leaf: Node3D = d["leaves"][0]
				var moved: bool = leaf.position.distance_to(d["closed"][0]) > 0.3
				var outside: Vector3 = car.to_global(d["center"] + Vector3(signf(d["center"].x) * 1.0, 0.0, 0.0))
				var su: Vector2 = _tt._rm.project(Vector2(outside.x, -outside.z))
				var platform_side := signf(su.y - _tt._track_u[k]) == pf_side
				var box: CollisionShape3D = car._door_boxes.get(d["key"])
				if moved != platform_side or (box and box.disabled != platform_side):
					return false
	return true


## A player in a doorway holds the doors open; in the car, they shut.
func _hold() -> void:
	var k := _service("eastbound")
	var mark: float = _lozere(_tt.services[k])["s"]["8"]
	var tr := _put(k, mark - 200.0, 12.0)
	var bot: Object = _tt.bots[tr]
	for f in 60 * 120:
		await physics_frame
		if bot.state == "dwell" and tr.door_t >= 1.0:
			break
	var car: Node3D = tr.cars[2]
	var side: int = tr.doors_side * (-1 if car.turned else 1)
	var d: Dictionary = car._doors["left" if side == 1 else "right"][1]
	var c: Vector3 = d["center"]
	_main.player.teleport(car.to_global(c + Vector3(signf(c.x) * 0.4, 0.05, 0.0)))
	var dwell: float = bot._stops[bot.stop_k]["dwell"]
	var held := false
	for f in 60 * 80:
		await physics_frame
		if bot.state == "dwell" and bot.t > dwell + 3.0 and tr.door_t > 0.9:
			held = true
			break
		if tr.door_t <= 0.0:
			break
	_check(held, "the doors held open past the %.0f s dwell while the player stands in a doorway" % dwell)
	_main.player.teleport(car.to_global(Vector3(0.0, float(car._floor_y) + 0.05, c.z - 2.5)))
	var shut := INF
	for f in 60 * 30:
		await physics_frame
		if tr.door_t <= 0.0:
			shut = f / 60.0
			break
	_check(shut < 12.0 and is_instance_valid(_main.player.carrier), "the player in, they shut %.1f s later" % shut)


## Walking in from the platform through an open door: over the gap and the step up, carried by the car.
func _walk_in() -> void:
	var k := _service("westbound")
	var mark: float = _lozere(_tt.services[k])["s"]["8"]
	var tr := _put(k, mark - 150.0, 10.0)
	var bot: Object = _tt.bots[tr]
	for f in 60 * 120:
		await physics_frame
		if bot.state == "dwell" and tr.door_t >= 1.0:
			break
	var car: Node3D = tr.cars[5]
	var side: int = tr.doors_side * (-1 if car.turned else 1)
	var d: Dictionary = car._doors["left" if side == 1 else "right"][2]
	var c: Vector3 = d["center"]
	var start: Vector3 = car.to_global(c + Vector3(signf(c.x) * 2.2, 0.0, 0.0))
	var inside: Vector3 = car.to_global(Vector3(0.0, c.y, c.z))
	var dir := (inside - start)
	dir.y = 0.0
	var rescues: int = _main.player.rescues
	_main.player.teleport(start + Vector3.UP * 0.15, atan2(-dir.x, -dir.z))
	await _frames(20)
	_main.player.scripted_input = Vector2(0.0, 1.0)
	await _frames(60)
	_main.player.scripted_input = Vector2.ZERO
	await _frames(30)
	_main.player.scripted_input = null
	var l: Vector3 = car.to_local(_main.player.global_position)
	_check(_main.player.carrier == car and l.y > float(car._floor_y) - 0.1 and _main.player.rescues == rescues,
			"walked in from the platform through an open door: carried by the car, on its floor (%.2f m above it)" % (
			l.y - float(car._floor_y)))
	_main.player.teleport(start + Vector3.UP * 0.15)


## Carried from the station to the map edge, then put down by the line.
func _ride() -> void:
	var k := _service("eastbound")
	var mark: float = _lozere(_tt.services[k])["s"]["8"]
	var tr := _put(k, mark - 150.0, 10.0)
	var bot: Object = _tt.bots[tr]
	for f in 60 * 120:
		await physics_frame
		if bot.state == "dwell":
			break
	var car: Node3D = tr.cars[4]
	_main.player.teleport(car.to_global(Vector3(0.0, float(car._floor_y) + 0.05, 3.0)))
	await _frames(10)
	var boarded: bool = _main.player.carrier == car
	var teleports: int = _tt.teleports
	var min_dy := INF
	var lost := 0
	var top_speed := 0.0
	for f in 60 * 720:                      # on to Massy-Palaiseau: three more stops (40 s each) before the map's end
		await physics_frame
		if _tt.teleports > teleports:
			break
		var c: Node3D = _main.player.carrier
		if c == null:
			lost += 1
			continue
		var l: Vector3 = c.to_local(_main.player.global_position)
		min_dy = minf(min_dy, l.y - float(c._floor_y))
		top_speed = maxf(top_speed, tr.speed)
	var landed: bool = _tt.teleports > teleports
	var spot: Dictionary = _tt._landing["east"]
	var p: Vector3 = _main.player.global_position
	_check(boarded, "the player boards at Lozère (carried by the car)")
	_check(lost == 0 and min_dy > -FLOOR_SLACK, "carried all the way at up to %.0f km/h, never below the floor (lowest %.2f m), never lost (%d ticks)" % [
			top_speed * 3.6, min_dy, lost])
	_check(landed and Vector2(p.x, -p.z).distance_to(Vector2(spot["x"], spot["y"])) < 15.0 \
			and not is_instance_valid(_main.player.carrier), "put down by the line at the east end of the map")


## A following train stops short of the red signal behind one standing at the platform.
func _signals() -> void:
	var k := _service("eastbound")
	var mark: float = _lozere(_tt.services[k])["s"]["8"]
	var lead := _put(k, mark, 0.0)
	var lead_bot: Object = _tt.bots[lead]
	lead_bot.state = "dwell"
	lead_bot._stops[0]["dwell"] = 1e9         # it stays
	lead.set_doors(true, 1)
	var follow := _put(k, mark - 1300.0, 25.0)
	var fb: Object = _tt.bots[follow]
	var closest := INF
	var stopped := false
	for f in 60 * 150:
		await physics_frame
		closest = minf(closest, lead.front - lead.length - follow.front)
		if follow.speed < 0.01 and fb.state == "run" and f > 60:
			stopped = true
			break
	await _frames(30)
	var red := false
	for sg: Dictionary in _tt.services[k]["signals"]:
		var node: Node3D = _tt._signals.get(sg["id"])
		if node and float(sg["s"]) > follow.front and float(sg["s"]) < follow.front + 60.0:
			red = node.get_meta("aspect", "") in ["S", "C"]
	_check(stopped and closest > fb.SIGNAL_MARGIN, "the train behind stops short of the red signal (%.0f m behind the tail at the closest)" % closest)
	_check(red, "the signal ahead of it shows red")
	lead_bot._stops[0]["dwell"] = _lozere(_tt.services[k])["dwell"]


## A car on the track: horn and a stop short of it; too close, an emergency stop and a knock.
func _obstacle() -> void:
	var k := _service("westbound")
	var svc: Dictionary = _tt.services[k]
	for far: bool in [true, false]:
		# west of Lozère, on the way to Le Guichet: no stop within reach (the line runs on east to Massy-Palaiseau)
		var tr := _put(k, float(_lozere(svc)["s"]["8"]) + 120.0, 25.0)
		var gap := 420.0 if far else 120.0
		var spot: Vector3 = tr.route_point(tr.front + gap)
		var car := Car.new()
		car.setup("sedan")
		_main.add_child(car)
		_main.cars.append(car)
		car.place(Transform3D(Basis(Vector3.UP, 0.3), spot + Vector3.UP * 0.6))
		await _frames(20)
		var bot: Object = _tt.bots[tr]
		var horn := false
		var emergency := false
		var h0: float = car.health
		var knocks: int = _tt.knocks
		for f in 60 * 60:
			await physics_frame
			horn = horn or tr.horn
			emergency = emergency or bot.emergency
			if tr.speed < 0.01 and f > 30:
				break
		var stop_gap: float = tr.route_point(tr.front).distance_to(spot)
		if far:
			_check(horn and _tt.knocks == knocks and car.health == h0,
					"a car 420 m ahead: horn, the train stops %.0f m short of it, untouched" % stop_gap)
		else:
			_check(horn and emergency and _tt.knocks > knocks and car.health < h0,
					"a car 120 m ahead: horn, emergency braking, knocked aside (health %.0f -> %.0f), stopped" % [h0, car.health])
		_main.cars.erase(car)
		car.queue_free()
		_tt._stow(tr)
		await _frames(5)


## Far away only the light shells are drawn.
func _far() -> void:
	var tr := _put(0, 1200.0, 0.0)
	var ok := true
	for car: Node3D in tr.cars:
		var far := car.get_node_or_null(String(car.kind + "_far")) as GeometryInstance3D
		var body := car.get_node_or_null(String(car.kind + "_body")) as GeometryInstance3D
		var inside := car.get_node_or_null(String(car.kind + "_interior")) as GeometryInstance3D
		ok = ok and far and body and inside and far.visibility_range_begin >= tr.FAR - 1.0 \
				and body.visibility_range_end <= tr.FAR + 1.0 and inside.visibility_range_end < body.visibility_range_end
	_check(ok, "each car: its light shell beyond %.0f m, its body within, its interior within %.0f m" % [tr.FAR, tr.INSIDE])


## Frame time of the trains: physics ticks with four trains running against none.
func _cost() -> void:
	var t0 := Time.get_ticks_usec()
	await _frames(300)
	var idle := (Time.get_ticks_usec() - t0) / 300.0
	for k in _tt.services.size():
		_put(k, 1300.0, 20.0)
		_put(k, 2100.0, 20.0)
	await _frames(30)
	t0 = Time.get_ticks_usec()
	await _frames(300)
	var busy := (Time.get_ticks_usec() - t0) / 300.0
	print("cost: %.2f ms per physics tick with four trains running, %.2f ms with none (+%.2f ms)" % [
			busy / 1000.0, idle / 1000.0, (busy - idle) / 1000.0])
	_check(busy - idle < 2000.0, "four trains cost under 2 ms a tick (+%.2f ms)" % ((busy - idle) / 1000.0))


## The service's stop at Lozère (the line runs on to Massy-Palaiseau: westbound trains stop elsewhere first).
static func _lozere(svc: Dictionary) -> Dictionary:
	for st: Dictionary in svc["stops"]:
		if st["name"] == "Lozère":
			return st
	return svc["stops"][0]
