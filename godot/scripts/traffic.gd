extends Node
## Traffic (game.gd makes it as Main/Traffic): the traffic lights' clock, the bot buses and the bot cars.
## - Lights: every car and pedestrian signal head runs the same CYCLE s cycle (shaders/toy_prop.gdshader) offset by its
##   phase (pipeline/plateau/props.py). The cycle runs on the game's shared clock (net.gd clock(): the host's in a LAN
##   game), handed to the shader as the global `signal_clock` each frame: the lights show the same colour on every
##   screen, and the bots stop at the reds the players see (light()).
## - Bot buses (scripts/bus_bot.gd): the lines of world/bus_routes.json (pipeline/plateau/transit.py, its lines and
##   headways in pipeline/buses.toml). A bus sets off every `headway` s from the start of each direction of each line
##   (where no bus runs on into it from a terminus), offset by the line's `phase`; at the start the lines are filled
##   as if they had been running (bus spacing from the planned speeds and the stops). A bus that vanished (map edge,
##   terminus) waits, stowed, for the next departure of its line; more buses are made while none waits.
## - Bot cars (scripts/bus_bot.gd too): `cars` of them (world/car_routes.json, car_traffic.py; PLATEAU_CARS=n overrides)
##   on routes from the map edge to the map edge, picked at random (longer ones more often). Spread along their routes
##   at the start; one that vanished at the edge comes back on another route, mid-way where no player is within HIDDEN
##   m, else at its map edge.
## The host can stop them (stop_bots: game.gd set_bot_traffic, the in-game menu) and start them again.
## Only the peer that hosts (or plays solo, or a dedicated server) runs the bots; the other peers get their vehicles as
## remote vehicles (net.gd), which they can ride in (buses) but not drive.

const BusBot = preload("res://scripts/bus_bot.gd")
const ROUTES := "res://world/bus_routes.json"
const CAR_ROUTES := "res://world/car_routes.json"
const CYCLE := 30.0                         # s, toy_prop.gdshader `cycle`
const GREEN := 0.45                         # share of the cycle: green until then, amber until AMBER, then red
const AMBER := 0.55
const SPAWN_CLEAR := 20.0                   # m from any vehicle a bot is spawned or comes back in (ahead of it)
const WAY_BEHIND := 8.0                     # m behind it
const LANE_CLEAR := 2.0                     # m either side of its path (vehicles in the other lane do not count)
const MAX_BUSES := 30                       # per line
const STOP_COST := 25.0                     # s a stop adds to a bus's trip on average (braking, doors, pulling out)
const TERMINUS_SEEN := 40.0                 # m: a player this close and a bus does not appear at a terminus...
const TERMINUS_WAIT := 0.5                  # ...for this share of the headway at most
const HIDDEN := 180.0                       # m from every player a bot car may come back in mid-route
const EDGE_SEEN := 60.0                     # m from every player it may come back in at the map edge
const CAR_LOOK := 0.5                       # s between looks for a way back in for the stowed cars

var game: Node3D                            # game.gd
var bots: Array = []                        # BusBot: the buses, then the cars
var lines: Array = []                       # bus_routes.json "lines"
var routes := {}                            # route id -> route (bus_routes.json, car_routes.json)
var car_line := {}                          # the bot cars' "line": every car route
var signal_clock := 0.0                     # s into the cycle, as last handed to the shader
var departures: Array = []                  # [line, route index, s of the next departure]
var time := 0.0                             # s since the bots started
var departed := {}                          # route id -> buses that set off from its start (tests)
var send_cars := true                       # stowed bot cars sent out again (tests turn it off)
# the vehicles out (not stowed) as of this physics tick, for the bots' looks around: footprint centre (pipeline x/y),
# velocity (BusBot.velocity_of), heading, half length
var snap_cars: Array = []
var snap_pos := PackedVector2Array()
var snap_vel := PackedVector2Array()
var snap_fwd := PackedVector2Array()
var snap_reach := PackedFloat32Array()

var _car_lengths := PackedFloat32Array()    # cumulative route lengths (picking routes by length)
var _car_models: Array = []
var _car_look := 0.0
var _rng := RandomNumberGenerator.new()


func _process(_delta: float) -> void:
	signal_clock = fposmod(clock(), CYCLE)
	RenderingServer.global_shader_parameter_set("signal_clock", signal_clock)


func _physics_process(delta: float) -> void:
	if bots.is_empty():
		return
	time += delta
	_snapshot()
	for d: Array in departures:
		if time >= d[2]:
			var late: float = time - d[2]
			if _depart(d[0], d[1], late) or late > float(d[0]["headway"]) * 0.9:
				d[2] += float(d[0]["headway"])
	_car_look -= delta
	if _car_look <= 0.0 and send_cars:
		_car_look = CAR_LOOK
		var n := 0
		for b: Object in bots:
			if b.idle and is_same(b.line, car_line) and n < 4:
				n += 1
				_send_car(b, false)


func _snapshot() -> void:
	snap_cars.clear()
	snap_pos.clear()
	snap_vel.clear()
	snap_fwd.clear()
	snap_reach.clear()
	for c: Node3D in game.cars:
		if c.stowed:
			continue
		snap_cars.append(c)
		snap_pos.append(BusBot.flat(c.to_global(c.extents_center)))
		snap_vel.append(BusBot.velocity_of(c))
		snap_fwd.append(BusBot.flat(c.global_basis.z).normalized())
		snap_reach.append(c.half_extents.z)


## Seconds on the game's shared clock (the lights' cycle runs on it).
func clock() -> float:
	return game.net.clock()


## A car signal head of phase `phase` at shared time `t`: 0 green, 1 amber, 2 red (toy_prop.gdshader lit()).
static func light(t: float, phase: float) -> int:
	var c := fposmod(t / CYCLE + phase, 1.0)
	return 0 if c < GREEN else (1 if c < AMBER else 2)


## Starts the bot buses and cars (solo, host, dedicated server).
func start_bots() -> void:
	_rng.randomize()
	var data: Variant = _read(ROUTES)
	if data != null:
		lines = data["lines"]
		routes = data["routes"]
		for line: Dictionary in lines:
			_start_line(line)
	var cars: Variant = _read(CAR_ROUTES)
	if cars != null:
		_start_cars(cars)


## Stops the bots: returns their vehicles, for game.gd to take off the map (on every peer). start_bots starts afresh.
func stop_bots() -> Array:
	var out := []
	for b: Object in bots:
		if is_instance_valid(b.car):
			out.append(b.car)
	bots.clear()
	lines = []
	routes = {}
	car_line = {}
	departures.clear()
	departed.clear()
	time = 0.0
	snap_cars.clear()
	snap_pos.clear()
	snap_vel.clear()
	snap_fwd.clear()
	snap_reach.clear()
	_car_lengths.clear()
	_car_models = []
	_car_look = 0.0
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("no %s: run `python -m plateau buses`" % path)
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("cannot read %s" % path)
		return null
	return data


# ---------------------------------------------------------------- buses

## The line's departures, and (`fill`) its buses on the way as if it had been running for a while.
func _start_line(line: Dictionary, fill := true) -> void:
	var ids: Array = line["routes"]
	var h := float(line["headway"])
	var first := fposmod(float(line.get("phase", 0.0)), 1.0) * h      # the next departure, s from now
	for r in ids.size():
		var before: Dictionary = routes[ids[(r - 1 + ids.size()) % ids.size()]]
		if ids.size() > 1 and before["then"] == "continue":
			continue                            # buses come into it from the one before
		departures.append([line, r, time + first])
		var k := 1
		while fill:
			var at := _after(line, r, k * h - first)
			if at.is_empty() or k > MAX_BUSES:
				break
			_spawn_bus(line, at[0], at[1])
			k += 1


## Where a bus that left the start of route `r` `elapsed` s ago is: [route index, s], or [] once off the map.
func _after(line: Dictionary, r: int, elapsed: float) -> Array:
	var ids: Array = line["routes"]
	var t := 0.0
	for hop in ids.size():
		var route: Dictionary = routes[ids[r]]
		var v: Array = route["v"]
		var step := float(route["step"])
		var stops: Array = route["stops"]
		var next_stop := 0
		for i in v.size():
			var d := i * step
			if next_stop < stops.size() and d >= float(stops[next_stop]["s"]):
				t += STOP_COST
				next_stop += 1
			t += step / maxf(float(v[i]), 2.0)
			if t >= elapsed:
				return [r, d]
		if route["then"] != "continue":
			return []
		r = (r + 1) % ids.size()
	return []


## A new bus of `line` on route `r`, its front about `s` m along (on to a free stretch ahead).
func _spawn_bus(line: Dictionary, r: int, s: float) -> void:
	var bot := _new_bot(line, line["model"])
	var route: Dictionary = routes[line["routes"][r]]
	var s0 := clampf(s - bot.nose, bot.tail + 1.0, float(route["length"]) - bot.nose - 1.0)
	bot._set_route(r)
	for k in 12:
		if way_clear(bot, s0):
			bot.put(r, s0, bot._planned(s0 + bot.nose) * 0.8)
			return
		s0 += 25.0
		if s0 > float(route["length"]) - bot.nose - 1.0:
			break
	bot._stow()


## A bus of `line` sets off from the start of route `r` (`late` s after its time): an idle one, else a new one.
## False when the way in is not free.
func _depart(line: Dictionary, r: int, late: float) -> bool:
	var bot: Object = null
	var count := 0
	for b: Object in bots:
		if is_same(b.line, line):
			count += 1
			if b.idle and bot == null:
				bot = b
	var route: Dictionary = routes[line["routes"][r]]
	if bot == null:
		if count >= MAX_BUSES:
			return false
		bot = _new_bot(line, line["model"])
		bot._stow()
	bot._set_route(r)
	var s0: float = bot.tail + 1.0
	var xf: Transform3D = bot.pose_at(s0)
	if not way_clear(bot, s0):
		return false
	if route["start"] == "terminus" and late < float(line["headway"]) * TERMINUS_WAIT \
			and _player_within(xf.origin, TERMINUS_SEEN):
		return false
	bot.put(r, s0, 0.0 if route["start"] == "terminus" else minf(bot._planned(s0 + bot.nose), 8.0))
	departed[line["routes"][r]] = departed.get(line["routes"][r], 0) + 1
	return true


# ---------------------------------------------------------------- cars

func _start_cars(data: Dictionary) -> void:
	var ids: Array = data["routes"].keys()
	var total := 0.0
	for id: String in ids:
		var route: Dictionary = data["routes"][id]
		route["then"] = "respawn"
		routes[id] = route
		total += float(route["length"])
		_car_lengths.append(total)
	if ids.is_empty():
		return
	car_line = {"ref": "car", "model": "", "routes": ids}
	_car_models = data["models"]
	var n := int(OS.get_environment("PLATEAU_CARS")) if OS.get_environment("PLATEAU_CARS") != "" else int(data["cars"])
	for k in n:
		var bot := _new_bot(car_line, _car_models[_rng.randi() % _car_models.size()])
		bot._stow()
		_send_car(bot, true)


## Sends stowed car `bot` out on a random route: mid-way out of the players' sight (anywhere at the start), else at
## the route's start by the map edge. Stays stowed when neither is free (looked at again in CAR_LOOK s).
func _send_car(bot: Object, start: bool) -> void:
	var u := _rng.randf() * _car_lengths[-1]
	var r := _car_lengths.bsearch(u)
	bot._set_route(r)
	var length := float(bot.route["length"])
	var lo: float = bot.tail + 1.0
	var hi: float = length - bot.nose - 30.0
	for k in 4:
		var s0 := _rng.randf_range(lo, hi) if k < 3 else lo
		var xf: Transform3D = bot.pose_at(s0)
		var seen := _player_within(xf.origin, (30.0 if start else HIDDEN) if k < 3 else EDGE_SEEN)
		if seen or not way_clear(bot, s0):
			continue
		bot.put(r, s0, bot._planned(s0 + bot.nose) * 0.8)
		return


# ---------------------------------------------------------------- both

func _new_bot(line: Dictionary, model: String) -> Object:
	var car: Node3D = game.new_vehicle(model)
	var bot := BusBot.new()
	bot.setup(self, car, line, 0)
	game.add_bot_bus(car, bot.pose_at(bot.tail + 1.0), bot)
	bots.append(bot)
	return bot


## True when no vehicle stands in `bot`'s lane (LANE_CLEAR m either side of its path, from WAY_BEHIND m behind its
## reference point at `d` to SPAWN_CLEAR m ahead of its front, on its route): where it may appear.
func way_clear(bot: Object, d: float) -> bool:
	var tip: Vector2 = bot.at(d)
	for c: Node3D in game.cars:
		if c == bot.car or c.stowed:
			continue
		var p := BusBot.flat(c.to_global(c.extents_center))
		if p.distance_to(tip) > bot.nose + SPAWN_CLEAR + WAY_BEHIND + c.half_extents.z:
			continue
		var reach: float = c.half_extents.z
		var q: Vector2 = bot.project(p, d - bot.tail - WAY_BEHIND - reach, d + bot.nose + SPAWN_CLEAR + reach)
		if q.x > d - bot.tail - WAY_BEHIND - reach and q.x < d + bot.nose + SPAWN_CLEAR + reach \
				and absf(q.y) < LANE_CLEAR + c.half_extents.x:
			return false
	return true


func _player_within(p: Vector3, d: float) -> bool:
	for q: Vector3 in game.player_spots():
		if Vector2(q.x - p.x, q.z - p.z).length() < d:
			return true
	return false
