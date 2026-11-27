extends RefCounted
## One car of the police's fleet (police.gd units, on the host): its job, the case it is on, its way, its driver.
## - Its job (set_job): STOWED (in the pool, off the map: police.gd puts it out where nobody sees, appear, and takes it
##   back, vanish), PATROL (police.gd: from one place to the next round the players, siren off), CALL (to a place
##   reported), SEARCH (tactics/search.gd: from block to block), CHASE (tactics/pursuit.gd: to where they were seen, then
##   straight at them), ROADBLOCK (tactics/roadblock.gd: across the road), OUT (its officer out: foot/arrest.gd). A new
##   job drops the last one's orders; ROADBLOCK and OUT keep the car braked where it stands.
## - Its way: asked (go, comb), plotted on a worker thread (roads/router.gd), then driven (driving/police_driver.gd). An
##   ask made while one is being plotted waits for it, and that one's way is dropped. No headway along its way for
##   STUCK s: plotted afresh from where it is, along the lanes only (what stood in its way off them may stand there
##   still). To an exact spot, with the physics (near a player), its way's length looked at every RECHECK s: what is
##   left of it a long way round (router.gd CUT_ACROSS, DETOUR: plotted far off, gliding, along the lanes), plotted
##   afresh (straight across, now). There (tick's answer, `there`): at its way's end, or blocked BLOCKED s near it. A
##   way given at once (drive_now: a roadblock's car, where it stands) drops any being plotted.
## - Its driver's other order: a quarry to close in on (close_in: tactics/pursuit.gd), instead of its way.
## Positions are pipeline x/y (x east, y north).

const Driver = preload("res://scripts/police/driving/police_driver.gd")
const Router = preload("res://scripts/police/roads/router.gd")

enum { PATROL, CALL, SEARCH, CHASE, ROADBLOCK, OUT, STOWED }

const STUCK := 40.0                         # s without headway along its way before it is plotted afresh
const HEADWAY := 5.0                        # m along its way that count as headway
const BLOCKED := 4.0                        # s blocked (a vehicle in the way)...
const NEAR := 30.0                          # ...this near its way's end: there (not on patrol)
const RECHECK := 3.0                        # s between two looks at a way to an exact spot (on the physics)

var index := 0                              # in police.gd units
var driver: Driver
var car: Node3D                             # car.gd
var job := STOWED
var case := 0                              # peer whose case it is on (0 none)
var dest := Vector2.ZERO                    # where it goes...
var spot := Vector2(NAN, NAN)               # ...and on off the lanes to exactly there (NAN: it stops on the lanes)
var block: Variant = null                   # the search block it goes into (comb: once plotted), null none
var appeared_at := -INF                     # police.gd time it was last put out of the pool

var _graph: RefCounted                      # roads/road_graph.gd
var _ask := {}                              # the way to plot next ({} none)
var _last_ask := {}                         # the last one (plotted afresh when stuck)
var _task := -1                             # its worker task (-1 none)...
var _task_serial := 0                       # ...for the ask of this number
var _serial := 0                            # asks and ways given so far (a way plotted for an older ask is dropped)
var _plotted := {}                          # the worker's answer (router.gd plan)
var _there := false
var _best := -INF                           # m along its way it got furthest...
var _stuck_t := 0.0                         # ...this many s ago
var _recheck_t := 0.0


func _init(i: int, d: Driver, graph: RefCounted) -> void:
	index = i
	driver = d
	car = d.car
	_graph = graph
	_there = d.arrived


## Its job now (on player `peer`'s case, 0 none): the last one's orders dropped (its quarry, the brakes).
func set_job(j: int, peer := 0) -> void:
	job = j
	case = peer
	driver.set_quarry({})
	driver.braked = j in [ROADBLOCK, OUT]
	driver.keep_going = j == CHASE          # (after them: no stop where they were, its way plotted afresh as they go)


## Sends it to `to` (map xy), siren on when `urgent`; on off the lanes to exactly `exact` when it is given.
func go(to: Vector2, urgent: bool, exact := Vector2(NAN, NAN)) -> void:
	dest = to
	spot = exact
	_ask_way({"dest": to, "spot": exact, "comb": null}, urgent)


## Searching: into whichever of `blocks` (road_graph.gd blocks) costs least, the drive into it counted besides `extra`
## (ms, one each); `block` once plotted. Siren on.
func comb(blocks: Array, extra: PackedInt32Array) -> void:
	dest = _graph.point(_graph.blocks[blocks[0]])
	spot = Vector2(NAN, NAN)
	_ask_way({"dest": dest, "spot": spot, "comb": [blocks, extra]}, true)


func _ask_way(ask: Dictionary, urgent: bool) -> void:
	block = null
	driver.set_urgent(urgent)
	_serial += 1
	_ask = ask
	_last_ask = ask
	_there = false


## Puts it on route `r` (road_graph.gd make_route) at once, at `to` (map xy), siren on when `urgent`: no plotting.
func drive_now(r: Dictionary, to: Vector2, urgent: bool) -> void:
	dest = to
	spot = Vector2(NAN, NAN)
	block = null
	driver.set_urgent(urgent)
	_serial += 1
	_ask = {}
	_last_ask = {}
	_there = false
	_take({"route": r, "block": null})


## Out of the pool onto route `r` (road_graph.gd make_route), at its start or at `xf` (Transform3D) when given, siren on
## when `urgent`; any way being plotted dropped. On patrol till the caller gives it another job.
func appear(r: Dictionary, xf: Variant = null, urgent := false) -> void:
	if job == STOWED:
		set_job(PATROL)
	_drop_ways()
	var last: Array = r["pts"][-1]
	dest = Vector2(last[0], last[1])
	spot = Vector2(NAN, NAN)
	driver.appear(r, xf)
	driver.set_urgent(urgent)
	_there = false
	_best = -INF
	_stuck_t = 0.0


## Back into the pool: off the map, no job, no way.
func vanish() -> void:
	set_job(STOWED)
	_drop_ways()
	driver.vanish()


## Whether it is on the map (not in the pool).
func on_map() -> bool:
	return job != STOWED


func _drop_ways() -> void:
	block = null
	_serial += 1
	_ask = {}
	_last_ask = {}


## Drives at `order` (police_driver.gd quarry) instead of its way; {} back to its way.
func close_in(order: Dictionary) -> void:
	if not (order.is_empty() and driver.quarry.is_empty()):
		driver.set_quarry(order)


func where() -> Vector2:
	return driver.where()


## Whether its way is being plotted (asked, or on a worker thread).
func plotting() -> bool:
	return not _ask.is_empty() or _task >= 0


## Whether it is where it was sent (nothing being plotted).
func there() -> bool:
	return _there and not plotting()


## Each physics tick (police.gd): its way plotted, then taken; its headway. True on the tick it gets there.
func tick(delta: float) -> bool:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _task_serial == _serial:         # (else asked anew meanwhile, or given a way: this one is dropped)
			_take(_plotted)
	if job == STOWED:
		return false
	if not _ask.is_empty():
		var ask := _ask.duplicate()
		_ask = {}
		ask["here"] = driver.where()
		ask["facing"] = driver.facing()
		ask["gliding"] = driver.gliding
		_task_serial = _serial
		_task = WorkerThreadPool.add_task(_plot.bind(ask), false, "police way")
		return false
	if _there or driver.braked:
		return false
	if driver.arrived or (job != PATROL and driver.blocked_time() > BLOCKED and where().distance_to(dest) < NEAR):
		_there = true
		return true
	if not driver.quarry.is_empty():        # (closing in on a quarry, not along its way: no headway to look for)
		_stuck_t = 0.0
		return false
	_recheck_t -= delta
	if _recheck_t <= 0.0:
		_recheck_t = RECHECK
		if _long_way_round():
			_serial += 1
			_ask = _last_ask.duplicate()
			_ask.erase("lanes")
			return false
	if driver.s > _best + HEADWAY:
		_best = driver.s
		_stuck_t = 0.0
	else:
		_stuck_t += delta
		if _stuck_t > STUCK and not _last_ask.is_empty():
			_stuck_t = 0.0
			_serial += 1
			_ask = _last_ask.duplicate()
			_ask["lanes"] = true
	return false


## Whether its way to an exact spot, on the physics, goes a long way round now (router.gd would cut across).
func _long_way_round() -> bool:
	if is_nan(spot.x) or driver.gliding or _last_ask.is_empty():
		return false
	var d := where().distance_to(spot)
	return d < Router.CUT_ACROSS and driver._length - driver.s > Router.DETOUR * d + 50.0


## Worker thread: its way (read by tick once done).
func _plot(ask: Dictionary) -> void:
	_plotted = Router.plan(_graph, ask)


## Its way plotted (`plotted`: router.gd plan) taken: driven; none, it is as near as it gets.
func _take(plotted: Dictionary) -> void:
	var r: Dictionary = plotted.get("route", {})
	if plotted.get("block") != null:
		block = plotted["block"]
		dest = _graph.point(_graph.blocks[block])
	_best = -INF
	_stuck_t = 0.0
	if r.is_empty() or (r["pts"] as Array).size() < 3:
		driver.arrived = true
	else:
		driver.follow(r)


## Leaving: its worker task let finish (it reads the road network).
func finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
