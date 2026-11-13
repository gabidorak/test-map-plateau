extends RefCounted
## Lot ligne18-viaduc's works drawn (viaduc_layout.gd says what goes where; ligne18_plan.gd the line): one cell at a
## time (build_cell(k): a Node3D, s from cuts[k] to cuts[k + 1]), in the map's frame (Godot (x, z, -y)), everything
## swept along the axis frame by frame (every 5 m: the plan's nodes, the rails' profile linear between them):
## - the deck, piece by piece: the plan's section() (the spine and its walkway, the slab, the thin edges; z over the
##   rails' top), its soffit with the AVPm's transverse ribs (coffers COFFER_DEPTH deep between ribs RIB wide, BAY m
##   apart, END_ZONE m solid at each bearing line), the end faces (section() exactly: at a station's zone_s, at s_edge),
##   the edge fascias;
## - the ramp (cell 0): its trackbed between retaining walls down to the ground, the abutment (its seat, its backwall,
##   the first span's bearings);
## - the top equipment (Layout.runs(): not over the stations' zones): the parapets (posts, a top rail, stainless
##   cables: a panel textured with them, faded to a haze far off), the cable troughs, the walkway's axial handrail;
## - the tracks, along the whole line: the plinths (their baseplates painted), the rails (rails' top at rail_z), the
##   third rail on each track's inner side under its cover, on insulators;
## - the piers (the plan's piers()): elliptic shafts from FOOT m into the game's ground (ground_map.gd: terraformed) to
##   soffit - BEARING, a perforated-metal collar from below the head up to the soffit round the bearings; a single
##   pier's head flared; a kerbed island round those of Layout.ISLAND_PIERS.
## Each cell: "Collision" (a StaticBody3D: the deck's outline, the trackbed, plinths, troughs, parapets as faces; the
## piers as convex prisms), made by build_cell(); "Near" (one MeshInstance3D per material) and "Far" (its own far
## shape: the deck's outline simplified, the piers' prisms, the ramp's walls; one plain material, no lit windows),
## computed by mesh_arrays() (pure: on a worker thread in the game) and put in place by fill(); none headless.

const Plan = preload("res://scripts/ligne18/ligne18_plan.gd")
const Layout = preload("res://scripts/ligne18/viaduc/viaduc_layout.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const OWN_VISIBILITY := "lot_own_visibility"  # (builder/lot_far.gd: the cells stream themselves, ligne18_viaduc.gd)

# the section, z over the rails' top (ligne18_plan.gd: the deck's top face RAIL_OVER_DECK under them)
const DECK_TOP := -0.47
const SPINE := 1.075                        # |v| of the spine's sides
const WALKWAY := 0.96                       # the walkway's top
const EDGE := 4.845                         # |v| of the deck's edge
const EDGE_LOW := -0.87                     # the edge's underside
const SOFFIT := -1.78                       # the soffit under the spine
const SOFFIT_V := 1.6                       # |v| where it starts sloping up to the edge
const RAIL_V := 0.7525                      # m: a rail's centre off its track's centre (gauge + a head)
const PLINTH := Vector2(1.55, 3.90)         # |v| of a track's plinth
const PLINTH_TOP := -0.17
const FASTENING := 0.75                     # m between two baseplates
const CONDUCTOR_V := 1.30                   # |v| of the third rail
const COVER := Vector2(1.17, 1.47)          # |v| of its cover board
const TROUGH := Vector2(4.15, 4.70)         # |v| of the cable troughs along the edges
const TROUGH_TOP := -0.22
const FASCIA := Vector2(-0.95, -0.40)       # z of the edge fascia (|v| EDGE .. Plan.EDGE_HALF)
const PARAPET_V := 4.80                     # |v| of the parapets' posts and cables
const POST_STEP := 1.5                      # m between two posts
const CABLES := Vector2(0.10, 1.42)         # m over the deck's top: the cables' panel
const HANDRAIL_H := 0.80                    # m over the walkway: its axial handrail
const HANDRAIL_STEP := 2.0
const COPING := 0.12                        # m: the ramp's walls over its trackbed
# the soffit's ribs (AVPm: 13 x 2.40 m between the end zones of a 35 m span)
const END_ZONE := 1.87
const BAY := 2.40
const RIB := 0.40
const CHAMFER := 0.12
const COFFER_DEPTH := 0.12
const COFFER_V := [1.6, 1.85, 1.97, 4.43, 4.55, 4.845]
const COFFER_IN := [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
# piers
const FOOT := 1.0                           # m into the ground
const COLLAR_H := 0.45                      # m: the collar below the head's top
const COLLAR_OUT := 0.03                    # m: the collar round the shaft
const RING := 24                            # segments round a shaft
const FLARE_H := 2.6                        # m: a single pier's flared head
const HEAD_SINGLE := Vector2(1.525, 2.3)    # its top, half along half across
const ISLAND_UP := 0.15                     # m: an island's kerb over the ground

const COLOURS := {
	"concrete": "#d7d6d0", "fascia": "#dddcd6", "coffer": "#cbcac4", "walkway": "#bebdb6", "plinth": "#c3c2bb",
	"rail": "#5b4f46", "rail_top": "#b7bbbe", "conductor": "#6e7276", "cover": "#d3c89a", "steel": "#c9cdd1",
	"bearing": "#3b3c3e", "joint": "#4a4b4d", "kerb": "#c9c3b7", "island": "#b7b3aa", "far": "#d2d1cb",
}

static var _mats := {}
static var _mottle_tex: Texture2D

var near: Acc
var far: Acc
var faces := PackedVector3Array()           # the cell's collision faces
var body: StaticBody3D
var _col_on := true                         # (collision shapes made: not when only the near meshes are)
var piers_built: Array = []                 # per pier built: {s, type, top, bottom, ground_min, shafts: [map centre]}


## One material's triangles.
class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()


## Triangles per material, committed as one mesh each.
class Acc:
	var on := true
	var surfs := {}

	## A triangle facing its normals (Godot: front faces wind clockwise seen from the front).
	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		if not on:
			return
		var s: Surf = surfs.get(m)
		if s == null:
			s = Surf.new()
			surfs[m] = s
		s.v.append(a)
		s.n.append(na)
		s.uv.append(ua)
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			s.v.append(c)
			s.n.append(nc)
			s.uv.append(uc)
			s.v.append(b)
			s.n.append(nb)
			s.uv.append(ub)
		else:
			s.v.append(b)
			s.n.append(nb)
			s.uv.append(ub)
			s.v.append(c)
			s.n.append(nc)
			s.uv.append(uc)

	## A quad a b c d (round it), its corners' normals.
	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			nd: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		tri(m, a, b, c, na, nb, nc, ua, ub, uc)
		tri(m, a, c, d, na, nc, nd, ua, uc, ud)

	## A flat quad facing n.
	func flat(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		tri(m, a, b, c, n, n, n)
		tri(m, a, c, d, n, n, n)

## The axis's frame at s: its point at the rails' top, its left and along (Godot, unit, level).
class F:
	var s: float
	var o: Vector3
	var l: Vector3
	var t: Vector3

	## Its point v to the left, dz over the rails' top.
	func p(v: float, dz: float) -> Vector3:
		return o + l * v + Vector3(0.0, dz, 0.0)

	## A section's direction (v, z) as a normal.
	func n(d: Vector2) -> Vector3:
		return (l * d.x + Vector3(0.0, d.y, 0.0)).normalized()


static func frame_at(s: float) -> F:
	var f := F.new()
	f.s = s
	var m := Plan.point(s)
	f.o = Vector3(m.x, Plan.rail_z(s), -m.y)
	var h := Plan.heading(s)
	f.t = Vector3(cos(h), 0.0, -sin(h))
	f.l = Vector3(-sin(h), 0.0, -cos(h))
	return f


## Frames from s0 to s1: its ends and the plan's nodes (every `step` m) between.
static func samples(s0: float, s1: float, step := 5.0) -> Array:
	var out := [frame_at(s0)]
	var k := floori(s0 / step) + 1
	while k * step < s1 - 0.01:
		if k * step > s0 + 0.01:
			out.append(frame_at(k * step))
		k += 1
	out.append(frame_at(s1))
	return out


## The game's ground at map (x, y) (terraformed: ground_map.gd), or the plan's on the axis.
static func ground(x: float, y: float) -> float:
	var gm: RefCounted = GroundMap.get_map()
	if gm:
		return gm.height(x, y)
	var sv := Plan.project(Vector2(x, y))
	return Plan.plan_ground_z(sv.x) if not is_nan(sv.x) else 0.0


## The deck's soffit at |v| (z over the rails' top).
static func soffit_at(v: float) -> float:
	var a := absf(v)
	if a <= SOFFIT_V:
		return SOFFIT
	return SOFFIT + (minf(a, EDGE) - SOFFIT_V) / (EDGE - SOFFIT_V) * (EDGE_LOW - SOFFIT)


## Cell k: its node and its collision; when `with_meshes`, an empty "Near" and "Far" (mesh_arrays() makes their
## meshes, fill() puts them there) and its box (meta "box": the streamer's).
func build_cell(k: int, with_meshes: bool) -> Node3D:
	_begin(false, false, true)
	var r := Layout.cell_range(k)
	var cell := Node3D.new()
	cell.name = "Cell%02d" % k
	cell.set_meta("s", r)
	cell.add_to_group(OWN_VISIBILITY)
	body = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Layers.BUILDINGS
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "lot", "lot": "ligne18-viaduc", "name": "Ligne 18 : viaduc",
			"about": "s %.0f .. %.0f" % [r.x, r.y]})
	cell.add_child(body)
	var built := _content(k)
	cell.set_meta("piers", built)
	piers_built.append_array(built)
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.name = "Faces"
		cs.shape = shape
		body.add_child(cs)
	faces = PackedVector3Array()
	if with_meshes:
		var n := Node3D.new()
		n.name = "Near"
		cell.add_child(n)
		cell.set_meta("near", [] as Array[Node3D])
		var f := MeshInstance3D.new()
		f.name = "Far"
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false                                   # (the streamer decides)
		cell.add_child(f)
		cell.set_meta("far", f)
		var lo := INF
		for q: Dictionary in built:
			lo = minf(lo, q["bottom"])
		var box := AABB(Plan.godot_at(r.x, 0.0, Plan.rail_z(r.x)), Vector3.ZERO)
		var s := r.x
		while true:                                         # (the deck and its parapets, the piers' feet)
			for v: float in [-6.0, 6.0]:
				var g := Plan.godot_at(s, v, Plan.rail_z(s) + 2.5)
				box = box.expand(g).expand(Vector3(g.x, minf(lo, Plan.rail_z(s) - 3.0), g.z))
			if s >= r.y:
				break
			s = minf(s + 10.0, r.y)
		cell.set_meta("box", box)
	return cell


## Cell k's meshes, as arrays: {"near": material -> [vertices, normals, uvs], "far": [vertices, normals, uvs]}:
## computed only (any thread).
func mesh_arrays(k: int) -> Dictionary:
	_begin(true, true, false)
	_content(k)
	faces = PackedVector3Array()
	var out := {}
	for m: String in near.surfs:
		var s: Surf = near.surfs[m]
		out[m] = [s.v, s.n, s.uv]
	var fs: Surf = far.surfs.get("far", Surf.new())
	near.surfs = {}
	far.surfs = {}
	return {"near": out, "far": [fs.v, fs.n, fs.uv]}


## mesh_arrays()'s meshes into `cell` (main thread): its near ones into "Near" (also in its meta "near"), its far
## shape into "Far".
static func fill(cell: Node3D, arrays: Dictionary) -> Array[Node3D]:
	var parent := cell.get_node("Near") as Node3D
	var out: Array[Node3D] = []
	var near: Dictionary = arrays["near"]
	for m: String in near:
		var e: Array = near[m]
		if (e[0] as PackedVector3Array).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "M_" + m
		mi.mesh = _mesh(e)
		mi.material_override = material(m)
		if m == "cables":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	cell.set_meta("near", out)
	var f: Array = arrays["far"]
	if not (f[0] as PackedVector3Array).is_empty():
		var fm := cell.get_node("Far") as MeshInstance3D
		fm.mesh = _mesh(f)
		fm.material_override = material("far")
	return out


static func _mesh(e: Array) -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = e[0]
	a[Mesh.ARRAY_NORMAL] = e[1]
	a[Mesh.ARRAY_TEX_UV] = e[2]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


func _begin(near_on: bool, far_on: bool, col_on: bool) -> void:
	near = Acc.new()
	far = Acc.new()
	near.on = near_on
	far.on = far_on
	_col_on = col_on
	faces = PackedVector3Array()


## What cell k holds (into near, far, faces, body); the piers built.
func _content(k: int) -> Array:
	var r := Layout.cell_range(k)
	if k == 0:
		_ramp()
	for p: Dictionary in Layout.cell_pieces(k):
		_deck(p)
	for run: Vector2 in Layout.runs():
		var a := maxf(run.x, r.x)
		var b := minf(run.y, r.y)
		if b - a > 0.01:
			_equipment(a, b)
	_track(r.x, r.y)
	var built := []
	for p: Dictionary in Layout.cell_piers(k):
		built.append(_pier(p))
	return built


# ---------------------------------------------------------------- sweeps

## A strip along frames fs from section point a to b (v, z over the rails' top), facing n2 (v, z); into the
## collision too when `col`. uv: 0 none, 1 a plinth's top, 2 the cables' panel.
func _strip(acc: Acc, m: String, fs: Array, a: Vector2, b: Vector2, n2: Vector2, col := false, uv := 0) -> void:
	for i in fs.size() - 1:
		var f0: F = fs[i]
		var f1: F = fs[i + 1]
		var a0 := f0.p(a.x, a.y)
		var b0 := f0.p(b.x, b.y)
		var a1 := f1.p(a.x, a.y)
		var b1 := f1.p(b.x, b.y)
		if acc.on:
			var n0 := f0.n(n2)
			var n1 := f1.n(n2)
			if uv == 0:
				acc.quad(m, a0, b0, b1, a1, n0, n0, n1, n1)
			elif uv == 1:
				var ua := (absf(a.x) - PLINTH.x) / (PLINTH.y - PLINTH.x)
				var ub := (absf(b.x) - PLINTH.x) / (PLINTH.y - PLINTH.x)
				acc.quad(m, a0, b0, b1, a1, n0, n0, n1, n1, Vector2(ua, f0.s / FASTENING),
						Vector2(ub, f0.s / FASTENING), Vector2(ub, f1.s / FASTENING), Vector2(ua, f1.s / FASTENING))
			else:
				var va := 1.0 - (a.y - DECK_TOP - CABLES.x) / (CABLES.y - CABLES.x)
				var vb := 1.0 - (b.y - DECK_TOP - CABLES.x) / (CABLES.y - CABLES.x)
				acc.quad(m, a0, b0, b1, a1, n0, n0, n1, n1, Vector2(f0.s, va), Vector2(f0.s, vb), Vector2(f1.s, vb),
						Vector2(f1.s, va))
		if col:
			faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))


## A closed or open profile (points v, z) swept along fs, each edge facing out of it (the profile wound clockwise in
## (v, z): up its left side, over, down its right); `mats` per edge (or one).
func _sweep(acc: Acc, mats: Variant, fs: Array, pts: Array, col := false) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		var m: String = mats[i] if mats is Array else mats
		_strip(acc, m, fs, a, b, Vector2(-d.y, d.x).normalized(), col)


## A box in frame f: along al (x0, x1), across v (x0, x1), z over the rails' top (x0, x1); its bottom left out
## unless `bottom`.
func _box(acc: Acc, m: String, f: F, al: Vector2, v: Vector2, z: Vector2, bottom := false, col := false) -> void:
	var c := func(i: float, j: float, k: float) -> Vector3: return f.o + f.t * i + f.l * j + Vector3(0.0, k, 0.0)
	var p000: Vector3 = c.call(al.x, v.x, z.x)
	var p100: Vector3 = c.call(al.y, v.x, z.x)
	var p010: Vector3 = c.call(al.x, v.y, z.x)
	var p110: Vector3 = c.call(al.y, v.y, z.x)
	var p001: Vector3 = c.call(al.x, v.x, z.y)
	var p101: Vector3 = c.call(al.y, v.x, z.y)
	var p011: Vector3 = c.call(al.x, v.y, z.y)
	var p111: Vector3 = c.call(al.y, v.y, z.y)
	var q := [[p001, p101, p111, p011, Vector3.UP], [p000, p100, p101, p001, -f.l], [p010, p110, p111, p011, f.l],
			[p000, p010, p011, p001, -f.t], [p100, p110, p111, p101, f.t]]
	if bottom:
		q.append([p000, p100, p110, p010, Vector3.DOWN])
	for e: Array in q:
		acc.flat(m, e[0], e[1], e[2], e[3], e[4])
		if col:
			faces.append_array(PackedVector3Array([e[0], e[1], e[2], e[0], e[2], e[3]]))


## An end face of the deck: section() at frame f, facing `out` (+-f.t).
func _cap(acc: Acc, f: F, out: Vector3, col := true) -> void:
	var sec := Plan.section()
	var idx := Geometry2D.triangulate_polygon(sec)
	for i in range(0, idx.size(), 3):
		var a := f.p(sec[idx[i]].x, sec[idx[i]].y)
		var b := f.p(sec[idx[i + 1]].x, sec[idx[i + 1]].y)
		var c := f.p(sec[idx[i + 2]].x, sec[idx[i + 2]].y)
		acc.tri("concrete", a, b, c, out, out, out)
		if col:
			faces.append_array(PackedVector3Array([a, b, c]))


# ---------------------------------------------------------------- the deck

## A deck piece (Layout.pieces()): its outline swept, its soffit's coffers, its end faces, its fascias; its far shape.
func _deck(p: Dictionary) -> void:
	var s0: float = p["s0"]
	var s1: float = p["s1"]
	var fs := samples(s0, s1)
	# the top: the edges' tops, the slab's top, the spine and its walkway (the edges' faces go with the soffit)
	var top := [Vector2(-EDGE, DECK_TOP), Vector2(-SPINE, DECK_TOP), Vector2(-SPINE, WALKWAY), Vector2(SPINE, WALKWAY),
			Vector2(SPINE, DECK_TOP), Vector2(EDGE, DECK_TOP)]
	_sweep(near, ["concrete", "concrete", "walkway", "concrete", "concrete"], fs, top, true)
	# the soffit: the coffers' grid, its s cut at the nodes and at the ribs' breaks
	var cuts := PackedFloat64Array()
	for f: F in fs:
		cuts.append(f.s)
	var a0: float = p["a0"]
	var a1: float = p["a1"]
	var span := a1 - a0 - 2.0 * END_ZONE
	var ribs := PackedFloat64Array()                        # [start, floor start, floor end, end] per coffer
	if span > BAY * 0.5:
		var n := maxi(1, roundi(span / BAY))
		var bay := span / n
		for i in n:
			var b0 := a0 + END_ZONE + i * bay + RIB * 0.5
			var b1 := a0 + END_ZONE + (i + 1) * bay - RIB * 0.5
			for s: float in [b0, b0 + CHAMFER, b1 - CHAMFER, b1]:
				ribs.append(s)
	for s in ribs:
		if s > s0 + 0.01 and s < s1 - 0.01:
			cuts.append(s)
	cuts.sort()
	var ss: Array = []
	var depth := PackedFloat32Array()
	for s in cuts:
		if not ss.is_empty() and s - (ss[ss.size() - 1] as F).s < 0.005:
			continue
		ss.append(frame_at(s))
		depth.append(_coffer(s, ribs))
	if near.on:
		for side: float in [1.0, -1.0]:
			_soffit_wing(ss, depth, side)
		var flat := [Vector2(SOFFIT_V, SOFFIT), Vector2(-SOFFIT_V, SOFFIT)]
		_strip(near, "concrete", ss, flat[0], flat[1], Vector2(0, -1))
		for side: float in [1.0, -1.0]:
			_strip(near, "concrete", ss, Vector2(side * EDGE, DECK_TOP), Vector2(side * EDGE, EDGE_LOW), Vector2(side, 0))
	# its collision: the plain outline
	for side: float in [1.0, -1.0]:
		var a := Vector2(side * EDGE, EDGE_LOW)
		var b := Vector2(side * SOFFIT_V, SOFFIT)
		faces_strip(fs, Vector2(side * EDGE, DECK_TOP), a)
		faces_strip(fs, a, b)
	faces_strip(fs, Vector2(SOFFIT_V, SOFFIT), Vector2(-SOFFIT_V, SOFFIT))
	# the end faces; over a pier, the joint's filler to the next span
	_cap(near, fs[0], -(fs[0] as F).t)
	_cap(near, fs[fs.size() - 1], (fs[fs.size() - 1] as F).t)
	if p["end1"] == "pier" and near.on:
		var sec := Array(Plan.section())
		sec.append(sec[0])
		_sweep(near, "joint", [frame_at(s1 - 0.01), frame_at(s1 + Layout.JOINT + 0.01)], sec)
	# the fascias along the edges
	for side: float in [1.0, -1.0]:
		var e0 := side * EDGE
		var e1 := side * Plan.EDGE_HALF
		_strip(near, "fascia", fs, Vector2(e1, FASCIA.y), Vector2(e1, FASCIA.x), Vector2(side, 0))
		_strip(near, "fascia", fs, Vector2(e0, FASCIA.y), Vector2(e1, FASCIA.y), Vector2(0, 1))
		_strip(near, "fascia", fs, Vector2(e0, FASCIA.x), Vector2(e1, FASCIA.x), Vector2(0, -1))
		_strip(near, "fascia", fs, Vector2(e0, DECK_TOP), Vector2(e0, FASCIA.y), Vector2(-side, 0))
		for f: F in [fs[0], fs[fs.size() - 1]]:
			var out: Vector3 = f.t if f == fs[fs.size() - 1] else -f.t
			near.flat("fascia", f.p(e0, FASCIA.x), f.p(e1, FASCIA.x), f.p(e1, FASCIA.y), f.p(e0, FASCIA.y), out)
	# its far shape: the outline simplified, every 10 m
	var ff := samples(s0, s1, 10.0)
	var fo := [Vector2(-Plan.EDGE_HALF, FASCIA.x), Vector2(-Plan.EDGE_HALF, DECK_TOP), Vector2(-SPINE, DECK_TOP),
			Vector2(-SPINE, WALKWAY), Vector2(SPINE, WALKWAY), Vector2(SPINE, DECK_TOP), Vector2(Plan.EDGE_HALF, DECK_TOP),
			Vector2(Plan.EDGE_HALF, FASCIA.x), Vector2(SOFFIT_V, SOFFIT), Vector2(-SOFFIT_V, SOFFIT),
			Vector2(-Plan.EDGE_HALF, FASCIA.x)]
	_sweep(far, "far", ff, fo)
	var fidx := Geometry2D.triangulate_polygon(PackedVector2Array(fo.slice(0, fo.size() - 1)))
	for f: F in [ff[0], ff[ff.size() - 1]]:
		var out: Vector3 = f.t if f == ff[ff.size() - 1] else -f.t
		for i in range(0, fidx.size(), 3):
			var a: Vector2 = fo[fidx[i]]
			var b: Vector2 = fo[fidx[i + 1]]
			var c: Vector2 = fo[fidx[i + 2]]
			far.tri("far", f.p(a.x, a.y), f.p(b.x, b.y), f.p(c.x, c.y), out, out, out)


## Collision faces along fs between section points a and b.
func faces_strip(fs: Array, a: Vector2, b: Vector2) -> void:
	for i in fs.size() - 1:
		var f0: F = fs[i]
		var f1: F = fs[i + 1]
		var a0 := f0.p(a.x, a.y)
		var b0 := f0.p(b.x, b.y)
		var a1 := f1.p(a.x, a.y)
		var b1 := f1.p(b.x, b.y)
		faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))


## How deep the soffit's coffer is at s (0 on the ribs and in the end zones, 1 in a coffer's floor).
static func _coffer(s: float, ribs: PackedFloat64Array) -> float:
	for i in range(0, ribs.size(), 4):
		if s <= ribs[i] or s >= ribs[i + 3]:
			continue
		if s < ribs[i + 1]:
			return (s - ribs[i]) / CHAMFER
		if s > ribs[i + 2]:
			return (ribs[i + 3] - s) / CHAMFER
		return 1.0
	return 0.0


## One wing's soffit (side +1 left, -1 right): the coffers' grid over frames ss (depth: theirs at each), flat facets.
func _soffit_wing(ss: Array, depth: PackedFloat32Array, side: float) -> void:
	var grid := []
	for i in ss.size():
		var f: F = ss[i]
		var row := PackedVector3Array()
		for j in COFFER_V.size():
			var v: float = COFFER_V[j]
			row.append(f.p(side * v, soffit_at(v) + COFFER_DEPTH * depth[i] * float(COFFER_IN[j])))
		grid.append(row)
	for i in ss.size() - 1:
		var r0: PackedVector3Array = grid[i]
		var r1: PackedVector3Array = grid[i + 1]
		for j in COFFER_V.size() - 1:
			var a := r0[j]
			var b := r0[j + 1]
			var c := r1[j + 1]
			var d := r1[j]
			var in_floor: bool = COFFER_IN[j] * COFFER_IN[j + 1] > 0.0 and depth[i] >= 1.0 and depth[i + 1] >= 1.0
			var m := "coffer" if in_floor else "concrete"
			for t: Array in [[a, b, c], [a, c, d]]:
				var n: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0])
				if n.length_squared() < 1e-12:
					continue
				n = n.normalized()
				if n.y > 0.0:
					n = -n
				near.tri(m, t[0], t[1], t[2], n, n, n)


# ---------------------------------------------------------------- the ramp and the abutment

## The ramp (s_start .. the abutment): its trackbed and spine between retaining walls down FOOT m into the ground, its
## start's face; the abutment: its seat (the first span's bearings on it), its backwall.
func _ramp() -> void:
	var s_ab := Layout.s_abutment()
	var end := s_ab - Layout.ABUT_DECK - 0.03
	var fs := samples(Layout.s_start(), end)
	var top := [Vector2(-EDGE, DECK_TOP), Vector2(-SPINE, DECK_TOP), Vector2(-SPINE, WALKWAY), Vector2(SPINE, WALKWAY),
			Vector2(SPINE, DECK_TOP), Vector2(EDGE, DECK_TOP)]
	_sweep(near, ["concrete", "concrete", "walkway", "concrete", "concrete"], fs, top, true)
	var w := Layout.RAMP_HALF
	for side: float in [1.0, -1.0]:
		_strip(near, "concrete", fs, Vector2(side * EDGE, DECK_TOP), Vector2(side * EDGE, DECK_TOP + COPING),
				Vector2(-side, 0), true)
		_strip(near, "concrete", fs, Vector2(side * EDGE, DECK_TOP + COPING), Vector2(side * w, DECK_TOP + COPING),
				Vector2(0, 1), true)
		# the wall's face, down into the ground
		for i in fs.size() - 1:
			var f0: F = fs[i]
			var f1: F = fs[i + 1]
			var a0 := f0.p(side * w, DECK_TOP + COPING)
			var a1 := f1.p(side * w, DECK_TOP + COPING)
			var b0 := Vector3(a0.x, _ground_g(a0) - FOOT, a0.z)
			var b1 := Vector3(a1.x, _ground_g(a1) - FOOT, a1.z)
			var n0 := f0.l * side
			var n1 := f1.l * side
			near.quad("concrete", a0, a1, b1, b0, n0, n1, n1, n0)
			faces.append_array(PackedVector3Array([a0, a1, b1, a0, b1, b0]))
		var fw := samples(Layout.s_start(), end, 20.0)
		for i in fw.size() - 1:
			var f0: F = fw[i]
			var f1: F = fw[i + 1]
			var a0 := f0.p(side * w, DECK_TOP + COPING)
			var a1 := f1.p(side * w, DECK_TOP + COPING)
			far.flat("far", a0, a1, Vector3(a1.x, _ground_g(a1) - FOOT, a1.z), Vector3(a0.x, _ground_g(a0) - FOOT, a0.z),
					f0.l * side)
	var fw := samples(Layout.s_start(), end, 20.0)
	_sweep(far, "far", fw, [Vector2(-w, DECK_TOP + COPING), Vector2(-SPINE, DECK_TOP + COPING),
			Vector2(-SPINE, WALKWAY), Vector2(SPINE, WALKWAY), Vector2(SPINE, DECK_TOP + COPING), Vector2(w, DECK_TOP + COPING)])
	# its start's face
	var f: F = fs[0]
	var low := INF
	for v: float in [-w, 0.0, w]:
		low = minf(low, _ground_g(f.p(v, 0.0)) - FOOT)
	var dz := low - f.o.y
	var face := PackedVector2Array([Vector2(-w, dz), Vector2(w, dz), Vector2(w, DECK_TOP + COPING),
			Vector2(EDGE, DECK_TOP + COPING), Vector2(EDGE, DECK_TOP), Vector2(SPINE, DECK_TOP), Vector2(SPINE, WALKWAY),
			Vector2(-SPINE, WALKWAY), Vector2(-SPINE, DECK_TOP), Vector2(-EDGE, DECK_TOP), Vector2(-EDGE, DECK_TOP + COPING),
			Vector2(-w, DECK_TOP + COPING)])
	var idx := Geometry2D.triangulate_polygon(face)
	for i in range(0, idx.size(), 3):
		var a := f.p(face[idx[i]].x, face[idx[i]].y)
		var b := f.p(face[idx[i + 1]].x, face[idx[i + 1]].y)
		var c := f.p(face[idx[i + 2]].x, face[idx[i + 2]].y)
		near.tri("concrete", a, b, c, -f.t, -f.t, -f.t)
		far.tri("far", a, b, c, -f.t, -f.t, -f.t)
		faces.append_array(PackedVector3Array([a, b, c]))


## The ground under Godot point p.
static func _ground_g(p: Vector3) -> float:
	return ground(p.x, -p.z)


## The abutment (pier p, its bearing line at s_abutment): its seat from FOOT m into the ground, the backwall up to the
## trackbed, the first span's two bearings.
func _abutment(p: Dictionary) -> Dictionary:
	var s := float(p["s"])
	var f := frame_at(s)
	var half := Layout.ABUT_HALF
	var low := INF
	for al: float in [-half.x, half.x]:
		for v: float in [-half.y, 0.0, half.y]:
			low = minf(low, _ground_g(f.o + f.t * al + f.l * v))
	var bottom := low - FOOT
	var seat := Plan.soffit_z(s) - Plan.BEARING
	var z := Vector2(bottom - f.o.y, seat - f.o.y)
	_box(near, "concrete", f, Vector2(-half.x, half.x), Vector2(-half.y, half.y), z, false, true)
	_box(far, "far", f, Vector2(-half.x, half.x), Vector2(-half.y, half.y), z)
	var back := Vector2(-half.x, -Layout.ABUT_DECK - 0.03)
	_box(near, "concrete", f, back, Vector2(-EDGE, EDGE), Vector2(z.y, DECK_TOP))
	for side: float in [1.0, -1.0]:
		var c := side * Layout.SHAFTS_APART * 0.5
		_box(near, "bearing", f, Vector2(-0.3, 0.3), Vector2(c - 0.35, c + 0.35), Vector2(z.y, soffit_at(absf(c) - 0.35)))
	return {"s": s, "type": "abutment", "top": seat, "bottom": bottom, "ground_min": low, "shafts": [Plan.point(s)]}


# ---------------------------------------------------------------- the top equipment

## The line's top equipment from s0 to s1 (a run's part in the cell): parapets, cable troughs, the walkway's handrail.
func _equipment(s0: float, s1: float) -> void:
	var fs := samples(s0, s1)
	for side: float in [1.0, -1.0]:
		# the cable trough
		var t0 := side * TROUGH.x
		var t1 := side * TROUGH.y
		_strip(near, "concrete", fs, Vector2(t0, DECK_TOP), Vector2(t0, TROUGH_TOP), Vector2(-side, 0), true)
		_strip(near, "concrete", fs, Vector2(t0, TROUGH_TOP), Vector2(t1, TROUGH_TOP), Vector2(0, 1), true)
		_strip(near, "concrete", fs, Vector2(t1, TROUGH_TOP), Vector2(t1, DECK_TOP), Vector2(side, 0), true)
		# the parapet: the cables' panel, its top rail; a wall in the collision
		var pv := side * PARAPET_V
		_strip(near, "cables", fs, Vector2(pv, DECK_TOP + CABLES.x), Vector2(pv, DECK_TOP + CABLES.y), Vector2(side, 0),
				false, 2)
		faces_strip(fs, Vector2(pv, DECK_TOP), Vector2(pv, DECK_TOP + Plan.PARAPET_H))
		var r0 := side * (PARAPET_V - 0.04)
		var r1 := side * (PARAPET_V + 0.04)
		var rz := DECK_TOP + Plan.PARAPET_H
		_strip(near, "steel", fs, Vector2(r0, rz), Vector2(r1, rz), Vector2(0, 1))
		_strip(near, "steel", fs, Vector2(r0, rz - 0.04), Vector2(r1, rz - 0.04), Vector2(0, -1))
		_strip(near, "steel", fs, Vector2(r1, rz - 0.04), Vector2(r1, rz), Vector2(side, 0))
		_strip(near, "steel", fs, Vector2(r0, rz - 0.04), Vector2(r0, rz), Vector2(-side, 0))
	# the posts
	if near.on:
		var posts := _steps(s0, s1, POST_STEP)
		for s in posts:
			var f := frame_at(s)
			for side: float in [1.0, -1.0]:
				var c := side * PARAPET_V
				_box(near, "steel", f, Vector2(-0.05, 0.05), Vector2(c - 0.015, c + 0.015),
						Vector2(DECK_TOP, DECK_TOP + Plan.PARAPET_H - 0.04))
		# the walkway's axial handrail
		for s in _steps(s0, s1, HANDRAIL_STEP):
			_box(near, "steel", frame_at(s), Vector2(-0.02, 0.02), Vector2(-0.02, 0.02),
					Vector2(WALKWAY, WALKWAY + HANDRAIL_H - 0.05))
		var hz := WALKWAY + HANDRAIL_H
		_sweep(near, "steel", fs, [Vector2(-0.025, hz - 0.05), Vector2(-0.025, hz), Vector2(0.025, hz),
				Vector2(0.025, hz - 0.05), Vector2(-0.025, hz - 0.05)])


## s from s0 to s1 every `step` m (multiples of it), and the ends.
static func _steps(s0: float, s1: float, step: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([s0 + 0.06])
	var k := ceili((s0 + step * 0.5) / step)
	while k * step < s1 - step * 0.5:
		out.append(k * step)
		k += 1
	out.append(s1 - 0.06)
	return out


# ---------------------------------------------------------------- the tracks

## The two tracks from s0 to s1: plinths, rails, the third rail and its cover on insulators.
func _track(s0: float, s1: float) -> void:
	var fs := samples(s0, s1)
	var head := [Vector2(-0.075, -0.150), Vector2(-0.009, -0.145), Vector2(-0.009, -0.055), Vector2(-0.035, -0.045),
			Vector2(-0.035, 0.0), Vector2(0.035, 0.0), Vector2(0.035, -0.045), Vector2(0.009, -0.055),
			Vector2(0.009, -0.145), Vector2(0.075, -0.150)]
	var rail_mats := ["rail", "rail", "rail", "rail", "rail_top", "rail", "rail", "rail", "rail"]
	for side: float in [1.0, -1.0]:
		# the plinth: its top (baseplates painted on), its sides; walked on
		var p0 := side * PLINTH.x
		var p1 := side * PLINTH.y
		_strip(near, "plinth", fs, Vector2(p0, PLINTH_TOP), Vector2(p1, PLINTH_TOP), Vector2(0, 1), true, 1)
		_strip(near, "concrete", fs, Vector2(p0, DECK_TOP), Vector2(p0, PLINTH_TOP), Vector2(-side, 0), true)
		_strip(near, "concrete", fs, Vector2(p1, DECK_TOP), Vector2(p1, PLINTH_TOP), Vector2(side, 0), true)
		if not near.on:
			continue
		# the rails
		for c: float in [side * (Plan.TRACK_V - RAIL_V), side * (Plan.TRACK_V + RAIL_V)]:
			var prof := head.map(func(q: Vector2) -> Vector2: return q + Vector2(c, 0.0))
			_sweep(near, rail_mats, fs, prof)
		# the third rail, its cover board (a lip down on the track's side)
		var cv := side * CONDUCTOR_V
		_sweep(near, "conductor", fs, [Vector2(cv - 0.04, -0.09), Vector2(cv - 0.04, 0.02), Vector2(cv + 0.04, 0.02),
				Vector2(cv + 0.04, -0.09)])
		var c0 := side * COVER.x
		var c1 := side * COVER.y
		_strip(near, "cover", fs, Vector2(c0, 0.125), Vector2(c1, 0.125), Vector2(0, 1))
		_strip(near, "cover", fs, Vector2(c0, 0.10), Vector2(c1, 0.10), Vector2(0, -1))
		_strip(near, "cover", fs, Vector2(c0, 0.10), Vector2(c0, 0.125), Vector2(-side, 0))
		_strip(near, "cover", fs, Vector2(c1, 0.03), Vector2(c1, 0.125), Vector2(side, 0))
		_strip(near, "cover", fs, Vector2(c1 - side * 0.012, 0.03), Vector2(c1 - side * 0.012, 0.10), Vector2(-side, 0))
		# its insulators and the cover's brackets, at the nodes
		for i in range(1, fs.size() - 1):
			var f: F = fs[i]
			_box(near, "bearing", f, Vector2(-0.06, 0.06), Vector2(cv - 0.06, cv + 0.06), Vector2(DECK_TOP, -0.09))
			var b := side * (COVER.x + 0.01)
			_box(near, "conductor", f, Vector2(-0.04, 0.04), Vector2(minf(b, b + side * 0.03), maxf(b, b + side * 0.03)),
					Vector2(DECK_TOP, 0.10))


# ---------------------------------------------------------------- the piers

## Pier p (the plan's piers()): its shafts and head, their collar, an island; its collision; its far shape. What was
## built (the test's): {s, type, top, bottom, ground_min, shafts}.
func _pier(p: Dictionary) -> Dictionary:
	if p["type"] == "abutment":
		return _abutment(p)
	var c := Vector2(float(p["x"]), float(p["y"]))
	var h := float(p["heading"])
	var soffit := Plan.soffit_z(float(p["s"]))               # (the deck's: the plan's soffit_z is rounded to 1 cm)
	var top := soffit - Plan.BEARING
	var double: bool = p["type"] == "double"
	var axes: Vector2 = Layout.SHAFT if double else Layout.SHAFT_SINGLE
	var offs := [-Layout.SHAFTS_APART * 0.5, Layout.SHAFTS_APART * 0.5] if double else [0.0]
	var low := INF
	var centres := []
	for off: float in offs:
		centres.append(Layout.pier_map(p, Vector2(0.0, off)))
		for k in 16:
			var a := TAU * k / 16.0
			var m := Layout.pier_map(p, Vector2(axes.x * cos(a), off + axes.y * sin(a)))
			low = minf(low, ground(m.x, m.y))
		var mc := Layout.pier_map(p, Vector2(0.0, off))
		low = minf(low, ground(mc.x, mc.y))
	var bottom := low - FOOT
	for off: float in offs:
		var collar := top - COLLAR_H
		var rings: Array
		if double:
			rings = [[bottom, axes.x, axes.y], [top, axes.x, axes.y]]
		else:
			rings = [[bottom, axes.x, axes.y]]
			for k in 7:
				var t := k / 6.0
				var e := t * t
				rings.append([collar - FLARE_H * (1.0 - t), lerpf(axes.x, HEAD_SINGLE.x, e), lerpf(axes.y, HEAD_SINGLE.y, e)])
			rings.append([top, HEAD_SINGLE.x, HEAD_SINGLE.y])
		_lathe(near, "concrete", p, off, rings, RING, soffit)
		# the collar: from below the head's top up to the soffit (round the bearings), its underside
		var hx: float = rings[rings.size() - 1][1]
		var hy: float = rings[rings.size() - 1][2]
		_lathe(near, "collar", p, off, [[collar, hx + COLLAR_OUT, hy + COLLAR_OUT],
				[NAN, hx + COLLAR_OUT, hy + COLLAR_OUT]], RING, soffit, true)
		_annulus(near, "collar", p, off, collar, Vector2(hx, hy), Vector2(hx + COLLAR_OUT, hy + COLLAR_OUT))
		# far: a prism (the head's top for a single pier)
		var fr: Array = [[bottom, axes.x, axes.y], [top, axes.x, axes.y]] if double else [[bottom, axes.x, axes.y],
				[collar - FLARE_H, axes.x, axes.y], [collar, HEAD_SINGLE.x, HEAD_SINGLE.y], [top, HEAD_SINGLE.x, HEAD_SINGLE.y]]
		_lathe(far, "far", p, off, fr, 8, soffit)
		# collision: the shaft's prism, a single pier's head's hull
		_convex(p, off, [[bottom, axes.x, axes.y], [top if double else collar - FLARE_H, axes.x, axes.y]])
		if not double:
			_convex(p, off, rings.slice(1))
	if Layout.has_island(p):
		_island(p)
	return {"s": float(p["s"]), "type": p["type"], "top": top, "bottom": bottom, "ground_min": low, "shafts": centres}


## Godot point of pier p's frame (along, across) at height z.
static func _pp(p: Dictionary, al: float, ac: float, z: float) -> Vector3:
	var m := Layout.pier_map(p, Vector2(al, ac))
	return Vector3(m.x, z, -m.y)


## Round pier p's axis `off` across: rings [z, half along, half across] (z NAN: up to the soffit, `soffit` at the axis,
## less 0.02, vertex by vertex) joined in a side of `seg` segments, smooth normals; uv: the collar's perforations.
func _lathe(acc: Acc, m: String, p: Dictionary, off: float, rings: Array, seg: int, soffit: float, uv := false) -> void:
	if not acc.on:
		return
	var pts := []
	for r: Array in rings:
		var row := PackedVector3Array()
		for j in seg:
			var a := TAU * j / seg
			var al: float = r[1] * cos(a)
			var ac: float = off + r[2] * sin(a)
			var z: float = r[0] if not is_nan(r[0]) else soffit + (soffit_at(ac) - SOFFIT) - 0.02
			row.append(_pp(p, al, ac, z))
		pts.append(row)
	var centre := _pp(p, 0.0, off, 0.0)
	var nr := pts.size()
	var norms := []
	for i in nr:
		var row: PackedVector3Array = pts[i]
		var up: PackedVector3Array = pts[mini(i + 1, nr - 1)]
		var dn: PackedVector3Array = pts[maxi(i - 1, 0)]
		var ns := PackedVector3Array()
		for j in seg:
			var tz := up[j] - dn[j]
			var ta := row[(j + 1) % seg] - row[(j - 1 + seg) % seg]
			var n := ta.cross(tz).normalized()
			var radial := row[j] - Vector3(centre.x, row[j].y, centre.z)
			if n.dot(radial) < 0.0:
				n = -n
			ns.append(n)
		norms.append(ns)
	var perim := 0.0
	if uv:
		var r0: PackedVector3Array = pts[0]
		for j in seg:
			perim += r0[j].distance_to(r0[(j + 1) % seg])
	for i in nr - 1:
		var r0: PackedVector3Array = pts[i]
		var r1: PackedVector3Array = pts[i + 1]
		var n0: PackedVector3Array = norms[i]
		var n1: PackedVector3Array = norms[i + 1]
		for j in seg:
			var k := (j + 1) % seg
			if uv:
				var u0 := perim * j / seg / 0.06
				var u1 := perim * (j + 1) / seg / 0.06
				acc.quad(m, r0[j], r0[k], r1[k], r1[j], n0[j], n0[k], n1[k], n1[j], Vector2(u0, r0[j].y / 0.06),
						Vector2(u1, r0[k].y / 0.06), Vector2(u1, r1[k].y / 0.06), Vector2(u0, r1[j].y / 0.06))
			else:
				acc.quad(m, r0[j], r0[k], r1[k], r1[j], n0[j], n0[k], n1[k], n1[j])


## A flat ring facing down at z round pier p's axis `off`: between ellipses `inner` and `outer` (half axes).
func _annulus(acc: Acc, m: String, p: Dictionary, off: float, z: float, inner: Vector2, outer: Vector2) -> void:
	for j in RING:
		var a0 := TAU * j / RING
		var a1 := TAU * (j + 1) / RING
		acc.flat(m, _pp(p, inner.x * cos(a0), off + inner.y * sin(a0), z),
				_pp(p, outer.x * cos(a0), off + outer.y * sin(a0), z),
				_pp(p, outer.x * cos(a1), off + outer.y * sin(a1), z), _pp(p, inner.x * cos(a1), off + inner.y * sin(a1), z),
				Vector3.DOWN)


## A convex collision shape round pier p's axis `off`: the hull of rings [z, half along, half across] (12 points each).
func _convex(p: Dictionary, off: float, rings: Array) -> void:
	if not _col_on:
		return
	var pts := PackedVector3Array()
	for r: Array in rings:
		for j in 12:
			var a := TAU * j / 12.0
			pts.append(_pp(p, r[1] * cos(a), off + r[2] * sin(a), r[0]))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## A kerbed island round pier p (its shafts and its island_margin(), corners cut), ISLAND_UP over the ground's highest.
func _island(p: Dictionary) -> void:
	var half := Layout.footprint(p) + Vector2.ONE * Layout.island_margin(p)
	var cut := 0.6
	var outline := PackedVector2Array([Vector2(-half.x + cut, -half.y), Vector2(half.x - cut, -half.y),
			Vector2(half.x, -half.y + cut), Vector2(half.x, half.y - cut), Vector2(half.x - cut, half.y),
			Vector2(-half.x + cut, half.y), Vector2(-half.x, half.y - cut), Vector2(-half.x, -half.y + cut)])
	var hi := -INF
	var lo := INF
	for q in outline:
		var m := Layout.pier_map(p, q)
		var g := ground(m.x, m.y)
		hi = maxf(hi, g)
		lo = minf(lo, g)
	var zt := hi + ISLAND_UP
	var zb := lo - 0.2
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var d := (b - a).normalized()
		var out := Layout.pier_map(p, a + Vector2(d.y, -d.x)) - Layout.pier_map(p, a)
		var nn := Vector3(out.x, 0.0, -out.y).normalized()
		near.flat("kerb", _pp(p, a.x, a.y, zb), _pp(p, b.x, b.y, zb), _pp(p, b.x, b.y, zt), _pp(p, a.x, a.y, zt), nn)
		near.tri("island", _pp(p, 0.0, 0.0, zt), _pp(p, a.x, a.y, zt), _pp(p, b.x, b.y, zt), Vector3.UP, Vector3.UP,
				Vector3.UP)
	if not _col_on:
		return
	var pts := PackedVector3Array()
	for q in outline:
		pts.append(_pp(p, q.x, q.y, zt))
		pts.append(_pp(p, q.x, q.y, zb))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


# ---------------------------------------------------------------- materials

## The lot's materials: light concrete (a faint mottle, world triplanar), the walkway's, the plinths' (their baseplates
## painted), steel, the rails', the cables' panel (alpha: cables every 12 cm), the collar's perforated metal.
static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(COLOURS.get(name, "#d7d6d0"))
	m.roughness = 0.88
	match name:
		"concrete", "coffer", "walkway", "fascia":
			m.albedo_texture = _mottle()
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / 9.0
		"plinth":
			m.albedo_texture = _baseplates()
			m.albedo_color = Color.WHITE
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"rail":
			m.metallic = 0.45
			m.roughness = 0.75
		"rail_top", "steel":
			m.metallic = 0.85
			m.roughness = 0.3
		"conductor":
			m.metallic = 0.6
			m.roughness = 0.5
		"cables":
			m.albedo_texture = _cables()
			m.albedo_color = Color("#e3e7ea")
			m.metallic = 0.6
			m.roughness = 0.35
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"collar":
			m.albedo_texture = _perforated()
			m.albedo_color = Color.WHITE
			m.metallic = 0.2
			m.roughness = 0.55
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"far":
			m.roughness = 0.9
	_mats[name] = m
	return m


## Concrete's faint mottle (a seamless noise, 0.93 .. 1.03).
static func _mottle() -> Texture2D:
	if _mottle_tex:
		return _mottle_tex
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = 18
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	var src := fn.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var g := 0.93 + 0.10 * src.get_pixel(x, y).r
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	_mottle_tex = ImageTexture.create_from_image(img)
	return _mottle_tex


## A plinth's top: concrete, a baseplate under each rail every FASTENING m (u across the plinth from its inner edge,
## v along).
static func _baseplates() -> Texture2D:
	var w := 128
	var hgt := 32
	var img := Image.create(w, hgt, false, Image.FORMAT_RGB8)
	img.fill(Color(COLOURS["plinth"]))
	var width := PLINTH.y - PLINTH.x
	for rail: float in [Plan.TRACK_V - RAIL_V, Plan.TRACK_V + RAIL_V]:
		var cu := (rail - PLINTH.x) / width
		for y in hgt:
			var along := float(y) / hgt * FASTENING
			if along < 0.20 or along > 0.55:
				continue
			for x in w:
				var across := (float(x) / w - cu) * width
				if absf(across) <= 0.17:
					var bolt := absf(absf(across) - 0.12) < 0.025 and absf(along - 0.375) < 0.03
					img.set_pixel(x, y, Color("#2f3033") if bolt else Color("#45474a"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The parapet's cables: thin lines every ~12 cm on nothing (alpha), the panel's height in 256 px.
static func _cables() -> Texture2D:
	var img := Image.create(4, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for k in 11:
		var y := 4 + k * 24
		for x in 4:
			img.set_pixel(x, y, Color(1, 1, 1, 1))
			img.set_pixel(x, y + 1, Color(1, 1, 1, 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Perforated metal: a round hole (dark: the bearings behind) per 6 cm tile.
static func _perforated() -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
			img.set_pixel(x, y, Color("#55575a") if d < n * 0.22 else Color("#d4d6d8"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
