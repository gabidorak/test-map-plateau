extends RefCounted
## Lot ligne18-viaduc's layout (scripts/ligne18/viaduc/): what goes where along the line, read off the master plan
## (ligne18_plan.gd, frozen): the deck's pieces (span by span, a JOINT between two spans over each pier, stopped at
## s = zone_s on each side of a station's zone, cut clean at s_edge), the runs of the deck's top equipment (everywhere
## but over the stations' zones), the cells (about CELL m of s each, cut at piers: the streaming's), the piers'
## footprints. The builder (viaduc_builder.gd), the lot's drop() and the test read it alike.

const Plan = preload("res://scripts/ligne18/ligne18_plan.gd")
const CELL := 200.0                         # m of s per cell (cut at the nearest pier)
const JOINT := 0.06                         # m between two spans' ends over a pier (centred on it)
const ABUT_DECK := 0.6                      # m: the first span's end over the abutment, behind its bearing line
const SHAFT := Vector2(1.375, 0.55)         # m: a double pier's shafts, half along x half across
const SHAFT_SINGLE := Vector2(1.375, 0.75)  # m: a single pier's shaft
const SHAFTS_APART := 3.5                   # m: a double pier's shafts' centres, across
const ABUT_HALF := Vector2(1.0, 5.05)       # m: the abutment's seat, half along x half across (the walls' outer face)
const RAMP_HALF := 5.05                     # m: the ramp's retaining walls' outer faces off the axis
## The piers on a road (the plan's on_road: off the stations' grounds, clear of the AI's lanes): a kerbed island, its
## margin round the shafts (m) what the lanes leave (the bd Gaspard Monge span's ends 0.44 m from a car's side).
const ISLAND_PIERS := {4803.3: 0.3, 4854.3: 0.3, 4953.8: 0.8}
const ISLAND_MARGIN := 1.0                  # m: the most an island takes round the shafts

static var _pieces: Array = []
static var _cuts := PackedFloat64Array()


static func s_start() -> float:
	return float(Plan.plan()["viaduct"]["s_start"])


static func s_abutment() -> float:
	return float(Plan.plan()["viaduct"]["s_abutment"])


static func s_edge() -> float:
	return float(Plan.plan()["viaduct"]["s_edge"])


## The stations' zones (built ones), in s order: Vector2(s0, s1).
static func zones() -> Array:
	var out := []
	for id: String in Plan.stations_built():
		var z: Array = Plan.station(id)["zone_s"]
		out.append(Vector2(float(z[0]), float(z[1])))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return out


## Whether s is over a station's zone (its ends excluded).
static func in_zone(s: float) -> bool:
	for z: Vector2 in zones():
		if s > z.x and s < z.y:
			return true
	return false


## The deck's pieces, in s order: {s0, s1 (its ends), a0, a1 (its bearing lines: a pier's s, a zone's end, the
## abutment's; s_edge for the last), end0, end1 ("pier", "zone", "abutment", "edge")}.
static func pieces() -> Array:
	if not _pieces.is_empty():
		return _pieces
	var sup := []                                           # [s, kind]
	for p: Dictionary in Plan.piers():
		sup.append([float(p["s"]), "abutment" if p["type"] == "abutment" else "pier"])
	for z: Vector2 in zones():
		sup.append([z.x, "zone_in"])
		sup.append([z.y, "zone_out"])
	sup.append([s_edge(), "edge"])
	sup.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in sup.size() - 1:
		var a: Array = sup[i]
		var b: Array = sup[i + 1]
		if a[1] == "zone_in" or a[0] >= s_edge():
			continue                                        # (a station's zone: its own deck)
		var end0: String = "zone" if a[1] == "zone_out" else a[1]
		var end1: String = "zone" if b[1] == "zone_in" else b[1]
		var s0: float = a[0] - ABUT_DECK if end0 == "abutment" else a[0] + (JOINT * 0.5 if end0 == "pier" else 0.0)
		var s1: float = b[0] - (JOINT * 0.5 if end1 == "pier" else 0.0)
		_pieces.append({"s0": s0, "s1": s1, "a0": a[0], "a1": b[0], "end0": end0, "end1": end1})
	return _pieces


## The runs of the line's top equipment (parapets, cable troughs, the walkway's handrail): from the ramp's start to the
## first zone, between the zones, from the last to s_edge (Vector2(s0, s1)).
static func runs() -> Array:
	var out := []
	var s := s_start()
	for z: Vector2 in zones():
		out.append(Vector2(s, z.x))
		s = z.y
	out.append(Vector2(s, s_edge()))
	return out


## The cells' cuts (s_start .. s_edge): about CELL m apart, each on a pier (the first on the abutment: the ramp alone).
static func cuts() -> PackedFloat64Array:
	if not _cuts.is_empty():
		return _cuts
	var piers := PackedFloat64Array()
	for p: Dictionary in Plan.piers():
		piers.append(float(p["s"]))
	_cuts.append(s_start())
	var target := s_start() + CELL
	while target < s_edge() - CELL * 0.5:
		var best := NAN
		for s in piers:
			if s > _cuts[_cuts.size() - 1] + CELL * 0.5 and (is_nan(best) or absf(s - target) < absf(best - target)):
				best = s
		if is_nan(best) or best >= s_edge() - CELL * 0.3:
			break
		_cuts.append(best)
		target = best + CELL
	_cuts.append(s_edge())
	return _cuts


## The number of cells.
static func cell_count() -> int:
	return cuts().size() - 1


## Cell k's s range.
static func cell_range(k: int) -> Vector2:
	return Vector2(cuts()[k], cuts()[k + 1])


## The cell s falls in.
static func cell_of(s: float) -> int:
	var c := cuts()
	for k in c.size() - 1:
		if s < c[k + 1]:
			return k
	return c.size() - 2


## The piers of cell k (the plan's dictionaries).
static func cell_piers(k: int) -> Array:
	return Plan.piers().filter(func(p: Dictionary) -> bool: return cell_of(float(p["s"])) == k)


## The deck's pieces of cell k (by their middle).
static func cell_pieces(k: int) -> Array:
	return pieces().filter(func(p: Dictionary) -> bool: return cell_of((p["s0"] + p["s1"]) * 0.5) == k)


## A pier's footprint, half sizes in its frame (x along the line, y across): its shafts', the abutment's seat.
static func footprint(p: Dictionary) -> Vector2:
	match str(p["type"]):
		"double":
			return Vector2(SHAFT.x, SHAFTS_APART * 0.5 + SHAFT.y)
		"single":
			return SHAFT_SINGLE
	return ABUT_HALF


## Map point m in pier p's frame (x along the line, y to its left).
static func pier_local(p: Dictionary, m: Vector2) -> Vector2:
	var h := float(p["heading"])
	var d := m - Vector2(float(p["x"]), float(p["y"]))
	return Vector2(d.x * cos(h) + d.y * sin(h), -d.x * sin(h) + d.y * cos(h))


## Pier p's frame point (along, across) on the map.
static func pier_map(p: Dictionary, l: Vector2) -> Vector2:
	var h := float(p["heading"])
	return Vector2(float(p["x"]), float(p["y"])) + Vector2(l.x * cos(h) - l.y * sin(h), l.x * sin(h) + l.y * cos(h))


## Whether pier p gets a kerbed island.
static func has_island(p: Dictionary) -> bool:
	return ISLAND_PIERS.keys().any(func(s: float) -> bool: return absf(float(p["s"]) - s) < 0.05)


## Pier p's island's margin round its shafts (0 without one).
static func island_margin(p: Dictionary) -> float:
	for s: float in ISLAND_PIERS:
		if absf(float(p["s"]) - s) < 0.05:
			return ISLAND_PIERS[s]
	return 0.0


## Whether map point m stands on a pier's footprint grown by `margin` (an island's whole), or under the ramp.
static func on_footprint(m: Vector2, margin: float) -> bool:
	var sv := Plan.project(m)
	if is_nan(sv.x):
		return false
	if sv.x >= s_start() - margin and sv.x <= s_abutment() and absf(sv.y) <= RAMP_HALF + margin:
		return true
	for p: Dictionary in Plan.piers():
		if absf(float(p["s"]) - sv.x) > 12.0:
			continue
		var l := pier_local(p, m)
		var half := footprint(p) + Vector2.ONE * maxf(margin, island_margin(p))
		if absf(l.x) <= half.x and absf(l.y) <= half.y:
			return true
	return false
