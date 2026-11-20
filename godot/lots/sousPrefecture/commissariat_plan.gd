extends RefCounted
## The plan of the commissariat, lot sousPrefecture: the sous-préfecture de Palaiseau (#630, osm:r20158551) made the
## police's commissariat, after Thomas's references (ref/prefecture/: Vue1, Vue2, Vue3 the building, Plan2DObjectif
## the grounds). Drawn in the building's frame (local x along its north facade, eastwards; y along its west facade,
## northwards; frame() turns it onto the map), its numbers read off the map's footprint:
## - the building (commissariat_builder.gd): a wedge, its west facade (x = 0) and its north facade (y = NORTH_Y) square,
##   its east facade from the courtyard's tip (TIP_E, 0) to the north-east corner (NORTH_E, NORTH_Y); its two long
##   walls rise from the ground at the tip to the parapet (TOP) at STEP_TOP; the courtyard between them, open to the
##   sky, its garden at the ground (y < its south face, COURT_W to COURT_E); north of it the building in three steps,
##   one, two and three storeys (ROOFS), their roofs the planted terraces and, on the highest, the heliport (HELIPAD);
## - its grounds (grounds_builder.gd, sous_prefecture.gd): the police's car park north of it (CARPARK, the turning
##   circle TURN; two rows of five bays; fenced, its gate off the boulevard: two lift gates), the courtyard's paths,
##   the apron at the tip; along the boulevard, from its kerb (KERB_LINE, the map's carriageway's edge) to the facade
##   and the car park's fence, the sidewalk (in place of the map's cycle track there): KERB high, lowered across the
##   car park's way out (the bateau) and at its ends (SIDEWALK_GAPS), a row of trees in it on grates, the flags before
##   the entrance; lawns over the rest of the lot (lot()) up to the road (north) and the track along line 18's viaduct
##   (east);
## - the ground (height()): one plane fitted to the map's ground round the building (PLANE, 0.6 %), terraformed so
##   (terraform_zones()), eased back to the map's over BLEND m round the lot;
## - the police's places (places()): the helicopter's base on the heliport, where the arrested are let go (before the
##   entrance); the car park's police cars, PTA Online's public vehicles (vehicles()).

const ANGLE := -0.184823                    # rad: the building's frame turned from the map's
const ORIGIN := Vector2(245.926, 410.288)   # map: the west facade's south end, the courtyard's tip
## The ground: h = a + b x + c y (local), fitted to the map's ground round the building (rms 0.18 m).
const PLANE := [-2.0637, 0.00042, -0.00644]
const BLEND := 3.0                          # m over which the terraformed ground eases back to the map's

# ---------------------------------------------------------------- the building
const NORTH_Y := 107.4                      # the north facade
const NORTH_E := 38.8                       # the north-east corner's x
const TIP_E := 9.09                         # the east facade's south end (x, at y 0)
const WALL := 0.4                           # m: the walls' thickness
const COURT_W := Vector2(0.4, 63.2)         # the courtyard's south face (the building's), its west end...
const COURT_E_Y := 57.0                     # ...and its east end's y (on the east wall's inside)
const STEP_MID := 74.0                      # y: the two-storey step's south face...
const STEP_TOP := 85.0                      # ...the three-storey's: the walls reach the parapet there
const FLOOR := -2.52                        # Godot y: the ground floor (the sidewalk's top at the entrance)
const ROOFS := [4.6, 8.8, 13.0]             # m over the floor: the one, two, three storeys' roofs
const PARAPET := 13.5                       # m over the floor: the walls' top from STEP_TOP on
const STOREY := 4.2                         # m: floor to floor
const ENTRANCE := Vector2(95.0, 101.0)      # y: the public entrance on the west facade
const HELIPAD := Rect2(11.0, 89.0, 16.0, 16.0)   # on the highest roof
const PAD_UP := 0.25                        # m: its deck over the roof

# ---------------------------------------------------------------- the grounds
## The boulevard's kerb, south to north: the map's carriageway's east edge (across the car park's way out, from the
## building's corner to past the gate, where the map's asphalt runs on: straight).
const KERB_LINE := [Vector2(-4.85, -4.0), Vector2(-5.45, 32.0), Vector2(-5.65, 44.0), Vector2(-6.75, 104.0),
		Vector2(-6.75, 106.0), Vector2(-4.8, 120.0), Vector2(-5.1, 129.0), Vector2(-5.2, 131.0)]
const SIDEWALK_Y := Vector2(-4.0, 131.0)    # the sidewalk's ends (y)
const KERB := 0.15                          # m: the sidewalk over the ground (the street kit's)
const LOW := 0.055                          # m: lowered (the street kit's)
const RAMP := 1.8                           # m over which it is lowered
const ROAD_IN := 2.0                        # m: the lot reaches into the road past the kerb (its ground the
                                            # plane under the gutter: the map's eases back beyond)
## The lot, from the boulevard's kerb (west) to the road (north) and the track along the viaduct (east); its north-west
## corner clear of the map's cycle track at the junction.
const LOT_EAST := [Vector2(-2.3, 131.0), Vector2(-2.3, 142.0), Vector2(56.0, 142.0), Vector2(57.5, 132.0),
		Vector2(56.5, 124.0), Vector2(53.5, 112.0), Vector2(50.5, 100.0), Vector2(44.5, 80.0), Vector2(33.5, 40.0),
		Vector2(24.0, 0.0), Vector2(23.0, -4.0)]
const CARPARK := Rect2(0.0, 107.6, 26.0, 16.9)  # asphalt, with the turning circle at its east end
const TURN := Vector2(26.0, 116.0)
const TURN_R := 8.0
const BAYS_X := 3.0                         # the bays from x 3 on, BAY_W wide, five a row
const BAY_W := 3.0
const BAYS_S := Vector2(108.4, 113.4)       # the south row (y), along the building...
const BAYS_N := Vector2(119.4, 124.4)       # ...the north row; the aisle between them, out through the gate
const FENCE_N := 126.0                      # the car park's fence: north side (y), east side at NORTH_E, west at x
const FENCE_W := 0.0                        # FENCE_W (on the facade's line), open across the aisle (the lift gates)
const HEDGE_Y := 127.6
const APRON := Rect2(0.0, -3.0, 9.1, 3.0)   # paving at the tip, from the sidewalk into the courtyard
const PATH_W := 2.0
## The courtyard's paths: the walk from the tip to the door in its south face, two branches.
const PATHS := [
	[Vector2(4.5, -1.0), Vector2(4.3, 10.0), Vector2(6.5, 22.0), Vector2(9.5, 32.0), Vector2(11.0, 42.0),
			Vector2(12.0, 52.0), Vector2(12.4, 60.4)],
	[Vector2(9.5, 32.0), Vector2(15.5, 40.0), Vector2(18.5, 48.0), Vector2(17.5, 55.0)],
	[Vector2(6.5, 22.0), Vector2(2.6, 26.0)],
]
const TREES := [   # [local, archetype, height]
	[Vector2(8.2, 9.0), "round", 7.0], [Vector2(2.6, 18.0), "oval", 8.0], [Vector2(11.5, 21.0), "round", 7.5],
	[Vector2(3.5, 33.0), "round", 8.0], [Vector2(15.0, 31.5), "oval", 8.5], [Vector2(6.0, 45.0), "round", 9.0],
	[Vector2(19.8, 42.0), "round", 8.0], [Vector2(16.0, 53.5), "oval", 9.0],
	[Vector2(21.5, 18.0), "round", 10.0], [Vector2(28.5, 44.0), "round", 11.0], [Vector2(36.5, 72.0), "oval", 10.0],
	[Vector2(43.5, 95.0), "round", 11.0], [Vector2(47.0, 115.0), "round", 10.0], [Vector2(48.0, 131.0), "oval", 11.0],
	[Vector2(5.0, 135.0), "round", 10.0], [Vector2(20.0, 135.5), "round", 11.0], [Vector2(35.0, 135.0), "round", 10.0],
]
const STREET_TREES := [6.0, 14.0, 22.0, 30.0, 38.0, 46.0, 54.0, 62.0, 70.0, 78.0, 86.0, 105.0, 125.0]   # y
const TREE_IN := 1.2                        # m from the kerb: the sidewalk's trees, the flags
const GRATE := 1.2                          # m: the trees' grates
const FLAGS := [91.3, 92.9]                 # y: the French and the European flags
const BENCHES := [   # [local, the way it looks (local)]
	[Vector2(2.9, 15.5), Vector2(1, 0)], [Vector2(2.4, 24.0), Vector2(1, 0)], [Vector2(13.8, 46.5), Vector2(-1, 0)],
	[Vector2(8.3, 56.0), Vector2(1, 0)],
]
const BINS := [Vector2(2.9, 17.2), Vector2(13.8, 48.2)]

static var _cache := {}


# ---------------------------------------------------------------- the frame

## The map's point of local p.
static func to_map(p: Vector2) -> Vector2:
	return ORIGIN + p.rotated(ANGLE)


## The local point of the map's m.
static func to_local(m: Vector2) -> Vector2:
	return (m - ORIGIN).rotated(-ANGLE)


## The building's frame in the game: a node so placed draws in local (x, height, -y).
static func frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ANGLE), Vector3(ORIGIN.x, 0.0, -ORIGIN.y))


## A local direction as a map yaw, degrees clockwise from north (the police's places, the public vehicles).
static func yaw_cw(d: Vector2) -> float:
	var m := d.rotated(ANGLE)
	return fposmod(rad_to_deg(atan2(m.x, m.y)), 360.0)


## A local direction as a prop's yaw, degrees anticlockwise from east (world.json's props).
static func yaw_prop(d: Vector2) -> float:
	var m := d.rotated(ANGLE)
	return fposmod(rad_to_deg(atan2(m.y, m.x)), 360.0)


## The ground as designed at local p (Godot y).
static func height(p: Vector2) -> float:
	return PLANE[0] + PLANE[1] * p.x + PLANE[2] * p.y


## The east facade's x at y.
static func east_x(y: float) -> float:
	return TIP_E + (NORTH_E - TIP_E) * y / NORTH_Y


## The courtyard's south face's east end.
static func court_e() -> Vector2:
	return Vector2(east_x(COURT_E_Y) - WALL, COURT_E_Y)


## The long walls' top at y (Godot y): from the ground at the tip up to the parapet at STEP_TOP.
static func wall_top(y: float) -> float:
	var tip := height(Vector2(TIP_E * 0.5, 0.0))
	return lerpf(tip, FLOOR + PARAPET, clampf(y / STEP_TOP, 0.0, 1.0))


# ---------------------------------------------------------------- the shapes (local)

## The lot: ROAD_IN m into the road from the kerb, the sidewalk's ends straight across; then LOT_EAST round.
static func lot() -> PackedVector2Array:
	if not _cache.has("lot"):
		var out := PackedVector2Array()
		for k: Vector2 in KERB_LINE:
			out.append(k - Vector2(ROAD_IN, 0.0))
		out.append_array(PackedVector2Array(LOT_EAST))
		_cache["lot"] = out
	return _cache["lot"]


## The building's outline.
static func building() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(0, NORTH_Y), Vector2(NORTH_E, NORTH_Y), Vector2(TIP_E, 0)])


## The building's solid part (north of the courtyard).
static func solid() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, COURT_W.y), Vector2(0, NORTH_Y), Vector2(NORTH_E, NORTH_Y),
			Vector2(east_x(COURT_E_Y), COURT_E_Y)])


## The courtyard, inside the walls.
static func courtyard() -> PackedVector2Array:
	return PackedVector2Array([Vector2(WALL, 0.0), COURT_W, court_e(), Vector2(TIP_E - WALL, 0.0)])


## The car park's asphalt: the bays and the aisle, the turning circle.
static func carpark() -> PackedVector2Array:
	if not _cache.has("carpark"):
		var r := CARPARK
		var rect := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var circle := PackedVector2Array()
		for i in 48:
			circle.append(TURN + Vector2.from_angle(TAU * i / 48.0) * TURN_R)
		var union: Array = Geometry2D.merge_polygons(rect, circle)
		var poly: PackedVector2Array = union[0]
		for p: PackedVector2Array in union:
			if not Geometry2D.is_polygon_clockwise(p) and p.size() > poly.size():
				poly = p
		# (not over the building: the circle's south edge clipped at the north facade)
		var clip: Array = Geometry2D.intersect_polygons(poly, PackedVector2Array([Vector2(-1, NORTH_Y + 0.2),
				Vector2(60, NORTH_Y + 0.2), Vector2(60, 160), Vector2(-1, 160)]))
		_cache["carpark"] = clip[0] if not clip.is_empty() else poly
	return _cache["carpark"]


## The paved walks (polygons, none over another): the courtyard's paths (one shape, in the courtyard), the apron at
## the tip.
static func paved() -> Array:
	if not _cache.has("paved"):
		var walk := _offset_line(PackedVector2Array(PATHS[0]), PATH_W * 0.5)
		for k in range(1, PATHS.size()):
			walk = _largest(Geometry2D.merge_polygons(walk, _offset_line(PackedVector2Array(PATHS[k]), PATH_W * 0.4)))
		var out: Array = Geometry2D.intersect_polygons(walk, courtyard())
		var a := APRON
		out.append(PackedVector2Array([a.position, Vector2(a.end.x, a.position.y), a.end, Vector2(a.position.x, a.end.y)]))
		_cache["paved"] = out
	return _cache["paved"]


static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p: PackedVector2Array in polys:
		if absf(_area(p)) > absf(_area(best)):
			best = p
	return best


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return s * 0.5


## The bays: [the bay's rectangle, its middle, which way the car looks there (nose out, to the aisle)].
static func bays() -> Array:
	var out := []
	for row: Vector2 in [BAYS_S, BAYS_N]:
		var out_dir := Vector2(0, 1) if row == BAYS_S else Vector2(0, -1)
		for i in 5:
			var r := Rect2(BAYS_X + BAY_W * i, row.x, BAY_W, row.y - row.x)
			out.append([r, r.get_center(), out_dir])
	return out


## The car park's fence (local polylines): its west side either side of the gate, its north side, its east side.
static func fence() -> Array:
	return [[Vector2(FENCE_W, NORTH_Y), Vector2(FENCE_W, BAYS_S.y)],
			[Vector2(FENCE_W, BAYS_N.x), Vector2(FENCE_W, FENCE_N), Vector2(NORTH_E, FENCE_N), Vector2(NORTH_E, NORTH_Y)]]


## The kerb's x at y (KERB_LINE, straight on past its ends).
static func kerb_x(y: float) -> float:
	var k: Array = KERB_LINE
	for i in range(1, k.size()):
		if y <= k[i].y or i == k.size() - 1:
			var a: Vector2 = k[i - 1]
			var b: Vector2 = k[i]
			return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
	return k[0].x


## The x of the sidewalk's trees and of the flags at y (TREE_IN m in from the kerb).
static func tree_x(y: float) -> float:
	return kerb_x(y) + TREE_IN


## The sidewalk's crossings, lowered (y spans): its south end (the courtyard's apron), the car park's way out (the
## bateau), its north end.
static func sidewalk_gaps() -> Array:
	return [Vector2(SIDEWALK_Y.x - 1.0, 0.5), Vector2(BAYS_S.y, BAYS_N.x), Vector2(SIDEWALK_Y.y - RAMP, SIDEWALK_Y.y + 1.0)]


## The sidewalk's top over the ground at y: KERB, LOW across its gaps, sloping between over RAMP m.
static func sidewalk_lift(y: float) -> float:
	var h := KERB
	for g: Vector2 in sidewalk_gaps():
		if y >= g.x and y <= g.y:
			return LOW
		if y > g.x - RAMP and y < g.x:
			h = minf(h, lerpf(KERB, LOW, (y - (g.x - RAMP)) / RAMP))
		if y > g.y and y < g.y + RAMP:
			h = minf(h, lerpf(LOW, KERB, (y - g.y) / RAMP))
	return h


## Whether local p is on the sidewalk (between the kerb and the facade or the car park's fence).
static func in_sidewalk(p: Vector2) -> bool:
	return p.y >= SIDEWALK_Y.x and p.y <= SIDEWALK_Y.y and p.x >= kerb_x(p.y) and p.x <= 0.0


## Whether local p is the road's, in the lot (between its edge and the kerb).
static func in_road(p: Vector2) -> bool:
	return p.x < kerb_x(p.y)


static func in_lot(p: Vector2) -> bool:
	return _inside(p, lot())


static func in_carpark(p: Vector2) -> bool:
	return _inside(p, carpark())


static func in_paved(p: Vector2) -> bool:
	for q: PackedVector2Array in paved():
		if _inside(p, q):
			return true
	return false


static func in_solid(p: Vector2) -> bool:
	return _inside(p, solid())


# ---------------------------------------------------------------- the ground

## The ground's terraforming (builder/terraform.gd, named by the lot): the plane over the lot, eased back to the map's
## over BLEND m round it. Map cells (1 m).
static func terraform_zones() -> Array:
	var l := map_poly(lot())
	var grown := _grown(l, 1.0 + BLEND)
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
			sf[j * w + i] = height(to_local(p))
			if Geometry2D.is_point_in_polygon(p, l):
				wt[j * w + i] = 255
			elif Geometry2D.is_point_in_polygon(p, grown):
				wt[j * w + i] = roundi(_ease(1.0 - (_dist_outline(p, l) - 1.0) / BLEND) * 255.0)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


# ---------------------------------------------------------------- the police's places

## The police's places (scripts/police/police.gd, through builder/lots.gd): the helicopter's base on the heliport (map x,
## y, its deck's z, yaw degrees clockwise from north), where the arrested are let go (before the entrance, facing the
## boulevard).
static func places() -> Dictionary:
	var pad := to_map(HELIPAD.get_center())
	var door := Vector2(-2.0, (ENTRANCE.x + ENTRANCE.y) * 0.5)
	var out := to_map(door)
	var west := yaw_cw(Vector2(-1, 0))
	return {"heli_base": {"x": pad.x, "y": pad.y, "z": FLOOR + ROOFS[2] + PAD_UP, "yaw": west},
			"release": {"x": out.x, "y": out.y, "z": height(door) + sidewalk_lift(door.y), "yaw": west}}


## The car park's police cars (PTA Online's public vehicles: scripts/online/public_vehicles.gd, through
## builder/lots.gd): one in each bay, nose out.
static func vehicles() -> Array:
	var out := []
	var k := 1
	for b: Array in bays():
		var m := to_map(b[1])
		out.append({"id": "commissariat-%d" % k, "model": "police-hatchback", "name": "Commissariat - parking",
				"x": m.x, "y": m.y, "yaw": yaw_cw(b[2])})
		k += 1
	return out


# ---------------------------------------------------------------- helpers

## Local polygon `poly` on the map.
static func map_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(to_map(p))
	return out


static func bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


static func _inside(p: Vector2, poly: PackedVector2Array) -> bool:
	return bounds(poly).has_point(p) and Geometry2D.is_point_in_polygon(p, poly)


static func _grown(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var g := Geometry2D.offset_polygon(poly, d)
	return g[0] if not g.is_empty() else poly


## Polyline `line` as a polygon `half` m either side, its ends round (worked at 10 times the scale: Godot's offsets
## round to a quarter of a unit).
static func _offset_line(line: PackedVector2Array, half: float) -> PackedVector2Array:
	var big := line * Transform2D.IDENTITY.scaled(Vector2(10, 10))
	var out: Array = Geometry2D.offset_polyline(big, half * 10.0, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	return (out[0] as PackedVector2Array) * Transform2D.IDENTITY.scaled(Vector2(0.1, 0.1))


static func _dist_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for i in poly.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return d


static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
