@tool
extends RefCounted
## Street furniture (milestone M6).
## Props: the soft-toy models of res://assets/props/ (blender/props/build_props.py) drawn with one MultiMesh
## per model and 96 m chunk; each instance sits on the draped ground (+ its lift on raised sidewalks), turned
## to its yaw and stretched by its scale, and carries its tint and a phase (INSTANCE_CUSTOM, signal cycle).
## Sign poles carry their faces stacked from the pole's `faces` anchor down. Fences and walls are panel
## models stretched to each segment, with posts between them. Bus stops get Label3D nodes: the stop name on
## the pole flag and the shelter fascia, and line badges in the line colours.
## Collision boxes and cylinders are created at runtime (prop_collision.gd) from prop_data.res.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const PropData = preload("res://scripts/prop_data.gd")
const PropCollision = preload("res://scripts/prop_collision.gd")
const MODELS_DIR := "res://assets/props/"
const SHADER := "res://shaders/toy_prop.gdshader"
const GLASS_SHADER := "res://shaders/toy_prop_glass.gdshader"
const CHUNK := 96.0
const SLOTS := {"toy": 0, "tint": 1, "glow": 2, "signal_car": 3, "signal_ped": 4}
## fence style -> [post model, panel model, panel length (m)] (blender/props/barriers.py FENCES)
const FENCES := {"bars": ["fence_post_bars", "fence_panel_bars", 2.5], "mesh": ["fence_post_mesh", "fence_panel_mesh", 2.5],
		"wood": ["fence_post_wood", "fence_panel_wood", 2.5], "wall": ["", "wall_block", 1.0],
		"guard_rail": ["guard_rail_post", "guard_rail_panel", 2.5]}
const FENCE_THICKNESS := 0.12
const LABEL_PIXEL := 0.002              # m per label pixel

var _models: Dictionary                 # props.json "models" and "faces" together
var _scenes := {}                       # glb path -> instantiated scene
var _meshes := {}                       # model name -> ArrayMesh
var _materials := {}                    # slot -> material
var _groups := {}                       # "cx|cy|model" -> [PackedFloat32Array, AABB, Vector2i, model]
var _badge_mats := {}
var _ground
var _data: PropData
var _palette: Dictionary
var _mesh_dir := ""
var _missing := {}


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> Error:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MODELS_DIR + "props.json"))
	if not manifest is Dictionary:
		push_error("no prop models: run blender/props/build_props.py")
		return ERR_FILE_NOT_FOUND
	_models = manifest["models"].duplicate()
	_models.merge(manifest["faces"])
	_mesh_dir = mesh_dir
	_palette = world["palette"]["props"]
	var t: Dictionary = world["terrain"]
	_ground = GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	for slot: String in SLOTS:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		mat.set_shader_parameter("mode", SLOTS[slot])
		_materials[slot] = MeshUtils.save(mat, mesh_dir + "prop_material_%s.tres" % slot)
	var glass := ShaderMaterial.new()
	glass.shader = load(GLASS_SHADER)
	_materials["glass"] = MeshUtils.save(glass, mesh_dir + "prop_material_glass.tres")
	for name: String in world["prop_models"] + world["sign_faces"]:
		if not _models.has(name):
			push_error("prop model %s missing from props.json: run blender/props/build_props.py" % name)
			return ERR_INVALID_DATA

	_data = PropData.new()
	var node := Node3D.new()
	node.name = "Props"
	root.add_child(node)
	var stops := Node3D.new()
	stops.name = "BusStops"
	node.add_child(stops)
	for p: Dictionary in world["props"]:
		_place_prop(p, stops)
	for f: Dictionary in world["fences"]:
		_place_fence(f)
	for scene: Node in _scenes.values():
		scene.free()
	if not _missing.is_empty():
		push_error("prop models missing from the .glb files: %s" % _missing.keys())
		return ERR_INVALID_DATA
	_emit(node)
	MeshUtils.save(_data, mesh_dir + "prop_data.res")
	var body := PropCollision.new()
	body.name = "PropCollision"
	body.collision_layer = Layers.PROPS
	body.collision_mask = 0
	body.data = _data
	body.set_meta("plateau", {"type": "props", "id": "props"})
	root.add_child(body)
	return OK


# ---------------------------------------------------------------- meshes

## The model as an ArrayMesh with the toy prop materials, saved once.
func _mesh(name: String) -> ArrayMesh:
	if _meshes.has(name):
		return _meshes[name]
	var glb: String = MODELS_DIR + String(_models[name]["glb"])
	if not _scenes.has(glb):
		_scenes[glb] = load(glb).instantiate()
	var mi := (_scenes[glb] as Node).find_child(name, true, false) as MeshInstance3D
	if mi == null:
		_missing[name] = true
		_meshes[name] = null
		return null
	var mesh := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var mat: Material = mi.mesh.surface_get_material(s)
		var slot := mat.resource_name if mat else "toy"
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(s))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials.get(slot, _materials["toy"]))
	_meshes[name] = MeshUtils.save(mesh, _mesh_dir + "prop_%s.res" % name)
	return mesh


## Model bounds in Godot model space (Blender x, z, -y).
func _bounds(name: String) -> AABB:
	var lo: Array = _models[name]["min"]
	var hi: Array = _models[name]["max"]
	return AABB(Vector3(lo[0], lo[2], -hi[1]), Vector3(hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))


func _instance(name: String, xf: Transform3D, custom: Color) -> void:
	if _mesh(name) == null:
		return
	var ck := Vector2i(floori(xf.origin.x / CHUNK), floori(-xf.origin.z / CHUNK))
	var key := "%d|%d|%s" % [ck.x, ck.y, name]
	if not _groups.has(key):
		_groups[key] = [PackedFloat32Array(), AABB(), ck, name]
	var g: Array = _groups[key]
	var local := xf
	local.origin -= Vector3((ck.x + 0.5) * CHUNK, 0.0, -(ck.y + 0.5) * CHUNK)
	var b := local.basis
	var o := local.origin
	g[0].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
			custom.r, custom.g, custom.b, custom.a])
	var box := local * _bounds(name)
	g[1] = box if g[0].size() == 16 else (g[1] as AABB).merge(box)


func _emit(node: Node3D) -> void:
	var chunks := {}
	for key: String in _groups:
		var g: Array = _groups[key]
		var ck: Vector2i = g[2]
		if not chunks.has(ck):
			var cn := Node3D.new()
			cn.name = "Chunk_%d_%d" % [ck.x, ck.y]
			cn.position = Vector3((ck.x + 0.5) * CHUNK, 0.0, -(ck.y + 0.5) * CHUNK)
			node.add_child(cn)
			chunks[ck] = cn
		var name: String = g[3]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[name]
		mm.instance_count = g[0].size() / 16
		mm.buffer = g[0]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		mmi.multimesh = mm
		mmi.custom_aabb = g[1]
		mmi.visibility_range_end = float(_models[name].get("range", 150.0))
		mmi.visibility_range_end_margin = 10.0
		mmi.set_meta("plateau", {"type": "props", "model": name})
		chunks[ck].add_child(mmi)


# ---------------------------------------------------------------- props

func _place_prop(p: Dictionary, stops: Node3D) -> void:
	var x: float = p["x"]
	var y: float = p["y"]
	var model: String = p["model"]
	var theta := deg_to_rad(float(p["yaw"])) + PI / 2.0          # model front (Godot +Z) towards the yaw
	var sc: Array = p.get("scale", [1.0, 1.0])
	var pos := MeshUtils.to_godot(x, y, _ground.at(x, y) + float(p.get("lift", 0.0)))
	var turn := Basis(Vector3.UP, theta)
	var xf := Transform3D(turn * Basis.from_scale(Vector3(sc[0], 1.0, sc[1])), pos)
	var info: Dictionary = p.get("info", {})
	var tint := Color.WHITE
	if p.has("tint"):
		tint = Color.html(_palette.get(p["tint"], "#ffffff"))
	var phase: float = info.get("phase", (hash(p["id"]) % 1000) / 1000.0)
	_instance(model, xf, Color(tint.r, tint.g, tint.b, phase))
	var meta := {"type": "prop", "id": p["id"], "kind": p["kind"], "model": model, "src": p["src"],
			"osm": p.get("osm", ""), "name": p.get("name", ""), "tags": p.get("tags", {}), "info": info,
			"yaw": p["yaw"], "tint": p.get("tint", "")}
	var k := _data.add_record(p["id"], meta)
	for c: Dictionary in _models[model]["colliders"]:
		_collider(k, c, Transform3D(turn, pos), theta, sc[0], sc[1])
	if model == "sign_pole":
		var a: Dictionary = _models[model]["anchors"]["faces"]
		var top: float = a["top"]
		for face: String in info.get("faces", []):
			var h: float = _models[face]["size"][2]
			var local := Vector3(0.0, top - h / 2.0, float(a["front"]) + 0.012)
			_instance(face, Transform3D(turn, pos + turn * local), Color.WHITE)
			top -= h + float(a["gap"])
	if model in ["bus_pole", "bus_shelter"]:
		_bus_labels(stops, p, Transform3D(turn, pos))


func _collider(k: int, c: Dictionary, xf: Transform3D, theta: float, sx: float, sy: float) -> void:
	if c.has("box"):
		var b: Array = c["box"]
		var local := Vector3(b[0] * sx, b[2], -b[1] * sy)
		_data.add_box(k, xf * local, Vector3(b[3] * sx, b[5], b[4] * sy), theta)
	elif c.has("cyl"):
		var q: Array = c["cyl"]
		var local := Vector3(q[0] * sx, q[2] + q[4] / 2.0, -q[1] * sy)
		_data.add_cylinder(k, xf * local, q[3], q[4])


# ---------------------------------------------------------------- fences

func _place_fence(f: Dictionary) -> void:
	var spec: Array = FENCES.get(f["style"], FENCES["bars"])
	var post: String = spec[0]
	var panel: String = spec[1]
	var ref: float = spec[2]
	var h: float = f["h"]
	var k := _data.add_record(f["id"], {"type": "fence", "id": f["id"], "style": f["style"], "height": h,
			"height_src": f["height_src"], "osm": f["osm"]})
	var pts: Array = f["pts"]
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var dir := (b - a) / length
		var theta := atan2(dir.y, dir.x)
		var turn := Basis(Vector3.UP, theta)
		var n := maxi(1, roundi(length / ref))
		var l := length / n
		for j in n:
			var c := a + dir * (j + 0.5) * l
			var z: float = _ground.at(c.x, c.y)
			_instance(panel, Transform3D(turn * Basis.from_scale(Vector3(l / ref, h, 1.0)), MeshUtils.to_godot(c.x, c.y, z)), Color.WHITE)
			_data.add_box(k, MeshUtils.to_godot(c.x, c.y, z + h / 2.0), Vector3(l, h, FENCE_THICKNESS), theta)
		if post.is_empty():
			continue
		for j in range(0 if i == 0 else 1, n + 1):
			var q := a + dir * j * l
			_instance(post, Transform3D(turn * Basis.from_scale(Vector3(1.0, h, 1.0)),
					MeshUtils.to_godot(q.x, q.y, _ground.at(q.x, q.y))), Color.WHITE)


# ---------------------------------------------------------------- bus stop labels

func _bus_labels(stops: Node3D, p: Dictionary, xf: Transform3D) -> void:
	var info: Dictionary = p["info"]
	var node := Node3D.new()
	node.name = String(p["id"]).replace(":", "_")
	node.transform = xf
	node.set_meta("plateau", {"type": "bus_stop_labels", "id": p["id"], "stop": info.get("stop", "")})
	stops.add_child(node)
	var lines: Array = info.get("lines", [])
	var name: String = info.get("stop", "")
	var blue := Color.html(_palette["idfm_blue"])
	if p["model"] == "bus_pole":
		var a: Dictionary = _models["bus_pole"]["anchors"]["flag"]
		for side: float in [1.0, -1.0]:                   # both faces of the flag
			var face := Node3D.new()
			face.rotation.y = 0.0 if side > 0 else PI
			node.add_child(face)
			var front := float(a["t"]) + 0.003
			var x := float(a["x"]) * side
			var top := float(a["z0"]) + float(a["h"])
			_label(face, name, Vector3(x, top - float(a["band"]) / 2.0, front), float(a["w"]) - 0.03, 32, Color.WHITE)
			_badges(face, lines, Vector3(x, top - float(a["band"]) - 0.075, front), 3, Vector2(0.15, 0.1))
	else:
		var a: Dictionary = _models["bus_shelter"]["anchors"]["fascia"]
		var w: float = a["w"]
		var front := -float(a["y"]) + 0.004
		_label(node, name, Vector3(float(a["x"]) - w * 0.17, float(a["z"]), front), w * 0.62, 72, blue)
		_badges(node, lines, Vector3(float(a["x"]) + w * 0.33, float(a["z"]), front), 4, Vector2(0.27, 0.17))


func _label(parent: Node3D, text: String, pos: Vector3, width: float, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = LABEL_PIXEL
	l.font_size = size
	l.outline_size = 0
	l.modulate = color
	l.width = width / LABEL_PIXEL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	parent.add_child(l)
	return l


## Line badges in rows of `cols`, centred on `start` (first row), each a rounded colour plate with its number.
func _badges(parent: Node3D, lines: Array, start: Vector3, cols: int, cell: Vector2) -> void:
	for i in lines.size():
		var line: Dictionary = lines[i]
		var row := i / cols
		var in_row := mini(cols, lines.size() - row * cols)
		var col := i % cols
		var c := start + Vector3((col - (in_row - 1) / 2.0) * cell.x, -row * cell.y, 0.0)
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(cell.x * 0.86, cell.y * 0.8, 0.006)
		plate.mesh = box
		plate.material_override = _badge_material(line["colour"])
		plate.position = c
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(plate)
		_label(parent, line["ref"], c + Vector3(0, 0, 0.004), cell.x, roundi(cell.y * 0.5 / LABEL_PIXEL), Color.html(line["text"]))


func _badge_material(hex: String) -> StandardMaterial3D:
	if not _badge_mats.has(hex):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.html(hex)
		m.roughness = 0.5
		_badge_mats[hex] = MeshUtils.save(m, _mesh_dir + "badge_%s.tres" % hex.trim_prefix("#"))
	return _badge_mats[hex]
