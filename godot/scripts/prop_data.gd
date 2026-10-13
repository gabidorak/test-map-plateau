@tool
extends Resource
## Street furniture records of the generated world (milestone M6), written by builder/prop_placer.gd and
## saved next to the generated meshes: one record per prop or fence line (picker metadata) and the
## collision shapes, created at runtime by prop_collision.gd. Shapes stand upright: a position (Godot
## coordinates, shape centre) and a turn about the vertical axis.

@export var ids := PackedStringArray()
@export var info := PackedStringArray()             # JSON picker metadata per record
@export var shape_record := PackedInt32Array()      # record index of each shape
@export var shape_kind := PackedByteArray()         # 0 box, 1 cylinder
@export var shape_size := PackedVector3Array()      # box size, or (radius, height, 0)
@export var shape_pos := PackedVector3Array()
@export var shape_yaw := PackedFloat32Array()


func size() -> int:
	return ids.size()


func add_record(id: String, meta: Dictionary) -> int:
	ids.append(id)
	info.append(JSON.stringify(meta))
	return ids.size() - 1


func add_box(record: int, centre: Vector3, box: Vector3, yaw: float) -> void:
	_add(record, 0, box, centre, yaw)


func add_cylinder(record: int, centre: Vector3, radius: float, height: float) -> void:
	_add(record, 1, Vector3(radius, height, 0.0), centre, 0.0)


func _add(record: int, kind: int, s: Vector3, centre: Vector3, yaw: float) -> void:
	shape_record.append(record)
	shape_kind.append(kind)
	shape_size.append(s)
	shape_pos.append(centre)
	shape_yaw.append(yaw)


## Picker metadata of record k.
func describe(k: int) -> Dictionary:
	var d: Dictionary = JSON.parse_string(info[k])
	d["index"] = k
	return d
