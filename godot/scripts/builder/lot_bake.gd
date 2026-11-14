extends RefCounted
## The finished lots (builder/lots.gd "finished") built into the map when it is built (builder/world_builder.gd, after
## the map's own builds): each one's node made as in the game (its _ready(), out of the tree) but with its meshes, its
## builds kept in the scene under Lots/<id> (a lot of one build: that build itself; a restyled building under
## Lots/<id>/<slug>, its ground floor's height in its meta "floor"). Their meshes, materials, textures and large
## collision shapes are saved with the map's (mesh_dir); the nodes their metas name become paths (Lots.node_meta()
## reads them back); their groups are kept. Each build is one building from afar (far_proxy.gd GROUP): far_builder.gd
## streams it with the map's, its far shape in its cell's. In the game the lot's node takes its builds back
## (Lots.baked()) and only brings them to life (Losplatos' door, the base nautique's counter): nothing of it is built
## at start.
const Lots = preload("res://scripts/builder/lots.gd")
const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const FarProxy = preload("res://scripts/builder/far_proxy.gd")
const Spec = preload("res://scripts/restyle/restyle_spec.gd")
const RestyleBuilding = preload("res://scripts/restyle/restyle_building.gd")
const Water = preload("res://scripts/water.gd")


## The finished lots into `root` (Lots): how many builds.
static func bake(root: Node3D, mesh_dir: String) -> int:
	var holder := Node3D.new()
	holder.name = Lots.BAKED
	root.add_child(holder)
	var water: Variant = Water.current
	Water.current = root.get_node_or_null("Water")         # (a lot on the water finds its level: the base nautique)
	Lots.baking = true
	var count := 0
	for l: Dictionary in Lots.all():
		if not Lots.finished(l) or not (l.has("node") or l.has("restyle")):
			continue                                        # (the railway's lots: built with the map, their "build")
		var id := str(l["id"])
		var keep := Node3D.new()
		if l.has("node"):                                   # its node's builds, made as at start in the game
			var n: Node = load(str(l["script"])).new()
			n.call("_ready")                                # (out of the tree: the map is built before the game runs)
			for c: Node in n.get_children():
				n.remove_child(c)
				keep.add_child(c)
			n.free()
		if keep.get_child_count() == 1 and l.get("restyle", []).is_empty():   # (its one build: Lots/<id> itself)
			var only := keep.get_child(0)
			keep.remove_child(only)
			keep.free()
			only.name = id
			holder.add_child(only)
			only.add_to_group(FarProxy.GROUP, true)
			_store(only, mesh_dir, id, {"n": 0})
			count += 1
			print("lots: %s baked, its build" % id)
			continue
		keep.name = id
		holder.add_child(keep)
		for slug: String in l.get("restyle", []):           # its restyled buildings
			for s: Dictionary in Spec.specs():
				if s["slug"] == slug:
					var b := RestyleBuilding.new()
					var node := b.build(s, true)
					node.name = slug
					node.set_meta("floor", b.floor_y())
					keep.add_child(node)
		for part: Node in keep.get_children():
			part.add_to_group(FarProxy.GROUP, true)
			count += 1
		_store(keep, mesh_dir, id, {"n": 0})
		print("lots: %s baked, %d builds" % [id, keep.get_child_count()])
	Lots.baking = false
	Water.current = water
	return count


## Node `n` (in lot `id`'s builds) ready to be saved: its resources to files, its metas' nodes as paths, its groups
## kept; then its children.
static func _store(n: Node, mesh_dir: String, id: String, k: Dictionary) -> void:
	for key: StringName in n.get_meta_list():
		var v: Variant = n.get_meta(key)
		if v is Node:
			n.set_meta(key, n.get_path_to(v))
		elif v is Array and (v as Array).any(func(e: Variant) -> bool: return e is Node):
			n.set_meta(key, (v as Array).map(func(e: Variant) -> Variant: return n.get_path_to(e) if e is Node else e))
	for g: StringName in n.get_groups():
		if not str(g).begins_with("_"):
			n.remove_from_group(g)
			n.add_to_group(g, true)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			_save_material(mi.mesh.surface_get_material(i), mesh_dir, id, k)
		_save_material(mi.material_override, mesh_dir, id, k)
		if mi.mesh.resource_path == "":
			MeshUtils.save(mi.mesh, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])
	elif n is CollisionShape3D and ((n as CollisionShape3D).shape is ConcavePolygonShape3D
			or (n as CollisionShape3D).shape is ConvexPolygonShape3D):
		var sh: Shape3D = (n as CollisionShape3D).shape
		if sh.resource_path == "":
			MeshUtils.save(sh, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])
	for c: Node in n.get_children():
		_store(c, mesh_dir, id, k)


## A material (and its textures, its shader) saved once, so the meshes share it.
static func _save_material(m: Material, mesh_dir: String, id: String, k: Dictionary) -> void:
	if m == null or m.resource_path != "":
		return
	if m is BaseMaterial3D:
		for t in BaseMaterial3D.TEXTURE_MAX:
			var tex: Texture2D = (m as BaseMaterial3D).get_texture(t)
			if tex and tex.resource_path == "":
				MeshUtils.save(tex, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		if sm.shader and sm.shader.resource_path == "":
			MeshUtils.save(sm.shader, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])
		if sm.shader:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var v: Variant = sm.get_shader_parameter(u["name"])
				if v is Texture2D and (v as Texture2D).resource_path == "":
					MeshUtils.save(v, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])
	if m.next_pass:
		_save_material(m.next_pass, mesh_dir, id, k)
	MeshUtils.save(m, mesh_dir + "lot_%s_%d.res" % [id, _next(k)])


static func _next(k: Dictionary) -> int:
	k["n"] += 1
	return k["n"]
