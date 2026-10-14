extends SceneTree
## Headless checks for the bot cars (scripts/traffic.gd, scripts/bus_bot.gd; world/car_routes.json):
## - they spawn (the [cars] count of pipeline/buses.toml) on their routes with a bot at the wheel, none on the player;
## - they drive: most of them out and moving a minute later, the ones that reached the map edge sent out again;
## - two of them meeting on a two-way road (one on its route, the other coming the other way in the other lane, both
##   with the physics) pass each other without slowing down for it, without touching;
## - two meeting head-on in one lane wait, then one drives past the other (no collision between them meanwhile), and
##   both go on.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_car_bots.gd

const MIN_PASS_SPEED := 3.0                 # m/s: slower than this while passing the oncoming car is slowing down for it

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
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


func _cars() -> Array:
	var traffic: Node = _main.traffic
	return traffic.bots.filter(func(b: Object) -> bool: return is_same(b.line, traffic.car_line))


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	await _frames(2)
	var traffic: Node = _main.traffic
	var cars := _cars()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/car_routes.json"))
	var out := 0
	var driven := true
	var near := 0
	var player: Vector3 = _main.player.global_position
	for b: Object in cars:
		driven = driven and b.car.is_bot()
		if not b.idle:
			out += 1
			var p: Vector3 = b.car.global_position
			if Vector2(p.x - player.x, p.z - player.z).length() < 25.0:
				near += 1
	_check(cars.size() == int(data["cars"]) and out >= cars.size() * 0.9 and driven,
			"%d bot cars on %d routes (%d out at the start, a bot driving each)" % [cars.size(), data["routes"].size(), out])
	_check(near == 0, "none put on the player (%d within 25 m)" % near)

	# a minute on
	var runs := 0
	var was := {}
	for b: Object in cars:
		was[b] = b.idle
	var t0: float = traffic.time
	while traffic.time < t0 + 60.0:
		await physics_frame
		for b: Object in cars:
			if was[b] and not b.idle:
				runs += 1
			was[b] = b.idle
	var moving := 0
	var speed := 0.0
	out = 0
	for b: Object in cars:
		if not b.idle:
			out += 1
			var v: float = b._speed if b.gliding else b.car.speed()
			speed += v
			moving += 1 if v > 1.0 else 0
	_check(out >= cars.size() * 0.85 and moving >= out * 0.5 and speed / maxf(out, 1) > 3.0,
			"a minute later %d out, %d moving (mean %.1f m/s), %d sent out again" % [out, moving, speed / maxf(out, 1), runs])

	# the rest with two cars alone
	traffic.send_cars = false
	traffic.departures.clear()
	for b: Object in traffic.bots:
		if not b.idle:
			b._stow()
	await _frames(2)
	await _oncoming(cars[0], cars[1], false)
	await _oncoming(cars[0], cars[1], true)
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## Car `a` on a straight two-way stretch of its route and car `b` 90 m ahead coming the other way, on a route made
## for the check: `a`'s path run backwards, in the other lane (or, `one_lane`, on `a`'s path itself).
func _oncoming(a: Object, b: Object, one_lane: bool) -> void:
	var traffic: Node = _main.traffic
	var spot := _stretch(a)
	if spot.is_empty():
		_check(false, "a straight two-way stretch to meet on")
		return
	a.put(spot[0], spot[1] - 45.0)
	var shift := 0.0 if one_lane else -minf(a._room_at(spot[1]), 3.2)    # m right of a's path: the other lane
	var id := "test:%s" % ("one lane" if one_lane else "two lanes")
	var pts := []
	var d: float = spot[1] + 60.0
	while d > spot[1] - 120.0:
		var p: Vector2 = a.at(d)
		var t: Vector2 = (a.at(d + 1.0) - p).normalized()
		var q := p + Vector2(t.y, -t.x) * shift
		pts.append([q.x, q.y])
		d -= a._step
	var v := []
	v.resize(pts.size())
	v.fill(8.0)
	traffic.routes[id] = {"pts": pts, "v": v, "step": a._step, "length": (pts.size() - 1) * a._step, "stops": [],
			"lights": [], "yields": [], "turns": [], "room": [], "then": "respawn", "start": "edge", "end": "edge"}
	b.line = {"ref": "test", "routes": [id]}
	b.put(0, 15.0)
	a.may_glide = false
	b.may_glide = false
	# the player between them, so that both drive with the physics
	_main.player.teleport(a.car.global_position + Vector3(0.0, 30.0, 0.0))
	var start_a: float = a.s
	var start_b: float = b.s
	var slowest := INF
	var closest := INF
	var both_stopped := 0
	var crossed := false
	var gone_by := false
	for f in 60 * 40:
		await physics_frame
		var pa: Vector3 = a.car.global_position
		var pb: Vector3 = b.car.global_position
		var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
		closest = minf(closest, dist)
		if dist < 25.0:
			slowest = minf(slowest, minf(a.car.speed(), b.car.speed()))
		if absf(a.car.speed()) < 0.3 and absf(b.car.speed()) < 0.3:
			both_stopped += 1
		# past each other: b behind a
		if not crossed and a.car.global_basis.z.dot(pb - pa) < -2.0:
			crossed = true
		if crossed and dist > 30.0:
			gone_by = true
			break
	if one_lane:
		_check(both_stopped > 30 and gone_by, "head-on in one lane: they wait (%.1f s), then one drives past the other, both on their way (%s; a %.0f m, b %.0f m on)" % [
				both_stopped / 60.0, "past each other" if gone_by else "stuck", a.s - start_a, b.s - start_b])
	else:
		_check(gone_by and slowest > MIN_PASS_SPEED and closest > a.half_width + b.half_width,
				"meeting a car coming the other way in its lane, it passes without slowing down (slowest %.1f m/s, %.1f m apart at closest)" % [
				slowest, closest])
	b.line = traffic.car_line
	b._stow()
	a._stow()
	traffic.routes.erase(id)


## [route index, s] of a straight stretch of `a`'s routes with room for a car coming the other way and nothing to stop
## at (no light, give-way) for 150 m around; [] if none.
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
