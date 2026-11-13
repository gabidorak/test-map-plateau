extends "res://scripts/street_kit.gd"
## Lot residenceHaignere's street works drawn (haignere_plan.gd: in the map's frame, on its plane): the bands along the
## roads (the kerb's top, the planted strip's paving between its beds, the cycle track's asphalt, the sidewalk), KERB
## high and lowered at the crossings, their faces down to the beds, the lawns and the map's ground, the kerb's face and
## its gutter along the roads; the flush paving (the alley's setts, the paths, the terrace's slabs), rising to the
## sidewalk where it meets it; the cycle track's markings (its dashed centre line, the bicycles). Its surfaces cut in
## EDGE m triangles (they follow the ramps). Collision: the bands' and the paving's tops and faces.

const Plan = preload("res://scripts/residenceHaignere/haignere_plan.gd")
const EDGE := 1.0                           # m: the surfaces' triangles at most
const MARK := 0.006                         # m: markings over the surface they are on
const BIKES := 32.0                         # m between two bicycles on the track (each way in turn)

var _raised: Array = []                     # the bands' polygons
var _low: Array = []                        # the flush paving's


func _init() -> void:
	super("ResidenceHaignere", {"type": "lot", "lot": "residenceHaignere", "name": "Résidence Haigneré: ses abords",
			"about": "its sidewalks, cycle track, alley, paths and terrace"}, Plan)


## The works, committed: a node (meshes only when `meshes`: none headless).
func build(meshes: bool) -> Node3D:
	_raised = Plan.bands().map(func(e: Array) -> PackedVector2Array: return e[0])
	_low = Plan.flush().map(func(e: Array) -> PackedVector2Array: return e[0])
	for e: Array in Plan.bands():
		_surface(e[0], e[1], Callable(Plan, "lift"), true)
	for e: Array in Plan.flush():
		_surface(e[0], e[1], Callable(Plan, "flush_lift"), false)
	_kerb()
	_cycle_marks()
	return commit(meshes)


## A surface over polygon `poly` (material m), `top`(p) over the ground; its faces down where what is next to it is
## lower (a bed, a lawn, the map's ground): none on the roads' side (the kerb's), against the residence or another
## surface.
func _surface(poly: PackedVector2Array, m: String, top: Callable, band: bool) -> void:
	var hs := {}
	var at := func(p: Vector2) -> Vector3:
		if not hs.has(p):
			hs[p] = top.call(p)
		return p3(p.x, p.y, hs[p])
	var t := PackedVector2Array()
	for f: PackedVector2Array in Plan.subtract([poly], Plan.ramp_zones(band)):   # (level: as the polygon is)
		var idx := Geometry2D.triangulate_polygon(f)
		for k in idx:
			t.append(f[k])
	for z: PackedVector2Array in Plan.ramp_zones(band):                           # (sloping: cut fine)
		for r: PackedVector2Array in Plan.intersect([poly], [z]):
			t.append_array(_fine(r))
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
			if not _open((p + q) * 0.5 + out * 0.08, band):
				continue
			var f := [p3(p.x, p.y, -0.05), p3(q.x, q.y, -0.05), at.call(q), at.call(p)]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(out))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))


## Whether map point p next to a surface is lower ground (a bed, a lawn, the map's ground round the lot).
func _open(p: Vector2, band: bool) -> bool:
	if Geometry2D.is_point_in_polygon(p, Plan.residence()):
		return false
	if band and not Geometry2D.is_point_in_polygon(p, Plan.lot_side()):
		return false                                       # (the kerb's face)
	for set: Array in [_raised, _low]:
		for q: PackedVector2Array in set:
			if Plan.inside(p, q):
				return false
	return true


## Polygon `poly`'s triangles (flat array of their corners), cut until no side is longer than EDGE.
static func _fine(poly: PackedVector2Array) -> PackedVector2Array:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("residence_haignere_builder: a polygon of %d points not triangulated" % poly.size())
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


## The kerb along the roads, in the lot: its face (the bands' top down to the road; low at the crossings), the gutter at
## its foot.
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
			if not Plan.in_lot((p + q) * 0.5 + inward * 0.1):
				continue
			var f := [p3(p.x, p.y, 0.02), p3(q.x, q.y, 0.02), p3(q.x, q.y, Plan.lift(q)), p3(p.x, p.y, Plan.lift(p))]
			quad("kerb_face", f[0], f[1], f[2], f[3], nrm(-inward))
			faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
			var g := -inward * GUTTER
			quad("gutter", p3(p.x, p.y, 0.012), p3(q.x, q.y, 0.012), p3(q.x + g.x, q.y + g.y, 0.012),
					p3(p.x + g.x, p.y + g.y, 0.012), Vector3.UP)


## The cycle track's markings: its dashed centre line, a bicycle every BIKES m (each way in turn), where it is level.
func _cycle_marks() -> void:
	var track: Array = []
	for e: Array in Plan.bands():
		if e[1] == "street_asphalt":
			track.append(e[0])
	var on_track := func(p: Vector2) -> bool:
		if absf(Plan.lift(p) - Plan.KERB) > 0.001:
			return false
		for q: PackedVector2Array in track:
			if Geometry2D.is_point_in_polygon(p, q):
				return true
		return false
	var mid := (Plan.CYCLE.x + Plan.CYCLE.y) * 0.5
	var lane := (Plan.CYCLE.y - Plan.CYCLE.x) * 0.25
	var h := Plan.KERB + MARK
	var line := Plan.kerb_sw()
	var run := 0.0
	var next_bike := 12.0
	var way := 1.0                                           # (keeping right: the kerb's side going along it)
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var l := a.distance_to(b)
		if l < 3.0:                                          # (the corner's: none round it)
			run += l
			continue
		var d := (b - a) / l
		var n := Vector2(-d.y, d.x)
		var s := 0.5
		while s + 1.5 < l - 0.5:                             # dashes 1.5 m, gaps 2.5 m
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
