extends SceneTree
## Review image of every toy ground material (toy_ground.gdshader) under the game lighting:
## data/review/<area>/ground_swatches.png. Needs a window (real renderer).
## godot --path godot --script res://tools/ground_swatches.gd

const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const SIZE := 4.0
const GAP := 1.2
const COLS := 5

var _main: Node
var _frames := 0
var _out := ""


func _initialize() -> void:
	var map := GroundMap.get_map()
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://world/world.json"))
	_out = ProjectSettings.globalize_path("res://").path_join("../data/review").path_join(world["meta"]["area"]) \
			.path_join("ground_swatches.png").simplify_path()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_main.get_node("Neighborhood").visible = false
	var mat := ShaderMaterial.new()
	mat.shader = load(GroundBuilder.SHADER)
	var names: Array = GroundBuilder.MATERIALS.filter(func(m): return m != "building")
	var holder := Node3D.new()
	holder.position = Vector3(0, 300, 0)
	_main.add_child(holder)
	for k in names.size():
		var name: String = names[k]
		var col: String
		if name == "kerb":
			col = map.palette["kerb"]["raised"]
		elif name == "paint":
			col = map.palette["markings"]["white"]
		else:
			col = map.palette["ground"][name]
		var x := (k % COLS) * (SIZE + GAP)
		var z := (k / COLS) * (SIZE + GAP)
		holder.add_child(_quad(x, z, Color.html(col), GroundBuilder.MATERIALS.find(name), mat))
		var label := Label3D.new()
		label.text = name
		label.font_size = 64
		label.pixel_size = 0.006
		label.outline_size = 12
		label.position = Vector3(x + SIZE / 2.0, 0.05, z + SIZE + 0.4)
		label.rotation_degrees = Vector3(-90, 0, 0)
		holder.add_child(label)


func _quad(x: float, z: float, col: Color, id: int, mat: Material) -> MeshInstance3D:
	var n := 8
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var custom := PackedByteArray()
	var idx := PackedInt32Array()
	for i in n + 1:
		for j in n + 1:
			verts.append(Vector3(x + SIZE * j / n, 0.0, z + SIZE * i / n))
			normals.append(Vector3.UP)
			colors.append(col)
			custom.append_array([id, 0, 0, 0])
	for i in n:
		for j in n:
			var a := i * (n + 1) + j
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.set_screenshot_mode()
		var cam: Camera3D = _main.get_node("Camera")
		var w := COLS * (SIZE + GAP) - GAP
		cam.look_at_from_position(Vector3(w / 2.0, 323.0, 19.0), Vector3(w / 2.0, 300.0, 9.5))
		cam.fov = 55.0
	elif _frames == 45:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
