extends "res://scripts/ilot/urban_kit.gd"
## The 25/8 supermarket's lot drawn (superette.gd), on the block's plan (scripts/ilot/ilot_plan.gd): its asphalt and
## kerbs, its markings (the car park's bays, PMR in blue, the EV chargers' in green, the one-way arrows, the yard's
## yellow lines), the shop (glazed south front under a green fascia with its red fillet, the 25/8 cartouche; the
## loading dock and its roller doors at the back, the waste room), the filling station (canopy, islands, pumps) and
## its price totem. The identity: green, red, white. Map coordinates, heights over the block's level.

const GREEN := "#0f7a3d"
const RED := "#d7262e"
const WHITE := "#f4f4f0"
const CONCRETE := "#bdb8ae"
const ANTHRACITE := "#2e3236"
const YELLOW := "#f2c84b"
const BLUE := "#2f6cc2"
const EV := "#2f9a57"
const CLADDING := "s258_cladding"
const SOLAR := "s258_solar"
const ROOF := "#8a8e93"
const BAY_MIN := 2.3                    # m: a bay's width at least (5 m deep)
const PMR_BAY := 3.3
const WALL_H := 6.0                     # the shop's walls; its parapet to PARAPET
const PARAPET := 6.7
const CANOPY_H := 5.2                   # the station's canopy, its underside
const PRICES := [["GAZOLE", "1,79"], ["SP95", "1,89"], ["SP98", "1,99"]]


func _init() -> void:
	super("Superette258", {"type": "lot", "lot": "superette258", "name": "25/8 · supérette 25h/24, 8j/7",
			"about": "the shop, its delivery yard, the filling station, the car park"})
	add_material(CLADDING, material_from({"colour": "#ecebe6", "texture": "cladding", "scale": 0.25, "rough": 0.7}))
	add_material(SOLAR, material_from({"colour": "#ffffff", "texture": "solar", "scale": 0.5, "rough": 0.2,
			"metal": 0.4}))


## The car park's bays: [x0, x1, y0 (south end), kind ("", "pmr", "ev"), the way they read (from their aisle)].
static func bays() -> Array:
	var out := []
	var x0 := Plan.PARKING.position.x
	var x1 := Plan.PARKING.end.x
	for i in Plan.ROWS.size():
		var y: float = Plan.ROWS[i]
		var widths: Array = [PMR_BAY, PMR_BAY] if i == 0 else []
		var rest: float = x1 - x0 - PMR_BAY * widths.size()
		var n := floori(rest / BAY_MIN)
		for j in n:
			widths.append(rest / n)
		var x := x0
		for j in widths.size():
			var kind := ""
			if i == 0 and j < 2:
				kind = "pmr"
			elif i == Plan.ROWS.size() - 1 and j >= widths.size() - 2:
				kind = "ev"
			out.append([x, x + widths[j], y, kind, NORTH if i % 2 == 0 else SOUTH])
			x += widths[j]
	return out


## The EV bays' middles (x): their chargers on the lawn behind them (superette.gd).
static func ev_bays() -> Array:
	var out := []
	for b: Array in bays():
		if b[3] == "ev":
			out.append((b[0] + b[1]) * 0.5)
	return out


func build(meshes: bool) -> Node3D:
	_ground()
	_markings()
	_shop()
	_back()
	_station()
	_totem()
	return commit(meshes)


# ---------------------------------------------------------------- ground

func _ground() -> void:
	var k := Plan.KERB_LINE                    # (the ring's sidewalks along the site: no kerb against them)
	var paved: Array = Plan.paved() + [Rect2(k.position.x, k.position.y, k.size.x, Plan.WALK_W),
			Rect2(k.position.x, Plan.INNER.end.y, k.size.x, Plan.WALK_W)]
	for r: Rect2 in [Plan.YARD, Plan.TRUCK_IN, Plan.TRUCK_OUT, Plan.FRONT_LANE, Plan.STATION, Plan.ENTRY, Plan.PARKING,
			Plan.RETURN_LANE]:
		asphalt(r, paved)
	slab(Plan.TOTEM_BED, "#6aa84f")


func _markings() -> void:
	const FILL := 0.028
	for b: Array in bays():
		var r := Rect2(b[0], b[2], b[1] - b[0], 5.0)
		if b[3] == "pmr":
			flat(r.grow(-0.08), FILL, BLUE)
			wheelchair(r.get_center(), b[4])
		elif b[3] == "ev":
			flat(r.grow(-0.08), FILL, EV)
			bolt(r.get_center(), b[4])
		line(Vector2(b[0], b[2]), Vector2(b[0], b[2] + 5.0), 0.12)
		if b[1] > Plan.PARKING.end.x - 0.01:
			line(Vector2(b[1], b[2]), Vector2(b[1], b[2] + 5.0), 0.12)
	# the one-way flow: in on the east (the entry lane), the aisles eastward, the return lane, the shop's front
	# westward, the station southward (under the canopy or by it), out on the west
	for a: Array in [[458.0, -170.0, NORTH], [458.0, -152.0, NORTH], [465.0, -147.0, EAST],
			[472.5, -147.0, EAST], [465.0, -163.0, EAST], [472.5, -163.0, EAST],
			[479.5, -160.0, NORTH], [479.5, -143.0, NORTH], [472.0, -131.0, WEST],
			[441.0, -131.0, WEST], [426.5, -150.0, SOUTH], [431.5, -139.0, SOUTH],
			[439.0, -139.0, SOUTH], [447.0, -139.0, SOUTH], [439.0, -166.0, SOUTH],
			[430.5, -171.5, SOUTH], [436.0, -91.0, SOUTH], [452.0, -91.5, EAST],
			[470.0, -91.0, NORTH]]:
		arrow(Vector2(a[0], a[1]), a[2])
	dashes(Vector2(428.9, -170.0), Vector2(428.9, -136.0), 0.12, 3.0, 2.0)        # the lane by the canopy
	dashes(Vector2(455.2, -134.3), Vector2(460.8, -134.3), 0.3, 0.5, 0.3)         # give way to the front lane
	line(Vector2(427.2, -175.45), Vector2(433.8, -175.45), 0.5)                   # stop: out across the sidewalk
	line(Vector2(466.2, -86.3), Vector2(473.8, -86.3), 0.5)                       # the lorries' out
	# the yard: the lorries' bay along the dock, the waste room's apron hatched, in yellow
	var bay := Rect2(Plan.DOCK.position.x, Plan.DOCK.end.y, Plan.DOCK.size.x, 3.2)
	var c := [bay.position, Vector2(bay.end.x, bay.position.y), bay.end, Vector2(bay.position.x, bay.end.y)]
	for i in 4:
		line(c[i], c[(i + 1) % 4], 0.15, YELLOW)
	hatch(Rect2(Plan.WASTE.position.x, Plan.WASTE.end.y, Plan.WASTE.size.x, 1.6), 0.15, 1.0, YELLOW)
	ground_text("LIVRAISONS", bay.get_center(), NORTH, 0.9, YELLOW)


# ---------------------------------------------------------------- the shop

func _shop() -> void:
	var s := Plan.STORE
	block(s, 0.0, WALL_H, CLADDING)
	flat(s.grow(-0.25), WALL_H + 0.03, ROOF)
	for e: Rect2 in [Rect2(s.position.x, s.position.y, s.size.x, 0.25), Rect2(s.position.x, s.end.y - 0.25, s.size.x, 0.25),
			Rect2(s.position.x, s.position.y, 0.25, s.size.y), Rect2(s.end.x - 0.25, s.position.y, 0.25, s.size.y)]:
		block(e, WALL_H, PARAPET, CLADDING)
		block(e.grow(0.03), PARAPET, PARAPET + 0.06, "steel")
	block_col(s, 0.0, PARAPET)
	var y := s.position.y                           # the south front
	# the glazing, its mullions, the doors, the marquee over them
	face(Vector2(436.0, y - 0.02), Vector2(472.0, y - 0.02), 0.3, 3.5, "glass_dark", SOUTH)
	var x := 436.0
	while x <= 472.01:
		block(Rect2(x - 0.05, y - 0.1, 0.1, 0.1), 0.0, 3.6, ANTHRACITE)
		x += 1.5
	block(Rect2(436.0, y - 0.1, 36.0, 0.1), 0.0, 0.3, ANTHRACITE)
	block(Rect2(436.0, y - 0.1, 36.0, 0.1), 3.5, 3.6, ANTHRACITE)
	var door := Rect2(Plan.ENTRANCE.x - 3.0, y - 0.14, 6.0, 0.14)
	block(door, 0.0, 2.7, ANTHRACITE)
	face(Vector2(door.position.x + 0.1, y - 0.16), Vector2(door.end.x - 0.1, y - 0.16), 0.05, 2.6, "glass", SOUTH)
	block(Rect2(Plan.ENTRANCE.x - 0.04, y - 0.18, 0.08, 0.06), 0.05, 2.6, ANTHRACITE)
	var marquee := Rect2(Plan.ENTRANCE.x - 6.0, y - 2.4, 12.0, 2.4)
	block(marquee, 3.55, 3.8, WHITE)
	block(Rect2(marquee.position.x, marquee.position.y, marquee.size.x, 0.06), 3.55, 3.8, GREEN)
	flat_down(marquee.grow(-0.4), 3.54, "led")
	# the fascia: green, its red fillet under it, a white line over it; round the four sides
	for f: Array in _sides(s):
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		var out: Vector2 = f[2]
		var front: bool = out == SOUTH
		var reach := 0.3 if front else 0.12
		band(a, b, out, reach, 3.85 if front else 4.9, 5.6, GREEN)
		band(a, b, out, reach + 0.04, 3.6 if front else 4.7, 3.85 if front else 4.9, RED)
		band(a, b, out, reach, 5.6, 5.68, WHITE)
	cartouche(Vector2(Plan.ENTRANCE.x, y - 0.38), SOUTH, 4.75, 9.0, 1.7, 1.3)
	sign_text("SUPÉRETTE", Vector2(441.0, y - 0.32), SOUTH, 4.75, 0.75, WHITE)
	sign_text("OUVERT 25H/24 · 8J/7", Vector2(467.5, y - 0.32), SOUTH, 4.75, 0.6, WHITE)
	cartouche(Vector2(s.end.x + 0.2, -111.0), EAST, 5.25, 4.4, 0.9, 0.7)       # to the car park
	cartouche(Vector2(s.position.x - 0.2, -111.0), WEST, 5.25, 4.4, 0.9, 0.7)   # to the station
	cartouche(Vector2(Plan.ENTRANCE.x, s.end.y + 0.2), NORTH, 5.25, 4.4, 0.9, 0.7)  # to the north road
	# the roof: plant, solar panels tilted south
	for u: Rect2 in [Rect2(438.0, -108.0, 3.0, 1.6), Rect2(463.0, -108.0, 3.0, 1.6), Rect2(470.0, -104.0, 2.0, 2.0)]:
		block(u, WALL_H, WALL_H + 1.3, "#b9bec4")
		block(u.grow(-0.3), WALL_H + 1.3, WALL_H + 1.36, ANTHRACITE)
	for py: float in [-119.0, -116.0, -113.0]:
		var a := p3(442.0, py, WALL_H + 0.25)
		var b := p3(470.0, py, WALL_H + 0.25)
		var up := Vector3(0.0, 0.42, -1.6)
		quad(SOLAR, a, b, b + up, a + up, Vector3(0.0, 0.97, 0.25))
		block(Rect2(442.0, py + 1.5, 28.0, 0.08), WALL_H, WALL_H + 0.67, "steel")


## A building's four sides: [from, to, outward] (map), anticlockwise.
static func _sides(r: Rect2) -> Array:
	return [[r.position, Vector2(r.end.x, r.position.y), SOUTH], [Vector2(r.end.x, r.position.y), r.end, EAST],
			[r.end, Vector2(r.position.x, r.end.y), NORTH], [Vector2(r.position.x, r.end.y), r.position, WEST]]


func _back() -> void:
	var y := Plan.STORE.end.y                  # the north wall
	var d := Plan.DOCK
	block(d, 0.0, 1.1, CONCRETE)
	block_col(d, 0.0, 1.1)
	block(Rect2(d.position.x, d.end.y - 0.15, d.size.x, 0.15), 1.1, 1.115, YELLOW)
	for k in 3:                                # its steps, on the west
		var step := Rect2(d.position.x - 0.35 * (k + 1), d.position.y, 0.35, 1.6)
		block(step, 0.0, 1.1 * (3 - k) / 4.0, CONCRETE)
		block_col(step, 0.0, 1.1 * (3 - k) / 4.0)
	for door_x: float in [445.0, 455.0]:       # the roller doors, their bumpers, a lamp over each
		face(Vector2(door_x + 3.2, y + 0.02), Vector2(door_x, y + 0.02), 1.1, 4.1, "garage_door", NORTH)
		block(Rect2(door_x - 0.12, y, 3.44, 0.1), 4.1, 4.25, ANTHRACITE)
		for bx: float in [door_x - 0.1, door_x + 3.05]:
			block(Rect2(bx, d.end.y, 0.25, 0.14), 0.55, 1.0, "rubber")
		block(Rect2(door_x + 1.35, y, 0.5, 0.35), 4.45, 4.6, ANTHRACITE)
		flat_down(Rect2(door_x + 1.4, y + 0.05, 0.4, 0.25), 4.44, "emit")
	var canopy := Rect2(d.position.x - 1.0, y, d.size.x + 2.0, 3.6)
	block(canopy, 4.8, 4.95, "zinc")
	block_col(canopy, 4.8, 4.95)
	face(Vector2(465.6, y + 0.02), Vector2(464.6, y + 0.02), 0.0, 2.2, "#3b4652", NORTH)   # the staff door
	# the waste room: open on the yard, slatted gates, the containers in it (props)
	var w := Plan.WASTE
	for r: Rect2 in [Rect2(w.position.x, w.position.y, 0.2, w.size.y), Rect2(w.end.x - 0.2, w.position.y, 0.2, w.size.y)]:
		block(r, 0.0, 2.4, CLADDING)
		block_col(r, 0.0, 2.4)
	block(Rect2(w.position.x, w.position.y, w.size.x, w.size.y + 0.2), 2.4, 2.55, GREEN)
	block_col(Rect2(w.position.x, w.position.y, w.size.x, w.size.y + 0.2), 2.4, 2.55)
	for g: Rect2 in [Rect2(w.position.x + 0.2, w.end.y - 0.08, 1.8, 0.08), Rect2(w.end.x - 2.0, w.end.y - 0.08, 1.8, 0.08)]:
		block(g, 0.1, 2.2, "slats")
		block_col(g, 0.0, 2.2)


# ---------------------------------------------------------------- the filling station

func _station() -> void:
	var c := Plan.CANOPY
	block(c, CANOPY_H, CANOPY_H + 0.9, WHITE)
	block_col(c, CANOPY_H, CANOPY_H + 0.9)
	for f: Array in _sides(c):
		band(f[0], f[1], f[2], 0.05, CANOPY_H + 0.3, CANOPY_H + 0.82, GREEN)
		band(f[0], f[1], f[2], 0.07, CANOPY_H + 0.08, CANOPY_H + 0.3, RED)
	for i in 3:
		for j in 2:
			flat_down(Rect2(c.position.x + 2.5 + i * 6.0, c.position.y + 3.0 + j * 8.0, 3.0, 2.0), CANOPY_H - 0.01, "led")
	cartouche(Vector2(c.get_center().x, c.position.y - 0.08), SOUTH, CANOPY_H + 0.45, 3.2, 0.62, 0.48)
	cartouche(Vector2(c.get_center().x, c.end.y + 0.08), NORTH, CANOPY_H + 0.45, 3.2, 0.62, 0.48)
	for ix: float in Plan.ISLANDS:
		var island := Rect2(ix - 0.6, -158.5, 1.2, 13.0)
		block(island, 0.0, 0.2, CONCRETE)
		block_col(island, 0.0, 0.2)
		for e: float in [island.position.y, island.end.y - 0.4]:
			block(Rect2(ix - 0.62, e, 1.24, 0.4), 0.0, 0.22, YELLOW)
		for py: float in [-157.0, -147.0]:          # the canopy's columns
			cyl(WHITE, p3(ix, py, 0.2), 0.22, CANOPY_H - 0.2, 12)
			col(ix - 0.22, ix + 0.22, Plan.LEVEL, Plan.LEVEL + CANOPY_H, -py - 0.22, -py + 0.22)
		for py: float in [-154.5, -149.5]:          # the pumps: both sides of the island served
			_pump(Vector2(ix, py))
	for p: Vector3 in [Vector3(434.0, -149.0, 0.0), Vector3(444.0, -155.0, 0.0)]:
		light(p3(p.x, p.y, CANOPY_H - 0.4), Color(1.0, 0.97, 0.92), 1.4, 14.0)


func _pump(at: Vector2) -> void:
	var body := Rect2(at.x - 0.3, at.y - 0.55, 0.6, 1.1)
	block(body, 0.2, 1.75, WHITE)
	block(body.grow(0.02), 1.75, 2.2, GREEN)
	block(body.grow(0.04), 2.2, 2.3, RED)
	block_col(body, 0.2, 2.3)
	for side: float in [-1.0, 1.0]:                 # each face: its screen, its nozzles and hoses
		var fx := at.x + side * 0.305
		face(Vector2(fx, at.y + 0.35 * side), Vector2(fx, at.y - 0.35 * side), 1.25, 1.6, "screen", Vector2(side, 0.0))
		for k in 3:
			var ny := at.y - 0.35 + k * 0.35
			block(Rect2(fx + (0.0 if side > 0 else -0.08), ny - 0.05, 0.08, 0.1), 0.85, 1.05,
					[GREEN, "#e8c021", ANTHRACITE][k])
			rod("rubber", p3(fx + side * 0.06, ny, 0.9), p3(fx + side * 0.25, ny, 0.45), 0.02, 6)


## The price totem on its planter: its faces east and west (to the south road's traffic both ways).
func _totem() -> void:
	var t := Plan.TOTEM
	var post := Rect2(t.x - 0.2, t.y - 0.8, 0.4, 1.6)
	var base := KERB
	block(post.grow(0.1), base, base + 0.5, CONCRETE)
	block(post, base + 0.5, base + 6.2, ANTHRACITE)
	block_col(post.grow(0.1), base, base + 6.2)
	block(post.grow(0.02), base + 4.7, base + 4.85, GREEN)
	block(post.grow(0.03), base + 4.85, base + 6.1, RED)
	block(post.grow(0.02), base + 6.1, base + 6.2, WHITE)
	for out: Vector2 in [EAST, WEST]:
		var fx := t.x + out.x * 0.24
		sign_text("25/8", Vector2(t.x + out.x * 0.235, t.y), out, base + 5.45, 0.5, WHITE)
		for k in PRICES.size():
			var h := base + 4.15 - k * 0.95
			face(Vector2(fx, t.y - out.x * 0.7), Vector2(fx, t.y + out.x * 0.7), h - 0.4, h + 0.4, "screen", out)
			sign_text(PRICES[k][0], Vector2(fx + out.x * 0.01, t.y - out.x * 0.46), out, h, 0.1, WHITE)
			sign_text(PRICES[k][1], Vector2(fx + out.x * 0.01, t.y + out.x * 0.2), out, h, 0.28, Color("#ffb52e"),
					false)


# ---------------------------------------------------------------- pieces

## A flat rectangle at h facing down (a ceiling's lights).
func flat_down(r: Rect2, h: float, m: String) -> void:
	quad(m, p3(r.position.x, r.position.y, h), p3(r.end.x, r.position.y, h), p3(r.end.x, r.end.y, h),
			p3(r.position.x, r.end.y, h), Vector3.DOWN)


## A band along a wall from a to b (map), standing `reach` m out of it towards `out`, from h0 to h1.
func band(a: Vector2, b: Vector2, out: Vector2, reach: float, h0: float, h1: float, m: String) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var r := Rect2(lo, hi - lo)
	if out.x != 0.0:
		r = Rect2(a.x + (0.0 if out.x > 0.0 else -reach), r.position.y - reach, reach, r.size.y + 2.0 * reach)
	else:
		r = Rect2(r.position.x - reach, a.y + (0.0 if out.y > 0.0 else -reach), r.size.x + 2.0 * reach, reach)
	block(r, h0, h1, m)


## The brand's cartouche: a red board w x hgt, its face at `at` (map) towards `out`, middle at h; "25/8" in white.
func cartouche(at: Vector2, out: Vector2, h: float, w: float, hgt: float, text_h: float) -> void:
	var side := Vector2(-out.y, out.x)
	var a := at - side * w * 0.5
	var b := at + side * w * 0.5
	var back := -out * 0.12
	var r := Rect2(a, Vector2.ZERO).expand(b).expand(a + back).expand(b + back)
	block(r, h - hgt * 0.5, h + hgt * 0.5, RED)
	block(r.grow(0.02), h + hgt * 0.5, h + hgt * 0.5 + 0.06, WHITE)
	sign_text("25/8", at + out * 0.01, out, h, text_h, WHITE)


## Text on a wall at `at` (map) facing `out`, its middle at h, its capitals `size` m tall.
func sign_text(text: String, at: Vector2, out: Vector2, h: float, size: float, colour: Variant, shaded := true) -> void:
	var xf := Transform3D(Basis(Vector3.UP, atan2(out.x, -out.y)), p3(at.x, at.y, h))
	var l := label(text, xf, 96, size / 70.0, Color(colour) if colour is String else colour, shaded)
	l.font = _font()
	l.outline_size = 0


## Text painted on the ground at `at`, its top towards `up` (map).
func ground_text(text: String, at: Vector2, up: Vector2, size: float, colour: String) -> void:
	var yaw := atan2(up.x, up.y)
	var xf := Transform3D(Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, -PI / 2.0), p3(at.x, at.y, PAINT + 0.005))
	var l := label(text, xf, 96, size / 70.0, Color(colour))
	l.font = _font()


static var _bold: Font

static func _font() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Arial Black", "Arial", "Helvetica", "sans-serif"])
		f.font_weight = 800
		_bold = f
	return _bold
