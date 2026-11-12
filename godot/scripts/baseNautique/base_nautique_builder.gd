extends "res://scripts/build_kit.gd"
## The boat hire on the Lac de l'X drawn (base_nautique.gd): in the map's frame (x east, y north; heights the game's),
## a wooden terrace over the gravel (level, a hand's breadth over its highest point; a wooden fence round it, open on
## the esplanade and where the pontoon leaves; two palm trees at its south corners, tables under parasols), the kiosk
## on it (painted boards, a white roof over its counter, a self-service till on the counter with its price card: PTA
## Online's terminal, its sign, the price board), the floating
## pontoon on the water's level (a gangway from the shore, the pier, its T head, floats, cleats, piles between the
## slips, a lifebuoy, two flags) and two of the base's jet-skis moored for show. Meta: "terminal" (by the counter, global),
## "slips" (global transforms on the water, facing out into the lake).

const GroundMap = preload("res://scripts/ground_map.gd")
const Water = preload("res://scripts/water.gd")
const NAVY := "#1f3b63"
const CYAN := "#2bb3c0"
const WHITE := "#f4f4f0"
const BOARDS := "bn_boards"
const DECK := "bn_deck"
const FLOAT := "#3a3d42"
const KIOSK := Rect2(742.0, 194.5, 7.0, 4.5)
const HATCH := Vector2(743.5, 747.5)        # the serving hatch in its south wall (x)
const TILL := Vector2(746.7, 194.27)        # the self-service till on the counter (map x, y)
const PIER := Rect2(756.0, 202.5, 2.4, 18.5)
const HEAD := Rect2(749.5, 221.0, 16.0, 3.0)
const SHORE := 199.6                        # y where the gangway leaves the gravel
const SLIPS := [Vector2(761.3, 206.0), Vector2(761.3, 210.5), Vector2(761.3, 215.0)]
const SHOW := [Vector2(753.0, 207.0), Vector2(753.0, 211.5)]    # the base's own jet-skis, moored for show
const DECK_UP := 0.4                        # m: the pontoon's deck over the water
const TERRACE := Rect2(741.0, 189.0, 19.0, 10.6)
const GATE := Vector2(748.5, 751.5)         # its way in from the esplanade (x, its south side)
const TERRACE_UP := 0.12                    # m: its deck over the gravel's highest point under it
const FENCE := 1.0                          # m: the fence's height
const PALMS := [Vector2(741.9, 189.9), Vector2(759.1, 189.9)]
const TABLES := [Vector2(743.9, 191.2), Vector2(754.2, 191.4), Vector2(757.6, 194.9), Vector2(753.3, 196.7)]

var g := 0.0                                # the terrace's deck
var level := 0.0                            # the water's


func _init() -> void:
	super("BaseNautique", {"type": "lot", "lot": "baseNautique", "name": "Base nautique du lac",
			"about": "jet-skis to buy or hire (PTA Online: the counter)"})
	add_material(BOARDS, material_from({"colour": "#efe9dc", "texture": "boards", "scale": 0.5, "rough": 0.8}))
	add_material(DECK, material_from({"colour": "#9a7752", "texture": "boards", "scale": 0.6, "rough": 0.85}))


func build(meshes: bool) -> Node3D:
	var gm: RefCounted = GroundMap.get_map()
	var low := INF
	g = -INF
	for x in range(int(TERRACE.position.x), int(TERRACE.end.x) + 1):
		for y in range(int(TERRACE.position.y), int(TERRACE.end.y) + 1):
			var h: float = gm.height(x, y) if gm else 0.0
			g = maxf(g, h)
			low = minf(low, h)
	g += TERRACE_UP
	level = Water.surface_at(Vector3(757.0, 0.0, -212.0))
	if is_nan(level):
		level = g - 0.4
	_terrace(low)
	_kiosk()
	_pontoon()
	for p: Vector2 in SHOW:
		_jet_ski(p)
	var slips := []
	for p: Vector2 in SLIPS:                  # (facing north: +z of a vehicle forward, scripts/water.gd spot_near)
		slips.append(Transform3D(Basis.looking_at(Vector3(0.0, 0.0, 1.0)), Vector3(p.x, level, -p.y)))
	var n := commit(meshes)
	n.set_meta("terminal", Vector3(TILL.x, g + 1.1, -(KIOSK.position.y - 0.5)))   # (the till, just clear of the roof)
	n.set_meta("slips", slips)
	return n


## A box over map rectangle r from height h0 to h1.
func _box(m: String, r: Rect2, h0: float, h1: float) -> void:
	box(m, r.position.x, r.end.x, h0, h1, -r.end.y, -r.position.y)


func _col(r: Rect2, h0: float, h1: float) -> void:
	col(r.position.x, r.end.x, h0, h1, -r.end.y, -r.position.y)


## Text at map point (x, y), h high, facing `yaw` (0 south, PI/2 east), `size` m capitals.
func _text(t: String, x: float, y: float, h: float, yaw: float, size: float, colour: String) -> void:
	label(t, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, h, -y)), 96, size / 70.0, Color(colour))


## The terrace: its deck down to the gravel (`low`: its lowest point under it), the fence round it with its two ways in
## (the gate on the esplanade, a ramp up to it; the pontoon's gangway), two palm trees, the tables under parasols.
func _terrace(low: float) -> void:
	var t := TERRACE
	_box(DECK, t, low - 0.2, g)
	_col(t, low - 0.2, g)
	var mid := Vector3(GATE.x + GATE.y, 0.0, 0.0) * 0.5
	var foot: float = GroundMap.get_map().height(mid.x, t.position.y - 1.2) if GroundMap.get_map() else g - 0.12
	var a := Vector3(mid.x, foot, -(t.position.y - 1.2))
	var b := Vector3(mid.x, g, -t.position.y)
	var w := (GATE.y - GATE.x) * 0.5
	quad(DECK, Vector3(a.x - w, a.y, a.z), Vector3(a.x + w, a.y, a.z), Vector3(b.x + w, b.y, b.z), Vector3(b.x - w, b.y, b.z),
			Vector3.UP)
	col_ramp(a, b, GATE.y - GATE.x)
	var s := t.position.y
	var n := t.end.y
	for run: Array in [[Vector2(t.position.x, s), Vector2(GATE.x, s)], [Vector2(GATE.y, s), Vector2(t.end.x, s)],
			[Vector2(t.end.x, s), Vector2(t.end.x, n)], [Vector2(t.end.x, n), Vector2(PIER.end.x, n)],
			[Vector2(PIER.position.x, n), Vector2(t.position.x, n)], [Vector2(t.position.x, n), Vector2(t.position.x, s)]]:
		_fence(run[0], run[1])
	for p: Vector2 in PALMS:
		_palm(p)
	for i in TABLES.size():
		_table(TABLES[i], CYAN if i % 2 == 0 else WHITE)


## A wooden fence from a to b (map) on the terrace: posts every 2 m or so, two rails; its collision.
func _fence(a: Vector2, b: Vector2) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_box(DECK, Rect2(p.x - 0.05, p.y - 0.05, 0.1, 0.1), g, g + FENCE)
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x) * 0.03
	for h: float in [0.45, FENCE - 0.08]:
		var r := Rect2(a - side, Vector2.ZERO).expand(b + side).expand(a + side).expand(b - side)
		_box(DECK, r, g + h, g + h + 0.08)
	var c := Rect2(a, Vector2.ZERO).expand(b).grow(0.06)
	_col(c, g, g + FENCE)


## A palm tree at map point p: its trunk curving up (rings of bark), its fronds drooping, coconuts.
func _palm(p: Vector2) -> void:
	var lean := (p - TERRACE.get_center()).normalized() * 0.6        # (leaning out of the terrace)
	var pts := []
	for i in 9:
		var t := float(i) / 8.0
		var off := lean * (t * t) * 1.6
		pts.append(Vector3(p.x + off.x, g + t * 6.5, -(p.y + off.y)))
	for i in 8:
		rod("#8b6a45", pts[i], pts[i + 1], lerpf(0.2, 0.13, float(i) / 8.0), 8)
		ball("#6f5236", pts[i], Vector3(0.24, 0.08, 0.24) * lerpf(1.0, 0.65, float(i) / 8.0), 8)
	col(p.x - 0.22, p.x + 0.22, g, g + 3.0, -p.y - 0.22, -p.y + 0.22)
	var top: Vector3 = pts[8]
	for k in 9:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 9.0 + 0.3)
		var tip := top + dir * 2.6 + Vector3.DOWN * 1.3
		var midp := top + dir * 1.4 + Vector3.UP * 0.25
		var side := dir.cross(Vector3.UP).normalized() * 0.45
		for seg: Array in [[top, midp, 0.15, 1.0], [midp, tip, 1.0, 0.1]]:
			var q0: Vector3 = seg[0]
			var q1: Vector3 = seg[1]
			var s0: Vector3 = side * float(seg[2])
			var s1: Vector3 = side * float(seg[3])
			var up := (q1 - q0).cross(side).normalized()
			if up.y < 0.0:
				up = -up
			quad("#4f9a3a", q0 - s0, q0 + s0, q1 + s1, q1 - s1, up)
			quad("#3f8030", q0 + s0, q0 - s0, q1 - s1, q1 + s1, -up)
	for k in 3:
		ball("#6b4a2b", top + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 3.0) * 0.22 + Vector3.DOWN * 0.25,
				Vector3(0.13, 0.15, 0.13), 8)


## A round table at map point p under a parasol (`colour` its canopy), four chairs round it; their collision.
func _table(p: Vector2, colour: String) -> void:
	var c := Vector3(p.x, g, -p.y)
	cyl("#2a2c2f", c, 0.05, 0.72, 10)
	cyl(WHITE, c + Vector3(0.0, 0.72, 0.0), 0.5, 0.04, 20)
	col(p.x - 0.5, p.x + 0.5, g, g + 0.76, -p.y - 0.5, -p.y + 0.5)
	for k in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 4.0 + PI * 0.25)
		var at := c + dir * 0.85
		var xf := Transform3D(Basis.looking_at(-dir), at)
		box_xf(WHITE, xf, Vector3(0.42, 0.05, 0.42), Vector3(0.0, 0.45, 0.0))
		box_xf(WHITE, xf, Vector3(0.42, 0.42, 0.04), Vector3(0.0, 0.68, 0.2))
		for lx: float in [-0.18, 0.18]:
			for lz: float in [-0.18, 0.18]:
				box_xf("#2a2c2f", xf, Vector3(0.03, 0.45, 0.03), Vector3(lx, 0.22, lz))
		col_xf(xf.translated_local(Vector3(0.0, 0.45, 0.0)), Vector3(0.42, 0.9, 0.42))
	cyl("#d8d4cc", c + Vector3(0.0, 0.76, 0.0), 0.025, 1.7, 8)
	cyl(colour, c + Vector3(0.0, 2.2, 0.0), 1.35, 0.4, 16, 0.03)
	cyl(NAVY, c + Vector3(0.0, 2.17, 0.0), 1.36, 0.04, 16)


func _kiosk() -> void:
	var k := KIOSK
	var f := g
	var top := f + 2.7
	# walls (the south one round its hatch), a cyan wave band under the roof
	var t := 0.12
	_box(BOARDS, Rect2(k.position.x, k.end.y - t, k.size.x, t), f, top)
	_box(BOARDS, Rect2(k.position.x, k.position.y, t, k.size.y), f, top)
	_box(BOARDS, Rect2(k.end.x - t, k.position.y, t, k.size.y), f, top)
	_box(BOARDS, Rect2(k.position.x, k.position.y, HATCH.x - k.position.x, t), f, top)
	_box(BOARDS, Rect2(HATCH.y, k.position.y, k.end.x - HATCH.y, t), f, top)
	_box(BOARDS, Rect2(HATCH.x, k.position.y, HATCH.y - HATCH.x, t), f, f + 1.0)
	_box(BOARDS, Rect2(HATCH.x, k.position.y, HATCH.y - HATCH.x, t), f + 2.1, top)
	_box(CYAN, k.grow(0.02), top - 0.35, top - 0.2)
	_col(k, f, top)
	# the counter under the hatch, the door on the west
	var counter := Rect2(HATCH.x - 0.2, k.position.y - 0.45, HATCH.y - HATCH.x + 0.4, 0.45)
	_box(WHITE, counter, f, f + 1.05)
	_box(NAVY, Rect2(counter.position.x, counter.position.y - 0.01, counter.size.x, 0.02), f + 0.15, f + 0.95)
	_col(counter, f, f + 1.05)
	_till(f + 1.05)
	_box("#3b4652", Rect2(k.position.x - 0.02, k.position.y + 2.6, 0.02, 1.0), f, f + 2.1)
	# the roof over the counter, the sign on it
	var roof := Rect2(k.position.x - 0.5, k.position.y - 0.4, k.size.x + 1.0, k.size.y + 0.8)   # (the terminal in the open)
	_box(WHITE, roof, top, top + 0.2)
	_box(NAVY, roof.grow(0.03), top + 0.02, top + 0.18)
	_col(roof, top, top + 0.2)
	var sign := Rect2(k.position.x + 0.5, roof.position.y + 0.05, k.size.x - 1.0, 0.1)
	_box(NAVY, sign, top + 0.2, top + 1.0)
	_text("BASE NAUTIQUE", k.get_center().x, sign.position.y - 0.01, top + 0.72, 0.0, 0.34, WHITE)
	_text("JET-SKI · LOCATION · VENTE", k.get_center().x, sign.position.y - 0.01, top + 0.36, 0.0, 0.17, CYAN)
	# the price board on its east wall
	var board := Rect2(k.end.x, k.position.y + 0.8, 0.08, 3.0)
	_box(NAVY, board, f + 0.9, f + 2.3)
	_text("LOCATION JET-SKI", board.end.x + 0.01, board.get_center().y, f + 2.0, PI * 0.5, 0.2, WHITE)
	_text("10 min · 500 €", board.end.x + 0.01, board.get_center().y, f + 1.62, PI * 0.5, 0.26, CYAN)
	_text("VENTE · 30 000 €", board.end.x + 0.01, board.get_center().y, f + 1.22, PI * 0.5, 0.2, WHITE)


## The self-service till on the counter (`h` its top): a body, a screen tilted to the customer glowing cyan, a card
## reader; beside it a small card standing on the counter with the prices.
func _till(h: float) -> void:
	var t := Vector3(TILL.x, h, -TILL.y)
	box("#2a2c2f", t.x - 0.2, t.x + 0.2, h, h + 0.12, t.z - 0.14, t.z + 0.14)
	var screen := Transform3D(Basis(Vector3.RIGHT, -0.5), t + Vector3(0.0, 0.32, 0.02))
	box_xf("#2a2c2f", screen, Vector3(0.38, 0.28, 0.04))
	box_xf("emit", screen, Vector3(0.32, 0.22, 0.01), Vector3(0.0, 0.0, 0.021))
	box_xf("#2a2c2f", Transform3D(Basis.IDENTITY, t + Vector3(0.0, 0.16, -0.02)), Vector3(0.06, 0.1, 0.06))
	box("#3b4652", t.x + 0.24, t.x + 0.36, h, h + 0.05, t.z - 0.03, t.z + 0.11)
	_text("PAYER ICI", t.x, TILL.y - 0.15, h + 0.06, 0.0, 0.045, CYAN)
	# the price card: two small boards leaning together on the counter
	var p := Vector3(TILL.x - 0.75, h, -TILL.y)
	var card := Transform3D(Basis(Vector3.RIGHT, -0.25), p + Vector3(0.0, 0.14, 0.02))
	box_xf(NAVY, card, Vector3(0.42, 0.3, 0.015))
	box_xf(NAVY, Transform3D(Basis(Vector3.RIGHT, 0.25), p + Vector3(0.0, 0.14, -0.04)), Vector3(0.42, 0.3, 0.015))
	var face := Transform3D(Basis(Vector3.RIGHT, -0.25), p + Vector3(0.0, 0.14, 0.03))
	label("Location 10 min", face.translated_local(Vector3(0.0, 0.08, 0.0)), 96, 0.0007, Color(WHITE))
	label("500 €", face.translated_local(Vector3(0.0, 0.0, 0.0)), 96, 0.0011, Color(CYAN))
	label("Vente 30 000 €", face.translated_local(Vector3(0.0, -0.09, 0.0)), 96, 0.0007, Color(WHITE))


func _pontoon() -> void:
	var d := level + DECK_UP
	# the gangway from the gravel down (or up) to the deck
	var a := Vector3(PIER.get_center().x, g, -SHORE)
	var b := Vector3(PIER.get_center().x, d, -PIER.position.y)
	var w := PIER.size.x * 0.5
	quad(DECK, Vector3(a.x - w, a.y, a.z), Vector3(a.x + w, a.y, a.z), Vector3(b.x + w, b.y, b.z), Vector3(b.x - w, b.y, b.z),
			Vector3.UP)
	col_ramp(a, b, PIER.size.x)
	for side: float in [-w, w]:
		quad(DECK, Vector3(a.x + side, a.y - 0.25, a.z), Vector3(a.x + side, a.y, a.z), Vector3(b.x + side, b.y, b.z),
				Vector3(b.x + side, b.y - 0.25, b.z), Vector3(signf(side), 0.0, 0.0))
	# the pier and its head: deck, floats under it, cleats along the edges
	for r: Rect2 in [PIER, HEAD]:
		_box(DECK, r, d - 0.12, d)
		_col(r, d - 0.6, d)
		var long := r.size.y > r.size.x
		var length := r.size.y if long else r.size.x
		var n := maxi(1, floori(length / 4.5))
		for i in n:
			var s := (i + 0.5) * length / n
			var fl := Rect2(r.position.x + 0.1, r.position.y + s - 1.2, r.size.x - 0.2, 2.4) if long \
					else Rect2(r.position.x + s - 1.2, r.position.y + 0.1, 2.4, r.size.y - 0.2)
			_box(FLOAT, fl, level - 0.3, d - 0.12)
			for e: float in ([r.position.x + 0.1, r.end.x - 0.1] if long else [r.position.y + 0.1, r.end.y - 0.1]):
				var c := Vector2(e, r.position.y + s) if long else Vector2(r.position.x + s, e)
				_box("rubber", Rect2(c.x - 0.1, c.y - 0.15, 0.2, 0.3), d, d + 0.12)
	# piles between the slips, a lifebuoy at the head, two flags
	for i in SLIPS.size() + 1:
		var y := SLIPS[0].y - 2.25 + i * 4.5
		cyl("#6b4f35", Vector3(SLIPS[0].x + 2.3, level - 1.0, -y), 0.14, d + 1.0 - (level - 1.0), 10)
		col(SLIPS[0].x + 2.16, SLIPS[0].x + 2.44, level - 1.0, d + 1.0, -y - 0.14, -y + 0.14)
	var post := Vector3(PIER.end.x - 0.3, d, -(HEAD.position.y - 0.4))
	cyl(WHITE, post, 0.05, 1.3, 8)
	torus("#e8552b", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), post + Vector3(0.0, 1.0, -0.12)), 0.22, 0.34)
	for x: float in [HEAD.position.x + 0.3, HEAD.end.x - 0.3]:
		var p := Vector3(x, d, -(HEAD.end.y - 0.3))
		cyl("steel", p, 0.05, 4.5, 8)
		tri(CYAN, p + Vector3(0.0, 4.4, 0.0), p + Vector3(0.0, 3.6, 0.0), p + Vector3(1.4, 4.0, 0.0), Vector3(0, 0, 1))
		tri(CYAN, p + Vector3(0.0, 4.4, 0.0), p + Vector3(1.4, 4.0, 0.0), p + Vector3(0.0, 3.6, 0.0), Vector3(0, 0, -1))
	light(Vector3(PIER.get_center().x, d + 3.5, -(HEAD.position.y - 1.0)), Color(1.0, 0.9, 0.75), 1.2, 14.0)


## One of the base's jet-skis, moored at map point p facing north (a hull, its stripe, the seat, the handlebar).
func _jet_ski(p: Vector2) -> void:
	var hull := Rect2(p.x - 0.55, p.y - 1.4, 1.1, 2.6)
	_box(WHITE, hull, level - 0.15, level + 0.3)
	_box(WHITE, Rect2(p.x - 0.4, hull.end.y, 0.8, 0.4), level - 0.05, level + 0.25)
	_box(CYAN, hull.grow(0.01), level + 0.12, level + 0.2)
	_box(NAVY, Rect2(p.x - 0.25, p.y - 1.1, 0.5, 1.3), level + 0.3, level + 0.55)
	_box("#2a2c2f", Rect2(p.x - 0.3, p.y + 0.4, 0.6, 0.35), level + 0.3, level + 0.62)
	rod("#2a2c2f", Vector3(p.x - 0.35, level + 0.85, -(p.y + 0.55)), Vector3(p.x + 0.35, level + 0.85, -(p.y + 0.55)), 0.025)
