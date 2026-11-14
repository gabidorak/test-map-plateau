extends RefCounted
## The ground as the game reads it: which ground piece covers a point (kind, material, its source), the ground's
## height as its mesh draws it, where it steps. Baked when the map is built (builder/ground_bake.gd) into
## res://scenes/generated/ground.json: the map's own ground (world/ground_index.json, written by
## pipeline/plateau/ground_mesh.py and tools/rail/patch_world.py) with the lots in it, their terraforming in its
## heights and their surfaces (roads, paving, lawns) among its pieces. Shared by the grass scatter, the picker, the
## bots, the races... Coordinates are the map's x (east), y (north).

const GroundHeights = preload("res://scripts/ground_heights.gd")
const DEFAULT_INDEX := "res://scenes/generated/ground.json"
const IDS_FILE := "ground_ids.bin"
const HEIGHTS_FILE := "ground_heights.bin"

static var _cache := {}

var pieces: Array = []                  # [kind, material, first source, number of sources]
var materials: Array = []
var palette: Dictionary = {}
var piece_material := PackedByteArray() # material id per piece
var _ids := PackedByteArray()           # u16 little endian per heightmap sample: piece index + 1
var _w := 0
var _h := 0
var _cell := 0.5
var _ox := 0.0
var _oy := 0.0
var heights: RefCounted              # GroundHeights: ground height as drawn
var cliffs := {}                     # Vector2i 2 m cells where the drawn ground steps (the railway's walls, edges):
									 # there the height is not the drawn one (index "cliffs", tools/rail/patch_world.py)
var _cliffs_index := {}              # (as read: saved again)
var _mesh_cell := 2.0
var _hox := 0.0
var _hoy := 0.0


## Loaded once per index file and shared.
static func get_map(path := DEFAULT_INDEX) -> RefCounted:
	if not _cache.has(path):
		var m = load("res://scripts/ground_map.gd").new()
		if not m._load(path):
			return null
		_cache[path] = m
	return _cache[path]


## While the map is built: the ground being baked is the one every reader gets (builder/ground_bake.gd).
static func install(map: RefCounted, path := DEFAULT_INDEX) -> void:
	_cache[path] = map


## The map's own ground (world/ground_index.json, as the pipeline and the railway's patch wrote it) on `h`, its
## heights as built (GroundHeights of the terraformed heightmap): what builder/ground_bake.gd bakes.
static func from_map_index(path: String, h: RefCounted) -> RefCounted:
	var index = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not index is Dictionary:
		push_error("cannot read %s" % path)
		return null
	var m = load("res://scripts/ground_map.gd").new()
	m._read(index)
	var ids: Dictionary = index["ids"]
	m._ids = FileAccess.get_file_as_bytes(path.get_base_dir().path_join(ids["file"])).decompress(ids["raw"],
			FileAccess.COMPRESSION_DEFLATE)
	m.heights = h
	return m


func _load(path: String) -> bool:
	var index = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not index is Dictionary:
		push_error("cannot read %s: build the map (tools/build_world.gd)" % path)
		return false
	var dir := path.get_base_dir()
	_read(index)
	var ids: Dictionary = index["ids"]
	_ids = FileAccess.get_file_as_bytes(dir.path_join(ids["file"])).decompress(ids["raw"], FileAccess.COMPRESSION_DEFLATE)
	var hm: Dictionary = index["heights"]
	var nodes := FileAccess.get_file_as_bytes(dir.path_join(hm["file"])).decompress(int(hm["raw"]),
			FileAccess.COMPRESSION_DEFLATE).to_float32_array()
	heights = GroundHeights.from_nodes(nodes, hm)
	return heights != null and _ids.size() == _w * _h * 2


## The index's pieces, materials, ids' grid, heights' grid and cliffs.
func _read(index: Dictionary) -> void:
	pieces = index["pieces"]
	materials = index["materials"]
	palette = index["palette"]
	piece_material.resize(pieces.size())
	for k in pieces.size():
		piece_material[k] = materials.find(pieces[k][1])
	var ids: Dictionary = index["ids"]
	_w = ids["w"]
	_h = ids["h"]
	_cell = ids["cell"]
	_ox = ids["origin_xy"][0]
	_oy = ids["origin_xy"][1]
	var hm: Dictionary = index["heights"]
	_mesh_cell = hm["mesh_cell"]
	_hox = hm["origin_xy"][0]
	_hoy = hm["origin_xy"][1]
	_cliffs_index = index.get("cliffs", {})
	for c: Array in _cliffs_index.get("cells", []):
		cliffs[Vector2i(int(c[0]), int(c[1]))] = true


## Index into `pieces` of the ground piece at pipeline (x, y), or -1 outside the map.
func piece_at(x: float, y: float) -> int:
	var c := roundi((x - _ox) / _cell)
	var r := roundi((_oy - y) / _cell)
	if c < 0 or r < 0 or c >= _w or r >= _h:
		return -1
	return _ids.decode_u16((r * _w + c) * 2) - 1


## Material id (index in `materials`) at (x, y), or -1.
func material_at(x: float, y: float) -> int:
	var k := piece_at(x, y)
	return piece_material[k] if k >= 0 else -1


## Ground height (relative to the world origin) as drawn by the ground mesh.
func height(x: float, y: float) -> float:
	return heights.at(x, y)


## True in a 2 m cell where the drawn ground steps (a wall, a platform edge): height() is not the drawn height there.
func in_cliff(x: float, y: float) -> bool:
	if cliffs.is_empty():
		return false
	return cliffs.has(Vector2i(floori((x - _hox) / _mesh_cell + 1.0), floori((_hoy - y) / _mesh_cell + 1.0)))


## Text for the picker.
func describe(x: float, y: float) -> String:
	var k := piece_at(x, y)
	if k < 0:
		return "Ground: outside the map"
	var p: Array = pieces[k]
	var src := "" if p[2] == "" else " · %s%s" % [p[2], (" +%d" % (int(p[3]) - 1)) if int(p[3]) > 1 else ""]
	return "Ground #%d: %s · %s%s" % [k, p[0], p[1], src]


# ---------------------------------------------------------------- baking (builder/ground_bake.gd)

## The ids' grid: sample (c, r) at x = origin.x + c * cell, y = origin.y - r * cell.
func ids_grid() -> Dictionary:
	return {"w": _w, "h": _h, "cell": _cell, "origin": Vector2(_ox, _oy)}


## The piece at sample (c, r) (-1: none), and setting it.
func piece_at_sample(c: int, r: int) -> int:
	return _ids.decode_u16((r * _w + c) * 2) - 1


func set_piece_at_sample(c: int, r: int, k: int) -> void:
	_ids.encode_u16((r * _w + c) * 2, k + 1)


## A new ground piece: its index.
func add_piece(kind: String, material: String, src: String) -> int:
	pieces.append([kind, material, src, 1])
	piece_material.append(materials.find(material))
	return pieces.size() - 1


## A material the map has not (a lot's: the railway's ballast), with its colour.
func add_material(material: String, colour: String) -> void:
	if not material in materials:
		materials.append(material)
		for k in pieces.size():
			if pieces[k][1] == material:
				piece_material[k] = materials.size() - 1
	if not (palette.get("ground", {}) as Dictionary).has(material):
		palette["ground"] = (palette.get("ground", {}) as Dictionary).duplicate()
		palette["ground"][material] = colour


## The 2 m cell at map (x, y) is a cliff: the drawn ground steps there (a lot's own ground's wall).
func add_cliff(x: float, y: float) -> void:
	var c := Vector2i(floori((x - _hox) / _mesh_cell + 1.0), floori((_hoy - y) / _mesh_cell + 1.0))
	if cliffs.has(c):
		return
	cliffs[c] = true
	if not _cliffs_index.has("cells"):
		_cliffs_index = {"about": "2 m cells (node i, j as ground_heights.gd counts them) where the ground steps: the "
				+ "height there is not the drawn one, so no grass tufts", "cells": []}
	_cliffs_index["cells"].append([c.x, c.y])


## Saved as `path` (the index) and its two files beside it.
func save(path: String, about: String) -> Error:
	var dir := path.get_base_dir()
	var nf: PackedFloat32Array = heights.nodes()
	var nodes := nf.to_byte_array()
	var hm: Dictionary = heights.grid()
	hm["file"] = HEIGHTS_FILE
	hm["raw"] = nodes.size()
	var index := {"about": about, "materials": materials, "palette": palette, "pieces": pieces,
			"ids": {"file": IDS_FILE, "w": _w, "h": _h, "cell": _cell, "origin_xy": [_ox, _oy], "raw": _ids.size()},
			"heights": hm, "cliffs": _cliffs_index}
	for f: Array in [[IDS_FILE, _ids.compress(FileAccess.COMPRESSION_DEFLATE)],
			[HEIGHTS_FILE, nodes.compress(FileAccess.COMPRESSION_DEFLATE)]]:
		var out := FileAccess.open(dir.path_join(f[0]), FileAccess.WRITE)
		if out == null:
			return FileAccess.get_open_error()
		out.store_buffer(f[1])
		out.close()
	var js := FileAccess.open(path, FileAccess.WRITE)
	if js == null:
		return FileAccess.get_open_error()
	js.store_string(JSON.stringify(index))
	js.close()
	return OK
