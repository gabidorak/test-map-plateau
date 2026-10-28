extends Node
## Traffic (game.gd makes it as Main/Traffic): the traffic lights' clock, the bot buses and the bot cars, and the RER B
## trains (scripts/train_traffic.gd, its child Trains on every peer; game.gd starts them with the bots).
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
## - Each tick: a snapshot of the vehicles out (positions on a grid of CELL m cells, near()) and of the players (where
##   they are, what they ride) for the bots' looks around; then the gliding bots due this tick move on (BusBot
##   glide_step: GLIDE_SLOTS slots of the ticks to come), the others are moved by their car.gd.
## - Load: the share of each tick the physics scripts take (`tick_load`, from this node, first, to TickEnd, last). In
##   the game (not the tools; PLATEAU_ADAPTIVE=1|0 overrides) the traffic thins out a level (LEVELS: gliding bots move
##   half as often, then fewer bot cars out) after LOAD_AFTER s over LOAD_HIGH, and fills up again a level after
##   LOAD_RELAX s under LOAD_LOW: a slow computer (a laptop on battery) stays playable instead of the physics falling
##   behind.
## The host can stop them (stop_bots: game.gd set_bot_traffic, the in-game menu) and start them again.
## Only the peer that hosts (or plays solo, or a dedicated server) runs the bots; the other peers get their vehicles as
## remote vehicles (net.gd), which they can ride in (buses) but not drive.

const BusBot = preload("res://scripts/bus_bot.gd")
const TrainTraffic = preload("res://scripts/train_traffic.gd")
const ROUTES := "res://world/bus_routes.json"
const CAR_ROUTES := "res://world/car_routes.json"
const CYCLE := 30.0                         # s, toy_prop.gdshader `cycle`
const GREEN := 0.45                         # share of the cycle: green until then, amber until AMBER, then red
const AMBER := 0.55
const SPAWN_CLEAR := 20.0                   # m from any vehicle a bot is spawned or comes back in (ahead of it)
const WAY_BEHIND := 8.0                     # m behind it
const LANE_CLEAR := 2.0                     # m either side of its path (vehicles in the other lane do not count)
const MAX_BUSES := 60                       # per line (the 4606 runs ~22 a direction at its 60 s headway since the west box)
const STOP_COST := 25.0                     # s a stop adds to a bus's trip on average (braking, doors, pulling out)
const TERMINUS_SEEN := 40.0                 # m: a player this close and a bus does not appear at a terminus...
const TERMINUS_WAIT := 0.5                  # ...for this share of the headway at most
const HIDDEN := 180.0                       # m from every player a bot car may come back in mid-route
const EDGE_SEEN := 60.0                     # m from every player it may come back in at the map edge
const CAR_LOOK := 0.5                       # s between looks for a way back in for the stowed cars
const CELL := 50.0                          # m, the snapshot's grid (near())
const CELL_KEY := 65536                     # grid key: x cell * CELL_KEY + y cell
const GLIDE_SLOTS := 32                     # ticks ahead a glide step may be due (> GLIDE_TICKS_FAR × glide_scale)
const LOAD_HIGH := 0.45                     # share of the tick the physics scripts may take...
const LOAD_AFTER := 4.0                     # ...for this many s before the traffic thins out a level
const LOAD_LOW := 0.2                       # under this share of the tick...
const LOAD_RELAX := 30.0                    # ...for this many s it fills up again a level
const LOAD_SETTLE := 10.0                   # s after the bots start before the load counts (spawns, first looks)
const LOAD_SMOOTH := 0.02                   # per tick, of the load's moving average
const LEVELS := [[1, 1.0], [2, 1.0], [2, 0.6], [2, 0.3]]    # [glide_scale, share of the bot cars out] per level

var game: Node3D                            # game.gd
var trains: TrainTraffic                    # the RER B (scripts/train_traffic.gd), on every peer
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
var snap_reach_max := 0.0                   # the longest half length among them
var _snap_feet: Array = []                  # their footprints (snap_footprint), null until a bot looks at one
var _cells := {}                            # grid key -> Array of snapshot indices (near())
# the players as of this physics tick (_players): game.player_spots(), the same and the camera, sections ridden
var _players_frame := -1
var _spots: Array = []
var _eyes: Array = []
var _ridden := {}                           # section -> players riding it (game.gd ridden_sections)
var _glide_slots: Array = []                # per tick to come (physics frame % GLIDE_SLOTS): the gliding bots due then
var tick_load := 0.0                        # share of the tick the physics scripts take, moving average (F3)
var load_level := 0                         # index into LEVELS: 0 the full traffic
var glide_scale := 1                        # BusBot glide intervals times this (LEVELS)
var adaptive := false                       # thins out under load (see the header)
var _tick_start := 0                        # usec, this tick's physics scripts started (0: not measured)
var _over_t := 0.0                          # s with the load over LOAD_HIGH
var _under_t := 0.0                         # s with it under LOAD_LOW
var _car_count := 0                         # bot cars made (out or stowed)

var _car_lengths := PackedFloat32Array()    # cumulative route lengths (picking routes by length)
var _car_models: Array = []
var _car_look := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -1000000     # first of the physics scripts, TickEnd last: the load
	trains = TrainTraffic.new()
	trains.name = "Trains"
	trains.game = game
	add_child(trains)
	var end := TickEnd.new()
	end.name = "TickEnd"
	end.traffic = self
	end.process_physics_priority = 1000000
	add_child(end)
	_glide_slots.resize(GLIDE_SLOTS)
	for k in GLIDE_SLOTS:
		_glide_slots[k] = []
	var env := OS.get_environment("PLATEAU_ADAPTIVE")
	adaptive = env == "1" if env != "" else get_tree().current_scene == game


## The last physics script of each tick: the load (see the header).
class TickEnd extends Node:
	var traffic: Node

	func _physics_process(_delta: float) -> void:
		traffic.tick_ended()


func _process(_delta: float) -> void:
	signal_clock = fposmod(clock(), CYCLE)
	RenderingServer.global_shader_parameter_set("signal_clock", signal_clock)


func _physics_process(delta: float) -> void:
	if bots.is_empty():
		_glide_due(delta)                   # a bot of its own (tools/test_races.gd) gliding over a stall
		return
	_tick_start = Time.get_ticks_usec()
	time += delta
	_snapshot()
	for d: Array in departures:
		if time >= d[2]:
			var late: float = time - d[2]
			if _depart(d[0], d[1], late) or late > float(d[0]["headway"]) * 0.9:
				d[2] += float(d[0]["headway"])
	_car_look -= delta
	if _car_look <= 0.0:
		_car_look = CAR_LOOK
		_balance_cars()
	_glide_due(delta)
	if adaptive:
		_adapt(delta)


## Moves on the gliding bots due this tick (or before it: ticks the tree was paused for), BusBot glide_step.
func _glide_due(delta: float) -> void:
	var now := Engine.get_physics_frames()
	var slot: Array = _glide_slots[now % GLIDE_SLOTS]
	if slot.is_empty():
		return
	_glide_slots[now % GLIDE_SLOTS] = []
	for b: Object in slot:
		if b._due >= 0 and b._due <= now and is_instance_valid(b.car):
			b.glide_step(delta)


## TickEnd: this tick's share of the tick taken by the physics scripts, into the load.
func tick_ended() -> void:
	if _tick_start == 0:
		return
	var used := float(Time.get_ticks_usec() - _tick_start) / 1e6 * Engine.physics_ticks_per_second
	_tick_start = 0
	if time > LOAD_SETTLE:
		tick_load = lerpf(tick_load, used, LOAD_SMOOTH)


## A level thinner after LOAD_AFTER s over LOAD_HIGH, a level fuller after LOAD_RELAX s under LOAD_LOW (see the header).
func _adapt(delta: float) -> void:
	_over_t = _over_t + delta if tick_load > LOAD_HIGH else 0.0
	_under_t = _under_t + delta if tick_load < LOAD_LOW else 0.0
	var level := load_level
	if _over_t > LOAD_AFTER and level < LEVELS.size() - 1:
		level += 1
	elif _under_t > LOAD_RELAX and level > 0:
		level -= 1
	if level != load_level:
		_over_t = 0.0
		_under_t = 0.0
		set_load_level(level)


## Traffic level `level` (index into LEVELS): how often the gliding bots move, how many bot cars are out
## (_balance_cars).
func set_load_level(level: int) -> void:
	load_level = clampi(level, 0, LEVELS.size() - 1)
	glide_scale = LEVELS[load_level][0]


## Sends stowed bot cars out again (up to 4 tries at a time) while fewer than the traffic level allows are out; past
## that, takes gliding ones nobody rides off the map (gliding: no player is near).
func _balance_cars() -> void:
	var out := 0
	for b: Object in bots:
		if not b.idle and is_same(b.line, car_line):
			out += 1
	var target := roundi(_car_count * float(LEVELS[load_level][1]))
	var n := 0
	for b: Object in bots:
		if n >= 4 or out == target:
			break
		if not is_same(b.line, car_line):
			continue
		if out < target and b.idle and send_cars:
			n += 1
			_send_car(b, false)
			if not b.idle:
				out += 1
		elif out > target and not b.idle and b.gliding and riders(b.car) == 0:
			n += 1
			b._stow()
			out -= 1


## A gliding bot's next glide step, on physics frame `tick` (BusBot._schedule).
func schedule_glide(bot: Object, tick: int) -> void:
	_glide_slots[tick % GLIDE_SLOTS].append(bot)


func _snapshot() -> void:
	snap_cars.clear()
	snap_pos.clear()
	snap_vel.clear()
	snap_fwd.clear()
	snap_reach.clear()
	snap_reach_max = 0.0
	_cells.clear()
	for c: Node3D in game.cars:
		if c.stowed:
			continue
		var xf: Transform3D = c.global_transform
		var p := BusBot.flat(xf * c.extents_center)
		var key := floori(p.x / CELL) * CELL_KEY + floori(p.y / CELL)
		var cell: Array = _cells.get(key, [])
		if cell.is_empty():
			_cells[key] = cell
		cell.append(snap_cars.size())
		snap_cars.append(c)
		snap_pos.append(p)
		snap_vel.append(BusBot.velocity_of(c))
		snap_fwd.append(BusBot.flat(xf.basis.z).normalized())
		snap_reach.append(c.half_extents.z)
		snap_reach_max = maxf(snap_reach_max, c.half_extents.z)
	_snap_feet.clear()
	_snap_feet.resize(snap_cars.size())


## Indices into the snapshot of the vehicles whose footprint centre may be within `r` m of `p` (pipeline x/y): those
## in the grid cells the square around it touches.
func near(p: Vector2, r: float) -> Array:
	var out := []
	for x in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
		for y in range(floori((p.y - r) / CELL), floori((p.y + r) / CELL) + 1):
			var cell: Variant = _cells.get(x * CELL_KEY + y)
			if cell != null:
				out.append_array(cell)
	return out


## The players as of this physics tick, for every bot (_spots, _eyes, _ridden).
func _players() -> void:
	if _players_frame == Engine.get_physics_frames():
		return
	_players_frame = Engine.get_physics_frames()
	_spots = game.player_spots()
	_eyes = _spots.duplicate()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and game.mode != "server" else null
	if cam:
		_eyes.append(cam.global_position)
	_ridden = game.ridden_sections()


## True when a player (game.gd player_spots) is within `d` m of `p` (on the map, heights aside).
func player_within(p: Vector3, d: float) -> bool:
	_players()
	for q: Vector3 in _spots:
		if Vector2(q.x - p.x, q.z - p.z).length() < d:
			return true
	return false


## Square of the distance on the map from `p` to the nearest player or the camera (INF with neither).
func eye_distance_squared(p: Vector3) -> float:
	_players()
	var best := INF
	for q: Vector3 in _eyes:
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length_squared())
	return best


## The players riding vehicle `c` (game.gd riders), as of this physics tick.
func riders(c: Node3D) -> int:
	_players()
	var n: int = _ridden.get(c, 0)
	if c.trailer:
		n += _ridden.get(c.trailer, 0)
	return n


## F3 (game.gd): the physics scripts' share of the tick, and the traffic level when thinned out; "" without bots.
func stats_text() -> String:
	if bots.is_empty():
		return ""
	return "scripts %d %% of the tick%s" % [roundi(tick_load * 100.0),
			" · traffic thinned (level %d)" % load_level if load_level > 0 else ""]


## Footprint of snapshot vehicle k (BusBot.footprint), made once per tick however many bots look at it.
func snap_footprint(k: int) -> PackedVector2Array:
	if _snap_feet[k] == null:
		_snap_feet[k] = BusBot.footprint(snap_cars[k])
	return _snap_feet[k]


## Seconds on the game's shared clock (the lights' cycle runs on it).
func clock() -> float:
	return game.net.clock()


## A car signal head of phase `phase` at shared time `t`: 0 green, 1 amber, 2 red (toy_prop.gdshader lit()).
static func light(t: float, phase: float) -> int:
	var c := fposmod(t / CYCLE + phase, 1.0)
	return 0 if c < GREEN else (1 if c < AMBER else 2)


## Starts the bot buses and cars (solo, host, dedicated server); with `pacer` (scripts/pacer.gd) a few per frame,
## under game.gd's loading overlay.
func start_bots(pacer: RefCounted = null) -> void:
	_rng.randomize()
	var data: Variant = _read(ROUTES)
	if data != null:
		lines = data["lines"]
		routes = data["routes"]
		for line: Dictionary in lines:
			await _start_line(line, true, pacer)
	var cars: Variant = _read(CAR_ROUTES)
	if cars != null:
		await _start_cars(cars, pacer)


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
	_snap_feet.clear()
	_cells.clear()
	for k in GLIDE_SLOTS:
		_glide_slots[k] = []
	_car_lengths.clear()
	_car_models = []
	_car_look = 0.0
	_car_count = 0
	tick_load = 0.0
	_tick_start = 0
	_over_t = 0.0
	_under_t = 0.0
	set_load_level(0)
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
func _start_line(line: Dictionary, fill := true, pacer: RefCounted = null) -> void:
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
			if pacer and pacer.due():
				await pacer.wait()


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

func _start_cars(data: Dictionary, pacer: RefCounted = null) -> void:
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
	_car_count = n
	for k in n:
		var bot := _new_bot(car_line, _car_models[_rng.randi() % _car_models.size()])
		bot._stow()
		_send_car(bot, true)
		if pacer and pacer.due():
			await pacer.wait()


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
	return player_within(p, d)
