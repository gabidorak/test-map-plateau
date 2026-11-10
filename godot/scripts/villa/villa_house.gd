extends "res://scripts/villa/villa_kit.gd"
## Villa Luxe's house (scripts/villa/villa.gd places it): a two-storey manor of coursed limestone, dressed stone
## quoins, window surrounds, a band and a cornice, white mullioned windows with light grey louvred shutters, a hipped
## roof of flat clay tiles over the main body and its two garden wings, dormers and two brick chimneys; the oak front
## door under a cornice at the top of the perron; three rising garage doors in the east wing (villa.gd lifts them).
## Inside, its shell: plaster walls, the floors (marble, oak, travertine), the first floor and its U gallery round the
## hall's void (no floor over the hall: 7.2 m to its ceiling), the grand stair (a 4 m flight up to a landing, two
## flights from it to the first floor), wrought-iron railings, the indoor pool hall open to the roof's ceiling with a
## balcony over it. Rooms' furniture: villa_interior.gd.
## Plan (x east 0..40, z south 0..22): the main body z 0..12; the west wing x 0..12 (the indoor pool) and the east
## wing x 28..40 (the garage, the utility room and the cellar; the gym above) z 12..22; the patio between them.

const W := 40.0
const D := 22.0
const T_STONE := 0.33
const T_IN := 0.12
const T := T_STONE + T_IN                   # the outer walls
const T_PART := 0.15                        # the partitions
const CEIL0 := 3.6                          # the ground floor's ceiling
const F1 := 3.9                             # the first floor
const CEIL1 := 7.2                          # its ceiling (and the hall's, and the pool's)
const WALL_TOP := 7.6
const FOOT := -1.6                          # the walls' foot (under the lowest ground round the house)
const PITCH := 0.84                         # the roof: rise per m
const OVER := 0.4                           # its overhang
const RISER := 3.9 / 22.0
const LANDING := RISER * 12.0
const FRONT_WIN := [2.5, 6.5, 10.5, 29.5, 33.5, 37.5]
const HALL_WIN := [17.3, 22.7]
const DOOR := Vector2(18.9, 21.1)           # the front door (x)
const GARAGE_DOOR_H := 2.55
const GARAGE_DOORS := [14.0, 17.0, 20.0]    # z of the garage doors' middles (in the east wall)
const GARAGE_DOORS_MID := Vector3(40.0, 1.2, 17.0)

var _gdoors: Array = []
var _gshapes: Array = []


func _init() -> void:
	super("VillaHouse", {"type": "villa", "name": "Villa Luxe", "id": "villa-luxe", "kind": "a stone manor"})


## The garage's bays in the villa's frame: each car's front (its +z) towards the doors.
static func garage_bays() -> Array:
	var out := []
	var nose := Vector3(1, 0, 0)
	for z: float in GARAGE_DOORS:
		out.append(Transform3D(Basis(Vector3.UP.cross(nose), Vector3.UP, nose), Vector3(37.0, 0.0, z)))
	return out


## Where the garage's terminal is (the villa's frame): on the wall by the door from the utility room.
const GARAGE_TERMINAL := Vector3(34.35, 0.0, 15.2)


func build(meshes := true) -> Node3D:
	_outer_walls()
	_partitions()
	_floors()
	_stairs()
	_railings()
	if meshes:
		_details()
		_roof()
	_garage_doors(meshes)
	root.set_meta("garage_doors", _gdoors)
	root.set_meta("garage_shapes", _gshapes)
	return commit(meshes)


# ---------------------------------------------------------------- walls

## Material m over a wall along `axis` ("x": a along x, b across in z; "z": a along z, b in x) from a0 to a1, b0 to
## b1, y0 to y1, but its holes ([a from, a to, y from, y to]); collision when `solid`.
func _wall(axis: String, a0: float, a1: float, b0: float, b1: float, y0: float, y1: float, holes: Array, m: String,
		solid := true) -> void:
	var hs := []
	for h: Array in holes:
		if float(h[1]) > a0 and float(h[0]) < a1 and float(h[3]) > y0 and float(h[2]) < y1:
			hs.append(h)
	# cut along a at every hole's sides; in each slice, the wall between the holes over it (one above another too)
	var cuts := [a0, a1]
	for h: Array in hs:
		cuts.append(clampf(float(h[0]), a0, a1))
		cuts.append(clampf(float(h[1]), a0, a1))
	cuts.sort()
	for i in cuts.size() - 1:
		var ia: float = cuts[i]
		var ib: float = cuts[i + 1]
		if ib - ia < 0.001:
			continue
		var mid := (ia + ib) * 0.5
		var over := []
		for h: Array in hs:
			if float(h[0]) < mid and float(h[1]) > mid:
				over.append(h)
		over.sort_custom(func(p: Array, q: Array) -> bool: return float(p[2]) < float(q[2]))
		var y := y0
		for h: Array in over:
			if float(h[2]) > y:
				_piece(axis, ia, ib, b0, b1, y, minf(float(h[2]), y1), m, solid)
			y = maxf(y, float(h[3]))
		if y < y1:
			_piece(axis, ia, ib, b0, b1, y, y1, m, solid)


func _piece(axis: String, a0: float, a1: float, b0: float, b1: float, y0: float, y1: float, m: String, solid: bool) -> void:
	if a1 - a0 < 0.001 or y1 - y0 < 0.001:
		return
	if m == "":
		if axis == "x":
			col(a0, a1, y0, y1, b0, b1)
		else:
			col(b0, b1, y0, y1, a0, a1)
		return
	if axis == "x":
		box(m, a0, a1, y0, y1, b0, b1)
		if solid:
			col(a0, a1, y0, y1, b0, b1)
	else:
		box(m, b0, b1, y0, y1, a0, a1)
		if solid:
			col(b0, b1, y0, y1, a0, a1)


## The outer walls' openings: [a from, a to, y from, y to, kind] per wall (kind: "win" a window with shutters,
## "tall" a tall window, "door" the front door, "french" a glazed door, "garage", "glass" a large pane).
static func openings() -> Dictionary:
	var front := []
	for x: float in FRONT_WIN + HALL_WIN:
		front.append([x - 0.7, x + 0.7, 0.05, 2.75, "win"])
		front.append([x - 0.65, x + 0.65, 4.35, 6.3, "win"])
	front.append([DOOR.x, DOOR.y, 0.0, 3.3, "door"])
	front.append([19.25, 20.75, 4.2, 6.6, "french_hi"])
	var west := [[2.3, 3.7, 0.05, 2.75, "win"], [8.3, 9.7, 0.05, 2.75, "win"], [2.35, 3.65, 4.35, 6.3, "win"],
			[6.35, 7.65, 4.35, 6.3, "win"], [13.2, 14.8, 0.05, 5.9, "tall"], [16.2, 17.8, 0.05, 5.9, "tall"],
			[19.2, 20.8, 0.05, 5.9, "tall"]]
	var east := [[3.3, 4.7, 0.05, 2.75, "win"], [7.3, 8.7, 0.05, 2.75, "win"], [3.35, 4.65, 4.35, 6.3, "win"],
			[7.35, 8.65, 4.35, 6.3, "win"], [15.8, 18.2, 4.1, 6.8, "glass"]]
	for z: float in GARAGE_DOORS:
		east.append([z - 1.4, z + 1.4, 0.0, GARAGE_DOOR_H, "garage"])
	var south_w := [[1.7, 3.5, 0.05, 5.9, "tall"], [5.1, 6.9, 0.05, 5.9, "tall"], [8.5, 10.3, 0.05, 5.9, "tall"]]
	var south_e := [[30.0, 31.0, 1.2, 2.3, "win_small"], [36.5, 37.5, 1.2, 2.3, "win_small"],
			[29.2, 31.8, 4.1, 6.8, "glass"], [32.7, 35.3, 4.1, 6.8, "glass"], [36.2, 38.8, 4.1, 6.8, "glass"]]
	var back := [[12.4, 14.6, 0.0, 2.8, "french"], [25.4, 27.6, 0.0, 2.8, "french"], [13.35, 14.65, 4.35, 6.3, "win"],
			[25.35, 26.65, 4.35, 6.3, "win"], [19.25, 20.75, 4.4, 6.6, "tall_hi"]]
	var wing_w := [[13.2, 14.8, 0.05, 5.9, "tall"], [16.0, 18.0, 0.0, 2.8, "french"], [19.2, 20.8, 0.05, 5.9, "tall"]]
	var wing_e := [[13.6, 14.6, 1.2, 2.3, "win_small"], [14.0, 16.4, 4.1, 6.8, "glass"], [17.6, 20.0, 4.1, 6.8, "glass"]]
	return {"front": front, "west": west, "east": east, "south_w": south_w, "south_e": south_e, "back": back,
			"wing_w": wing_w, "wing_e": wing_e}


func _outer_walls() -> void:
	var o := openings()
	var s := T_STONE
	var t := T
	# stone (outside), plaster (inside)
	_wall("x", 0.0, W, 0.0, s, FOOT, WALL_TOP, o["front"], "stone")
	_wall("x", s, W - s, s, t, 0.0, CEIL1, o["front"], "plaster", false)
	_wall("z", s, D - s, 0.0, s, FOOT, WALL_TOP, o["west"], "stone")
	_wall("z", t, D - t, s, t, 0.0, CEIL1, o["west"], "plaster", false)
	_wall("z", s, D - s, W - s, W, FOOT, WALL_TOP, o["east"], "stone")
	_wall("z", t, D - t, W - t, W - s, 0.0, CEIL1, o["east"], "plaster", false)
	_wall("x", 0.0, 12.0, D - s, D, FOOT, WALL_TOP, o["south_w"], "stone")
	_wall("x", t, 12.0 - t, D - t, D - s, 0.0, CEIL1, o["south_w"], "plaster", false)
	_wall("x", 28.0, W, D - s, D, FOOT, WALL_TOP, o["south_e"], "stone")
	_wall("x", 28.0 + t, W - t, D - t, D - s, 0.0, CEIL1, o["south_e"], "plaster", false)
	_wall("x", 12.0 - s, 28.0 + s, 12.0 - s, 12.0, FOOT, WALL_TOP, o["back"], "stone")
	_wall("x", 12.0 - t, 28.0 + t, 12.0 - t, 12.0 - s, 0.0, CEIL1, o["back"], "plaster", false)
	_wall("z", 12.0, D - s, 12.0 - s, 12.0, FOOT, WALL_TOP, o["wing_w"], "stone")
	_wall("z", 12.0 + t - s, D - t, 12.0 - t, 12.0 - s, 0.0, CEIL1, o["wing_w"], "plaster", false)
	_wall("z", 12.0, D - s, 28.0, 28.0 + s, FOOT, WALL_TOP, o["wing_e"], "stone")
	_wall("z", 12.0 + t - s, D - t, 28.0 + s, 28.0 + t, 0.0, CEIL1, o["wing_e"], "plaster", false)
	# the windows' glass stops whoever walks into it (the doors stay open)
	var lines := {"front": ["x", 0.0, s], "west": ["z", 0.0, s], "east": ["z", W - s, W], "south_w": ["x", D - s, D],
			"south_e": ["x", D - s, D], "back": ["x", 12.0 - s, 12.0], "wing_w": ["z", 12.0 - s, 12.0],
			"wing_e": ["z", 28.0, 28.0 + s]}
	for k: String in lines:
		var l: Array = lines[k]
		for h: Array in o[k]:
			if h[4] in ["french", "door", "garage"]:
				continue
			_piece(l[0], h[0], h[1], l[1], l[2], h[2], h[3], "", true)


## The partitions: [axis, a0, a1, b (the wall's middle), y0, y1, holes].
func _partitions() -> void:
	var p := T_PART * 0.5
	var walls := [
		# ground floor
		["z", T, 12.0 - T, 15.0, 0.0, CEIL0, [[3.6, 6.2, 0.0, 2.9]]],
		["z", T, 12.0 - T, 25.0, 0.0, CEIL0, [[3.6, 6.2, 0.0, 2.9]]],
		["z", T, 2.0, 32.0, 0.0, CEIL0, []], ["z", 8.0, 12.0 - T, 32.0, 0.0, CEIL0, []],
		["x", 28.0 + T, W - T, 12.0, 0.0, CEIL0, [[32.4, 33.4, 0.0, 2.3]]],
		["z", 12.0, D - T, 34.0, 0.0, CEIL0, [[13.0, 14.0, 0.0, 2.3]]],
		["x", 28.0 + T, 34.0, 17.0, 0.0, CEIL0, [[30.0, 31.0, 0.0, 2.3]]],
		# first floor
		["z", T, 9.0, 9.0, F1, CEIL1, [[7.2, 8.1, F1, F1 + 2.3]]],
		["x", 9.0, 15.0, 5.5, F1, CEIL1, [[11.0, 11.9, F1, F1 + 2.3]]],
		["x", T, 15.0, 9.0, F1, CEIL1, [[6.0, 7.0, F1, F1 + 2.3]]],
		["z", T, 9.0, 15.0, F1, CEIL1, []],
		["z", T, 9.0, 25.0, F1, CEIL1, []],
		["x", 25.0, W - T, 9.0, F1, CEIL1, [[27.0, 28.0, F1, F1 + 2.3], [34.0, 35.0, F1, F1 + 2.3]]],
		["z", T, 9.0, 32.5, F1, CEIL1, []],
		["x", 29.5, 32.5, 6.0, F1, CEIL1, []], ["z", 6.0, 9.0, 29.5, F1, CEIL1, [[7.0, 7.8, F1, F1 + 2.2]]],
		["x", 37.0, W - T, 6.0, F1, CEIL1, []], ["z", 6.0, 9.0, 37.0, F1, CEIL1, [[7.0, 7.8, F1, F1 + 2.2]]],
		["x", 28.0 + T, W - T, 12.0, F1, CEIL1, [[33.0, 35.0, F1, F1 + 2.5]]],
	]
	for w: Array in walls:
		_wall(w[0], w[1], w[2], float(w[3]) - p, float(w[3]) + p, w[4], w[5], w[6], "plaster")
	# the doorways' oak casings
	for w: Array in walls:
		for h: Array in w[6]:
			_casing(w[0], h[0], h[1], float(w[3]), h[2], h[3])
	# the glass wall between the salon and the indoor pool: steel frames, a doorway in its middle
	var gz := 12.0 - T + 0.06
	for x: float in [T, 3.2, 5.2, 6.8, 8.8, 12.0 - T]:
		box("iron", x - 0.04, x + 0.04, 0.0, CEIL0, gz - 0.04, gz + 0.04)
	box("iron", T, 12.0 - T, CEIL0 - 0.08, CEIL0, gz - 0.04, gz + 0.04)
	box("iron", T, 12.0 - T, 2.6, 2.66, gz - 0.03, gz + 0.03)
	for r: Vector2 in [Vector2(T, 5.2), Vector2(6.8, 12.0 - T)]:
		box("glass", r.x, r.y, 0.0, CEIL0 - 0.08, gz - 0.01, gz + 0.01)
		col(r.x, r.y, 0.0, CEIL0, gz - 0.05, gz + 0.05)
	box("glass", 5.2, 6.8, 2.66, CEIL0 - 0.08, gz - 0.01, gz + 0.01)
	# the wall over the glass, up to the first floor (the pool hall's side of the slab edge)
	box("plaster", T, 12.0 - T, CEIL0, F1, 12.0 - T, 12.0 - T + 0.12)


## A doorway's oak casing: its jambs and head 1 cm into the opening (off the wall's reveals' planes).
func _casing(axis: String, a0: float, a1: float, b: float, y0: float, y1: float) -> void:
	var c := 0.07
	var half := T_PART * 0.5 + 0.02
	if axis == "x":
		box("oak", a0 - c, a0 + 0.01, y0, y1 - 0.01, b - half, b + half)
		box("oak", a1 - 0.01, a1 + c, y0, y1 - 0.01, b - half, b + half)
		box("oak", a0 - c, a1 + c, y1 - 0.01, y1 + c, b - half, b + half)
	else:
		box("oak", b - half, b + half, y0, y1 - 0.01, a0 - c, a0 + 0.01)
		box("oak", b - half, b + half, y0, y1 - 0.01, a1 - 0.01, a1 + c)
		box("oak", b - half, b + half, y1 - 0.01, y1 + c, a0 - c, a1 + c)


# ---------------------------------------------------------------- floors

func _floors() -> void:
	# the ground floor: a slab, its rooms' floors
	for r0: Rect2 in [Rect2(0, 0, W, 12), Rect2(28, 12, 12, 10)]:
		var r := _inside(r0)
		box("ashlar", r.position.x, r.end.x, -0.4, -0.02, r.position.y, r.end.y)
		col(r.position.x, r.end.x, -0.4, 0.0, r.position.y, r.end.y)
	var rooms := [[Rect2(T, T, 15.0 - T, 12.0 - 2 * T), "oak_floor"], [Rect2(15, T, 10, 12.0 - 2 * T), "marble"],
			[Rect2(25, T, 7, 12.0 - 2 * T), "oak_floor"], [Rect2(32, T, 8.0 - T, 12.0 - 2 * T), "oak_floor"],
			[Rect2(T, 12.0 - T, 12.0 - 2 * T, 10.0), "travertine"], [Rect2(28.0 + T, 12.0, 6.0 - T, 10.0 - T), "travertine"],
			[Rect2(34, 12, 6.0 - T, 10.0 - T), "travertine"]]
	for r: Array in rooms:
		var q: Rect2 = r[0]
		if r[1] == "travertine" and q.position.x < 1.0:
			_pool_floor(q)
			continue
		box(r[1], q.position.x, q.end.x, -0.02, 0.0, q.position.y, q.end.y)
	# the first floor: the slab (the ceiling below), the rooms' floors on it
	var slabs := [Rect2(0, 0, 15, 12), Rect2(25, 0, 15, 12), Rect2(15, 0, 10, 2), Rect2(15, 2, 1.5, 7.9),
			Rect2(23.5, 2, 1.5, 7.9), Rect2(28, 12, 12, 10)]
	for r0: Rect2 in slabs:
		var r := _inside(r0)
		box("ceiling", r.position.x, r.end.x, CEIL0, F1 - 0.02, r.position.y, r.end.y)
		col(r.position.x, r.end.x, CEIL0, F1, r.position.y, r.end.y)
	var tops := [[Rect2(0, 0, 9, 9), "oak_floor"], [Rect2(9, 0, 6, 5.5), "marble_blue"], [Rect2(9, 5.5, 6, 3.5), "oak_floor"],
			[Rect2(0, 9, 15, 3), "oak_floor"], [Rect2(15, 0, 10, 2), "oak_floor"], [Rect2(15, 2, 1.5, 7.9), "oak_floor"],
			[Rect2(23.5, 2, 1.5, 7.9), "oak_floor"], [Rect2(25, 0, 15, 9), "oak_floor"], [Rect2(25, 9, 15, 3), "oak_floor"],
			[Rect2(28, 12, 12, 10), "herringbone"]]
	for r: Array in tops:
		var q: Rect2 = _inside(r[0])
		box(r[1], q.position.x, q.end.x, F1 - 0.02, F1, q.position.y, q.end.y)
	# the ceilings: the first floor's (and the hall's, the pool hall's sky) under the roof
	var c0 := _inside(Rect2(0, 0, W, 12))
	var c1 := _inside(Rect2(28, 12, 12, 10))
	box("ceiling", c0.position.x, c0.end.x, CEIL1, CEIL1 + 0.15, c0.position.y, c0.end.y)
	box("ceiling", c1.position.x, c1.end.x, CEIL1, CEIL1 + 0.15, c1.position.y, c1.end.y)


## Rectangle r (a floor, a slab, a ceiling) kept inside the outer walls' stone: its sides on the facades' lines
## stopped T_STONE short of them (their faces not in the facades' planes).
func _inside(r: Rect2) -> Rect2:
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var s := T_STONE + 0.005
	if x0 <= 0.001 or (absf(x0 - 28.0) < 0.001 and z0 >= 11.999):
		x0 += s
	if x1 >= W - 0.001 or (absf(x1 - 12.0) < 0.001 and z0 >= 11.999):
		x1 -= s
	if z0 <= 0.001:
		z0 += s
	if z1 >= D - 0.001 or (absf(z1 - 12.0) < 0.001 and x0 < 28.0 and x1 > 12.0):
		z1 -= s
	return Rect2(x0, z0, x1 - x0, z1 - z0)
	box("sky", T, 12.0 - T, CEIL1, CEIL1 + 0.15, 12.0 - T + 0.12, D - T)


## The indoor pool hall's floor: travertine round the basin (sunk in the slab), its water.
func _pool_floor(q: Rect2) -> void:
	var c := Vector2(6.0, 17.2)
	var half := Vector2(4.0, 2.2)
	var pool := Rect2(c - half, half * 2.0)
	for r: Rect2 in [Rect2(q.position, Vector2(q.size.x, pool.position.y - q.position.y)),
			Rect2(Vector2(q.position.x, pool.end.y), Vector2(q.size.x, q.end.y - pool.end.y)),
			Rect2(Vector2(q.position.x, pool.position.y), Vector2(pool.position.x - q.position.x, pool.size.y)),
			Rect2(Vector2(pool.end.x, pool.position.y), Vector2(q.end.x - pool.end.x, pool.size.y))]:
		box("travertine", r.position.x, r.end.x, -0.02, 0.0, r.position.y, r.end.y)
		box("ashlar", r.position.x, r.end.x, -0.4, -0.02, r.position.y, r.end.y)
		col(r.position.x, r.end.x, -0.4, 0.0, r.position.y, r.end.y)
	box("ashlar", 0.0, 12.0, -0.4, -0.02, 12.0, T)
	box("ashlar", 0.0, 12.0, -0.4, -0.02, D - T, D)
	box("ashlar", 0.0, T, -0.4, -0.02, 12.0, D)
	box("ashlar", 12.0 - T, 12.0, -0.4, -0.02, 12.0, D)
	# its basin: mosaic sides and floor, a band of dark marble round it, the water
	var depth := 0.9
	box("mosaic", pool.position.x, pool.end.x, -depth - 0.1, -depth, pool.position.y, pool.end.y)
	col(pool.position.x, pool.end.x, -depth - 0.4, -depth, pool.position.y, pool.end.y)
	for e: Array in [[pool.position.x, pool.end.x, pool.position.y, pool.position.y + 0.05],
			[pool.position.x, pool.end.x, pool.end.y - 0.05, pool.end.y],
			[pool.position.x, pool.position.x + 0.05, pool.position.y + 0.05, pool.end.y - 0.05],
			[pool.end.x - 0.05, pool.end.x, pool.position.y + 0.05, pool.end.y - 0.05]]:
		box("mosaic", e[0], e[1], -depth, -0.03, e[2], e[3])
	box("wood_dark", pool.position.x - 0.4, pool.end.x + 0.4, -0.01, 0.007, pool.position.y - 0.4, pool.position.y)
	box("wood_dark", pool.position.x - 0.4, pool.end.x + 0.4, -0.01, 0.007, pool.end.y, pool.end.y + 0.4)
	box("wood_dark", pool.position.x - 0.4, pool.position.x, -0.01, 0.007, pool.position.y, pool.end.y)
	box("wood_dark", pool.end.x, pool.end.x + 0.4, -0.01, 0.007, pool.position.y, pool.end.y)
	# steps out at its east end, a ramp up them
	for k in 3:
		var w := 0.45 * (3 - k)
		box("travertine", pool.end.x - 0.05 - w, pool.end.x - 0.05, -depth, -depth + depth * (k + 1) / 4.0, 15.8, 18.6)
	col_ramp(Vector3(pool.end.x - 1.45, -depth, 17.2), Vector3(pool.end.x, 0.0, 17.2), 2.8)
	box("water_in", pool.position.x, pool.end.x, -0.17, -0.15, pool.position.y, pool.end.y)
	root.set_meta("indoor_pool", pool)


# ---------------------------------------------------------------- the grand stair

func _stairs() -> void:
	var back := 12.0 - T
	# the central flight: 12 steps from the hall's floor up to the landing against the back wall
	for k in 12:
		var z0 := 4.4 + k * 0.3
		box("marble", 18.0, 22.0, 0.0, RISER * (k + 1), z0, z0 + 0.3)
		box("marble", 17.98, 22.02, RISER * (k + 1) - 0.03, RISER * (k + 1) + 0.005, z0 - 0.02, z0 + 0.3)
	box("marble", 18.0, 22.0, 0.0, LANDING, 8.0, back)
	col_ramp(Vector3(20.0, 0.0, 4.4), Vector3(20.0, LANDING, 8.0), 4.0)
	col(18.0, 22.0, 0.0, LANDING, 8.0, back)
	# the two flights from the landing up to the first floor, west and east along the back wall
	for side: float in [-1.0, 1.0]:
		var x0 := 18.0 if side < 0.0 else 22.0
		for k in 10:
			var xa := x0 + side * k * 0.3
			var xb := xa + side * 0.3
			var y := LANDING + RISER * (k + 1)
			box("marble", minf(xa, xb), maxf(xa, xb), 0.0, y, 9.9, back)
			box("marble", minf(xa, xb) - 0.02, maxf(xa, xb) + 0.02, y - 0.03, y + 0.005, 9.88, back)
		var x1 := x0 + side * 3.0
		col_ramp(Vector3(x0, LANDING, (9.9 + back) * 0.5), Vector3(x1, F1, (9.9 + back) * 0.5), back - 9.9)
		for k in 10:
			var xa := x0 + side * k * 0.3
			col(minf(xa, xa + side * 0.3), maxf(xa, xa + side * 0.3), 0.0, LANDING + RISER * k, 9.9, back)
	# the stair's sides in dark marble skirting
	box("wood_dark", 17.96, 18.0, 0.0, 0.12, 4.4, 8.0)
	box("wood_dark", 22.0, 22.04, 0.0, 0.12, 4.4, 8.0)


# ---------------------------------------------------------------- railings

## A wrought-iron railing from a to b (feet), 1 m high: bars, rings between the rails, an oak handrail; collision.
func _railing(a: Vector3, b: Vector3, solid := true) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	if length < 0.05:
		return
	var n := maxi(1, ceili(length / 0.12))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		rod("iron", p, p + Vector3(0, 0.95, 0), 0.011, 5)
	var h := Vector3(0, 0.95, 0)
	rod("iron", a + Vector3(0, 0.08, 0), b + Vector3(0, 0.08, 0), 0.016, 5)
	rod("iron", a + Vector3(0, 0.78, 0), b + Vector3(0, 0.78, 0), 0.014, 5)
	rod("walnut", a + h, b + h, 0.035, 8)
	var rings := maxi(1, int(length / 0.45))
	for i in rings:
		var p := a.lerp(b, (i + 0.5) / rings) + Vector3(0, 0.43, 0)
		var dir := Vector3(d.x, 0, d.z).normalized()
		torus("iron", Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).rotated(dir, 0.0) * Basis(Vector3.RIGHT, PI * 0.5),
				p), 0.14, 0.165)
	if solid:
		var mid := (a + b) * 0.5 + Vector3(0, 0.5, 0)
		var along := Vector3(d.x, 0, d.z).normalized()
		var basis := Basis(along.cross(Vector3.UP).normalized(), Vector3.UP, along)
		col_xf(Transform3D(basis, mid), Vector3(0.08, 1.0 + absf(d.y), length))


func _railings() -> void:
	# the central flight's sides (open to the hall), the landing's edges
	for x: float in [18.0, 22.0]:
		_railing(Vector3(x, 0.15, 4.5), Vector3(x, LANDING, 8.0))
		_railing(Vector3(x, LANDING, 8.0), Vector3(x, LANDING, 9.9))
	# the two upper flights' open side (to the hall)
	_railing(Vector3(18.0, LANDING, 9.9), Vector3(15.1, F1, 9.9))
	_railing(Vector3(22.0, LANDING, 9.9), Vector3(24.9, F1, 9.9))
	# the U gallery round the hall's void
	_railing(Vector3(16.5, F1, 2.0), Vector3(23.5, F1, 2.0))
	_railing(Vector3(16.5, F1, 2.0), Vector3(16.5, F1, 9.85))
	_railing(Vector3(23.5, F1, 2.0), Vector3(23.5, F1, 9.85))
	# the balcony over the indoor pool
	_railing(Vector3(T, F1, 12.0 - T + 0.15), Vector3(12.0 - T, F1, 12.0 - T + 0.15))
	# the front window's balconet
	_railing(Vector3(19.2, F1 - 0.1, -0.12), Vector3(20.8, F1 - 0.1, -0.12), false)


# ---------------------------------------------------------------- the facades' details

func _details() -> void:
	var o := openings()
	# [wall, the outer face's line, outward sign, axis]
	var faces := [["front", 0.0, -1.0, "x"], ["west", 0.0, -1.0, "z"], ["east", W, 1.0, "z"], ["south_w", D, 1.0, "x"],
			["south_e", D, 1.0, "x"], ["back", 12.0, 1.0, "x"], ["wing_w", 12.0, 1.0, "z"], ["wing_e", 28.0, -1.0, "z"]]
	for f: Array in faces:
		for h: Array in o[f[0]]:
			_opening(h, f[1], f[2], f[3])
	# the plinth, the band between the floors, the cornice: dressed stone round the outline
	var outline := [Vector2(0, 0), Vector2(W, 0), Vector2(W, D), Vector2(28, D), Vector2(28, 12), Vector2(12, 12),
			Vector2(12, D), Vector2(0, D)]
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var t := (b - a).normalized()
		var out := Vector2(t.y, -t.x)           # (the outline runs clockwise seen from above: out is to its left)
		for band: Array in [[FOOT, 0.02, 0.05, "ashlar"], [F1 - 0.2, F1 + 0.02, 0.06, "ashlar"],
				[WALL_TOP - 0.45, WALL_TOP - 0.25, 0.1, "coping"], [WALL_TOP - 0.25, WALL_TOP, 0.18, "coping"]]:
			var e: float = band[2]
			var e0 := e if _convex(outline, i) else -e
			var e1 := e if _convex(outline, (i + 1) % outline.size()) else -e
			var q0 := a - t * e0 - out * 0.02
			var q1 := b + t * e1 + out * e
			box(band[3], minf(q0.x, q1.x), maxf(q0.x, q1.x), band[0], band[1], minf(q0.y, q1.y), maxf(q0.y, q1.y))
	# the quoins at the outer corners
	for c: Array in [[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)], [Vector2(W, 0), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(W, D), Vector2(-1, 0), Vector2(0, -1)], [Vector2(28, D), Vector2(1, 0), Vector2(0, -1)],
			[Vector2(12, D), Vector2(-1, 0), Vector2(0, -1)], [Vector2(0, D), Vector2(1, 0), Vector2(0, -1)]]:
		var p: Vector2 = c[0]
		var ax: Vector2 = c[1]
		var az: Vector2 = c[2]
		var y := 0.05
		var k := 0
		while y < WALL_TOP - 0.55:
			var long := 0.9 if k % 2 == 0 else 0.5
			var short := 0.5 if k % 2 == 0 else 0.9
			_corner_box(p, ax, az, -0.03, long, -0.03, 0.0, y, y + 0.38)
			_corner_box(p, ax, az, -0.03, 0.0, 0.0, short, y, y + 0.38)
			y += 0.42
			k += 1
	# the front door: oak leaves with panels, a fanlight, a dressed stone surround and cornice, lanterns
	var dz := 0.2
	for side: float in [-1.0, 1.0]:
		var hx := DOOR.x + 0.04 if side < 0.0 else DOOR.y - 0.11
		box("door_oak", hx, hx + 0.07, 0.0, 2.75, T + 0.02, T + 1.12)
		for y: Vector2 in [Vector2(0.25, 1.25), Vector2(1.45, 2.55)]:
			var px := hx + 0.07 if side < 0.0 else hx - 0.015
			box("walnut", px, px + 0.015, y.x, y.y, T + 0.2, T + 0.94)
	box("door_oak", DOOR.x, DOOR.y, 2.75, 2.85, dz, dz + 0.08)
	box("glass", DOOR.x + 0.05, DOOR.y - 0.05, 2.85, 3.28, dz + 0.03, dz + 0.04)
	box("frame", 19.98, 20.02, 2.85, 3.28, dz + 0.02, dz + 0.05)
	for x: float in [DOOR.x - 0.22, DOOR.y + 0.22]:
		box("ashlar", x - 0.22, x + 0.22, 0.0, 3.45, -0.06, 0.0)
	box("coping", DOOR.x - 0.6, DOOR.y + 0.6, 3.45, 3.62, -0.16, 0.0)
	box("coping", DOOR.x - 0.5, DOOR.y + 0.5, 3.3, 3.45, -0.08, 0.0)
	for x: float in [DOOR.x - 0.75, DOOR.y + 0.75]:
		var p := Vector3(x, 2.45, -0.06)
		box("iron", x - 0.03, x + 0.03, 2.3, 2.5, -0.2, -0.0)
		box("iron", x - 0.12, x + 0.12, 2.48, 2.52, -0.32, -0.08)
		box("glass", x - 0.1, x + 0.1, 2.52, 2.82, -0.3, -0.1)
		ball("bulb", Vector3(x, 2.66, -0.2), Vector3(0.05, 0.07, 0.05), 6)
		cyl("iron", Vector3(x, 2.82, -0.2), 0.16, 0.12, 4, 0.02)
	# the wisteria round the door
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for side: float in [-1.0, 1.0]:
		var x0 := 20.0 + side * 2.3
		for i in 18:
			var y := rng.randf_range(0.4, 4.4)
			var x := x0 + side * rng.randf_range(-0.4, 1.4) * (0.4 + y / 4.4)
			ball("vine", Vector3(x, y, -0.12), Vector3(rng.randf_range(0.25, 0.5), rng.randf_range(0.2, 0.35), 0.16), 7)
		rod("wood_dark", Vector3(x0, 0.0, -0.1), Vector3(x0 + side * 0.4, 3.8, -0.1), 0.04, 5)
	# the downpipes at the corners
	for p: Vector2 in [Vector2(0.25, -0.12), Vector2(W - 0.25, -0.12), Vector2(-0.12, D - 0.25), Vector2(W + 0.12, D - 0.25)]:
		cyl("zinc", Vector3(p.x, -0.6, p.y), 0.05, WALL_TOP + 0.4, 8)


## A dressed stone block at corner p: from u0 to u1 along u, v0 to v1 along v (the walls' directions from it).
func _corner_box(p: Vector2, u: Vector2, v: Vector2, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	var q0 := p + u * u0 + v * v0
	var q1 := p + u * u1 + v * v1
	box("ashlar", minf(q0.x, q1.x), maxf(q0.x, q1.x), y0, y1, minf(q0.y, q1.y), maxf(q0.y, q1.y))


## Whether the outline turns outwards (a convex corner) at vertex i.
func _convex(outline: Array, i: int) -> bool:
	var a: Vector2 = outline[(i - 1 + outline.size()) % outline.size()]
	var b: Vector2 = outline[i]
	var c: Vector2 = outline[(i + 1) % outline.size()]
	return (b - a).cross(c - b) > 0.0


## An opening's dressing on a facade (`line` the face, `sign` outward, `axis` along): its stone surround and sill,
## its window (white frame, glazing bars, glass) or door, the shutters beside it.
func _opening(h: Array, line: float, sign: float, axis: String) -> void:
	var a0: float = h[0]
	var a1: float = h[1]
	var y0: float = h[2]
	var y1: float = h[3]
	var kind: String = h[4]
	var out := line + sign * 0.05                # the surround's face
	var glass_at := line - sign * 0.14           # the window set back in the opening
	var put := func(m: String, p0: float, p1: float, q0: float, q1: float, b0: float, b1: float) -> void:
		if axis == "x":
			box(m, p0, p1, q0, q1, minf(b0, b1), maxf(b0, b1))
		else:
			box(m, minf(b0, b1), maxf(b0, b1), q0, q1, p0, p1)
	if kind == "door":
		return
	var stone := kind not in ["garage", "glass"]
	if stone:
		var s := 0.17
		put.call("ashlar", a0 - s, a0, y0 - 0.05, y1 + s, line, out)
		put.call("ashlar", a1, a1 + s, y0 - 0.05, y1 + s, line, out)
		put.call("ashlar", a0 - s, a1 + s, y1, y1 + s, line, out)
		if y0 > 0.02:
			put.call("coping", a0 - s - 0.05, a1 + s + 0.05, y0 - 0.08, y0, line + sign * 0.1, line - sign * 0.02)
		if kind in ["tall", "tall_hi", "french_hi"]:
			put.call("coping", a0 - s - 0.06, a1 + s + 0.06, y1 + s, y1 + s + 0.12, line, line + sign * 0.12)
	else:
		put.call("charcoal", a0 - 0.06, a0, y0, y1, line, line + sign * 0.03)
		put.call("charcoal", a1, a1 + 0.06, y0, y1, line, line + sign * 0.03)
		put.call("charcoal", a0 - 0.06, a1 + 0.06, y1, y1 + 0.06, line, line + sign * 0.03)
	if kind == "garage":
		return
	var fm := "iron" if kind == "glass" else "frame"
	var f := 0.07
	var b0 := glass_at - sign * 0.03
	var b1 := glass_at + sign * 0.03
	if kind == "french":
		# glazed doors opened in against the reveals
		put.call(fm, a0, a1, y1 - f, y1, b0, b1)
		var inner := line - sign * T
		var w := (a1 - a0) * 0.5 - 0.05
		for e: Array in [[a0 + 0.02, a0 + 0.08], [a1 - 0.08, a1 - 0.02]]:
			put.call(fm, e[0], e[1], 0.0, y1 - f, inner, inner - sign * w)
		return
	a0 += 0.012                                 # (the frame 1 cm inside the opening: off its reveals' planes)
	a1 -= 0.012
	y1 -= 0.012
	if y0 > 0.02:
		y0 += 0.012
	put.call(fm, a0, a0 + f, y0, y1, b0, b1)
	put.call(fm, a1 - f, a1, y0, y1, b0, b1)
	put.call(fm, a0, a1, y1 - f, y1, b0, b1)
	put.call(fm, a0, a1, y0, y0 + f, b0, b1)
	put.call("glass_win", a0 + f, a1 - f, y0 + f, y1 - f, glass_at - 0.006, glass_at + 0.006)
	var mid := (a0 + a1) * 0.5
	if kind in ["win", "tall", "tall_hi", "french", "french_hi", "win_small"]:
		put.call(fm, mid - 0.025, mid + 0.025, y0, y1, b0 + sign * 0.01, b1 + sign * 0.01)
		var rows := 3 if (y1 - y0) > 2.2 else (2 if (y1 - y0) > 1.4 else 1)
		if kind in ["tall", "tall_hi"]:
			rows = 5
		for r in range(1, rows + 1):
			var y := y0 + (y1 - y0) * r / (rows + 1)
			put.call(fm, a0, a1, y - 0.02, y + 0.02, b0 + sign * 0.01, b1 + sign * 0.01)
	elif kind == "glass":
		put.call(fm, mid - 0.03, mid + 0.03, y0, y1, b0, b1)
	# the shutters, folded back against the facade
	if kind == "win":
		var w := (a1 - a0) * 0.5
		var sb0 := line + sign * 0.05
		var sb1 := line + sign * 0.09
		put.call("shutter", a0 - 0.2 - w, a0 - 0.2, y0, y1, sb0, sb1)
		put.call("shutter", a1 + 0.2, a1 + 0.2 + w, y0, y1, sb0, sb1)
		for e: float in [a0 - 0.2 - w, a0 - 0.24, a1 + 0.2, a1 + 0.16 + w]:
			put.call("frame", e, e + 0.04, y0, y1, sb1, sb1 + sign * 0.005)


# ---------------------------------------------------------------- the roof

## The roof over the main body and the wings, hipped all round at one pitch: the highest of the three hip roofs
## (each over its rectangle grown by the overhang) at each point of a grid aligned on its hips and valleys; dormers
## on the front slope, two chimneys; the soffit and the gutter round it.
func _roof() -> void:
	var rects := [Rect2(-OVER, -OVER, W + 2 * OVER, 12 + 2 * OVER), Rect2(-OVER, -OVER, 12 + 2 * OVER, D + 2 * OVER),
			Rect2(28 - OVER, -OVER, 12 + 2 * OVER, D + 2 * OVER)]
	var eave := WALL_TOP + 0.04 - OVER * PITCH
	var h := func(x: float, z: float) -> float:
		var best := -1.0
		for r: Rect2 in rects:
			if r.grow(0.001).has_point(Vector2(x, z)):
				var d := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
				best = maxf(best, d)
		return best
	var step := 0.4
	var nx := int(round((W + 2 * OVER) / step))
	var nz := int(round((D + 2 * OVER) / step))
	var st := tool("roof")
	for i in nx:
		for j in nz:
			var x0 := -OVER + i * step
			var z0 := -OVER + j * step
			var cx := x0 + step * 0.5
			var cz := z0 + step * 0.5
			if float(h.call(cx, cz)) < 0.0:
				continue
			var p := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for q in 4:
				var v: Vector3 = p[q]
				v.y = eave + maxf(float(h.call(v.x, v.z)), 0.0) * PITCH
				p[q] = v
			# the diagonal through the cell's crease
			var hc := eave + float(h.call(cx, cz)) * PITCH
			var d02 := absf(((p[0] as Vector3).y + (p[2] as Vector3).y) * 0.5 - hc)
			var d13 := absf(((p[1] as Vector3).y + (p[3] as Vector3).y) * 0.5 - hc)
			var tris := [[p[0], p[1], p[2]], [p[0], p[2], p[3]]] if d02 <= d13 else [[p[0], p[1], p[3]], [p[1], p[2], p[3]]]
			for t: Array in tris:
				_roof_tri(st, t[0], t[1], t[2])
	# the soffit and the gutter along the eaves
	var outline := [Vector2(-OVER, -OVER), Vector2(W + OVER, -OVER), Vector2(W + OVER, D + OVER), Vector2(28 - OVER, D + OVER),
			Vector2(28 - OVER, 12 + OVER), Vector2(12 + OVER, 12 + OVER), Vector2(12 + OVER, D + OVER), Vector2(-OVER, D + OVER)]
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var horizontal := absf(a.y - b.y) < 0.01
		var e := 0.07
		if horizontal:
			box("zinc", lo.x - e, hi.x + e, eave - 0.14, eave + 0.02, lo.y - e, hi.y + e)
		else:
			box("zinc", lo.x - e, hi.x + e, eave - 0.14, eave + 0.02, lo.y - e, hi.y + e)
	for r: Rect2 in rects:
		box("frame", r.position.x, r.end.x, eave - 0.02, eave, r.position.y, r.end.y)
	# dormers on the front slope
	for x: float in [8.5, 14.5, 25.5, 31.5]:
		var zf := 1.0
		var yb := eave + (zf + OVER) * PITCH - 0.25
		box("ashlar", x - 0.95, x + 0.95, yb, yb + 1.85, zf, zf + 2.2)
		box("glass_dark", x - 0.55, x + 0.55, yb + 0.3, yb + 1.6, zf - 0.02, zf)
		box("frame", x - 0.6, x + 0.6, yb + 0.25, yb + 0.31, zf - 0.04, zf)
		box("frame", x - 0.6, x + 0.6, yb + 1.6, yb + 1.66, zf - 0.04, zf)
		box("frame", x - 0.03, x + 0.03, yb + 0.3, yb + 1.6, zf - 0.04, zf)
		box("frame", x - 0.55, x + 0.55, yb + 0.92, yb + 0.97, zf - 0.04, zf)
		var top := yb + 1.85
		var a := Vector3(x - 1.15, top, zf - 0.15)
		var b := Vector3(x + 1.15, top, zf - 0.15)
		var c := Vector3(x, top + 0.95, zf + 0.5)
		var a2 := Vector3(x - 1.15, top, zf + 2.4)
		var b2 := Vector3(x + 1.15, top, zf + 2.4)
		var c2 := Vector3(x, top + 0.95, zf + 2.4)
		box("frame", x - 1.15, x + 1.15, top - 0.04, top - 0.005, zf - 0.15, zf + 2.4)
		_roof_tri(st, a, b, c)
		_roof_tri(st, a, c, c2)
		_roof_tri(st, a, c2, a2)
		_roof_tri(st, b, c2, c)
		_roof_tri(st, b, b2, c2)
	# the chimneys
	for p: Vector2 in [Vector2(3.6, 6.0), Vector2(36.4, 6.0)]:
		var top := eave + (6.0 + OVER) * PITCH + 1.3
		box("brick", p.x - 0.55, p.x + 0.55, eave, top, p.y - 0.4, p.y + 0.4)
		box("coping", p.x - 0.65, p.x + 0.65, top, top + 0.12, p.y - 0.5, p.y + 0.5)
		for k: float in [-0.25, 0.25]:
			cyl("terracotta", Vector3(p.x + k, top + 0.12, p.y), 0.11, 0.35, 8, 0.09)


## A roof triangle facing up, its tiles' rows along its slope's contour (uv: u along it, v up the slope).
func _roof_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var down := Vector2(n.x, n.z)
	if down.length() < 0.01:
		down = Vector2(0, 1)
	down = down.normalized()
	var along := Vector2(-down.y, down.x)
	var slope := sqrt(1.0 + PITCH * PITCH)
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(Vector2(p.x, p.z).dot(along) / 1.6, -Vector2(p.x, p.z).dot(down) * slope / 1.6))
		st.add_vertex(p)


# ---------------------------------------------------------------- the garage doors

func _garage_doors(meshes: bool) -> void:
	for z: float in GARAGE_DOORS:
		var node := Node3D.new()
		node.name = "GarageDoor"
		node.position = Vector3(W - T_STONE * 0.5, 0.0, z)
		node.set_meta("y0", 0.0)
		root.add_child(node)
		if meshes:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, GARAGE_DOOR_H, 2.78)
			mi.mesh = bm
			mi.position = Vector3(0, GARAGE_DOOR_H * 0.5, 0)
			mi.material_override = mat("garage_door")
			node.add_child(mi)
		_gdoors.append(node)
		_gshapes.append(col(W - T_STONE, W, 0.0, GARAGE_DOOR_H, z - 1.4, z + 1.4))
