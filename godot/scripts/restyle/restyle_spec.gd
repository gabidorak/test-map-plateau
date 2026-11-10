extends RefCounted
## Restyled buildings' specs (data/restyle/<slug>.json, made by tools/restyle.py: the method is that tool's help), the
## shared library (data/restyle/_library.json: materials, style presets) and geometry helpers. The building and its
## grounds are made by restyle_building.gd, set in the world by restyle.gd.
##
## A spec: "rings" the footprint (map x east, y north: the outer ring, then its courtyards; none: grounds only);
## "roof" the map's roof (points, triangles, "colour" a material); "height" from the ground floor to the roof's top;
## "storeys" their heights from the ground floor up (the rest up to "height" is the attic); "materials" its own
## (as the library's); "style":
##   preset   a style of the library (data/restyle/_library.json "styles") under this one's keys (presets nest)
##   fill     per storey (the last one goes on), a type or {"type", any style key for that storey}: "open" a
##            gallery, a préau (the glass "gallery" m behind the facade line), "curtain" glass "inset" m behind it
##            (mullions every "mullion" m), "louvres" a curtain with brise-soleil in the frame's bays ("louvres":
##            {"colour", "every", "clear"}), "fins" a curtain behind vertical fins ("fins": {"every", "depth",
##            "width", "material"}), "punched" a wall on the line, windows with reveals ("punched": {"w", "sill",
##            "head", "reveal"}); a new type is a method _fill_<type>(i, xf, L, k)
##   bay      m between the frame's posts and between punched windows
##   frame    {"colour", "post": [width, depth]}: an exoskeleton of posts on the facade line; {} none
##   ledge    m the floors' edges stand out of the facade line (white rings, balconies); "brim" the roof's
##   skin     {"gap", "every", "blade", "width", "material", "from"}: a second skin of vertical blades round the
##            outer ring, "gap" m out, from storey "from" to over the roof
##   band     true: a band at each floor between punched storeys ("band_colour")
##   glass, wall, plinth, floor (the gallery's), slab (the floors' edges), mullions, attic: materials
## Materials: the kit's (scripts/villa/villa_kit.gd mat()), "#rrggbb", or the library's / the spec's "materials":
## {"colour", "metal", "rough", "specular", "alpha", "texture" (restyle_textures.gd or the kit's), "scale", "emit"}.
## "site": "area" the grounds' outline (map), "paths" the map's paths round it (drawn inside the area), "walks"
## raised walks ({"pts", "w", "lift", "colour"}: level with the ground floor by the building, "lift" m over the ground
## elsewhere).

const Kit = preload("res://scripts/villa/villa_kit.gd")
const Textures = preload("res://scripts/restyle/restyle_textures.gd")
const DIR := "res://data/restyle/"
const LIBRARY := "res://data/restyle/_library.json"

static var _specs: Array = []
static var _lib: Dictionary = {}


static func library() -> Dictionary:
	if _lib.is_empty():
		var l: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY)) if FileAccess.file_exists(LIBRARY) \
				else {}
		_lib = l if l is Dictionary else {}
		for k: String in ["materials", "styles"]:
			if not _lib.has(k):
				_lib[k] = {}
	return _lib


static func specs() -> Array:
	if _specs.is_empty() and DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".json") and not f.begins_with("_"):
				var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
				if s is Dictionary:
					s["slug"] = f.get_basename()
					s["style"] = style_of(s.get("style", {}))
					_specs.append(s)
	return _specs


## A style with its preset's keys under its own (nested presets; dictionaries merged one level down).
static func style_of(st: Dictionary) -> Dictionary:
	var out := {}
	var preset: Dictionary = library()["styles"].get(str(st.get("preset", "")), {})
	if preset.has("preset"):
		preset = style_of(preset)
	for src: Dictionary in [preset, st]:
		for key: String in src:
			if src[key] is Dictionary and out.get(key) is Dictionary:
				var merged: Dictionary = (out[key] as Dictionary).duplicate()
				merged.merge(src[key], true)
				out[key] = merged
			else:
				out[key] = src[key]
	return out


## The library's and spec s's materials, into the kit's (any style key may name them).
static func register_materials(s: Dictionary) -> void:
	var defs: Dictionary = (library()["materials"] as Dictionary).duplicate()
	defs.merge(s.get("materials", {}), true)
	for name: String in defs:
		if not Kit._mats.has(name):
			Kit._mats[name] = material(defs[name])


static func material(d: Dictionary) -> StandardMaterial3D:
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
		var img := Textures.make(str(d["texture"]))
		m.albedo_texture = ImageTexture.create_from_image(img) if img else Kit.texture(str(d["texture"]))
		var sc := float(d.get("scale", 1.0))
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(sc, sc, sc)
		m.uv1_triplanar_sharpness = 8.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if d.has("emit"):
		m.emission_enabled = true
		m.emission = Color.html(str(d["emit"]))
		m.emission_energy_multiplier = float(d.get("energy", 1.0))
	return m


static func poly(a: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for q: Array in a:
		p.append(Vector2(q[0], q[1]))
	return p


static func rings_of(s: Dictionary) -> Array:
	var out := []
	for r: Array in s.get("rings", []):
		out.append(poly(r))
	return out


## Whether map point p is on the building: in its outer ring, in none of its courtyards.
static func inside(rings: Array, p: Vector2) -> bool:
	if rings.is_empty() or not Geometry2D.is_point_in_polygon(p, rings[0]):
		return false
	for k in range(1, rings.size()):
		if Geometry2D.is_point_in_polygon(p, rings[k]):
			return false
	return true


## The walks' outlines (map), grown by `grow` m.
static func walk_polys(s: Dictionary, grow := 0.0) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for w: Dictionary in s.get("site", {}).get("walks", []):
		for q: PackedVector2Array in Geometry2D.offset_polyline(poly(w["pts"]), float(w.get("w", 2.0)) * 0.5 + grow):
			out.append(q)
	return out
