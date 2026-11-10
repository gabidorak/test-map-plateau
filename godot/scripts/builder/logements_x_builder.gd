@tool
extends RefCounted
## The École polytechnique's new student housing (world/rail.json `logements_x`, tools/rail/logements_x.py), drawn
## over the six world.json masses patch_world.py restyled (a white concrete ground floor core, a floating upper body in
## khaki ribbed panels with a green roof) after Thomas's photos (ref/logementsX/):
## - the facades: a projecting white slab band at every floor (alternately 0.45 and 0.30 m deep: the "drawers" of the
##   photos) and a deep one round the parapet, white surrounds either side of each window, the windows (anthracite
##   frames, a mullion, sky-reflecting panes lit at night: shaders/toy_window.gdshader) in pairs or alone, a few
##   staggered from floor to floor; on the ground floor white piers, full-height glazing between them, concrete bays
##   with a slit window, a louvre or a service door, a dark plinth;
## - the corner cut out under the overhang (facing the promenade): the bike shelter on its raised slab behind
##   expanded-metal mesh with red hoops, then the porch with the glazed entrance door, the plot's number on a black
##   hexagon, downlights; white columns;
## - on the roof: the atrium's skylight, ventilation units, a hatch, white copings;
## - round them: the boulevard sidewalk's kerb stones, the car park's flush kerbs and bay lines, the light bollards
##   along the paths (dark grey, a glowing head), limestone boulders, mulch rings under the young trees.
## Collision: the ground floor's columns, the bike shelter's mesh and slab, the roof plant, bollards, boulders.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
const RAIL_PATH := "res://world/rail.json"
const PROP_SHADER := "res://shaders/toy_prop.gdshader"
const GLASS_SHADER := "res://shaders/toy_prop_glass.gdshader"
const WINDOW_SHADER := "res://shaders/toy_window.gdshader"

const FRAME := Color("#3a3d42")             # anthracite window frames (photos)
const PLINTH := Color("#4b4e53")
const CURTAIN := Color("#e6e2d9")             # white curtains behind some panes (photos)
const PANE := Color("#8f98a3")                # the panes' tint over the sky's reflection: dark grey glass (photos)
const MESH := Color("#c9ced3")              # the bike shelter's expanded metal
const STEEL := Color("#8d949b")
const HOOP := Color("#c8322b")              # the red bike hoops (photos)
const SLAB := Color("#d9d5cc")
const LOUVRE := Color("#4a4e54")
const SERVICE := Color("#a7abae")           # the grey service doors (photo)
const PLANT := Color("#a9aeb3")
const HEX := Color("#1c1d20")
const KERB_TOP := Color("#e3dfd6")
const KERB_FACE := Color("#c9c3b7")
const BORDER := Color("#d8d4cc")
const PAINT := Color("#f3f2ec")
const BOLLARD := Color("#3b3f44")
const GLOW := Color("#fff3cc")
const ROCK := Color("#d6be86")
const MULCH := Color("#7b5c3e")
const LAYOUTS := [[[5.0, 2], [13.6, 2]], [[6.3, 1], [13.5, 1]], [[4.5, 1], [9.9, 1], [15.3, 1]],
		[[4.2, 2], [11.6, 1], [16.2, 1]]]       # m along a face: window centre, 1 alone / 2 a pair (photos)
const STAGGER := [0.0, -1.4, 0.7, -0.6, 1.0]    # m: a lone window's shift from floor to floor (photos)
const WIN_W := 1.45                         # m, a window with its frame
const PIER_W := 0.3                         # m, the white surround either side
const PAIR := 1.85                          # m between the centres of a pair
const FRAME_BAR := 0.07                     # m, a window frame's bars (the pane fills the opening between them)
const PORCH_DOOR := 2.3                     # m from the recess's inner corner to the porch's entrance door

var _mesh_dir := ""
var _mat: ShaderMaterial
var _glass: ShaderMaterial
var _glow: ShaderMaterial
var _win: ShaderMaterial
var _ground: GroundHeights
var _node: Node3D
var _body: StaticBody3D
var _L: Dictionary
var _D: Dictionary
var _white := Color.WHITE
var _wall := Color.WHITE
var _meshers := {}
var _rng := RandomNumberGenerator.new()


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> void:
	if not FileAccess.file_exists(RAIL_PATH):
		return
	var rail = JSON.parse_string(FileAccess.get_file_as_string(RAIL_PATH))
	if not rail is Dictionary or not (rail as Dictionary).has("logements_x"):
		return
	_L = rail["logements_x"]
	_D = _L["dims"]
	_white = Color(_D["white"])
	_wall = Color(_D["wall"])
	_mesh_dir = mesh_dir
	_rng.seed = 2026
	var t: Dictionary = world["terrain"]
	_ground = GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	_mat = ShaderMaterial.new()
	_mat.shader = load(PROP_SHADER)
	_mat.set_shader_parameter("mode", 0)
	MeshUtils.save(_mat, mesh_dir + "logx_material.tres")
	_glass = ShaderMaterial.new()
	_glass.shader = load(GLASS_SHADER)
	_glass.set_shader_parameter("opacity", 0.38)
	MeshUtils.save(_glass, mesh_dir + "logx_glass.tres")
	_glow = ShaderMaterial.new()
	_glow.shader = load(PROP_SHADER)
	_glow.set_shader_parameter("mode", 2)
	MeshUtils.save(_glow, mesh_dir + "logx_glow.tres")
	_win = ShaderMaterial.new()
	_win.shader = load(WINDOW_SHADER)
	var pal: Dictionary = world["palette"]["building"]
	_win.set_shader_parameter("glass_sky_color", Color.html(pal["glass_sky"]))
	_win.set_shader_parameter("glass_deep_color", Color.html(pal["glass_deep"]))
	MeshUtils.save(_win, mesh_dir + "logx_window.tres")
	_node = Node3D.new()
	_node.name = "LogementsX"
	root.add_child(_node)
	_body = StaticBody3D.new()
	_body.name = "LogementsXCollision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "site_structure", "id": "logx"})
	root.add_child(_body)
	for pl: Dictionary in _L["plots"]:
		_plot(pl)
	_kerb()
	_borders()
	_markings()
	_bollards()
	_rocks()
	_mulch()
	_node.set_meta("lamp_lights", PackedVector3Array())
	for name: String in _meshers:
		var e: Array = _meshers[name]
		_emit(name, e[0], e[1], e[2], e[3])
	print("logements X: %d plots, %d bays, %d bollards, %d boulders" % [_L["plots"].size(), int(_L["bays"]),
			_L["bollards"].size(), _L["rocks"].size()])


# ---------------------------------------------------------------- helpers

static func _gp(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, z, -p.y)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _gd(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, -d.y)


func _info(kind: String, id: String, name := "") -> Dictionary:
	var d := {"type": "site_structure", "kind": kind, "id": id}
	if name:
		d["name"] = name
	return d


## The Mesher named `name`: the window panes' material when it ends with Windows, glass with Glass, glow with Lights,
## else the toy one.
func _mesher(name: String, range_end := 900.0) -> RailBuilder.Mesher:
	if not _meshers.has(name):
		var mat: Material = _mat
		if name.ends_with("Windows"):
			mat = _win
		elif name.ends_with("Glass"):
			mat = _glass
		elif name.ends_with("Lights"):
			mat = _glow
		_meshers[name] = [RailBuilder.Mesher.new(), mat, range_end, not name.ends_with("Glass")]
	return _meshers[name][0]


func _emit(name: String, m: RailBuilder.Mesher, mat: Material, range_end: float, shadows: bool) -> void:
	if m.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = MeshUtils.save(m.commit(mat), _mesh_dir + "logx_%s.res" % name.to_lower())
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = 20.0
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("plateau", _info("site", "logx:" + name.to_lower(), "Logements élèves de l'X"))
	_node.add_child(mi)


## The frame of a face from map point o along `along` (unit), `out` its outward normal: a box from u0 to u1 along it,
## d0 to d1 out of it, z0 to z1.
static func _face_xf(o: Vector2, along: Vector2, out: Vector2, u0: float, u1: float, d0: float, d1: float, z0: float,
		z1: float) -> Array:
	var c := o + along * (u0 + u1) * 0.5 + out * (d0 + d1) * 0.5
	var xf := Transform3D(Basis(_gd(along), Vector3.UP, _gd(out)), _gp(c, (z0 + z1) * 0.5))
	return [xf, Vector3(absf(u1 - u0), absf(z1 - z0), absf(d1 - d0))]


func _fbox(m: RailBuilder.Mesher, o: Vector2, along: Vector2, out: Vector2, u0: float, u1: float, d0: float, d1: float,
		z0: float, z1: float, col: Color, info := {}) -> void:
	var b := _face_xf(o, along, out, u0, u1, d0, d1, z0, z1)
	m.box(b[0], b[1], col)
	if not info.is_empty():
		MeshUtils.shape_box(_body, b[0], b[1], info)


## A vertical quad facing `out`, d out of the face, from u0 to u1 and z0 to z1.
static func _fquad(m: RailBuilder.Mesher, o: Vector2, along: Vector2, out: Vector2, u0: float, u1: float, d: float,
		z0: float, z1: float, col: Color) -> void:
	var a := o + along * u0 + out * d
	var b := o + along * u1 + out * d
	m.quad(_gp(a, z0), _gp(b, z0), _gp(b, z1), _gp(a, z1), _gd(out), col)


## A window: its frame (four dark bars round an opening, so that a flat built behind the facade sees out: the pane and
## the building's walls are drawn from the outside only), the pane in it (window material: the colour's alpha is its
## random draw for the lights at night), a mullion; `d` out of the face.
func _window(o: Vector2, along: Vector2, out: Vector2, u0: float, u1: float, z0: float, z1: float, d := 0.0,
		mullions := 1) -> void:
	var m := _mesher("Plots")
	var w := _mesher("Plots_Windows", 700.0)
	var f := FRAME_BAR
	_fbox(m, o, along, out, u0, u0 + f, d, d + 0.05, z0, z1, FRAME)
	_fbox(m, o, along, out, u1 - f, u1, d, d + 0.05, z0, z1, FRAME)
	_fbox(m, o, along, out, u0 + f, u1 - f, d, d + 0.05, z0, z0 + f, FRAME)
	_fbox(m, o, along, out, u0 + f, u1 - f, d, d + 0.05, z1 - f, z1, FRAME)
	var tint := CURTAIN if _rng.randf() < 0.25 else PANE
	tint.a = _rng.randf()
	_fquad(w, o, along, out, u0 + f, u1 - f, d + 0.055, z0 + f, z1 - f, tint)
	for k in range(1, mullions + 1):
		var u := u0 + (u1 - u0) * k / (mullions + 1)
		_fbox(m, o, along, out, u - 0.03, u + 0.03, d + 0.05, d + 0.08, z0 + 0.05, z1 - 0.05, FRAME)


# ---------------------------------------------------------------- where things are (also for scripts/online/properties.gd)

## Face `i` of plot `pl`'s upper body: [its first corner, the unit vector along it, its outward normal, its length]
## (map coordinates).
static func face(pl: Dictionary, i: int) -> Array:
	var p := _v2(pl["ring"][i])
	var q := _v2(pl["ring"][(i + 1) % 4])
	var L := p.distance_to(q)
	var along := (q - p) / L
	return [p, along, Vector2(along.y, -along.x), L]


## The window layout of face `i` of plot `pl`: [[centre along a 19.7 m face, 1 alone / 2 a pair], ...].
static func layout(pl: Dictionary, i: int) -> Array:
	return LAYOUTS[(i + int(pl["num"])) % LAYOUTS.size()]


## Window slot `j` of floor `k` (1 the first upper floor) on face `i` of plot `pl`: [its centre along the face, 1 alone
## / 2 a pair].
static func slot(pl: Dictionary, i: int, k: int, j: int) -> Array:
	var lay := layout(pl, i)
	var L: float = face(pl, i)[3]
	var c: float = lay[j][0] * L / 19.7
	var n: int = lay[j][1]
	if n == 1 and j % 2 == 1:
		c += STAGGER[(k + j + int(pl["num"])) % STAGGER.size()]
	var half := WIN_W * 0.5 + (PAIR * 0.5 if n == 2 else 0.0)
	return [clampf(c, half + PIER_W + 0.6, L - half - PIER_W - 0.6), n]


## The windows of slot `j`, floor `k`, face `i`: [[u0, u1], ...] along the face (frames included).
static func slot_windows(pl: Dictionary, i: int, k: int, j: int) -> Array:
	var s := slot(pl, i, k, j)
	var c: float = s[0]
	if s[1] == 2:
		return [[c - PAIR * 0.5 - WIN_W * 0.5, c - PAIR * 0.5 + WIN_W * 0.5],
				[c + PAIR * 0.5 - WIN_W * 0.5, c + PAIR * 0.5 + WIN_W * 0.5]]
	return [[c - WIN_W * 0.5, c + WIN_W * 0.5]]


## Floor `k` (1 the first upper floor) of plot `pl`: [its floor level, the windows' bottom, the windows' top (frames
## included)], heights in Godot y.
static func floor_levels(pl: Dictionary, dims: Dictionary, k: int) -> Array:
	var zp: float = pl["zp"]
	var zk: float = zp + float(dims["ground"]) + float(dims["floor"]) * (k - 1)
	var z1: float = (zk + float(dims["floor"]) - 0.3) if k < int(dims["floors"]) else (zp + float(dims["height"]) - 1.1)
	return [zk, zk + 0.42, z1 - 0.02]


## Plot `pl`'s entrance door (in the porch, beside the plot's number): [its middle on the wall (map), the way out of
## the wall (unit, map), the porch's floor height].
static func porch(pl: Dictionary) -> Array:
	var P := _v2(pl["ring"][int(pl["corner"])])
	var ea := _v2(pl["ea"])
	var eb := _v2(pl["eb"])
	var ci: float = pl["core_in"]
	var ru: float = float(pl["recess"][0]) + ci
	var rv: float = float(pl["recess"][1]) + ci
	return [P + ea * (ru - PORCH_DOOR) + eb * rv, -eb, float(pl["zp"])]


# ---------------------------------------------------------------- the plots

func _plot(pl: Dictionary) -> void:
	var R: Array[Vector2] = []
	for q: Array in pl["ring"]:
		R.append(_v2(q))
	var zp: float = pl["zp"]
	var G: float = _D["ground"]
	var F: float = _D["floor"]
	var nf: int = _D["floors"]
	var H: float = _D["height"]
	var deck: float = zp + H - float(_D["parapet"])
	var m := _mesher("Plots")
	var name := "Logements élèves %s" % pl["num"]
	var info := _info("plot", "logx:plot-%s" % pl["num"], name)
	for i in 4:
		var p := R[i]
		var q := R[(i + 1) % 4]
		var L := p.distance_to(q)
		var along := (q - p) / L
		var out := Vector2(along.y, -along.x)
		# the slab bands, the parapet's band and its coping
		for k in range(1, nf + 1):
			var zk := zp + G + F * (k - 1)
			var d := 0.45 if k % 2 == 1 else 0.30
			_fbox(m, p, along, out, -d, L + d, 0.0, d, zk - 0.3, zk + 0.4, _white)
		_fbox(m, p, along, out, -0.4, L + 0.4, 0.0, 0.4, zp + H - 1.1, zp + H, _white)
		_fbox(m, p, along, out, -0.4, L + 0.4, -0.32, 0.4, zp + H, zp + H + 0.05, _white.lightened(0.04))
		_fquad(m, p, along, -out, 0.3, L - 0.3, 0.31, deck - 0.02, zp + H, _white.darkened(0.04))
		# the floors' windows and their white surrounds
		var lay := layout(pl, i)
		for k in range(1, nf + 1):
			var zk := zp + G + F * (k - 1)
			var z0 := zk + 0.4
			var z1 := (zk + F - 0.3) if k < nf else (zp + H - 1.1)
			for j in lay.size():
				var sl := slot(pl, i, k, j)
				var c: float = sl[0]
				var n: int = sl[1]
				var half := WIN_W * 0.5 + (PAIR * 0.5 if n == 2 else 0.0)
				_fbox(m, p, along, out, c - half - PIER_W, c - half, 0.0, 0.14, z0, z1, _white)
				_fbox(m, p, along, out, c + half, c + half + PIER_W, 0.0, 0.14, z0, z1, _white)
				if n == 2:
					_fbox(m, p, along, out, c - (PAIR - WIN_W) * 0.5, c + (PAIR - WIN_W) * 0.5, 0.0, 0.14, z0, z1, _white)
					_window(p, along, out, c - PAIR * 0.5 - WIN_W * 0.5, c - PAIR * 0.5 + WIN_W * 0.5, z0 + 0.02, z1 - 0.02)
					_window(p, along, out, c + PAIR * 0.5 - WIN_W * 0.5, c + PAIR * 0.5 + WIN_W * 0.5, z0 + 0.02, z1 - 0.02)
				else:
					_window(p, along, out, c - WIN_W * 0.5, c + WIN_W * 0.5, z0 + 0.02, z1 - 0.02)
	_ground_floor(pl, R, zp, info)
	_roof(R, zp, deck, info)


## The ground floor round the core (world.json's tier, white concrete): a dark plinth, white piers, full-height
## glazing or concrete bays (slit window, louvre, service door); in the recess the bike shelter and the porch.
func _ground_floor(pl: Dictionary, R: Array[Vector2], zp: float, info: Dictionary) -> void:
	var m := _mesher("Plots")
	var G: float = _D["ground"]
	var top := zp + G - 0.3
	var c_i: int = pl["corner"]
	var P := R[c_i]
	var ea := _v2(pl["ea"])
	var eb := _v2(pl["eb"])
	var rec: Array = pl["recess"]
	var ci: float = pl["core_in"]
	var ru: float = float(rec[0]) + ci
	var rv: float = float(rec[1]) + ci
	var seed := int(pl["num"])
	var core: Array[Vector2] = []
	for q: Array in pl["core"]:
		core.append(_v2(q))
	var feature := seed
	for e in core.size():
		var a := core[e]
		var b := core[(e + 1) % core.size()]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var along := (b - a) / L
		var out := Vector2(along.y, -along.x)
		_fbox(m, a, along, out, 0.0, L, 0.0, 0.02, zp - 0.15, zp + 0.22, PLINTH)
		var ua := (a - P).dot(ea)
		var va := (a - P).dot(eb)
		var ub := (b - P).dot(ea)
		var vb := (b - P).dot(eb)
		var inner := maxf(ua, ub) <= ru + 0.05 and maxf(va, vb) <= rv + 0.05
		if inner:
			# the porch's wall (along the entrance face, beyond the shelter): the door and the number
			if absf(va - vb) < 0.1:
				var u_door := ru - PORCH_DOOR
				var s0 := (P + ea * (u_door - 0.9) - a).dot(along)
				var s1 := (P + ea * (u_door + 0.9) - a).dot(along)
				_window(a, along, out, minf(s0, s1), maxf(s0, s1), zp + 0.05, zp + 2.6, 0.0, 1)
				_fbox(m, a, along, out, minf(s0, s1) - 0.05, maxf(s0, s1) + 0.05, 0.0, 0.06, zp + 2.6, zp + 2.75, FRAME)
				var sh := (P + ea * (ru - 0.75) - a).dot(along)
				_hexagon(a + along * sh + out * 0.03, out, zp + 2.0, 0.62, String(pl["num"]))
			continue
		# outer faces: bays between white piers
		var nb := maxi(1, roundi(L / 4.2))
		var bw := L / nb
		for k in nb + 1:
			var u := clampf(k * bw, 0.18, L - 0.18)
			_fbox(m, a, along, out, u - 0.18, u + 0.18, 0.0, 0.12, zp - 0.1, top, _white, info if k in [0, nb] else {})
		for k in nb:
			var u0 := k * bw + 0.18
			var u1 := (k + 1) * bw - 0.18
			feature += 1
			if (feature + e) % 3 != 0:
				_window(a, along, out, u0 + 0.05, u1 - 0.05, zp + 0.25, top - 0.15, 0.0, maxi(1, roundi((u1 - u0) / 1.1) - 1))
			else:
				var mid := (u0 + u1) * 0.5
				match feature % 3:
					0:
						_window(a, along, out, mid - 0.35, mid + 0.35, zp + 0.3, top - 0.35, 0.0, 0)
					1:
						_fbox(m, a, along, out, mid - 0.4, mid + 0.4, 0.0, 0.04, zp + 0.3, top - 0.45, LOUVRE)
						for z in range(0, 14):
							_fbox(m, a, along, out, mid - 0.38, mid + 0.38, 0.04, 0.06, zp + 0.4 + z * 0.2,
									zp + 0.46 + z * 0.2, PLINTH)
					_:
						_fbox(m, a, along, out, mid - 0.45, mid + 0.45, 0.0, 0.04, zp + 0.22, zp + 2.3, SERVICE)
	# the recess: columns, the bike shelter (slab, mesh, hoops), downlights in the porch's soffit
	var col_xf := func(u: float, v: float) -> Transform3D:
		return Transform3D(Basis(_gd(ea), Vector3.UP, _gd(-eb)), _gp(P + ea * u + eb * v, (zp - 0.1 + top) * 0.5))
	var cage_u := 5.0
	for u in [0.22, cage_u]:
		var xf: Transform3D = col_xf.call(u, 0.22)
		m.box(xf, Vector3(0.4, top - zp + 0.1, 0.4), _white)
		MeshUtils.shape_box(_body, xf, Vector3(0.4, top - zp + 0.1, 0.4), info)
	var slab_xf := Transform3D(Basis(_gd(ea), Vector3.UP, _gd(-eb)), _gp(P + ea * cage_u * 0.5 + eb * rv * 0.5, zp + 0.05))
	m.box(slab_xf, Vector3(cage_u, 0.4, rv), SLAB)
	MeshUtils.shape_box(_body, slab_xf, Vector3(cage_u, 0.4, rv), info)
	_fbox(m, P, ea, -eb, 0.0, cage_u, 0.0, 0.02, zp - 0.12, zp + 0.25, PLINTH)
	_fbox(m, P, eb, -ea, 0.0, rv, -0.02, 0.0, zp - 0.12, zp + 0.25, PLINTH)
	var gl := _mesher("Plots_Glass", 500.0)
	var mz0 := zp + 0.25
	for run: Array in [[P + eb * 0.12, ea, cage_u - 0.12], [P + ea * 0.12, eb, rv - 0.12], [P + ea * cage_u, eb, rv]]:
		var o: Vector2 = run[0]
		var dir: Vector2 = run[1]
		var len: float = run[2]
		var nrm := Vector2(-dir.y, dir.x)
		_fquad(gl, o, dir, nrm, 0.0, len, 0.0, mz0, top, MESH)
		var posts := maxi(1, ceili(len / 1.6))
		for k in posts + 1:
			var u := len * k / posts
			_fbox(m, o, dir, nrm, u - 0.03, u + 0.03, -0.03, 0.03, mz0, top, STEEL)
		_fbox(m, o, dir, nrm, 0.0, len, -0.025, 0.025, top - 0.06, top, STEEL)
		_fbox(m, o, dir, nrm, 0.0, len, -0.025, 0.025, mz0, mz0 + 0.06, STEEL)
		var b := _face_xf(o, dir, nrm, 0.0, len, -0.04, 0.04, mz0, top)
		MeshUtils.shape_box(_body, b[0], b[1], info)
	for k in 6:
		var u := 0.6 + k * 0.78
		var v1 := rv - 0.3
		var v0 := v1 - 0.7
		for v in [v0, v1]:
			m.box(Transform3D(Basis.IDENTITY, _gp(P + ea * u + eb * v, mz0 + 0.38)), Vector3(0.05, 0.76, 0.05), HOOP)
		var bm := _face_xf(P + ea * u, eb, ea, v0, v1, -0.025, 0.025, mz0 + 0.73, mz0 + 0.79)
		m.box(bm[0], bm[1], HOOP)
	var lights := _mesher("Plots_Lights", 500.0)
	for uv: Array in [[ru - 2.0, rv * 0.35], [ru - 2.0, rv * 0.75], [2.5, rv * 0.5]]:
		var c := P + ea * float(uv[0]) + eb * float(uv[1])
		lights.quad(_gp(c + ea * 0.2 + eb * 0.2, top - 0.01), _gp(c - ea * 0.2 + eb * 0.2, top - 0.01),
				_gp(c - ea * 0.2 - eb * 0.2, top - 0.01), _gp(c + ea * 0.2 - eb * 0.2, top - 0.01), Vector3.DOWN, GLOW)


## The plot's number in white on a black hexagon (photo: "22").
func _hexagon(c: Vector2, out: Vector2, z: float, r: float, text: String) -> void:
	var m := _mesher("Plots")
	var along := Vector2(-out.y, out.x)
	var pts: Array[Vector3] = []
	for k in 6:
		var a := PI / 6.0 + k * PI / 3.0
		pts.append(_gp(c + along * cos(a) * r, z + sin(a) * r))
	var cen := _gp(c, z)
	for k in 6:
		m.tri(cen, pts[k], pts[(k + 1) % 6], _gd(out), HEX)
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.9 * r / 96.0 * 1.25
	l.outline_size = 0
	l.modulate = Color("#f2f2ee")
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	var z_ax := _gd(out)
	l.transform = Transform3D(Basis(Vector3.UP.cross(z_ax).normalized(), Vector3.UP, z_ax), _gp(c + out * 0.01, z))
	l.visibility_range_end = 120.0
	l.name = "PlotNumber_%s" % text
	_node.add_child(l)


## The roof: the atrium's skylight on a white upstand, two ventilation units, a hatch.
func _roof(R: Array[Vector2], zp: float, deck: float, info: Dictionary) -> void:
	var m := _mesher("Plots")
	var gl := _mesher("Plots_Glass", 600.0)
	var c := (R[0] + R[1] + R[2] + R[3]) * 0.25
	var e1 := (R[1] - R[0]).normalized()
	var e2 := Vector2(-e1.y, e1.x)
	var bs := Basis(_gd(e1), Vector3.UP, _gd(-e2))
	var up := Transform3D(bs, _gp(c, deck + 0.2))
	m.box(up, Vector3(4.6, 0.4, 4.6), _white)
	MeshUtils.shape_box(_body, up, Vector3(4.6, 0.4, 4.6), info)
	var g0 := deck + 0.4
	var g1 := deck + 0.9
	var corners: Array[Vector2] = [c + e1 * 2.1 + e2 * 2.1, c - e1 * 2.1 + e2 * 2.1, c - e1 * 2.1 - e2 * 2.1,
			c + e1 * 2.1 - e2 * 2.1]
	gl.quad(_gp(corners[0], g1), _gp(corners[1], g1), _gp(corners[2], g1), _gp(corners[3], g1), Vector3.UP, Color("#bfd9e6"))
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var mid := (a + b) * 0.5 - c
		gl.quad(_gp(a, g0), _gp(b, g0), _gp(b, g1), _gp(a, g1), _gd(mid.normalized()), Color("#bfd9e6"))
		var bm := _face_xf(a, (b - a).normalized(), mid.normalized(), 0.0, a.distance_to(b), -0.03, 0.03, g1 - 0.05, g1)
		m.box(bm[0], bm[1], FRAME)
	for spec: Array in [[5.2, 4.0, 2.4, 1.1, 1.1], [-5.6, -3.6, 2.4, 1.1, 1.1], [-1.5, -6.2, 1.0, 1.0, 0.7]]:
		var p := c + e1 * float(spec[0]) + e2 * float(spec[1])
		var size := Vector3(spec[2], spec[4], spec[3])
		var xf := Transform3D(bs, _gp(p, deck + float(spec[4]) * 0.5))
		m.box(xf, size, PLANT)
		MeshUtils.shape_box(_body, xf, size, info)
		if float(spec[2]) > 2.0:
			m.box(Transform3D(bs, _gp(p, deck + float(spec[4]) + 0.01)), Vector3(size.x - 0.3, 0.02, size.z - 0.3), PLINTH)


# ---------------------------------------------------------------- round the plots

## The boulevard sidewalk's kerb: a lighter stone on its edge and the stone's face down to the road.
func _kerb() -> void:
	var m := _mesher("Site_Kerbs", 400.0)
	var pts: Array = _L["kerb"]
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		if a.distance_to(b) < 0.01:
			continue
		var e := (b - a).normalized()
		var inward := Vector2(-e.y, e.x)          # the sidewalk's side (north of the kerb, which runs west -> east)
		var za := float(pts[i][2])
		var zb := float(pts[i + 1][2])
		var ai := a + inward * 0.3
		var bi := b + inward * 0.3
		m.quad(_gp(a, za + 0.006), _gp(b, zb + 0.006), _gp(bi, zb + 0.006), _gp(ai, za + 0.006), Vector3.UP, KERB_TOP)
		var ao := a - inward * 0.012
		var bo := b - inward * 0.012
		m.quad(_gp(ao, za - 0.2), _gp(bo, zb - 0.2), _gp(bo, zb + 0.006), _gp(ao, za + 0.006), _gd(-inward), KERB_FACE)


## The car park's kerb stones, flush with the ground on both sides: 0.15 m wide, 0.1 m proud.
func _borders() -> void:
	var m := _mesher("Site_Kerbs", 400.0)
	for run: Array in _L["copings"]:
		for i in run.size() - 1:
			var a := Vector2(run[i][0], run[i][1])
			var b := Vector2(run[i + 1][0], run[i + 1][1])
			var length := a.distance_to(b)
			if length < 0.02:
				continue
			var z := (float(run[i][2]) + float(run[i + 1][2])) * 0.5
			var d := (b - a) / length
			var bx := _face_xf(a, d, Vector2(-d.y, d.x), -0.07, length + 0.07, -0.075, 0.075, z - 0.08, z + 0.1)
			m.box(bx[0], bx[1], BORDER)


func _markings() -> void:
	var m := _mesher("Site_Paint", 300.0)
	var a: Array = _L["markings"]["white"]
	for k in range(0, a.size() - 8, 9):
		m.tri(Vector3(a[k], a[k + 2], -a[k + 1]), Vector3(a[k + 3], a[k + 5], -a[k + 4]),
				Vector3(a[k + 6], a[k + 8], -a[k + 7]), Vector3.UP, PAINT)


## Light bollards (photos: dark grey cylinders ~1 m, a glowing head).
func _bollards() -> void:
	var m := _mesher("Site_Furniture", 300.0)
	var g := _mesher("Site_Lights", 300.0)
	var info := _info("bollard", "logx:bollards", "Borne lumineuse")
	for b: Array in _L["bollards"]:
		var p := _v2(b)
		var z := _ground.at(p.x, p.y)
		_prism(m, p, 0.1, z - 0.05, z + 0.8, BOLLARD)
		_prism(g, p, 0.101, z + 0.8, z + 0.9, GLOW)
		_prism(m, p, 0.105, z + 0.9, z + 0.98, BOLLARD)
		MeshUtils.shape_box(_body, Transform3D(Basis.IDENTITY, _gp(p, z + 0.5)), Vector3(0.2, 1.0, 0.2), info)


## An octagonal prism (radius r) from z0 to z1 with its top.
static func _prism(m: RailBuilder.Mesher, c: Vector2, r: float, z0: float, z1: float, col: Color) -> void:
	var pts: Array[Vector2] = []
	for k in 8:
		var a := k * TAU / 8.0 + PI / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in 8:
		var a := pts[k]
		var b := pts[(k + 1) % 8]
		var n := ((a + b) * 0.5 - c).normalized()
		m.quad(_gp(a, z0), _gp(b, z0), _gp(b, z1), _gp(a, z1), _gd(n), col)
		m.tri(_gp(c, z1), _gp(a, z1), _gp(b, z1), Vector3.UP, col)


## Limestone boulders (photo): low irregular blocks, a ring of seven points at the foot, a smaller tilted one on top.
func _rocks() -> void:
	var m := _mesher("Site_Furniture", 300.0)
	var info := _info("boulder", "logx:boulders", "Bloc calcaire")
	for r: Array in _L["rocks"]:
		var p := _v2(r)
		var z := _ground.at(p.x, p.y)
		var yaw := deg_to_rad(float(r[2]))
		var sx: float = r[3]
		var sy: float = r[4]
		var sz: float = r[5]
		var low: Array[Vector3] = []
		var top: Array[Vector3] = []
		for k in 7:
			var a := yaw + k * TAU / 7.0
			var f := 0.82 + 0.3 * _rng.randf()
			var d := Vector2(cos(a) * sx * 0.5, sin(a) * sy * 0.5) * f
			low.append(_gp(p + d, z - 0.05))
			top.append(_gp(p + d * (0.55 + 0.2 * _rng.randf()), z + sz * (0.8 + 0.35 * _rng.randf())))
		var apex := _gp(p + Vector2(0.1 * sx, -0.05 * sy), z + sz * 1.05)
		for k in 7:
			var j := (k + 1) % 7
			var side := ((low[k] + low[j]) * 0.5 - _gp(p, low[k].y)).normalized()
			var col := ROCK.darkened(0.06 * (k % 3))
			m.quad(low[k], low[j], top[j], top[k], (side + Vector3.UP * 0.4).normalized(), col)
			m.tri(top[k], top[j], apex, Vector3.UP, ROCK.lightened(0.05))
		MeshUtils.shape_box(_body, Transform3D(Basis(Vector3.UP, yaw), _gp(p, z + sz * 0.45)), Vector3(sx * 0.9, sz * 0.9, sy * 0.9), info)


## Mulch rings under the young trees (photos): a low cone of wood chips.
func _mulch() -> void:
	var m := _mesher("Site_Mulch", 250.0)
	for r: Array in _L["mulch"]:
		var c := _v2(r)
		var rad: float = r[2]
		var zc := _ground.at(c.x, c.y) + 0.09
		var rim: Array[Vector3] = []
		for k in 12:
			var a := k * TAU / 12.0
			var q := c + Vector2(cos(a), sin(a)) * rad
			rim.append(_gp(q, _ground.at(q.x, q.y) + 0.015))
		for k in 12:
			m.tri(_gp(c, zc), rim[k], rim[(k + 1) % 12], Vector3.UP, MULCH)
