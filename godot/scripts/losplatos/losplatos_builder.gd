extends RefCounted
## Losplatos Custom, the car repair and paint shop in place of building #758 (the LadHyX; scripts/losplatos/
## losplatos.gd places it and runs its door), after Thomas's references and corrections (ref/LosPalaisosCustom/): an
## industrial workshop of grey blocks under anthracite ribbed steel cladding, a sawtooth roof of four teeth glazed to
## the north, a roll-up door between two barred windows, the customers' lounge's shop window and glazed door, the two
## neon signs on poles at the facade's ends; round it paved sidewalks, granite kerbs, new asphalt in front, along the
## north end and over the yard behind (the tow truck's bay), a concrete ramp up to the door (_site); inside, a workshop of cream blocks over a yellow band, blue steel, fluorescent tubes, benches and
## tyres, and the customers' lounge (counter, sofas, coffee). Its own name and logo; the brands on its posters are
## made up.
## Built in its own frame: x along the west facade (north), y up from the floor, z into the building (east). The shop
## is L x W m: at its south end the lounge (in front) and a store (behind it), then the workshop hall, entered by the
## roll-up door, the service bay painted in its middle (where a car is repaired and painted).
## Collision (BUILDINGS): the walls, floor, roof, partition, the sidewalk and ramp, the furniture one bumps into; the
## door's own shape is the caller's (it opens).

const Layers = preload("res://scripts/physics_layers.gd")

const L := 31.0                             # m along the west facade
const W := 16.0                             # m deep
const H := 6.2                              # m, walls (the roof's low edge)
const T := 0.3                              # m, walls
const TEETH := 4                            # the sawtooth roof: its teeth along x, rising RISE to the north...
const RISE := 2.2                           # ...where each one's glazed face looks north
const HALL_X := 11.0                        # the workshop from here (its partition from HALL_X to HALL_X + T)
const DOOR := Vector3(19.0, 24.0, 4.4)      # the roll-up door in the west wall: x from, x to, height
const BAR_WINDOWS := [[13.6, 17.4, 1.2, 3.6], [25.6, 29.4, 1.2, 3.6]]   # the workshop's barred windows either side of
											# the door (x from, x to, y from, y to): the same, symmetric
const LOUNGE_GLASS := [1.2, 8.4, 0.45, 3.6] # the lounge's
const LOUNGE_DOOR := [8.9, 10.3, 0.0, 2.4]  # its glazed door
const LOUNGE_Z := 7.2                       # the lounge's back wall (the store behind it)
const LOUNGE_CEILING := 3.7
const PASS_Z := Vector2(5.5, 6.6)           # the doorway between the lounge and the workshop
const BAY := Vector3(21.5, 0.0, 8.6)        # the service bay's middle (a car stands in it facing +z)
const BAY_SIZE := Vector2(3.8, 6.8)         # m across (x) and along (z)
const SLATS := 16                           # the door's slats
const RAMP := 1.6                           # m of lowered kerb either side of the door, then FLARE m back up
const FLARE := 1.4
const FRONT_W := 3.0                        # m, the front sidewalk (its kerb parallel to the facade)
const KERB_UP := 0.17                       # m, the sidewalks over the ground (the kerbs' height over the asphalt)
const TAR_UP := 0.04                        # m, the new asphalt over the ground
const GRID := 0.5                           # m, the paving's grid
## The paved rectangles [x0, z0, x1, z1]: the sidewalks (in front, along the north end, behind), the asphalt (between
## the front kerb and the road, the access lane along the north end, the yard behind), and the kerbs between them
## [from, to, the asphalt's side].
const SIDEWALKS := [[-3.5, -3.0, 34.0, 0.0], [31.0, 0.0, 34.0, 18.0], [-0.5, 16.0, 31.0, 18.0]]
const ASPHALT := [[-3.5, -6.0, 46.0, -3.0], [34.0, -3.0, 46.0, 18.0], [1.5, 18.0, 46.0, 33.5]]
const KERBS := [[Vector2(-3.5, -3.0), Vector2(34.0, -3.0), Vector2(0, -1)],
		[Vector2(34.0, -3.0), Vector2(34.0, 18.0), Vector2(1, 0)], [Vector2(34.0, 18.0), Vector2(-0.5, 18.0), Vector2(0, 1)]]
const TOW_BAY := Rect2(7.4, 18.6, 3.8, 9.0) # the tow truck's bay in the yard (x z, size), the truck facing -z
const NAVY := Color("#16213e")
const YELLOW := Color("#f2c230")
const RED := Color("#d8343a")

var _st := {}
var _mats := {}
var _body: StaticBody3D
var _root: Node3D
var _off := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

static var _textures := {}


## The shop (its frame's origin at the floor of the west facade's south end); `ground` (x, z) -> the map's ground
## height in its frame (the paving follows it), `_on_road` (unused). Meta: "bay" (Vector3), "bay_size"
## (Vector2), "door" (Vector3: its middle, on the facade line), "slats" (the door's slat nodes, bottom first),
## "door_shape" (its CollisionShape3D), "paved" (the paved rectangles [x0, z0, x1, z1]), "tow_bay" (Transform3D: the
## tow truck's bay, its +z the truck's front), "tow_bay_size" (Vector2), "tow_terminal" (Vector3).
func build(ground: Callable, _on_road: Callable, meshes := true) -> Node3D:
	_rng.seed = 758
	_root = Node3D.new()
	_root.name = "LosplatosCustom"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "custom_garage", "name": "Losplatos Custom", "id": "losplatos",
			"kind": "car repairs and paint"})
	_root.add_child(_body)
	_shell()
	_roof()
	_site(ground)
	_door()
	if meshes:
		_facade()
		var sw := func(x: float, z: float) -> float: return _sidewalk_y(ground, x, z)
		_pole_sign(Vector3(-1.4, 0.0, -1.7), sw)
		_pole_sign(Vector3(L + 1.4, 0.0, -1.7), sw)
		_yard(ground)
		_hall()
		_lounge()
		_lights()
		for name: String in _st:
			var mi := MeshInstance3D.new()
			mi.name = "M_" + name
			mi.mesh = (_st[name] as SurfaceTool).commit()
			mi.material_override = _mat(name)
			if name in ["glass", "emit", "bulb", "screen_on"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mi)
	_root.set_meta("bay", BAY)
	_root.set_meta("bay_size", BAY_SIZE)
	_root.set_meta("door", Vector3((DOOR.x + DOOR.y) * 0.5, 0.0, 0.0))
	return _root


# ---------------------------------------------------------------- the shell

func _shell() -> void:
	_box("floor", 0.0, L, -0.3, 0.0, 0.0, W)
	_col(0.0, L, -0.3, 0.0, 0.0, W)
	# the outer walls up to the roof's low edge (the north one to its high edge), the west one open at its windows,
	# the lounge's door and the roll-up door
	_wall_open(0.0, L, H, 0.0, T, [BAR_WINDOWS[0], BAR_WINDOWS[1], LOUNGE_GLASS, LOUNGE_DOOR, [DOOR.x, DOOR.y, 0.0, DOOR.z]])
	_wall(0.0, L, 0.0, H, W - T, W)
	_wall(0.0, T, 0.0, H, T, W - T)
	_wall(L - T, L, 0.0, H, 0.0, W)
	_wall(L - T, L, H, H + RISE, T, W - T)          # (over the side walls: between the gables, not in their planes)
	# the workshop | the lounge and the store: up to the roof, a doorway into the lounge
	var top := _roof_at(HALL_X + T)
	_wall(HALL_X, HALL_X + T, 0.0, top, T, PASS_Z.x)
	_wall(HALL_X, HALL_X + T, 0.0, top, PASS_Z.y, W - T)
	_wall(HALL_X, HALL_X + T, 2.2, top, PASS_Z.x, PASS_Z.y)
	# the lounge's back wall (the store behind it) and its ceiling
	_wall(T, HALL_X, 0.0, LOUNGE_CEILING, LOUNGE_Z, LOUNGE_Z + T)
	_box("lounge_ceiling", T, HALL_X, LOUNGE_CEILING, LOUNGE_CEILING + 0.1, T, LOUNGE_Z + T)
	_col(T, HALL_X, LOUNGE_CEILING, LOUNGE_CEILING + 0.1, T, LOUNGE_Z + T)


## The roof's underside over x (its sawtooth).
static func _roof_at(x: float) -> float:
	var tw := L / TEETH
	var k := clampi(int(floorf(x / tw)), 0, TEETH - 1)
	return H + RISE * clampf((x - k * tw) / tw, 0.0, 1.0)


## A wall from x0 to x1 (z0..z1) up to `top`, open at `holes` ([x from, x to, y from, y to] each).
func _wall_open(x0: float, x1: float, top: float, z0: float, z1: float, holes: Array) -> void:
	var hs := holes.duplicate()
	hs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var x := x0
	for h: Array in hs:
		_wall(x, h[0], 0.0, top, z0, z1)
		_wall(h[0], h[1], 0.0, h[2], z0, z1)
		_wall(h[0], h[1], h[3], top, z0, z1)
		x = h[1]
	_wall(x, x1, 0.0, top, z0, z1)


## A wall piece of grey blocks (its upper band clad outside: _facade; lined inside: _hall, _lounge).
func _wall(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if x1 - x0 < 0.005 or y1 - y0 < 0.005 or z1 - z0 < 0.005:
		return
	_box("blocks_out", x0, x1, y0, y1, z0, z1)
	_col(x0, x1, y0, y1, z0, z1)


## The sawtooth roof: TEETH ribbed steel slopes rising to the north, the glazed north faces (the last one is the north
## wall), the west and east walls' triangular gables clad in steel.
func _roof() -> void:
	var tw := L / TEETH
	var length := sqrt(tw * tw + RISE * RISE)
	var basis := Basis(Vector3(0, 0, 1), atan2(RISE, tw))
	var up := basis * Vector3.UP
	for k in TEETH:
		var x0 := k * tw
		var x1 := x0 + tw
		var xf := Transform3D(basis, Vector3((x0 + x1) * 0.5, H + RISE * 0.5, W * 0.5) + up * 0.1)
		_box_xf("roof_metal", xf, Vector3(length + 0.1, 0.2, W + 0.3), Vector3.ZERO)
		_col_xf(xf, Vector3(length, 0.2, W))
		_box_xf("dark_steel", xf, Vector3(length + 0.14, 0.26, 0.08), Vector3(0, 0, -W * 0.5 - 0.15))
		_box_xf("dark_steel", xf, Vector3(length + 0.14, 0.26, 0.08), Vector3(0, 0, W * 0.5 + 0.15))
		_gable(x0, x1, 0.0, T)
		_gable(x0, x1, W - T, W)
		if k < TEETH - 1:
			_box("dark_steel", x1 - 0.08, x1, H, H + 0.12, T, W - T)
			_box("glass", x1 - 0.05, x1 - 0.03, H + 0.12, H + RISE - 0.05, T, W - T)
			var n := 9
			for j in n + 1:
				var z := T + (W - 2.0 * T) * j / n
				_box("dark_steel", x1 - 0.08, x1, H, H + RISE, z - 0.04, z + 0.04)
			_col(x1 - 0.06, x1, H, H + RISE, T, W - T)


## A triangular gable on a side wall (z0..z1) under the slope from (x0, H) to (x1, H + RISE).
func _gable(x0: float, x1: float, z0: float, z1: float) -> void:
	var st := _tool("cladding_gable")
	var a0 := Vector3(x0, H - 0.04, z0)
	var b0 := Vector3(x1, H - 0.04, z0)
	var c0 := Vector3(x1, H + RISE - 0.04, z0)
	var a1 := Vector3(x0, H - 0.04, z1)
	var b1 := Vector3(x1, H - 0.04, z1)
	var c1 := Vector3(x1, H + RISE - 0.04, z1)
	# (wound clockwise seen from outside: Godot's front faces, one-sided: a double-sided face shadows itself)
	for tri: Array in [[a0, b0, c0, Vector3(0, 0, -1)], [a1, c1, b1, Vector3(0, 0, 1)]]:
		for p: int in 3:
			st.set_normal(tri[3])
			st.add_vertex(tri[p])
	var slope := (c0 - a0).cross(Vector3(0, 0, 1)).normalized() * -1.0
	for p: Vector3 in [a0, c1, a1, a0, c0, c1]:
		st.set_normal(slope)
		st.add_vertex(p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a0, b0, c0, a1, b1, c1])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)


# ---------------------------------------------------------------- the site: sidewalks, kerbs, asphalt

## Round the shop (Thomas's plan, ref/LosPalaisosCustom/vueDessus.png): paved sidewalks in front (straight, its kerb
## parallel to the facade, level with the floor at the facade: no step at the doors), along the north end and behind;
## new asphalt between the front kerb and the road, over the access lane along the north end and the yard behind (the
## tow truck's bay in it); granite kerbs as at Massy-Palaiseau (a light top, its face, a gutter) between them; before
## the roll-up door the kerb lowered and a concrete ramp, flaring back up either side.
## Heights follow the map's `ground` (local): the asphalt just over it, the sidewalks KERB_UP over it (the kerb's
## height), the front sidewalk falling from the floor at the facade to its kerb.
func _site(ground: Callable) -> void:
	var paved: Array = []
	var faces := PackedVector3Array()
	var sw := func(x: float, z: float) -> float: return _sidewalk_y(ground, x, z)
	var tar := func(x: float, z: float) -> float: return float(ground.call(x, z)) + TAR_UP
	# the sidewalks (the front one in concrete before the door: the ramp)
	for r: Array in SIDEWALKS:
		faces.append_array(_grid(r, sw, func(x: float, z: float) -> String:
				return "drive" if r == SIDEWALKS[0] and _ramp_weight(x) > 0.5 and z < 0.0 else "pavers"))
		paved.append(r)
	# the asphalt
	for r: Array in ASPHALT:
		faces.append_array(_grid(r, tar, func(_x: float, _z: float) -> String: return "asphalt"))
		paved.append(r)
	# the kerbs: [from, to (x z), the side the asphalt is on]
	for k: Array in KERBS:
		faces.append_array(_kerb(k[0], k[1], k[2], sw, tar))
	# the sidewalks' open edges (on the grass, by the corners): their sides down to the ground
	for e: Array in [[Vector2(-3.5, -3.0), Vector2(-3.5, 0.0)], [Vector2(-3.5, 0.0), Vector2(0.0, 0.0)],
			[Vector2(-0.5, 16.0), Vector2(-0.5, 18.0)], [Vector2(-0.5, 16.0), Vector2(0.0, 16.0)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := maxi(1, ceili(a.distance_to(b) / GRID))
		for i in n:
			var p := a.lerp(b, float(i) / n)
			var q := a.lerp(b, float(i + 1) / n)
			var pt := Vector3(p.x, float(sw.call(p.x, p.y)), p.y)
			var qt := Vector3(q.x, float(sw.call(q.x, q.y)), q.y)
			var pb := Vector3(p.x, float(ground.call(p.x, p.y)) - 0.05, p.y)
			var qb := Vector3(q.x, float(ground.call(q.x, q.y)) - 0.05, q.y)
			_tris("kerb_face", [pb, qb, qt, pb, qt, pt])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)
	_root.set_meta("paved", paved)
	# the ramp's guide lines, the threshold's steel edge, the yellow bollards by the door
	for gx: float in [DOOR.x + 0.4, DOOR.y - 0.4]:
		var a := Vector3(gx, float(sw.call(gx, -0.3)) + 0.015, -0.3)
		var b := Vector3(gx, float(sw.call(gx, -FRONT_W + 0.4)) + 0.015, -FRONT_W + 0.4)
		var side := Vector3(0.06, 0, 0)
		_tris("white_paint", [a - side, b - side, b + side, a - side, b + side, a + side])
	_box("steel", DOOR.x, DOOR.y, -0.01, 0.015, -0.05, T)
	for bx: float in [DOOR.x - 0.55, DOOR.y + 0.55]:
		var by: float = sw.call(bx, -0.22)
		_cyl("yellow", Vector3(bx, by - 0.05, -0.22), 0.11, 1.05, 14)
		_cyl("yellow", Vector3(bx, by + 1.0, -0.22), 0.11, 0.05, 14, 0.06)
		_col(bx - 0.11, bx + 0.11, by, by + 1.05, -0.33, -0.11)
	# the tow truck's bay in the yard, painted yellow, its name on the asphalt
	var t0 := TOW_BAY.position
	var t1 := TOW_BAY.end
	for e: Array in [[Vector2(t0.x, t0.y), Vector2(t1.x, t0.y)], [Vector2(t1.x, t0.y), Vector2(t1.x, t1.y)],
			[Vector2(t1.x, t1.y), Vector2(t0.x, t1.y)], [Vector2(t0.x, t1.y), Vector2(t0.x, t0.y)]]:
		_paint_line(e[0], e[1], 0.12, tar)
	var mid := TOW_BAY.get_center()
	var name := _label("DÉPANNAGE", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, 0.0),
			Vector3(mid.x, float(tar.call(mid.x, t1.y - 1.4)) + 0.01, t1.y - 1.4)), 72, 0.012, Color(1.0, 0.82, 0.25, 0.9))
	name.shaded = true
	_root.set_meta("tow_bay", Transform3D(Basis(Vector3.UP, PI), Vector3(mid.x, float(tar.call(mid.x, mid.y)), mid.y)))
	_root.set_meta("tow_bay_size", Vector2(TOW_BAY.size.x, TOW_BAY.size.y))
	_root.set_meta("tow_terminal", Vector3(TOW_BAY.end.x + 1.6, float(tar.call(TOW_BAY.end.x + 1.6, mid.y - 2.0)),
			mid.y - 2.0))


## The sidewalks' height at (x, z): KERB_UP over the ground; in front, falling from the floor at the facade to the kerb
## (lowered before the door: the ramp), never under the ground.
func _sidewalk_y(ground: Callable, x: float, z: float) -> float:
	var g: float = float(ground.call(x, z))
	var y := g + KERB_UP
	if z <= 0.0 and z >= -FRONT_W:
		var k := float(ground.call(x, -FRONT_W)) + KERB_UP
		k = lerpf(k, float(ground.call(x, -FRONT_W - 0.2)) + TAR_UP + 0.02, _ramp_weight(x))
		var f := lerpf(k, 0.0, (z + FRONT_W) / FRONT_W)
		var along := clampf(minf(x + 0.5, L + 0.5 - x), 0.0, 1.0)        # (beyond the facade's ends: KERB_UP)
		y = lerpf(y, f, along)
	return maxf(y, g + 0.03)


## A grid over rectangle r ([x0, z0, x1, z1]) at height(x, z), each cell in the material mat_at(x, z) gives; its faces.
func _grid(r: Array, height: Callable, mat_at: Callable) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var x0: float = r[0]
	var z0: float = r[1]
	var x1: float = r[2]
	var z1: float = r[3]
	var nx := maxi(1, ceili((x1 - x0) / GRID))
	var nz := maxi(1, ceili((z1 - z0) / GRID))
	var pts := []
	for i in nx + 1:
		var col := []
		var x := lerpf(x0, x1, float(i) / nx)
		for j in nz + 1:
			var z := lerpf(z0, z1, float(j) / nz)
			col.append(Vector3(x, height.call(x, z), z))
		pts.append(col)
	for i in nx:
		for j in nz:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			var m: String = mat_at.call((a.x + c.x) * 0.5, (a.z + c.z) * 0.5)
			var quad := [a, b, c, a, c, d]
			_tris(m, quad)
			faces.append_array(PackedVector3Array(quad))
	return faces


## A granite kerb from `a` to `b` (x z) between a sidewalk (heights `sw`) and the asphalt (`tar`) on side `out`: a light
## top 0.3 m wide, its face down to the asphalt, a gutter on the asphalt's side. Its faces.
func _kerb(a: Vector2, b: Vector2, out: Vector2, sw: Callable, tar: Callable) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var n := maxi(1, ceili(a.distance_to(b) / GRID))
	var inward := -out * 0.3
	for i in n:
		var p := a.lerp(b, float(i) / n)
		var q := a.lerp(b, float(i + 1) / n)
		var p_top := Vector3(p.x, float(sw.call(p.x, p.y)) + 0.022, p.y)
		var q_top := Vector3(q.x, float(sw.call(q.x, q.y)) + 0.022, q.y)
		var p_in := Vector3(p.x + inward.x, float(sw.call(p.x + inward.x, p.y + inward.y)) + 0.022, p.y + inward.y)
		var q_in := Vector3(q.x + inward.x, float(sw.call(q.x + inward.x, q.y + inward.y)) + 0.022, q.y + inward.y)
		_tris("kerb_top", [p_top, q_top, q_in, p_top, q_in, p_in])
		var p_foot := Vector3(p.x, float(tar.call(p.x, p.y)) - 0.02, p.y)
		var q_foot := Vector3(q.x, float(tar.call(q.x, q.y)) - 0.02, q.y)
		var face := [p_foot, q_foot, q_top, p_foot, q_top, p_top]
		_tris("kerb_face", face)
		faces.append_array(PackedVector3Array(face))
		var po := Vector3(p.x + out.x * 0.3, float(tar.call(p.x + out.x * 0.3, p.y + out.y * 0.3)) + 0.012, p.y + out.y * 0.3)
		var qo := Vector3(q.x + out.x * 0.3, float(tar.call(q.x + out.x * 0.3, q.y + out.y * 0.3)) + 0.012, q.y + out.y * 0.3)
		var pg := Vector3(p.x, float(tar.call(p.x, p.y)) + 0.012, p.y)
		var qg := Vector3(q.x, float(tar.call(q.x, q.y)) + 0.012, q.y)
		_tris("gutter", [pg, qg, qo, pg, qo, po])
	return faces


## A painted line from `a` to `b` (x z), `w` m wide, on the asphalt.
func _paint_line(a: Vector2, b: Vector2, w: float, tar: Callable) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / GRID))
	var side := (b - a).normalized().orthogonal() * w * 0.5
	for i in n:
		var p := a.lerp(b, float(i) / n)
		var q := a.lerp(b, float(i + 1) / n)
		var pts := []
		for c: Vector2 in [p - side, q - side, q + side, p + side]:
			pts.append(Vector3(c.x, float(tar.call(c.x, c.y)) + 0.014, c.y))
		_tris("yellow_paint_floor", [pts[0], pts[1], pts[2], pts[0], pts[2], pts[3]])


## 1 before the door (the lowered kerb), 0 beyond the flares, between in them.
static func _ramp_weight(x: float) -> float:
	var a := DOOR.x - RAMP
	var b := DOOR.y + RAMP
	if x >= a and x <= b:
		return 1.0
	var d := a - x if x < a else x - b
	return clampf(1.0 - d / FLARE, 0.0, 1.0)


## Triangles `pts` (three by three) in material `mat`, facing up or out (both faces drawn: the material's cull).
func _tris(mat: String, pts: Array) -> void:
	var st := _tool(mat)
	for i in range(0, pts.size() - 2, 3):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var c: Vector3 = pts[i + 2]
		var n := (b - a).cross(c - a).normalized()
		if n.y < -0.01 or (absf(n.y) <= 0.01 and n.z > 0.0):
			n = -n
		for p: Vector3 in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)


## The roll-up door: SLATS slats, each its own node (losplatos.gd lifts them into the housing over the opening), a
## housing over the opening inside, steel guides; its collision shape (a box over the opening).
func _door() -> void:
	var slats := []
	var h := DOOR.z / SLATS
	var mesh := BoxMesh.new()
	mesh.size = Vector3(DOOR.y - DOOR.x - 0.04, h - 0.006, 0.05)
	for k in SLATS:
		var mi := MeshInstance3D.new()
		mi.name = "Slat%d" % k
		mi.mesh = mesh
		mi.material_override = _mat("door")
		mi.position = Vector3((DOOR.x + DOOR.y) * 0.5, (k + 0.5) * h, T * 0.5)
		_root.add_child(mi)
		slats.append(mi)
	_root.set_meta("slats", slats)
	_box("dark_steel", DOOR.x - 0.12, DOOR.x + 0.02, 0.0, DOOR.z + 0.1, -0.04, T + 0.04)
	_box("dark_steel", DOOR.y - 0.02, DOOR.y + 0.12, 0.0, DOOR.z + 0.1, -0.04, T + 0.04)
	_box("dark_steel", DOOR.x - 0.12, DOOR.y + 0.12, DOOR.z, DOOR.z + 0.12, -0.04, 0.0)
	_box("door_housing", DOOR.x - 0.2, DOOR.y + 0.2, DOOR.z, DOOR.z + 0.6, T, T + 0.55)
	var cs := CollisionShape3D.new()
	cs.name = "DoorShape"
	var box := BoxShape3D.new()
	box.size = Vector3(DOOR.y - DOOR.x, DOOR.z, 0.2)
	cs.shape = box
	cs.position = Vector3((DOOR.x + DOOR.y) * 0.5, DOOR.z * 0.5, T * 0.5)
	_body.add_child(cs)
	_root.set_meta("door_shape", cs)


# ---------------------------------------------------------------- outside

func _facade() -> void:
	# anthracite ribbed steel over the blocks from a dark flashing up, on every side; a dark plinth
	for f: Array in [[0.0, L, -0.012, 0.0], [0.0, L, W, W + 0.012], [-0.012, 0.0, 0.0, W], [L, L + 0.012, 0.0, W]]:
		var top: float = H + RISE if f[0] == L else H
		_box("cladding", f[0], f[1], 4.7, top, f[2], f[3])
		_box("dark_steel", f[0], f[1], 4.55, 4.7, f[2], f[3])
	for seg: Array in [[0.0, LOUNGE_DOOR[0]], [LOUNGE_DOOR[1], DOOR.x - 0.12], [DOOR.y + 0.12, L]]:
		_box("plinth", seg[0], seg[1], 0.0, 0.35, -0.022, 0.0)
	# the logo over the door
	_logo(Transform3D(Basis(Vector3.UP, PI), Vector3((DOOR.x + DOOR.y) * 0.5, 5.32, -0.05)), 4.6, 1.15)
	# the shop windows, the lounge's glazed door, the services board over the lounge's window
	for g: Array in BAR_WINDOWS:
		_barred_window(g)
	_shop_window(LOUNGE_GLASS)
	_glazed_door(LOUNGE_DOOR)
	# lamps over the door, a dumpster
	for lx: float in [DOOR.x - 0.7, DOOR.y + 0.7]:
		_box("dark_steel", lx - 0.04, lx + 0.04, 4.0, 4.08, -0.4, 0.0)
		_cyl("dark_steel", Vector3(lx, 3.85, -0.4), 0.16, 0.15, 14, 0.06)
		_cyl("emit", Vector3(lx, 3.84, -0.4), 0.13, 0.01, 14)


## A shop window in the west wall's opening g ([x0, x1, y0, y1]): a dark steel frame, clear glass between mullions
## every ~1.8 m, a sill.
func _shop_window(g: Array) -> void:
	var x0: float = g[0]
	var x1: float = g[1]
	var y0: float = g[2]
	var y1: float = g[3]
	var z := T * 0.5
	x0 += 0.01                                  # (1 cm inside the opening: not in its reveals' planes)
	x1 -= 0.01
	y1 -= 0.01
	_box("glass", x0, x1, y0, y1, z - 0.006, z + 0.006)
	for e: Array in [[x0, x0 + 0.08, y0, y1], [x1 - 0.08, x1, y0, y1], [x0, x1, y0, y0 + 0.08], [x0, x1, y1 - 0.08, y1]]:
		_box("dark_steel", e[0], e[1], e[2], e[3], z - 0.05, z + 0.05)
	var n := maxi(1, roundi((x1 - x0) / 1.8))
	for k in range(1, n):
		var mx := x0 + (x1 - x0) * k / n
		_box("dark_steel", mx - 0.04, mx + 0.04, y0, y1, z - 0.05, z + 0.05)
	_box("dark_steel", x0, x1, y0 + 2.2 - 0.03, y0 + 2.2 + 0.03, z - 0.04, z + 0.04)
	_box("sill_out", x0 - 0.05, x1 + 0.05, y0 - 0.06, y0 + 0.012, -0.1, T + 0.05)
	_col(x0, x1, y0, y1, z - 0.03, z + 0.03)


## The lounge's glazed door, its two leaves slid open behind the wall's inner face (one walks in).
func _glazed_door(g: Array) -> void:
	var x0: float = g[0]
	var x1: float = g[1]
	var y1: float = g[3]
	for e: Array in [[x0 - 0.06, x0 + 0.02, 0.0, y1 + 0.06], [x1 - 0.02, x1 + 0.06, 0.0, y1 + 0.06],
			[x0, x1, y1 - 0.02, y1 + 0.06]]:
		_box("dark_steel", e[0], e[1], e[2], e[3], -0.03, T + 0.03)
	var w := (x1 - x0) * 0.5
	for leaf: Array in [[x0 - w + 0.05, x0 + 0.05], [x1 - 0.05, x1 + w - 0.05]]:
		_box("glass", leaf[0], leaf[1], 0.02, y1 - 0.02, T + 0.04, T + 0.05)
		_box("dark_steel", leaf[0], leaf[1], 0.02, 0.1, T + 0.03, T + 0.06)
		_box("dark_steel", leaf[0], leaf[1], y1 - 0.1, y1 - 0.02, T + 0.03, T + 0.06)
	_label("ACCUEIL", Transform3D(Basis(Vector3.UP, PI), Vector3((x0 + x1) * 0.5, y1 + 0.3, -0.02)), 32, 0.005,
			Color(0.95, 0.95, 0.95))


## A barred window in the west wall's opening g ([x0, x1, y0, y1]): clear glass in a dark frame, steel bars in front of
## it (a grille on a frame fixed to the wall), a sill.
func _barred_window(g: Array) -> void:
	var x0: float = g[0]
	var x1: float = g[1]
	var y0: float = g[2]
	var y1: float = g[3]
	var z := T * 0.5
	var gx0 := x0 + 0.01                         # (1 cm inside the opening: not in its reveals' planes)
	var gx1 := x1 - 0.01
	var gy0 := y0 + 0.01
	var gy1 := y1 - 0.01
	_box("glass", gx0, gx1, gy0, gy1, z - 0.006, z + 0.006)
	for e: Array in [[gx0, gx0 + 0.07, gy0, gy1], [gx1 - 0.07, gx1, gy0, gy1], [gx0, gx1, gy0, gy0 + 0.07],
			[gx0, gx1, gy1 - 0.07, gy1]]:
		_box("dark_steel", e[0], e[1], e[2], e[3], z - 0.04, z + 0.04)
	_box("dark_steel", (x0 + x1) * 0.5 - 0.035, (x0 + x1) * 0.5 + 0.035, y0, y1, z - 0.04, z + 0.04)
	_col(x0, x1, y0, y1, z - 0.03, z + 0.03)
	# the grille: a frame on the wall's face, bars every 0.13 m, two cross bars
	_box("dark_steel", x0 - 0.08, x1 + 0.08, y0 - 0.08, y0, -0.07, 0.0)
	_box("dark_steel", x0 - 0.08, x1 + 0.08, y1, y1 + 0.08, -0.07, 0.0)
	_box("dark_steel", x0 - 0.08, x0, y0, y1, -0.07, 0.0)
	_box("dark_steel", x1, x1 + 0.08, y0, y1, -0.07, 0.0)
	var n := int((x1 - x0) / 0.13)
	for k in range(1, n):
		var bx := x0 + (x1 - x0) * k / n
		_cyl("dark_steel", Vector3(bx, y0, -0.04), 0.012, y1 - y0, 6)
	for cy: float in [y0 + (y1 - y0) * 0.33, y0 + (y1 - y0) * 0.66]:
		_box("dark_steel", x0, x1, cy - 0.02, cy + 0.02, -0.06, -0.02)
	_box("sill_out", x0 - 0.12, x1 + 0.12, y0 - 0.16, y0 - 0.08, -0.14, 0.0)


## The yard's furniture: the dumpster by the small building.
func _yard(ground: Callable) -> void:
	var y: float = float(ground.call(3.3, 19.6)) + TAR_UP
	_box("dumpster", 2.2, 4.4, y, y + 1.25, 18.9, 20.3)
	_box("dumpster_lid", 2.15, 4.45, y + 1.25, y + 1.33, 18.85, 20.35, Vector3(0.05, 0, 0))
	_col(2.2, 4.4, y, y + 1.3, 18.9, 20.3)


## The shop's logo board (its own design): a navy board in a yellow frame, LOSPLATOS in big cream letters over a red
## ribbon with CUSTOM; `xf` its middle (its text towards +z of `xf`), `w` x `h` m.
func _logo(xf: Transform3D, w: float, h: float) -> void:
	var b := xf.basis
	var o := xf.origin
	var hw := w * 0.5
	var hh := h * 0.5
	_box_xf("navy", xf, Vector3(w, h, 0.08), Vector3(0, 0, 0))
	_box_xf("yellow", xf, Vector3(w + 0.16, 0.08, 0.1), Vector3(0, hh + 0.04, 0.0))
	_box_xf("yellow", xf, Vector3(w + 0.16, 0.08, 0.1), Vector3(0, -hh - 0.04, 0.0))
	_box_xf("yellow", xf, Vector3(0.08, h, 0.1), Vector3(-hw - 0.04, 0, 0.0))
	_box_xf("yellow", xf, Vector3(0.08, h, 0.1), Vector3(hw + 0.04, 0, 0.0))
	_box_xf("red", xf, Vector3(w * 0.56, h * 0.26, 0.02), Vector3(0, -h * 0.26, 0.05))
	_label("LOSPLATOS", Transform3D(b, o + b * Vector3(0, h * 0.13, 0.06)), 96, h * 0.0052, Color("#fff3d6"),
			RED.darkened(0.3), 18)
	_label("CUSTOM", Transform3D(b, o + b * Vector3(0, -h * 0.26, 0.065)), 64, h * 0.0034, YELLOW)


## A sign on its pole at `p` (x z; its foot on `ground`), both faces towards the road's two ways: LOSPLATOS CUSTOM in
## neon over the services, bulbs round it.
func _pole_sign(p: Vector3, ground: Callable) -> void:
	p.y = ground.call(p.x, p.z)
	_cyl("dark_steel", p - Vector3(0, 0.4, 0), 0.14, 7.2, 12)
	_col(p.x - 0.15, p.x + 0.15, p.y, p.y + 6.8, p.z - 0.15, p.z + 0.15)
	var c := p + Vector3(0, 5.8, 0)
	var w := 4.6
	var h := 2.0
	for side: float in [1.0, -1.0]:
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 if side > 0.0 else -PI * 0.5), c)
		if side > 0.0:
			_box_xf("navy", xf, Vector3(w, h, 0.3), Vector3.ZERO)     # (the board once: both its faces)
		var b := xf.basis
		_label("LOSPLATOS", Transform3D(b, c + b * Vector3(0, 0.38, 0.16)), 96, 0.0074, Color(1.6, 0.5, 0.55),
				Color(0.3, 0.02, 0.05), 10)
		_label("CUSTOM", Transform3D(b, c + b * Vector3(0, -0.22, 0.16)), 80, 0.0068, Color(1.5, 1.2, 0.45),
				Color(0.25, 0.15, 0.0), 8)
		_label("24H · RÉPARATION · PEINTURE", Transform3D(b, c + b * Vector3(0, -0.7, 0.16)), 40, 0.0052,
				Color(0.95, 0.95, 1.0))
		var n := 16
		for k in n:
			var t := (k + 0.5) / n
			for y: float in [h * 0.5 - 0.1, -h * 0.5 + 0.1]:
				_ball("bulb", c + b * Vector3(-w * 0.5 + w * t, y, 0.17), Vector3(0.045, 0.045, 0.045))
		for k in 5:
			var t := (k + 0.5) / 5.0
			for x: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
				_ball("bulb", c + b * Vector3(x, -h * 0.5 + h * t, 0.17), Vector3(0.045, 0.045, 0.045))


# ---------------------------------------------------------------- inside

func _hall() -> void:
	var x0 := HALL_X + T
	var x1 := L - T
	var z0 := T
	var z1 := W - T
	# the floor's concrete, the bay's yellow lines and the arrows either side of it
	_box("concrete_floor", x0, x1, 0.0, 0.004, z0, z1)
	var bx0 := BAY.x - BAY_SIZE.x * 0.5
	var bx1 := BAY.x + BAY_SIZE.x * 0.5
	var bz0 := BAY.z - BAY_SIZE.y * 0.5
	var bz1 := BAY.z + BAY_SIZE.y * 0.5
	for ln: Array in [[bx0, bx0 + 0.12, bz0, bz1], [bx1 - 0.12, bx1, bz0, bz1], [bx0, bx1, bz1 - 0.12, bz1]]:
		_box("yellow", ln[0], ln[1], 0.004, 0.014, ln[2], ln[3])
	for k in 6:
		var zz := bz0 + 0.3 + k * 0.5
		_box("yellow", bx0 - 0.5, bx0 - 0.15, 0.004, 0.014, zz, zz + 0.18, Vector3(0, 0.6, 0))
		_box("yellow", bx1 + 0.15, bx1 + 0.5, 0.004, 0.014, zz, zz + 0.18, Vector3(0, -0.6, 0))
	# the walls' lining: cream blocks over a yellow band, blue steel columns, the beams and a duct under the roof
	var d := 0.012
	var w0: Array = BAR_WINDOWS[0]
	var w1: Array = BAR_WINDOWS[1]
	for s: Array in [[x0, w0[0], z0, z0 + d], [w0[1], DOOR.x - 0.12, z0, z0 + d], [DOOR.y + 0.12, w1[0], z0, z0 + d],
			[w1[1], x1, z0, z0 + d], [x0, x1, z1 - d, z1], [x1 - d, x1, z0, z1], [x0, x0 + d, z0, PASS_Z.x - 0.06],
			[x0, x0 + d, PASS_Z.y + 0.06, z1]]:
		_box("yellow_band", s[0], s[1], 0.0, 1.15, s[2], s[3])
		_box("blocks_in", s[0], s[1], 1.15, H, s[2], s[3])
	for w: Array in BAR_WINDOWS:
		_box("yellow_band", w[0], w[1], 0.0, 1.15, z0, z0 + d)
		_box("blocks_in", w[0], w[1], 1.15, w[2], z0, z0 + d)
		_box("blocks_in", w[0], w[1], w[3], H, z0, z0 + d)
	_box("blocks_in", x0, x0 + d, 2.26, H, PASS_Z.x - 0.06, PASS_Z.y + 0.06)
	for e: Array in [[PASS_Z.x - 0.06, PASS_Z.x, 0.0, 2.26], [PASS_Z.y, PASS_Z.y + 0.06, 0.0, 2.26],
			[PASS_Z.x, PASS_Z.y, 2.2, 2.26]]:
		_box("dark_steel", x0, x0 + 0.02, e[2], e[3], e[0], e[1])
	_box("blocks_in", DOOR.x - 0.12, DOOR.y + 0.12, DOOR.z + 0.6, H, z0, z0 + d)       # over the door's housing
	for k in 5:
		var cx := x0 + 0.2 + k * (x1 - x0 - 0.4) / 4.0
		for cz: float in [z0, z1 - 0.3]:
			if cz == z0 and ((cx > DOOR.x - 0.5 and cx < DOOR.y + 0.5) or (cx > w0[0] - 0.3 and cx < w0[1] + 0.3)
					or (cx > w1[0] - 0.3 and cx < w1[1] + 0.3)):
				continue
			_box("blue_steel", cx - 0.15, cx + 0.15, 0.0, H, cz, cz + 0.3)
		_box("teal_steel", cx - 0.12, cx + 0.12, H - 0.5, H, z0, z1)
	_rod("duct", Vector3(x0, H - 0.75, 4.2), Vector3(x1, H - 0.75, 4.2), 0.28)
	_rod("duct", Vector3(x0, H - 0.9, 12.6), Vector3(x1, H - 0.9, 12.6), 0.14)
	# the logo on the back wall, facing the door
	_logo(Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(BAY.x, 3.2, z1 - 0.06)), 7.0, 1.8)
	# made-up brands' posters and flags on the walls
	var posters := [["PLATEAU OIL", Color("#1f5fa8"), Color.WHITE], ["SACLAY TYRES", Color("#202020"), YELLOW],
			["ORSAY MOTORS", Color("#b3202a"), Color.WHITE], ["YVETTE PARTS", Color("#e8e2d0"), Color("#1f5fa8")],
			["X-RACING", Color("#f2c230"), Color("#202020")]]
	for k in posters.size():
		var px := x0 + 1.2 + k * 2.2
		if px > DOOR.x - 1.0:
			px += 7.0
		var po: Array = posters[k]
		_poster(Vector3(px, 2.6, z1 - 0.02), po[0], po[1], po[2])
	_workbench()
	_stock()
	_lamps()
	# under the sawtooth: its trusses' bottom chords and the glazed faces' light
	var tw := L / TEETH
	for k in range(1, TEETH):
		var tx := k * tw
		if tx > x0:
			_box("teal_steel", tx - 0.12, tx, H - 0.35, H, z0, z1)


## A poster on the back wall at `p` (its middle): a board of colour `bg` with `text` in `fg`.
func _poster(p: Vector3, text: String, bg: Color, fg: Color) -> void:
	var name := "poster_%s" % text.to_lower().replace(" ", "_").replace("-", "_")
	_mats[name] = _plain_mat(bg, 0.7)
	_box(name, p.x - 0.75, p.x + 0.75, p.y - 0.5, p.y + 0.5, p.z - 0.015, p.z)
	_label(text, Transform3D(Basis(Vector3.UP, PI), p + Vector3(0, 0, -0.02)), 40, 0.0045, fg)


## Along the north wall: the workbench under a pegboard of tools, a vice, the red tool chest, an engine on its stand.
func _workbench() -> void:
	var x := L - T
	var z0 := 1.6
	var z1 := 6.4
	_box("wood", x - 0.8, x, 0.9, 0.96, z0, z1)
	for zz: float in [z0 + 0.05, z1 - 0.1]:
		for xx: float in [x - 0.75, x - 0.1]:
			_box("dark_steel", xx, xx + 0.05, 0.0, 0.9, zz, zz + 0.05)
	_box("dark_steel", x - 0.78, x - 0.02, 0.25, 0.28, z0 + 0.05, z1 - 0.05)
	_col(x - 0.8, x, 0.0, 0.96, z0, z1)
	_box("pegboard", x - 0.03, x, 1.2, 2.5, z0, z1)
	for k in 14:
		var tz := z0 + 0.25 + k * 0.32
		var ty := 1.5 + float(k % 3) * 0.3
		_box("dark_steel", x - 0.06, x - 0.03, ty, ty + 0.25 + float(k % 2) * 0.12, tz, tz + 0.05)
	_box("dark_steel", x - 0.5, x - 0.2, 0.96, 1.14, z0 + 0.3, z0 + 0.5)                # the vice
	_box("red", x - 0.7, x - 0.06, 0.0, 1.05, 7.0, 8.0)                                   # the tool chest
	for k in 5:
		_box("steel", x - 0.72, x - 0.68, 0.15 + k * 0.18, 0.18 + k * 0.18, 7.1, 7.9)
	_col(x - 0.72, x, 0.0, 1.05, 7.0, 8.0)
	_box("engine", x - 2.6, x - 1.8, 0.6, 1.2, 9.8, 10.8)
	_box("dark_steel", x - 2.3, x - 2.1, 0.0, 0.6, 10.2, 10.4)
	_cyl("dark_steel", Vector3(x - 2.2, 0.0, 10.3), 0.35, 0.05, 12)
	_col(x - 2.6, x - 1.8, 0.0, 1.2, 9.8, 10.8)


## Along the partition: stacks of tyres, oil drums, the compressor, a shelf of boxes.
func _stock() -> void:
	var x := HALL_X + T
	for s: Vector3 in [Vector3(x + 0.6, 0, 2.0), Vector3(x + 0.6, 0, 3.4), Vector3(x + 1.9, 0, 2.6)]:
		var n := 3 + int(_rng.randi() % 3)
		for k in n:
			_cyl("tyre", s + Vector3(0, k * 0.26, 0), 0.45, 0.24, 20)
			_cyl("rim", s + Vector3(0, k * 0.26 + 0.24, 0), 0.22, 0.012, 14)
		_col(s.x - 0.45, s.x + 0.45, 0.0, n * 0.26, s.z - 0.45, s.z + 0.45)
	for k in 4:
		var dp := Vector3(x + 0.5 + (k % 2) * 0.65, 0, 11.0 + floorf(k / 2.0) * 0.65)
		_cyl("drum_red" if k % 3 != 1 else "drum_blue", dp, 0.29, 0.9, 16)
		_cyl("dark_steel", dp + Vector3(0, 0.3, 0), 0.3, 0.03, 16)
		_cyl("dark_steel", dp + Vector3(0, 0.6, 0), 0.3, 0.03, 16)
	_col(x + 0.2, x + 1.45, 0.0, 0.9, 10.7, 12.25)
	# the compressor: a tank on its side, the motor on it
	_rod("drum_red", Vector3(x + 0.6, 0.45, 8.4), Vector3(x + 0.6, 0.45, 10.0), 0.35)
	_box("dark_steel", x + 0.4, x + 0.8, 0.8, 1.15, 8.8, 9.4)
	_col(x + 0.25, x + 0.95, 0.0, 1.15, 8.3, 10.1)
	# the shelf on the back wall's corner
	var sz := W - T
	_box("dark_steel", x + 0.0, x + 2.6, 0.0, 2.4, sz - 0.6, sz - 0.56)
	for y: float in [0.3, 1.0, 1.7, 2.4]:
		_box("wood", x, x + 2.6, y, y + 0.04, sz - 0.6, sz)
		for k in 4:
			var bxx := x + 0.15 + k * 0.62
			_box("box" if k % 2 == 0 else "box_b", bxx, bxx + 0.45, y + 0.04, y + 0.36, sz - 0.5, sz - 0.1)
	_col(x, x + 2.6, 0.0, 2.45, sz - 0.6, sz)


## Two work lamps on yellow tripods by the bay.
func _lamps() -> void:
	for p: Vector3 in [Vector3(BAY.x - 3.0, 0, BAY.z + 2.4), Vector3(BAY.x + 3.0, 0, BAY.z - 2.0)]:
		for k in 3:
			var a := k * TAU / 3.0
			_rod("yellow", p + Vector3(cos(a), 0, sin(a)) * 0.45, p + Vector3(0, 1.1, 0), 0.02)
		_rod("yellow", p + Vector3(0, 1.1, 0), p + Vector3(0, 2.3, 0), 0.025)
		_box("dark_steel", p.x - 0.3, p.x + 0.3, 2.3, 2.6, p.z - 0.1, p.z + 0.1)
		_box("emit", p.x - 0.26, p.x + 0.26, 2.33, 2.57, p.z - 0.11, p.z - 0.1)
		_box("emit", p.x - 0.26, p.x + 0.26, 2.33, 2.57, p.z + 0.1, p.z + 0.11)


## The customers' lounge (behind the lounge's window): dark tiles, warm grey walls, oak slats behind the counter and
## the logo, the counter, a leather sofa and an armchair round a low table on a rug, the TV, coffee, a rack of rims in
## the window, plants; recessed lights in its ceiling.
func _lounge() -> void:
	var x0 := T
	var x1 := HALL_X
	var z0 := T
	var z1 := LOUNGE_Z
	_box("lounge_floor", x0, x1, 0.0, 0.006, z0, z1)
	var d := 0.012
	var lg0: float = LOUNGE_GLASS[0]
	var lg1: float = LOUNGE_GLASS[1]
	var ld0: float = LOUNGE_DOOR[0]
	var ld1: float = LOUNGE_DOOR[1]
	for s: Array in [[x0, lg0, z0, z0 + d, 0.0, LOUNGE_CEILING], [lg0, lg1, z0, z0 + d, 0.0, LOUNGE_GLASS[2]],
			[lg1, ld0, z0, z0 + d, 0.0, LOUNGE_CEILING], [ld1, x1, z0, z0 + d, 0.0, LOUNGE_CEILING],
			[ld0, ld1, z0, z0 + d, LOUNGE_DOOR[3], LOUNGE_CEILING], [x0, x0 + d, z0, z1, 0.0, LOUNGE_CEILING],
			[x0, x1, z1 - d, z1, 0.0, LOUNGE_CEILING], [x1 - d, x1, z0, PASS_Z.x, 0.0, LOUNGE_CEILING],
			[x1 - d, x1, PASS_Z.y, z1, 0.0, LOUNGE_CEILING], [x1 - d, x1, PASS_Z.x, PASS_Z.y, 2.2, LOUNGE_CEILING]]:
		_box("lounge_wall", s[0], s[1], s[4], s[5], s[2], s[3])
	for s: Array in [[x0, lg0, z0], [lg1, ld0, z0], [ld1, x1, z0], [x0, x1, z1 - 0.024]]:
		_box("dark_steel", s[0], s[1], 0.0, 0.08, s[2], s[2] + 0.024)
	# the oak slats behind the counter, the logo on them
	var n := 34
	for k in n:
		var sx := 5.2 + k * (x1 - 0.3 - 5.2) / n
		_box("oak", sx, sx + 0.08, 0.0, LOUNGE_CEILING, z1 - 0.06, z1 - d)
	_logo(Transform3D(Basis(Vector3.UP, PI), Vector3(8.1, 2.45, z1 - 0.12)), 3.6, 0.9)
	# the counter
	var cz0 := 3.7
	var cz1 := 4.35
	_box("navy", 6.0, 9.4, 0.0, 1.0, cz0, cz1)
	_box("yellow", 6.0, 9.4, 0.42, 0.48, cz0 - 0.005, cz0)
	_box("counter_top", 5.95, 9.45, 1.0, 1.06, cz0 - 0.05, cz1 + 0.02)
	_col(6.0, 9.4, 0.0, 1.06, cz0, cz1)
	_box("screen", 7.9, 8.4, 1.06, 1.42, cz1 - 0.25, cz1 - 0.21, Vector3(-0.15, 0, 0))
	_box("dark_steel", 8.12, 8.18, 1.06, 1.2, cz1 - 0.19, cz1 - 0.15)
	_box("black", 6.6, 7.05, 1.06, 1.09, cz0 + 0.15, cz0 + 0.45)
	# the sofa along the south wall, an armchair, the low table on a rug
	_box("rug_lounge", 1.1, 4.3, 0.006, 0.014, 1.5, 5.0)
	_box("leather_brown", x0 + 0.05, x0 + 0.95, 0.0, 0.45, 1.6, 4.8)
	_box("leather_brown", x0 + 0.05, x0 + 0.3, 0.45, 0.95, 1.6, 4.8)
	_box("leather_brown", x0 + 0.05, x0 + 0.95, 0.45, 0.7, 1.6, 1.82)
	_box("leather_brown", x0 + 0.05, x0 + 0.95, 0.45, 0.7, 4.58, 4.8)
	for cz: Array in [[1.84, 3.18], [3.22, 4.56]]:
		_box("leather_dark", x0 + 0.3, x0 + 0.93, 0.45, 0.55, cz[0], cz[1])
	_col(x0, x0 + 0.95, 0.0, 0.95, 1.6, 4.8)
	_box("leather_brown", 4.0, 4.85, 0.0, 0.45, 2.7, 3.55)
	_box("leather_brown", 4.6, 4.85, 0.45, 0.95, 2.7, 3.55)
	_box("leather_brown", 4.0, 4.6, 0.45, 0.68, 2.7, 2.9)
	_box("leather_brown", 4.0, 4.6, 0.45, 0.68, 3.35, 3.55)
	_col(4.0, 4.85, 0.0, 0.95, 2.7, 3.55)
	_box("oak", 1.9, 3.1, 0.36, 0.42, 2.6, 3.6)
	for c: Vector2 in [Vector2(1.95, 2.65), Vector2(3.05, 2.65), Vector2(1.95, 3.55), Vector2(3.05, 3.55)]:
		_box("dark_steel", c.x - 0.02, c.x + 0.02, 0.0, 0.36, c.y - 0.02, c.y + 0.02)
	_col(1.9, 3.1, 0.0, 0.42, 2.6, 3.6)
	_box("black", 2.2, 2.6, 0.42, 0.44, 2.9, 3.2)
	_cyl("ceramic", Vector3(2.8, 0.42, 3.3), 0.045, 0.1, 12)
	# the TV over the sofa
	_box("black", x0 + d, x0 + 0.06, 1.55, 2.4, 2.4, 3.95)
	_box("screen_on", x0 + 0.066, x0 + 0.068, 1.58, 2.37, 2.43, 3.92)
	# coffee on the back wall
	_box("lounge_cabinet", 2.2, 3.4, 0.0, 0.9, z1 - 0.6, z1 - d)
	_col(2.2, 3.4, 0.0, 0.9, z1 - 0.6, z1)
	_box("black", 2.4, 2.8, 0.9, 1.35, z1 - 0.45, z1 - 0.1)
	_box("steel", 2.45, 2.75, 1.05, 1.1, z1 - 0.47, z1 - 0.45)
	for k in 3:
		_cyl("ceramic", Vector3(2.95 + 0.12 * k, 0.9, z1 - 0.3), 0.04, 0.09, 12)
	# a rack of rims in the window
	_box("dark_steel", 4.6, 6.4, 0.0, 0.05, 0.55, 0.9)
	for k in 3:
		var rx := 4.9 + k * 0.6
		_box("dark_steel", rx - 0.02, rx + 0.02, 0.0, 0.9, 0.7, 0.74)
		_rod("chrome", Vector3(rx, 0.55, 0.62), Vector3(rx, 0.55, 0.84), 0.3)
		_rod("tyre", Vector3(rx, 0.55, 0.6), Vector3(rx, 0.55, 0.86), 0.36)
	# plants
	for pp: Vector3 in [Vector3(0.75, 0.0, 6.6), Vector3(5.6, 0.0, 6.6), Vector3(10.4, 0.0, 0.8)]:
		_cyl("pot", pp, 0.24, 0.5, 14, 0.2)
		for k in 6:
			var a := k * TAU / 6.0
			_ball("plant", pp + Vector3(cos(a) * 0.14, 0.75 + 0.12 * (k % 3), sin(a) * 0.14), Vector3(0.18, 0.32, 0.18))
		_col(pp.x - 0.24, pp.x + 0.24, 0.0, 0.5, pp.z - 0.24, pp.z + 0.24)
	# the ceiling's lights
	for lc: Vector3 in [Vector3(2.6, 0, 2.2), Vector3(2.6, 0, 5.0), Vector3(6.2, 0, 2.2), Vector3(8.2, 0, 4.4), Vector3(9.8, 0, 2.2)]:
		_box("emit", lc.x - 0.3, lc.x + 0.3, LOUNGE_CEILING - 0.01, LOUNGE_CEILING, lc.z - 0.3, lc.z + 0.3)
	for lc: Vector3 in [Vector3(2.8, LOUNGE_CEILING - 0.3, 3.4), Vector3(8.0, LOUNGE_CEILING - 0.3, 3.6)]:
		var l := OmniLight3D.new()
		l.position = lc
		l.light_color = Color(1.0, 0.88, 0.74)
		l.light_energy = 1.0
		l.omni_range = 6.0
		l.omni_attenuation = 1.2
		_root.add_child(l)
	var probe := ReflectionProbe.new()
	probe.name = "LoungeProbe"
	probe.size = Vector3(x1 - x0 + 0.2, LOUNGE_CEILING + 0.2, z1 - z0 + 0.2)
	probe.position = Vector3((x0 + x1) * 0.5, LOUNGE_CEILING * 0.5, (z0 + z1) * 0.5)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.9, 0.84, 0.76)
	probe.ambient_color_energy = 0.5
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_root.add_child(probe)


func _lights() -> void:
	# the fluorescent tubes under the beams
	var x0 := HALL_X + T
	var x1 := L - T
	var tubes: Array[Vector3] = []
	for i in 3:
		for j in 3:
			tubes.append(Vector3(x0 + 2.8 + i * (x1 - x0 - 5.6) / 2.0, H - 1.1, 3.4 + j * 4.6))
	for t: Vector3 in tubes:
		_box("dark_steel", t.x - 0.8, t.x + 0.8, t.y + 0.06, t.y + 0.1, t.z - 0.12, t.z + 0.12)
		_box("emit", t.x - 0.75, t.x + 0.75, t.y, t.y + 0.06, t.z - 0.05, t.z + 0.05)
		_rod("dark_steel", t + Vector3(-0.6, 0.1, 0), t + Vector3(-0.6, 1.1 - 0.5, 0), 0.006)
		_rod("dark_steel", t + Vector3(0.6, 0.1, 0), t + Vector3(0.6, 1.1 - 0.5, 0), 0.006)
	var cool := Color(0.92, 0.97, 1.0)
	for k in tubes.size():
		if k % 2 == 0:
			var l := OmniLight3D.new()
			l.position = tubes[k] - Vector3(0, 0.3, 0)
			l.light_color = cool
			l.light_energy = 1.1
			l.omni_range = 9.0
			l.omni_attenuation = 1.1
			l.shadow_enabled = k == 4
			_root.add_child(l)
	# the work lamps' beams on the bay
	for p: Vector3 in [Vector3(BAY.x - 3.0, 2.45, BAY.z + 2.4), Vector3(BAY.x + 3.0, 2.45, BAY.z - 2.0)]:
		var s := SpotLight3D.new()
		s.transform = Transform3D(Basis.looking_at(Vector3(BAY.x, 0.6, BAY.z) - p, Vector3.UP), p)
		s.light_color = Color(1.0, 0.93, 0.8)
		s.light_energy = 2.2
		s.spot_range = 8.0
		s.spot_angle = 40.0
		_root.add_child(s)
	# the hall's own ambient light and reflections (no sky inside)
	var probe := ReflectionProbe.new()
	probe.name = "Probe"
	probe.size = Vector3(x1 - x0 + 0.2, H + RISE + 0.2, W - 2.0 * T + 0.2)
	probe.position = Vector3((x0 + x1) * 0.5, (H + RISE) * 0.5, W * 0.5)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.86, 0.84, 0.8)
	probe.ambient_color_energy = 0.45
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_root.add_child(probe)


# ---------------------------------------------------------------- mesh building

func _tool(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]


func _box(mat: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var xf := Transform3D(Basis.from_euler(rot), Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5 + _off)
	_tool(mat).append_from(m, 0, xf)


## A box of `size` at `at` in frame `xf`.
func _box_xf(mat: String, xf: Transform3D, size: Vector3, at: Vector3) -> void:
	var m := BoxMesh.new()
	m.size = size
	_tool(mat).append_from(m, 0, Transform3D(xf.basis, xf * at))


func _cyl(mat: String, p: Vector3, r: float, h: float, seg := 16, top := -1.0) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top < 0.0 else top
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_tool(mat).append_from(m, 0, Transform3D(Basis.IDENTITY, p + _off + Vector3(0, h * 0.5, 0)))


func _rod(mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = length
	m.radial_segments = 10
	m.rings = 1
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_tool(mat).append_from(m, 0, Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5 + _off))


func _ball(mat: String, c: Vector3, r: Vector3) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 8
	m.rings = 4
	_tool(mat).append_from(m, 0, Transform3D(Basis.from_scale(r), c + _off))


func _col(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var s := BoxShape3D.new()
	s.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5 + _off
	_body.add_child(cs)


## A collision box of `size` at frame `xf`'s origin.
func _col_xf(xf: Transform3D, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	_body.add_child(cs)


## A text at `xf` (read from its +z side).
func _label(text: String, xf: Transform3D, size: int, pixel: float, colour: Color, outline := Color.BLACK,
		outline_px := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = outline_px
	l.outline_modulate = outline
	l.shaded = false
	l.double_sided = false
	l.transform = xf
	l.visibility_range_end = 260.0
	_root.add_child(l)
	return l


# ---------------------------------------------------------------- materials

func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: StandardMaterial3D
	match name:
		"blocks_out": m = _textured("blocks_out", Vector3(1.0 / 1.6, 1.0 / 1.6, 1.0 / 1.6), 0.95)
		"blocks_in": m = _textured("blocks_in", Vector3(1.0 / 1.6, 1.0 / 1.6, 1.0 / 1.6), 0.9)
		"concrete_floor": m = _textured("floor", Vector3(1.0 / 6.0, 1.0, 1.0 / 6.0), 0.75)
		"concrete":
			m = _textured("concrete", Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), 0.95)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"door": m = _textured("slats", Vector3(1.0 / 2.0, 1.0 / 0.275, 1.0), 0.5)
		"cladding", "cladding_gable":
			m = _textured("cladding", Vector3(1.0 / 2.0, 1.0 / 2.0, 1.0 / 2.0), 0.55)
			m.metallic = 0.45
			m.uv1_triplanar_sharpness = 24.0
		"roof_metal":
			m = _textured("roof_ribs", Vector3(1.0 / 2.0, 1.0 / 2.0, 1.0 / 2.0), 0.5)
			m.metallic = 0.45
			m.uv1_triplanar_sharpness = 24.0
			m.albedo_color = Color(1.2, 1.2, 1.2)
		"pavers":
			m = _textured("pavers", Vector3(1.0 / 1.6, 1.0 / 1.6, 1.0 / 1.6), 0.9)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"drive":
			m = _textured("drive", Vector3(1.0 / 4.0, 1.0 / 4.0, 1.0 / 4.0), 0.85)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"kerb", "kerb_top", "kerb_face", "gutter", "yellow_paint_floor":
			var c := {"kerb": "#b9b6ae", "kerb_top": "#e3dfd6", "kerb_face": "#c9c3b7", "gutter": "#8f8c86",
					"yellow_paint_floor": "#e9b934"}
			m = _plain_mat(Color(c[name]), 0.8)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"asphalt":
			m = _textured("asphalt", Vector3(1.0 / 4.0, 1.0 / 4.0, 1.0 / 4.0), 0.9)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"white_paint":
			m = _plain_mat(Color("#eeeeea"), 0.7)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"lounge_floor": m = _textured("tiles", Vector3(1.0 / 1.2, 1.0, 1.0 / 1.2), 0.25)
		"lounge_wall": m = _plain_mat(Color("#55585c"), 0.85)
		"lounge_ceiling": m = _plain_mat(Color("#e9e6df"), 0.9)
		"lounge_cabinet": m = _plain_mat(Color("#2a2c30"), 0.5)
		"oak": m = _plain_mat(Color("#a7774a"), 0.6)
		"counter_top": m = _plain_mat(Color("#f2f0ea"), 0.25)
		"leather_brown": m = _plain_mat(Color("#6b3f24"), 0.45)
		"leather_dark": m = _plain_mat(Color("#55311c"), 0.5)
		"rug_lounge": m = _plain_mat(Color("#2f3a4c"), 1.0)
		"ceramic": m = _plain_mat(Color("#f4f4f2"), 0.2)
		"black": m = _plain_mat(Color("#141518"), 0.4)
		"screen": m = _plain_mat(Color("#0d0f12"), 0.2)
		"pot": m = _plain_mat(Color("#3c3f44"), 0.6)
		"plant": m = _plain_mat(Color("#3f7a3a"), 0.8)
		"chrome": m = _metal(Color("#d7dce2"), 0.15)
		"screen_on":
			m = _plain_mat(Color(0.1, 0.2, 0.35), 0.3)
			m.emission_enabled = true
			m.emission = Color(0.25, 0.45, 0.8)
			m.emission_energy_multiplier = 1.4
		"glass":
			m = _plain_mat(Color(0.75, 0.85, 0.9, 0.16), 0.05)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic_specular = 0.9
		"floor": m = _plain_mat(Color("#6f6d69"), 0.95)
		"roof": m = _plain_mat(Color("#8c8a86"), 0.95)
		"coping": m = _plain_mat(Color("#d9d4c8"), 0.8)
		"unit": m = _plain_mat(Color("#b9bcbf"), 0.6)
		"grille": m = _plain_mat(Color("#55595e"), 0.7)
		"plinth": m = _plain_mat(Color("#55534f"), 0.9)
		"yellow_paint": m = _plain_mat(Color("#c9a63e"), 0.85)
		"navy_paint": m = _plain_mat(NAVY.lightened(0.05), 0.7)
		"yellow_band": m = _plain_mat(Color("#cfa93a"), 0.8)
		"red_paint": m = _plain_mat(RED, 0.6)
		"navy": m = _plain_mat(NAVY, 0.5)
		"yellow": m = _plain_mat(YELLOW, 0.5)
		"red": m = _plain_mat(RED, 0.45)
		"steel": m = _metal(Color("#b9bec4"), 0.3)
		"dark_steel": m = _metal(Color("#2b2e33"), 0.45)
		"blue_steel": m = _metal(Color("#2f5d8a"), 0.5)
		"teal_steel": m = _metal(Color("#2f6f6a"), 0.55)
		"duct": m = _metal(Color("#9aa0a6"), 0.4)
		"door_housing": m = _metal(Color("#3b4048"), 0.5)
		"door_out": m = _plain_mat(Color("#3e4650"), 0.6)
		"sill_out": m = _plain_mat(Color("#b8b2a6"), 0.8)
		"dumpster": m = _plain_mat(Color("#2e4d3a"), 0.7)
		"dumpster_lid": m = _plain_mat(Color("#1d2a22"), 0.6)
		"pegboard": m = _plain_mat(Color("#a8865a"), 0.85)
		"wood": m = _plain_mat(Color("#8a6844"), 0.8)
		"engine": m = _metal(Color("#4a4f55"), 0.45)
		"tyre": m = _plain_mat(Color("#1a1a1b"), 0.85)
		"rim": m = _metal(Color("#8f959b"), 0.35)
		"drum_red": m = _plain_mat(Color("#a8282c"), 0.55)
		"drum_blue": m = _plain_mat(Color("#25508f"), 0.55)
		"box": m = _plain_mat(Color("#b48a5a"), 0.9)
		"box_b": m = _plain_mat(Color("#c9a77a"), 0.9)
		"glass_dark":
			m = _plain_mat(Color("#20262d"), 0.12)
			m.metallic_specular = 0.8
		"emit", "bulb":
			m = _plain_mat(Color(1.0, 0.97, 0.9), 0.5)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.95, 0.85) if name == "emit" else Color(1.0, 0.85, 0.45)
			m.emission_energy_multiplier = 3.0 if name == "emit" else 4.0
		_:
			m = _plain_mat(Color("#ff00ff"), 1.0)
	_mats[name] = m
	return m


static func _plain_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := _plain_mat(c, rough)
	m.metallic = 0.7
	return m


static func _textured(tex: String, scale: Vector3, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = scale
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------- textures (drawn once a session)

static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var img: Image
		match name:
			"blocks_out": img = _blocks(Color("#a9a8a4"), Color("#86847f"), 11)
			"pavers": img = _blocks(Color("#b4b0a8"), Color("#8b8780"), 14)
			"drive": img = _noise(Color("#aaa69e"), 0.035, 15)
			"asphalt": img = _noise(Color("#4a4c50"), 0.05, 17)
			"cladding": img = _ribs(false)
			"roof_ribs": img = _ribs(true)
			"tiles": img = _tiles()
			"blocks_in": img = _blocks(Color("#e6e0d0"), Color("#b9b2a2"), 12)
			"floor": img = _floor()
			"concrete": img = _noise(Color("#a19d95"), 0.05, 13)
			_: img = _slats()
		img.generate_mipmaps()
		_textures[name] = ImageTexture.create_from_image(img)
	return _textures[name]


## Concrete blocks 0.4 x 0.2 m in running bond with their mortar (the texture spans 1.6 m).
static func _blocks(base: Color, mortar: Color, seed: int) -> Image:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bw := n / 4                         # 0.4 m
	var bh := n / 8                         # 0.2 m
	var shades := []
	for i in 64:
		shades.append(rng.randf_range(-0.04, 0.04))
	for y in n:
		var row := y / bh
		var shift := (bw / 2) * (row % 2)
		for x in n:
			var col := ((x + shift) % n) / bw
			var c := base
			var s: float = shades[(row * 4 + col) % 64]
			c = Color(c.r + s, c.g + s, c.b + s)
			var grain := sin(float(x) * 1.7 + float(y) * 2.3) * 0.012 + rng.randf_range(-0.015, 0.015)
			c = Color(c.r + grain, c.g + grain, c.b + grain)
			if y % bh < 3 or (x + shift) % bw < 3:
				c = mortar
			img.set_pixel(x, y, c)
	return img


## Workshop concrete: grey, mottled, with oil stains and a few saw cuts (the texture spans 6 m).
static func _floor() -> Image:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var stains := []
	for i in 18:
		stains.append([Vector2(rng.randf() * n, rng.randf() * n), rng.randf_range(20.0, 90.0), rng.randf_range(0.15, 0.45)])
	var base := Color("#5c5b58")
	for y in n:
		for x in n:
			var m := sin(float(x) * 0.013 + 1.3) * sin(float(y) * 0.017) * 0.03 + sin(float(x + y) * 0.061) * 0.012
			m += rng.randf_range(-0.02, 0.02)
			var c := Color(base.r + m, base.g + m, base.b + m)
			for s: Array in stains:
				var d := Vector2(x, y).distance_to(s[0]) / float(s[1])
				if d < 1.0:
					c = c.darkened(float(s[2]) * (1.0 - d * d))
			if x % 512 < 2 or y % 512 < 2:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	return img


static func _noise(base: Color, amount: float, seed: int) -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in n:
		for x in n:
			var m := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + m, base.g + m, base.b + m))
	return img


## Anthracite ribbed steel cladding: a trapezoidal rib every 0.25 m (the texture spans 2 m), across the image (`down`:
## along it: the roof's ribs run down its slopes).
static func _ribs(down: bool) -> Image:
	var w := 256 if not down else 16
	var h := 16 if not down else 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var base := Color("#3b3e43")
	for x in maxi(w, h):
		var t := fmod(float(x) / 32.0, 1.0)
		var s := 0.0
		if t < 0.15:
			s = 0.07
		elif t < 0.25:
			s = -0.05
		elif t > 0.9:
			s = 0.03
		for y in mini(w, h):
			if down:
				img.set_pixel(y, x, Color(base.r + s, base.g + s, base.b + s))
			else:
				img.set_pixel(x, y, Color(base.r + s, base.g + s, base.b + s))
	return img


## Large dark grey floor tiles 0.6 m with thin joints (the texture spans 1.2 m).
static func _tiles() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	var base := Color("#3d3f43")
	for y in n:
		for x in n:
			var m := rng.randf_range(-0.012, 0.012) + (0.015 if (x / 128 + y / 128) % 2 == 0 else 0.0)
			var c := Color(base.r + m, base.g + m, base.b + m)
			if x % 128 < 2 or y % 128 < 2:
				c = Color("#2a2b2e")
			img.set_pixel(x, y, c)
	return img


## The roll-up door's ribbed steel: horizontal ribs (one slat's height per texture repeat).
static func _slats() -> Image:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var base := Color("#7d8a99")
	for y in h:
		var t := float(y) / h
		var rib := sin(t * TAU * 2.0) * 0.07
		var edge := 0.18 if y < 4 or y > h - 5 else 0.0
		for x in w:
			var c := Color(base.r + rib, base.g + rib, base.b + rib).darkened(edge)
			img.set_pixel(x, y, c)
	return img
