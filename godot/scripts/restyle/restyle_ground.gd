extends RefCounted
## The ground of restyled grounds smoothed (a spec's site.garden.flatten, from tools/restyle.py garden): heights eased
## onto a smooth surface (a quadratic fitted to the LiDAR ground, or its median: flat), fully `blend` m inside the
## grounds' outline, the map's at it. Applied alike everywhere heights are made: the heightmap when the map is built
## (its collision, water, trees, props: builder/world_builder.gd), the ground's mesh (builder/ground_builder.gd), the
## heights read in the game (ground_map.gd height()). No preloads (ground_map.gd uses it).

const DIR := "res://data/restyle/"

static var _zones: Array = []                # [{"poly", "box", "o", "c", "blend"}]
static var _loaded := false
static var original: RefCounted              # (the map being built: its heights before, for the ground's mesh)


static func zones() -> Array:
	if not _loaded:
		_loaded = true
		if DirAccess.dir_exists_absolute(DIR):
			for f in DirAccess.get_files_at(DIR):
				if not f.ends_with(".json") or f.begins_with("_"):
					continue
				var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
				if not (s is Dictionary):
					continue
				var fl: Dictionary = s.get("site", {}).get("garden", {}).get("flatten", {})
				if fl.is_empty():
					continue
				var poly := PackedVector2Array()
				for q: Array in fl["poly"]:
					poly.append(Vector2(q[0], q[1]))
				var box := Rect2(poly[0], Vector2.ZERO)
				for p in poly:
					box = box.expand(p)
				_zones.append({"poly": poly, "box": box, "o": Vector2(fl["origin"][0], fl["origin"][1]),
						"c": fl["coef"], "blend": float(fl.get("blend", 8.0))})
	return _zones


## How much the ground at map (x, y), `h` high on the map, moves.
static func delta(x: float, y: float, h: float) -> float:
	if _loaded and _zones.is_empty():
		return 0.0
	var p := Vector2(x, y)
	for z: Dictionary in zones():
		if not (z["box"] as Rect2).has_point(p):
			continue
		var poly: PackedVector2Array = z["poly"]
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var d := INF
		for i in poly.size():
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
		var c: Array = z["c"]
		var o: Vector2 = z["o"]
		var u := (x - o.x) / 100.0
		var v := (y - o.y) / 100.0
		var s := float(c[0]) + float(c[1]) * u + float(c[2]) * v + float(c[3]) * u * u + float(c[4]) * u * v \
				+ float(c[5]) * v * v
		return smoothstep(0.0, z["blend"], d) * (s - h)
	return 0.0


## The heightmap (world.json "terrain": row 0 north, `cell` m apart from origin_xy) smoothed in the zones.
static func patch(heights: PackedFloat32Array, t: Dictionary) -> void:
	var w := int(t["w"])
	var hh := int(t["h"])
	var cell := float(t["cell"])
	var ox := float(t["origin_xy"][0])
	var oy := float(t["origin_xy"][1])
	for z: Dictionary in zones():
		var box: Rect2 = z["box"]
		var i0 := clampi(floori((box.position.x - ox) / cell), 0, w - 1)
		var i1 := clampi(ceili((box.end.x - ox) / cell), 0, w - 1)
		var j0 := clampi(floori((oy - box.end.y) / cell), 0, hh - 1)
		var j1 := clampi(ceili((oy - box.position.y) / cell), 0, hh - 1)
		for j in range(j0, j1 + 1):
			var y := oy - j * cell
			for i in range(i0, i1 + 1):
				var k := j * w + i
				heights[k] += delta(ox + i * cell, y, heights[k])


## A ground chunk's vertices (Godot x, y, z; its box `aabb` [x, y, z, sx, sy, sz]) moved alike.
static func move(verts: PackedVector3Array, aabb: Array) -> void:
	if original == null or zones().is_empty():
		return
	var r := Rect2(float(aabb[0]), -float(aabb[2]) - float(aabb[5]), float(aabb[3]), float(aabb[5]))
	var near := false
	for z: Dictionary in _zones:
		near = near or (z["box"] as Rect2).intersects(r)
	if not near:
		return
	for k in verts.size():
		var v := verts[k]
		var d := delta(v.x, -v.z, original.at(v.x, -v.z))
		if d != 0.0:
			verts[k] = Vector3(v.x, v.y + d, v.z)
