extends RefCounted
## The road network the bot cars drive (world/car_routes.json: the lanes of every car route, car_traffic.py) as a graph,
## for the vehicles sent somewhere rather than along a route (the police: scripts/police/police.gd):
## - The routes run from map edge to map edge and share their lanes where they run together. build() finds those shared
##   runs (points of two routes within SAME m of each other, heading the same way: a spatial hash of every lane point,
##   by CELL m cell and by heading) and puts a node at both ends of each, joined to its twin on the other route; and a
##   node at each route's ends. Edges: along each route between its nodes (the time its planned speeds take), between
##   twins (nothing), the U-turns (UTURN_COST), and the turns at the junctions (the routes' lights and give-ways: from
##   each lane through one onto each other lane through it going elsewhere, across the corner). Built once, on a worker
##   thread (a few seconds).
## - path(): A* from the lane nearest a place (heading its way when a heading is given) to the lane nearest another
##   (path_any: to whichever of several is the quickest to reach), fastest by the planned speeds: [[route, from point,
##   to point], ...]. Lanes are one-way: a target behind is reached round the blocks, at a junction, or by a U-turn.
## - make_route(): those pieces as one route, the format bus_bot.gd drives (points every STEP m, planned speeds, the
##   lights, give-ways, turns, room and bridge decks of the pieces at their new distances along it), ending with a
##   straight run off the lanes to an exact spot when given. It ends ("then": "stop") where the driver stops. Besides
##   the planned speeds ("v": the limits), the speeds of an urgent driver ("vu"): only the grip in the bends (GRIP), the
##   braking before them (URGENT_BRAKE), URGENT_TOP at most, OFF_ROAD_URGENT off the lanes.
## - nearest(): the lane point nearest a place (a coarser hash of every lane point, NEAR_CELL m cells, looked at ring
##   by ring from the place out: a fraction of a millisecond).
## - ahead(): where someone on a lane going on is likely to be so many metres on: along their lane, at each run it
##   shares with others, the one going on the straightest (the police's roadblocks, scripts/police/tactics/).
## - blocks: the map cut in BLOCK m squares, each with a lane through it, the lane point nearest its middle and where
##   each lane comes into it (entries); best_way(): of several blocks, the one quickest to get into, all told (one
##   Dijkstra; the police's searches comb the blocks one by one: scripts/police/tactics/search.gd).
## All read only once built: the queries may run on worker threads.
## Positions are pipeline x/y (x east, y north; Godot = (x, -z)).

const DATA := "res://world/car_routes.json"
const STEP := 2.0                           # m between the routes' points (car_traffic.py)
const CELL := 2.5                           # m, the spatial hash's cells
const HEADINGS := 8                         # heading buckets in the hash
const SAME := 1.3                           # m: two routes' points this near and heading alike: one lane
const SAME_DIR := 0.92                      # cos of the angle between their headings
const STRIDE := 3                           # points between two looks for shared lanes
const MIN_SPEED := 3.0                      # m/s counted on a lane, at least (a stop sign's 0)
const OFF_ROAD_SPEED := 6.0                 # m/s off the lanes to an exact spot (planned; counted for the ways there)...
const OFF_ROAD_URGENT := 14.0               # ...an urgent driver's at most (a car park, the grass: what stands there)
const UTURN_REACH := 10.0                   # m: a lane the other way this near, a U-turn onto it...
const UTURN_COST := 25000                   # ...counted as this many ms (taken when going round is longer)
const UTURN_EVERY := 50                     # points along a route between two places it may turn round
const UTURN_SPEED := 4.0                    # m/s round it
const JUNCTION_REACH := 14.0                # m round a junction (a light, a give-way) the lanes through it are...
const JUNCTION_SAME := 8.0                  # ...(two junctions this near are one)...
const TURN_IN := 3                          # ...a turn from one onto another this many points before and after it...
const TURN_SPEED := 7.0                     # ...taken at this many m/s...
const TURN_COST := 2000                     # ...plus this many ms
const NODE_KEY := 1 << 20                   # the A* heap's ints: f (ms) * NODE_KEY + node
const H_SPEED := 16.0                       # m/s of the A* heuristic: a little under the fastest roads' (quicker
											# searches, ways a little longer at most)
const GRIP := 6.5                           # m/s² sideways an urgent driver takes the bends at...
const URGENT_BRAKE := 6.0                   # ...braking at this before them...
const URGENT_TOP := 45.0                    # ...this fast at most (m/s)
const BEND := 3                             # points either side over which a bend's curvature is measured
const AHEAD_STEP := 5                       # points between two looks for the straightest lane (ahead)
const AHEAD_LOOK := 10                      # points ahead a lane's way on is judged
const NEAR_CELL := 16.0                     # m, the cells of nearest()'s hash...
const NEAR_RINGS := 12                      # ...looked at this many rings out at most (NEAR_CELL m each)
const BLOCK := 120.0                        # m, the side of a search block

var ready := false
var build_ms := 0
var ids: Array = []                         # route index -> its id
var src: Array = []                         # route index -> the route (car_routes.json)
var pts: Array = []                         # route index -> PackedVector2Array
var dirs: Array = []                        # route index -> PackedVector2Array, unit
var times: Array = []                       # route index -> PackedFloat32Array: s from its start to each point
var node_route := PackedInt32Array()
var node_index := PackedInt32Array()
var node_edges: Array = []                  # node -> PackedInt32Array of [to, cost (ms)] pairs
var route_nodes: Array = []                 # route index -> PackedInt32Array of its nodes, along it
var blocks := {}                            # Vector2i block (block_of) -> Vector2i(route, point) nearest its middle
var _entries := {}                          # Vector2i block -> PackedInt32Array of route << 16 | point coming into it
var _cells := {}                            # cell and heading key -> PackedInt32Array of route << 16 | point
var _near := {}                             # NEAR_CELL m cell key -> PackedInt32Array of route << 16 | point
var _rings: Array = []                      # ring -> Array[Vector2i]: the cells on its edge (offsets)
var _lengths := PackedFloat32Array()        # cumulative route lengths (random points)
var _decks: Array = []                      # route index -> PackedFloat32Array: the deck's height at each point (NAN
											# off a bridge deck)
var _rooms: Array = []                      # route index -> PackedFloat32Array: its "room" at each point


## Reads the routes and builds the graph (on a worker thread: touches nothing else).
func build() -> void:
	var t0 := Time.get_ticks_msec()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not data is Dictionary:
		push_error("No road network: %s missing" % DATA)
		return
	var routes: Dictionary = data["routes"]
	var total := 0.0
	for id: String in routes:
		var r: Dictionary = routes[id]
		var p := PackedVector2Array()
		for q: Array in r["pts"]:
			p.append(Vector2(q[0], q[1]))
		if p.size() < 3:
			continue
		var d := PackedVector2Array()
		d.resize(p.size())
		for i in p.size():
			d[i] = (p[mini(i + 1, p.size() - 1)] - p[maxi(i - 1, 0)]).normalized()
		var v: Array = r["v"]
		var t := PackedFloat32Array()
		t.resize(p.size())
		for i in range(1, p.size()):
			t[i] = t[i - 1] + STEP / maxf(float(v[mini(i, v.size() - 1)]), MIN_SPEED)
		ids.append(id)
		src.append(r)
		pts.append(p)
		dirs.append(d)
		times.append(t)
		_decks.append(_deck_points(r.get("decks", []), p.size()))
		_rooms.append(_runs(r.get("room", []), p.size(), 3.5))
		total += STEP * (p.size() - 1)
		_lengths.append(total)
	for r in pts.size():
		var p: PackedVector2Array = pts[r]
		var d: PackedVector2Array = dirs[r]
		for i in p.size():
			var key := _key(p[i], d[i])
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			var cell: PackedInt32Array = _cells[key]
			cell.append(r << 16 | i)
			_cells[key] = cell
			var near_key := _near_key(floori(p[i].x / NEAR_CELL), floori(p[i].y / NEAR_CELL))
			if not _near.has(near_key):
				_near[near_key] = PackedInt32Array()
			var near: PackedInt32Array = _near[near_key]
			near.append(r << 16 | i)
			_near[near_key] = near
			var b := block_of(p[i])
			if not blocks.has(b) or p[i].distance_to(block_middle(b)) < point(blocks[b]).distance_to(block_middle(b)):
				blocks[b] = Vector2i(r, i)
			if i == 0 or block_of(p[i - 1]) != b:
				if not _entries.has(b):
					_entries[b] = PackedInt32Array()
				var e: PackedInt32Array = _entries[b]
				e.append(r << 16 | i)
				_entries[b] = e
	_rings.append([Vector2i.ZERO])
	for ring in range(1, NEAR_RINGS + 1):
		var edge: Array[Vector2i] = []
		for k in range(-ring, ring + 1):
			edge.append_array([Vector2i(k, -ring), Vector2i(k, ring)])
			if absi(k) < ring:
				edge.append_array([Vector2i(-ring, k), Vector2i(ring, k)])
		_rings.append(edge)
	var nodes := {}                         # route << 16 | point -> node
	route_nodes.resize(pts.size())
	for r in pts.size():
		var last: int = (pts[r] as PackedVector2Array).size() - 1
		_node(nodes, r, 0)
		_node(nodes, r, last)
	var twins: Array = []                   # [node, node] joined
	for r in pts.size():
		_shared_runs(r, nodes, twins)
	var turns: Array = []                   # [node, node]: a U-turn from the first onto the lane the other way
	for r in pts.size():                    # every UTURN_EVERY points along each route, where a lane goes back
		var p: PackedVector2Array = pts[r]
		for i in range(UTURN_EVERY, p.size() - 1, UTURN_EVERY):
			if _opposite(r, p[i], (dirs[r] as PackedVector2Array)[i]).x >= 0:
				_node(nodes, r, i)
	for n in node_route.size():
		var r := node_route[n]
		var o := _opposite(r, (pts[r] as PackedVector2Array)[node_index[n]], (dirs[r] as PackedVector2Array)[node_index[n]])
		if o.x >= 0:
			turns.append([n, _node(nodes, o.x, o.y)])
	var corners := _junction_turns(nodes)   # [node, node, ms]: a turn at a junction
	node_edges.resize(node_route.size())
	for n in node_edges.size():
		node_edges[n] = PackedInt32Array()
	var lists: Array = []                   # route index -> its nodes (one pass over them all)
	lists.resize(pts.size())
	for r in pts.size():
		lists[r] = []
	for n in node_route.size():
		(lists[node_route[n]] as Array).append(n)
	for r in pts.size():
		var list: Array = lists[r]
		list.sort_custom(func(a: int, b: int) -> bool: return node_index[a] < node_index[b])
		route_nodes[r] = PackedInt32Array(list)
		var t: PackedFloat32Array = times[r]
		for k in range(1, list.size()):
			_edge(list[k - 1], list[k], roundi((t[node_index[list[k]]] - t[node_index[list[k - 1]]]) * 1000.0))
	for pair: Array in twins:
		_edge(pair[0], pair[1], 0)
		_edge(pair[1], pair[0], 0)
	for pair: Array in turns:
		_edge(pair[0], pair[1], UTURN_COST)
	for corner: Array in corners:
		_edge(corner[0], corner[1], corner[2])
	build_ms = Time.get_ticks_msec() - t0
	ready = true


func _key(p: Vector2, d: Vector2) -> int:
	var h := posmod(roundi(atan2(d.y, d.x) / TAU * HEADINGS), HEADINGS)
	return ((floori(p.x / CELL) + 32768) * 65536 + floori(p.y / CELL) + 32768) * HEADINGS + h


static func _near_key(x: int, y: int) -> int:
	return (x + 32768) * 65536 + y + 32768


func _node(nodes: Dictionary, r: int, i: int) -> int:
	var k := r << 16 | i
	if nodes.has(k):
		return nodes[k]
	nodes[k] = node_route.size()
	node_route.append(r)
	node_index.append(i)
	return nodes[k]


func _edge(a: int, b: int, cost: int) -> void:
	var e: PackedInt32Array = node_edges[a]
	e.append(b)
	e.append(cost)
	node_edges[a] = e


## The runs where route `r` shares a lane with another: a node at both ends of each, joined to its twin.
func _shared_runs(r: int, nodes: Dictionary, twins: Array) -> void:
	var p: PackedVector2Array = pts[r]
	var d: PackedVector2Array = dirs[r]
	var open := {}                          # other route -> [first i, first j, last i, last j]
	var i := 0
	while i < p.size():
		var here := _alike(r, p[i], d[i])
		for o: int in open.keys():
			if not here.has(o):
				_close(r, o, open[o], nodes, twins)
				open.erase(o)
		for o: int in here:
			if open.has(o):
				open[o][2] = i
				open[o][3] = here[o]
			else:
				open[o] = [i, here[o], i, here[o]]
		i += STRIDE
	for o: int in open:
		_close(r, o, open[o], nodes, twins)


func _close(r: int, o: int, run: Array, nodes: Dictionary, twins: Array) -> void:
	twins.append([_node(nodes, r, run[0]), _node(nodes, o, run[1])])
	if run[2] != run[0]:
		twins.append([_node(nodes, r, run[2]), _node(nodes, o, run[3])])


## The turns at the junctions (the lights, the give-ways of every route): from each lane through one onto each other
## lane through it going elsewhere (neither the same way nor back), across the corner (from TURN_IN points before the
## junction to TURN_IN after); none to or from a bridge deck (a road over another). [[node, node, ms], ...]
func _junction_turns(nodes: Dictionary) -> Array:
	var out: Array = []
	var seen := {}                          # junctions done (JUNCTION_SAME m cells)
	for r in pts.size():
		var p: PackedVector2Array = pts[r]
		var places: Array[Vector2] = []
		for y: Dictionary in src[r]["yields"]:
			places.append(Vector2(float(y["x"]), float(y["y"])))
		for l: Dictionary in src[r]["lights"]:
			places.append(p[clampi(roundi(float(l["s"]) / STEP), 0, p.size() - 1)])
		for j: Vector2 in places:
			var key := _near_key(roundi(j.x / JUNCTION_SAME), roundi(j.y / JUNCTION_SAME))
			if seen.has(key):
				continue
			seen[key] = true
			var through := _lanes_through(j)
			for a: int in through:
				for b: int in through:
					var da: Vector2 = (dirs[a] as PackedVector2Array)[through[a]]
					var db: Vector2 = (dirs[b] as PackedVector2Array)[through[b]]
					if a == b or da.dot(db) > SAME_DIR or da.dot(db) < -0.7:
						continue
					var ia: int = maxi(through[a] - TURN_IN, 0)
					var ib: int = mini(through[b] + TURN_IN, (pts[b] as PackedVector2Array).size() - 1)
					if _on_deck(a, ia) or _on_deck(b, ib):
						continue
					var length := point(Vector2i(a, ia)).distance_to(point(Vector2i(b, ib)))
					out.append([_node(nodes, a, ia), _node(nodes, b, ib), TURN_COST + roundi(length / TURN_SPEED * 1000.0)])
	return out


## The lanes through junction `j`: route -> its point nearest `j` (within JUNCTION_REACH m).
func _lanes_through(j: Vector2) -> Dictionary:
	var out := {}
	var best := {}
	var cx := floori(j.x / NEAR_CELL)
	var cy := floori(j.y / NEAR_CELL)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for packed: int in _near.get(_near_key(cx + dx, cy + dy), PackedInt32Array()):
				var r := packed >> 16
				var i := packed & 0xFFFF
				var d: float = (pts[r] as PackedVector2Array)[i].distance_to(j)
				if d < JUNCTION_REACH and d < float(best.get(r, INF)):
					best[r] = d
					out[r] = i
	return out


## Whether point `i` of route `r` is on a bridge deck.
func _on_deck(r: int, i: int) -> bool:
	return not is_nan((_decks[r] as PackedFloat32Array)[i])


## The lane the other way by lane point `at` (UTURN_REACH m at most: the other side of the road), its nearest point:
## Vector2i(route, point), (-1, -1) none.
func opposite(at: Vector2i) -> Vector2i:
	if at.x < 0:
		return at
	return _opposite(at.x, point(at), heading(at))


## The nearest lane point within UTURN_REACH m of `p` heading the other way from `d` (a lane back): Vector2i(route,
## point), (-1, -1) none.
func _opposite(r: int, p: Vector2, d: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := UTURN_REACH
	var h := posmod(roundi(atan2(-d.y, -d.x) / TAU * HEADINGS), HEADINGS)
	var cx := floori(p.x / CELL)
	var cy := floori(p.y / CELL)
	var n := ceili(UTURN_REACH / CELL)
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			for dh: int in [-1, 0, 1]:
				var key := ((cx + dx + 32768) * 65536 + cy + dy + 32768) * HEADINGS + posmod(h + dh, HEADINGS)
				if not _cells.has(key):
					continue
				for packed: int in _cells[key]:
					var o := packed >> 16
					var j := packed & 0xFFFF
					var dist: float = (pts[o] as PackedVector2Array)[j].distance_to(p)
					if o != r and dist > 2.0 and dist < best_d and (dirs[o] as PackedVector2Array)[j].dot(d) < -0.85:
						best_d = dist
						best = Vector2i(o, j)
	return best


## The other routes with a point within SAME m of `p` heading like `d`: route -> its nearest point.
func _alike(r: int, p: Vector2, d: Vector2) -> Dictionary:
	var out := {}
	var best := {}
	var h := posmod(roundi(atan2(d.y, d.x) / TAU * HEADINGS), HEADINGS)
	var cx := floori(p.x / CELL)
	var cy := floori(p.y / CELL)
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dh: int in [-1, 0, 1]:
				var key := ((cx + dx + 32768) * 65536 + cy + dy + 32768) * HEADINGS + posmod(h + dh, HEADINGS)
				if not _cells.has(key):
					continue
				for packed: int in _cells[key]:
					var o := packed >> 16
					if o == r:
						continue
					var j := packed & 0xFFFF
					var dist: float = (pts[o] as PackedVector2Array)[j].distance_to(p)
					if dist < SAME and (dirs[o] as PackedVector2Array)[j].dot(d) > SAME_DIR \
							and dist < float(best.get(o, INF)):
						best[o] = dist
						out[o] = j
	return out


# ---------------------------------------------------------------- queries

## The lane point nearest `p` within `reach` m (heading within 60° of `heading`, when not zero): Vector2i(route, point),
## (-1, -1) none. NEAR_CELL m cells ring by ring from `p` out, till the rings left are all further than the nearest.
func nearest(p: Vector2, heading := Vector2.ZERO, reach := 40.0) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := reach
	var h := heading.normalized()
	var cx := floori(p.x / NEAR_CELL)
	var cy := floori(p.y / NEAR_CELL)
	for ring in mini(ceili(reach / NEAR_CELL), NEAR_RINGS) + 1:
		if (ring - 1) * NEAR_CELL >= best_d:
			break                               # (every cell from here out is further than that)
		for o: Vector2i in _rings[ring]:
			var key := _near_key(cx + o.x, cy + o.y)
			if not _near.has(key):
				continue
			for packed: int in _near[key]:
				var r := packed >> 16
				var j := packed & 0xFFFF
				var dist: float = (pts[r] as PackedVector2Array)[j].distance_to(p)
				if dist < best_d and (h == Vector2.ZERO or (dirs[r] as PackedVector2Array)[j].dot(h) > 0.5):
					best_d = dist
					best = Vector2i(r, j)
	return best


## The lanes within `reach` m of `p` (NEAR_RINGS cells at most), off the bridge decks (no way down from one to
## there): each route's point nearest `p`, Vector2i(route, point).
func near_lanes(p: Vector2, reach: float) -> Array[Vector2i]:
	var best := {}                          # route -> [m, point]
	var cx := floori(p.x / NEAR_CELL)
	var cy := floori(p.y / NEAR_CELL)
	for ring in mini(ceili(reach / NEAR_CELL), NEAR_RINGS) + 1:
		for o: Vector2i in _rings[ring]:
			for packed: int in _near.get(_near_key(cx + o.x, cy + o.y), PackedInt32Array()):
				var r := packed >> 16
				var j := packed & 0xFFFF
				var d: float = (pts[r] as PackedVector2Array)[j].distance_to(p)
				if d < reach and d < float(best.get(r, [INF])[0]) and not _on_deck(r, j):
					best[r] = [d, j]
	var out: Array[Vector2i] = []
	for r: int in best:
		out.append(Vector2i(r, best[r][1]))
	return out


## The search block map point `p` is in.
static func block_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BLOCK), floori(p.y / BLOCK))


## The middle of block `b` (map xy).
static func block_middle(b: Vector2i) -> Vector2:
	return (Vector2(b) + Vector2(0.5, 0.5)) * BLOCK


## Where the lanes come into block `b`: Vector2i(route, point) each.
func entries(b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for packed: int in _entries.get(b, PackedInt32Array()):
		out.append(Vector2i(packed >> 16, packed & 0xFFFF))
	return out


## A random lane point (routes by length), at least `margin` m from the routes' ends.
func random_point(rng: RandomNumberGenerator, margin := 60.0) -> Vector2i:
	var r := _lengths.bsearch(rng.randf() * _lengths[-1])
	var n: int = (pts[r] as PackedVector2Array).size()
	var m := mini(roundi(margin / STEP), n / 3)
	return Vector2i(r, rng.randi_range(m, n - 1 - m))


func point(at: Vector2i) -> Vector2:
	return (pts[at.x] as PackedVector2Array)[at.y]


func heading(at: Vector2i) -> Vector2:
	return (dirs[at.x] as PackedVector2Array)[at.y]


## The fastest way along the lanes from lane point `from` to lane point `to` (nearest()): [[route, from point, to
## point], ...], or [] when there is none.
func path(from: Vector2i, to: Vector2i) -> Array:
	var goals: Array[Vector2i] = [to]
	return path_any(from, goals)


## The fastest way along the lanes from lane point `from` to whichever of lane points `goals` is the quickest to reach,
## `extra` (ms, one for each goal; none: 0) counted besides (all near one another: a block's entries, the lanes round a
## place): [[route, from point, to point], ...], or [] when there is none.
func path_any(from: Vector2i, goals: Array[Vector2i], extra := PackedInt32Array()) -> Array:
	var want := {}                          # route -> [the goal on it (the first along it), its extra ms]
	var target := Vector2.ZERO              # (the A* heuristic's: the goals' middle...)
	var count := 0
	for k in goals.size():
		var q := goals[k]
		if q.x >= 0:
			if not want.has(q.x) or q.y < int(want[q.x][0]):
				want[q.x] = [q.y, extra[k] if k < extra.size() else 0]
			target += point(q)
			count += 1
	if from.x < 0 or want.is_empty():
		return []
	target /= count
	var slack := 0.0                        # (...less the furthest goal's m from it)
	for q: Vector2i in goals:
		if q.x >= 0:
			slack = maxf(slack, point(q).distance_to(target))
	var n := node_route.size()
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(0x7FFFFFFF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var heap := []                          # f * NODE_KEY + node
	var tf: PackedFloat32Array = times[from.x]
	var best := 0x7FFFFFFF
	var best_node := -1                     # (-1: straight on along the route it starts on)
	var best_goal := Vector2i(-1, -1)
	if want.has(from.x) and int(want[from.x][0]) >= from.y:
		best = roundi((tf[want[from.x][0]] - tf[from.y]) * 1000.0) + int(want[from.x][1])
		best_goal = Vector2i(from.x, want[from.x][0])
	var sn: PackedInt32Array = route_nodes[from.x]
	for k in sn.size():                     # the first node ahead on the route it starts on
		if node_index[sn[k]] > from.y:
			var c := roundi((tf[node_index[sn[k]]] - tf[from.y]) * 1000.0)
			g[sn[k]] = c
			_push(heap, (c + _h(sn[k], target, slack)) * NODE_KEY + sn[k])
			break
	while not heap.is_empty():
		var top: int = _pop(heap)
		var u: int = top % NODE_KEY
		var f: int = top / NODE_KEY
		if f >= best:
			break
		if f - _h(u, target, slack) > g[u]:
			continue
		var r := node_route[u]
		if want.has(r) and node_index[u] <= int(want[r][0]):
			var tr: PackedFloat32Array = times[r]
			var c: int = g[u] + roundi((tr[want[r][0]] - tr[node_index[u]]) * 1000.0) + int(want[r][1])
			if c < best:
				best = c
				best_node = u
				best_goal = Vector2i(r, want[r][0])
		var e: PackedInt32Array = node_edges[u]
		for k in range(0, e.size(), 2):
			var w := e[k]
			var c: int = g[u] + e[k + 1]
			if c < g[w]:
				g[w] = c
				came[w] = u
				_push(heap, (c + _h(w, target, slack)) * NODE_KEY + w)
	return _pieces(from, best_node, best_goal, came) if best_goal.x >= 0 else []


## The way into whichever of `blocks` (Vector2i each) costs least from lane point `from`: the drive into it (by the
## first lane into it to reach: entries) plus `extra` (ms, one for each block, none below 0). One Dijkstra for them all,
## the entries weighed as the nodes before them on their lanes come out of it, and stopped as soon as nothing left could
## do better (or past `limit` ms): the blocks are near, it looks at a corner of the map, not all of it. {"block",
## "pieces" ([[route, from point, to point], ...])}, {} none.
func best_way(from: Vector2i, blocks: Array, extra: PackedInt32Array, limit: int) -> Dictionary:
	if from.x < 0:
		return {}
	var want := {}                          # route -> [[entry point, block index], ...]
	for k in blocks.size():
		for goal: Vector2i in entries(blocks[k]):
			if not want.has(goal.x):
				want[goal.x] = []
			(want[goal.x] as Array).append([goal.y, k])
	if want.is_empty():
		return {}
	var n := node_route.size()
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(0x7FFFFFFF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var heap := []                          # time * NODE_KEY + node
	var tf: PackedFloat32Array = times[from.x]
	var best := 0x7FFFFFFF
	var best_k := -1
	var best_node := -2
	var best_goal := Vector2i(-1, -1)
	for e: Array in want.get(from.x, []):   # (straight on along the route it starts on)
		if int(e[0]) >= from.y:
			var c := roundi((tf[e[0]] - tf[from.y]) * 1000.0) + extra[e[1]]
			if c < best:
				best = c
				best_k = e[1]
				best_node = -1
				best_goal = Vector2i(from.x, e[0])
	var sn: PackedInt32Array = route_nodes[from.x]
	for k in sn.size():                     # the first node ahead on the route it starts on
		if node_index[sn[k]] > from.y:
			g[sn[k]] = roundi((tf[node_index[sn[k]]] - tf[from.y]) * 1000.0)
			_push(heap, g[sn[k]] * NODE_KEY + sn[k])
			break
	while not heap.is_empty():
		var top: int = _pop(heap)
		var u: int = top % NODE_KEY
		var c0: int = top / NODE_KEY
		if c0 >= best or c0 > limit:
			break
		if c0 > g[u]:
			continue
		var r := node_route[u]
		if want.has(r):                     # (the entries ahead of it on its lane)
			var tr: PackedFloat32Array = times[r]
			for e: Array in want[r]:
				if int(e[0]) >= node_index[u]:
					var c := c0 + roundi((tr[e[0]] - tr[node_index[u]]) * 1000.0) + extra[e[1]]
					if c < best:
						best = c
						best_k = e[1]
						best_node = u
						best_goal = Vector2i(r, e[0])
		var e: PackedInt32Array = node_edges[u]
		for k in range(0, e.size(), 2):
			var w := e[k]
			var c: int = c0 + e[k + 1]
			if c < g[w]:
				g[w] = c
				came[w] = u
				_push(heap, c * NODE_KEY + w)
	if best_goal.x < 0:
		return {}
	return {"block": blocks[best_k], "pieces": _pieces(from, best_node, best_goal, came)}


## The pieces of a way from lane point `from` through the nodes up to `last` (`came`: each node's one before; -1:
## none, straight on along from's route) to lane point `goal`: [[route, from point, to point], ...].
func _pieces(from: Vector2i, last: int, goal: Vector2i, came: PackedInt32Array) -> Array:
	var chain: Array = []
	var u := last
	while u >= 0:
		chain.push_front(u)
		u = came[u]
	var pieces: Array = [[from.x, from.y, from.y]]  # (a twin edge, a turn: onto another route)
	for m: int in chain:
		var last_piece: Array = pieces[-1]
		if node_route[m] == last_piece[0]:
			last_piece[2] = node_index[m]
		else:
			pieces.append([node_route[m], node_index[m], node_index[m]])
	(pieces[-1] as Array)[2] = goal.y
	return pieces.filter(func(q: Array) -> bool: return q[2] > q[1])


## A* heuristic: the time to within `slack` m of `target` in a straight line at a fast road's speed (ms).
func _h(node: int, target: Vector2, slack: float) -> int:
	var d := (pts[node_route[node]] as PackedVector2Array)[node_index[node]].distance_to(target) - slack
	return roundi(maxf(d, 0.0) / H_SPEED * 1000.0)


## A binary heap of ints (smallest first): f * NODE_KEY + node.
static func _push(heap: Array, item: int) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent] <= item:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _pop(heap: Array) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var c := l + 1 if l + 1 < n and heap[l + 1] < heap[l] else l
		if heap[c] >= last:
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


## `pieces` (path()) as one route bus_bot.gd drives, then straight off the lanes to `spot` when it is not NAN (an exact
## place: where someone stands); no pieces but a `start`: straight from there to `spot`. Points every STEP m.
func make_route(pieces: Array, spot := Vector2(NAN, NAN), start := Vector2(NAN, NAN)) -> Dictionary:
	var out_pts := []
	var xy := PackedVector2Array()          # (the same points, ready for the driver: no conversion on the main thread)
	var v := PackedFloat32Array()
	var cap := PackedFloat32Array()         # (an urgent driver's speed at most: off the lanes)
	var lights := []
	var yields := []
	var turns := []
	var room := PackedFloat32Array()
	var decks := PackedFloat32Array()
	var heading := Vector2.ZERO              # at the end of the last piece
	for piece: Array in pieces:
		var r: int = piece[0]
		var i0: int = piece[1]
		var i1: int = piece[2]
		var route: Dictionary = src[r]
		var p: PackedVector2Array = pts[r]
		if not xy.is_empty():
			var a := xy[-1]
			if a.distance_to(p[i0]) > 3.0:  # (a U-turn onto the lane the other way: half a circle, ahead; a turn at a
				var back := heading.dot((dirs[r] as PackedVector2Array)[i0]) < -0.5     # junction: across the corner)
				for q: Vector2 in _uturn(a, p[i0], heading) if back else _across(a, p[i0]):
					xy.append(q)
					v.append(UTURN_SPEED if back else TURN_SPEED)
					cap.append(INF)
					room.append(0.0)
					decks.append(NAN)
			else:
				i0 += 1                     # (its first point is the twin of the last one)
		if i1 < i0:
			continue
		heading = (dirs[r] as PackedVector2Array)[i1]
		var offset := STEP * xy.size() - STEP * i0
		var rv: Array = route["v"]
		var rroom: PackedFloat32Array = _rooms[r]
		var rdeck: PackedFloat32Array = _decks[r]
		xy.append_array(p.slice(i0, i1 + 1))
		room.append_array(rroom.slice(i0, i1 + 1))
		decks.append_array(rdeck.slice(i0, i1 + 1))
		for i in range(i0, i1 + 1):
			v.append(float(rv[mini(i, rv.size() - 1)]))
			cap.append(INF)
		var lo := STEP * i0
		var hi := STEP * i1
		for l: Dictionary in route["lights"]:
			if float(l["s"]) >= lo and float(l["s"]) <= hi:
				var c := l.duplicate()
				c["s"] = float(l["s"]) + offset
				lights.append(c)
		for y: Dictionary in route["yields"]:
			if float(y["s"]) >= lo and float(y["s"]) <= hi:
				var c := y.duplicate()
				c["s"] = float(y["s"]) + offset
				yields.append(c)
		for t: Array in route["turns"]:
			if float(t[1]) >= lo and float(t[0]) <= hi:
				turns.append([maxf(float(t[0]), lo) + offset, minf(float(t[1]), hi) + offset, t[2]])
	if xy.is_empty() and not is_nan(start.x):
		xy.append(start)
		v.append(OFF_ROAD_SPEED)
		cap.append(OFF_ROAD_URGENT)
		room.append(3.5)
		decks.append(NAN)
	if not is_nan(spot.x) and not xy.is_empty():
		var a := xy[-1]
		var n := floori(a.distance_to(spot) / STEP)
		for k in range(1, n + 1):
			xy.append(a.move_toward(spot, STEP * k))
			v.append(OFF_ROAD_SPEED)
			cap.append(OFF_ROAD_URGENT)
			room.append(3.5)
			decks.append(NAN)
	out_pts.resize(xy.size())
	for k in xy.size():
		out_pts[k] = [xy[k].x, xy[k].y]
	# (bus_bot.gd _set_route takes "xy", "room_xy" and "deck_xy" as they are; "pts", "room", "decks" for the rest)
	var route_out := {"start": "police", "end": "terminus", "then": "stop", "step": STEP,
			"length": STEP * maxf(xy.size() - 1, 0), "pts": out_pts, "v": v, "vu": urgent_speeds_xy(xy, cap),
			"lights": lights, "yields": yields, "turns": turns, "stops": [], "room": _encode_runs(room),
			"decks": _encode_decks(decks), "xy": xy, "room_xy": room, "deck_xy": decks}
	return route_out


## An urgent driver's speeds along `points` ([x, y] every STEP m): the most GRIP holds in each bend (its curvature over
## BEND points either side), `cap` at most (one each; none: no more), braking at URGENT_BRAKE before the tighter ones,
## URGENT_TOP at most.
static func urgent_speeds_xy(points: PackedVector2Array, cap := PackedFloat32Array()) -> PackedFloat32Array:
	var n := points.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var b := points[i]
		var d1 := b - points[maxi(i - BEND, 0)]
		var d2 := points[mini(i + BEND, n - 1)] - b
		var arc := d1.length() + d2.length()
		var k := absf(d1.angle_to(d2)) / arc if d1.length() > 0.1 and d2.length() > 0.1 else 0.0
		out[i] = minf(sqrt(GRIP / maxf(k, 1e-5)), URGENT_TOP)
		if i < cap.size():
			out[i] = minf(out[i], cap[i])
	for i in range(n - 2, -1, -1):
		out[i] = minf(out[i], sqrt(out[i + 1] * out[i + 1] + 2.0 * URGENT_BRAKE * STEP))
	return out


## Where someone on lane point `at` is likely to be `distance` m on, going on along the lanes: theirs, and at each run
## it shares with others the one going on the straightest (AHEAD_LOOK points on), looked at every AHEAD_STEP points;
## the end of a lane (the map's edge) at the furthest. Vector2i(route, point).
func ahead(at: Vector2i, distance: float) -> Vector2i:
	if at.x < 0:
		return at
	var r := at.x
	var i := at.y
	var left := distance
	while left > 0.0:
		var n: int = (pts[r] as PackedVector2Array).size()
		var k := mini(AHEAD_STEP, n - 1 - i)
		if k <= 0:
			break
		i += k
		left -= k * STEP
		var d: Vector2 = (dirs[r] as PackedVector2Array)[i]
		var best := _going_on(r, i, d)
		var alike := _alike(r, (pts[r] as PackedVector2Array)[i], d)
		for o: int in alike:
			var on := _going_on(o, alike[o], d)
			if on > best + 0.05:
				best = on
				r = o
				i = alike[o]
	return Vector2i(r, i)


## How straight on from heading `d` lane `r` goes from its point `i` (cos of the turn AHEAD_LOOK points on).
func _going_on(r: int, i: int, d: Vector2) -> float:
	var dr: PackedVector2Array = dirs[r]
	return d.dot(dr[mini(i + AHEAD_LOOK, dr.size() - 1)])


## The points of a U-turn from `a` to `b` (on the lane the other way), every STEP m round half a circle on the side
## ahead of `heading`, the ends left out.
static func _uturn(a: Vector2, b: Vector2, heading: Vector2) -> Array:
	var mid := (a + b) * 0.5
	var u := a - mid
	var turn := 1.0 if u.rotated(PI * 0.5).dot(heading) > 0.0 else -1.0
	var n := maxi(ceili(PI * u.length() / STEP), 2)
	var out := []
	for k in range(1, n):
		out.append(mid + u.rotated(turn * PI * k / n))
	return out


## The points from `a` to `b` in a straight line, every STEP m, the ends left out.
static func _across(a: Vector2, b: Vector2) -> Array:
	var out := []
	for k in range(1, ceili(a.distance_to(b) / STEP)):
		out.append(a.move_toward(b, STEP * k))
	return out


## Run-length "room" ([[count, m], ...]) as one value per point (`fill` past its end).
static func _runs(runs: Array, n: int, fill: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for run: Array in runs:
		for k in int(run[0]):
			out.append(float(run[1]))
	while out.size() < n:
		out.append(fill)
	return out


static func _encode_runs(values: PackedFloat32Array) -> Array:
	var out := []
	for x in values:
		if not out.is_empty() and is_equal_approx(float(out[-1][1]), x):
			out[-1][0] += 1
		else:
			out.append([1, x])
	return out


## "decks" ([[first point, [heights...]], ...]) as one height per point, NAN on the ground.
static func _deck_points(spans: Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(NAN)
	for span: Array in spans:
		var zs: Array = span[1]
		for k in zs.size():
			if int(span[0]) + k < n:
				out[int(span[0]) + k] = zs[k]
	return out


static func _encode_decks(values: PackedFloat32Array) -> Array:
	var out := []
	var i := 0
	while i < values.size():
		if is_nan(values[i]):
			i += 1
			continue
		var zs := []
		var first := i
		while i < values.size() and not is_nan(values[i]):
			zs.append(values[i])
			i += 1
		out.append([first, zs])
	return out
