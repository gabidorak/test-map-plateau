extends RefCounted
## The way a police car takes where it is sent (unit.gd asks; plan runs on a worker thread: it reads the road network,
## road_graph.gd, and nothing else).
## - To a place: along the lanes to the lane by it (ON_LANE m: either way of its road); off the lanes, to the lane round
##   it (DEST_REACH m) quickest to get there from, the drive off the lanes counted (road_graph.gd OFF_ROAD_SPEED). Then,
##   sent to an exact spot (someone's), on off the lanes to it.
## - `lanes` asked (a car stuck on its way: unit.gd): the lanes only, to the lane nearest the place, no drive off them.
## - Straight to the spot, off the lanes, instead: from off the lanes already or near it (OFF_LANE, CLOSE); or, on the
##   physics (not gliding: near a player), when the lanes go a long way round (CUT_ACROSS, DETOUR). The pursuit pilot
##   drives round what stands in the way (driving/pursuit_pilot.gd).
## - Searching: into the search block that costs least, the drive into it counted (road_graph.gd best_way).
## Positions are pipeline x/y (x east, y north).

const ON_LANE := 6.0                        # m: a lane this near a place, it is got to from that lane (its road)...
const DEST_REACH := 120.0                   # ...else from the lanes this near
const OFF_LANE := 8.0                       # m off its lanes...
const CLOSE := 50.0                         # ...or this near the spot: straight there
const CUT_ACROSS := 200.0                   # m: on the physics this near the spot, the lanes...
const DETOUR := 2.5                         # ...this many times longer than straight there (and 50 m): straight there
const COMB_REACH := 300000                  # ms of driving the search blocks are looked for within


## The way for an ask {"here", "facing", "gliding", "dest", "spot" (NAN none), "comb" ([blocks, extra ms] or null),
## "lanes" (the lanes only)}: {"route" (road_graph.gd make_route, {} none), "block" (the search block chosen, or null)}.
static func plan(graph: RefCounted, ask: Dictionary) -> Dictionary:
	var here: Vector2 = ask["here"]
	var from: Vector2i = graph.nearest(here, ask["facing"], 30.0)
	if from.x < 0:
		from = graph.nearest(here, Vector2.ZERO, 60.0)
	if ask["comb"] != null:
		var way: Dictionary = graph.best_way(from, ask["comb"][0], ask["comb"][1], COMB_REACH)
		var pieces: Array = way.get("pieces", [])
		return {"route": graph.make_route(pieces) if not pieces.is_empty() else {}, "block": way.get("block")}
	if ask.get("lanes", false):
		var pieces: Array = graph.path(from, graph.nearest(ask["dest"], Vector2.ZERO, DEST_REACH))
		return {"route": graph.make_route(pieces) if not pieces.is_empty() else {}, "block": null}
	var spot: Vector2 = ask["spot"]
	var exact := not is_nan(spot.x)
	var d := here.distance_to(spot) if exact else INF
	if d < DEST_REACH and (from.x < 0 or graph.point(from).distance_to(here) > OFF_LANE or d < CLOSE):
		return {"route": graph.make_route([], spot, here), "block": null}
	var pieces := _along_lanes(graph, from, ask["dest"])
	var route: Dictionary = graph.make_route(pieces, spot) if not pieces.is_empty() else {}
	if exact and not ask["gliding"] and d < CUT_ACROSS \
			and (route.is_empty() or float(route["length"]) > DETOUR * d + 50.0):
		route = graph.make_route([], spot, here)
	return {"route": route, "block": null}


## The pieces of the way from lane point `from` along the lanes to the lane by `dest` (ON_LANE m), or else to the
## lane round it quickest to get there from (DEST_REACH m, or further when there is none), the drive off the lanes
## counted.
static func _along_lanes(graph: RefCounted, from: Vector2i, dest: Vector2) -> Array:
	var goals: Array[Vector2i] = graph.near_lanes(dest, ON_LANE)
	if goals.is_empty():
		goals = graph.near_lanes(dest, DEST_REACH)
	if goals.is_empty():
		goals = graph.near_lanes(dest, graph.NEAR_CELL * graph.NEAR_RINGS)
	var off := PackedInt32Array()
	for q: Vector2i in goals:
		off.append(roundi(graph.point(q).distance_to(dest) / graph.OFF_ROAD_SPEED * 1000.0))
	return graph.path_any(from, goals, off)
