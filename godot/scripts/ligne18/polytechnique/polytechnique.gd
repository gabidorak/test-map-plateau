extends Node3D
## Lot ligne18-polytechnique (data/lots/ligne18-polytechnique.json, child of ligne18): line 18's Polytechnique
## station (ex Palaiseau) and its grounds, on its plan (polytechnique_plan.gd; the line: ligne18_plan.gd). The map's
## station building (#394, osm:w1063329861) out, and in the perimeter the map's trees, props, kits' modules, hedges,
## fences, kerbs and markings (the old construction loop's); in, the grounds' trees (rows along the TCSP, the
## forecourt's beds, an orchard on the east lawn, the north path's, the west verge's) and furniture (street and path
## lamps, benches, bins, bike racks, bollards: map props, lit at night, knocked over like the others). The ground
## terraformed (the plan's terraform_zones()) and painted: lawn (mown), asphalt under the west street.
## Drawn at start, four cells (each a child: builder/lot_far.gd streams them): the station's deck, hall and envelope
## (station_builder.gd), the grounds (grounds_builder.gd).

const Plan = preload("res://scripts/ligne18/polytechnique/polytechnique_plan.gd")
const StationBuilder = preload("res://scripts/ligne18/polytechnique/station_builder.gd")
const GroundsBuilder = preload("res://scripts/ligne18/polytechnique/grounds_builder.gd")
const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const GrassLookup = preload("res://scripts/ligne18/grass_lookup.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const KEPT_MARKS := ["zebra", "stop_line", "centre_line", "cycle_lane_line", "bike_symbol"]   # (the TCSP's, outside)

static var _ids := {}                       # the grass field's lookups: material name -> id, "box"
static var _lookup: RefCounted               # _grass_at made fast (grass_lookup.gd)

var game: Node                              # game.gd (null in the tools)


## The world without the map's things in the perimeter (the station building first); with the lot's own.
static func drop(world: Dictionary) -> void:
	var area := Plan.perimeter_map()
	var box := Plan.bounds(area).grow(0.5)
	var inside := func(x: float, y: float) -> bool:
		return box.has_point(Vector2(x, y)) and Geometry2D.is_point_in_polygon(Vector2(x, y), area)
	WorldEdits.drop_buildings(world, [Plan.OSM], area)
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool: return not inside.call(t["x"], t["y"]))
	world["props"] = world["props"].filter(func(p: Dictionary) -> bool: return not inside.call(p["x"], p["y"]))
	for key: String in ["hedges", "kerbs", "fences"]:          # (the lines cut: their runs out of it kept)
		var kept := []
		for rec: Dictionary in world[key]:
			var runs := []
			var run := []
			for q: Variant in rec["pts"]:
				if inside.call(q[0], q[1]):
					if run.size() >= 2:
						runs.append(run)
					run = []
				else:
					run.append(q)
			if run.size() >= 2:
				runs.append(run)
			for k in runs.size():
				var r: Dictionary = rec.duplicate()
				r["pts"] = runs[k]
				if r.has("id") and runs.size() > 1:
					r["id"] = "%s~%d" % [rec["id"], k]
				kept.append(r)
		world[key] = kept
	var marks := []                                          # (the markings' triangles in it out)
	for m: Dictionary in world["markings"]:
		var v: Array = m["verts"]
		var t: Array = m["tris"]
		if not v.any(func(q: Array) -> bool: return box.has_point(Vector2(q[0], q[1]))):
			marks.append(m)
			continue
		var tris := []
		for i in range(0, t.size(), 3):
			var c := (Vector2(v[t[i]][0], v[t[i]][1]) + Vector2(v[t[i + 1]][0], v[t[i + 1]][1])
					+ Vector2(v[t[i + 2]][0], v[t[i + 2]][1])) / 3.0
			if not inside.call(c.x, c.y):
				tris.append_array([t[i], t[i + 1], t[i + 2]])
		if tris.size() == t.size():
			marks.append(m)
		elif not tris.is_empty():
			var r: Dictionary = m.duplicate()
			r["tris"] = tris
			marks.append(r)
	world["markings"] = marks
	_plant(world)


## The lot's trees and street furniture (map records, built with the map's own).
static func _plant(world: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 394
	var arch: Dictionary = world["tree_archetypes"]
	var k := 0
	for t: Array in Plan.trees():
		var m := Plan.to_map(t[0])
		var kind: String = t[1] if arch.has(t[1]) else str(arch.keys()[0])
		var s := rng.randf_range(0.9, 1.1)
		world["trees"].append({"id": "lot:polytechnique:tree:%d" % k, "x": m.x, "y": m.y, "h": float(t[2]) * s,
				"r": float(t[2]) * 0.32 * s, "arch": kind, "var": rng.randi() % maxi(1, int(arch[kind])),
				"tint": t[3], "src": "lot"})
		k += 1
	k = 0
	for p: Array in Plan.props():
		var q: Vector2 = p[1]
		var m := Plan.to_map(q)
		var lift: float = Plan.lift(q) if Plan.paved(q) else 0.0
		world["props"].append({"id": "lot:polytechnique:prop:%d" % k, "kind": p[0], "model": p[0], "x": m.x, "y": m.y,
				"yaw": p[2], "lift": lift, "src": "lot"})
		k += 1


## The ground's paint (builder/ground_builder.gd): in the perimeter lawn (mown) all over, asphalt under the west street
## (everything paved is drawn over the lawn), the station's floor over a concrete ground.
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var area := Plan.perimeter_map()
	var box := Plan.bounds(area).grow(0.2)
	var grass := materials.find("grass")
	var grass_colour := Color.html(str(palette["grass"]))
	var asphalt := materials.find("asphalt")
	var asphalt_colour := Color.html(str(palette["asphalt"]))
	var concrete := materials.find("concrete")
	var concrete_colour := Color.html(str(palette["concrete"]))
	for k in verts.size():
		var m := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(m) or not Geometry2D.is_point_in_polygon(m, area):
			continue
		var p := Plan.to_local(m)
		if Plan.in_road(p):
			ids[k * 4] = asphalt
			colours[k] = asphalt_colour
		elif Plan.in_station(p):
			ids[k * 4] = concrete
			colours[k] = concrete_colour
		else:
			ids[k * 4] = grass
			colours[k] = grass_colour
	return [ids, colours]


## The grass field in the perimeter: none on what is paved, the road, the station; the lawn's on the rest.
static func _grass_at(x: float, y: float) -> int:
	if _ids.is_empty() or not (_ids["box"] as Rect2).has_point(Vector2(x, y)):
		return -2
	var p := Plan.to_local(Vector2(x, y))
	if not Plan.in_perimeter(p):
		return -2
	return _ids["paving"] if Plan.in_road(p) or Plan.in_station(p) or Plan.paved(p) else _ids["grass"]


func _ready() -> void:
	name = "Ligne18Polytechnique"
	var gm: RefCounted = GroundMap.get_map()
	if gm:
		_ids = {"paving": gm.materials.find("paving"), "grass": gm.materials.find("grass"),
				"box": Plan.bounds(Plan.perimeter_map())}
	if _lookup == null and not _ids.is_empty():
		var polys := [Plan.perimeter(), Plan.road(), Plan.outline()]
		for e: Array in Plan.surfaces():
			polys.append(e[0])
		var on_map := polys.map(func(poly: PackedVector2Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for q in poly:
				out.append(Plan.to_map(q))
			return out)
		_lookup = GrassLookup.new(_grass_at, _ids["box"], on_map)
		GrassField.overrides.append(_lookup.at)
	var meshes := DisplayServer.get_name() != "headless"
	add_child(StationBuilder.new("Deck").deck(meshes))
	add_child(StationBuilder.new("Hall").hall(meshes))
	add_child(StationBuilder.new("Envelope").envelope(meshes))
	add_child(GroundsBuilder.new().build(meshes))
