extends "res://scripts/street_kit.gd"
## Lot ligne18-polytechnique's grounds drawn (polytechnique_plan.gd: in the streets' grid, local (a, b), on its
## designed ground): the surfaces KERB high (the TCSP's kerb top, the strip paved at its openings, the two-way cycle
## track, the sidewalk, the forecourt's slabs, the esplanade, the paths, the west street's sidewalks), lowered at the
## crossings; their faces down to the lawns and beds; the granite kerb along the TCSP and round the west street, its
## gutter; the west street's asphalt and turning circle; the markings (the cycle track's centre line and bicycles, the
## west street's centre line and zebra). Surfaces cut in EDGE m triangles (they follow the eased ground). Collision:
## the surfaces' tops and faces.

const Plan = preload("res://lots/ligne18-polytechnique/polytechnique_plan.gd")
const EDGE := 2.0                           # m: the surfaces' triangles at most
const MARK := 0.006                         # m: markings over the surface they are on
const BIKES := 40.0                         # m between two bicycles on the cycle track

var _raised: Array = []


func _init() -> void:
	super("Grounds", {"type": "lot", "lot": "ligne18-polytechnique", "name": "Gare Polytechnique: ses abords",
			"about": "its forecourt, esplanade, sidewalks, cycle track and the west street"}, Plan)
	if not _mats.has("l18p_parvis"):
		var m := StandardMaterial3D.new()                    # large light granite slabs (1.2 x 0.6 m)
		m.albedo_texture = ImageTexture.create_from_image(_slabs())
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / 4.8
		m.uv1_triplanar_sharpness = 8.0
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		add_material("l18p_parvis", m)


## The works, committed: a node (meshes only when `meshes`).
func build(meshes: bool) -> Node3D:
	_raised = Plan.surfaces().map(func(e: Array) -> PackedVector2Array: return e[0])
	for e: Array in Plan.surfaces():
		_surface(e[0], e[1])
	_road()
	_kerbs()
	_marks()
	return commit(meshes)


## A surface over polygon `poly` (material m), lift(p) over the ground; its faces down where what is next to it is
## lower (a lawn, a bed, the map's ground), none against the roads (the kerbs'), the station or another surface.
func _surface(poly: PackedVector2Array, m: String) -> void:
	var hs := {}
	var at := func(p: Vector2) -> Vector3:
		if not hs.has(p):
			hs[p] = Plan.lift(p)
		return p3(p.x, p.y, hs[p])
	var t := _fine(poly)
	for i in range(0, t.size(), 3):
		var a: Vector3 = at.call(t[i])
		var b: Vector3 = at.call(t[i + 1])
		var c: Vector3 = at.call(t[i + 2])
		tri(m, a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var u := poly[i]
		var v := poly[(i + 1) % poly.size()]
		var d := (v - u).normalized()
		var out := Vector2(-d.y, d.x) if cw else Vector2(d.y, -d.x)
		var n := maxi(1, ceili(u.distance_to(v) / EDGE))
		for j in n:
			var p := u.lerp(v, float(j) / n)
			var q := u.lerp(v, float(j + 1) / n)
			if not _open((p + q) * 0.5 + out * 0.08):
				continue
			var f := [p3(p.x, p.y, -0.05), p3(q.x, q.y, -0.05), at.call(q), at.call(p)]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(out))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))


## Whether local p next to a surface is lower ground (a lawn, a bed, the map's ground; not the avenue's sidewalk).
func _open(p: Vector2) -> bool:
	if Plan.in_station(p) or Plan.in_road(p) or Geometry2D.is_point_in_polygon(p, Plan.tcsp_side()):
		return false
	if p.x > Plan.EAST_EDGE.x + Plan.EAST_EDGE.y * p.y - 0.3 or p.y > Plan.NORTH_B + 0.2:
		return false
	for q: PackedVector2Array in _raised:
		if Plan.inside(p, q):
			return false
	return true


## Polygon `poly`'s triangles (flat array of their corners), cut until no side is longer than EDGE.
static func _fine(poly: PackedVector2Array) -> PackedVector2Array:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("polytechnique grounds: a polygon of %d points not triangulated" % poly.size())
	var todo := []
	for i in range(0, idx.size(), 3):
		todo.append([poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]])
	var out := PackedVector2Array()
	var lim := EDGE * EDGE
	while not todo.is_empty():
		var t: Array = todo.pop_back()
		var best := -1
		var longest := lim
		for k in 3:
			var l := (t[k] as Vector2).distance_squared_to(t[(k + 1) % 3])
			if l > longest:
				longest = l
				best = k
		if best < 0:
			out.append_array(PackedVector2Array(t))
			continue
		var a: Vector2 = t[best]
		var b: Vector2 = t[(best + 1) % 3]
		var c: Vector2 = t[(best + 2) % 3]
		var mid := (a + b) * 0.5
		todo.append([a, mid, c])
		todo.append([mid, b, c])
	return out


## The west street's asphalt and turning circle, ASPHALT_UP over the ground.
func _road() -> void:
	var t := _fine(Plan.road())
	for i in range(0, t.size(), 3):
		tri("street_asphalt", p3(t[i].x, t[i].y, ASPHALT_UP), p3(t[i + 1].x, t[i + 1].y, ASPHALT_UP),
				p3(t[i + 2].x, t[i + 2].y, ASPHALT_UP), Vector3.UP)


## The granite kerbs: along the TCSP (its face from the TCSP's asphalt up to the surfaces' top, the gutter on the
## TCSP), round the west street.
func _kerbs() -> void:
	var lines := []
	var k := PackedVector2Array(Plan.KERB_S)
	for i in k.size() - 1:
		lines.append([k[i], k[i + 1], 1.0])
	for s: Array in Plan.road_kerb():
		lines.append([s[0], s[1], 0.0])
	for l: Array in lines:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var d := (b - a).normalized()
		var n := maxi(1, ceili(a.distance_to(b) / EDGE))
		for j in n:
			var p := a.lerp(b, float(j) / n)
			var q := a.lerp(b, float(j + 1) / n)
			var mid := (p + q) * 0.5
			var side := Vector2(-d.y, d.x)                   # (the road's side: where the probe is not raised)
			if Plan.paved(mid - side * 0.3):
				side = -side
			if not Plan.paved(mid - side * 0.3) or not Plan.in_perimeter(mid - side * 0.3):
				continue
			var low := 0.02 if l[2] > 0.0 else ASPHALT_UP - 0.02
			var f := [p3(p.x, p.y, low), p3(q.x, q.y, low), p3(q.x, q.y, Plan.lift(q)), p3(p.x, p.y, Plan.lift(p))]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(side))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
			var g := side * GUTTER
			var gy := 0.012 if l[2] > 0.0 else ASPHALT_UP + 0.012
			quad("gutter", p3(p.x, p.y, gy), p3(q.x, q.y, gy), p3(q.x + g.x, q.y + g.y, gy), p3(p.x + g.x, p.y + g.y, gy),
					Vector3.UP)


## The markings: the cycle track's dashed centre line and bicycles (each way in turn), the west street's centre line
## and zebra.
func _marks() -> void:
	var mid := (Plan.CYCLE.x + Plan.CYCLE.y) * 0.5
	var lane := (Plan.CYCLE.y - Plan.CYCLE.x) * 0.25
	var on_track := func(p: Vector2) -> bool:
		if absf(Plan.lift(p) - Plan.KERB) > 0.001 or not Plan.in_perimeter(p):
			return false
		for e: Array in Plan.surfaces():
			if e[1] == "street_asphalt" and Plan.inside(p, e[0]):
				return true
		return false
	var h := Plan.KERB + MARK
	var k := PackedVector2Array(Plan.KERB_S)
	var run := 0.0
	var next_bike := 20.0
	var way := 1.0
	for i in k.size() - 1:
		var a := k[i]
		var b := k[i + 1]
		var l := a.distance_to(b)
		var d := (b - a) / l
		var n := Vector2(-d.y, d.x)
		if n.y < 0.0:
			n = -n
		var s := 0.5
		while s + 1.5 < l - 0.5:
			var u := a + d * s + n * mid
			var v := a + d * (s + 1.5) + n * mid
			if on_track.call(u) and on_track.call(v):
				line(u, v, 0.1, "#eeeeea", h)
			s += 4.0
		while next_bike < run + l:
			var c := a + d * (next_bike - run) + n * (mid - lane * way)
			if on_track.call(c + d * 0.8) and on_track.call(c - d * 0.8) and on_track.call(c - n * 0.6 * way):
				bike(c, d * way, h)
				way = -way
			next_bike += BIKES * 0.5
		run += l
	var st := Plan.STREET                                    # the west street: its centre line, its zebra
	var cx := st.get_center().x
	var z := Plan.STREET_ZEBRA
	dashes(Vector2(cx, Plan.CIRCLE.y + Plan.CIRCLE.z + 2.0), Vector2(cx, z.x - 1.0), 0.12, 3.0, 3.0)
	dashes(Vector2(cx, z.y + 1.0), Vector2(cx, st.end.y - 2.0), 0.12, 3.0, 3.0)
	var y := st.position.x + 0.5
	while y < st.end.x - 0.4:
		line(Vector2(y, z.x + 0.2), Vector2(y, z.y - 0.2), 0.5, "#eeeeea", ASPHALT_UP + MARK)
		y += 1.0


## Large granite slabs, light grey with darker bands (1.2 x 0.6 m at the material's scale: the texture spans 4.8 m).
static func _slabs() -> Image:
	var img := blocks(Color("#c9c8c2"), Color("#a9a8a2"), 63)
	var n := img.get_width()
	for y in n:
		if (y / (n / 8)) % 4 == 3:                           # every fourth row darker
			for x in n:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.18))
	img.generate_mipmaps()
	return img
