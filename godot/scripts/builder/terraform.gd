extends RefCounted
## Terraforming, the zones the lots name (builder/lots.gd): files of data/terraform/ (made by tools/terraform.py: a
## surface fitted to the LiDAR ground, a quadratic or a plane, or a level: a restyled garden, the villa's garden path)
## or a lot's code (its terraform_zones(): a surface given cell by cell, the villa's court). In each zone the map's
## heights are eased onto the surface by the zone's weight grid (0 at its outline, full `blend` m in). The first step after the map
## is read (builder/world_builder.gd), so everything is built on the ground as it ends up. Applied alike everywhere
## heights are made: the
## heightmap when the map is built (its collision, water, trees, props: builder/world_builder.gd), the ground's mesh
## and its raised sidewalks' collision (builder/ground_builder.gd), the heights read in the game (ground_map.gd
## height()). No preloads (ground_map.gd uses it).

const DIR := "res://data/terraform/"
const Lots = preload("res://scripts/builder/lots.gd")

static var _zones: Array = []                # [{"box", "x0", "y0", "cell", "w", "h", "wt"; "o", "c" or "s"}]
static var _loaded := false


## A grid's layer (base64 of deflated bytes, w x h: data/terraform's weights, a restyled garden's kind).
static func layer(grid: Dictionary, key: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(str(grid[key])).decompress(int(grid["w"]) * int(grid["h"]),
			FileAccess.COMPRESSION_DEFLATE)


static func zones() -> Array:
	if not _loaded:
		_loaded = true
		if DirAccess.dir_exists_absolute(DIR):
			for name: String in Lots.terraform_files():          # (the lots' zones: builder/lots.gd)
				if name.ends_with(".gd"):                       # (a lot's code makes its zones: terraform_zones())
					_zones.append_array(load(name).terraform_zones())
					continue
				var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + name + ".json"))
				if not (s is Dictionary):
					continue
				for zn: Dictionary in s.get("zones", []):
					var grid: Dictionary = zn["grid"]
					var cell := float(grid["cell"])
					var x0 := float(grid["origin"][0])
					var y0 := float(grid["origin"][1])
					_zones.append({"box": Rect2(x0, y0 - cell * int(grid["h"]), cell * int(grid["w"]),
							cell * int(grid["h"])), "o": Vector2(zn["origin"][0], zn["origin"][1]),
							"c": PackedFloat32Array(zn["coef"]), "x0": x0, "y0": y0, "cell": cell, "w": int(grid["w"]),
							"h": int(grid["h"]), "wt": layer(grid, "weight")})
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
		if z.has("s"):                                   # (a surface given cell by cell)
			var sf: PackedFloat32Array = z["s"]
			return weight * (lerpf(lerpf(sf[k], sf[k + 1], u), lerpf(sf[k + w], sf[k + w + 1], u), v) - h)
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


## A ground chunk's vertices (Godot x, y, z; its box `aabb` [x, y, z, sx, sy, sz]) moved alike, each from its own
## height: where a zone's weight is full its surface is met exactly, whatever stood on the old ground (a raised
## sidewalk, a building's pad); where the weight eases, so do they.
static func move(verts: PackedVector3Array, aabb: Array) -> void:
	var r := Rect2(float(aabb[0]), -float(aabb[2]) - float(aabb[5]), float(aabb[3]), float(aabb[5]))
	if not zones().any(func(z: Dictionary) -> bool: return (z["box"] as Rect2).intersects(r)):
		return
	for k in verts.size():
		var v := verts[k]
		var d := delta(v.x, -v.z, v.y)
		if d != 0.0:
			verts[k] = Vector3(v.x, v.y + d, v.z)
