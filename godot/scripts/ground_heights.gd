extends RefCounted
## Ground height as the ground mesh draws it (pipeline/plateau/ground_mesh.py Heights): heightmap
## samples every `mesh_cell` metres, planar inside the two triangles of each cell (diagonal
## south-west -> north-east). Used for the terrain collision (so feet sit on the drawn ground), the
## grass scatter and the picker. Pipeline coordinates: x east, y north.

var _nodes := PackedFloat32Array()      # node (j, i) at x = ox + (i - 1) * mesh_cell, y = oy - (j - 1) * mesh_cell
var _nw := 0
var _nh := 0
var _ox := 0.0
var _oy := 0.0
var _mesh_cell := 2.0


## The heightmap described by world.json "terrain" (or ground_index.json "heights") in `dir`: its file, or the bands of
## rows it is split into when large ("parts", pipeline/plateau/terrain.py write_heightmap), joined in order.
static func read_heightmap(dir: String, t: Dictionary) -> PackedFloat32Array:
	var bytes := PackedByteArray()
	for f in t.get("parts", [t["file"]]):
		bytes.append_array(FileAccess.get_file_as_bytes(dir.path_join(f)))
	return bytes.to_float32_array()


## heights: the heightmap (row 0 north), w x h samples `cell` apart, sample (0, 0) at (ox, oy).
func _init(heights: PackedFloat32Array, w: int, h: int, cell: float, ox: float, oy: float, mesh_cell: float) -> void:
	_ox = ox
	_oy = oy
	_mesh_cell = mesh_cell
	var step := roundi(mesh_cell / cell)
	_nw = (w - 1) / step + 4
	_nh = (h - 1) / step + 4
	_nodes.resize(_nw * _nh)
	for j in _nh:
		var r := clampi((j - 1) * step, 0, h - 1)
		for i in _nw:
			_nodes[j * _nw + i] = heights[r * w + clampi((i - 1) * step, 0, w - 1)]


func at(x: float, y: float) -> float:
	var fx := (x - _ox) / _mesh_cell + 1.0
	var fy := (_oy - y) / _mesh_cell + 1.0
	var i := clampi(floori(fx), 0, _nw - 2)
	var j := clampi(floori(fy), 0, _nh - 2)
	var u := fx - i
	var v := fy - j
	var z00 := _nodes[j * _nw + i]
	var z10 := _nodes[j * _nw + i + 1]
	var z01 := _nodes[(j + 1) * _nw + i]
	var z11 := _nodes[(j + 1) * _nw + i + 1]
	if u + v <= 1.0:
		return z00 + u * (z10 - z00) + v * (z01 - z00)
	return z11 + (1.0 - u) * (z01 - z11) + (1.0 - v) * (z10 - z11)
