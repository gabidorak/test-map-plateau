extends RefCounted
## The building kit: what the buildings drawn by code share — Villa de charme (scripts/villaEnPierreCoteaux/: its builders extend it), the
## restyled buildings (scripts/restyle/). Meshes are merged per material (one SurfaceTool each, committed as one
## MeshInstance3D per material), collision boxes and faces go into one StaticBody3D (BUILDINGS), materials and their
## procedural textures (drawn once a session) are cached: mat() names them ("#rrggbb" a plain colour; the restyled
## buildings' library adds its own). Coordinates are its user's frame (the villa's: x east, y up from the house's floor,
## z south; the restyled buildings': the map's).

const Layers = preload("res://scripts/physics_layers.gd")
const WATER_SHADER := preload("res://shaders/kit_water.gdshader")

var root: Node3D
var body: StaticBody3D
var _st := {}

static var _mats := {}
static var _textures := {}


func _init(name: String, info := {}) -> void:
	root = Node3D.new()
	root.name = name
	body = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Layers.BUILDINGS
	body.collision_mask = 0
	if not info.is_empty():
		body.set_meta("plateau", info)
	root.add_child(body)


## The meshes into `root` (one MeshInstance3D per material); `meshes` false (headless): none, collision only.
func commit(meshes := true, range_end := 0.0) -> Node3D:
	if meshes:
		for name: String in _st:
			var mi := MeshInstance3D.new()
			mi.name = "M_" + name
			mi.mesh = (_st[name] as SurfaceTool).commit()
			var mname: String = name.split("|")[0]
			mi.material_override = mat(mname)
			if mname in ["glass", "glass_win", "water", "fall", "foam", "emit", "bulb", "led", "sky"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if range_end > 0.0:
				mi.visibility_range_end = range_end
			root.add_child(mi)
	_st.clear()
	return root


# ---------------------------------------------------------------- meshes

func tool(m: String) -> SurfaceTool:
	if not _st.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[m] = st
	return _st[m]


func box(m: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if absf(x1 - x0) < 0.0005 or absf(y1 - y0) < 0.0005 or absf(z1 - z0) < 0.0005:
		return
	var b := BoxMesh.new()
	b.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	tool(m).append_from(b, 0, Transform3D(Basis.IDENTITY, Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5))


## A box of `size` centred at `at` in frame `xf`.
func box_xf(m: String, xf: Transform3D, size: Vector3, at := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	tool(m).append_from(b, 0, Transform3D(xf.basis, xf * at))


func cyl(m: String, p: Vector3, r: float, h: float, seg := 16, top := -1.0) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = r if top < 0.0 else top
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	tool(m).append_from(c, 0, Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)))


## A cylinder of radius r from a to b.
func rod(m: String, a: Vector3, b: Vector3, r: float, seg := 8) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = length
	c.radial_segments = seg
	c.rings = 1
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	tool(m).append_from(c, 0, Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5))


func ball(m: String, c: Vector3, r: Vector3, seg := 10) -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = seg
	s.rings = maxi(4, seg / 2)
	tool(m).append_from(s, 0, Transform3D(Basis.from_scale(r), c))


func torus(m: String, xf: Transform3D, r_in: float, r_out: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 16
	t.ring_segments = 6
	tool(m).append_from(t, 0, xf)


## A triangle facing `n` (Godot: front faces wind clockwise seen from the front).
func tri(m: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv := false) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var st := tool(m + "|t")                  # (not with the meshes appended: a SurfaceTool takes one or the other)
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		if uv:
			st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)


## A quad a b c d (in order round it) facing `n`.
func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = -(b - a).cross(c - a).normalized()
	tri(m, a, b, c, n)
	tri(m, a, c, d, n)


## A surface over a grid of points `pts` (rows of Vector3), facing up, smooth normals; cut by `keep` (x, z) -> bool.
func sheet(m: String, pts: Array, keep := Callable()) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var st := tool(m + "|t")
	for i in pts.size() - 1:
		var r0: Array = pts[i]
		var r1: Array = pts[i + 1]
		for j in r0.size() - 1:
			var a: Vector3 = r0[j]
			var b: Vector3 = r1[j]
			var c: Vector3 = r1[j + 1]
			var d: Vector3 = r0[j + 1]
			if keep.is_valid() and not keep.call((a.x + c.x) * 0.5, (a.z + c.z) * 0.5):
				continue
			for t: Array in [[a, b, c], [a, c, d]]:
				var n: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).normalized()
				if n.y < 0.0:
					n = -n
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
					var s := p1
					p1 = p2
					p2 = s
				for p: Vector3 in [p0, p1, p2]:
					st.set_normal(n)
					st.add_vertex(p)
				faces.append_array(PackedVector3Array([p0, p1, p2]))
	return faces


# ---------------------------------------------------------------- collision

func col(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> CollisionShape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(maxf(absf(x1 - x0), 0.01), maxf(absf(y1 - y0), 0.01), maxf(absf(z1 - z0), 0.01))
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5
	body.add_child(cs)
	return cs


func col_xf(xf: Transform3D, size: Vector3) -> CollisionShape3D:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	body.add_child(cs)
	return cs


func col_faces(faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## A ramp walked up from `a` to `b` (the tread line's ends, middle of the flight), `w` wide: a thin box along it, its
## top through a and b.
func col_ramp(a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var along := d.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	if up.y < 0.0:
		up = -up
	var basis := Basis(side, up, along)
	col_xf(Transform3D(basis, (a + b) * 0.5 - up * 0.1), Vector3(w, 0.2, d.length()))


func label(text: String, xf: Transform3D, size: int, pixel: float, colour: Color, shaded := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 0
	l.shaded = shaded
	l.double_sided = false
	l.transform = xf
	l.visibility_range_end = 80.0
	root.add_child(l)
	return l


func light(p: Vector3, colour: Color, energy: float, reach: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 15.0
	root.add_child(l)
	return l


# ---------------------------------------------------------------- materials

## Material `m` under `name` for mat() (a user's library: the restyled buildings'); a name already there stays.
static func add_material(name: String, m: Material) -> void:
	if not _mats.has(name):
		_mats[name] = m


## A material from a description: {"colour", "metal", "rough", "specular", "alpha", "texture" (texture()'s names),
## "scale" (tiles a metre), "emit", "energy"}.
static func material_from(d: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := Color.html(str(d.get("colour", "#ffffff")))
	m.roughness = float(d.get("rough", 0.6))
	m.metallic = float(d.get("metal", 0.0))
	m.metallic_specular = float(d.get("specular", 0.5))
	if d.has("alpha"):
		c.a = float(d["alpha"])
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	if d.has("texture"):
		var sc := float(d.get("scale", 1.0))
		m.albedo_texture = texture(str(d["texture"]))
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(sc, sc, sc)
		m.uv1_triplanar_sharpness = 8.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if d.has("emit"):
		m.emission_enabled = true
		m.emission = Color.html(str(d["emit"]))
		m.emission_energy_multiplier = float(d.get("energy", 1.0))
	return m


static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"stone": m = _textured("stone", 1.0 / 2.4, 0.92)
		"rubble": m = _textured("rubble", 1.0 / 2.0, 0.95)
		"ashlar": m = _textured("ashlar", 1.0 / 1.2, 0.85)
		"coping": m = _textured("ashlar", 1.0 / 1.2, 0.8)
		"roof":
			var r := StandardMaterial3D.new()
			r.albedo_texture = texture("tiles")
			r.roughness = 0.8
			r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m = r
		"garage_door": m = _textured("panels", 1.0 / 2.55, 0.6)
		"gravel":
			var g := _textured("gravel", 1.0 / 2.0, 0.95)
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"pavers":
			var p := _textured("travertine", 1.0 / 2.4, 0.75)
			p.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = p
		"travertine": m = _textured("travertine", 1.0 / 2.4, 0.6)
		"oak_floor": m = _textured("parquet", 1.0 / 2.0, 0.55)
		"herringbone": m = _textured("herringbone", 1.0 / 1.6, 0.6)
		"marble": m = _textured("marble", 1.0 / 2.4, 0.18)
		"marble_blue": m = _textured("marble_blue", 1.0 / 2.4, 0.15)
		"mosaic": m = _textured("mosaic", 1.0 / 1.0, 0.2)
		"sky": m = _textured("sky", 1.0 / 12.0, 0.9)
		"slats": m = _textured("slats", 1.0 / 1.2, 0.6)
		"plaster": m = _plain(Color("#f1ece2"), 0.9)
		"plaster_warm": m = _plain(Color("#ece2d0"), 0.9)
		"ceiling": m = _plain(Color("#f6f3ec"), 0.95)
		"cream": m = _plain(Color("#eee3cc"), 0.7)
		"wood_dark": m = _plain(Color("#5e4129"), 0.55)
		"oak": m = _plain(Color("#b8915f"), 0.55)
		"oak_light": m = _plain(Color("#d2b48a"), 0.6)
		"walnut": m = _plain(Color("#6e4a2c"), 0.45)
		"white": m = _plain(Color("#f5f4f0"), 0.45)
		"white_gloss": m = _plain(Color("#fbfbf9"), 0.15)
		"black": m = _plain(Color("#18191b"), 0.4)
		"charcoal": m = _plain(Color("#2a2c2f"), 0.5)
		"iron": m = _metal(Color("#26292c"), 0.55)
		"brass": m = _metal(Color("#c9a45c"), 0.3)
		"chrome": m = _metal(Color("#d9dde1"), 0.12)
		"steel": m = _metal(Color("#a9aeb3"), 0.35)
		"zinc": m = _metal(Color("#8e979a"), 0.5)
		"shutter": m = _textured("louvres", 1.0 / 0.6, 0.7)
		"frame": m = _plain(Color("#f4f3ee"), 0.5)
		"door_oak": m = _plain(Color("#6f4c2e"), 0.5)
		"brick": m = _plain(Color("#a85a42"), 0.85)
		"terracotta": m = _plain(Color("#c06c40"), 0.85)
		"boxwood": m = _textured("leaves", 1.0 / 1.0, 0.95)
		"leaves": m = _textured("leaves", 1.0 / 1.0, 0.95)
		"vine": m = _textured("vine", 1.0 / 1.0, 0.95)
		"lavender": m = _plain(Color("#8c7bb5"), 0.95)
		"soil": m = _plain(Color("#4d3b2a"), 1.0)
		"lawn": m = _textured("leaves", 1.0 / 0.6, 1.0)
		"linen": m = _plain(Color("#f3f0e9"), 0.95)
		"taupe": m = _plain(Color("#8f8273"), 0.95)
		"greige": m = _plain(Color("#c9bfb1"), 0.95)
		"sand_fabric": m = _plain(Color("#d8cbb6"), 0.95)
		"velvet_cream": m = _plain(Color("#e6dccb"), 0.85)
		"leather_black": m = _plain(Color("#1d1c1b"), 0.45)
		"leather_tan": m = _plain(Color("#8a5a35"), 0.5)
		"rug_beige": m = _plain(Color("#d9cfbf"), 1.0)
		"rug_grey": m = _plain(Color("#9b9890"), 1.0)
		"blue_grey": m = _plain(Color("#7f97ab"), 0.5)
		"plant": m = _plain(Color("#3f6f38"), 0.9)
		"plant_light": m = _plain(Color("#6f9a4f"), 0.9)
		"gold_paint": m = _metal(Color("#b9954f"), 0.35)
		"art_a": m = _plain(Color("#c5a98a"), 0.9)
		"art_b": m = _plain(Color("#2f3238"), 0.9)
		"art_c": m = _plain(Color("#9a5b3c"), 0.9)
		"screen": m = _plain(Color("#0c0d10"), 0.15)
		"rubber": m = _plain(Color("#202020"), 0.8)
		"car_cover": m = _plain(Color("#5a5f66"), 0.8)
		"glass":
			var g := _plain(Color(0.78, 0.86, 0.9, 0.18), 0.04)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			g.metallic_specular = 0.9
			m = g
		"glass_win":
			var g := _plain(Color(0.5, 0.62, 0.7, 0.38), 0.02)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			g.metallic = 0.0
			g.metallic_specular = 0.45
			m = g
		"sett":
			var s := _textured("setts", 1.0 / 1.0, 0.85)
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
		"glass_dark":
			var g := _plain(Color("#2b3640"), 0.08)
			g.metallic_specular = 0.9
			m = g
		"emit", "bulb", "led":
			var e := _plain(Color(1.0, 0.96, 0.88), 0.5)
			e.emission_enabled = true
			e.emission = Color(1.0, 0.9, 0.72) if name != "led" else Color(1.0, 0.86, 0.6)
			e.emission_energy_multiplier = 2.5 if name == "emit" else (4.0 if name == "bulb" else 3.0)
			m = e
		"water", "water_in", "fall", "foam":
			var s := ShaderMaterial.new()
			s.shader = WATER_SHADER
			s.set_shader_parameter("mode", {"water": 0, "water_in": 0, "fall": 1, "foam": 2}[name])
			if name == "water_in":
				s.set_shader_parameter("tint", Color(0.2, 0.72, 0.8))
			m = s
		_:
			# "#rrggbb": a plain colour (restyled buildings' specs, scripts/restyle/)
			m = _plain(Color.html(name), 0.6) if name.begins_with("#") else _plain(Color("#ff00ff"), 1.0)
	_mats[name] = m
	return m


## A plain material: colour `c`, `rough`, `metal` (the kit's own and anyone's: NPCs, vehicles).
static func plain(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := _plain(c, rough)
	m.metallic = metal
	return m


static func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := _plain(c, rough)
	m.metallic = 0.75
	return m


static func _textured(tex: String, scale: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 8.0
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------- textures (drawn once a session)

static func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var img: Image
		match name:
			"stone": img = _ashlar_courses(512, 8, Color("#d6c4a0"), Color("#b39e7c"), 31, 0.07)
			"rubble": img = _ashlar_courses(256, 7, Color("#bfae8d"), Color("#8a7a62"), 32, 0.1)
			"ashlar": img = _ashlar_courses(256, 4, Color("#e6dac2"), Color("#c8b99c"), 33, 0.03)
			"tiles": img = _roof_tiles()
			"gravel": img = _gravel_img()
			"travertine": img = _flags(512, Color("#e2d6bd"), Color("#c4b597"), 34)
			"parquet": img = _planks(512, Color("#c9a77c"), 35)
			"herringbone": img = _herringbone(512, Color("#d4b78f"), 36)
			"marble": img = _marble(256, Color("#f2efe9"), Color("#b9b2a6"), 37, 4)
			"marble_blue": img = _marble(256, Color("#9fb3c4"), Color("#3e566c"), 38, 6)
			"mosaic": img = _mosaic()
			"sky": img = _sky()
			"slats": img = _wood_slats()
			"louvres": img = _louvres()
			"panels": img = _panels()
			"setts": img = _flags(256, Color("#b9ae9a"), Color("#857a68"), 45)
			"leaves": img = _leafy(Color("#3d6a34"), 39)
			"vine": img = _leafy(Color("#5c8a45"), 40)
			"solar": img = _solar()
			"cladding": img = _cladding()
			"brick": img = _brick_bond()
			"boards": img = _boards()
			_: img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.generate_mipmaps()
		_textures[name] = ImageTexture.create_from_image(img)
	return _textures[name]


static func _shade(c: Color, s: float) -> Color:
	return Color(clampf(c.r + s, 0, 1), clampf(c.g + s, 0, 1), clampf(c.b + s, 0, 1))


## Coursed stone: `rows` courses of blocks of random lengths, mortar joints, each block its own shade and grain.
static func _ashlar_courses(n: int, rows: int, base: Color, mortar: Color, seed: int, var_amt: float) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rh := n / rows
	var joints := []                        # per row: the x of each joint
	var shades := []
	for r in rows:
		var xs := []
		var x := rng.randi_range(0, n / 4)
		while x < n + n:
			xs.append(x % n)
			x += rng.randi_range(n / 7, n / 3)
		xs.sort()
		joints.append(xs)
		var sh := []
		for k in xs.size() + 1:
			sh.append([rng.randf_range(-var_amt, var_amt), rng.randf_range(-0.02, 0.03)])
		shades.append(sh)
	for y in n:
		var r := mini(y / rh, rows - 1)
		var xs: Array = joints[r]
		for x in n:
			var k := 0
			while k < xs.size() and x >= int(xs[k]):
				k += 1
			var near_joint := false
			for j: int in xs:
				if absi(x - j) < 2:
					near_joint = true
			var c: Color
			if y % rh < 2 or near_joint:
				c = mortar
			else:
				var s: Array = shades[r][k]
				var g := rng.randf_range(-0.035, 0.035) + sin(float(x) * 0.21 + float(y) * 0.13) * 0.012
				c = _shade(Color(base.r + float(s[1]) * 0.6, base.g + float(s[1]) * 0.3, base.b), float(s[0]) + g)
				if y % rh < 4:
					c = c.darkened(0.08)
			img.set_pixel(x, y, c)
	return img


## Flat clay tiles in staggered rows (the texture spans 1.6 m: 10 rows of 16 cm, tiles 20 cm wide).
static func _roof_tiles() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var rows := 10
	var rh := n / rows
	var cols := 8
	var cw := n / cols
	var tone := []
	for i in rows * cols:
		tone.append([rng.randf_range(-0.07, 0.07), rng.randf_range(-0.04, 0.05)])
	for y in n:
		var r := mini(y / rh, rows - 1)
		var shift := (cw / 2) * (r % 2)
		for x in n:
			var c := ((x + shift) % n) / cw
			var t: Array = tone[(r * cols + c) % tone.size()]
			var base := Color(0.70 + float(t[1]), 0.36 + float(t[1]) * 0.5, 0.25)
			var col := _shade(base, float(t[0]) + rng.randf_range(-0.03, 0.03))
			var yy := y % rh
			if yy > rh - 4:
				col = col.darkened(0.45)           # the shadow under the row above
			elif yy < 3:
				col = col.lightened(0.05)
			if (x + shift) % cw < 2:
				col = col.darkened(0.3)
			img.set_pixel(x, y, col)
	return img


## White gravel: small pale stones with grey shadows between (the texture spans 2 m).
static func _gravel_img() -> Image:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	img.fill(Color("#a39e93"))
	for i in 9000:
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randf_range(1.5, 3.6)
		var c := Color("#ebe7dd").darkened(rng.randf_range(0.0, 0.16))
		if rng.randf() < 0.12:
			c = Color("#d6cdbb")
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d := sqrt(float(dx * dx + dy * dy)) / r
				if d <= 1.0:
					var px := (cx + dx + n) % n
					var py := (cy + dy + n) % n
					img.set_pixel(px, py, c.darkened(0.12 * d * d) if dy < 0 else c.darkened(0.06 + 0.2 * d))
	return img


## Stone flags (travertine): rectangular slabs of two sizes, thin joints, pitted surface.
static func _flags(n: int, base: Color, joint: Color, seed: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows := [0, 128, 256, 320, 448, 512]
	var tone := {}
	for y in n:
		var r := 0
		while r < rows.size() - 2 and y >= int(rows[r + 1]):
			r += 1
		var shift: int = [0, 96, 40, 150, 70][r]
		var w: int = [128, 192, 160, 128, 200][r]
		for x in n:
			var c := int((x + shift) % n / w)
			var key := r * 10 + c
			if not tone.has(key):
				tone[key] = rng.randf_range(-0.045, 0.045)
			var col := _shade(base, float(tone[key]) + rng.randf_range(-0.025, 0.025))
			if rng.randf() < 0.012:
				col = col.darkened(0.18)
			if y - int(rows[r]) < 2 or (x + shift) % n % w < 2:
				col = joint
			img.set_pixel(x, y, col)
	return img


## Oak planks 14 cm wide, staggered ends, grain lines.
static func _planks(n: int, base: Color, seed: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pw := n / 14                        # (the texture spans 2 m)
	var ends := []
	var tones := []
	for k in 15:
		ends.append(rng.randi_range(0, n - 1))
		tones.append([rng.randf_range(-0.06, 0.05), rng.randf_range(-0.05, 0.05)])
	for x in n:
		var k := mini(x / pw, 14)
		for y in n:
			var half := 0 if ((y - int(ends[k]) + n) % n) < n / 2 else 1
			var t: float = tones[k][half]
			var grain := sin(float(y) * 0.05 + float(x) * 0.9 + float(k) * 3.0) * 0.025 + sin(float(y) * 0.31 + float(k)) * 0.012
			var col := _shade(base, t + grain + rng.randf_range(-0.012, 0.012))
			if x % pw < 1 or ((y - int(ends[k]) + n) % (n / 2)) < 1:
				col = col.darkened(0.3)
			img.set_pixel(x, y, col)
	return img


## Herringbone oak (the gym): planks 10 x 50 cm at right angles.
static func _herringbone(n: int, base: Color, seed: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var u := n / 16                         # a plank's width
	for y in n:
		for x in n:
			var a := x + y
			var b := x - y + n
			var band := (a / (u * 5)) % 2
			var k := 0
			var t := 0.0
			if band == 0:
				k = (b / u) * 7 + (a / (u * 10))
				t = float(b % u) / u
			else:
				k = (a / u) * 5 + (b / (u * 10)) + 999
				t = float(a % u) / u
			var tone := fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0) * 0.1 - 0.05
			var col := _shade(base, tone + sin(float(a) * 0.4) * 0.01 + rng.randf_range(-0.01, 0.01))
			if t < 0.06 or a % (u * 5) < 1:
				col = col.darkened(0.28)
			img.set_pixel(x, y, col)
	return img


## Veined marble: soft base clouds, a few dark veins (`veins`), slabs 1.2 m.
static func _marble(n: int, base: Color, vein: Color, seed: int, veins: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.016
	noise.fractal_octaves = 4
	var warp := FastNoiseLite.new()
	warp.seed = seed + 1
	warp.frequency = 0.008
	for y in n:
		for x in n:
			var v := noise.get_noise_2d(x, y)
			var w := warp.get_noise_2d(x, y) * 120.0
			var col := _shade(base, v * 0.06)
			for k in veins:
				var d := absf(sin((float(x) * 0.7 + float(y) * 0.45 + w * 0.5 + k * 97.0) * 0.024 * (1.0 + k * 0.3)))
				if d < 0.02 + absf(v) * 0.03:
					col = col.lerp(vein, (1.0 - d / (0.02 + absf(v) * 0.03)) * (0.55 if k % 2 == 0 else 0.3))
			if x % (n / 2) < 1 or y % (n / 2) < 1:
				col = col.darkened(0.06)
			img.set_pixel(x, y, col)
	return img


## Turquoise pool mosaic: 2.5 cm tesserae, with a darker meander band near the top of the texture.
static func _mosaic() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var t := 8
	for y in n:
		for x in n:
			var cell := Vector2i(x / t, y / t)
			var h := fposmod(sin(float(cell.x * 31 + cell.y * 17) * 12.9898) * 43758.5453, 1.0)
			var col := Color(0.25 + h * 0.08, 0.68 + h * 0.08, 0.78 + h * 0.06)
			if x % t < 1 or y % t < 1:
				col = Color(0.85, 0.92, 0.92)
			img.set_pixel(x, y, col)
	return img


## A painted sky (the indoor pool's ceiling): blue fading to white with soft clouds.
static func _sky() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 44
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var c := Color(0.62, 0.78, 0.92)
			var v := clampf(noise.get_noise_2d(x, y) * 1.6 + 0.1, 0.0, 1.0)
			c = c.lerp(Color(0.98, 0.97, 0.94), v)
			img.set_pixel(x, y, c)
	return img


## Vertical oak slats with dark gaps (the master bedroom's wall), 4 cm slats every 6 cm.
static func _wood_slats() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for x in n:
		var k := x % 13
		for y in n:
			var col := Color("#c9a77a")
			col = _shade(col, sin(float(y) * 0.08 + float(x / 13) * 2.0) * 0.03)
			if k < 4:
				col = Color("#3b2a1c")
			img.set_pixel(x, y, col)
	return img


## Louvred shutters: slanted slats every 6 cm.
static func _louvres() -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var t := float(y % 13) / 13.0
		var s := 0.06 if t < 0.55 else -0.08
		for x in n:
			img.set_pixel(x, y, _shade(Color("#c3cbcb"), s))
	return img


## Foliage (box balls, hedges, the climbing plants): leaf blobs in greens.
static func _leafy(base: Color, seed: int) -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	img.fill(base.darkened(0.45))
	for i in 2600:
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randf_range(2.0, 5.0)
		var c := _shade(base, rng.randf_range(-0.1, 0.12))
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx * dx * 1.8 + dy * dy <= r * r:
					img.set_pixel((cx + dx + n) % n, (cy + dy + n) % n, c.darkened(0.15 * float(dy + ri) / (2 * ri)))
	return img


## A sectional garage door's oak panels: horizontal boards with grooves (the texture spans its height, 2.55 m).
static func _panels() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var k := y % 51
		for x in n:
			var c := _shade(Color("#7a5a3c"), sin(float(x) * 0.07 + float(y / 51) * 1.7) * 0.025)
			if k < 3:
				c = Color("#3e2b1b")
			elif k % 17 == 0:
				c = c.darkened(0.2)
			img.set_pixel(x, y, c)
	return img


static func _paint(n: int, f: Callable) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, f.call(x, y))
	return img


## Photovoltaic panels: dark blue cells in a lighter grid, an aluminium frame round each panel (128 x 64 px).
static func _solar() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	return _paint(256, func(x: int, y: int) -> Color:
		var px := x % 128
		var py := y % 64
		if px < 3 or px > 124 or py < 3 or py > 60:
			return Color("#b9bec4")
		if (px - 3) % 15 == 0 or (py - 3) % 15 == 0:
			return Color("#4f648a")
		return Color("#1c2a47").lightened(rng.randf() * 0.05))


## Metal cladding: panels 64 x 128 px, thin dark joints, each panel a shade of its own.
static func _cladding() -> Image:
	return _paint(256, func(x: int, y: int) -> Color:
		if x % 64 < 2 or y % 128 < 2:
			return Color(0.55, 0.56, 0.58)
		var k := (x / 64) * 7 + (y / 128) * 13
		return Color(0.93, 0.93, 0.94).darkened(float(k % 5) * 0.012))


## Brick in running bond: 64 x 21 px bricks, 3 px mortar.
static func _brick_bond() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var shades := []
	for k in 64:
		shades.append(Color("#a4573e").lightened(rng.randf_range(-0.12, 0.12)))
	return _paint(256, func(x: int, y: int) -> Color:
		var row := y / 21
		var bx := x + (32 if row % 2 == 1 else 0)
		if y % 21 < 3 or bx % 64 < 3:
			return Color("#cfc6b8")
		return shades[(row * 5 + bx / 64) % 64])


## Wooden boards, vertical: 32 px wide, grain along them.
static func _boards() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var tone := []
	for k in 8:
		tone.append(Color("#b38a5c").lightened(rng.randf_range(-0.1, 0.1)))
	return _paint(256, func(x: int, y: int) -> Color:
		if x % 32 < 2:
			return Color("#5e4630")
		var c: Color = tone[x / 32]
		return c.darkened(0.06 * (0.5 + 0.5 * sin(float(y) * 0.11 + float(x % 32) * 0.7))))
