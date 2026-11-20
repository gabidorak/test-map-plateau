extends Node3D
## Lot sousPrefecture (lots/sousPrefecture/lot.json): the sous-préfecture de Palaiseau (#630, osm:r20158551) made the
## police's commissariat, after Thomas's references (ref/prefecture/; its plan: commissariat_plan.gd). When the map is
## built: its ground one plane (terraformed), out of the map the building #630 and, in the lot, the map's trees, props
## (but the street furniture on the new sidewalk: up on it), hedges, kerbs, fences and the cycle track's markings; in,
## the lot's trees (the courtyard's, the lawns', the row on the sidewalk), the car park's fence, its two lift gates
## across the way out (they break when a car rams them, scripts/breakables.gd), the hedge north of it, the courtyard's
## benches and bins (map records: built with the map's own); the ground painted lawn, asphalt under the car park and
## the road's edge; its surfaces in the map's ground (surface_at(): builder/ground_bake.gd). Drawn at start: the
## building (commissariat_builder.gd), the sidewalk, the car park and the paths (grounds_builder.gd).
## Its places, read through builder/lots.gd: the police's (scripts/police/police.gd: the helicopter's base on the
## heliport, where the arrested are let go: before the entrance), PTA Online's public vehicles (the car park's police
## cars: scripts/online/public_vehicles.gd).

const Plan = preload("res://lots/sousPrefecture/commissariat_plan.gd")
const Building = preload("res://lots/sousPrefecture/commissariat_builder.gd")
const Grounds = preload("res://lots/sousPrefecture/grounds_builder.gd")
const Lots = preload("res://scripts/builder/lots.gd")
const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const BUILDING_ID := "osm:r20158551"        # #630
const ID := "lot:sousPrefecture"
const KEPT_PROPS := ["fire_hydrant", "sign", "traffic_light", "pedestrian_light"]   # (on the sidewalk: up on it)
const KEPT_MARKS := ["zebra", "stop_line", "centre_line", "lane_line"]

var game: Node                              # game.gd
var building: Node3D                        # what the builders made
var grounds: Node3D


## The world without #630 and the map's things in the lot; with the lot's own.
static func drop(world: Dictionary) -> void:
	var footprint := Plan.map_poly(Plan.building())
	WorldEdits.drop_buildings(world, [BUILDING_ID], WorldEdits.grown(footprint, 1.0))
	var l := Plan.map_poly(Plan.lot())
	var near := WorldEdits.grown(l, 0.6)
	var box := Plan.bounds(near)
	var inside := func(x: float, y: float, poly: PackedVector2Array) -> bool:
		return box.has_point(Vector2(x, y)) and Geometry2D.is_point_in_polygon(Vector2(x, y), poly)
	var row := []                                            # (the sidewalk's trees and the flags: room round them)
	for y: float in Plan.STREET_TREES + Plan.FLAGS:
		row.append(Plan.to_map(Vector2(Plan.tree_x(y), y)))
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool:
		var p := Vector2(t["x"], t["y"])
		return not inside.call(p.x, p.y, l) and row.all(func(q: Vector2) -> bool: return p.distance_to(q) > 3.0))
	var props := []
	for p: Dictionary in world["props"]:
		if not inside.call(p["x"], p["y"], l):
			props.append(p)
			continue
		var at := Plan.to_local(Vector2(p["x"], p["y"]))
		if p["kind"] in KEPT_PROPS and Plan.in_sidewalk(at):
			p["lift"] = Plan.sidewalk_lift(at.y)
			props.append(p)
	world["props"] = props
	var marks := []                                          # (the markings' triangles in it out: the cycle track's)
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
	for key: String in ["hedges", "kerbs", "fences"]:        # (the lines cut: their runs out of it kept)
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
	_plant(world)


## The lot's trees, fence, hedge, gates and furniture (map records).
static func _plant(world: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 630
	var arch: Dictionary = world["tree_archetypes"]
	var trees := Plan.TREES.duplicate()
	for y: float in Plan.STREET_TREES:
		trees.append([Vector2(Plan.tree_x(y), y), "round", 9.0])
	var k := 0
	for t: Array in trees:
		var m := Plan.to_map(t[0])
		var kind: String = t[1] if arch.has(t[1]) else str(arch.keys()[0])
		var s := rng.randf_range(0.9, 1.1)
		world["trees"].append({"id": "%s:tree:%d" % [ID, k], "x": m.x, "y": m.y, "h": float(t[2]) * s,
				"r": float(t[2]) * 0.32 * s, "arch": kind, "var": rng.randi() % maxi(1, int(arch[kind])),
				"tint": ["leaf", "deep", "spring"][rng.randi() % 3], "src": "lot"})
		k += 1
	k = 0
	for line: Array in Plan.fence():
		world["fences"].append({"id": "%s:fence:%d" % [ID, k], "style": "bars", "h": 2.0, "height_src": "lot",
				"osm": "", "pts": line.map(func(p: Vector2) -> Array: return [Plan.to_map(p).x, Plan.to_map(p).y])})
		k += 1
	var hedge := [Vector2(Plan.FENCE_W, Plan.HEDGE_Y), Vector2(Plan.NORTH_E, Plan.HEDGE_Y)]
	world["hedges"].append({"id": "%s:hedge:0" % ID, "h": 1.5, "w": 1.1, "tint": "spring", "src": "lot",
			"height_src": "lot", "pts": hedge.map(func(p: Vector2) -> Array: return [Plan.to_map(p).x, Plan.to_map(p).y])})
	var props := []                                          # [model, local, front (local direction), scale, lift]
	var up := Vector2(0, 1)
	# the lift gates: their arm (the model's x, a quarter turn anticlockwise from its front: prop_placer.gd) 3 m across
	# the way out, one from each post (the south one's arm north, its front into the car park; the north one's south)
	var span := 0.75
	var post := 2.15 * span
	var gate_x := Plan.FENCE_W + 0.5
	props.append(["lift_gate", Vector2(gate_x, Plan.BAYS_S.y + 0.2 + post), Vector2(1, 0), [span, 1.0], 0.04])
	props.append(["lift_gate", Vector2(gate_x, Plan.BAYS_N.x - 0.2 - post), Vector2(-1, 0), [span, 1.0], 0.04])
	for b: Array in Plan.BENCHES:
		props.append(["bench_back", b[0], b[1], [1.0, 1.0], 0.0])
	for p: Vector2 in Plan.BINS:
		props.append(["bin_vigipirate", p, up, [1.0, 1.0], 0.0])
	k = 0
	for p: Array in props:
		var m := Plan.to_map(p[1])
		world["props"].append({"id": "%s:prop:%d" % [ID, k], "kind": p[0], "model": p[0], "x": m.x, "y": m.y,
				"yaw": Plan.yaw_prop(p[2]), "lift": p[4], "scale": p[3], "src": "lot"})
		k += 1


## The ground's paint (builder/ground_builder.gd): asphalt under the car park, on the road's edge (past the kerb) and
## under the sidewalk (the ground's paint blends across its triangles: lawn there would show along the kerb), lawn
## over the rest of the lot (the paths are drawn over it); not on the map's kerb stones and markings.
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var grass := materials.find("grass")
	var grass_colour := Color.html(str(palette["grass"]))
	var asphalt := materials.find("asphalt")
	var asphalt_colour := Color.html(str(palette["asphalt"]))
	var kept := [materials.find("kerb"), materials.find("paint")]
	var inner := WorldEdits.grown(Plan.map_poly(Plan.lot()), -0.12)
	var box := Plan.bounds(inner)
	for k in verts.size():
		var m := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(m) or int(ids[k * 4]) in kept or not Geometry2D.is_point_in_polygon(m, inner):
			continue
		var p := Plan.to_local(m)
		if Plan.in_carpark(p) or Plan.in_road(p) or (Plan.in_sidewalk(p) and p.x < -1.0):
			ids[k * 4] = asphalt                             # (under the sidewalk too: no lawn by the kerb)
			colours[k] = asphalt_colour
		else:
			ids[k * 4] = grass
			colours[k] = grass_colour
	return [ids, colours]


## The lot's surfaces in the map's ground (builder/ground_bake.gd): asphalt (the car park, the road's edge), paving
## (the sidewalk, the paths, the apron), lawn on the rest of the lot; under the building, the map's.
static func surface_boxes() -> Array:
	return [Plan.bounds(Plan.map_poly(Plan.lot()))]


static func surface_at(x: float, y: float, _current: String) -> String:
	var p := Plan.to_local(Vector2(x, y))
	if not Plan.in_lot(p):
		return ""
	if Plan.in_carpark(p) or Plan.in_road(p):
		return "asphalt"
	if Plan.in_sidewalk(p) or Plan.in_paved(p):
		return "paving"
	if Plan.in_solid(p):
		return ""
	return "grass"


## The police's places (scripts/police/police.gd).
static func police_places() -> Dictionary:
	return Plan.places()


## PTA Online's public vehicles here (scripts/online/public_vehicles.gd): the car park's police cars.
static func public_vehicles() -> Array:
	return Plan.vehicles()


func _ready() -> void:
	name = "Commissariat"
	building = Building.new().build(Lots.meshes())
	add_child(building)
	grounds = Grounds.new().build(Lots.meshes())
	add_child(grounds)
