extends RefCounted
## The master plan of the supermarket's block (Thomas's plans, ref/superette/): one source for its lots. The block is
## the one the four roads round it close: Losplatos Custom, the Laboratoire de Mécanique (#771), the Service
## Infrastructure (#896) and the 25/8 supermarket in place of the SMAT (#813) and #851 (#785 and #889 out, lawn).
## Its plan is drawn in its streets' frame (local u, v: the map's x, y turned by -ANGLE round PIVOT, where the streets
## run straight; to_map(), to_local(), frame()):
## - the ring: the four roads, ROAD_W wide, one asphalt, kerbed (where the traffic's routes ran); a sidewalk WALK_W wide
##   on the block's side all round, its corners rounded (CORNER), lowered where an access crosses it (gaps()); along
##   Losplatos Custom it is the shop's own front sidewalk (scripts/losplatos/: the shop set square to the street);
## - the ground (height()): the supermarket's site and the roads along it flat (LEVEL), the rest of the ring on a
##   surface fitted to the map's ground (RING_FIT), eased into LEVEL; terraformed so (terraform_zones()), eased back
##   to the map's ground round it;
## - the 25/8 supermarket's lot (superette258, scripts/superette/): the shop, its delivery yard on the north road
##   (lorries in on the west, out on the east, never on the customers' lanes), the customers' one-way flow east to west
##   (in from the south road on the east, the car park, the shop's front, the filling station, out on the west), a
##   footway from the south sidewalk to the shop's doors;
## - the block's own lot (ilot-001, scripts/ilot/ilot_public.gd), the parent of its others (losplatos, superette258):
##   the ground, the ring, the forecourt, the footway, greenery, lights, furniture; its children may terraform inside
##   the block (child_weight()), not under its streets.
## Rect2: its position the south-west corner (u, v).

const ANGLE := -0.0575959                   # rad (-3.3°): the streets' frame turned from the map's
const PIVOT := Vector2(455.0, -130.0)
const LEVEL := 0.85                         # m: the site's ground, flat
## The ring's ground away from the site: a quadratic fitted to the map's ground along it (residual 6 cm rms):
## c0 + c1 uu + c2 vv + c3 uu² + c4 uu vv + c5 vv², (uu, vv) = ((u, v) - PIVOT) / 100.
const RING_FIT := [1.155, 0.3435, -0.4547, -0.6873, 0.0758, 0.0232]
const FLAT := Rect2(419.0, -186.0, 66.0, 110.0)    # LEVEL: the site and the roads along it
const EASE := 20.0                          # m over which the ring's ground eases from LEVEL to RING_FIT
const BLEND := 5.0                          # m over which the terraformed ground eases back to the map's

# the ring
const ROAD_W := 6.5
const WALK_W := 3.0
const CORNER := 5.0                         # m: the kerb's radius round the block's corners
const KERB_LINE := Rect2(386.15, -178.85, 138.2, 95.95)   # the block's kerb (the roads' inner edges)
const INNER := Rect2(389.15, -175.85, 132.2, 89.95)       # the block inside its sidewalks
## The roads (their ends: where the ring's asphalt stops on the roads going on).
const WEST_ROAD := Rect2(379.65, -192.0, 6.5, 122.0)
const SOUTH_ROAD := Rect2(379.65, -185.35, 158.35, 6.5)
const EAST_ROAD := Rect2(524.35, -192.0, 6.5, 115.6)
const NORTH_ROAD := Rect2(379.65, -82.9, 151.2, 6.5)
## The service road between the supermarket and #896 (north road to south road, across the sidewalks).
const SERVICE_ROAD := Rect2(484.0, -175.85, 5.0, 89.95)
## Where Losplatos Custom's front sidewalk is the block's (v along the west side).
const LOSPLATOS_FRONT := Vector2(-173.84, -139.34)
## The map's buildings out: #785, #889 (lawn where they stood).
const DROPPED := ["osm:w198355830", "osm:w71355749"]
const DROPPED_AT := [Rect2(411.2, -177.8, 15.4, 7.1), Rect2(491.6, -178.8, 24.9, 8.0)]   # (their footprints)
## The map's buildings kept in the block (their ground is theirs): #771, #896.
const KEPT := [Rect2(389.4, -120.8, 26.2, 23.7), Rect2(492.5, -163.3, 24.7, 63.7)]

# the 25/8 supermarket's lot
const STORE := Rect2(430.0, -122.0, 48.0, 22.0)
const ENTRANCE := Vector2(454.0, -122.0)    # the shop's doors (the middle of its south front)
const YARD := Rect2(426.0, -100.0, 54.0, 12.0)    # the lorries drive through it, west to east, along the dock
const TRUCK_IN := Rect2(432.0, -88.0, 8.0, 2.1)   # (to the north sidewalk, lowered across it)
const TRUCK_OUT := Rect2(466.0, -88.0, 8.0, 2.1)
const DOCK := Rect2(441.0, -100.0, 22.0, 2.6)     # the loading dock along the shop's back
const WASTE := Rect2(467.0, -100.0, 11.0, 4.0)    # the waste room, against the shop's back (clear of the lorries)
const FRONT_LANE := Rect2(424.0, -134.0, 58.0, 6.0)   # one way, westward
const STATION := Rect2(424.0, -175.85, 26.0, 41.85)   # southward under the canopy or by it; out across the sidewalk
const STATION_EXIT := Vector2(427.0, 434.0)           # (u: its lowered sidewalk)
const TOTEM_BED := Rect2(443.5, -175.85, 6.5, 2.6)    # the price totem's planter, in its south-east corner
const TOTEM := Vector2(446.8, -174.55)
const CANOPY := Rect2(429.0, -160.0, 20.0, 16.0)
const ISLANDS := [434.5, 443.5]            # u of the pumps' islands (north to south under the canopy)
const ENTRY := Rect2(455.0, -175.85, 6.0, 41.85)      # one way, northward, from the south road
const PARKING := Rect2(461.0, -172.0, 16.0, 33.0)     # bays off two eastward aisles (a lawn strip on its north)
const AISLES := [-147.0, -163.0]          # v of the aisles' middles (6 m wide)
const ROWS := [-144.0, -155.0, -160.0, -171.0]   # v of the bays' south ends (5 m deep): north of aisle 1, south of
                                             # it, north of aisle 2, south of it
const RETURN_LANE := Rect2(477.0, -172.0, 5.0, 38.0)  # one way, northward, back to the front lane

# the public spaces in the site
const PLAZA := Rect2(424.0, -128.0, 58.0, 6.0)        # the shop's forecourt
const WALK := Rect2(452.0, -175.85, 3.0, 41.85)       # the footway from the south sidewalk to the shop
## The zebras in the site: over the front lane (the footway to the shop's doors), the entry lane (the car park to it).
const ZEBRAS := [Rect2(452.0, -134.0, 3.0, 6.0), Rect2(455.0, -142.0, 6.0, 3.0)]
## The site: where the block is redone (its ground LEVEL, the map's trees, hedges, props, kerbs and markings out).
const SITE := [Rect2(424.0, -175.85, 60.0, 51.85), Rect2(419.0, -124.0, 65.0, 38.1)]


## The map's point of local p.
static func to_map(p: Vector2) -> Vector2:
	return PIVOT + (p - PIVOT).rotated(ANGLE)


## The local point of the map's p.
static func to_local(m: Vector2) -> Vector2:
	return PIVOT + (m - PIVOT).rotated(-ANGLE)


## The block's frame in the game: a node so placed draws in local (u, height, -v).
static func frame() -> Transform3D:
	var b := Basis(Vector3.UP, ANGLE)
	var p := Vector3(PIVOT.x, 0.0, -PIVOT.y)
	return Transform3D(b, p - b * p)


## The ground's height as designed at local p (the site, the ring).
static func height(p: Vector2) -> float:
	var f := _ease(1.0 - _rect_dist(FLAT, p) / EASE)
	if f >= 1.0:
		return LEVEL
	var uu := (p.x - PIVOT.x) / 100.0
	var vv := (p.y - PIVOT.y) / 100.0
	var c := RING_FIT
	var q: float = c[0] + c[1] * uu + c[2] * vv + c[3] * uu * uu + c[4] * uu * vv + c[5] * vv * vv
	return lerpf(q, LEVEL, f)


## Local point (u, v), h over the designed ground, in the game's frame (the map's).
static func at(u: float, v: float, h := 0.0) -> Vector3:
	var m := to_map(Vector2(u, v))
	return Vector3(m.x, height(Vector2(u, v)) + h, -m.y)


## The ring's roads, cut where they cross (none overlapping; the north-east corner is the bend's, drawn round).
static func road_pieces() -> Array[Rect2]:
	var k := KERB_LINE
	var w0 := WEST_ROAD.position.x
	var s0 := SOUTH_ROAD.position.y
	var e1 := EAST_ROAD.end.x
	return [Rect2(w0, WEST_ROAD.position.y, ROAD_W, s0 - WEST_ROAD.position.y),       # the west road's south end
			Rect2(w0, s0, ROAD_W, WEST_ROAD.end.y - s0),                              # the west road
			Rect2(k.position.x, s0, k.size.x, ROAD_W),                                # the south road
			Rect2(k.end.x, s0, ROAD_W, ROAD_W),                                       # its crossing with the east one
			Rect2(e1, s0, SOUTH_ROAD.end.x - e1, ROAD_W),                             # its east end
			Rect2(k.end.x, EAST_ROAD.position.y, ROAD_W, s0 - EAST_ROAD.position.y),  # the east road's south end
			Rect2(k.end.x, k.position.y, ROAD_W, k.size.y - CORNER),                  # the east road (to the bend)
			Rect2(k.position.x, k.end.y, k.size.x - CORNER, ROAD_W)]                  # the north road (to the bend)


## The sidewalks' sides: [kerb from, kerb to, inward, side] (local, the kerb line between the corners' arcs).
static func walk_sides() -> Array:
	var k := KERB_LINE
	var r := CORNER
	return [[Vector2(k.position.x, k.position.y + r), Vector2(k.position.x, k.end.y - r), Vector2.RIGHT, "W"],
			[Vector2(k.position.x + r, k.position.y), Vector2(k.end.x - r, k.position.y), Vector2(0.0, 1.0), "S"],
			[Vector2(k.end.x, k.position.y + r), Vector2(k.end.x, k.end.y - r), Vector2.LEFT, "E"],
			[Vector2(k.position.x + r, k.end.y), Vector2(k.end.x - r, k.end.y), Vector2(0.0, -1.0), "N"]]


## The corners' centres, south-west first, anticlockwise (the kerb CORNER m round them, the sidewalk's inner edge
## CORNER - WALK_W).
static func corners() -> Array[Vector2]:
	var k := KERB_LINE.grow(-CORNER)
	return [k.position, Vector2(k.end.x, k.position.y), k.end, Vector2(k.position.x, k.end.y)]


## The accesses lowered across the sidewalk: [side, from, to] (along v on "W" and "E", u on "N" and "S").
static func gaps() -> Array:
	return [["W", LOSPLATOS_FRONT.y, -127.34],                          # Losplatos Custom's lane
			["N", 409.5, 415.5],                                         # #771's drive
			["N", TRUCK_IN.position.x, TRUCK_IN.end.x], ["N", TRUCK_OUT.position.x, TRUCK_OUT.end.x],
			["N", SERVICE_ROAD.position.x, SERVICE_ROAD.end.x], ["S", SERVICE_ROAD.position.x, SERVICE_ROAD.end.x],
			["E", -153.5, -143.5], ["E", -113.0, -105.0],                 # #896's
			["S", STATION_EXIT.x, STATION_EXIT.y], ["S", ENTRY.position.x, ENTRY.end.x]]


## Everything paved in the site (no lawn, no grass on it).
static func paved() -> Array[Rect2]:
	return [STORE, YARD, TRUCK_IN, TRUCK_OUT, FRONT_LANE, STATION, ENTRY, PARKING, RETURN_LANE, PLAZA, WALK]


## Whether local p is on the ring (its roads, its sidewalks), `margin` m round them.
static func on_ring(p: Vector2, margin := 0.0) -> bool:
	for r: Rect2 in [WEST_ROAD, SOUTH_ROAD, EAST_ROAD, NORTH_ROAD]:
		if r.grow(margin).has_point(p):
			return true
	return KERB_LINE.grow(margin).has_point(p) and not INNER.grow(-margin).has_point(p)


## Whether local p is in the site.
static func in_site(p: Vector2) -> bool:
	for r: Rect2 in SITE:
		if r.has_point(p):
			return true
	return false


## The block's terraforming (builder/terraform.gd, named by its lots): the ring and the site on height(), eased back to
## the map's ground over BLEND m round them (not into the buildings kept); a 1 m grid on the map.
static func terraform_zones() -> Array:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c: Vector2 in [Vector2(372.0, -199.0), Vector2(545.0, -199.0), Vector2(545.0, -62.0), Vector2(372.0, -62.0)]:
		var m := to_map(c)
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
			sf[j * w + i] = height(p)
			var full := on_ring(p, 1.0) or in_site(p) or SERVICE_ROAD.grow(1.0).has_point(p)
			var out := 0.0 if full else _out_dist(p)
			var near := INF
			if not full:
				for k: Rect2 in KEPT:
					near = minf(near, _rect_dist(k, p))
			wt[j * w + i] = roundi(_ease(1.0 - out / BLEND) * _ease(near / BLEND) * 255.0)
	return [{"box": Rect2(x0, y0 - h, w, h), "x0": x0, "y0": y0, "cell": 1.0, "w": w, "h": h, "wt": wt, "s": sf}]


## Where the block's children's terraforming may act, at the map's (x, y): fully 1 m inside the sidewalks, nowhere on
## the ring.
static func child_weight(x: float, y: float) -> float:
	var p := to_local(Vector2(x, y))
	var i := INNER
	return clampf(minf(minf(p.x - i.position.x, i.end.x - p.x), minf(p.y - i.position.y, i.end.y - p.y)), 0.0, 1.0)


## How far local p is from the ring and the site (BLEND at most).
static func _out_dist(p: Vector2) -> float:
	var d := BLEND
	for r: Rect2 in [WEST_ROAD, SOUTH_ROAD, EAST_ROAD, NORTH_ROAD]:
		d = minf(d, _rect_dist(r.grow(1.0), p))
	var i := INNER.grow(-1.0)
	if i.has_point(p):                               # (inside the block: from the sidewalks' inner edge)
		d = minf(d, minf(minf(p.x - i.position.x, i.end.x - p.x), minf(p.y - i.position.y, i.end.y - p.y)))
	for r: Rect2 in SITE + [SERVICE_ROAD.grow(1.0)]:
		d = minf(d, _rect_dist(r, p))
	return d


static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()
