@tool
extends RefCounted
## Helpers shared by the builders. Pipeline coordinates are x east, y north, z up;
## Godot is y up with -z north, so a pipeline point (x, y, z) becomes Vector3(x, z, -y).


static func to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("could not save %s: %s" % [path, error_string(err)])
	res.take_over_path(path)  # so scenes reference the file instead of embedding a copy
	return res


## A box collision shape of `size` at `xf` in `body`, the picker's `info` on it.
static func shape_box(body: Node, xf: Transform3D, size: Vector3, info: Dictionary) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.transform = xf
	cs.set_meta("plateau", info)
	body.add_child(cs)
