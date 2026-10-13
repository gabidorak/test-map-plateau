extends SceneTree
## Renders the game from the camera pose of each landmark reference photo (milestone M9), at the photo's
## aspect ratio and horizontal field of view, for the photo | render review sheets.
## godot --path godot --script res://tools/landmark_shots.gd -- --shots=/abs/path/shots.json
## shots.json (written by `python -m plateau landmark <name>`): {"shots": [{"eye": [x, y, h], "target": [x, y, h],
## "fov": degrees (horizontal), "w": px, "h": px, "out": "/abs/path.png"}]}, pipeline axes, heights above the
## ground under each point. Needs a window (not --headless): it uses the real renderer.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const SETTLE_FRAMES := 40       # frames per shot, so shadows and SSAO/SSIL converge

var _main: Node
var _shots: Array = []
var _index := 0
var _frames := -10              # a few frames for the scene and physics to start


func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "--shots":
			path = kv[1]
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("shots", []).is_empty():
		push_error("no shots in %s" % path)
		quit(1)
		return
	_shots = data["shots"]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _shots.is_empty():
		return true
	_frames += 1
	if _frames == 0:
		_main.set_screenshot_mode()
		_place(_shots[_index])
	elif _frames == SETTLE_FRAMES:
		var s: Dictionary = _shots[_index]
		root.get_texture().get_image().save_png(s["out"])
		print("saved ", s["out"])
		_index += 1
		if _index >= _shots.size():
			return true
		_frames = 0
		_place(_shots[_index])
	return false


func _place(s: Dictionary) -> void:
	root.size = Vector2i(int(s["w"]), int(s["h"]))
	var cam: Camera3D = _main.get_node("Camera")
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = float(s.get("fov", 70.0))
	cam.look_at_from_position(_point(s["eye"]), _point(s["target"]))


func _point(p: Array) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), p[0], -p[1])
	return MeshUtils.to_godot(p[0], p[1], (0.0 if is_nan(g) else g) + p[2])
