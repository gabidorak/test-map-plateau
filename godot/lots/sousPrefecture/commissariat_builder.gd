extends "res://scripts/street_kit.gd"
## The commissariat drawn (lot sousPrefecture, commissariat_plan.gd: in the building's frame), after ref/prefecture/
## Vue1-3: the wedge in ochre concrete with fine horizontal lines (CONCRETE), its two long walls rising from the
## ground at the courtyard's tip to the parapet, the courtyard open between them; north of it the building in three
## steps (one, two, three storeys), their roofs the planted terraces (planters, shrubs, small trees on gravel) and the
## highest one's the heliport (its deck, its markings, its lights); punched windows on the long facades, the wide
## glazing of the north facade, the glazed fronts of the steps and of the courtyard's south face, the public entrance
## on the west facade under its name; the French and European flags on the sidewalk before it. No interior:
## its outside is closed (walls, glass, roofs). Collision: every face of it (the heliport's deck the helicopter's base).

const Plan = preload("res://lots/sousPrefecture/commissariat_plan.gd")
const CONCRETE := "commissariat_concrete"
const GLASS := "glass_dark"
const FRAME := "charcoal"
const DEPTH := 0.25                         # m: the glazing set back in the walls
const FOOT := -3.4                          # Godot y: the walls' foot (under the lowest ground round it)
const SILL := [0.9, 5.1, 9.3]               # m over the floor: each storey's windows, 2.4 m high
const WIN_H := 2.4
const WIN_W := 1.5
const WIN_STEP := 3.0
const MARK := "#f1f0ea"                     # the heliport's markings


func _init() -> void:
	super("Commissariat", {"type": "lot", "lot": "sousPrefecture", "name": "Commissariat",
			"about": "the police's commissariat in the sous-préfecture (#630): its heliport, terraces, courtyard"}, Plan)
	add_material(CONCRETE, _concrete())
	var amber := plain(Color("#ffa21a"), 0.4)
	amber.emission_enabled = true
	amber.emission = Color("#ff9a10")
	amber.emission_energy_multiplier = 3.0
	add_material("commissariat_pad_light", amber)


## The building, committed: a node (meshes only when `meshes`).
func build(meshes: bool) -> Node3D:
	_walls()
	_north()
	_steps()
	_roofs()
	_heliport()
	_terraces()
	_flag_poles()
	_name()
	return commit(meshes)


## Local point (x, y) at Godot height z (absolute), in the node's frame.
static func v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func lvl(i: int) -> float:
	return Plan.FLOOR + Plan.ROOFS[i]


# ---------------------------------------------------------------- the walls

## The two long walls: their outer faces (the windows of the storeys behind them, the entrance), their inner faces
## over the courtyard and the roofs, their tops, their ends at the tip.
func _walls() -> void:
	var top := func(y: float) -> float: return Plan.wall_top(y)
	var cy := Plan.COURT_W.y
	# west: x 0 (outside), WALL (inside); t = y
	var holes := _windows(func(y: float) -> float: return y, cy, true)
	holes.append(Rect2(Plan.ENTRANCE.x, Plan.FLOOR, Plan.ENTRANCE.y - Plan.ENTRANCE.x, 3.4))
	facade(Vector2(0, 0), Vector2(0, Plan.NORTH_Y), Vector2(-1, 0), FOOT, top, holes, [Plan.STEP_TOP], 0.0,
			{Plan.ENTRANCE.x: 1.5})
	var w := Plan.WALL
	for seg: Array in [[0.0, cy, FOOT], [cy, Plan.STEP_MID, lvl(0)], [Plan.STEP_MID, Plan.STEP_TOP, lvl(1)],
			[Plan.STEP_TOP, Plan.NORTH_Y - w, lvl(2)]]:
		facade(Vector2(w, seg[0]), Vector2(w, seg[1]), Vector2(1, 0), seg[2], func(t: float) -> float:
				return Plan.wall_top(seg[0] + t), [], [Plan.STEP_TOP - seg[0]])
	# east: from the tip to the north-east corner; t along it
	var a := Vector2(Plan.TIP_E, 0)
	var b := Vector2(Plan.NORTH_E, Plan.NORTH_Y)
	var d := (b - a).normalized()
	var out := Vector2(d.y, -d.x)
	var t_of := func(y: float) -> float: return y / d.y
	facade(a, b, out, FOOT, func(t: float) -> float: return Plan.wall_top(t * d.y),
			_windows(t_of, Plan.COURT_E_Y, false), [Plan.STEP_TOP / d.y])
	for seg: Array in [[0.0, Plan.COURT_E_Y, FOOT], [Plan.COURT_E_Y, Plan.STEP_MID, lvl(0)],
			[Plan.STEP_MID, Plan.STEP_TOP, lvl(1)], [Plan.STEP_TOP, Plan.NORTH_Y - w, lvl(2)]]:
		var p := Vector2(Plan.east_x(seg[0]) - w, seg[0])
		var q := Vector2(Plan.east_x(seg[1]) - w, seg[1])
		var dy: float = (q - p).normalized().y
		facade(p, q, -out, seg[2], func(t: float) -> float: return Plan.wall_top(seg[0] + t * dy), [],
				[(Plan.STEP_TOP - seg[0]) / dy])
	# their tops: sloping up to STEP_TOP, then the parapet round the highest roof (one U)
	var s := Plan.STEP_TOP
	var ts := Plan.wall_top(0.0)
	var tp := Plan.FLOOR + Plan.PARAPET
	_top([v(0, 0, ts), v(w, 0, ts), v(w, s, tp), v(0, s, tp)])
	_top([v(Plan.TIP_E - w, 0, ts), v(Plan.TIP_E, 0, ts), v(Plan.east_x(s), s, tp), v(Plan.east_x(s) - w, s, tp)])
	var ny := Plan.NORTH_Y
	_poly(PackedVector2Array([Vector2(0, s), Vector2(0, ny), Vector2(Plan.NORTH_E, ny), Vector2(Plan.east_x(s), s),
			Vector2(Plan.east_x(s) - w, s), Vector2(Plan.east_x(ny - w) - w, ny - w), Vector2(w, ny - w), Vector2(w, s)]),
			tp, CONCRETE)
	# their ends at the tip (into the ground)
	for x0: float in [0.0, Plan.TIP_E - w]:
		var f := [v(x0, 0, FOOT), v(x0 + w, 0, FOOT), v(x0 + w, 0, ts), v(x0, 0, ts)]
		quad(CONCRETE, f[0], f[1], f[2], f[3], Vector3.BACK)
		faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))


## The punched windows of a long facade (t_of(y): its t at y), each storey where the building behind it has it: the
## ground floor from `g0` (its y), the first from STEP_MID, the second from STEP_TOP; none across the entrance (the
## west facade's, `entrance`).
func _windows(t_of: Callable, g0: float, entrance: bool) -> Array:
	var out := []
	for s in 3:
		var y: float = [g0, Plan.STEP_MID, Plan.STEP_TOP][s] + 1.5
		while y + WIN_W <= Plan.NORTH_Y - 1.2:
			if s > 0 or not entrance or y + WIN_W < Plan.ENTRANCE.x - 0.8 or y > Plan.ENTRANCE.y + 0.8:
				var t0: float = t_of.call(y)
				out.append(Rect2(t0, Plan.FLOOR + SILL[s], float(t_of.call(y + WIN_W)) - t0, WIN_H))
			y += WIN_STEP
	return out


## A sloping top face (its normal up).
func _top(q: Array) -> void:
	var n := ((q[1] - q[0]) as Vector3).cross(q[3] - q[0]).normalized()
	quad(CONCRETE, q[0], q[1], q[2], q[3], n if n.y > 0.0 else -n)
	faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))


## A flat polygon (local) at Godot height z, facing up.
func _poly(p: PackedVector2Array, z: float, m: String) -> void:
	var idx := Geometry2D.triangulate_polygon(p)
	if idx.is_empty():
		push_warning("commissariat: a polygon of %d points not triangulated" % p.size())
	for i in range(0, idx.size(), 3):
		var a := v(p[idx[i]].x, p[idx[i]].y, z)
		var b := v(p[idx[i + 1]].x, p[idx[i + 1]].y, z)
		var c := v(p[idx[i + 2]].x, p[idx[i + 2]].y, z)
		tri(m, a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))


## A facade from a to b (local; t m along it from a), facing `out`, from z0 up to top(t) (Godot y), with `holes`
## (Rect2: t, z (Godot y), width, height): each a glazing DEPTH m in, its reveals, its frame, mullions every `mull` m
## (and those listed in `doors`: t of a hole -> its mullions' step); `breaks`: the t where top() bends.
func facade(a: Vector2, b: Vector2, out: Vector2, z0: float, top: Callable, holes: Array, breaks := [],
		mull := 0.0, doors := {}, m := CONCRETE) -> void:
	var length := a.distance_to(b)
	var ts := [0.0, length]
	for t: float in breaks:
		if t > 0.0 and t < length:
			ts.append(t)
	for h: Rect2 in holes:
		ts.append(h.position.x)
		ts.append(h.end.x)
	ts.sort()
	var n := nrm(out)
	for i in ts.size() - 1:
		var t0: float = ts[i]
		var t1: float = ts[i + 1]
		if t1 - t0 < 0.001:
			continue
		var tm := (t0 + t1) * 0.5
		var zs := [z0]
		for h: Rect2 in holes:
			if h.position.x < tm and tm < h.end.x:
				zs.append(h.position.y)
				zs.append(h.end.y)
		zs.sort()
		var top0: float = top.call(t0)
		var top1: float = top.call(t1)
		for j in zs.size() - 1:
			var za: float = zs[j]
			var zb: float = zs[j + 1]
			if zb - za < 0.001 or _in_hole(tm, (za + zb) * 0.5, holes):
				continue
			_cell(a, b, length, t0, t1, za, za, zb, zb, n, m)
		var zl: float = zs.back()
		if minf(top0, top1) > zl + 0.001:
			_cell(a, b, length, t0, t1, zl, zl, top0, top1, n, m)
	for h: Rect2 in holes:
		_opening(a, b, length, h, out, float(doors.get(h.position.x, mull)))


static func _in_hole(t: float, z: float, holes: Array) -> bool:
	for h: Rect2 in holes:
		if h.has_point(Vector2(t, z)):
			return true
	return false


## A facade's quad between t0 and t1, from za0/za1 up to zb0/zb1.
func _cell(a: Vector2, b: Vector2, length: float, t0: float, t1: float, za0: float, za1: float, zb0: float,
		zb1: float, n: Vector3, m: String) -> void:
	var p := a.lerp(b, t0 / length)
	var q := a.lerp(b, t1 / length)
	var f := [v(p.x, p.y, za0), v(q.x, q.y, za1), v(q.x, q.y, zb1), v(p.x, p.y, zb0)]
	quad(m, f[0], f[1], f[2], f[3], n)
	faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))


## A hole of a facade: its reveals DEPTH m in, its glass there, its frame and mullions just in front of the glass.
func _opening(a: Vector2, b: Vector2, length: float, h: Rect2, out: Vector2, mull: float) -> void:
	var d := (b - a) / length
	var inw := -out * DEPTH
	var p := a + d * h.position.x
	var q := a + d * h.end.x
	var z0 := h.position.y
	var z1 := h.end.y
	var pi := p + inw
	var qi := q + inw
	for f: Array in [[v(p.x, p.y, z0), v(q.x, q.y, z0), v(qi.x, qi.y, z0), v(pi.x, pi.y, z0), Vector3.UP],
			[v(p.x, p.y, z1), v(q.x, q.y, z1), v(qi.x, qi.y, z1), v(pi.x, pi.y, z1), Vector3.DOWN],
			[v(p.x, p.y, z0), v(pi.x, pi.y, z0), v(pi.x, pi.y, z1), v(p.x, p.y, z1), nrm(d)],
			[v(q.x, q.y, z0), v(qi.x, qi.y, z0), v(qi.x, qi.y, z1), v(q.x, q.y, z1), nrm(-d)]]:
		quad(CONCRETE, f[0], f[1], f[2], f[3], f[4])
	var g := [v(pi.x, pi.y, z0), v(qi.x, qi.y, z0), v(qi.x, qi.y, z1), v(pi.x, pi.y, z1)]
	quad(GLASS, g[0], g[1], g[2], g[3], nrm(out))
	faces.append_array(PackedVector3Array([g[0], g[1], g[2], g[0], g[2], g[3]]))
	# the frame round it, the mullions, a transom on the storeys' line
	var f0 := pi + out * 0.02
	var f1 := qi + out * 0.02
	var fw := 0.07
	_bar(f0, f1, z0, z0 + fw, out)
	_bar(f0, f1, z1 - fw, z1, out)
	_bar(f0, f0 + d * fw, z0, z1, out)
	_bar(f1 - d * fw, f1, z0, z1, out)
	if mull > 0.0:
		var w := h.size.x
		var k := maxi(1, roundi(w / mull))
		for i in range(1, k):
			var c := f0 + d * (w * i / k)
			_bar(c - d * 0.04, c + d * 0.04, z0, z1, out)
	for s in [1, 2]:
		var zs: float = Plan.FLOOR + Plan.STOREY * float(s)
		if zs > z0 + 0.5 and zs < z1 - 0.5:
			_bar(f0, f1, zs - 0.15, zs + 0.15, out)


## A frame bar on a glazing's plane, from p to q (local), z0 to z1, facing `out`.
func _bar(p: Vector2, q: Vector2, z0: float, z1: float, out: Vector2) -> void:
	quad(FRAME, v(p.x, p.y, z0), v(q.x, q.y, z0), v(q.x, q.y, z1), v(p.x, p.y, z1), nrm(out))


# ---------------------------------------------------------------- the north facade, the steps' fronts

## The north facade (on the car park): its wide glazing over two storeys, the staff door, the second storey's
## windows; its parapet's inside over the highest roof.
func _north() -> void:
	var ny := Plan.NORTH_Y
	var f := Plan.FLOOR
	var holes := [Rect2(2.0, f, 1.8, 2.5), Rect2(6.0, f + 0.9, 27.0, 6.7)]
	for k in 9:
		holes.append(Rect2(6.75 + 3.0 * k, f + SILL[2], WIN_W, WIN_H))
	facade(Vector2(0, ny), Vector2(Plan.NORTH_E, ny), Vector2(0, 1), FOOT,
			func(_t: float) -> float: return f + Plan.PARAPET, holes, [], 0.0, {6.0: 1.5})
	var w := Plan.WALL
	facade(Vector2(w, ny - w), Vector2(Plan.east_x(ny - w) - w, ny - w), Vector2(0, -1), lvl(2),
			func(_t: float) -> float: return f + Plan.PARAPET, [])


## The glazed fronts: the courtyard's south face (the ground floor) and the steps' (over the terraces).
func _steps() -> void:
	var w := Plan.WALL
	var ce := Plan.court_e()
	var d := (ce - Plan.COURT_W).normalized()
	var l := Plan.COURT_W.distance_to(ce)
	facade(Plan.COURT_W, ce, Vector2(d.y, -d.x), FOOT, func(_t: float) -> float: return lvl(0),
			[Rect2(1.0, Plan.FLOOR + 0.3, l - 2.0, 3.4)], [], 1.5)
	for k in 2:
		var y: float = [Plan.STEP_MID, Plan.STEP_TOP][k]
		var a := Vector2(w, y)
		var b := Vector2(Plan.east_x(y) - w, y)
		var z0 := lvl(k)
		var z1 := lvl(k + 1)
		facade(a, b, Vector2(0, -1), z0, func(_t: float) -> float: return z1,
				[Rect2(0.5, z0 + 0.35, a.distance_to(b) - 1.0, z1 - z0 - 1.1)], [], 1.6)


# ---------------------------------------------------------------- the roofs

func _roofs() -> void:
	var w := Plan.WALL
	var e := func(y: float) -> float: return Plan.east_x(y) - w
	var ce := Plan.court_e()
	var sm := Plan.STEP_MID
	var st := Plan.STEP_TOP
	var ny := Plan.NORTH_Y - w
	_poly(PackedVector2Array([Plan.COURT_W, Vector2(w, sm), Vector2(e.call(sm), sm), ce]), lvl(0), "#a39c90")
	_poly(PackedVector2Array([Vector2(w, sm), Vector2(w, st), Vector2(e.call(st), st), Vector2(e.call(sm), sm)]),
			lvl(1), "#a39c90")
	_poly(PackedVector2Array([Vector2(w, st), Vector2(w, ny), Vector2(e.call(ny), ny), Vector2(e.call(st), st)]),
			lvl(2), "#b7b1a6")


## The heliport on the highest roof: its deck PAD_UP high, the white edge, the circle and the H, a light at each
## corner and in the middle of each side.
func _heliport() -> void:
	var r := Plan.HELIPAD
	var z0 := lvl(2)
	var z1 := z0 + Plan.PAD_UP
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	_poly(PackedVector2Array(c), z1, "#5d6268")
	for i in 4:
		var p: Vector2 = c[i]
		var q: Vector2 = c[(i + 1) % 4]
		var t := (q - p).normalized()
		var f := [v(p.x, p.y, z0), v(q.x, q.y, z0), v(q.x, q.y, z1), v(p.x, p.y, z1)]
		quad("#5d6268", f[0], f[1], f[2], f[3], nrm(Vector2(t.y, -t.x)))
		faces.append_array(PackedVector3Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
	var zm := z1 + 0.01
	var inner := r.grow(-0.3)
	for e: Rect2 in [Rect2(inner.position, Vector2(inner.size.x, 0.4)),
			Rect2(inner.position.x, inner.end.y - 0.4, inner.size.x, 0.4),
			Rect2(inner.position.x, inner.position.y + 0.4, 0.4, inner.size.y - 0.8),
			Rect2(inner.end.x - 0.4, inner.position.y + 0.4, 0.4, inner.size.y - 0.8)]:
		_rect(e, zm, MARK)
	var mid := r.get_center()
	for i in 48:
		var a0 := TAU * i / 48.0
		var a1 := TAU * (i + 1) / 48.0
		var p0 := mid + Vector2.from_angle(a0) * 5.6
		var p1 := mid + Vector2.from_angle(a1) * 5.6
		var q0 := mid + Vector2.from_angle(a0) * 6.1
		var q1 := mid + Vector2.from_angle(a1) * 6.1
		quad(MARK, v(p0.x, p0.y, zm), v(p1.x, p1.y, zm), v(q1.x, q1.y, zm), v(q0.x, q0.y, zm), Vector3.UP)
	_rect(Rect2(mid.x - 2.0, mid.y - 2.6, 0.8, 5.2), zm, MARK)      # the H, upright from the south
	_rect(Rect2(mid.x + 1.2, mid.y - 2.6, 0.8, 5.2), zm, MARK)
	_rect(Rect2(mid.x - 1.2, mid.y - 0.4, 2.4, 0.8), zm, MARK)
	for p: Vector2 in c + [(c[0] + c[1]) * 0.5, (c[1] + c[2]) * 0.5, (c[2] + c[3]) * 0.5, (c[3] + c[0]) * 0.5]:
		var q := mid + (p - mid) * 0.985
		box("commissariat_pad_light", q.x - 0.15, q.x + 0.15, z1, z1 + 0.12, -q.y - 0.15, -q.y + 0.15)


func _rect(r: Rect2, z: float, m: String) -> void:
	quad(m, v(r.position.x, r.position.y, z), v(r.end.x, r.position.y, z), v(r.end.x, r.end.y, z),
			v(r.position.x, r.end.y, z), Vector3.UP)


## The terraces' planting: rows of planters (lawn on top, shrubs along), a few small trees; on the highest roof a strip
## of sedum along its south edge.
func _terraces() -> void:
	var w := Plan.WALL
	var rows := [[lvl(0), [66.0, 69.6]], [lvl(1), [77.0, 80.6]]]
	for row: Array in rows:
		var z: float = row[0]
		for y0: float in row[1]:
			var y1 := y0 + 1.4
			var x0 := w + 1.6
			var x1 := Plan.east_x(y0) - w - 1.6
			if x1 - x0 < 3.0:
				continue
			box("#b9a58c", x0, x1, z, z + 0.5, -y1, -y0)
			_rect(Rect2(x0 + 0.1, y0 + 0.1, x1 - x0 - 0.2, 1.2), z + 0.51, "plant_light")
			var x := x0 + 0.9
			while x < x1 - 0.6:
				ball("plant", v(x, y0 + 0.7, z + 0.75), Vector3(0.55, 0.45, 0.55), 8)
				x += 2.3
	for t: Array in [[Vector2(6.0, 72.0), 0], [Vector2(15.0, 72.2), 0], [Vector2(5.0, 83.0), 1], [Vector2(18.0, 83.2), 1]]:
		var p: Vector2 = t[0]
		var z := lvl(int(t[1]))
		box("#b9a58c", p.x - 0.7, p.x + 0.7, z, z + 0.6, -p.y - 0.7, -p.y + 0.7)
		rod("wood_dark", v(p.x, p.y, z + 0.6), v(p.x, p.y, z + 2.4), 0.09, 6)
		ball("plant", v(p.x, p.y, z + 3.0), Vector3(1.3, 1.1, 1.3), 10)
		ball("plant_light", v(p.x + 0.4, p.y - 0.3, z + 3.5), Vector3(0.8, 0.7, 0.8), 8)
	var y := Plan.STEP_TOP + w
	_rect(Rect2(w, y, Plan.east_x(y) - 2 * w, 2.5), lvl(2) + 0.02, "plant_light")


# ---------------------------------------------------------------- the entrance

## The French and the European flags on the sidewalk before the entrance (8 m poles).
func _flag_poles() -> void:
	for k in 2:
		var y: float = Plan.FLAGS[k]
		var p := Vector2(Plan.tree_x(y), y)
		var g := Plan.height(p) - 0.2
		cyl("#c9c3b7", v(p.x, p.y, g), 0.11, 0.35, 10)
		rod("white", v(p.x, p.y, g + 0.1), v(p.x, p.y, g + 8.2), 0.045, 8)
		col(p.x - 0.06, p.x + 0.06, g, g + 8.2, -p.y - 0.06, -p.y + 0.06)
		var z0 := g + 7.0
		var z1 := g + 8.0
		if k == 0:
			for i in 3:
				var c: String = ["#2e4fa8", "#f4f4f2", "#e1393b"][i]
				_cloth(p.x, p.y + 0.06 + 0.5 * i, p.y + 0.06 + 0.5 * (i + 1), z0, z1, c)
		else:
			_cloth(p.x, p.y + 0.06, p.y + 1.56, z0, z1, "#1f3f99")
			var mid := Vector2(p.y + 0.81, (z0 + z1) * 0.5)
			for i in 12:
				var s := mid + Vector2.from_angle(TAU * i / 12.0) * 0.33
				for side: float in [-0.02, 0.02]:
					quad("#ffcc00", Vector3(p.x + side, s.y - 0.035, -(s.x - 0.035)), Vector3(p.x + side, s.y - 0.035,
							-(s.x + 0.035)), Vector3(p.x + side, s.y + 0.035, -(s.x + 0.035)),
							Vector3(p.x + side, s.y + 0.035, -(s.x - 0.035)), Vector3(signf(side), 0, 0))


## A flag's cloth (both faces) in the plane x, from y0 to y1, z0 to z1.
func _cloth(x: float, y0: float, y1: float, z0: float, z1: float, m: String) -> void:
	for side: float in [-0.008, 0.008]:
		quad(m, v(x + side, y0, z0), v(x + side, y1, z0), v(x + side, y1, z1), v(x + side, y0, z1),
				Vector3(signf(side), 0, 0))


## The name over the entrance.
func _name() -> void:
	var y := (Plan.ENTRANCE.x + Plan.ENTRANCE.y) * 0.5
	label("COMMISSARIAT", Transform3D(Basis(Vector3.UP, -PI * 0.5), v(-0.03, y, Plan.FLOOR + 4.15)), 72, 0.01,
			Color("#1d2a44"))


# ---------------------------------------------------------------- the concrete

## Ochre concrete with fine horizontal lines (formwork boards' joints, every 0.3 m), mapped from the building's own
## axes (triplanar).
static func _concrete() -> StandardMaterial3D:
	var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
	var base := Color("#cc976c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 630
	for j in 64:
		var c := base.darkened(rng.randf_range(0.0, 0.04))
		if j % 16 == 0:
			c = base.darkened(0.16)
		elif j % 16 == 1:
			c = base.darkened(0.08)
		for i in 8:
			img.set_pixel(i, j, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE / 1.2
	m.uv1_triplanar_sharpness = 8.0
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
