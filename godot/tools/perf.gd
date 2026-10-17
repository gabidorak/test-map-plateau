extends SceneTree
## Frame time at every viewpoint of tools/viewpoints.json (vsync off), with triangle and draw-call
## counts. godot --path godot --script res://tools/perf.gd [-- --only=name,name] [--no-rail] [--trains]
## --no-rail hides the RER B (rail_builder.gd's Rail node: "before" it); --trains stands an RER B train each way at
## Lozère, doors open (scripts/train_traffic.gd, the bots stopped).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const SETTLE := 30
const MEASURE := 120

var _main: Node
var _views: Array = []
var _index := 0
var _frames := -10
var _t0 := 0
var _no_rail := false
var _trains := false


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg == "--no-rail":
			_no_rail = true
		elif arg == "--trains":
			_trains = true
			OS.set_environment("PLATEAU_TRAINS", "1")
	for v: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tools/viewpoints.json"))["viewpoints"]:
		if only.is_empty() or v["name"] in only:
			_views.append(v)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 0 and _trains and not _main.traffic.trains.running:
		_frames = -1                        # until the trains run
		return false
	if _frames == 0 and _index == 0:
		if _no_rail and _main.world_root.get_node_or_null("Rail"):
			_main.world_root.get_node("Rail").visible = false
		if _trains:
			_stand(_main.traffic.trains)
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


## One RER B train each way at its stopping mark with its doors open, the others stowed, the bots off.
func _stand(tt: Node) -> void:
	tt.running = false
	var used := {}
	for tr: Node3D in tt.trains:
		var k: int = tt.service_index(tr)
		if used.has(k):
			tr.set_stowed(true)
			continue
		used[k] = true
		tr.set_stowed(false)
		tr.speed = 0.0
		tr.place(float(tr.service["stops"][0]["s"]["8"]))
		tr.set_doors(true, 1)
		tr.door_t = 1.0
		for car in tr.cars:
			car.pose_doors(1.0, -1 if car.turned else 1)


func _place(v: Dictionary) -> void:
	var cam: Camera3D = _main.get_node("Camera")
	cam.look_at_from_position(_point(v["eye"]), _point(v["target"]))


func _point(p: Array) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), p[0], -p[1])
	return MeshUtils.to_godot(p[0], p[1], (0.0 if is_nan(g) else g) + p[2])
