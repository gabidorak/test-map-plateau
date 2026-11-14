extends RefCounted
## The plan of Université Paris-Saclay's station (ex Orsay-Gif, plateau de Moulon) and its grounds, lot
## ligne18-universite (lots/ligne18-universite/lot.json, a child of ligne18): one source for its terraforming, its
## drop, its paint and its builders (universite.gd, station_builder.gd, grounds_builder.gd). Drawn in the station's
## frame (the line's plan: lots/ligne18/ligne18_plan.gd, station "universite"): u along the line (westwards, towards
## Versailles), v to its left (southwards), from the axis at the station's centre; heights are the map's z (frame():
## the station's frame at z 0; the station's own node sits at its hall's level, station_transform()).
## - the station (station_builder.gd): its socle (SOCLE: 64 m by 32 m, the hall at hall_z under the deck, the rooms on
##   either side), the passerelle at passerelle_z, the platforms at platform_z (u -30..30, edge at |v| 4.00), the folded
##   glass envelope and its roof (72 m by 40.6 m at the top, roof_max_z), the deck over the zone (u -45..45, its top at
##   deck_top_z, the line's section at its ends), its piers and the supports at u +-45 the viaduct's spans rest on;
## - the grounds, up to and including the roads round it (PERIMETER): rue Sophie Germain to the west (its carriageway,
##   SG_ROAD), the TCSP to the south (its carriageway, TCSP_ROAD, and the stop « Université Paris-Saclay » on its south
##   side, PLATFORM), rue Nicolas Appert to the east (its west kerb: the junction kept); north, the grounds stop at
##   NORTH (the construction site beyond). On the block's side of the kerbs (block()): along the TCSP the kerb, a
##   strip with the lamps, the two-way cycle track and the sidewalk; along the two streets a sidewalk; the forecourts
##   (west and east under the viaduct, south, north under the envelope), the promenade under the viaduct to rue Nicolas
##   Appert and a path across the north-east lawn; mown lawns, trees in rows (none within TREE_CLEAR m of the axis nor
##   on the viaduct's piers' footprints), lamps, benches, bins, bike racks;
## - the ground (height()): flat at the doors (hall_z - KERB under the paving: its top at hall_z), easing to the roads'
##   levels at the kerbs (the TCSP regraded flatter along the station: TCSP_Z), terraformed so (terraform_zones()),
##   eased back to the map's ground round the perimeter over BLEND m.

const L18 = preload("res://lots/ligne18/ligne18_plan.gd")
const ID := "universite"

const KERB := 0.15                          # m: sidewalks, forecourts over the designed ground (the street kit's KERB)
const LOW := 0.055                          # m: lowered at a crossing (the kit's LOW)
const RAMP := 1.5                           # m over which a crossing's lowering runs
const BLEND := 3.0                          # m over which the terraformed ground eases back to the map's
const FINE := 10.0                          # the polygon offsets worked at this scale (offset())
const TREE_CLEAR := 9.0                     # m off the axis: no tree nearer (the line wants 7)
const PIER_MARGIN := 1.0                    # m round a pier's shafts kept clear

# ---------------------------------------------------------------- the station
const SOCLE := Rect2(-32.0, -16.0, 64.0, 32.0)      # the building at the ground (u, v)
const HALL_V := 8.5                         # the hall under the deck and the platforms: |v| <= HALL_V
const ROOF_U := 36.0                        # the envelope at the top: |u| <= ROOF_U
const ROOF_V := 20.3                        # its folds' outer tips (17.4 inner)
const DOORS := [Rect2(30.0, -5.0, 4.0, 10.0), Rect2(-34.0, -5.0, 4.0, 10.0), Rect2(-3.0, 14.0, 6.0, 4.0)]
## Its supports: the end ones (u = +-45: a cross-beam on two shafts, the viaduct's first spans rest on it), the station's
## single piers under its deck (u = +-15, in the hall).
const END_U := 45.0
const PIER_U := 15.0

# ---------------------------------------------------------------- the roads (station frame), from the map's
## Rue Sophie Germain's east kerb: u = SG_U0 + SG_DU v (its carriageway SG_W m wide westwards).
const SG_U0 := 60.53
const SG_DU := 0.0094
const SG_W := 6.0
## The TCSP's north kerb: v = T_V0 + T_DV u (straight from rue Sophie Germain to u -92), then round to rue Nicolas
## Appert (T_CURVE, the map's road edge); its carriageway TCSP_W m wide southwards.
const T_V0 := 28.91
const T_DV := -0.005
const TCSP_W := 7.05
const T_CURVE := [Vector2(-92.0, 29.37), Vector2(-100.0, 28.56), Vector2(-108.0, 27.3), Vector2(-114.0, 25.6),
	Vector2(-118.0, 24.0), Vector2(-121.5, 22.6), Vector2(-124.2, 20.8), Vector2(-126.0, 19.0), Vector2(-127.0, 17.4)]
## Rue Nicolas Appert's west kerb: u = NA_U0 + NA_DU v (from the junction north).
const NA_U0 := -120.58
const NA_DU := -0.4315
const NA_JOIN := 16.0                       # v where the TCSP's curve meets it
const NORTH := -33.0                        # v: the grounds' north edge
const NW := Vector2(57.0, -33.0)            # where the north edge turns to rue Sophie Germain's kerb at v SG_FROM
const SG_FROM := -28.0                      # v: rue Sophie Germain redone from here south
const SG_FAR := [Vector2(66.23, -28.0), Vector2(66.88, 24.0), Vector2(66.9, 28.65)]   # its west kerb (kept)
const TCSP_END := -100.0                    # u: the TCSP redone from rue Sophie Germain to here
const TCSP_FAR := [Vector2(66.9, 35.6), Vector2(40.3, 35.73), Vector2(-0.5, 35.97), Vector2(-100.0, 35.67)]  # its south kerb
## The stop « Université Paris-Saclay » on the TCSP's south side (eastbound): its platform, from its kerb to the bank.
const PLATFORM := [Vector2(40.3, 35.73), Vector2(40.3, 39.2), Vector2(-0.5, 39.2), Vector2(-0.5, 35.97)]

## The roads' levels at their kerbs (the map's, fitted): rue Sophie Germain z(v) = SG_Z . (1, v, v²); rue Nicolas
## Appert z(v) = NA_Z . (1, v); the north edge (the map's ground) z(u) = N_Z . (1, u, u², u³). The TCSP regraded
## (TCSP_Z: (u, z) knots, the map's at its ends): flatter along the station (0.4 % instead of 1 %), the map's beyond.
const SG_Z := [-3.93864, -0.0156882, 7.891e-6]
const NA_Z := [-6.67135, 0.0067857]
const N_Z := [-4.15573, 0.0155544, -4.42312e-5, 2.53504e-7]
const TCSP_Z := [Vector2(66.9, -4.30), Vector2(40.0, -4.81), Vector2(-40.0, -5.13), Vector2(-100.0, -5.95),
	Vector2(-118.0, -6.15), Vector2(-128.0, -6.55)]
## The ground flat (at hall_z - KERB) round the building, |u| <= FLAT.x, v in FLAT_V; eased to the roads' levels at
## the kerbs and to the map's at the north edge.
const FLAT := 36.0
const FLAT_V := Vector2(-17.0, 18.0)

# ---------------------------------------------------------------- the grounds (station frame)
## The bands along the kerbs, m in from the kerb: along the TCSP the kerb's top, the strip (lamps), the two-way cycle
## track, the sidewalk; along the two streets the kerb's top and the sidewalk.
const T_STRIP := Vector2(0.15, 1.0)
const T_CYCLE := Vector2(1.0, 3.6)
const T_WALK := 6.6
const S_WALK := 3.5
## Paved at KERB: the forecourts, the promenade, the paths ([rect or polygon, material]).
const WEST_PLAZA := Rect2(32.0, -21.5, 29.0, 44.5)
const EAST_PLAZA := Rect2(-60.0, -21.5, 28.0, 44.5)
const SOUTH_FORE := Rect2(-32.0, 16.0, 64.0, 7.0)
const NORTH_WALK := Rect2(-32.0, -21.5, 64.0, 5.5)
const PROMENADE := Rect2(-130.0, 6.0, 70.0, 4.5)        # under the viaduct's south edge, to rue Nicolas Appert's zebra
const NE_PATH := [Vector2(-58.0, -15.0), Vector2(-110.0, -27.0)]   # a path across the north-east lawn (3 m)
const NE_PATH_W := 3.0
## The crossings where the kerb is lowered (their ends, on the kerb): rue Sophie Germain's zebra, the cycle track's
## crossing of it, the TCSP's zebra to the island, the zebras at rue Nicolas Appert's junction (across the TCSP and
## across the street, where the promenade and the cycle track end).
const GAPS := [[Vector2(60.6, 7.4), Vector2(60.6, 11.0)], [Vector2(60.8, 25.2), Vector2(60.8, 27.95)],
	[Vector2(42.4, 28.7), Vector2(46.0, 28.7)], [Vector2(-121.8, 22.4), Vector2(-125.0, 20.0)],
	[Vector2(-125.2, 10.2), Vector2(-126.4, 12.9)]]
## The platform's kerb is a bus stop's (its top KERB too; lowered nowhere).

static var _cache := {}


# ---------------------------------------------------------------- the frames

## The station's frame at z 0 (Godot local (u, z, -v)): the grounds' node's.
static func frame() -> Transform3D:
	var t := L18.station_transform(ID)
	t.origin.y = 0.0
	return t


## The station's frame at its hall's level (Godot local (u, z - hall_z, -v)): the station's node's.
static func station_frame() -> Transform3D:
	return L18.station_transform(ID)


## A level of the station (map z): hall_z, passerelle_z, rail_z, deck_top_z, platform_z, roof_max_z.
static func level(key: String) -> float:
	return float(L18.station(ID)["levels"][key])


static func to_map(p: Vector2) -> Vector2:
	return L18.station_to_map(ID, p.x, p.y)


static func to_local(m: Vector2) -> Vector2:
	return L18.station_from_map(ID, m)


## A map direction's yaw (degrees: 0 east, 90 north) of local direction d.
static func yaw(d: Vector2) -> float:
	var m := to_map(d) - to_map(Vector2.ZERO)
	return fposmod(rad_to_deg(atan2(m.y, m.x)), 360.0)


# ---------------------------------------------------------------- the kerbs

## Rue Sophie Germain's east kerb's u at v.
static func sg_u(v: float) -> float:
	return SG_U0 + SG_DU * v


## Rue Nicolas Appert's west kerb's u at v.
static func na_u(v: float) -> float:
	return NA_U0 + NA_DU * v


## The TCSP's north kerb's v at u (on its straight part).
static func t_v(u: float) -> float:
	return T_V0 + T_DV * u


## The corner where rue Sophie Germain's kerb meets the TCSP's.
static func sw_corner() -> Vector2:
	var v := (T_V0 + T_DV * SG_U0) / (1.0 - T_DV * SG_DU)
	return Vector2(sg_u(v), v)


## The TCSP's north kerb, from rue Sophie Germain to rue Nicolas Appert's kerb.
static func kerb_t() -> PackedVector2Array:
	var k := PackedVector2Array([sw_corner()])
	k.append_array(PackedVector2Array(T_CURVE))
	k.append(Vector2(na_u(NA_JOIN), NA_JOIN))
	return k


static func kerb_sg() -> PackedVector2Array:
	return PackedVector2Array([Vector2(sg_u(SG_FROM), SG_FROM), sw_corner()])


static func kerb_na() -> PackedVector2Array:
	return PackedVector2Array([Vector2(na_u(NA_JOIN), NA_JOIN), Vector2(na_u(NORTH), NORTH)])


## The kerb all round the block: rue Sophie Germain's (north to south), the TCSP's (west to east), rue Nicolas
## Appert's (south to north).
static func kerb_line() -> PackedVector2Array:
	if not _cache.has("kerb_line"):
		var k := kerb_sg()
		var t := kerb_t()
		k.append_array(t.slice(1))
		k.append(Vector2(na_u(NORTH), NORTH))
		_cache["kerb_line"] = k
	return (_cache["kerb_line"] as PackedVector2Array).duplicate()


## The block: the station's side of the kerbs, up to the north edge.
static func block() -> PackedVector2Array:
	if not _cache.has("block"):
		var b := kerb_line()
		b.append(NW)
		_cache["block"] = b
	return _cache["block"]


## Rue Sophie Germain's carriageway, from SG_FROM to the TCSP.
static func sg_road() -> PackedVector2Array:
	var c := sw_corner()
	return PackedVector2Array([Vector2(sg_u(SG_FROM), SG_FROM), SG_FAR[0], SG_FAR[1], SG_FAR[2], c])


## The TCSP's carriageway, from rue Sophie Germain's far kerb to TCSP_END.
static func tcsp_road() -> PackedVector2Array:
	var r := PackedVector2Array([SG_FAR[2]])
	r.append_array(PackedVector2Array(TCSP_FAR))
	r.append_array(PackedVector2Array([T_CURVE[1], T_CURVE[0], sw_corner()]))
	return r


## What the lot redoes: the block, the two carriageways, the stop's platform.
static func perimeter() -> PackedVector2Array:
	if not _cache.has("perimeter"):
		var p := PackedVector2Array([Vector2(sg_u(SG_FROM), SG_FROM)])
		p.append_array(PackedVector2Array(SG_FAR))
		p.append_array(PackedVector2Array([TCSP_FAR[0], PLATFORM[0], PLATFORM[1], PLATFORM[2], PLATFORM[3], TCSP_FAR[3]]))
		p.append_array(PackedVector2Array(T_CURVE.slice(1)))
		p.append(Vector2(na_u(NA_JOIN), NA_JOIN))
		p.append(Vector2(na_u(NORTH), NORTH))
		p.append(NW)
		_cache["perimeter"] = p
	return _cache["perimeter"]


## The perimeter on the map (x, y).
static func perimeter_map() -> PackedVector2Array:
	if not _cache.has("perimeter_map"):
		var out := PackedVector2Array()
		for q in perimeter():
			out.append(to_map(q))
		_cache["perimeter_map"] = out
	return _cache["perimeter_map"]


# ---------------------------------------------------------------- the ground

## The ground as designed at local p (map z): on the carriageways their levels, in the block flat round the building
## (hall_z - KERB) eased to the kerbs' levels and the north edge's.
static func height(p: Vector2) -> float:
	if p.x < sg_u(p.y) and p.x > TCSP_END - 0.5 and p.y >= t_v(p.x):
		return tcsp_z(p.x)                                   # (the TCSP, its platform)
	if p.x >= sg_u(p.y) - 0.001:
		return tcsp_z(p.x) if p.y >= t_v(p.x) else sg_z(p.y)   # (rue Sophie Germain, the junction the TCSP's)
	var flat := level("hall_z") - KERB
	var f := _flat_weight(p)
	if f >= 1.0:
		return flat
	return lerpf(_ring(p), flat, f)


## The TCSP's level at u (regraded: TCSP_Z).
static func tcsp_z(u: float) -> float:
	var k := TCSP_Z
	if u >= (k[0] as Vector2).x:
		return (k[0] as Vector2).y + 0.019 * (u - (k[0] as Vector2).x)
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		if u <= a.x and u >= b.x:
			return lerpf(a.y, b.y, (a.x - u) / (a.x - b.x))
	var l: Vector2 = k[k.size() - 1]
	return l.y - 0.04 * (l.x - u)


static func sg_z(v: float) -> float:
	return SG_Z[0] + SG_Z[1] * v + SG_Z[2] * v * v


static func na_z(v: float) -> float:
	return NA_Z[0] + NA_Z[1] * v


static func north_z(u: float) -> float:
	return N_Z[0] + N_Z[1] * u + N_Z[2] * u * u + N_Z[3] * u * u * u


## How flat the ground is at p (1 round the building, 0 at the kerbs and the north edge).
static func _flat_weight(p: Vector2) -> float:
	var fu := 1.0
	if p.x > FLAT:
		fu = _ease(1.0 - (p.x - FLAT) / maxf(sg_u(p.y) - FLAT, 1.0))
	elif p.x < -FLAT:
		fu = _ease(1.0 - (-FLAT - p.x) / maxf(-FLAT - na_u(minf(p.y, NA_JOIN)), 1.0))
	var fv := 1.0
	if p.y > FLAT_V.y:
		fv = _ease(1.0 - (p.y - FLAT_V.y) / maxf(_kerb_t_v(p.x) - FLAT_V.y, 1.0))
	elif p.y < FLAT_V.x:
		fv = _ease(1.0 - (FLAT_V.x - p.y) / (FLAT_V.x - NORTH))
	return fu * fv


## The TCSP's kerb's v at u (on its curve too).
static func _kerb_t_v(u: float) -> float:
	if u >= (T_CURVE[0] as Vector2).x:
		return t_v(u)
	for i in T_CURVE.size() - 1:
		var a: Vector2 = T_CURVE[i]
		var b: Vector2 = T_CURVE[i + 1]
		if u <= a.x and u >= b.x:
			return lerpf(a.y, b.y, (a.x - u) / (a.x - b.x))
	return NA_JOIN


## The ground away from the building: the kerbs' and the north edge's levels, each weighed by how near it is (1/d²).
static func _ring(p: Vector2) -> float:
	var sum := 0.0
	var wsum := 0.0
	var kt := kerb_t()
	var best := INF
	var zt := 0.0
	for i in kt.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, kt[i], kt[i + 1])
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			zt = tcsp_z(q.x)
	var edges := [[best, zt]]
	var vs := clampf(p.y, SG_FROM - 6.0, sw_corner().y)
	edges.append([pow(p.x - sg_u(vs), 2.0) + pow(p.y - vs, 2.0), sg_z(vs)])
	var vn := clampf(p.y, NORTH, NA_JOIN)
	edges.append([pow(p.x - na_u(vn), 2.0) + pow(p.y - vn, 2.0), na_z(vn)])
	var un := clampf(p.x, na_u(NORTH), NW.x + 3.0)
	edges.append([pow(p.x - un, 2.0) + pow(p.y - NORTH, 2.0), north_z(un)])
	for e: Array in edges:
		var w := 1.0 / (float(e[0]) + 0.01)
		sum += w * float(e[1])
		wsum += w
	return sum / wsum


## The ground's terraforming (builder/terraform.gd, named by the lot): the designed ground over the perimeter (and 1 m
## round it), eased back to the map's over BLEND m.
static func terraform_zones() -> Array:
	var l := perimeter_map()
	var grown := offset(l, 1.0 + BLEND)
	var box := bounds(grown)
	var x0 := floorf(box.position.x)
	var y0 := ceilf(box.end.y)
	var w := int(ceilf(box.end.x - x0)) + 1
	var h := int(ceilf(y0 - box.position.y)) + 1
	var wt := PackedByteArray()
	wt.resize(w * h)
	var sf := PackedFloat32Array()
	sf.resize(w * h)
	for j in h:
		for i in w:
			var p := Vector2(x0 + i + 0.5, y0 - j - 0.5)
			if not Geometry2D.is_point_in_polygon(p, grown):
				continue
			sf[j * w + i] = height(to_local(p))
			if Geometry2D.is_point_in_polygon(p, l):
				wt[j * w + i] = 255
			else:
				wt[j * w + i] = roundi(_ease(1.0 - (_dist_outline(p, l) - 1.0) / BLEND) * 255.0)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


# ---------------------------------------------------------------- the grounds' shapes (local)

## The roads' side of the kerb (the kerb line closed far round the roads): its offsets are the bands.
static func roads_side() -> PackedVector2Array:
	if not _cache.has("roads_side"):
		var r := kerb_line()
		r.append_array(PackedVector2Array([Vector2(-140.0, NORTH - 5.0), Vector2(-140.0, 60.0), Vector2(120.0, 60.0),
				Vector2(120.0, SG_FROM - 5.0), Vector2(sg_u(SG_FROM - 5.0), SG_FROM - 5.0)]))
		_cache["roads_side"] = r
	return _cache["roads_side"]


## The bands along a kerb line `k` (a polyline) from o0 to o1 m in from it, in the block.
static func _kerb_band(k: PackedVector2Array, o0: float, o1: float) -> Array:
	var outer := offset(k, o1, Geometry2D.JOIN_MITER, true, Geometry2D.END_BUTT)
	var inner := offset(k, o0, Geometry2D.JOIN_MITER, true, Geometry2D.END_BUTT) if o0 > 0.0 else PackedVector2Array()
	var a := intersect([block()], [outer])
	return subtract(a, [inner]) if o0 > 0.0 else a


## Everything paved in the block, KERB high: [[polygon, material], ...] (no two overlap).
static func paved() -> Array:
	if not _cache.has("paved"):
		var out := []
		var taken := []
		var add := func(polys: Array, m: String) -> void:
			for p: PackedVector2Array in subtract(polys, taken):
				out.append([p, m])
			taken.append_array(polys)
		var kt := kerb_t()
		var ks := kerb_sg()
		ks.append(ks[1] + Vector2(0.0, 0.5))                 # (to the corner's end)
		var kn := kerb_na()
		add.call(_kerb_band(kt, 0.0, T_STRIP.x), "kerb_top")
		add.call(_kerb_band(ks, 0.0, T_STRIP.x), "kerb_top")
		add.call(_kerb_band(kn, 0.0, T_STRIP.x), "kerb_top")
		add.call(_kerb_band(kt, T_STRIP.x, T_STRIP.y), "street_pavers")
		var cycle := _kerb_band(kt, T_CYCLE.x, T_CYCLE.y)
		_cache["cycle"] = subtract(cycle, taken)
		add.call(cycle, "street_asphalt")
		add.call(_kerb_band(kt, T_CYCLE.y, T_WALK), "street_pavers")
		add.call(_kerb_band(ks, T_STRIP.x, S_WALK), "street_pavers")
		add.call(_kerb_band(kn, T_STRIP.x, S_WALK), "street_pavers")
		var socle := [_rect(SOCLE)]
		taken.append_array(socle)
		var plazas := []
		for r: Rect2 in [WEST_PLAZA, EAST_PLAZA, SOUTH_FORE, NORTH_WALK]:
			plazas.append(_rect(r))
		add.call(intersect(plazas, [block()]), "l18_slabs")
		add.call(intersect([_rect(PROMENADE)], [block()]), "l18_slabs")
		var path := offset(PackedVector2Array(NE_PATH), NE_PATH_W * 0.5, Geometry2D.JOIN_ROUND, true, Geometry2D.END_BUTT)
		add.call(intersect([path], [block()]), "l18_slabs")
		_cache["paved"] = out
	return _cache["paved"]


## The two-way cycle track (polygons).
static func cycle() -> Array:
	paved()
	return _cache["cycle"]


## Whether local p is paved (the block's paving, the stop's platform), the hall's floor not.
static func is_paved(p: Vector2) -> bool:
	if inside(p, PackedVector2Array(PLATFORM)):
		return true
	for e: Array in paved():
		if inside(p, e[0]):
			return true
	return false


## Whether local p is on a lawn (the block, not paved, not the building).
static func is_lawn(p: Vector2) -> bool:
	return inside(p, block()) and not SOCLE.has_point(p) and not is_paved(p)


## A paved surface's top over the designed ground at p: KERB, lowered to LOW at the crossings' kerb (over RAMP).
static func lift(p: Vector2) -> float:
	var h := KERB
	for g: PackedVector2Array in gap_lines():
		var d := _dist_line(p, g)
		if d < RAMP:
			h = minf(h, lerpf(LOW, KERB, _ease(d / RAMP)))
	return h


## Where the tops slope (cut fine there): round the crossings.
static func ramp_zones() -> Array:
	if not _cache.has("ramps"):
		var out := []
		for g: PackedVector2Array in gap_lines():
			out.append(offset(g, RAMP + 0.1, Geometry2D.JOIN_ROUND, true))
		_cache["ramps"] = out
	return _cache["ramps"]


## The crossings' kerb: the kerb line between each crossing's ends.
static func gap_lines() -> Array:
	if not _cache.has("gaps"):
		var out := []
		for g: Array in GAPS:
			out.append(kerb_part(kerb_d(g[0]), kerb_d(g[1])))
		_cache["gaps"] = out
	return _cache["gaps"]


## The kerb line (kerb_line()) from d0 to d1 m along it.
static func kerb_part(d0: float, d1: float) -> PackedVector2Array:
	if d0 > d1:
		var t := d0
		d0 = d1
		d1 = t
	var line := PackedVector2Array()
	var run := 0.0
	var k := kerb_line()
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		var l := a.distance_to(b)
		var s0 := maxf(d0, run)
		var s1 := minf(d1, run + l)
		if s1 > s0 and l > 0.0:
			var p := a.lerp(b, (s0 - run) / l)
			if line.is_empty() or line[line.size() - 1].distance_to(p) > 0.001:
				line.append(p)
			line.append(a.lerp(b, (s1 - run) / l))
		run += l
	return line


## How far along the kerb line its point nearest p is.
static func kerb_d(p: Vector2) -> float:
	var best := INF
	var at := 0.0
	var run := 0.0
	var k := kerb_line()
	for i in k.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, k[i], k[i + 1])
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			at = run + k[i].distance_to(q)
		run += k[i].distance_to(k[i + 1])
	return at


## The kerb line's point d m along it, and its direction there.
static func kerb_at(d: float) -> Array:
	var run := 0.0
	var k := kerb_line()
	for i in k.size() - 1:
		var l := k[i].distance_to(k[i + 1])
		if d <= run + l or i == k.size() - 2:
			return [k[i].lerp(k[i + 1], clampf((d - run) / l, 0.0, 1.0)), (k[i + 1] - k[i]).normalized()]
		run += l
	return [k[0], Vector2.RIGHT]


# ---------------------------------------------------------------- the viaduct's piers

## The piers near the station: [local centre, half size along u, half size across] (their shafts' footprint).
static func piers() -> Array:
	if not _cache.has("piers"):
		var out := []
		for pr: Dictionary in L18.piers():
			var c := to_local(Vector2(pr["x"], pr["y"]))
			if absf(c.x) > 160.0 or absf(c.y) > 60.0:
				continue
			out.append([c, 1.4, 2.3 if str(pr["type"]) == "double" else 0.75, float(pr["s"])])
		_cache["piers"] = out
	return _cache["piers"]


## Whether local p is on a pier's footprint grown by `margin`.
static func on_pier(p: Vector2, margin := PIER_MARGIN) -> bool:
	for pr: Array in piers():
		var c: Vector2 = pr[0]
		if absf(p.x - c.x) <= float(pr[1]) + margin and absf(p.y - c.y) <= float(pr[2]) + margin:
			return true
	return false


# ---------------------------------------------------------------- trees and furniture

## The grounds' trees: [local point, archetype, height].
static func trees() -> Array:
	if not _cache.has("trees"):
		var out := []
		var add := func(p: Vector2, arch: String, h: float) -> void:
			if absf(p.y) >= TREE_CLEAR and not on_pier(p, PIER_MARGIN + 2.0) and inside(p, block()):
				out.append([p, arch, h])
		for u: float in [-31.5, -22.5, -13.5, 13.5, 22.5, 31.5]:          # birches along the south facade
			add.call(Vector2(u, 24.0), "columnar", 10.0)
		for u: float in [40.0, 47.5, 55.0]:                               # the west forecourt's grove
			for v: float in [-17.0, -11.0, 11.0, 17.0]:
				add.call(Vector2(u, v), "round", 9.5)
		for u: float in [-40.0, -47.5, -55.0]:                            # the east forecourt's
			for v: float in [-17.0, -11.0, 11.0, 17.0]:
				add.call(Vector2(u, v), "round", 9.5)
		var u := -66.0                                                    # along the promenade, on its south side
		while u > -118.0:
			add.call(Vector2(u, 14.0), "oval", 9.0)
			u -= 9.0
		u = -68.0                                                         # the north-east lawn, two loose rows
		while u > -104.0:
			add.call(Vector2(u, -11.5), "round", 8.5)
			add.call(Vector2(u - 4.5, -21.0 - 0.1 * (u + 68.0)), "round", 10.0)
			u -= 9.0
		u = 54.0                                                          # a row along the north edge
		while u > -64.0:
			add.call(Vector2(u, -27.5), "oval", 10.0)
			u -= 9.0
		for v: float in [-26.0, -16.0]:                                   # by rue Nicolas Appert's sidewalk
			add.call(Vector2(na_u(v) + S_WALK + 3.0, v), "round", 9.0)
		_cache["trees"] = out
	return _cache["trees"]


## The grounds' furniture: [model, local point, local direction it faces (a lamp: where its arm reaches)].
static func props() -> Array:
	if not _cache.has("props"):
		var out := []
		var add := func(m: String, p: Vector2, d: Vector2) -> void:
			if not on_pier(p) and (m != "lamp_street" or absf(p.y) > 7.0):
				out.append([m, p, d])
		var strip := (T_STRIP.x + T_STRIP.y) * 0.5
		for u: float in [52.0, 27.0, 2.0, -23.0, -48.0, -73.0, -98.0]:   # street lamps on the TCSP's strip
			add.call("lamp_street", Vector2(u, t_v(u) - strip), Vector2(0.0, 1.0))
		for v: float in [-24.0, -9.0, 15.0]:                              # along rue Sophie Germain
			add.call("lamp_street", Vector2(sg_u(v) - 0.6, v), Vector2(1.0, 0.0))
		for v: float in [-26.0, -6.0]:                                     # along rue Nicolas Appert
			add.call("lamp_street", Vector2(na_u(v) + 0.6, v), Vector2(-1.0, -NA_DU).normalized())
		for u: float in [-66.0, -78.0, -90.0, -102.0, -114.0]:            # the promenade's path lamps
			add.call("lamp_path", Vector2(u + 3.0, PROMENADE.end.y - 0.4), Vector2.ZERO)
		for u: float in [-27.0, -9.0, 9.0, 27.0]:                         # the north walk's
			add.call("lamp_path", Vector2(u, NORTH_WALK.position.y + 0.4), Vector2.ZERO)
		for u: float in [38.0, 58.0, -38.0, -58.0]:                       # the forecourts', clear of the deck
			add.call("lamp_path", Vector2(u, 7.5), Vector2.ZERO)
			add.call("lamp_path", Vector2(u, -7.5), Vector2.ZERO)
		for e: Array in [[43.75, 1.0], [51.25, 1.0], [-43.75, -1.0], [-51.25, -1.0]]:   # benches in the groves
			for v: float in [-14.0, 14.0]:
				var p := Vector2(e[0], v)
				add.call("bench_back", p, Vector2(-float(e[1]), 0.0))
			add.call("bin_vigipirate", Vector2(float(e[0]) + 1.6, 14.0), Vector2.ZERO)
		for u: float in [-27.0, -18.0, 18.0, 27.0]:                       # by the south facade, looking at the TCSP
			add.call("bench_back", Vector2(u, 22.0), Vector2(0.0, 1.0))
		add.call("bin_vigipirate", Vector2(-6.5, 22.2), Vector2.ZERO)
		add.call("bin_vigipirate", Vector2(6.5, 22.2), Vector2.ZERO)
		for u: float in [-70.5, -88.5, -106.5]:                           # along the promenade
			add.call("bench_back", Vector2(u, PROMENADE.end.y - 0.6), Vector2(0.0, -1.0))
			add.call("bin_vigipirate", Vector2(u + 1.8, PROMENADE.end.y - 0.5), Vector2.ZERO)
		for i in 7:                                                       # bike racks under the deck's edge
			for v: float in [-6.2, 6.2]:
				add.call("bike_rack", Vector2(49.0 + 1.2 * i, v), Vector2(0.0, -signf(v)))
				add.call("bike_rack", Vector2(-49.0 - 1.2 * i, v), Vector2(0.0, -signf(v)))
		_cache["props"] = out
	return _cache["props"]


# ---------------------------------------------------------------- polygon tools

static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


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
			if q.size() < 3:
				continue
			var next := []
			for r: PackedVector2Array in pieces:
				if not bounds(r).intersects(bounds(q)):
					next.append(r)
					continue
				next.append_array(_split_holes(Geometry2D.clip_polygons(r, q)))
			pieces = next
		out.append_array(pieces)
	return out


## A boolean's result without holes: an outline with a hole in it cut in two along a line through the hole (Godot's
## polygons have none); slivers out.
static func _split_holes(polys: Array) -> Array:
	var outs := []
	var holes := []
	for p: PackedVector2Array in polys:
		if Geometry2D.is_polygon_clockwise(p):
			holes.append(p)
		else:
			outs.append(p)
	if holes.is_empty() or outs.is_empty():
		return _outer(polys)
	var result := []
	for o: PackedVector2Array in outs:
		var pieces := [o]
		for h: PackedVector2Array in holes:
			var hb := bounds(h)
			if not bounds(o).encloses(hb):
				continue
			var cx := hb.get_center().x
			var ob := bounds(o)
			var left := _rect(Rect2(ob.position.x - 1.0, ob.position.y - 1.0, cx - ob.position.x + 1.0, ob.size.y + 2.0))
			var right := _rect(Rect2(cx, ob.position.y - 1.0, ob.end.x - cx + 1.0, ob.size.y + 2.0))
			var next := []
			for r: PackedVector2Array in pieces:
				for half: PackedVector2Array in [left, right]:
					for q: PackedVector2Array in _outer(Geometry2D.intersect_polygons(r, half)):
						next.append_array(_outer(Geometry2D.clip_polygons(q, _ccw(h))))
			pieces = next
		result.append_array(pieces)
	return result


static func _ccw(p: PackedVector2Array) -> PackedVector2Array:
	if Geometry2D.is_polygon_clockwise(p):
		var r := p.duplicate()
		r.reverse()
		return r
	return p


## The pieces of a boolean's result that are not holes, nor slivers.
static func _outer(polys: Array) -> Array:
	var out := []
	for p: PackedVector2Array in polys:
		if polys.size() > 1 and Geometry2D.is_polygon_clockwise(p):
			continue
		if _area(p) > 0.05:
			out.append(p)
	return out


## Polygon (or `line`: polyline) `poly` grown by d m (shrunk if d < 0), the largest piece; worked at FINE times the
## scale (Godot's offsets round to a quarter of a unit).
static func offset(poly: PackedVector2Array, d: float, join := Geometry2D.JOIN_ROUND, line := false,
		end := Geometry2D.END_ROUND) -> PackedVector2Array:
	var big := poly * Transform2D.IDENTITY.scaled(Vector2(FINE, FINE))
	var out: Array = Geometry2D.offset_polyline(big, d * FINE, join, end) if line else \
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
	if p.is_empty():
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## Whether p is in polygon `poly` (its box first: cached).
static func inside(p: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	var key := poly.size() * 7919 + int(poly[0].x * 100.0) * 31 + int(poly[0].y * 100.0) + int(poly[1].x * 7.0)
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
