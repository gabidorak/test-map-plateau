extends RefCounted
## Physics queries against the generated world, in Godot coordinates.

const Layers = preload("res://scripts/physics_layers.gd")


## Height (Godot y) of the first surface below `top` at (x, z), or NAN when nothing is there.
static func ground_y(world: World3D, x: float, z: float, mask := Layers.TERRAIN, top := 1000.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -1000.0, z), mask)
	var hit := world.direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else NAN


## Metadata dictionary of what a ray hit: the body's info_for_shape() when it has one (tree trunks),
## else the CollisionShape3D's "plateau" meta, else the body's.
static func hit_info(hit: Dictionary) -> Dictionary:
	if not hit:
		return {}
	var body: CollisionObject3D = hit["collider"]
	if body.has_method("info_for_shape"):        # runtime shapes (tree trunks)
		return body.info_for_shape(hit["shape"])
	var owner_id := body.shape_find_owner(hit["shape"])
	var shape_node := body.shape_owner_get_owner(owner_id) as Node
	if shape_node and shape_node.has_meta("plateau"):
		return shape_node.get_meta("plateau")
	return body.get_meta("plateau", {})


## The shape node a ray hit (CollisionShape3D), or null.
static func hit_node(hit: Dictionary) -> Node:
	if not hit:
		return null
	var body: CollisionObject3D = hit["collider"]
	return body.shape_owner_get_owner(body.shape_find_owner(hit["shape"])) as Node
