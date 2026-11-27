extends RefCounted
## Where the police look for someone wanted they lost sight of (police.gd runs it on the host every LOOK_EVERY s for
## each case not seen; its searchers: unit.gd's SEARCH cars on the case): they comb the blocks round where they think
## that someone is (roads/road_graph.gd blocks: BLOCK m squares with a lane through them), a block each, from the zone's
## middle out.
## - The zone: ZONE m round its middle at first, ZONE_GROW m more each second unseen, ZONE_MAX at most. Its middle
##   starts where they were last seen, carried on AHEAD s at their speed then, and drifts toward where they really are
##   (HINT_SPEED m/s, to a point HINT_OFF m off them: a hint, not a tracker; the "coup de pouce" Thomas asked for).
## - The blocks: each searcher goes into a block of the zone near where the middle will be once it gets there (its m
##   from it at TRAVEL m/s: it aims ahead, toward them), one nobody else goes to (CLAIMED) and nobody combed lately
##   (REVISIT s); and quick to drive into (the lanes are few and one-way: a block near may be a long way round). The
##   CHOICES cheapest by the rest go to unit.gd comb, whose way (roads/router.gd, on a worker thread) counts the drive
##   into each (FAR_WEIGHT: a second of it as TRAVEL * FAR_WEIGHT m) and takes the cheapest. A block is combed once a
##   police car is in it, or the helicopter over it (HELI_SWEEP m). A searcher is sent on once its block is combed (by
##   it or another), out of the zone, or not to be got to (there as near as it gets); and thought over every RETHINK s
##   on its way (the middle moved on meanwhile). Two sent at once may take the same block: one goes elsewhere.
## - The helicopter: from block to block the same way (it flies fast: HELI_TRAVEL m/s, far blocks counting little,
##   HELI_FAR_WEIGHT; its block thought over every RETHINK s on its way), HELI_DWELL s circling over each (HELI_ORBIT
##   m out).
## - Seen again (seen): the plan dropped, the searchers sent to where they are seen.
## Positions are pipeline x/y (x east, y north).

const Graph = preload("res://scripts/police/roads/road_graph.gd")
const Unit = preload("res://scripts/police/unit.gd")

const ZONE := 220.0                         # m round its middle the zone is at first...
const ZONE_GROW := 6.0                      # ...this many more each second unseen...
const ZONE_MAX := 1100.0                    # ...this many at most
const AHEAD := 4.0                          # s at their last speed the middle starts ahead of where they were seen...
const HINT_SPEED := 10.0                    # ...and drifts this many m/s toward them...
const HINT_OFF := 70.0                      # ...to a point this far off them
const TRAVEL := 15.0                        # m/s a searcher is reckoned to get on at (in a straight line)
const FAR_WEIGHT := 0.2                     # what a second's drive into a block counts against it (TRAVEL m each)
const CHOICES := 10                         # blocks a searcher chooses from (the cheapest before the drive)
const CLAIMED := 3000.0                     # m counted against a block another searcher goes to (when there is no
											# other)...
const REVISIT := 50.0                       # ...and against one combed under this many s ago...
const RECENT_WEIGHT := 25.0                 # ...this many m per s left
const KEEP := 2.0                           # s a searcher keeps its block at least (not sent on at each look)
const RETHINK := 10.0                       # s between two looks for a better block for a searcher under way
const MOVED := 60.0                         # m: seen, a searcher goes again once they are this far from where it goes
const HELI_TRAVEL := 35.0                   # m/s the helicopter is reckoned to get on at
const HELI_FAR_WEIGHT := 0.15               # what a block's m from the helicopter count against it (in a straight line)
const HELI_ORBIT := 70.0                    # m out the helicopter circles a block's middle...
const HELI_OVER := 120.0                    # ...over it from this near (where it starts circling: heli_pilot.gd)...
const HELI_DWELL := 6.0                     # ...this many s
const HELI_SWEEP := 110.0                   # m: the blocks whose middle it passes this near are combed
const NONE := Vector2i(-1048576, -1048576)  # no block

var police: Node                            # police.gd
## peer -> {"t" (s since the plan was made: the clock of the rest), "mid" (the zone's middle), "target" (where it drifts
## to), "off" (the hint's, off them), "done" (block -> t combed), "claims" (unit index -> [block (NONE till chosen), t
## it was sent there, t it was last sent or thought over]), "heli" (block), "heli_t" (s over it), "heli_at" (t sent)}
var plans := {}

var _rng := RandomNumberGenerator.new()


func _init(p: Node) -> void:
	police = p
	_rng.randomize()


## Every LOOK_EVERY s (`dt`), case `c` not seen (`s`: police.gd suspect, {} off the map): the zone moved on, the
## blocks combed noted, the searchers and the helicopter sent on.
func update(c: RefCounted, s: Dictionary, dt: float) -> void:
	var plan: Dictionary = plans.get(c.peer, {})
	if plan.is_empty():
		var mid: Vector2 = c.last + c.vel * AHEAD
		plan = {"t": 0.0, "mid": mid, "target": mid, "off": Vector2.from_angle(_rng.randf() * TAU) * HINT_OFF,
				"done": {}, "claims": {}, "heli": NONE, "heli_t": 0.0, "heli_at": 0.0}
		plans[c.peer] = plan
	var t: float = float(plan["t"]) + dt
	plan["t"] = t
	if not s.is_empty():
		plan["target"] = Vector2(s["pos"].x, -s["pos"].z) + (plan["off"] as Vector2)
	plan["mid"] = (plan["mid"] as Vector2).move_toward(plan["target"], HINT_SPEED * dt)
	var radius := minf(ZONE + ZONE_GROW * c.since, ZONE_MAX)
	var claims: Dictionary = plan["claims"]
	var blocks: Array = []                  # (the zone's: worked out once a searcher needs them)
	for u: Unit in _comb(c.peer, plan):
		var claim: Array = claims.get(u.index, [])
		_settle(u, claim, t)
		var renew := _sent_on(u, plan, radius) or (not claim.is_empty() and _taken(claims, u.index).has(claim[0]))
		if not renew and (t - float(claim[2]) < RETHINK or u.plotting()):
			continue
		if blocks.is_empty():
			blocks = _blocks(plan, radius)
		var choice := _choices(blocks, _aim(plan, u.where(), TRAVEL), _taken(claims, u.index))
		if (choice[0] as Array).is_empty():
			claims.erase(u.index)
			continue
		if renew:
			claims[u.index] = [NONE, t, t]
		else:
			claim[2] = t                    # (under way: perhaps into another block now)
		u.comb(choice[0], choice[1])
	if police.heli_case == c.peer and police.heli_flying():
		_heli(plan, radius, dt, blocks)


## Unit `u` sent elsewhere (police.gd: put out nearer, on another case): its block given up, on every plan.
func release(u: Unit) -> void:
	for plan: Dictionary in plans.values():
		(plan["claims"] as Dictionary).erase(u.index)


## Case `c` seen: its plan dropped; its searchers to where they are seen (sent again once MOVED m off).
func seen(c: RefCounted) -> void:
	plans.erase(c.peer)
	for u: Unit in police.units:
		if u.job == Unit.SEARCH and u.case == c.peer and u.dest.distance_to(c.last) > MOVED:
			u.go(c.last, true)


## Player `peer`'s case closed: their plan dropped.
func forget(peer: int) -> void:
	plans.erase(peer)


## Where the helicopter searches for case `c` now and how far out it circles: its block's middle (where they were last
## seen till there is one).
func heli_spot(c: RefCounted) -> Array:
	var plan: Dictionary = plans.get(c.peer, {})
	if plan.is_empty() or plan["heli"] == NONE:
		return [c.last, HELI_ORBIT]
	return [Graph.block_middle(plan["heli"]), HELI_ORBIT]


## Where a searcher at `here` going at `speed` aims (the blocks nearest it first): the zone's middle as it will be by
## the time it gets there, drifting on toward them.
static func _aim(plan: Dictionary, here: Vector2, speed: float) -> Vector2:
	var mid: Vector2 = plan["mid"]
	return mid.move_toward(plan["target"], HINT_SPEED * here.distance_to(mid) / speed)


## The blocks the police are in now noted combed (every car's; the helicopter's, HELI_SWEEP m round it); the searchers
## on player `peer`'s case, their claims tidied.
func _comb(peer: int, plan: Dictionary) -> Array[Unit]:
	var done: Dictionary = plan["done"]
	var t: float = plan["t"]
	var searchers: Array[Unit] = []
	for u: Unit in police.units:
		if not u.on_map():
			continue                        # (in the pool: nowhere)
		done[Graph.block_of(u.where())] = t
		if u.job == Unit.SEARCH and u.case == peer:
			searchers.append(u)
	var claims: Dictionary = plan["claims"]
	for i: int in claims.keys():
		if police.units[i].job != Unit.SEARCH or police.units[i].case != peer:
			claims.erase(i)
	if police.heli_flying():
		var h := Vector2(police.heli.global_position.x, -police.heli.global_position.z)
		var b0 := Graph.block_of(h)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var b := b0 + Vector2i(dx, dy)
				if Graph.block_middle(b).distance_to(h) < HELI_SWEEP:
					done[b] = t
	return searchers


## Searcher `u`'s claim (`claim`, [] none) once its way is plotted: the block unit.gd comb took, from `t` on if it is
## another.
static func _settle(u: Unit, claim: Array, t: float) -> void:
	if not claim.is_empty() and not u.plotting() and u.block != null and u.block != claim[0]:
		claim[0] = u.block
		claim[1] = t


## Whether searcher `u` is to be sent to another block: none yet; or, KEEP s after it was last sent and its way
## plotted: no block it could get into, its block combed since (by it or another), out of the zone, or there as near
## as it gets.
func _sent_on(u: Unit, plan: Dictionary, radius: float) -> bool:
	var claim: Array = (plan["claims"] as Dictionary).get(u.index, [])
	if claim.is_empty():
		return true
	if float(plan["t"]) - float(claim[2]) < KEEP or u.plotting():
		return false
	var b: Vector2i = claim[0]
	if b == NONE:
		return true                         # (none it could get into: the zone has grown since, perhaps)
	if float((plan["done"] as Dictionary).get(b, -INF)) >= float(claim[1]):
		return true
	if Graph.block_middle(b).distance_to(plan["mid"]) > radius + Graph.BLOCK:
		return true
	if u.there():
		(plan["done"] as Dictionary)[b] = plan["t"]     # (as near as it gets)
		return true
	return false


## The blocks of the zone (with a lane): [[m counted against it (combed lately: _recent), block], ...].
func _blocks(plan: Dictionary, radius: float) -> Array:
	var mid: Vector2 = plan["mid"]
	var lo := Graph.block_of(mid - Vector2(radius, radius))
	var hi := Graph.block_of(mid + Vector2(radius, radius))
	var out: Array = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var b := Vector2i(x, y)
			if police.graph.blocks.has(b) and Graph.block_middle(b).distance_to(mid) <= radius:
				out.append([_recent(plan, b), b])
	return out


## The m counted against block `b` combed lately: RECENT_WEIGHT per s left of REVISIT.
static func _recent(plan: Dictionary, b: Vector2i) -> float:
	var age := float(plan["t"]) - float((plan["done"] as Dictionary).get(b, -INF))
	return maxf(REVISIT - age, 0.0) * RECENT_WEIGHT


## The blocks the searchers but unit `but` go to (block -> true).
static func _taken(claims: Dictionary, but: int) -> Dictionary:
	var out := {}
	for k: int in claims:
		if k != but and claims[k][0] != NONE:
			out[claims[k][0]] = true
	return out


## The CHOICES of `blocks` (_blocks) cheapest for a searcher aiming at `aim` (their m from it, _recent's, CLAIMED for
## those in `taken`), cheapest first, and what each costs (ms: a second for TRAVEL * FAR_WEIGHT m; the drive into it
## is counted besides by the way's plotting): [blocks, PackedInt32Array].
static func _choices(blocks: Array, aim: Vector2, taken: Dictionary) -> Array:
	var costs: Array = []
	for e: Array in blocks:
		var b: Vector2i = e[1]
		costs.append([Graph.block_middle(b).distance_to(aim) + float(e[0]) + (CLAIMED if taken.has(b) else 0.0), b])
	costs.sort()
	var out: Array = []
	var ms := PackedInt32Array()
	for e: Array in costs.slice(0, CHOICES):
		out.append(e[1])
		ms.append(roundi(float(e[0]) / (TRAVEL * FAR_WEIGHT) * 1000.0))
	return [out, ms]


## The helicopter on the plan: over its block HELI_DWELL s, then the next (the searchers' blocks counted CLAIMED, the
## blocks in a straight line); on its way, its block thought over every RETHINK s.
func _heli(plan: Dictionary, radius: float, dt: float, blocks: Array) -> void:
	var h := Vector2(police.heli.global_position.x, -police.heli.global_position.z)
	var b: Vector2i = plan["heli"]
	var over := b != NONE and Graph.block_middle(b).distance_to(h) < HELI_OVER
	if over:
		plan["heli_t"] = float(plan["heli_t"]) + dt
	if b != NONE and float(plan["heli_t"]) <= HELI_DWELL \
			and Graph.block_middle(b).distance_to(plan["mid"]) <= radius + Graph.BLOCK \
			and (over or float(plan["t"]) - float(plan["heli_at"]) <= RETHINK):
		return
	if float(plan["heli_t"]) > HELI_DWELL:
		(plan["done"] as Dictionary)[b] = plan["t"]
	var aim := _aim(plan, h, HELI_TRAVEL)
	var taken := _taken(plan["claims"], -1)
	var best := NONE
	var best_cost := INF
	if blocks.is_empty():                   # (the searchers' this look, if any were sent)
		blocks = _blocks(plan, radius)
	for e: Array in blocks:
		var m := Graph.block_middle(e[1])
		var cost: float = m.distance_to(aim) + m.distance_to(h) * HELI_FAR_WEIGHT + float(e[0]) \
				+ (CLAIMED if taken.has(e[1]) else 0.0)
		if cost < best_cost:
			best_cost = cost
			best = e[1]
	plan["heli"] = best
	plan["heli_t"] = 0.0
	plan["heli_at"] = plan["t"]
