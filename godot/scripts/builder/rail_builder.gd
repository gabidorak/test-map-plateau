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
const RailMap = preload("res://scripts/rail_map.gd")
const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
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
# the track (dimensions from rail.json track: UIC 60 rails, M450 sleepers, ballast)
const CHUNK := 96.0                         # m, as the props, trees and kit: nested in far_builder.gd's 192 m cells
const SEG := 2.0                            # m per rail and ballast segment (sagitta 1.2 mm on the tightest 404 m curve)
const FAR_SEG := 8.0                        # m per segment of the far ballast strip
const FAR_CELL := 192.0                     # m, far_builder.gd CELL: the far strip is cut per far cell
const CANT_BASE := 1.5                      # m between the rail head centres, over which the cant is measured
const SLEEPER_SHOW := 0.04                  # m of the sleepers' tops left above the ballast (photos)
const RAIL_RANGE := 260.0                   # m, rails drawn up to this distance
const SLEEPER_RANGE := 170.0                # m, sleepers drawn up to this distance
const RAIL_HEAD := Color("#c4c7ca")         # the polished rail head (photos of the station)
const RAIL_RUST := Color("#6b4d3e")         # rusty web and foot (photos)
const SLEEPER := Color("#a9a49b")           # concrete monobloc sleepers (photos)
const FASTENING := Color("#3b3d40")
# the platforms and the station (photos of Gare de Lozère, 2026-01: tools/rail references in the README)
const COPING_DEPTH := 0.30                  # m, the edge coping slab under the platform top; assumed
const COPING_BACK := 0.25                   # m of the coping resting on the platform behind its wall
const BAND := 0.90                          # m from the edge: the light edge slabs (photos: a ~1 m light band)...
const TACTILE := 0.40                       # ...then the tactile warning strip (NF P98-351: 0.40 m wide)
const YELLOW_LINE := 0.08                   # m, the yellow line along the south platform's edge (photos)
const COPING := Color("#dad6cd")
const COPING_FACE := Color("#9b968c")
const EDGE_SLABS := Color("#d3d0c8")
const TACTILE_COL := Color("#e2dfd6")
const YELLOW := Color("#e2bd2c")
const STATION_RANGE := 350.0                # m, the station's furniture drawn up to this distance
const LAMP_HEIGHT := 4.5                    # m, the platform lamps (photos: about two and a half people)
const SEAT_WIDTH := 0.5                     # m per seat
const SEAT_BLUE := Color("#2f5aa6")         # the platforms' blue shell seats (photos)
const BIN_GREEN := Color("#2f6b52")         # RATP/SNCF dark green of the bins and validators (photos)
const BOARD_SIZE := Vector2(2.4, 0.55)      # m, the "Lozère" name boards (photos: about the width of a bench)
const BOARD_HEIGHT := 2.3                   # m, their bottom edge above the platform
const RATP_BLUE := Color("#232f6e")         # the dark blue of the name and track boards (photos)
const SCREEN_AMBER := Color("#ffb347")      # the departure screens' lettering
const VALIDATOR_SPACING := 0.9              # m between the Navigo validators of an entrance
const NAVIGO_PURPLE := Color("#6c3fa0")     # the validators' card reader (photo of the station's)
const CANOPY_HEIGHT := 3.0                  # m, the canopies' roof above the platform; assumed
const CANOPY_TILT := 0.06                   # rad the canopies' roof falls towards the track
const LABEL_PIXEL := 0.002                  # m per label pixel (as prop_placer.gd)
# signals, posts and the catenary
const LENS_RADIUS := 0.085                  # m, the signal lamps (SNCF/RATP lenses, about 0.18 m across)
const LENS_PITCH := 0.32                    # m between the lamps of a target
const SIGNAL_HEIGHT := 3.0                  # m above the rail to the target's bottom; assumed (photos: over a cab)
const SIGNAL_GLOW := 4.0                    # emission of a lit lamp (as toy_prop.gdshader signal_energy)
const SIGNAL_RANGE := 500.0                 # m, signals, plates and posts drawn up to this distance
const LENS_COLOURS := {"VL": Color("#33e07a"), "A": Color("#ffb21e"), "S": Color("#ff2a1e"), "C": Color("#ff2a1e"),
		"R": Color("#ffb21e"), "RR": Color("#ffb21e")}
const POST_OFFSET := 2.5                    # m from the track centre to a kilometre post (as the signals)
const MAST := 0.30                          # m, the catenary masts' section (photos: square steel posts)
const PORTAL := Color("#c9cdd1")            # the portals' light grey galvanised steel (photos)
const PORTAL_RANGE := 900.0                 # m, masts and portals drawn up to this distance
const WIRE_RANGE := 220.0                   # m, the wires drawn up to this distance
const WIRE := Color("#5b4a3c")              # copper going brown
const WIRE_RADIUS := 0.007                  # m (contact wire 107 mm², about 12 mm across)
const SAG_MID := 0.55                       # system height left at mid-span, as a share of the supports'; assumed
const WALL_CAP := Vector2(0.35, 0.15)       # m, the retaining walls' copings (width, height); assumed

var _mesh_dir := ""
var _mat_toy: ShaderMaterial
var _mat_glow: ShaderMaterial
var _ground_mat: Material                   # the toy ground's (the ballast bed is drawn with its "ballast" material)
var _ballast_col := Color("#8f8a84")
var _rm                                     # RailMap: the centreline
var _rail: Dictionary
var _box := Rect2()                         # the map box (rail.json box): the line is drawn inside it
var _chunks := {}                           # Vector2i -> chunk Node3D under Rail/Track
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
	_rm = RailMap.get_map(RAIL_PATH)
	_rail = rail
	_ground_mat = load(mesh_dir + "ground_material.tres")
	_ballast_col = Color.html(world["palette"]["ground"].get("ballast", "#8f8a84"))
	var b: Array = rail["box"]
	_box = Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	_track(node, root)
	_rail_bridges(node)
	_yard(node)
	_islands(node)
	_platforms(node)
	_furniture(node)
	_signals(node)
	_posts(node)
	_catenary(node)
	_walls(node)
	_station_roofs(node, world)
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


## The Mesher of the far cell holding map point p: a mesh along the whole line would be culled where it is drawn (its
## visibility range is measured from its centre, kilometres away since the line runs on to Le Guichet and Massy).
func _cell_mesher(cells: Dictionary, p: Vector2) -> Mesher:
	var cell := Vector2i(floori(p.x / FAR_CELL), floori(p.y / FAR_CELL))
	if not cells.has(cell):
		cells[cell] = Mesher.new()
	return cells[cell]


## One mesh per far cell (_cell_mesher), named <name>_<x>_<y>.
func _emit_cells(parent: Node3D, name: String, cells: Dictionary, mat: Material, info: Dictionary, range_end := 0.0) -> void:
	for cell: Vector2i in cells:
		_emit(parent, "%s_%d_%d" % [name, cell.x, cell.y], cells[cell], mat, info, range_end)


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


# ---------------------------------------------------------------- the track

## Packed non-indexed triangles for the toy ground shader: one colour and ground material id per strip (custom0 =
## material, flags, variation), as the patched ground's own chunks.
class Strip:
	var v := PackedVector3Array()
	var n := PackedVector3Array()

	## Quad a, b, c, d (in order round it), facing up.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-12:
			nrm = (c - b).cross(d - b)
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		for t: Array in [[a, b, c], [a, c, d]]:
			var p0: Vector3 = t[0]
			var p1: Vector3 = t[1]
			var p2: Vector3 = t[2]
			if (p2 - p0).cross(p1 - p0).dot(nrm) < 0.0:      # Godot fronts are clockwise
				var tmp := p1
				p1 = p2
				p2 = tmp
			v.append_array([p0, p1, p2])
			n.append_array([nrm, nrm, nrm])

	func commit(mat: Material, col: Color, material_id: int) -> ArrayMesh:
		var cols := PackedColorArray()
		cols.resize(v.size())
		cols.fill(col)
		var cust := PackedByteArray()
		cust.resize(v.size() * 4)
		for i in v.size():
			cust[i * 4] = material_id
			cust[i * 4 + 2] = 128
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_CUSTOM0] = cust
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, mat)
		return mesh


## Both tracks across the map box: the ballast bed (a prism on the formation the patched ground draws, its top under
## the sleepers' tops, sloped shoulders down to the formation, stopping at the platform walls), the four rails (UIC 60
## profile, canted with the track) and the sleepers (one MultiMesh per chunk), all per CHUNK m chunk; the ballast
## also as walkable collision (terrain layer) and as a light strip under Rail/Far for far_builder.gd's far cells.
func _track(node: Node3D, root: Node3D) -> void:
	var track_node := Node3D.new()
	track_node.name = "Track"
	node.add_child(track_node)
	var far_node := Node3D.new()
	far_node.name = "Far"
	node.add_child(far_node)
	var ballast_body := StaticBody3D.new()
	ballast_body.name = "RailBallast"
	ballast_body.collision_layer = Layers.TERRAIN
	ballast_body.collision_mask = 0
	ballast_body.set_meta("plateau", {"type": "rail_track", "id": "rail:track"})
	root.add_child(ballast_body)
	var span := _span()
	if span.y <= span.x:
		return
	var tr: Dictionary = _rail["track"]
	var tracks: Array = (_rail["tracks"] as Array).duplicate()
	tracks.sort_custom(func(a, b): return float(a["offset"]) < float(b["offset"]))
	var ballast_id := GroundBuilder.MATERIALS.find("ballast")
	var parts := {}                         # chunk -> [ballast Strip, rails Mesher, collision faces]
	var n := ceili((span.y - span.x) / SEG)
	var prev := _section_points(span.x, _ballast_uz(span.x, tracks))
	var prev_rails := _rail_frames(span.x, tracks)
	for i in range(1, n + 1):
		var s := minf(span.x + i * SEG, span.y)
		var sec := _section_points(s, _ballast_uz(s, tracks))
		var rails := _rail_frames(s, tracks)
		var mid: Vector2 = _rm.point(s - SEG * 0.5)
		var ck := Vector2i(floori(mid.x / CHUNK), floori(mid.y / CHUNK))
		if not parts.has(ck):
			parts[ck] = [Strip.new(), Mesher.new(), PackedVector3Array()]
		var p: Array = parts[ck]
		p[2] = _ballast_quads(p[0], p[2], prev, sec)
		for k in rails.size():
			_rail_quads(p[1], prev_rails[k], rails[k])
		prev = sec
		prev_rails = rails
	# the far strip: coarser, the top and the shoulders only, per far cell
	var far_parts := {}
	var nf := ceili((span.y - span.x) / FAR_SEG)
	var fprev := _section_points(span.x, _far_uz(_ballast_uz(span.x, tracks)))
	for i in range(1, nf + 1):
		var s := minf(span.x + i * FAR_SEG, span.y)
		var fsec := _section_points(s, _far_uz(_ballast_uz(s, tracks)))
		var mid: Vector2 = _rm.point(s - FAR_SEG * 0.5)
		var cell := Vector2i(floori(mid.x / FAR_CELL), floori(mid.y / FAR_CELL))
		if not far_parts.has(cell):
			far_parts[cell] = Strip.new()
		_ballast_quads(far_parts[cell], PackedVector3Array(), fprev, fsec)
		fprev = fsec
	for ck: Vector2i in parts:
		var chunk := _chunk(track_node, ck)
		var tag := "%d_%d" % [ck.x, ck.y]
		var p: Array = parts[ck]
		var info := {"type": "rail_track", "id": "rail:track_" + tag}
		var bmi := MeshInstance3D.new()
		bmi.name = "Ballast"
		bmi.mesh = MeshUtils.save((p[0] as Strip).commit(_ground_mat, _ballast_col, ballast_id),
				_mesh_dir + "rail_ballast_%s.res" % tag)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bmi.position = -chunk.position
		bmi.set_meta("plateau", info)
		chunk.add_child(bmi)
		var rmi := MeshInstance3D.new()
		rmi.name = "Rails"
		rmi.mesh = MeshUtils.save((p[1] as Mesher).commit(_mat_toy), _mesh_dir + "rail_rails_%s.res" % tag)
		rmi.position = -chunk.position
		rmi.visibility_range_end = RAIL_RANGE
		rmi.visibility_range_end_margin = 10.0
		rmi.set_meta("plateau", info)
		chunk.add_child(rmi)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(p[2])
		MeshUtils.save(shape, _mesh_dir + "rail_col_ballast_%s.res" % tag)
		var cs := CollisionShape3D.new()
		cs.name = "Ballast_" + tag
		cs.shape = shape
		cs.set_meta("plateau", info)
		ballast_body.add_child(cs)
	var sleeper_mesh: ArrayMesh = MeshUtils.save(_sleeper_mesh(tr), _mesh_dir + "rail_sleeper.res")
	var sleepers := _sleepers(span, tracks, tr)
	for ck: Vector2i in sleepers:
		var chunk := _chunk(track_node, ck)
		var buf: PackedFloat32Array = sleepers[ck][0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sleeper_mesh
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Sleepers"
		mmi.multimesh = mm
		mmi.custom_aabb = sleepers[ck][1]
		mmi.visibility_range_end = SLEEPER_RANGE
		mmi.visibility_range_end_margin = 10.0
		mmi.set_meta("plateau", {"type": "rail_track", "id": "rail:sleepers_%d_%d" % [ck.x, ck.y]})
		chunk.add_child(mmi)
	for cell: Vector2i in far_parts:
		var holder := Node3D.new()
		holder.name = "Cell_%d_%d" % [cell.x, cell.y]
		far_node.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.name = "RailBallast"
		mi.mesh = MeshUtils.save((far_parts[cell] as Strip).commit(_ground_mat, _ballast_col, ballast_id),
				_mesh_dir + "rail_far_ballast_%d_%d.res" % [cell.x, cell.y])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


## The chunk node of Rail/Track for chunk ck (made on first use), at the chunk's centre like the prop chunks.
func _chunk(track_node: Node3D, ck: Vector2i) -> Node3D:
	if not _chunks.has(ck):
		var c := Node3D.new()
		c.name = "Chunk_%d_%d" % [ck.x, ck.y]
		c.position = Vector3((ck.x + 0.5) * CHUNK, 0.0, -(ck.y + 0.5) * CHUNK)
		track_node.add_child(c)
		_chunks[ck] = c
	return _chunks[ck]


## [first s, last s] of the centreline inside the map box, where the patched ground has the formation.
func _span() -> Vector2:
	var ew: Dictionary = _rail["earthworks"]
	var s0: float = ew["s0"]
	var s1: float = s0 + ((ew["formation"] as Array).size() - 1) * float(ew["step"])
	var lo := INF
	var hi := -INF
	var s := s0
	while s <= s1:
		if _box.has_point(_rm.point(s)):
			lo = minf(lo, s)
			hi = maxf(hi, s)
		s += 1.0
	return Vector2(lo, hi)


## Earthworks value `key` ("formation", or a side's "edge") at s, between the metres.
func _ew_at(s: float, key: String, side := "") -> float:
	var ew: Dictionary = _rail["earthworks"]
	var arr: Array = ew[key] if side.is_empty() else ew[side][key]
	var f := clampf((s - float(ew["s0"])) / float(ew["step"]), 0.0, arr.size() - 1.000001)
	var i := floori(f)
	return lerpf(arr[i], arr[i + 1], f - i)


## Cross-section of the ballast bed at s, south to north, as (u, z): the south toe, then per track the shoulder edges
## of its top (the plane of the sleeper tops less SLEEPER_SHOW, canted with the track) with the dip between the
## tracks, the north toe. A toe beyond the formation's edge (a platform wall) stops at the edge.
func _ballast_uz(s: float, tracks: Array) -> PackedVector2Array:
	var tr: Dictionary = _rail["track"]
	var hw: float = float(tr["sleeper"]["length"]) * 0.5 + float(tr["ballast"]["shoulder"])
	var slope: float = tr["ballast"]["slope"]
	var cf: float = _rail["earthworks"]["crossfall"]
	var F := _ew_at(s, "formation")
	var drop := float(tr["rail"]["height"]) + float(tr["pad"]) + SLEEPER_SHOW
	var c: float = _rm.cant(s)
	var zc: float = _rm.level(s) + absf(c) * 0.5 - drop
	var k := c / CANT_BASE
	var out := PackedVector2Array()
	var o0: float = tracks[0]["offset"]
	var o1: float = tracks[-1]["offset"]
	var ua := o0 - hw
	var za := zc + k * (ua - o0)
	out.append(_toe(ua, za, -1.0, F, cf, slope, _ew_at(s, "edge", "right")))
	out.append(Vector2(ua, za))
	for t in range(1, tracks.size()):
		var oa: float = tracks[t - 1]["offset"]
		var ob: float = tracks[t]["offset"]
		var u1 := oa + hw
		var u2 := ob - hw
		var z1 := zc + k * (u1 - oa)
		var z2 := zc + k * (u2 - ob)
		if u2 > u1:
			var um := (u1 + u2) * 0.5
			out.append(Vector2(u1, z1))
			out.append(Vector2(um, maxf(minf(z1 - (um - u1) / slope, z2 - (u2 - um) / slope), F - cf * absf(um))))
			out.append(Vector2(u2, z2))
		else:
			out.append(Vector2((u1 + u2) * 0.5, (z1 + z2) * 0.5))
	var ub := o1 + hw
	var zb := zc + k * (ub - o1)
	out.append(Vector2(ub, zb))
	out.append(_toe(ub, zb, 1.0, F, cf, slope, _ew_at(s, "edge", "left")))
	return out


## Where the shoulder slope from (u0, z0), going outward (dir -1 south, +1 north) down 1 in `slope`, meets the
## formation (F at the centre, falling cf per metre outwards), or the formation's edge.
static func _toe(u0: float, z0: float, dir: float, F: float, cf: float, slope: float, edge: float) -> Vector2:
	var u := (z0 - F + absf(u0) / slope) / (1.0 / slope - cf) * dir
	if absf(u) > edge:
		u = edge * dir
	var z := z0 - absf(u - u0) / slope
	return Vector2(u, maxf(z, F - cf * absf(u)))


## The far strip's section: the toes and the outer shoulder edges.
static func _far_uz(uz: PackedVector2Array) -> PackedVector2Array:
	return PackedVector2Array([uz[0], uz[1], uz[uz.size() - 2], uz[uz.size() - 1]])


## Godot points of a section (u, z) at s.
func _section_points(s: float, uz: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in uz:
		var p: Vector2 = _rm.point(s, q.x)
		out.append(_g(p.x, p.y, q.y))
	return out


## Quads between two sections at consecutive s; returns `faces` with their triangles added (collision).
func _ballast_quads(strip: Strip, faces: PackedVector3Array, a: PackedVector3Array, b: PackedVector3Array) -> PackedVector3Array:
	for j in a.size() - 1:
		strip.quad(a[j], a[j + 1], b[j + 1], b[j])
		faces.append_array([a[j], a[j + 1], b[j + 1], a[j], b[j + 1], b[j]])
	return faces


## Per rail (track by track, south rail first) at s: [Godot point of the head's top centre, across (left, tilted
## with the cant), up (tilted)].
func _rail_frames(s: float, tracks: Array) -> Array:
	var tr: Dictionary = _rail["track"]
	var half := float(tr["gauge"]) * 0.5 + float(tr["rail"]["head"]) * 0.5
	var basis := _track_basis(s)
	var out := []
	for t: Dictionary in tracks:
		var o: float = t["offset"]
		for side: float in [-1.0, 1.0]:
			var u := o + side * half
			var p: Vector2 = _rm.point(s, u)
			out.append([_g(p.x, p.y, _rm.rail_top(s, u, o)), basis.x, basis.y])
	return out


## The track's frame at s: x across to the left (north), tilted by the cant; y up, tilted; z along the line.
func _track_basis(s: float) -> Basis:
	var th: float = _rm.heading(s)
	var roll := atan2(_rm.cant(s), CANT_BASE)
	var left := Vector3(-sin(th), 0.0, -cos(th))
	var along := Vector3(cos(th), 0.0, -sin(th))
	var l3 := (left * cos(roll) + Vector3.UP * sin(roll)).normalized()
	return Basis(l3, along.cross(l3).normalized(), along)


## Toy 60E1 section (EN 13674-1: 172 mm high, head 72 mm wide, foot 150 mm, web 16.5 mm; head depth ~49 mm),
## clockwise from the head's top left corner, (across, up) from the head's top centre.
const RAIL_PROFILE := [Vector2(-0.036, 0.0), Vector2(0.036, 0.0), Vector2(0.036, -0.049), Vector2(0.00825, -0.06),
		Vector2(0.00825, -0.14), Vector2(0.075, -0.155), Vector2(0.075, -0.172), Vector2(-0.075, -0.172),
		Vector2(-0.075, -0.155), Vector2(-0.00825, -0.14), Vector2(-0.00825, -0.06), Vector2(-0.036, -0.049)]


## One rail between two frames: the section's faces (not the underside), the head's top polished.
func _rail_quads(m: Mesher, fa: Array, fb: Array) -> void:
	for j in RAIL_PROFILE.size():
		if j == 6:
			continue                        # the foot's underside, on the pads
		var p: Vector2 = RAIL_PROFILE[j]
		var q: Vector2 = RAIL_PROFILE[(j + 1) % RAIL_PROFILE.size()]
		var d := q - p
		var nl := Vector2(-d.y, d.x).normalized()   # outward (clockwise section)
		var a0: Vector3 = fa[0] + fa[1] * p.x + fa[2] * p.y
		var a1: Vector3 = fa[0] + fa[1] * q.x + fa[2] * q.y
		var b0: Vector3 = fb[0] + fb[1] * p.x + fb[2] * p.y
		var b1: Vector3 = fb[0] + fb[1] * q.x + fb[2] * q.y
		var nrm: Vector3 = (fa[1] * nl.x + fa[2] * nl.y).normalized()
		m.quad(a0, a1, b1, b0, nrm, RAIL_HEAD if j == 0 else RAIL_RUST)


## A sleeper (x across, y up, z along; origin at its centre): the concrete block, the rail pads and the clips of
## both rails' fastenings.
func _sleeper_mesh(tr: Dictionary) -> ArrayMesh:
	var m := Mesher.new()
	var sl: Dictionary = tr["sleeper"]
	var length: float = sl["length"]
	var width: float = sl["width"]
	var depth: float = sl["depth"]
	m.box(Transform3D.IDENTITY, Vector3(length, depth, width), SLEEPER)
	var half := float(tr["gauge"]) * 0.5 + float(tr["rail"]["head"]) * 0.5
	var foot: float = tr["rail"]["foot"]
	var pad: float = tr["pad"]
	for side: float in [-1.0, 1.0]:
		var x := side * half
		m.box(Transform3D(Basis.IDENTITY, Vector3(x, depth * 0.5 + pad * 0.5, 0.0)), Vector3(foot + 0.02, pad, width * 0.7),
				FASTENING)
		for e: float in [-1.0, 1.0]:
			m.box(Transform3D(Basis.IDENTITY, Vector3(x + e * (foot * 0.5 + 0.03), depth * 0.5 + 0.025, 0.0)),
					Vector3(0.05, 0.05, 0.12), FASTENING)
	return m.commit(_mat_toy)


## Sleeper instances every sleeper spacing on both tracks, per chunk: [TRANSFORM_3D buffer (chunk-local), AABB].
func _sleepers(span: Vector2, tracks: Array, tr: Dictionary) -> Dictionary:
	var out := {}
	var spacing: float = tr["sleeper"]["spacing"]
	var drop := float(tr["rail"]["height"]) + float(tr["pad"]) + float(tr["sleeper"]["depth"]) * 0.5
	var reach := Vector3.ONE * float(tr["sleeper"]["length"]) * 0.5
	var s := span.x + spacing * 0.5
	while s < span.y:
		var basis := _track_basis(s)
		var c: float = _rm.cant(s)
		var zc: float = _rm.level(s) + absf(c) * 0.5 - drop
		for t: Dictionary in tracks:
			var p: Vector2 = _rm.point(s, float(t["offset"]))
			var ck := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
			if not out.has(ck):
				out[ck] = [PackedFloat32Array(), AABB()]
			var o := _g(p.x, p.y, zc) - Vector3((ck.x + 0.5) * CHUNK, 0.0, -(ck.y + 0.5) * CHUNK)
			var g: Array = out[ck]
			g[0].append_array([basis.x.x, basis.y.x, basis.z.x, o.x, basis.x.y, basis.y.y, basis.z.y, o.y,
					basis.x.z, basis.y.z, basis.z.z, o.z])
			var box := AABB(o - reach, reach * 2.0)
			g[1] = box if g[0].size() == 12 else (g[1] as AABB).merge(box)
		s += spacing
	return out


# ---------------------------------------------------------------- rail bridges

## The line's short bridges beyond the first box (rail.json rail_bridges: the ground under them is the road's): a
## concrete deck under the formation from one formation edge to the other, parapets along both edges; collision for
## the deck top and the parapets (the ballast is the track's). Where a platform runs over one (Le Guichet's, over the
## N118), the platform's floor is a slab on the deck (the patch leaves no platform ground over the road): from behind
## its coping to the deck's edge, its wall under the coping, a railing along the edge.
func _rail_bridges(node: Node3D) -> void:
	for k in (_rail.get("rail_bridges", []) as Array).size():
		var m := Mesher.new()                   # one mesh each (see _cell_mesher)
		var b: Dictionary = _rail["rail_bridges"][k]
		var info := {"type": "rail_structure", "kind": "rail_bridge", "id": "rail_bridge:%d" % k, "osm": b.get("osm", [])}
		var faces := PackedVector3Array()
		var s0: float = b["s0"]
		var s1: float = b["s1"]
		var n := maxi(1, ceili((s1 - s0) / 1.0))
		var prev := []
		var slab_prev := {}                     # platform id -> its slab's previous row
		for i in n + 1:
			var s := lerpf(s0, s1, float(i) / n)
			var F := _ew_at(s, "formation")
			var ul := _ew_at(s, "edge", "left") + 0.3
			var ur := -_ew_at(s, "edge", "right") - 0.3
			var pl: Vector2 = _rm.point(s, ul)
			var pr: Vector2 = _rm.point(s, ur)
			var cur := [_g(pl.x, pl.y, F), _g(pr.x, pr.y, F), _g(pl.x, pl.y, F - 0.9), _g(pr.x, pr.y, F - 0.9)]
			if not prev.is_empty():
				var along: Vector3 = (cur[0] - prev[0]).normalized()
				var left := Vector3.UP.cross(along).normalized() * -1.0
				m.quad(prev[0], prev[1], cur[1], cur[0], Vector3.UP, CONCRETE)
				faces.append_array([prev[0], prev[1], cur[1], prev[0], cur[1], cur[0]])
				m.quad(prev[2], prev[3], cur[3], cur[2], Vector3.DOWN, Color(CONCRETE_DARK, 0.6))
				m.quad(prev[0], cur[0], cur[2], prev[2], left, CONCRETE_DARK)
				m.quad(prev[1], cur[1], cur[3], prev[3], -left, CONCRETE_DARK)
				for e in [[prev[0], cur[0], left], [prev[1], cur[1], -left]]:
					var a: Vector3 = e[0]
					var c: Vector3 = e[1]
					var o: Vector3 = e[2]
					var h := Vector3(0.0, 1.0, 0.0)
					m.quad(a, c, c + h, a + h, o, CONCRETE)
					m.quad(a - o * 0.3, c - o * 0.3, c - o * 0.3 + h, a - o * 0.3 + h, -o, CONCRETE)
					m.quad(a + h, c + h, c - o * 0.3 + h, a - o * 0.3 + h, Vector3.UP, CONCRETE)
					faces.append_array([a - o * 0.3, c - o * 0.3, c - o * 0.3 + h, a - o * 0.3, c - o * 0.3 + h, a - o * 0.3 + h])
			prev = cur
			for pf: Dictionary in _rail.get("platforms", []):
				var ends: Array = pf.get("ends", [float(pf["s0"]) - 0.5, float(pf["s1"]) + 0.5])
				if s < float(ends[0]) or s > float(ends[1]):
					slab_prev.erase(pf["id"])
					continue
				var side: float = pf["side"]
				var top := _platform_top(pf, s)
				var pi: Vector2 = _rm.point(s, side * (float(pf["wall"]) + COPING_BACK * 0.5))
				var po: Vector2 = pl if side > 0.0 else pr
				var row := [_g(pi.x, pi.y, top), _g(po.x, po.y, top), _g(pi.x, pi.y, F - 0.9), _g(po.x, po.y, F - 0.9),
						pi, po, top]
				var sp: Array = slab_prev.get(pf["id"], [])
				if not sp.is_empty():
					var along: Vector3 = (row[0] - sp[0]).normalized()
					var outw := (Vector3.UP.cross(along).normalized() * -1.0) * side     # towards the deck's edge
					m.quad(sp[0], sp[1], row[1], row[0], Vector3.UP, CONCRETE)             # the floor
					m.quad(sp[0], row[0], row[2], sp[2], -outw, COPING_FACE)                # its wall over the track
					m.quad(sp[1], row[1], row[3], sp[3], outw, CONCRETE_DARK)               # its outer face
					faces.append_array([sp[0], sp[1], row[1], sp[0], row[1], row[0]])
					faces.append_array([sp[0], row[0], row[2], sp[0], row[2], sp[2]])
					_railing(m, sp[5], sp[6], row[5], top, RAILING_HEIGHT, true, info)
				slab_prev[pf["id"]] = row
		_shape_faces("RailBridge_%d" % k, faces, info)
		_emit(node, "RailBridges_%d" % k, m, _mat_toy, {"type": "rail_structure", "id": "rail:bridges"}, PORTAL_RANGE)


# ---------------------------------------------------------------- the yard (tools/rail/yard.py)

## The yard's tracks beyond the alignment (rail.json yard tracks: each its own line, rail top per metre): rails and
## sleepers per CHUNK m chunk; the ballast is the patched ground's ("yard" zones), the sleepers' tops show above it.
func _yard(node: Node3D) -> void:
	var yard: Dictionary = _rail.get("yard", {})
	if yard.is_empty():
		return
	var tr: Dictionary = _rail["track"]
	var half := float(tr["gauge"]) * 0.5 + float(tr["rail"]["head"]) * 0.5
	var drop := float(tr["rail"]["height"]) + float(tr["pad"]) + float(tr["sleeper"]["depth"]) * 0.5
	var spacing: float = tr["sleeper"]["spacing"]
	var reach := Vector3.ONE * float(tr["sleeper"]["length"]) * 0.5
	var track_node := node.get_node("Track")
	var rails := {}                         # chunk -> Mesher
	var sleepers := {}                      # chunk -> [buffer, AABB]
	for t: Dictionary in yard.get("tracks", []):
		var pts: Array = t["pts"]
		var zs: Array = t["z"]
		var hs: Array = t["heading"]
		var prev := []
		var next_sleeper := spacing * 0.5
		var d := 0.0
		var drawn: Array = t.get("drawn", [0, pts.size() - 1])     # its run on the map's ground (build_rail.py)
		for i in range(int(drawn[0]), int(drawn[1]) + 1):
			var p := Vector2(pts[i][0], pts[i][1])
			if i > int(drawn[0]):
				d += p.distance_to(Vector2(pts[i - 1][0], pts[i - 1][1]))
			var th: float = hs[i]
			var left := Vector3(-sin(th), 0.0, -cos(th))
			var along := Vector3(cos(th), 0.0, -sin(th))
			var basis := Basis(left, Vector3.UP, along)
			var frames := []
			for side: float in [-1.0, 1.0]:
				var q := p + Vector2(-sin(th), cos(th)) * side * half
				frames.append([_g(q.x, q.y, zs[i]), left, Vector3.UP])
			var ck := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
			if not prev.is_empty():
				if not rails.has(ck):
					rails[ck] = Mesher.new()
				for k in 2:
					_rail_quads(rails[ck], prev[k], frames[k])
			prev = frames
			while next_sleeper <= d and i > int(drawn[0]):
				var f := (d - next_sleeper) / maxf(p.distance_to(Vector2(pts[i - 1][0], pts[i - 1][1])), 1e-6)
				var sp := p.lerp(Vector2(pts[i - 1][0], pts[i - 1][1]), f)
				var sz := lerpf(zs[i], zs[i - 1], f) - drop
				var sk := Vector2i(floori(sp.x / CHUNK), floori(sp.y / CHUNK))
				if not sleepers.has(sk):
					sleepers[sk] = [PackedFloat32Array(), AABB()]
				var o := _g(sp.x, sp.y, sz) - Vector3((sk.x + 0.5) * CHUNK, 0.0, -(sk.y + 0.5) * CHUNK)
				var g: Array = sleepers[sk]
				g[0].append_array([basis.x.x, basis.y.x, basis.z.x, o.x, basis.x.y, basis.y.y, basis.z.y, o.y,
						basis.x.z, basis.y.z, basis.z.z, o.z])
				var box := AABB(o - reach, reach * 2.0)
				g[1] = box if g[0].size() == 12 else (g[1] as AABB).merge(box)
				next_sleeper += spacing
	for ck: Vector2i in rails:
		var chunk := _chunk(track_node, ck)
		var mi := MeshInstance3D.new()
		mi.name = "YardRails"
		mi.mesh = MeshUtils.save((rails[ck] as Mesher).commit(_mat_toy), _mesh_dir + "rail_yard_rails_%d_%d.res" % [ck.x, ck.y])
		mi.position = -chunk.position
		mi.visibility_range_end = RAIL_RANGE
		mi.visibility_range_end_margin = 10.0
		mi.set_meta("plateau", {"type": "rail_track", "id": "rail:yard_%d_%d" % [ck.x, ck.y]})
		chunk.add_child(mi)
	var sleeper_mesh: ArrayMesh = load(_mesh_dir + "rail_sleeper.res")
	for ck: Vector2i in sleepers:
		var chunk := _chunk(track_node, ck)
		var buf: PackedFloat32Array = sleepers[ck][0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sleeper_mesh
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "YardSleepers"
		mmi.multimesh = mm
		mmi.custom_aabb = sleepers[ck][1]
		mmi.visibility_range_end = SLEEPER_RANGE
		mmi.visibility_range_end_margin = 10.0
		mmi.set_meta("plateau", {"type": "rail_track", "id": "rail:yard_sleepers_%d_%d" % [ck.x, ck.y]})
		chunk.add_child(mmi)


## The yard's islands (rail.json yard islands; their raised top is the patched ground's "island" zone): the edge
## coping over each track, the light band and the tactile strip behind it (walkable: collision), railings across the
## ends.
func _islands(node: Node3D) -> void:
	var m := Mesher.new()
	for isl: Dictionary in _rail.get("yard", {}).get("islands", []):
		var z: float = isl["top"]
		var info := {"type": "rail_platform", "id": isl["id"], "osm": isl.get("osm", ""), "name": isl["name"],
				"track": ", ".join(isl.get("refs", [])), "height": isl["top"], "tags": isl.get("tags", {})}
		var faces := PackedVector3Array()
		var spine: Array = isl["spine"]
		for e: Dictionary in isl["edges"]:
			var pts: Array = e["pts"]
			for i in pts.size() - 1:
				var a := Vector2(pts[i][0], pts[i][1])
				var b := Vector2(pts[i + 1][0], pts[i + 1][1])
				var c := Vector2(spine[mini(i, spine.size() - 1)][0], spine[mini(i, spine.size() - 1)][1])
				var inward := (c - a).normalized()   # from the edge onto the island
				var rows := []
				for u: float in [0.0, COPING_BACK + 0.30, BAND, BAND + TACTILE]:     # the coping is 0.30 m over the wall
					rows.append([a + inward * u, b + inward * u])
				var e0: Array = rows[0]
				var e1: Array = rows[1]
				var top := [_g(e0[0].x, e0[0].y, z + 0.012), _g(e1[0].x, e1[0].y, z + 0.012), _g(e1[1].x, e1[1].y, z + 0.012),
						_g(e0[1].x, e0[1].y, z + 0.012)]
				m.quad(top[0], top[1], top[2], top[3], Vector3.UP, COPING)
				var down := Vector3(0.0, -COPING_DEPTH - 0.012, 0.0)
				m.quad(top[0], top[3], top[3] + down, top[0] + down, _gd(-inward), COPING_FACE)
				faces.append_array([top[0], top[1], top[2], top[0], top[2], top[3]])
				var b0: Array = rows[2]
				var c0: Array = rows[3]
				m.quad(_g(e1[0].x, e1[0].y, z + 0.006), _g(b0[0].x, b0[0].y, z + 0.006), _g(b0[1].x, b0[1].y, z + 0.006),
						_g(e1[1].x, e1[1].y, z + 0.006), Vector3.UP, EDGE_SLABS)
				m.quad(_g(b0[0].x, b0[0].y, z + 0.008), _g(c0[0].x, c0[0].y, z + 0.008), _g(c0[1].x, c0[1].y, z + 0.008),
						_g(b0[1].x, b0[1].y, z + 0.008), Vector3.UP, TACTILE_COL)
		_shape_faces("Island_" + String(isl["id"]).replace(":", "_"), faces, info)
		# railings across both ends, edge to edge
		var ea: Array = isl["edges"][0]["pts"]
		var eb: Array = isl["edges"][1]["pts"]
		for k in [0, -1]:
			var a := Vector2(ea[k][0], ea[k][1])
			var b := Vector2(eb[k][0], eb[k][1])
			var d := (b - a).normalized()
			_railing(m, a + d * 0.35, z, b - d * 0.35, z, RAILING_HEIGHT, true, info)
	_emit(node, "Islands", m, _mat_toy, {"type": "rail_platform", "id": "rail:islands"}, STATION_RANGE)


# ---------------------------------------------------------------- the platforms and the station

## Frame of a piece of platform furniture at map (x, y, z) beside s: x along the platform (eastwards on the north
## platform, westwards on the south one), y up, z towards the track.
func _platform_frame(x: float, y: float, z: float, s: float, side: float) -> Transform3D:
	var th: float = _rm.heading(s)
	var along := Vector3(cos(th), 0.0, -sin(th)) * side
	var out := Vector3(sin(th), 0.0, cos(th)) * side         # -left * side: towards the track
	return Transform3D(Basis(along, Vector3.UP, out), _g(x, y, z))


## Platform top at s (rail.json platforms top, per metre from s0; the ends half a metre beyond s0 and s1).
static func _platform_top(pf: Dictionary, s: float) -> float:
	var top: Array = pf["top"]
	var f := clampf(s - float(pf["s0"]), 0.0, top.size() - 1.000001)
	var i := floori(f)
	return lerpf(top[i], top[i + 1], f - i)


static func _platform_back(pf: Dictionary, s: float) -> float:
	var back: Array = pf["back"]
	var f := clampf(s - float(pf["s0"]), 0.0, back.size() - 1.000001)
	var i := floori(f)
	return lerpf(back[i], back[i + 1], f - i)


## Both platforms: the edge coping overhanging the wall (walkable: collision), the light band of the edge slabs and
## the tactile strip behind it, the yellow line along the south platform's edge (photos), bar railings across the ends.
func _platforms(node: Node3D) -> void:
	for pf: Dictionary in _rail.get("platforms", []):
		var m := Mesher.new()                   # one mesh each (see _cell_mesher)
		var side: float = pf["side"]
		var edge: float = pf["edge"]
		var wall: float = pf["wall"]
		var ends: Array = pf.get("ends", [float(pf["s0"]) - 0.5, float(pf["s1"]) + 0.5])
		var info := {"type": "rail_platform", "id": pf["id"], "osm": pf["osm"], "name": pf["name"], "track": pf["track"],
				"height": pf["height"], "edge": edge - absf(_track_offset(pf["track"])),
				"length": float(ends[1]) - float(ends[0]), "tags": pf.get("tags", {})}
		var faces := PackedVector3Array()
		var n := maxi(1, ceili((float(ends[1]) - float(ends[0])) / 1.0))
		var prev := []
		for i in n + 1:
			var s: float = lerpf(ends[0], ends[1], float(i) / n)
			var z := _platform_top(pf, s)
			var row := []
			# u across (from the track outwards), the coping top a hair over the platform's ground
			for u: float in [edge, wall + COPING_BACK, edge + BAND, edge + BAND + TACTILE]:
				var p: Vector2 = _rm.point(s, side * u)
				row.append(p)
			var e0: Vector2 = row[0]
			var e1: Vector2 = row[1]
			var cur := [_g(e0.x, e0.y, z + 0.012), _g(e1.x, e1.y, z + 0.012), _g(e0.x, e0.y, z - COPING_DEPTH),
					_g(e1.x, e1.y, z - COPING_DEPTH), row, z]
			if not prev.is_empty():
				var up := Vector3.UP
				var out := _gd((row[0] as Vector2) - (row[1] as Vector2)).normalized()
				m.quad(prev[0], prev[1], cur[1], cur[0], up, COPING)                   # coping top
				m.quad(prev[0], cur[0], cur[2], prev[2], out, COPING_FACE)              # its face over the track
				m.quad(prev[2], cur[2], cur[3], prev[3], Vector3.DOWN, Color(COPING_FACE, 0.6))
				faces.append_array([prev[0], prev[1], cur[1], prev[0], cur[1], cur[0]])
				faces.append_array([prev[0], cur[0], cur[2], prev[0], cur[2], prev[2]])
				var pr: Array = prev[4]
				var zp: float = prev[5]
				# the light edge slabs and the tactile strip behind them, on the platform's ground
				var a0: Vector2 = pr[1]
				var a1: Vector2 = row[1]
				var b0: Vector2 = pr[2]
				var b1: Vector2 = row[2]
				var c0: Vector2 = pr[3]
				var c1: Vector2 = row[3]
				m.quad(_g(a0.x, a0.y, zp + 0.006), _g(b0.x, b0.y, zp + 0.006), _g(b1.x, b1.y, z + 0.006),
						_g(a1.x, a1.y, z + 0.006), up, EDGE_SLABS)
				m.quad(_g(b0.x, b0.y, zp + 0.008), _g(c0.x, c0.y, zp + 0.008), _g(c1.x, c1.y, z + 0.008),
						_g(b1.x, b1.y, z + 0.008), up, TACTILE_COL)
				if side < 0.0:
					var y0: Vector2 = _rm.point(s - (float(ends[1]) - float(ends[0])) / n, side * (edge + 0.03))
					var y1: Vector2 = _rm.point(s - (float(ends[1]) - float(ends[0])) / n, side * (edge + 0.03 + YELLOW_LINE))
					var y2: Vector2 = _rm.point(s, side * (edge + 0.03 + YELLOW_LINE))
					var y3: Vector2 = _rm.point(s, side * (edge + 0.03))
					m.quad(_g(y0.x, y0.y, zp + 0.016), _g(y1.x, y1.y, zp + 0.016), _g(y2.x, y2.y, z + 0.016),
							_g(y3.x, y3.y, z + 0.016), up, YELLOW)
			prev = cur
		_shape_faces("Platform_" + String(pf["id"]).get_slice(":", 1), faces, info)
		# railings across the ends, from the coping to the back
		for k in 2:
			var s: float = ends[k]
			var z := _platform_top(pf, s)
			var a: Vector2 = _rm.point(s, side * (edge + 0.35))
			var b: Vector2 = _rm.point(s, side * _platform_back(pf, s))
			_railing(m, a, z, b, z, RAILING_HEIGHT, true, info)
		_emit(node, "Platforms_" + String(pf["id"]).get_slice(":", 1) + "_" + String(pf["id"]).get_slice(":", 2),
				m, _mat_toy, {"type": "rail_platform", "id": "rail:platforms"}, STATION_RANGE)


func _track_offset(ref: String) -> float:
	for t: Dictionary in _rail["tracks"]:
		if t["ref"] == ref:
			return t["offset"]
	return 0.0


## The station's furniture (rail.json station furniture, placed by build_rail.py): lamps, benches, bins, the
## "Lozère" name boards, the track number boards, the departure screens, the Navigo validators at the entrances and the
## platform canopies; one toy mesh, one glow mesh (lamps, screens: night.gd), labels, and collision boxes.
func _furniture(node: Node3D) -> void:
	var station := Node3D.new()
	station.name = "Station"
	node.add_child(station)
	var cells := {}
	var glow_cells := {}
	var lights := PackedVector3Array()
	var n_screen := 0
	for f: Dictionary in _rail["station"].get("furniture", []):
		var m := _cell_mesher(cells, Vector2(f["x"], f["y"]))
		var glow := _cell_mesher(glow_cells, Vector2(f["x"], f["y"]))
		var pf := _platform_of(f.get("platform", ""))
		var side: float = pf.get("side", 1.0)
		var s: float = f.get("s", 0.0)
		var fz: float = f.get("z", _ground_at(Vector2(f["x"], f["y"])))
		var xf := _platform_frame(f["x"], f["y"], fz, s, side)
		if pf.is_empty() and f.has("yaw"):     # a yard island's (build_rail.py island_furniture): its own heading
			var to := Vector3(cos(deg_to_rad(f["yaw"])), 0.0, -sin(deg_to_rad(f["yaw"])))
			xf = Transform3D(Basis(Vector3.UP.cross(to).normalized(), Vector3.UP, to), _g(f["x"], f["y"], fz))
			pf = _island_of(f.get("platform", ""))
		var info := {"type": "rail_furniture", "kind": f["kind"], "id": "rail:%s_%s_%d" % [f["kind"], f.get("platform", ""), roundi(s)],
				"platform": f.get("platform", ""), "station": pf.get("name", _rail["station"]["name"])}
		match f["kind"]:
			"lamp":
				_lamp(m, glow, xf, info)
				lights.append(xf * Vector3(0.0, LAMP_HEIGHT - 0.25, 0.0))
			"bench":
				_bench(m, xf, int(f.get("seats", 3)), info)
			"bin":
				_bin(m, xf, info)
			"name_board":
				_board(station, m, xf, f.get("text", "Lozère"), f.get("subtitle", ""), info)
			"track_board":
				_track_board(station, m, xf, f.get("text", ""), info)
			"departure_screen":
				_screen(station, m, glow, xf, f, n_screen, info, info["station"])
				n_screen += 1
			"gates":
				info["name"] = f.get("name", "")
				info["osm"] = f.get("osm", "")
				_validators(m, f, int(f.get("count", 3)), info)
			"canopy":
				_canopy(m, xf, f["length"], f["depth"], info)
	_emit_cells(station, "Furniture", cells, _mat_toy, {"type": "rail_furniture", "id": "rail:furniture"}, STATION_RANGE)
	_emit_cells(station, "Glow", glow_cells, _mat_glow, {"type": "rail_furniture", "id": "rail:lamps"}, STATION_RANGE)
	station.set_meta("lamp_lights", lights)          # night.gd lights the platforms from there


func _island_of(id: String) -> Dictionary:
	for isl: Dictionary in _rail.get("yard", {}).get("islands", []):
		if isl["id"] == id:
			return isl
	return {}


func _platform_of(id: String) -> Dictionary:
	for pf: Dictionary in _rail.get("platforms", []):
		if pf["id"] == id:
			return pf
	return {}


## A platform lamp (photos: a pole with two luminaires on a cross arm along the platform).
func _lamp(m: Mesher, glow: Mesher, xf: Transform3D, info: Dictionary) -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0)), Vector3(0.12, LAMP_HEIGHT, 0.12), STEEL)
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT - 0.05, 0.0)), Vector3(1.6, 0.06, 0.06), STEEL)
	for e: float in [-0.75, 0.75]:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(e, LAMP_HEIGHT - 0.12, 0.0)), Vector3(0.5, 0.1, 0.22), ANTHRACITE)
		glow.box(xf * Transform3D(Basis.IDENTITY, Vector3(e, LAMP_HEIGHT - 0.18, 0.0)), Vector3(0.42, 0.02, 0.16), GLOW)
	_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0)), Vector3(0.14, LAMP_HEIGHT, 0.14), info)


## A row of `seats` blue shell seats on a beam, facing the track (photos).
func _bench(m: Mesher, xf: Transform3D, seats: int, info: Dictionary) -> void:
	var w := seats * SEAT_WIDTH
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, -0.05)), Vector3(w, 0.06, 0.08), ANTHRACITE)
	for e: float in [-w * 0.5 + 0.15, w * 0.5 - 0.15]:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(e, 0.15, -0.05)), Vector3(0.06, 0.3, 0.4), ANTHRACITE)
	for k in seats:
		var x := -w * 0.5 + (k + 0.5) * SEAT_WIDTH
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(x, 0.44, 0.0)), Vector3(SEAT_WIDTH - 0.06, 0.05, 0.42), SEAT_BLUE)
		m.box(xf * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(x, 0.7, -0.2)), Vector3(SEAT_WIDTH - 0.06, 0.45, 0.05), SEAT_BLUE)
	_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.45, 0.0)), Vector3(w, 0.9, 0.5), info)


## A Vigipirate bin: a ring on a post with its clear bag.
func _bin(m: Mesher, xf: Transform3D, info: Dictionary) -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -0.18)), Vector3(0.06, 1.0, 0.06), BIN_GREEN)
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.92, 0.0)), Vector3(0.36, 0.05, 0.36), BIN_GREEN)
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 0.0)), Vector3(0.3, 0.55, 0.3), Color("#d9dfe2"))
	_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3(0.38, 1.0, 0.38), info)


## The station name board (RATP: white lettering on dark blue, the station's name and its subtitle), on two posts,
## parallel to the track, lettered on both faces.
func _board(parent: Node3D, m: Mesher, xf: Transform3D, text: String, subtitle: String, info: Dictionary) -> void:
	var w := BOARD_SIZE.x
	var h := BOARD_SIZE.y
	for e: float in [-w * 0.4, w * 0.4]:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(e, BOARD_HEIGHT * 0.5, 0.0)), Vector3(0.08, BOARD_HEIGHT, 0.08), ANTHRACITE)
		_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(e, BOARD_HEIGHT * 0.5, 0.0)), Vector3(0.1, BOARD_HEIGHT, 0.1), info)
	var centre := Vector3(0.0, BOARD_HEIGHT + h * 0.5, 0.0)
	m.box(xf * Transform3D(Basis.IDENTITY, centre), Vector3(w, h, 0.06), RATP_BLUE)
	for face: float in [1.0, -1.0]:
		var holder := Node3D.new()
		holder.transform = xf * Transform3D(Basis(Vector3.UP, 0.0 if face > 0.0 else PI), Vector3.ZERO)
		holder.set_meta("plateau", info)
		parent.add_child(holder)
		_label(holder, text, centre + Vector3(0.0, 0.07 if subtitle else 0.0, 0.034), 150, Color.WHITE, w - 0.1)
		if subtitle:
			_label(holder, subtitle, centre + Vector3(0.0, -0.17, 0.034), 52, Color.WHITE, w - 0.1)


## The track number board ("Voie" n) above the platform edge.
func _track_board(parent: Node3D, m: Mesher, xf: Transform3D, text: String, info: Dictionary) -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)), Vector3(0.07, 2.8, 0.07), ANTHRACITE)
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.95, 0.0)), Vector3(0.5, 0.5, 0.05), RATP_BLUE)
	_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)), Vector3(0.09, 2.8, 0.09), info)
	for face: float in [1.0, -1.0]:
		var holder := Node3D.new()
		holder.transform = xf * Transform3D(Basis(Vector3.UP, 0.0 if face > 0.0 else PI), Vector3.ZERO)
		parent.add_child(holder)
		_label(holder, text, Vector3(0.0, 2.95, 0.03), 160, Color.WHITE, 0.45)


## A departure screen on a post, across the platform, readable from both ends; the runtime writes the next trains
## into its labels (named "Screen_<n>": the trains, scripts/train_traffic.gd).
func _screen(parent: Node3D, m: Mesher, glow: Mesher, xf: Transform3D, f: Dictionary, k: int, info: Dictionary,
		station_name := "Lozère") -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 0.0)), Vector3(0.1, 2.6, 0.1), ANTHRACITE)
	_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 0.0)), Vector3(0.12, 2.6, 0.12), info)
	var across := Basis(Vector3.UP, PI * 0.5)        # its faces along the platform
	var centre := Vector3(0.0, 2.9, 0.0)
	m.box(xf * Transform3D(across, centre), Vector3(1.1, 0.6, 0.12), Color("#202226"))
	glow.box(xf * Transform3D(across, centre), Vector3(1.0, 0.5, 0.125), Color("#10161f"))
	var holder := Node3D.new()
	holder.name = "Screen_%d" % k
	holder.transform = xf * Transform3D(across, Vector3.ZERO)
	var meta := info.duplicate()
	meta["platform"] = f.get("platform", "")
	holder.set_meta("plateau", meta)
	parent.add_child(holder)
	for face: float in [1.0, -1.0]:
		var side := Node3D.new()
		side.name = "Face%d" % (0 if face > 0.0 else 1)
		side.rotation.y = 0.0 if face > 0.0 else PI
		holder.add_child(side)
		var l := _label(side, station_name + "\n—", centre + Vector3(0.0, 0.0, 0.07), 26, SCREEN_AMBER, 0.95)
		l.name = "Text"


## Navigo validators at an entrance (photos: pillars with the purple reader under a lit panel), side by side across
## the way in.
func _validators(m: Mesher, f: Dictionary, count: int, info: Dictionary) -> void:
	var s: float = f["s"]
	var th: float = _rm.heading(s)
	var along := Vector3(cos(th), 0.0, -sin(th))
	var z := _ground_at(Vector2(f["x"], f["y"]))
	for k in count:
		var off := (k - (count - 1) * 0.5) * VALIDATOR_SPACING
		var p := _g(f["x"], f["y"], z) + along * off
		var xf := Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)), p)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0)), Vector3(0.3, 1.6, 0.22), STEEL)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.63, 0.0)), Vector3(0.32, 0.06, 0.24), BIN_GREEN)
		for face: float in [1.0, -1.0]:
			m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 0.115 * face)), Vector3(0.16, 0.16, 0.01), NAVIGO_PURPLE)
			m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.35, 0.115 * face)), Vector3(0.24, 0.3, 0.01), Color("#e8a64a"))
		_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0)), Vector3(0.3, 1.6, 0.22), info)


## A platform canopy `length` long along the station building backing the platform (build_rail.py puts its back line
## there), `depth` deep: posts along the back, brackets and the roof cantilevered towards the track, sloping a little
## (photos of the south platform's: brackets off the wall).
func _canopy(m: Mesher, xf: Transform3D, length: float, depth: float, info: Dictionary) -> void:
	var n := maxi(2, ceili(length / 4.0) + 1)
	var tilt := Basis(Vector3.RIGHT, CANOPY_TILT)
	for k in n:
		var x := -length * 0.5 + length * k / (n - 1)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(x, CANOPY_HEIGHT * 0.5, 0.1)), Vector3(0.12, CANOPY_HEIGHT, 0.12), STEEL)
		m.box(xf * Transform3D(tilt, Vector3(x, CANOPY_HEIGHT + 0.08, depth * 0.5)), Vector3(0.1, 0.12, depth), STEEL)
		_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(x, CANOPY_HEIGHT * 0.5, 0.1)), Vector3(0.14, CANOPY_HEIGHT, 0.14), info)
	m.box(xf * Transform3D(tilt, Vector3(0.0, CANOPY_HEIGHT + 0.2, depth * 0.5)), Vector3(length + 0.3, 0.08, depth + 0.2),
			ANTHRACITE)


func _label(parent: Node3D, text: String, pos: Vector3, size: int, color: Color, width: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = LABEL_PIXEL
	l.font_size = size
	l.outline_size = 0
	l.modulate = color
	l.width = width / LABEL_PIXEL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.visibility_range_end = 80.0
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- signals, posts, catenary

## The lineside signals inside the map box (rail.json signals): a mast beside the track, the target facing the trains
## it protects with a lamp per aspect it can show (rail.json states: VL green, A yellow, S and C red, R/RR yellow
## pairs), the ref plate; the speed boards (TIV) with their number. Each signal is a node (meta type rail_signal) whose
## lamps the trains switch (scripts/rail_signals.gd); they show green until then.
func _signals(node: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Signals"
	node.add_child(holder)
	var lens_off := StandardMaterial3D.new()
	lens_off.albedo_color = Color("#15171a")
	lens_off.roughness = 0.3
	MeshUtils.save(lens_off, _mesh_dir + "rail_lens_off.tres")
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = LENS_RADIUS
	lens_mesh.bottom_radius = LENS_RADIUS
	lens_mesh.height = 0.03
	lens_mesh.radial_segments = 12
	lens_mesh.rings = 1
	MeshUtils.save(lens_mesh, _mesh_dir + "rail_lens.res")
	var lit := {}
	for aspect: String in LENS_COLOURS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LENS_COLOURS[aspect]
		mat.emission_enabled = true
		mat.emission = LENS_COLOURS[aspect]
		mat.emission_energy_multiplier = SIGNAL_GLOW
		lit[aspect] = MeshUtils.save(mat, _mesh_dir + "rail_lens_%s.tres" % aspect.to_lower())
	var cells := {}
	var m: Mesher
	for sg: Dictionary in _rail.get("signals", []):
		var s: float = sg["s"]
		var p: Vector2 = _rm.point(s, float(sg["u"]))
		if not _box.has_point(p) or sg["kind"] == "unknown":
			continue
		m = _cell_mesher(cells, p)
		var facing: float = sg["facing"]
		var th: float = _rm.heading(s)
		var towards := Vector3(cos(th), 0.0, -sin(th)) * -facing      # the target faces the trains coming
		var basis := Basis(towards.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, towards)
		var g := _ground_at(p)
		var rail_z: float = _rm.level(s)
		var base := _g(p.x, p.y, g)
		var info := {"type": "rail_signal", "id": sg["id"], "osm": sg.get("osm", ""), "ref": sg.get("ref", ""),
				"kind": sg["kind"], "states": sg.get("states", []), "track": sg["track"], "facing": facing,
				"speed": sg.get("speed"), "plate": sg.get("plate", ""), "s": s}
		var node3 := Node3D.new()
		node3.name = String(sg["id"]).replace(":", "_")
		node3.transform = Transform3D(basis, base)
		node3.set_meta("plateau", info)
		holder.add_child(node3)
		if String(sg["kind"]).begins_with("FR:TIV"):
			var top := rail_z + 2.2 - g
			m.box(Transform3D(basis, base) * Transform3D(Basis.IDENTITY, Vector3(0.0, top * 0.5, 0.0)), Vector3(0.08, top, 0.08), ANTHRACITE)
			m.box(Transform3D(basis, base) * Transform3D(Basis.IDENTITY, Vector3(0.0, top + 0.3, 0.0)), Vector3(0.6, 0.6, 0.04), WHITE)
			_shape_box(Transform3D(basis, base) * Transform3D(Basis.IDENTITY, Vector3(0.0, top * 0.5, 0.0)), Vector3(0.1, top, 0.1), info)
			if sg.get("speed") != null:
				_label(node3, str(int(sg["speed"])), Vector3(0.0, top + 0.3, 0.025), 120, Color.BLACK, 0.55)
			continue
		var states: Array = sg.get("states", [])
		var rows := []                      # [aspect, offset across] top to bottom
		for a: String in ["VL", "A", "S", "R", "RR"]:
			if "FR:" + a in states:
				rows.append(a)
		if rows.is_empty():
			rows = ["VL", "S"]
		var carre := "FR:C" in states
		var head_h := rows.size() * LENS_PITCH + 0.15
		var head_w := 0.42 if not carre else 0.72
		var mast := rail_z + SIGNAL_HEIGHT - g
		var xf := Transform3D(basis, base)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast * 0.5, -0.12)), Vector3(0.14, mast, 0.14), STEEL)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast + head_h * 0.5, 0.0)), Vector3(head_w + 0.06, head_h + 0.06, 0.05), WHITE)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast + head_h * 0.5, 0.012)), Vector3(head_w, head_h, 0.05), Color("#141517"))
		_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast * 0.5, -0.12)), Vector3(0.16, mast, 0.16), info)
		var lamps := {}
		for r in rows.size():
			var y := mast + head_h - 0.15 - r * LENS_PITCH
			var aspect: String = rows[r]
			var x := 0.15 if carre else 0.0
			lamps[aspect] = _lens(node3, lens_mesh, lens_off, aspect, Vector3(x, y, 0.045))
			if carre and aspect == "S":
				lamps["C"] = _lens(node3, lens_mesh, lens_off, "C", Vector3(-0.15, y, 0.045))
		# the ref plate under the target, the F / Nf letters of the plate below it
		if sg.get("ref", "") != "":
			m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast - 0.22, 0.0)), Vector3(0.42, 0.22, 0.03), WHITE)
			_label(node3, sg["ref"], Vector3(0.0, mast - 0.22, 0.017), 64, Color.BLACK, 0.4)
		if sg.get("plate", "") in ["FR:F", "FR:NF"]:
			m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, mast - 0.5, 0.0)), Vector3(0.3, 0.26, 0.03), WHITE)
			_label(node3, "Nf" if sg["plate"] == "FR:NF" else "F", Vector3(0.0, mast - 0.5, 0.017), 72, Color.BLACK, 0.3)
		node3.set_meta("lamps", lamps)
		node3.set_meta("lit", lit)
		node3.set_meta("off", lens_off)
		_set_aspect(lamps, lit, lens_off, "VL" if "VL" in lamps else rows[0])
	_emit_cells(holder, "Masts", cells, _mat_toy, {"type": "rail_signal", "id": "rail:signals"}, SIGNAL_RANGE)


func _lens(parent: Node3D, mesh: Mesh, off: Material, aspect: String, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Lens_" + aspect
	mi.mesh = mesh
	mi.material_override = off
	mi.rotation.x = PI * 0.5                # the cylinder's axis towards the trains
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SIGNAL_RANGE
	parent.add_child(mi)
	return mi


## Lights the lamps of `aspect` (the carré "C": both reds), the others off. Shared with scripts/rail_signals.gd.
static func _set_aspect(lamps: Dictionary, lit: Dictionary, off: Material, aspect: String) -> void:
	for a: String in lamps:
		var on := a == aspect or (aspect == "C" and a == "S")
		(lamps[a] as MeshInstance3D).material_override = lit[a] if on else off


## Kilometre posts (rail.json pk: OSM, at their s, set beside their track outside the gauge) and the hectometre
## plates on the catenary masts.
func _posts(node: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Posts"
	node.add_child(holder)
	var cells := {}
	for post: Dictionary in _rail["pk"].get("posts", []):
		var s: float = post["s"]
		var side := signf(float(post["u"]))
		var u := side * (absf(_track_offset("2" if side > 0.0 else "1")) + POST_OFFSET)
		var p: Vector2 = _rm.point(s, u)
		if not _box.has_point(p):
			continue
		var g := _ground_at(p)
		var th: float = _rm.heading(s)
		var basis := Basis(Vector3.UP, th + (PI * 0.5 if side > 0.0 else -PI * 0.5))
		var xf := Transform3D(basis, _g(p.x, p.y, g))
		var info := {"type": "rail_pk", "id": post["id"], "osm": post.get("osm", ""), "km": post["km"], "s": s}
		_cell_mesher(cells, p).box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)), Vector3(0.3, 1.2, 0.12), WHITE)
		_shape_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)), Vector3(0.3, 1.2, 0.12), info)
		var l := Node3D.new()
		l.transform = xf
		l.set_meta("plateau", info)
		holder.add_child(l)
		for face: float in [1.0, -1.0]:
			var lab := _label(l, str(int(post["km"])), Vector3(0.0, 0.85, 0.061 * face), 90, Color.BLACK, 0.28)
			lab.rotation.y = 0.0 if face > 0.0 else PI
	var cat: Dictionary = _rail["catenary"]
	var supports: Array = cat["supports"]
	for plate: Dictionary in cat.get("plates", []):
		var sp: Dictionary = supports[int(plate["support"])]
		for mast: Array in sp["masts"]:
			var p := Vector2(mast[0], mast[1])
			if not _box.has_point(p):
				continue
			var s: float = sp["s"]
			var th: float = _rm.heading(s)
			var side := signf(float(mast[3]))
			var face := Vector3(sin(th), 0.0, cos(th)) * side          # towards the track
			var xf := Transform3D(Basis(face.cross(Vector3.UP) * -1.0, Vector3.UP, face), _g(p.x, p.y, float(mast[2]) + 2.2) + face * 0.2)
			_cell_mesher(cells, p).box(xf, Vector3(0.26, 0.16, 0.02), WHITE)
			var l := Node3D.new()
			l.transform = xf
			holder.add_child(l)
			_label(l, "%.1f" % float(plate["km"]), Vector3(0.0, 0.0, 0.011), 48, Color.BLACK, 0.25)
	_emit_cells(holder, "PK", cells, _mat_toy, {"type": "rail_pk", "id": "rail:pk"}, SIGNAL_RANGE)


## The catenary (rail.json catenary: portals by rule in build_rail.py): per support its two masts and the portal beam
## over both tracks, per track a drop tube and the registration arm holding the contact wire at its stagger; the
## contact wire and the messenger (sagging between supports, droppers every `droppers` m) per span. Masts and beams
## are drawn far (one mesh per far cell), the wires near (per track chunk).
func _catenary(node: Node3D) -> void:
	var cat: Dictionary = _rail["catenary"]
	var supports: Array = cat["supports"]
	var holder := Node3D.new()
	holder.name = "Catenary"
	node.add_child(holder)
	var masts := {}                         # far cell -> Mesher
	var wires := {}                         # track chunk -> Mesher
	var drop_step: float = cat.get("droppers", 5.0)
	for k in supports.size():
		var sp: Dictionary = supports[k]
		var mp: Vector2 = Vector2(sp["masts"][0][0], sp["masts"][0][1])
		var mq: Vector2 = Vector2(sp["masts"][1][0], sp["masts"][1][1])
		if not (_box.has_point(mp) or _box.has_point(mq)):
			continue
		var cell := Vector2i(floori(mp.x / FAR_CELL), floori(mp.y / FAR_CELL))
		if not masts.has(cell):
			masts[cell] = Mesher.new()
		var m: Mesher = masts[cell]
		var beam: float = sp["beam"]
		var info := {"type": "rail_catenary", "id": "rail:support_%d" % k, "s": sp["s"], "contact": cat["contact"]}
		for mast: Array in sp["masts"]:
			var base := _g(mast[0], mast[1], mast[2])
			var h: float = beam + 0.35 - float(mast[2])
			m.box(Transform3D(Basis.IDENTITY, base + Vector3(0.0, h * 0.5, 0.0)), Vector3(MAST, h, MAST), PORTAL)
			m.box(Transform3D(Basis.IDENTITY, base + Vector3(0.0, 0.15, 0.0)), Vector3(MAST + 0.25, 0.3, MAST + 0.25), CONCRETE)
			_shape_box(Transform3D(Basis.IDENTITY, base + Vector3(0.0, h * 0.5, 0.0)), Vector3(MAST, h, MAST), info)
		var bm := _beam(mp, beam, mq, beam, 0.22, 0.2, 0.2)
		m.box(bm[0], bm[1], PORTAL)
		for ref: String in sp["wires"]:
			var w: Array = sp["wires"][ref]
			var wp := Vector2(w[0], w[1])
			var z_c: float = w[2]
			var z_m: float = w[3]
			var on_beam := mp.lerp(mq, clampf(Geometry2D.get_closest_point_to_segment(wp, mp, mq).distance_to(mp) / mp.distance_to(mq), 0.0, 1.0))
			# drop tube from the beam, the arm out to the wire, the messenger's support
			m.box(Transform3D(Basis.IDENTITY, _g(on_beam.x, on_beam.y, (beam - 0.2 + z_c + 0.3) * 0.5)),
					Vector3(0.07, beam - 0.2 - z_c - 0.3, 0.07), PORTAL)
			var arm := _beam(on_beam, z_c + 0.3, wp, z_c + 0.05, 0.04, 0.02, 0.02)
			m.box(arm[0], arm[1], PORTAL)
			var marm := _beam(on_beam, z_m + 0.05, wp, z_m, 0.04, 0.02, 0.02)
			m.box(marm[0], marm[1], PORTAL)
			# the span to the next support
			if k + 1 < supports.size():
				var nx: Array = supports[k + 1]["wires"][ref]
				_wire_span(wires, Vector3(w[0], w[1], z_c), Vector3(nx[0], nx[1], nx[2]), z_m - z_c,
						float(nx[3]) - float(nx[2]), drop_step)
	for cell: Vector2i in masts:
		_emit(holder, "Portals_%d_%d" % [cell.x, cell.y], masts[cell], _mat_toy,
				{"type": "rail_catenary", "id": "rail:portals"}, PORTAL_RANGE)
	var track_node := node.get_node("Track")
	for ck: Vector2i in wires:
		var chunk := _chunk(track_node, ck)
		var mi := MeshInstance3D.new()
		mi.name = "Wires"
		mi.mesh = MeshUtils.save((wires[ck] as Mesher).commit(_mat_toy), _mesh_dir + "rail_wires_%d_%d.res" % [ck.x, ck.y])
		mi.position = -chunk.position
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = WIRE_RANGE
		mi.visibility_range_end_margin = 10.0
		mi.set_meta("plateau", {"type": "rail_catenary", "id": "rail:wires"})
		chunk.add_child(mi)


## One span (map x, y, z of the contact wire at both supports; the system height there): the contact wire straight,
## the messenger a parabola sagging to SAG_MID of the system height at mid-span, droppers between them.
func _wire_span(wires: Dictionary, a: Vector3, b: Vector3, ha: float, hb: float, drop_step: float) -> void:
	var length := Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
	if length < 1.0:
		return
	var n := maxi(1, roundi(length / drop_step))
	var prev_c := Vector3.ZERO
	var prev_m := Vector3.ZERO
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		var h := lerpf(ha, hb, t) * (1.0 - (1.0 - SAG_MID) * 4.0 * t * (1.0 - t))
		var c := _g(p.x, p.y, p.z)
		var mm := _g(p.x, p.y, p.z + h)
		var ck := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
		if not wires.has(ck):
			wires[ck] = Mesher.new()
		var m: Mesher = wires[ck]
		if i > 0:
			_wire(m, prev_c, c, WIRE)
			_wire(m, prev_m, mm, WIRE)
		if i > 0 and i < n:
			_wire(m, c, mm, WIRE, 0.008)
		prev_c = c
		prev_m = mm


## A thin wire from a to b (Godot): a square tube.
static func _wire(m: Mesher, a: Vector3, b: Vector3, col: Color, r := WIRE_RADIUS) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var z := d / length
	var x := Vector3.UP.cross(z)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	m.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(r * 2.0, r * 2.0, length), col)


## Concrete copings along the tops of the retaining walls (their faces are the patched ground's skirts).
func _walls(node: Node3D) -> void:
	var cells := {}
	for w: Dictionary in _rail["earthworks"].get("walls", []):
		var pts: Array = w["pts"]
		var top: Array = w["top"]
		var info := {"type": "rail_structure", "kind": "retaining_wall", "id": w["id"], "why": w.get("why", [])}
		for i in pts.size() - 1:
			var a := _v2(pts[i])
			var b := _v2(pts[i + 1])
			if not _box.has_point(a):
				continue
			var bm := _beam(a, float(top[i]), b, float(top[i + 1]), WALL_CAP.x, 0.05, WALL_CAP.y - 0.05)
			_cell_mesher(cells, a).box(bm[0], bm[1], CONCRETE)
	_emit_cells(node, "WallCopings", cells, _mat_toy, {"type": "rail_structure", "id": "rail:walls"}, PORTAL_RANGE)


## The gabled roofs patch_world.py asks for (world.json buildings[].rail_roof: the station building, whose body
## building_builder.gd stops at the eaves): slate planes over the longest walls with their overhang, the gable walls
## in the render colour with the station's name in brick lettering (photos), a brick chimney.
func _station_roofs(node: Node3D, world: Dictionary) -> void:
	for b: Dictionary in world["buildings"]:
		if not b.has("rail_roof"):
			continue
		var r: Dictionary = b["rail_roof"]
		var ring: Array = b["rings"][0]
		var pts: Array[Vector2] = []
		for q: Array in ring:
			pts.append(Vector2(q[0], q[1]))
		var d := Vector2.ZERO
		for i in pts.size():
			var e: Vector2 = pts[(i + 1) % pts.size()] - pts[i]
			if e.length() > d.length():
				d = e
		d = d.normalized()
		var n := Vector2(-d.y, d.x)
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var a0 := INF
		var a1 := -INF
		var b0 := INF
		var b1 := -INF
		for p in pts:
			a0 = minf(a0, (p - c).dot(d))
			a1 = maxf(a1, (p - c).dot(d))
			b0 = minf(b0, (p - c).dot(n))
			b1 = maxf(b1, (p - c).dot(n))
		var ov: float = r["overhang"]
		var eaves: float = r["eaves"]
		var rise: float = r["rise"]
		var half := (b1 - b0) * 0.5
		var bm := (b0 + b1) * 0.5
		var drop := ov * rise / half                    # the slope carried on over the overhang
		var slate := Color.html(r["slate"])
		var wall := Color.html(r["wall"])
		var brick := Color.html(r["accent"])
		var at := func(a: float, bb: float, z: float) -> Vector3:
			var p: Vector2 = c + d * a + n * bb
			return _g(p.x, p.y, z)
		var m := Mesher.new()
		var faces := PackedVector3Array()
		var info := {"type": "building_roof", "id": b["id"], "name": b.get("name", ""), "shape": "gabled"}
		for s: float in [-1.0, 1.0]:
			var eb := bm + s * (half + ov)
			var lo_a: Vector3 = at.call(a0 - ov, eb, eaves - drop)
			var lo_b: Vector3 = at.call(a1 + ov, eb, eaves - drop)
			var hi_a: Vector3 = at.call(a0 - ov, bm, eaves + rise)
			var hi_b: Vector3 = at.call(a1 + ov, bm, eaves + rise)
			var nrm := (hi_a - lo_a).cross(lo_b - lo_a).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			m.quad(lo_a, lo_b, hi_b, hi_a, nrm, slate)
			var t := Vector3(0.0, -0.12, 0.0)               # the slab's underside (soffit over the overhang)
			m.quad(lo_a + t, lo_b + t, hi_b + t, hi_a + t, -nrm, Color(wall, 0.7))
			m.quad(lo_a, lo_b, lo_b + t, lo_a + t, _gd(n * s), Color(slate, 0.8))
			faces.append_array([lo_a, lo_b, hi_b, lo_a, hi_b, hi_a])
		# the gables, flush with the end walls, and the verges over them
		for e: float in [a0, a1]:
			var out := d * signf(e)
			var g0: Vector3 = at.call(e, bm - half, eaves)
			var g1: Vector3 = at.call(e, bm + half, eaves)
			var g2: Vector3 = at.call(e, bm, eaves + rise)
			m.tri(g0, g1, g2, _gd(out), wall)
			for s: float in [-1.0, 1.0]:
				var v0: Vector3 = at.call(e + signf(e) * ov, bm + s * (half + ov), eaves - drop)
				var v1: Vector3 = at.call(e + signf(e) * ov, bm, eaves + rise)
				m.box(Transform3D(Basis.IDENTITY, (v0 + v1) * 0.5).looking_at(v1, Vector3.UP), Vector3(0.12, 0.12, v0.distance_to(v1)), Color(wall, 0.9))
			var holder := Node3D.new()
			var face_dir := _gd(out)
			holder.transform = Transform3D(Basis(face_dir.cross(Vector3.UP) * -1.0, Vector3.UP, face_dir),
					at.call(e, bm, eaves + rise * 0.32) + face_dir * 0.03)
			holder.set_meta("plateau", info)
			node.add_child(holder)
			_label(holder, String(_rail["station"]["name"]).to_upper(), Vector3.ZERO, 170, brick, (b1 - b0) * 0.9)
		var chimney: Vector3 = at.call(a1 - 2.5, bm + half * 0.35, eaves + rise * 0.65)
		m.box(Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), chimney + Vector3(0.0, 0.7, 0.0)), Vector3(0.9, 1.6, 0.5), brick)
		_emit(node, "Roof_" + String(b["id"]).replace(":", "_"), m, _mat_toy, info)
		_shape_faces("Roof_" + String(b["id"]).replace(":", "_"), faces, info)
