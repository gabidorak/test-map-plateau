extends RefCounted
## The ground of restyled grounds smoothed (a spec's site.garden.flatten, from tools/restyle.py garden): heights eased
## onto a smooth surface (a quadratic fitted to the LiDAR ground, or its median: flat) by the garden's weight grid
## (site.garden.grid: 0 at the grounds' outline, full `blend` m in). Applied alike everywhere heights are made: the
## heightmap when the map is built (its collision, water, trees, props: builder/world_builder.gd), the ground's mesh
## (builder/ground_builder.gd), the heights read in the game (ground_map.gd height()). No preloads (ground_map.gd uses
## it).

const DIR := "res://data/restyle/"

static var _zones: Array = []                # [{"box", "o", "c", "x0", "y0", "cell", "w", "h", "wt"}]
static var _loaded := false
static var original: RefCounted              # (the map being built: its heights before, for the ground's mesh)


## A garden's grid layer (base64 of deflated bytes, w x h).
static func layer(grid: Dictionary, key: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(str(grid[key])).decompress(int(grid["w"]) * int(grid["h"]),
			FileAccess.COMPRESSION_DEFLATE)


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
				var garden: Dictionary = s.get("site", {}).get("garden", {})
				var fl: Dictionary = garden.get("flatten", {})
				var grid: Dictionary = garden.get("grid", {})
				if fl.is_empty() or grid.is_empty():
					continue
				var cell := float(grid["cell"])
				var x0 := float(grid["origin"][0])
				var y0 := float(grid["origin"][1])
				_zones.append({"box": Rect2(x0, y0 - cell * int(grid["h"]), cell * int(grid["w"]), cell * int(grid["h"])),
						"o": Vector2(fl["origin"][0], fl["origin"][1]), "c": PackedFloat32Array(fl["coef"]), "x0": x0,
						"y0": y0, "cell": cell, "w": int(grid["w"]), "h": int(grid["h"]), "wt": layer(grid, "weight")})
	return _zones


## How much the ground at map (x, y), `h` high on the map, moves.
static func delta(x: float, y: float, h: float) -> float:
	if _loaded and _zones.is_empty():
		return 0.0
	for z: Dictionary in zones():
		if not (z["box"] as Rect2).has_point(Vector2(x, y)):
			continue
		var w: int = z["w"]
		var fx := (x - float(z["x0"])) / float(z["cell"]) - 0.5
		var fy := (float(z["y0"]) - y) / float(z["cell"]) - 0.5
		var i := clampi(floori(fx), 0, w - 2)
		var j := clampi(floori(fy), 0, int(z["h"]) - 2)
		var u := clampf(fx - i, 0.0, 1.0)
		var v := clampf(fy - j, 0.0, 1.0)
		var wt: PackedByteArray = z["wt"]
		var k := j * w + i
		var a := lerpf(wt[k], wt[k + 1], u)
		var b := lerpf(wt[k + w], wt[k + w + 1], u)
		var weight := lerpf(a, b, v) / 255.0
		if weight <= 0.0:
			return 0.0
		var c: PackedFloat32Array = z["c"]
		var o: Vector2 = z["o"]
		var uu := (x - o.x) / 100.0
		var vv := (y - o.y) / 100.0
		return weight * (c[0] + c[1] * uu + c[2] * vv + c[3] * uu * uu + c[4] * uu * vv + c[5] * vv * vv - h)
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
