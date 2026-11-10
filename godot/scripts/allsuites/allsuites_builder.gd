extends RefCounted
## All Suites Study Paris Saclay, the students' residence in place of building #184 (osm:w626590677;
## scripts/allsuites/allsuites.gd places it), after Thomas's photos (ref/proprietes/AllSuitesStudy/): a U of five floors
## over a tall glazed ground floor, open to the north on its garden courtyard.
## - The south facade on the boulevard and the corner blocks at both ends of it (coin1: the south-west one, coin2 and
##   "rue coin2": the south-east one): a ground floor of black-framed shop windows between white columns, yellow glass at
##   the corners, a white slab band; over it aluminium cladding panels in four shades, tall narrow windows, louvred
##   sliding shutters, loggias with glass rails (stacked at the corners round a black post), the black mullions of every
##   bay rising over the roof's edge.
## - The wings' outer facades (on the west street and the east lane): a sawtooth, its short faces looking south in sage
##   cladding with a tall window, its long faces in grey render with small windows, over a black colonnade (coin3,
##   arriere).
## - The north gables blank, with their panel joints; the courtyard in white render with ribbon windows between grey
##   green spandrels, balconies stacked in its north corners (arriere).
## Built in its own frame: x along the south facade (east), y up from the ground floor, z = -v; the plan (u, v) has u
## along the south facade from its west end, v north along the west facade. No two faces of the same side ever lie in
## one plane where they overlap (tools/test_allsuites.gd checks it): what is laid on a wall stands off it, and a hole
## in a wall is cut (its reveals drawn), never covered.
## Collision (BUILDINGS): the masses, the ground floor at its glazing, the columns, the parapets, the colonnades' paving.

const Layers = preload("res://scripts/physics_layers.gd")

const NAME := "All Suites Study Paris Saclay"
const LEN := 67.51                          # m, the south facade, its south-west corner to its south-east one
const WING := 15.4                          # m, the wings' width
const BAR := 13.5                           # m, the south bar's depth (the courtyard's south side)
const NORTH := 49.4                         # m, the wings' north gables
const NOTCH_V := 40.8                       # the courtyard's north corners: the wings narrower from here...
const NOTCH_IN := 12.7                      # ...to here (from their outer facade), balconies in the notch
const SKIN := 1.6                           # m, the street facades' skin (panels, loggias) before the core
const GF_IN := 3.35                         # m, the shops behind the street glazing (from the facade line)
const GLAZ := 0.35                          # m, the street glazing behind the facade line
const COL := 1.5                            # m, the wings' colonnade (its glazing back from the facade line)
const TEETH := 10                           # the sawtooth along each wing's outer facade
const TOOTH := (NORTH - BAR) / TEETH        # m, 3.59
const D := 1.4                              # m, its depth
const BAYS := 20                            # along the south facade
const BAY := LEN / BAYS                     # m, 3.38
const MODULE := LEN / 10.0                  # m, the ground floor's glazed modules (two bays)
const GF_H := 4.9                           # m, the first floor over the ground floor's
const FH := 2.9                             # m, floor to floor
const FLOORS := 5
const ROOF := GF_H + FH * FLOORS            # m, 19.4
const PARA := 0.35                          # m, the parapet over the roof
const PARA_T := 0.3                         # m, its thickness
## The ground floor's modules along the south facade (west to east), and the two of each return (from the corner).
const SOUTH_GF := ["shop", "pharmacy", "frosted", "entrance", "lobby", "frosted", "shop", "restaurant", "restaurant",
		"shop"]
const WEST_GF := ["yellow", "frosted"]
const EAST_GF := ["yellow", "shop"]
const CLADS := ["clad_white", "clad_white", "clad_pearl", "clad_pearl", "clad_silver", "clad_grey"]

var _st := {}
var _mats := {}
var _body: StaticBody3D
var _root: Node3D
var _rng := RandomNumberGenerator.new()
var _ground: Callable
var _yb := -1.5                             # the masses' foot, under the ground
var _detail := false                        # meshes made now are details (drawn closer)

static var _textures := {}


## The residence (its frame's origin at the ground floor's level at the south-west corner); `ground` (u, v) -> the
## map's ground height in its frame, `foot` a height under the ground everywhere round it. Meta: "paved" (the paved
## rectangles [u0, v0, u1, v1]).
func build(ground: Callable, foot: float, meshes := true) -> Node3D:
	_rng.seed = 184
	_ground = ground
	_yb = foot
	_root = Node3D.new()
	_root.name = "AllSuitesStudy"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "allsuites", "name": NAME, "id": "allsuites", "kind": "students' residence"})
	_root.add_child(_body)
	_collision()
	# (the meshes are made headless too, for the collision of the steps and roof cores made with them; not drawn)
	_paving()
	_masses()
	_street_ground_floor()
	_street_upper()
	_colonnades()
	_balconies()
	_roof()
	if meshes:
		_signs()
		_commit()
	_root.set_meta("paved", [[0.0, BAR, COL, NORTH], [LEN - COL, BAR, LEN, NORTH]])
	return _root


## The triangles drawn, by material (the tests): {material: PackedVector3Array, three by three}.
func triangles() -> Dictionary:
	var out := {}
	for key: String in _st:
		var arrays := (_st[key] as SurfaceTool).commit_to_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tris := PackedVector3Array()
		if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				tris.append(verts[i])
		else:
			tris = verts
		var mat := key.get_slice("|", 0)
		var all: PackedVector3Array = out.get(mat, PackedVector3Array())
		all.append_array(tris)
		out[mat] = all              # (a packed array is copied, not shared)
	return out


static func floor_y(f: int) -> float:
	return GF_H + FH * (f - 1)


# ---------------------------------------------------------------- the masses

## The upper floors' core (y GF_H..ROOF) and the ground floor's (_yb..GF_H), each an outline extruded with its faces
## pierced; the roof's parapet round the whole outline.
func _masses() -> void:
	# the upper floors: the core behind the street skin, the sawtooth, the gables, the courtyard
	var pts: Array[Vector2] = []
	var specs: Array = []
	var add := func(p: Vector2, spec: Dictionary) -> void:
		pts.append(p)
		specs.append(spec)
	add.call(Vector2(SKIN, SKIN), {"mat": "core"})
	add.call(Vector2(LEN - SKIN, SKIN), {"mat": "core"})
	add.call(Vector2(LEN - SKIN, BAR), {})          # (against the east return's skin end)
	for k in TEETH:
		var a := BAR + k * TOOTH
		var b := a + TOOTH
		add.call(Vector2(LEN, a), {"mat": "render_grey", "holes": _long_face_holes(k, false)})
		if k < TEETH - 1:
			add.call(Vector2(LEN - D, b), {"mat": "sage", "holes": _short_face_holes()})
		else:
			add.call(Vector2(LEN - D, NORTH), {"mat": "render_white", "holes": _gable_holes(LEN - D - (LEN - NOTCH_IN))})
	add.call(Vector2(LEN - NOTCH_IN, NORTH), {"mat": "render_white", "holes": _notch_holes(NORTH - NOTCH_V, true)})
	add.call(Vector2(LEN - NOTCH_IN, NOTCH_V), {"mat": "render_white", "holes": _small_face_holes()})
	add.call(Vector2(LEN - WING, NOTCH_V), {"mat": "render_white", "holes": _ribbon_holes(NOTCH_V - BAR)})
	add.call(Vector2(LEN - WING, BAR), {"mat": "render_white", "holes": _ribbon_holes(LEN - 2.0 * WING)})
	add.call(Vector2(WING, BAR), {"mat": "render_white", "holes": _ribbon_holes(NOTCH_V - BAR)})
	add.call(Vector2(WING, NOTCH_V), {"mat": "render_white", "holes": _small_face_holes()})
	add.call(Vector2(NOTCH_IN, NOTCH_V), {"mat": "render_white", "holes": _notch_holes(NORTH - NOTCH_V, false)})
	add.call(Vector2(NOTCH_IN, NORTH), {"mat": "gable_grey", "holes": _gable_holes(NOTCH_IN - D)})
	for k in range(TEETH - 1, -1, -1):
		var a := BAR + k * TOOTH
		add.call(Vector2(D, a + TOOTH), {"mat": "render_grey", "holes": _long_face_holes(k, true)})
		if k > 0:
			add.call(Vector2(0.0, a), {"mat": "sage", "holes": _short_face_holes()})
		else:
			add.call(Vector2(0.0, BAR), {})        # (against the west return's skin end)
	add.call(Vector2(SKIN, BAR), {"mat": "core"})
	_extrude(pts, specs, GF_H, ROOF, "roof_gravel")

	# the ground floor: the shops' back walls behind the street glazing, the colonnades, the gables, the courtyard
	var g: Array[Vector2] = []
	var gs: Array = []
	var gadd := func(p: Vector2, spec: Dictionary) -> void:
		g.append(p)
		gs.append(spec)
	gadd.call(Vector2(GF_IN, GF_IN), {"mat": "shop_wall"})
	gadd.call(Vector2(LEN - GF_IN, GF_IN), {"mat": "shop_wall"})
	gadd.call(Vector2(LEN - GF_IN, BAR), {"mat": "shop_wall"})
	gadd.call(Vector2(LEN - COL, BAR), {"mat": "colonnade_wall", "holes": _colonnade_holes(), "steps": true})
	gadd.call(Vector2(LEN - COL, NORTH), {"mat": "render_white"})
	gadd.call(Vector2(LEN - NOTCH_IN, NORTH), {"mat": "render_white", "holes": _gf_holes(NORTH - NOTCH_V, 1), "steps": true})
	gadd.call(Vector2(LEN - NOTCH_IN, NOTCH_V), {"mat": "render_white"})
	gadd.call(Vector2(LEN - WING, NOTCH_V), {"mat": "render_white", "holes": _gf_holes(NOTCH_V - BAR, 2), "steps": true})
	gadd.call(Vector2(LEN - WING, BAR), {"mat": "render_white", "holes": _gf_holes(LEN - 2.0 * WING, 3), "steps": true})
	gadd.call(Vector2(WING, BAR), {"mat": "render_white", "holes": _gf_holes(NOTCH_V - BAR, 2), "steps": true})
	gadd.call(Vector2(WING, NOTCH_V), {"mat": "render_white"})
	gadd.call(Vector2(NOTCH_IN, NOTCH_V), {"mat": "render_white", "holes": _gf_holes(NORTH - NOTCH_V, 1), "steps": true})
	gadd.call(Vector2(NOTCH_IN, NORTH), {"mat": "gable_grey"})
	gadd.call(Vector2(COL, NORTH), {"mat": "colonnade_wall", "holes": _colonnade_holes(), "steps": true})
	gadd.call(Vector2(COL, BAR), {"mat": "shop_wall"})
	gadd.call(Vector2(GF_IN, BAR), {"mat": "shop_wall"})
	_extrude(g, gs, _yb, GF_H, "")

	# the parapet round the roof, on the whole outline (the street facades' too)
	var r: Array[Vector2] = [Vector2(0, 0), Vector2(LEN, 0)]
	var rm: Array = ["black_frame", "black_frame"]
	for i in range(3, pts.size() - 2):
		r.append(pts[i])
		rm.append(specs[i]["mat"])
	r.append(Vector2(0.0, BAR))
	rm.append("black_frame")
	_parapet(r, rm)
	# the rails along the sawtooth's parapets: the east teeth from r[2], the west ones the last 2 TEETH points
	var mid := _offset(r, PARA_T * 0.5)
	_rails(mid.slice(2, 2 + 2 * TEETH))
	_rails(mid.slice(mid.size() - 2 * TEETH))


## An outline (counter-clockwise, its faces' specs: {mat, holes} each, {} hidden) extruded from y0 to y1, its top in
## `top` ("": none).
func _extrude(pts: Array[Vector2], specs: Array, y0: float, y1: float, top: String) -> void:
	for i in pts.size():
		var spec: Dictionary = specs[i]
		if spec.is_empty():
			continue
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		_face(spec["mat"], a, b, y0, y1, spec.get("holes", []))
		if spec.get("steps", false):
			for h: Array in spec.get("holes", []):
				if h[2] <= 0.01:
					_door_steps(a, b, h)
	if top != "":
		var poly := PackedVector2Array(pts)
		var idx := Geometry2D.triangulate_polygon(poly)
		var st := _tool(top, true)
		for k in range(0, idx.size(), 3):
			var tri := [poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]
			_tri(st, _p(tri[0].x, y1, tri[0].y), _p(tri[1].x, y1, tri[1].y), _p(tri[2].x, y1, tri[2].y), Vector3.UP)


## The face over a -> b (the outline's interior on its left, the face looking right) from y0 to y1, pierced by
## `holes` ([s0, s1, y0, y1, kind]: s along it from a): the face in rows of quads round them, each hole's reveals and
## what closes it (_hole).
func _face(mat: String, a: Vector2, b: Vector2, y0: float, y1: float, holes: Array) -> void:
	var length := a.distance_to(b)
	var t := (b - a) / length
	var n := Vector2(t.y, -t.x)
	var ss := [0.0, length]
	var ys := [y0, y1]
	for h: Array in holes:
		ss.append_array([h[0], h[1]])
		ys.append_array([h[2], h[3]])
	ss = _unique(ss)
	ys = _unique(ys)
	var st := _tool(mat, true)
	var nn := Vector3(n.x, 0, -n.y)
	for j in ys.size() - 1:
		var ya: float = ys[j]
		var yb: float = ys[j + 1]
		var ym := (ya + yb) * 0.5
		var run := -1
		for i in ss.size():
			var open := i < ss.size() - 1
			if open:
				var sm := (float(ss[i]) + float(ss[i + 1])) * 0.5
				for h: Array in holes:
					if sm > h[0] and sm < h[1] and ym > h[2] and ym < h[3]:
						open = false
						break
			if open and run < 0:
				run = i
			elif not open and run >= 0:
				var sa: float = ss[run]
				var sb: float = ss[i]
				_quad(st, _fp(a, t, n, sa, ya, 0.0), _fp(a, t, n, sb, ya, 0.0), _fp(a, t, n, sb, yb, 0.0),
						_fp(a, t, n, sa, yb, 0.0), nn)
				run = -1
	for h: Array in holes:
		_hole(mat, a, t, n, h)


static func _unique(v: Array) -> Array:
	v.sort()
	var out := []
	for x: float in v:
		if out.is_empty() or x - float(out[-1]) > 0.0005:
			out.append(x)
	return out


## A hole in a face: its reveals in the face's material down to its glass (or a groove's back), its frame, mullions,
## sill. Kinds: "win", "win_c" (curtains drawn), "door", "dark" and "dark_door" (the colonnades' black glazing),
## "ribbon" (the courtyard's window bands: glass and spandrels), "groove" (a panel joint).
func _hole(mat: String, a: Vector2, t: Vector2, n: Vector2, h: Array) -> void:
	var s0: float = h[0]
	var s1: float = h[1]
	var y0: float = h[2]
	var y1: float = h[3]
	var kind: String = h[4]
	var r: float = {"groove": 0.025, "dark": 0.12, "dark_door": 0.12, "ribbon": 0.18}.get(kind, 0.2)
	var st := _tool(mat, true)
	var tt := Vector3(t.x, 0, -t.y)
	_quad(st, _fp(a, t, n, s0, y0, 0.0), _fp(a, t, n, s0, y1, 0.0), _fp(a, t, n, s0, y1, -r), _fp(a, t, n, s0, y0, -r), tt)
	_quad(st, _fp(a, t, n, s1, y0, 0.0), _fp(a, t, n, s1, y1, 0.0), _fp(a, t, n, s1, y1, -r), _fp(a, t, n, s1, y0, -r), -tt)
	_quad(st, _fp(a, t, n, s0, y0, 0.0), _fp(a, t, n, s1, y0, 0.0), _fp(a, t, n, s1, y0, -r), _fp(a, t, n, s0, y0, -r),
			Vector3.UP)
	_quad(st, _fp(a, t, n, s0, y1, 0.0), _fp(a, t, n, s1, y1, 0.0), _fp(a, t, n, s1, y1, -r), _fp(a, t, n, s0, y1, -r),
			Vector3.DOWN)
	var back := mat
	if kind != "groove":
		back = "glass_dark" if kind.begins_with("dark") else ("glass_curtain" if kind == "win_c" else "glass_win")
	var nn := Vector3(n.x, 0, -n.y)
	_quad(_tool(back, true), _fp(a, t, n, s0, y0, -r), _fp(a, t, n, s1, y0, -r), _fp(a, t, n, s1, y1, -r),
			_fp(a, t, n, s0, y1, -r), nn)
	if kind == "groove":
		return
	# the frame: its sides full height, its head and foot between them
	var fw := 0.07 if kind.begins_with("dark") else 0.05
	var d0 := -r - 0.01
	var d1 := -r + 0.05
	_fbox("black_frame", a, t, n, s0, s0 + fw, y0, y1, d0, d1)
	_fbox("black_frame", a, t, n, s1 - fw, s1, y0, y1, d0, d1)
	_fbox("black_frame", a, t, n, s0 + fw, s1 - fw, y0, y0 + fw, d0, d1)
	_fbox("black_frame", a, t, n, s0 + fw, s1 - fw, y1 - fw, y1, d0, d1)
	var mid := (s0 + s1) * 0.5
	match kind:
		"win", "win_c":
			if s1 - s0 > 1.3:
				_fbox("black_frame", a, t, n, mid - 0.025, mid + 0.025, y0 + fw, y1 - fw, -r - 0.005, -r + 0.04)
			# the sill over the reveal's foot, standing out of the wall
			_fbox("coping", a, t, n, s0 - 0.04, s1 + 0.04, y0 - 0.04, y0 + 0.015, -r + 0.06, 0.05)
		"door":
			if s1 - s0 > 1.4:
				_fbox("black_frame", a, t, n, mid - 0.025, mid + 0.025, y0 + fw, y1 - fw, -r - 0.005, -r + 0.04)
			_fbox("black_frame", a, t, n, s0 + fw, s1 - fw, y0 + 0.95, y0 + 1.0, -r + 0.002, -r + 0.035)   # (the push bar)
		"dark", "dark_door":
			_fbox("black_frame", a, t, n, mid - 0.035, mid + 0.035, y0 + fw, y1 - fw, -r - 0.005, -r + 0.04)
			if kind == "dark":
				for part: Array in [[s0 + fw, mid - 0.035], [mid + 0.035, s1 - fw]]:
					_fbox("black_frame", a, t, n, part[0], part[1], y0 + 2.6, y0 + 2.66, -r - 0.005, -r + 0.035)
		"ribbon":
			# glass and grey-green spandrels in turn, a black mullion between each
			var x := s0 + fw
			var marks: Array[float] = []
			var glass := true
			while true:
				var w := 1.35 if glass else 0.95
				if x + w > s1 - fw - 0.5:
					break
				x += w
				marks.append(x)
				glass = not glass
			var prev := s0 + fw
			glass = true
			for m: float in marks:
				_fbox("black_frame", a, t, n, m - 0.025, m + 0.025, y0 + fw, y1 - fw, -r - 0.005, -r + 0.04)
				if not glass:
					_fbox("spandrel_green", a, t, n, prev + 0.025, m - 0.025, y0 + fw, y1 - fw, -r + 0.005, -r + 0.03)
				prev = m
				glass = not glass


## Steps up to a door at the foot of a face, where the ground is under the floor: the top one level with it.
func _door_steps(a: Vector2, b: Vector2, h: Array) -> void:
	var t := (b - a).normalized()
	var n := Vector2(t.y, -t.x)
	var s0: float = h[0] - 0.25
	var s1: float = h[1] + 0.25
	var mid := a + t * ((s0 + s1) * 0.5) + n * 0.5
	var drop := -float(_ground.call(mid.x, mid.y))
	if drop < 0.08:
		return
	var k := ceili(drop / 0.17) - 1
	for i in k:
		var top := -drop * float(i + 1) / float(k + 1)
		var dd0 := 0.34 * i
		var dd1 := dd0 + 0.34
		_fbox("granite", a, t, n, s0, s1, _yb, top, dd0, dd1)
		_fcol(a, t, n, s0, s1, _yb, top, dd0, dd1)


## The parapet round the roof over `outline` (counter-clockwise), its outer faces in `mats` (one an edge), its inner
## faces and coping light grey (black over the street facades).
func _parapet(outline: Array[Vector2], mats: Array) -> void:
	var m := outline.size()
	var inner := _offset(outline, PARA_T)
	var y0 := ROOF
	var y1 := ROOF + PARA
	for i in m:
		var a := outline[i]
		var b := outline[(i + 1) % m]
		var ia := inner[i]
		var ib := inner[(i + 1) % m]
		var t := (b - a).normalized()
		var out := Vector3(t.y, 0, t.x)
		var mat: String = mats[i]
		_quad(_tool(mat, true), _p(a.x, y0, a.y), _p(b.x, y0, b.y), _p(b.x, y1, b.y), _p(a.x, y1, a.y), out)
		_quad(_tool("parapet_in", true), _p(ia.x, y0, ia.y), _p(ib.x, y0, ib.y), _p(ib.x, y1, ib.y), _p(ia.x, y1, ia.y),
				-out)
		var cop := "black_frame" if mat == "black_frame" else "coping"
		_quad(_tool(cop, true), _p(a.x, y1, a.y), _p(b.x, y1, b.y), _p(ib.x, y1, ib.y), _p(ia.x, y1, ia.y), Vector3.UP)


## `outline` (counter-clockwise) moved `dist` in, each edge parallel to its own (mitred corners).
static func _offset(outline: Array[Vector2], dist: float) -> Array[Vector2]:
	var m := outline.size()
	var out: Array[Vector2] = []
	for i in m:
		var p := outline[(i - 1 + m) % m]
		var q := outline[i]
		var r := outline[(i + 1) % m]
		var t0 := (q - p).normalized()
		var t1 := (r - q).normalized()
		var l0 := Vector2(-t0.y, t0.x)          # (the interior's side)
		var l1 := Vector2(-t1.y, t1.x)
		var hit: Variant = Geometry2D.line_intersects_line(p + l0 * dist, t0, q + l1 * dist, t1)
		out.append(hit if hit != null else q + l0 * dist)
	return out


# ---------------------------------------------------------------- the holes of each face

## The sawtooth's long faces (their outer point to their inner one, east; the other way, west): a small square
## window a floor near the inner corner, now and then a slit.
func _long_face_holes(k: int, west: bool) -> Array:
	var length := sqrt(TOOTH * TOOTH + D * D)
	var out := []
	for f in range(1, FLOORS + 1):
		var y := floor_y(f)
		if (k + f) % 4 == 1 and k > 3:
			var s := [0.5, 2.9] if west else [length - 2.9, length - 0.5]
			out.append([s[0], s[1], y + 1.55, y + 2.05, "win"])
		else:
			var s := [0.95, 1.75] if west else [length - 1.75, length - 0.95]
			out.append([s[0], s[1], y + 1.15, y + 2.0, "win_c" if _rng.randf() < 0.25 else "win"])
	return out


## The sawtooth's short faces (looking south): a tall window a floor.
func _short_face_holes() -> Array:
	var out := []
	for f in range(1, FLOORS + 1):
		var y := floor_y(f)
		out.append([0.35, D - 0.35, y + 0.45, y + 2.35, "win_c" if _rng.randf() < 0.2 else "win"])
	return out


## A blank gable: the joints of its big panels.
func _gable_holes(length: float) -> Array:
	var out := []
	for y: float in [GF_H + 0.03, floor_y(3) - 0.02, floor_y(5) - 0.02]:
		out.append([0.04, length - 0.04, y, y + 0.03, "groove"])
	return out


## The courtyard's ribbon windows, a floor each.
func _ribbon_holes(length: float) -> Array:
	var out := []
	for f in range(1, FLOORS + 1):
		var y := floor_y(f)
		out.append([0.8, length - 0.8, y + 0.85, y + 2.25, "ribbon"])
	return out


## The courtyard's north corners: the french windows onto the balconies (`east`: the east wing's, from the north).
func _notch_holes(length: float, _east: bool) -> Array:
	var out := []
	for f in range(1, FLOORS + 1):
		var y := floor_y(f)
		for s: float in [1.3, length - 2.9]:
			out.append([s, s + 1.6, y + 0.06, y + 2.3, "door"])
	return out


func _small_face_holes() -> Array:
	var out := []
	for f in range(1, FLOORS + 1):
		var y := floor_y(f)
		out.append([0.9, 1.8, y + 0.9, y + 2.2, "win"])
	return out


## The colonnades' black glazing: a pane between two columns, a door in the fifth.
func _colonnade_holes() -> Array:
	var out := []
	for k in TEETH:
		var s0 := k * TOOTH + 0.32
		var s1 := (k + 1) * TOOTH - 0.32
		if k == 4:
			out.append([s0 + 0.6, s1 - 0.6, 0.0, 2.7, "dark_door"])
		else:
			out.append([s0, s1, 0.15, 4.2, "dark"])
	return out


## The courtyard's ground floor: windows every 4.5 m, `doors` doors among them.
func _gf_holes(length: float, doors: int) -> Array:
	var out := []
	var n := maxi(1, int((length - 1.6) / 4.5))
	var step := (length - 1.6) / n
	var door_at := []
	for i in doors:
		door_at.append(int(round((i + 0.5) * n / doors - 0.5)))
	for i in n:
		var s := 0.8 + step * i + (step - 2.2) * 0.5
		if i in door_at:
			out.append([s + 0.1, s + 2.1, 0.0, 2.7, "door"])
		else:
			out.append([s, s + 2.2, 0.6, 3.4, "win"])
	return out


# ---------------------------------------------------------------- the street facades

## Street face `f` ("S" the boulevard, "W" and "E" the returns from their corner): along c from its corner, d out of
## the facade line. A box from (c0, d0) to (c1, d1), y0 to y1.
func _sbox(f: String, mat: String, c0: float, c1: float, y0: float, y1: float, d0: float, d1: float, col := false) -> void:
	var r := _srect(f, c0, c1, d0, d1)
	_box(mat, r[0], r[1], y0, y1, r[2], r[3])
	if col:
		_col(r[0], r[1], y0, y1, r[2], r[3])


static func _srect(f: String, c0: float, c1: float, d0: float, d1: float) -> Array:
	match f:
		"S": return [c0, c1, -d1, -d0]
		"W": return [-d1, -d0, c0, c1]
		_: return [LEN + d0, LEN + d1, c0, c1]


## A quad on street face `f` at d, from c0 to c1, y0 to y1, looking out.
func _squad(f: String, mat: String, c0: float, c1: float, y0: float, y1: float, d: float) -> void:
	var a := _splan(f, c0, d)
	var b := _splan(f, c1, d)
	var out := {"S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}[f] as Vector3
	_quad(_tool(mat, true), _p(a.x, y0, a.y), _p(b.x, y0, b.y), _p(b.x, y1, b.y), _p(a.x, y1, a.y), out)


static func _splan(f: String, c: float, d: float) -> Vector2:
	match f:
		"S": return Vector2(c, -d)
		"W": return Vector2(-d, c)
		_: return Vector2(LEN + d, c)


## The ground floor on the street: white columns, the black-framed glazing between them (shop windows, the yellow
## glass at the corners, frosted glass), the white slab band over it, the stone threshold, the shops behind.
func _street_ground_floor() -> void:
	# the corner columns, the slab band, the threshold, the shops' floor and ceiling
	_box("column_white", -0.05, 0.5, 0.0, 4.4, -0.05, 0.5)
	_box("column_white", LEN - 0.5, LEN + 0.05, 0.0, 4.4, -0.05, 0.5)
	_box("slab_white", -0.1, LEN + 0.1, 4.4, GF_H, -0.1, GF_IN)
	_box("slab_white", -0.1, GF_IN, 4.4, GF_H, GF_IN, BAR)
	_box("slab_white", LEN - GF_IN, LEN + 0.1, 4.4, GF_H, GF_IN, BAR)
	_box("granite", 0.0, LEN, _yb, 0.0, 0.0, 0.3)
	_box("granite", 0.0, 0.3, _yb, 0.0, 0.3, BAR)
	_box("granite", LEN - 0.3, LEN, _yb, 0.0, 0.3, BAR)
	_box("shop_floor", 0.3, LEN - 0.3, -0.3, 0.0, 0.3, GF_IN)
	_box("shop_floor", 0.3, GF_IN, -0.3, 0.0, GF_IN, BAR)
	_box("shop_floor", LEN - GF_IN, LEN - 0.3, -0.3, 0.0, GF_IN, BAR)
	_box("ceiling", 0.45, LEN - 0.45, 3.65, 4.39, 0.45, GF_IN)
	_box("ceiling", 0.45, GF_IN, 3.65, 4.39, GF_IN, BAR - 0.3)
	_box("ceiling", LEN - GF_IN, LEN - 0.45, 3.65, 4.39, GF_IN, BAR - 0.3)
	# the returns' shops closed at the colonnade, between the last column and the colonnade's glazing
	_box("colonnade_wall", 0.6, COL, 0.0, 4.4, BAR - 0.3, BAR)
	_box("colonnade_wall", LEN - COL, LEN - 0.6, 0.0, 4.4, BAR - 0.3, BAR)
	# the modules
	for i in 10:
		var c0 := 0.5 if i == 0 else MODULE * i + 0.25
		var c1 := LEN - 0.5 if i == 9 else MODULE * (i + 1) - 0.25
		if i > 0:
			_sbox("S", "column_white", MODULE * i - 0.25, MODULE * i + 0.25, 0.0, 4.4, -0.6, 0.05)
			if SOUTH_GF[i] != SOUTH_GF[i - 1]:
				_sbox("S", "shop_wall", MODULE * i - 0.06, MODULE * i + 0.06, 0.0, 3.65, -GF_IN, -0.6)
		_module("S", c0, c1, SOUTH_GF[i])
	for f: String in ["W", "E"]:
		var kinds: Array = WEST_GF if f == "W" else EAST_GF
		_sbox(f, "column_white", 6.5, 7.0, 0.0, 4.4, -0.6, 0.05)
		_sbox(f, "column_white", BAR - 0.5, BAR, 0.0, 4.4, -0.6, 0.05)
		_sbox(f, "shop_wall", 6.69, 6.81, 0.0, 3.65, -GF_IN, -0.6)
		_module(f, 0.5, 6.5, kinds[0])
		_module(f, 7.0, BAR - 0.5, kinds[1])


## A glazed module on street face `f` from c0 to c1 (between two columns), of `kind`: its frame, mullions, transom,
## the glass (the shops' see-through), its door, what is behind it.
func _module(f: String, c0: float, c1: float, kind: String) -> void:
	var fd0 := -0.42
	var fd1 := -0.3
	var n := maxi(2, roundi((c1 - c0) / 2.1))
	var w := (c1 - c0) / n
	# the frame: its posts full height, rails and transom between them, mullions
	_sbox(f, "black_frame", c0, c0 + 0.08, 0.0, 4.4, fd0, fd1)
	_sbox(f, "black_frame", c1 - 0.08, c1, 0.0, 4.4, fd0, fd1)
	for k in range(1, n):
		var m := c0 + w * k
		_sbox(f, "black_frame", m - 0.035, m + 0.035, 0.1, 4.32, fd0 + 0.01, fd1 - 0.01)
	_sbox(f, "black_frame", c0 + 0.08, c1 - 0.08, 0.0, 0.1, fd0, fd1)
	_sbox(f, "black_frame", c0 + 0.08, c1 - 0.08, 3.55, 3.65, fd0, fd1)
	_sbox(f, "black_frame", c0 + 0.08, c1 - 0.08, 4.32, 4.4, fd0, fd1)
	var lower: String = {"yellow": "yellow_glass", "frosted": "frosted"}.get(kind, "glass_shop")
	_squad(f, lower, c0, c1, 0.1, 3.55, -0.36)
	_squad(f, "glass_shop", c0, c1, 3.65, 4.32, -0.36)
	if kind in ["yellow", "frosted"]:
		return
	# the door in the middle third: its head, handles (a double door at the residence's entrance)
	var dm := c0 + w * floorf(n * 0.5) + (w * 0.5 if n % 2 == 1 else 0.0)
	var half := 0.95 if kind == "entrance" else 0.5
	_sbox(f, "black_frame", dm - half, dm + half, 2.45, 2.52, fd0 + 0.01, fd1 - 0.01)
	if kind == "entrance":
		_sbox(f, "black_frame", dm - 0.03, dm + 0.03, 0.1, 2.45, fd0 + 0.01, fd1 - 0.01)
	for hx: float in ([dm - 0.12, dm + 0.12] if kind == "entrance" else [dm + half - 0.15]):
		_sbox(f, "steel", hx - 0.015, hx + 0.015, 0.9, 1.9, -0.29, -0.26)
	_door_step(f, dm - half - 0.2, dm + half + 0.2)
	# inside: lights under the ceiling, the shop's fittings
	_detail = true
	for k in n:
		var m := c0 + w * (k + 0.5)
		_sbox(f, "emit_light", m - 0.5, m + 0.5, 3.615, 3.645, -2.0, -1.4)
	match kind:
		"shop", "pharmacy":
			_sbox(f, "counter", c0 + 0.6, c0 + 2.2, 0.0, 1.0, -2.4, -1.9)
			var shelf := "shelf_green" if kind == "pharmacy" else "shelf"
			_sbox(f, shelf, c0 + 0.4, c1 - 0.4, 0.0, 2.1, -GF_IN, -GF_IN + 0.4)
			for y: float in [0.7, 1.4]:
				_sbox(f, "shop_floor", c0 + 0.4, c1 - 0.4, y, y + 0.04, -GF_IN + 0.4, -GF_IN + 0.45)
		"restaurant":
			_sbox(f, "wood", c0 + 0.5, c0 + 2.6, 0.0, 1.05, -GF_IN, -GF_IN + 0.6)
			for k in 3:
				var tx := c0 + 3.4 + k * 1.0
				if tx + 0.4 < c1:
					_scyl(f, "wood", tx, -1.6, 0.72, 0.04, 0.38)
					_scyl(f, "black_frame", tx, -1.6, 0.0, 0.72, 0.05)
		"entrance", "lobby":
			_sbox(f, "letterbox", c0 + 0.5, c0 + 2.9, 0.4, 1.9, -GF_IN, -GF_IN + 0.3)
			_sbox(f, "sofa", c1 - 2.6, c1 - 0.6, 0.0, 0.45, -GF_IN, -GF_IN + 0.85)
			_sbox(f, "sofa", c1 - 2.6, c1 - 0.6, 0.45, 0.85, -GF_IN, -GF_IN + 0.2)
	_detail = false


## Steps up to a street door where the sidewalk is under the floor (the threshold is the top one).
func _door_step(f: String, c0: float, c1: float) -> void:
	var p := _splan(f, (c0 + c1) * 0.5, 0.5)
	var drop := -float(_ground.call(p.x, p.y))
	if drop < 0.08:
		return
	var k := ceili(drop / 0.17) - 1
	for i in k:
		var top := -drop * float(i + 1) / float(k + 1)
		_sbox(f, "granite", c0, c1, _yb, top, 0.34 * i, 0.34 * (i + 1), true)


func _scyl(f: String, mat: String, c: float, d: float, y: float, h: float, r: float) -> void:
	var p := _splan(f, c, d)
	_cyl(mat, _p(p.x, y, p.y), r, h)


## The floors over it: the black mullions of every bay (over the roof's edge), the corner posts, a bay at a time and a
## floor at a time its panels round a window (louvred shutters), or a loggia; the corner loggias; the skin's roof.
func _street_upper() -> void:
	var top := ROOF + PARA + 0.05
	_box("black_frame", -0.08, 0.12, GF_H, top, -0.08, 0.12)
	_box("black_frame", LEN - 0.12, LEN + 0.08, GF_H, top, -0.08, 0.12)
	# the south facade
	for k in BAYS:
		var c0 := k * BAY
		var c1 := c0 + BAY
		if k > 0:
			_mullion("S", c0 - 0.05, c0 + 0.05)
		var lo := 0.12 if k == 0 else c0 + 0.05
		var hi := LEN - 0.12 if k == BAYS - 1 else c1 - 0.05
		var corner := k == 0 or k == BAYS - 1
		_bay("S", lo, hi, corner, corner)
		_skin_roof("S", 0.0 if k == 0 else lo, LEN if k == BAYS - 1 else hi)
	# the returns: the corner loggia's other side, three bays, the mullion ending the skin at the sawtooth
	for f: String in ["W", "E"]:
		var ends := [0.0, BAY, 2.0 * BAY, 3.0 * BAY, BAR - 0.1]
		for j in 4:
			var c0: float = ends[j]
			var c1: float = ends[j + 1]
			if j > 0:
				_mullion(f, c0 - 0.05, c0 + 0.05)
			var lo := SKIN if j == 0 else c0 + 0.05
			var hi := c1 - 0.05 if j < 3 else c1
			_bay(f, lo, hi, j == 0, j == 0)
			_skin_roof(f, lo, hi)
		_mullion(f, BAR - 0.1, BAR)


## The skin's roof over a bay (c0..c1): gravel over it, white under it (the top loggias' ceiling).
func _skin_roof(f: String, c0: float, c1: float) -> void:
	_sbox(f, "slab_white", c0, c1, ROOF - 0.01, ROOF - 0.005, -SKIN, 0.0)
	_sbox(f, "roof_gravel", c0, c1, ROOF - 0.005, ROOF, -SKIN, 0.0)


## A black mullion on street face `f` from c0 to c1: through the skin, its crown over the parapet.
func _mullion(f: String, c0: float, c1: float) -> void:
	_sbox(f, "black_frame", c0, c1, GF_H, ROOF, -SKIN, 0.08)
	_sbox(f, "black_frame", c0, c1, ROOF, ROOF + PARA + 0.05, -0.05, 0.08)


## A bay of street face `f` between its mullions (c0..c1), five floors: loggias (`loggia`: all of them; `corner`: the
## loggia runs round the corner, its rail from the corner post), or its panels round a window.
func _bay(f: String, c0: float, c1: float, loggia: bool, corner: bool) -> void:
	for fl in range(1, FLOORS + 1):
		var y := floor_y(fl)
		var kind := "L" if loggia else ("L" if _rng.randf() < 0.1 else ("S" if _rng.randf() < 0.35 else "W"))
		if kind == "L":
			_loggia(f, c0, c1, y, corner)
		else:
			_panels(f, c0, c1, y, kind == "S")


## A loggia: its deck, the glass rail, the glazed door in its back wall (the core).
func _loggia(f: String, c0: float, c1: float, y: float, corner: bool) -> void:
	var dc0 := 0.0 if corner and f == "S" and c0 < 1.0 else c0
	var dc1 := LEN if corner and f == "S" and c1 > LEN - 1.0 else c1
	_sbox(f, "slab_white", dc0, dc1, y - 0.01, y + 0.12, -SKIN, 0.0)
	var r0 := 0.12 if corner and f != "S" else c0
	_detail = true
	_sbox(f, "rail_glass", r0, c1, y + 0.12, y + 1.05, -0.07, -0.05)
	_sbox(f, "black_frame", r0, c1, y + 1.05, y + 1.09, -0.09, -0.03)
	_detail = false
	# the glazed door: in the core's face, where the loggia is in front of it
	var b0 := maxf(c0, SKIN) if corner else c0
	var b1 := minf(c1, LEN - SKIN) if corner and f == "S" else c1
	var x0 := b0 + 0.25
	var x1 := minf(b1 - 0.25, x0 + 1.7)
	if x1 - x0 < 0.8:
		return
	var d0 := -SKIN
	_sbox(f, "glass_win", x0 + 0.05, x1 - 0.05, y + 0.12, y + 2.35, d0, d0 + 0.03)
	_sbox(f, "black_frame", x0, x0 + 0.05, y + 0.12, y + 2.35, d0, d0 + 0.06)
	_sbox(f, "black_frame", x1 - 0.05, x1, y + 0.12, y + 2.35, d0, d0 + 0.06)
	_sbox(f, "black_frame", x0, x1, y + 2.35, y + 2.42, d0, d0 + 0.06)
	_sbox(f, "black_frame", (x0 + x1) * 0.5 - 0.025, (x0 + x1) * 0.5 + 0.025, y + 0.12, y + 2.35, d0 + 0.03, d0 + 0.05)


## A floor of a bay in cladding panels round a tall window (2 cm joints between them, the dark core behind), its sill;
## `shutter`: a louvred panel slid over part of it on its rails.
func _panels(f: String, c0: float, c1: float, y: float, shutter: bool) -> void:
	var ww := 0.95
	var pos := _rng.randi() % 3
	var w0 := c0 + 0.45 if pos == 0 else (c1 - 0.45 - ww if pos == 1 else (c0 + c1 - ww) * 0.5)
	var w1 := w0 + ww
	var oy0 := y + 0.35
	var oy1 := y + 2.45
	var py0 := y + 0.01
	var py1 := y + FH - 0.01
	# the panels either side (a wide one in two), the spandrel and the lintel
	for side: Array in [[c0, w0 - 0.02], [w1 + 0.02, c1]]:
		var a: float = side[0]
		var b: float = side[1]
		if b - a < 0.05:
			continue
		if b - a > 1.4 and _rng.randf() < 0.6:
			var m := a + (b - a) * _rng.randf_range(0.35, 0.65)
			_sbox(f, _clad(), a, m - 0.01, py0, py1, -SKIN, 0.0)
			_sbox(f, _clad(), m + 0.01, b, py0, py1, -SKIN, 0.0)
		else:
			_sbox(f, _clad(), a, b, py0, py1, -SKIN, 0.0)
	var under := _clad()
	_sbox(f, under, w0 - 0.02, w1 + 0.02, py0, oy0, -SKIN, 0.0)
	_sbox(f, under, w0 - 0.02, w1 + 0.02, oy1, py1, -SKIN, 0.0)
	# the window: glass, frame, sill
	var glass := "glass_curtain" if _rng.randf() < 0.22 else "glass_win"
	_sbox(f, glass, w0 + 0.01, w1 - 0.01, oy0 + 0.01, oy1 - 0.01, -0.24, -0.2)
	_sbox(f, "black_frame", w0 - 0.02, w0 + 0.05, oy0, oy1, -0.25, -0.17)
	_sbox(f, "black_frame", w1 - 0.05, w1 + 0.02, oy0, oy1, -0.25, -0.17)
	_sbox(f, "black_frame", w0 + 0.05, w1 - 0.05, oy0, oy0 + 0.05, -0.25, -0.17)
	_sbox(f, "black_frame", w0 + 0.05, w1 - 0.05, oy1 - 0.05, oy1, -0.25, -0.17)
	_sbox(f, "black_frame", w0 + 0.05, w1 - 0.05, y + 1.05, y + 1.09, -0.23, -0.18)     # (the guard bar)
	_sbox(f, "coping", w0 - 0.05, w1 + 0.05, oy0 - 0.04, oy0 + 0.02, -0.15, 0.04)
	if not shutter:
		return
	# the louvred shutter, slid over the window (shut, half open) or beside it, along its rails
	var sw := ww + 0.12
	var shut := w0 - 0.06
	var x: float = [shut, shut + sw * 0.5, shut][_rng.randi() % 3]
	if _rng.randf() < 0.4:
		if w1 + 0.04 + sw <= c1:
			x = w1 + 0.04
		elif w0 - 0.04 - sw >= c0:
			x = w0 - 0.04 - sw
	var r0 := maxf(minf(x, shut) - 0.04, c0)
	var r1 := minf(maxf(x + sw, shut + sw) + 0.04, c1)
	_sbox(f, "louvre", x, x + sw, oy0 - 0.06, oy1 + 0.05, 0.03, 0.07)
	_sbox(f, "steel", r0, r1, oy1 + 0.05, oy1 + 0.09, 0.0, 0.08)
	_sbox(f, "steel", r0, r1, oy0 - 0.1, oy0 - 0.07, 0.0, 0.06)


func _clad() -> String:
	return CLADS[_rng.randi() % CLADS.size()]


# ---------------------------------------------------------------- the wings, the courtyard, the roof

## Under each wing's sawtooth: the black canopy, its columns at the teeth, the pavers (made in _paving).
func _colonnades() -> void:
	for west: bool in [true, false]:
		var u0 := 0.0 if west else LEN - COL
		var u1 := COL if west else LEN
		_box("black_frame", u0, u1, 4.6, GF_H, BAR, NORTH)
		var cu0 := 0.05 if west else LEN - 0.35
		for k in range(1, TEETH + 1):
			var v := BAR + k * TOOTH if k < TEETH else NORTH - 0.35
			_box("black_frame", cu0, cu0 + 0.3, _yb, 4.6, v - 0.15, v + 0.15)


## The pavers under the colonnades: a grid over the ground (collision with it).
func _paving() -> void:
	var faces := PackedVector3Array()
	for r: Array in [[0.0, BAR, COL, NORTH], [LEN - COL, BAR, LEN, NORTH]]:
		var nu := 3
		var nv := ceili((float(r[3]) - float(r[1])) / 0.5)
		var pts := []
		for i in nu + 1:
			var row := []
			var u := lerpf(r[0], r[2], float(i) / nu)
			for j in nv + 1:
				var v := lerpf(r[1], r[3], float(j) / nv)
				row.append(_p(u, minf(float(_ground.call(u, v)) + 0.05, -0.02), v))
			pts.append(row)
		for i in nu:
			for j in nv:
				var q := [pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1]]
				faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
				_quad(_tool("pavers", true), q[0], q[1], q[2], q[3], Vector3.UP)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)


## The balconies stacked in the courtyard's north corners: white slabs, glass rails, a black post.
func _balconies() -> void:
	for west: bool in [true, false]:
		var ua := NOTCH_IN if west else LEN - WING + 0.1
		var ub := WING - 0.1 if west else LEN - NOTCH_IN
		var ue := ub if west else ua            # (the open side's edge)
		for fl in range(1, FLOORS + 1):
			var y := floor_y(fl)
			_box("slab_white", ua, ub, y - 0.18, y + 0.02, NOTCH_V, NORTH - 0.1)
			_detail = true
			var ru0 := ue - 0.08 if west else ue + 0.06
			_box("rail_glass", ru0, ru0 + 0.02, y + 0.02, y + 1.0, NOTCH_V, NORTH - 0.18)
			_box("rail_glass", ua, ub, y + 0.02, y + 1.0, NORTH - 0.18, NORTH - 0.16)
			_box("black_frame", ru0 - 0.01, ru0 + 0.03, y + 1.0, y + 1.04, NOTCH_V, NORTH - 0.19)
			_box("black_frame", ua, ub, y + 1.0, y + 1.04, NORTH - 0.19, NORTH - 0.15)
			_detail = false
		var pu := ub - 0.07 if west else ua + 0.07
		_rod("black_frame", _p(pu, GF_H - 0.2, NORTH - 0.17), _p(pu, ROOF - 0.1, NORTH - 0.17), 0.06)


## On the roof: the stair and lift cores, the plant, solar panels over the south bar, rails along the sawtooth.
func _roof() -> void:
	for core: Array in [[31.0, 36.5, 3.6, 9.2], [4.6, 9.8, 27.0, 32.5], [LEN - 9.8, LEN - 4.6, 27.0, 32.5]]:
		var u0: float = core[0]
		var u1: float = core[1]
		var v0: float = core[2]
		var v1: float = core[3]
		_box("render_white", u0, u1, ROOF, ROOF + 3.0, v0, v1)
		_col(u0, u1, ROOF, ROOF + 3.0, v0, v1)
		_box("coping", u0 - 0.05, u1 + 0.05, ROOF + 3.0, ROOF + 3.12, v0 - 0.05, v1 + 0.05)
		_box("door_grey", (u0 + u1) * 0.5 - 0.5, (u0 + u1) * 0.5 + 0.5, ROOF + 0.05, ROOF + 2.15, v1, v1 + 0.04)
	# the plant and the solar panels on the south bar
	_detail = true
	for unit: Array in [[12.0, 14.6, 4.0, 5.8], [16.0, 18.6, 4.0, 5.8], [58.5, 60.5, 4.5, 7.5]]:
		_box("unit", unit[0], unit[1], ROOF, ROOF + 1.4, unit[2], unit[3])
		_box("grille", float(unit[0]) + 0.2, float(unit[1]) - 0.2, ROOF + 0.3, ROOF + 1.2, float(unit[3]),
				float(unit[3]) + 0.02)
	for row in 2:
		for i in 9:
			var u := 39.0 + i * 1.8
			var v := 3.4 + row * 3.6
			var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(18.0)), _p(u + 0.85, ROOF + 0.55, v + 0.8))
			_xbox("solar", xf, Vector3(1.7, 0.04, 1.0))
			_box("steel", u + 0.1, u + 0.16, ROOF, ROOF + 0.42, v + 0.2, v + 0.26)
			_box("steel", u + 1.54, u + 1.6, ROOF, ROOF + 0.42, v + 0.2, v + 0.26)
	_detail = false


## The rails along the sawtooth's parapets (coin2): posts on the coping's middle line `path`, two rails.
func _rails(path: Array[Vector2]) -> void:
	_detail = true
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		for y: float in [ROOF + PARA + 0.5, ROOF + PARA + 1.0]:
			_rod("steel", _p(a.x, y, a.y), _p(b.x, y, b.y), 0.022)
		var n := maxi(1, ceili(a.distance_to(b) / 1.4))
		for j in n + (1 if i == path.size() - 2 else 0):
			var p := a.lerp(b, float(j) / n)
			_rod("steel", _p(p.x, ROOF + PARA, p.y), _p(p.x, ROOF + PARA + 1.02, p.y), 0.02)
	_detail = false


## The residence's name over its door, the shops' signs.
func _signs() -> void:
	var entrance := MODULE * 3.5
	_sbox("S", "black_frame", entrance - 2.5, entrance + 2.5, 4.47, 4.83, 0.1, 0.14)
	_label("ALL SUITES STUDY", Transform3D(Basis.IDENTITY, Vector3(entrance, 4.65, 0.145)), 72, 0.0055, Color("#f4f2ec"))
	var resto := MODULE * 8.0
	_sbox("S", "black_frame", resto - 2.0, resto + 2.0, 4.47, 4.83, 0.1, 0.14)
	_label("TRATTORIA", Transform3D(Basis.IDENTITY, Vector3(resto, 4.65, 0.145)), 72, 0.0055, Color("#f0c56a"))
	# the pharmacy's green cross, out of the slab band
	var px := MODULE * 1.0 + 0.6
	_detail = true
	_sbox("S", "steel", px - 0.03, px + 0.03, 4.55, 4.75, 0.1, 0.5)
	_sbox("S", "sign_green", px - 0.06, px + 0.06, 4.2, 5.1, 0.5, 1.1)
	_sbox("S", "sign_green", px - 0.05, px + 0.05, 4.5, 4.8, 0.2, 1.4)
	_detail = false


# ---------------------------------------------------------------- collision

func _collision() -> void:
	# the upper floors (the street skin to its facade line), the sawtooth's teeth, the roof's parapet
	_col(0.0, LEN, 4.4, ROOF, 0.0, BAR)
	for west: bool in [true, false]:
		var ua := D if west else LEN - WING
		var ub := WING if west else LEN - D
		_col(ua, ub, 4.6, ROOF, BAR, NOTCH_V)
		_col(ua if west else LEN - NOTCH_IN, NOTCH_IN if west else ub, 4.6, ROOF, NOTCH_V, NORTH)
		_col(0.0 if west else LEN - COL, COL if west else LEN, 4.6, GF_H, BAR, NORTH)
		for k in TEETH:
			var a := BAR + k * TOOTH
			var tri := [Vector2(0, a), Vector2(D, a), Vector2(D, a + TOOTH)] if west else \
					[Vector2(LEN, a), Vector2(LEN - D, a), Vector2(LEN - D, a + TOOTH)]
			var pts := PackedVector3Array()
			for p: Vector2 in tri:
				pts.append(_p(p.x, GF_H, p.y))
				pts.append(_p(p.x, ROOF, p.y))
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			var cs := CollisionShape3D.new()
			cs.shape = shape
			_body.add_child(cs)
		# the ground floor at its glazing, the colonnade's columns
		var ga := COL if west else LEN - WING
		var gb := WING if west else LEN - COL
		_col(ga, gb, _yb, GF_H, BAR, NOTCH_V)
		_col(ga if west else LEN - NOTCH_IN, NOTCH_IN if west else gb, _yb, GF_H, NOTCH_V, NORTH)
		var cu0 := 0.05 if west else LEN - 0.35
		for k in range(1, TEETH + 1):
			var v := BAR + k * TOOTH if k < TEETH else NORTH - 0.35
			_col(cu0, cu0 + 0.3, _yb, 4.6, v - 0.15, v + 0.15)
	_col(GLAZ, LEN - GLAZ, _yb, 4.4, GLAZ, BAR)
	_col(0.0, LEN, _yb, 0.0, 0.0, GLAZ)
	_col(0.0, GLAZ, _yb, 0.0, GLAZ, BAR)
	_col(LEN - GLAZ, LEN, _yb, 0.0, GLAZ, BAR)
	# the street columns
	_col(-0.05, 0.5, 0.0, 4.4, -0.05, 0.5)
	_col(LEN - 0.5, LEN + 0.05, 0.0, 4.4, -0.05, 0.5)
	for i in range(1, 10):
		_col(MODULE * i - 0.25, MODULE * i + 0.25, 0.0, 4.4, -0.05, 0.6)
	for c: float in [6.5, BAR - 0.5]:
		_col(-0.05, 0.6, 0.0, 4.4, c, c + 0.5)
		_col(LEN - 0.6, LEN + 0.05, 0.0, 4.4, c, c + 0.5)
	# the parapets on the straight edges
	var y0 := ROOF
	var y1 := ROOF + PARA
	_col(0.0, LEN, y0, y1, 0.0, PARA_T)
	_col(0.0, PARA_T, y0, y1, PARA_T, BAR)
	_col(LEN - PARA_T, LEN, y0, y1, PARA_T, BAR)
	_col(D, NOTCH_IN, y0, y1, NORTH - PARA_T, NORTH)
	_col(LEN - NOTCH_IN, LEN - D, y0, y1, NORTH - PARA_T, NORTH)
	_col(WING, LEN - WING, y0, y1, BAR, BAR + PARA_T)
	_col(WING - PARA_T, WING, y0, y1, BAR, NOTCH_V)
	_col(LEN - WING, LEN - WING + PARA_T, y0, y1, BAR, NOTCH_V)


# ---------------------------------------------------------------- mesh building

## A point of the plan (u, v) at height y, in the residence's frame.
static func _p(u: float, y: float, v: float) -> Vector3:
	return Vector3(u, y, -v)


## A point on the face from `a` along `t` (its outward normal `n`): s along it, y, d out of it.
static func _fp(a: Vector2, t: Vector2, n: Vector2, s: float, y: float, d: float) -> Vector3:
	var p := a + t * s + n * d
	return Vector3(p.x, y, -p.y)


## The surface of `mat` (details apart). Everything is drawn in raw triangles (no primitive meshes: headless, the tests
## have none).
func _tool(mat: String, _raw := false) -> SurfaceTool:
	var key := mat + ("|d" if _detail else "")
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


## A triangle facing `n` (Godot's front faces are wound clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var x := b
		b = c
		c = x
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## A box over the plan's (u0..u1, v0..v1), y0..y1.
func _box(mat: String, u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> void:
	if absf(u1 - u0) < 0.002 or absf(y1 - y0) < 0.002 or absf(v1 - v0) < 0.002:
		return
	_xbox(mat, Transform3D(Basis.IDENTITY, Vector3((u0 + u1) * 0.5, (y0 + y1) * 0.5, -(v0 + v1) * 0.5)),
			Vector3(absf(u1 - u0), absf(y1 - y0), absf(v1 - v0)))


## A box on a face (from `a` along `t`, looking `n`): s0..s1, y0..y1, d0..d1 out of it.
func _fbox(mat: String, a: Vector2, t: Vector2, n: Vector2, s0: float, s1: float, y0: float, y1: float, d0: float,
		d1: float) -> void:
	if s1 - s0 < 0.002 or y1 - y0 < 0.002 or d1 - d0 < 0.002:
		return
	var basis := Basis(Vector3(t.x, 0, -t.y), Vector3.UP, Vector3(n.x, 0, -n.y))
	_xbox(mat, Transform3D(basis, _fp(a, t, n, (s0 + s1) * 0.5, (y0 + y1) * 0.5, (d0 + d1) * 0.5)),
			Vector3(s1 - s0, y1 - y0, d1 - d0))


func _fcol(a: Vector2, t: Vector2, n: Vector2, s0: float, s1: float, y0: float, y1: float, d0: float, d1: float) -> void:
	var s := BoxShape3D.new()
	s.size = Vector3(s1 - s0, y1 - y0, d1 - d0)
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = Transform3D(Basis(Vector3(t.x, 0, -t.y), Vector3.UP, Vector3(n.x, 0, -n.y)),
			_fp(a, t, n, (s0 + s1) * 0.5, (y0 + y1) * 0.5, (d0 + d1) * 0.5))
	_body.add_child(cs)


## A box of `size` centred on frame `xf` (an orthonormal basis): its six faces.
func _xbox(mat: String, xf: Transform3D, size: Vector3) -> void:
	var st := _tool(mat)
	var h := size * 0.5
	for ax in 3:
		for sign: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sign
			var u := Vector3.ZERO
			var w := Vector3.ZERO
			u[(ax + 1) % 3] = 1.0
			w[(ax + 2) % 3] = 1.0
			var c := n * h[ax]
			var du := u * h[(ax + 1) % 3]
			var dw := w * h[(ax + 2) % 3]
			_quad(st, xf * (c - du - dw), xf * (c + du - dw), xf * (c + du + dw), xf * (c - du + dw),
					(xf.basis * n).normalized())


## An upright cylinder from p up h, radius r.
func _cyl(mat: String, p: Vector3, r: float, h: float, seg := 14) -> void:
	_prism(mat, Transform3D(Basis.IDENTITY, p), r, h, seg)


## A cylinder from a to b, radius r.
func _rod(mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_prism(mat, Transform3D(Basis(x, y, x.cross(y)), a), r, length, 8)


## A `seg`-sided prism along frame xf's y from its origin up h, radius r: its sides and caps.
func _prism(mat: String, xf: Transform3D, r: float, h: float, seg: int) -> void:
	var st := _tool(mat)
	var ring := []
	for k in seg:
		var ang := TAU * k / seg
		ring.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))
	var up := (xf.basis * Vector3.UP).normalized()
	var top := xf * Vector3(0, h, 0)
	var bottom := xf.origin
	for k in seg:
		var p: Vector3 = ring[k]
		var q: Vector3 = ring[(k + 1) % seg]
		var mid := (xf.basis * ((p + q) * 0.5)).normalized()
		_quad(st, xf * p, xf * q, xf * (q + Vector3(0, h, 0)), xf * (p + Vector3(0, h, 0)), mid)
		_tri(st, bottom, xf * p, xf * q, -up)
		_tri(st, top, xf * (p + Vector3(0, h, 0)), xf * (q + Vector3(0, h, 0)), up)


func _col(u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> void:
	var s := BoxShape3D.new()
	s.size = Vector3(absf(u1 - u0), absf(y1 - y0), absf(v1 - v0))
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3((u0 + u1) * 0.5, (y0 + y1) * 0.5, -(v0 + v1) * 0.5)
	_body.add_child(cs)


func _label(text: String, xf: Transform3D, size: int, pixel: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.transform = xf
	l.visibility_range_end = 220.0
	_root.add_child(l)
	return l


## One mesh instance a material (details drawn up to 220 m), glass casting no shadow.
func _commit() -> void:
	for key: String in _st:
		var mat := key.get_slice("|", 0)
		var mi := MeshInstance3D.new()
		mi.name = "M_" + key.replace("|", "_")
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _mat(mat)
		if mat in ["glass_shop", "rail_glass", "emit_light", "sign_green"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key.ends_with("|d"):
			mi.visibility_range_end = 220.0
		_root.add_child(mi)


# ---------------------------------------------------------------- materials

func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: StandardMaterial3D
	match name:
		"core": m = _plain(Color("#8b8e92"), 0.85)
		"clad_white": m = _metal(Color("#efefeb"), 0.42, 0.15)
		"clad_pearl": m = _metal(Color("#dedfdb"), 0.38, 0.2)
		"clad_silver": m = _metal(Color("#c4c7ca"), 0.34, 0.35)
		"clad_grey": m = _metal(Color("#a5a9ad"), 0.38, 0.35)
		"black_frame": m = _metal(Color("#1e1f22"), 0.45, 0.5)
		"glass_win": m = _metal(Color("#26303a"), 0.06, 0.7)
		"glass_curtain": m = _metal(Color("#8c867b"), 0.25, 0.15)
		"glass_dark": m = _metal(Color("#1b2127"), 0.08, 0.7)
		"glass_shop":
			m = _metal(Color(0.2, 0.25, 0.29, 0.6), 0.04, 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"rail_glass":
			m = _metal(Color(0.78, 0.86, 0.88, 0.22), 0.05, 0.3)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"yellow_glass": m = _metal(Color("#e9b62a"), 0.14, 0.2)
		"frosted": m = _metal(Color("#c3c9cc"), 0.3, 0.1)
		"slab_white": m = _plain(Color("#efeee9"), 0.7)
		"column_white": m = _plain(Color("#e9e7e1"), 0.6)
		"granite": m = _plain(Color("#7a7a7c"), 0.8)
		"shop_floor": m = _plain(Color("#cfc9be"), 0.35)
		"shop_wall": m = _plain(Color("#e8e3d9"), 0.85)
		"ceiling": m = _plain(Color("#f1efea"), 0.9)
		"render_white": m = _plain(Color("#ebeae5"), 0.92)
		"render_grey": m = _plain(Color("#d3d4d1"), 0.92)
		"gable_grey": m = _plain(Color("#cbcdcb"), 0.92)
		"sage": m = _metal(Color("#b0b8a4"), 0.55, 0.1)
		"spandrel_green": m = _metal(Color("#8e998a"), 0.5, 0.2)
		"colonnade_wall": m = _plain(Color("#3b3d41"), 0.7)
		"parapet_in": m = _plain(Color("#b9b9b5"), 0.9)
		"coping": m = _metal(Color("#c9cacb"), 0.4, 0.5)
		"steel": m = _metal(Color("#b9bec4"), 0.3, 0.7)
		"unit": m = _plain(Color("#b9bcbf"), 0.6)
		"grille": m = _plain(Color("#55595e"), 0.7)
		"solar": m = _metal(Color("#1d2b45"), 0.15, 0.6)
		"door_grey": m = _plain(Color("#5b5f64"), 0.6)
		"counter": m = _plain(Color("#3a3b3f"), 0.5)
		"shelf": m = _plain(Color("#d8d4cc"), 0.7)
		"shelf_green": m = _plain(Color("#cfe0d2"), 0.7)
		"wood": m = _plain(Color("#9a7550"), 0.6)
		"letterbox": m = _metal(Color("#9ea3a8"), 0.4, 0.5)
		"sofa": m = _plain(Color("#4a5560"), 0.9)
		"emit_light", "sign_green":
			var c := Color(1.0, 0.96, 0.88) if name == "emit_light" else Color(0.2, 0.85, 0.35)
			m = _plain(c, 0.5)
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5 if name == "emit_light" else 1.6
		"roof_gravel": m = _textured("gravel", 1.0 / 3.0, 0.95)
		"pavers": m = _textured("pavers", 1.0 / 1.6, 0.9)
		"louvre":
			m = _textured("louvre", 1.0 / 0.5, 0.45)
			m.metallic = 0.4
		_: m = _plain(Color("#ff00ff"), 1.0)
	_mats[name] = m
	return m


static func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _metal(c: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := _plain(c, rough)
	m.metallic = metallic
	return m


static func _textured(tex: String, scale: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## The textures, drawn once a session: roof gravel, concrete pavers (0.4 x 0.2 m, the texture spans 1.6 m), the
## shutters' horizontal louvres (a slat every 5 cm, the texture spans 0.5 m).
static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var img: Image
		var rng := RandomNumberGenerator.new()
		rng.seed = name.hash()
		match name:
			"gravel":
				img = Image.create(256, 256, false, Image.FORMAT_RGB8)
				var base := Color("#8e8b85")
				for y in 256:
					for x in 256:
						var s := rng.randf_range(-0.07, 0.07)
						img.set_pixel(x, y, Color(base.r + s, base.g + s, base.b + s * 0.8))
			"pavers":
				var n := 256
				img = Image.create(n, n, false, Image.FORMAT_RGB8)
				var base := Color("#b2aea6")
				var shades := []
				for i in 64:
					shades.append(rng.randf_range(-0.035, 0.035))
				for y in n:
					var row := y / (n / 8)
					var shift := (n / 8) * (row % 2)
					for x in n:
						var col := ((x + shift) % n) / (n / 4)
						var s: float = shades[(row * 4 + col) % 64] + rng.randf_range(-0.012, 0.012)
						var c := Color(base.r + s, base.g + s, base.b + s)
						if y % (n / 8) < 2 or (x + shift) % (n / 4) < 2:
							c = Color("#8b877f")
						img.set_pixel(x, y, c)
			_:
				img = Image.create(16, 160, false, Image.FORMAT_RGB8)
				var base := Color("#8d9297")
				for y in 160:
					var t := fmod(float(y) / 16.0, 1.0)
					var s := 0.08 if t < 0.25 else (-0.1 if t > 0.8 else 0.0)
					for x in 16:
						img.set_pixel(x, y, Color(base.r + s, base.g + s, base.b + s))
		img.generate_mipmaps()
		_textures[name] = ImageTexture.create_from_image(img)
	return _textures[name]
