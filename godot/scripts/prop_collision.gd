extends StaticBody3D
## Street furniture collision (milestone M6): boxes and cylinders created at runtime from the PropData
## resource, so the scene file stays small. The picker maps a hit shape back to its prop or fence with
## info_for_shape(); shape_aabb() gives its extent for the highlight.
## The props vehicles knock over (scripts/breakables.gd) go into a child body of the same script, "Breakable", also
## on the BREAKABLE layer: switching one off rebuilds only that small compound shape.

const PropData = preload("res://scripts/prop_data.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const Breakables = preload("res://scripts/breakables.gd")

@export var data: PropData

var breakable := false                      # this body holds only the props that break

var _breaks := PackedByteArray()            # per record: 1 when it breaks
var _record_of_owner := {}
var _owners_of_record := {}                 # record -> Array of shape owner ids


func _ready() -> void:
	if data == null:
		return
	if not breakable:
		_breaks.resize(data.size())
		for k in data.size():
			_breaks[k] = int(Breakables.breaks(data.describe(k).get("model", "")))
		var sub: StaticBody3D = (get_script() as GDScript).new()
		sub.name = "Breakable"
		sub.breakable = true
		sub.data = data
		sub._breaks = _breaks
		sub.collision_layer = collision_layer | Layers.BREAKABLE
		sub.collision_mask = 0
		sub.set_meta("plateau", get_meta("plateau", {}))
		add_child(sub)
	# Jolt rebuilds the body's compound shape on every add while the body is in a space, which made
	# thousands of adds quadratic (~50 s at startup): add them all out of the space, then put it back.
	var space := PhysicsServer3D.body_get_space(get_rid())
	PhysicsServer3D.body_set_space(get_rid(), RID())
	var cache := {}
	for k in data.shape_record.size():
		var record := data.shape_record[k]
		if bool(_breaks[record]) != breakable:
			continue
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
		_record_of_owner[owner_id] = record
		if not _owners_of_record.has(record):
			_owners_of_record[record] = []
		_owners_of_record[record].append(owner_id)
	PhysicsServer3D.body_set_space(get_rid(), space)


## Metadata of the prop or fence owning body shape `shape_index` (from a ray hit), or {}.
func info_for_shape(shape_index: int) -> Dictionary:
	var k := record_for_shape(shape_index)
	return data.describe(k) if k >= 0 else {}


## Index of the record owning body shape `shape_index`, or -1.
func record_for_shape(shape_index: int) -> int:
	return _record_of_owner.get(shape_find_owner(shape_index), -1)


## Turns the colliders of record k (one of this body's) off or back on.
func set_solid(k: int, on: bool) -> void:
	for owner_id: int in _owners_of_record.get(k, []):
		shape_owner_set_disabled(owner_id, not on)


## [shape, global transform] of each collider of record k (one of this body's).
func record_shapes(k: int) -> Array:
	var out := []
	for owner_id: int in _owners_of_record.get(k, []):
		out.append([shape_owner_get_shape(owner_id, 0), global_transform * shape_owner_get_transform(owner_id)])
	return out


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
