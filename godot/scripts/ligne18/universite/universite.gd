extends Node3D
## Lot ligne18-universite (data/lots/ligne18-universite.json, a child of ligne18): Université Paris-Saclay's station
## (ex Orsay-Gif, plateau de Moulon) on line 18's viaduct and its grounds up to the roads round it, on its plan
## (universite_plan.gd; ref/metro18/ §3 and §5).
## When the map is built: its ground terraformed (the plan's terraform_zones()); out of the map (drop()) the map's
## station (osm:w1063329862, #7056) and, in the perimeter, the trees, the hedges and fences, the map's kerbs on the
## block's side and the platform's, the markings but the zebras, stop lines and cycle crossings, the props but the
## signals, signs and the stop's pole and shelter (lifted onto the new paving); in, its trees (rows, groves: none
## within TREE_CLEAR m of the axis nor on the viaduct's piers) and furniture (street and path lamps, benches, bins,
## bike racks: map props, lit at night, knocked over like the others); the ground painted (repaint()): lawn in the
## block, asphalt on the carriageways redone, paving under the platform.
## In the game, two cells (builder/lot_far.gd streams each child): the station (station_builder.gd: its deck,
## supports, hall, passerelle, flights, platforms, envelope and roof) and its grounds (grounds_builder.gd: the paving,
## kerbs, the stop's platform, the markings).

const Plan = preload("res://scripts/ligne18/universite/universite_plan.gd")
const Station = preload("res://scripts/ligne18/universite/station_builder.gd")
const Grounds = preload("res://scripts/ligne18/universite/grounds_builder.gd")
const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const KEPT_PROPS := ["traffic_light", "pedestrian_light", "sign", "bus_pole", "bus_shelter"]
const KEPT_MARKS := ["zebra", "stop_line", "cycle_crossing"]

static var _ids := {}                       # the grass field's lookups: material name -> id, "box"

var game: Node                              # game.gd (null in the tools)
var station: Node3D
var grounds: Node3D


## The world without the map's things in the perimeter; with the lot's.
static func drop(world: Dictionary) -> void:
	var per := Plan.perimeter_map()
	var box := Plan.bounds(per).grow(1.0)
	var inside := func(x: float, y: float, poly: PackedVector2Array) -> bool:
		return box.has_point(Vector2(x, y)) and Geometry2D.is_point_in_polygon(Vector2(x, y), poly)
	WorldEdits.drop_buildings(world, [str(Plan.L18.station(Plan.ID)["osm_building"])], per)
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool: return not inside.call(t["x"], t["y"], per))
	var props := []
	for p: Dictionary in world["props"]:
		if not inside.call(p["x"], p["y"], per):
			props.append(p)
		elif p["kind"] in KEPT_PROPS:                        # (onto the new paving)
			var q := Plan.to_local(Vector2(p["x"], p["y"]))
			p["lift"] = Plan.lift(q) if Plan.is_paved(q) else 0.0
			props.append(p)
	world["props"] = props
	var cuts := {"kerbs": _kerb_cuts(), "hedges": [per], "fences": [per]}
	for key: String in cuts:                                 # (the lines cut: their runs out of it kept)
		var kept := []
		for rec: Dictionary in world.get(key, []):
			var runs := []
			var run := []
			for q: Variant in rec["pts"]:
				if (cuts[key] as Array).any(func(c: PackedVector2Array) -> bool: return inside.call(q[0], q[1], c)):
					if run.size() >= 2:
						runs.append(run)
					run = []
				else:
					run.append(q)
			if run.size() >= 2:
				runs.append(run)
			if runs.size() == 1 and (runs[0] as Array).size() == (rec["pts"] as Array).size():
				kept.append(rec)
				continue
			for k in runs.size():
				var r: Dictionary = rec.duplicate()
				r["pts"] = runs[k]
				if r.has("id") and runs.size() > 1:
					r["id"] = "%s~%d" % [rec["id"], k]
				kept.append(r)
		world[key] = kept
	var marks := []                                          # (the markings' triangles out of it kept)
	for m: Dictionary in world["markings"]:
		var v: Array = m["verts"]
		var t: Array = m["tris"]
		if m["kind"] in KEPT_MARKS or not v.any(func(q: Array) -> bool: return box.has_point(Vector2(q[0], q[1]))):
			marks.append(m)
			continue
		var tris := []
		for i in range(0, t.size(), 3):
			var c := (Vector2(v[t[i]][0], v[t[i]][1]) + Vector2(v[t[i + 1]][0], v[t[i + 1]][1])
					+ Vector2(v[t[i + 2]][0], v[t[i + 2]][1])) / 3.0
			if not inside.call(c.x, c.y, per):
				tris.append_array([t[i], t[i + 1], t[i + 2]])
		if tris.size() == t.size():
			marks.append(m)
		elif not tris.is_empty():
			var r: Dictionary = m.duplicate()
			r["tris"] = tris
			marks.append(r)
	world["markings"] = marks
	_plant(world)


## Where the map's kerbs go (map polygons): the block's side (and 0.6 m round it: the kerbs along it), the platform's.
static func _kerb_cuts() -> Array:
	var out := []
	for poly: PackedVector2Array in [Plan.block(), PackedVector2Array(Plan.PLATFORM)]:
		var m := PackedVector2Array()
		for q in Plan.offset(poly, 0.6):
			m.append(Plan.to_map(q))
		out.append(m)
	return out


## The lot's trees and furniture (map records, built with the map's own). A street lamp's yaw is where its arm reaches
## (over the road), a bench's where it looks.
static func _plant(world: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6869
	var arch: Dictionary = world["tree_archetypes"]
	var k := 0
	for t: Array in Plan.trees():
		var m := Plan.to_map(t[0])
		var kind: String = t[1] if arch.has(t[1]) else str(arch.keys()[0])
		var s := rng.randf_range(0.9, 1.1)
		world["trees"].append({"id": "lot:l18u:tree:%d" % k, "x": m.x, "y": m.y, "h": float(t[2]) * s,
				"r": float(t[2]) * (0.22 if kind == "columnar" else 0.32) * s, "arch": kind,
				"var": rng.randi() % maxi(1, int(arch[kind])), "tint": ["leaf", "deep", "spring"][rng.randi() % 3],
				"src": "lot"})
		k += 1
	k = 0
	for p: Array in Plan.props():
		var q: Vector2 = p[1]
		var m := Plan.to_map(q)
		var d: Vector2 = p[2]
		world["props"].append({"id": "lot:l18u:prop:%d" % k, "kind": p[0], "model": p[0], "x": m.x, "y": m.y,
				"yaw": Plan.yaw(d) if d != Vector2.ZERO else 0.0, "lift": Plan.lift(q) if Plan.is_paved(q) else 0.0,
				"src": "lot"})
		k += 1


## The ground's paint (builder/ground_builder.gd): in the block lawn (everything paved is drawn over it; under the
## building concrete) but along the kerb (the paving there: a lawn's paint would run onto the road), the carriageways
## redone asphalt, the platform paving; the map's kerb stones and markings kept off the block (their skirts keep their
## own).
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var per := Plan.perimeter_map()
	var box := Plan.bounds(per).grow(0.5)
	var paint := {}
	for name: String in ["grass", "asphalt", "paving", "concrete"]:
		paint[name] = [materials.find(name), Color.html(str(palette[name]))]
	var kept := [materials.find("kerb"), materials.find("paint")]
	var roads := [Plan.sg_road(), Plan.tcsp_road()]
	var kerb := Plan.kerb_line()
	for k in verts.size():
		var mp := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(mp) or not Geometry2D.is_point_in_polygon(mp, per):
			continue
		var p := Plan.to_local(mp)
		var what := ""
		if Plan.SOCLE.grow(0.5).has_point(p):
			what = "concrete"
		elif Plan.inside(p, Plan.block()):
			if Plan._dist_line(p, kerb) < 1.2:                   # (by the kerb: its paint would run onto the road)
				continue
			what = "grass"
		elif Plan.inside(p, PackedVector2Array(Plan.PLATFORM)):
			what = "paving"
		elif roads.any(func(r: PackedVector2Array) -> bool: return Plan.inside(p, r)):
			if int(ids[k * 4]) in kept:
				continue
			what = "asphalt"
		else:
			continue
		ids[k * 4] = paint[what][0]
		colours[k] = paint[what][1]
	return [ids, colours]


## The grass field in the perimeter: none on the paving, the building or the roads; the lawn's on the rest.
static func _grass_at(x: float, y: float) -> int:
	if _ids.is_empty() or not (_ids["box"] as Rect2).has_point(Vector2(x, y)):
		return -2
	var p := Plan.to_local(Vector2(x, y))
	if not Plan.inside(p, Plan.perimeter()):
		return -2
	return _ids["grass"] if Plan.is_lawn(p) else _ids["paving"]


func _ready() -> void:
	name = "LigneUniversite"
	var gm: RefCounted = GroundMap.get_map()
	if gm:
		_ids = {"paving": gm.materials.find("paving"), "grass": gm.materials.find("grass"),
				"box": Plan.bounds(Plan.perimeter_map())}
		GrassField.overrides.append(_grass_at)
	var meshes := DisplayServer.get_name() != "headless"
	station = Station.new().build(meshes)
	add_child(station)
	grounds = Grounds.new().build(meshes)
	add_child(grounds)
