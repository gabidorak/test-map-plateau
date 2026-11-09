extends RefCounted
## The basic studio of PTA Online's properties (scripts/online/properties.gd, data/properties.json "interior": "studio"),
## after Thomas's plan (ref/proprietes/PlanStudioBasique.jpg), built in the flat's own frame and given to the caller to
## place behind the building's real windows: the building's walls and window panes are drawn from the outside only,
## and its window frames are open (scripts/builder/logements_x_builder.gd), so through the studio's windows one sees
## the residence as it is.
## The frame: x along the facade (to the right looking out), y up from the floor, z into the building from the facade
## line. The main room is ROOM_W x (BACK - WALL_IN) m (the plan, seen from its window side, laid out roomy: wide
## passages, doors 1-1.6 m wide):
## - left, the sleeping corner: a double bed, its head against a beige wall and an upholstered headboard, a round white
##   bedside table and its lamp either side, an arched wardrobe in the front corner;
## - a full-height partition down the middle (open on the windows' side), the dark grey sofa against it, an arc floor
##   lamp over it, a patterned rug, the TV on the right wall over a floating shelf;
## - at the back right, the kitchen: white units, a black worktop, an oven under a hob, a sink and its tap, a
##   microwave, a cutting board, a patterned splashback, a wall cupboard over a light strip, two oak shelves with plants
##   and jars, a tall fridge column; a small oval bar table and two stools in front of it;
## - light oak parquet, white walls and skirting, two tall windows (white frames, glass, sills, radiators, linen
##   curtains drawn aside).
## Beside it (not on the plan, a studio needs them): the entrance hall (the flat's front door: leaving, a bench, hooks;
## with the garage option, the garage lift's steel doors: leaving by car) and the shower room (a shower, a WC, a basin
## under a mirror).
## Lights: the ceiling's, the lamps', the kitchen strip; a cool light in from each window by day.
## Collision (BUILDINGS): the floor, the ceiling, the walls, the furniture one walks into.
## The furniture is drawn piece by piece in its own coordinates, moved into place by `_off`.

const Layers = preload("res://scripts/physics_layers.gd")

const H := 2.7                              # m, floor to ceiling
const WALL_OUT := 0.03                      # m from the facade line to the front wall's outer face
const WALL_IN := 0.25                       # m from the facade line to the room's side of the front wall
const ROOM_W := 6.6                         # m, the main room's width
const BACK := 6.2                           # m from the facade line to the back wall
const HALL_X := 6.7                         # the hall and the shower room: from here...
const END_X := 9.2                          # ...to here
const SPLIT_Z := 2.9                        # the wall between the hall and the shower room
const PARTITION_X := 3.2
const PARTITION_Z := 1.3                    # the partition runs from here to the back wall
const WINDOW_X := 3.3                       # m from the room's left wall to the middle of its window pair
const DOORWAY := Vector3(0.4, 1.9, 2.3)     # the open doorway between the room and the hall: z from, z to, height
const DOOR_H := 2.2                         # m, the doors' height
const DOOR_Z := Vector2(0.45, 1.55)         # the flat's front door, in the hall's right wall
const LIFT_Z := Vector2(1.75, 2.7)          # the garage lift's doors beside it (with the garage option)
const SHOWER_DOOR := Vector2(7.1, 8.1)      # x of the shower room's door, in the hall's back wall
const SPAWN := Vector3(END_X - 0.75, 0.02, 1.0)    # where one comes in, facing the room
const EXIT := Vector3(END_X - 0.2, 1.0, 1.0)       # E by the front door: leave
const LIFT := Vector3(END_X - 0.2, 1.0, 2.225)     # E by the lift's doors: leave by car
const RUG := Rect2(4.28, 1.425, 1.4, 2.0)   # the rug, x z (its pattern laid on it exactly)
const SOFA_Z := 0.35                        # the sofa (drawn from z = 1.1 to 3.05) moved this far back
const TABLE := Vector3(5.1, 0.0, BACK - 2.0)   # the bar table's foot: beyond the sofa's end, 1 m from the worktop

var _st := {}                               # material name -> SurfaceTool
var _mats := {}                             # material name -> Material
var _body: StaticBody3D
var _root: Node3D
var _rng := RandomNumberGenerator.new()
var _off := Vector3.ZERO                    # added to everything drawn (a piece of furniture into its place)
var _garage := false

static var _textures := {}                  # name -> ImageTexture, made once a session


## The studio, its windows `windows` ([x0, x1, y0, y1] in its frame, frames included: the building's openings);
## `garage`: the garage option's lift in the hall.
## Meta on the node: "spawn" [Vector3, facing Vector3], "exit" Vector3, "lift" Vector3 (with the garage), "bounds"
## AABB (all in its frame).
func build(windows: Array, garage := false) -> Node3D:
	_rng.seed = 19
	_garage = garage
	_root = Node3D.new()
	_root.name = "Studio"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "property", "kind": "studio"})
	_root.add_child(_body)
	_shell(windows)
	for w: Array in windows:
		_window(w)
	_sleeping()
	_living()
	_kitchen()
	_hall()
	if garage:
		_lift()
	_shower_room()
	_lights(windows)
	for name: String in _st:
		var mi := MeshInstance3D.new()
		mi.name = "M_" + name
		mi.mesh = (_st[name] as SurfaceTool).commit()
		mi.material_override = _mat(name)
		if name in ["glass", "emit", "emit_cool"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
	_root.set_meta("spawn", [SPAWN, Vector3(-1.0, 0.0, 0.0)])
	_root.set_meta("exit", EXIT)
	if garage:
		_root.set_meta("lift", LIFT)
	_root.set_meta("bounds", AABB(Vector3(-0.2, -0.3, 0.0), Vector3(END_X + 0.4, H + 0.6, BACK + 0.3)))
	return _root


# ---------------------------------------------------------------- the shell

func _shell(windows: Array) -> void:
	# floors: parquet in the room and the hall, tiles in the shower room; the slab under them; the ceiling
	_box("parquet", -0.12, END_X + 0.1, -0.02, 0.0, WALL_OUT, BACK + 0.1)
	_box("tile_floor", HALL_X, END_X, 0.0, 0.006, SPLIT_Z + 0.1, BACK)
	_box("concrete", -0.12, END_X + 0.1, -0.25, -0.02, WALL_OUT, BACK + 0.1)
	_col(-0.12, END_X + 0.1, -0.25, 0.0, WALL_OUT, BACK + 0.1)
	_box("ceiling", -0.12, END_X + 0.1, H, H + 0.2, WALL_OUT, BACK + 0.1)
	_col(-0.12, END_X + 0.1, H, H + 0.2, WALL_OUT, BACK + 0.1)
	# the front wall, open at the windows
	var xs: Array = []
	for w: Array in windows:
		xs.append([float(w[0]), float(w[1]), float(w[2]), float(w[3])])
	xs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var x := -0.12
	for w: Array in xs:
		_wall(x, w[0], 0.0, H, WALL_OUT, WALL_IN)
		_wall(w[0], w[1], 0.0, w[2], WALL_OUT, WALL_IN)
		_wall(w[0], w[1], w[3], H, WALL_OUT, WALL_IN)
		x = w[1]
	_wall(x, END_X + 0.1, 0.0, H, WALL_OUT, WALL_IN)
	# the left wall, the back wall (beige behind the bed), the right walls, the partition
	_wall(-0.12, 0.0, 0.0, H, WALL_IN, BACK)
	_wall(-0.12, END_X + 0.1, 0.0, H, BACK, BACK + 0.1)
	_box("beige", 0.0, PARTITION_X, 0.0, H, BACK - 0.012, BACK)
	_wall(ROOM_W, HALL_X, 0.0, H, DOORWAY.y, BACK)                  # the room | the shower room
	_wall(ROOM_W, HALL_X, 0.0, H, WALL_IN, DOORWAY.x)               # the room | the hall: a wide open doorway
	_wall(ROOM_W, HALL_X, DOORWAY.z, H, DOORWAY.x, DOORWAY.y)
	_trim_door_x(ROOM_W - 0.012, DOORWAY.x, DOORWAY.y, DOORWAY.z)
	_trim_door_x(HALL_X, DOORWAY.x, DOORWAY.y, DOORWAY.z)
	_wall(HALL_X, SHOWER_DOOR.x, 0.0, H, SPLIT_Z, SPLIT_Z + 0.1)    # the hall | the shower room: a door
	_wall(SHOWER_DOOR.y, END_X, 0.0, H, SPLIT_Z, SPLIT_Z + 0.1)
	_wall(SHOWER_DOOR.x, SHOWER_DOOR.y, DOOR_H, H, SPLIT_Z, SPLIT_Z + 0.1)
	_trim_door_z(SPLIT_Z - 0.012, SHOWER_DOOR.x, SHOWER_DOOR.y, DOOR_H)
	_wall(END_X, END_X + 0.1, 0.0, H, WALL_IN, BACK)                # the right outer wall, the front door in it
	_box("partition", PARTITION_X, PARTITION_X + 0.1, 0.0, H, PARTITION_Z, BACK)
	_col(PARTITION_X, PARTITION_X + 0.1, 0.0, H, PARTITION_Z, BACK)
	_box("oak", PARTITION_X - 0.005, PARTITION_X + 0.105, 0.0, H, PARTITION_Z - 0.01, PARTITION_Z)   # its end: oak
	# skirting
	for s: Array in [[0.0, ROOM_W, WALL_IN, WALL_IN + 0.012], [HALL_X, END_X, WALL_IN, WALL_IN + 0.012],
			[0.0, PARTITION_X, BACK - 0.024, BACK - 0.012], [HALL_X, SHOWER_DOOR.x - 0.06, SPLIT_Z - 0.024, SPLIT_Z - 0.012],
			[SHOWER_DOOR.y + 0.06, END_X, SPLIT_Z - 0.024, SPLIT_Z - 0.012]]:
		_box("white", s[0], s[1], 0.0, 0.07, s[2], s[3])
	var right: Array = [[END_X - 0.012, END_X, WALL_IN, DOOR_Z.x - 0.06]]
	if _garage:
		right += [[END_X - 0.012, END_X, DOOR_Z.y + 0.06, LIFT_Z.x - 0.06],
				[END_X - 0.012, END_X, LIFT_Z.y + 0.06, SPLIT_Z]]
	else:
		right.append([END_X - 0.012, END_X, DOOR_Z.y + 0.06, SPLIT_Z])
	for s: Array in right + [[0.0, 0.012, WALL_IN, BACK], [ROOM_W - 0.012, ROOM_W, WALL_IN, DOORWAY.x - 0.06],
			[ROOM_W - 0.012, ROOM_W, DOORWAY.y + 0.06, BACK - 0.62], [PARTITION_X - 0.012, PARTITION_X, PARTITION_Z, BACK],
			[PARTITION_X + 0.1, PARTITION_X + 0.112, PARTITION_Z, BACK - 0.62],
			[HALL_X, HALL_X + 0.012, WALL_IN, DOORWAY.x - 0.06], [HALL_X, HALL_X + 0.012, DOORWAY.y + 0.06, SPLIT_Z]]:
		_box("white", s[0], s[1], 0.0, 0.07, s[2], s[3])


## A plain white wall piece, solid.
func _wall(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if x1 - x0 < 0.005 or y1 - y0 < 0.005:
		return
	_box("wall", x0, x1, y0, y1, z0, z1)
	_col(x0, x1, y0, y1, z0, z1)


## The white casing round a doorway in a wall along z (from z0 to z1, up to y1), its face from x to x + 0.012.
func _trim_door_x(x: float, z0: float, z1: float, y1: float) -> void:
	_box("white", x, x + 0.012, 0.0, y1 + 0.06, z0 - 0.06, z0)
	_box("white", x, x + 0.012, 0.0, y1 + 0.06, z1, z1 + 0.06)
	_box("white", x, x + 0.012, y1, y1 + 0.06, z0, z1)


## The same round a doorway in a wall along x (from x0 to x1), its face from z to z + 0.012.
func _trim_door_z(z: float, x0: float, x1: float, y1: float) -> void:
	_box("white", x0 - 0.06, x0, 0.0, y1 + 0.06, z, z + 0.012)
	_box("white", x1, x1 + 0.06, 0.0, y1 + 0.06, z, z + 0.012)
	_box("white", x0, x1, y1, y1 + 0.06, z, z + 0.012)


# ---------------------------------------------------------------- windows

## A window in the front wall's opening w = [x0, x1, y0, y1]: the reveal is the wall's own sides; a white frame with
## two leaves and its mullion, the glass, a stone sill, a radiator under it, linen curtains drawn aside.
func _window(w: Array) -> void:
	var x0: float = w[0]
	var x1: float = w[1]
	var y0: float = w[2]
	var y1: float = w[3]
	var z := 0.12                               # the frame's plane, in the reveal
	var f := 0.065
	_box("frame", x0, x0 + f, y0, y1, z, z + 0.07)
	_box("frame", x1 - f, x1, y0, y1, z, z + 0.07)
	_box("frame", x0 + f, x1 - f, y0, y0 + f, z, z + 0.07)
	_box("frame", x0 + f, x1 - f, y1 - f, y1, z, z + 0.07)
	var mid := (x0 + x1) * 0.5
	_box("frame", mid - 0.045, mid + 0.045, y0 + f, y1 - f, z, z + 0.075)
	for lx: Array in [[x0 + f, mid - 0.045], [mid + 0.045, x1 - f]]:
		var a: float = lx[0]
		var b: float = lx[1]
		_box("frame", a, a + 0.04, y0 + f, y1 - f, z + 0.01, z + 0.06)     # each leaf's own frame
		_box("frame", b - 0.04, b, y0 + f, y1 - f, z + 0.01, z + 0.06)
		_box("frame", a, b, y0 + f, y0 + f + 0.04, z + 0.01, z + 0.06)
		_box("frame", a, b, y1 - f - 0.04, y1 - f, z + 0.01, z + 0.06)
		_box("glass", a + 0.04, b - 0.04, y0 + f + 0.04, y1 - f - 0.04, z + 0.03, z + 0.036)
	for hx: float in [mid - 0.075, mid + 0.075]:                       # the handles
		_box("steel", hx - 0.012, hx + 0.012, 1.02, 1.18, z + 0.075, z + 0.095)
	# the sill, the radiator, the curtains and their rail
	_box("sill", x0 - 0.06, x1 + 0.06, y0 - 0.03, y0, z + 0.06, WALL_IN + 0.06)
	if y0 > 0.3:
		var rx0 := x0 + 0.15
		var rx1 := x1 - 0.15
		_box("radiator", rx0, rx1, 0.12, y0 - 0.1, WALL_IN + 0.03, WALL_IN + 0.09)
		var n := int((rx1 - rx0) / 0.05)
		for k in n:
			var xx := rx0 + (k + 0.5) * (rx1 - rx0) / n
			_box("radiator", xx - 0.008, xx + 0.008, 0.13, y0 - 0.11, WALL_IN + 0.09, WALL_IN + 0.1)
	_box("black_metal", x0 - 0.3, x1 + 0.3, H - 0.1, H - 0.085, WALL_IN + 0.06, WALL_IN + 0.075)
	for side: float in [-1.0, 1.0]:
		var cx: float = (x0 - 0.18) if side < 0.0 else (x1 + 0.18)
		for k in 5:                                                      # folds
			var fx := cx + (k - 2) * 0.055 * side
			var r := 0.035 + 0.008 * float(k % 2)
			_cyl("curtain", Vector3(fx, 0.06, WALL_IN + 0.1 + 0.02 * float(k % 2)), r, H - 0.17, 7)


# ---------------------------------------------------------------- the sleeping corner

func _sleeping() -> void:
	# the bed (drawn with its head against a back wall at z = 4.05, moved into place): an upholstered base, the
	# mattress, the duvet hanging over its sides, a patterned throw at its foot, the turned-down sheet, two pillows and
	# two cushions, the headboard on the beige wall
	_off = Vector3(0.55, 0.0, BACK - 4.05)
	var back := 4.05
	var bx0 := 0.3
	var bx1 := 1.9
	var bz0 := 2.0
	var bz1 := back - 0.05
	_box("upholstery", bx0, bx1, 0.05, 0.34, bz0, bz1)
	for lx: float in [bx0 + 0.06, bx1 - 0.06]:
		for lz: float in [bz0 + 0.06, bz1 - 0.06]:
			_box("oak_dark", lx - 0.025, lx + 0.025, 0.0, 0.05, lz - 0.025, lz + 0.025)
	_col(bx0, bx1, 0.0, 0.56, bz0, bz1)
	_box("linen_white", bx0 + 0.04, bx1 - 0.04, 0.34, 0.56, bz0 + 0.04, bz1 - 0.02)
	var dz1 := 3.42
	_box("duvet", bx0 - 0.02, bx1 + 0.02, 0.54, 0.63, bz0 - 0.02, dz1)
	_box("duvet", bx0 - 0.03, bx0 - 0.01, 0.28, 0.6, bz0 - 0.02, dz1)
	_box("duvet", bx1 + 0.01, bx1 + 0.03, 0.28, 0.6, bz0 - 0.02, dz1)
	_box("duvet", bx0 - 0.02, bx1 + 0.02, 0.3, 0.6, bz0 - 0.04, bz0 - 0.02)
	_box("linen_white", bx0 + 0.02, bx1 - 0.02, 0.56, 0.645, dz1 - 0.14, dz1 + 0.02)
	_box("throw", bx0 - 0.04, bx1 + 0.04, 0.63, 0.655, bz0 + 0.06, bz0 + 0.55)
	_box("throw", bx0 - 0.05, bx0 - 0.03, 0.36, 0.655, bz0 + 0.06, bz0 + 0.55)
	_box("throw", bx1 + 0.03, bx1 + 0.05, 0.36, 0.655, bz0 + 0.06, bz0 + 0.55)
	for px: float in [0.71, 1.49]:
		var tilt := Vector3(-0.32, 0, 0)
		_box("linen_white", px - 0.3, px + 0.3, 0.6, 0.74, 3.55, 3.93, tilt)
		_ball("linen_white", Vector3(px, 0.68, 3.75), Vector3(0.29, 0.09, 0.18), tilt)
		_box("linen_cream", px - 0.19, px + 0.19, 0.6, 0.86, 3.43, 3.55, Vector3(-0.5, 0, 0.06))
		_ball("linen_cream", Vector3(px, 0.73, 3.48), Vector3(0.18, 0.13, 0.06), Vector3(-0.5, 0, 0.06))
	_box("upholstery_light", 0.22, 1.98, 0.3, 1.22, back - 0.07, back - 0.012)
	for gx: float in [0.22 + 1.76 / 3.0, 0.22 + 1.76 * 2.0 / 3.0]:
		_box("upholstery", gx - 0.006, gx + 0.006, 0.32, 1.2, back - 0.075, back - 0.07)
	# a round white bedside table and its lamp either side, a book on the right one
	_bedside(Vector3(2.12, 0.0, 3.7), -0.04)
	_bedside(Vector3(0.08, 0.0, 3.7), 0.04)
	_box("book_a", 2.04, 2.22, 0.515, 0.54, 3.62, 3.75)
	_off = Vector3.ZERO
	# the arched wardrobe in the front corner: its doors face the room
	var wz0 := 0.45
	var wz1 := 1.55
	var wx1 := 0.6
	var r := (wz1 - wz0) * 0.5
	var wzc := (wz0 + wz1) * 0.5
	_box("blush_dark", 0.02, wx1 - 0.02, 0.0, 0.08, wz0 + 0.02, wz1 - 0.02)
	_box("blush", 0.0, wx1, 0.08, 1.45, wz0, wz1)
	var slices := 14
	for k in slices:
		var za := wz0 + (wz1 - wz0) * k / slices
		var zb := wz0 + (wz1 - wz0) * (k + 1) / slices
		var dz := absf((za + zb) * 0.5 - wzc)
		var top := 1.45 + sqrt(maxf(r * r - dz * dz, 0.0))
		_box("blush", 0.0, wx1, 1.45, top, za, zb)
	_box("blush_dark", wx1, wx1 + 0.004, 0.1, 1.8, wzc - 0.003, wzc + 0.003)
	for kz: float in [wzc - 0.06, wzc + 0.06]:
		_ball("brass", Vector3(wx1 + 0.02, 1.0, kz), Vector3(0.018, 0.018, 0.018))
	_col(0.0, wx1, 0.0, 2.0, wz0, wz1)


## A round white bedside table standing at `nt`, its lamp `dx` off its middle.
func _bedside(nt: Vector3, dx: float) -> void:
	_cyl("white", nt, 0.12, 0.02, 18)
	_cyl("white", nt + Vector3(0, 0.02, 0), 0.045, 0.46, 12)
	_cyl("white", nt + Vector3(0, 0.48, 0), 0.2, 0.035, 24)
	_ball("ceramic", nt + Vector3(dx, 0.58, 0.02), Vector3(0.07, 0.065, 0.07))
	_cyl("brass", nt + Vector3(dx, 0.63, 0.02), 0.008, 0.1, 6)
	_cyl("shade", nt + Vector3(dx, 0.72, 0.02), 0.11, 0.15, 20, 0.08)
	_cyl("emit", nt + Vector3(dx, 0.725, 0.02), 0.07, 0.01, 12)


# ---------------------------------------------------------------- the living corner

func _living() -> void:
	# the sofa, its back against the partition (drawn against one at x = 2.35, moved into place)
	_off = Vector3(PARTITION_X - 2.35, 0.0, SOFA_Z)
	var x0 := 2.35 + 0.12
	var x1 := 3.35
	var z0 := 1.1
	var z1 := 3.05
	_box("fabric_dark", x0 + 0.02, x1 - 0.02, 0.03, 0.14, z0 + 0.02, z1 - 0.02)
	for lz: float in [z0 + 0.08, z1 - 0.08]:
		_box("black_metal", x1 - 0.1, x1 - 0.05, 0.0, 0.04, lz - 0.025, lz + 0.025)
	_box("fabric", x0 + 0.2, x1, 0.14, 0.4, z0 + 0.18, z1 - 0.18)
	_box("fabric", x0, x0 + 0.24, 0.14, 0.8, z0, z1)
	_box("fabric", x0, x1, 0.14, 0.6, z0, z0 + 0.18)
	_box("fabric", x0, x1, 0.14, 0.6, z1 - 0.18, z1)
	var zm := (z0 + z1) * 0.5
	for c: Array in [[z0 + 0.19, zm - 0.006], [zm + 0.006, z1 - 0.19]]:
		_box("fabric_light", x0 + 0.26, x1 - 0.01, 0.4, 0.5, c[0], c[1])
		_box("fabric_light", x0 + 0.24, x0 + 0.4, 0.45, 0.86, c[0], c[1])
	_ball("linen_cream", Vector3(x0 + 0.45, 0.62, z1 - 0.38), Vector3(0.06, 0.17, 0.17), Vector3(0, 0, -0.25))
	_col(x0, x1, 0.0, 0.6, z0, z1)
	# the arc floor lamp: a marble base by the sofa's end, the arc over the sofa, a black dome
	var base := Vector3(2.66, 0.0, 3.3)
	_cyl("marble", base, 0.15, 0.04, 24)
	var pts: Array[Vector3] = []
	var p0 := base + Vector3(0, 0.04, 0)
	var p1 := base + Vector3(0.05, 2.25, -0.2)
	var p2 := Vector3(3.3, 1.95, 2.35)
	for k in 13:
		var t := k / 12.0
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	for k in 12:
		_rod("black_metal", pts[k], pts[k + 1], 0.011)
	_cyl("black_metal", p2 + Vector3(0, -0.2, 0), 0.2, 0.2, 24, 0.05)
	_cyl("emit", p2 + Vector3(0, -0.205, 0), 0.16, 0.01, 18)
	# the rug (its pattern laid on it: _mat), the TV on the right wall and the floating shelf under it
	_off = Vector3.ZERO
	_box("rug", RUG.position.x, RUG.end.x, 0.0, 0.012, RUG.position.y, RUG.end.y)
	_off = Vector3(0.0, 0.0, SOFA_Z + 0.2)
	_box("tv", ROOM_W - 0.06, ROOM_W - 0.015, 1.05, 1.7, 1.52, 2.68)
	_box("screen", ROOM_W - 0.062, ROOM_W - 0.058, 1.07, 1.68, 1.54, 2.66)
	_box("oak", ROOM_W - 0.28, ROOM_W, 0.4, 0.44, 1.62, 2.58)
	_box("black", ROOM_W - 0.2, ROOM_W - 0.08, 0.44, 0.5, 1.75, 2.45)
	_plant(Vector3(ROOM_W - 0.14, 0.44, 2.53), 0.06, 0.32)
	_box("book_b", ROOM_W - 0.25, ROOM_W - 0.05, 0.44, 0.47, 1.66, 1.72)
	_box("book_a", ROOM_W - 0.24, ROOM_W - 0.06, 0.47, 0.49, 1.665, 1.715)
	# the oval bar table beyond the sofa's end (not in front of it), a stool at either end, a wide way between it and
	# the kitchen
	_off = Vector3.ZERO
	var t := TABLE
	_cyl("black_metal", t, 0.2, 0.02, 24)
	_cyl("black_metal", t + Vector3(0, 0.02, 0), 0.035, 0.88, 10)
	_cyl("oak", t + Vector3(0, 0.9, 0), 0.46, 0.035, 32, -1.0, Vector3(1.0, 1.0, 0.6))
	_col(t.x - 0.46, t.x + 0.46, 0.0, 0.94, t.z - 0.28, t.z + 0.28)
	_stool(t + Vector3(-0.71, 0.0, 0.0), PI * 0.5)
	_stool(t + Vector3(0.71, 0.0, 0.0), -PI * 0.5)


## A bar stool standing at `s`, turned `yaw` about the vertical (0: its back towards -z).
func _stool(s: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for a in 4:
		var ang := PI * 0.25 + a * PI * 0.5
		var foot := s + Vector3(cos(ang), 0, sin(ang)) * 0.17
		_rod("black_metal", foot, s + Vector3(cos(ang), 0, sin(ang)) * 0.12 + Vector3(0, 0.66, 0), 0.01)
	_cyl("black_metal", s + Vector3(0, 0.25, 0), 0.155, 0.012, 16)
	_cyl("leather", s + Vector3(0, 0.66, 0), 0.17, 0.05, 20)
	var c := s + b * Vector3(0.0, 0.825, -0.16)
	_box("leather", c.x - 0.13, c.x + 0.13, 0.75, 0.9, c.z - 0.01, c.z + 0.01, Vector3(0.0, yaw, 0.0))
	for x: float in [-0.1, 0.1]:
		_rod("black_metal", s + b * Vector3(x, 0.7, -0.15), s + b * Vector3(x, 0.78, -0.16), 0.008)


# ---------------------------------------------------------------- the kitchen

func _kitchen() -> void:
	# drawn from the partition at x = 2.35 along a back wall at z = 4.05, moved into place; the fridge column closes it
	# at the room's right wall
	_off = Vector3(PARTITION_X - 2.35, 0.0, BACK - 4.05)
	var back := 4.05
	var x0 := 2.35 + 0.1
	var x1 := ROOM_W - _off.x - 0.95
	var zf := back - 0.6
	_box("plinth", x0 + 0.02, x1, 0.0, 0.1, zf + 0.06, back - 0.02)
	_box("units", x0, x1, 0.1, 0.86, zf, back)
	_col(x0, x1, 0.0, 0.9, zf - 0.04, back)
	var doors := [x0, 2.97, 3.53, 4.02, x1]
	for k in range(1, doors.size() - 1):
		_box("groove", doors[k] - 0.003, doors[k] + 0.003, 0.11, 0.85, zf - 0.002, zf)
	for k in doors.size() - 1:
		if k == 1:
			continue                                                   # the oven
		var a: float = doors[k] + 0.08
		var b: float = doors[k + 1] - 0.08
		_box("black_metal", a, b, 0.79, 0.81, zf - 0.02, zf - 0.002)
	# the oven under the hob
	_box("black_glass", 2.99, 3.51, 0.14, 0.76, zf - 0.006, zf)
	_box("screen", 3.06, 3.44, 0.22, 0.58, zf - 0.008, zf - 0.006)
	_box("steel", 3.04, 3.46, 0.665, 0.685, zf - 0.04, zf - 0.02)
	_box("steel", 3.06, 3.08, 0.665, 0.685, zf - 0.02, zf - 0.006)
	_box("steel", 3.42, 3.44, 0.665, 0.685, zf - 0.02, zf - 0.006)
	# the worktop, the hob, the sink and its tap
	_box("worktop", x0 - 0.02, x1, 0.86, 0.9, zf - 0.04, back)
	_box("black_glass", 2.99, 3.51, 0.9, 0.905, zf + 0.06, back - 0.06)
	for hp: Vector2 in [Vector2(3.12, zf + 0.18), Vector2(3.38, zf + 0.18), Vector2(3.12, back - 0.2), Vector2(3.38, back - 0.19)]:
		_cyl("hob_ring", Vector3(hp.x, 0.905, hp.y), 0.075 if int(hp.x * 100) % 2 == 0 else 0.09, 0.002, 24)
	_box("sink", 4.08, 4.56, 0.9, 0.903, zf + 0.08, back - 0.1)
	_box("steel", 4.12, 4.52, 0.903, 0.905, zf + 0.11, back - 0.13)
	var tap := Vector3(4.32, 0.9, back - 0.06)
	_cyl("black_metal", tap, 0.022, 0.26, 10)
	_rod("black_metal", tap + Vector3(0, 0.26, 0), tap + Vector3(0, 0.34, -0.06), 0.012)
	_rod("black_metal", tap + Vector3(0, 0.34, -0.06), tap + Vector3(0, 0.32, -0.2), 0.012)
	_rod("black_metal", tap + Vector3(0, 0.32, -0.2), tap + Vector3(0, 0.25, -0.22), 0.012)
	_rod("black_metal", tap + Vector3(0.04, 0.1, 0), tap + Vector3(0.1, 0.12, 0), 0.006)
	# on the worktop: the microwave, the cutting board, a utensil jar, oil
	_box("appliance", 2.5, 2.93, 0.9, 1.17, back - 0.36, back - 0.03)
	_box("screen", 2.53, 2.78, 0.94, 1.13, back - 0.362, back - 0.36)
	_box("black", 2.81, 2.9, 0.98, 1.1, back - 0.362, back - 0.36)
	_box("oak_light", 3.6, 3.86, 0.9, 1.3, back - 0.05, back - 0.03, Vector3(0.12, 0, 0))
	_cyl("ceramic", Vector3(3.95, 0.9, back - 0.12), 0.05, 0.14, 14)
	for k in 3:
		_rod("oak_light", Vector3(3.94 + k * 0.012, 0.95, back - 0.12), Vector3(3.9 + k * 0.03, 1.2, back - 0.13), 0.007)
	_cyl("bottle", Vector3(4.65, 0.9, back - 0.12), 0.03, 0.22, 10, 0.012)
	# the splashback, the wall cupboard and its light strip, the oak shelves and what is on them
	_box("splashback", x0, x1, 0.9, 1.52, back - 0.012, back)
	_box("units", x0, 3.6, 1.56, 2.36, back - 0.33, back)
	_box("groove", 3.023, 3.027, 1.57, 2.35, back - 0.332, back - 0.33)
	_box("black", 2.99, 3.51, 1.545, 1.56, back - 0.33, back - 0.04)
	_box("emit", x0 + 0.04, 2.97, 1.555, 1.56, back - 0.08, back - 0.05)
	_box("emit", 3.53, 3.56, 1.555, 1.56, back - 0.08, back - 0.05)
	for sy: float in [1.62, 2.0]:
		_box("oak", 3.72, x1 - 0.02, sy, sy + 0.03, back - 0.23, back)
	_plant(Vector3(3.84, 1.65, back - 0.12), 0.055, 0.22)
	_cyl("glass_jar", Vector3(4.05, 1.65, back - 0.12), 0.045, 0.16, 12)
	_cyl("pasta", Vector3(4.05, 1.652, back - 0.12), 0.04, 0.11, 12)
	_cyl("glass_jar", Vector3(4.18, 1.65, back - 0.12), 0.045, 0.12, 12)
	_cyl("coffee", Vector3(4.18, 1.652, back - 0.12), 0.04, 0.07, 12)
	for k in 3:
		_cyl("ceramic", Vector3(4.36 + k * 0.1, 1.65, back - 0.11), 0.038, 0.09, 12)
	_plant(Vector3(4.55, 2.03, back - 0.12), 0.06, 0.3)
	_cyl("vase", Vector3(4.3, 2.03, back - 0.11), 0.05, 0.2, 14, 0.035)
	_cyl("plant", Vector3(4.3, 2.2, back - 0.11), 0.004, 0.18, 4)
	_ball("plant", Vector3(4.3, 2.4, back - 0.11), Vector3(0.07, 0.05, 0.07))
	for k in 4:
		_box("book_a" if k % 2 == 0 else "book_b", 3.8 + k * 0.04, 3.835 + k * 0.04, 2.03, 2.27 - k * 0.012, back - 0.2, back - 0.04)
	# the tall column: the fridge over the freezer, a narrow larder beside it
	var f0 := x1 + 0.005
	var f1 := x1 + 0.95
	var fm := f0 + 0.6
	_box("plinth", f0 + 0.02, f1, 0.0, 0.1, zf + 0.06, back - 0.02)
	_box("units", f0, f1, 0.1, 2.36, zf, back)
	_col(f0, f1, 0.0, 2.36, zf, back)
	_box("groove", fm - 0.003, fm + 0.003, 0.11, 2.35, zf - 0.002, zf)
	_box("groove", f0 + 0.01, fm - 0.01, 0.857, 0.863, zf - 0.002, zf)
	_box("black_metal", fm - 0.06, fm - 0.04, 0.95, 1.45, zf - 0.03, zf - 0.002)
	_box("black_metal", fm - 0.06, fm - 0.04, 0.55, 0.8, zf - 0.03, zf - 0.002)
	_box("black_metal", fm + 0.04, fm + 0.06, 0.95, 1.45, zf - 0.03, zf - 0.002)
	_off = Vector3.ZERO


# ---------------------------------------------------------------- the hall and the shower room

func _hall() -> void:
	# the flat's front door (E by it: leave), its casing, a doormat
	var d0 := DOOR_Z.x
	var d1 := DOOR_Z.y
	_box("door", END_X - 0.055, END_X, 0.0, DOOR_H, d0, d1)
	_box("door_panel", END_X - 0.058, END_X - 0.055, 0.25, DOOR_H - 0.25, d0 + 0.12, d1 - 0.12)
	_box("white", END_X - 0.07, END_X - 0.055, 0.0, DOOR_H + 0.06, d0 - 0.06, d0)
	_box("white", END_X - 0.07, END_X - 0.055, 0.0, DOOR_H + 0.06, d1, d1 + 0.06)
	_box("white", END_X - 0.07, END_X - 0.055, DOOR_H, DOOR_H + 0.06, d0, d1)
	_box("steel", END_X - 0.1, END_X - 0.058, 1.0, 1.02, d1 - 0.1, d1 - 0.08)
	_rod("steel", Vector3(END_X - 0.1, 1.01, d1 - 0.09), Vector3(END_X - 0.1, 1.01, d1 - 0.24), 0.011)
	_cyl("steel", Vector3(END_X - 0.07, 1.55, (d0 + d1) * 0.5), 0.012, 0.015, 8)
	_col(END_X - 0.06, END_X + 0.1, 0.0, DOOR_H + 0.1, d0, d1)
	_box("doormat", END_X - 0.72, END_X - 0.08, 0.0, 0.012, d0 + 0.1, d1 - 0.1)
	# a bench with shoes along the front wall, hooks with coats over it (drawn for a hall from x = 4.9)
	_off = Vector3(HALL_X - 4.9 + 0.1, 0.0, 0.0)
	_box("oak", 5.15, 6.15, 0.42, 0.46, WALL_IN, WALL_IN + 0.36)
	_box("white", 5.17, 6.13, 0.0, 0.42, WALL_IN + 0.02, WALL_IN + 0.34)
	_col(5.15, 6.15, 0.0, 0.46, WALL_IN, WALL_IN + 0.36)
	for k in 3:
		var sx := 5.3 + k * 0.28
		_box("shoe", sx, sx + 0.1, 0.0, 0.09, WALL_IN + 0.06, WALL_IN + 0.32)
		_box("shoe", sx + 0.12, sx + 0.22, 0.0, 0.09, WALL_IN + 0.06, WALL_IN + 0.32)
	_box("oak", 5.15, 6.15, 1.68, 1.76, WALL_IN, WALL_IN + 0.025)
	for k in 4:
		var hx := 5.3 + k * 0.24
		_rod("black_metal", Vector3(hx, 1.72, WALL_IN + 0.025), Vector3(hx, 1.75, WALL_IN + 0.09), 0.008)
	_box("coat", 5.2, 5.62, 0.95, 1.7, WALL_IN + 0.04, WALL_IN + 0.17)
	_box("coat_b", 5.68, 6.0, 1.15, 1.7, WALL_IN + 0.04, WALL_IN + 0.15)
	_off = Vector3.ZERO
	# the light switch by the doorway to the room
	_box("white", HALL_X, HALL_X + 0.012, 1.05, 1.13, DOORWAY.y + 0.14, DOORWAY.y + 0.22)


## The garage option: a private lift down to the residence's car park in the hall's right wall, beside the front door
## (E by it: leave by car): brushed steel doors in a dark frame, a lit call button, GARAGE over it.
func _lift() -> void:
	var z0 := LIFT_Z.x
	var z1 := LIFT_Z.y
	var zm := (z0 + z1) * 0.5
	var x := END_X
	_box("black_metal", x - 0.07, x, 0.0, DOOR_H + 0.08, z0 - 0.06, z0)
	_box("black_metal", x - 0.07, x, 0.0, DOOR_H + 0.08, z1, z1 + 0.06)
	_box("black_metal", x - 0.07, x, DOOR_H, DOOR_H + 0.08, z0, z1)
	_box("steel", x - 0.04, x, 0.0, DOOR_H, z0, zm - 0.004)
	_box("steel", x - 0.04, x, 0.0, DOOR_H, zm + 0.004, z1)
	_box("black", x - 0.035, x, 0.0, DOOR_H, zm - 0.004, zm + 0.004)
	_col(x - 0.05, x + 0.1, 0.0, DOOR_H + 0.1, z0, z1)
	# the call button's plate on the wall beside it
	_box("steel", x - 0.015, x, 1.0, 1.22, z1 + 0.08, z1 + 0.16)
	_cyl("emit_cool", Vector3(x - 0.02, 1.11, z1 + 0.12), 0.022, 0.01, 12)
	var sign := Label3D.new()
	sign.name = "LiftSign"
	sign.text = "GARAGE"
	sign.font_size = 40
	sign.pixel_size = 0.0022
	sign.outline_size = 0
	sign.modulate = Color(0.2, 0.21, 0.24)
	sign.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x - 0.012, DOOR_H + 0.22, zm))
	_root.add_child(sign)


func _shower_room() -> void:
	var z0 := SPLIT_Z + 0.1
	# tiles on the walls up to 2.1 m
	_box("tile_wall", HALL_X, HALL_X + 0.01, 0.0, 2.1, z0, BACK)
	_box("tile_wall", END_X - 0.01, END_X, 0.0, 2.1, z0, BACK)
	_box("tile_wall", HALL_X, END_X, 0.0, 2.1, BACK - 0.01, BACK)
	_box("tile_wall", HALL_X, SHOWER_DOOR.x, 0.0, 2.1, z0, z0 + 0.01)
	_box("tile_wall", SHOWER_DOOR.y, END_X, 0.0, 2.1, z0, z0 + 0.01)
	# its door, open against the wall
	var dw := SHOWER_DOOR.y - SHOWER_DOOR.x
	_box("door", SHOWER_DOOR.x, SHOWER_DOOR.x + 0.04, 0.0, DOOR_H - 0.04, z0 + 0.01, z0 + 0.01 + dw)
	_box("steel", SHOWER_DOOR.x + 0.04, SHOWER_DOOR.x + 0.06, 1.0, 1.02, z0 + dw - 0.1, z0 + dw - 0.04)
	# the shower in the back corner (drawn for a room ending at x = 6.8, z = 4.05): a tray, a glass screen, a rain head
	# and its mixer
	_off = Vector3(END_X - 6.8, 0.0, BACK - 4.05)
	var e := 6.8
	var back := 4.05
	_box("ceramic", 6.0, e - 0.01, 0.0, 0.05, 3.25, back - 0.01)
	_box("glass", 6.0, 6.01, 0.05, 2.0, 3.25, back - 0.01)
	_box("steel", 5.995, 6.015, 0.05, 2.0, 3.24, 3.26)
	_col(5.99, 6.02, 0.0, 2.0, 3.25, back)
	_rod("steel", Vector3(6.45, 2.1, back - 0.01), Vector3(6.45, 2.1, back - 0.3), 0.012)
	_cyl("steel", Vector3(6.45, 2.08, back - 0.3), 0.12, 0.015, 24)
	_box("steel", 6.38, 6.52, 1.05, 1.12, back - 0.04, back - 0.01)
	_rod("steel", Vector3(6.45, 1.12, back - 0.02), Vector3(6.45, 2.1, back - 0.02), 0.01)
	# the WC on the right wall, its flush plate
	_off = Vector3(END_X - 6.8, 0.0, 1.1)
	_box("ceramic", e - 0.22, e - 0.01, 0.25, 1.1, 2.3, 2.75)
	_box("steel", e - 0.225, e - 0.22, 0.85, 1.0, 2.44, 2.61)
	_ball("ceramic", Vector3(e - 0.42, 0.33, 2.525), Vector3(0.24, 0.1, 0.19))
	_box("ceramic", e - 0.62, e - 0.22, 0.42, 0.45, 2.36, 2.69)
	_col(e - 0.65, e, 0.0, 0.45, 2.3, 2.75)
	# the basin on an oak unit on the left wall, the mirror, a towel
	_off = Vector3(HALL_X - 4.9, 0.0, 1.5)
	var hx := 4.9
	_box("oak", hx + 0.01, hx + 0.5, 0.45, 0.82, 2.95, 3.6)
	_box("ceramic", hx + 0.03, hx + 0.48, 0.82, 0.88, 2.98, 3.57)
	_box("sink", hx + 0.1, hx + 0.42, 0.875, 0.882, 3.05, 3.5)
	_rod("steel", Vector3(hx + 0.03, 0.95, 3.275), Vector3(hx + 0.15, 0.97, 3.275), 0.012)
	_cyl("steel", Vector3(hx + 0.04, 0.88, 3.275), 0.02, 0.08, 10)
	_col(hx, hx + 0.5, 0.0, 0.88, 2.95, 3.6)
	_box("mirror", hx + 0.01, hx + 0.02, 1.1, 1.85, 3.0, 3.55)
	_box("towel", hx + 0.01, hx + 0.06, 0.9, 1.3, 3.72, 4.0)
	_off = Vector3.ZERO


# ---------------------------------------------------------------- lights

func _lights(windows: Array) -> void:
	var warm := Color(1.0, 0.87, 0.72)
	var bed := Vector3(0.55, 0.0, BACK - 4.05)              # _sleeping's _off
	for c: Vector3 in [Vector3(1.6, H, 3.4), Vector3(4.95, H, 2.5), Vector3(TABLE.x, H, TABLE.z), Vector3(7.95, H, 1.55),
			Vector3(7.95, H, 4.6)]:
		_cyl("white", c - Vector3(0, 0.03, 0), 0.17, 0.03, 24)
		_cyl("emit", c - Vector3(0, 0.035, 0), 0.15, 0.006, 24)
	_omni(Vector3(1.6, 2.45, 3.4), warm, 1.0, 5.6, true)
	_omni(Vector3(4.95, 2.45, 2.5), warm, 1.1, 5.4, true)
	_omni(Vector3(TABLE.x, 2.45, TABLE.z), warm, 0.6, 3.4, false)
	_omni(Vector3(7.95, 2.45, 1.55), warm, 0.65, 3.6, false)
	_omni(Vector3(7.95, 2.45, 4.6), Color(1.0, 0.96, 0.92), 0.75, 3.8, false)
	_omni(Vector3(PARTITION_X + 0.7, 1.45, BACK - 0.15), warm, 0.5, 2.2, false)
	_omni(bed + Vector3(2.08, 0.8, 3.72), Color(1.0, 0.78, 0.55), 0.45, 1.8, false)
	_omni(bed + Vector3(0.12, 0.8, 3.72), Color(1.0, 0.78, 0.55), 0.45, 1.8, false)
	_omni(Vector3(PARTITION_X - 2.35 + 3.3, 1.6, SOFA_Z + 2.35), Color(1.0, 0.82, 0.6), 0.5, 2.6, false)
	# the room's own ambient light and reflections (an interior probe): not the open sky's blue, which the building's
	# walls would hide; the outside seen through the windows keeps the world's
	var probe := ReflectionProbe.new()
	probe.name = "Probe"
	probe.size = Vector3(END_X + 0.3, H + 0.3, BACK + 0.2)
	probe.position = Vector3((END_X - 0.1) * 0.5, H * 0.5, (BACK + WALL_OUT) * 0.5)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.93, 0.89, 0.83)
	probe.ambient_color_energy = 0.55
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.blend_distance = 0.2
	_root.add_child(probe)
	# daylight in from the windows (properties.gd turns these off at night)
	var day := Node3D.new()
	day.name = "Daylight"
	_root.add_child(day)
	for w: Array in windows:
		var s := SpotLight3D.new()
		s.position = Vector3((float(w[0]) + float(w[1])) * 0.5, float(w[3]) - 0.1, WALL_IN + 0.05)
		s.rotation = Vector3(-0.75, PI, 0.0)
		s.light_color = Color(0.92, 0.96, 1.0)
		s.light_energy = 1.7
		s.spot_range = 7.0
		s.spot_angle = 55.0
		s.spot_attenuation = 0.8
		s.shadow_enabled = false
		day.add_child(s)


func _omni(p: Vector3, col: Color, energy: float, range_m: float, shadows: bool) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	_root.add_child(l)


# ---------------------------------------------------------------- small things

func _plant(p: Vector3, r: float, h: float) -> void:
	_cyl("pot", p, r, r * 1.6, 14, r * 0.8)
	_cyl("soil", p + Vector3(0, r * 1.5, 0), r * 0.92, 0.01, 12)
	for k in 5:
		var a := k * TAU / 5.0 + _rng.randf() * 0.5
		var lean := Vector3(cos(a), 0, sin(a)) * r * 1.3
		_ball("plant", p + Vector3(0, r * 1.6 + h * (0.35 + 0.12 * (k % 3)), 0) + lean,
				Vector3(r * 0.9, h * 0.32, r * 0.9), Vector3(sin(a) * 0.4, 0, cos(a) * 0.4))


# ---------------------------------------------------------------- mesh building

func _tool(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]


## A box from (x0, y0, z0) to (x1, y1, z1) in the studio's frame, turned by `rot` (Euler, radians) about its middle.
func _box(mat: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var xf := Transform3D(Basis.from_euler(rot), Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5 + _off)
	_tool(mat).append_from(m, 0, xf)


## A vertical cylinder standing on `p` (its foot's middle), radius r (`top` its top's radius, -1 the same), `scale`
## stretching it (an oval).
func _cyl(mat: String, p: Vector3, r: float, h: float, seg := 16, top := -1.0, scale := Vector3.ONE) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top < 0.0 else top
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	var xf := Transform3D(Basis.from_scale(scale), p + _off + Vector3(0, h * 0.5, 0))
	_tool(mat).append_from(m, 0, xf)


## A rod from a to b, radius r.
func _rod(mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = L
	m.radial_segments = 8
	m.rings = 1
	var y := d / L
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_tool(mat).append_from(m, 0, Transform3D(Basis(x, y, z), (a + b) * 0.5 + _off))


## An ellipsoid at c with radii `r`, turned by `rot`.
func _ball(mat: String, c: Vector3, r: Vector3, rot := Vector3.ZERO) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 16
	m.rings = 8
	_tool(mat).append_from(m, 0, Transform3D(Basis.from_euler(rot) * Basis.from_scale(r), c + _off))


func _col(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var s := BoxShape3D.new()
	s.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5 + _off
	_body.add_child(cs)


# ---------------------------------------------------------------- materials

func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	match name:
		"wall": _plain(m, "#f1efea", 0.95)
		"ceiling": _plain(m, "#f6f5f1", 0.95)
		"concrete": _plain(m, "#9c9a95", 1.0)
		"beige": _plain(m, "#d8c6ae", 0.95)
		"partition": _plain(m, "#e6ddd1", 0.9)
		"white": _plain(m, "#fbfbf9", 0.6)
		"sill": _plain(m, "#ecebe7", 0.35)
		"frame": _plain(m, "#f7f7f5", 0.4)
		"radiator": _plain(m, "#f4f4f2", 0.45)
		"curtain": _plain(m, "#ebe3d6", 1.0)
		"oak": _plain(m, "#b98d63", 0.6)
		"oak_light": _plain(m, "#cfa978", 0.65)
		"oak_dark": _plain(m, "#6e4f37", 0.6)
		"upholstery": _plain(m, "#d9cab8", 1.0)
		"upholstery_light": _plain(m, "#e8ddcf", 1.0)
		"linen_white": _plain(m, "#f4f2ed", 1.0)
		"linen_cream": _plain(m, "#e9dfcf", 1.0)
		"duvet": _plain(m, "#bca995", 1.0)
		"blush": _plain(m, "#e3cab6", 0.7)
		"blush_dark": _plain(m, "#c7ab96", 0.7)
		"fabric": _plain(m, "#4a4d53", 1.0)
		"fabric_light": _plain(m, "#55585e", 1.0)
		"fabric_dark": _plain(m, "#2f3135", 1.0)
		"leather": _plain(m, "#1f1f22", 0.5)
		"black": _plain(m, "#1c1d20", 0.45)
		"tv": _plain(m, "#121316", 0.3)
		"worktop": _plain(m, "#1e1f22", 0.3)
		"units": _plain(m, "#f3f3f1", 0.55)
		"groove": _plain(m, "#9a9a98", 0.8)
		"plinth": _plain(m, "#7c7c7a", 0.8)
		"appliance": _plain(m, "#e9e9e7", 0.4)
		"door": _plain(m, "#f5f4f1", 0.5)
		"door_panel": _plain(m, "#ecebe7", 0.5)
		"doormat": _plain(m, "#6b5a4a", 1.0)
		"shoe": _plain(m, "#3a3f47", 0.7)
		"coat": _plain(m, "#56606b", 1.0)
		"coat_b": _plain(m, "#a2876a", 1.0)
		"towel": _plain(m, "#dcd3c5", 1.0)
		"book_a": _plain(m, "#7a8e8a", 0.8)
		"book_b": _plain(m, "#c9b49a", 0.8)
		"pot": _plain(m, "#d8cdbf", 0.8)
		"vase": _plain(m, "#cbb59b", 0.6)
		"soil": _plain(m, "#4a3a2c", 1.0)
		"plant": _plain(m, "#4f7d3a", 0.9)
		"pasta": _plain(m, "#e3c37a", 0.9)
		"coffee": _plain(m, "#4a3021", 0.9)
		"tile_wall": _plain(m, "#f4f4f2", 0.15)
		"ceramic": _plain(m, "#fbfbfa", 0.12)
		"sink": _plain(m, "#2a2b2e", 0.25)
		"shade": _plain(m, "#f1ebe0", 0.9)
		"marble":
			_plain(m, "#e9e6e1", 0.2)
		"black_metal":
			_plain(m, "#1f2023", 0.35)
			m.metallic = 0.6
		"steel":
			_plain(m, "#c3c7cc", 0.22)
			m.metallic = 0.9
		"brass":
			_plain(m, "#c9a24c", 0.3)
			m.metallic = 0.85
		"hob_ring":
			_plain(m, "#5a5c60", 0.4)
		"screen", "black_glass":
			_plain(m, "#0d0f12", 0.22)
			m.metallic_specular = 0.6
		"mirror":
			_plain(m, "#dfe6ea", 0.0)
			m.metallic = 1.0
		"glass", "glass_jar", "bottle":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(0.86, 0.93, 0.95, 0.1) if name == "glass" else Color(0.8, 0.88, 0.85, 0.3)
			if name == "bottle":
				m.albedo_color = Color(0.55, 0.62, 0.25, 0.7)
			m.roughness = 0.04
			m.metallic_specular = 0.9
		"emit", "emit_cool":
			m.albedo_color = Color(1.0, 0.95, 0.85)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.88, 0.7)
			m.emission_energy_multiplier = 2.5
		"parquet": _textured(m, "parquet", Vector3(1.0 / 2.4, 1.0, 1.0 / 0.6), 0.55)
		"tile_floor": _textured(m, "tiles", Vector3(1.0 / 0.6, 1.0, 1.0 / 0.6), 0.35)
		"rug":
			_textured(m, "rug", Vector3(1.0 / RUG.size.x, 1.0, 1.0 / RUG.size.y), 1.0)
			m.uv1_offset = Vector3(-RUG.position.x / RUG.size.x, 0.0, -RUG.position.y / RUG.size.y)
		"throw": _textured(m, "throw", Vector3(1.0 / 0.45, 1.0 / 0.45, 1.0 / 0.45), 1.0)
		"splashback": _textured(m, "splashback", Vector3(1.0 / 0.62, 1.0 / 0.62, 1.0 / 0.62), 0.3)
		_: _plain(m, "#ff00ff", 1.0)
	_mats[name] = m
	return m


static func _plain(m: StandardMaterial3D, hex: String, rough: float) -> void:
	m.albedo_color = Color(hex)
	m.roughness = rough


## A texture laid on in the studio's own frame (triplanar on the object's coordinates: no UVs needed).
static func _textured(m: StandardMaterial3D, tex: String, scale: Vector3, rough: float) -> void:
	m.albedo_texture = _texture(tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = scale
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


# ---------------------------------------------------------------- textures (drawn once a session)

static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var img: Image
		match name:
			"parquet": img = _parquet()
			"tiles": img = _tiles()
			"rug": img = _rug()
			"throw": img = _throw()
			_: img = _splashback()
		img.generate_mipmaps()
		_textures[name] = ImageTexture.create_from_image(img)
	return _textures[name]


## Light oak boards 0.15 m wide (4 rows on the 0.6 m the texture spans across) and about 1.2 m long (2.4 m along it),
## joints staggered, each board its own slight shade and its straight grain along its length (fine streaks, a few
## darker ones).
static func _parquet() -> Image:
	var w := 1024
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rows := 4
	var rh := h / rows
	var base := Color("#caa679")
	for r in rows:
		var off := rng.randi_range(0, w - 1)
		var cuts := [off, (off + w / 2 + rng.randi_range(-70, 70)) % w]
		cuts.sort()
		var shades := [rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)]
		var phases := [rng.randf() * 50.0, rng.randf() * 50.0, rng.randf() * 50.0]
		for y in range(r * rh, (r + 1) * rh):
			for x in w:
				var board := 0 if x < cuts[0] else (1 if x < cuts[1] else 2)
				var s: float = shades[board]
				var ph: float = phases[board]
				var fy := float(y) + sin(float(x) * 0.011 + ph) * 1.6        # the grain drifts gently along the board
				var streak := pow(sin(fy * 0.9 + ph) * 0.5 + 0.5, 10.0) * 0.06
				var fine := sin(fy * 3.1 + ph * 2.0) * 0.012
				var dark := pow(sin(fy * 0.23 + ph * 0.5) * 0.5 + 0.5, 30.0) * 0.08
				var g := streak + fine + dark
				var c := Color(base.r + s - g, base.g + s * 0.92 - g * 0.95, base.b + s * 0.75 - g * 0.8)
				if y == r * rh or x == cuts[0] or x == cuts[1]:
					c = c.darkened(0.22)
				img.set_pixel(x, y, c)
	return img


## Grey floor tiles 0.3 m with light joints (two by two on the 0.6 m the texture spans).
static func _tiles() -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in n:
		for x in n:
			var c := Color("#a5a39f")
			var v := rng.randf_range(-0.015, 0.015)
			c = Color(c.r + v, c.g + v, c.b + v)
			if x % 64 < 1 or y % 64 < 1:
				c = Color("#d9d7d2")
			img.set_pixel(x, y, c)
	return img


## The rug of the plan: cream with beige lines in a herringbone of chevrons and a plain border.
static func _rug() -> Image:
	var w := 256
	var h := 384
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var cream := Color("#eee7da")
	var line := Color("#c6ae90")
	for y in h:
		for x in w:
			var c := cream
			var bx := mini(x, w - 1 - x)
			var by := mini(y, h - 1 - y)
			if bx < 14 or by < 14:
				c = Color("#e2d7c6")
			elif bx < 18 or by < 18:
				c = line
			else:
				var cx := (x - 18) % 56
				var cy := float((y - 18) % 40)
				var v := float(absi(cx - 28))
				if absf(cy - v * 0.7) < 2.0 or absf(cy - v * 0.7 - 20.0) < 2.0:
					c = line
			img.set_pixel(x, y, c)
	return img


## The throw at the bed's foot: brown and black zigzags on grey.
static func _throw() -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var zz := absi((x % 32) - 16)
			var band := int((y + zz) / 8.0) % 4
			var c: Color = [Color("#6d5444"), Color("#2b2626"), Color("#a3988c"), Color("#d9d0c3")][band]
			img.set_pixel(x, y, c)
	return img


## The splashback: white tiles with a grey feathered pattern (the plan's), fine joints.
static func _splashback() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := Color("#f2f0ec")
			var tx := x % 64
			var ty := y % 64
			var fx := float(tx) - 32.0
			var fy := float(ty) - 32.0
			var stem := absf(fx) < 1.2 and absf(fy) < 26.0
			var barb := absf(absf(fx) - (fy + 26.0) * 0.42) < 1.0 and fy > -26.0 and fy < 20.0 and absf(fx) < 16.0
			if stem or (barb and int(fy) % 4 != 0):
				c = Color("#8e9093")
			if tx == 0 or ty == 0:
				c = Color("#d2cfca")
			img.set_pixel(x, y, c)
	return img
