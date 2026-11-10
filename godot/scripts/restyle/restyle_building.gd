extends RefCounted
## One restyled building and its grounds, after its spec (restyle_spec.gd describes it): facades storey by storey on
## each edge of its footprint (the fills: _fill_<type>), its roof, its paths and walks. build() gives the node.

const Spec = preload("res://scripts/restyle/restyle_spec.gd")
const Kit = preload("res://scripts/build_kit.gd")
const Marks = preload("res://scripts/race_marks.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const PATH_LOOK := {"concrete": "#d6d3cc", "paving": "pavers", "sett": "sett", "gravel": "gravel", "dirt": "#9c8466",
		"wood": "oak"}
const SLAB := 0.3                            # m, the floors' edges
const OUT := 0.12                            # m, the frame's posts out of the facade line
const STEP := 1.5                            # m, the paths' triangles at most (they follow the ground)

# the building being made
var _k: Kit
var _st: Dictionary
var _r: PackedVector2Array                   # the ring being made, its edges' normals (out, to the open air)
var _n: PackedVector2Array
var _outer := true                           # (the ring being made is the outer one)
var _fl := 0.0                               # y: the ground floor, the foot, the floors, the roof's top
var _foot := 0.0
var _lv: Array[float] = []
var _roof := 0.0
var _fill: Array[String] = []
var _sk: Array[Dictionary] = []              # per storey: its fill's keys (over the style's)
var _depth: Array[float] = []                # per storey: its glass (or wall) behind the facade line
var _rng := RandomNumberGenerator.new()
var _ground := {}                            # (the paths' points: their ground, each read once)


## Its ground floor's height (y), once built.
func floor_y() -> float:
	return _fl


## Spec s's building and grounds (`meshes` false: collision only, headless).
func build(s: Dictionary, meshes: bool) -> Node3D:
	_st = s["style"]
	Spec.register_materials(s)
	var kinds: PackedStringArray = []
	for f: Variant in _st.get("fill", []):
		kinds.append(str(f.get("type", "?")) if f is Dictionary else str(f))
	_k = Kit.new("Restyle_" + str(s["slug"]), {"type": "restyle", "name": s.get("name", ""), "num": s.get("num", 0),
			"id": ", ".join(s.get("replace", [])), "slug": s["slug"], "preset": _st.get("preset", ""),
			"height": float(s.get("height", 0.0)), "storeys": (s.get("storeys", []) as Array).size(),
			"fills": ", ".join(kinds)})
	_rng.seed = hash(s["slug"])
	var rings := Spec.rings_of(s)
	if rings.is_empty():
		_site(s, rings)
		return _k.commit(meshes)
	# the ground floor over the highest ground along the outer facades, the foot under the lowest along them all
	var top := -INF
	var low := INF
	for k in rings.size():
		var r: PackedVector2Array = rings[k]
		for i in r.size():
			var a := r[i]
			var b := r[(i + 1) % r.size()]
			var cuts := maxi(1, ceili(a.distance_to(b) / 2.0))
			for j in cuts:
				var p := a.lerp(b, float(j) / cuts)
				var g := Marks.ground(p.x, p.y)
				if k == 0:
					top = maxf(top, g)
				low = minf(low, g)
	_fl = top + float(_st.get("floor_up", 0.05))
	_foot = low - 0.6
	_lv.clear()
	_lv.append(_fl)
	for h: Variant in s["storeys"]:
		_lv.append(_lv[-1] + float(h))
	_roof = _fl + float(s["height"])
	var fills: Array = _st.get("fill", ["curtain"])
	_fill.clear()
	_sk.clear()
	_depth.clear()
	for k in (s["storeys"] as Array).size():
		var f: Variant = fills[mini(k, fills.size() - 1)]
		var d: Dictionary = f if f is Dictionary else {"type": str(f)}
		var type := str(d.get("type", "curtain"))
		_fill.append(type)
		_sk.append(d)
		var dflt := float(_st.get("gallery", 3.0)) if type == "open" else (0.0 if type == "punched" else
				float(_fs(k, "inset", 0.6)))
		_depth.append(float(d.get("depth", dflt)))
	for k in rings.size():
		_outer = k == 0
		_ring(rings[k], rings)
	# the roof: the map's triangles
	var roof: Dictionary = s["roof"]
	var pts := Spec.poly(roof["pts"])
	var tris: Array = roof["tris"]
	var faces := PackedVector3Array()
	var rm := str(roof.get("colour", "#a3a19d"))
	for t in range(0, tris.size() - 2, 3):
		var v3: Array[Vector3] = []
		for q in 3:
			var p := pts[int(tris[t + q])]
			v3.append(Vector3(p.x, _roof - 0.02, -p.y))
		_k.tri(rm, v3[0], v3[1], v3[2], Vector3.UP)
		faces.append_array(PackedVector3Array(v3))
	_k.col_faces(faces)
	_site(s, rings)
	return _k.commit(meshes)


## Storey k's value of a style key: its fill's, else the style's.
func _fs(k: int, key: String, default: Variant = null) -> Variant:
	var d: Dictionary = _sk[k] if k < _sk.size() else {}
	return d[key] if d.has(key) else _st.get(key, default)


## Point i of the ring being made, `d` m in from the facade line (mitred: the facades' parallels meet at the corners).
func _o(i: int, d: float) -> Vector2:
	var m := _r.size()
	var n1: Vector2 = _n[(i - 1 + m) % m]
	var n2: Vector2 = _n[i % m]
	return _r[i % m] - (n1 + n2) * d / maxf(1.0 + n1.dot(n2), 0.05)


static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, -p.y)


## Edge i's face `d` m in from the line, from y0 to y1, facing out.
func _face(i: int, d: float, y0: float, y1: float, m: String) -> void:
	if y1 - y0 < 0.005:
		return
	var a := _o(i, d)
	var b := _o(i + 1, d)
	_k.quad(m, _v(a, y0), _v(b, y0), _v(b, y1), _v(a, y1), Vector3(_n[i].x, 0, -_n[i].y))


## Edge i's flat between d0 and d1 m in from the line, at y, facing `up` (UP or DOWN).
func _flat(i: int, d0: float, d1: float, y: float, m: String, up: Vector3) -> void:
	_k.quad(m, _v(_o(i, d0), y), _v(_o(i + 1, d0), y), _v(_o(i + 1, d1), y), _v(_o(i, d1), y), up)


## A box from lo to hi in frame xf, with the faces named in `faces` (x X y Y z Z: -x +x -y +y -z +z); `flip`: facing
## in (an opening's reveals).
func _cub(m: String, xf: Transform3D, lo: Vector3, hi: Vector3, faces := "xXyYzZ", flip := false) -> void:
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xf * Vector3(hi.x if k & 1 else lo.x, hi.y if k & 2 else lo.y, hi.z if k & 4 else lo.z))
	var f := -1.0 if flip else 1.0
	var bx := xf.basis.x.normalized() * f
	var bz := xf.basis.z.normalized() * f
	var up := Vector3.UP * f
	if "x" in faces:
		_k.quad(m, p[0], p[2], p[6], p[4], -bx)
	if "X" in faces:
		_k.quad(m, p[1], p[3], p[7], p[5], bx)
	if "y" in faces:
		_k.quad(m, p[0], p[1], p[5], p[4], -up)
	if "Y" in faces:
		_k.quad(m, p[2], p[3], p[7], p[6], up)
	if "z" in faces:
		_k.quad(m, p[0], p[1], p[3], p[2], -bz)
	if "Z" in faces:
		_k.quad(m, p[4], p[5], p[7], p[6], bz)


func _ring(r: PackedVector2Array, rings: Array) -> void:
	_r = r
	_n = PackedVector2Array()
	var m := r.size()
	for i in m:
		var t := (r[(i + 1) % m] - r[i]).normalized()
		var nn := Vector2(t.y, -t.x)
		if Spec.inside(rings, (r[i] + r[(i + 1) % m]) * 0.5 + nn * 0.3):
			nn = -nn
		_n.append(nn)
	for i in m:
		if r[i].distance_to(r[(i + 1) % m]) > 0.05:
			_edge(i)


func _edge(i: int) -> void:
	var a := _r[i]
	var b := _r[(i + 1) % _r.size()]
	var L := a.distance_to(b)
	var t := (b - a) / L
	var xf := Transform3D(Basis(Vector3(t.x, 0, -t.y), Vector3.UP, Vector3(_n[i].x, 0, -_n[i].y)), _v(a, 0.0))
	var frame: Dictionary = _st.get("frame", {})
	var slab := str(_st.get("slab", frame.get("colour", _st.get("wall", "#c8c4bc"))))
	var n := _fill.size()
	# the plinth on the line, the gallery's floor behind it
	_face(i, 0.0, _foot, _fl, str(_st.get("plinth", "#b8b5ae")))
	if _depth[0] > 0.01:
		_flat(i, 0.0, _depth[0], _fl, str(_st.get("floor", "#cfcbc3")), Vector3.UP)
	# the storeys, each by its fill's method
	for k in n:
		var method := "_fill_" + _fill[k]
		if has_method(method):
			call(method, i, xf, L, k)
		else:
			push_warning("restyle: no fill \"%s\" (a method %s)" % [_fill[k], method])
			_fill_curtain(i, xf, L, k)
	# the floors' edges, out to the ledge and in to the deeper glass of the storeys round them; the attic up to the
	# roof
	for k in range(1, n + 1):
		var dd := maxf(_depth[k - 1], _depth[k] if k < n else 0.0)
		var out := -float(_fs(k - 1, "ledge", 0.0)) if k < n else 0.0
		var y := _lv[k]
		var sm := str(_fs(k - 1, "slab", slab))
		if dd > 0.01 or out < -0.01:
			_flat(i, out, dd, y - SLAB, sm, Vector3.DOWN)
			if k < n:
				_flat(i, out, dd, y, sm, Vector3.UP)
			_face(i, out, y - SLAB, y, sm)
			if k == n:
				_face(i, 0.0, y, _roof, str(_st.get("attic", sm)))
		elif k == n:
			_face(i, 0.0, y, _roof, str(_st.get("attic", _fs(k - 1, "wall", slab))))
		elif _fs(k - 1, "band", false):
			var bm := str(_fs(k - 1, "band_colour", slab))
			_face(i, -0.06, y - 0.12, y + 0.12, bm)
			_flat(i, -0.06, 0.0, y + 0.12, bm, Vector3.UP)
			_flat(i, -0.06, 0.0, y - 0.12, bm, Vector3.DOWN)
	# the roof's edge: a coping, or a brim standing out
	var brim := maxf(float(_st.get("brim", 0.0)), 0.08)
	var bh := 0.15 if brim <= 0.08 else 0.3
	var cm := str(_st.get("brim_colour", slab))
	_flat(i, -brim, 0.5, _roof, cm, Vector3.UP)
	_face(i, -brim, _roof - bh, _roof, cm)
	_flat(i, -brim, 0.0, _roof - bh, cm, Vector3.DOWN)
	# the frame's posts on the line, from the ground to over the roof
	if not frame.is_empty():
		var post: Array = frame.get("post", [0.16, 0.34])
		var bays := maxi(1, roundi(L / float(_st.get("bay", 2.4))))
		for j in bays:
			var u := L * j / bays
			_cub(str(frame.get("colour", slab)), xf, Vector3(u - float(post[0]) * 0.5, _foot, -float(post[1])),
					Vector3(u + float(post[0]) * 0.5, _roof + 0.1, OUT), "xXYzZ")
	if _outer and _st.has("skin"):
		_skin(i, xf)
	# collision: the ground floor's glass line up to the roof, the plinth
	var d0 := _depth[0]
	_k.col_xf(xf * Transform3D(Basis.IDENTITY, Vector3(L * 0.5, (_fl + _roof) * 0.5, -d0 - 0.15)),
			Vector3(L, _roof - _fl, 0.3))
	if d0 > 0.01 and _fl - _foot > 0.05:
		_k.col_xf(xf * Transform3D(Basis.IDENTITY, Vector3(L * 0.5, (_foot + _fl) * 0.5, -d0 * 0.5)),
				Vector3(L, _fl - _foot, d0))


## Edge i's u range (along it from its first point) of its parallel d m in.
func _span(i: int, d: float) -> Vector2:
	var a := _r[i]
	var t := (_r[(i + 1) % _r.size()] - a).normalized()
	return Vector2((_o(i, d) - a).dot(t), (_o(i + 1, d) - a).dot(t))


## Glass `depth` m in, mullions every "mullion" m.
func _fill_curtain(i: int, xf: Transform3D, _L: float, k: int) -> void:
	var d := _depth[k]
	var y0 := _lv[k]
	var y1 := _lv[k + 1] - SLAB
	_face(i, d, y0, y1, str(_fs(k, "glass", "glass_dark")))
	var mm := str(_fs(k, "mullions", _fs(k, "slab", "#d9dcdf")))
	var s := _span(i, d)
	var cuts := maxi(1, roundi((s.y - s.x) / float(_fs(k, "mullion", 1.2))))
	for j in range(1, cuts):
		var u := lerpf(s.x, s.y, float(j) / cuts)
		_cub(mm, xf, Vector3(u - 0.03, y0, -d), Vector3(u + 0.03, y1, -d + 0.08), "xXZ")


## A gallery (préau): the glass "gallery" m in.
func _fill_open(i: int, xf: Transform3D, L: float, k: int) -> void:
	_fill_curtain(i, xf, L, k)


## A curtain with brise-soleil in the frame's bays: slats between the posts, between the posts' depth and the glass.
func _fill_louvres(i: int, xf: Transform3D, L: float, k: int) -> void:
	_fill_curtain(i, xf, L, k)
	var frame: Dictionary = _st.get("frame", {})
	var lv: Dictionary = _fs(k, "louvres", {})
	var m := str(lv.get("colour", frame.get("colour", "#eef0f1")))
	var every := float(lv.get("every", 0.3))
	var post: Array = frame.get("post", [0.0, 0.0])
	var bays := maxi(1, roundi(L / float(_st.get("bay", 2.4))))
	var end := maxf(float(post[0]) * 0.5, float(post[1])) + 0.02        # (off the corner posts)
	var z0 := -minf(float(post[1]) + 0.02, _depth[k] - 0.1)
	var y1 := _lv[k + 1] - SLAB
	for j in bays:
		if _rng.randf() < float(lv.get("clear", 0.0)):
			continue
		var u0 := L * j / bays + (end if j == 0 else float(post[0]) * 0.5 + 0.02)
		var u1 := L * (j + 1) / bays - (end if j == bays - 1 else float(post[0]) * 0.5 + 0.02)
		var y := _lv[k] + every * 0.5
		while y < y1 - 0.05:
			_cub(m, xf, Vector3(u0, y, z0), Vector3(u1, y + 0.03, z0 + 0.24), "yYZ")
			y += every


## A curtain behind vertical fins standing out of the facade line ("fins": every, depth, width, material); the fins of
## storeys of fins on end run on.
func _fill_fins(i: int, xf: Transform3D, L: float, k: int) -> void:
	_fill_curtain(i, xf, L, k)
	var fn: Dictionary = _fs(k, "fins", {})
	var m := str(fn.get("material", "#2a2d31"))
	var every := float(fn.get("every", 0.6))
	var w := float(fn.get("width", 0.06))
	var dep := float(fn.get("depth", 0.4))
	var last := k == _fill.size() - 1 or _fill[k + 1] != "fins"
	var cuts := maxi(1, roundi(L / every))
	for j in cuts:
		var u := L * (j + 0.5) / cuts
		_cub(m, xf, Vector3(u - w * 0.5, _lv[k], -0.05), Vector3(u + w * 0.5, _lv[k + 1], dep),
				"xXZY" if last else "xXZ")


## A wall on the line from this floor to the next, its windows (one a bay) with reveals and sills.
func _fill_punched(i: int, xf: Transform3D, L: float, k: int) -> void:
	var y0 := _lv[k]
	var y1 := _lv[k + 1]
	var p: Dictionary = _fs(k, "punched", {})
	var wall := str(_fs(k, "wall", "#c8c4bc"))
	var ww := float(p.get("w", 1.4))
	var rv := float(p.get("reveal", 0.22))
	var ys := y0 + float(p.get("sill", 0.9))
	var yh := minf(y0 + float(p.get("head", 2.3)), y1 - 0.3)
	var bays := maxi(1, roundi(L / float(_fs(k, "bay", 2.7))))
	var bw := L / bays
	if yh - ys < 0.4 or bw < ww + 0.4:
		_face(i, 0.0, y0, y1, wall)
		return
	_face(i, 0.0, y0, ys, wall)
	_face(i, 0.0, yh, y1, wall)
	var glass := str(_fs(k, "glass", "glass_dark"))
	var sill := str(_fs(k, "slab", wall))
	for j in bays:
		var c := bw * (j + 0.5)
		var wl := c - ww * 0.5
		var wr := c + ww * 0.5
		_cub(wall, xf, Vector3(bw * j, ys, -0.01), Vector3(wl, yh, 0.0), "Z")       # the piers
		_cub(wall, xf, Vector3(wr, ys, -0.01), Vector3(bw * (j + 1), yh, 0.0), "Z")
		_cub(wall, xf, Vector3(wl, ys, -rv), Vector3(wr, yh, 0.0), "xXyY", true)    # the reveals, facing in
		_cub(glass, xf, Vector3(wl, ys, -rv), Vector3(wr, yh, -rv + 0.001), "Z")
		_cub(sill, xf, Vector3(wl - 0.05, ys - 0.06, 0.0), Vector3(wr + 0.05, ys, 0.06), "xXyYZ")


## A second skin round the outer ring: vertical blades "gap" m out, from storey "from" to over the roof, a ring on top.
func _skin(i: int, xf: Transform3D) -> void:
	var sk: Dictionary = _st["skin"]
	var gap := float(sk.get("gap", 0.9))
	var bd := float(sk.get("blade", 0.35))
	var w := float(sk.get("width", 0.03))
	var m := str(sk.get("material", "#cfe0e8"))
	var y0 := _lv[clampi(int(sk.get("from", 0)), 0, _lv.size() - 1)]
	var y1 := _roof + float(sk.get("over", 0.8))
	var s := _span(i, -gap - bd * 0.5)
	var cuts := maxi(1, roundi((s.y - s.x) / float(sk.get("every", 0.6))))
	for j in cuts:
		var u := lerpf(s.x, s.y, (j + 0.5) / cuts)
		_cub(m, xf, Vector3(u - w * 0.5, y0, gap), Vector3(u + w * 0.5, y1, gap + bd), "xXzZ")
	var rm := str(sk.get("ring", _st.get("slab", "#e6e9ec")))
	_flat(i, -gap - bd, -gap + 0.05, y1, rm, Vector3.UP)
	_flat(i, -gap - bd, -gap + 0.05, y1 - 0.25, rm, Vector3.DOWN)
	_face(i, -gap - bd, y1 - 0.25, y1, rm)


func _site(s: Dictionary, rings: Array) -> void:
	var site: Dictionary = s.get("site", {})
	var area := Spec.poly(site.get("area", []))
	for pa: Dictionary in site.get("paths", []):
		var look := str(PATH_LOOK.get(str(pa["material"]), "#d6d3cc"))
		if pa.has("tris"):                                   # (a garden's: its triangles, holes kept)
			var tp: Array = pa["tris"]
			for t in range(0, tp.size() - 2, 3):
				_gtri(look, Vector2(tp[t][0], tp[t][1]), Vector2(tp[t + 1][0], tp[t + 1][1]),
						Vector2(tp[t + 2][0], tp[t + 2][1]), 0.05)
			continue
		var shape := Spec.poly(pa["pts"])
		var parts: Array = Geometry2D.intersect_polygons(shape, area) if area.size() > 2 else [shape]
		for q: PackedVector2Array in parts:
			var idx := Geometry2D.triangulate_polygon(q)
			for t in range(0, idx.size() - 2, 3):
				_gtri(look, q[idx[t]], q[idx[t + 1]], q[idx[t + 2]], 0.05)
	for w: Dictionary in site.get("walks", []):
		_walk(w, rings)
	for q in Spec.walk_polys(s):
		GrassField.keep_out.append(q)


## A triangle of path on the ground (map points), cut until it follows it.
func _gtri(m: String, a: Vector2, b: Vector2, c: Vector2, lift: float, depth := 0) -> void:
	var ab := a.distance_squared_to(b)
	var bc := b.distance_squared_to(c)
	var ca := c.distance_squared_to(a)
	var mx := maxf(ab, maxf(bc, ca))
	if mx > STEP * STEP and depth < 16:
		if mx == ab:
			_gtri(m, a, (a + b) * 0.5, c, lift, depth + 1)
			_gtri(m, (a + b) * 0.5, b, c, lift, depth + 1)
		elif mx == bc:
			_gtri(m, a, b, (b + c) * 0.5, lift, depth + 1)
			_gtri(m, a, (b + c) * 0.5, c, lift, depth + 1)
		else:
			_gtri(m, a, b, (c + a) * 0.5, lift, depth + 1)
			_gtri(m, (c + a) * 0.5, b, c, lift, depth + 1)
		return
	_k.tri(m, _v(a, _ground_at(a) + lift), _v(b, _ground_at(b) + lift), _v(c, _ground_at(c) + lift), Vector3.UP, true)


func _ground_at(p: Vector2) -> float:
	if not _ground.has(p):
		_ground[p] = Marks.ground(p.x, p.y)
	return _ground[p]


## A raised walk: level with the ground floor at its ends by the building, `lift` m over the ground elsewhere, its
## sides down into the ground; a ramp to walk on.
func _walk(w: Dictionary, rings: Array) -> void:
	var pts := Spec.poly(w["pts"])
	var half := float(w.get("w", 2.0)) * 0.5
	var lift := float(w.get("lift", 0.3))
	var m := str(w.get("colour", "#d9d6cf"))
	var hs: Array[float] = []
	for p in pts:
		var by := false
		for r: PackedVector2Array in rings:
			for i in r.size():
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[i], r[(i + 1) % r.size()])) < 1.5:
					by = true
		hs.append(_fl if by else Marks.ground(p.x, p.y) + lift)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var t := (b - a).normalized()
		var side := Vector2(-t.y, t.x) * half
		var cuts := maxi(1, ceili(a.distance_to(b) / 2.0))
		for j in cuts:
			var p0 := a.lerp(b, float(j) / cuts)
			var p1 := a.lerp(b, float(j + 1) / cuts)
			var h0 := maxf(lerpf(hs[i], hs[i + 1], float(j) / cuts), Marks.ground(p0.x, p0.y) + 0.1)
			var h1 := maxf(lerpf(hs[i], hs[i + 1], float(j + 1) / cuts), Marks.ground(p1.x, p1.y) + 0.1)
			var l0 := _v(p0 + side, h0)
			var r0 := _v(p0 - side, h0)
			var l1 := _v(p1 + side, h1)
			var r1 := _v(p1 - side, h1)
			_k.quad(m, l0, r0, r1, l1, Vector3.UP)
			for e: Array in [[l0, l1, side], [r0, r1, -side]]:
				var e0: Vector3 = e[0]
				var e1: Vector3 = e[1]
				var g0 := Marks.ground(e0.x, -e0.z) - 0.1
				var g1 := Marks.ground(e1.x, -e1.z) - 0.1
				var sd: Vector2 = e[2]
				_k.quad(m, e0, e1, Vector3(e1.x, g1, e1.z), Vector3(e0.x, g0, e0.z), Vector3(sd.x, 0, -sd.y).normalized())
			_k.col_ramp(_v(p0, h0), _v(p1, h1), half * 2.0)
