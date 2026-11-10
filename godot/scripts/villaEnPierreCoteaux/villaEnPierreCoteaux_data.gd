extends RefCounted
## Villa de charme's place on the map (scripts/villaEnPierreCoteaux/villaEnPierreCoteaux.gd and its builders share it): its name, its frame, the wall
## round its grounds and its gate. The villa's frame: x east, y up from the house's floor, z south; its origin at the
## front facade's west end (map ORIGIN).

const NAME := "Villa de charme"
const ID := "villa-001"                     # (permanent: owners keep it; the name may change)
const ORIGIN := Vector2(264.0, -424.0)      # map: the house's frame origin
const W := 40.0                             # the house: m along its front (x)
const D := 22.0                             # m deep (z), the wings included
const PLINTH := 0.6                         # m, its floor over the highest ground under it
## The wall round the grounds (map x east, y north): Thomas's red line, kept 9 m off the road's lane.
const WALL := [Vector2(223.0, -435.8), Vector2(211.9, -422.0), Vector2(207.1, -413.3), Vector2(207.4, -405.5),
		Vector2(219.8, -394.1), Vector2(229.6, -381.8), Vector2(242.8, -358.0), Vector2(250.4, -356.0),
		Vector2(260.0, -358.4), Vector2(276.3, -364.4), Vector2(304.3, -369.3), Vector2(310.4, -373.0),
		Vector2(315.0, -378.9), Vector2(321.7, -391.0), Vector2(334.9, -404.8), Vector2(338.5, -410.3),
		Vector2(342.4, -422.9), Vector2(349.5, -459.5), Vector2(349.3, -477.9), Vector2(346.3, -486.5),
		Vector2(340.7, -493.6), Vector2(332.8, -498.1), Vector2(324.4, -501.3), Vector2(307.4, -504.3),
		Vector2(291.3, -504.7), Vector2(276.2, -503.8), Vector2(268.8, -502.9), Vector2(254.8, -498.3),
		Vector2(248.7, -494.1), Vector2(243.6, -488.8), Vector2(239.8, -482.4), Vector2(232.9, -456.8),
		Vector2(229.0, -446.5)]
const GATE := Vector2(238.7, -365.4)        # map: the gate's middle, on the wall
const GATE_HALF := 3.45                     # m: the wall stops this far either side (the pillars, the leaves between)
const LEAF := 2.55                          # m, each leaf


## The ground's material ids (ground_builder.gd, a chunk's vertices in Godot coordinates) painted `grass` inside the
## wall (the lawn; what is built lies over it).
## The old track from the road to the former houses (gravel on the map) is lawn this far round the gate too.
const OLD_TRACK := 25.0


static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var grass := materials.find("grass")
	var water := materials.find("water")
	var gravel := materials.find("gravel")
	var grass_colour := Color.html(str(palette["grass"]))
	var gravel_colour := Color.html(str(palette.get("gravel", palette["grass"])))
	var court := court_shape()
	var wall := PackedVector2Array(WALL)
	var box := Rect2(wall[0], Vector2.ZERO)
	for p in wall:
		box = box.expand(p)
	for k in verts.size():
		var v := verts[k]
		var p := Vector2(v.x, -v.z)
		if box.has_point(p) and ids[k * 4] != water and Geometry2D.is_point_in_polygon(p, wall):
			var l := to_local2(p)
			var paved := Geometry2D.is_point_in_polygon(l, court)
			ids[k * 4] = gravel if paved else grass
			colours[k] = gravel_colour if paved else grass_colour
		elif gravel >= 0 and ids[k * 4] == gravel and p.distance_to(GATE) < OLD_TRACK:
			ids[k * 4] = grass
			colours[k] = grass_colour
	return [ids, colours]


## Map -> the villa's frame (x, z).
static func to_local2(m: Vector2) -> Vector2:
	return Vector2(m.x - ORIGIN.x, ORIGIN.y - m.y)


## The villa's frame (x, z) -> map.
static func to_map(l: Vector2) -> Vector2:
	return Vector2(l.x + ORIGIN.x, ORIGIN.y - l.y)


## The gate in the villa's frame: [middle (x, z), along the wall (unit), into the grounds (unit)].
static func gate_local() -> Array:
	var g := to_local2(GATE)
	var best := INF
	var along := Vector2.RIGHT
	var snapped := g
	for i in WALL.size():
		var a := to_local2(WALL[i])
		var b := to_local2(WALL[(i + 1) % WALL.size()])
		var c := Geometry2D.get_closest_point_to_segment(g, a, b)
		if c.distance_to(g) < best:
			best = c.distance_to(g)
			along = (b - a).normalized()
			snapped = c
	var inward := Vector2(-along.y, along.x)
	var mid := Vector2.ZERO
	for p: Vector2 in WALL:
		mid += to_local2(p)
	mid /= WALL.size()
	if inward.dot(mid - snapped) < 0.0:
		inward = -inward
	return [snapped, along, inward]


# ---------------------------------------------------------------- the court

## The court (Thomas: one simple shape, white gravel in it, a stone border round it), in the villa's frame (x east,
## z south): the main court, flat; the drive from the gate, down to it evenly; the bateau, a gentle slope up from it to
## the garage court, level with the garage doors' sill; the fountain's basin cut out of its edge. Its levels are the
## design's (from the floor), the ground terraformed to them (terraform_zones(), named by the lot).
const FLOOR_Y := -4.6                       # m (the map's height): the house's floor, the garage doors' sill
const COURT_Y := -0.9                       # the main court, under the floor (the perron's steps)
const GATE_Y := -0.05                       # the drive at the gate (the road's level there)
const COURT := Rect2(-21.0, -24.0, 83.0, 24.0)
const COURT_ROUND := 3.0
const BATEAU := Rect2(41.0, -1.0, 8.0, 12.0)    # its slope from z = 0 (the court) to z = 11 (the garage court)
const GARAGE_COURT := Rect2(40.0, 11.0, 14.0, 14.5)
const DRIVE_HALF := 2.6
## The drive after the gate: it bends east then south to the court.
const DRIVE := [Vector2(-8.0, -55.5), Vector2(3.0, -52.0), Vector2(13.0, -46.5), Vector2(21.0, -41.0),
		Vector2(27.0, -35.0), Vector2(30.0, -29.0), Vector2(31.0, -22.0)]
const FOUNTAIN := Vector3(41.0, -26.0, 0.0)
const BASIN := Vector2(5.8, 5.2)            # the fountain basin's half-axes (x, z)
const COURT_BLEND := 5.0                    # m of ground round the court eased to its edge

static var _court := PackedVector2Array()
static var _drive := PackedVector2Array()


## The drive's line, from the gate's middle.
static func drive_line() -> PackedVector2Array:
	if _drive.is_empty():
		_drive.append(gate_local()[0])
		for p: Vector2 in DRIVE:
			_drive.append(p)
	return _drive


## The court's outline.
static func court_shape() -> PackedVector2Array:
	if _court.is_empty():
		var shape: PackedVector2Array = Geometry2D.offset_polygon(_rect(COURT.grow(-COURT_ROUND)), COURT_ROUND,
				Geometry2D.JOIN_ROUND)[0]
		var band: PackedVector2Array = Geometry2D.offset_polyline(drive_line(), DRIVE_HALF, Geometry2D.JOIN_ROUND,
				Geometry2D.END_BUTT)[0]
		for part: PackedVector2Array in [_rect(BATEAU), _rect(GARAGE_COURT), band]:
			shape = _largest(Geometry2D.merge_polygons(shape, part))
		var basin := PackedVector2Array()
		for k in 48:
			basin.append(Vector2(FOUNTAIN.x + cos(TAU * k / 48) * (BASIN.x + 0.45),
					FOUNTAIN.y + sin(TAU * k / 48) * (BASIN.y + 0.45)))
		_court = _largest(Geometry2D.clip_polygons(shape, basin))
	return _court


## The court's height (from the floor) at its point l.
static func court_y(l: Vector2) -> float:
	if l.x >= BATEAU.position.x and l.x <= BATEAU.end.x and l.y > 0.0 and l.y < GARAGE_COURT.position.y:
		return lerpf(COURT_Y, 0.0, l.y / GARAGE_COURT.position.y)
	if l.y >= GARAGE_COURT.position.y:
		return 0.0
	if COURT.has_point(l):
		return COURT_Y
	return lerpf(GATE_Y, COURT_Y, clampf(_along_drive(l) / _along_drive_to_court(), 0.0, 1.0))


## How far along the drive (from the gate) its point nearest to l is.
static func _along_drive(l: Vector2) -> float:
	var line := drive_line()
	var best := INF
	var at := 0.0
	var s := 0.0
	for i in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(l, line[i], line[i + 1])
		if l.distance_to(q) < best:
			best = l.distance_to(q)
			at = s + line[i].distance_to(q)
		s += line[i].distance_to(line[i + 1])
	return at


## How far along the drive it reaches the court.
static func _along_drive_to_court() -> float:
	var line := drive_line()
	var s := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		if b.y >= COURT.position.y:
			return s + a.distance_to(b) * clampf((COURT.position.y - a.y) / (b.y - a.y), 0.0, 1.0)
		s += a.distance_to(b)
	return s


## How far l is from outline `poly`, and its nearest point on it.
static func outline_nearest(poly: PackedVector2Array, l: Vector2) -> Vector2:
	var best := INF
	var at := l
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(l, poly[i], poly[(i + 1) % poly.size()])
		if l.distance_squared_to(q) < best:
			best = l.distance_squared_to(q)
			at = q
	return at


## The court's terraforming (builder/terraform.gd): the ground in it at its levels, eased back to the map's over
## COURT_BLEND m round it; 1 m grids on the map, made from the design alone (the same when the map is built and in the
## game).
static func terraform_zones() -> Array:
	var shape := court_shape()
	var reach: PackedVector2Array = Geometry2D.offset_polygon(shape, COURT_BLEND + 1.5)[0]
	var a := to_map(Vector2(_bounds(reach).position.x, _bounds(reach).end.y))       # (the south-west corner)
	var b := to_map(Vector2(_bounds(reach).end.x, _bounds(reach).position.y))       # (the north-east one)
	var x0 := floorf(a.x)
	var y0 := ceilf(b.y)
	var w := int(ceilf(b.x - x0)) + 1
	var h := int(ceilf(y0 - a.y)) + 1
	var wt := PackedByteArray()
	wt.resize(w * h)
	var sf := PackedFloat32Array()
	sf.resize(w * h)
	sf.fill(FLOOR_Y + COURT_Y)
	for j in h:
		for i in w:
			var l := to_local2(Vector2(x0 + i + 0.5, y0 - j - 0.5))
			if not Geometry2D.is_point_in_polygon(l, reach):
				continue
			var k := j * w + i
			if Geometry2D.is_point_in_polygon(l, shape):
				wt[k] = 255
				sf[k] = FLOOR_Y + court_y(l)
				continue
			var q := outline_nearest(shape, l)
			var t := clampf(1.0 - l.distance_to(q) / COURT_BLEND, 0.0, 1.0)
			wt[k] = roundi(t * t * (3.0 - 2.0 * t) * 255.0)
			sf[k] = FLOOR_Y + court_y(q)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## The largest of polygons (Geometry2D's results: the outline, not a hole).
static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var most := -1.0
	for p: PackedVector2Array in polys:
		var area := 0.0
		for i in p.size():
			area += p[i].cross(p[(i + 1) % p.size()])
		if absf(area) > most:
			most = absf(area)
			best = p
	return best
