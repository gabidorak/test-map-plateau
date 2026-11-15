extends Node3D
## Two thin wires from one node to another for a while (the taser's, from the shooter's hand to the darts in the person
## hit: scripts/items/weapons/taser.gd), posed each frame while they last, then gone. A wire to a point stays put.

const Fx = preload("res://scripts/people/people_fx.gd")

const CHEST := Vector3(0.0, 1.1, 0.0)       # where the darts sit, in the body's frame

var _from_node: Node3D                      # the shooter's hand (or null: _from stays)
var _to_node: Node3D                        # the body hit (or null: _to stays)
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _life := 1.0
var _wires: Node3D


## From `from_node` (or point `from`) to `to_node`'s chest (or point `to`) for `life` s.
func setup(from_node: Node3D, from: Vector3, to_node: Node3D, to: Vector3, life: float) -> void:
	_from_node = from_node
	_from = from
	_to_node = to_node
	_to = to
	_life = life
	top_level = true
	_wires = Fx.wire()
	add_child(_wires)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if is_instance_valid(_from_node) and _from_node.is_inside_tree():
		_from = _from_node.global_position
	if is_instance_valid(_to_node) and _to_node.is_inside_tree():
		_to = _to_node.global_transform * CHEST     # (lying: the body's own up is along it)
	Fx.wire_pose(_wires, _from, _to)
