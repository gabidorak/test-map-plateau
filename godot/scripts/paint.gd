extends RefCounted
## Vehicle paint (PTA Online's repaints, ONLINE_MODE.md 4; car.gd set_paint): the colours a model can be painted in,
## by id ("" is its own colour), and the materials of a repainted model:
## - a car with real materials (blender/vehicles: build_car.py, import_car.py...): its "paint*" material covering the
##   most area (the body; a black roof or a carbon bonnet keep theirs) in the colour, clear coat kept;
## - a toy car painted from a palette texture (Kenney Car Kit, KayKit): the swatch its body samples (the saturated one
##   covering the most area) recoloured in a copy of the texture, its light-to-dark gradient kept;
## - the biplane, the horse and the jet-ski make their own materials and recolour them (their _repaint).
## Work vehicles (liveries come later), police cars, armed ones and the 1928 Mercedes (a collector's piece: its
## painted textures stay) can't be painted. Repainted materials are made once per model and colour, and shared.

const CAR := [
	["white", "Glacier white", Color(0.9, 0.91, 0.9)],
	["silver", "Silver", Color(0.62, 0.64, 0.66)],
	["graphite", "Graphite", Color(0.2, 0.21, 0.23)],
	["black", "Night black", Color(0.03, 0.03, 0.035)],
	["red", "Racing red", Color(0.66, 0.04, 0.05)],
	["orange", "Sunset orange", Color(0.93, 0.38, 0.05)],
	["yellow", "Taxi yellow", Color(0.96, 0.75, 0.08)],
	["green", "British green", Color(0.05, 0.29, 0.15)],
	["teal", "Lagoon teal", Color(0.0, 0.5, 0.5)],
	["sky", "Sky blue", Color(0.4, 0.62, 0.86)],
	["blue", "Royal blue", Color(0.07, 0.19, 0.6)],
	["violet", "Violet", Color(0.36, 0.12, 0.52)],
	["pink", "Flamingo pink", Color(0.95, 0.45, 0.65)],
	["gold", "Prestige gold", Color(0.85, 0.65, 0.24)],
]
const COATS := [
	["bay", "Bay", Color(0.4, 0.19, 0.08)],
	["black", "Black", Color(0.07, 0.06, 0.06)],
	["grey", "Dapple grey", Color(0.62, 0.62, 0.6)],
	["palomino", "Palomino", Color(0.87, 0.7, 0.42)],
	["dun", "Dun", Color(0.7, 0.56, 0.38)],
	["white", "White", Color(0.93, 0.91, 0.87)],
]
const UNPAINTED := ["bus-idfm", "bus-idfm-artic", "fire-truck", "police", "police-hatchback", "ambulance",
		"mercedes-1928", "biplane-armed", "biplane-gunner", "gaz-tiger"]
const SWATCH_STEP := 0.06                   # a palette texture's swatch: neighbouring texels closer than this

static var _bodies := {}                    # model -> what its body is painted with (_body_of)
static var _made := {}                      # "model/id" -> the repainted material


## [[id, label, Color]] `model` can be painted in ([] none: it keeps its own).
static func palette(model: String) -> Array:
	if model in UNPAINTED or not load("res://scripts/car.gd").SPECS.has(model):
		return []
	return COATS if model == "horse" else CAR


static func can_paint(model: String) -> bool:
	return not palette(model).is_empty()


## The colour of paint `id` for `model`, null for its own ("", or not in its palette).
static func colour(model: String, id: String) -> Variant:
	for p: Array in palette(model):
		if p[0] == id:
			return p[2]
	return null


## The label of paint `id` for `model` ("Racing red"; "" its own).
static func label(model: String, id: String) -> String:
	for p: Array in palette(model):
		if p[0] == id:
			return p[1]
	return ""


## Paints the meshes of `car` (car.gd, set up) in `c`, or back in their own colours (null).
static func repaint(car: Node3D, c: Variant) -> void:
	var body := _body_of(car)
	if body.is_empty():
		return
	var key := "%s/%s" % [car.model_name, (c as Color).to_html() if c != null else ""]
	if c != null and not _made.has(key):
		_made[key] = _material(body, c)
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(k) == body["material"]:
				mi.set_surface_override_material(k, _made[key] if c != null else null)


## What `car`'s body is painted with: {"material": its own (shared by the model's meshes), "atlas": [swatch (_swatch),
## reference colour] for a palette texture}, {} when nothing is.
static func _body_of(car: Node3D) -> Dictionary:
	var model: String = car.model_name
	if _bodies.has(model):
		return _bodies[model]
	var paint := {}                         # material -> area, the "paint*" ones
	var textured := {}                      # material -> {colour bin -> [area, texel]}, palette textures
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.mesh is ArrayMesh:
			continue
		var xf: Transform3D = car._in_frame(mi, car)
		for k in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(k) as BaseMaterial3D
			if mat == null:
				continue
			var named := mat.resource_name.begins_with("paint") and mat.albedo_texture == null
			var atlas := mat.albedo_texture != null and mat.resource_name in ["colormap", "citybits_texture"]
			if not named and not atlas:
				continue
			var arrays := mi.mesh.surface_get_arrays(k)
			var v: PackedVector3Array = xf * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ind.is_empty():
				ind = PackedInt32Array(range(v.size()))
			if named:
				for t in range(0, ind.size() - 2, 3):
					paint[mat] = paint.get(mat, 0.0) + (v[ind[t + 1]] - v[ind[t]]).cross(v[ind[t + 2]] - v[ind[t]]).length()
				continue
			var img := _image(mat.albedo_texture)
			var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if img == null or not uv is PackedVector2Array:
				continue
			var bins: Dictionary = textured.get_or_add(mat, {})
			for t in range(0, ind.size() - 2, 3):
				var mid: Vector2 = (uv[ind[t]] + uv[ind[t + 1]] + uv[ind[t + 2]]) / 3.0
				var px := _texel(img, mid)
				var col := img.get_pixelv(px)
				if col.s < 0.25 or col.v < 0.15:
					continue                    # greys: tyres, bumpers, glass, the underside
				var bin := "%d,%d,%d" % [roundi(col.h * 24.0), roundi(col.s * 4.0), roundi(col.v * 4.0)]
				var area := (v[ind[t + 1]] - v[ind[t]]).cross(v[ind[t + 2]] - v[ind[t]]).length()
				var b: Array = bins.get_or_add(bin, [0.0, px])
				b[0] += area
	var out := {}
	var best := 0.0
	for mat: BaseMaterial3D in paint:
		if paint[mat] > best:
			best = paint[mat]
			out = {"material": mat}
	if out.is_empty():
		for mat: BaseMaterial3D in textured:
			for bin: String in textured[mat]:
				var b: Array = textured[mat][bin]
				if b[0] > best:
					best = b[0]
					out = {"material": mat, "seed": b[1]}
		if not out.is_empty():
			var img := _image((out["material"] as BaseMaterial3D).albedo_texture)
			out["atlas"] = [_swatch(img, out["seed"]), img.get_pixelv(out["seed"])]
	_bodies[model] = out
	return out


## A copy of `body`'s material in colour `c`.
static func _material(body: Dictionary, c: Color) -> BaseMaterial3D:
	var m := (body["material"] as BaseMaterial3D).duplicate() as BaseMaterial3D
	if not body.has("atlas"):
		m.albedo_color = c
		return m
	var img := _image(m.albedo_texture).duplicate() as Image
	var region: Image = body["atlas"][0][0]
	var rect: Rect2i = body["atlas"][0][1]
	var ref_lum := maxf((body["atlas"][1] as Color).get_luminance(), 0.05)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if region.get_pixel(x, y).r > 0.5:
				var k := img.get_pixel(x, y).get_luminance() / ref_lum
				img.set_pixel(x, y, Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0)))
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m


## The swatch of palette texture `img` holding texel `seed`: the texels reached from it through neighbours closer than
## SWATCH_STEP (a swatch's gradient, up to the sharp edge of the next one): [white in an Image of the same size, their
## bounding Rect2i].
static func _swatch(img: Image, seed: Vector2i) -> Array:
	var size := img.get_size()
	var out := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var todo: Array[Vector2i] = [seed]
	var rect := Rect2i(seed, Vector2i.ONE)
	out.set_pixelv(seed, Color.WHITE)
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		var c := img.get_pixelv(p)
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q := p + d
			if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or out.get_pixelv(q).r > 0.5:
				continue
			var n := img.get_pixelv(q)
			if maxf(maxf(absf(n.r - c.r), absf(n.g - c.g)), absf(n.b - c.b)) < SWATCH_STEP:
				out.set_pixelv(q, Color.WHITE)
				rect = rect.expand(q)
				todo.append(q)
	return [out, Rect2i(rect.position, rect.size + Vector2i.ONE)]


static func _texel(img: Image, uv: Vector2) -> Vector2i:
	return Vector2i(int(fposmod(uv.x, 1.0) * img.get_width()), int(fposmod(uv.y, 1.0) * img.get_height())).clamp(
			Vector2i.ZERO, img.get_size() - Vector2i.ONE)


## The texture's image, decompressed, without mipmaps (null when it can't be read).
static func _image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	img = img.duplicate() as Image
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
