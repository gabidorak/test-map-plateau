extends "res://scripts/street_kit.gd"
## Lot ligne18-universite's grounds drawn (universite_plan.gd: in the station's frame, on the designed ground): the
## paving (the bands along the kerbs: the kerb's top, the TCSP's strip, its two-way cycle track and sidewalk, the
## streets' sidewalks; the forecourts, the promenade, the paths), KERB high and lowered at the crossings, their faces
## down to the lawns; the granite kerb along the roads and its gutter; the stop's platform on the TCSP's south side,
## its kerb and its yellow zigzag; the markings of the roads redone (the centre lines of rue Sophie Germain and the
## TCSP, the cycle track's crossing of rue Sophie Germain) and the cycle track's (its dashed centre line, the
## bicycles). The map's zebras, stop lines and signals are kept where they are. Surfaces cut on a CELL m grid (they
## follow the designed ground), finer round the crossings. Collision: the paving's tops and faces.

const Plan = preload("res://lots/ligne18-universite/universite_plan.gd")
const CELL := 2.0                           # m: the surfaces cut on this grid (they follow the ground)
const RAMP_CELL := 0.75                     # m: round the crossings (their ramps)
const EDGE := 1.5                           # m: the faces' pieces at most
const MARK := 0.006                         # m: markings over the surface they are on
const BIKES := 30.0                         # m between two bicycles on the cycle track
const YELLOW := "#e3b622"
## The street kit's sidewalk() and corners read these off the plan (not used here).
const WALK_W := 3.0
const CORNER := 3.0


func _init() -> void:
	super("UniversiteGrounds", {"type": "lot", "lot": "ligne18-universite", "name": "Gare Université Paris-Saclay : ses abords",
			"about": "its forecourts, sidewalks, cycle track, promenade and the TCSP's stop"}, Plan)
	add_material("l18_slabs", material_from({"colour": "#e4e3df", "texture": "travertine", "scale": 1.0 / 2.4,
			"rough": 0.8}))
	add_material("l18_tactile", plain(Color("#ece6cf"), 0.8))


## The grounds, committed: a node at the plan's frame (meshes only when `meshes`: none headless).
func build(meshes: bool) -> Node3D:
	for e: Array in Plan.paved():
		_surface(e[0], e[1], Callable(Plan, "lift"))
	_platform()
	_kerb()
	_marks()
	return commit(meshes)


## A surface over polygon `poly` (material m), `top`(p) over the ground; its faces down where what is next to it is
## lower (a lawn, the map's ground): none on the roads' side (the kerb's), against the building or other paving.
func _surface(poly: PackedVector2Array, m: String, top: Callable) -> void:
	var hs := {}
	var at := func(p: Vector2) -> Vector3:
		if not hs.has(p):
			hs[p] = top.call(p)
		return p3(p.x, p.y, hs[p])
	var t := PackedVector2Array()
	for f: PackedVector2Array in Plan.subtract([poly], Plan.ramp_zones()):
		t.append_array(_cells(f, CELL))
	for z: PackedVector2Array in Plan.ramp_zones():
		for r: PackedVector2Array in Plan.intersect([poly], [z]):
			t.append_array(_cells(r, RAMP_CELL))
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


## Whether local p next to a paved surface is lower ground (a lawn, the map's ground round the grounds).
func _open(p: Vector2) -> bool:
	if Plan.SOCLE.has_point(p) or Plan.is_paved(p):
		return false
	return not Plan.inside(p, Plan.roads_side())             # (the kerb's side: its own face)


## Polygon `poly`'s triangles (flat array of their corners), cut on a grid of `size` m cells (in the plan's frame):
## its pieces in each cell triangulated (the surfaces follow the designed ground).
static func _cells(poly: PackedVector2Array, size: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var b := Plan.bounds(poly)
	var i0 := floori(b.position.x / size)
	var i1 := floori(b.end.x / size)
	var j0 := floori(b.position.y / size)
	var j1 := floori(b.end.y / size)
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var r := Rect2(i * size, j * size, size, size)
			var cell := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, cell):
				if Geometry2D.is_polygon_clockwise(piece) and piece.size() > 0 and Plan._area(piece) < 1e-4:
					continue
				var idx := Geometry2D.triangulate_polygon(piece)
				for k in idx:
					out.append(piece[k])
	return out


## The kerb along the roads: its face (the paving's top down to the road; lowered at the crossings), the gutter at its
## foot.
func _kerb() -> void:
	var line := Plan.kerb_line()
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var d := (b - a).normalized()
		var inward := Vector2(-d.y, d.x)
		var n := maxi(1, ceili(a.distance_to(b) / EDGE))
		for j in n:
			var p := a.lerp(b, float(j) / n)
			var q := a.lerp(b, float(j + 1) / n)
			var f := [p3(p.x, p.y, 0.02), p3(q.x, q.y, 0.02), p3(q.x, q.y, Plan.lift(q)), p3(p.x, p.y, Plan.lift(p))]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(-inward))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
			var g := -inward * GUTTER
			quad("gutter", p3(p.x, p.y, 0.012), p3(q.x, q.y, 0.012), p3(q.x + g.x, q.y + g.y, 0.012),
					p3(p.x + g.x, p.y + g.y, 0.012), Vector3.UP)


## The stop « Université Paris-Saclay »: its platform KERB high (slabs, a tactile band along its kerb), its kerb on the
## TCSP's side with the gutter, its other faces down to the ground; the yellow zigzag along it on the road.
func _platform() -> void:
	var poly := PackedVector2Array(Plan.PLATFORM)
	var top := func(_p: Vector2) -> float: return Plan.KERB
	var t := _cells(poly, CELL)
	for i in range(0, t.size(), 3):
		var a := p3(t[i].x, t[i].y, Plan.KERB)
		var b := p3(t[i + 1].x, t[i + 1].y, Plan.KERB)
		var c := p3(t[i + 2].x, t[i + 2].y, Plan.KERB)
		tri("street_pavers", a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))
	var k0: Vector2 = Plan.PLATFORM[0]                          # its kerb: from its east end (u 40.3) west
	var k1: Vector2 = Plan.PLATFORM[3]
	var d := (k1 - k0).normalized()
	var inward := Vector2(-d.y, d.x)
	if inward.y < 0.0:
		inward = -inward
	var band := 0.5
	quad("l18_tactile", p3(k0.x, k0.y + 0.15, Plan.KERB + MARK), p3(k1.x, k1.y + 0.15, Plan.KERB + MARK),
			p3(k1.x, k1.y + 0.15 + band, Plan.KERB + MARK), p3(k0.x, k0.y + 0.15 + band, Plan.KERB + MARK), Vector3.UP)
	var n := maxi(1, ceili(k0.distance_to(k1) / EDGE))
	for j in n:
		var p := k0.lerp(k1, float(j) / n)
		var q := k0.lerp(k1, float(j + 1) / n)
		var f := [p3(p.x, p.y, 0.02), p3(q.x, q.y, 0.02), p3(q.x, q.y, Plan.KERB), p3(p.x, p.y, Plan.KERB)]
		quad("kerb_face", f[0], f[1], f[2], f[3], nrm(-inward))
		quad("kerb_top", p3(p.x, p.y, Plan.KERB + 0.005), p3(q.x, q.y, Plan.KERB + 0.005),
				p3(q.x, q.y + 0.15, Plan.KERB + 0.005), p3(p.x, p.y + 0.15, Plan.KERB + 0.005), Vector3.UP)
		faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
		var g := -inward * GUTTER
		quad("gutter", p3(p.x, p.y, 0.012), p3(q.x, q.y, 0.012), p3(q.x + g.x, q.y + g.y, 0.012),
				p3(p.x + g.x, p.y + g.y, 0.012), Vector3.UP)
	for e: Array in [[Plan.PLATFORM[0], Plan.PLATFORM[1]], [Plan.PLATFORM[1], Plan.PLATFORM[2]],
			[Plan.PLATFORM[2], Plan.PLATFORM[3]]]:                  # its other sides
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var dd := (b - a).normalized()
		var out := Vector2(dd.y, -dd.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.1, poly):
			out = -out
		var m := maxi(1, ceili(a.distance_to(b) / EDGE))
		for j in m:
			var p := a.lerp(b, float(j) / m)
			var q := a.lerp(b, float(j + 1) / m)
			var f := [p3(p.x, p.y, -0.05), p3(q.x, q.y, -0.05), p3(q.x, q.y, top.call(q)), p3(p.x, p.y, top.call(p))]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(out))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
	var u := k0.x - 2.0                                           # the zigzag, on the road along the kerb
	var up := true
	while u > k1.x + 2.0:
		var v0 := Plan.PLATFORM[0].y + (u - k0.x) / (k1.x - k0.x) * (k1.y - k0.y) - GUTTER - 0.1
		var a := Vector2(u, v0 - (0.0 if up else 0.7))
		var b := Vector2(u - 1.0, v0 - (0.7 if up else 0.0))
		line(a, b, 0.1, YELLOW)
		up = not up
		u -= 1.0


## The roads' markings redone and the cycle track's.
func _marks() -> void:
	var skip_sg := func(p: Vector2) -> bool: return (p.y > 6.6 and p.y < 11.8) or p.y > 22.0
	dashes(Vector2(Plan.sg_u(Plan.SG_FROM) + Plan.SG_W * 0.5, Plan.SG_FROM),
			Vector2(Plan.sg_u(22.0) + Plan.SG_W * 0.5, 22.0), 0.12, 3.0, 5.0, skip_sg)
	var skip_t := func(p: Vector2) -> bool: return p.x > 41.6 and p.x < 46.8
	var t0 := Vector2(58.0, Plan.t_v(58.0) + Plan.TCSP_W * 0.5)
	var t1 := Vector2(Plan.TCSP_END + 1.0, Plan.t_v(Plan.TCSP_END + 1.0) + Plan.TCSP_W * 0.5)
	dashes(t0, t1, 0.12, 3.0, 5.0, skip_t)
	# the cycle track's crossing of rue Sophie Germain: square dashes along both its sides
	var c := Plan.sw_corner()
	for o: float in [Plan.T_CYCLE.x, Plan.T_CYCLE.y]:
		var v := c.y - o
		dashes(Vector2(Plan.sg_u(v) + 0.3, v), Vector2(Plan.sg_u(v) + Plan.SG_W - 0.3, v), 0.4, 0.5, 0.5)
	# the cycle track: its dashed centre line, a bicycle every BIKES m (each way in turn), on its straight part
	var mid := (Plan.T_CYCLE.x + Plan.T_CYCLE.y) * 0.5
	var lane := (Plan.T_CYCLE.y - Plan.T_CYCLE.x) * 0.25
	var h := Plan.KERB + MARK
	var u := 58.5
	while u - 1.5 > -91.0:
		var a := Vector2(u, Plan.t_v(u) - mid)
		var b := Vector2(u - 1.5, Plan.t_v(u - 1.5) - mid)
		if not _near_gap(a) and not _near_gap(b):
			line(a, b, 0.1, "#eeeeea", h)
		u -= 4.0
	var way := 1.0
	u = 50.0
	while u > -88.0:
		var p := Vector2(u, Plan.t_v(u) - mid + lane * way)
		if not _near_gap(p):
			bike(p, Vector2(-way, 0.0), h)
		way = -way
		u -= BIKES * 0.5


func _near_gap(p: Vector2) -> bool:
	return Plan.lift(p) < Plan.KERB - 0.001
