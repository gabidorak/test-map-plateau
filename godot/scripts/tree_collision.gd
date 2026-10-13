extends StaticBody3D
## Trunk collision (milestone M5): one cylinder per tree, created at runtime from the VegetationData
## resource so the scene file stays small. Crowns do not collide (the player walks under them).
## The picker maps a hit shape back to its tree with info_for_shape().

const VegetationData = preload("res://scripts/vegetation_data.gd")
const MIN_RADIUS := 0.12

@export var data: VegetationData

var _tree_of_owner := {}


func _ready() -> void:
	if data == null:
		return
	# Jolt rebuilds the body's compound shape on every add while the body is in a space, which made
	# thousands of adds quadratic (~50 s at startup): add them all out of the space, then put it back.
	var space := PhysicsServer3D.body_get_space(get_rid())
	PhysicsServer3D.body_set_space(get_rid(), RID())
	var shapes := {}
	for k in data.size():
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
	PhysicsServer3D.body_set_space(get_rid(), space)


## Metadata of the tree owning body shape `shape_index` (from a ray hit), or {}.
func info_for_shape(shape_index: int) -> Dictionary:
	var k: int = _tree_of_owner.get(shape_find_owner(shape_index), -1)
	return data.describe(k) if k >= 0 else {}
