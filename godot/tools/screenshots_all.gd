extends SceneTree
## Renders every viewpoint of tools/viewpoints.json into data/review/shots/<milestone>/<name>.png.
## godot --path godot --script res://tools/screenshots_all.gd -- --milestone=M2 [--only=name,name]
## Needs a window (not --headless): it uses the real renderer.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const SETTLE_FRAMES := 40       # frames per shot, so shadows and SSAO/SSIL converge

var _main: Node
var _views: Array = []
var _out_dir := ""
var _index := 0
var _frames := -10              # a few frames for the scene and physics to start


func _initialize() -> void:
	var milestone := "latest"
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "--milestone":
			milestone = kv[1]
		elif kv.size() == 2 and kv[0] == "--only":
			only = kv[1].split(",")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/viewpoints.json"))
	for v: Dictionary in data["viewpoints"]:
		if only.is_empty() or v["name"] in only:
			_views.append(v)
	_out_dir = ProjectSettings.globalize_path("res://").path_join("../data/review/shots").path_join(milestone).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 0:
		_main.set_screenshot_mode()
		_place(_views[_index])
	elif _frames == SETTLE_FRAMES:
		var v: Dictionary = _views[_index]
		var path := _out_dir.path_join(v["name"] + ".png")
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_index += 1
		if _index >= _views.size():
			return true
		_frames = 0
		_place(_views[_index])
	return false


## Viewpoint heights are above the ground (terrain, not roofs) under each point.
func _place(v: Dictionary) -> void:
	var cam: Camera3D = _main.get_node("Camera")
	cam.look_at_from_position(_point(v["eye"]), _point(v["target"]))


func _point(p: Array) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), p[0], -p[1])
	return MeshUtils.to_godot(p[0], p[1], (0.0 if is_nan(g) else g) + p[2])
