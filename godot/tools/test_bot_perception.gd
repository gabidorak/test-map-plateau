extends "res://tools/test_base.gd"
## Headless checks for what the bots see and how they take it (scripts/traffic/perception.gd, scripts/traffic/bus_bot.gd):
## - perception: the player on foot is a walker, not at the wheel; a vehicle's siren puts it among the sirens and in its
##   LAN state;
## - the drivers' reaction times: drawn about bus_bot.gd REACTION (median, spread, range);
## - a walker standing in a bot car's lane: it stops short of them without touching them, sounds the horn when kept
##   waiting, and drives on once they have stepped off the road;
## - a walker stepping out in front of it closer than it drives in its reaction time and a bit: it reacts its reaction
##   time later, too late: it runs into them;
## - a walker crossing in front of it: seen on their way into its lane (before they are in it), never run over;
## - an emergency vehicle coming up behind with its siren on: it puts its right indicator on, pulls over to the right
##   and stops; drives on, back in its lane, once the siren is off;
## - one coming the other way: it slows down to ONCOMING_SLOW, pulled over, and they pass;
## - one about to cross its path ahead: it stops short of the crossing and goes on once it has gone by;
## - a bus serves its stop with the player waiting by it on the pavement.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_bot_perception.gd

const BusBot = preload("res://scripts/traffic/bus_bot.gd")
const Car = preload("res://scripts/car.gd")
const REACTION := 1.0                       # s, the cars' reaction time in the checks (the median)

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	OS.set_environment("PLATEAU_CARS", "4")
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
	await _frames(30)
	var traffic: Node = _main.traffic
	# the bots alone on the map, sent out by hand
	traffic.send_cars = false
	traffic.departures.clear()
	for b: Object in traffic.bots:
		if not b.idle:
			b._stow()
	await _frames(2)
	await _perception()
	var cars := _cars()
	var a: Object = cars[0]
	var b: Object = cars[1]
	var spot := _stretch(a)
	if spot.is_empty():
		_check(false, "a straight two-way stretch to test on")
	else:
		_reaction_draws(a)
		await _walker_in_lane(a, spot)
		await _walker_stepping_out(a, spot)
		await _walker_crossing(a, spot)
		await _siren_behind(a, b, spot)
		await _siren_oncoming(a, b, spot)
		await _siren_across(a, b, spot)
	await _bus_stop()
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## The player is a walker on foot, not at the wheel; a siren puts its vehicle among the sirens and in its LAN state.
func _perception() -> void:
	var seen: RefCounted = _main.traffic.seen
	var player: Node3D = _main.player
	await _frames(2)
	var on_foot: bool = player in seen.walkers
	var car: Node3D = _main.spawn_car_near_player()
	_main.enter_car(car)
	car.siren = true
	await _frames(2)
	var driving: bool = player in seen.walkers
	var k: int = seen.cars.find(car)
	_check(on_foot and not driving, "the player on foot is a walker, not at the wheel")
	_check(k >= 0 and k in seen.sirens and car.net_state()[4] & Car.FLAGS_SIREN != 0 and car.audio.siren,
			"a vehicle with its siren on is among the sirens, its LAN state says so, it sounds")
	car.siren = false
	_main.exit_car()
	_main.remove_vehicles([car])
	await _frames(2)


## A walker standing in the lane ahead of a bot car: it stops short of them, sounds the horn, and drives on once they
## have stepped off the road.
func _walker_in_lane(a: Object, spot: Array) -> void:
	var player: Node3D = _main.player
	a.may_glide = false
	a.put(spot[0], spot[1] - 60.0, 8.0)
	a.reaction = REACTION
	player.teleport(_on_road(a, spot[1], 0.0))
	var closest := INF
	var stopped := 0.0
	var gap := INF
	var horn := false
	var why := ""
	for f in 60 * 30:
		await physics_frame
		var g: float = spot[1] - (a.s + a.nose)
		closest = minf(closest, g)
		if absf(a.car.speed()) < 0.3:
			stopped += 1.0 / 60.0
			if gap == INF:
				gap = g
				why = a.reason
		horn = horn or a.horn
		if stopped > a.HORN_AFTER + 1.0 and horn:
			break
	_check(gap > 1.0 and gap < a.GAP + 2.5 and closest > 0.5 and why == "walker" and a.obstacle_walker == player,
			"a walker in its lane: it stops %.1f m short of them (closest %.1f m, %s)" % [gap, closest, why])
	_check(horn, "and sounds the horn when kept waiting")
	player.teleport(_on_road(a, spot[1], 10.0))
	var on := false
	for f in 60 * 12:
		await physics_frame
		if a.car.speed() > 2.0:
			on = true
			break
	_check(on, "drives on once they have stepped off the road")
	a._stow()
	await _frames(2)


## The drivers' reaction times (bus_bot.gd draw_reaction): about REACTION, log-normal, within REACTION_RANGE.
func _reaction_draws(a: Object) -> void:
	var t := PackedFloat32Array()
	for k in 4000:
		t.append(a.draw_reaction())
	t.sort()
	var range_: Vector2 = a.REACTION_RANGE
	var within := 0
	for x in t:
		within += 1 if x > 0.74 and x < 1.35 else 0
	_check(absf(t[2000] - a.REACTION) < 0.05 and absf(within / 4000.0 - 0.68) < 0.04 and t[0] >= range_.x
			and t[-1] <= range_.y, "reaction times: median %.2f s, %d %% within 0.74-1.35 s, %.2f-%.2f s" % [t[2000],
			roundi(within / 40.0), t[0], t[-1]])


## A walker steps out in front of a bot car, as far as it drives in its reaction time and 0.3 s more, plus 1 m: it
## notices them its reaction time later, too late to stop: it runs into them.
func _walker_stepping_out(a: Object, spot: Array) -> void:
	var player: Node3D = _main.player
	a.may_glide = false
	a.put(spot[0], spot[1] - 80.0, 8.0)
	a.reaction = REACTION
	while a.s + a.nose < spot[1] - (a.car.speed() * (REACTION + 0.3) + 1.0):
		await physics_frame
	var v0: float = a.car.speed()
	var ahead: float = spot[1] - (a.s + a.nose)
	player.teleport(_on_road(a, spot[1], 0.0))
	var t := 0.0
	var reacted := INF
	var impact := -1.0                      # its speed as its front reached them
	for f in 60 * 6:
		await physics_frame
		t += 1.0 / 60.0
		if reacted == INF and a.obstacle_walker == player:
			reacted = t
		if spot[1] - (a.s + a.nose) < 1.0:
			impact = a.car.speed()
			break
	_check(reacted >= REACTION and reacted < REACTION + 0.25,
			"a walker stepping out %.1f m ahead (at %.1f m/s): it reacts %.2f s later" % [ahead, v0, reacted])
	_check(impact > 3.0, "too late: it runs into them at %.1f m/s" % impact)
	player.teleport(_on_road(a, spot[1], 10.0))
	a._stow()
	await _frames(30)


## A walker crossing the road in front of a bot car: seen on their way into its lane, before they are in it; never run
## over; it goes on once they are across.
func _walker_crossing(a: Object, spot: Array) -> void:
	var player: Node3D = _main.player
	a.may_glide = false
	a.put(spot[0], spot[1] - 35.0, 8.0)
	a.reaction = REACTION
	var side: float = a.half_width + a.WALKER_SIDE
	var seen_at := INF                      # m right of its path the walker was when it first stopped for them
	var closest := INF                      # m from its front to them along the path while they were in its lane
	var lat := 5.0
	for f in 60 * 20:
		lat = maxf(lat - 1.5 / 60.0, -5.0)  # 1.5 m/s, right to left
		player.teleport(_on_road(a, spot[1], lat))
		await physics_frame
		if a.obstacle_walker == player and seen_at == INF:
			seen_at = lat
		if absf(lat) < side:
			closest = minf(closest, spot[1] - (a.s + a.nose))
		if a.s + a.nose > spot[1] + 5.0:
			break
	_check(seen_at > side and closest > 0.5, "a walker crossing: seen %.1f m right of its path on their way into its lane (in it within %.1f), never closer than %.1f m" % [
			seen_at, side, closest])
	_check(a.s + a.nose > spot[1] + 5.0, "and on its way once they are across")
	player.teleport(_on_road(a, spot[1], 10.0))
	a._stow()
	await _frames(2)


## An emergency vehicle comes up behind with its siren on: the car puts its right indicator on, pulls over as far as
## there is room (felt for: bus_bot.gd _room_right) without touching the kerb (no jolt, no bounce off it) and stops; the
## siren off, it drives on back in its lane.
func _siren_behind(a: Object, b: Object, spot: Array) -> void:
	a.may_glide = false
	b.may_glide = false
	a.put(spot[0], spot[1] - 45.0, 8.0)
	a.reaction = REACTION
	b.put(spot[0], spot[1] - 90.0, 10.0)
	b.car.siren = true
	_hide_player(a)
	var right := false
	var stopped := 0
	var aside := 0.0
	var off := 0.0
	var lowest := 0.0                       # m right of its path its body got to at least (< 0: thrown left)
	var jolt := 0.0                         # m/s², the hardest slowing down from one tick to the next over 3 m/s (a knock;
											# slower, the wheels' brakes snap a car still at once)
	var v := absf(a.car.speed())
	for f in 60 * 20:
		await physics_frame
		var v1 := absf(a.car.speed())
		if a.making_way == BusBot.WAY_BEHIND:
			if v > 3.0:
				jolt = maxf(jolt, (v - v1) * 60.0)
			lowest = minf(lowest, _off_path(a))
			right = right or a.car.indicator == -1
		v = v1
		stopped = stopped + 1 if v1 < 0.3 and a.making_way == BusBot.WAY_BEHIND else 0
		if stopped > 60:
			aside = a._aside
			off = _off_path(a)
			break
	var room: float = a._aside_room
	# (the kerb here is 1.7-1.8 m right of its path, world.json: room for any of the bot cars to pull over a little)
	_check(right and stopped > 60 and room > 0.2 and aside > room - 0.05 and off > room * 0.5 - 0.05 and lowest > -0.1
			and jolt < 9.0,
			"an emergency vehicle coming up behind: right indicator, pulled over %.2f m (room %.2f m, its body %.2f m right of its path, never thrown left: %.2f, hardest slowing %.1f m/s²) and stopped" % [
			aside, room, off, lowest, jolt])
	b.car.siren = false
	b._stow()
	var on := false
	for f in 60 * 15:
		await physics_frame
		if a.making_way == BusBot.WAY_NONE and a.car.speed() > 2.0 and a._aside < 0.05:
			on = true
			break
	_check(on, "the siren off, it drives on, back in its lane")
	a._stow()
	_show_player()
	await _frames(2)


## An emergency vehicle comes the other way in the other lane with its siren on: the car slows down to ONCOMING_SLOW,
## pulled over, and they pass.
func _siren_oncoming(a: Object, b: Object, spot: Array) -> void:
	var traffic: Node = _main.traffic
	a.may_glide = false
	b.may_glide = false
	a.put(spot[0], spot[1] - 45.0, 8.0)
	a.reaction = REACTION
	var id := _route_beside(a, spot, -minf(a._room_at(spot[1]), 3.2))
	b.line = {"ref": "test", "routes": [id]}
	b.put(0, 15.0, 8.0)
	b.car.siren = true
	_hide_player(a)
	var oncoming := false
	var fastest := 0.0
	var gone_by := false
	var crossed := false
	for f in 60 * 30:
		await physics_frame
		oncoming = oncoming or a.making_way == BusBot.WAY_ONCOMING
		var pa: Vector3 = a.car.global_position
		var pb: Vector3 = b.car.global_position
		var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
		if dist < 20.0:
			fastest = maxf(fastest, a.car.speed())
		if not crossed and a.car.global_basis.z.dot(pb - pa) < -2.0:
			crossed = true
		if crossed and dist > 30.0:
			gone_by = true
			break
	_check(oncoming and gone_by and fastest < a.ONCOMING_SLOW + 1.0,
			"an emergency vehicle coming the other way: it slows down (at most %.1f m/s as they meet) and they pass" % fastest)
	b.car.siren = false
	b.line = traffic.car_line
	b._stow()
	a._stow()
	traffic.routes.erase(id)
	_show_player()
	await _frames(2)


## An emergency vehicle about to cross the car's path ahead with its siren on (gliding across, through whatever is
## there): the car stops short of the crossing and goes on once it has gone by.
func _siren_across(a: Object, b: Object, spot: Array) -> void:
	var traffic: Node = _main.traffic
	a.may_glide = false
	a.put(spot[0], spot[1] - 50.0, 8.0)
	a.reaction = REACTION
	var x: Vector2 = a.at(spot[1])
	var t: Vector2 = (a.at(spot[1] + 1.0) - x).normalized()
	var n := Vector2(t.y, -t.x)             # right of a's path
	var pts := []
	for k in range(70, -71, -2):
		var p := x + n * k
		pts.append([p.x, p.y])
	var v := []
	v.resize(pts.size())
	v.fill(10.0)
	var id := "test:across"
	traffic.routes[id] = {"pts": pts, "v": v, "step": 2.0, "length": (pts.size() - 1) * 2.0, "stops": [], "lights": [],
			"yields": [], "turns": [], "room": [], "then": "respawn", "start": "edge", "end": "edge"}
	b.line = {"ref": "test", "routes": [id]}
	b.may_glide = true
	b.put(0, 25.0, 10.0)                    # 45 m right of a's path
	b._assist_to = INF                      # gliding all along: through the buildings
	b.car.siren = true
	_hide_player(a)
	var crossed := false
	var furthest := -INF                    # a's front, m past the crossing, until b is across
	var why := false
	var on := false
	for f in 60 * 30:
		await physics_frame
		why = why or a.reason == "emergency vehicle"
		var lb: float = (BusBot.flat(b.car.global_position) - x).dot(n)
		crossed = crossed or lb < -6.0
		if not crossed:
			furthest = maxf(furthest, a.s + a.nose - spot[1])
		elif a.s + a.nose > spot[1] + 5.0:
			on = true
			break
	_check(crossed and why and furthest < -1.0,
			"an emergency vehicle crossing its path ahead: it stops short of the crossing (front %.1f m before it)" % -furthest)
	_check(on, "and goes on once it has gone by")
	b.car.siren = false
	b.line = traffic.car_line
	b._stow()
	a._stow()
	traffic.routes.erase(id)
	_show_player()
	await _frames(2)


## A bus serves its stop with the player waiting on the pavement by it, a metre from its side.
func _bus_stop() -> void:
	var bus: Object = null
	for b: Object in _main.traffic.bots:
		if b.line["ref"] == "4606":
			bus = b
			break
	if bus == null:
		_check(false, "a bus of the 4606")
		return
	bus.may_glide = false
	var stop: Dictionary = bus.route["stops"][1]
	var at: float = float(stop["s"]) - bus.nose
	bus.put(bus.route_index, at - 90.0)
	_main.player.teleport(_on_road(bus, at, bus.half_width + 1.0))
	var opened := false
	for f in 60 * 60:
		await physics_frame
		if bus.state == 1 and bus.car.doors_open:
			opened = true
			break
	_check(opened, "a bus serves its stop %s with the player waiting by it" % stop["name"])
	bus._stow()
	await _frames(2)


# ---------------------------------------------------------------- helpers

## The point on the road `lat` m right of bot `b`'s path `d` m along it (global, on the surface).
func _on_road(b: Object, d: float, lat: float) -> Vector3:
	var p: Vector2 = b.at(d)
	var t: Vector2 = (b.at(d + 1.0) - p).normalized()
	var q := p + Vector2(t.y, -t.x) * lat
	return Vector3(q.x, b._surface(d, q) + 0.05, -q.y)


## m right of its path the middle of bot `b`'s body is.
func _off_path(b: Object) -> float:
	var c: Node3D = b.car
	return b.project(BusBot.flat(c.to_global(c.extents_center)), b.s - 8.0, b.s + 8.0).y


## The player out of the bots' way (no walker) but near `b`, so that the bots about drive with the physics.
func _hide_player(b: Object) -> void:
	var player: Node3D = _main.player
	player.teleport(b.car.global_position + Vector3(0.0, 40.0, 0.0))
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED


func _show_player() -> void:
	var player: Node3D = _main.player
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT


## A route made for a check: `a`'s path around `spot` run backwards, `shift` m right of it (< 0: the other lane).
func _route_beside(a: Object, spot: Array, shift: float) -> String:
	var id := "test:beside"
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
	_main.traffic.routes[id] = {"pts": pts, "v": v, "step": a._step, "length": (pts.size() - 1) * a._step, "stops": [],
			"lights": [], "yields": [], "turns": [], "room": [], "then": "respawn", "start": "edge", "end": "edge"}
	return id


## [route index, s] of a straight stretch of `a`'s routes with room for a car coming the other way and nothing to stop
## at (no light, give-way) for 150 m around; [] if none (as tools/test_car_bots.gd).
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
