extends RefCounted
## Villa Luxe's place on the map (scripts/villa/villa.gd and its builders share it): its name, its frame, the wall
## round its grounds and its gate. The villa's frame: x east, y up from the house's floor, z south; its origin at the
## front facade's west end (map ORIGIN).

const NAME := "Villa Luxe"
const ID := "villa-luxe"
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


static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, grass: int, water: int,
		grass_colour: Color, gravel := -1) -> Array:
	var wall := PackedVector2Array(WALL)
	var box := Rect2(wall[0], Vector2.ZERO)
	for p in wall:
		box = box.expand(p)
	for k in verts.size():
		var v := verts[k]
		var p := Vector2(v.x, -v.z)
		if box.has_point(p) and ids[k * 4] != water and Geometry2D.is_point_in_polygon(p, wall):
			ids[k * 4] = grass
			colours[k] = grass_colour
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
