extends RefCounted
## The plan of Polytechnique's station (ex Palaiseau) and its grounds, lot ligne18-polytechnique (child of ligne18:
## scripts/ligne18/ligne18_plan.gd gives the line, the station's frame and levels). Two frames:
## - the station's (u along the line towards Versailles, v to its left, y = z - hall_z: Line.station_transform()):
##   its building (station_builder.gd): the hall at the ground under the deck (its glass folded skirts on an opaque
##   base, the white "Gare" box, the terracotta east box, the 1 000 m² shops building square to the boulevard, the
##   porch of the main doors between them), the passerelle (level 1), the platforms, the origami roof;
## - the streets' grid (local (a, b): a along bd Gaspard Monge eastward, b northward, along av. de la Vauve; the map
##   turned by ANGLE round PIVOT: to_map(), to_local(), frame()): the grounds (grounds_builder.gd), redone inside
##   perimeter(): from the TCSP's north kerb (kerb_s(), the map's) to the Danone road, from av. de la Vauve's west
##   sidewalk (kept) to the west street. Along the TCSP: the kerb, a planted strip with its trees, a two-way cycle
##   track, the sidewalk; the forecourt (place Marguerite Perey's parvis) from it up to the station's doors, its beds
##   and groves; the west street (the old loop's west side, straight: from the Danone road down to a turning circle,
##   the drop-off, at the forecourt's west corner); the east esplanade from the station's east doors to the avenue's
##   zebra; a path along the north side; mown lawns elsewhere, trees in rows and groups (none within TREE_V of the
##   axis, nor on the viaduct's piers' footprints).
## - the ground (height()): FLAT round the station (the paving's top at hall_z at the doors), eased over EASE m into a
##   surface fitted to the map's ground along the perimeter (Q, the edges' tables: the TCSP's level at its kerb);
##   terraformed so (terraform_zones()), eased back to the map's over BLEND m outside (not over the avenue's sidewalk).

const Line = preload("res://scripts/ligne18/ligne18_plan.gd")
const ID := "polytechnique"
const OSM := "osm:w1063329861"              # the map's station building (#394)

# ---------------------------------------------------------------- the station (its frame: u, v; y over the hall)

const HALL_Z := -1.88
const PASS_Y := 5.0                         # the passerelle, level 1 (z 3.12)
const DECK_Y := 8.88                        # the deck's top face (z 7.00)
const RAIL_Y := 9.35                        # the rails' top (z 7.47)
const PLAT_Y := 10.40                       # the platforms' top (z 8.52)
const ROOF_Y := 20.10                       # the roof's highest (z 18.22)
const PLAT_U := 30.0                        # the platforms: u -30..30
const PLAT_V := Vector2(4.0, 8.6)           # |v| of their edge, their back
## The envelope: its folded glass skirts from the base (BASE_H over the hall, the zigzag between V_IN and V_OUT,
## FOLDS half folds from U_BASE.x to U_BASE.y) out to the eaves (FLARE m further out, U_TOP: it leans out at the ends).
const U_BASE := Vector2(-32.7, 35.3)
const U_TOP := Vector2(-34.7, 37.3)
const V_IN := 15.6
const V_OUT := 18.4
const FOLDS := 16
const FLARE := 2.5
const BASE_H := 3.5
const EAVE_Y := Vector2(17.3, 19.92)        # the eaves' valleys (inner folds) and peaks (outer folds)
const CENTRE_Y := Vector2(15.6, 16.6)       # the roof along the axis, under them
## The boxes at the ground: the white "Gare" box (u, v rect; its height), the terracotta east box, the shops building
## (square to the boulevard: OSM's), the porch between them (the main doors at DOOR_V).
const WHITE_BOX := Rect2(16.0, 15.6, 21.6, 5.8)
const WHITE_H := 12.6
const EAST_BOX := Rect2(-35.0, 15.6, 8.91, 6.2)
const EAST_H := 9.0
const SHOPS := [Vector2(-26.09, 15.6), Vector2(7.3, 15.6), Vector2(7.51, 35.0), Vector2(-8.55, 46.44),
		Vector2(-26.09, 21.87)]
const SHOPS_H := 8.5
const DOOR_V := 17.0
const PORCH := Vector2(7.3, 16.0)           # u of the porch's sides (the main doors between)
const PASSAGE_V := 8.6                      # |v| of the open ends' doors (the passage under the deck)
## The station's piers (single, elliptic, under the axis) and the end supports (a cross-beam on two shafts).
const PIERS_U := [-22.5, 0.0, 22.5]
const END_U := 45.0

# ---------------------------------------------------------------- the grounds (the grid: a, b)

const PIVOT := Vector2(100.0, 180.0)
const ANGLE := -0.178023584                 # rad (-10.2°): bd Gaspard Monge's direction (av. de la Vauve square to it)
const FLAT := -2.03                         # the ground round the station: the paving KERB over it, at hall_z
const KERB := 0.15                          # m: the paving, sidewalks, cycle track over the ground (the street kit's)
const LOW := 0.055                          # m: lowered at a crossing
const ASPHALT_UP := 0.04
const RAMP := 1.5                           # m over which a lowering eases
const EASE := 20.0                          # m from the flat zone to the fitted ground
const BLEND := 3.0                          # m outside the perimeter: the terraforming eases back to the map's
const EDGE_W := 12.0                        # m in from the perimeter over which the edges' tables count
const EDGE_FADE := 8.0                      # m in from the perimeter over which the flat zone gives way to them
## The fitted ground: c0 + c1 a' + c2 b' + c3 a'² + c4 a'b' + c5 b'², (a', b') = (a, b) / 100 (rms 0.17 m), and the
## map's ground along the edges (8 m apart): the TCSP at its kerb (a from -88), the avenue's sidewalk (b from -16),
## the Danone road's verge at b 116.5 (a from -88), the west edge at a -80.5 (b from -16).
const Q := [-1.604, 0.405, -0.394, 0.317, -0.002, -0.281]
const SOUTH_G := [-2.023, -1.982, -1.941, -1.897, -1.853, -1.811, -1.772, -1.732, -1.690, -1.645, -1.599, -1.553,
		-1.509, -1.468, -1.430, -1.395, -1.358, -1.314, -1.263, -1.217, -1.192, -1.220]
const EAST_G := [-1.197, -1.192, -1.122, -1.134, -1.179, -1.268, -1.327, -1.408, -1.449, -1.540, -1.596, -1.601,
		-1.626, -1.559, -1.594, -1.592, -1.612, -1.869, -1.560]
const NORTH_G := [-2.696, -2.668, -2.638, -2.523, -2.404, -2.351, -2.274, -2.347, -2.293, -2.328, -2.347, -2.385,
		-2.430, -2.470, -2.542, -2.561, -2.680, -2.571, -2.348, -2.006, -1.627, -1.742]
const WEST_G := [-2.014, -1.985, -1.801, -1.324, -1.547, -1.529, -1.588, -1.858, -2.030, -2.184, -2.253, -2.314,
		-2.372, -2.422, -2.485, -2.529, -2.944, -2.620, -2.475]
## The TCSP's north edge (the map's: kept), west to east; the kerb drawn along it.
const KERB_S := [Vector2(-82.0, -3.96), Vector2(-60.0, -3.87), Vector2(-44.0, -3.66), Vector2(-24.0, -3.52),
		Vector2(-20.0, -2.93), Vector2(-12.0, -2.67), Vector2(-4.0, -2.49), Vector2(24.0, -2.52), Vector2(56.0, -2.58),
		Vector2(60.0, -3.53), Vector2(64.0, -4.67), Vector2(68.0, -5.81), Vector2(72.0, -7.44), Vector2(76.0, -9.85)]
## Av. de la Vauve's west sidewalk's west edge (kept): a = EAST_EDGE.x + EAST_EDGE.y b.
const EAST_EDGE := Vector2(73.4, -0.0167)
const NORTH_B := 115.5                      # the perimeter's north edge (the Danone road's verge north of it)
const WEST_A := -80.0
## The bands along the TCSP, m in from its kerb: the kerb's top, the planted strip, the cycle track (two-way), the
## sidewalk (east of the forecourt; the forecourt's paving elsewhere).
const STRIP := Vector2(0.15, 2.5)
const CYCLE := Vector2(2.5, 5.5)
const WALK := 8.5
## Where the strip is paved (a from, to): the forecourt's opening (its zebra), the east zebra, the turning circle's.
const OPENINGS := [Vector2(-30.0, 4.0), Vector2(52.0, 60.5), Vector2(-74.5, -63.0)]
## The zebras over the TCSP (the map's: a from, to), the kerb lowered there.
const ZEBRAS := [Vector2(-9.1, -3.9), Vector2(53.2, 59.1), Vector2(-72.3, -67.2)]
## The forecourt (a from, to; b up to), the east esplanade, its path to the avenue's zebra, the north path.
const FORECOURT := Rect2(-75.0, -20.0, 99.5, 76.0)
const ESPLANADE := Rect2(0.0, 56.0, 36.0, 51.0)
const EAST_PATH := Rect2(36.0, 99.0, 40.0, 8.0)
const NORTH_PATH := Rect2(-62.5, 106.0, 63.0, 3.0)
## The west street: two-way, from the Danone road down to a turning circle (the drop-off); its sidewalks; its zebra.
const STREET := Rect2(-72.0, 19.0, 6.5, 100.75)
const CIRCLE := Vector3(-68.75, 19.0, 8.0)  # centre (a, b), the kerb's radius
const ISLAND := 3.0                         # m: the turning circle's island (setts, kerbed)
const STREET_WALK := 3.0
const STREET_ZEBRA := Vector2(106.0, 109.0) # b from, to
## The forecourt's beds (lawn, sunken: at the ground), each with two trees; the planters near the doors.
const BEDS := [Rect2(-58.0, 9.0, 9.0, 5.0), Rect2(-45.0, 9.0, 9.0, 5.0), Rect2(4.5, 9.0, 8.0, 5.0),
		Rect2(16.0, 9.0, 8.0, 5.0), Rect2(-33.0, 15.0, 8.0, 4.5)]
const PLANTERS := [Rect2(-26.0, 26.0, 4.0, 4.0), Rect2(17.0, 22.0, 4.0, 4.0)]
const TREE_V := 7.0                         # m: no tree nearer the axis
const PIER_CLEAR := 1.0                     # m kept clear round a pier's shafts

const FINE := 10.0                          # the polygon offsets worked at this scale

static var _cache := {}
static var _st_c := Vector2(NAN, NAN)       # the station's centre (map), heading
static var _st_th := 0.0


# ---------------------------------------------------------------- frames

## The map's point of local (a, b).
static func to_map(p: Vector2) -> Vector2:
	return PIVOT + p.rotated(ANGLE)


## The local (a, b) of the map's p.
static func to_local(m: Vector2) -> Vector2:
	return (m - PIVOT).rotated(-ANGLE)


## The grounds' frame in the game: a node so placed draws in local (a, height, -b).
static func frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ANGLE), Vector3(PIVOT.x, 0.0, -PIVOT.y))


## The station's (u, v) in the grid, and back.
static func st_to_local(q: Vector2) -> Vector2:
	_st()
	return to_local(_st_c + q.rotated(_st_th))


static func st_from_local(p: Vector2) -> Vector2:
	_st()
	return (to_map(p) - _st_c).rotated(-_st_th)


static func _st() -> void:
	if is_nan(_st_c.x):
		var st := Line.station(ID)
		_st_c = Vector2(st["centre"][0], st["centre"][1])
		_st_th = float(st["heading"])


## A station-frame polygon in the grid.
static func st_poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Vector2 in pts:
		out.append(st_to_local(q))
	return out


# ---------------------------------------------------------------- the station's shapes (station frame)

## The skirts' base node k (0 at the west end, FOLDS at the east), side +1 (south, v > 0) or -1: (u, v).
static func base_node(k: int, side: float) -> Vector2:
	var u := lerpf(U_BASE.y, U_BASE.x, float(k) / FOLDS)
	return Vector2(u, side * (V_IN if k % 2 == 0 else V_OUT))


## The eave's node k: (u, v, y).
static func eave_node(k: int, side: float) -> Vector3:
	var u := lerpf(U_TOP.y, U_TOP.x, float(k) / FOLDS)
	var outer := k % 2 == 1
	return Vector3(u, side * ((V_OUT if outer else V_IN) + FLARE), EAVE_Y.y if outer else EAVE_Y.x)


## The roof along the axis at node k: (u, 0, y) (at the ends, on the gable's plane).
static func centre_node(k: int) -> Vector3:
	var u := lerpf(U_TOP.y, U_TOP.x, float(k) / FOLDS)
	var y: float = CENTRE_Y.y if k % 2 == 1 else CENTRE_Y.x
	if k == 0 or k == FOLDS:
		u = gable_u(k == FOLDS, y)
	return Vector3(u, 0.0, y)


## The gable's u at height y (east: true), leaning out from the base to the eaves.
static func gable_u(east: bool, y: float) -> float:
	var t := (y - BASE_H) / (EAVE_Y.x - BASE_H)
	return lerpf(U_BASE.x, U_TOP.x, t) if east else lerpf(U_BASE.y, U_TOP.y, t)


## The roof's underside at (u, v) (station frame), interpolated as its folds are.
static func roof_y(u: float, v: float) -> float:
	var f := clampf((U_TOP.y - u) / (U_TOP.y - U_TOP.x) * FOLDS, 0.0, FOLDS - 0.0001)
	var k := int(f)
	var t := f - k
	var e0 := eave_node(k, 1.0)
	var e1 := eave_node(k + 1, 1.0)
	var c0 := centre_node(k)
	var c1 := centre_node(k + 1)
	var ev := lerpf(e0.y, e1.y, t)
	var ey := lerpf(e0.z, e1.z, t)
	var cy := lerpf(c0.z, c1.z, t)
	return lerpf(cy, ey, clampf(absf(v) / ev, 0.0, 1.0))


## The hall's floor (station frame): the skirts' base round it, the porch to the doors.
static func hall_floor() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in FOLDS + 1:
		out.append(base_node(k, -1.0))
	out.append_array([Vector2(U_BASE.x, V_IN), Vector2(PORCH.x, V_IN), Vector2(PORCH.x, DOOR_V),
			Vector2(PORCH.y, DOOR_V), Vector2(PORCH.y, V_IN), Vector2(U_BASE.y, V_IN)])
	return out


## The station's outline at the ground (station frame): the hall, the boxes, the shops building, the porch out.
static func outline_st() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in FOLDS + 1:
		out.append(base_node(k, -1.0))
	var e := EAST_BOX
	var w := WHITE_BOX
	out.append_array([Vector2(U_BASE.x, V_IN), Vector2(e.position.x, V_IN), Vector2(e.position.x, e.end.y),
			SHOPS[4], SHOPS[3], SHOPS[2], Vector2(PORCH.x, DOOR_V), Vector2(PORCH.y, DOOR_V), Vector2(PORCH.y, w.end.y),
			Vector2(w.end.x, w.end.y), Vector2(w.end.x, V_IN), Vector2(U_BASE.y, V_IN)])
	return out


## The station's outline in the grid.
static func outline() -> PackedVector2Array:
	if not _cache.has("outline"):
		_cache["outline"] = st_poly(Array(outline_st()))
	return _cache["outline"]


## Whether local (a, b) is in the station (its outline).
static func in_station(p: Vector2) -> bool:
	return inside(p, outline())


# ---------------------------------------------------------------- the ground

## The surface fitted to the map's ground (local a, b): Q, corrected along the edges by their tables.
static func fitted(p: Vector2) -> float:
	var q := _q(p)
	var acc := 0.0
	var ws := 0.0
	var bk := kerb_b(p.x)
	var w := _ease(1.0 - (p.y - bk) / EDGE_W)
	if w > 0.0:
		acc += w * (_table(SOUTH_G, -88.0, p.x) - _q(Vector2(p.x, bk)))
		ws += w
	var ae: float = EAST_EDGE.x + EAST_EDGE.y * p.y
	w = _ease(1.0 - (ae - p.x) / EDGE_W)
	if w > 0.0:
		acc += w * (_table(EAST_G, -16.0, p.y) - _q(Vector2(ae, p.y)))
		ws += w
	w = _ease(1.0 - (NORTH_B + 1.0 - p.y) / EDGE_W)
	if w > 0.0:
		acc += w * (_table(NORTH_G, -88.0, p.x) - _q(Vector2(p.x, NORTH_B + 1.0)))
		ws += w
	w = _ease(1.0 - (p.x - WEST_A + 0.5) / EDGE_W)
	if w > 0.0:
		acc += w * (_table(WEST_G, -16.0, p.y) - _q(Vector2(WEST_A - 0.5, p.y)))
		ws += w
	return q + acc / maxf(1.0, ws)


static func _q(p: Vector2) -> float:
	var u := p.x / 100.0
	var v := p.y / 100.0
	return Q[0] + Q[1] * u + Q[2] * v + Q[3] * u * u + Q[4] * u * v + Q[5] * v * v


static func _table(t: Array, x0: float, x: float) -> float:
	var f := clampf((x - x0) / 8.0, 0.0, t.size() - 1.0001)
	var i := int(f)
	return lerpf(t[i], t[i + 1], f - i)


## How far local p is from the flat zone round the station (0 in it).
static func flat_dist(p: Vector2) -> float:
	var q := st_from_local(p)
	var dr := Vector2(maxf(maxf(-45.0 - q.x, q.x - 47.6), 0.0), maxf(maxf(-28.4 - q.y, q.y - 31.4), 0.0)).length()
	var shops := PackedVector2Array(SHOPS)
	var ds := 0.0 if Geometry2D.is_point_in_polygon(q, shops) else _dist_outline(q, shops)
	return maxf(0.0, minf(dr, ds - 10.0))


## The ground as designed at local p: FLAT round the station, eased into the fitted surface (wholly on it within
## EDGE_FADE m of the perimeter: the map's ground there).
static func height(p: Vector2) -> float:
	var edge := minf(minf(p.y - kerb_b(p.x), EAST_EDGE.x + EAST_EDGE.y * p.y - p.x), minf(NORTH_B - p.y, p.x - WEST_A))
	var f := _ease(1.0 - flat_dist(p) / EASE) * _ease(edge / EDGE_FADE)
	if f >= 1.0:
		return FLAT
	return lerpf(fitted(p), FLAT, f)


## The TCSP kerb's b at a.
static func kerb_b(a: float) -> float:
	var k := KERB_S
	if a <= (k[0] as Vector2).x:
		return (k[0] as Vector2).y
	for i in k.size() - 1:
		var p: Vector2 = k[i]
		var q: Vector2 = k[i + 1]
		if a <= q.x:
			return lerpf(p.y, q.y, (a - p.x) / (q.x - p.x))
	return (k[k.size() - 1] as Vector2).y


## The terraforming (builder/terraform.gd, named by the lot): the perimeter on height(), eased back to the map's
## ground over BLEND m round it (not east of it: the avenue's sidewalk, kept as it is); a 1 m grid on the map.
static func terraform_zones() -> Array:
	var per := perimeter()
	var grown := offset(per, BLEND + 1.0, Geometry2D.JOIN_MITER)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in grown:
		var m := to_map(p)
		lo = lo.min(m)
		hi = hi.max(m)
	var x0 := floorf(lo.x)
	var y0 := ceilf(hi.y)
	var w := int(ceilf(hi.x - x0)) + 1
	var h := int(ceilf(y0 - lo.y)) + 1
	var wt := PackedByteArray()
	wt.resize(w * h)
	var sf := PackedFloat32Array()
	sf.resize(w * h)
	for j in h:
		for i in w:
			var p := to_local(Vector2(x0 + i + 0.5, y0 - j - 0.5))
			if Geometry2D.is_point_in_polygon(p, per):
				wt[j * w + i] = 255
			elif Geometry2D.is_point_in_polygon(p, grown) and p.x < EAST_EDGE.x + EAST_EDGE.y * p.y - 0.5:
				wt[j * w + i] = roundi(_ease(1.0 - _dist_outline(p, per) / BLEND) * 255.0)
			else:
				continue
			sf[j * w + i] = height(p)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


# ---------------------------------------------------------------- the grounds' shapes (grid)

## The perimeter: from the TCSP's kerb to the Danone road's verge, from the west edge to the avenue's sidewalk; the
## west street up to the Danone road.
static func perimeter() -> PackedVector2Array:
	if not _cache.has("perimeter"):
		var p := PackedVector2Array([Vector2(WEST_A, kerb_b(WEST_A))])
		for q: Vector2 in KERB_S:
			if q.x > WEST_A and q.x < 73.4:
				p.append(q)
		var ae := func(b: float) -> float: return EAST_EDGE.x + EAST_EDGE.y * b
		p.append(Vector2(73.5, -8.34))
		var sx: float = STREET.position.x - STREET_WALK
		var ex: float = STREET.end.x + STREET_WALK
		p.append_array([Vector2(ae.call(NORTH_B), NORTH_B), Vector2(ex, NORTH_B), Vector2(ex, STREET.end.y),
				Vector2(sx, STREET.end.y), Vector2(sx, NORTH_B), Vector2(WEST_A, NORTH_B)])
		_cache["perimeter"] = p
	return _cache["perimeter"]


## The perimeter on the map.
static func perimeter_map() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in perimeter():
		out.append(to_map(p))
	return out


## Whether local p is in the perimeter.
static func in_perimeter(p: Vector2) -> bool:
	return inside(p, perimeter())


## The TCSP's side of its kerb: the kerb closed round the road, far south.
static func tcsp_side() -> PackedVector2Array:
	if not _cache.has("tcsp"):
		var s := PackedVector2Array(KERB_S)
		s.append_array([Vector2(90.0, -60.0), Vector2(-100.0, -60.0), Vector2(-100.0, -3.96)])
		_cache["tcsp"] = s
	return _cache["tcsp"]


## The TCSP and o m round it (o m in from its kerb).
static func within(o: float) -> PackedVector2Array:
	var key := "within %s" % o
	if not _cache.has(key):
		_cache[key] = tcsp_side() if o <= 0.0 else offset(tcsp_side(), o)
	return _cache[key]


## A disc round the turning circle's centre.
static func disc(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 48:
		out.append(Vector2(CIRCLE.x, CIRCLE.y) + Vector2.from_angle(TAU * i / 48.0) * r)
	return out


## The west street's asphalt: the street and its turning circle (one polygon; its island drawn over it).
static func road() -> PackedVector2Array:
	if not _cache.has("road"):
		var dc := disc(CIRCLE.z)
		var r := STREET
		var rect := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		_cache["road"] = largest(Geometry2D.merge_polygons(rect, dc))
	return _cache["road"]


static func in_road(p: Vector2) -> bool:
	return inside(p, road())


## The road's kerb: its outline but the north end (it goes on into the Danone road), as segments [a, b] (the road on
## their right going a -> b... whichever: the builder looks).
static func road_kerb() -> Array:
	var out := []
	var r := road()
	for i in r.size():
		var a := r[i]
		var b := r[(i + 1) % r.size()]
		if a.y > STREET.end.y - 0.01 and b.y > STREET.end.y - 0.01:
			continue
		out.append([a, b])
	var island := disc(ISLAND)
	for i in island.size():
		out.append([island[i], island[(i + 1) % island.size()]])
	return out


## The pedestrian and cycle surfaces, KERB high: [[polygon, material], ...].
static func surfaces() -> Array:
	if not _cache.has("surfaces"):
		var out := []
		var per := [perimeter()]
		var taken := [outline(), road()]
		for p in subtract(intersect(per, [within(STRIP.x)]), [tcsp_side()]):
			out.append([p, "kerb_top"])
		var strip := subtract(intersect(per, [within(STRIP.y)]), [within(STRIP.x)])
		for o: Vector2 in OPENINGS:
			for p in intersect(strip, [_slab_a(o.x, o.y)]):
				out.append([p, "l18p_parvis"])
		for p in subtract(intersect(per, [within(CYCLE.y)]), [within(CYCLE.x)]):
			out.append([p, "street_asphalt"])
		var east := _slab_a(FORECOURT.end.x, 90.0)
		for p in subtract(intersect(intersect(per, [within(WALK)]), [east]), [within(CYCLE.y)]):
			out.append([p, "street_pavers"])
		var paved := []
		paved.append(disc(CIRCLE.z + STREET_WALK))
		paved.append(_rect(FORECOURT))
		paved.append(_rect(ESPLANADE))
		paved.append(_rect(EAST_PATH))
		paved.append(_rect(NORTH_PATH))
		paved.append(_rect(Rect2(STREET.position.x - STREET_WALK, STREET.position.y, STREET.size.x + 2.0 * STREET_WALK,
				STREET.size.y)))
		var beds := []
		for r: Rect2 in BEDS + PLANTERS:
			beds.append(_rect(r))
		var prev := []                                       # (each rectangle without the ones before: no overlaps)
		for q in paved:
			for p in subtract(intersect(per, [q]), [within(CYCLE.y)] + taken + beds + prev):
				out.append([p, "l18p_parvis"])
			prev.append(q)
		out.append([disc(ISLAND), "street_setts"])
		_cache["surfaces"] = out
	return _cache["surfaces"]


## Whether local p is on a surface (paved, the cycle track, the kerb's top).
static func paved(p: Vector2) -> bool:
	for e: Array in surfaces():
		if inside(p, e[0]):
			return true
	return false


## A surface's top over the ground at p: KERB, lowered to LOW at the crossings' kerbs, eased back over RAMP.
static func lift(p: Vector2) -> float:
	var h := KERB
	for g: PackedVector2Array in gap_lines():
		var d := _dist_line(p, g)
		if d < RAMP:
			h = minf(h, lerpf(LOW, KERB, _ease(d / RAMP)))
	return h


## The crossings' kerbs (polylines): the TCSP's zebras, the west street's.
static func gap_lines() -> Array:
	if not _cache.has("gaps"):
		var out := []
		for z: Vector2 in ZEBRAS:
			var line := PackedVector2Array()
			for i in 5:
				var a := lerpf(z.x, z.y, i / 4.0)
				line.append(Vector2(a, kerb_b(a)))
			out.append(line)
		for a: float in [STREET.position.x, STREET.end.x]:
			out.append(PackedVector2Array([Vector2(a, STREET_ZEBRA.x), Vector2(a, STREET_ZEBRA.y)]))
		_cache["gaps"] = out
	return _cache["gaps"]


## Where surfaces slope (cut fine there): round the gaps.
static func ramp_zones() -> Array:
	if not _cache.has("ramps"):
		var out := []
		for g: PackedVector2Array in gap_lines():
			out.append(offset(g, RAMP + 0.1, Geometry2D.JOIN_ROUND, true))
		_cache["ramps"] = out
	return _cache["ramps"]


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## A slab across the bands from a0 to a1.
static func _slab_a(a0: float, a1: float) -> PackedVector2Array:
	return _rect(Rect2(a0, -40.0, a1 - a0, 200.0))



# ---------------------------------------------------------------- the viaduct's piers

## The piers' footprints near (map polygons): [shafts' rectangle, the same grown by PIER_CLEAR].
static func pier_footprints() -> Array:
	if not _cache.has("piers"):
		var out := []
		var c0 := Line.station_to_map(ID, 0.0, 0.0)
		for pr: Dictionary in Line.piers():
			var c := Vector2(pr["x"], pr["y"])
			if c.distance_to(c0) > 220.0 or str(pr["type"]) == "abutment":
				continue
			var half := Vector2(1.4, 2.3 if str(pr["type"]) == "double" else 0.75)
			out.append([_box(c, float(pr["heading"]), half), _box(c, float(pr["heading"]), half + Vector2.ONE * PIER_CLEAR),
					float(pr["s"])])
		_cache["piers"] = out
	return _cache["piers"]


static func _box(c: Vector2, h: float, half: Vector2) -> PackedVector2Array:
	var d := Vector2.from_angle(h)
	var n := Vector2(-d.y, d.x)
	return PackedVector2Array([c - d * half.x - n * half.y, c + d * half.x - n * half.y, c + d * half.x + n * half.y,
			c - d * half.x + n * half.y])


## Whether the map's point m is on a pier's footprint (`clear`: with PIER_CLEAR round it).
static func on_pier(m: Vector2, clear := true) -> bool:
	for f: Array in pier_footprints():
		if Geometry2D.is_point_in_polygon(m, f[1] if clear else f[0]):
			return true
	return false


## Whether a tree may stand at local p: off the axis (TREE_V), the piers, the station, the roads, the surfaces.
static func tree_ok(p: Vector2) -> bool:
	var m := to_map(p)
	var sv := Line.project(m)
	if not is_nan(sv.y) and absf(sv.y) < TREE_V:
		return false
	return in_perimeter(p) and not on_pier(m) and not in_station(p) and not in_road(p)


# ---------------------------------------------------------------- trees, furniture

## The trees: [local point, archetype, height, tint].
static func trees() -> Array:
	if _cache.has("trees"):
		return _cache["trees"]
	var out := []
	var mid := (STRIP.x + STRIP.y) * 0.5
	var a := WEST_A + 3.0
	while a < 70.0:                                          # the strip along the TCSP
		var open := false
		for o: Vector2 in OPENINGS:
			open = open or (a > o.x - 2.0 and a < o.y + 2.0)
		var p := Vector2(a, kerb_b(a) + mid)
		if not open and tree_ok(p):
			out.append([p, "round", 9.0, "leaf"])
		a += 8.0
	for r: Rect2 in BEDS:                                    # the forecourt's beds
		for t: float in [0.27, 0.73]:
			out.append([Vector2(r.position.x + r.size.x * t, r.get_center().y), "oval", 9.5, "deep"])
	out.append([PLANTERS[0].get_center(), "round", 7.0, "copper"])     # the jacaranda before the doors
	out.append([PLANTERS[1].get_center(), "oval", 8.5, "spring"])
	for b in range(16, 96, 11):                              # the east lawn: an orchard of rows
		for ea in range(30, 70, 9):
			var p := Vector2(float(ea) + (3.0 if int(b / 11.0) % 2 == 1 else 0.0), float(b))
			if tree_ok(p) and not paved(p) and p.x < EAST_EDGE.x + EAST_EDGE.y * p.y - 3.0 and p.y < EAST_PATH.position.y - 3.0:
				out.append([p, ["round", "oval", "columnar"][(b + ea) % 3], 8.0 + float((b * 7 + ea) % 5) * 0.6, "leaf"])
	for na in range(-58, -4, 9):                             # a row along the north path
		var p := Vector2(float(na), NORTH_PATH.position.y - 2.5)
		if tree_ok(p):
			out.append([p, "oval", 9.0, "spring"])
	for nb in range(36, 114, 9):                             # the west verge
		var p := Vector2(WEST_A + 2.5, float(nb))
		if tree_ok(p):
			out.append([p, "round", 8.5, "leaf"])
	for p: Vector2 in [Vector2(-50.0, 70.0), Vector2(-40.0, 80.0), Vector2(-30.0, 88.0), Vector2(-55.0, 92.0),
			Vector2(-42.0, 98.0), Vector2(-20.0, 97.0)]:          # a grove on the north lawn
		if tree_ok(p) and not paved(p):
			out.append([p, "round", 8.0, "deep"])
	for p: Vector2 in [Vector2(40.0, 62.0), Vector2(40.0, 76.0), Vector2(42.0, 96.5), Vector2(50.0, 96.5),
			Vector2(58.0, 96.5), Vector2(66.0, 96.5)]:              # by the esplanade, along its path to the avenue
		if tree_ok(p) and not paved(p):
			out.append([p, "columnar", 8.5, "spring"])
	_cache["trees"] = out
	return out


## The street furniture: [model, local point, yaw (map degrees: where a lamp's arm reaches, a bench looks)].
static func props() -> Array:
	if _cache.has("props"):
		return _cache["props"]
	var out := []
	var mid := (STRIP.x + STRIP.y) * 0.5
	var south := yaw(Vector2(0.0, -1.0))
	var a := WEST_A + 7.0
	while a < 70.0:                                          # street lamps along the TCSP, between the trees
		var p := Vector2(a, kerb_b(a) + mid)
		if _prop_ok(p):
			out.append(["lamp_street", p, south])
		a += 24.0
	for b in range(32, 118, 22):                             # along the west street, both sides
		out.append(["lamp_street", Vector2(STREET.position.x - 0.6, float(b)), yaw(Vector2(1.0, 0.0))])
		out.append(["lamp_street", Vector2(STREET.end.x + 0.6, float(b) + 11.0), yaw(Vector2(-1.0, 0.0))])
	for p: Vector2 in [Vector2(-60.0, 22.0), Vector2(-40.0, 20.0), Vector2(-15.0, 18.0), Vector2(10.0, 18.0),
			Vector2(22.0, 32.0), Vector2(-30.0, 40.0), Vector2(-55.0, 48.0), Vector2(8.0, 62.0), Vector2(26.0, 90.0),
			Vector2(40.0, 102.0), Vector2(62.0, 102.0), Vector2(-50.0, 107.5), Vector2(-30.0, 107.5), Vector2(-10.0, 107.5)]:
		if _prop_ok(p):                                      # path lamps on the forecourt, the esplanade, the paths
			out.append(["lamp_path", p, 0.0])
	for r: Rect2 in BEDS:                                    # benches along the beds' north sides, a bin by each
		for t: float in [0.3, 0.7]:
			out.append(["bench_back", Vector2(r.position.x + r.size.x * t, r.end.y + 0.7), yaw(Vector2(0.0, 1.0))])
		out.append(["bin_vigipirate", Vector2(r.end.x + 0.8, r.end.y + 0.6), 0.0])
	for r: Rect2 in PLANTERS:
		out.append(["bench_back", Vector2(r.get_center().x, r.position.y - 0.7), yaw(Vector2(0.0, -1.0))])
	for i in 10:                                             # bike racks east of the shops, on the esplanade
		out.append(["bike_rack", Vector2(19.0, 36.0 + 1.6 * i), yaw(Vector2(1.0, 0.0))])
		out.append(["bike_rack", Vector2(22.5, 36.0 + 1.6 * i), yaw(Vector2(-1.0, 0.0))])
	for i in 8:
		var p := Vector2(28.0, 66.0 + 1.6 * i)
		if _prop_ok(p):
			out.append(["bike_rack", p, yaw(Vector2(1.0, 0.0))])
	for p: Vector2 in [Vector2(-18.0, 30.0), Vector2(14.0, 28.0), Vector2(20.0, 84.0), Vector2(-64.0, 30.0)]:
		if _prop_ok(p):
			out.append(["bin_vigipirate", p, 0.0])
	var o: Vector2 = OPENINGS[0]                             # bollards across the forecourt's opening
	a = o.x + 0.8
	while a < o.y:
		out.append(["bollard", Vector2(a, kerb_b(a) + STRIP.y - 0.4), 0.0])
		a += 1.8
	_cache["props"] = out.filter(func(e: Array) -> bool:
		return _prop_ok(e[1]) and (not str(e[0]).begins_with("lamp") or off_deck(e[1])))
	return _cache["props"]


static func _prop_ok(p: Vector2) -> bool:
	return in_perimeter(p) and not in_station(p) and not in_road(p) and not on_pier(to_map(p))


## Whether local p is off the deck (TREE_V from the axis): a lamp or a tree may stand there.
static func off_deck(p: Vector2) -> bool:
	var sv := Line.project(to_map(p))
	return is_nan(sv.y) or absf(sv.y) >= TREE_V


## A local direction's yaw (map degrees: 0 east, 90 north).
static func yaw(d: Vector2) -> float:
	var m := d.rotated(ANGLE)
	return fposmod(rad_to_deg(atan2(m.y, m.x)), 360.0)


# ---------------------------------------------------------------- polygon tools (as haignere_plan.gd's)

## a's pieces within every polygon of b (subtract(): out of all of them).
static func intersect(a: Array, b: Array) -> Array:
	var out := []
	for p: PackedVector2Array in a:
		var pieces := [p]
		for q: PackedVector2Array in b:
			var next := []
			for r: PackedVector2Array in pieces:
				next.append_array(_outer(Geometry2D.intersect_polygons(r, q)))
			pieces = next
		out.append_array(pieces)
	return out


static func subtract(a: Array, b: Array) -> Array:
	var out := []
	for p: PackedVector2Array in a:
		var pieces := [p]
		for q: PackedVector2Array in b:
			var next := []
			for r: PackedVector2Array in pieces:
				next.append_array(_clip(r, q))
			pieces = next
		out.append_array(pieces)
	return out


## r without q; where q falls inside r (a hole), r cut in two across q's middle first (no holes: one outline each).
static func _clip(r: PackedVector2Array, q: PackedVector2Array) -> Array:
	var res := Geometry2D.clip_polygons(r, q)
	var cw := 0
	for p: PackedVector2Array in res:
		cw += 1 if Geometry2D.is_polygon_clockwise(p) else 0
	if cw == 0 or cw == res.size():
		return _outer(res)
	var c := bounds(q).get_center().x
	var out := []
	for half: PackedVector2Array in [_rect(Rect2(c - 1000.0, -1000.0, 1000.0, 2000.0)), _rect(Rect2(c, -1000.0, 1000.0, 2000.0))]:
		for piece: PackedVector2Array in _outer(Geometry2D.intersect_polygons(r, half)):
			out.append_array(_outer(Geometry2D.clip_polygons(piece, q)))
	return out


## The pieces of a boolean's result that are not holes (a hole: its piece kept whole, the hole filled) nor slivers.
static func _outer(polys: Array) -> Array:
	var out := []
	var cw := 0
	var ccw := 0
	for p: PackedVector2Array in polys:
		if Geometry2D.is_polygon_clockwise(p):
			cw += 1
		else:
			ccw += 1
	for p: PackedVector2Array in polys:
		if polys.size() > 1 and Geometry2D.is_polygon_clockwise(p) != (ccw < cw):
			continue
		if _area(p) > 0.05:
			out.append(p)
	return out


## Polygon (or `line`: polyline) `poly` grown by d m (shrunk if d < 0), the largest piece.
static func offset(poly: PackedVector2Array, d: float, join := Geometry2D.JOIN_ROUND, line := false) -> PackedVector2Array:
	var big := poly * Transform2D.IDENTITY.scaled(Vector2(FINE, FINE))
	var out: Array = Geometry2D.offset_polyline(big, d * FINE, join, Geometry2D.END_ROUND) if line else \
			Geometry2D.offset_polygon(big, d * FINE, join)
	return largest(out) * Transform2D.IDENTITY.scaled(Vector2(1.0 / FINE, 1.0 / FINE))


static func largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p: PackedVector2Array in polys:
		if _area(p) > _area(best):
			best = p
	return best


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## Whether p is in polygon `poly` (its box first: cached).
static func inside(p: Vector2, poly: PackedVector2Array) -> bool:
	var key := poly.size() * 7919 + int(poly[0].x * 100.0) * 31 + int(poly[0].y * 100.0)
	if not _cache.has(key):
		_cache[key] = bounds(poly)
	return (_cache[key] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, poly)


static func _dist_line(p: Vector2, line: PackedVector2Array) -> float:
	var d := INF
	for i in line.size() - 1:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return d


static func _dist_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for i in poly.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return d


static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
