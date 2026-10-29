extends Node
## PTA Online's bus job (ONLINE_MILESTONES.md O5, ONLINE_MODE.md 5): a child of the PTA Online mode (scripts/modes/
## online_mode.gd) on every peer, with its own RPCs. The host (the official server) judges everything from the states it
## already gets of the player's bus, and pays through the accounts service; the player's game only asks and shows.
## - Duty: at the bus depot's terminal, the player picks one of the real lines the bots run (world/bus_routes.json,
##   pipeline/plateau/transit.py). They drive their bus out (one of theirs) or, without one, a lent bus of the line's
##   model comes out on a bay. One bot bus of the line leaves the map meanwhile (traffic.gd hold_bus); it comes back
##   when they go off duty (the depot's terminal, U), take another vehicle out, wreck the bus, or leave.
## - The line: its routes in turn (both directions, and the short Lozère lines' legs). The job first waits for the bus
##   to be on one of them, going its way (from the depot, the 4606 starts at the door); from there it follows the
##   front of the bus along the route (`s`) and the next stop. Between two routes (a terminus, a map edge) it waits
##   again for the bus on the next one.
## - A stop is served once the front of the bus is in its bay (STOP_BEFORE m short of the stop's mark to STOP_AFTER m
##   past it, within STOP_SIDE m of the path), under STILL m/s, its doors open `doors` s on end (the doors key). It pays
##   at once (data/jobs.json "bus"): `stop` + `per_km` for the route driven since the last stop, + `fast_share` when
##   that stretch took no longer than `fast_ratio` times the bots' planned driving time, + the stretch's bonuses (air
##   time, near misses, overtakes, drifts); times the combo (up by `combo_step` per stop served, back to 1 at a
##   penalty), times `owned` for the player's own bus, times 1 + `rider` per other player riding along.
## - Penalties (taken from the next pay, the combo back to 1): a stop driven past without serving it, a hard crash
##   (CRASH of the bus's health at once), off the route (over ON_ROUTE m from its path for OFF_TIME s on end, or over
##   OFF_FAR m at once: the job then waits for the bus back on the route, and the stops missed meanwhile are skipped).
## - Checks against a patched game (the bus is simulated by its driver, ONLINE_MODE.md 6.1): a jump of over TELEPORT m
##   in a tick, a speed over the model's top speed (SPEED_MARGIN, SPEED_SLACK) for TOO_FAST s, or a stretch driven
##   faster than that on average: the stretch pays nothing, and the job finds the bus on the route again. The doors'
##   time is counted here. The accounts service cuts what an account earns from all jobs to `hour_cap` an hour.
## - Nobody at the wheel, or another player: the job waits (nothing counts).
## The player's game shows the line, the next stop and how far, the stretch's time, the combo and what it has paid
## (top right, under the wallet), the money and bonuses popping in, and puts the waypoint on the next stop.
## Played solo (the tools), the money is the mode's test_money, the cap counted here; PLATEAU_JOB_LOG=1 prints the log
## lines a dedicated server prints (every stop's pay worked out, the bonuses, the penalties).

const Car = preload("res://scripts/car.gd")
const BusBot = preload("res://scripts/bus_bot.gd")
const Economy = preload("res://scripts/economy.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const UiStyle = preload("res://scripts/ui_style.gd")

signal answered(ok: bool, text: String)     # the host's answer to our last duty request

const DATA := "res://data/jobs.json"
const ROUTES := "res://world/bus_routes.json"
const BUSES := ["bus-idfm", "bus-idfm-artic"]
const STOP_BEFORE := 14.0                   # m short of a stop's mark the front may be (a 12 m bus at an 18 m's stop)
const STOP_AFTER := 12.0                    # m past it (an 18 m bus at a 12 m's stop)
const STOP_SIDE := 3.5                      # m off the path
const SKIP_PAST := 8.0                      # m past the bay: the stop is skipped
const STILL := 1.0                          # m/s
const ON_ROUTE := 12.0                      # m from the path the bus is still on the route (a lane or two over)...
const OFF_TIME := 4.0                       # ...and further for this many s on end it is off it
const OFF_FAR := 40.0                       # m: off it at once
const JOIN_SIDE := 6.0                      # m from the path the bus joins the route...
const JOIN_ANGLE := 0.64                    # ...facing its way (cos 50°)
const END_REACH := 25.0                     # m from the end of a route with every stop done: on to the next
const TELEPORT := 25.0                      # m in a tick
const SPEED_MARGIN := 1.2                   # times the model's top speed...
const SPEED_SLACK := 3.0                    # ...+ this, m/s
const TOO_FAST := 0.5                       # s over it
const CRASH := 0.15                         # share of the health lost in a tick: a hard crash
const CRASH_AGAIN := 2.0                    # s before another crash counts
const LOOK_EVERY := 0.1                     # s between looks for bonuses
const SEARCH_EVERY := 0.5                   # s between looks for the bus on the route
const NEAR_SPEED := 8.0                     # m/s at least for a near miss...
const NEAR_REL := 8.0                       # ...passing a moving vehicle this much faster or the other way...
const NEAR_GAP := 0.8                       # ...within this many m, without touching it
const NEAR_AGAIN := 10.0                    # s before the same vehicle counts again
const PASS_SIDE := 5.5                      # m between the middles of the bus and a vehicle it overtakes
const PASS_AGAIN := 20.0                    # s before overtaking the same vehicle counts again
const DRIFT_ANGLE := 0.21                   # rad between the way it faces and the way it goes...
const DRIFT_SPEED := 7.0                    # ...at this speed (m/s): drifting
const AIR_LIFT := 0.6                       # m higher off the ground than it rides: in the air
const AIR_SPEED := 4.0                      # m/s at least
const RIDE_SMOOTH := 0.05                   # per look, of the moving average of how high it rides
const POP_TIME := 3.5                       # s a popping line stays

var mode: Node                              # online_mode.gd, which makes this node
var pay := {}                               # data/jobs.json "bus"
var cap := 30000                            # € an account may earn from jobs an hour (data/jobs.json "hour_cap")
var duties := {}                            # host: peer -> Duty
var time := 0.0                             # host: s of physics since it started (played solo: the cap's clock)
var info := {}                              # client: our duty as the host sent it, {} off duty
var _routes := {}                           # host: route id -> Route
var _lines: Array = []                      # host: bus_routes.json "lines"
var _solo_paid: Array = []                  # played solo: [time, €] paid this last hour
var _info_t := 0.0                          # client: s since `info` came
var _waypoint: Variant = null               # client: the waypoint we put (on the next stop)
var _hud: PanelContainer
var _head: Label
var _next: Label
var _stats: Label
var _pops: VBoxContainer


## A route of a line (bus_routes.json): its path, the bots' planned speeds and its stops.
class Route:
	var id := ""
	var dest := ""
	var pts := PackedVector2Array()
	var tcum := PackedFloat32Array()        # planned s from its start to each point (the bots' speeds, no stops)
	var step := 1.0
	var length := 0.0
	var stops: Array = []                   # {"s", "name"}

	func _init(rid: String, r: Dictionary) -> void:
		id = rid
		dest = str(r["dest"])
		step = float(r["step"])
		length = float(r["length"])
		stops = r["stops"]
		var t := 0.0
		var v: Array = r["v"]
		for i in r["pts"].size():
			pts.append(Vector2(r["pts"][i][0], r["pts"][i][1]))
			tcum.append(t)
			t += step / maxf(float(v[i]), 2.0)

	func at(d: float) -> Vector2:
		var f := clampf(d / step, 0.0, pts.size() - 1.001)
		var i := int(f)
		return pts[i].lerp(pts[i + 1], f - i)

	func dir(d: float) -> Vector2:
		var i := clampi(int(d / step), 0, pts.size() - 2)
		return (pts[i + 1] - pts[i]).normalized()

	## s of the bots' planned driving from `a` to `b` m along it.
	func planned(a: float, b: float) -> float:
		var n := tcum.size() - 1
		return tcum[clampi(int(b / step), 0, n)] - tcum[clampi(int(a / step), 0, n)]

	## (distance along the path, offset to its right) of `p`, nearest within [from, to] (as bus_bot.gd's).
	func project(p: Vector2, from: float, to: float) -> Vector2:
		var n := pts.size()
		var i0 := clampi(floori(from / step), 0, n - 2)
		var i1 := clampi(ceili(to / step), 0, n - 2)
		var best := INF
		var out := Vector2(from, INF)
		for i in range(i0, i1 + 1):
			var a := pts[i]
			var ab := pts[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d2 := p.distance_squared_to(a + ab * t)
			if d2 < best:
				best = d2
				out = Vector2((i + t) * step, -ab.cross(p - a) / maxf(ab.length(), 1e-6))
		return out

	## s of the point of the path nearest to `p` from `from` m on, within JOIN_SIDE m of it and facing `fwd` its
	## way, or -1. Skips the stretches too far to come within reach (the points are `step` apart along it).
	func find(p: Vector2, fwd: Vector2, from: float) -> float:
		var n := pts.size()
		var best := -1.0
		var best_off := INF
		var i := clampi(int(from / step), 0, n - 1)
		while i < n:
			var d := pts[i].distance_to(p)
			if d > 30.0:
				i += maxi(1, int((d - 30.0) / step))
				continue
			var q := project(p, maxf((i - 10) * step, from), (i + 10) * step)
			if absf(q.y) < JOIN_SIDE and absf(q.y) < best_off and dir(q.x).dot(fwd) > JOIN_ANGLE:
				best_off = absf(q.y)
				best = q.x
			i += 10
		return best


## A player on duty (host).
class Duty:
	var peer := 0
	var account := 0
	var username := ""
	var line: Dictionary                    # bus_routes.json line
	var car_id := ""                        # their bus (online_mode.gd vehicles)
	var owned := false                      # their own (not lent)
	var held: Object                        # the bot bus taken off the map (traffic.gd hold_bus), or null
	var r := 0                              # index into the line's routes
	var state := "start"                    # "start" (waiting for the bus on the route), "route", "lost" (off it)
	var joined := false                     # it has been on the line (else "start" looks on every route of it)
	var s := 0.0                            # m along the route of the front of the bus
	var next := 0                           # index of the next stop
	var seg_s := 0.0                        # s of the last stop served (or where it joined)
	var seg_t := 0.0                        # s since
	var bonus := 0                          # € of the stretch's bonuses
	var debt := 0                           # € of penalties, taken from the next pay
	var combo := 1.0
	var void_why := ""                      # the stretch pays nothing (teleport, too fast)
	var doors_t := 0.0                      # s stopped in the bay with the doors open
	var off_t := 0.0                        # s off the route
	var last := Vector3.ZERO                # middle of its front section last tick
	var has_last := false
	var vel := Vector2.ZERO                 # m/s, pipeline x/y (from the positions: the server poses remote buses)
	var fast_t := 0.0
	var health := -1.0
	var crash_t := 0.0
	var look_t := 0.0
	var search_t := 0.0
	var ride := NAN                         # m from the bus's origin down to the ground on its wheels (moving average)
	var air_t := 0.0
	var drift_t := 0.0
	var near := {}                          # vehicle -> time it may count again
	var ahead := {}                         # vehicle -> true: close ahead going the same way (overtakes)
	var passed := {}                        # vehicle -> time it may count again
	var earned := 0                         # € paid this duty
	var served := 0                         # stops served
	var events: Array = []                  # [kind, €, text, s, route index] (tests)


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if data is Dictionary:
		pay = data["bus"]
		cap = int(data["hour_cap"])
	else:
		push_error("No PTA Online job pay: %s missing" % DATA)
	if OS.get_environment("PLATEAU_JOB_CAP") != "":
		cap = int(OS.get_environment("PLATEAU_JOB_CAP"))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if duties.has(id):
			end_duty(id, "left the game"))


func _exit_tree() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.queue_free()


# ---------------------------------------------------------------- host: lines

func _load() -> void:
	if not _lines.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES)) if FileAccess.file_exists(ROUTES) else null
	if not data is Dictionary:
		push_error("No bus lines: %s missing" % ROUTES)
		return
	_lines = data["lines"]
	for rid: String in data["routes"]:
		_routes[rid] = Route.new(rid, data["routes"][rid])


## The bus lines the depot offers: [{"duty": ref, "label", "note"}], the player's own first ("On duty"), then "Go off
## duty" when they are.
func offer(peer: int) -> Array:
	_load()
	var out := []
	var on: Duty = duties.get(peer)
	for line: Dictionary in _lines:
		var ends := str(_routes[line["routes"][0]].dest)
		var start := str(_routes[line["routes"][-1]].dest)
		out.append({"duty": line["ref"], "label": "Line %s · %s ↔ %s" % [line["ref"], start, ends], "note":
				"On duty" if on and on.line["ref"] == line["ref"] else Car.display_name(line["model"])})
	if on:
		out.append({"duty": "", "label": "Go off duty", "note": "%s paid this duty" % Economy.money(on.earned)})
	return out


func _line(ref: String) -> Dictionary:
	_load()
	for line: Dictionary in _lines:
		if line["ref"] == ref:
			return line
	return {}


func _route(d: Duty) -> Route:
	return _routes[d.line["routes"][d.r]]


# ---------------------------------------------------------------- host: duty

## Host: player `peer` goes on duty on line `ref` at garage `gid` (the bus depot): [ok, text].
func duty_for(peer: int, gid: String, ref: String) -> Array:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return [false, "Not logged in."]
	var g: Dictionary = mode.garages.get_garage(gid)
	if g.get("kind", "") != "depot":
		return [false, "Duty starts at the bus depot."]
	if not mode.near(peer, g):
		return [false, "Walk up to the terminal."]
	var line := _line(ref)
	if line.is_empty():
		return [false, "No such line."]
	if duties.has(peer):
		if duties[peer].line["ref"] == ref:
			return [false, "You are on duty on line %s already." % ref]
		end_duty(peer, "", false)
	var id: String = mode.vehicle_of(int(acc["account"]))
	var car: Car = mode.car_of(id)
	if car == null or car.model_name not in BUSES:
		var problem: String = mode.spawn_for(peer, gid, 0, str(line["model"]))
		if problem != "":
			return [false, problem]
		id = mode.vehicle_of(int(acc["account"]))
		car = mode.car_of(id)
	var d := Duty.new()
	d.peer = peer
	d.account = int(acc["account"])
	d.username = str(acc["username"])
	d.line = line
	d.car_id = id
	d.owned = int(mode.vehicles[id].get("vehicle", 0)) > 0
	d.health = car.health
	var traffic: Node = mode.game.traffic
	if traffic and not traffic.bots.is_empty():
		d.held = traffic.hold_bus(ref, car.global_position)
	var front := car.to_global(car.extents_center)
	var best := INF
	for k in line["routes"].size():         # its first route: the one starting nearest
		var dist: float = _routes[line["routes"][k]].at(5.0).distance_to(_flat(front))
		if dist < best:
			best = dist
			d.r = k
	duties[peer] = d
	_log("%s is on duty on line %s (%s %s)%s" % [d.username, ref, "their" if d.owned else "a lent", car.model_name,
			", bot bus %s off the map" % d.held.car.net_id if d.held else ""])
	_send_info(d)
	return [true, "On duty: line %s. Drive to the line (the waypoint), serve every stop: in the bay, doors open (%s)." % [
			ref, Settings.key_text("doors")]]


## Host: player `peer` goes off duty (`why` told them; "" says nothing): the bot bus held comes back.
func end_duty(peer: int, why: String, tell := true) -> void:
	var d: Duty = duties.get(peer)
	if d == null:
		return
	duties.erase(peer)
	var back := ""
	if d.held and mode.game.traffic:
		back = mode.game.traffic.release_bus(d.held)
	_log("%s is off duty (%s): %d € in %d stops%s" % [d.username, why if why != "" else "changed lines", d.earned, d.served,
			", bot bus %s back %s" % [d.held.car.net_id, "on the map" if back == "map" else "at its next departure"]
			if d.held and back != "" else ""])
	if tell:
		mode.send_to(peer, self, "_c_duty", [{}])
		if why != "" and why != "left the game":
			mode.send_to(peer, self, "_c_notice", ["Off duty: %s. %s paid." % [why, Economy.money(d.earned)]])


func _physics_process(delta: float) -> void:
	if mode == null or not mode.hosting:
		return
	time += delta
	for peer: int in duties.keys():
		if duties.has(peer):
			_tick(duties[peer], delta)


func _tick(d: Duty, delta: float) -> void:
	var car: Car = mode.car_of(d.car_id)
	if car == null or not mode.vehicles.has(d.car_id):
		end_duty(d.peer, "your bus went back")
		return
	if car.broken:
		end_duty(d.peer, "your bus is wrecked")
		return
	var mid := car.to_global(car.extents_center)
	if d.has_last:
		var jump := Vector2(mid.x - d.last.x, mid.z - d.last.z).length()
		if jump > maxf(TELEPORT, car.max_speed * delta * 3.0):
			_cheat(d, "teleport", "a jump of %d m" % roundi(jump))
		else:
			d.vel = d.vel.lerp(Vector2(mid.x - d.last.x, d.last.z - mid.z) / delta, 0.3)
			d.fast_t = d.fast_t + delta if jump / delta > car.max_speed * SPEED_MARGIN + SPEED_SLACK else 0.0
			if d.fast_t > TOO_FAST:
				d.fast_t = 0.0
				_cheat(d, "too fast", "%d km/h" % roundi(jump / delta * 3.6))
	d.last = mid
	d.has_last = true
	d.crash_t -= delta
	var driver: int = _driver(car)
	if car.health < d.health - CRASH * car.max_health and d.crash_t <= 0.0 and driver == d.peer and d.state == "route":
		d.crash_t = CRASH_AGAIN
		_penalty(d, "crash", "Hard crash", int(pay["crash_fine"]))
	d.health = car.health
	if driver != d.peer:
		d.doors_t = 0.0
		return
	if d.state == "route":
		d.seg_t += delta
		_follow(d, car, mid, delta)
		if d.state == "route":
			_bonuses(d, car, delta)
	else:
		d.search_t -= delta
		if d.search_t <= 0.0:
			d.search_t = SEARCH_EVERY
			_search(d, car, mid)


## The bus is on its route (`mid`: the middle of its front section, which keeps closer to the path in the bends than
## its front): how far along, off it, at a stop, at the end.
func _follow(d: Duty, car: Car, mid: Vector3, delta: float) -> void:
	var route := _route(d)
	var reach := car.half_extents.z
	var q := route.project(_flat(mid), d.s - reach - 20.0, d.s - reach + 60.0)
	q.x += reach                            # the front's s
	if absf(q.y) < ON_ROUTE:
		d.off_t = 0.0
		d.s = maxf(d.s, q.x)
	else:
		d.off_t += delta
		if d.off_t > OFF_TIME or absf(q.y) > OFF_FAR:
			d.state = "lost"
			d.off_t = 0.0
			_penalty(d, "off_route", "Off the route", int(pay["off_route_fine"]))
			_send_info(d)
			return
	while d.next < route.stops.size() and d.s > float(route.stops[d.next]["s"]) + STOP_AFTER + SKIP_PAST:
		_penalty(d, "skip", "Skipped %s" % route.stops[d.next]["name"], int(pay["skip_fine"]))
		d.next += 1
		d.doors_t = 0.0
		_send_info(d)
	if d.next < route.stops.size():
		var mark := float(route.stops[d.next]["s"])
		if q.x > mark - STOP_BEFORE and q.x < mark + STOP_AFTER and absf(q.y) < STOP_SIDE and d.vel.length() < STILL \
				and car.doors_open:
			d.doors_t += delta
			if d.doors_t >= float(pay["doors"]):
				_serve(d, car, route, q.x)
		else:
			d.doors_t = 0.0
	elif d.s > route.length - END_REACH:
		d.r = (d.r + 1) % d.line["routes"].size()
		d.state = "start"
		d.s = 0.0
		d.next = 0
		d.search_t = 0.0
		_event(d, "info", "Line %s: %s reached" % [d.line["ref"], route.dest], 0)
		_send_info(d)


## Stop `d.next` of `route` served, the front at `at`: the pay.
func _serve(d: Duty, car: Car, route: Route, at: float) -> void:
	var stop := str(route.stops[d.next]["name"])
	var dist := maxf(at - d.seg_s, 0.0)
	if d.seg_t > 0.0 and dist / d.seg_t > car.max_speed * SPEED_MARGIN and d.void_why == "":
		d.void_why = "driven faster than the bus goes (%d km/h on average)" % roundi(dist / d.seg_t * 3.6)
	var base := float(pay["stop"]) + dist / 1000.0 * float(pay["per_km"])
	var planned := route.planned(d.seg_s, at)
	var fast := base * float(pay["fast_share"]) if dist > 100.0 and d.seg_t <= planned * float(pay["fast_ratio"]) else 0.0
	var riders := mini(maxi(mode.game.riders(car), 0), int(pay["riders_max"]))
	var gross := roundi((base + fast + d.bonus) * d.combo * (float(pay["owned"]) if d.owned else 1.0)
			* (1.0 + float(pay["rider"]) * riders))
	var why := d.void_why
	if why != "":
		gross = 0
	var due := maxi(gross - d.debt, 0)
	var fined := mini(d.debt, gross)
	d.debt -= fined
	_log("%s served %s (line %s): %d € (%d m in %.0f s, planned %.0f s: base %d, fast %d, bonus %d, ×%.1f combo%s%s%s)%s" % [
			d.username, stop, d.line["ref"], due, roundi(dist), d.seg_t, planned, roundi(base), roundi(fast), d.bonus,
			d.combo, ", owned" if d.owned else "", ", %d riding" % riders if riders > 0 else "",
			", %d € of fines" % fined if fined > 0 else "", " NOT PAID: " + why if why != "" else ""])
	var text := stop
	if why != "":
		text = "%s · not paid: %s" % [stop, why]
	elif fined > 0:
		text = "%s (−%s fines)" % [stop, Economy.money(fined)]
	d.served += 1
	d.next += 1
	d.combo = minf(d.combo + float(pay["combo_step"]), float(pay["combo_max"]))
	d.seg_s = at
	d.seg_t = 0.0
	d.bonus = 0
	d.void_why = ""
	d.doors_t = 0.0
	_send_info(d)
	_pay(d, due, text, "%s (line %s)" % [stop, d.line["ref"]], fast > 0.0)


## Waiting for the bus on the route (to start, between routes, or back from off it).
func _search(d: Duty, car: Car, mid: Vector3) -> void:
	var fwd := _flat(car.global_transform.basis.z).normalized()
	var p := _flat(mid)
	var ks: Array = range(d.line["routes"].size()) if not d.joined else [d.r]
	for k: int in ks:
		var route: Route = _routes[d.line["routes"][k]]
		var at := route.find(p, fwd, d.s - 50.0 if d.state == "lost" and k == d.r else 0.0)
		if at < 0.0:
			continue
		at += car.half_extents.z             # the front's s
		var was_lost := d.state == "lost"
		d.r = k
		d.state = "route"
		d.joined = true
		d.off_t = 0.0
		if was_lost:
			if at - d.s > 100.0:            # a shortcut: what was driven off the route pays nothing
				d.seg_s = at
			d.s = maxf(d.s, at)
		else:
			d.s = at
			d.seg_s = at
			d.seg_t = 0.0
			d.next = 0
			while d.next < route.stops.size() and float(route.stops[d.next]["s"]) + STOP_AFTER < at:
				d.next += 1                 # joining past them: not skipped
		_send_info(d)
		return


## The server doesn't believe what the bus did (`kind`: teleport, too fast): the stretch pays nothing, and the job
## finds the bus on the route again.
func _cheat(d: Duty, kind: String, what: String) -> void:
	if d.void_why == "":
		_log("%s's bus on line %s: %s (%s), the stretch won't pay" % [d.username, d.line["ref"], kind, what])
		_event(d, "void", "Refused: %s (%s), this stretch won't pay" % [kind, what], 0)
	d.void_why = kind
	if d.state == "route":
		d.state = "lost"
		_send_info(d)


func _penalty(d: Duty, kind: String, text: String, fine: int) -> void:
	d.debt += fine
	d.combo = 1.0
	_event(d, kind, text, -fine)
	_log("%s on line %s: %s (−%d €)" % [d.username, d.line["ref"], text, fine])
	_send_info(d)


func _bonus(d: Duty, kind: String, text: String, amount: int) -> void:
	if amount <= 0:
		return
	d.bonus += amount
	_event(d, kind, text, amount)
	_log("%s on line %s: %s (+%d €)" % [d.username, d.line["ref"], text, amount])
	_send_info(d)


## Air time, drifts, near misses and overtakes, every LOOK_EVERY s.
func _bonuses(d: Duty, car: Car, delta: float) -> void:
	d.look_t -= delta
	if d.look_t > 0.0:
		return
	var dt := LOOK_EVERY - d.look_t
	d.look_t = LOOK_EVERY
	var v := d.vel.length()
	var fwd := _flat(car.global_transform.basis.z).normalized()
	var gap := _ground_gap(car)               # air
	if is_nan(d.ride) and gap < INF:
		d.ride = gap
	elif gap < d.ride + AIR_LIFT:
		d.ride = lerpf(d.ride, gap, RIDE_SMOOTH)
	if gap < INF and gap > d.ride + AIR_LIFT and v > AIR_SPEED:
		d.air_t += dt
	elif d.air_t > 0.0:
		if d.air_t >= float(pay["air_min"]):
			_bonus(d, "air", "Air time %.1f s" % d.air_t, roundi(d.air_t * float(pay["air_per_s"])))
		d.air_t = 0.0
	if v > DRIFT_SPEED and d.vel.dot(fwd) > 0.0 and acos(clampf(d.vel.normalized().dot(fwd), -1.0, 1.0)) > DRIFT_ANGLE:
		d.drift_t += dt
	elif d.drift_t > 0.0:
		if d.drift_t >= float(pay["drift_min"]):
			_bonus(d, "drift", "Drift %.1f s" % d.drift_t, roundi(d.drift_t * float(pay["drift_per_s"])))
		d.drift_t = 0.0
	var mid := _flat(car.to_global(car.extents_center))
	var right := Vector2(fwd.y, -fwd.x)
	var length := car.half_extents.z + (8.0 if car.trailer else 0.0)
	var mine := []
	for c: Car in mode.game.cars:
		if c == car or c.stowed or not is_instance_valid(c):
			continue
		var pc := _flat(c.to_global(c.extents_center))
		if pc.distance_to(mid) > 40.0:
			d.ahead.erase(c)
			continue
		var cv: Vector2 = BusBot.velocity_of(c)
		var lon := (pc - mid).dot(fwd)
		var lat := absf((pc - mid).dot(right))
		if cv.dot(fwd) > 3.0 and v > cv.dot(fwd) + 2.0 and lat < PASS_SIDE:   # overtakes
			if lon > car.half_extents.z:
				d.ahead[c] = true
			elif lon < -length - c.half_extents.z and d.ahead.has(c):
				d.ahead.erase(c)
				if d.passed.get(c, 0.0) <= time:
					d.passed[c] = time + PASS_AGAIN
					_bonus(d, "overtake", "Overtake", int(pay["overtake"]))
		else:
			d.ahead.erase(c)
		if v > NEAR_SPEED and cv.length() > 2.0 and (d.vel - cv).length() > NEAR_REL and d.near.get(c, 0.0) <= time \
				and d.crash_t <= 0.0:   # near misses
			if mine.is_empty():
				mine = _rects(car)
			var g := _gap(mine, _rects(c))
			if g > 0.05 and g < NEAR_GAP:
				d.near[c] = time + NEAR_AGAIN
				_bonus(d, "near_miss", "Near miss", int(pay["near_miss"]))


## Pays `due` € to the duty's account for a stop (`text` shown, `reason` in the payments log).
func _pay(d: Duty, due: int, text: String, reason: String, fast: bool) -> void:
	var paid := due
	if due > 0:
		if mode.game.economy.official:
			var r: Dictionary = await mode.game.economy.pay(d.account, due, reason, "bus:%s" % d.line["ref"], cap)
			paid = int(r["data"].get("paid", 0)) if r["ok"] else 0
			if not r["ok"]:
				push_warning("Could not pay %s: %s" % [d.username, r["message"]])
		else:
			paid = solo_pay(due)
		if paid < due:
			_log("%s: %d € of %d paid (hourly cap %d €)" % [d.username, paid, due, cap])
	d.earned += paid
	_event(d, "stop", text + (" · fast" if fast else "") + (" · hourly cap reached" if paid < due else ""), paid)
	_send_info(d)


## Played solo: pays `amount` € into the mode's test_money, within the hourly cap (every job's: the stunts' too); what
## was paid.
func solo_pay(amount: int) -> int:
	_solo_paid = _solo_paid.filter(func(e: Array) -> bool: return time - e[0] < 3600.0)
	var hour := 0
	for e: Array in _solo_paid:
		hour += int(e[1])
	var paid := mini(amount, maxi(cap - hour, 0))
	_solo_paid.append([time, paid])
	mode.test_money += paid
	mode.game.economy.balance = mode.test_money
	mode.game.economy.wallet_changed.emit()
	return paid


func _event(d: Duty, kind: String, text: String, amount: int) -> void:
	d.events.append([kind, amount, text, d.s, d.r])
	mode.send_to(d.peer, self, "_c_event", [kind, text, amount])


func _send_info(d: Duty) -> void:
	var route := _route(d)
	var out := {"ref": d.line["ref"], "colour": d.line.get("colour", "#3bb2ff"), "text": d.line.get("text", "#000000"),
			"dest": route.dest, "state": d.state, "combo": d.combo, "bonus": d.bonus, "debt": d.debt, "earned": d.earned,
			"seg_t": d.seg_t, "owned": d.owned, "held": d.held.car.net_id if d.held else "", "served": d.served}
	if d.state != "route":
		out["stop"] = "the line" if d.state == "start" else "back to the route"
		out["at"] = route.at(5.0) if d.state == "start" else route.at(d.s + 20.0)
	elif d.next < route.stops.size():
		out["stop"] = str(route.stops[d.next]["name"])
		out["at"] = route.at(float(route.stops[d.next]["s"]))
	else:
		out["stop"] = route.dest + " (end of the line)"
		out["at"] = route.at(route.length)
	mode.send_to(d.peer, self, "_c_duty", [out])


func _log(text: String) -> void:
	if mode.game.net.dedicated or OS.get_environment("PLATEAU_JOB_LOG") == "1":
		print(text)


## Who drives `car`: a peer, 0 nobody (played solo: us when we do).
func _driver(car: Car) -> int:
	if mode.game.net.active:
		return int(mode.game.net.driver_of.get(car.net_id, 0))
	return mode.me() if mode.game.driving == car else 0


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)


## m from `car`'s floor down to the ground (or a deck) at its least, under its front, middle and rear (one end over a
## kerb or a drop is not in the air), INF when none of them finds anything within 8 m.
static func _ground_gap(car: Car) -> float:
	var skip: Array[RID] = []
	for b in car.bodies():
		skip.append(b.get_rid())
	var space := car.get_world_3d().direct_space_state
	var best := INF
	for f: float in [-0.8, 0.0, 0.8]:
		var from := car.to_global(Vector3(car.extents_center.x, 0.0, car.extents_center.z + car.half_extents.z * f))
		var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 8.0, Layers.SOLID)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.y - (hit["position"] as Vector3).y)
	return best


## The boxes of `c`'s sections seen from above: [centre, x axis, z axis, half sizes] (pipeline x/y).
static func _rects(c: Car) -> Array:
	var out := []
	for b in c.bodies():
		for cs in b.get_children():
			if cs is CollisionShape3D and cs.shape is BoxShape3D and not cs.disabled:
				var xf: Transform3D = b.global_transform * cs.transform
				var h: Vector3 = cs.shape.size * 0.5
				out.append([_flat(xf.origin), _flat(xf.basis.x).normalized(), _flat(xf.basis.z).normalized(),
						Vector2(h.x * xf.basis.x.length(), h.z * xf.basis.z.length())])
	if out.is_empty():
		var xf := c.global_transform
		out.append([_flat(xf * c.extents_center), _flat(xf.basis.x).normalized(), _flat(xf.basis.z).normalized(),
				Vector2(c.half_extents.x, c.half_extents.z)])
	return out


## m between the nearest boxes of two vehicles (_rects), 0 touching.
static func _gap(a: Array, b: Array) -> float:
	var best := INF
	for ra: Array in a:
		for rb: Array in b:
			for pair: Array in [[ra, rb], [rb, ra]]:
				var r: Array = pair[0]
				var o: Array = pair[1]
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var corner: Vector2 = r[0] + r[1] * r[3].x * sx + r[2] * r[3].y * sz
						var l: Vector2 = corner - o[0]
						var dx := maxf(absf(l.dot(o[1])) - o[3].x, 0.0)
						var dz := maxf(absf(l.dot(o[2])) - o[3].y, 0.0)
						best = minf(best, Vector2(dx, dz).length())
	return best


# ---------------------------------------------------------------- the local player

## Asks to go on duty on line `ref` at garage `gid`'s terminal ("" ref: off duty).
func ask_duty(gid: String, ref: String) -> void:
	if ref == "":
		mode.to_host(self, "_h_off", [])
	else:
		mode.to_host(self, "_h_duty", [gid, ref])


func on_duty() -> bool:
	return not info.is_empty()


func _build_hud() -> void:
	_hud = PanelContainer.new()
	_hud.name = "BusJob"
	_hud.add_theme_stylebox_override("panel", UiStyle.panel(0.72, 10, 12))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size.x = 330
	_hud.add_child(box)
	_head = UiStyle.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(_head)
	_next = UiStyle.label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_next)
	_stats = UiStyle.label("", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(_stats)
	_pops = VBoxContainer.new()
	_pops.add_theme_constant_override("separation", 2)
	box.add_child(_pops)
	mode.game.hud.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_hud.offset_top = 54.0
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.visible = false


func _process(delta: float) -> void:
	if _hud == null or info.is_empty():
		return
	_info_t += delta
	var here: Vector3 = mode.game.driving.global_position if mode.game.driving else mode.game.map_eye()
	var at: Vector2 = info["at"]
	var dist := at.distance_to(Vector2(here.x, -here.z))
	var far := "%d m" % roundi(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
	if info["state"] == "route":
		_next.text = "Next: %s · %s" % [info["stop"], far]
	elif info["state"] == "start":
		_next.text = "Drive to the line: %s (the waypoint), going towards %s" % [far, info["dest"]]
	else:
		_next.text = "Off the route! Back on it, %s away" % far
	var t := float(info["seg_t"]) + (_info_t if info["state"] == "route" else 0.0)
	var parts := ["%d:%02d" % [int(t) / 60, int(t) % 60], "combo ×%.1f" % float(info["combo"])]
	if int(info["bonus"]) > 0:
		parts.append("+%s bonus" % Economy.money(int(info["bonus"])))
	if int(info["debt"]) > 0:
		parts.append("−%s fines" % Economy.money(int(info["debt"])))
	parts.append("%s this duty" % Economy.money(int(info["earned"])))
	_stats.text = "  ·  ".join(parts)
	for p in _pops.get_children():
		p.set_meta("t", float(p.get_meta("t")) + delta)
		p.modulate.a = clampf((POP_TIME - float(p.get_meta("t"))) / 0.6, 0.0, 1.0)
		if float(p.get_meta("t")) > POP_TIME:
			p.queue_free()


## The HUD's lines (tests).
func hud_text() -> String:
	if _hud == null or not _hud.visible:
		return ""
	return "%s\n%s\n%s" % [_head.text, _next.text, _stats.text]


# ---------------------------------------------------------------- messages

@rpc("any_peer", "call_remote", "reliable")
func _h_duty(gid: String, ref: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r := duty_for(peer, gid, ref)
	if not r[0]:
		_log("%s: no duty on line %s (%s)" % [mode.game.net.player_name(peer), ref, r[1]])
	mode.send_to(peer, self, "_c_answer", r)


@rpc("any_peer", "call_remote", "reliable")
func _h_off() -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	if duties.has(peer):
		end_duty(peer, "you asked")
		mode.send_to(peer, self, "_c_answer", [true, "Off duty."])
	else:
		mode.send_to(peer, self, "_c_answer", [false, "You aren't on duty."])


@rpc("authority", "call_remote", "reliable")
func _c_answer(ok: bool, text: String) -> void:
	answered.emit(ok, text)
	if ok and mode.ui_open():
		mode.close_ui()
	if ok or not mode.ui_open():
		mode.game.toast(text)
	else:
		mode._panel.set_status(text)


@rpc("authority", "call_remote", "reliable")
func _c_duty(now: Dictionary) -> void:
	var was := info
	info = now
	_info_t = 0.0
	if _hud == null and mode.game.mode != "server":
		_build_hud()
	if _hud == null:
		return
	_hud.visible = not now.is_empty()
	if now.is_empty():
		if _waypoint != null and mode.game.waypoint == _waypoint:
			mode.game.set_waypoint(null)
		_waypoint = null
		for p in _pops.get_children():
			p.queue_free()
		return
	_head.text = "%s  →  %s%s" % [now["ref"], now["dest"], "  ·  your bus ×%s" % str(pay.get("owned", 1.5))
			if now["owned"] else ""]
	_head.add_theme_color_override("font_color", Color(str(now["colour"])).lightened(0.25))
	if was.get("at") != now["at"]:
		_waypoint = now["at"]
		mode.game.set_waypoint(_waypoint)


@rpc("authority", "call_remote", "reliable")
func _c_event(kind: String, text: String, amount: int) -> void:
	if _hud == null:
		return
	var l := UiStyle.label("", 17 if kind == "stop" else 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	if kind == "stop":
		l.text = "+%s  %s" % [Economy.money(amount), text]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.5))
	elif amount < 0:
		l.text = "%s  −%s" % [text, Economy.money(-amount)]
		l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif amount > 0:
		l.text = "%s  +%s" % [text, Economy.money(amount)]
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		l.text = text
		l.add_theme_color_override("font_color", UiStyle.TEXT_WARN if kind == "void" else Color.WHITE)
	l.set_meta("t", 0.0)
	_pops.add_child(l)
	_pops.move_child(l, 0)
	while _pops.get_child_count() > 4:
		_pops.get_child(_pops.get_child_count() - 1).free()


@rpc("authority", "call_remote", "reliable")
func _c_notice(text: String) -> void:
	mode.game.toast(text)
