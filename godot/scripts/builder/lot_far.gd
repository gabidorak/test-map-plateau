extends RefCounted
## The lots' streaming (performance): what the lots build in the game (builder/lots.gd) is streamed like the map's
## buildings (scripts/world_streamer.gd). Each of a lot's buildings (its node's children) is one cell: its meshes in full
## detail near the camera, far away its far shape (builder/far_proxy.gd, surveyed: its form, none of its details).
## Nodes whose visibility their lot runs itself (a door's slats rolling up) are in the group OWN_VISIBILITY: never
## streamed. Nothing to do per building: whatever a lot builds is streamed.

const FarProxy = preload("res://scripts/builder/far_proxy.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const OWN_VISIBILITY := "lot_own_visibility"


## The lot's node `lot`'s buildings into `streamer` (the world's Streamer node).
static func stream(lot: Node, streamer: Node) -> void:
	var gm: RefCounted = GroundMap.get_map()
	if streamer == null or gm == null:
		return
	var ground := func(x: float, y: float) -> float: return gm.height(x, y)
	for part: Node in lot.get_children():
		if not part is Node3D or part.is_in_group(OWN_VISIBILITY):
			continue
		var parts := FarProxy.parts_of(part, OWN_VISIBILITY)
		if parts.is_empty():
			continue
		var near: Array[Node3D] = []
		var box := AABB()
		_meshes(part, near)
		for mi: Node3D in near:
			var b := mi.global_transform * (mi as MeshInstance3D).mesh.get_aabb()
			box = b if box.size == Vector3.ZERO else box.merge(b)
		var shapes := FarProxy.Shapes.new()
		FarProxy.add(shapes, parts, ground)
		var far: MeshInstance3D = null
		var mesh := FarProxy.mesh(shapes)
		if mesh:
			far = MeshInstance3D.new()
			far.name = "Far_" + part.name
			far.mesh = mesh
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.visible = false                  # (the streamer decides)
			lot.add_child(far)
			far.global_transform = Transform3D.IDENTITY
		streamer.add_cell(near, far, box)


## Its visible meshes, not in the group OWN_VISIBILITY.
static func _meshes(n: Node, out: Array[Node3D]) -> void:
	if n.is_in_group(OWN_VISIBILITY) or (n is Node3D and not (n as Node3D).visible):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
