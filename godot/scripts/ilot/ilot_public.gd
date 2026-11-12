extends Node3D
## Lot ilot-001 (data/lots/ilot-001.json): the supermarket's block's own lot, the parent of its others (Losplatos
## Custom, the 25/8 supermarket), on the block's plan (ilot_plan.gd). Its ground terraformed (the plan's terraform_zones()); where it is redone (the ring, the site,
## where #785 and #889 stood) the map's trees, hedges, props, kerbs and markings out (the long ones cut), its own in:
## street trees, hedges, street and path lamps, benches, bins, bike racks, bollards (map props: lit at night by
## night.gd, knocked over like the others). Drawn at start: the ring (its roads, one asphalt, kerbed where nothing goes
## on, their centre lines, the give-way lines and zebras; the sidewalk all round the block, lowered across its
## accesses), the shop's forecourt and the footway to it, the site's zebras. The ground painted paving under what is
## paved, lawn where the block is redone.

const Plan = preload("res://scripts/ilot/ilot_plan.gd")
const UrbanKit = preload("res://scripts/ilot/urban_kit.gd")
const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const SOFT := ["asphalt", "concrete", "paving", "sett", "gravel", "dirt", "sand", "grass", "tall_grass", "forest_floor",
		"construction", "clay", "building"]
const MARGIN := 1.5                         # m round the ring's roads where the map's things go too
const WALKS := ["sidewalk", "footway", "path", "pedestrian", "steps", "cycleway"]

static var _ids := {}                       # the grass field's lookups: material name -> id, "soft" -> ids, "box"

var game: Node


## Where the block's children's terraforming may act (builder/lots.gd): the plan's.
static func child_weight(x: float, y: float) -> float:
	return Plan.child_weight(x, y)


## Whether local p is redone: the ring (MARGIN round its roads), the site, where the buildings out stood.
static func _redone(p: Vector2) -> bool:
	return Plan.on_ring(p, MARGIN) or Plan.in_site(p) or _cleared(p) or Plan.SERVICE_ROAD.grow(1.0).has_point(p)


static func _cleared(p: Vector2) -> bool:
	for r: Rect2 in Plan.DROPPED_AT:
		if r.grow(1.0).has_point(p):
			return true
	return false


static func _redone_map(q: Variant) -> bool:
	var m := Vector2(q[0], q[1])
	return _ids["box"].has_point(m) and _redone(Plan.to_local(m))


## The world without the map's things where the block is redone (#785, #889 out); with its own.
static func drop(world: Dictionary) -> void:
	_ids["box"] = _box()
	for i in Plan.DROPPED.size():
		var r: Rect2 = Plan.DROPPED_AT[i].grow(1.0)
		var area := PackedVector2Array()
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			area.append(Plan.to_map(c))
		WorldEdits.drop_buildings(world, [Plan.DROPPED[i]], area)
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool: return not _redone_map([t["x"], t["y"]]))
	world["props"] = world["props"].filter(func(p: Dictionary) -> bool: return not _redone_map([p["x"], p["y"]]))
	for key: String in ["hedges", "kerbs"]:                 # (the lines cut: their runs out of it kept)
		var kept := []
		for rec: Dictionary in world[key]:
			var runs := _runs(rec["pts"])
			for k in runs.size():
				var r := rec.duplicate()
				r["pts"] = runs[k]
				if r.has("id") and runs.size() > 1:
					r["id"] = "%s~%d" % [rec["id"], k]
				kept.append(r)
		world[key] = kept
	var marks := []                                          # (the markings' triangles out of it kept)
	for m: Dictionary in world["markings"]:
		var v: Array = m["verts"]
		var t: Array = m["tris"]
		if not v.any(func(q: Array) -> bool: return (_ids["box"] as Rect2).has_point(Vector2(q[0], q[1]))):
			marks.append(m)
			continue
		var tris := []
		for i in range(0, t.size(), 3):
			var c := (Vector2(v[t[i]][0], v[t[i]][1]) + Vector2(v[t[i + 1]][0], v[t[i + 1]][1])
					+ Vector2(v[t[i + 2]][0], v[t[i + 2]][1])) / 3.0
			if not _redone_map([c.x, c.y]):
				tris.append_array([t[i], t[i + 1], t[i + 2]])
		if tris.size() == t.size():
			marks.append(m)
		elif not tris.is_empty():
			var r := m.duplicate()
			r["tris"] = tris
			marks.append(r)
	world["markings"] = marks
	_plant(world)


## A polyline's runs (two points at least) out of what is redone.
static func _runs(pts: Array) -> Array:
	var out := []
	var run := []
	for q: Variant in pts:
		if _redone_map(q):
			if run.size() >= 2:
				out.append(run)
			run = []
		else:
			run.append(q)
	if run.size() >= 2:
		out.append(run)
	return out


## The block's trees, hedges and street furniture (local; map records, built with the map's own). A lamp's yaw is
## where its arm reaches (over the carriageway), a bench's where it looks.
static func _plant(world: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2508
	var arch: Dictionary = world["tree_archetypes"]
	var trees := []                          # [u, v, archetype, height]
	for u: float in [424.5, 443.0, 449.5, 456.0, 462.5, 478.5]:
		trees.append([u, -87.0, "round", 9.0])           # the lawn strip by the north road (clear of the lorries)
	for u: float in [395.0, 402.0]:
		trees.append([u, -90.0, "round", 9.0])           # #771's lawn on the north road
	for u: float in [393.0, 401.0]:
		trees.append([u, -124.0, "oval", 8.0])           # between Losplatos's lane and #771
	for v: float in [-98.0, -106.0, -114.0, -121.0]:
		trees.append([421.8, v, "oval", 8.0])            # the strip by #771
		trees.append([481.0, v - 2.0, "oval", 8.0])       # by the service road
	for u: float in [428.0, 438.0, 470.0, 479.0]:
		trees.append([u, -126.6, "oval", 6.5])            # the forecourt's
	for u: float in [464.0, 470.0, 476.0]:
		trees.append([u, -136.6, "round", 7.5])           # the car park's north strip
	trees.append([451.0, -137.5, "oval", 6.0])            # the planter between the station and the footway
	trees.append([451.0, -170.0, "oval", 6.0])
	for u: float in [463.5, 468.5]:
		trees.append([u, -173.4, "round", 7.5])           # the car park's south strip
	for u: float in [413.0, 419.5]:
		trees.append([u, -173.6, "round", 8.0])           # where #785 stood
	for u: float in [495.0, 503.0, 511.0]:
		trees.append([u, -172.6, "round", 9.0])           # where #889 stood
	for v: float in [-168.0, -158.0, -100.0, -91.0]:
		trees.append([519.3, v, "oval", 8.0])             # the strip by #896 on the east road
	var k := 0
	for t: Array in trees:
		var m := Plan.to_map(Vector2(t[0], t[1]))
		if world["trees"].any(func(o: Dictionary) -> bool: return m.distance_to(Vector2(o["x"], o["y"])) < 4.0):
			continue                                     # (the map's tree there kept)
		var kind: String = t[2] if arch.has(t[2]) else str(arch.keys()[0])
		var s := rng.randf_range(0.9, 1.1)
		world["trees"].append({"id": "lot:ilot:tree:%d" % k, "x": m.x, "y": m.y, "h": float(t[3]) * s,
				"r": float(t[3]) * 0.32 * s, "arch": kind, "var": rng.randi() % maxi(1, int(arch[kind])),
				"tint": ["leaf", "deep", "spring"][rng.randi() % 3], "src": "lot"})
		k += 1
	var hedges := [
		[[420.5, -87.4], [431.0, -87.4]], [[441.0, -87.4], [465.0, -87.4]], [[475.0, -87.4], [482.5, -87.4]],
		[[423.4, -175.0], [423.4, -134.5]],                       # the station by Losplatos's yard
		[[461.5, -174.9], [482.0, -174.9]],                        # the car park's south strip
		[[461.5, -135.0], [476.5, -135.0]],                        # its north strip
		[[451.0, -167.5], [451.0, -140.0]],                        # the planter between the station and the footway
		[[483.0, -172.0], [483.0, -134.5]],                        # the car park by the service road
	]
	k = 0
	for h: Array in hedges:
		var pts := h.map(func(q: Array) -> Array:
			var m := Plan.to_map(Vector2(q[0], q[1]))
			return [m.x, m.y])
		world["hedges"].append({"id": "lot:ilot:hedge:%d" % k, "pts": pts, "h": 1.1, "w": 0.9, "tint": "deep",
				"src": "lot", "height_src": "lot"})
		k += 1
	var up := UrbanKit.KERB
	var s := 270.0                           # (yaws in the block's frame: turned onto the map below)
	var n := 90.0
	var props := [                           # [model, u, v, yaw, lift]
		["lamp_street", 398.0, -178.35, s, up], ["lamp_street", 418.0, -178.35, s, up],
		["lamp_street", 441.0, -178.35, s, up], ["lamp_street", 467.0, -178.35, s, up],
		["lamp_street", 498.0, -178.35, s, up], ["lamp_street", 516.0, -178.35, s, up],
		["lamp_street", 395.0, -83.4, n, up], ["lamp_street", 422.0, -83.4, n, up],
		["lamp_street", 451.0, -83.4, n, up], ["lamp_street", 478.0, -83.4, n, up], ["lamp_street", 505.0, -83.4, n, up],
		["lamp_street", 386.65, -165.0, 180.0, up], ["lamp_street", 386.65, -118.0, 180.0, up],
		["lamp_street", 386.65, -98.0, 180.0, up],
		["lamp_street", 523.85, -165.0, 0.0, up], ["lamp_street", 523.85, -128.0, 0.0, up],
		["lamp_street", 523.85, -95.0, 0.0, up],
		["lamp_street", 433.0, -127.2, s, up], ["lamp_street", 447.0, -127.2, s, up],
		["lamp_street", 461.0, -127.2, s, up], ["lamp_street", 475.0, -127.2, s, up],
		["lamp_street", 467.0, -136.6, s, 0.0], ["lamp_street", 473.0, -174.0, n, 0.0],
		["lamp_street", 426.5, -128.5, s, 0.0],               # (on the station's corner: its north entry)
		["lamp_street", 450.5, -155.0, 180.0, 0.0],           # (in the planter: its arm over the station's east lane)
		["lamp_street", 428.0, -89.0, s, 0.0], ["lamp_street", 455.0, -89.0, s, 0.0],   # the yard's
		["lamp_street", 478.0, -89.0, s, 0.0],
		["lamp_path", 452.6, -140.0, 0.0, up], ["lamp_path", 452.6, -152.0, 0.0, up],
		["lamp_path", 452.6, -164.0, 0.0, up],
		["bench_back", 433.5, -124.0, s, up], ["bench_back", 441.0, -124.0, s, up],
		["bench_back", 467.0, -124.0, s, up], ["bench_back", 474.5, -124.0, s, up],
		["bin_vigipirate", 448.0, -123.0, 0.0, up], ["bin_vigipirate", 460.0, -123.0, 0.0, up],
		["bin_vigipirate", 453.5, -175.2, 0.0, up], ["bin_vigipirate", 480.0, -177.2, 0.0, up],
		["bin_vigipirate", 400.0, -84.5, 0.0, up], ["bin_vigipirate", 522.8, -120.0, 0.0, up],
		["bike_rack", 425.5, -123.3, 0.0, up], ["bike_rack", 427.0, -123.3, 0.0, up],
		["bike_rack", 478.5, -123.3, 0.0, up], ["bike_rack", 480.0, -123.3, 0.0, up],
		["defibrillator", 449.0, -122.3, s, up],
	]
	var x := 425.25                          # bollards along the forecourt's edge (not on the zebra, nor the lamps)
	while x < 481.5:
		if [433.0, 447.0, 461.0, 475.0].all(func(l: float) -> bool: return absf(x - l) > 0.8) and (x < 451.5 or x > 455.5):
			props.append(["bollard", x, -127.65, 0.0, up])
		x += 2.5
	var turn := rad_to_deg(Plan.ANGLE)
	k = 0
	for p: Array in props:
		var m := Plan.to_map(Vector2(p[1], p[2]))
		world["props"].append({"id": "lot:ilot:prop:%d" % k, "kind": p[0], "model": p[0], "x": m.x, "y": m.y,
				"yaw": fposmod(float(p[3]) + turn, 360.0), "lift": p[4], "src": "lot"})
		k += 1


## The ground's paint (builder/ground_builder.gd): paving under what is paved (the site's, the ring's sidewalks),
## lawn on the rest of what is redone inside the block.
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var grass := materials.find("grass")
	var paving := materials.find("paving")
	var grass_colour := Color.html(str(palette["grass"]))
	var paving_colour := Color.html(str(palette.get("paving", palette["grass"])))
	var soft: Array = SOFT.map(func(m: String) -> int: return materials.find(m))
	var box := _box()
	for k in verts.size():
		var m := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(m):
			continue
		var p := Plan.to_local(m)
		if _paved(p):
			ids[k * 4] = paving
			colours[k] = paving_colour
		elif (Plan.in_site(p) or _cleared(p)) and int(ids[k * 4]) in soft:
			ids[k * 4] = grass
			colours[k] = grass_colour
	return [ids, colours]


## Whether local p is paved: the site's, the ring's sidewalks (inside the kerb line, out of the block).
static func _paved(p: Vector2) -> bool:
	if Plan.KERB_LINE.has_point(p) and not Plan.INNER.has_point(p):
		return true
	if Plan.in_site(p):
		for r: Rect2 in Plan.paved():
			if r.has_point(p):
				return true
	return false


## The block's box on the map (a quick test before its own).
static func _box() -> Rect2:
	var r := Rect2(Plan.to_map(Plan.KERB_LINE.position), Vector2.ZERO)
	for c: Vector2 in [Vector2(Plan.KERB_LINE.end.x, Plan.KERB_LINE.position.y), Plan.KERB_LINE.end,
			Vector2(Plan.KERB_LINE.position.x, Plan.KERB_LINE.end.y)]:
		r = r.expand(Plan.to_map(c))
	return r.grow(Plan.ROAD_W + MARGIN + 1.0)


## The grass field in the block: none on what is paved nor on the ring's roads, lawn where it is redone inside.
static func _grass_at(x: float, y: float) -> int:
	if _ids.is_empty() or not (_ids["box"] as Rect2).has_point(Vector2(x, y)):
		return -2
	var p := Plan.to_local(Vector2(x, y))
	if _paved(p) or Plan.on_ring(p) or Plan.SERVICE_ROAD.has_point(p):
		return _ids["paving"]
	if (Plan.in_site(p) or _cleared(p)) and GroundMap.get_map().material_at(x, y) in _ids["soft"]:
		return _ids["grass"]
	return -2


func _ready() -> void:
	name = "Ilot001"
	var gm: RefCounted = GroundMap.get_map()
	if gm:
		_ids = {"paving": gm.materials.find("paving"), "grass": gm.materials.find("grass"), "box": _box(),
				"soft": SOFT.map(func(m: String) -> int: return gm.materials.find(m))}
	GrassField.overrides.append(_grass_at)
	var k := UrbanKit.new("Ilot001", {"type": "lot", "lot": "ilot-001",
			"name": "Îlot de la supérette 25/8: espaces publics", "about": "the streets round the block, its greenery"})
	_ring(k, gm)
	k.slab(Plan.PLAZA)
	k.slab(Plan.WALK)
	for z: Rect2 in Plan.ZEBRAS:                       # (bars along the lane they cross)
		k.zebra(z, UrbanKit.EAST if z.size.y > z.size.x else UrbanKit.NORTH)
	add_child(k.commit(DisplayServer.get_name() != "headless"))


## The ring: its roads, their kerbs, the sidewalk round the block, the markings.
func _ring(k: UrbanKit, gm: RefCounted) -> void:
	for r: Rect2 in Plan.road_pieces():
		k.flat(r, UrbanKit.ASPHALT_UP, "street_asphalt")
	var c := Plan.corners()                            # south-west, south-east, north-east, north-west
	var arcs := [[PI, 1.5 * PI], [1.5 * PI, TAU], [0.0, 0.5 * PI], [0.5 * PI, PI]]
	for i in [0, 1, 3]:
		k.asphalt_fillet(c[i], arcs[i][0], arcs[i][1])
	var bend := Plan.CORNER + Plan.ROAD_W
	k.asphalt_arc(c[2], Plan.CORNER, bend, 0.0, 0.5 * PI)
	# the sidewalk round the block (Losplatos Custom's front its own), lowered across the accesses
	var gaps := {"W": [], "S": [], "E": [], "N": []}
	for g: Array in Plan.gaps():
		gaps[g[0]].append(Vector2(g[1], g[2]))
	for side: Array in Plan.walk_sides():
		var a: Vector2 = side[0]
		var base: float = a.y if side[3] in ["W", "E"] else a.x
		var along := func(g: Vector2) -> Vector2: return g - Vector2.ONE * base   # (the plan's u or v: m from a)
		var skips := [along.call(Plan.LOSPLATOS_FRONT)] if side[3] == "W" else []
		k.sidewalk(a, side[1], side[2], gaps[side[3]].map(along), skips)
	for i in 4:
		k.sidewalk_arc(c[i], arcs[i][0], arcs[i][1])
	# the kerbs on the roads' other sides: raised, lowered before a yard, none where a road goes on
	var kind_at := func(p: Vector2) -> int:
		if gm == null:
			return 2
		var m := Plan.to_map(p)
		var piece: int = gm.piece_at(m.x, m.y)
		if piece < 0:
			return 2
		var rec: Array = gm.pieces[piece]
		if rec[0] == "road":
			return 0
		return 1 if rec[1] in ["asphalt", "concrete", "sett"] and not (rec[0] in WALKS) else 2
	var kl := Plan.KERB_LINE
	var w := Plan.WEST_ROAD
	var s := Plan.SOUTH_ROAD
	var e := Plan.EAST_ROAD
	var n := Plan.NORTH_ROAD
	for edge: Array in [
			[Vector2(w.position.x, w.position.y), Vector2(w.position.x, w.end.y), UrbanKit.WEST],
			[Vector2(kl.position.x, w.position.y), Vector2(kl.position.x, s.position.y), UrbanKit.EAST],
			[Vector2(kl.position.x, n.end.y), Vector2(kl.position.x, w.end.y), UrbanKit.EAST],
			[Vector2(kl.position.x, s.position.y), Vector2(kl.end.x, s.position.y), UrbanKit.SOUTH],
			[Vector2(e.end.x, s.position.y), Vector2(s.end.x, s.position.y), UrbanKit.SOUTH],
			[Vector2(e.end.x, kl.position.y), Vector2(s.end.x, kl.position.y), UrbanKit.NORTH],
			[Vector2(kl.end.x, e.position.y), Vector2(kl.end.x, s.position.y), UrbanKit.WEST],
			[Vector2(e.end.x, e.position.y), Vector2(e.end.x, s.position.y), UrbanKit.EAST],
			[Vector2(e.end.x, kl.position.y), Vector2(e.end.x, c[2].y), UrbanKit.EAST],
			[Vector2(kl.position.x, n.end.y), Vector2(c[2].x, n.end.y), UrbanKit.NORTH]]:
		k.road_edge(edge[0], edge[1], edge[2], kind_at)
	k.road_edge_arc(c[2], bend, 0.0, 0.5 * PI, kind_at)
	# the service road between the supermarket and #896: kerbed (lowered by #896's yard), giving way at both ends
	var sr := Plan.SERVICE_ROAD
	k.flat(sr, UrbanKit.ASPHALT_UP, "street_asphalt")
	k.road_edge(sr.position, Vector2(sr.position.x, sr.end.y), UrbanKit.WEST, kind_at)
	k.road_edge(Vector2(sr.end.x, sr.position.y), sr.end, UrbanKit.EAST, kind_at)
	for v: float in [sr.position.y + 0.45, sr.end.y - 0.45]:
		k.dashes(Vector2(sr.position.x + 0.2, v), Vector2(sr.end.x - 0.2, v), 0.3, 0.5, 0.5)
	# the centre lines (broken where the east road crosses the south one), the give-way lines, the zebras
	var mid := Plan.ROAD_W * 0.5
	k.dashes(Vector2(w.position.x + mid, w.position.y), Vector2(w.position.x + mid, w.end.y), 0.12, 3.0, 3.5)
	k.dashes(Vector2(kl.position.x, s.position.y + mid), Vector2(s.end.x, s.position.y + mid), 0.12, 3.0, 3.5,
			func(p: Vector2) -> bool: return p.x > kl.end.x - 1.0 and p.x < e.end.x + 1.0)
	k.dashes(Vector2(e.position.x + mid, kl.position.y), Vector2(e.position.x + mid, c[2].y), 0.12, 3.0, 3.5)
	k.dashes(Vector2(e.position.x + mid, e.position.y), Vector2(e.position.x + mid, s.position.y - 1.0), 0.12, 3.0, 3.5)
	k.dashes(Vector2(kl.position.x, n.position.y + mid), Vector2(c[2].x, n.position.y + mid), 0.12, 3.0, 3.5)
	k.dashes_arc(c[2], Plan.CORNER + mid, 0.0, 0.5 * PI, 0.12, 3.0, 3.5)
	for g: Array in [[Vector2(kl.position.x + 0.5, s.position.y + mid), Vector2(kl.position.x + 0.5, kl.position.y)],
			[Vector2(kl.position.x + 0.5, n.position.y + mid), Vector2(kl.position.x + 0.5, n.end.y)],
			[Vector2(kl.end.x, kl.position.y + 0.5), Vector2(e.position.x + mid, kl.position.y + 0.5)],
			[Vector2(e.position.x + mid, s.position.y - 0.5), Vector2(e.end.x, s.position.y - 0.5)]]:
		k.dashes(g[0], g[1], 0.3, 0.5, 0.5)              # (give way: the south, north, east roads to the through ones)
	k.zebra(Rect2(518.5, s.position.y, 3.0, Plan.ROAD_W), UrbanKit.EAST)          # the south road by the east one
	k.zebra(Rect2(w.position.x, -160.0, Plan.ROAD_W, 3.0), UrbanKit.NORTH)        # the west road by Losplatos Custom
