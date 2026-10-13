extends StaticBody3D
## Trunk collision (milestone M5): one cylinder per tree, created at runtime from the VegetationData
## resource so the scene file stays small. Crowns do not collide (the player walks under them).
## The picker maps a hit shape back to its tree with info_for_shape().
## The thin trees vehicles bend (scripts/breakables.gd) go into a child body of the same script, "Bendable", also on
## the BREAKABLE layer: switching one trunk off rebuilds only that small compound shape (~3 ms for the main one).

const VegetationData = preload("res://scripts/vegetation_data.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const Breakables = preload("res://scripts/breakables.gd")
const MIN_RADIUS := 0.12

@export var data: VegetationData

var bendable := false                       # this body holds only the trees that bend

var _tree_of_owner := {}
var _owner_of_tree := {}


func _ready() -> void:
	if data == null:
		return
	if not bendable:
		var sub: StaticBody3D = (get_script() as GDScript).new()
		sub.name = "Bendable"
		sub.bendable = true
		sub.data = data
		sub.collision_layer = collision_layer | Layers.BREAKABLE
		sub.collision_mask = 0
		sub.set_meta("plateau", get_meta("plateau", {}))
		add_child(sub)
	# Jolt rebuilds the body's compound shape on every add while the body is in a space, which made
	# thousands of adds quadratic (~50 s at startup): add them all out of the space, then put it back.
	var space := PhysicsServer3D.body_get_space(get_rid())
	PhysicsServer3D.body_set_space(get_rid(), RID())
	var shapes := {}
	for k in data.size():
		if Breakables.bends(data, k) != bendable:
			continue
		var t := data.trunk[k]
		var r := maxf(t.x, MIN_RADIUS)
		var key := Vector2i(roundi(r * 50.0), roundi(t.y * 2.0))       # 2 cm radius, 0.5 m height buckets
		if not shapes.has(key):
			var cyl := CylinderShape3D.new()
			cyl.radius = key.x / 50.0
			cyl.height = maxf(key.y / 2.0, 0.5)
			shapes[key] = cyl
		var shape: CylinderShape3D = shapes[key]
		var owner_id := create_shape_owner(self)
		shape_owner_add_shape(owner_id, shape)
		shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, data.base[k] + Vector3.UP * shape.height / 2.0))
		_tree_of_owner[owner_id] = k
		_owner_of_tree[k] = owner_id
	PhysicsServer3D.body_set_space(get_rid(), space)


## Metadata of the tree owning body shape `shape_index` (from a ray hit), or {}.
func info_for_shape(shape_index: int) -> Dictionary:
	var k := tree_for_shape(shape_index)
	return data.describe(k) if k >= 0 else {}


## Index of the tree owning body shape `shape_index`, or -1.
func tree_for_shape(shape_index: int) -> int:
	return _tree_of_owner.get(shape_find_owner(shape_index), -1)


## Turns the trunk collider of tree k (one of this body's) off or back on.
func set_solid(k: int, on: bool) -> void:
	if _owner_of_tree.has(k):
		shape_owner_set_disabled(_owner_of_tree[k], not on)
