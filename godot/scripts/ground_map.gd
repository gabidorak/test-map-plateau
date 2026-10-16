extends RefCounted
## Runtime ground lookups from world/ground_index.json (written by pipeline/plateau/ground_mesh.py):
## which ground piece covers a point (kind, material, OSM source) and the ground height as the
## mesh draws it. Coordinates are pipeline x (east), y (north). Shared by the grass scatter and the picker.

const GroundHeights = preload("res://scripts/ground_heights.gd")
const DEFAULT_INDEX := "res://world/ground_index.json"

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


func _load(path: String) -> bool:
	var index = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not index is Dictionary:
		push_error("cannot read %s" % path)
		return false
	var dir := path.get_base_dir()
	pieces = index["pieces"]
	materials = index["materials"]
	palette = index["palette"]
	piece_material.resize(pieces.size())
	for k in pieces.size():
		piece_material[k] = materials.find(pieces[k][1])
	var ids: Dictionary = index["ids"]
	_ids = FileAccess.get_file_as_bytes(dir.path_join(ids["file"])).decompress(ids["raw"], FileAccess.COMPRESSION_DEFLATE)
	_w = ids["w"]
	_h = ids["h"]
	_cell = ids["cell"]
	_ox = ids["origin_xy"][0]
	_oy = ids["origin_xy"][1]

	var hm: Dictionary = index["heights"]
	var data := FileAccess.get_file_as_bytes(dir.path_join(hm["file"])).to_float32_array()
	heights = GroundHeights.new(data, hm["w"], hm["h"], hm["cell"], hm["origin_xy"][0], hm["origin_xy"][1], hm["mesh_cell"])
	_mesh_cell = hm["mesh_cell"]
	_hox = hm["origin_xy"][0]
	_hoy = hm["origin_xy"][1]
	for c: Array in index.get("cliffs", {}).get("cells", []):
		cliffs[Vector2i(int(c[0]), int(c[1]))] = true
	return _ids.size() == _w * _h * 2


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
