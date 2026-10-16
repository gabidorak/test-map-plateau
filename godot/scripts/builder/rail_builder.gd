@tool
extends RefCounted
## The RER B (Ligne de Sceaux) in the generated scene, from world/rail.json (tools/rail/build_rail.py; the ground it
## reshapes is already in world/: tools/rail/patch_world.py). Structures, built from code in the toy prop style
## (shaders/toy_prop.gdshader, vertex colour = palette colour and ambient occlusion):
## - the covered road under the line (Place de la Gare de Lozère): its concrete box (road surface with its lines,
##   walls, ceiling and lights) from portal to portal, a frame round each portal; the open ends are the patched
##   ground's trench;
## - the footbridges: deck, bar railings, the stair flights down to the platforms or the ground (steps, stringers,
##   handrails), the pillars under the deck ends;
## - the pedestrian underpasses: the covered passages (floor, walls, ceiling, light strips, portal frames), the steps
##   of the stairwells the patched ground opens, their railings.
## Collision (one StaticBody3D "RailCollision" on the buildings layer, each shape tagged for the picker): the road box
## and the passages as concave shells, the decks and steps as boxes, stair flights as ramps under their nosings so
## walking up them is smooth, railings as thin walls.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const RAIL_PATH := "res://world/rail.json"
const PROP_SHADER := "res://shaders/toy_prop.gdshader"
const CONCRETE := Color("#cfc8ba")          # palette props.concrete
const CONCRETE_DARK := Color("#b4ad9f")
const STEEL := Color("#a7aeb6")             # palette props.steel
const ANTHRACITE := Color("#4b5059")        # palette props.anthracite
const ROAD := Color("#63666b")              # palette ground.asphalt
const DECK := Color("#6e7177")
const WHITE := Color("#f3f3ee")             # palette props.white
const GLOW := Color("#fff3cc")              # palette props.glow (lamp diffusers)
const RAILING_HEIGHT := 1.1                 # m; usual French public railing height (NF P01-012: 1.0 m minimum)
const BRIDGE_RAILING := 1.3                 # m, the footbridge's bar railings (photos of the station: above the handrails)
const BAR_SPACING := 0.12                   # m between the bars of a bar railing (NF P01-012: gaps under 0.11 m)
const RAILING_WHITE := Color("#dfe2e2")     # the station's painted steel railings (photos)
const POST_SPACING := 2.0                   # m between railing posts; assumed
const TUNNEL_WALL := 0.40                   # m, the covered road's walls; assumed
const LIGHT_SPACING := 8.0                  # m between tunnel and passage lights; assumed
const DASH := [3.0, 10.0]                   # French road centre line T1: 3 m dashes, 10 m apart (urban)
const LINE_WIDTH := 0.12                    # m (urban centre line)

var _mesh_dir := ""
var _mat_toy: ShaderMaterial
var _mat_glow: ShaderMaterial
var _ground: GroundHeights
var _body: StaticBody3D


## Packed non-indexed triangles with a colour per vertex (alpha: ambient occlusion).
class Mesher:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	## Triangle facing `normal` (the winding is fixed so it is front facing: Godot fronts are clockwise).
	func tri(a: Vector3, b: Vector3, d: Vector3, normal: Vector3, col: Color) -> void:
		if (d - a).cross(b - a).dot(normal) < 0.0:
			var tmp := b
			b = d
			d = tmp
		for p in [a, b, d]:
			v.append(p)
			n.append(normal)
			c.append(col)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, normal: Vector3, col: Color) -> void:
		tri(a, b, d, normal, col)
		tri(a, d, e, normal, col)

	## Box of `size` centred on `xf`'s origin, along its axes; the underside a little darker.
	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var bs := xf.basis
		var o := xf.origin
		var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
				[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
				[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
		for f: Array in faces:
			var nn: Vector3 = f[0]
			var u: Vector3 = f[1]
			var w: Vector3 = f[2]
			var centre := nn * h.abs()
			var du := u * h.abs()
			var dw := w * h.abs()
			var pts := [centre - du - dw, centre + du - dw, centre + du + dw, centre - du + dw]
			var wp := []
			for p: Vector3 in pts:
				wp.append(o + bs * p)
			var shade := col
			if nn == Vector3.DOWN:
				shade = Color(col.r, col.g, col.b, 0.7)
			quad(wp[0], wp[1], wp[2], wp[3], (bs * nn).normalized(), shade)

	func is_empty() -> bool:
		return v.is_empty()

	func commit(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		return mesh


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> Error:
	if not FileAccess.file_exists(RAIL_PATH):
		return OK                           # no railway in this map
	var rail = JSON.parse_string(FileAccess.get_file_as_string(RAIL_PATH))
	if not rail is Dictionary:
		push_error("cannot parse %s" % RAIL_PATH)
		return ERR_PARSE_ERROR
	_mesh_dir = mesh_dir
	var t: Dictionary = world["terrain"]
	_ground = GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	_mat_toy = ShaderMaterial.new()
	_mat_toy.shader = load(PROP_SHADER)
	_mat_toy.set_shader_parameter("mode", 0)
	MeshUtils.save(_mat_toy, mesh_dir + "rail_material.tres")
	_mat_glow = ShaderMaterial.new()
	_mat_glow.shader = load(PROP_SHADER)
	_mat_glow.set_shader_parameter("mode", 2)
	MeshUtils.save(_mat_glow, mesh_dir + "rail_material_glow.tres")
	var node := Node3D.new()
	node.name = "Rail"
	root.add_child(node)
	var structures := Node3D.new()
	structures.name = "Structures"
	node.add_child(structures)
	_body = StaticBody3D.new()
	_body.name = "RailCollision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "rail", "id": "rail"})
	root.add_child(_body)
	if rail.get("road_tunnel") != null:
		_road_tunnel(structures, rail["road_tunnel"])
	for fb: Dictionary in rail.get("footbridges", []):
		_footbridge(structures, fb)
	for up: Dictionary in rail.get("underpasses", []):
		_underpass(structures, up)
	return OK


# ---------------------------------------------------------------- helpers

static func _g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func _v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


## Godot direction of map direction d (x east, y north), horizontal.
static func _gd(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, -d.y)


func _ground_at(p: Vector2) -> float:
	return _ground.at(p.x, p.y)


func _emit(parent: Node3D, name: String, m: Mesher, mat: Material, info: Dictionary, range_end := 0.0) -> void:
	if m.is_empty():
		return
	var mesh := MeshUtils.save(m.commit(mat), _mesh_dir + "rail_%s.res" % name.to_lower())
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.set_meta("plateau", info)
	if range_end > 0.0:
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = 10.0
	parent.add_child(mi)


func _shape_box(xf: Transform3D, size: Vector3, info: Dictionary) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.transform = xf
	cs.set_meta("plateau", info)
	_body.add_child(cs)


func _shape_faces(name: String, faces: PackedVector3Array, info: Dictionary) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	MeshUtils.save(shape, _mesh_dir + "rail_col_%s.res" % name.to_lower())
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = shape
	cs.set_meta("plateau", info)
	_body.add_child(cs)


## Frames along a polyline (map points `pts`, heights `zs`): per point the Godot position, the horizontal direction
## along the line and its left normal (smoothed at the corners).
static func _frames(pts: Array, zs: PackedFloat32Array) -> Array:
	var out := []
	for i in pts.size():
		var a: Vector2 = _v2(pts[maxi(i - 1, 0)])
		var b: Vector2 = _v2(pts[mini(i + 1, pts.size() - 1)])
		var d := (b - a).normalized()
		var p: Vector2 = _v2(pts[i])
		out.append([p, zs[i], d, Vector2(-d.y, d.x)])
	return out


## A box from map point a to map point b (horizontal centre line at heights za, zb: may slope), `w` wide and from
## `below` under that line to `above` over it.
static func _beam(a: Vector2, za: float, b: Vector2, zb: float, w: float, below: float, above: float) -> Array:
	var pa := _g(a.x, a.y, za)
	var pb := _g(b.x, b.y, zb)
	var axis := pb - pa
	var length := axis.length()
	var z := axis / maxf(length, 1e-6)
	var x := Vector3.UP.cross(z).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	var centre := (pa + pb) * 0.5 + y * (above - below) * 0.5
	return [Transform3D(Basis(x, y, z), centre), Vector3(w, above + below, length)]


# ---------------------------------------------------------------- the covered road

func _road_tunnel(parent: Node3D, rt: Dictionary) -> void:
	var t: Array = rt["t"]
	var a: float = rt["covered"][0]
	var b: float = rt["covered"][1]
	var pts := []
	var zs := PackedFloat32Array()
	for i in t.size():
		if float(t[i]) >= a - 0.01 and float(t[i]) <= b + 0.01:
			pts.append(rt["pts"][i])
			zs.append(rt["z"][i])
	if pts.size() < 2:
		return
	var w: float = rt["width"] * 0.5
	var hh: float = rt["headroom"]
	var slab: float = rt["slab"]
	var fr := _frames(pts, zs)
	var m := Mesher.new()
	var lines := Mesher.new()
	var glow := Mesher.new()
	var faces := PackedVector3Array()
	var info := {"type": "rail_structure", "kind": "road_tunnel", "id": rt["id"], "name": rt.get("name", ""),
			"osm": rt["osm"], "headroom": hh, "maxheight": rt.get("maxheight", ""), "lowest": rt.get("lowest", 0.0)}
	for i in fr.size() - 1:
		var f0: Array = fr[i]
		var f1: Array = fr[i + 1]
		var l0: Vector2 = f0[0] + f0[3] * w
		var r0: Vector2 = f0[0] - f0[3] * w
		var l1: Vector2 = f1[0] + f1[3] * w
		var r1: Vector2 = f1[0] - f1[3] * w
		var z0: float = f0[1]
		var z1: float = f1[1]
		var floor_q := [_g(l0.x, l0.y, z0), _g(r0.x, r0.y, z0), _g(r1.x, r1.y, z1), _g(l1.x, l1.y, z1)]
		var ceil_q := [_g(l0.x, l0.y, z0 + hh), _g(r0.x, r0.y, z0 + hh), _g(r1.x, r1.y, z1 + hh), _g(l1.x, l1.y, z1 + hh)]
		m.quad(floor_q[0], floor_q[1], floor_q[2], floor_q[3], Vector3.UP, ROAD)
		m.quad(ceil_q[0], ceil_q[1], ceil_q[2], ceil_q[3], Vector3.DOWN, Color(CONCRETE_DARK, 0.75))
		var nl := _gd(-f0[3])                   # the left wall faces right, into the tunnel
		m.quad(floor_q[0], floor_q[3], ceil_q[3], ceil_q[0], nl, CONCRETE)
		m.quad(floor_q[1], floor_q[2], ceil_q[2], ceil_q[1], -nl, CONCRETE)
		for q: Array in [floor_q, ceil_q]:
			faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		faces.append_array([floor_q[0], floor_q[3], ceil_q[3], floor_q[0], ceil_q[3], ceil_q[0]])
		faces.append_array([floor_q[1], floor_q[2], ceil_q[2], floor_q[1], ceil_q[2], ceil_q[1]])
	# road lines: edge lines and the dashed centre line, a hair over the road
	var along := 0.0
	for i in fr.size() - 1:
		var f0: Array = fr[i]
		var f1: Array = fr[i + 1]
		var seg: float = (f1[0] - f0[0]).length()
		for off: float in [w - 0.35, -(w - 0.35), 0.0]:
			var dashed := off == 0.0
			var s0 := 0.0
			while s0 < seg:
				var s1 := seg
				if dashed:
					var phase := fmod(along + s0, DASH[0] + DASH[1])
					if phase >= DASH[0]:
						s0 += DASH[0] + DASH[1] - phase
						continue
					s1 = minf(seg, s0 + DASH[0] - phase)
				var pa: Vector2 = f0[0] + (f1[0] - f0[0]) * (s0 / seg) + f0[3] * off
				var pb: Vector2 = f0[0] + (f1[0] - f0[0]) * (s1 / seg) + f0[3] * off
				var za: float = lerpf(f0[1], f1[1], s0 / seg) + 0.01
				var zb: float = lerpf(f0[1], f1[1], s1 / seg) + 0.01
				var hw: Vector2 = f0[3] * LINE_WIDTH * 0.5
				lines.quad(_g(pa.x + hw.x, pa.y + hw.y, za), _g(pa.x - hw.x, pa.y - hw.y, za),
						_g(pb.x - hw.x, pb.y - hw.y, zb), _g(pb.x + hw.x, pb.y + hw.y, zb), Vector3.UP, WHITE)
				s0 = s1 if not dashed else s1 + 0.001
		along += seg
	# ceiling lights
	var acc := LIGHT_SPACING * 0.5
	for i in fr.size() - 1:
		var f0: Array = fr[i]
		var f1: Array = fr[i + 1]
		var seg: float = (f1[0] - f0[0]).length()
		while acc < seg:
			var p: Vector2 = f0[0] + (f1[0] - f0[0]) * (acc / seg)
			var z: float = lerpf(f0[1], f1[1], acc / seg) + hh - 0.06
			var d: Vector2 = f0[2]
			var xf := Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x) - PI * 0.5), _g(p.x, p.y, z))
			for side: float in [1.0, -1.0]:
				var q: Vector2 = p + f0[3] * side * (w - 1.2)
				glow.box(Transform3D(xf.basis, _g(q.x, q.y, z)), Vector3(0.25, 0.1, 1.4), GLOW)
			acc += LIGHT_SPACING
		acc -= seg
	# portal frames where the box meets the open trench (both ends: the road comes in from a trench at each)
	for end in [0, fr.size() - 1]:
		var f: Array = fr[end]
		var out_dir := -1.0 if end == 0 else 1.0
		var d: Vector2 = f[2] * out_dir
		var p: Vector2 = f[0]
		var z: float = f[1]
		var nrm := _gd(d)
		var xf := Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x) - PI * 0.5), _g(p.x, p.y, z))
		for side: float in [1.0, -1.0]:
			var q: Vector2 = p + f[3] * side * (w + TUNNEL_WALL * 0.5)
			m.box(Transform3D(xf.basis, _g(q.x, q.y, z + (hh + slab) * 0.5)) .translated(nrm * 0.1),
					Vector3(TUNNEL_WALL + 0.1, hh + slab, 0.25), CONCRETE)
		m.box(Transform3D(xf.basis, _g(p.x, p.y, z + hh + slab * 0.5)).translated(nrm * 0.1),
				Vector3(2.0 * (w + TUNNEL_WALL), slab, 0.25), CONCRETE)
	_emit(parent, "RoadTunnel", m, _mat_toy, info)
	_emit(parent, "RoadTunnelLines", lines, _mat_toy, info, 120.0)
	_emit(parent, "RoadTunnelLights", glow, _mat_glow, info, 200.0)
	_shape_faces("RoadTunnel", faces, info)


# ---------------------------------------------------------------- footbridges

func _footbridge(parent: Node3D, fb: Dictionary) -> void:
	var m := Mesher.new()
	var info := {"type": "rail_structure", "kind": "footbridge", "id": fb["id"], "osm": fb["osm"],
			"level": fb["level"], "clearance": fb["clearance"]}
	var z: float = fb["level"]
	var w: float = fb["width"]
	var depth: float = fb["depth"]
	var deck: Array = fb["deck"]
	for i in deck.size() - 1:
		var a := _v2(deck[i])
		var b := _v2(deck[i + 1])
		var d := (b - a).normalized()
		# overlap a little past the ends, under the landings of the flights
		var bm := _beam(a - d * 0.6, z, b + d * 0.6, z, w + 0.3, depth, 0.0)
		m.box(bm[0], bm[1], STEEL)
		var top := _beam(a - d * 0.6, z + 0.01, b + d * 0.6, z + 0.01, w, 0.02, 0.0)
		m.box(top[0], top[1], DECK)
		_shape_box(bm[0], bm[1], info)
		var n := Vector2(-d.y, d.x)
		for side: float in [1.0, -1.0]:
			var off := n * side * (w * 0.5 + 0.05)
			_railing(m, a + off - d * 0.6, z, b + off + d * 0.6, z, BRIDGE_RAILING, true, info)
		# pillars under both ends, down to the ground (or the platform)
		for e: Vector2 in [a, b]:
			for side: float in [1.0, -1.0]:
				var q := e + n * side * (w * 0.5 - 0.2)
				var g := _ground_at(q)
				if z - depth - g > 0.5:
					var col := Transform3D(Basis.IDENTITY, _g(q.x, q.y, (g + z - depth) * 0.5))
					m.box(col, Vector3(0.35, z - depth - g, 0.35), STEEL)
					_shape_box(col, Vector3(0.35, z - depth - g, 0.35), info)
	for f: Dictionary in fb["flights"]:
		_flight(m, f, info, true)
	_emit(parent, "Footbridge_%s" % String(fb["id"]).get_slice(":", 1), m, _mat_toy, info)


## A flight of steps along `f.pts` from f.bottom (first point) to f.top (last), f.steps steps: the steps (solid
## blocks for a stairwell `on_ground`, slabs with stringers for an open flight), handrails on both sides, and a
## ramp collision under the nosings.
func _flight(m: Mesher, f: Dictionary, info: Dictionary, open: bool) -> void:
	var pts: Array = f["pts"]
	var n: int = f["steps"]
	var z0: float = f["bottom"]
	var z1: float = f["top"]
	var w: float = f["width"]
	var cum := [0.0]
	for i in pts.size() - 1:
		cum.append(cum[-1] + _v2(pts[i]).distance_to(_v2(pts[i + 1])))
	var length: float = cum[-1]
	if length < 0.1 or n < 1:
		return
	var at := func(s: float) -> Array:      # [point, direction]
		for i in pts.size() - 1:
			if s <= cum[i + 1] or i == pts.size() - 2:
				var a := _v2(pts[i])
				var b := _v2(pts[i + 1])
				var tt := clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 1e-6), 0.0, 1.0)
				return [a.lerp(b, tt), (b - a).normalized()]
		return [_v2(pts[-1]), Vector2.RIGHT]
	var going := length / n
	var rise := (z1 - z0) / n
	for k in n:
		var sa: float = k * going
		var sb: float = (k + 1) * going
		var pa: Array = at.call(sa)
		var pb: Array = at.call(sb)
		var top := z0 + (k + 1) * rise
		var thick := rise + (0.12 if open else 0.6)
		var bm := _beam(pa[0], top, pb[0], top, w, thick, 0.0)
		m.box(bm[0], bm[1], CONCRETE if not open else DECK)
	# stringers and handrails along each straight piece, a ramp collision under the nosings
	for i in pts.size() - 1:
		var a := _v2(pts[i])
		var b := _v2(pts[i + 1])
		var za: float = lerpf(z0, z1, cum[i] / length)
		var zb: float = lerpf(z0, z1, cum[i + 1] / length)
		var d := (b - a).normalized()
		var nn := Vector2(-d.y, d.x)
		for side: float in [1.0, -1.0]:
			var off := nn * side * (w * 0.5 + 0.06)
			if open:
				var st := _beam(a + off, za, b + off, zb, 0.12, 0.35, 0.05)
				m.box(st[0], st[1], STEEL)
			_railing(m, a + off, za, b + off, zb, RAILING_HEIGHT, false, info)
		var ramp := _beam(a, za, b, zb, w, 0.3, 0.0)
		_shape_box(ramp[0], ramp[1], info)


## Handrail from map point a (height za) to b (zb): posts, a top rail and a mid rail (`bars`: a bottom rail and
## vertical bars instead, painted white like the station's), and its collision (a thin wall).
func _railing(m: Mesher, a: Vector2, za: float, b: Vector2, zb: float, h: float, bars: bool, info: Dictionary) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var col := RAILING_WHITE if bars else STEEL
	var posts := maxi(1, ceili(length / POST_SPACING))
	for k in posts + 1:
		var tt := float(k) / posts
		var p := a.lerp(b, tt)
		var z := lerpf(za, zb, tt)
		m.box(Transform3D(Basis.IDENTITY, _g(p.x, p.y, z + h * 0.5)), Vector3(0.06, h, 0.06), col)
	var top := _beam(a, za + h, b, zb + h, 0.07, 0.035, 0.035)
	m.box(top[0], top[1], col)
	if bars:
		var low := _beam(a, za + 0.1, b, zb + 0.1, 0.05, 0.025, 0.025)
		m.box(low[0], low[1], col)
		var n := maxi(1, floori(length / BAR_SPACING))
		for k in range(1, n):
			var tt := float(k) / n
			var p := a.lerp(b, tt)
			var z := lerpf(za, zb, tt)
			m.box(Transform3D(Basis.IDENTITY, _g(p.x, p.y, z + 0.1 + (h - 0.1) * 0.5)), Vector3(0.022, h - 0.1, 0.022), col)
	else:
		var mid := _beam(a, za + h * 0.5, b, zb + h * 0.5, 0.04, 0.02, 0.02)
		m.box(mid[0], mid[1], STEEL)
	var wall := _beam(a, za, b, zb, 0.08, 0.0, h)
	_shape_box(wall[0], wall[1], info)


# ---------------------------------------------------------------- pedestrian underpasses

func _underpass(parent: Node3D, up: Dictionary) -> void:
	var m := Mesher.new()
	var glow := Mesher.new()
	var faces := PackedVector3Array()
	var info := {"type": "rail_structure", "kind": "underpass", "id": up["id"], "osm": up["osm"],
			"floor": up["floor"], "headroom": up["headroom"]}
	var z: float = up["floor"]
	var hh: float = up["headroom"]
	var w: float = up["width"] * 0.5
	for ps: Dictionary in up["passages"]:
		var pts: Array = ps["pts"]
		var zs := PackedFloat32Array()
		zs.resize(pts.size())
		zs.fill(z)
		var fr := _frames(pts, zs)
		for i in fr.size() - 1:
			var f0: Array = fr[i]
			var f1: Array = fr[i + 1]
			var l0: Vector2 = f0[0] + f0[3] * w
			var r0: Vector2 = f0[0] - f0[3] * w
			var l1: Vector2 = f1[0] + f1[3] * w
			var r1: Vector2 = f1[0] - f1[3] * w
			var fq := [_g(l0.x, l0.y, z), _g(r0.x, r0.y, z), _g(r1.x, r1.y, z), _g(l1.x, l1.y, z)]
			var cq := [_g(l0.x, l0.y, z + hh), _g(r0.x, r0.y, z + hh), _g(r1.x, r1.y, z + hh), _g(l1.x, l1.y, z + hh)]
			m.quad(fq[0], fq[1], fq[2], fq[3], Vector3.UP, Color("#9a958c"))
			m.quad(cq[0], cq[1], cq[2], cq[3], Vector3.DOWN, Color(WHITE, 0.8))
			var nl := _gd(-f0[3])
			m.quad(fq[0], fq[3], cq[3], cq[0], nl, Color("#e3ddd0"))
			m.quad(fq[1], fq[2], cq[2], cq[1], -nl, Color("#e3ddd0"))
			for q: Array in [fq, cq]:
				faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
			faces.append_array([fq[0], fq[3], cq[3], fq[0], cq[3], cq[0]])
			faces.append_array([fq[1], fq[2], cq[2], fq[1], cq[2], cq[1]])
			# a light strip along the ceiling
			var mid0: Vector2 = f0[0]
			var mid1: Vector2 = f1[0]
			var seg := mid0.distance_to(mid1)
			if seg > 1.0:
				var lb := _beam(mid0 + (mid1 - mid0) * 0.1, z + hh - 0.05, mid1 - (mid1 - mid0) * 0.1, z + hh - 0.05,
						0.2, 0.04, 0.0)
				glow.box(lb[0], lb[1], GLOW)
	for f: Dictionary in up["stairwells"]:
		var g := f.duplicate()
		g["pts"] = (f["pts"] as Array).duplicate()
		g["pts"].reverse()               # from the passage up to the street
		g["bottom"] = f["bottom"]
		g["top"] = f["top"]
		_flight(m, g, info, false)
		# railings along the stairwell's top edges (on the ground beside it)
		var pts: Array = f["pts"]
		for i in pts.size() - 1:
			var a := _v2(pts[i])
			var b := _v2(pts[i + 1])
			var d := (b - a).normalized()
			var nn := Vector2(-d.y, d.x)
			for side: float in [1.0, -1.0]:
				var off := nn * side * (float(f["width"]) * 0.5 + 0.35)
				_railing(m, a + off, _ground_at(a + off), b + off, _ground_at(b + off), RAILING_HEIGHT, false, info)
	for f: Dictionary in up["stairs_up"]:
		_flight(m, f, info, false)
	var name := "Underpass_%s" % String(up["id"]).get_slice(":", 1)
	_emit(parent, name, m, _mat_toy, info)
	_emit(parent, name + "_Lights", glow, _mat_glow, info, 200.0)
	_shape_faces(name, faces, info)
