extends Node
## PTA Online's police (scripts/modes/online_mode.gd makes it as Main/Mode/Police on every peer; the host runs it: the
## official server, or the PTA Online test). This script holds the fleet and the cases and says who does what; the
## rest, by file:
##   case.gd                    a wanted player: level, where last seen, since when unseen
##   unit.gd                    a car of the fleet: its job, its way (plotted on a worker thread), its driver's orders
##   roads/road_graph.gd        the road network: nearest lanes, fastest ways, search blocks, where someone is going
##   roads/router.gd            the way a car takes where it is sent (the lanes, then off them)
##   driving/police_driver.gd   a car's driver: its way, a quarry to close in on, or braked; its levels of detail
##   driving/pursuit_pilot.gd   the driving off the lanes near a player
##   tactics/pursuit.gd         the chasers' roles (PIT, passing and cutting in, boxing in someone stopped)
##   tactics/roadblock.gd       the roadblocks
##   tactics/search.gd          the search, block by block, when they are not seen
##   air/heli_pilot.gd          the helicopter's pilot
##   air/canopy.gd              the trees' crowns, which the helicopter cannot see through
##   foot/arrest.gd, officer.gd the officers out of their cars, the arrests
##   hud/police_hud.gd          the stars
## - The fleet, as in GTA: UNITS patrol cars made once when the game starts (FLEET_PER_TICK a tick, once the road
##   network is built on a worker thread), kept in a pool off the map (stowed: hidden, out of the physics, nothing to
##   compute) and put out where they are wanted, never in anyone's sight (HIDDEN m from every player and camera; a lane
##   SPAWN m from there, heading that way if it may), at most SPAWNS_PER_TICK a tick: no car is ever made during the
##   game, putting one out costs a fraction of a millisecond.
##   - Patrols: AMBIENT round each player (within AMBIENT_RANGE m), from one place PATROL m round the nearest player to
##     the next; taken back to the pool once DESPAWN m from every player and camera, or one too many round a player and
##     nobody sees it. The pool keeps RESERVE cars for the cases.
##   - A case: DISPATCH cars (one star), DISPATCH + SEARCHERS (two): free patrols within STAFF_NEAR m first, then the
##     pool, else a patrol nobody sees. One RECYCLE m behind where they were last seen, or with a long way round to go
##     there (LONG_WAY), out of everyone's sight, is put out again elsewhere (GTA's way: the pursuers never left far
##     behind; RESPAWN_AFTER s apart for a car). One too many (a roadblock's cars after them): the farthest back on
##     patrol.
## - Wanted: each player has a level (0 none, 1 reported, 2 on the run; up to 5 later), shown as stars on their screen,
##   blinking while the police do not see them.
##   - A car stolen (scripts/carjack/carjack.gd car_stolen) is reported by its driver VICTIM_CALL s later, unless they
##     were stunned meanwhile, and by the bot drivers who saw it (WITNESS_RANGE m, in sight) a few seconds later; a
##     police car that saw it acts at once. Reported: level 1, its cars there (CALL, siren on).
##   - Every LOOK_EVERY s, are they seen? By a car: its vision cone, as in GTA (SIGHT_FRONT m over the half in front of
##     it, SIGHT_BACK m behind; in sight: no wall, no hedge between), whatever they are in; that car chases them (PACK
##     at most); by the helicopter (HELI_SEE m, not under the trees: air/canopy.gd; it guides the cars on their case
##     nearest them after them); by an officer
##     on foot. Seen fleeing (faster than FLEE_SPEED), or not there when the first car on the call gets there: level 2,
##     the helicopter.
##   - Seen: tactics/pursuit.gd closes in, tactics/roadblock.gd blocks the road ahead. Not seen: CHASE_GRACE s on, the
##     chasers search too; tactics/search.gd sends the searchers and the helicopter from block to block.
##   - Not seen LOSE[level] s: lost; level 0, their cars back to their patrols (and to the pool, as they get far).
## - The helicopter (one, Car.SPECS HELI_MODEL, flown by heli_pilot.gd): parked on its base, the commissariat's
##   heliport (lot sousPrefecture's places, through builder/lots.gd), when the game starts; someone on the run, it takes off; it keeps above them while it
##   sees them, else searches; nobody on the run any more, back to its base, the rotor winding down. Out of fuel
##   after FUEL s after someone: it gives up and flies home (it sees nobody any more); REFUEL s after it left, it
##   comes back (someone still on the run), its tank full.
## - The arrests (foot/arrest.gd, Police/Arrest): near someone wanted and slow, a car on their case stops and its
##   officer gets out after them (unit.gd OUT); back in, the car goes on (resume). Put in a car: arrested (no star).
## - Cheap: the looks 4 times a second; where a player is (suspect) worked out once a tick; one sight ray object for all.
## Positions are pipeline x/y (x east, y north; Godot = (x, -z)).

const RoadGraph = preload("res://scripts/police/roads/road_graph.gd")
const Case = preload("res://scripts/police/case.gd")
const Unit = preload("res://scripts/police/unit.gd")
const PoliceDriver = preload("res://scripts/police/driving/police_driver.gd")
const Pursuit = preload("res://scripts/police/tactics/pursuit.gd")
const Roadblock = preload("res://scripts/police/tactics/roadblock.gd")
const Search = preload("res://scripts/police/tactics/search.gd")
const HeliPilot = preload("res://scripts/police/air/heli_pilot.gd")
const Canopy = preload("res://scripts/police/air/canopy.gd")
const Arrest = preload("res://scripts/police/foot/arrest.gd")
const PoliceHud = preload("res://scripts/police/hud/police_hud.gd")
const Garages = preload("res://scripts/online/garages.gd")
const Car = preload("res://scripts/car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const Lots = preload("res://scripts/builder/lots.gd")

const UNITS := 20                           # cars in the fleet (the pool and those out)
const FLEET_PER_TICK := 1                   # cars made a tick when the game starts (a vehicle made: some 30 ms)
const MODEL := "police-hatchback"
const HELI_MODEL := "helicopter-police"
const HIDDEN := 220.0                       # m from every player and camera a car is put out or taken back
const SPAWN := Vector2(250.0, 480.0)        # m from where it is wanted a car is put out, at least and at most
const SPAWNS_PER_TICK := 1                  # cars put out a physics tick at most
const ROOM := Vector3(2.8, 1.8, 5.4)        # m: a police car's box and room round it, free where one is put out
const AMBIENT := 3                          # patrols round each player...
const AMBIENT_RANGE := 700.0                # ...within this many m...
const AMBIENT_EVERY := 1.0                  # ...looked at every this many s
const RESERVE := 7                          # cars the patrols leave in the pool for the cases
const DESPAWN := 900.0                      # m from every player and camera a patrol is taken back
const PATROL := Vector2(200.0, 700.0)       # m round the nearest player a patrol goes, at least and at most
const STAFF_NEAR := 900.0                   # m: free patrols this near a case join it
const RECYCLE := 700.0                      # m behind where they were last seen a car of their case is put out nearer...
const LONG_WAY := 2000.0                    # ...or its way there longer than this (m) and LONG_WAY_RATIO times the
const LONG_WAY_RATIO := 4.0                 # straight line (the one-way lanes: a long way round)...
const RESPAWN_AFTER := 25.0                 # ...this many s after it was last put out at the soonest
const VIEW := 900.0                         # m: a place within this of a player or a camera, in their line of sight, is seen
const VICTIM_CALL := 5.0                    # s after the theft the driver robbed calls the police
const WITNESS_RANGE := 35.0                 # m: a bot driver this near (and in sight) saw the theft...
const WITNESS_CALL := Vector2(3.0, 7.0)     # ...and calls after this many s
const DISPATCH := 3                         # cars on a case reported (one star)...
const SEARCHERS := 4                        # ...this many more on the run (two stars)
const PACK := 4                             # cars at most chasing one suspect
const SIGHT_FRONT := 300.0                  # m a police car sees over the half in front of it...
const SIGHT_BACK := 50.0                    # ...and behind it
const HELI_SEE := 200.0                     # m the helicopter sees
const FUEL := 120.0                         # s after someone before the helicopter is out of fuel, flies home...
const REFUEL := 60.0                        # ...and comes back this many s after it left
const FLEE_SPEED := 5.0                     # m/s: seen going faster than this, they are on the run
const LOOK_EVERY := 0.25                    # s between the police's looks at the cases
const CHASE_GRACE := 3.0                    # s unseen before the chasers search too
const LOSE := [0.0, 60.0, 120.0]            # s unseen before the police lose someone, per level

signal wanted_changed(peer: int, level: int)    # host

var mode: Node                              # online_mode.gd
var game: Node3D
var hosting := false
var graph: RoadGraph                        # host: the road network
var units: Array[Unit] = []                 # host: the fleet (the pool too: unit.gd STOWED)
var cases := {}                             # host: peer -> Case, those wanted
var pursuit: Pursuit                        # host: the tactics
var roadblock: Roadblock
var search: Search
var heli: Car                               # host: the helicopter (null: none)...
var heli_pilot: HeliPilot                   # ...its pilot...
var heli_case := 0                          # ...whom it hunts (peer, 0 nobody)
var heli_flown := 0.0                       # ...s after someone since it took off or refuelled (FUEL)
var heli_away := 0.0                        # ...out of fuel: the time it may come back (0: it is not)
var canopy: Canopy                          # host: the trees' crowns it cannot see through (null: no trees)
var arrest: Arrest                          # the officers on foot, the arrests (every peer)
var release := Transform3D()                # host: where an arrested player is let go (the commissariat's entrance)
var time := 0.0                             # host: s since the game started (the tactics' clock)
var tick_us := 0                            # host: µs its last physics tick took (profiling, tests)
var spawning := true                        # host: cars put out of the pool and taken back by themselves (tests: off)
var level := 0                              # ours (every player), from the host...
var seen := false                           # ...and whether the police see us
var hud: PoliceHud

var _task := -1                             # host: the road network's worker task
var _calls: Array = []                      # host: {"peer", "key", "pos", "at", "who" (person id, "" a bot driver)}
var _look_t := 0.0
var _ambient_t := 0.0
var _spawns_left := 0                       # cars it may still put out this tick
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()   # (one for every sight line)
var _room_query := PhysicsShapeQueryParameters3D.new()
var _suspect_frame := -1                    # the physics tick _suspects holds...
var _suspects := {}                         # ...peer -> suspect()
var _drivers := {}                          # ...peer -> the net id of the vehicle they drive (others' peers)


func _ready() -> void:
	_rng.randomize()
	set_physics_process(false)
	_ray.collision_mask = Layers.SOLID | Layers.VEGETATION
	var box := BoxShape3D.new()
	box.size = ROOM
	_room_query.shape = box
	_room_query.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.PROPS | Layers.VEGETATION | Layers.VEHICLES
	arrest = Arrest.new()
	arrest.name = "Arrest"
	arrest.police = self
	arrest.mode = mode
	add_child(arrest)


## The game started here (online_mode.gd begin): the host builds the road network, then makes the fleet; every player
## gets the stars.
func begin(host: bool) -> void:
	hosting = host
	game = mode.game
	if game.mode != "server":
		hud = PoliceHud.new()
		hud.name = "Wanted"
		hud.police = self
		game.hud.add_child(hud)
	arrest.begin(host)
	if not hosting:
		return
	graph = RoadGraph.new()
	pursuit = Pursuit.new(self)
	roadblock = Roadblock.new(self)
	search = Search.new(self)
	_task = WorkerThreadPool.add_task(graph.build, false, "police road network")
	_load_places()
	var trees: Node = game.world_root.get_node_or_null("TreeCollision")
	if trees and trees.get("data"):
		canopy = Canopy.new(trees.data)
	game.carjack.car_stolen.connect(_on_car_stolen)
	set_physics_process(true)


## Leaving: the worker tasks under way let finish (they read the road network).
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	for u: Unit in units:
		u.finish()


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	tick_us = Time.get_ticks_usec() - t0


func _tick(delta: float) -> void:
	time += delta
	_spawns_left = SPAWNS_PER_TICK
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not graph.ready:
			set_physics_process(false)
			return
		print("police: road network of %d nodes in %d ms" % [graph.node_route.size(), graph.build_ms])
	for k in mini(FLEET_PER_TICK, UNITS - units.size()):
		_make_unit()
	_take_calls()
	for peer: int in cases.keys():
		_staff(cases[peer])
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		roadblock.tick(LOOK_EVERY)
		for peer: int in cases.keys():
			if cases.has(peer):
				_look(cases[peer])
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = AMBIENT_EVERY
		_ambient()
	for u: Unit in units:
		if u.tick(delta):
			_arrived(u)
	_heli_fuel(delta)
	if heli_flying() and (heli_pilot.done or heli.broken):
		heli.set_pilot(null)                # (back on its base: the rotor winds down; broken: it falls where it is)
		heli_pilot.order = HeliPilot.PARKED
		heli_case = 0
		heli_flown = 0.0                    # (filled up on its base)


# ---------------------------------------------------------------- the fleet: the pool, putting out, taking back

## A car of the fleet made, straight into the pool (it is made on a lane somewhere, then stowed at once).
func _make_unit() -> void:
	var r := _lane_route(graph.random_point(_rng))
	var car: Node3D = game.new_vehicle(MODEL)
	car.contact_monitor = true              # (what it touches: a PIT's knock, a ram)
	car.max_contacts_reported = 4
	var d := PoliceDriver.new()
	d.route_key = "police:%d" % units.size()
	game.traffic.routes[d.route_key] = r
	d.setup(game.traffic, car, {"ref": "police", "routes": [d.route_key]}, 0)
	game.add_bot_bus(car, d.pose_at(d.tail + 1.0), d)
	game.traffic.bots.append(d)
	d.knocked.connect(knock)
	var u := Unit.new(units.size(), d, graph)
	units.append(u)
	u.vanish()


## A short way along the lane of lane point `at` (a car put out there drives it before its first way is plotted).
func _lane_route(at: Vector2i) -> Dictionary:
	var n: int = (graph.pts[at.x] as PackedVector2Array).size()
	var i1 := mini(at.y + 12, n - 1)
	return graph.make_route([[at.x, maxi(i1 - 12, 0), i1]])


## Car `u` put on the map at `xf` (Transform3D; on its lane's way there, siren on when `urgent`), whoever sees it (tests,
## a roadblock's place found already). Its job is the caller's to give.
func deploy(u: Unit, xf: Transform3D, urgent := false) -> void:
	var p := Vector2(xf.origin.x, -xf.origin.z)
	var h := Vector2(xf.basis.z.x, -xf.basis.z.z).normalized()
	var lane := graph.nearest(p, h, 30.0)
	var r := _lane_route(lane) if lane.x >= 0 else graph.make_route([], p + h * 20.0, p)
	u.appear(r, xf, urgent)


## Car `u` put out of the pool (or from where nobody sees it) SPAWN m round `near`, out of everyone's sight; false when
## it may not (none this tick, or no lane fit for it there).
func _appear(u: Unit, near: Vector2, urgent: bool) -> bool:
	if not spawning or _spawns_left <= 0:
		return false
	_spawns_left -= 1                       # (a try counts, found or not: a few looks a tick at most)
	var at := _spawn_spot(near)
	if at.x < 0:
		return false
	u.appear(_lane_route(at), null, urgent)
	u.appeared_at = time
	return true


## A lane point SPAWN m round `near` where a car may be put out: nobody sees there (HIDDEN), off the bridge decks,
## nothing stands there (ROOM), its lane heading towards `near` if any does (a few tries, the search blocks' lane points:
## a dictionary's look-up each). (-1, -1) none.
func _spawn_spot(near: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for k in 10:
		var p := near + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(SPAWN.x, SPAWN.y)
		var b := RoadGraph.block_of(p)
		if not graph.blocks.has(b):
			continue
		var at: Vector2i = graph.blocks[b]
		var q := graph.point(at)
		var score := graph.heading(at).dot((near - q).normalized())
		if score <= best_score or not hidden(q) or graph._on_deck(at.x, at.y) or _occupied(at):
			continue
		best = at
		best_score = score
		if score > 0.5:
			break
	return best


## Whether something stands at lane point `at` (a vehicle, a wall, a prop): no car put out there.
func _occupied(at: Vector2i) -> bool:
	var q := graph.point(at)
	var h := graph.heading(at)
	_room_query.transform = Transform3D(Basis(Vector3.UP, atan2(h.x, -h.y)), Garages._at(q.x, q.y) + Vector3.UP * 1.05)
	return not game.get_world_3d().direct_space_state.intersect_shape(_room_query, 1).is_empty()


## Whether nobody could see a car at map point `p` (put out or taken back there): no player nor camera within HIDDEN
## m, and none within VIEW m with a line of sight to it (as GTA: out of sight, not only far; a straight road is seen a
## long way).
func hidden(p: Vector2) -> bool:
	var at := Garages._at(p.x, p.y) + Vector3.UP * 1.5
	for e: Vector3 in game.traffic.eye_spots():
		var d2 := Vector2(e.x - p.x, e.z + p.y).length_squared()
		if d2 < HIDDEN * HIDDEN or (d2 < VIEW * VIEW and in_sight(e + Vector3.UP * 1.6, at, [])):
			return false
	return true


## A car to put out for a case: one in the pool; else the patrol nobody sees farthest from every player. Null none.
func free_unit() -> Unit:
	var far: Unit = null
	var far_d := HIDDEN * HIDDEN
	for u: Unit in units:
		if u.job == Unit.STOWED:
			return u
		if u.job == Unit.PATROL:
			var d: float = game.traffic.eye_distance_squared(u.car.global_position)
			if d > far_d:
				far = u
				far_d = d
	return far if far and hidden(far.where()) else null


## Every AMBIENT_EVERY s: the patrols round the players. Those far from everyone taken back; AMBIENT round each player
## (one put out of the pool when short, the pool's RESERVE kept; one too many and nobody sees it, taken back).
func _ambient() -> void:
	if not spawning:
		return
	var stowed := 0
	for u: Unit in units:
		if u.job == Unit.PATROL and game.traffic.eye_distance_squared(u.car.global_position) > DESPAWN * DESPAWN:
			u.vanish()
		stowed += 1 if u.job == Unit.STOWED else 0
	for p: Vector3 in game.traffic.player_spots():
		var me := Vector2(p.x, -p.z)
		var round_me: Array[Unit] = []
		for u: Unit in units:
			if u.job == Unit.PATROL and u.where().distance_squared_to(me) < AMBIENT_RANGE * AMBIENT_RANGE:
				round_me.append(u)
		if round_me.size() < AMBIENT and stowed > RESERVE:
			var u := free_unit()
			if u and u.job == Unit.STOWED and _appear(u, me, false):
				stowed -= 1
				patrol(u)
		elif round_me.size() > AMBIENT + 1:
			for u: Unit in round_me:
				if hidden(u.where()):
					u.vanish()
					stowed += 1
					break


## Car `u` patrols: to a place PATROL m round the nearest player (where they would see it), siren off. (One in the pool
## stays there.)
func patrol(u: Unit) -> void:
	if not u.on_map():
		return
	u.set_job(Unit.PATROL)
	var here := u.where()
	var around := here
	var best := INF
	for p: Vector3 in game.traffic.player_spots():
		var d := here.distance_squared_to(Vector2(p.x, -p.z))
		if d < best:
			best = d
			around = Vector2(p.x, -p.z)
	for k in 8:
		var b := RoadGraph.block_of(around + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(PATROL.x, PATROL.y))
		if graph.blocks.has(b) and graph.point(graph.blocks[b]).distance_to(here) > 120.0:
			u.go(graph.point(graph.blocks[b]), false)
			return
	u.go(graph.point(graph.random_point(_rng)), false)


## Car `u` got where it was sent: patrolling, on to the next place; on a call, the case goes on (nobody there: on the
## run) and it searches. (Searchers, chasers: their tactics see to it.)
func _arrived(u: Unit) -> void:
	match u.job:
		Unit.PATROL:
			patrol(u)
		Unit.CALL:
			var c: Case = cases.get(u.case)
			if c == null:
				patrol(u)
				return
			if c.level == 1 and not c.seen:
				set_level(c.peer, 2)
			u.set_job(Unit.SEARCH, c.peer)


## The cars on patrol within `within` m of `p`, `n` of them at most, nearest first.
func _nearest_free(p: Vector2, n: int, within := INF) -> Array[Unit]:
	var free: Array = []
	for u: Unit in units:
		if u.job == Unit.PATROL:
			var d := u.where().distance_squared_to(p)
			if d < within * within:
				free.append([d, u.index])
	free.sort()
	var out: Array[Unit] = []
	for e: Array in free.slice(0, n):
		out.append(units[e[1]])
	return out


## Each tick, case `c`'s cars: as many as its level wants (DISPATCH, + SEARCHERS on the run): one too many (the
## farthest, not straight at them) back on patrol; short, free patrols near first, then one out of the pool; else one
## far behind them and out of sight put out nearer.
func _staff(c: Case) -> void:
	var want := DISPATCH + (SEARCHERS if c.level >= 2 else 0)
	var mine: Array = []                    # [m² from them, unit index]
	for u: Unit in units:
		if u.case == c.peer and u.job in [Unit.CALL, Unit.SEARCH, Unit.CHASE, Unit.OUT]:
			mine.append([u.where().distance_squared_to(c.last), u.index])
	mine.sort()
	if mine.size() > want:                  # (one too many: the farthest on a call or searching; never one after them)
		for k in range(mine.size() - 1, -1, -1):
			var u: Unit = units[mine[k][1]]
			if u.job in [Unit.CALL, Unit.SEARCH]:
				patrol(u)
				mine.remove_at(k)
				if mine.size() <= want:
					break
	if mine.size() < want:
		var near := _nearest_free(c.last, want - mine.size(), STAFF_NEAR)
		for u: Unit in near:
			_join(u, c)
		if mine.size() + near.size() < want:
			var u := free_unit()
			if u and _appear(u, c.last, true):
				_join(u, c)
		return
	for k in range(mine.size() - 1, -1, -1):    # (the farthest first)
		var u: Unit = units[mine[k][1]]
		if not u.job in [Unit.CALL, Unit.SEARCH, Unit.CHASE] or u.driver.pursuing() \
				or time - u.appeared_at < RESPAWN_AFTER or not hidden(u.where()):
			continue
		var d := sqrt(float(mine[k][0]))
		var long_way: bool = u.job != Unit.SEARCH and not u.plotting() \
				and u.driver.left() > maxf(LONG_WAY, LONG_WAY_RATIO * d)
		if d > RECYCLE or long_way:
			if _appear(u, c.last, true):
				_join(u, c)
			break


## Car `u` on case `c`, sent: one star, to the place reported; on the run, after them if seen (PACK at most chasing),
## searching else (tactics/search.gd sends it; seen, to where they are).
func _join(u: Unit, c: Case) -> void:
	search.release(u)
	if c.level < 2:
		u.set_job(Unit.CALL, c.peer)
		u.go(c.scene, true, c.scene)
	elif c.seen and pack(c.peer) < PACK:
		u.set_job(Unit.CHASE, c.peer)
		u.go(c.last, true, c.last)
	else:
		u.set_job(Unit.SEARCH, c.peer)      # (tactics/search.gd sends it at its next look)
		u.driver.set_urgent(true)


## How many cars chase player `peer`.
func pack(peer: int) -> int:
	var n := 0
	for u: Unit in units:
		n += 1 if u.job == Unit.CHASE and u.case == peer else 0
	return n


## Car `u`'s officer gets out (foot/arrest.gd): braked, on player `peer`'s case.
func officer_out(u: Unit, peer: int) -> void:
	u.set_job(Unit.OUT, peer)


## Car `u`'s officer is back in (foot/arrest.gd): after its quarry if still wanted (chasing them if seen, searching
## else), patrolling if not.
func resume(u: Unit) -> void:
	var c: Case = cases.get(u.case)
	if c == null:
		patrol(u)
	else:
		_join(u, c)                         # (a job and a way: after them, or searching)


# ---------------------------------------------------------------- the wanted

## Host: player `peer` stole the car of key `key` (carjack.gd car_stolen): the witnesses call.
func _on_car_stolen(peer: int, key: String, driver: String) -> void:
	var car: Car = game.carjack.car_of(key)
	if car == null:
		return
	var pos := Vector2(car.global_position.x, -car.global_position.z)
	_calls.append({"peer": peer, "key": key, "pos": pos, "at": time + VICTIM_CALL, "who": driver})
	var eye := car.global_position + Vector3.UP * 1.2
	for b: Object in game.traffic.bots:
		if b is PoliceDriver or b.idle or not is_instance_valid(b.car) or b.car == car:
			continue
		var p: Vector3 = b.car.global_position + Vector3.UP * 1.4
		if p.distance_squared_to(eye) < WITNESS_RANGE * WITNESS_RANGE \
				and in_sight(p, eye, [b.car.get_rid(), car.get_rid()]):
			_calls.append({"peer": peer, "key": key, "pos": pos,
					"at": time + _rng.randf_range(WITNESS_CALL.x, WITNESS_CALL.y), "who": ""})
	for u: Unit in units:
		if u.on_map() and _sees(u.car, eye, [car.get_rid()]):
			report(peer, pos, key)
			return


## The calls due. A person stunned before they could call (the driver robbed, tased, netted) does not.
func _take_calls() -> void:
	if _calls.is_empty():
		return
	for c: Dictionary in _calls.duplicate():
		if c["who"] != "" and game.people.is_down(c["who"]):
			_calls.erase(c)
		elif time >= float(c["at"]):
			_calls.erase(c)
			report(c["peer"], c["pos"], c["key"])


## Host: player `peer` reported at `pos` (map xy), in the car of key `key` they stole: level 1, cars there.
func report(peer: int, pos: Vector2, key: String) -> void:
	if cases.has(peer) and (cases[peer] as Case).level >= 1:
		return                              # (already: the first call counts)
	var c := Case.new(peer, pos, key)
	cases[peer] = c
	set_level(peer, 1)
	_staff(c)


## Host: player `peer`'s level `n`; on the run (2): more cars on their case (_staff), the helicopter.
func set_level(peer: int, n: int) -> void:
	var c: Case = cases.get(peer)
	if c == null or c.level == n:
		return
	c.level = n
	if n == 2:
		_staff(c)
		_send_heli(peer)
	_tell(peer)
	wanted_changed.emit(peer, n)


## Host: player `peer` no longer wanted (lost, arrested): their cars back on patrol (an officer out walks back first),
## their roadblock lifted, the helicopter after someone else or home.
func close_case(peer: int) -> void:
	cases.erase(peer)
	roadblock.lift(peer)
	search.forget(peer)
	for u: Unit in units:
		if u.case == peer and u.job != Unit.OUT:
			patrol(u)
	if heli_case == peer:
		heli_case = 0
		for other: int in cases:
			if (cases[other] as Case).level >= 2:
				_send_heli(other)
		if heli_case == 0 and heli_flying():
			heli_pilot.home()
	mode.send_to(peer, self, "_c_wanted", [0, false])
	wanted_changed.emit(peer, 0)


## Host: player `peer` arrested (arrest.gd, once put in a police car).
func arrested(peer: int) -> void:
	if cases.has(peer):
		close_case(peer)


## Every LOOK_EVERY s, case `c`: do the police see them? The cars that do chase them, the helicopter guides others;
## then, seen, the pursuit and the roadblocks; not seen, the search (the chasers too, CHASE_GRACE s on); unseen too
## long, lost.
func _look(c: Case) -> void:
	var s := suspect(c.peer)
	var was := c.seen
	c.seen = false
	var guided := false
	if not s.is_empty():
		var veh: Car = s["car"]
		var target: Vector3 = (s["pos"] as Vector3) + Vector3.UP
		var exclude := [veh.get_rid()] if veh else []
		var chasing := pack(c.peer)
		for u: Unit in units:
			if not u.on_map() or not _sees(u.car, target, exclude):
				continue
			c.seen = true
			if u.job in [Unit.PATROL, Unit.CALL, Unit.SEARCH] and chasing < PACK:   # (a roadblock keeps its place)
				u.set_job(Unit.CHASE, c.peer)
				chasing += 1
		if arrest.sees(target, exclude):
			c.seen = true
		if heli_flying() and heli_away == 0.0 and heli_sees(target, exclude):
			c.seen = true
			guided = true
		if c.seen:
			var now := Vector2(target.x, -target.z)
			c.vel = (now - c.last) / LOOK_EVERY if was else Vector2.ZERO
			c.last = now
			c.since = 0.0
			if c.level == 1 and float(s["speed"]) > FLEE_SPEED:
				set_level(c.peer, 2)
			if guided:
				_guide(c)
	if not c.seen:
		c.since += LOOK_EVERY
		if c.since > LOSE[mini(c.level, LOSE.size() - 1)]:
			close_case(c.peer)
			return
		if c.since > CHASE_GRACE:
			for u: Unit in units:
				if u.job == Unit.CHASE and u.case == c.peer:
					u.set_job(Unit.SEARCH if c.level >= 2 else Unit.CALL, c.peer)
					u.go(c.last, true, c.last)
	if c.seen:
		search.seen(c)
		var q := Pursuit.quarry_of(c, s)
		pursuit.update(c, q)
		roadblock.update(c, q)
	else:
		pursuit.release(c)
		search.update(c, s, LOOK_EVERY)
	if heli_case == c.peer and heli_flying():
		if c.seen:
			heli_pilot.follow(c.last, c.vel)
		else:
			var spot: Array = search.heli_spot(c)
			heli_pilot.search(spot[0], spot[1])
	if c.seen != was:
		_tell(c.peer)


## Whether police car `car` sees `target` (global): its vision cone (SIGHT_FRONT m over the half in front of it,
## SIGHT_BACK behind), nothing between (but `exclude` and itself).
func _sees(car: Node3D, target: Vector3, exclude: Array) -> bool:
	var eye := car.global_position + Vector3.UP * 1.4
	var rel := Vector2(target.x - eye.x, target.z - eye.z)
	var f: Vector3 = car.global_basis.z
	var reach := SIGHT_FRONT if rel.dot(Vector2(f.x, f.z)) >= 0.0 else SIGHT_BACK
	return rel.length_squared() < reach * reach and in_sight(eye, target, exclude + [car.get_rid()])


## Whether the helicopter sees `target` (global): HELI_SEE m, nothing between (but `exclude` and itself), no tree's
## crown over them or between (under the trees, it loses you: air/canopy.gd).
func heli_sees(target: Vector3, exclude: Array) -> bool:
	var eye := heli.global_position + Vector3.UP * 0.2
	return eye.distance_squared_to(target) < HELI_SEE * HELI_SEE \
			and in_sight(eye, target, exclude + [heli.get_rid()]) \
			and not (canopy and canopy.hides(eye, target))


## The helicopter sees case `c`'s quarry: the cars on their case nearest them (on a call, searching) after them,
## chasing them, PACK at most.
func _guide(c: Case) -> void:
	var near: Array = []                    # [m², unit index]
	for u: Unit in units:
		if u.case == c.peer and u.job in [Unit.CALL, Unit.SEARCH]:
			near.append([u.where().distance_squared_to(c.last), u.index])
	near.sort()
	for e: Array in near.slice(0, maxi(PACK - pack(c.peer), 0)):
		units[e[1]].set_job(Unit.CHASE, c.peer)


## Where player `peer` is and what they are in: {"pos" (global), "car" (or null), "key" (its carjack key), "speed"};
## {} when they are not on the map. Worked out once a physics tick (the looks, the arrests, each officer ask).
func suspect(peer: int) -> Dictionary:
	var f := Engine.get_physics_frames()
	if f != _suspect_frame:
		_suspect_frame = f
		_suspects.clear()
		_drivers.clear()
		for id: String in game.net.driver_of:   # (who drives what, once a tick for every suspect)
			_drivers[int(game.net.driver_of[id])] = id
	if not _suspects.has(peer):
		_suspects[peer] = _suspect(peer)
	return _suspects[peer]


func _suspect(peer: int) -> Dictionary:
	var car: Car = null
	var pos := Vector3.ZERO
	var speed := 0.0
	if peer == game.net.me() and game.mode != "server":
		car = game.driving if game.driving else game.riding
		if car == null and not game.player.visible:
			return {}
		pos = car.global_position if car else game.player.global_position
		var v: Vector3 = car.linear_velocity if car else game.player.velocity
		speed = Vector2(v.x, v.z).length() if car == null else v.length()    # (on foot, a fall is no flight)
	else:
		if _drivers.has(peer):
			car = game.net.cars.get(_drivers[peer])
		var a: Node3D = game.net.avatar(peer)
		if car == null and a and a.riding_in() is Car:
			car = a.riding_in()
		if car == null and (a == null or not a.visible):
			return {}
		pos = car.global_position if car else a.global_position
		speed = car.linear_velocity.length() if car else 0.0
		if car and car.remote:
			speed = absf(car.speed())
	return {"pos": pos, "car": car, "key": game.carjack.key_of(car) if car else "", "speed": speed}


## Whether nothing solid (buildings, walls, the ground, the vegetation) stands between `from` and `to` (global), but
## `exclude` (RIDs).
func in_sight(from: Vector3, to: Vector3, exclude: Array) -> bool:
	_ray.from = from
	_ray.to = to
	_ray.exclude = exclude
	return game.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Host: vehicle `car` knocked on its rear by a PIT (police_driver.gd knocked): its rear tyres loose `seconds`
## (car.gd knock_loose), on the peer that simulates it (here, or its driver's).
func knock(car: Node3D, seconds: float) -> void:
	if not car.remote:
		car.knock_loose(seconds)
		return
	var peer: int = game.net.owner_of.get(car.net_id, 0)
	if peer != 0:
		mode.send_to(peer, self, "_c_knock", [car.net_id, seconds])


@rpc("authority", "call_remote", "reliable")
func _c_knock(net_id: String, seconds: float) -> void:
	var car: Car = game.net.cars.get(net_id)
	if car and not car.remote:
		car.knock_loose(seconds)


## Host: player `peer` came in: the officers out.
func player_registered(peer: int) -> void:
	if hosting:
		arrest.player_registered(peer)


## Tells player `peer` their level and whether the police see them now.
func _tell(peer: int) -> void:
	var c: Case = cases.get(peer)
	mode.send_to(peer, self, "_c_wanted", [c.level if c else 0, c.seen if c else false])


@rpc("authority", "call_remote", "reliable")
func _c_wanted(n: int, seen_now: bool) -> void:
	level = n
	seen = seen_now
	if hud:
		hud.queue_redraw()


# ---------------------------------------------------------------- the helicopter

## Host, when the game starts: its places (the lots': the commissariat's, lot sousPrefecture): the helicopter on its
## base, rotor still; where the arrested are let go.
func _load_places() -> void:
	var parsed := Lots.police_places()
	if not parsed.has("heli_base"):
		push_warning("police: no places (no lot gives them)")
		return
	release = _place(parsed.get("release", parsed["heli_base"]))
	if not Car.SPECS.has(HELI_MODEL):
		return
	var b: Dictionary = parsed["heli_base"]
	var at := _place(b)
	heli = game.park_vehicle(HELI_MODEL, at, true)
	heli_pilot = HeliPilot.new()
	heli_pilot.setup(heli as HeliPilot.Heli, Vector2(float(b["x"]), float(b["y"])), at.basis.get_euler().y)


## A police place (map x, y, yaw degrees clockwise from north) on the ground, or at its z (a roof), facing that way
## (+Z).
static func _place(d: Dictionary) -> Transform3D:
	var at := Garages._at(float(d["x"]), float(d["y"]))
	if d.has("z"):
		at.y = float(d["z"])
	return Transform3D(Basis(Vector3.UP, PI - deg_to_rad(float(d["yaw"]))), at)


## Whether the helicopter flies (its pilot at the controls).
func heli_flying() -> bool:
	return heli != null and heli.pilot != null


## The helicopter after player `peer` (on the run), unless it hunts someone else already, is broken or away for fuel.
func _send_heli(peer: int) -> void:
	if heli == null or heli.broken or heli_away > 0.0 or (heli_case != 0 and cases.has(heli_case)):
		return
	heli_case = peer
	if heli.pilot == null:
		heli.set_pilot(heli_pilot)
	heli_pilot.search((cases[peer] as Case).last)


## Its fuel: FUEL s after someone, it gives up and flies home (heli_away); REFUEL s after it left, back after someone
## still on the run, its tank full.
func _heli_fuel(delta: float) -> void:
	if heli_away > 0.0:
		if time < heli_away:
			return
		heli_away = 0.0
		heli_flown = 0.0
		for peer: int in cases:
			if (cases[peer] as Case).level >= 2:
				_send_heli(peer)
				break
		return
	if not heli_flying() or heli_case == 0:
		return
	heli_flown += delta
	if heli_flown >= FUEL:
		heli_case = 0
		heli_away = time + REFUEL
		heli_pilot.home()
