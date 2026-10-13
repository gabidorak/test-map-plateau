@tool
extends RefCounted
## Helpers shared by the builders. Pipeline coordinates are x east, y north, z up;
## Godot is y up with -z north, so a pipeline point (x, y, z) becomes Vector3(x, z, -y).


static func to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


## Adds a triangle facing `normal`, fixing the winding so it is front-facing
## (Godot treats clockwise triangles as front faces).
static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).dot(normal) < 0.0:
		var tmp := b
		b = c
		c = tmp
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("could not save %s: %s" % [path, error_string(err)])
	res.take_over_path(path)  # so scenes reference the file instead of embedding a copy
	return res
