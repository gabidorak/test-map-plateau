extends SceneTree
## Renders the RER B trains for review into data/review/shots/<milestone>/train_<view>.png: one train each way standing
## at Lozère with its doors open (the bots stopped), seen from the station's viewpoints (tools/viewpoints.json) and from
## cameras on the trains (inside a car, the cab front, the bogies, along the side). --night renders at night.
## godot --path godot --script res://tools/train_shots.gd -- --milestone=rerb_E [--night]
## Needs a window (not --headless): it uses the real renderer.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const SETTLE_FRAMES := 40
const STATION_VIEWS := ["rerb_platform_north", "rerb_platform_south", "rerb_footbridge", "rerb_station_forecourt"]

var _main: Node
var _views: Array = []
var _out_dir := ""
var _index := 0
var _frames := -60
var _night := false
var _ready_trains := false


func _initialize() -> void:
	OS.set_environment("PLATEAU_TRAINS", "1")
	var milestone := "latest"
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "--milestone":
			milestone = kv[1]
		elif kv[0] == "--night":
			_night = true
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/viewpoints.json"))
	for v: Dictionary in data["viewpoints"]:
		if v["name"] in STATION_VIEWS:
			_views.append(v)
	for name in ["inside", "front", "doorway", "bogie", "side"]:
		_views.append({"name": name})
	_out_dir = ProjectSettings.globalize_path("res://").path_join("../data/review/shots").path_join(milestone).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _ready_trains:
		var tt: Node = _main.traffic.trains
		if tt.running and _frames > 0:
			_stand(tt)
			_ready_trains = true
			_frames = -1
		return false
	if _frames == 0:
		_main.set_screenshot_mode()
		if _night:
			_main.night.set_night(true)
		_place(_views[_index])
	elif _frames == SETTLE_FRAMES:
		var v: Dictionary = _views[_index]
		var path := _out_dir.path_join("train_%s%s.png" % [v["name"], "_night" if _night else ""])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_index += 1
		if _index >= _views.size():
			return true
		_frames = 0
		_place(_views[_index])
	return false


## One train each way at its stopping mark, doors open; the others stowed; the bots off.
func _stand(tt: Node) -> void:
	tt.running = false
	var used := {}
	for tr: Node3D in tt.trains:
		var k: int = tt.service_index(tr)
		if used.has(k):
			tr.set_stowed(true)
			continue
		used[k] = tr
		tr.set_stowed(false)
		var stop: float = tr.service["stops"][0]["s"]["8"]
		tr.speed = 0.0
		tr.place(stop)
		tr.set_doors(true, 1)
		tr.door_t = 1.0
		for car in tr.cars:
			car.pose_doors(1.0, -1 if car.turned else 1)
	_trains = used


var _trains := {}


func _place(v: Dictionary) -> void:
	var cam: Camera3D = _main.get_node("Camera")
	if v.has("eye"):
		cam.look_at_from_position(_point(v["eye"]), _point(v["target"]))
		return
	var east: Node3D = _trains.get(0)
	if east == null:
		return
	for tr: Node3D in _trains.values():
		tr.visible = v["name"] != "bogie" or tr == east
	match v["name"]:
		"inside":                           # in the second car, by a door, looking along it
			var car: Node3D = east.cars[1]
			cam.look_at_from_position(car.to_global(Vector3(0.3, 2.85, 7.0)), car.to_global(Vector3(0.0, 2.3, -8.0)))
		"front":                            # on the platform ahead of the leading cab
			var car: Node3D = east.cars[0]
			cam.look_at_from_position(car.to_global(Vector3(4.5, 2.9, 22.0)), car.to_global(Vector3(0.0, 2.0, 5.0)))
		"doorway":                          # from the platform into an open doorway
			var car: Node3D = east.cars[2]
			cam.look_at_from_position(car.to_global(Vector3(4.2, 2.9, 4.5)), car.to_global(Vector3(0.0, 2.2, 2.0)))
		"bogie":                            # from the other platform (the other train hidden), at the bogies of two cars
			var car: Node3D = east.cars[1]
			cam.look_at_from_position(car.to_global(Vector3(-6.5, 1.9, -4.0)), car.to_global(Vector3(0.0, 0.6, -12.0)))
		"side":                             # from the other platform, across the tracks, along the train
			var car: Node3D = east.cars[2]
			cam.look_at_from_position(car.to_global(Vector3(-8.0, 2.95, -6.0)), car.to_global(Vector3(0.0, 2.2, 14.0)))


func _point(p: Array) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), p[0], -p[1])
	return MeshUtils.to_godot(p[0], p[1], (0.0 if is_nan(g) else g) + p[2])
