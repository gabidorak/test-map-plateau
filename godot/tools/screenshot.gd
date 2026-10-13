extends SceneTree
## Renders scenes/main.tscn from a given camera pose and saves a PNG.
## godot --path godot --script res://tools/screenshot.gd -- --pos=x,y,z --look=x,y,z --out=file.png
## Positions use pipeline axes (x east, y north, z up, metres from the origin).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")

var _frames := 0
var _out := "user://screenshot.png"
var _main: Node
var _pos := Vector3(-60, 90, 45)
var _look := Vector3.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--pos": _pos = _vec(kv[1])
			"--look": _look = _vec(kv[1])
			"--out": _out = kv[1]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _vec(s: String) -> Vector3:
	var p := s.split_floats(",")
	return Vector3(p[0], p[1], p[2])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:  # after main.gd has spawned the player
		_main.set_screenshot_mode()
		var cam: Camera3D = _main.get_node("Camera")
		cam.look_at_from_position(MeshUtils.to_godot(_pos.x, _pos.y, _pos.z), MeshUtils.to_godot(_look.x, _look.y, _look.z))
	elif _frames == 50:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
