extends SceneTree
## Frame time at every viewpoint of tools/viewpoints.json (vsync off), with triangle and draw-call
## counts. godot --path godot --script res://tools/perf.gd [-- --only=name,name]

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const SETTLE := 30
const MEASURE := 120

var _main: Node
var _views: Array = []
var _index := 0
var _frames := -10
var _t0 := 0


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	for v: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tools/viewpoints.json"))["viewpoints"]:
		if only.is_empty() or v["name"] in only:
			_views.append(v)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 0:
		_main.set_screenshot_mode()
		_place(_views[_index])
	elif _frames == SETTLE:
		_t0 = Time.get_ticks_usec()
	elif _frames == SETTLE + MEASURE:
		var ms := (Time.get_ticks_usec() - _t0) / 1000.0 / MEASURE
		var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("%-26s %6.2f ms  %5.0f fps  %5.2f M triangles  %4d draw calls" % [_views[_index]["name"], ms, 1000.0 / ms,
				tris / 1e6, calls])
		_index += 1
		if _index >= _views.size():
			return true
		_frames = 0
		_place(_views[_index])
	return false


func _place(v: Dictionary) -> void:
	var cam: Camera3D = _main.get_node("Camera")
	cam.look_at_from_position(_point(v["eye"]), _point(v["target"]))


func _point(p: Array) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), p[0], -p[1])
	return MeshUtils.to_godot(p[0], p[1], (0.0 if is_nan(g) else g) + p[2])
