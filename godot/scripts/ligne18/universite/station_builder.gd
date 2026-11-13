extends "res://scripts/build_kit.gd"
## Université Paris-Saclay's station (lot ligne18-universite, universite_plan.gd), drawn in its frame at its hall's
## level (local (u, z - hall_z, -v): Plan.station_frame()), its levels the line's plan's (ligne18_plan.gd):
## - the deck over the station's zone (u -45..45): the line's section (the spine and its walkway, the slab, its edges,
##   the soffit) its top at deck_top_z, its end faces at u = +-45 the section exactly (the viaduct's spans meet them);
##   no rails (the viaduct's lot lays the tracks on it); its edge fascias and, out of the building, its parapets (the
##   viaduct's: light concrete with a faint mottle, the fascia to |v| 4.945, posts at |v| 4.80);
## - its supports: at each end the cross-beam on two elliptic shafts the viaduct's first span and the deck rest on (its
##   top at rail_z - 1.78 - 0.30, the bearings on it), and in the hall two single piers with flared heads;
## - the hall at the ground (hall_z), its glazed ends under the deck (west to rue Sophie Germain, east to rue Nicolas
##   Appert: their doors at |v| < 5) and its south door to the TCSP; the rooms on either side (white panels, ribbed
##   cladding above, shop windows);
## - on each side, the flights in the open zone by the hall: a stair and an escalator from the hall up to the
##   passerelle's landing (passerelle_z), on to the platform's floor (platform_z); the passerelle across the hall
##   under the deck; a glass lift; the platform (u -30..30, edge at |v| 4.00), its glass screens set 0.15 m back, the
##   floor behind it out to the envelope; benches and the station's name;
## - the envelope: on each long side nine folds of glass in white frames (their tips out at the top, down to the socle
##   at the bottom), the gables glazed over the tracks, the roof's triangles alternately glass and white panels with
##   their undersides in yellow slats, under roof_max_z.
## Collision: the deck, the supports, the floors (the hall, the passerelle, the platforms' floor), the flights (ramps),
## the walls but the doors, the screens and balustrades.

const Plan = preload("res://scripts/ligne18/universite/universite_plan.gd")
const L18 = preload("res://scripts/ligne18/ligne18_plan.gd")

const ROOMS_V := 13.0                       # |v|: the rooms beyond the flights' zone
const ZONE_U := Vector2(-12.0, 20.0)        # u: the flights' zone, open to the hall
const STAIR_V := Vector2(9.2, 11.2)         # |v|: the stairs
const ESC_V := Vector2(11.6, 12.7)          # |v|: the escalators
const LAND_U := Vector2(-2.0, 4.0)          # u: the passerelle and its landings
const WELL := Rect2(4.0, 9.0, 8.7, 3.9)     # (u, |v|): the opening in the platforms' floor over the upper flights
const LIFT := Rect2(15.0, 9.4, 2.5, 2.5)    # (u, |v|)
const PLATFORM_U := 30.0
const SCREEN_V := Vector2(4.15, 4.22)       # |v|: the platform screens (set back from the edge at 4.00)
const FOLD := 4.5                           # m between a fold's tip and the next notch, at the top
const FASCIA := Vector2(-0.95, -0.40)       # z over the rails of the deck's edge fascia (the viaduct's)
const PARAPET_V := 4.80                     # |v| of the parapets (the viaduct's)

var y_pass := 5.0
var y_rail := 9.35
var y_deck := 8.88
var y_plat := 10.4
var y_roof := 20.1
var y_soffit := 7.57
var y_support := 7.27
var edge_v := 4.0
var _built_mats := false


func _init() -> void:
	super("UniversiteStation", {"type": "lot", "lot": "ligne18-universite", "name": "Gare Université Paris-Saclay",
			"about": "Line 18's station (ex Orsay-Gif): its hall, passerelle, platforms, envelope and deck"})
	var h := Plan.level("hall_z")
	y_pass = Plan.level("passerelle_z") - h
	y_rail = Plan.level("rail_z") - h
	y_deck = Plan.level("deck_top_z") - h
	y_plat = Plan.level("platform_z") - h
	y_roof = Plan.level("roof_max_z") - h
	y_soffit = y_rail - L18.SOFFIT_UNDER_RAIL
	y_support = y_soffit - L18.BEARING
	edge_v = L18.PLATFORM_EDGE_V
	_materials()


## The station, committed: a node at the station's frame (meshes only when `meshes`: none headless).
func build(meshes: bool) -> Node3D:
	_deck()
	_supports()
	_hall()
	_socle()
	_passerelle()
	for s: float in [-1.0, 1.0]:
		_flights(s)
		_lift(s)
		_platform(s)
		_envelope(s)
	for su: float in [-1.0, 1.0]:
		_gable(su)
	_roof()
	_labels()
	_totems()
	for u: float in [-24.0, -8.0, 8.0, 24.0]:                # the hall's lights
		light(P(u, 6.2, 0.0), Color(1.0, 0.95, 0.86), 1.4, 16.0)
	var n := commit(meshes)
	n.transform = Plan.station_frame()
	return n


# ---------------------------------------------------------------- helpers

## Local point (u, y over the hall, v).
static func P(u: float, y: float, v: float) -> Vector3:
	return Vector3(u, y, -v)


## A box over u0..u1, y0..y1, v0..v1 (material m: none if ""), and its collision when `solid`.
func bx(m: String, u0: float, u1: float, y0: float, y1: float, v0: float, v1: float, solid := false) -> void:
	if m != "":
		box(m, minf(u0, u1), maxf(u0, u1), minf(y0, y1), maxf(y0, y1), -maxf(v0, v1), -minf(v0, v1))
	if solid:
		col(minf(u0, u1), maxf(u0, u1), minf(y0, y1), maxf(y0, y1), -maxf(v0, v1), -minf(v0, v1))


## A slab: its top in `top_m`, its underside and edges in `side_m`; solid.
func slab(top_m: String, side_m: String, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	var a := minf(v0, v1)
	var b := maxf(v0, v1)
	quad(top_m, P(u0, y1, a), P(u1, y1, a), P(u1, y1, b), P(u0, y1, b), Vector3.UP)
	quad(side_m, P(u0, y0, a), P(u1, y0, a), P(u1, y0, b), P(u0, y0, b), Vector3.DOWN)
	quad(side_m, P(u0, y0, a), P(u1, y0, a), P(u1, y1, a), P(u0, y1, a), Vector3(0, 0, 1))
	quad(side_m, P(u0, y0, b), P(u1, y0, b), P(u1, y1, b), P(u0, y1, b), Vector3(0, 0, -1))
	quad(side_m, P(u0, y0, a), P(u0, y0, b), P(u0, y1, b), P(u0, y1, a), Vector3(-1, 0, 0))
	quad(side_m, P(u1, y0, a), P(u1, y0, b), P(u1, y1, b), P(u1, y1, a), Vector3(1, 0, 0))
	bx("", u0, u1, y0, y1, a, b, true)


## An elliptic shaft (half sizes ru along u, rv across) from y0, h high, its top scaled by `top`.
func shaft(m: String, u: float, v: float, ru: float, rv: float, y0: float, h: float, top := 1.0, seg := 20) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = 1.0
	c.top_radius = top
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	tool(m).append_from(c, 0, Transform3D(Basis.from_scale(Vector3(ru, 1.0, rv)), P(u, y0 + h * 0.5, v)))


## A glass panel between two points at the ground of it (a, b: (u, v)), from y0 to y1, facing `n`.
func pane(m: String, a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var d := (b - a).normalized()
	quad(m, P(a.x, y0, a.y), P(b.x, y0, b.y), P(b.x, y1, b.y), P(a.x, y1, a.y), Vector3(-d.y, 0.0, -d.x))


## A balustrade from a to b ((u, v), y0 the floor): glass, a steel handrail; solid.
func balustrade(a: Vector2, b: Vector2, y0: float, h := 1.1) -> void:
	pane("glass", a, b, y0 + 0.05, y0 + h - 0.05)
	rod("steel", P(a.x, y0 + h, a.y), P(b.x, y0 + h, b.y), 0.03, 6)
	var c := (a + b) * 0.5
	var d := b - a
	col_xf(Transform3D(Basis(Vector3.UP, atan2(d.y, d.x)), P(c.x, y0 + h * 0.5, c.y)), Vector3(d.length(), h, 0.08))


## A face (a polygon of local points, convex or not, in a plane) facing `n`.
func face_poly(m: String, pts: PackedVector3Array, n: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		tri(m, pts[0], pts[i], pts[i + 1], n)


## The deck's soffit's y at |v| (the line's section).
func soffit_at(v: float) -> float:
	var a := absf(v)
	if a <= 1.6:
		return y_rail - 1.78
	return lerpf(y_rail - 1.78, y_rail - 0.87, clampf((a - 1.6) / (L18.DECK_HALF - 1.6), 0.0, 1.0))


# ---------------------------------------------------------------- materials

func _materials() -> void:
	if not _mats.has("l18_concrete"):                          # (the viaduct's: light concrete, a faint mottle)
		for e: Array in [["l18_concrete", "#d7d6d0"], ["l18_fascia", "#dddcd6"]]:
			var c := StandardMaterial3D.new()
			c.albedo_color = Color(str(e[1]))
			c.roughness = 0.88
			c.albedo_texture = _mottle()
			c.uv1_triplanar = true
			c.uv1_world_triplanar = true
			c.uv1_scale = Vector3.ONE / 9.0
			add_material(e[0], c)
	add_material("l18_white", plain(Color("#f1f0eb"), 0.5))
	add_material("l18_floor", plain(Color("#cfcdc8"), 0.7))
	add_material("l18_ceiling", plain(Color("#e9e8e3"), 0.9))
	add_material("l18_tactile", plain(Color("#ece6cf"), 0.8))
	add_material("l18_roofwhite", plain(Color("#f3f3ef"), 0.6))
	add_material("l18_screen", plain(Color("#23272b"), 0.4))
	add_material("l18_clad", material_from({"colour": "#dcdddb", "texture": "cladding", "scale": 0.35, "rough": 0.55,
			"metal": 0.15}))
	add_material("l18_shop", material_from({"colour": "#33424c", "rough": 0.08, "specular": 0.8}))
	if not _mats.has("l18_envglass"):
		var g := StandardMaterial3D.new()
		g.albedo_texture = _stripes(64, Color(0.82, 0.9, 0.88, 0.32), Color(0.97, 0.98, 0.97, 0.9), 16, 3, false)
		g.albedo_color = Color.WHITE
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		g.roughness = 0.06
		g.metallic_specular = 0.8
		g.uv1_triplanar = true
		g.uv1_scale = Vector3(1.0 / 0.9, 1.0 / 0.9, 1.0 / 0.9)
		g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		add_material("l18_envglass", g)
	if not _mats.has("l18_yellow"):
		var y := StandardMaterial3D.new()
		y.albedo_texture = _stripes(64, Color("#e7bd3a"), Color("#6f5314"), 16, 5, true)
		y.roughness = 0.65
		y.uv1_triplanar = true
		y.uv1_scale = Vector3(1.0 / 0.32, 1.0 / 0.32, 1.0 / 0.32)
		y.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		add_material("l18_yellow", y)


## Concrete's faint mottle (a seamless noise, 0.93 .. 1.03: the viaduct's).
static func _mottle() -> Texture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = 18
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	var src := fn.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var g := 0.93 + 0.10 * src.get_pixel(x, y).r
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A striped texture n x n: `base`, a stripe of `line` every `every` px, `w` px wide (vertical stripes, or horizontal).
static func _stripes(n: int, base: Color, line: Color, every: int, w: int, vertical: bool) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			var k := i if vertical else j
			img.set_pixel(i, j, line if k % every < w else base)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- the deck and its supports

## The deck over the zone: the line's section from u -45 to 45, its ends capped; its parapets out of the building.
func _deck() -> void:
	var e := Plan.END_U
	var pts := PackedVector2Array()                          # (v, y)
	for q: Vector2 in L18.section():
		pts.append(Vector2(q.x, y_rail + q.y))
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var d := (b - a).normalized()
		var o := Vector2(-d.y, d.x)                          # (the outline goes clockwise: outward on its left)
		quad("l18_concrete", P(-e, a.y, a.x), P(e, a.y, a.x), P(e, b.y, b.x), P(-e, b.y, b.x), Vector3(0.0, o.y, -o.x))
	var idx := Geometry2D.triangulate_polygon(pts)
	for su: float in [-1.0, 1.0]:
		for i in range(0, idx.size(), 3):
			var t := [pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]
			tri("l18_concrete", P(su * e, t[0].y, t[0].x), P(su * e, t[1].y, t[1].x), P(su * e, t[2].y, t[2].x),
					Vector3(su, 0.0, 0.0))
	var hs := L18.half_section()                             # its collision: the spine, the two sides (convex)
	var sp := hs[1].x
	_prism(e, PackedVector2Array([Vector2(-sp, hs[0].y), Vector2(sp, hs[0].y), Vector2(sp, hs[6].y), Vector2(-sp, hs[6].y)]))
	for s: float in [-1.0, 1.0]:
		var side := PackedVector2Array()
		for q: Vector2 in [hs[2], hs[3], hs[4], hs[5], Vector2(sp, hs[5].y)]:
			side.append(Vector2(s * q.x, q.y))
		_prism(e, side)
		var f0 := s * L18.DECK_HALF                          # the edge fascia (the viaduct's: |v| 4.845..4.945)
		var f1 := s * L18.EDGE_HALF
		var fz := Vector2(y_rail + FASCIA.x, y_rail + FASCIA.y)
		quad("l18_fascia", P(-e, fz.x, f1), P(e, fz.x, f1), P(e, fz.y, f1), P(-e, fz.y, f1), Vector3(0, 0, -s))
		quad("l18_fascia", P(-e, fz.y, f0), P(e, fz.y, f0), P(e, fz.y, f1), P(-e, fz.y, f1), Vector3.UP)
		quad("l18_fascia", P(-e, fz.x, f0), P(e, fz.x, f0), P(e, fz.x, f1), P(-e, fz.x, f1), Vector3.DOWN)
		quad("l18_fascia", P(-e, y_deck, f0), P(e, y_deck, f0), P(e, fz.y, f0), P(-e, fz.y, f0), Vector3(0, 0, s))
		quad("l18_fascia", P(-e, fz.x, f0), P(e, fz.x, f0), P(e, y_rail - 0.87, f0), P(-e, y_rail - 0.87, f0), Vector3(0, 0, s))
		for su: float in [-1.0, 1.0]:
			quad("l18_fascia", P(su * e, fz.x, f0), P(su * e, fz.x, f1), P(su * e, fz.y, f1), P(su * e, fz.y, f0),
					Vector3(su, 0, 0))
		for su: float in [-1.0, 1.0]:                        # the parapets out of the envelope
			var u0 := su * 32.3
			var u1 := su * e
			var v := s * PARAPET_V
			rod("steel", P(u0, y_deck + L18.PARAPET_H, v), P(u1, y_deck + L18.PARAPET_H, v), 0.035, 6)
			for k in 4:
				var y := y_deck + 0.35 + 0.28 * k
				rod("steel", P(u0, y, v), P(u1, y, v), 0.006, 3)
			var u := u0
			while absf(u) <= absf(u1) + 0.01:
				box("steel", u - 0.04, u + 0.04, y_deck, y_deck + L18.PARAPET_H, -v - 0.04, -v + 0.04)
				u += su * 1.5
			bx("", minf(u0, u1 - su * 0.1), maxf(u0, u1 - su * 0.1), y_deck, y_deck + L18.PARAPET_H, s * L18.DECK_HALF,
					s * (L18.DECK_HALF + 0.1), true)


## A convex prism from u -e to e over outline `vy` ((v, z over the rails) points): a collision shape.
func _prism(e: float, vy: PackedVector2Array) -> void:
	var pts := PackedVector3Array()
	for q in vy:
		for u: float in [-e, e]:
			pts.append(P(u, y_rail + q.y, q.x))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## The supports: at each end (u = +-45) the cross-beam on two elliptic shafts (the viaduct's double piers' own: 2.75 by
## 1.10 m, 3.50 m apart), its top at the soffit less the bearings, the bearings under the deck and the span's ends;
## the single piers with flared heads in the hall (u = +-15).
func _supports() -> void:
	var e := Plan.END_U
	var base := -1.5                                         # (into the ground)
	var beam0 := y_support - 1.3
	for su: float in [-1.0, 1.0]:
		var u := su * e
		for sv: float in [-1.0, 1.0]:
			shaft("l18_concrete", u, sv * 1.75, 1.375, 0.55, base, beam0 - base)
			shaft("l18_screen", u, sv * 1.75, 1.42, 0.6, beam0 - 0.55, 0.5)
			bx("", u - 1.375, u + 1.375, base, beam0, sv * 1.75 - 0.55, sv * 1.75 + 0.55, true)
		bx("l18_concrete", u - 1.2, u + 1.2, beam0, y_support, -3.6, 3.6, true)
		for du: float in [-0.65, 0.65]:
			for v: float in [-0.9, 0.9]:
				bx("l18_screen", u + du - 0.25, u + du + 0.25, y_support, y_soffit, v - 0.25, v + 0.25)
	for su: float in [-1.0, 1.0]:
		var u := su * Plan.PIER_U
		var head := y_soffit - 2.4
		shaft("l18_concrete", u, 0.0, 1.375, 0.75, base, head - base, 1.0, 24)
		shaft("l18_concrete", u, 0.0, 1.375, 0.75, head, y_soffit - head, 1.85, 24)
		bx("", u - 1.375, u + 1.375, base, y_soffit, -0.75, 0.75, true)


# ---------------------------------------------------------------- the hall and the socle

## The hall's floor, its glazed ends under the deck (doors at |v| < 5), the band over them up to the deck and the
## platforms' floor.
func _hall() -> void:
	var r := Plan.SOCLE
	slab("l18_floor", "l18_concrete", r.position.x, r.end.x, r.position.y, r.end.y, -0.3, 0.0)
	var hv := Plan.HALL_V
	for su: float in [-1.0, 1.0]:
		var u := su * r.end.x
		pane("glass_win", Vector2(u, -hv), Vector2(u, hv), 0.0, 7.4)
		var v := -hv
		while v <= hv + 0.01:                                # mullions
			bx("frame", u - 0.06, u + 0.06, 0.0, 7.4, v - 0.06, v + 0.06)
			v += 1.7
		for y: float in [3.0, 7.4]:
			bx("frame", u - 0.07, u + 0.07, y - 0.08, y + 0.08, -hv, hv)
		for sv: float in [-1.0, 1.0]:                        # (the doors at |v| < 5: open)
			bx("", u - 0.1, u + 0.1, 0.0, 7.4, sv * 5.0, sv * hv, true)
		bx("", u - 0.1, u + 0.1, 3.0, 7.4, -5.0, 5.0, true)
		var band := PackedVector2Array([Vector2(-hv, 7.4), Vector2(hv, 7.4), Vector2(hv, y_plat - 0.5),
				Vector2(L18.DECK_HALF, y_plat - 0.5), Vector2(L18.DECK_HALF, soffit_at(L18.DECK_HALF)),
				Vector2(1.6, y_soffit), Vector2(-1.6, y_soffit), Vector2(-L18.DECK_HALF, soffit_at(L18.DECK_HALF)),
				Vector2(-L18.DECK_HALF, y_plat - 0.5), Vector2(-hv, y_plat - 0.5)])   # up to the soffit, the floor
		var idx := Geometry2D.triangulate_polygon(band)
		for i in range(0, idx.size(), 3):
			var t := [band[idx[i]], band[idx[i + 1]], band[idx[i + 2]]]
			tri("l18_white", P(u + su * 0.02, t[0].y, t[0].x), P(u + su * 0.02, t[1].y, t[1].x),
					P(u + su * 0.02, t[2].y, t[2].x), Vector3(su, 0.0, 0.0))


## The socle round the hall: its long walls (white panels, ribbed cladding over them, shop windows; the south door),
## its ends beyond the hall (the station's name), the rooms' walls along the hall and round the flights' zone (white,
## with fins on the hall's side), the south door's passage.
func _socle() -> void:
	var r := Plan.SOCLE
	var t := 0.3
	for s: float in [-1.0, 1.0]:
		var v1 := s * r.end.y
		var v0 := s * (r.end.y - t)
		var door := s > 0.0
		for seg: Vector2 in ([Vector2(r.position.x, -3.0), Vector2(3.0, r.end.x)] if door else [Vector2(r.position.x, r.end.x)]):
			bx("l18_white", seg.x, seg.y, 0.0, 4.2, v0, v1, true)
		if door:
			bx("l18_white", -3.0, 3.0, 3.4, 4.2, v0, v1, true)
			pane("glass_win", Vector2(-3.0, v1 + s * 0.02), Vector2(3.0, v1 + s * 0.02), 3.4, 4.2)
		bx("l18_clad", r.position.x, r.end.x, 4.2, y_plat - 0.5, v0, v1, true)     # (the platforms' floor over it)
		for w: Vector2 in [Vector2(-27.0, -19.0), Vector2(-13.0, -6.0), Vector2(7.0, 14.0), Vector2(19.0, 27.0)]:
			var vv := v1 + s * 0.03
			if s > 0.0:                                          # (facing out)
				pane("l18_shop", Vector2(w.x, vv), Vector2(w.y, vv), 0.4, 3.6)
			else:
				pane("l18_shop", Vector2(w.y, vv), Vector2(w.x, vv), 0.4, 3.6)
			for u: float in [w.x, (w.x + w.y) * 0.5, w.y]:
				bx("frame", u - 0.06, u + 0.06, 0.4, 3.6, vv - s * 0.02, vv + s * 0.06)
			for y: float in [0.4, 3.6]:
				bx("frame", w.x, w.y, y - 0.06, y + 0.06, vv - s * 0.02, vv + s * 0.06)
		# the rooms along the hall, beyond the flights' zone, and round it
		var hv := s * Plan.HALL_V
		var rv := s * ROOMS_V
		for seg: Vector2 in [Vector2(r.position.x, ZONE_U.x), Vector2(ZONE_U.y, r.end.x)]:
			bx("l18_white", seg.x, seg.y, 0.0, y_plat - 0.5, hv, hv + s * 0.2, true)
			var u := seg.x + 0.45
			while u < seg.y - 0.3:                               # the fins on the hall's side
				bx("l18_white", u - 0.03, u + 0.03, 0.0, y_plat - 0.5, hv - s * 0.32, hv)
				u += 0.9
		for u: float in [ZONE_U.x, ZONE_U.y]:
			bx("l18_white", u - 0.1, u + 0.1, 0.0, y_plat - 0.5, hv, rv, true)
		var segs := [Vector2(ZONE_U.x, -3.0), Vector2(3.0, ZONE_U.y)] if door else [Vector2(ZONE_U.x, ZONE_U.y)]
		for seg: Vector2 in segs:
			bx("l18_white", seg.x, seg.y, 0.0, y_plat - 0.5, rv, rv + s * 0.2, true)
		if door:                                                 # the passage from the south door
			bx("l18_white", -3.0, 3.0, 4.0, y_plat - 0.5, rv, rv + s * 0.2, true)
			for u: float in [-3.1, 3.1]:
				bx("l18_white", u - 0.1, u + 0.1, 0.0, 4.0, rv + s * 0.2, v0, true)
			slab("l18_ceiling", "l18_ceiling", -3.2, 3.2, rv + s * 0.2, v0, 4.0, 4.2)
	for su: float in [-1.0, 1.0]:                                # the socle's ends beyond the hall
		var u := su * r.end.x
		for s: float in [-1.0, 1.0]:
			bx("l18_white", u - su * t, u, 0.0, y_plat - 0.5, s * Plan.HALL_V, s * r.end.y, true)


# ---------------------------------------------------------------- the passerelle, the flights, the lifts

## The passerelle across the hall under the deck and its landings on either side (passerelle_z), balustrades along it.
func _passerelle() -> void:
	var y := y_pass
	slab("l18_floor", "l18_ceiling", LAND_U.x, LAND_U.y, -ROOMS_V, ROOMS_V, y - 0.45, y)
	for u: float in [LAND_U.x, LAND_U.y]:
		balustrade(Vector2(u, -Plan.HALL_V), Vector2(u, Plan.HALL_V), y)
		for s: float in [-1.0, 1.0]:                             # (the flights arrive between)
			balustrade(Vector2(u, s * Plan.HALL_V), Vector2(u, s * STAIR_V.x), y)
			balustrade(Vector2(u, s * ESC_V.y), Vector2(u, s * ROOMS_V), y)

## A side's flights: from the hall up to the landing (a stair, an escalator beside it), from the landing up to the
## platforms' floor; their balustrades.
func _flights(s: float) -> void:
	var run_a := 0.32 * 24.0
	_stair(s, LAND_U.x - run_a, 0.0, LAND_U.x, y_pass, 25)
	_escalator(s, LAND_U.x - run_a, 0.0, LAND_U.x, y_pass)
	var run_b := WELL.end.x - LAND_U.y
	_stair(s, LAND_U.y, y_pass, WELL.end.x, y_plat, 30)
	_escalator(s, LAND_U.y, y_pass, WELL.end.x, y_plat)


## A stair along +u from (u0, y0) to (u1, y1), n risers, at |v| STAIR_V on side s: its steps, its soffit and stringers,
## its balustrades; its ramp.
func _stair(s: float, u0: float, y0: float, u1: float, y1: float, n: int) -> void:
	var r := (y1 - y0) / n
	var t := (u1 - u0) / (n - 1)
	var va := s * STAIR_V.x
	var vb := s * STAIR_V.y
	for k in n - 1:
		var top := y0 + (k + 1) * r
		bx("l18_floor", u0 + k * t, u0 + (k + 1) * t, top - r - 0.04, top, va, vb)
	var d := Vector2(u1 - u0, y1 - y0).normalized()
	var under := Vector2(d.y, -d.x) * 0.25
	quad("l18_ceiling", P(u0 + under.x, y0 + under.y, va), P(u1 + under.x, y1 + under.y, va),
			P(u1 + under.x, y1 + under.y, vb), P(u0 + under.x, y0 + under.y, vb), Vector3(0, -1, 0))
	for v: float in [va - s * 0.06, vb + s * 0.06]:              # the stringers
		var sp := PackedVector3Array([P(u0, y0 - 0.3, v), P(u1, y1 - 0.3, v), P(u1, y1 + 0.2, v), P(u0, y0 + r + 0.2, v)])
		face_poly("l18_white", sp, Vector3(0, 0, -signf(v - (va + vb) * 0.5)))
	var vm := (va + vb) * 0.5
	col_ramp(P(u0 - 0.2, y0, vm), P(u1, y1, vm), absf(vb - va))
	_rail_along(s, u0, y0, u1, y1, absf(va) - 0.08)              # (the hall's side)


## An escalator beside the stair (|v| ESC_V), from (u0, y0) to (u1, y1): its steps' slope between flat ends, its
## glass sides and black handrails; walkable (a ramp).
func _escalator(s: float, u0: float, y0: float, u1: float, y1: float) -> void:
	var va := s * ESC_V.x
	var vb := s * ESC_V.y
	var a := Vector3(u0 + 1.0, y0, 0.0)
	var b := Vector3(u1 - 1.0, y1, 0.0)
	for q: Array in [[Vector3(u0 - 0.2, y0, 0), a], [a, b], [b, Vector3(u1, y1, 0)]]:
		var p: Vector3 = q[0]
		var e: Vector3 = q[1]
		quad("l18_screen", P(p.x, p.y + 0.02, va), P(e.x, e.y + 0.02, va), P(e.x, e.y + 0.02, vb), P(p.x, p.y + 0.02, vb),
				Vector3.UP)
		for v: float in [va, vb]:
			var sp := PackedVector3Array([P(p.x, p.y - 0.4, v), P(e.x, e.y - 0.4, v), P(e.x, e.y + 0.95, v), P(p.x, p.y + 0.95, v)])
			face_poly("glass", sp, Vector3(0, 0, 1))
			rod("black", P(p.x, p.y + 0.98, v), P(e.x, e.y + 0.98, v), 0.045, 6)
	quad("l18_white", P(u0 - 0.2, y0 - 0.45, va), P(u1, y1 - 0.45, va), P(u1, y1 - 0.45, vb), P(u0 - 0.2, y0 - 0.45, vb),
			Vector3.DOWN)
	col_ramp(P(u0 - 0.2, y0, (va + vb) * 0.5), P(u1, y1, (va + vb) * 0.5), absf(vb - va))
	_rail_along(s, u0, y0, u1, y1, absf(vb) + 0.1)               # (the rooms' side)


## A balustrade along a flight at |v| `av` (side s): glass, a handrail; solid (a sloping wall).
func _rail_along(s: float, u0: float, y0: float, u1: float, y1: float, av: float) -> void:
	var v := s * av
	var sp := PackedVector3Array([P(u0, y0 + 0.1, v), P(u1, y1 + 0.1, v), P(u1, y1 + 1.0, v), P(u0, y0 + 1.0, v)])
	face_poly("glass", sp, Vector3(0, 0, 1))
	rod("steel", P(u0, y0 + 1.05, v), P(u1, y1 + 1.05, v), 0.03, 6)
	var d := Vector3(u1 - u0, y1 - y0, 0.0)
	var along := d.normalized()
	var basis := Basis(along, Vector3(-along.y, along.x, 0.0), Vector3(0, 0, 1))
	col_xf(Transform3D(basis, P((u0 + u1) * 0.5, (y0 + y1) * 0.5 + 0.6, v)), Vector3(d.length(), 1.2, 0.08))


## A side's glass lift from the hall to above the platforms' floor.
func _lift(s: float) -> void:
	var r := LIFT
	var va := s * r.position.y
	var vb := s * r.end.y
	var top := y_plat + 2.8
	for e: Array in [[Vector2(r.position.x, va), Vector2(r.end.x, va)], [Vector2(r.end.x, va), Vector2(r.end.x, vb)],
			[Vector2(r.end.x, vb), Vector2(r.position.x, vb)], [Vector2(r.position.x, vb), Vector2(r.position.x, va)]]:
		pane("glass", e[0], e[1], 0.0, top)
	for u: float in [r.position.x, r.end.x]:
		for v: float in [va, vb]:
			bx("frame", u - 0.08, u + 0.08, 0.0, top, v - 0.08, v + 0.08)
	bx("frame", r.position.x, r.end.x, top, top + 0.25, va, vb)
	bx("l18_clad", r.position.x + 0.15, r.end.x - 0.15, 0.05, 2.45, va + s * 0.15, vb - s * 0.15)
	bx("", r.position.x, r.end.x, 0.0, top, va, vb, true)


# ---------------------------------------------------------------- the platforms

## A side's platform and the floor behind it out to the envelope (platform_z): the platform's edge on the deck, its
## white band, the screens set back from it (doors along u -30..30), the opening over the upper flights and its
## balustrades, the floor's edges; benches, the station's name.
func _platform(s: float) -> void:
	var e := 32.0
	var y := y_plat
	var dv := L18.DECK_HALF
	var ev := s * edge_v
	slab("l18_floor", "l18_concrete", -e, e, ev, s * dv, y_deck, y)        # on the deck's edge
	quad("l18_tactile", P(-PLATFORM_U, y + 0.005, ev), P(PLATFORM_U, y + 0.005, ev),
			P(PLATFORM_U, y + 0.005, ev + s * 0.5), P(-PLATFORM_U, y + 0.005, ev + s * 0.5), Vector3.UP)
	var w := WELL
	var pieces := [[-e, w.position.x, dv, 16.0], [w.position.x, w.end.x, dv, w.position.y], [w.position.x, w.end.x, w.end.y, 16.0],
			[w.end.x, e, dv, 16.0]]
	for p: Array in pieces:
		slab("l18_floor", "l18_ceiling", p[0], p[1], s * float(p[2]), s * float(p[3]), y - 0.5, y)
	# the screens: glass, black posts, the header over the doors
	var sv := SCREEN_V
	var u := -e
	while u < e - 0.01:
		var u1 := minf(u + 1.6, e)
		pane("glass", Vector2(u, s * sv.x), Vector2(u1, s * sv.x), y, y + 2.2)
		bx("l18_screen", u - 0.04, u + 0.04, y, y + 2.2, s * sv.x, s * sv.y)
		u = u1
	bx("l18_screen", -PLATFORM_U, PLATFORM_U, y + 2.2, y + 2.75, s * (sv.x - 0.05), s * (sv.y + 0.25))
	bx("", -e, e, y, y + 2.2, s * sv.x, s * sv.y, true)
	# the well over the upper flights: balustrades on three sides
	balustrade(Vector2(w.position.x, s * w.position.y), Vector2(w.end.x, s * w.position.y), y)
	balustrade(Vector2(w.position.x, s * w.end.y), Vector2(w.end.x, s * w.end.y), y)
	balustrade(Vector2(w.position.x, s * w.position.y), Vector2(w.position.x, s * w.end.y), y)
	# the floor's edges: along the envelope, at the gables
	bx("l18_white", -e, e, y, y + 0.35, s * 16.0, s * 16.6, true)
	bx("", -e, e, y, y + 1.2, s * 16.0, s * 16.3, true)
	for su: float in [-1.0, 1.0]:
		balustrade(Vector2(su * e, ev), Vector2(su * e, s * 16.0), y)
	# benches (facing the track) and the name boards
	for bu: float in [-24.0, -9.0, 22.0]:
		var bv := s * 7.6
		bx("oak", bu - 1.0, bu + 1.0, y + 0.42, y + 0.47, bv - 0.22, bv + 0.22)
		bx("oak", bu - 1.0, bu + 1.0, y + 0.47, y + 0.9, bv + s * 0.2, bv + s * 0.25)
		for lu: float in [bu - 0.85, bu + 0.85]:
			bx("l18_screen", lu - 0.04, lu + 0.04, y, y + 0.42, bv - 0.2, bv + 0.2)
	for nu: float in [-16.0, 14.0]:
		var nv := s * 8.3
		bx("l18_screen", nu - 2.2, nu + 2.2, y + 2.0, y + 2.9, nv - 0.04, nv + 0.04)
		for lu: float in [nu - 1.8, nu + 1.8]:
			bx("l18_screen", lu - 0.05, lu + 0.05, y, y + 2.0, nv - 0.05, nv + 0.05)
		var xf := Transform3D(Basis(Vector3.UP, PI if s < 0.0 else 0.0), P(nu, y + 2.45, nv - s * 0.06))
		label("Université Paris-Saclay", xf, 64, 0.0075, Color("#f2f2f2"), false)


# ---------------------------------------------------------------- the envelope

## The top edge's points on side s (j 0..16): the notches (in, lower) and the tips (out, higher), FOLD m apart.
func _top(s: float, j: int) -> Vector3:
	var u := -Plan.ROOF_U + FOLD * j
	if j % 2 == 0:
		return P(u, y_roof - 0.9, s * 17.4)
	return P(u, y_roof, s * Plan.ROOF_V)


## A side's folded glass wall: under each tip a fold down to the socle (its point at 6.8 m), raised between them to the
## platforms' floor; white frames along every fold.
func _envelope(s: float) -> void:
	var rs := []                                             # the raised points (under the notches)
	for k in 9:
		var u := -Plan.ROOF_U + 9.0 * k
		u = clampf(u, -32.3, 32.3)
		rs.append(P(u, y_plat, s * 16.5))
	var bs := []                                             # the folds' bottom points (under the tips)
	for k in 8:
		bs.append(P(-Plan.ROOF_U + 4.5 + 9.0 * k, 6.8, s * 16.05))
	for k in 8:
		var na := _top(s, 2 * k)
		var tt := _top(s, 2 * k + 1)
		var nb := _top(s, 2 * k + 2)
		var ra: Vector3 = rs[k]
		var rb: Vector3 = rs[k + 1]
		var b: Vector3 = bs[k]
		for t: Array in [[na, tt, b], [tt, nb, b], [ra, na, b], [nb, rb, b]]:
			var t0: Vector3 = t[0]
			var n := ((t[1] as Vector3) - t0).cross((t[2] as Vector3) - t0).normalized()
			if n.z * -s < 0.0:
				n = -n
			tri("l18_envglass", t[0], t[1], t[2], n)
		for l: Array in [[na, tt], [tt, nb], [tt, b], [na, b], [nb, b], [ra, b], [b, rb], [ra, na]]:
			rod("frame", l[0], l[1], 0.13, 6)
	rod("frame", rs[8], _top(s, 16), 0.13, 6)


## A gable (su: +1 west, -1 east): glass from the platforms' floor (at u +-32.3) leaning out to the roof's end (u +-36),
## open over the tracks; its frames.
func _gable(su: float) -> void:
	var ytop := func(v: float) -> float: return y_roof - 0.9 + 0.9 * (1.0 - absf(v) / 17.4)
	var at := func(v: float, y: float) -> Vector3:
		var f := clampf((y - y_plat) / (float(ytop.call(v)) - y_plat), 0.0, 1.0)
		return P(su * (32.3 + (Plan.ROOF_U - 32.3) * f), y, v)
	var open := 4.4
	var y_open := y_rail + 4.6
	var poly := PackedVector2Array([Vector2(-16.5, y_plat), Vector2(-open, y_plat), Vector2(-open, y_open),
			Vector2(open, y_open), Vector2(open, y_plat), Vector2(16.5, y_plat), Vector2(17.4, y_roof - 0.9),
			Vector2(0.0, y_roof), Vector2(-17.4, y_roof - 0.9)])
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a: Vector3 = at.call(poly[idx[i]].x, poly[idx[i]].y)
		var b: Vector3 = at.call(poly[idx[i + 1]].x, poly[idx[i + 1]].y)
		var c: Vector3 = at.call(poly[idx[i + 2]].x, poly[idx[i + 2]].y)
		tri("l18_envglass", a, b, c, Vector3(su, 0.2, 0.0).normalized())
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		rod("frame", at.call(p.x, p.y), at.call(q.x, q.y), 0.12, 6)
	for v: float in [-12.5, -8.5, 8.5, 12.5]:
		rod("frame", at.call(v, y_plat), at.call(v, float(ytop.call(v))), 0.09, 6)
	rod("frame", at.call(-open, y_open), at.call(open, y_open), 0.12, 6)
	rod("frame", at.call(-open, y_open), at.call(0.0, y_roof), 0.09, 6)
	rod("frame", at.call(open, y_open), at.call(0.0, y_roof), 0.09, 6)


## The roof: from each side's top edge to the ridge on the axis, triangles alternately glazed and of white panels with
## yellow slats under them; white members along its folds.
func _roof() -> void:
	var axis := func(j: int) -> Vector3:
		return P(-Plan.ROOF_U + FOLD * j, y_roof if j % 2 == 0 else y_roof - 0.6, 0.0)
	for s: float in [-1.0, 1.0]:
		for j in 16:
			var t0 := _top(s, j)
			var t1 := _top(s, j + 1)
			var a0: Vector3 = axis.call(j)
			var a1: Vector3 = axis.call(j + 1)
			var tris := [[t0, t1, a1], [t0, a1, a0]]
			for k in 2:
				var t: Array = tris[k]
				var slats := (j + k) % 2 == 0
				var c0: Vector3 = t[0]
				var n := ((t[1] as Vector3) - c0).cross((t[2] as Vector3) - c0).normalized()
				if n.y < 0.0:
					n = -n
				if slats:
					tri("l18_roofwhite", t[0], t[1], t[2], n)
					var dn := Vector3(0, -0.14, 0)
					tri("l18_yellow", (t[0] as Vector3) + dn, (t[1] as Vector3) + dn, (t[2] as Vector3) + dn, -n)
				else:
					tri("glass", t[0], t[1], t[2], n)
			rod("frame", t0, a0, 0.1, 6)
			rod("frame", t0, a1, 0.08, 6)
		rod("frame", _top(s, 16), axis.call(16), 0.1, 6)
	for j in 16:
		rod("frame", axis.call(j), axis.call(j + 1), 0.12, 6)


# ---------------------------------------------------------------- the name

## The line's totems at the accesses (west, east, south): a dark slab, the « M » and the line's number on it.
func _totems() -> void:
	for t: Array in [[Vector2(37.0, -5.6), 1.0], [Vector2(-37.0, 5.6), -1.0], [Vector2(6.0, 19.0), 0.0]]:
		var p: Vector2 = t[0]
		var face := float(t[1])
		var yaw := PI * 0.5 * face if face != 0.0 else PI
		var b := Basis(Vector3.UP, yaw)
		box_xf("l18_screen", Transform3D(b, P(p.x, 1.75, p.y)), Vector3(0.5, 3.5, 0.18))
		var xf := Transform3D(b, P(p.x, 2.85, p.y) + b * Vector3(0.0, 0.0, 0.1))
		label("M\n18", xf, 96, 0.006, Color("#f4f4f2"), false)
		col_xf(Transform3D(b, P(p.x, 1.75, p.y)), Vector3(0.5, 3.5, 0.18))


func _labels() -> void:
	var r := Plan.SOCLE
	for su: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			var xf := Transform3D(Basis(Vector3.UP, su * PI * 0.5), P(su * (r.end.x + 0.03), 6.6, s * 12.2))
			label("Université\nParis-Saclay", xf, 96, 0.0085, Color("#3a3f44"), true)
	var xf := Transform3D(Basis(Vector3.UP, PI), P(0.0, 5.2, r.end.y + 0.03))
	label("Université Paris-Saclay", xf, 96, 0.0085, Color("#3a3f44"), true)
	var xn := Transform3D(Basis.IDENTITY, P(0.0, 5.2, -r.end.y - 0.03))
	label("Université Paris-Saclay", xn, 96, 0.0085, Color("#3a3f44"), true)
