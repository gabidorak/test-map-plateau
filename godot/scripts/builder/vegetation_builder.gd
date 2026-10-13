@tool
extends RefCounted
## Trees and hedges (milestone M5).
## Trees: the soft-toy models of res://assets/trees/ (blender/trees/build_trees.py) drawn with one
## MultiMesh per model, LOD and 96 m chunk; each instance is scaled to the tree's real height and crown
## radius, turned randomly, and carries its palette tint and a wind phase (INSTANCE_CUSTOM).
## The three LODs of a chunk share one custom AABB, so their visibility ranges switch together.
## Hedges: swept rounded profiles with lumps, draped on the ground, with collision.
## Trunk collision is created at runtime (tree_collision.gd) from vegetation_data.res.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const VegetationData = preload("res://scripts/vegetation_data.gd")
const TreeCollision = preload("res://scripts/tree_collision.gd")
const SHADER := "res://shaders/toy_foliage.gdshader"
const MODELS_DIR := "res://assets/trees/"
const CHUNK := 96.0
const LOD_END := [70.0, 220.0]          # LOD0 up to 70 m, LOD1 up to 220 m, LOD2 beyond
const SHADOW_LODS := 2                  # LOD0 and LOD1 cast shadows
const TRUNK_COLLIDER_MAX := 4.0         # m of trunk collider above the ground
const HEDGE_STEP := 0.5                 # m between hedge profile rings
const HEDGE_PROFILE := 12               # points of the rounded cross-section


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> Error:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MODELS_DIR + "models.json"))
	if not manifest is Dictionary:
		push_error("no tree models: run blender/trees/build_trees.py")
		return ERR_FILE_NOT_FOUND
	var models: Dictionary = manifest["models"]
	var t: Dictionary = world["terrain"]
	var ground := GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	var trunk_cols: Dictionary = world["palette"]["trunk"]
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter("bark_color", Color.html(trunk_cols["bark"]))
	mat.set_shader_parameter("wood_color", Color.html(trunk_cols["stake"]))
	mat.set_shader_parameter("tie_color", Color.html(trunk_cols["tie"]))
	MeshUtils.save(mat, mesh_dir + "foliage_material.tres")

	var meshes := {}                    # model name -> [lod0, lod1, lod2]
	for arch: String in world["tree_archetypes"]:
		var path := MODELS_DIR + arch + ".glb"
		if not ResourceLoader.exists(path):
			push_error("missing %s: run blender/trees/build_trees.py, then godot --headless --import" % path)
			return ERR_FILE_NOT_FOUND
		var scene: Node = load(path).instantiate()
		for v in int(world["tree_archetypes"][arch]):
			var name := "%s_%d" % [arch, v]
			if not models.has(name):
				scene.free()
				push_error("tree model %s missing from models.json" % name)
				return ERR_INVALID_DATA
			var lods := []
			for lod in 3:
				var mi := scene.find_child("%s_lod%d" % [name, lod], true, false) as MeshInstance3D
				if mi == null:
					scene.free()
					push_error("tree model %s has no LOD %d" % [name, lod])
					return ERR_INVALID_DATA
				lods.append(MeshUtils.save(_merge(mi.mesh, mat), mesh_dir + "tree_%s_lod%d.res" % [name, lod]))
			meshes[name] = lods
		scene.free()

	var node := Node3D.new()
	node.name = "Vegetation"
	root.add_child(node)
	var data := _place_trees(node, world, models, meshes, ground)
	MeshUtils.save(data, mesh_dir + "vegetation_data.res")
	var trunks := TreeCollision.new()
	trunks.name = "TreeCollision"
	trunks.collision_layer = Layers.VEGETATION
	trunks.collision_mask = 0
	trunks.data = data
	trunks.set_meta("plateau", {"type": "trees", "id": "trees"})
	root.add_child(trunks)
	_hedges(node, root, world, ground, mesh_dir)
	return OK


## One surface per model LOD (leaves, trunk and wood parts are told apart by COLOR.a in the shader).
func _merge(src: Mesh, mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		var base := verts.size()
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		colors.append_array(a[Mesh.ARRAY_COLOR])
		for i: int in a[Mesh.ARRAY_INDEX]:
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


func _place_trees(node: Node3D, world: Dictionary, models: Dictionary, meshes: Dictionary, ground) -> VegetationData:
	var fol: Dictionary = world["palette"]["foliage"]
	var data := VegetationData.new()
	var groups := {}                    # Vector3i(chunk x, chunk y, model index) -> [instance floats, aabb]
	var names := meshes.keys()
	for tr: Dictionary in world["trees"]:
		var name := "%s_%d" % [tr["arch"], tr["var"]]
		var m: Dictionary = models[name]
		var x: float = tr["x"]
		var y: float = tr["y"]
		var z: float = ground.at(x, y)
		var sx: float = float(tr["r"]) / float(m["radius"])
		var sy: float = float(tr["h"]) / float(m["height"])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(tr["id"])
		var yaw := rng.randf() * TAU
		var col := Color.html(fol[tr["tint"]])
		var key := Vector3i(floori(x / CHUNK), floori(y / CHUNK), names.find(name))
		var centre := Vector2((key.x + 0.5) * CHUNK, (key.y + 0.5) * CHUNK)
		if not groups.has(key):
			groups[key] = [PackedFloat32Array(), AABB()]
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sx, sy, sx))
		var p := Vector3(x - centre.x, z, -(y - centre.y))        # local to the chunk node
		var g: Array = groups[key]
		g[0].append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z,
				col.r, col.g, col.b, rng.randf()])
		var box := AABB(p - Vector3(tr["r"], 0.5, tr["r"]), Vector3(2.0 * tr["r"], float(tr["h"]) + 1.0, 2.0 * tr["r"]))
		g[1] = box if g[0].size() == 16 else (g[1] as AABB).merge(box)

		var crown_base := float(m["crown_base"]) * sy
		data.ids.append(tr["id"])
		data.info.append("%s|%s|%s|%s|%.1f|%.1f" % [name, tr["tint"], tr["src"], tr.get("osm", ""), tr["h"], tr["r"]])
		data.base.append(MeshUtils.to_godot(x, y, z))
		data.trunk.append(Vector2(float(m["trunk_radius"]) * sx, clampf(crown_base, 1.0, TRUNK_COLLIDER_MAX)))
		data.crown_center.append(MeshUtils.to_godot(x, y, z + (crown_base + float(tr["h"])) / 2.0))
		data.crown_radii.append(Vector2(tr["r"], maxf((float(tr["h"]) - crown_base) / 2.0, 0.3)))

	var trees := Node3D.new()
	trees.name = "Trees"
	node.add_child(trees)
	var chunks := {}
	for key: Vector3i in groups:
		var ck := Vector2i(key.x, key.y)
		if not chunks.has(ck):
			var cn := Node3D.new()
			cn.name = "Chunk_%d_%d" % [ck.x, ck.y]
			cn.position = Vector3((ck.x + 0.5) * CHUNK, 0.0, -(ck.y + 0.5) * CHUNK)
			trees.add_child(cn)
			chunks[ck] = cn
		var g: Array = groups[key]
		var name: String = names[key.z]
		for lod in 3:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[name][lod]
			mm.instance_count = g[0].size() / 16
			mm.buffer = g[0]
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_lod%d" % [name, lod]
			mmi.multimesh = mm
			mmi.custom_aabb = g[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < SHADOW_LODS \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_begin = 0.0 if lod == 0 else LOD_END[lod - 1]
			mmi.visibility_range_end = LOD_END[lod] if lod < 2 else 0.0
			mmi.set_meta("plateau", {"type": "trees", "model": name, "lod": lod})
			chunks[Vector2i(key.x, key.y)].add_child(mmi)
	return data


# ---------------------------------------------------------------- hedges

func _hedges(node: Node3D, root: Node3D, world: Dictionary, ground, mesh_dir: String) -> void:
	var hedges: Array = world["hedges"]
	var parent := Node3D.new()
	parent.name = "Hedges"
	node.add_child(parent)
	var body := StaticBody3D.new()
	body.name = "HedgeCollision"
	body.collision_layer = Layers.VEGETATION
	body.collision_mask = 0
	root.add_child(body)
	var fol: Dictionary = world["palette"]["foliage"]
	var mats := {}
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.6
	for h: Dictionary in hedges:
		var tint: String = h["tint"]
		if not mats.has(tint):
			var mat := ShaderMaterial.new()
			mat.shader = load(SHADER)
			mat.set_shader_parameter("use_instance_tint", false)
			mat.set_shader_parameter("tint", Color.html(fol[tint]))
			mat.set_shader_parameter("sway", 0.02)
			mat.set_shader_parameter("flutter", 0.02)
			mats[tint] = MeshUtils.save(mat, mesh_dir + "hedge_material_%s.tres" % tint)
		var mesh := _hedge_mesh(h, ground, noise)
		mesh.surface_set_material(0, mats[tint])
		var id := String(h["id"]).replace(":", "_")
		MeshUtils.save(mesh, mesh_dir + "%s.res" % id)
		var info := {"type": "hedge", "id": h["id"], "src": h["src"], "height": h["h"], "width": h["w"],
				"height_src": h["height_src"], "tint": tint}
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = mesh
		mi.set_meta("plateau", info)
		parent.add_child(mi)
		var shape := mesh.create_trimesh_shape()
		MeshUtils.save(shape, mesh_dir + "%s_col.res" % id)
		var cs := CollisionShape3D.new()
		cs.name = id
		cs.shape = shape
		cs.set_meta("plateau", info)
		body.add_child(cs)


## Points along the hedge every HEDGE_STEP metres (corners kept), with the distance along it.
func _resample(pts: Array) -> Array:
	var out := []
	var dist := 0.0
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var n := maxi(ceili(a.distance_to(b) / HEDGE_STEP), 1)
		for k in n:
			out.append([a.lerp(b, float(k) / n), dist + a.distance_to(b) * k / n])
		dist += a.distance_to(b)
	out.append([Vector2(pts[-1][0], pts[-1][1]), dist])
	return out


## Swept soft rounded box: superellipse cross-section with lumps, tapered closed ends.
## COLOR = (ambient occlusion from height, lump, height fraction, leaves).
func _hedge_mesh(h: Dictionary, ground, noise: FastNoiseLite) -> ArrayMesh:
	var w: float = h["w"]
	var ht: float = h["h"]
	var samples := _resample(h["pts"])
	var length: float = samples[-1][1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 0
	for i in samples.size():
		var p: Vector2 = samples[i][0]
		var d: float = samples[i][1]
		var prev: Vector2 = samples[maxi(i - 1, 0)][0]
		var next: Vector2 = samples[mini(i + 1, samples.size() - 1)][0]
		var tang := (next - prev).normalized()
		var side := Vector2(-tang.y, tang.x)
		var end := minf(d, length - d)
		var taper := sqrt(clampf(end / minf(0.6, length / 2.0), 0.0, 1.0)) * 0.75 + 0.25
		var z: float = ground.at(p.x, p.y)
		for k in HEDGE_PROFILE + 1:
			var a := PI * k / HEDGE_PROFILE                       # 0: right foot, PI/2: top, PI: left foot
			var cu := cos(a)
			var su := sin(a)
			var u := signf(cu) * pow(absf(cu), 0.55) * w / 2.0
			var v := pow(su, 0.55) * ht
			var lump := 1.0 + 0.09 * noise.get_noise_2d(d * 1.3, k * 0.9) + 0.05 * noise.get_noise_2d(d * 4.0, k * 2.7)
			u *= lump * taper
			v *= lump * lerpf(0.55, 1.0, taper)
			var xy := p + side * u
			var height := maxf(v, 0.0)
			st.set_color(Color(lerpf(0.45, 1.0, clampf(height / ht, 0.0, 1.0)), 0.5 + 0.5 * noise.get_noise_2d(d * 0.7, k),
					clampf(height / ht, 0.0, 1.0), 1.0))
			st.add_vertex(MeshUtils.to_godot(xy.x, xy.y, z - 0.08 + height))
		rings += 1
	var n := HEDGE_PROFILE + 1
	for r in rings - 1:
		for k in HEDGE_PROFILE:
			var a := r * n + k
			var b := a + 1
			var c := a + n
			var e := c + 1
			# Godot front faces are clockwise seen from outside
			st.add_index(a)
			st.add_index(e)
			st.add_index(b)
			st.add_index(a)
			st.add_index(c)
			st.add_index(e)
	# rounded end caps: a fan from each end ring to a point just past the hedge end
	for cap in 2:
		var s: Array = samples[0] if cap == 0 else samples[-1]
		var o: Array = samples[1] if cap == 0 else samples[-2]
		var out_dir := ((s[0] as Vector2) - (o[0] as Vector2)).normalized()
		var tip := (s[0] as Vector2) + out_dir * minf(w * 0.15, 0.2)
		st.set_color(Color(0.8, 0.5, 0.45, 1.0))
		st.add_vertex(MeshUtils.to_godot(tip.x, tip.y, ground.at(tip.x, tip.y) - 0.08 + ht * 0.45))
		var centre := rings * n + cap
		var first := 0 if cap == 0 else (rings - 1) * n
		for k in HEDGE_PROFILE:
			st.add_index(centre)
			if cap == 0:
				st.add_index(first + k)
				st.add_index(first + k + 1)
			else:
				st.add_index(first + k + 1)
				st.add_index(first + k)
	st.generate_normals()
	return st.commit()
