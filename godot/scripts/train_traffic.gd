extends Node
## The RER B service (traffic.gd makes it as Main/Traffic/Trains on every peer).
## - Departures (on the peer running the bots: solo, the host, a dedicated server): per direction (world/rail.json
##   services) a train sets off every `headway` s (rail.json: HEADWAY, a compressed game headway; PLATEAU_TRAIN_HEADWAY=s
##   overrides; the real B4 service at Lozère is every 10-15 min), offset by the service's phase so that the two
##   directions meet in the station now and then. Eastbound trains come in at line speed from beyond the map's
##   south-west end (before Le Guichet), westbound ones from the north-east; both are out of sight when they appear
##   and vanish (stowed,
##   kept for the next departure). At the start the line is filled as if it had been running: each train that would be
##   on its way is run from its start for its age (FILL_STEP s steps, the block signals respected).
## - Bots (scripts/train_bot.gd) drive them; this node gives each its look ahead: the other trains of its direction and
##   what is on the track (the players on foot, every vehicle out, projected on its route: distance along, offset from
##   the track centre, height above the rails).
## - Every peer: the lineside signals show the blocks' occupancy (S or the carré's two reds for an occupied block, A for
##   the one after, else VL: scripts/builder/rail_builder.gd's lamps); the departure screens at Lozère list the next two
##   trains of their platform; a train running into something this peer simulates knocks it aside (its own player:
##   pushed off the track, not launched; a vehicle: a capped push and damage, car.gd damage(), the two kept from
##   colliding while it clears); a player riding a train off the playable box is put down next to the line at that end
##   of the map (rail.json landing), as the train goes on out of sight.

const Train = preload("res://scripts/train.gd")
const TrainBot = preload("res://scripts/train_bot.gd")
const RailMap = preload("res://scripts/rail_map.gd")
const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const RAIL := "res://world/rail.json"
const FILL_STEP := 0.25                     # s per step when filling the line at the start
const MAX_TRIP := 1500.0                    # s: a trip longer than this is given up (stowed)
const KNOCK_SPEED := 6.0                    # m/s: the most a train's knock sends a vehicle off at
const KNOCK_DAMAGE := 3.0                   # health per m/s of the train's speed when it knocks a vehicle
const KNOCK_CLEAR := 2.5                    # s a knocked vehicle and the train do not collide (it gets clear)
const PUSH_ASIDE := 2.8                     # m from the track centre a player on the track is pushed to
const SIGNAL_EVERY := 0.25                  # s between signal updates
const SCREEN_EVERY := 1.0                   # s between departure screen updates
const NEAR := 900.0                         # m: things farther from a train's front are not looked at
const DOORWAY_PLAYERS := 6.0                # m: players this close to a train may hold its doors

var game: Node3D                            # game.gd
var services: Array = []                    # rail.json services
var spec: Dictionary                        # rail.json train
var trains: Array = []                      # Train, stowed ones included
var bots := {}                              # Train -> TrainBot (on the peer running them)
var headway := 120.0                        # s per direction
var running := false                        # this peer runs the trains (bots)
var time := 0.0                             # s since start()
var departures := PackedFloat64Array()      # per service: time of its next departure
var departed := PackedInt32Array()          # per service: trains sent (tests)
var knocks := 0                             # things knocked (tests)
var teleports := 0                          # riders put down at the map edge (tests)

var _rm
var _route_s: Array = []                    # per service: centreline s of each route point
var _route_inc: Array = []                  # per service: whether that s grows along the route
var _track_u := PackedFloat32Array()        # per service: its track centre's offset from the centreline
var _cum: Array = []                        # per service: s from its route's start to each metre, planned (screens)
var _landing := {}
var _play := Rect2()
var _play_area: Array = []                  # rail.json playable_area: rings of the walkable polygon (else _play)
var _signals := {}                          # signal id -> Node3D (Rail/Signals)
var _screens: Array = []                    # [service index, Array[Label3D], stop s, station name]
var _signal_t := 0.0
var _screen_t := 0.0
var _next_id := 0
var _cleared := {}                          # car -> s left of its collision exceptions with the trains


func _ready() -> void:
	var rail = JSON.parse_string(FileAccess.get_file_as_string(RAIL)) if FileAccess.file_exists(RAIL) else null
	if not rail is Dictionary:
		return
	_rm = RailMap.get_map(RAIL)
	services = rail["services"]
	spec = rail["train"]
	_landing = rail.get("landing", {})
	var pl: Array = rail["playable"]
	_play = Rect2(pl[0], pl[1], float(pl[2]) - float(pl[0]), float(pl[3]) - float(pl[1]))
	var area = rail.get("playable_area")
	if area is Array:
		for ring: Array in area:
			var poly := PackedVector2Array()
			for q: Array in ring:
				poly.append(Vector2(q[0], q[1]))
			_play_area.append(poly)
	headway = float(services[0].get("headway", headway)) if not services.is_empty() else headway
	var env := OS.get_environment("PLATEAU_TRAIN_HEADWAY")
	if env.is_valid_float() and float(env) > 30.0:
		headway = float(env)
	for k in services.size():
		var svc: Dictionary = services[k]
		var sc := PackedFloat32Array()
		for s in svc["s_centre"]:
			sc.append(s)
		_route_s.append(sc)
		_route_inc.append(sc.size() < 2 or sc[sc.size() - 1] > sc[0])
		var u := 0.0
		for tr: Dictionary in rail["tracks"]:
			if tr["ref"] == svc["track"]:
				u = tr["offset"]
		_track_u.append(u)
		# time from the route's start to each metre at the planned speeds (the departure screens: to a stop)
		var v: Array = svc["v"]
		var cum := PackedFloat32Array()
		cum.resize(v.size())
		var acc := 0.0
		for i in v.size():
			cum[i] = acc
			acc += 1.0 / maxf(float(v[i]), 3.0)
		_cum.append(cum)
	departures.resize(services.size())
	departed.resize(services.size())


## Runs the trains here (solo, the host, a dedicated server): fills the line and schedules the departures.
func start() -> void:
	if services.is_empty() or running:
		return
	running = true
	time = 0.0
	_find_world_nodes()
	for k in services.size():
		var phase: float = float(services[k].get("phase", 0.0)) * headway
		departures[k] = phase
		_fill(k, phase)


## The trains of service k that would be on their way at time 0: departures at phase - n * headway.
func _fill(k: int, phase: float) -> void:
	var placed: Array = []
	var ages: Array = []
	var n := 1
	while phase - n * headway > -MAX_TRIP and n < 30:
		ages.append(n * headway - phase)
		n += 1
	ages.reverse()                          # the oldest first: it is the one ahead
	for age: float in ages:
		var tr := _new_train(k)
		var bot: TrainBot = bots[tr]
		bot.start()
		var t := 0.0
		while t < age and not bot.is_done():
			bot.drive(FILL_STEP, placed, [], [])
			t += FILL_STEP
		if bot.is_done() or tr.front >= float(services[k]["end"]):
			_stow(tr)
			continue
		if tr.door_t > 0.0:
			for car: Train.TrainCar in tr.cars:
				car.pose_doors(tr.door_t, tr.doors_side * (-1 if car.turned else 1))
		tr.pose()
		placed.append(tr)


## A train for service k: a stowed one of the service if any, else a new one.
func _new_train(k: int) -> Node3D:
	for tr: Node3D in trains:
		if tr.stowed and tr.service == services[k] and bots.has(tr):
			tr.set_stowed(false)
			return tr
	var tr := Train.new()
	_next_id += 1
	tr.setup(services[k], "train:%d" % _next_id)
	add_child(tr)
	_adopt(tr)
	if running:
		var bot := TrainBot.new()
		bot.setup(tr, services[k], spec)
		bots[tr] = bot
		tr.pilot = bot
	return tr


## A train made here or for another peer's states: the player passes through its outer boxes to its walkable hulls.
func _adopt(tr: Node3D) -> void:
	trains.append(tr)
	if game and game.player:
		for car: Train.TrainCar in tr.cars:
			game.player.add_collision_exception_with(car.shell)


## The train with `net_id` (another peer runs it: net.gd), made on first sight.
func ensure(net_id: String, k: int) -> Node3D:
	for tr: Node3D in trains:
		if tr.net_id == net_id:
			return tr
	if k < 0 or k >= services.size():
		return null
	var tr := Train.new()
	tr.setup(services[k], net_id)
	tr.remote = true
	add_child(tr)
	_adopt(tr)
	if _signals.is_empty():
		_find_world_nodes()
	return tr


func service_index(tr: Node3D) -> int:
	return services.find(tr.service)


func _depart(k: int) -> void:
	var tr := _new_train(k)
	(bots[tr] as TrainBot).start()
	tr.pose()
	departed[k] += 1


func _stow(tr: Node3D) -> void:
	tr.set_stowed(true)


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	if services.is_empty():
		return
	if running:
		time += delta
		for k in services.size():
			if time >= departures[k]:
				departures[k] += headway
				_depart(k)
		var doorway := _doorway_players()
		var near_line = null                # only looked for when some train runs (not at a stop)
		for tr: Node3D in trains:
			if tr.stowed or not bots.has(tr):
				continue
			var bot: TrainBot = bots[tr]
			var k := service_index(tr)
			var obstacles: Array = []
			if bot.state == "run":
				if near_line == null:
					near_line = _near_line()
				obstacles = _obstacles(tr, k, near_line)
			bot.drive(delta, _same_service(tr), obstacles, doorway)
			if bot.is_done():
				_stow(tr)
	_knock_things(delta)
	_land_riders()
	_signal_t += delta
	if _signal_t >= SIGNAL_EVERY:
		_signal_t = 0.0
		_update_signals()
	_screen_t += delta
	if _screen_t >= SCREEN_EVERY:
		_screen_t = 0.0
		_update_screens()


func _same_service(tr: Node3D) -> Array:
	var out: Array = []
	for o: Node3D in trains:
		if o != tr and not o.stowed and o.service == tr.service:
			out.append(o)
	return out


## Route distance along service k and offset from its track centre of map point xy, or null when off its route.
func route_distance(k: int, xy: Vector2) -> Variant:
	return _route_distance_su(k, _rm.project(xy))


## Same from the point's (s, u) on the centreline (rail_map.gd project()).
func _route_distance_su(k: int, su: Vector2) -> Variant:
	if is_nan(su.x):
		return null
	var sc: PackedFloat32Array = _route_s[k]
	var inc: bool = _route_inc[k]
	# s_centre runs monotonic along the route: a bisection
	var lo := 0
	var hi := sc.size() - 1
	if (inc and (su.x < sc[0] or su.x > sc[hi])) or (not inc and (su.x > sc[0] or su.x < sc[hi])):
		return null
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if (sc[mid] <= su.x) == inc:
			lo = mid
		else:
			hi = mid
	var span := sc[hi] - sc[lo]
	var f := (su.x - sc[lo]) / span if absf(span) > 1e-6 else 0.0
	var d := (lo + clampf(f, 0.0, 1.0)) * float(services[k]["step"])
	return Vector2(d, su.y - _track_u[k])


## The players on foot and the vehicles near the line this tick: [global position, (s, u) on the centreline, half
## width]. Projected once per tick for every train; most vehicles are far from the line and cost one lookup.
func _near_line() -> Array:
	var out: Array = []
	if game == null:
		return out
	for p: Vector3 in _people():
		_add_near(out, p, 0.0)
	for car: Node3D in game.cars:
		if is_instance_valid(car) and not car.stowed:
			_add_near(out, car.global_position, 1.0)
	return out


func _add_near(out: Array, p: Vector3, half: float) -> void:
	var su: Vector2 = _rm.project(Vector2(p.x, -p.z))
	if not is_nan(su.x):
		out.append([p, su, half])


## What is near the track ahead of `tr`, from `near_line` (_near_line()): [route distance, offset from the track
## centre (vehicles: less their half width), height above the rails].
func _obstacles(tr: Node3D, k: int, near_line: Array) -> Array:
	var out: Array = []
	var head: Vector3 = tr.route_point(tr.front)
	for n: Array in near_line:
		var p: Vector3 = n[0]
		if p.distance_squared_to(head) > NEAR * NEAR:
			continue
		var rd: Variant = _route_distance_su(k, n[1])
		if rd == null:
			continue
		var lateral: float = maxf(absf(rd.y) - n[2], 0.0)
		var level: float = p.y - tr.route_point(rd.x).y
		out.append([rd.x, lateral, level - 0.6 if level > 0.6 else level])
	return out


## Global positions of the players on foot: this peer's and the others'.
func _people() -> Array:
	var out: Array = []
	if game.player and game.player.visible and not game.driving and not game.flying \
			and not is_instance_valid(game.player.carrier):
		out.append(game.player.global_position)
	if game.net and game.net.active:
		for r: Node3D in game.net.avatars():
			if r.visible:
				out.append(r.global_position)
	return out


func _doorway_players() -> Array:
	var out: Array = []
	if game == null:
		return out
	if game.player and game.player.visible and not game.driving:
		out.append(game.player.global_position)
	if game.net and game.net.active:
		for r: Node3D in game.net.avatars():
			if r.visible:
				out.append(r.global_position)
	return out


## A moving train running into this peer's player or a vehicle it simulates knocks it aside (see the header).
func _knock_things(delta: float) -> void:
	for car: Node3D in _cleared.keys():
		_cleared[car] -= delta
		if _cleared[car] <= 0.0 or not is_instance_valid(car):
			if is_instance_valid(car):
				_set_clear(car, false)
			_cleared.erase(car)
	if game == null:
		return
	for tr: Node3D in trains:
		if tr.stowed or tr.speed < 0.5:
			continue
		var k := service_index(tr)
		var head: Vector3 = tr.route_point(tr.front)
		# this peer's player on foot
		var p: Vector3 = game.player.global_position
		if game.player.visible and not game.driving and not is_instance_valid(game.player.carrier) \
				and p.distance_to(head) < tr.length + 20.0:
			var rd: Variant = route_distance(k, Vector2(p.x, -p.z))
			if rd != null and rd.x < tr.front + 1.0 and rd.x > tr.front - tr.length and absf(rd.y) < 1.7 \
					and absf(p.y - tr.route_point(rd.x).y) < 2.5:
				_push_aside(tr, k, rd)
		# vehicles simulated here
		for car: Node3D in game.cars:
			if car.stowed or car.remote or _cleared.has(car) or car.global_position.distance_to(head) > 12.0:
				continue
			var cp: Vector3 = car.global_position
			var rc: Variant = route_distance(k, Vector2(cp.x, -cp.z))
			if rc == null or rc.x > tr.front + 2.5 or rc.x < tr.front - 6.0 or absf(rc.y) > 2.6 \
					or absf(cp.y - tr.route_point(rc.x).y) > 3.0:
				continue
			var fwd: Vector3 = tr.cars[0].global_basis.z
			var side: Vector3 = tr.cars[0].global_basis.x * (signf(rc.y) if rc.y != 0.0 else 1.0)
			var dv := minf(tr.speed, KNOCK_SPEED)
			for b: RigidBody3D in car.bodies():
				b.linear_velocity += fwd * dv * 0.8 + side * dv * 0.6 + Vector3.UP * 0.5
			car.damage(tr.speed * KNOCK_DAMAGE)
			_set_clear(car, true)
			_cleared[car] = KNOCK_CLEAR
			knocks += 1


## This peer's player in the train's way: put beside the track on the side they were on, moving off it.
func _push_aside(tr: Node3D, k: int, rd: Vector2) -> void:
	var side := signf(rd.y) if rd.y != 0.0 else 1.0
	var xy: Vector2 = _rm.point(_route_centre_s(k, rd.x), _track_u[k] + side * PUSH_ASIDE)
	var g: float = game.player.global_position.y
	game.player.teleport(MeshUtils.to_godot(xy.x, xy.y, g + 0.1), game.player.body_yaw())
	game.player.velocity = tr.cars[0].global_basis.x * side * 3.0 + tr.cars[0].global_basis.z * minf(tr.speed, 3.0)
	knocks += 1


## The centreline s of route distance d of service k.
func _route_centre_s(k: int, d: float) -> float:
	var sc: PackedFloat32Array = _route_s[k]
	var f := clampf(d / float(services[k]["step"]), 0.0, sc.size() - 1.000001)
	var i := floori(f)
	return lerpf(sc[i], sc[i + 1], f - i)


func _set_clear(car: Node3D, on: bool) -> void:
	for tr: Node3D in trains:
		for tc: Train.TrainCar in tr.cars:
			for b: RigidBody3D in car.bodies():
				if on:
					b.add_collision_exception_with(tc.shell)
				else:
					b.remove_collision_exception_with(tc.shell)


## This peer's player riding a train past the playable box (or in one that vanished) is put down by the line at that
## end of the map.
func _land_riders() -> void:
	if game == null or game.player == null:
		return
	var c: Node3D = game.player.carrier if is_instance_valid(game.player.carrier) else null
	if c == null or not c is Train.TrainCar:
		return
	var p: Vector3 = game.player.global_position
	var xy := Vector2(p.x, -p.z)
	if _walkable(xy) and not c.train.stowed:
		return
	var spot := {}                          # the nearer end's landing spot
	for key: String in _landing:
		var cand: Dictionary = _landing[key]
		if spot.is_empty() or xy.distance_to(Vector2(cand["x"], cand["y"])) < xy.distance_to(Vector2(spot["x"], spot["y"])):
			spot = cand
	if spot.is_empty():
		return
	game.player.set_carrier(null)
	game.spawn_at(Vector2(spot["x"], spot["y"]), game.player.body_yaw())
	game.player.velocity = Vector3.ZERO
	teleports += 1
	game._show_toast("The RER B leaves the map here: you are put down by the line")


## Map point inside the walkable area (rail.json playable_area: the corridors' polygon, holes included; else the box).
func _walkable(xy: Vector2) -> bool:
	if _play_area.is_empty():
		return _play.has_point(xy)
	if not Geometry2D.is_point_in_polygon(xy, _play_area[0]):
		return false
	for k in range(1, _play_area.size()):
		if Geometry2D.is_point_in_polygon(xy, _play_area[k]):
			return false
	return true


## The car of a train carrying global point p, or null.
func carrier_at(p: Vector3, margin := 0.0) -> Node3D:
	for tr: Node3D in trains:
		var c: Node3D = tr.carrier_at(p, margin)
		if c:
			return c
	return null


## The train whose body is within `d` m of global point p, or null.
func train_near(p: Vector3, d: float) -> Node3D:
	for tr: Node3D in trains:
		if tr.stowed:
			continue
		for car: Train.TrainCar in tr.cars:
			if car.to_local(p).abs().x < 1.4 + d and absf(car.to_local(p).z) < 13.0 + d:
				return tr
	return null


# ---------------------------------------------------------------- signals and screens

func _find_world_nodes() -> void:
	var root: Node = game.world_root if game else null
	if root == null:
		return
	var sig := root.get_node_or_null("Rail/Signals")
	if sig:
		for n in sig.get_children():
			if n.has_meta("lamps"):
				_signals[String(n.get_meta("plateau", {}).get("id", ""))] = n
	var station := root.get_node_or_null("Rail/Station")
	if station:
		for n in station.get_children():
			if String(n.name).begins_with("Screen_"):
				var pf: String = n.get_meta("plateau", {}).get("platform", "")
				var k := -1
				var stop := 0.0
				var stop_name := ""
				for i in services.size():
					for st: Dictionary in services[i]["stops"]:
						if st.get("platform", "") == pf:
							k = i
							stop = float(st["s"]["8"])
							stop_name = st["name"]
				var labels: Array = []
				for face in n.get_children():
					var l := face.get_node_or_null("Text") as Label3D
					if l:
						labels.append(l)
				if k >= 0:
					_screens.append([k, labels, stop, stop_name])


## Each service's signals from the trains' positions: the block beyond an occupied signal shows S (a carré its two
## reds), the one before it A, the others VL.
func _update_signals() -> void:
	if _signals.is_empty():
		return
	for k in services.size():
		var svc: Dictionary = services[k]
		var sigs: Array = svc["signals"]
		var blocks: Array = svc["blocks"]
		var occupied := []
		for i in blocks.size():
			var s0: float = blocks[i]
			var s1: float = blocks[i + 1] if i + 1 < blocks.size() else INF
			var occ := false
			for tr: Node3D in trains:
				if not tr.stowed and tr.service == svc and tr.front - tr.length < s1 and tr.front > s0:
					occ = true
			occupied.append(occ)
		for sg: Dictionary in sigs:
			var node: Node3D = _signals.get(sg["id"])
			if node == null:
				continue
			var s: float = sg["s"]
			var i := -1
			for j in blocks.size():
				if absf(float(blocks[j]) - s) < 1.0:
					i = j
			var aspect := "VL"
			if i >= 0 and occupied[i]:
				aspect = "C" if sg["kind"] == "FR:CARRE" else "S"
			elif i >= 0 and i + 1 < occupied.size() and occupied[i + 1]:
				aspect = "A"
			elif i < 0:
				# a distant signal (FR:A) or one off the blocks: warning when the next block signal is red
				for j in blocks.size():
					if float(blocks[j]) > s:
						aspect = "A" if occupied[j] else "VL"
						break
			var lamps: Dictionary = node.get_meta("lamps")
			if not lamps.has(aspect):
				aspect = "S" if aspect == "C" and lamps.has("S") else ("A" if lamps.has("A") and aspect != "VL" else "VL")
			if node.get_meta("aspect", "") != aspect and lamps.has(aspect):
				node.set_meta("aspect", aspect)
				RailBuilder._set_aspect(lamps, node.get_meta("lit"), node.get_meta("off"), aspect)


## The departure screens: the next two trains of their platform's direction (minutes to Lozère, "à quai" while one
## stands there, "à l'approche" within a minute).
func _update_screens() -> void:
	for sc: Array in _screens:
		var k: int = sc[0]
		var svc: Dictionary = services[k]
		var cum: PackedFloat32Array = _cum[k]
		var stop: float = sc[2]
		var at_stop: float = cum[clampi(int(stop), 0, cum.size() - 1)]
		var etas: Array = []
		var at_platform := false
		for tr: Node3D in trains:
			if tr.stowed or tr.service != svc:
				continue
			if absf(tr.front - stop) < 2.0 and tr.speed < 0.1:
				at_platform = true
				continue
			if tr.front < stop:
				etas.append(at_stop - cum[clampi(int(tr.front), 0, cum.size() - 1)])
		if running:
			var t_next: float = departures[k] - time
			etas.append(t_next + at_stop - cum[clampi(int(svc["start"]), 0, cum.size() - 1)])
		etas.sort()
		var dest: String = Train.DESTINATIONS.get(svc.get("direction", ""), "")
		var lines: PackedStringArray = ["RER B · " + String(sc[3])]
		if at_platform:
			lines.append("%s   à quai" % dest)
		for eta: float in etas.slice(0, 2 - (1 if at_platform else 0)):
			lines.append("%s   %s" % [dest, "à l'approche" if eta < 60.0 else "%d min" % roundi(eta / 60.0)])
		var text := "\n".join(lines)
		for l: Label3D in sc[1]:
			l.text = text
