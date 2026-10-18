@tool
extends RefCounted
## Ground (milestone M4): the draped ground mesh from the pipeline (world/ground.bin, see
## pipeline/plateau/ground_mesh.py) as one MeshInstance3D per 64 m chunk with the toy ground shader,
## collision for raised sidewalks, and the runtime grass scatter. The orthophoto is never used. Under the lakes and
## ponds the ground is dug out and their water surface laid over it (root's "Water", scripts/water.gd).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const SHADER := "res://shaders/toy_ground.gdshader"
## Must match the material ids hard-coded in toy_ground.gdshader. "ballast" (the railway's trackbed) is appended by
## tools/rail/patch_world.py, after the pipeline's kerb and paint.
const MATERIALS := ["asphalt", "concrete", "paving", "sett", "gravel", "dirt", "sand", "grass", "tall_grass",
		"forest_floor", "construction", "water", "clay", "tartan", "artificial_turf", "court", "wood", "building",
		"kerb", "paint", "ballast"]


func build(root: Node3D, world: Dictionary, world_dir: String, mesh_dir: String) -> Error:
	var gm: Dictionary = world["ground_mesh"]
	if gm["materials"] != MATERIALS:
		push_error("ground materials changed in the pipeline: update toy_ground.gdshader and ground_builder.gd")
		return ERR_INVALID_DATA
	var bytes := FileAccess.get_file_as_bytes(world_dir.path_join(gm["file"]))
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	MeshUtils.save(mat, mesh_dir + "ground_material.tres")

	var node := Node3D.new()
	node.name = "Ground"
	root.add_child(node)
	var body := StaticBody3D.new()
	body.name = "RaisedCollision"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "ground", "id": "ground:raised"})
	root.add_child(body)
	var custom_flags := Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var water: Variant = root.get_node_or_null("Water")
	var water_id := MATERIALS.find("water")
	for c: Dictionary in gm["chunks"]:
		var raw := bytes.slice(c["offset"], c["offset"] + c["size"]).decompress(c["raw"], FileAccess.COMPRESSION_DEFLATE)
		if raw.size() != int(c["raw"]):
			push_error("ground chunk %s is corrupt" % c["name"])
			return ERR_FILE_CORRUPT
		var nv: int = c["nv"]
		var ni: int = c["ni"]
		var nc: int = c["nc"]
		var o := 0
		var parts := []
		for size in [nv * 12, nv * 12, nv * 16, nv * 4, ni * 4, nc * 12]:
			parts.append(raw.slice(o, o + size))
			o += size
		if nv > 0:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var verts: PackedVector3Array = parts[0].to_vector3_array()
			var normals: PackedVector3Array = parts[1].to_vector3_array()
			var index: PackedInt32Array = parts[4].to_int32_array()
			var a: Array = c["aabb"]
			if water and water.touches(AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]))):
				water.carve_vertices(verts, normals)
				var is_water := PackedByteArray()
				is_water.resize(nv)
				var custom: PackedByteArray = parts[3]
				for k in nv:
					is_water[k] = 1 if custom[k * 4] == water_id else 0
				water.add_surface(c["name"], verts, index, is_water, mesh_dir)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = parts[2].to_color_array()
			arrays[Mesh.ARRAY_CUSTOM0] = parts[3]
			arrays[Mesh.ARRAY_INDEX] = index
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_flags)
			mesh.surface_set_material(0, mat)
			MeshUtils.save(mesh, mesh_dir + "ground_%s.res" % c["name"])
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_" + c["name"]
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("plateau", {"type": "ground", "id": "ground:chunk_" + c["name"]})
			node.add_child(mi)
		if nc > 0:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(parts[5].to_vector3_array())
			MeshUtils.save(shape, mesh_dir + "ground_col_%s.res" % c["name"])
			var cs := CollisionShape3D.new()
			cs.name = "Raised_" + c["name"]
			cs.shape = shape
			cs.set_meta("plateau", {"type": "ground", "id": "ground:raised_" + c["name"]})
			body.add_child(cs)

	var grass := GrassField.new()
	grass.name = "Grass"
	grass.index_path = world_dir.path_join(gm["index"])
	root.add_child(grass)
	return OK
