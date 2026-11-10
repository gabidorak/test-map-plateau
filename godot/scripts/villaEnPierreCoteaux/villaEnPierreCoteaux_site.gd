extends "res://scripts/build_kit.gd"
## Villa de charme's grounds (scripts/villaEnPierreCoteaux/villaEnPierreCoteaux.gd places them): the rubble stone wall along Thomas's line, coped in
## dressed stone; the gate on the road between two ashlar pillars with lanterns, its two wrought-iron leaves (arched,
## barred, medallions, spikes; villaEnPierreCoteaux.gd swings them); white gravel for the drive, the forecourt and the lane to the
## garage (rising to the garage floor); the perron at the front door; the patio between the wings and the terrace
## along the garden front, at the floor's level, a balustrade round it and steps down to the path to the pool; the
## pool's raised deck (travertine, coping, mosaic basin, loungers, parasols); the grotto fountain by the forecourt (a
## raised basin, a rock wall on the slope, an upper basin pouring a curtain of water); terracotta pots, box balls and
## hedges.
## In the villa's frame (x east, y up from the house's floor, z south); `ground` (x, z) -> the map's ground there.

const VillaEnPierreCoteaux = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_data.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const KitScript = preload("res://scripts/build_kit.gd")

const DRIVE_HALF := 2.6                     # m, half the drive's width
## The drive after the gate (the villa's frame x, z): it bends east then south to the forecourt.
const DRIVE := [Vector2(-8.0, -55.5), Vector2(3.0, -52.0), Vector2(13.0, -46.5), Vector2(21.0, -41.0),
		Vector2(27.0, -35.0), Vector2(30.0, -29.0), Vector2(31.0, -22.0)]
const FORECOURT := Rect2(-21.0, -24.0, 83.0, 24.0)
const FORE_ROUND := 3.0
const LANE := [Vector2(40.0, 0.0), Vector2(49.0, 0.0), Vector2(49.0, 8.0), Vector2(54.0, 10.0), Vector2(54.0, 25.0),
		Vector2(40.0, 25.0)]
const CENTRE_LAWN := Vector3(20.0, -12.5, 5.5)   # x, z, radius
const PATIO := Rect2(12.0, 12.0, 16.0, 10.0)
const TERRACE := Rect2(-2.0, 22.0, 42.0, 5.0)
const STAIRS_W := Vector2(17.5, 22.5)       # x of the perron's and the garden steps' ends
const PATH := Vector2(18.5, 21.5)           # x of the garden path's edges
const DECK := Rect2(5.0, 59.0, 30.0, 14.5)
const POOL := Vector4(20.0, 66.25, 18.0, 7.0)    # x, z of its middle, length (x), width
const FOUNTAIN := Vector3(41.0, -26.0, 0.0)
const BASIN := Vector2(5.8, 5.2)            # the fountain basin's half-axes (x, z)
const GROTTO := Vector2(-2.3, 0.4)          # its rock wall's arc (angles round the basin, atan2(z, x))
const WALL_H := 2.2
const WALL_T := 0.5
const GRID := 0.5
const RISE := 0.16                          # m, a step at most
const TREAD := 0.34

var _ground: Callable
var _faces := PackedVector3Array()
var _paved: Array = []


func _init() -> void:
	super("VillaEnPierreCoteauxGrounds", {"type": "villa", "name": VillaEnPierreCoteaux.NAME, "id": VillaEnPierreCoteaux.ID, "kind": "a villa for sale"})


## The grounds. Meta: "leaves" ([pivot, opening sign, shut angle] each), "gate_shape", "plaque" (Label3D),
## "plaque_at" (Vector3: where one stands to read it), "paved" (polygons (x, z) the grass keeps off).
func build(ground: Callable, meshes := true) -> Node3D:
	_ground = ground
	_wall()
	_gate(meshes)
	_gravel()
	_perron()
	_terrace()
	_garden()
	_pool()
	_fountain()
	if meshes:
		_pots()
	col_faces(_faces)
	root.set_meta("paved", _paved)
	return commit(meshes)


func g(x: float, z: float) -> float:
	return float(_ground.call(x, z))


## The ground's highest round (x, z) within a metre (paving lies over it: the drawn ground is a coarser mesh, and
## raised paths step up).
func g_top(x: float, z: float) -> float:
	var h := g(x, z)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		h = maxf(h, g(x + d.x, z + d.y))
	return h


## How far a point (the villa's frame x, z) is from what is built in the grounds (the trees keep off it).
static func clearance(p: Vector2) -> float:
	var d := INF
	var gate: Array = VillaEnPierreCoteaux.gate_local()
	var drive := [gate[0], (gate[0] as Vector2) + (gate[2] as Vector2) * 6.0] + DRIVE
	for i in drive.size() - 1:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, drive[i], drive[i + 1])) - DRIVE_HALF)
	for r: Rect2 in [FORECOURT, Rect2(40, 0, 14, 25), Rect2(-2, 0, 44, 27), Rect2(PATH.x, 27, PATH.y - PATH.x, 32), DECK]:
		d = minf(d, _rect_dist(r, p))
	d = minf(d, p.distance_to(Vector2(FOUNTAIN.x, FOUNTAIN.y)) - 9.0)
	return d


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()


func _poly_rect(r: Rect2, grow := 0.3) -> PackedVector2Array:
	var a := r.grow(grow)
	return PackedVector2Array([a.position, Vector2(a.end.x, a.position.y), a.end, Vector2(a.position.x, a.end.y)])


# ---------------------------------------------------------------- the wall

## The wall from one side of the gate round to the other: a rubble stone wall on the ground, coped.
func _wall() -> void:
	var gl: Array = VillaEnPierreCoteaux.gate_local()
	var gm: Vector2 = gl[0]
	var along: Vector2 = gl[1]
	var pts := PackedVector2Array()
	for p: Vector2 in VillaEnPierreCoteaux.WALL:
		pts.append(VillaEnPierreCoteaux.to_local2(p))
	# the segment the gate is on, the loop from the gate's far side round to its near side
	var best := INF
	var k := 0
	for i in pts.size():
		var c := Geometry2D.get_closest_point_to_segment(gm, pts[i], pts[(i + 1) % pts.size()])
		if c.distance_to(gm) < best:
			best = c.distance_to(gm)
			k = i
	var a := pts[k]
	var b := pts[(k + 1) % pts.size()]
	var dir := (b - a).normalized()
	var line := [gm + dir * VillaEnPierreCoteaux.GATE_HALF]
	for i in range(1, pts.size() + 1):
		line.append(pts[(k + i) % pts.size()])
	line.append(gm - dir * VillaEnPierreCoteaux.GATE_HALF)
	# resampled every 2 m at most
	var s: Array = [line[0]]
	for i in range(1, line.size()):
		var p: Vector2 = line[i - 1]
		var q: Vector2 = line[i]
		var n := maxi(1, ceili(p.distance_to(q) / 2.0))
		for j in range(1, n + 1):
			s.append(p.lerp(q, float(j) / n))
	var out := []                           # per sample: its normal (outward-ish, either side does)
	for i in s.size():
		var t: Vector2 = ((s[mini(i + 1, s.size() - 1)] as Vector2) - (s[maxi(i - 1, 0)] as Vector2)).normalized()
		out.append(Vector2(-t.y, t.x))
	for i in s.size() - 1:
		var p: Vector2 = s[i]
		var q: Vector2 = s[i + 1]
		var np: Vector2 = out[i]
		var nq: Vector2 = out[i + 1]
		var gp := g(p.x, p.y)
		var gq := g(q.x, q.y)
		for side: float in [1.0, -1.0]:
			var o := WALL_T * 0.5 * side
			var a0 := Vector3(p.x + np.x * o, gp - 0.5, p.y + np.y * o)
			var b0 := Vector3(q.x + nq.x * o, gq - 0.5, q.y + nq.y * o)
			var b1 := Vector3(b0.x, gq + WALL_H, b0.z)
			var a1 := Vector3(a0.x, gp + WALL_H, a0.z)
			var n := Vector3(np.x + nq.x, 0, np.y + nq.y).normalized() * side
			quad("rubble", a0, b0, b1, a1, n)
			_faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
		# the coping: a dressed stone slab over it
		var w := WALL_T * 0.5 + 0.07
		var pa := Vector3(p.x + np.x * w, gp + WALL_H, p.y + np.y * w)
		var pb := Vector3(p.x - np.x * w, gp + WALL_H, p.y - np.y * w)
		var qa := Vector3(q.x + nq.x * w, gq + WALL_H, q.y + nq.y * w)
		var qb := Vector3(q.x - nq.x * w, gq + WALL_H, q.y - nq.y * w)
		var up := Vector3(0, 0.14, 0)
		quad("coping", pa + up, qa + up, qb + up, pb + up, Vector3.UP)
		quad("coping", pa - Vector3(0, 0.02, 0), qa - Vector3(0, 0.02, 0), qa + up, pa + up,
				Vector3(np.x + nq.x, 0, np.y + nq.y).normalized())
		quad("coping", pb - Vector3(0, 0.02, 0), qb - Vector3(0, 0.02, 0), qb + up, pb + up,
				-Vector3(np.x + nq.x, 0, np.y + nq.y).normalized())
	# its ends (behind the pillars)
	for e: Array in [[s[0], out[0]], [s[s.size() - 1], out[out.size() - 1]]]:
		var p: Vector2 = e[0]
		var n2: Vector2 = e[1]
		var gp := g(p.x, p.y)
		var o := WALL_T * 0.5
		var t := Vector3(-n2.y, 0, n2.x)
		quad("rubble", Vector3(p.x + n2.x * o, gp - 0.5, p.y + n2.y * o), Vector3(p.x - n2.x * o, gp - 0.5, p.y - n2.y * o),
				Vector3(p.x - n2.x * o, gp + WALL_H, p.y - n2.y * o), Vector3(p.x + n2.x * o, gp + WALL_H, p.y + n2.y * o), t)


# ---------------------------------------------------------------- the gate

func _gate(meshes: bool) -> void:
	var gl: Array = VillaEnPierreCoteaux.gate_local()
	var gm: Vector2 = gl[0]
	var along: Vector2 = gl[1]
	var inward: Vector2 = gl[2]
	var gy := g(gm.x, gm.y)
	var basis := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(inward.x, 0, inward.y)).orthonormalized()
	# the pillars (ashlar, a cap, a lantern each)
	for side: float in [1.0, -1.0]:
		var c := gm + along * 3.0 * side
		var gc := minf(g(c.x, c.y), gy)
		var xf := Transform3D(basis, Vector3(c.x, 0, c.y))
		box_xf("ashlar", xf, Vector3(0.9, 3.4, 0.9), Vector3(0, gc + 1.2, 0))
		box_xf("coping", xf, Vector3(1.12, 0.12, 1.12), Vector3(0, gc + 2.96, 0))
		box_xf("coping", xf, Vector3(1.02, 0.1, 1.02), Vector3(0, gc + 2.85, 0))
		box_xf("ashlar", xf, Vector3(0.96, 0.25, 0.96), Vector3(0, gc - 0.3, 0))
		col_xf(Transform3D(basis, Vector3(c.x, gc + 1.2, c.y)), Vector3(0.9, 3.4, 0.9))
		# the lantern
		var top := Vector3(c.x, gc + 3.02, c.y)
		rod("iron", top, top + Vector3(0, 0.25, 0), 0.04)
		box_xf("iron", Transform3D(basis, top + Vector3(0, 0.3, 0)), Vector3(0.36, 0.05, 0.36))
		for cx: float in [-0.16, 0.16]:
			for cz: float in [-0.16, 0.16]:
				var cp: Vector3 = top + basis * Vector3(cx, 0.3, cz)
				rod("iron", cp, cp + Vector3(0, 0.5, 0), 0.012)
		box_xf("glass", Transform3D(basis, top + Vector3(0, 0.56, 0)), Vector3(0.3, 0.48, 0.3))
		ball("bulb", top + Vector3(0, 0.55, 0), Vector3(0.07, 0.09, 0.07), 8)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.02
		roof.bottom_radius = 0.3
		roof.height = 0.22
		roof.radial_segments = 4
		tool("iron").append_from(roof, 0, Transform3D(basis.rotated(Vector3.UP, PI / 4.0), top + Vector3(0, 0.93, 0)))
		if meshes:
			light(top + Vector3(0, 0.55, 0), Color(1.0, 0.82, 0.55), 0.6, 7.0)
	# the plaque, on the road face of the south pillar
	var pc := gm - along * 3.0
	var face := Vector3(-inward.x, 0, -inward.y)
	var pxf := Transform3D(Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face), Vector3(pc.x, gy + 1.55, pc.y) + face * 0.455)
	box_xf("black", pxf, Vector3(0.66, 0.42, 0.025))
	box_xf("brass", pxf, Vector3(0.7, 0.46, 0.012), Vector3(0, 0, -0.008))
	var plaque := label("VILLA LUXE", Transform3D(pxf.basis, pxf * Vector3(0, 0, 0.014)), 26, 0.0016, Color(0.93, 0.86, 0.66))
	plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plaque.visibility_range_end = 40.0
	root.set_meta("plaque", plaque)
	var stand := pc - inward * 1.4
	root.set_meta("plaque_at", Vector3(stand.x, g(stand.x, stand.y), stand.y))
	# the leaves: each its own node on a hinge at a pillar's inner face, closed in the wall's line
	var leaves := []
	for side: float in [1.0, -1.0]:
		var hinge := gm + along * (VillaEnPierreCoteaux.LEAF) * side
		var pivot := Node3D.new()
		pivot.name = "GateLeaf%s" % ("A" if side > 0 else "B")
		pivot.position = Vector3(hinge.x, gy, hinge.y)
		root.add_child(pivot)
		var v := -along * side                  # from the hinge to the middle
		var shut := atan2(-v.y, v.x)
		var open_sign := signf(v.y * inward.x - v.x * inward.y)
		pivot.rotation.y = shut
		if meshes:
			var leaf := _leaf(side)
			pivot.add_child(leaf)
		leaves.append([pivot, open_sign, shut])
	root.set_meta("leaves", leaves)
	var shape := col_xf(Transform3D(basis, Vector3(gm.x, gy + 1.3, gm.y)), Vector3(VillaEnPierreCoteaux.LEAF * 2.0, 2.6, 0.25))
	root.set_meta("gate_shape", shape)
	# the paving outside, from the road to the gate
	_apron(gm, along, inward)


## The paving outside the gate, from it to the road: as wide as the gate between the pillars' outer faces, flaring
## towards the road, its far edge along the road's own edge (found column by column on the map's asphalt), never
## over it.
func _apron(gm: Vector2, along: Vector2, inward: Vector2) -> void:
	var cols := 16
	var rows := 10
	var pts := []
	var outline_far := []
	for i in cols + 1:
		var u := -1.0 + 2.0 * i / cols
		var reach := _to_road(gm + along * u * 4.2, -inward) + 0.15
		var col := []
		for j in rows + 1:
			var v := float(j) / rows
			var q := gm - inward * (0.05 + v * (reach - 0.05)) + along * u * (3.45 + 1.4 * v * v)
			col.append(Vector3(q.x, g_top(q.x, q.y) + 0.05, q.y))
		pts.append(col)
		outline_far.append(col[rows])
	_faces.append_array(sheet("pavers", pts))
	# its sides down to the ground
	for side: int in [0, cols]:
		var col: Array = pts[side]
		for j in rows:
			var a3: Vector3 = col[j]
			var b3: Vector3 = col[j + 1]
			quad("pavers", Vector3(a3.x, a3.y - 0.12, a3.z), Vector3(b3.x, b3.y - 0.12, b3.z), b3, a3,
					Vector3(along.x, 0, along.y) * (1.0 if side == cols else -1.0))
	var poly := PackedVector2Array()
	for col: Array in pts:
		var q: Vector3 = col[0]
		poly.append(Vector2(q.x, q.z))
	for i in range(outline_far.size() - 1, -1, -1):
		var q: Vector3 = outline_far[i]
		poly.append(Vector2(q.x, q.z))
	_paved.append(poly)


## Whether (x, z) (the villa's frame) is on the road (the map's asphalt, its kerbs and markings).
static func _on_road(x: float, z: float) -> bool:
	var gm: RefCounted = GroundMap.get_map()
	if gm == null:
		return false
	var m := VillaEnPierreCoteaux.to_map(Vector2(x, z))
	var id: int = gm.material_at(m.x, m.y)
	return id >= 0 and str(gm.materials[id]) in ["asphalt", "kerb", "paint"]


## How far from `from` along `dir` (the villa's frame) the road begins (at most 10 m).
static func _to_road(from: Vector2, dir: Vector2) -> float:
	var t := 0.0
	while t < 10.0:
		var p := from + dir * t
		if _on_road(p.x, p.y):
			return maxf(t, 1.0)
		t += 0.1
	return 7.0


## One leaf in its hinge's frame: x from the hinge to the gate's middle, y up, z across: a wrought-iron frame arched
## up to the middle, bars with spikes, two rails, two medallions.
func _leaf(side: float) -> Node3D:
	var k = KitScript.new("Leaf")
	var w := VillaEnPierreCoteaux.LEAF - 0.04
	var h0 := 2.15
	var h1 := 2.6
	var top := func(x: float) -> float: return h0 + (h1 - h0) * sin(clampf(x / w, 0.0, 1.0) * PI * 0.5)
	k.box("iron", 0.0, 0.07, 0.06, h0 + 0.05, -0.035, 0.035)
	k.box("iron", w - 0.07, w, 0.06, h1 + 0.05, -0.035, 0.035)
	for y: float in [0.1, 0.42, 1.42]:
		k.box("iron", 0.0, w, y - 0.035, y + 0.035, -0.03, 0.03)
	var x := 0.12
	var prev := Vector3(0.0, h0, 0)
	while x < w - 0.06:
		var t: float = top.call(x)
		k.rod("iron", Vector3(x, 0.1, 0), Vector3(x, t, 0), 0.014, 6)
		k.cyl("iron", Vector3(x, t, 0), 0.03, 0.14, 6, 0.0)
		var p := Vector3(x, t - 0.05, 0)
		k.rod("iron", prev, p, 0.028, 6)
		prev = p
		x += 0.11
	k.rod("iron", prev, Vector3(w, h1 - 0.05, 0), 0.028, 6)
	var rail2 := func(xx: float) -> float: return float(top.call(xx)) - 0.32
	var px := 0.07
	while px < w - 0.1:
		k.rod("iron", Vector3(px, rail2.call(px), 0), Vector3(px + 0.1, rail2.call(px + 0.1), 0), 0.02, 6)
		px += 0.1
	for mx: float in [w * 0.3, w * 0.72]:
		var c := Vector3(mx, 0.92, 0)
		var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c)
		k.torus("iron", xf, 0.25, 0.3)
		k.torus("iron", xf, 0.12, 0.16)
		k.rod("iron", c + Vector3(-0.27, 0, 0), c + Vector3(0.27, 0, 0), 0.015, 6)
		k.rod("iron", c + Vector3(0, -0.27, 0), c + Vector3(0, 0.27, 0), 0.015, 6)
		k.ball("brass", c, Vector3(0.05, 0.05, 0.04), 8)
	var rx := 0.22
	while rx < w - 0.15:
		var c := Vector3(rx, 1.42 + (float(rail2.call(rx)) - 1.42) * 0.5, 0)
		k.torus("iron", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c), 0.07, 0.095)
		rx += 0.22
	return k.commit(true, 120.0)


# ---------------------------------------------------------------- gravel and paving

## A sheet of `m` over rectangle r where keep(x, z), `up` over the ground (or over height(x, z) when given): its
## faces go to the collision.
func _sheet_over(r: Rect2, m: String, keep: Callable, up: float, height := Callable(), step := GRID) -> void:
	var nx := maxi(1, ceili(r.size.x / step))
	var nz := maxi(1, ceili(r.size.y / step))
	var rows := []
	for i in nx + 1:
		var row := []
		var x := r.position.x + r.size.x * i / nx
		for j in nz + 1:
			var z := r.position.y + r.size.y * j / nz
			var y: float = height.call(x, z) if height.is_valid() else g_top(x, z) + up
			row.append(Vector3(x, y, z))
		rows.append(row)
	_faces.append_array(sheet(m, rows, keep))


static func _in_fore(x: float, z: float) -> bool:
	var r := FORECOURT
	if not r.has_point(Vector2(x, z)):
		return false
	var cx := clampf(x, r.position.x + FORE_ROUND, r.end.x - FORE_ROUND)
	var cz := clampf(z, r.position.y + FORE_ROUND, r.end.y - FORE_ROUND)
	return Vector2(x - cx, z - cz).length() <= FORE_ROUND


static func _in_drive(x: float, z: float) -> bool:
	var gl: Array = VillaEnPierreCoteaux.gate_local()
	var p := Vector2(x, z)
	if (p - (gl[0] as Vector2)).dot(gl[2]) < -0.05:
		return false
	var line := [gl[0], (gl[0] as Vector2) + (gl[2] as Vector2) * 6.0] + DRIVE
	for i in line.size() - 1:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])) < DRIVE_HALF:
			return true
	return false


static func _in_fountain(x: float, z: float, grow := 0.0) -> bool:
	var dx := (x - FOUNTAIN.x) / (BASIN.x + 0.45 + grow)
	var dz := (z - FOUNTAIN.y) / (BASIN.y + 0.45 + grow)
	return dx * dx + dz * dz < 1.0


## The lane to the garage, and its height: rising from the ground to the garage floor (0) at its doors (x = 40).
static func _lane_ramp(x: float, z: float) -> float:
	return -0.11 * (x - 40.0) - 0.11 * maxf(0.0, 11.5 - z)


func _gravel() -> void:
	var lane := PackedVector2Array(LANE)
	var perron_z := -maxi(1, ceili(-(g_top(20.0, -3.2) + 0.05) / RISE)) * TREAD
	var keep := func(x: float, z: float) -> bool:
		if _in_fountain(x, z, 0.2):
			return false
		if Vector2(x, z).distance_to(Vector2(CENTRE_LAWN.x, CENTRE_LAWN.y)) < CENTRE_LAWN.z:
			return false
		if z > -0.02 and x > -0.3 and x < 40.0:
			return false                        # (the house)
		if x > STAIRS_W.x - 0.7 and x < STAIRS_W.y + 0.7 and z > perron_z + 0.1:
			return false                        # (the perron and its cheeks)
		return _in_fore(x, z) or _in_drive(x, z) or Geometry2D.is_point_in_polygon(Vector2(x, z), lane)
	var height := func(x: float, z: float) -> float:
		var y := g_top(x, z) + 0.05                 # (the forecourt is terraformed: data/terraform/)
		if x > 39.0 and z > -0.5:
			y = maxf(y, _lane_ramp(x, z))
		return y
	_sheet_over(Rect2(-30.0, -62.0, 86.0, 88.0), "gravel", keep, 0.04, height)
	_edging(height)
	# the lane's raised edge: a low stone wall where it stands over the ground
	for e: Array in [[Vector2(54.0, 10.0), Vector2(54.0, 25.0)], [Vector2(54.0, 25.0), Vector2(40.4, 25.0)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := ceili(a.distance_to(b) / 1.0)
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n)
			var top := maxf(float(height.call(p.x, p.y)), g(p.x, p.y)) + 0.3
			var half := a.distance_to(b) / n * 0.5
			var t := (b - a).normalized()
			var c := p
			box("ashlar", c.x - (half if t.x != 0.0 else 0.2), c.x + (half if t.x != 0.0 else 0.2), g(p.x, p.y) - 0.3, top,
					c.y - (half if t.y != 0.0 else 0.2), c.y + (half if t.y != 0.0 else 0.2))
			col(c.x - (half if t.x != 0.0 else 0.2), c.x + (half if t.x != 0.0 else 0.2), g(p.x, p.y) - 0.3, top,
					c.y - (half if t.y != 0.0 else 0.2), c.y + (half if t.y != 0.0 else 0.2))
	# the centre lawn's stone kerb
	var lc := Vector2(CENTRE_LAWN.x, CENTRE_LAWN.y)
	var segs := 40
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var r0 := CENTRE_LAWN.z
		var r1 := CENTRE_LAWN.z + 0.25
		var p0 := lc + Vector2(cos(a0), sin(a0)) * r0
		var p1 := lc + Vector2(cos(a1), sin(a1)) * r0
		var q0 := lc + Vector2(cos(a0), sin(a0)) * r1
		var q1 := lc + Vector2(cos(a1), sin(a1)) * r1
		var y0 := (g_top(p0.x, p0.y) + 0.05) + 0.1
		var y1 := (g_top(p1.x, p1.y) + 0.05) + 0.1
		tri("lawn", Vector3(p0.x, y0 - 0.03, p0.y), Vector3(p1.x, y1 - 0.03, p1.y), Vector3(lc.x, (g_top(lc.x, lc.y) + 0.05) + 0.07, lc.y),
				Vector3.UP)
		quad("coping", Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), Vector3(q1.x, y1, q1.y), Vector3(q0.x, y0, q0.y), Vector3.UP)
		quad("coping", Vector3(q0.x, y0 - 0.25, q0.y), Vector3(q1.x, y1 - 0.25, q1.y), Vector3(q1.x, y1, q1.y), Vector3(q0.x, y0, q0.y),
				Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)))
		quad("coping", Vector3(p0.x, y0 - 0.2, p0.y), Vector3(p1.x, y1 - 0.2, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y0, p0.y),
				-Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)))
	# where the grass keeps off
	var fore := PackedVector2Array()
	for p: Vector2 in [FORECOURT.position, Vector2(FORECOURT.end.x, FORECOURT.position.y), FORECOURT.end,
			Vector2(FORECOURT.position.x, FORECOURT.end.y)]:
		fore.append(p)
	_paved.append(Geometry2D.offset_polygon(fore, 0.3)[0])
	var gl: Array = VillaEnPierreCoteaux.gate_local()
	var line := PackedVector2Array([gl[0], (gl[0] as Vector2) + (gl[2] as Vector2) * 6.0] + DRIVE)
	for poly in Geometry2D.offset_polyline(line, DRIVE_HALF + 0.3):
		_paved.append(poly)
	_paved.append(Geometry2D.offset_polygon(lane, 0.3)[0])


## A border of setts along the gravel's edges (the drive's sides, the forecourt's round its open sides), over the
## grid's steps: segments 0.7 m wide, left out where they would cross another gravel area.
func _edging(height: Callable) -> void:
	var gl: Array = VillaEnPierreCoteaux.gate_local()
	var line := [gl[0], (gl[0] as Vector2) + (gl[2] as Vector2) * 6.0] + DRIVE
	var paths := []
	for side: float in [-1.0, 1.0]:
		var pts := []
		for i in line.size():
			var a: Vector2 = line[maxi(i - 1, 0)]
			var b: Vector2 = line[mini(i + 1, line.size() - 1)]
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			pts.append((line[i] as Vector2) + n * DRIVE_HALF * side)
		paths.append([pts, "drive"])
	# the forecourt's outline (rounded corners), its facade side left out
	var r := FORECOURT
	var fo := []
	var c := [Vector2(r.position.x + FORE_ROUND, r.end.y - FORE_ROUND), Vector2(r.position.x + FORE_ROUND, r.position.y + FORE_ROUND),
			Vector2(r.end.x - FORE_ROUND, r.position.y + FORE_ROUND), Vector2(r.end.x - FORE_ROUND, r.end.y - FORE_ROUND)]
	var starts := [PI * 0.5, PI, PI * 1.5, 0.0]
	for k in 4:
		for i in 7:
			var a: float = starts[k] + PI * 0.5 * i / 6.0
			fo.append((c[k] as Vector2) + Vector2(cos(a), sin(a)) * FORE_ROUND)
	paths.append([fo, "fore"])
	var lane := PackedVector2Array(LANE)
	for p: Array in paths:
		var pts: Array = p[0]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, ceili(a.distance_to(b) / 0.8))
			for j in n:
				var q0 := a.lerp(b, float(j) / n)
				var q1 := a.lerp(b, float(j + 1) / n)
				var m := (q0 + q1) * 0.5
				if p[1] == "drive" and _in_fore(m.x, m.y):
					continue
				if p[1] == "fore" and (_in_drive(m.x, m.y) or m.y > -0.6 or Geometry2D.is_point_in_polygon(m, lane)
						or _in_fountain(m.x, m.y, 0.4)):
					continue
				var t := (q1 - q0).normalized()
				var o := Vector2(-t.y, t.x) * 0.35
				var pts4 := []
				for v: Vector2 in [q0 - o, q1 - o, q1 + o, q0 + o]:
					pts4.append(Vector3(v.x, float(height.call(v.x, v.y)) + 0.025, v.y))
				quad("sett", pts4[0], pts4[1], pts4[2], pts4[3], Vector3.UP)
				# its sides down to the ground (where the gravel stands over it)
				for e: Array in [[pts4[0], pts4[1], -o], [pts4[3], pts4[2], o]]:
					var a3: Vector3 = e[0]
					var b3: Vector3 = e[1]
					var ga := g(a3.x, a3.z) - 0.08
					var gb := g(b3.x, b3.z) - 0.08
					if a3.y - ga > 0.12 or b3.y - gb > 0.12:
						var on := Vector3((e[2] as Vector2).x, 0, (e[2] as Vector2).y).normalized()
						quad("sett", Vector3(a3.x, ga, a3.z), Vector3(b3.x, gb, b3.z), b3, a3, on)


# ---------------------------------------------------------------- the perron, the patio, the terrace

## Steps from height y0 at z0 up to y1 at z1 (along z, x from x0 to x1): solid stone, a ramp to walk up.
func _steps(x0: float, x1: float, z0: float, y0: float, z1: float, y1: float, m := "ashlar") -> void:
	var n := maxi(1, ceili(absf(y1 - y0) / RISE))
	var dz := (z1 - z0) / n
	var dy := (y1 - y0) / n
	for k in n:
		var top := y0 + dy * (k + 1) if dy > 0.0 else y0 + dy * k
		var za := z0 + dz * k
		var zb := z0 + dz * (k + 1)
		var foot := minf(minf(y0, y1), minf(minf(g(x0, za), g(x1, za)), minf(g(x0, zb), g(x1, zb)))) - 0.3
		box(m, x0, x1, foot, top, minf(za, zb), maxf(za, zb))
	col_ramp(Vector3((x0 + x1) * 0.5, y0, z0), Vector3((x0 + x1) * 0.5, y1, z1), x1 - x0)


func _perron() -> void:
	var gy := (g_top(20.0, -3.2) + 0.05)
	var n := maxi(1, ceili(-gy / RISE))
	var z0 := -n * TREAD
	_steps(STAIRS_W.x, STAIRS_W.y, z0, gy, 0.0, 0.0)
	# its cheeks, a box ball on each
	for x: float in [STAIRS_W.x - 0.35, STAIRS_W.y + 0.35]:
		box("ashlar", x - 0.35, x + 0.35, gy - 0.3, 0.42, z0, 0.0)
		box("coping", x - 0.4, x + 0.4, 0.42, 0.52, z0 - 0.05, 0.0)
		col(x - 0.35, x + 0.35, gy - 0.3, 0.52, z0, 0.0)
		ball("boxwood", Vector3(x, 0.85, z0 * 0.5), Vector3(0.36, 0.34, 0.36), 10)
	_paved.append(_poly_rect(Rect2(STAIRS_W.x - 0.8, z0, STAIRS_W.y - STAIRS_W.x + 1.6, -z0)))


func _terrace() -> void:
	var lo := INF
	for x in range(-2, 42, 2):
		for z in range(12, 28, 2):
			lo = minf(lo, g(x, z))
	# the patio and the terrace: travertine at the floor's level on a stone base
	for r: Rect2 in [PATIO, TERRACE]:
		box("pavers", r.position.x, r.end.x, -0.05, 0.0, r.position.y, r.end.y)
		box("ashlar", r.position.x, r.end.x, lo - 0.4, -0.05, r.position.y, r.end.y)
		col(r.position.x, r.end.x, lo - 0.4, 0.0, r.position.y, r.end.y)
	# the balustrade along its edge, but the steps
	var bal := [[Vector2(-2.0, 22.0), Vector2(-2.0, 27.0)], [Vector2(-2.0, 27.0), Vector2(STAIRS_W.x, 27.0)],
			[Vector2(STAIRS_W.y, 27.0), Vector2(40.0, 27.0)], [Vector2(40.0, 27.0), Vector2(40.0, 25.0)]]
	for e: Array in bal:
		_balustrade(e[0], e[1], 0.0)
	var gb := (g_top(20.0, 28.5) + 0.06)
	var n := maxi(1, ceili(-gb / RISE))
	gb = (g_top(20.0, 27.0 + n * TREAD) + 0.06)
	_steps(STAIRS_W.x, STAIRS_W.y, 27.0 + n * TREAD, gb, 27.0, 0.0)
	root.set_meta("garden_steps_end", 27.0 + n * TREAD)
	_paved.append(_poly_rect(Rect2(-2.3, -0.3, 42.6, 27.6 + n * TREAD), 0.0))
	# the patio's pergola: oak posts and beams over it
	for x: float in [12.4, 17.6, 22.4, 27.6]:
		for z: float in [21.6]:
			box("oak", x - 0.1, x + 0.1, 0.0, 3.2, z - 0.1, z + 0.1)
			col(x - 0.1, x + 0.1, 0.0, 3.2, z - 0.1, z + 0.1)
	box("oak", 12.2, 27.8, 3.2, 3.42, 21.48, 21.72)
	var bx := 12.6
	while bx < 27.5:
		box("oak", bx - 0.05, bx + 0.05, 3.42, 3.6, 12.0, 22.1)
		bx += 0.8
	# the patio's table, chairs, lounge
	box("oak", 15.0, 19.2, 0.72, 0.78, 15.0, 16.2)
	for x: float in [15.3, 18.9]:
		for z: float in [15.2, 16.0]:
			box("iron", x - 0.04, x + 0.04, 0.0, 0.72, z - 0.04, z + 0.04)
	for x: float in [15.6, 16.6, 17.6, 18.6]:
		for z: float in [14.55, 16.65]:
			_chair_out(Vector3(x, 0.0, z), z > 15.6)
	col(15.0, 19.2, 0.0, 0.78, 15.0, 16.2)
	box("iron", 21.0, 26.0, 0.0, 0.4, 18.3, 19.3)
	box("sand_fabric", 21.05, 25.95, 0.4, 0.55, 18.35, 19.25)
	box("sand_fabric", 21.05, 25.95, 0.55, 0.95, 19.05, 19.3)
	col(21.0, 26.0, 0.0, 0.6, 18.3, 19.3)
	box("travertine", 22.5, 24.5, 0.0, 0.38, 16.4, 17.4)
	col(22.5, 24.5, 0.0, 0.38, 16.4, 17.4)
	for p: Vector3 in [Vector3(15.7, 0, 12.55), Vector3(24.3, 0, 12.55), Vector3(12.9, 0, 21.0), Vector3(27.1, 0, 21.0)]:
		_pot(p, 0.42, 0.6)
		ball("leaves", p + Vector3(0, 1.05, 0), Vector3(0.5, 0.55, 0.5), 10)


func _chair_out(p: Vector3, south: bool) -> void:
	var s := 1.0 if south else -1.0
	box("iron", p.x - 0.22, p.x + 0.22, 0.42, 0.46, p.z - 0.22, p.z + 0.22)
	box("sand_fabric", p.x - 0.2, p.x + 0.2, 0.46, 0.52, p.z - 0.2, p.z + 0.2)
	box("iron", p.x - 0.22, p.x + 0.22, 0.46, 0.9, p.z + s * 0.2, p.z + s * 0.24)
	for dx: float in [-0.19, 0.19]:
		for dz: float in [-0.19, 0.19]:
			box("iron", p.x + dx - 0.015, p.x + dx + 0.015, 0.0, 0.42, p.z + dz - 0.015, p.z + dz + 0.015)


## A stone balustrade from a to b at the floor height `y`: a plinth, turned balusters, a rail.
func _balustrade(a: Vector2, b: Vector2, y: float) -> void:
	var t := (b - a).normalized()
	var length := a.distance_to(b)
	var n := Vector2(-t.y, t.x)
	var basis := Basis(Vector3(t.x, 0, t.y), Vector3.UP, Vector3(n.x, 0, n.y))
	var mid := (a + b) * 0.5
	var xf := Transform3D(basis, Vector3(mid.x, y, mid.y))
	box_xf("ashlar", xf, Vector3(length + 0.3, 0.16, 0.36), Vector3(0, 0.08, 0))
	box_xf("coping", xf, Vector3(length + 0.36, 0.1, 0.4), Vector3(0, 0.9, 0))
	col_xf(Transform3D(basis, xf * Vector3(0, 0.5, 0)), Vector3(length + 0.3, 1.0, 0.36))
	var k := 0.18
	while k < length - 0.1:
		var p := xf * Vector3(k - length * 0.5, 0.0, 0)
		cyl("coping", p + Vector3(0, 0.16, 0), 0.06, 0.1, 8, 0.09)
		cyl("coping", p + Vector3(0, 0.26, 0), 0.09, 0.32, 8, 0.05)
		cyl("coping", p + Vector3(0, 0.58, 0), 0.05, 0.2, 8, 0.07)
		cyl("coping", p + Vector3(0, 0.78, 0), 0.07, 0.07, 8)
		k += 0.24
	for e: float in [-length * 0.5, length * 0.5]:
		box_xf("ashlar", xf, Vector3(0.34, 0.95, 0.4), Vector3(e, 0.47, 0))


# ---------------------------------------------------------------- the garden path, the box hedges

func _garden() -> void:
	var z0: float = root.get_meta("garden_steps_end")
	var z1 := DECK.position.y - _deck_steps_len()
	_sheet_over(Rect2(PATH.x, z0, PATH.y - PATH.x, z1 - z0), "pavers", func(_x: float, _z: float) -> bool: return true, 0.05,
			func(_x: float, z: float) -> float: return (g_top(20.0, z) + 0.06))
	var nz := ceili((z1 - z0) / 0.5)
	for i in nz:
		var za := z0 + (z1 - z0) * i / nz
		var zb := z0 + (z1 - z0) * (i + 1) / nz
		for e: Array in [[PATH.x, -1.0], [PATH.y, 1.0]]:
			var x: float = e[0]
			quad("ashlar", Vector3(x, g(x, za) - 0.1, za), Vector3(x, g(x, zb) - 0.1, zb), Vector3(x, (g_top(20.0, zb) + 0.06), zb),
					Vector3(x, (g_top(20.0, za) + 0.06), za), Vector3(e[1], 0, 0))
	_paved.append(_poly_rect(Rect2(PATH.x, z0, PATH.y - PATH.x, z1 - z0)))
	# box hedges along it, gaps for the lawn's paths, box balls at their ends
	var z := z0 + 1.0
	while z < z1 - 1.0:
		var zb := minf(z + 6.0, z1 - 1.0)
		for x: float in [PATH.x - 0.55, PATH.y + 0.55]:
			var n := ceili((zb - z) / 1.0)
			for i in n:
				var za := z + (zb - z) * i / n
				var zz := z + (zb - z) * (i + 1) / n
				var gy := g(x, (za + zz) * 0.5)
				box("boxwood", x - 0.25, x + 0.25, gy - 0.1, gy + 0.55, za, zz)
			ball("boxwood", Vector3(x, g(x, z) + 0.45, z - 0.45), Vector3(0.38, 0.38, 0.38), 10)
		z = zb + 1.6


func _deck_top() -> float:
	var hi := -INF
	for x in range(int(DECK.position.x), int(DECK.end.x) + 1, 2):
		for z in range(int(DECK.position.y), int(DECK.end.y) + 1, 2):
			hi = maxf(hi, g(x, z))
	return hi + 1.5


func _deck_steps_len() -> float:
	var top := _deck_top()
	var gy := (g_top(20.0, DECK.position.y - 1.5) + 0.06)
	return maxi(1, ceili((top - gy) / RISE)) * TREAD


# ---------------------------------------------------------------- the pool

func _pool_outline(grow := 0.0, n := 18) -> PackedVector2Array:
	var cx := POOL.x
	var cz := POOL.y
	var r := POOL.w * 0.5 + grow
	var half := POOL.z * 0.5 - POOL.w * 0.5
	var out := PackedVector2Array()
	for i in n + 1:
		var a := -PI * 0.5 + PI * i / n
		out.append(Vector2(cx + half + cos(a) * r, cz + sin(a) * r))
	for i in n + 1:
		var a := PI * 0.5 + PI * i / n
		out.append(Vector2(cx - half + cos(a) * r, cz + sin(a) * r))
	return out


func _pool() -> void:
	var top := _deck_top()
	var lo := INF
	for x in range(int(DECK.position.x), int(DECK.end.x) + 1, 2):
		for z in range(int(DECK.position.y), int(DECK.end.y) + 1, 2):
			lo = minf(lo, g(x, z))
	var water := top - 0.14
	var bottom := top - 1.5
	var edge := _pool_outline()
	var coping := _pool_outline(0.42)
	# the deck: a stone base, travertine on top round the pool
	var d := DECK
	var pr := Rect2(POOL.x - POOL.z * 0.5, POOL.y - POOL.w * 0.5, POOL.z, POOL.w)
	for r: Rect2 in [Rect2(d.position, Vector2(d.size.x, pr.position.y - d.position.y)),
			Rect2(Vector2(d.position.x, pr.end.y), Vector2(d.size.x, d.end.y - pr.end.y)),
			Rect2(Vector2(d.position.x, pr.position.y), Vector2(pr.position.x - d.position.x, pr.size.y)),
			Rect2(Vector2(pr.end.x, pr.position.y), Vector2(d.end.x - pr.end.x, pr.size.y))]:
		box("ashlar", r.position.x, r.end.x, lo - 0.4, top - 0.06, r.position.y, r.end.y)
	var keep := func(x: float, z: float) -> bool:
		return not Geometry2D.is_point_in_polygon(Vector2(x, z), _pool_outline(0.2))
	_sheet_over(d, "pavers", keep, 0.0, func(_x: float, _z: float) -> float: return top, 0.25)
	box("coping", d.position.x - 0.08, d.end.x + 0.08, top - 0.06, top + 0.02, d.position.y - 0.08, d.position.y + 0.3)
	# its edge round the pool: coping stones over the jagged paving
	var ct := top + 0.025
	for i in edge.size():
		var a := edge[i]
		var b := edge[(i + 1) % edge.size()]
		var ca := coping[i]
		var cb := coping[(i + 1) % coping.size()]
		quad("coping", Vector3(a.x, ct, a.y), Vector3(b.x, ct, b.y), Vector3(cb.x, ct, cb.y), Vector3(ca.x, ct, ca.y), Vector3.UP)
		var inward := Vector3(POOL.x - (a.x + b.x) * 0.5, 0, POOL.y - (a.y + b.y) * 0.5)
		var nrm := -Vector3((b - a).y, 0, -(b - a).x).normalized()
		if nrm.dot(inward) < 0.0:
			nrm = -nrm
		quad("coping", Vector3(a.x, ct, a.y), Vector3(b.x, ct, b.y), Vector3(b.x, top - 0.12, b.y), Vector3(a.x, top - 0.12, a.y), nrm)
		# the basin's side, mosaic, down to its floor
		quad("mosaic", Vector3(a.x, top - 0.12, a.y), Vector3(b.x, top - 0.12, b.y), Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y), nrm)
		_faces.append_array(PackedVector3Array([Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bottom, b.y),
				Vector3(a.x, top, a.y), Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y)]))
		var c := Vector3(POOL.x, 0, POOL.y)
		tri("mosaic", Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(c.x, bottom, c.z), Vector3.UP)
		tri("water", Vector3(a.x, water, a.y), Vector3(b.x, water, b.y), Vector3(c.x, water, c.z), Vector3.UP)
		_faces.append_array(PackedVector3Array([Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(c.x, bottom, c.z)]))
	# the steps up from the path
	var gy := (g_top(20.0, d.position.y - 1.5) + 0.06)
	var n := maxi(1, ceili((top - gy) / RISE))
	gy = (g_top(20.0, d.position.y - n * TREAD) + 0.06)
	_steps(PATH.x - 1.0, PATH.y + 1.0, d.position.y - n * TREAD, gy, d.position.y, top)
	# steps down into the pool on its north side, a ramp up them (one walks out)
	var ez := POOL.y - POOL.w * 0.5
	var depth := [1.6, 1.2, 0.8, 0.4]
	for k in 4:
		var st_top := bottom + (top - 0.06 - bottom) * (k + 1) / 4.0
		box("travertine", 21.8, 25.2, bottom, st_top, ez, ez + depth[k])
		box("coping", 21.8, 25.2, st_top - 0.03, st_top + 0.005, ez + depth[k] - 0.06, ez + depth[k] + 0.01)
	col_ramp(Vector3(23.5, bottom, ez + 2.0), Vector3(23.5, top, ez), 3.4)
	for x: float in [21.6, 25.4]:
		rod("chrome", Vector3(x, top, ez - 0.25), Vector3(x, top + 0.9, ez - 0.05), 0.022)
		rod("chrome", Vector3(x, top + 0.9, ez - 0.05), Vector3(x, top + 0.5, ez + 0.5), 0.022)
		rod("chrome", Vector3(x, top + 0.5, ez + 0.5), Vector3(x, bottom + 0.6, ez + 1.4), 0.022)
	_paved.append(_poly_rect(Rect2(d.position.x, d.position.y - n * TREAD, d.size.x, d.size.y + n * TREAD)))
	# loungers along its south side, parasols between
	for x: float in [10.5, 14.5, 25.5, 29.5]:
		_lounger(Vector3(x, top, 71.6))
	for x: float in [20.0]:
		_parasol(Vector3(x - 7.5, top, 72.6))
		_parasol(Vector3(x + 7.5, top, 72.6))
	for x: float in [7.0, 33.0]:
		_pot(Vector3(x, top, 60.6), 0.5, 0.75)
		ball("leaves", Vector3(x, top + 1.5, 60.6), Vector3(0.75, 0.9, 0.75), 10)
		rod("wood_dark", Vector3(x, top + 0.6, 60.6), Vector3(x, top + 1.0, 60.6), 0.05)
	root.set_meta("pool_water", water)


func _lounger(p: Vector3) -> void:
	box("white", p.x - 0.36, p.x + 0.36, p.y + 0.28, p.y + 0.36, p.z - 0.6, p.z + 0.95)
	box("linen", p.x - 0.33, p.x + 0.33, p.y + 0.36, p.y + 0.43, p.z - 0.6, p.z + 0.95)
	var back := Transform3D(Basis(Vector3.RIGHT, -0.7), p + Vector3(0, 0.62, 1.15))
	box_xf("linen", back, Vector3(0.66, 0.08, 0.8))
	for dx: float in [-0.3, 0.3]:
		for dz: float in [-0.5, 1.25]:
			box("white", p.x + dx - 0.03, p.x + dx + 0.03, p.y, p.y + 0.3, p.z + dz - 0.03, p.z + dz + 0.03)
	box("linen", p.x - 0.25, p.x + 0.25, p.y + 0.43, p.y + 0.5, p.z - 0.45, p.z - 0.2)
	col(p.x - 0.36, p.x + 0.36, p.y, p.y + 0.45, p.z - 0.6, p.z + 1.5)


func _parasol(p: Vector3) -> void:
	box("travertine", p.x - 0.3, p.x + 0.3, p.y, p.y + 0.12, p.z - 0.3, p.z + 0.3)
	rod("oak", p, p + Vector3(0, 2.5, 0), 0.03)
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 1.6
	c.height = 0.5
	c.radial_segments = 8
	c.rings = 1
	tool("linen").append_from(c, 0, Transform3D(Basis.IDENTITY, p + Vector3(0, 2.45, 0)))


func _pot(p: Vector3, r: float, h: float) -> void:
	cyl("terracotta", p, r * 0.75, h, 14, r)
	torus("terracotta", Transform3D(Basis.IDENTITY, p + Vector3(0, h, 0)), r - 0.03, r + 0.05)
	cyl("soil", p + Vector3(0, h - 0.03, 0), r - 0.03, 0.05, 14)
	col(p.x - r * 0.8, p.x + r * 0.8, p.y, p.y + h, p.z - r * 0.8, p.z + r * 0.8)


func _pots() -> void:
	for x: float in [3.0, 9.0, 31.0, 37.0]:
		var gy := g(x, -1.8)
		_pot(Vector3(x, gy, -1.8), 0.62, 0.85)
	for x: float in [12.6, 27.4]:
		var gy := g(x, -1.3)
		_pot(Vector3(x, gy, -1.3), 0.4, 0.5)
		ball("boxwood", Vector3(x, gy + 0.85, -1.3), Vector3(0.42, 0.4, 0.42), 10)
	# lavender along the facade's foot, between the windows
	for x: float in [0.8, 5.0, 7.0, 11.0, 13.6, 26.4, 29.0, 33.0, 35.0, 39.2]:
		var gy := g(x, -0.6)
		for i in 5:
			ball("lavender", Vector3(x - 0.6 + i * 0.3, gy + 0.22, -0.55), Vector3(0.2, 0.24, 0.2), 8)


# ---------------------------------------------------------------- the fountain

func _fountain() -> void:
	var c := Vector2(FOUNTAIN.x, FOUNTAIN.y)
	var hi := -INF
	var lo := INF
	for i in 16:
		var a := TAU * i / 16
		for f: float in [0.0, 0.5, 1.0]:
			var p := c + Vector2(cos(a) * BASIN.x, sin(a) * BASIN.y) * f
			hi = maxf(hi, g(p.x, p.y))
			lo = minf(lo, g(p.x, p.y))
	var bottom := hi + 0.08
	var water := bottom + 0.6
	var rim := water + 0.2
	var n := 48
	# the basin: a stone rim wall from the ground, coping, a balustrade on the forecourt's side; its floor and water
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector2(cos(a0) * BASIN.x, sin(a0) * BASIN.y)
		var p1 := c + Vector2(cos(a1) * BASIN.x, sin(a1) * BASIN.y)
		var o0 := c + Vector2(cos(a0) * (BASIN.x + 0.45), sin(a0) * (BASIN.y + 0.45))
		var o1 := c + Vector2(cos(a1) * (BASIN.x + 0.45), sin(a1) * (BASIN.y + 0.45))
		var nrm := Vector3(cos((a0 + a1) * 0.5) / BASIN.x, 0, sin((a0 + a1) * 0.5) / BASIN.y).normalized()
		quad("ashlar", Vector3(o0.x, g(o0.x, o0.y) - 0.3, o0.y), Vector3(o1.x, g(o1.x, o1.y) - 0.3, o1.y),
				Vector3(o1.x, rim, o1.y), Vector3(o0.x, rim, o0.y), nrm)
		quad("coping", Vector3(p0.x, rim + 0.08, p0.y), Vector3(p1.x, rim + 0.08, p1.y), Vector3(o1.x, rim + 0.08, o1.y),
				Vector3(o0.x, rim + 0.08, o0.y), Vector3.UP)
		quad("coping", Vector3(o0.x, rim - 0.02, o0.y), Vector3(o1.x, rim - 0.02, o1.y), Vector3(o1.x, rim + 0.08, o1.y),
				Vector3(o0.x, rim + 0.08, o0.y), nrm)
		quad("ashlar", Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y), Vector3(p1.x, rim + 0.08, p1.y),
				Vector3(p0.x, rim + 0.08, p0.y), -nrm)
		tri("rubble", Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y), Vector3(c.x, bottom, c.y), Vector3.UP)
		tri("water", Vector3(p0.x, water, p0.y), Vector3(p1.x, water, p1.y), Vector3(c.x, water, c.y), Vector3.UP)
		_faces.append_array(PackedVector3Array([Vector3(o0.x, lo - 0.3, o0.y), Vector3(o1.x, lo - 0.3, o1.y),
				Vector3(o1.x, rim + 0.08, o1.y), Vector3(o0.x, lo - 0.3, o0.y), Vector3(o1.x, rim + 0.08, o1.y),
				Vector3(o0.x, rim + 0.08, o0.y), Vector3(p0.x, rim + 0.08, p0.y), Vector3(p1.x, rim + 0.08, p1.y),
				Vector3(o1.x, rim + 0.08, o1.y), Vector3(p0.x, rim + 0.08, p0.y), Vector3(o1.x, rim + 0.08, o1.y),
				Vector3(o0.x, rim + 0.08, o0.y), Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y),
				Vector3(c.x, bottom, c.y)]))
		# balusters on the forecourt's half (away from the grotto)
		var am := (a0 + a1) * 0.5
		if not _in_grotto(am):
			var q := c + Vector2(cos(am) * (BASIN.x + 0.22), sin(am) * (BASIN.y + 0.22))
			var base := Vector3(q.x, rim + 0.08, q.y)
			cyl("coping", base, 0.07, 0.12, 8, 0.1)
			cyl("coping", base + Vector3(0, 0.12, 0), 0.1, 0.34, 8, 0.055)
			cyl("coping", base + Vector3(0, 0.46, 0), 0.06, 0.16, 8, 0.08)
			var r0 := c + Vector2(cos(a0) * (BASIN.x + 0.22), sin(a0) * (BASIN.y + 0.22))
			var r1 := c + Vector2(cos(a1) * (BASIN.x + 0.22), sin(a1) * (BASIN.y + 0.22))
			var rail_xf := Transform3D(Basis.looking_at(Vector3(r1.x - r0.x, 0, r1.y - r0.y), Vector3.UP),
					Vector3((r0.x + r1.x) * 0.5, rim + 0.08 + 0.66, (r0.y + r1.y) * 0.5))
			box_xf("coping", rail_xf, Vector3(0.3, 0.1, r0.distance_to(r1) + 0.04))
			col_xf(Transform3D(rail_xf.basis, rail_xf.origin - Vector3(0, 0.33, 0)), Vector3(0.3, 0.75, r0.distance_to(r1)))
	_grotto(c, water)
	_paved.append(_ellipse(c, BASIN + Vector2(3.5, 3.5)))


func _in_grotto(a: float) -> bool:
	var x := wrapf(a, -PI, PI)
	return x > GROTTO.x and x < GROTTO.y


func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


## The grotto on the slope behind the basin: a wall of rocks, plants in its ledges, an upper basin in its middle
## pouring a curtain of water into the pool below (foam where it falls), side jets, a stone urn on top.
func _grotto(c: Vector2, water: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 391
	var steps := 22
	for i in steps + 1:
		var a := lerpf(GROTTO.x, GROTTO.y, float(i) / steps)
		var mid := 1.0 - absf(float(i) / steps - 0.5) * 2.0       # 1 in the middle, 0 at the ends
		var height := 1.6 + mid * 3.2
		for layer in 4:
			var rr := 0.9 + layer * 0.75
			var p := c + Vector2(cos(a) * (BASIN.x + rr), sin(a) * (BASIN.y + rr))
			var gy := g(p.x, p.y)
			var y := maxf(gy, water - 0.3)
			var top := water + height * (1.0 - layer * 0.12)
			while y < top:
				var s := rng.randf_range(0.55, 1.0)
				ball("rubble", Vector3(p.x + rng.randf_range(-0.3, 0.3), y + s * 0.5, p.y + rng.randf_range(-0.3, 0.3)),
						Vector3(s * rng.randf_range(0.8, 1.25), s * rng.randf_range(0.55, 0.8), s * rng.randf_range(0.8, 1.2)), 7)
				if rng.randf() < 0.18:
					ball("leaves", Vector3(p.x, y + s * 0.95, p.y), Vector3(0.5, 0.35, 0.5) * rng.randf_range(0.7, 1.3), 8)
				y += s * 0.75
			if layer == 0:
				var q := c + Vector2(cos(a) * (BASIN.x + 1.6), sin(a) * (BASIN.y + 1.6))
				col(q.x - 0.9, q.x + 0.9, g(q.x, q.y) - 0.2, top, q.y - 0.9, q.y + 0.9)
	# the upper basin and its curtain of water
	var am := (GROTTO.x + GROTTO.y) * 0.5
	var dir := Vector2(cos(am), sin(am))
	var lip := c + Vector2(dir.x * (BASIN.x - 0.2), dir.y * (BASIN.y - 0.2))
	var up := water + 2.6
	var side := Vector2(-dir.y, dir.x)
	var hw := 1.9
	var basin_c := lip + dir * 1.1
	var bxf := Transform3D(Basis.looking_at(Vector3(-dir.x, 0, -dir.y), Vector3.UP), Vector3(basin_c.x, up - 0.4, basin_c.y))
	box_xf("ashlar", bxf, Vector3(hw * 2.0 + 0.4, 0.5, 2.4))
	box_xf("coping", bxf, Vector3(hw * 2.0 + 0.6, 0.12, 0.3), Vector3(0, 0.3, 1.1))
	box_xf("water", bxf, Vector3(hw * 2.0, 0.02, 2.0), Vector3(0, 0.22, 0))
	var nf := 8
	for i in nf:
		var s0 := -hw + 2.0 * hw * i / nf
		var s1 := -hw + 2.0 * hw * (i + 1) / nf
		for j in 6:
			var t0 := float(j) / 6.0
			var t1 := float(j + 1) / 6.0
			var o0 := 0.12 + t0 * t0 * 0.9
			var o1 := 0.12 + t1 * t1 * 0.9
			var y0 := lerpf(up - 0.15, water, t0)
			var y1 := lerpf(up - 0.15, water, t1)
			var pa := lip - dir * o0 + side * s0
			var pb := lip - dir * o0 + side * s1
			var pc := lip - dir * o1 + side * s1
			var pd := lip - dir * o1 + side * s0
			quad("fall", Vector3(pa.x, y0, pa.y), Vector3(pb.x, y0, pb.y), Vector3(pc.x, y1, pc.y), Vector3(pd.x, y1, pd.y),
					Vector3(-dir.x, 0.3, -dir.y).normalized())
	var foam_c := lip - dir * 1.05
	for i in 16:
		var a0 := TAU * i / 16
		var a1 := TAU * (i + 1) / 16
		tri("foam", Vector3(foam_c.x, water + 0.015, foam_c.y),
				Vector3(foam_c.x + cos(a0) * 2.4, water + 0.015, foam_c.y + sin(a0) * 1.2),
				Vector3(foam_c.x + cos(a1) * 2.4, water + 0.015, foam_c.y + sin(a1) * 1.2), Vector3.UP)
	# side jets: arcs of water from the rocks
	for k: float in [-0.7, -0.35, 0.35, 0.7]:
		var a := am + k * (GROTTO.y - GROTTO.x) * 0.5
		var from := c + Vector2(cos(a) * (BASIN.x + 0.7), sin(a) * (BASIN.y + 0.7))
		var to := c + Vector2(cos(a) * (BASIN.x - 1.6), sin(a) * (BASIN.y - 1.6))
		var prev := Vector3(from.x, water + 1.0, from.y)
		for j in range(1, 7):
			var t := float(j) / 6.0
			var p := from.lerp(to, t)
			var y := water + 1.0 + 0.6 * t - 1.6 * t * t
			var q := Vector3(p.x, y, p.y)
			rod("fall", prev, q, 0.035, 6)
			prev = q
	# the urn on top
	var top_c := c + Vector2(dir.x * (BASIN.x + 2.4), dir.y * (BASIN.y + 2.4))
	var ty := water + 5.0
	box("ashlar", top_c.x - 0.5, top_c.x + 0.5, ty - 1.0, ty, top_c.y - 0.5, top_c.y + 0.5)
	cyl("coping", Vector3(top_c.x, ty, top_c.y), 0.22, 0.2, 12, 0.3)
	ball("coping", Vector3(top_c.x, ty + 0.55, top_c.y), Vector3(0.42, 0.42, 0.42), 12)
	cyl("coping", Vector3(top_c.x, ty + 0.85, top_c.y), 0.42, 0.12, 12, 0.48)
	ball("leaves", Vector3(top_c.x, ty + 1.15, top_c.y), Vector3(0.5, 0.35, 0.5), 10)
