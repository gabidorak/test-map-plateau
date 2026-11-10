extends "res://scripts/build_kit.gd"
## Villa de charme's rooms (scripts/villaEnPierreCoteaux/villaEnPierreCoteaux.gd builds them while the camera is near the house; the walls, floors and
## stair are the house's, villaEnPierreCoteaux_house.gd), after Thomas's photos (ref/proprietes/Villa Luxe/):
## - the hall: a crystal chandelier over the stair's void, a marble inlay, consoles with mirrors, two palms;
## - the salon: a stone fireplace, a sofa and armchairs round a low table on a large rug, a grand piano, bookshelves;
## - the dining room: a long live-edge oak table on black X legs, twelve taupe chairs, an oak sideboard, abstract art,
##   globe pendants;
## - the kitchen: light oak units, a black glass display cabinet lit inside, a white marble waterfall island on a black
##   base, three black leather and brass stools, three glass pendants;
## - the indoor pool: cream columns, sconces, loungers, the painted sky over it;
## - upstairs, the master bedroom (a tall padded headboard lit from behind between oak slats, globe pendants, a bench,
##   a desk), its blue marble bathroom (a lit freestanding bath, a glass shower, a floating vanity, a lit mirror), its
##   dressing room; two guest rooms with their shower rooms; the gym (oak, a green wall, a curved treadmill, a rower,
##   wall bars, a bench, weights);
## - the utility room, the wine cellar, the garage (its terminal on the wall).
## Lights: warm lamps (no shadows), reflection probes giving each part its ambient light.

const House = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_house.gd")
const F1 := House.F1
const CEIL0 := House.CEIL0
const CEIL1 := House.CEIL1
const T := House.T

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	super("VillaEnPierreCoteauxInterior")


func build(meshes := true) -> Node3D:
	_rng.seed = 2026
	_hall()
	_salon()
	_dining()
	_kitchen()
	_pool_hall()
	_service()
	_master()
	_guests()
	_gym()
	if meshes:
		_lights()
	return commit(meshes, 110.0)


# ---------------------------------------------------------------- furniture pieces

func _sofa(c: Vector3, length: float, depth: float, yaw: float, m := "greige") -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, c)
	box_xf("wood_dark", xf, Vector3(length, 0.1, depth - 0.1), Vector3(0, 0.05, 0))
	box_xf(m, xf, Vector3(length, 0.3, depth), Vector3(0, 0.25, 0))
	box_xf(m, xf, Vector3(length - 0.4, 0.16, depth - 0.25), Vector3(0, 0.47, 0.06))
	box_xf(m, xf, Vector3(length, 0.5, 0.22), Vector3(0, 0.6, -depth * 0.5 + 0.11))
	for s: float in [-1.0, 1.0]:
		box_xf(m, xf, Vector3(0.2, 0.32, depth), Vector3(s * (length * 0.5 - 0.1), 0.56, 0))
	var n := maxi(1, int(length / 0.9))
	for i in n:
		var x := -length * 0.5 + 0.35 + (length - 0.7) * (i + 0.5) / n
		box_xf("linen", xf, Vector3(0.45, 0.4, 0.14), Vector3(x, 0.72, -depth * 0.5 + 0.3))
	col_xf(Transform3D(b, c + Vector3(0, 0.4, 0)), Vector3(length, 0.8, depth))


func _armchair(c: Vector3, yaw: float, m := "sand_fabric") -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, c)
	box_xf(m, xf, Vector3(0.85, 0.42, 0.85), Vector3(0, 0.21, 0))
	box_xf(m, xf, Vector3(0.85, 0.48, 0.2), Vector3(0, 0.6, -0.33))
	for s: float in [-1.0, 1.0]:
		box_xf(m, xf, Vector3(0.16, 0.26, 0.8), Vector3(s * 0.35, 0.55, 0))
	box_xf("linen", xf, Vector3(0.6, 0.12, 0.6), Vector3(0, 0.48, 0.05))
	col_xf(Transform3D(b, c + Vector3(0, 0.4, 0)), Vector3(0.85, 0.8, 0.85))


## A dining chair (taupe, rounded back, black legs) facing `yaw` (its front towards -z of its basis).
func _dining_chair(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, c)
	box_xf("taupe", xf, Vector3(0.48, 0.1, 0.48), Vector3(0, 0.47, 0))
	box_xf("taupe", xf, Vector3(0.5, 0.42, 0.08), Vector3(0, 0.73, 0.22))
	for dx: float in [-0.2, 0.2]:
		for dz: float in [-0.2, 0.2]:
			box_xf("black", xf, Vector3(0.03, 0.44, 0.03), Vector3(dx, 0.22, dz))


func _plant(c: Vector3, h: float, r: float, pot := "charcoal") -> void:
	cyl(pot, c, r * 0.6, 0.45, 12, r * 0.75)
	cyl("soil", c + Vector3(0, 0.435, 0), r * 0.72, 0.03, 12)
	rod("wood_dark", c + Vector3(0, 0.4, 0), c + Vector3(0, h * 0.6, 0), 0.025, 5)
	for i in 6:
		var a := TAU * i / 6.0 + _rng.randf() * 0.5
		var p := c + Vector3(cos(a) * r * 0.55, h * _rng.randf_range(0.55, 0.95), sin(a) * r * 0.55)
		ball("plant", p, Vector3(r * 0.55, r * 0.35, r * 0.55), 8)
	ball("plant_light", c + Vector3(0, h, 0), Vector3(r * 0.6, r * 0.4, r * 0.6), 8)
	col(c.x - r * 0.5, c.x + r * 0.5, c.y, c.y + 0.5, c.z - r * 0.5, c.z + r * 0.5)


func _palm(c: Vector3) -> void:
	cyl("white", c, 0.32, 0.6, 14, 0.38)
	rod("wood_dark", c + Vector3(0, 0.55, 0), c + Vector3(0.05, 2.0, 0.03), 0.06, 6)
	for i in 9:
		var a := TAU * i / 9.0
		var tip := c + Vector3(cos(a) * 1.0, 1.7 + _rng.randf_range(-0.2, 0.3), sin(a) * 1.0)
		var base := c + Vector3(0.05, 2.0, 0.03)
		var mid := base.lerp(tip, 0.5) + Vector3(0, 0.25, 0)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.18
		for seg: Array in [[base, mid], [mid, tip]]:
			var p: Vector3 = seg[0]
			var q: Vector3 = seg[1]
			quad("plant", p - side, q - side * 0.6, q + side * 0.6, p + side, Vector3.UP)
	col(c.x - 0.38, c.x + 0.38, c.y, c.y + 0.6, c.z - 0.38, c.z + 0.38)


## A framed abstract painting on a wall: centre c, facing n (unit, horizontal), w x h.
func _art(c: Vector3, n: Vector3, w: float, h: float, scheme: int) -> void:
	var side := Vector3.UP.cross(n).normalized()
	var b := Basis(side, Vector3.UP, n)
	var xf := Transform3D(b, c)
	box_xf("black", xf, Vector3(w + 0.08, h + 0.08, 0.04), Vector3(0, 0, 0.02))
	box_xf("linen", xf, Vector3(w, h, 0.02), Vector3(0, 0, 0.045))
	var mats: Array = [["art_a", "art_b", "art_c"], ["art_b", "art_c", "art_a"], ["taupe", "art_b", "art_a"]][scheme % 3]
	box_xf(mats[0], xf, Vector3(w * 0.45, h * 0.55, 0.01), Vector3(-w * 0.12, h * 0.1, 0.058))
	box_xf(mats[1], xf, Vector3(w * 0.3, h * 0.3, 0.012), Vector3(w * 0.18, -h * 0.18, 0.06))
	ball(mats[2], xf * Vector3(w * 0.1, h * 0.22, 0.06), Vector3(w * 0.12, w * 0.12, 0.01), 12)


func _lamp_table(c: Vector3) -> void:
	cyl("brass", c, 0.08, 0.04, 10)
	rod("brass", c, c + Vector3(0, 0.4, 0), 0.012, 6)
	cyl("linen", c + Vector3(0, 0.36, 0), 0.16, 0.22, 12, 0.12)


func _pendant(top: Vector3, drop: float, r: float, m := "bulb") -> void:
	rod("black", top, top - Vector3(0, drop, 0), 0.006, 4)
	ball(m, top - Vector3(0, drop + r, 0), Vector3(r, r, r), 12)


func _bed(c: Vector3, yaw: float, width: float) -> void:
	# its head towards -z of its basis
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, c)
	box_xf("velvet_cream", xf, Vector3(width, 0.32, 2.1), Vector3(0, 0.16, 0))
	box_xf("linen", xf, Vector3(width - 0.04, 0.26, 2.04), Vector3(0, 0.45, 0))
	box_xf("greige", xf, Vector3(width + 0.06, 0.06, 0.7), Vector3(0, 0.6, 0.62))
	for s: float in [-1.0, 1.0]:
		box_xf("white", xf, Vector3(width * 0.4, 0.18, 0.4), Vector3(s * width * 0.22, 0.66, -0.78))
		box_xf("linen", xf, Vector3(width * 0.38, 0.14, 0.3), Vector3(s * width * 0.21, 0.64, -0.5))
	col_xf(Transform3D(b, c + Vector3(0, 0.3, 0)), Vector3(width, 0.6, 2.1))


func _wall_panel(m: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	box(m, x0, x1, y0, y1, z0, z1)


# ---------------------------------------------------------------- the ground floor

func _hall() -> void:
	# the marble inlay before the stair, the chandelier over the void
	cyl("wood_dark", Vector3(20.0, 0.0, 2.4), 1.5, 0.004, 32)
	cyl("marble", Vector3(20.0, 0.0, 2.4), 1.3, 0.006, 32)
	cyl("brass", Vector3(20.0, 0.0, 2.4), 0.25, 0.008, 16)
	var cc := Vector3(20.0, 5.2, 5.6)
	rod("brass", Vector3(cc.x, CEIL1, cc.z), cc + Vector3(0, 0.9, 0), 0.02, 6)
	for tier: Array in [[0.0, 1.05], [0.45, 0.75], [0.85, 0.45]]:
		var y: float = tier[0]
		var r: float = tier[1]
		torus("brass", Transform3D(Basis.IDENTITY, cc + Vector3(0, y, 0)), r - 0.03, r)
		var n := int(r * 14)
		for i in n:
			var a := TAU * i / n
			var p := cc + Vector3(cos(a) * r, y, sin(a) * r)
			cyl("brass", p, 0.025, 0.08, 6)
			ball("bulb", p + Vector3(0, 0.13, 0), Vector3(0.035, 0.06, 0.035), 6)
			ball("glass", p - Vector3(0, 0.12, 0), Vector3(0.04, 0.07, 0.04), 6)
			ball("glass", p - Vector3(0, 0.28, 0), Vector3(0.03, 0.05, 0.03), 6)
	ball("glass", cc - Vector3(0, 0.45, 0), Vector3(0.12, 0.2, 0.12), 10)
	# consoles with mirrors on the side walls, before the doorways
	for x: float in [15.08, 24.92]:
		var s := 1.0 if x < 20.0 else -1.0
		box("walnut", x, x + s * 0.45, 0.82, 0.86, 0.9, 2.9)
		for z: float in [1.0, 2.8]:
			box("brass", minf(x + s * 0.05, x + s * 0.1), maxf(x + s * 0.05, x + s * 0.1), 0.0, 0.82, z - 0.025, z + 0.025)
		box("brass", minf(x, x + s * 0.03), maxf(x, x + s * 0.03), 1.25, 2.55, 1.2, 2.6)
		box("chrome", minf(x + s * 0.03, x + s * 0.035), maxf(x + s * 0.03, x + s * 0.035), 1.3, 2.5, 1.25, 2.55)
		cyl("white", Vector3(x + s * 0.22, 0.86, 1.9), 0.11, 0.35, 12, 0.07)
		for i in 5:
			ball("plant_light", Vector3(x + s * 0.22 + _rng.randf_range(-0.12, 0.12), 1.3 + _rng.randf() * 0.2, 1.9 + _rng.randf_range(-0.15, 0.15)),
					Vector3(0.12, 0.1, 0.12), 6)
		col(minf(x, x + s * 0.45), maxf(x, x + s * 0.45), 0.0, 0.86, 0.9, 2.9)
	_palm(Vector3(16.6, 0.0, 4.4))
	_palm(Vector3(23.4, 0.0, 4.4))
	# art on the back wall over the landing
	_art(Vector3(20.0, LANDING_ART_Y, 11.5), Vector3(0, 0, -1), 2.4, 1.6, 0)
	# the upper hall: a long bench and lamps on the gallery
	box("velvet_cream", 17.0, 23.0, F1 + 0.38, F1 + 0.48, 0.55, 1.05)
	for x: float in [17.2, 22.8]:
		box("brass", x - 0.03, x + 0.03, F1, F1 + 0.38, 0.6, 1.0)


const LANDING_ART_Y := 4.6


func _salon() -> void:
	# the fireplace on the west wall, a TV over it
	var fx := T
	box("travertine", fx, fx + 0.5, 0.0, 1.25, 4.9, 7.1)
	box("black", fx + 0.3, fx + 0.52, 0.12, 0.95, 5.35, 6.65)
	box("travertine", fx, fx + 0.62, 1.25, 1.36, 4.75, 7.25)
	box("travertine", fx, fx + 0.12, 1.36, CEIL0, 5.0, 7.0)
	box("screen", fx + 0.12, fx + 0.16, 1.75, 2.6, 5.25, 6.75)
	box("emit", fx + 0.36, fx + 0.48, 0.14, 0.24, 5.5, 6.5)
	col(fx, fx + 0.62, 0.0, 1.36, 4.75, 7.25)
	# the rug, the sofa facing the fire, armchairs either side, the low table
	box("rug_beige", 2.2, 10.2, 0.0, 0.015, 3.0, 9.0)
	_sofa(Vector3(8.6, 0.0, 6.0), 3.0, 1.0, -PI * 0.5)
	_armchair(Vector3(4.6, 0.0, 3.6), 0.0)
	_armchair(Vector3(4.6, 0.0, 8.4), PI)
	box("travertine", 5.0, 7.4, 0.0, 0.38, 5.2, 6.8)
	box("art_b", 5.6, 6.0, 0.38, 0.5, 5.8, 6.2)
	col(5.0, 7.4, 0.0, 0.38, 5.2, 6.8)
	for p: Vector3 in [Vector3(8.7, 0.0, 4.1), Vector3(8.7, 0.0, 7.9)]:
		cyl("brass", p, 0.22, 0.5, 14, 0.22)
		cyl("travertine", p + Vector3(0, 0.5, 0), 0.25, 0.03, 14)
		_lamp_table(p + Vector3(0, 0.53, 0))
	# the grand piano by the front windows
	var pc := Vector3(12.4, 0.0, 2.5)
	ball("black", pc + Vector3(0, 0.82, 0), Vector3(0.75, 0.12, 1.0), 14)
	box("black", pc.x - 0.75, pc.x + 0.75, 0.7, 0.86, pc.z + 0.6, pc.z + 1.1)
	box("white", pc.x - 0.7, pc.x + 0.7, 0.86, 0.88, pc.z + 0.95, pc.z + 1.1)
	for d: Vector3 in [Vector3(-0.55, 0, 0.9), Vector3(0.55, 0, 0.9), Vector3(0, 0, -0.75)]:
		box("black", pc.x + d.x - 0.05, pc.x + d.x + 0.05, 0.0, 0.72, pc.z + d.z - 0.05, pc.z + d.z + 0.05)
	box("black", pc.x - 0.35, pc.x + 0.35, 0.45, 0.5, pc.z + 1.45, pc.z + 1.8)
	col(pc.x - 0.8, pc.x + 0.8, 0.0, 1.0, pc.z - 1.0, pc.z + 1.1)
	# the bookshelves on the hall's wall, art, plants
	# open walnut shelves: a back, two sides, the boards, books on them
	box("walnut", 14.86, 14.92, 0.0, 2.8, 6.5, 10.3)
	box("walnut", 14.5, 14.86, 0.0, 2.8, 6.5, 6.56)
	box("walnut", 14.5, 14.86, 0.0, 2.8, 10.24, 10.3)
	for y: float in [0.0, 0.42, 0.92, 1.42, 1.92, 2.42, 2.76]:
		box("walnut", 14.5, 14.86, y, y + 0.03, 6.56, 10.24)
	for y: float in [0.45, 0.95, 1.45, 1.95, 2.45]:
		var z := 6.6
		while z < 10.15:
			var w := _rng.randf_range(0.03, 0.06)
			var h := _rng.randf_range(0.25, 0.38)
			box(["art_a", "art_b", "art_c", "taupe", "linen"][_rng.randi() % 5], 14.58, 14.85, y, y + h, z, z + w)
			z += w + 0.004
			if _rng.randf() < 0.05:
				z += 0.25
	col(14.5, 14.92, 0.0, 2.8, 6.5, 10.3)
	_art(Vector3(7.5, 1.9, 11.48), Vector3(0, 0, -1), 1.4, 1.0, 1)
	_plant(Vector3(1.3, 0.0, 1.3), 1.6, 0.5)
	_plant(Vector3(1.3, 0.0, 10.9), 1.4, 0.45)


func _dining() -> void:
	box("rug_beige", 26.2, 30.9, 0.0, 0.015, 2.8, 9.6)
	# the table: a thick live-edge oak top on two black X legs
	var x0 := 27.9
	var x1 := 29.1
	box("oak", x0, x1, 0.71, 0.77, 3.4, 8.6)
	box("walnut", x0 - 0.02, x0, 0.71, 0.77, 3.5, 8.5)
	box("walnut", x1, x1 + 0.02, 0.71, 0.77, 3.5, 8.5)
	for z: float in [4.3, 7.7]:
		for s: float in [-1.0, 1.0]:
			box_xf("black", Transform3D(Basis(Vector3.FORWARD, s * 0.55), Vector3(28.5, 0.36, z)), Vector3(0.08, 0.85, 0.08))
		box("black", 28.0, 29.0, 0.66, 0.71, z - 0.04, z + 0.04)
	col(x0, x1, 0.0, 0.77, 3.4, 8.6)
	for z: float in [4.0, 4.9, 5.8, 6.7, 7.6, 8.4]:
		_dining_chair(Vector3(27.35, 0.0, z), -PI * 0.5)
		_dining_chair(Vector3(29.65, 0.0, z), PI * 0.5)
	# candles and a centrepiece
	for z: float in [5.2, 6.0, 6.8]:
		cyl("linen", Vector3(28.5, 0.77, z), 0.05, 0.18, 8)
		ball("bulb", Vector3(28.5, 0.98, z), Vector3(0.015, 0.03, 0.015), 4)
	cyl("glass", Vector3(28.5, 0.77, 6.4), 0.1, 0.3, 10, 0.06)
	for i in 6:
		ball("plant", Vector3(28.5 + _rng.randf_range(-0.2, 0.2), 1.15 + _rng.randf() * 0.2, 6.4 + _rng.randf_range(-0.2, 0.2)),
				Vector3(0.1, 0.08, 0.1), 6)
	# the sideboard, lamps and vases on it, two pictures over it
	box("oak", 25.08, 25.58, 0.15, 0.85, 6.6, 9.9)
	box("black", 25.12, 25.54, 0.0, 0.15, 6.7, 9.8)
	for z: float in [7.5, 8.25, 9.0]:
		box("walnut", 25.58, 25.595, 0.2, 0.8, z - 0.36, z + 0.36)
	col(25.08, 25.58, 0.0, 0.85, 6.6, 9.9)
	_lamp_table(Vector3(25.33, 0.85, 7.0))
	cyl("taupe", Vector3(25.33, 0.85, 8.1), 0.1, 0.3, 10, 0.05)
	cyl("art_c", Vector3(25.33, 0.85, 8.6), 0.08, 0.22, 10, 0.04)
	_lamp_table(Vector3(25.33, 0.85, 9.5))
	_art(Vector3(25.08, 1.85, 7.6), Vector3(1, 0, 0), 0.9, 1.2, 0)
	_art(Vector3(25.08, 1.85, 8.9), Vector3(1, 0, 0), 0.9, 1.2, 2)
	for z: float in [4.6, 6.0, 7.4]:
		_pendant(Vector3(28.5, CEIL0, z), 1.3, 0.16)
	_plant(Vector3(31.4, 0.0, 10.9), 1.8, 0.5)
	_plant(Vector3(25.9, 0.0, 1.1), 1.5, 0.45)


func _kitchen() -> void:
	var e := 39.55
	# the units along the east wall: the sink under the window, the hob under the hood
	var z0 := 3.0
	var z1 := 8.4
	box("oak_light", e - 0.65, e, 0.1, 0.88, z0, z1)
	box("black", e - 0.6, e, 0.0, 0.1, z0, z1)
	box("marble", e - 0.68, e, 0.88, 0.92, z0 - 0.05, z1 + 0.05)
	var z := z0
	while z < z1 - 0.3:
		box("black", e - 0.665, e - 0.65, 0.75, 0.78, z + 0.15, z + 0.45)
		z += 0.6
	box("chrome", e - 0.5, e - 0.1, 0.86, 0.925, 3.6, 4.4)
	rod("chrome", Vector3(e - 0.08, 0.92, 4.0), Vector3(e - 0.08, 1.25, 4.0), 0.015)
	rod("chrome", Vector3(e - 0.08, 1.25, 4.0), Vector3(e - 0.3, 1.25, 4.0), 0.012)
	box("black", e - 0.6, e - 0.08, 0.92, 0.93, 5.6, 6.4)
	col(e - 0.68, e, 0.0, 0.92, z0, z1)
	box("charcoal", e - 0.55, e, 1.75, 2.6, 5.2, 6.8)
	box("marble", e - 0.02, e, 0.93, 1.6, 4.9, 7.1)
	# in place of the rest: plants, a brass bar cart and a picture, open shelves with vases
	_plant(Vector3(32.9, 0.0, 1.2), 1.9, 0.55)
	_plant(Vector3(38.9, 0.0, 1.2), 1.6, 0.5)
	_plant(Vector3(38.95, 0.0, 10.6), 1.4, 0.45)
	var cart := Vector3(39.0, 0.0, 9.3)
	for y: float in [0.25, 0.8]:
		box("glass", cart.x - 0.25, cart.x + 0.25, y, y + 0.02, cart.z - 0.4, cart.z + 0.4)
	for dx: float in [-0.24, 0.24]:
		for dz: float in [-0.39, 0.39]:
			rod("brass", cart + Vector3(dx, 0.0, dz), cart + Vector3(dx, 0.95, dz), 0.012, 5)
	for k in 5:
		var b := cart + Vector3(_rng.randf_range(-0.15, 0.15), 0.82, -0.3 + k * 0.15)
		cyl(["art_b", "glass_dark", "art_c", "glass", "art_b"][k], b, 0.04, 0.26, 8, 0.02)
	col(cart.x - 0.26, cart.x + 0.26, 0.0, 0.95, cart.z - 0.41, cart.z + 0.41)
	_art(Vector3(e - 0.02, 1.75, 9.3), Vector3(-1, 0, 0), 1.0, 0.8, 1)
	for y: float in [1.2, 1.7]:
		box("oak", e - 0.3, e, y, y + 0.04, 1.4, 2.8)
		for k in 3:
			cyl(["white", "taupe", "art_a"][k], Vector3(e - 0.15, y + 0.04, 1.6 + k * 0.45), 0.07, 0.18 + k * 0.05, 10, 0.05)
	# the tall units on the back wall: the fridge, oak, the black glass display cabinet lit inside
	var bz := 12.0 - T
	box("steel", 38.2, 39.5, 0.0, 2.3, bz - 0.68, bz)
	box("charcoal", 38.84, 38.86, 0.9, 1.8, bz - 0.71, bz - 0.69)
	box("oak_light", 36.7, 38.2, 0.0, 2.3, bz - 0.62, bz)
	box("black", 35.0, 36.7, 0.0, 0.5, bz - 0.5, bz)
	box("black", 35.0, 36.7, 2.34, 2.4, bz - 0.5, bz)
	box("black", 35.0, 36.7, 0.5, 2.34, bz - 0.04, bz)
	box("black", 35.0, 35.05, 0.5, 2.34, bz - 0.5, bz - 0.04)
	box("black", 36.65, 36.7, 0.5, 2.34, bz - 0.5, bz - 0.04)
	box("glass", 35.0, 36.7, 0.5, 2.34, bz - 0.53, bz - 0.52)
	for y: float in [0.9, 1.3, 1.7, 2.1]:
		box("glass", 35.06, 36.64, y, y + 0.015, bz - 0.48, bz - 0.05)
		box("led", 35.06, 36.64, y + 0.25, y + 0.26, bz - 0.46, bz - 0.43)
		for i in 4:
			cyl(["white", "art_a", "white", "taupe"][i], Vector3(35.3 + i * 0.36, y + 0.015, bz - 0.25), 0.07, 0.16, 8)
	col(35.0, 39.5, 0.0, 2.4, bz - 0.68, bz)
	# the island: a white marble waterfall on a black base, the stools on its west side
	box("black", 35.45, 36.35, 0.0, 0.88, 3.9, 7.9)
	box("marble", 35.2, 36.6, 0.88, 0.95, 3.8, 8.0)
	box("marble", 35.2, 36.6, 0.0, 0.88, 3.8, 3.86)
	box("marble", 35.2, 36.6, 0.0, 0.88, 7.94, 8.0)
	box("marble", 36.3, 36.6, 0.0, 0.88, 3.86, 7.94)
	col(35.2, 36.6, 0.0, 0.95, 3.8, 8.0)
	for zz: float in [4.6, 5.9, 7.2]:
		var p := Vector3(34.65, 0.0, zz)
		box("leather_black", p.x - 0.22, p.x + 0.22, 0.66, 0.74, zz - 0.22, zz + 0.22)
		box("leather_black", p.x - 0.26, p.x - 0.2, 0.74, 1.05, zz - 0.22, zz + 0.22)
		for dx: float in [-0.17, 0.17]:
			for dz: float in [-0.17, 0.17]:
				rod("brass", p + Vector3(dx, 0, dz), p + Vector3(dx * 0.8, 0.66, dz * 0.8), 0.014, 5)
		torus("brass", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.28, 0)), 0.17, 0.19)
	for zz: float in [4.8, 5.9, 7.0]:
		rod("black", Vector3(35.9, CEIL0, zz), Vector3(35.9, 2.05, zz), 0.005, 4)
		ball("glass", Vector3(35.9, 1.85, zz), Vector3(0.17, 0.22, 0.17), 12)
		ball("bulb", Vector3(35.9, 1.85, zz), Vector3(0.06, 0.08, 0.06), 8)
	# a vase of branches on the island, a cove of light round the ceiling
	cyl("charcoal", Vector3(35.9, 0.95, 6.5), 0.08, 0.35, 8, 0.06)
	for i in 5:
		rod("wood_dark", Vector3(35.9, 1.25, 6.5), Vector3(35.9 + _rng.randf_range(-0.3, 0.3), 1.85, 6.5 + _rng.randf_range(-0.3, 0.3)), 0.008, 4)
	for r: Array in [[32.2, 39.5, T + 0.05, T + 0.12], [32.2, 39.5, 11.4, 11.48]]:
		box("led", r[0], r[1], CEIL0 - 0.06, CEIL0 - 0.02, r[2], r[3])


func _pool_hall() -> void:
	# cream columns between the windows, pilasters with sconces on the walls
	for x: float in [1.2, 4.4, 7.6, 10.8]:
		for z: float in [13.0, 21.0]:
			var p := Vector3(x, 0.0, z)
			box("cream", x - 0.32, x + 0.32, 0.0, 0.25, z - 0.32, z + 0.32)
			cyl("cream", p + Vector3(0, 0.25, 0), 0.24, 6.3, 16, 0.22)
			box("cream", x - 0.34, x + 0.34, 6.55, CEIL1, z - 0.34, z + 0.34)
			col(x - 0.25, x + 0.25, 0.0, CEIL1, z - 0.25, z + 0.25)
	# a cornice round the sky ceiling
	for r: Array in [[T, 12.0 - T, 12.0 - T + 0.12, 12.0 - T + 0.4], [T, 12.0 - T, 22.0 - T - 0.28, 22.0 - T],
			[T, T + 0.28, 12.0, 22.0 - T], [12.0 - T - 0.28, 12.0 - T, 12.0, 22.0 - T]]:
		box("cream", r[0], r[1], CEIL1 - 0.35, CEIL1, r[2], r[3])
		box("led", r[0], r[1], CEIL1 - 0.37, CEIL1 - 0.35, r[2], r[3])
	for p: Vector3 in [Vector3(T + 0.02, 2.4, 15.6), Vector3(T + 0.02, 2.4, 18.6), Vector3(12.0 - T - 0.02, 2.4, 15.0),
			Vector3(12.0 - T - 0.02, 2.4, 19.0)]:
		var s := 1.0 if p.x < 6.0 else -1.0
		box("chrome", minf(p.x, p.x + s * 0.08), maxf(p.x, p.x + s * 0.08), 2.0, 2.8, p.z - 0.08, p.z + 0.08)
		box("emit", minf(p.x + s * 0.08, p.x + s * 0.14), maxf(p.x + s * 0.08, p.x + s * 0.14), 2.05, 2.75, p.z - 0.06, p.z + 0.06)
	# loungers along the north side, small tables and palms
	for x: float in [2.8, 6.0, 9.2]:
		var c := Vector3(x, 0.0, 14.1)
		box("oak", x - 0.36, x + 0.36, 0.22, 0.3, 13.25, 14.95)
		box("white", x - 0.34, x + 0.34, 0.3, 0.42, 13.25, 14.95)
		box_xf("white", Transform3D(Basis(Vector3.RIGHT, 0.75), c + Vector3(0, 0.6, -0.95)), Vector3(0.68, 0.1, 0.65))
		box("linen", x - 0.25, x + 0.25, 0.42, 0.48, 14.5, 14.85)
		col(x - 0.36, x + 0.36, 0.0, 0.45, 13.25, 14.95)
	for p: Vector3 in [Vector3(1.0, 0.0, 20.0), Vector3(11.0, 0.0, 20.0)]:
		_palm(p)
	for x: float in [4.4, 7.6]:
		cyl("white", Vector3(x - 0.9, 0.0, 20.2), 0.25, 0.5, 12)
		box("linen", x - 1.1, x - 0.7, 0.5, 0.56, 20.0, 20.4)
	# a handrail by the pool's steps
	for z: float in [15.95, 18.45]:
		rod("chrome", Vector3(10.35, 0.0, z), Vector3(10.35, 0.9, z), 0.02, 6)
		rod("chrome", Vector3(10.35, 0.9, z), Vector3(9.2, -0.1, z), 0.02, 6)


func _service() -> void:
	# the utility room: washer and dryer under a counter, shelves
	for z: float in [12.7, 13.4]:
		box("white", 28.5, 29.15, 0.0, 0.85, z - 0.32, z + 0.32)
		cyl("glass_dark", Vector3(29.16, 0.45, z), 0.2, 0.02, 16)
	box("marble", 28.45, 29.2, 0.85, 0.89, 12.1, 16.7)
	box("oak_light", 28.45, 29.1, 0.0, 0.85, 13.8, 16.7)
	box("oak_light", 28.45, 28.8, 1.6, 2.4, 12.2, 16.6)
	col(28.45, 29.2, 0.0, 0.9, 12.1, 16.7)
	# the cellar: wine racks along its walls, a barrel and two stools
	for r: Array in [[28.45, 28.85, 17.2, 21.5], [29.0, 33.8, 21.15, 21.55], [33.4, 33.8, 17.2, 21.1]]:
		box("walnut", r[0], r[1], 0.0, 2.2, r[2], r[3])
		var y := 0.15
		while y < 2.1:
			var along_x: bool = (r[1] - r[0]) > (r[3] - r[2])
			var k := 0.12
			var length: float = (r[1] - r[0]) if along_x else (r[3] - r[2])
			while k < length - 0.05:
				var p := Vector3(r[0] + k, y, (r[2] + r[3]) * 0.5) if along_x else Vector3((r[0] + r[1]) * 0.5, y, r[2] + k)
				ball(["art_b", "black", "art_c"][_rng.randi() % 3], p, Vector3(0.035, 0.035, 0.035), 6)
				k += 0.12
			y += 0.18
		col(r[0], r[1], 0.0, 2.2, r[2], r[3])
	cyl("oak", Vector3(31.2, 0.0, 19.2), 0.35, 0.95, 14, 0.3)
	box("oak", 30.8, 31.6, 0.95, 1.0, 18.8, 19.6)
	col(30.85, 31.55, 0.0, 1.0, 18.85, 19.55)
	# the garage: its terminal on the wall, tubes, a tool wall
	var tp := House.GARAGE_TERMINAL
	box("charcoal", tp.x, tp.x + 0.06, 1.1, 1.8, tp.z - 0.35, tp.z + 0.35)
	box("led", tp.x + 0.06, tp.x + 0.065, 1.2, 1.7, tp.z - 0.3, tp.z + 0.3)
	label("GARAGE", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(tp.x + 0.07, 1.9, tp.z)), 40, 0.004, Color(0.95, 0.85, 0.6), false)
	for z: float in [14.0, 17.0, 20.0]:
		box("emit", 36.3, 37.7, CEIL0 - 0.06, CEIL0 - 0.02, z - 0.06, z + 0.06)
	box("charcoal", 34.08, 34.12, 1.0, 2.2, 19.0, 21.3)
	for i in 8:
		var zz := 19.2 + i * 0.26
		box("steel", 34.12, 34.18, 1.4 + (i % 3) * 0.2, 1.7 + (i % 3) * 0.2, zz - 0.02, zz + 0.02)


# ---------------------------------------------------------------- the first floor

func _master() -> void:
	var f := F1
	# the headboard wall: oak slats, the padded headboard lit from behind, a marble panel over it
	box("slats", 8.88, 8.92, f, CEIL1, 0.6, 2.9)
	box("slats", 8.88, 8.92, f, CEIL1, 6.3, 8.85)
	box("marble", 8.89, 8.925, f + 1.9, CEIL1, 2.9, 6.3)
	for i in 4:
		var z0 := 3.05 + i * 0.78
		box("velvet_cream", 8.74, 8.9, f + 0.3, f + 2.2, z0, z0 + 0.74)
	box("led", 8.88, 8.9, f + 0.25, f + 2.27, 2.98, 3.02)
	box("led", 8.88, 8.9, f + 0.25, f + 2.27, 6.18, 6.22)
	box("led", 8.88, 8.9, f + 2.24, f + 2.27, 2.98, 6.22)
	_bed(Vector3(7.65, f, 4.6), -PI * 0.5, 2.0)
	for z: float in [3.0, 6.2]:
		box("white", 8.2, 8.72, f, f + 0.55, z - 0.3, z + 0.3)
		col(8.2, 8.72, f, f + 0.55, z - 0.3, z + 0.3)
		_pendant(Vector3(8.3, CEIL1, z), 1.6, 0.15)
		cyl("white", Vector3(8.45, f + 0.55, z + 0.1), 0.06, 0.18, 8)
	box("rug_beige", 3.2, 8.0, f, f + 0.015, 2.2, 7.0)
	# the bench at the foot, a desk and a pouf by the window, an armchair, the TV
	box("oak_light", 5.6, 6.0, f + 0.38, f + 0.44, 3.6, 5.6)
	for z: float in [3.7, 5.5]:
		box("brass", 5.62, 5.98, f, f + 0.38, z - 0.02, z + 0.02)
	col(5.6, 6.0, f, f + 0.44, 3.6, 5.6)
	box("oak_light", T, T + 0.55, f + 0.72, f + 0.76, 4.1, 5.9)
	box("white", T, T + 0.5, f, f + 0.72, 5.3, 5.85)
	cyl("velvet_cream", Vector3(T + 0.75, f, 4.8), 0.24, 0.45, 14)
	_lamp_table(Vector3(T + 0.25, f + 0.76, 4.3))
	col(T, T + 0.55, f, f + 0.76, 4.1, 5.9)
	_armchair(Vector3(1.3, f, 8.0), PI * 0.75, "velvet_cream")
	box("screen", 3.4, 5.4, f + 1.1, f + 2.2, T, T + 0.04)
	_plant(Vector3(1.0, f, 1.0), 1.3, 0.4, "white")
	# the bathroom: blue marble walls, the shower, the bath, the vanity and its lit mirror
	var bz := 5.5 - 0.075
	box("marble_blue", 9.075, 9.1, f, f + 2.9, T, bz)
	box("marble_blue", 9.075, 15.0 - 0.075, f, f + 2.9, bz - 0.025, bz)
	box("marble_blue", 14.9, 14.925, f, f + 2.9, T, bz)
	box("glass", 11.55, 11.57, f, f + 2.3, T, 2.55)
	box("glass", 9.1, 10.5, f, f + 2.3, 2.53, 2.55)
	box("chrome", 9.1, 11.57, f + 2.3, f + 2.33, 2.52, 2.56)
	box("marble_blue", 9.1, 11.55, f, f + 0.02, T, 2.53)
	cyl("chrome", Vector3(10.3, f + 2.4, 1.5), 0.15, 0.02, 12)
	rod("chrome", Vector3(10.3, f + 2.42, 1.5), Vector3(10.3, f + 2.42, T), 0.012, 6)
	ball("white_gloss", Vector3(13.7, f + 0.32, 1.35), Vector3(0.95, 0.36, 0.48), 16)
	ball("water_in", Vector3(13.7, f + 0.52, 1.35), Vector3(0.82, 0.02, 0.38), 12)
	cyl("led", Vector3(13.7, f + 0.005, 1.35), 0.7, 0.01, 20)
	col(12.75, 14.65, f, f + 0.6, 0.9, 1.8)
	box("white_gloss", 11.4, 14.7, f + 0.45, f + 0.9, bz - 0.55, bz - 0.025)
	for x: float in [12.3, 13.8]:
		box("white", x - 0.25, x + 0.25, f + 0.88, f + 0.91, bz - 0.45, bz - 0.12)
		rod("chrome", Vector3(x, f + 0.9, bz - 0.06), Vector3(x, f + 1.1, bz - 0.06), 0.012, 6)
	box("chrome", 11.6, 14.5, f + 1.15, f + 2.1, bz - 0.04, bz - 0.025)
	box("led", 11.55, 14.55, f + 1.1, f + 2.15, bz - 0.022, bz - 0.02)
	box("white_gloss", 9.15, 9.6, f, f + 0.42, 3.85, 4.45)
	box("white_gloss", 9.12, 9.2, f + 0.4, f + 0.8, 3.85, 4.45)
	# the dressing room: shelves and hanging clothes on both walls
	for z: Array in [[5.5 + 0.075, 6.1], [8.4, 9.0 - 0.075]]:
		box("oak_light", 9.2, 14.8, f, f + 2.5, z[0], z[1])
		var x := 9.3
		while x < 14.7:
			var w := _rng.randf_range(0.04, 0.09)
			box(["linen", "taupe", "art_b", "blue_grey", "white", "greige"][_rng.randi() % 6], x, x + w, f + 1.0, f + 2.1,
					(z[0] + z[1]) * 0.5 - 0.22, (z[0] + z[1]) * 0.5 + 0.22)
			x += w + 0.02
		col(9.2, 14.8, f, f + 2.5, z[0], z[1])
	box("walnut", 11.2, 12.8, f, f + 0.9, 7.0, 7.6)
	box("glass", 11.2, 12.8, f + 0.9, f + 0.92, 7.0, 7.6)
	col(11.2, 12.8, f, f + 0.92, 7.0, 7.6)
	# the corridor: a runner, a console, art over the pool's balcony
	box("rug_grey", 1.0, 14.0, f, f + 0.012, 9.6, 10.6)
	_art(Vector3(4.5, f + 1.6, 9.08), Vector3(0, 0, 1), 1.2, 0.9, 2)
	_art(Vector3(11.0, f + 1.6, 9.08), Vector3(0, 0, 1), 1.2, 0.9, 1)


func _guests() -> void:
	var f := F1
	for room: Array in [[25.0, 32.5, 29.5], [32.5, 40.0 - T, 37.0]]:
		var x0: float = room[0] + 0.075
		var x1: float = room[1] - 0.075
		var bath: float = room[2]
		# the bed against the west wall, a headboard, nightstands, a desk on the front wall
		box("velvet_cream", x0, x0 + 0.12, f + 0.3, f + 1.7, 2.3, 4.9)
		_bed(Vector3(x0 + 1.15, f, 3.6), PI * 0.5, 1.8)
		for z: float in [1.9, 5.3]:
			box("oak_light", x0, x0 + 0.5, f, f + 0.5, z - 0.25, z + 0.25)
			_lamp_table(Vector3(x0 + 0.25, f + 0.5, z))
		box("rug_beige", x0 + 0.6, x0 + 3.8, f, f + 0.012, 2.0, 5.3)
		box("oak_light", x1 - 1.8, x1 - 0.4, f + 0.72, f + 0.76, T, T + 0.55)
		cyl("velvet_cream", Vector3(x1 - 1.1, f, T + 0.9), 0.22, 0.45, 12)
		_art(Vector3(x0 + 0.02, f + 2.3, 3.6), Vector3(1, 0, 0), 1.6, 0.6, int(bath))
		_plant(Vector3(x1 - 0.5, f, 5.3), 1.2, 0.4, "white")
		# its shower room: a glass shower, a vanity, a WC
		var bx0 := bath + 0.075
		var bx1 := x1
		box("marble", bx0, bx1, f, f + 0.015, 6.075, 9.0 - 0.075)
		box("glass", bx0 + 0.3, bx0 + 1.5, f, f + 2.2, 6.95, 6.97)
		box("marble", bx0, bx0 + 1.5, f, f + 2.4, 6.08, 6.1)
		box("white_gloss", bx1 - 1.2, bx1, f + 0.5, f + 0.85, 8.45, 8.9)
		box("chrome", bx1 - 1.1, bx1 - 0.1, f + 1.1, f + 1.9, 8.9, 8.92)
		box("white_gloss", bx0 + 0.1, bx0 + 0.55, f, f + 0.42, 8.3, 8.9)


func _gym() -> void:
	var f := F1
	# oak panels and the green wall on the north wall, a mirror on the west
	box("oak_light", 28.45, 33.0, f, CEIL1, 12.075, 12.11)
	box("oak_light", 35.0, 39.55, f, CEIL1, 12.075, 12.11)
	box("plant", 35.4, 39.2, f + 0.3, f + 2.8, 12.11, 12.16)
	for i in 70:
		ball(["plant", "plant_light", "leaves"][_rng.randi() % 3], Vector3(_rng.randf_range(35.5, 39.1), f + _rng.randf_range(0.4, 2.7),
				12.18), Vector3(0.18, 0.14, 0.08), 6)
	box("chrome", 28.45, 28.5, f + 0.3, f + 2.4, 20.3, 21.4)
	# wall bars by the mirror
	for z: float in [12.6, 13.6]:
		box("black", 28.5, 28.58, f, f + 2.5, z - 0.03, z + 0.03)
	var y := f + 0.2
	while y < f + 2.45:
		rod("oak", Vector3(28.54, y, 12.6), Vector3(28.54, y, 13.6), 0.018, 6)
		y += 0.22
	# the curved treadmill facing the garden
	var tc := Vector3(31.0, f, 19.8)
	for i in 12:
		var a0 := PI * (0.15 + 0.7 * i / 12.0)
		var a1 := PI * (0.15 + 0.7 * (i + 1) / 12.0)
		var p0 := tc + Vector3(-cos(a0) * 1.0, 1.0 - sin(a0) * 0.9, 0)
		var p1 := tc + Vector3(-cos(a1) * 1.0, 1.0 - sin(a1) * 0.9, 0)
		box_xf("black", Transform3D(Basis.looking_at(p1 - p0, Vector3.FORWARD), (p0 + p1) * 0.5), Vector3(0.6, 0.05, p0.distance_to(p1)))
	for s: float in [-0.33, 0.33]:
		box("brass", tc.x - 1.0, tc.x + 1.0, f + 0.05, f + 0.45, tc.z + s - 0.03, tc.z + s + 0.03)
		rod("brass", tc + Vector3(0.8, 0.2, s), tc + Vector3(1.0, 1.3, s), 0.02, 6)
	box("black", tc.x + 0.9, tc.x + 1.1, f + 1.3, f + 1.36, tc.z - 0.3, tc.z + 0.3)
	col(tc.x - 1.0, tc.x + 1.0, f, f + 0.5, tc.z - 0.35, tc.z + 0.35)
	# the rower, the bench, the weights rack, a ball, mats
	box("oak", 33.0, 35.6, f + 0.1, f + 0.2, 16.6, 16.85)
	box("black", 33.0, 33.6, f, f + 0.55, 16.4, 17.05)
	cyl("black", Vector3(33.3, f + 0.15, 16.73), 0.3, 0.12, 14)
	box("leather_black", 34.6, 35.0, f + 0.2, f + 0.3, 16.55, 16.9)
	col(33.0, 35.6, f, f + 0.5, 16.4, 17.05)
	box_xf("leather_black", Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(36.6, f + 0.6, 15.6)), Vector3(1.2, 0.08, 0.32))
	box("black", 36.0, 37.4, f, f + 0.42, 15.5, 15.7)
	col(36.0, 37.4, f, f + 0.6, 15.4, 15.8)
	box("black", 38.6, 39.5, f, f + 0.9, 13.0, 15.0)
	for i in 6:
		var zz := 13.2 + i * 0.3
		for yy: float in [0.35, 0.75]:
			cyl("black", Vector3(38.75, f + yy, zz), 0.08, 0.14, 8)
			cyl("brass", Vector3(38.75, f + yy + 0.14, zz), 0.03, 0.06, 6)
	col(38.6, 39.5, f, f + 0.9, 13.0, 15.0)
	ball("leather_black", Vector3(38.9, f + 0.35, 20.6), Vector3(0.35, 0.35, 0.35), 12)
	box("charcoal", 32.8, 34.8, f, f + 0.01, 19.0, 19.7)
	_plant(Vector3(39.0, f, 21.0), 1.5, 0.45, "white")


# ---------------------------------------------------------------- lights

const LANDING := House.LANDING


func _lights() -> void:
	var warm := Color(1.0, 0.85, 0.66)
	light(Vector3(20.0, 4.8, 5.6), warm, 1.6, 12.0)                 # the chandelier
	light(Vector3(20.0, 1.6, 1.5), warm, 0.6, 6.0)
	light(Vector3(7.5, 2.9, 6.0), warm, 1.0, 9.0)                   # the salon
	light(Vector3(1.0, 0.6, 6.0), Color(1.0, 0.6, 0.3), 0.8, 4.0)   # the fire
	light(Vector3(28.5, 2.2, 6.0), warm, 1.0, 7.5)                  # the dining room
	light(Vector3(36.0, 2.6, 6.0), Color(1.0, 0.92, 0.82), 1.1, 7.5) # the kitchen
	light(Vector3(6.0, 4.5, 17.0), Color(0.92, 0.97, 1.0), 1.3, 11.0) # the pool hall
	light(Vector3(6.0, 2.5, 13.2), warm, 0.6, 6.0)
	light(Vector3(5.0, F1 + 2.4, 4.5), warm, 0.9, 7.5)               # the master bedroom
	light(Vector3(12.0, F1 + 2.4, 2.8), Color(0.85, 0.92, 1.0), 0.8, 5.5)   # its bathroom
	light(Vector3(28.7, F1 + 2.4, 4.0), warm, 0.8, 6.5)
	light(Vector3(36.2, F1 + 2.4, 4.0), warm, 0.8, 6.5)
	light(Vector3(34.0, F1 + 2.6, 17.0), Color(1.0, 0.95, 0.88), 1.0, 9.0)  # the gym
	light(Vector3(31.0, 1.8, 15.0), Color(1.0, 0.95, 0.9), 0.6, 6.0)
	light(Vector3(37.0, 2.6, 17.0), Color(0.95, 0.97, 1.0), 0.9, 7.0)       # the garage
	light(Vector3(7.0, F1 + 2.4, 10.5), warm, 0.5, 6.0)
	# each part's ambient light and reflections (inside, the sky's is wrong)
	for p: Array in [[Vector3(20.0, 3.6, 6.0), Vector3(39.2, 7.3, 11.2)], [Vector3(6.0, 3.6, 17.0), Vector3(11.2, 7.3, 9.9)],
			[Vector3(34.0, 3.6, 17.0), Vector3(11.2, 7.3, 9.9)]]:
		var probe := ReflectionProbe.new()
		probe.size = p[1]
		probe.position = p[0]
		probe.interior = true
		probe.box_projection = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.9, 0.86, 0.8)
		probe.ambient_color_energy = 0.5
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		root.add_child(probe)
