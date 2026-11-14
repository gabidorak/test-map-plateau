extends RefCounted
## Lot logementsX (data/lots/logementsX.json): the École polytechnique's new student housing on the Boulevard des
## Maréchaux, on its design data/logementsX/plan.json (tools/logements_x/build_plan.py, logements_x.py: the six R+5
## plots, their gardens, the residents' car park, the boulevard's sidewalk). When the map is built:
## - its terraforming (terraform_zones()): the site's ground one smooth surface (the plan's repair grid);
## - its own ground (ground_owned()): the boulevard's sidewalk, a step over the road (the map's ground cut out there,
##   builder/ground_cut.gd; logements_x_builder.gd draws it and its collision);
## - its removals and additions (its drop, data/logementsX/drop.json: builder/world_edits.gd): the construction site's
##   fence and trees out, its trees, props (lamps, benches, bike racks...) in, the props on its sidewalk lifted onto it,
##   the map's kerbs cut back, the kit modules on its plots out, the six OSM placeholder blocks swapped for the plan's
##   buildings (same ids);
## - its surfaces in the map's ground (surface_at()) and the ground's paint (repaint()): the plan's zones (the road
##   fill and the car park asphalt, the forecourts, paths and sidewalk concrete, the gravel strips, the lawns);
## - its build (logements_x_builder.gd): the facades, the surfaces themselves, kerbs, markings, bollards, boulders.

const Plan = preload("res://scripts/logementsX/logements_x_plan.gd")
const GroundMap = preload("res://scripts/ground_map.gd")



static func terraform_zones() -> Array:
	var out := []
	for rp: Dictionary in Plan.data()["repairs"]:
		var g: Dictionary = rp["grid"]
		var w := int(g["w"])
		var h := int(g["h"])
		var cell := float(g["cell"])
		var x0 := float(g["x0"])
		var y0 := float(g["y0"])
		var core: Array = rp["core"].map(func(c: Array) -> PackedVector2Array: return Plan.ring(c))
		var wt := PackedByteArray()
		wt.resize(w * h)
		var sf := PackedFloat32Array()
		sf.resize(w * h)
		for j in h:
			for i in w:
				var k := j * w + i
				var p := Vector2(x0 + i * cell, y0 - j * cell)            # (the grid's samples on its nodes)
				sf[k] = float(g["z"][k])
				wt[k] = 255 if core.any(func(c: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, c)) else 0
		# terraform.gd's samples are at their cells' middles: the grid moved half a cell so they fall on its nodes
		out.append({"box": Rect2(x0 - cell * 0.5, y0 + cell * 0.5 - cell * h, cell * w, cell * h), "x0": x0 - cell * 0.5,
				"y0": y0 + cell * 0.5, "cell": cell, "w": w, "h": h, "wt": wt, "s": sf})
	return out


static func ground_owned() -> Array:
	var out := []
	for z: Array in Plan.zones():
		if z[0] == "logx:sidewalk":
			for pg: Array in z[3]:
				out.append(pg[0])
	return out


static func surface_boxes() -> Array:
	return [Plan.box()]


static func surface_at(x: float, y: float, _current: String) -> String:
	return Plan.material_at(Vector2(x, y))


## The ground's paint (builder/ground_builder.gd) in the site: the lawns grass; under the surfaces drawn over the ground
## (and the plots), the ground's material just outside them, so that the paint, which runs over a triangle of the
## ground mesh, stops at their edges on either side (the lawn's green on one, the boulevard's asphalt on the other).
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var box := Plan.box().grow(1.0)
	var gm: RefCounted = GroundMap.get_map()                 # (the ground being baked: its lawns, the map's road)
	for k in verts.size():
		var m := Vector2(verts[k].x, -verts[k].z)
		if not box.has_point(m):
			continue
		var mat := Plan.material_at(m)
		if mat == "":
			continue
		if mat != "grass":
			mat = _outside(m, gm, materials)
			if mat == "":
				continue
		ids[k * 4] = materials.find(mat)
		colours[k] = Color.html(str(palette.get(mat, palette["grass"])))
	return [ids, colours]


## The ground's material nearest map point m out of the surfaces drawn over it ("" none within 4 m).
static func _outside(m: Vector2, gm: RefCounted, materials: Array) -> String:
	for r: float in [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]:
		for i in 16:
			var q := m + Vector2.from_angle(TAU * i / 16.0) * r
			var mat := Plan.material_at(q)
			if mat == "grass" or (mat == "" and gm):
				if mat == "grass":
					return mat
				var id: int = gm.material_at(q.x, q.y)
				if id >= 0 and id < materials.size():
					return str(materials[id])
	return ""
