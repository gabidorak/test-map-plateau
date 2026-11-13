extends RefCounted
## The master plan of the Haigneré residence's grounds (Thomas's plan: ref/residencHaignere/PlanUrbanisme.png), lot
## residenceHaignere: everything round #536 (the residence, kept as it is) up to the roads' kerbs and the alley's outer
## edge. In the map's frame (x east, y north: frame() is the identity), its shapes made from a few lines with the
## polygon tools (Geometry2D):
## - the lot (lot()): from the roads' kerb (kerb_sw(): the west road's and the south road's edges, straight up to the
##   corner, where they meet square with a KERB_R m fillet; the road's old bulge there made road: fill(); the service
##   road's stub up to the old alley out) to the alley's outer edge (ALLEY.y m off the residence's north-east facade),
##   and at its south-east tip on to the east road's kerb (EAST_KERB) along the south road, with the lawn north of it
##   up to #692's paved foot and the east road's sidewalk (TIP_LAWN: the old alley's end, out);
## - along the roads, from the kerb in (bands()), all KERB high: the kerb's top, a planted strip (sunken grass beds with
##   a tree each, paved between, lowered where a crossing meets the kerb: GAPS), the two-way cycle track (on from the
##   existing one; on the west road up to CYCLE_END; at the south-east tip on to the east road, the kerb lowered where
##   it meets it), the sidewalk up to the facade (WALK m wide past it); all round the corner on the kerb's fillet;
## - flush with the lawns (flush()): the alley in setts from the north-west corner to the south-east tip (a lawn strip
##   with a row of trees between it and the residence), the terrace in the residence's notch, two paths from the alley
##   down to the south sidewalk (the second on the zebra's line); each rises to the sidewalk where it meets it (RAMP);
## - the ground (height()): one plane fitted to the map's ground round the lot (PLANE, 0.8 %), terraformed so
##   (terraform_zones()), eased back to the map's over BLEND m round it.

const KERB := 0.15                          # m: the bands over the ground (the street kit's KERB)
const LOW := 0.055                          # m: lowered at a crossing (the kit's LOW)
const FLUSH := 0.03                         # m: the alley, the terrace, the paths over the ground
const RAMP := 1.8                           # m over which a crossing's lowering and a path's rise run
const BLEND := 3.0                          # m over which the terraformed ground eases back to the map's
## The ground: h = a + b (x - 200) + c (y + 70), fitted to the map's ground along the lot's outline (rms 0.10 m).
const PLANE := [-0.22978, 0.00449, -0.00677]

## The roads' edge (the map's road's), north-west to south-east: the west road, the corner (its bulge), the south road
## (straight across where the service road's stub left it). The kerb (kerb_sw()) is its straight lines, filleted.
const ROAD_EDGE := [
	Vector2(167.37, -9.47), Vector2(158.08, -62.25), Vector2(153.72, -87.0), Vector2(153.35, -89.09),
	Vector2(153.19, -89.96), Vector2(152.7, -92.22), Vector2(152.15, -94.8), Vector2(152.05, -95.33),
	Vector2(151.22, -99.54), Vector2(151.18, -100.15), Vector2(151.29, -100.75), Vector2(151.54, -101.31),
	Vector2(151.92, -101.8), Vector2(152.25, -102.05), Vector2(152.97, -102.42), Vector2(153.57, -102.52),
	Vector2(154.22, -102.54), Vector2(155.68, -102.6), Vector2(156.86, -102.7), Vector2(161.09, -103.08),
	Vector2(162.62, -103.16), Vector2(163.06, -103.25), Vector2(167.25, -103.63), Vector2(168.79, -103.91),
	Vector2(170.97, -104.33), Vector2(191.11, -108.25), Vector2(240.21, -117.79), Vector2(254.4, -120.55),
	Vector2(258.93, -121.43), Vector2(273.39, -124.16), Vector2(277.45, -124.92), Vector2(280.08, -125.4),
	Vector2(287.77, -126.86), Vector2(310.95, -131.11), Vector2(318.66, -132.52), Vector2(325.55, -133.78),
	Vector2(333.73, -135.25)]
## The west and south roads' straight lines (two points on each) and the kerb's fillet where they meet.
const WEST_LINE := [Vector2(167.37, -9.47), Vector2(153.72, -87.0)]
const SOUTH_LINE := [Vector2(170.97, -104.33), Vector2(191.11, -108.25)]
const KERB_R := 4.0
## The east road's west kerb, from the south road's corner north (past where the lot stops).
const EAST_KERB := [Vector2(333.73, -135.25), Vector2(335.7, -135.6), Vector2(336.5, -133.7), Vector2(337.0, -132.3),
	Vector2(339.0, -110.2)]
## #536's footprint (osm:w1473225811), kept as it is.
const RESIDENCE := [Vector2(185.9, -41.0), Vector2(171.1, -25.5), Vector2(159.3, -94.4), Vector2(245.1, -111.6),
	Vector2(248.9, -91.8), Vector2(211.3, -62.9), Vector2(182.5, -57.8)]
## Its facades: west (C to A), south (A to B), north-east (D to E), the notch (N1, N2).
const A := Vector2(159.3, -94.4)
const B := Vector2(245.1, -111.6)
const C := Vector2(171.1, -25.5)
const D := Vector2(248.9, -91.8)
const E := Vector2(211.3, -62.9)
const N1 := Vector2(185.9, -41.0)
const N2 := Vector2(182.5, -57.8)

# the bands, m in from the kerb
const STRIP := Vector2(0.15, 1.5)           # the planted strip (behind the kerb's top)
const CYCLE := Vector2(1.5, 4.3)            # the cycle track
const WALK := 6.8                           # the sidewalk's inner edge where there is no facade
const FRONT_REACH := 10.0                   # m out from the facades where the sidewalk runs up to them
const CYCLE_END := -20.0                    # y where the cycle track ends on the west road (the sidewalk on)
## The beds along the south road (x from, to) and along the west one (y from, to).
const BEDS_X := [Vector2(160.0, 169.0), Vector2(172.5, 181.5), Vector2(185.0, 194.0), Vector2(197.5, 206.5),
	Vector2(210.0, 219.0), Vector2(222.5, 231.5), Vector2(235.0, 244.0), Vector2(247.5, 256.5), Vector2(260.0, 268.5),
	Vector2(280.0, 289.0), Vector2(292.5, 301.5), Vector2(305.0, 314.0)]
const BEDS_Y := [Vector2(-84.0, -75.5), Vector2(-72.0, -63.5), Vector2(-60.0, -51.5), Vector2(-48.0, -39.5),
	Vector2(-36.0, -27.5), Vector2(-24.0, -15.5)]
## Crossings at the kerb (their ends): the corner's (the west road's zebra and cycle crossing, the south road's zebra),
## the south road's zebra to the second path, the cycle track's way onto the east road.
const GAPS := [[Vector2(153.8, -86.4), Vector2(156.3, -102.66)], [Vector2(271.4, -123.88), Vector2(276.9, -124.82)],
	[Vector2(336.2, -134.4), Vector2(337.1, -131.0)]]

## The lawn at the south-east tip, where the old alley ran on to the east road's sidewalk (#692's paved foot north of
## it, the sidewalk east, kept).
const TIP_LAWN := [Vector2(310.0, -136.0), Vector2(334.0, -134.3), Vector2(335.0, -132.0), Vector2(335.3, -130.4),
	Vector2(335.5, -129.2), Vector2(336.4, -124.4), Vector2(332.8, -124.4), Vector2(319.8, -122.9), Vector2(310.0, -121.0)]

# flush
const ALLEY := Vector2(7.0, 14.0)           # m off the north-east facade line: its inner, outer edge (the lot's)
## The paths from the alley to the south sidewalk: x on the kerb, width (the second on the zebra).
const PATHS := [Vector2(252.5, 2.4), Vector2(274.15, 3.0)]

const FINE := 10.0                          # the polygon offsets worked at this scale (offset())

static var _cache := {}


# ---------------------------------------------------------------- the frame, the ground

static func frame() -> Transform3D:
	return Transform3D.IDENTITY


## The ground as designed at map p.
static func height(p: Vector2) -> float:
	return PLANE[0] + PLANE[1] * (p.x - 200.0) + PLANE[2] * (p.y + 70.0)


## The ground's terraforming (builder/terraform.gd, named by the lot): the plane over the lot and the road made at the
## corner (and 1 m round them), eased back to the map's over BLEND m.
static func terraform_zones() -> Array:
	var l := area()
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
			sf[j * w + i] = height(p)
			if Geometry2D.is_point_in_polygon(p, l):
				wt[j * w + i] = 255
			elif Geometry2D.is_point_in_polygon(p, grown):
				wt[j * w + i] = roundi(_ease(1.0 - (_dist_outline(p, l) - 1.0) / BLEND) * 255.0)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


# ---------------------------------------------------------------- the shapes

## The lot's outline: between the kerb and the alley's outer edge; at the south-east tip, the bands on to the east
## road.
static func lot() -> PackedVector2Array:
	if not _cache.has("lot"):
		var main := largest(Geometry2D.intersect_polygons(lot_side(), _ne_band(-300.0, ALLEY.y)))
		var tip := intersect([lot_side()], [_within(WALK), PackedVector2Array([Vector2(310.0, -150.0),
				Vector2(350.0, -150.0), Vector2(350.0, -100.0), Vector2(310.0, -100.0)])])
		tip = intersect([lot_side()], [largest(Geometry2D.merge_polygons(largest(tip), PackedVector2Array(TIP_LAWN)))])
		_cache["lot"] = largest(Geometry2D.merge_polygons(main, largest(tip)))
	return _cache["lot"]


## The kerbs' lot side: the kerb (on along the east road's) closed round it, far.
static func lot_side() -> PackedVector2Array:
	if not _cache.has("side"):
		_cache["side"] = _closed(kerb_line())
	return _cache["side"]


## A kerb (north-west to south-east, on along the east road's) closed round its lot's side, far.
static func _closed(k: PackedVector2Array) -> PackedVector2Array:
	var side := PackedVector2Array(k)
	var k0: Vector2 = WEST_LINE[0]
	var k1: Vector2 = WEST_LINE[1]
	side.append_array([Vector2(340.0, 10.0), k0 + (k0 - k1).normalized() * 20.0])
	return side


## The kerb all along: the west road's, the south road's, the east road's.
static func kerb_line() -> PackedVector2Array:
	var k := kerb_sw()
	k.append_array(PackedVector2Array(EAST_KERB.slice(1)))
	return k


## The west and south roads' kerb: their straight lines up to the corner, the fillet between, then the south road's edge
## on east.
static func kerb_sw() -> PackedVector2Array:
	if not _cache.has("kerb_sw"):
		var w0: Vector2 = WEST_LINE[0]
		var dw: Vector2 = ((WEST_LINE[1] as Vector2) - w0).normalized()          # (southward)
		var s0: Vector2 = SOUTH_LINE[0]
		var ds: Vector2 = ((SOUTH_LINE[1] as Vector2) - s0).normalized()         # (eastward)
		var corner: Vector2 = Geometry2D.line_intersects_line(w0, dw, s0, ds)
		var half := acos(clampf((-dw).dot(ds), -1.0, 1.0)) * 0.5
		var t := KERB_R / tan(half)
		var t1 := corner - dw * t
		var t2 := corner + ds * t
		var c := corner + (ds - dw).normalized() * (KERB_R / sin(half))
		var a1 := (t1 - c).angle()
		var da := wrapf((t2 - c).angle() - a1, -PI, PI)
		var k := PackedVector2Array([w0, t1])
		for i in range(1, 12):
			k.append(c + Vector2.from_angle(a1 + da * i / 12.0) * KERB_R)
		k.append(t2)
		for q: Vector2 in ROAD_EDGE:
			if q.y < -100.0 and q.x >= (SOUTH_LINE[1] as Vector2).x - 0.01:
				k.append(q)
		_cache["kerb_sw"] = k
	return (_cache["kerb_sw"] as PackedVector2Array).duplicate()   # (a copy: packed arrays go by reference)


## Made road: between the road's old edge (its bulge at the corner) and the kerb.
static func fill() -> Array:
	if not _cache.has("fill"):
		var old := _closed(PackedVector2Array(ROAD_EDGE) + PackedVector2Array(EAST_KERB.slice(1)))
		var near := PackedVector2Array([Vector2(140.0, -115.0), Vector2(200.0, -115.0), Vector2(200.0, -55.0),
				Vector2(140.0, -55.0)])
		_cache["fill"] = intersect([old], [roads(), near])
	return _cache["fill"]


## The lot and the road made at the corner: what the lot terraforms and clears.
static func area() -> PackedVector2Array:
	if not _cache.has("area"):
		var a := lot()
		for f: PackedVector2Array in fill():
			a = largest(Geometry2D.merge_polygons(a, offset(f, 0.05)))
		_cache["area"] = a
	return _cache["area"]


## Map point p if it is on the bands; else the point of the planted strip by the kerb nearest it (a traffic signal of
## the map's left on the road made).
static func on_kerb_strip(p: Vector2) -> Vector2:
	if in_band(p):
		return p
	var k := kerb_line()
	var best := INF
	var at := p
	for i in k.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, k[i], k[i + 1])
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			var d := (k[i + 1] - k[i]).normalized()
			at = q + Vector2(-d.y, d.x) * (STRIP.x + STRIP.y) * 0.5
	return at


## Whether map p is on the road made at the corner.
static func in_fill(p: Vector2) -> bool:
	for f: PackedVector2Array in fill():
		if inside(p, f):
			return true
	return false


## The roads' side: the west and south roads' kerb closed round the roads, the south one straight on past the lot (its
## offsets: how far from the kerb).
static func roads() -> PackedVector2Array:
	if not _cache.has("roads"):
		var r := kerb_sw()
		var k0: Vector2 = WEST_LINE[0]
		var k1: Vector2 = WEST_LINE[1]
		r.append_array([Vector2(345.0, -137.3), Vector2(345.0, -175.0), Vector2(120.0, -175.0), Vector2(120.0, 10.0),
				k0 + (k0 - k1).normalized() * 20.0])
		_cache["roads"] = r
	return _cache["roads"]


static func residence() -> PackedVector2Array:
	return PackedVector2Array(RESIDENCE)


## The bands along the roads, KERB high: [[polygon, material], ...]; the beds (grass, at the ground) apart: beds().
static func bands() -> Array:
	if not _cache.has("bands"):
		var out := []
		var l := lot()
		var reach := _reach()
		var cut := _cycle_cut()
		for p in subtract(intersect([l], [_within(STRIP.x)]), [roads()]):
			out.append([p, "kerb_top"])
		beds()
		for p in _strip():
			for q in subtract([p], _cache["bed_cuts"]):         # (the boxes: past the strip's edges, clean cuts)
				out.append([q, "street_pavers"])
		var cycle := _band(l, CYCLE.x, CYCLE.y)
		for q in subtract(cycle, [cut]):
			out.append([q, "street_asphalt"])
		for q in intersect(cycle, [cut]):
			out.append([q, "street_pavers"])
		for q in subtract(intersect(_band(l, CYCLE.y, WALK + FRONT_REACH), [reach]), [residence()]):
			out.append([q, "street_pavers"])
		_cache["bands"] = out
	return _cache["bands"]


## The sunken beds: polygons.
static func beds() -> Array:
	if not _cache.has("beds"):
		var cuts := []
		for r: Vector2 in BEDS_X:
			cuts.append(_cross_box(_kerb_at(r.x, true), _kerb_at(r.y, true)))
		for r: Vector2 in BEDS_Y:
			cuts.append(_cross_box(_kerb_at(r.y, false), _kerb_at(r.x, false)))
		_cache["bed_cuts"] = cuts
		var strip := _strip()
		var out := []
		for c: PackedVector2Array in cuts:
			out.append_array(intersect(strip, [c]))
		_cache["beds"] = out
	return _cache["beds"]


## The flush paving: [[polygon, material], ...]: the alley, the paths, the terrace.
static func flush() -> Array:
	if not _cache.has("flush"):
		var out := []
		var l := lot()
		var taken := [_reach(), residence()]
		var alley := subtract(intersect([l], [_ne_band(ALLEY.x, ALLEY.y)]), taken)   # (none on the tip's lawn)
		for q in alley:
			out.append([q, "street_setts"])
		for p: Vector2 in PATHS:
			var k := _kerb_at(p.x, true)
			var d := _kerb_dir(p.x)
			var n := Vector2(-d.y, d.x)
			var h := d * p.y * 0.5
			var r := PackedVector2Array([k - h - n, k + h - n, k + h + n * 40.0, k - h + n * 40.0])
			for q in subtract(intersect([l], [r]), taken + [_ne_band(ALLEY.x, ALLEY.y + 1.0)]):
				out.append([q, "street_setts"])
		var nn := _ne_normal()
		out.append([PackedVector2Array([N1, N2, E, E + nn * ALLEY.x, N1 + nn * (ALLEY.x - off_ne(N1))]), "street_pavers"])
		_cache["flush"] = out
	return _cache["flush"]


## Whether map p is paved (anything drawn: the bands, the flush paving); false on the lawns and beds, out of the lot.
static func paved(p: Vector2) -> bool:
	return in_band(p) or in_flush(p)


## Whether map p is on the flush paving (the alley, the paths, the terrace).
static func in_flush(p: Vector2) -> bool:
	for e: Array in flush():
		if inside(p, e[0]):
			return true
	return false


## Whether map p is on the bands along the roads.
static func in_band(p: Vector2) -> bool:
	for e: Array in bands():
		if inside(p, e[0]):
			return true
	return false


## Whether map p is in the lot (the residence's footprint out).
static func in_lot(p: Vector2) -> bool:
	return inside(p, lot()) and not Geometry2D.is_point_in_polygon(p, residence())


# ---------------------------------------------------------------- heights over the ground

## A band's top over the ground at p: KERB, lowered to LOW at the crossings' kerb, eased back over RAMP.
static func lift(p: Vector2) -> float:
	var h := KERB
	for g: PackedVector2Array in _gap_lines():
		var d := _dist_line(p, g)
		if d < RAMP:
			h = minf(h, lerpf(LOW, KERB, _ease(d / RAMP)))
	return h


## The flush paving's top over the ground at p: FLUSH, rising to the bands' top where it meets them (over RAMP).
static func flush_lift(p: Vector2) -> float:
	if not inside(p, ramp_zones(false)[0]):
		return FLUSH
	var d := _dist_outline(p, _reach())
	if Geometry2D.is_point_in_polygon(p, _reach()):
		d = 0.0
	if d >= RAMP:
		return FLUSH
	return lerpf(lift(p), FLUSH, _ease(d / RAMP))


## Where the tops slope (their surfaces cut fine there): round the crossings' kerb (`band`), or where the flush paving
## rises to the sidewalk.
static func ramp_zones(band: bool) -> Array:
	var key := "ramps_band" if band else "ramps_flush"
	if not _cache.has(key):
		var out := []
		if band:
			for g: PackedVector2Array in _gap_lines():
				out.append(offset(g, RAMP + 0.1, Geometry2D.JOIN_ROUND, true))
		else:
			out.append(offset(_reach(), RAMP + 0.1))
		_cache[key] = out
	return _cache[key]


# ---------------------------------------------------------------- where things go

## The north-east facade's outward normal (to the alley) and how far map p is off that facade's line.
static func _ne_normal() -> Vector2:
	var d := (E - D).normalized()
	return Vector2(d.y, -d.x)


static func off_ne(p: Vector2) -> float:
	return (p - D).dot(_ne_normal())


## A point `along` m from D towards E (and on past it), `off` m out from the north-east facade's line.
static func ne_point(along: float, off: float) -> Vector2:
	return D + (E - D).normalized() * along + _ne_normal() * off


## The kerb's point at x (`south`: on the south road) or at y (on the west road).
static func _kerb_at(v: float, south: bool) -> Vector2:
	var k := kerb_sw()
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		if south and a.y < -100.0 and a.x <= v and b.x >= v:
			return a.lerp(b, (v - a.x) / (b.x - a.x))
		if not south and a.x > 152.0 and b.x > 152.0 and a.y >= v and b.y <= v and absf(a.y - b.y) > 0.01:
			return a.lerp(b, (a.y - v) / (a.y - b.y))
	push_error("haignere_plan: no kerb at %s" % v)
	return Vector2.ZERO


## The south kerb's direction (eastward) at x.
static func _kerb_dir(x: float) -> Vector2:
	var k := kerb_sw()
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		if a.y < -100.0 and a.x <= x and b.x >= x:
			return (b - a).normalized()
	return Vector2.RIGHT


## The kerb's point at x (south road) or y (west road), `o` m in from it.
static func kerb_point(v: float, south: bool, o: float) -> Vector2:
	var k := _kerb_at(v, south)
	var d := _kerb_dir(v) if south else (_kerb_at(v - 1.0, false) - k).normalized()
	return k + Vector2(-d.y, d.x) * o


## The street trees: [map point, archetype, height].
static func trees() -> Array:
	var out := []
	for r: Vector2 in BEDS_X:                                  # one in each bed
		out.append([kerb_point((r.x + r.y) * 0.5, true, (STRIP.x + STRIP.y) * 0.5), "round", 9.0])
	for r: Vector2 in BEDS_Y:
		out.append([kerb_point((r.x + r.y) * 0.5, false, (STRIP.x + STRIP.y) * 0.5), "round", 8.5])
	var along := 5.0                                           # the lawn strip along the north-east facade
	while along < 47.0:
		out.append([ne_point(along, 3.6), "oval", 8.5])
		along += 8.4
	for t: Vector2 in [Vector2(86.0, 4.9), Vector2(95.0, 5.7)]: # the lawn by the north-west facade
		out.append([ne_point(t.x, t.y), "oval", 6.5])
	for t: Vector3 in [Vector3(259.0, 10.5, 9.0), Vector3(268.0, 10.5, 9.0), Vector3(259.0, 17.0, 10.0),
			Vector3(287.0, 9.6, 8.0), Vector3(326.5, 8.6, 7.0)]:   # the lawns at the east end
		out.append([kerb_point(t.x, true, t.y), "round", t.z])
	return out


# ---------------------------------------------------------------- polygon tools

## The band from o0 to o1 m in from the kerb, in polygon `l`.
static func _band(l: PackedVector2Array, o0: float, o1: float) -> Array:
	return subtract(intersect([l], [_within(o1)]), [_within(o0)])


## The planted strip: from the kerb's top to STRIP.y m from the kerb.
static func _strip() -> Array:
	return _band(lot(), STRIP.x, STRIP.y)


## The roads and o m round them (o m from the kerb).
static func _within(o: float) -> PackedVector2Array:
	var key := "within %s" % o
	if not _cache.has(key):
		_cache[key] = roads() if o <= 0.0 else offset(roads(), o)
	return _cache[key]


## Where the bands reach: WALK m from the kerb, up to the facades along them.
static func _reach() -> PackedVector2Array:
	if not _cache.has("reach"):
		var dw := (A - C).normalized()
		var nw := Vector2(dw.y, -dw.x)                         # (out of the west facade)
		var ds := (B - A).normalized()
		var ns := Vector2(ds.y, -ds.x)                         # (out of the south facade)
		var f := FRONT_REACH
		var front := PackedVector2Array([C + nw * f, C, A, B, B + ns * f, A + ns * f + nw * f])
		var both := largest(Geometry2D.merge_polygons(_within(WALK), front))
		_cache["reach"] = largest(subtract(intersect([lot()], [both]), [residence()]))
	return _cache["reach"]


## Where the cycle track gives way to the sidewalk: north of CYCLE_END on the west road.
static func _cycle_cut() -> PackedVector2Array:
	var k := _kerb_at(CYCLE_END, false)
	var up := (_kerb_at(CYCLE_END + 1.0, false) - k).normalized()   # (northward)
	var n := Vector2(up.y, -up.x)
	return PackedVector2Array([k - n * 20.0, k + n * 40.0, k + n * 40.0 + up * 60.0, k - n * 20.0 + up * 60.0])


## The strip between o0 and o1 m off the north-east facade's line, long.
static func _ne_band(o0: float, o1: float) -> PackedVector2Array:
	var d := (E - D).normalized()
	var n := _ne_normal()
	return PackedVector2Array([D - d * 300.0 + n * o0, D + d * 300.0 + n * o0, D + d * 300.0 + n * o1, D - d * 300.0 + n * o1])


## A box across the kerb from its point a to b: from 1 m out to 3 m in.
static func _cross_box(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return PackedVector2Array([a - n, b - n, b + n * 3.0, a + n * 3.0])


## The crossings' kerb: the kerb's line between each crossing's ends.
static func _gap_lines() -> Array:
	if not _cache.has("gaps"):
		var out := []
		for g: Array in GAPS:
			out.append(kerb_part(kerb_d(g[0]), kerb_d(g[1])))
		_cache["gaps"] = out
	return _cache["gaps"]


## The kerb's line (kerb_line()) from d0 to d1 m along it (from its north-west end).
static func kerb_part(d0: float, d1: float) -> PackedVector2Array:
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


## How far along the kerb (kerb_line(), from its north-west end) its point nearest p is.
static func kerb_d(p: Vector2) -> float:
	var best := INF
	var at := 0.0
	var run := 0.0
	var k := kerb_line()
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			at = run + a.distance_to(q)
		run += a.distance_to(b)
	return at


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
				next.append_array(_outer(Geometry2D.clip_polygons(r, q)))
			pieces = next
		out.append_array(pieces)
	return out


## The pieces of a boolean's result that are not holes (none are expected) and not slivers.
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
			push_warning("haignere_plan: a hole dropped at %s" % bounds(p))
			continue
		if _area(p) > 0.05:
			out.append(p)
	return out


## Polygon (or `line`: polyline) `poly` grown by d m (shrunk if d < 0), the largest piece; its rounds smooth (Godot's
## offsets round to a quarter of a unit: worked at FINE times the scale).
static func offset(poly: PackedVector2Array, d: float, join := Geometry2D.JOIN_ROUND, line := false) -> PackedVector2Array:
	var big := poly * Transform2D.IDENTITY.scaled(Vector2(FINE, FINE))
	var out: Array = Geometry2D.offset_polyline(big, d * FINE, join, Geometry2D.END_ROUND) if line else 			Geometry2D.offset_polygon(big, d * FINE, join)
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
