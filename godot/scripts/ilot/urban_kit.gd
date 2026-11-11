extends "res://scripts/build_kit.gd"
## Street works in the supermarket's block (scripts/ilot/ilot_plan.gd), drawn in its streets' frame (local u, v: the
## node turned onto the map when committed) on its designed ground (heights over it): asphalt, paving slabs, granite
## kerbs as at Losplatos Custom's (their top, their face, the gutter at their foot), sidewalks along a kerb line and
## round corners, lowered where an access crosses them, and road markings (lines, dashes, zebras, arrows, the bays'
## pictograms). Collision: boxes on the flat site, the sidewalks' faces on the ring (its ground slopes).

const Plan = preload("res://scripts/ilot/ilot_plan.gd")
const KERB := 0.15                          # m: sidewalks over the asphalt (Losplatos Custom's KERB_UP)
const ASPHALT_UP := 0.04                    # m: asphalt over the ground (its TAR_UP)
const FILL := 0.05                          # m: painted fills (the bays') over the ground
const PAINT := 0.055                        # m: markings over the ground
const STEP := 2.0                           # m: surfaces cut so (the ground slopes)
const RAMP := 1.2                           # m: a sidewalk's slope down to a lowered crossing
const LOW := 0.055                          # m: a lowered crossing over the ground (just over the asphalt)
const KERB_TOP := 0.15                      # m: the kerb's top, wide
const GUTTER := 0.3
## The map's directions in the frame (y north: not Godot's 2D Vector2.UP, which is (0, -1)).
const NORTH := Vector2(0.0, 1.0)
const SOUTH := Vector2(0.0, -1.0)
const EAST := Vector2(1.0, 0.0)
const WEST := Vector2(-1.0, 0.0)

var faces := PackedVector3Array()           # collision faces (the ring's sidewalks), committed with the meshes


## Local point (u, v), h over the designed ground, in the node's frame.
static func p3(u: float, v: float, h: float) -> Vector3:
	return Vector3(u, Plan.height(Vector2(u, v)) + h, -v)


## A local direction as a normal in the node's frame.
static func nrm(out: Vector2) -> Vector3:
	return Vector3(out.x, 0.0, -out.y)


## The meshes and the collision, the node turned onto the map.
func commit(meshes := true, range_end := 0.0) -> Node3D:
	col_faces(faces)
	faces = PackedVector3Array()
	var n := super(meshes, range_end)
	n.transform = Plan.frame()
	return n


## A flat rectangle at h over the ground, facing up (cut in STEP m cells: it follows the ground).
func flat(r: Rect2, h: float, m: String) -> void:
	var nu := maxi(1, ceili(r.size.x / STEP))
	var nv := maxi(1, ceili(r.size.y / STEP))
	for i in nu:
		for j in nv:
			var u0 := r.position.x + r.size.x * i / nu
			var u1 := r.position.x + r.size.x * (i + 1) / nu
			var v0 := r.position.y + r.size.y * j / nv
			var v1 := r.position.y + r.size.y * (j + 1) / nv
			quad(m, p3(u0, v0, h), p3(u1, v0, h), p3(u1, v1, h), p3(u0, v1, h), Vector3.UP)


## A box over rectangle r from h0 to h1 over the ground at its middle (on the flat site).
func block(r: Rect2, h0: float, h1: float, m: String) -> void:
	var g := Plan.height(r.get_center())
	box(m, r.position.x, r.end.x, g + h0, g + h1, -r.end.y, -r.position.y)


## Its collision.
func block_col(r: Rect2, h0: float, h1: float) -> void:
	var g := Plan.height(r.get_center())
	col(r.position.x, r.end.x, g + h0, g + h1, -r.end.y, -r.position.y)


## A vertical face from a to b, heights h0..h1, facing `out`.
func face(a: Vector2, b: Vector2, h0: float, h1: float, m: String, out: Vector2) -> void:
	quad(m, p3(a.x, a.y, h0), p3(b.x, b.y, h0), p3(b.x, b.y, h1), p3(a.x, a.y, h1), nrm(out))


## A paved slab KERB high on the site: its top, its sides in kerb stone, a collision.
func slab(r: Rect2, top := "street_pavers", side := "kerb_face") -> void:
	flat(r, KERB, top)
	var a := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var u: Vector2 = a[i]
		var v: Vector2 = a[(i + 1) % 4]
		var t := (v - u).normalized()
		face(u, v, -0.05, KERB, side, Vector2(t.y, -t.x))
	block_col(r, -0.3, KERB)


## Asphalt over r, and a granite kerb along its edges where they meet bare ground (none of `paved` beyond).
func asphalt(r: Rect2, paved: Array, m := "street_asphalt") -> void:
	flat(r, ASPHALT_UP, m)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var u: Vector2 = corners[i]
		var v: Vector2 = corners[(i + 1) % 4]
		var t := (v - u).normalized()
		var out := Vector2(t.y, -t.x)            # (round anticlockwise: out on the right)
		var cuts := maxi(1, ceili(u.distance_to(v)))
		for j in cuts:
			var a := u.lerp(v, float(j) / cuts)
			var b := u.lerp(v, float(j + 1) / cuts)
			var probe := (a + b) * 0.5 + out * 0.3
			var bare := true
			for q: Rect2 in paved:
				bare = bare and not q.has_point(probe)
			if bare:
				kerb(a + out * KERB_TOP, b + out * KERB_TOP, -out, KERB)


## A granite kerb along its face's foot a -> b, its face towards `out` (the asphalt; its top KERB_TOP back from it),
## `top` m over the ground; the gutter at its foot.
func kerb(a: Vector2, b: Vector2, out: Vector2, top: float) -> void:
	var back := -out * KERB_TOP
	quad("kerb_top", p3(a.x, a.y, top), p3(b.x, b.y, top), p3(b.x + back.x, b.y + back.y, top),
			p3(a.x + back.x, a.y + back.y, top), Vector3.UP)
	quad("kerb_face", p3(a.x, a.y, ASPHALT_UP - 0.02), p3(b.x, b.y, ASPHALT_UP - 0.02), p3(b.x, b.y, top),
			p3(a.x, a.y, top), nrm(out))
	quad("kerb_face", p3(a.x + back.x, a.y + back.y, top), p3(b.x + back.x, b.y + back.y, top),
			p3(b.x + back.x, b.y + back.y, -0.1), p3(a.x + back.x, a.y + back.y, -0.1), nrm(-out))
	var g := out * GUTTER
	quad("gutter", p3(a.x, a.y, ASPHALT_UP + 0.012), p3(b.x, b.y, ASPHALT_UP + 0.012),
			p3(b.x + g.x, b.y + g.y, ASPHALT_UP + 0.012), p3(a.x + g.x, a.y + g.y, ASPHALT_UP + 0.012), Vector3.UP)


## A sidewalk along the kerb line a -> b, WALK_W m in towards `inward`: KERB high, lowered to LOW across the crossings
## `gaps` (Vector2: from, to, m from a) with RAMP m slopes either side; nothing drawn over `skips` (another's sidewalk).
func sidewalk(a: Vector2, b: Vector2, inward: Vector2, gaps: Array, skips := []) -> void:
	var t := (b - a).normalized()
	var length := a.distance_to(b)
	var cuts := [0.0, length]
	var s := STEP
	while s < length:
		cuts.append(s)
		s += STEP
	for g: Vector2 in gaps + skips:
		for c: float in [g.x - RAMP, g.x, g.y, g.y + RAMP]:
			if c > 0.0 and c < length:
				cuts.append(c)
	cuts.sort()
	var w := Plan.WALK_W
	for i in cuts.size() - 1:
		var d0: float = cuts[i]
		var d1: float = cuts[i + 1]
		var mid := (d0 + d1) * 0.5
		if d1 - d0 < 0.01 or _within(mid, skips):
			continue
		var h0 := _lift(d0, gaps, skips)
		var h1 := _lift(d1, gaps, skips)
		var k0 := a + t * d0
		var k1 := a + t * d1
		var e0 := k0 + inward * KERB_TOP
		var e1 := k1 + inward * KERB_TOP
		var i0 := k0 + inward * w
		var i1 := k1 + inward * w
		var top := [p3(k0.x, k0.y, h0), p3(k1.x, k1.y, h1), p3(e1.x, e1.y, h1), p3(e0.x, e0.y, h0)]
		var body := [top[3], top[2], p3(i1.x, i1.y, h1), p3(i0.x, i0.y, h0)]
		var front := [p3(k0.x, k0.y, ASPHALT_UP - 0.02), p3(k1.x, k1.y, ASPHALT_UP - 0.02), top[1], top[0]]
		quad("kerb_top", top[0], top[1], top[2], top[3], Vector3.UP)
		quad("street_drive" if _within(mid, gaps) else "street_pavers", body[0], body[1], body[2], body[3], Vector3.UP)
		quad("kerb_face", front[0], front[1], front[2], front[3], nrm(-inward))
		for q: Array in [top, body, front]:
			faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		var g := -inward * GUTTER
		quad("gutter", p3(k0.x, k0.y, ASPHALT_UP + 0.012), p3(k1.x, k1.y, ASPHALT_UP + 0.012),
				p3(k1.x + g.x, k1.y + g.y, ASPHALT_UP + 0.012), p3(k0.x + g.x, k0.y + g.y, ASPHALT_UP + 0.012), Vector3.UP)
		quad("kerb_face", body[3], body[2], p3(i1.x, i1.y, -0.25), p3(i0.x, i0.y, -0.25), nrm(inward))


static func _within(d: float, spans: Array) -> bool:
	for g: Vector2 in spans:
		if d > g.x and d < g.y:
			return true
	return false


## A sidewalk's height d m along it: KERB, LOW across its crossings, sloping between over RAMP m (none against a skip).
static func _lift(d: float, gaps: Array, skips: Array) -> float:
	var h := KERB
	for g: Vector2 in gaps:
		if d >= g.x and d <= g.y:
			return LOW
		if d > g.x - RAMP and d < g.x and not _within(g.x - 0.5 * RAMP, skips):
			h = minf(h, lerpf(KERB, LOW, (d - (g.x - RAMP)) / RAMP))
		if d > g.y and d < g.y + RAMP and not _within(g.y + 0.5 * RAMP, skips):
			h = minf(h, lerpf(LOW, KERB, (d - g.y) / RAMP))
	return h


## A sidewalk round a corner: centre c, from angle a0 to a1 (radians), its kerb Plan.CORNER m out, WALK_W m wide.
func sidewalk_arc(c: Vector2, a0: float, a1: float) -> void:
	var r := Plan.CORNER
	var ri := r - Plan.WALK_W
	var n := 9
	for i in n:
		var d0 := Vector2.from_angle(lerpf(a0, a1, float(i) / n))
		var d1 := Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n))
		var top := [_at(c, d0, r, KERB), _at(c, d1, r, KERB), _at(c, d1, r - KERB_TOP, KERB), _at(c, d0, r - KERB_TOP, KERB)]
		var body := [top[3], top[2], _at(c, d1, ri, KERB), _at(c, d0, ri, KERB)]
		var front := [_at(c, d0, r, ASPHALT_UP - 0.02), _at(c, d1, r, ASPHALT_UP - 0.02), top[1], top[0]]
		var out := nrm((d0 + d1).normalized())
		quad("kerb_top", top[0], top[1], top[2], top[3], Vector3.UP)
		quad("street_pavers", body[0], body[1], body[2], body[3], Vector3.UP)
		quad("kerb_face", front[0], front[1], front[2], front[3], out)
		for q: Array in [top, body, front]:
			faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		quad("gutter", _at(c, d0, r, ASPHALT_UP + 0.012), _at(c, d1, r, ASPHALT_UP + 0.012),
				_at(c, d1, r + GUTTER, ASPHALT_UP + 0.012), _at(c, d0, r + GUTTER, ASPHALT_UP + 0.012), Vector3.UP)
		quad("kerb_face", body[3], body[2], _at(c, d1, ri, -0.25), _at(c, d0, ri, -0.25), -out)


static func _at(c: Vector2, d: Vector2, r: float, h: float) -> Vector3:
	return p3(c.x + d.x * r, c.y + d.y * r, h)


## Asphalt between a corner's kerb (centre c, radius CORNER, from a0 to a1) and its square's far corner.
func asphalt_fillet(c: Vector2, a0: float, a1: float, m := "street_asphalt") -> void:
	var r := Plan.CORNER
	var far := c + (Vector2.from_angle(a0) + Vector2.from_angle(a1)) * r
	var n := 9
	for i in n:
		var p := c + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r
		var q := c + Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n)) * r
		tri(m, p3(far.x, far.y, ASPHALT_UP), p3(p.x, p.y, ASPHALT_UP), p3(q.x, q.y, ASPHALT_UP), Vector3.UP)


## Asphalt round a bend: centre c, from radius r0 to r1, from angle a0 to a1.
func asphalt_arc(c: Vector2, r0: float, r1: float, a0: float, a1: float, m := "street_asphalt") -> void:
	var n := 12
	for i in n:
		var d0 := Vector2.from_angle(lerpf(a0, a1, float(i) / n))
		var d1 := Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n))
		quad(m, _at(c, d0, r0, ASPHALT_UP), _at(c, d1, r0, ASPHALT_UP), _at(c, d1, r1, ASPHALT_UP),
				_at(c, d0, r1, ASPHALT_UP), Vector3.UP)


## The kerb along a road's edge a -> b (`out`: off the road), piece by piece as kind_at(local point beyond) says:
## 0 none (a road goes on), 1 lowered (a yard, a car park), 2 raised.
func road_edge(a: Vector2, b: Vector2, out: Vector2, kind_at: Callable) -> void:
	var cuts := maxi(1, ceili(a.distance_to(b)))
	for j in cuts:
		var p := a.lerp(b, float(j) / cuts)
		var q := a.lerp(b, float(j + 1) / cuts)
		var k: int = kind_at.call((p + q) * 0.5 + out * 0.8)
		if k > 0:
			kerb(p, q, -out, KERB if k == 2 else 0.06)


## The kerb round a bend's outside: centre c, radius r, from a0 to a1.
func road_edge_arc(c: Vector2, r: float, a0: float, a1: float, kind_at: Callable) -> void:
	var n := 12
	for i in n:
		var d0 := Vector2.from_angle(lerpf(a0, a1, float(i) / n))
		var d1 := Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n))
		var out := (d0 + d1).normalized()
		var k: int = kind_at.call(c + out * (r + 0.8))
		if k > 0:
			kerb(c + d0 * r, c + d1 * r, -out, KERB if k == 2 else 0.06)


## A painted line from a to b, w wide (cut in STEP m pieces: it follows the ground).
func line(a: Vector2, b: Vector2, w: float, m := "#eeeeea", h := PAINT) -> void:
	var n := (b - a).normalized()
	var o := Vector2(-n.y, n.x) * w * 0.5
	var cuts := maxi(1, ceili(a.distance_to(b) / STEP))
	for i in cuts:
		var p := a.lerp(b, float(i) / cuts)
		var q := a.lerp(b, float(i + 1) / cuts)
		quad(m, p3(p.x + o.x, p.y + o.y, h), p3(q.x + o.x, q.y + o.y, h), p3(q.x - o.x, q.y - o.y, h),
				p3(p.x - o.x, p.y - o.y, h), Vector3.UP)


## Dashes from a to b: `dash` m painted, `gap` m bare, skipping where skip(p) (a Callable, Vector2 -> bool).
func dashes(a: Vector2, b: Vector2, w: float, dash: float, gap: float, skip := Callable(), m := "#eeeeea") -> void:
	var length := a.distance_to(b)
	var s := 0.0
	while s < length:
		var e := minf(s + dash, length)
		var u := a.lerp(b, s / length)
		var v := a.lerp(b, e / length)
		if not (skip.is_valid() and skip.call((u + v) * 0.5)):
			line(u, v, w, m)
		s += dash + gap


## Dashes round an arc (centre c, radius r, from a0 to a1).
func dashes_arc(c: Vector2, r: float, a0: float, a1: float, w: float, dash: float, gap: float) -> void:
	var length := absf(a1 - a0) * r
	var s := 0.0
	while s < length:
		var e := minf(s + dash, length)
		var n := maxi(1, ceili(e - s))
		for i in n:
			var p := c + Vector2.from_angle(lerpf(a0, a1, (s + (e - s) * i / n) / length)) * r
			var q := c + Vector2.from_angle(lerpf(a0, a1, (s + (e - s) * (i + 1) / n) / length)) * r
			line(p, q, w)
		s += dash + gap


## A zebra over r: bars along `axis` (the road's direction: EAST or NORTH), 0.5 m wide every metre.
func zebra(r: Rect2, axis: Vector2) -> void:
	if axis.x != 0.0:
		var y := r.position.y + 0.25
		while y < r.end.y - 0.2:
			line(Vector2(r.position.x, y + 0.25), Vector2(r.end.x, y + 0.25), 0.5)
			y += 1.0
	else:
		var x := r.position.x + 0.25
		while x < r.end.x - 0.2:
			line(Vector2(x + 0.25, r.position.y), Vector2(x + 0.25, r.end.y), 0.5)
			x += 1.0


## An arrow painted at p pointing along dir (a shaft and a head).
func arrow(p: Vector2, dir: Vector2, m := "#eeeeea") -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	line(p - d * 2.0, p + d * 0.6, 0.18, m)
	var tip := p + d * 1.6
	var l := p + d * 0.5 + n * 0.55
	var r := p + d * 0.5 - n * 0.55
	tri(m, p3(tip.x, tip.y, PAINT), p3(l.x, l.y, PAINT), p3(r.x, r.y, PAINT), Vector3.UP)


## A painted polygon (local points, either way round).
func paint_poly(pts: PackedVector2Array, m: String, h := PAINT) -> void:
	var t := Geometry2D.triangulate_polygon(pts)
	for i in range(0, t.size(), 3):
		var a := pts[t[i]]
		var b := pts[t[i + 1]]
		var c := pts[t[i + 2]]
		tri(m, p3(a.x, a.y, h), p3(b.x, b.y, h), p3(c.x, c.y, h), Vector3.UP)


## A painted disc (or a ring from r0 out to r1).
func disc(c: Vector2, r1: float, m := "#eeeeea", r0 := 0.0, seg := 20) -> void:
	for i in seg:
		var a := Vector2.from_angle(TAU * i / seg)
		var b := Vector2.from_angle(TAU * (i + 1) / seg)
		if r0 <= 0.0:
			tri(m, p3(c.x, c.y, PAINT), p3(c.x + a.x * r1, c.y + a.y * r1, PAINT), p3(c.x + b.x * r1, c.y + b.y * r1, PAINT),
					Vector3.UP)
		else:
			quad(m, p3(c.x + a.x * r0, c.y + a.y * r0, PAINT), p3(c.x + a.x * r1, c.y + a.y * r1, PAINT),
					p3(c.x + b.x * r1, c.y + b.y * r1, PAINT), p3(c.x + b.x * r0, c.y + b.y * r0, PAINT), Vector3.UP)


## Diagonal hatching over r: lines w wide every `step` m.
func hatch(r: Rect2, w: float, step: float, m := "#eeeeea") -> void:
	var dx := r.size.y
	var t := -dx
	while t < r.size.x:
		var a := Vector2(r.position.x + t, r.position.y)
		var b := a + Vector2(dx, dx)
		var s0 := maxf(0.0, (r.position.x - a.x) / dx)
		var s1 := minf(1.0, (r.end.x - a.x) / dx)
		if s1 > s0:
			line(a.lerp(b, s0), a.lerp(b, s1), w, m)
		t += step
	line(r.position, Vector2(r.end.x, r.position.y), w, m)
	line(Vector2(r.position.x, r.end.y), r.end, w, m)


## The wheelchair pictogram of a PMR bay at c, upright towards `up`, about 2 m tall.
func wheelchair(c: Vector2, up: Vector2) -> void:
	var right := Vector2(up.y, -up.x)
	var at := func(a: float, b: float) -> Vector2: return c + right * a + up * b
	disc(at.call(0.1, -0.45), 0.8, "#eeeeea", 0.62)
	disc(at.call(-0.15, 1.0), 0.21)
	line(at.call(-0.15, 0.7), at.call(-0.15, -0.15), 0.2)
	line(at.call(-0.15, -0.15), at.call(0.6, -0.15), 0.2)
	line(at.call(0.6, -0.15), at.call(0.8, -0.8), 0.18)
	line(at.call(-0.15, 0.45), at.call(0.35, 0.25), 0.15)


## The lightning bolt of an EV charger's bay at c, upright towards `up`, about 2 m tall.
func bolt(c: Vector2, up: Vector2) -> void:
	var right := Vector2(up.y, -up.x)
	var pts := PackedVector2Array()
	for q: Vector2 in [Vector2(0.2, 1.0), Vector2(-0.45, -0.1), Vector2(-0.02, -0.1), Vector2(-0.25, -1.0),
			Vector2(0.45, 0.2), Vector2(0.02, 0.2)]:
		pts.append(c + right * q.x + up * q.y)
	paint_poly(pts, "#eeeeea")
