extends SceneTree
## World checks (milestone M4). Exit code 0 when everything passes.
##  1. No satellite image in the game: no image file under res://world/ or res://scenes/, none among
##     the dependencies of the generated scene, no "ortho" entry in world.json, and no texture in any
##     node or resource of the generated scene (the toy shaders are procedural).
##  2. No holes in the ground mesh: the ground surface triangles of all chunks cover the whole box,
##     and every edge is shared by exactly two triangles except along the box boundary (no gaps,
##     cracks or T-junctions). Positions are compared exactly, as the pipeline writes shared
##     vertices bit-identical.
##  3. The runtime ground index loads and raised-surface collision exists.
##  4. Vegetation (M5): every tree of world.json is drawn once per LOD, has trunk data, and every
##     hedge has a mesh and a collision shape.
##  5. Street furniture (M6): every prop and sign face of world.json is drawn once, fences have their
##     panels and posts, every prop whose model has colliders has collision shapes, bus stops have their
##     name and line badges.
##  6. Toy buildings (M7): every mass has its mesh with the facade data (UV2 + four custom channels) and the
##     one shared building material, a collision shape, and every kit module and name sign is drawn once.
## godot --headless --path godot --script res://tools/check_world.gd

const GroundMap = preload("res://scripts/ground_map.gd")
const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
const PropPlacer = preload("res://scripts/builder/prop_placer.gd")
const SCENE := "res://scenes/generated/neighborhood.tscn"
const WORLD := "res://world/world.json"
const IMAGE_EXT := ["jpg", "jpeg", "png", "webp", "tif", "tiff", "bmp", "tga", "exr", "hdr", "svg", "ktx",
		"dds", "ctex", "astc", "jp2"]

var _failures: PackedStringArray = []
var _seen := {}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var world = JSON.parse_string(FileAccess.get_file_as_string(WORLD))
	_check_files()
	_check_json(world, "world.json")
	var root: Node = load(SCENE).instantiate()
	_check_textures(root)
	_check_ground(root, world)
	_check_runtime(root)
	_check_vegetation(root, world)
	_check_props(root, world)
	_check_buildings(root, world)
	root.free()
	print("checked in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if _failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d FAILURES" % _failures.size())
		for f in _failures.slice(0, 40):
			print("  ", f)
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- 1. no satellite image ----------------------------------------------------------------------

func _check_files() -> void:
	for dir in ["res://world/", "res://scenes/", "res://assets/"]:
		for path in _files(dir):
			# the debug cars (third-party CC0 models, never in the generated scene) keep their colour atlases
			if path.begins_with("res://assets/cars/"):
				continue
			if path.get_extension().to_lower() in IMAGE_EXT:
				_fail("image file in the game data: " + path)
	for dep in _deps(SCENE, {}):
		if dep.get_extension().to_lower() in IMAGE_EXT:
			_fail("the generated scene depends on an image: " + dep)
	print("files: no image under res://world/, res://scenes/ and res://assets/ (debug cars aside), %d scene dependencies checked" % _deps(SCENE, {}).size())


func _files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d)))
	return out


func _deps(path: String, seen: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in ResourceLoader.get_dependencies(path):
		var p := d.get_slice("::", 2) if d.contains("::") else d
		if p.begins_with("uid://"):
			p = ResourceUID.get_id_path(ResourceUID.text_to_id(p))
		if p.is_empty() or seen.has(p):
			continue
		seen[p] = true
		out.append(p)
		out.append_array(_deps(p, seen))
	return out


func _check_json(v: Variant, where: String) -> void:
	if v is Dictionary:
		for k in v:
			if String(k).to_lower().contains("ortho"):
				_fail("%s has an orthophoto entry: %s" % [where, k])
			if k not in ["ground", "buildings", "markings", "kerbs"]:   # big arrays of plain numbers
				_check_json(v[k], where + "." + String(k))
	elif v is Array and v.size() < 2000:
		for x in v:
			_check_json(x, where)
	elif v is String and (v.to_lower().get_extension() in IMAGE_EXT):
		_fail("%s references an image file: %s" % [where, v])


func _check_textures(root: Node) -> void:
	var nodes := [root]
	var count := 0
	while not nodes.is_empty():
		var n: Node = nodes.pop_back()
		nodes.append_array(n.get_children())
		_scan(n, n.name)
		count += 1
	print("textures: %d nodes and %d resources scanned" % [count, _seen.size()])


func _scan(o: Object, where: String) -> void:
	if o == null:
		return
	if o is Texture or o is Image:
		_fail("texture in the generated scene: %s (%s %s)" % [where, o.get_class(), (o as Resource).resource_path])
		return
	if o is Resource:
		if _seen.has(o):
			return
		_seen[o] = true
	if o is ShaderMaterial and o.shader:
		for u in o.shader.get_shader_uniform_list():
			_scan_value(o.get_shader_parameter(u["name"]), where + ":" + u["name"])
	for prop in o.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_STORAGE and prop["type"] in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY]:
			_scan_value(o.get(prop["name"]), where + "." + prop["name"])


func _scan_value(v: Variant, where: String) -> void:
	if v is Object:
		_scan(v, where)
	elif v is Array:
		for x in v:
			if x is Object or x is Array or x is Dictionary:
				_scan_value(x, where)
	elif v is Dictionary:
		for k in v:
			_scan_value(v[k], where + "/" + str(k))


# --- 2. no holes in the ground mesh -------------------------------------------------------------

func _check_ground(root: Node, world: Dictionary) -> void:
	var ground := root.get_node_or_null("Ground")
	if ground == null:
		_fail("no Ground node in the generated scene")
		return
	var kerb_id := GroundBuilder.MATERIALS.find("kerb")
	var area := 0.0
	var tris := 0
	var open := {}              # edges seen once so far, across chunks
	for mi: MeshInstance3D in ground.get_children():
		var arrays := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
		var local := {}
		for t in range(0, idx.size(), 3):
			if custom[idx[t] * 4] >= kerb_id:
				continue
			var a := Vector2(v[idx[t]].x, v[idx[t]].z)
			var b := Vector2(v[idx[t + 1]].x, v[idx[t + 1]].z)
			var c := Vector2(v[idx[t + 2]].x, v[idx[t + 2]].z)
			area += absf((b - a).cross(c - a)) / 2.0
			tris += 1
			for e in [[a, b], [b, c], [c, a]]:
				var key := _edge(e[0], e[1])
				if local.has(key):
					local[key] += 1
				else:
					local[key] = 1
		for key in local:
			if local[key] > 2:
				_fail("ground edge used %d times in %s: %s" % [local[key], mi.name, key])
			elif local[key] == 1:
				if open.has(key):
					open.erase(key)
				else:
					open[key] = mi.name
	var b: Array = world["meta"]["bounds"]
	var box_area: float = (float(b[2]) - float(b[0])) * (float(b[3]) - float(b[1]))
	var holes := 0
	for key: Vector4 in open:
		# box edges, Godot axes: x = const at bounds x, or z = const at -bounds y
		var on_box := (key.x == key.z and (is_equal_approx(key.x, b[0]) or is_equal_approx(key.x, b[2]))) or \
				(key.y == key.w and (is_equal_approx(key.y, -b[1]) or is_equal_approx(key.y, -b[3])))
		if not on_box:
			holes += 1
			if holes <= 10:
				_fail("ground edge without a neighbour (hole or crack) at x %.3f y %.3f -> x %.3f y %.3f in %s" % [
						key.x, -key.y, key.z, -key.w, open[key]])
	if absf(area - box_area) > box_area * 1e-5:
		_fail("ground mesh covers %.1f m² of the %.1f m² box" % [area, box_area])
	print("ground: %d chunks, %d surface triangles, %.1f m² of %.1f m², %d open edges inside the box" % [
			ground.get_child_count(), tris, area, box_area, holes])


## Undirected edge key (Godot x, z of both ends), exact floats.
func _edge(a: Vector2, b: Vector2) -> Vector4:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4(a.x, a.y, b.x, b.y)
	return Vector4(b.x, b.y, a.x, a.y)


# --- 3. runtime data ----------------------------------------------------------------------------

func _check_runtime(root: Node) -> void:
	var map := GroundMap.get_map()
	if map == null:
		_fail("cannot load the runtime ground index")
		return
	var raised := root.get_node_or_null("RaisedCollision")
	if raised == null or raised.get_child_count() == 0:
		_fail("no raised-surface collision")
	if root.get_node_or_null("Grass") == null:
		_fail("no Grass node")
	print("runtime: %d ground pieces in the index, %d raised collision shapes" % [map.pieces.size(),
			raised.get_child_count() if raised else 0])


# --- 4. vegetation ------------------------------------------------------------------------------

func _check_vegetation(root: Node, world: Dictionary) -> void:
	var n_trees: int = world["trees"].size()
	var trees := root.get_node_or_null("Vegetation/Trees")
	if trees == null:
		_fail("no Vegetation/Trees node")
		return
	var per_lod := [0, 0, 0]
	var per_model := {}
	for chunk in trees.get_children():
		for mmi: MultiMeshInstance3D in chunk.get_children():
			var lod := int(String(mmi.name).right(1))
			per_lod[lod] += mmi.multimesh.instance_count
			if lod == 0:
				var model := String(mmi.name).trim_suffix("_lod0")
				per_model[model] = per_model.get(model, 0) + mmi.multimesh.instance_count
	for lod in 3:
		if per_lod[lod] != n_trees:
			_fail("LOD %d draws %d trees, world.json has %d" % [lod, per_lod[lod], n_trees])
	var want := {}
	for t: Dictionary in world["trees"]:
		var model := "%s_%d" % [t["arch"], t["var"]]
		want[model] = want.get(model, 0) + 1
	if want != per_model:
		_fail("trees per model differ from world.json: %s vs %s" % [per_model, want])
	var col := root.get_node_or_null("TreeCollision")
	if col == null or col.data == null or col.data.size() != n_trees:
		_fail("trunk collision data missing or incomplete")
	var hedges := root.get_node_or_null("Vegetation/Hedges")
	var hcol := root.get_node_or_null("HedgeCollision")
	var n_hedges: int = world["hedges"].size()
	if hedges == null or hedges.get_child_count() != n_hedges or hcol == null or hcol.get_child_count() != n_hedges:
		_fail("hedges: %d in world.json, meshes or collision shapes missing" % n_hedges)
	print("vegetation: %d trees x 3 LODs in %d chunks, %d models, %d hedges" % [n_trees, trees.get_child_count(),
			per_model.size(), hedges.get_child_count() if hedges else 0])


# --- 5. street furniture ------------------------------------------------------------------------

func _check_props(root: Node, world: Dictionary) -> void:
	var props := root.get_node_or_null("Props")
	if props == null:
		_fail("no Props node")
		return
	var drawn := {}
	for chunk in props.get_children():
		if chunk.name == "BusStops":
			continue
		for mmi: MultiMeshInstance3D in chunk.get_children():
			drawn[String(mmi.name)] = drawn.get(String(mmi.name), 0) + mmi.multimesh.instance_count
	var want := {}
	var stops := 0
	for p: Dictionary in world["props"]:
		want[p["model"]] = want.get(p["model"], 0) + 1
		for face: String in p.get("info", {}).get("faces", []):
			want[face] = want.get(face, 0) + 1
		if p["model"] in ["bus_pole", "bus_shelter"]:
			stops += 1
	for f: Dictionary in world["fences"]:
		var spec: Array = PropPlacer.FENCES[f["style"]]
		var pts: Array = f["pts"]
		for i in pts.size() - 1:
			var length := Vector2(pts[i][0], pts[i][1]).distance_to(Vector2(pts[i + 1][0], pts[i + 1][1]))
			if length < 0.05:
				continue
			var n := maxi(1, roundi(length / float(spec[2])))
			want[spec[1]] = want.get(spec[1], 0) + n
			if spec[0] != "":
				want[spec[0]] = want.get(spec[0], 0) + n + (1 if i == 0 else 0)
	for model: String in want:
		if drawn.get(model, 0) != want[model]:
			_fail("prop model %s drawn %d times, world.json needs %d" % [model, drawn.get(model, 0), want[model]])
	for model: String in drawn:
		if not want.has(model):
			_fail("prop model %s drawn but not in world.json" % model)
	var body := root.get_node_or_null("PropCollision")
	var n_records: int = world["props"].size() + world["fences"].size()
	if body == null or body.data == null or body.data.size() != n_records:
		_fail("prop collision data missing or incomplete")
	else:
		var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/props/props.json"))
		var shaped := {}
		for r in body.data.shape_record:
			shaped[r] = true
		var missing := 0
		for k in world["props"].size():
			var model: String = world["props"][k]["model"]
			if not manifest["models"][model]["colliders"].is_empty() and not shaped.has(k):
				missing += 1
		if missing:
			_fail("%d props have no collision shape" % missing)
	var labels := props.get_node_or_null("BusStops")
	if labels == null or labels.get_child_count() != stops:
		_fail("bus stops: %d poles and shelters, %d label groups" % [stops, labels.get_child_count() if labels else 0])
	else:
		var by_id := {}
		for p: Dictionary in world["props"]:
			by_id[String(p["id"]).replace(":", "_")] = p
		for g in labels.get_children():
			var p: Dictionary = by_id[String(g.name)]
			var sides := 2 if p["model"] == "bus_pole" else 1
			var need: int = sides * (1 + p["info"]["lines"].size())
			var have := g.find_children("*", "Label3D", true, false).size()
			if have != need:
				_fail("bus stop labels of %s %s: %d labels, %d expected (name + line badges)" % [p["id"], p["info"]["stop"], have, need])
	var faces := 0
	for p: Dictionary in world["props"]:
		faces += p.get("info", {}).get("faces", []).size()
	print("props: %d props (%d sign faces), %d fence lines, %d models drawn, %d collision shapes, %d bus stop label groups" % [
			world["props"].size(), faces, world["fences"].size(), drawn.size(),
			body.data.shape_record.size() if body and body.data else 0, labels.get_child_count() if labels else 0])


# --- 6. toy buildings -----------------------------------------------------------------------------

func _check_buildings(root: Node, world: Dictionary) -> void:
	var meshes := root.get_node("Buildings")
	var cols := root.get_node("BuildingCollision")
	var shared: Material = null
	var tris := 0
	var need := Mesh.ARRAY_FORMAT_TEX_UV2
	for k in 4:
		need |= Mesh.ARRAY_FORMAT_CUSTOM0 << k
	for b: Dictionary in world["buildings"]:
		var name := String(b["id"]).replace(":", "_")
		var mi := meshes.get_node_or_null(name) as MeshInstance3D
		if mi == null or mi.mesh == null:
			_fail("building %s has no mesh" % b["id"])
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh.get_surface_count() != 1 or (mesh.surface_get_format(0) & need) != need:
			_fail("building %s mesh lacks the facade data" % b["id"])
		var mat := mesh.surface_get_material(0)
		if shared == null:
			shared = mat
		elif mat != shared:
			_fail("building %s does not use the shared building material" % b["id"])
		tris += mesh.surface_get_array_len(0) / 3
		if cols.get_node_or_null(name) == null:
			_fail("building %s has no collision shape" % b["id"])
	if shared == null or not (shared is ShaderMaterial) or not String(shared.shader.resource_path).ends_with("toy_building.gdshader"):
		_fail("buildings do not use shaders/toy_building.gdshader")
	var drawn := {}
	for chunk in root.get_node("BuildingKit").get_children():
		for mmi: MultiMeshInstance3D in chunk.get_children():
			drawn[mmi.name] = drawn.get(mmi.name, 0) + mmi.multimesh.instance_count
	var want := {}
	for md: Dictionary in world["building_modules"]:
		want[md["m"]] = want.get(md["m"], 0) + 1
	for m: String in want:
		if drawn.get(m, 0) != want[m]:
			_fail("building kit %s: %d drawn, %d in world.json" % [m, drawn.get(m, 0), want[m]])
	var signs := root.get_node("Buildings/Signs").get_child_count()
	if signs != world["building_signs"].size():
		_fail("building signs: %d drawn, %d in world.json" % [signs, world["building_signs"].size()])
	print("buildings: %d masses (%d triangles, one material), %d kit modules %s, %d name signs" % [
			world["buildings"].size(), tris, world["building_modules"].size(), want, signs])
