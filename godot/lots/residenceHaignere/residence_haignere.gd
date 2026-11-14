extends Node3D
## Lot residenceHaignere (lots/residenceHaignere/lot.json): the grounds round the Haigneré residence (#536, kept as it
## is) redone on Thomas's plan (ref/residencHaignere/PlanUrbanisme.png; haignere_plan.gd): its ground one plane
## (terraformed, and the road made where the kerb's corner is squared); out of the lot the map's trees, props (not the
## traffic signals: on the new sidewalk, moved onto it from the road made), hedges, kerbs and the old cycle track's
## markings; in, its street trees (one in each bed along the south road, a row along the
## residence's north-east facade, the lawns'), lamps (street lamps along the roads, path lamps along the alley),
## benches, bins and bike racks (map props: lit at night by night.gd, knocked over like the others). Drawn at start
## (residence_haignere_builder.gd): the sidewalks, cycle track and kerbs along the roads, the alley, paths and terrace.
## The ground painted lawn (mown) under it all; its surfaces in the map's ground (surface_at(): builder/ground_bake.gd).

const Plan = preload("res://lots/residenceHaignere/haignere_plan.gd")
const Builder = preload("res://lots/residenceHaignere/residence_haignere_builder.gd")
const KEPT_PROPS := ["pedestrian_light", "traffic_light"]
const KEPT_MARKS := ["zebra", "stop_line", "cycle_crossing", "centre_line"]   # (the roads': at their kerb)


var game: Node                              # game.gd (null in the tools)


## The world without the map's things in the lot; with its own.
static func drop(world: Dictionary) -> void:
	var l := Plan.area()
	var near := Plan.offset(l, 0.6)          # (the kerbs along its edge too)
	var box := Plan.bounds(near)
	var inside := func(x: float, y: float, poly: PackedVector2Array) -> bool:
		return box.has_point(Vector2(x, y)) and Geometry2D.is_point_in_polygon(Vector2(x, y), poly)
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool: return not inside.call(t["x"], t["y"], l))
	var props := []
	for p: Dictionary in world["props"]:
		if not inside.call(p["x"], p["y"], l):
			props.append(p)
		elif p["kind"] in KEPT_PROPS:                        # (on the new sidewalk: up on it)
			var at := Plan.on_kerb_strip(Vector2(p["x"], p["y"]))
			p["x"] = at.x
			p["y"] = at.y
			p["lift"] = Plan.lift(at)
			props.append(p)
	world["props"] = props
	for key: String in ["hedges", "kerbs"]:                  # (the lines cut: their runs out of it kept)
		var kept := []
		for rec: Dictionary in world[key]:
			var runs := []
			var run := []
			for q: Variant in rec["pts"]:
				if inside.call(q[0], q[1], near):
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
			if not inside.call(c.x, c.y, l):
				tris.append_array([t[i], t[i + 1], t[i + 2]])
		if tris.size() == t.size():
			marks.append(m)
		elif not tris.is_empty():
			var r: Dictionary = m.duplicate()
			r["tris"] = tris
			marks.append(r)
	world["markings"] = marks
	_plant(world)


## The lot's trees and street furniture (map records, built with the map's own). A street lamp's yaw is where its arm
## reaches (over the road), a bench's where it looks.
static func _plant(world: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 536
	var arch: Dictionary = world["tree_archetypes"]
	var k := 0
	for t: Array in Plan.trees():
		var m: Vector2 = t[0]
		var kind: String = t[1] if arch.has(t[1]) else str(arch.keys()[0])
		var s := rng.randf_range(0.9, 1.1)
		world["trees"].append({"id": "lot:haignere:tree:%d" % k, "x": m.x, "y": m.y, "h": float(t[2]) * s,
				"r": float(t[2]) * 0.32 * s, "arch": kind, "var": rng.randi() % maxi(1, int(arch[kind])),
				"tint": ["leaf", "deep", "spring"][rng.randi() % 3], "src": "lot"})
		k += 1
	var props := []                                          # [model, map point, yaw]
	var strip := (Plan.STRIP.x + Plan.STRIP.y) * 0.5
	for x: float in [170.75, 195.75, 220.75, 245.75, 290.75, 303.25]:   # between the south road's beds
		var p := Plan.kerb_point(x, true, strip)
		props.append(["lamp_street", p, _yaw(Plan.kerb_point(x, true, 0.0) - p)])
	for y: float in [-73.75, -49.75, -25.75]:                # between the west road's beds
		var p := Plan.kerb_point(y, false, strip)
		props.append(["lamp_street", p, _yaw(Plan.kerb_point(y, false, 0.0) - p)])
	var into_alley := _yaw(Plan.ne_point(0.0, 1.0) - Plan.ne_point(0.0, 0.0))
	var along := -60.0                                       # path lamps along the alley's inner edge
	while along <= 100.0:
		if not Plan.in_band(Plan.ne_point(along, Plan.ALLEY.x + 0.4)):   # (not where the alley meets the sidewalk)
			props.append(["lamp_path", Plan.ne_point(along, Plan.ALLEY.x + 0.4), 0.0])
		along += 20.0
	for a: float in [9.0, 26.0, 43.0, 90.0]:                 # benches by the lawn, looking over the alley; a bin by each
		props.append(["bench_back", Plan.ne_point(a, Plan.ALLEY.x + 0.7), into_alley])
		props.append(["bin_vigipirate", Plan.ne_point(a + 1.6, Plan.ALLEY.x + 0.5), 0.0])
	var face := (Plan.E - Plan.N2).normalized()              # the terrace: bike racks along the notch's south side,
	var off := Vector2(-face.y, face.x)                      # benches and a bin by the alley
	for i in 6:
		props.append(["bike_rack", Plan.N2 + face * (14.0 + 1.5 * i) + off * 1.3, _yaw(off)])   # (clear of the door)
	props.append(["bench_back", Plan.ne_point(55.0, Plan.ALLEY.x - 1.2), _yaw(-(Plan.ne_point(0.0, 1.0) - Plan.ne_point(0.0, 0.0)))])
	props.append(["bench_back", Plan.ne_point(66.0, Plan.ALLEY.x - 1.2), _yaw(-(Plan.ne_point(0.0, 1.0) - Plan.ne_point(0.0, 0.0)))])
	props.append(["bin_vigipirate", Plan.ne_point(60.5, Plan.ALLEY.x - 0.8), 0.0])
	k = 0
	for p: Array in props:
		var m: Vector2 = p[1]
		var lift: float = Plan.lift(m) if Plan.in_band(m) else Plan.flush_lift(m) if Plan.paved(m) else 0.0
		world["props"].append({"id": "lot:haignere:prop:%d" % k, "kind": p[0], "model": p[0], "x": m.x, "y": m.y,
				"yaw": p[2], "lift": lift, "src": "lot"})
		k += 1


## A map direction's yaw (degrees: 0 east, 90 north).
static func _yaw(d: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(d.y, d.x)), 360.0)


## The ground's paint (builder/ground_builder.gd): asphalt on the road made at the corner; everything paved is drawn
## over it, so lawn all over (the ground's
## paint runs over a triangle's width: none paved under the lawns' edges), but none along the alley's outer edge (the
## map's own paths go on there), on the kerb's line (the road's own edge: its paint would run onto the road), nor on
## the map's kerb stones and markings (their skirts, flattened, keep their own).
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var grass := materials.find("grass")
	var grass_colour := Color.html(str(palette["grass"]))
	var asphalt := materials.find("asphalt")
	var asphalt_colour := Color.html(str(palette["asphalt"]))
	var kept := [materials.find("kerb"), materials.find("paint")]
	var inner := Plan.offset(Plan.lot(), -0.12)
	var road := Plan.fill().map(func(f: PackedVector2Array) -> PackedVector2Array: return Plan.offset(f, 1.6))   # (and under the strip by it: its paint would run onto the road)
	var box := Plan.bounds(Plan.area()).grow(0.2)
	for k in verts.size():
		var m := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(m) or int(ids[k * 4]) in kept:
			continue
		if road.any(func(f: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(m, f)):
			ids[k * 4] = asphalt                             # (the road made at the corner, to its old edge)
			colours[k] = asphalt_colour
			continue
		if not Geometry2D.is_point_in_polygon(m, inner) or Geometry2D.is_point_in_polygon(m, Plan.residence()):
			continue
		if Plan.off_ne(m) > Plan.ALLEY.y - 1.2 and Plan.in_flush(m):
			continue
		ids[k * 4] = grass
		colours[k] = grass_colour
	return [ids, colours]


## The lot's surfaces in the map's ground (builder/ground_bake.gd): asphalt on the road made at the corner, paving on
## what is paved, lawn on the rest of the lot.
static func surface_boxes() -> Array:
	return [Plan.bounds(Plan.lot())]


static func surface_at(x: float, y: float, _current: String) -> String:
	var m := Vector2(x, y)
	if Plan.in_fill(m):
		return "asphalt"
	if not Plan.in_lot(m):
		return ""
	return "paving" if Plan.paved(m) else "grass"


func _ready() -> void:
	name = "ResidenceHaignere"
	add_child(Builder.new().build(DisplayServer.get_name() != "headless"))
