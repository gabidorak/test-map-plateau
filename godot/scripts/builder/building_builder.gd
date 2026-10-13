@tool
extends RefCounted
## Toy buildings (milestone M7): every mass is a stack of tiers (pipeline/plateau/massing.py), extruded here
## with rounded corners (already in the rings), a quarter-round bevel along the top edge, parapets around
## lowered roof decks, undersides of floating tiers and pitched pyramid roofs. One shared material
## (shaders/toy_building.gdshader) draws windows, doors, materials and roofs from per-vertex data:
##   COLOR   wall / roof colour            UV      (u along the facade, h above the building base) in m
##   UV2     (facade length, h of the last window floor's ceiling)
##   CUSTOM0 (ground floor height, floor height, door u (-1: none), bay width)
##   CUSTOM1 (part, floor style, ground style, material)   (indices: plateau/facades.py and the shader)
##   CUSTOM2 (accent colour rgb, top style + 4 * window variant)
##   CUSTOM3 (seed, window floors, tier top h, parapet height)
## Building-kit modules (res://assets/building_kit/, blender/building_kit/) are drawn with one MultiMesh per
## module and 96 m chunk (toy prop shader, accent tint per instance); name signs are Label3D on a plate.
## Collision: one StaticBody3D, one concave shape per mass from the plain tier prisms and the pillars.
## Landmarks (M9): toy.styles holds per-facade styles (runs[k][3] indexes it; volume tiers too), a style's
## ground_wall colours the ground floor band, toy.columns are round columns (kit pilotis + collision boxes).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const SHADER := "res://shaders/toy_building.gdshader"
const PROP_SHADER := "res://shaders/toy_prop.gdshader"
const GLASS_SHADER := "res://shaders/toy_prop_glass.gdshader"
const KIT_DIR := "res://assets/building_kit/"
const CHUNK := 96.0
const PART := {"wall": 0, "roof": 1, "coping": 2, "parapet": 3, "soffit": 4, "fascia": 5, "plant": 6, "pitched": 7}
const BEVEL_MID := Vector2(0.293, 0.707)   # quarter round: inset and height shares of the middle ring
const PILLAR_SIZE := 0.45
const PILLAR_SIZE_TALL := 0.75
const PILLAR_TALL := 6.0
const KIT_SLOTS := {"toy": 0, "tint": 1, "glow": 2}
const LABEL_PIXEL := 0.004

var _kit: Dictionary
var _kit_meshes := {}
var _kit_scene: Node
var _kit_mats := {}
var _groups := {}
var _mesh_dir := ""


## Packed vertex buffers of one mesh (non-indexed triangles).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	# per-surface state, set before adding triangles
	var color := Color.WHITE
	var uv2_val := Vector2.ZERO
	var cust := [Color(), Color(), Color(), Color()]

	func vert(p: Vector3, nrm: Vector3, u: Vector2) -> void:
		v.append(p)
		n.append(nrm)
		col.append(color)
		uv.append(u)
		uv2.append(uv2_val)
		var a: Color = cust[0]
		var b: Color = cust[1]
		var c: Color = cust[2]
		var d: Color = cust[3]
		c0.append_array([a.r, a.g, a.b, a.a])
		c1.append_array([b.r, b.g, b.b, b.a])
		c2.append_array([c.r, c.g, c.b, c.a])
		c3.append_array([d.r, d.g, d.b, d.a])

	## Triangle a, b, c (with per-vertex normals and uvs) turned to face `face` (Godot: clockwise = front).
	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2,
			uc: Vector2, face: Vector3) -> void:
		if (c - a).cross(b - a).dot(face) < 0.0:
			vert(a, na, ua)
			vert(c, nc, uc)
			vert(b, nb, ub)
		else:
			vert(a, na, ua)
			vert(b, nb, ub)
			vert(c, nc, uc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, face: Vector3) -> void:
		tri(a, b, c, na, nb, nc, ua, ub, uc, face)
		tri(a, c, d, na, nc, nd, ua, uc, ud, face)

	func commit(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_CUSTOM2] = c2
		arrays[Mesh.ARRAY_CUSTOM3] = c3
		var fmt := 0
		for k in 4:
			fmt |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		mesh.surface_set_material(0, mat)
		return mesh


func build(root: Node3D, world: Dictionary, mesh_dir: String) -> Error:
	_mesh_dir = mesh_dir
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(KIT_DIR + "kit.json"))
	if not manifest is Dictionary:
		push_error("no building kit: run blender/building_kit/build_kit.py")
		return ERR_FILE_NOT_FOUND
	_kit = manifest["models"]
	for name: String in world["building_kit"]:
		if not _kit.has(name):
			push_error("building kit module %s missing from kit.json: run blender/building_kit/build_kit.py" % name)
			return ERR_INVALID_DATA
	var pal: Dictionary = world["palette"]["building"]
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	for key in ["coping", "soffit", "glass_sky", "glass_deep", "door", "plant"]:
		mat.set_shader_parameter(key + "_color", Color.html(pal[key]))
	MeshUtils.save(mat, mesh_dir + "building_material.tres")

	var node := Node3D.new()
	node.name = "Buildings"
	root.add_child(node)
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	body.collision_layer = Layers.BUILDINGS
	body.collision_mask = 0
	root.add_child(body)
	for b: Dictionary in world["buildings"]:
		var buf := Buf.new()
		var faces := PackedVector3Array()
		var toy: Dictionary = b["toy"]
		for t: Dictionary in toy["tiers"]:
			_add_tier(buf, faces, b, toy, t)
		_add_pillars(faces, b, toy)
		_add_columns(faces, toy)
		var info := info_of(b)
		var node_name := String(b["id"]).replace(":", "_")
		var mi := MeshInstance3D.new()
		mi.name = node_name
		if buf.v.size() > 0:
			var mesh := buf.commit(mat)
			MeshUtils.save(mesh, mesh_dir + "bmesh_%s.res" % node_name)
			mi.mesh = mesh
		mi.set_meta("plateau", info)
		node.add_child(mi)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		MeshUtils.save(shape, mesh_dir + "bcol_%s.res" % node_name)
		var cs := CollisionShape3D.new()
		cs.name = node_name             # same name as the MeshInstance3D under Buildings/
		cs.shape = shape
		cs.set_meta("plateau", info)
		body.add_child(cs)

	var err := _modules(root, world)
	if err != OK:
		return err
	_signs(node, world)
	return OK


## Metadata shown by the debug picker; stored on both the mesh and the collision shape.
static func info_of(b: Dictionary) -> Dictionary:
	var info := {"type": "building", "pillars": b["pillars"].size()}
	for key in ["id", "num", "name", "landmark", "kind", "parent", "src", "walls", "base_z", "foot_z", "height", "min_height",
			"height_src", "heights"]:
		if b.get(key) != null:
			info[key] = b[key]
	info["roof_shape"] = b["roof"]["shape"]
	var toy: Dictionary = b["toy"]
	var st: Dictionary = toy["style"]
	info["style"] = st["names"]
	info["group"] = st["group"]
	info["levels"] = st["levels"]
	info["floor_heights"] = [st["g"], st["f"]]
	var kinds := {}
	for t: Dictionary in toy["tiers"]:
		kinds[t["kind"]] = kinds.get(t["kind"], 0) + 1
	info["tiers"] = kinds
	info["passages"] = toy["passages"].size()
	info["facade"] = b["facade"]
	return info


# ---------------------------------------------------------------- tiers

func _add_tier(buf: Buf, faces: PackedVector3Array, b: Dictionary, toy: Dictionary, t: Dictionary) -> void:
	var st: Dictionary = toy["style"]
	var runs: Array = toy["runs"]
	var base: float = b["base_z"]
	var z0: float = t["z0"]
	var top: float = t["top"]
	var par: float = t["parapet"]
	var pw: float = t["pwidth"]
	var bev: float = t["bevel"]
	var deck := top - par
	var inset := pw if par > 0.0 else bev
	var kind: String = t["kind"]
	var wall_part := float(PART["wall"])
	if kind == "slab":
		wall_part = float(PART["fascia"])
	elif kind == "box":
		wall_part = float(PART["plant"])
	var styles: Array = toy.get("styles", [st])
	var wall_col := Color.html(st["wall"])
	var roof_col := Color.html(t["roof"])
	var c2 := _c2(st)
	var c3 := Color(float(st["seed"]), float(st["levels"]), top - base, par)
	var rings: Array = t["rings"]
	var ws: Array = t["w"]
	var up := Vector3.UP

	# collision: the plain prism
	var flat_v: Array[Vector2] = []
	for ri in rings.size():
		var ring: Array = rings[ri]
		var n := ring.size()
		for i in n:
			var p := _v2(ring[i])
			var q := _v2(ring[(i + 1) % n])
			flat_v.append(p)
			_col_quad(faces, p, q, z0, top)
	var tris: Array = t["tris"]
	for k in range(0, tris.size(), 3):
		var a := flat_v[tris[k]]
		var bb := flat_v[tris[k + 1]]
		var c := flat_v[tris[k + 2]]
		_col_tri(faces, MeshUtils.to_godot(a.x, a.y, top), MeshUtils.to_godot(bb.x, bb.y, top), MeshUtils.to_godot(c.x, c.y, top), up)
		if t["floating"]:
			_col_tri(faces, MeshUtils.to_godot(a.x, a.y, z0), MeshUtils.to_godot(bb.x, bb.y, z0), MeshUtils.to_godot(c.x, c.y, z0), Vector3.DOWN)

	# walls, bevel, coping, parapet inner walls
	for ri in rings.size():
		var ring: Array = rings[ri]
		var w: Array = ws[ri]
		var expo: Array = t["exp"][ri]
		var seg: Array = t["seg"][ri]
		var n := ring.size()
		for i in n:
			var j := (i + 1) % n
			var p := _v2(ring[i])
			var q := _v2(ring[j])
			var wp := _v2(w[i])
			var wq := _v2(w[j])
			var length := p.distance_to(q)
			if length < 1e-4:
				continue
			var nrm := Vector3(q.y - p.y, 0.0, q.x - p.x).normalized()     # outward (pipeline right of p->q)
			var run: Array = runs[int(seg[2 * i])]
			var u0: float = seg[2 * i + 1]
			var exposed: bool = int(expo[i]) == 1
			var rs: Dictionary = styles[int(run[3])] if run.size() > 3 else st
			var wcol := Color.html(rs["wall"])
			buf.color = wcol
			buf.uv2_val = Vector2(run[0], deck - base)
			buf.cust = [Color(rs["g"], rs["f"], run[1], rs["bay"]), Color(wall_part, rs["floors"], rs["ground"], rs["material"]),
					_c2(rs), Color(float(rs["seed"]), float(rs["levels"]), top - base, par)]
			var zt := top - bev
			# a ground floor in its own colour (M9): the wall is cut at the ground floor height
			var zg: float = base + float(rs["g"])
			if rs.has("ground_wall") and kind != "box" and z0 < zg - 0.05 and zg < zt - 0.05:
				buf.color = Color.html(rs["ground_wall"])
				buf.quad(_g(p, z0), _g(q, z0), _g(q, zg), _g(p, zg), nrm, nrm, nrm, nrm,
						Vector2(u0, z0 - base), Vector2(u0 + length, z0 - base), Vector2(u0 + length, zg - base),
						Vector2(u0, zg - base), nrm)
				buf.color = wcol
				buf.quad(_g(p, zg), _g(q, zg), _g(q, zt), _g(p, zt), nrm, nrm, nrm, nrm,
						Vector2(u0, zg - base), Vector2(u0 + length, zg - base), Vector2(u0 + length, zt - base),
						Vector2(u0, zt - base), nrm)
			else:
				buf.quad(_g(p, z0), _g(q, z0), _g(q, zt), _g(p, zt), nrm, nrm, nrm, nrm,
						Vector2(u0, z0 - base), Vector2(u0 + length, z0 - base), Vector2(u0 + length, zt - base),
						Vector2(u0, zt - base), nrm)
			# quarter-round bevel: wall top -> middle ring -> bevel ring at the top
			buf.color = wcol
			buf.cust[1] = Color(PART["coping"], rs["floors"], rs["ground"], rs["material"])
			var n_mid := (nrm + up).normalized() if exposed else nrm
			var n_top := up if exposed else nrm
			var pm := p + wp * bev * BEVEL_MID.x
			var qm := q + wq * bev * BEVEL_MID.x
			var zm := top - bev + bev * BEVEL_MID.y
			var pb := p + wp * bev
			var qb := q + wq * bev
			if bev > 0.0:
				buf.quad(_g(p, zt), _g(q, zt), _g(qm, zm), _g(pm, zm), nrm, nrm, n_mid, n_mid,
						Vector2(u0, zt - base), Vector2(u0 + length, zt - base), Vector2(u0 + length, zm - base), Vector2(u0, zm - base), nrm)
				buf.quad(_g(pm, zm), _g(qm, zm), _g(qb, top), _g(pb, top), n_mid, n_mid, n_top, n_top,
						Vector2(u0, zm - base), Vector2(u0 + length, zm - base), Vector2(u0 + length, top - base), Vector2(u0, top - base),
						n_mid)
			if par <= 0.0 or not exposed:
				continue
			var pi := p + wp * pw
			var qi := q + wq * pw
			if pb.distance_to(qb) > 1e-3 or pi.distance_to(qi) > 1e-3:
				buf.quad(_g(pb, top), _g(qb, top), _g(qi, top), _g(pi, top), up, up, up, up,
						Vector2(u0, top - base), Vector2(u0 + length, top - base), Vector2(u0 + length, top - base),
						Vector2(u0, top - base), up)
			# inner face of the parapet, facing the roof
			buf.color = wcol.darkened(0.08)
			buf.cust[1] = Color(PART["parapet"], rs["floors"], rs["ground"], rs["material"])
			var inward := -nrm
			buf.quad(_g(pi, deck), _g(qi, deck), _g(qi, top), _g(pi, top), inward, inward, inward, inward,
					Vector2(u0, deck - base), Vector2(u0 + length, deck - base), Vector2(u0 + length, top - base),
					Vector2(u0, top - base), inward)

	# roof: deck (parapet) or top (bevel), pyramid when it has an apex
	var cap: Array = t["cap"]
	var flat_c: Array[Vector2] = []
	for ri in rings.size():
		for i in rings[ri].size():
			flat_c.append(_v2(rings[ri][i]) + _v2(ws[ri][i]) * inset)
	var zr := deck if par > 0.0 else top
	buf.color = roof_col
	buf.uv2_val = Vector2(0.0, deck - base)
	buf.cust = [Color(st["g"], st["f"], -1.0, st["bay"]), Color(PART["roof"], st["floors"], st["ground"], st["material"]), c2, c3]
	if t.has("apex"):
		var ax: Array = t["apex"]
		var apex := MeshUtils.to_godot(ax[0], ax[1], top + float(ax[2]))
		buf.cust[1] = Color(PART["pitched"], st["floors"], st["ground"], st["material"])
		var ring0: Array = rings[0]
		var n0 := ring0.size()
		for i in n0:
			var a := MeshUtils.to_godot(flat_c[i].x, flat_c[i].y, top)
			var c := MeshUtils.to_godot(flat_c[(i + 1) % n0].x, flat_c[(i + 1) % n0].y, top)
			var fn := (c - a).cross(apex - a).normalized()
			if fn.y < 0.0:
				fn = -fn
			buf.tri(a, c, apex, fn, fn, fn, Vector2(a.x, -a.z), Vector2(c.x, -c.z), Vector2(apex.x, -apex.z), fn)
	else:
		for k in range(0, cap.size(), 3):
			var a := flat_c[cap[k]]
			var bb := flat_c[cap[k + 1]]
			var c := flat_c[cap[k + 2]]
			buf.tri(_g(a, zr), _g(bb, zr), _g(c, zr), up, up, up, a, bb, c, up)
	if t["floating"]:
		buf.color = wall_col
		buf.cust = [Color(st["g"], st["f"], -1.0, st["bay"]), Color(PART["soffit"], st["floors"], st["ground"], st["material"]), c2, c3]
		var down := Vector3.DOWN
		for k in range(0, tris.size(), 3):
			var a := flat_v[tris[k]]
			var bb := flat_v[tris[k + 1]]
			var c := flat_v[tris[k + 2]]
			buf.tri(_g(a, z0), _g(bb, z0), _g(c, z0), down, down, down, a, bb, c, down)


## CUSTOM2: accent colour and top style + 4 * window variant.
static func _c2(st: Dictionary) -> Color:
	var accent := Color.html(st["accent"])
	return Color(accent.r, accent.g, accent.b, float(st["top"]) + 4.0 * float(st.get("windows", 0)))


## Landmark columns (M9): collision boxes; the kit pilotis draw them.
func _add_columns(faces: PackedVector3Array, toy: Dictionary) -> void:
	for c: Array in toy.get("columns", []):
		var s: float = c[4]
		var corners: Array[Vector2] = [Vector2(c[0] - s, c[1] - s), Vector2(c[0] + s, c[1] - s),
				Vector2(c[0] + s, c[1] + s), Vector2(c[0] - s, c[1] + s)]  # CCW
		for i in 4:
			_col_quad(faces, corners[i], corners[(i + 1) % 4], c[2] - 0.3, c[3])


func _add_pillars(faces: PackedVector3Array, b: Dictionary, toy: Dictionary) -> void:
	var z_bot := INF
	for t: Dictionary in toy["tiers"]:
		if t["kind"] == "slab":
			z_bot = minf(z_bot, t["z0"])
	if z_bot == INF:
		return
	for pl: Array in b["pillars"]:
		var s: float = (PILLAR_SIZE_TALL if z_bot - pl[2] > PILLAR_TALL else PILLAR_SIZE) / 2.0
		var corners: Array[Vector2] = [Vector2(pl[0] - s, pl[1] - s), Vector2(pl[0] + s, pl[1] - s),
				Vector2(pl[0] + s, pl[1] + s), Vector2(pl[0] - s, pl[1] + s)]  # CCW
		for i in 4:
			_col_quad(faces, corners[i], corners[(i + 1) % 4], pl[2] - 0.3, z_bot)


static func _v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


static func _g(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, z, -p.y)


## Collision wall quad from p to q (CCW outline: (dy, -dx) points outwards).
static func _col_quad(faces: PackedVector3Array, p: Vector2, q: Vector2, z0: float, z1: float) -> void:
	var normal := Vector3(q.y - p.y, 0.0, q.x - p.x)
	_col_tri(faces, _g(p, z0), _g(q, z0), _g(q, z1), normal)
	_col_tri(faces, _g(p, z0), _g(q, z1), _g(p, z1), normal)


static func _col_tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (c - a).cross(b - a).dot(normal) < 0.0:
		faces.append_array([a, c, b])
	else:
		faces.append_array([a, b, c])


# ---------------------------------------------------------------- kit modules

func _modules(root: Node3D, world: Dictionary) -> Error:
	for slot: String in KIT_SLOTS:
		var mat := ShaderMaterial.new()
		mat.shader = load(PROP_SHADER)
		mat.set_shader_parameter("mode", KIT_SLOTS[slot])
		_kit_mats[slot] = MeshUtils.save(mat, _mesh_dir + "kit_material_%s.tres" % slot)
	var glass := ShaderMaterial.new()
	glass.shader = load(GLASS_SHADER)
	_kit_mats["glass"] = MeshUtils.save(glass, _mesh_dir + "kit_material_glass.tres")
	if not ResourceLoader.exists(KIT_DIR + "kit.glb"):
		push_error("missing %skit.glb: run blender/building_kit/build_kit.py, then godot --headless --import" % KIT_DIR)
		return ERR_FILE_NOT_FOUND
	_kit_scene = load(KIT_DIR + "kit.glb").instantiate()
	for md: Dictionary in world["building_modules"]:
		var s: Array = md.get("s", [1.0, 1.0, 1.0])
		var theta := deg_to_rad(float(md["yaw"])) + PI / 2.0
		var xf := Transform3D(Basis(Vector3.UP, theta) * Basis.from_scale(Vector3(s[0], s[2], s[1])),
				MeshUtils.to_godot(md["x"], md["y"], md["z"]))
		var tint := Color.html(md["tint"]) if md.has("tint") else Color.WHITE
		if not _instance(md["m"], xf, Color(tint.r, tint.g, tint.b, 0.0)):
			_kit_scene.free()
			return ERR_INVALID_DATA
	_kit_scene.free()
	var node := Node3D.new()
	node.name = "BuildingKit"
	root.add_child(node)
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
		mm.mesh = _kit_meshes[name]
		mm.instance_count = g[0].size() / 16
		mm.buffer = g[0]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		mmi.multimesh = mm
		mmi.custom_aabb = g[1]
		mmi.visibility_range_end = float(_kit[name].get("range", 250.0))
		mmi.visibility_range_end_margin = 10.0
		mmi.set_meta("plateau", {"type": "building_kit", "model": name})
		chunks[ck].add_child(mmi)
	return OK


func _kit_mesh(name: String) -> ArrayMesh:
	if _kit_meshes.has(name):
		return _kit_meshes[name]
	var mi := _kit_scene.find_child(name, true, false) as MeshInstance3D
	if mi == null:
		push_error("building kit module %s missing from kit.glb" % name)
		return null
	var mesh := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var mat: Material = mi.mesh.surface_get_material(s)
		var slot := mat.resource_name if mat else "toy"
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(s))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _kit_mats.get(slot, _kit_mats["toy"]))
	_kit_meshes[name] = MeshUtils.save(mesh, _mesh_dir + "kit_%s.res" % name)
	return mesh


func _instance(name: String, xf: Transform3D, custom: Color) -> bool:
	if _kit_mesh(name) == null:
		return false
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
	var lo: Array = _kit[name]["min"]
	var hi: Array = _kit[name]["max"]
	var box := local * AABB(Vector3(lo[0], lo[2], -hi[1]), Vector3(hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))
	g[1] = box if g[0].size() == 16 else (g[1] as AABB).merge(box)
	return true


# ---------------------------------------------------------------- name signs

func _signs(node: Node3D, world: Dictionary) -> void:
	var parent := Node3D.new()
	parent.name = "Signs"
	node.add_child(parent)
	var mats := {}
	for s: Dictionary in world["building_signs"]:
		var w: float = s["w"]
		var holder := Node3D.new()
		holder.name = String(s["building"]).replace(":", "_")
		holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"])) + PI / 2.0),
				MeshUtils.to_godot(s["x"], s["y"], s["z"]))
		holder.set_meta("plateau", {"type": "building_sign", "text": s["text"], "building": s["building"]})
		parent.add_child(holder)
		var hex: String = s["plate"]
		if not mats.has(hex):
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.html(hex)
			m.roughness = 0.5
			mats[hex] = MeshUtils.save(m, _mesh_dir + "sign_plate_%s.tres" % hex.trim_prefix("#"))
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, 0.62, 0.08)
		plate.mesh = box
		plate.material_override = mats[hex]
		plate.position = Vector3(0.0, 0.0, 0.1)
		holder.add_child(plate)
		var l := Label3D.new()
		l.text = s["text"]
		l.pixel_size = LABEL_PIXEL
		l.font_size = 96
		l.outline_size = 0
		l.modulate = Color.html(s["color"])
		l.width = (w - 0.2) / LABEL_PIXEL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.position = Vector3(0.0, 0.0, 0.145)
		var lines := maxi(1, ceili(String(s["text"]).length() * 96 * 0.55 * LABEL_PIXEL / (w - 0.2)))
		if lines > 1:
			l.font_size = maxi(40, 96 / lines)
		holder.add_child(l)
