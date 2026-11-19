extends RefCounted
## The roadblocks (police.gd runs it on the host every LOOK_EVERY s for each case seen): two stars and more, one at a
## time, REST s apart on a case. AHEAD m ahead of them along the lanes they are on (road_graph.gd ahead), where nobody
## sees (police.gd hidden: HIDDEN m from every player and camera), two cars of the fleet are put at once (out of the
## pool, as GTA does; else patrols nobody sees: police.gd free_unit), slewed across the road's two lanes, sirens on,
## braked (unit.gd ROADBLOCK: cars like any other, a knock moves them), until they are past it (PASSED m), lost, or MAX
## s; then after them. No place for one (seen there, no room, no car): tried again RETRY s later, not at every look.
## Positions are pipeline x/y (x east, y north).

const Unit = preload("res://scripts/police/unit.gd")
const Garages = preload("res://scripts/online/garages.gd")
const Layers = preload("res://scripts/physics_layers.gd")

const AHEAD := 400.0                        # m ahead of them along the lanes
const LANE := 3.4                           # m between the two cars when the lane the other way is not known
const PASSED := 25.0                        # m past it they are past it
const MAX := 90.0                           # s at most...
const REST := 60.0                          # ...and before the next on the same case
const SLEW := 1.2                           # rad a car is turned across its lane
const SHIFTS := [0.0, 4.0, -4.0, 8.0, -8.0] # m along the road its place is looked for
const MOVING := 4.0                         # m/s: slower, no roadblock further on
const ROOM := Vector3(2.8, 1.8, 5.4)        # m: a police car's box, and room round it
const RETRY := 1.5                          # s after a roadblock that could not be set before the next try

var police: Node                            # police.gd
var active := {}                            # peer -> {"at" (map xy), "dir" (map xy, their way), "units", "t"}
var _rest := {}                             # peer -> s before the next on their case
var refused := ""                          # why the last try at one came to nothing (tests, debugging)
var _query := PhysicsShapeQueryParameters3D.new()


func _init(p: Node) -> void:
	police = p
	var box := BoxShape3D.new()
	box.size = ROOM
	_query.shape = box
	_query.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.PROPS | Layers.VEGETATION | Layers.VEHICLES


## Each LOOK_EVERY s (`dt`), before the cases: the clocks; those of cases closed lifted.
func tick(dt: float) -> void:
	for peer: int in active.keys():
		active[peer]["t"] += dt
		if not police.cases.has(peer):
			lift(peer)
	for peer: int in _rest.keys():
		_rest[peer] -= dt
		if _rest[peer] <= 0.0 or not police.cases.has(peer):
			_rest.erase(peer)


## Case `c` seen, its quarry `q` (tactics/pursuit.gd quarry_of): a roadblock set ahead of them, or the one there lifted
## once they are past it (or it is too old).
func update(c: RefCounted, q: Dictionary) -> void:
	if active.has(c.peer):
		var b: Dictionary = active[c.peer]
		if ((q["xy"] as Vector2) - (b["at"] as Vector2)).dot(b["dir"]) > PASSED or float(b["t"]) > MAX:
			lift(c.peer)
	elif c.level >= 2:
		set_up(c, q)


## A roadblock ahead of case `c`'s quarry `q` when they are on the move, there is room, a car or two to put there and
## nobody sees there; none else (tried again RETRY s later).
func set_up(c: RefCounted, q: Dictionary) -> void:
	if q["car"] == null or float(q["speed"]) < MOVING or _rest.has(c.peer):
		return
	_rest[c.peer] = RETRY                   # (till it is set: then REST)
	var graph: RefCounted = police.graph
	var at: Vector2i = graph.nearest(q["xy"], q["dir_xy"], 30.0)
	if at.x < 0:
		refused = "no lane under them"
		return
	var far: Vector2i = graph.ahead(at, AHEAD)
	var p: Vector2 = graph.point(far)
	var h: Vector2 = graph.heading(far)
	var lanes: Array[Vector2] = [p]         # (its lane, and the other way's: the road's two lanes)
	var heads: Array[Vector2] = [h]
	var back: Vector2i = graph.opposite(far)
	if back.x >= 0:
		lanes.append(graph.point(back))
		heads.append(graph.heading(back))
	else:
		lanes.append(p - h.orthogonal() * LANE)     # (no lane known the other way: its left, where it is)
		heads.append(-h)
	if lanes[1].distance_to(p) < LANE:      # (a narrow road: the two cars LANE m apart, not one into the other)
		var out := lanes[1] - p
		lanes[1] = p + (out.normalized() if out.length() > 0.1 else -h.orthogonal()) * LANE
	for spot: Vector2 in lanes:
		if not police.hidden(spot):
			refused = "in sight (%.0f m from them)" % spot.distance_to(q["xy"])
			return
	var chosen: Array[Unit] = []
	for spot: Vector2 in lanes:
		var u := _free(chosen)
		if u == null:
			refused = "no car"
			return
		chosen.append(u)
	var places := _clear_places(lanes, heads, h)
	if places.is_empty():
		refused = "no room"
		return
	var indices: Array[int] = []
	for k in chosen.size():
		_put_across(chosen[k], places[k], c.peer)
		indices.append(chosen[k].index)
	active[c.peer] = {"at": p, "dir": h, "units": indices, "t": 0.0}
	_rest.erase(c.peer)
	refused = ""


## Player `peer`'s roadblock lifted: its cars after them (their case still open), or back on patrol.
func lift(peer: int) -> void:
	var b: Dictionary = active.get(peer, {})
	active.erase(peer)
	if b.is_empty():
		return
	_rest[peer] = REST
	for i: int in b["units"]:
		var u: Unit = police.units[i]
		u.driver.may_glide = true
		if u.job != Unit.ROADBLOCK:
			continue                        # (its officer out meanwhile: foot/arrest.gd)
		var c: RefCounted = police.cases.get(peer)
		if c:
			u.set_job(Unit.CHASE, peer)
			u.go(c.last, true, c.last)
		else:
			police.patrol(u)


## Where the cars go by lane points `lanes` (headings `heads`), side by side: each slewed across its lane, where
## nothing stands (ROOM), the same SHIFTS m along the road (heading `h`) for them all (the first shift with room for
## every one); [] none.
func _clear_places(lanes: Array[Vector2], heads: Array[Vector2], h: Vector2) -> Array[Transform3D]:
	var space: PhysicsDirectSpaceState3D = police.game.get_world_3d().direct_space_state
	var q := _query
	for shift: float in SHIFTS:
		var out: Array[Transform3D] = []
		for k in lanes.size():
			var yaw := atan2(heads[k].x, -heads[k].y) + SLEW * (1.0 if k % 2 == 0 else -1.0)
			var at: Vector2 = lanes[k] + h * shift
			var ground := Garages._at(at.x, at.y)
			q.transform = Transform3D(Basis(Vector3.UP, yaw), ground + Vector3.UP * 1.05)
			if not space.intersect_shape(q, 1).is_empty():
				break
			out.append(Transform3D(Basis(Vector3.UP, yaw), ground + Vector3.UP * 0.3))
		if out.size() == lanes.size():
			return out
	return []


## A car for a roadblock, not one of `taken`: out of the pool (unless police.gd puts none out: tests), else a patrol
## nobody sees; null none.
func _free(taken: Array[Unit]) -> Unit:
	for u: Unit in police.units:
		if police.spawning and u.job == Unit.STOWED and not u in taken:
			return u
	var best: Unit = null
	var best_d: float = police.HIDDEN * police.HIDDEN
	for u: Unit in police.units:
		if u.job != Unit.PATROL or u in taken:
			continue
		var d: float = police.game.traffic.eye_distance_squared(u.car.global_position)
		if d > best_d:
			best = u
			best_d = d
	return best if best and police.hidden(best.where()) else null     # (nobody sees it vanish from there either)


## Car `u` put at `xf` (on its lane), on the physics (no gliding back onto its lane), braked, siren on.
func _put_across(u: Unit, xf: Transform3D, peer: int) -> void:
	u.driver.may_glide = false
	police.deploy(u, xf, true)
	u.set_job(Unit.ROADBLOCK, peer)
	u.dest = Vector2(xf.origin.x, -xf.origin.z)
