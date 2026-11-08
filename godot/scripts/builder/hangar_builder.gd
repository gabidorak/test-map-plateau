@tool
extends RefCounted
## The Atlantis bus station's finish and the bus depot beside it (world/rail.json massy `bus_station`,
## tools/rail/bus_station.py and bus_depot.py), drawn for massy_builder.gd (`host`: its meshers, collision, labels and
## lamp lights):
## - the road markings (white and yellow triangles just over the ground: lane lines, arrows, the stop bays' zigzags,
##   zebras, the hatched nose; the depot's lanes, bays, walkway hatch and car park spaces), the BUS letters and the
##   bays' numbers (Label3D lying on the ground);
## - the kerb stones (the quays', the sidewalks', the depot's edges over its grass), the retaining walls (concrete, a
##   coping or a parapet over the higher ground), the lamps along the quays, the sidewalk and in the depot's car park;
## - the depot (bus_depot.py, after Gent's bus station): one thin flat roof, light grey, its underside smooth, its edge
##   bevelled up to a slim fascia, on slender inclined columns in V pairs, no walls; round downlights under it,
##   "Hangar de la gare routière" on both long fascias, the stairs from the car park, the "Nous recrutons !" panel
##   facing the avenue, the green welded-mesh fence round it; collision for the roof, columns, stairs, fence.
## The lamps' lights are night.gd's (the MassyPalaiseau node's "lamp_lights" meta).

const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
const LabelFit = preload("res://scripts/label_fit.gd")

const PAINT := {"white": Color("#f3f2ec"), "yellow": Color("#f0be2a")}
const KERB_TOP := Color("#e3dfd6")
const KERB_FACE := Color("#c9c3b7")
const CONCRETE := Color("#d3cec4")
const COPING := Color("#e6e2da")
const STEEL := Color("#5b6168")
const GLOW := Color("#fff3cc")
const ROOF_TOP := Color("#c9ccd0")
const ROOF_UNDER := Color("#e4e5e6")         # the smooth light underside (photo of Gent)
const ROOF_EDGE_COL := Color("#d9dbdd")
const COLUMN := Color("#cfd3d6")
const STONE := Color("#cfcac0")
const SIGN_BLUE := Color("#20386f")
const BANNER_RED := Color("#c8102e")
const FENCE_GREEN := Color("#2e5a36")       # as the RATP's welded mesh along the tracks
const FENCE_H := 2.0
const LAMP_HEIGHT := 5.5                    # m, the bus station's lamps
const KERB_W := 0.3                         # m, a kerb stone's top

var host                                    # massy_builder.gd
var B: Dictionary
var _o := Vector2.ZERO
var _d := Vector2.RIGHT
var _n := Vector2.UP
var _s0 := 0.0
var _t0 := 0.0


func build(h, bus: Dictionary) -> void:
	host = h
	B = bus
	_o = host._v2(B["frame"]["o"])
	_d = host._v2(B["frame"]["d"]).normalized()
	_n = Vector2(-_d.y, _d.x)
	_markings()
	_labels()
	_copings()
	_walls()
	_lamps()
	if B.has("depot"):
		_depot(B["depot"])
		_fences(B.get("depot_fences", []))


# ---------------------------------------------------------------- frame

## Map point at (s along the station's axis, t across it towards the tracks).
func _p(s: float, t: float) -> Vector2:
	return _o + _d * s + _n * t


func _q(s: float, t: float, z: float) -> Vector3:
	var p := _p(s, t)
	return Vector3(p.x, z, -p.y)


## Godot direction of the frame's (ds, dt).
func _dir(ds: float, dt: float) -> Vector3:
	var v := _d * ds + _n * dt
	return Vector3(v.x, 0.0, -v.y).normalized()


func _box_st(m: RailBuilder.Mesher, s: float, t: float, z: float, size: Vector3, col: Color, shape := false,
		info := {}) -> void:
	## A box centred on (s, t, z), its x along the axis, y up, z across (towards -t: Godot's frame stays right-handed).
	var bx := _dir(1.0, 0.0)
	var bz := _dir(0.0, -1.0)
	var xf := Transform3D(Basis(bx, Vector3.UP, bz), _q(s, t, z))
	m.box(xf, size, col)
	if shape:
		host._shape_box(xf, size, info)


# ---------------------------------------------------------------- the bus station

func _markings() -> void:
	var m: RailBuilder.Mesher = host._mesher("BusStation_Paint", 400.0)
	for col: String in B["markings"]:
		var a: Array = B["markings"][col]
		var c: Color = PAINT.get(col, PAINT["white"])
		for k in range(0, a.size() - 8, 9):
			m.tri(Vector3(a[k], a[k + 2], -a[k + 1]), Vector3(a[k + 3], a[k + 5], -a[k + 4]),
					Vector3(a[k + 6], a[k + 8], -a[k + 7]), Vector3.UP, c)


## Letters painted on the ground, reading along `heading` (map degrees from east, anticlockwise).
func _labels() -> void:
	for lb: Dictionary in B["labels"]:
		var l := Label3D.new()
		l.text = lb["text"]
		l.font_size = 96
		l.pixel_size = float(lb["size"]) / 96.0
		l.outline_size = 0
		l.modulate = PAINT.get(lb["color"], PAINT["white"])
		l.shaded = true
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		var hd := deg_to_rad(float(lb["heading"]))
		var fwd := Vector3(cos(hd), 0.0, -sin(hd))
		var right := Vector3(sin(hd), 0.0, cos(hd))
		l.transform = Transform3D(Basis(right, fwd, Vector3.UP), Vector3(lb["x"], float(lb["z"]) + 0.004, -float(lb["y"])))
		l.visibility_range_end = 160.0
		l.name = "Paint_%s_%d" % [String(lb["text"]).replace(" ", "_"), host._node.get_child_count()]
		host._node.add_child(l)


## The kerb stones: a lighter strip on the top along the edge and the stone's face down to the lane (`left`: the
## raised side is on the line's left, else the quays' inside or the sidewalks' side).
func _copings() -> void:
	var m: RailBuilder.Mesher = host._mesher("BusStation_Kerbs", 500.0)
	for c: Dictionary in B["copings"]:
		var pts: Array = c["pts"]
		var closed: bool = c["closed"]
		var area := 0.0
		for i in pts.size() - 1:
			area += float(pts[i][0]) * float(pts[i + 1][1]) - float(pts[i + 1][0]) * float(pts[i][1])
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			if a.distance_to(b) < 0.01:
				continue
			var e := (b - a).normalized()
			var left := Vector2(-e.y, e.x)
			var inward := (left if area > 0.0 else -left) if closed else -_n
			if c.has("left"):
				inward = left if c["left"] else -left
			var za := float(pts[i][2])
			var zb := float(pts[i + 1][2])
			var ai := a + inward * KERB_W
			var bi := b + inward * KERB_W
			m.quad(Vector3(a.x, za + 0.006, -a.y), Vector3(b.x, zb + 0.006, -b.y), Vector3(bi.x, zb + 0.006, -bi.y),
					Vector3(ai.x, za + 0.006, -ai.y), Vector3.UP, KERB_TOP)
			var ao := a - inward * 0.012
			var bo := b - inward * 0.012
			var out3 := Vector3(-inward.x, 0.0, inward.y)
			m.quad(Vector3(ao.x, za - 0.22, -ao.y), Vector3(bo.x, zb - 0.22, -bo.y), Vector3(bo.x, zb + 0.006, -bo.y),
					Vector3(ao.x, za + 0.006, -ao.y), out3, KERB_FACE)


## Retaining walls: their face towards the lower ground from its level to a parapet over the higher one, their back
## from under the higher ground, a coping on top; a collision box per segment.
func _walls() -> void:
	var m: RailBuilder.Mesher = host._mesher("BusStation_Walls", 600.0)
	var info: Dictionary = host._info("retaining_wall", "massy:bus-walls", "", "Mur de soutènement")
	for w: Dictionary in B["walls"]:
		var pts: Array = w["pts"]
		var o := Vector2(w["out"][0], w["out"][1]).normalized()
		var foot: Array = w["foot"]
		var top: Array = w["top"]
		var gr: Array = w["ground"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			if a.distance_to(b) < 0.05:
				continue
			var e := (b - a).normalized()
			var nn := Vector2(-e.y, e.x)
			if nn.dot(o) < 0.0:
				nn = -nn
			var a2 := a + nn * 0.28
			var b2 := b + nn * 0.28
			var fa := float(foot[i]) - 0.05
			var fb := float(foot[i + 1]) - 0.05
			var ta := float(top[i])
			var tb := float(top[i + 1])
			var n3 := Vector3(nn.x, 0.0, -nn.y)
			m.quad(Vector3(a.x, fa, -a.y), Vector3(b.x, fb, -b.y), Vector3(b.x, tb, -b.y), Vector3(a.x, ta, -a.y), -n3,
					CONCRETE)
			m.quad(Vector3(a2.x, float(gr[i]) - 0.3, -a2.y), Vector3(b2.x, float(gr[i + 1]) - 0.3, -b2.y),
					Vector3(b2.x, tb, -b2.y), Vector3(a2.x, ta, -a2.y), n3, CONCRETE)
			var ac := a - nn * 0.04
			var bc := b - nn * 0.04
			var a3 := a2 + nn * 0.04
			var b3 := b2 + nn * 0.04
			m.quad(Vector3(ac.x, ta + 0.08, -ac.y), Vector3(bc.x, tb + 0.08, -bc.y), Vector3(b3.x, tb + 0.08, -b3.y),
					Vector3(a3.x, ta + 0.08, -a3.y), Vector3.UP, COPING)
			m.quad(Vector3(ac.x, ta, -ac.y), Vector3(bc.x, tb, -bc.y), Vector3(bc.x, tb + 0.08, -bc.y),
					Vector3(ac.x, ta + 0.08, -ac.y), -n3, COPING)
			m.quad(Vector3(a3.x, ta, -a3.y), Vector3(b3.x, tb, -b3.y), Vector3(b3.x, tb + 0.08, -b3.y),
					Vector3(a3.x, ta + 0.08, -a3.y), n3, COPING)
			var lo := minf(fa, fb)
			var hi := maxf(ta, tb) + 0.08
			var bm: Array = host._beam(a + nn * 0.14, lo, b + nn * 0.14, lo, 0.32, 0.0, hi - lo)
			host._shape_box(bm[0], bm[1], info)
		for k: int in [0, pts.size() - 1]:          # the ends
			var p := Vector2(pts[k][0], pts[k][1])
			var q := Vector2(pts[maxi(k - 1, 0) if k > 0 else 1][0], pts[maxi(k - 1, 0) if k > 0 else 1][1])
			var e := (p - q).normalized()
			var e3 := Vector3(e.x, 0.0, -e.y)
			var p2 := p + o * 0.28
			m.quad(Vector3(p.x, float(foot[k]) - 0.05, -p.y), Vector3(p2.x, float(gr[k]) - 0.3, -p2.y),
					Vector3(p2.x, float(top[k]), -p2.y), Vector3(p.x, float(top[k]), -p.y), e3, CONCRETE)


func _lamps() -> void:
	var m: RailBuilder.Mesher = host._mesher("BusStation_Furniture", 500.0)
	var glow: RailBuilder.Mesher = host._mesher("BusStation_Lights", 700.0)
	var info: Dictionary = host._info("lamp", "massy:bus-lamps", "", "Gare routière Atlantis")
	for p: Array in B["lamps"]:
		var base := Vector3(p[0], p[2], -float(p[1]))
		var xf := Transform3D(Basis(_dir(1.0, 0.0), Vector3.UP, _dir(1.0, 0.0).cross(Vector3.UP)), base)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0)), Vector3(0.14, LAMP_HEIGHT, 0.14), STEEL)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT + 0.05, 0.0)), Vector3(0.9, 0.14, 0.42), STEEL)
		glow.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT - 0.03, 0.0)), Vector3(0.78, 0.02, 0.32), GLOW)
		host._shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0)), Vector3(0.16, LAMP_HEIGHT, 0.16),
				info)
		host._lamp_lights.append(base + Vector3(0.0, LAMP_HEIGHT - 0.25, 0.0))


# ---------------------------------------------------------------- the bus depot (tools/rail/bus_depot.py)

## Map point of the depot's frame (u along the roof to the north-east, v across it towards the bus lane).
func _pu(u: float, v: float) -> Vector2:
	return _p(u + _s0, v + _t0)


func _qu(u: float, v: float, z: float) -> Vector3:
	var p := _pu(u, v)
	return Vector3(p.x, z, -p.y)


## The open depot after Gent's bus station: one thin flat roof (light grey, a smooth underside, its edge bevelled up
## to a slim fascia) on slender inclined columns in V pairs, no walls; round downlights under it; "Hangar de la gare
## routière" on both long fascias; the stairs from the car park; "Nous recrutons !" on a panel facing the avenue.
func _depot(Dd: Dictionary) -> void:
	_s0 = float(Dd["s0"])
	_t0 = float(Dd["t0"])
	var r: Array = Dd["roof"]
	var u0: float = r[0]
	var u1: float = r[1]
	var v0: float = r[2]
	var v1: float = r[3]
	var zf: float = Dd["floor"]
	var zu: float = zf + float(Dd["roof_under"])
	var zt: float = zu + float(Dd["roof_thick"])
	var ze: float = zt - float(Dd["roof_edge"])
	var bev: float = Dd["bevel"]
	var m: RailBuilder.Mesher = host._mesher("Depot", 900.0)
	var lights: RailBuilder.Mesher = host._mesher("Depot_Lights", 900.0)
	var info: Dictionary = host._info("bus_depot", "massy:bus-depot", "", String(Dd["signs"]["facade"]))
	# the roof: its top, the smooth underside (inset by the bevel), the bevel up to the fascia, the fascia
	m.quad(_qu(u0, v0, zt), _qu(u1, v0, zt), _qu(u1, v1, zt), _qu(u0, v1, zt), Vector3.UP, ROOF_TOP)
	m.quad(_qu(u0 + bev, v1 - bev, zu), _qu(u1 - bev, v1 - bev, zu), _qu(u1 - bev, v0 + bev, zu), _qu(u0 + bev, v0 + bev, zu),
			Vector3.DOWN, ROOF_UNDER)
	var outer := [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
	var inner := [[u0 + bev, v0 + bev], [u1 - bev, v0 + bev], [u1 - bev, v1 - bev], [u0 + bev, v1 - bev]]
	for k in 4:
		var a: Array = outer[k]
		var b: Array = outer[(k + 1) % 4]
		var ia: Array = inner[k]
		var ib: Array = inner[(k + 1) % 4]
		var out := (_qu((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, 0.0) - _qu((ia[0] + ib[0]) * 0.5, (ia[1] + ib[1]) * 0.5, 0.0)).normalized()
		m.quad(_qu(ia[0], ia[1], zu), _qu(ib[0], ib[1], zu), _qu(b[0], b[1], ze), _qu(a[0], a[1], ze),
				(out + Vector3.DOWN * 2.0).normalized(), ROOF_UNDER)
		m.quad(_qu(a[0], a[1], ze), _qu(b[0], b[1], ze), _qu(b[0], b[1], zt), _qu(a[0], a[1], zt), out, ROOF_EDGE_COL)
	var c := _qu((u0 + u1) * 0.5, (v0 + v1) * 0.5, (zu + zt) * 0.5)
	host._shape_box(Transform3D(Basis(_dir(1, 0), Vector3.UP, _dir(0, -1)), c), Vector3(u1 - u0, zt - zu, v1 - v0), info)
	# the columns: V pairs, leaning apart along the roof, from one footing to the underside
	for cu: float in Dd["columns_u"]:
		for cv: float in Dd["columns_v"]:
			var foot := _pu(cu, cv)
			_box_st(m, cu + _s0, cv + _t0, zf + 0.06, Vector3(0.9, 0.12, 0.6), CONCRETE)
			for side: float in [-1.0, 1.0]:
				var top_u := clampf(cu + side * 1.4, u0 + 0.3, u1 - 0.3)
				var bm: Array = host._beam(foot, zf, _pu(top_u, cv), zu + 0.05, 0.2, 0.1, 0.1)
				m.box(bm[0], bm[1], COLUMN)
				host._shape_box(bm[0], bm[1], info)
	# round downlights under the roof (glowing; lit at night: night.gd), over the passage lane and the lanes
	var vs: Array = [(float(Dd["passage"][0]) + float(Dd["passage"][1])) * 0.5]
	for ln: Array in Dd["lanes"]:
		vs.append((float(ln[0]) + float(ln[1])) * 0.5)
	var k := 0
	for v: float in vs:
		var u := u0 + 3.0
		while u < u1 - 2.0:
			_box_st(m, u + _s0, v + _t0, zu - 0.03, Vector3(0.9, 0.06, 0.9), STEEL)
			_box_st(lights, u + _s0, v + _t0, zu - 0.065, Vector3(0.7, 0.02, 0.7), GLOW)
			if k % 2 == 0:
				host._lamp_lights.append(_qu(u, v, zu - 0.3))
			k += 1
			u += 6.0
	# the name on both long fascias, a band under them
	var sgn: Dictionary = Dd["signs"]
	for side: Array in [[v1, 1.0], [v0, -1.0]]:
		var vv: float = side[0]
		var out := _dir(0.0, side[1])
		var um := (u0 + u1) * 0.5
		_box_st(m, um + _s0, vv + side[1] * 0.06 + _t0, ze - 0.38, Vector3(22.0, 0.7, 0.08), SIGN_BLUE)
		_board_text(_qu(um, vv + side[1] * 0.11, ze - 0.38), out, String(sgn["facade"]), Vector2(21.0, 0.55), Color.WHITE, 96)
	_stairs(m, Dd["stairs"], info)
	_panel(m, Dd["panel"], sgn)


## Steps from the car park down to the walkway along u, a handrail on each side; collision per step.
func _stairs(m: RailBuilder.Mesher, S: Dictionary, info: Dictionary) -> void:
	var ua: float = S["u"][0]
	var ub: float = S["u"][1]
	var va: float = S["v"][0]
	var vb: float = S["v"][1]
	var top: float = S["top"]
	var bot: float = S["bottom"]
	var n := maxi(1, roundi((top - bot) / 0.17))
	var rise := (top - bot) / n
	var run := (ub - ua) / n
	for i in n:
		var z := top - rise * (i + 1)
		var ca := ua + run * (i + 0.5)
		_box_st(m, ca + _s0, (va + vb) * 0.5 + _t0, (bot + z + rise) * 0.5, Vector3(run, z + rise - bot, vb - va), STONE, true,
				info)
	for vv: float in [va + 0.06, vb - 0.06]:
		host._railing(m, _pu(ua - 0.3, vv), top, _pu(ub, vv), bot, 1.0, STEEL, info)


## "Nous recrutons !" on a red board on two posts, facing the avenue (-v).
func _panel(m: RailBuilder.Mesher, Pn: Dictionary, sgn: Dictionary) -> void:
	var u: float = Pn["u"]
	var v: float = Pn["v"]
	var z: float = Pn["z"]
	var info: Dictionary = host._info("sign", "massy:bus-depot-panel", "", String(sgn["banner"]))
	for du: float in [-1.8, 1.8]:
		_box_st(m, u + du + _s0, v + _t0, z + 1.6, Vector3(0.12, 3.2, 0.12), STEEL, true, info)
	_box_st(m, u + _s0, v + _t0, z + 2.3, Vector3(4.6, 2.0, 0.1), BANNER_RED, true, info)
	_board_text(_qu(u, v - 0.06, z + 2.6), _dir(0, -1), String(sgn["banner"]), Vector2(4.2, 0.8), Color.WHITE, 96)
	_board_text(_qu(u, v - 0.06, z + 1.75), _dir(0, -1), String(sgn["line"]), Vector2(4.2, 0.35), Color("#ffe9a8"), 48)


## The welded-mesh fences (green, 2 m): posts, a top rail, the mesh's wires; collision per segment.
func _fences(runs: Array) -> void:
	var m: RailBuilder.Mesher = host._mesher("Depot_Fence", 300.0)
	var info: Dictionary = host._info("fence", "massy:bus-depot-fence", "", "Grillage")
	for f: Dictionary in runs:
		var pts: Array = f["pts"]
		var zs: Array = f["z"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var L := a.distance_to(b)
			if L < 0.05:
				continue
			var za: float = zs[i]
			var zb: float = zs[i + 1]
			var e := (b - a) / L
			var n3 := Vector3(-e.y, 0.0, -e.x)
			m.box(Transform3D(Basis.IDENTITY, Vector3(a.x, za + FENCE_H * 0.5, -a.y)), Vector3(0.06, FENCE_H, 0.06), FENCE_GREEN)
			var top: Array = host._beam(a, za + FENCE_H, b, zb + FENCE_H, 0.05, 0.03, 0.02)
			m.box(top[0], top[1], FENCE_GREEN)
			var nw := maxi(1, roundi(L / 0.2))
			for w in nw + 1:
				var t := float(w) / nw
				var p := a.lerp(b, t)
				var z := lerpf(za, zb, t)
				var q := p + e * 0.012
				m.quad(Vector3(p.x, z + 0.05, -p.y), Vector3(q.x, z + 0.05, -q.y), Vector3(q.x, z + FENCE_H, -q.y),
						Vector3(p.x, z + FENCE_H, -p.y), n3, FENCE_GREEN)
				m.quad(Vector3(q.x, z + 0.05, -q.y), Vector3(p.x, z + 0.05, -p.y), Vector3(p.x, z + FENCE_H, -p.y),
						Vector3(q.x, z + FENCE_H, -q.y), -n3, FENCE_GREEN)
			var hz := 0.2
			while hz < FENCE_H:
				var wire: Array = host._beam(a, za + hz, b, zb + hz, 0.01, 0.006, 0.006)
				m.box(wire[0], wire[1], FENCE_GREEN)
				hz += 0.5
			var bm: Array = host._beam(a, za, b, zb, 0.08, 0.0, FENCE_H)
			host._shape_box(bm[0], bm[1], info)
		var last := Vector2(pts[-1][0], pts[-1][1])
		m.box(Transform3D(Basis.IDENTITY, Vector3(last.x, float(zs[-1]) + FENCE_H * 0.5, -last.y)), Vector3(0.06, FENCE_H, 0.06),
				FENCE_GREEN)


func _board_text(pos: Vector3, out: Vector3, text: String, box: Vector2, col: Color, size: int) -> void:
	var holder := Node3D.new()
	holder.name = "Depot_Sign_%d" % host._node.get_child_count()
	holder.transform = Transform3D(host._facing(out), pos)
	holder.set_meta("plateau", host._info("sign", "massy:bus-depot-sign", "", text))
	host._node.add_child(holder)
	var l: Label3D = host._label(holder, text, Vector3.ZERO, size, col, box.x)
	l.visibility_range_end = 500.0
	LabelFit.fit(l, box)
