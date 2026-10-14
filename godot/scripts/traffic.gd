extends Node
## Traffic (game.gd makes it as Main/Traffic): the traffic lights' clock and the bot buses.
## - Lights: every car and pedestrian signal head runs the same CYCLE s cycle (shaders/toy_prop.gdshader) offset by its
##   phase (pipeline/plateau/props.py). The cycle runs on the game's shared clock (net.gd clock(): the host's in a LAN
##   game), handed to the shader as the global `signal_clock` each frame: the lights show the same colour on every
##   screen, and the bot buses stop at the reds the players see (light()).
## - Bot buses (scripts/bus_bot.gd): the lines of world/bus_routes.json (pipeline/plateau/transit.py, its lines and bus
##   counts in pipeline/buses.toml), spread along each line's round trip. Only the peer that hosts (or plays solo, or a
##   dedicated server) spawns and drives them; the other peers get them as remote vehicles (net.gd), which they can
##   ride in but not drive.

const BusBot = preload("res://scripts/bus_bot.gd")
const ROUTES := "res://world/bus_routes.json"
const CYCLE := 30.0                         # s, toy_prop.gdshader `cycle`
const GREEN := 0.45                         # share of the cycle: green until then, amber until AMBER, then red
const AMBER := 0.55
const SPAWN_CLEAR := 20.0                   # m from any vehicle a bus is spawned or comes back in

var game: Node3D                            # game.gd
var bots: Array = []                        # BusBot
var lines: Array = []                       # bus_routes.json "lines"
var routes := {}                            # route id -> route (bus_routes.json)
var signal_clock := 0.0                     # s into the cycle, as last handed to the shader


func _process(_delta: float) -> void:
	signal_clock = fposmod(clock(), CYCLE)
	RenderingServer.global_shader_parameter_set("signal_clock", signal_clock)


## Seconds on the game's shared clock (the lights' cycle runs on it).
func clock() -> float:
	return game.net.clock()


## A car signal head of phase `phase` at shared time `t`: 0 green, 1 amber, 2 red (toy_prop.gdshader lit()).
static func light(t: float, phase: float) -> int:
	var c := fposmod(t / CYCLE + phase, 1.0)
	return 0 if c < GREEN else (1 if c < AMBER else 2)


## Spawns the bot buses (solo, host, dedicated server), each line's spread evenly over its round trip.
func start_bots() -> void:
	if not FileAccess.file_exists(ROUTES):
		push_warning("no %s: run `python -m plateau buses`" % ROUTES)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES))
	if not data is Dictionary:
		push_error("cannot read %s" % ROUTES)
		return
	lines = data["lines"]
	routes = data["routes"]
	for line: Dictionary in lines:
		var ids: Array = line["routes"]
		var total := 0.0
		for id: String in ids:
			total += float(routes[id]["length"])
		var n := int(line["buses"])
		for k in n:
			# where along the round trip: the route, and the distance into it
			var u := total * (k + 0.25) / n
			var r := 0
			while r < ids.size() - 1 and u > float(routes[ids[r]]["length"]):
				u -= float(routes[ids[r]]["length"])
				r += 1
			_spawn(line, r, u)


func _spawn(line: Dictionary, route_index: int, s: float) -> void:
	var car: Node3D = game.new_vehicle(line["model"])
	var bot := BusBot.new()
	bot.setup(self, car, line, route_index)
	# a free stretch of the route at or after `s`
	var route: Dictionary = routes[line["routes"][route_index]]
	var s0 := clampf(s, bot.tail + 1.0, float(route["length"]) - bot.nose - 1.0)
	var xf := bot.pose_at(s0)
	for k in 12:
		if is_clear(xf.origin):
			break
		s0 = minf(s0 + 25.0, float(route["length"]) - bot.nose - 1.0)
		xf = bot.pose_at(s0)
	bot.s = s0
	game.add_bot_bus(car, xf, bot)
	bots.append(bot)


## True when no vehicle (bots coming back in excepted while stowed) stands within SPAWN_CLEAR m of `p` (global).
func is_clear(p: Vector3, except: Node3D = null) -> bool:
	for c: Node3D in game.cars:
		if c == except or c.stowed:
			continue
		var q: Vector3 = c.to_global(c.extents_center)
		if Vector2(q.x - p.x, q.z - p.z).length() < SPAWN_CLEAR + c.half_extents.z:
			return false
	return true
