extends StaticBody3D
## Street furniture collision (milestone M6): boxes and cylinders created at runtime from the PropData
## resource, so the scene file stays small. The picker maps a hit shape back to its prop or fence with
## info_for_shape(); shape_aabb() gives its extent for the highlight.

const PropData = preload("res://scripts/prop_data.gd")

@export var data: PropData

var _record_of_owner := {}


func _ready() -> void:
	if data == null:
		return
	# Jolt rebuilds the body's compound shape on every add while the body is in a space, which made
	# thousands of adds quadratic (~50 s at startup): add them all out of the space, then put it back.
	var space := PhysicsServer3D.body_get_space(get_rid())
	PhysicsServer3D.body_set_space(get_rid(), RID())
	var cache := {}
	for k in data.shape_record.size():
		var s := data.shape_size[k]
		var key := [data.shape_kind[k], snappedf(s.x, 0.01), snappedf(s.y, 0.01), snappedf(s.z, 0.01)]
		if not cache.has(key):
			if data.shape_kind[k] == 0:
				var box := BoxShape3D.new()
				box.size = Vector3(maxf(key[1], 0.02), maxf(key[2], 0.02), maxf(key[3], 0.02))
				cache[key] = box
			else:
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(key[1], 0.02)
				cyl.height = maxf(key[2], 0.05)
				cache[key] = cyl
		var owner_id := create_shape_owner(self)
		shape_owner_add_shape(owner_id, cache[key])
		shape_owner_set_transform(owner_id, Transform3D(Basis(Vector3.UP, data.shape_yaw[k]), data.shape_pos[k]))
		_record_of_owner[owner_id] = data.shape_record[k]
	PhysicsServer3D.body_set_space(get_rid(), space)


## Metadata of the prop or fence owning body shape `shape_index` (from a ray hit), or {}.
func info_for_shape(shape_index: int) -> Dictionary:
	var k: int = _record_of_owner.get(shape_find_owner(shape_index), -1)
	return data.describe(k) if k >= 0 else {}


## World-space box around every shape of record k (for the picker highlight).
func record_aabb(k: int) -> AABB:
	var out := AABB()
	var first := true
	for i in data.shape_record.size():
		if data.shape_record[i] != k:
			continue
		var s := data.shape_size[i]
		var ext := s if data.shape_kind[i] == 0 else Vector3(s.x * 2.0, s.y, s.x * 2.0)
		var r := maxf(ext.x, ext.z)
		var box := AABB(data.shape_pos[i] - Vector3(r, ext.y, r) / 2.0, Vector3(r, ext.y, r))
		out = box if first else out.merge(box)
		first = false
	return out
