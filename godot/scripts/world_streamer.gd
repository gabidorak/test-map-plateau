extends Node
## Chunk streaming (performance): every frame, cells near the camera show their full-detail nodes and the
## others their far version (built by scripts/builder/far_builder.gd). Hidden nodes cost nothing to render,
## and they stay in the tree, so collision, the picker and the tools still find everything.
## Off when PLATEAU_STREAMING=0 (full detail everywhere, e.g. to compare shots).

const NEAR := 180.0                     # m from the camera to a cell's box under which it shows full detail
const HYSTERESIS := 40.0                # m further it must go before switching back to the far version

@export var near_paths: Array = []      # per cell: PackedStringArray of paths from the world root
@export var far_paths := PackedStringArray()
@export var boxes: Array[AABB] = []

var enabled := true
var _near_nodes: Array = []             # per cell: Array[Node3D]
var _far_nodes: Array[Node3D] = []
var _is_near := PackedByteArray()       # 1 near, 0 far, 2 not decided yet


func _ready() -> void:
	enabled = OS.get_environment("PLATEAU_STREAMING") != "0"
	var world := get_parent()
	for i in boxes.size():
		var nodes: Array[Node3D] = []
		for p: String in near_paths[i]:
			var n := world.get_node_or_null(p) as Node3D
			if n:
				nodes.append(n)
		_near_nodes.append(nodes)
		_far_nodes.append(world.get_node_or_null(far_paths[i]) as Node3D)
	_is_near.resize(boxes.size())
	_is_near.fill(2)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	for i in boxes.size():
		var box := boxes[i]
		var d := p.distance_to(p.clamp(box.position, box.end))
		var state := _is_near[i]
		var near := not enabled or d < NEAR or (state == 1 and d < NEAR + HYSTERESIS)
		if state != int(near):
			_set_cell(i, near)


## Full detail everywhere (true) or back to streaming (false).
func set_enabled(on: bool) -> void:
	enabled = on


func _set_cell(i: int, near: bool) -> void:
	_is_near[i] = int(near)
	for n: Node3D in _near_nodes[i]:
		n.visible = near
	if _far_nodes[i]:
		_far_nodes[i].visible = not near
