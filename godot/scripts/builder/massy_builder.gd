@tool
extends RefCounted
## Massy-Palaiseau's station precinct (world/rail.json `massy`, tools/rail/massy_station.py), drawn from code in the
## toy prop style of the RER B's structures (rail_builder.gd), its glazing in see-through glass
## (shaders/toy_prop_glass.gdshader):
## - the concourse deck the three footbridges share at their real level (le Lien, the historic footbridge, the Atlantis
##   bus station walkway), its edges (le Lien's glass walls, the historic one's panels, the walkway's glass
##   balustrades, railings round the stairwells), le Lien's pointed glass vault on white ribs, the flat roofs of its
##   halls and of the historic footbridge, the walkway's canopy on white portal frames over its red girders, the piers;
## - the stairs and escalators down to the forecourts and the RER B islands, the glazed lift shafts;
## - Massy TGV's hall (photo of its forecourt): the glazed gable under the tent roof, the arches behind the glass, the
##   two masts and their stays, the canopies over the doors, its name and clock;
## - the line 18 station: the surface hall (curtain walls behind brise-soleil fins, a roof of three bands rising to the
##   north-east, the white block at the high end, corten posts along the tracks), the stairs down into it from le Lien,
##   the shaft down to the mezzanine (the patched ground opens it: its floor is the mezzanine's), and under the ground
##   the station box: the tracks, two side platforms behind half-height platform doors, the mezzanine over the tracks
##   with its stairs down to each platform, the tunnel mouths, the lights and the signs. The metro runs in it in the
##   next patch.
## Collision (StaticBody3D "MassyCollision" on the buildings layer, each shape tagged "station_structure" for the
## picker): the floors as concave shells, walls, balustrades and railings as thin boxes, flights as ramps under their
## nosings, the TGV hall as a closed volume.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
const LabelFit = preload("res://scripts/label_fit.gd")
const HangarBuilder = preload("res://scripts/builder/hangar_builder.gd")
const RAIL_PATH := "res://world/rail.json"
const PROP_SHADER := "res://shaders/toy_prop.gdshader"
const GLASS_SHADER := "res://shaders/toy_prop_glass.gdshader"
const NO_LEG := ["road", "railway", "platform", "steps"]     # ground a canopy frame's leg never stands on
const LABEL_PIXEL := 0.002

const FLOOR := Color("#c9c4ba")             # the concourse's stone floor
const SOFFIT := Color("#e2e1dc")
const WHITE := Color("#f2f2ee")             # le Lien's ribs and frames, the walkway's portals (photos)
const FASCIA := Color("#e8e8e3")
const STEEL := Color("#b8bec5")
const DARK := Color("#3a3f46")              # TGV canopies, escalator handrails
const ROOF := Color("#767c84")              # the halls' grey roofs (render of the station)
const PANEL := Color("#d9dbdc")             # the historic footbridge's panels
const RED := Color("#b8372b")               # the walkway's girders and stairs (photo of the bus station)
const CONCRETE := Color("#d8d4cb")
const STONE := Color("#cfcac0")             # stair treads
const STEP_METAL := Color("#5a5f66")        # escalator steps
const TRUSS := Color("#a9afb6")             # escalator trusses
const GLASS := Color("#cfe4ea")             # the glazing's tint
const GLASS_GREEN := Color("#bfe0d6")       # the line 18 hall's (photo: green-grey glass)
const FABRIC := Color("#ece4cc")            # Massy TGV's tent roof (photo)
const CREAM := Color("#e9e6dc")
const CORTEN := Color("#8a4a2b")
const L18_GREEN := Color("#00a88f")         # line 18's colour
const SIGN_DARK := Color("#2b2f36")
const GLOW := Color("#fff3cc")
const TRACK_BED := Color("#6c6f73")
const RAIL := Color("#8e9399")
const TUNNEL := Color("#55585d")
const BLACK := Color("#121315")
const TGV_DOOR := Vector2(6.0, 3.2)         # m: Massy TGV's two doorways under the canopies (photo), width and height

var _mesh_dir := ""
var _mat: ShaderMaterial
var _glass: ShaderMaterial
var _glow: ShaderMaterial
var _ground: GroundHeights
var _map: RefCounted
var _body: StaticBody3D
var _node: Node3D
var _M: Dictionary
var _level := 0.0
var _depth := 0.9
var _meshers := {}                          # name -> [Mesher, material, visibility range, casts shadows]
var _box_faces := PackedVector3Array()      # the line 18 box's floors and walls (lambdas cannot append to a local)
var _lamp_lights := PackedVector3Array()    # night.gd lights the bus station and the hangar from these (node meta)


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> void:
	if not FileAccess.file_exists(RAIL_PATH):
		return
	var rail = JSON.parse_string(FileAccess.get_file_as_string(RAIL_PATH))
	if not rail is Dictionary or not (rail as Dictionary).has("massy"):
		return
	_M = rail["massy"]
	_level = _M["level"]
	_depth = _M["deck_depth"]
	_mesh_dir = mesh_dir
	var t: Dictionary = world["terrain"]
	_ground = GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	_map = GroundMap.get_map("res://world/" + String(world["ground_mesh"]["index"]))
	_mat = ShaderMaterial.new()
	_mat.shader = load(PROP_SHADER)
	_mat.set_shader_parameter("mode", 0)
	MeshUtils.save(_mat, mesh_dir + "massy_material.tres")
	_glass = ShaderMaterial.new()
	_glass.shader = load(GLASS_SHADER)
	_glass.set_shader_parameter("opacity", 0.22)
	MeshUtils.save(_glass, mesh_dir + "massy_glass.tres")
	_glow = ShaderMaterial.new()
	_glow.shader = load(PROP_SHADER)
	_glow.set_shader_parameter("mode", 2)
	MeshUtils.save(_glow, mesh_dir + "massy_glow.tres")
	_node = Node3D.new()
	_node.name = "MassyPalaiseau"
	root.add_child(_node)
	_body = StaticBody3D.new()
	_body.name = "MassyCollision"
	_body.collision_layer = Layers.BUILDINGS
	_body.collision_mask = 0
	_body.set_meta("plateau", {"type": "station_structure", "id": "massy"})
	root.add_child(_body)
	_deck()
	_edges()
	_vault()
	_flat_roofs()
	_canopies()
	_piers()
	for f: Dictionary in _M["flights"]:
		_flight(_mesher("Footbridges"), _mesher("Footbridges_Glass"), f, _info("flight", f["id"], String(f.get("osm", ""))))
	_lifts()
	_tgv()
	_l18_hall()
	_l18_box()
	if _M.has("bus_station"):              # the Atlantis bus station's finish and the bus hangar
		HangarBuilder.new().build(self, _M["bus_station"])
	_node.set_meta("lamp_lights", _lamp_lights)
	for name: String in _meshers:
		var e: Array = _meshers[name]
		_emit(name, e[0], e[1], e[2], e[3])
	print("massy: deck at %.2f m, %d flights, %d lifts, %d piers" % [_level, _M["flights"].size(), _M["lifts"].size(),
			_M["piers"].size()])


# ---------------------------------------------------------------- helpers

static func _g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func _gp(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, z, -p.y)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Godot direction of map direction d, horizontal.
static func _gd(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, -d.y)


## A right-handed frame standing up and facing `out` (Godot direction): a Label3D in it reads from that side.
static func _facing(out: Vector3) -> Basis:
	var z := Vector3(out.x, 0.0, out.z).normalized()
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)


## Map direction of a horizontal Godot direction.
static func _md(d: Vector3) -> Vector2:
	return Vector2(d.x, -d.z)


## A box from map point a (height za) to b (zb) along its centre line, `w` wide, from `below` under it to `above` over it
## (as rail_builder.gd _beam).
static func _beam(a: Vector2, za: float, b: Vector2, zb: float, w: float, below: float, above: float) -> Array:
	var pa := _gp(a, za)
	var pb := _gp(b, zb)
	var axis := pb - pa
	var length := axis.length()
	var z := axis / maxf(length, 1e-6)
	var x := Vector3.UP.cross(z).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	var centre := (pa + pb) * 0.5 + y * (above - below) * 0.5
	return [Transform3D(Basis(x, y, z), centre), Vector3(w, above + below, length)]


func _info(kind: String, id: String, osm := "", name := "") -> Dictionary:
	var d := {"type": "station_structure", "kind": kind, "id": id, "station": "Massy-Palaiseau"}
	if osm:
		d["osm"] = osm
	if name:
		d["name"] = name
	return d


## The Mesher named `name` (made on first use): toy material unless the name says Glass or Lights.
func _mesher(name: String, range_end := 1200.0) -> RailBuilder.Mesher:
	if not _meshers.has(name):
		var mat: Material = _glass if name.ends_with("Glass") else (_glow if name.ends_with("Lights") else _mat)
		_meshers[name] = [RailBuilder.Mesher.new(), mat, range_end, not name.ends_with("Glass")]
	return _meshers[name][0]


func _emit(name: String, m: RailBuilder.Mesher, mat: Material, range_end: float, shadows: bool) -> void:
	if m.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = MeshUtils.save(m.commit(mat), _mesh_dir + "massy_%s.res" % name.to_lower())
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = 20.0
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("plateau", _info("station", "massy:" + name.to_lower(), "", "Massy-Palaiseau"))
	_node.add_child(mi)


func _shape_faces(name: String, faces: PackedVector3Array, info: Dictionary) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	MeshUtils.save(shape, _mesh_dir + "massy_col_%s.res" % name.to_lower())
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = shape
	cs.set_meta("plateau", info)
	_body.add_child(cs)


## A thin wall's collision from a to b, z0 to z1.
func _wall_shape(a: Vector2, b: Vector2, z0: float, z1: float, thick: float, info: Dictionary) -> void:
	if a.distance_to(b) < 0.05 or z1 - z0 < 0.05:
		return
	var bm := _beam(a, z0, b, z0, thick, 0.0, z1 - z0)
	MeshUtils.shape_box(_body, bm[0], bm[1], info)


## A vertical quad from a to b, its bottom za0 / zb0 and top za1 / zb1 at either end, facing the left of a -> b
## (`both`: and the right).
func _vquad(m: RailBuilder.Mesher, a: Vector2, b: Vector2, za0: float, za1: float, zb0: float, zb1: float, col: Color,
		both := true) -> void:
	var d := (b - a).normalized()
	var nrm := _gd(Vector2(-d.y, d.x))
	m.quad(_gp(a, za0), _gp(b, zb0), _gp(b, zb1), _gp(a, za1), nrm, col)
	if both:
		m.quad(_gp(a, za0), _gp(b, zb0), _gp(b, zb1), _gp(a, za1), -nrm, col)


## A horizontal slab over the polygon {rings, tris}: its top at `top`, `thick` deep, the sides; returns the top's
## triangles (Godot points) for collision.
func _slab(m: RailBuilder.Mesher, poly: Dictionary, top: float, thick: float, col_top: Color, col_under: Color,
		col_side: Color) -> PackedVector3Array:
	var verts: Array[Vector2] = []
	var rings: Array = []
	for r: Array in poly["rings"]:
		var pr := PackedVector2Array()
		for q: Array in r:
			verts.append(_v2(q))
			pr.append(_v2(q))
		rings.append(pr)
	var faces := PackedVector3Array()
	var t: Array = poly["tris"]
	var bot := top - thick
	for k in range(0, t.size() - 2, 3):
		var a: Vector2 = verts[int(t[k])]
		var b: Vector2 = verts[int(t[k + 1])]
		var c: Vector2 = verts[int(t[k + 2])]
		m.tri(_gp(a, top), _gp(b, top), _gp(c, top), Vector3.UP, col_top)
		m.tri(_gp(a, bot), _gp(b, bot), _gp(c, bot), Vector3.DOWN, col_under)
		faces.append_array([_gp(a, top), _gp(b, top), _gp(c, top)])
	for ri in rings.size():
		var r: PackedVector2Array = rings[ri]
		for k in r.size():
			var a := r[k]
			var b := r[(k + 1) % r.size()]
			var e := b - a
			if e.length() < 0.01:
				continue
			var nrm := Vector2(e.y, -e.x).normalized()
			if _inside(rings, (a + b) * 0.5 + nrm * 0.03):
				nrm = -nrm
			m.quad(_gp(a, top), _gp(b, top), _gp(b, bot), _gp(a, bot), _gd(nrm), col_side)
	return faces


static func _inside(rings: Array, p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, rings[0]):
		return false
	for k in range(1, rings.size()):
		if Geometry2D.is_point_in_polygon(p, rings[k]):
			return false
	return true


## Posts, a top rail and a mid rail from a (height za) to b (zb), `h` high; its collision.
func _railing(m: RailBuilder.Mesher, a: Vector2, za: float, b: Vector2, zb: float, h: float, col: Color,
		info: Dictionary) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var posts := maxi(1, ceili(length / 1.5))
	for k in posts + 1:
		var tt := float(k) / posts
		var p := a.lerp(b, tt)
		m.box(Transform3D(Basis.IDENTITY, _gp(p, lerpf(za, zb, tt) + h * 0.5)), Vector3(0.05, h, 0.05), col)
	var top := _beam(a, za + h, b, zb + h, 0.06, 0.03, 0.03)
	m.box(top[0], top[1], col)
	var mid := _beam(a, za + h * 0.5, b, zb + h * 0.5, 0.035, 0.018, 0.018)
	m.box(mid[0], mid[1], col)
	var wall := _beam(a, za, b, zb, 0.08, 0.0, h)
	MeshUtils.shape_box(_body, wall[0], wall[1], info)


## A glass balustrade from a (za) to b (zb): glass panels, posts and a handrail; its collision.
func _balustrade(m: RailBuilder.Mesher, g: RailBuilder.Mesher, a: Vector2, za: float, b: Vector2, zb: float, h: float,
		rail_col: Color, info: Dictionary) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	_vquad(g, a, b, za + 0.08, za + h - 0.08, zb + 0.08, zb + h - 0.08, GLASS, false)
	var posts := maxi(1, ceili(length / 1.5))
	for k in posts + 1:
		var tt := float(k) / posts
		var p := a.lerp(b, tt)
		m.box(Transform3D(Basis.IDENTITY, _gp(p, lerpf(za, zb, tt) + h * 0.5)), Vector3(0.05, h, 0.05), STEEL)
	var top := _beam(a, za + h, b, zb + h, 0.07, 0.04, 0.03)
	m.box(top[0], top[1], rail_col)
	var wall := _beam(a, za, b, zb, 0.08, 0.0, h)
	MeshUtils.shape_box(_body, wall[0], wall[1], info)


# ---------------------------------------------------------------- the concourse deck

func _deck() -> void:
	var m := _mesher("Footbridges")
	var faces := PackedVector3Array()
	for d: Dictionary in _M["deck"]:
		faces.append_array(_slab(m, d, _level, _depth, FLOOR, Color(SOFFIT, 0.8), FASCIA))
	_shape_faces("Deck", faces, _info("deck", "massy:deck", "", "Concourse of the footbridges"))


## Along the deck's outline: le Lien's glass walls (mullions every 1.5 m, a white kick plate and head), the historic
## footbridge's panels (white below, a band of glass, grey above), the walkway's glass balustrades, railings round
## the stairwells.
func _edges() -> void:
	var m := _mesher("Footbridges")
	var g := _mesher("Footbridges_Glass")
	var z := _level
	for e: Array in _M["edges"]:
		var kind: String = e[0]
		var a := _v2(e[1])
		var b := _v2(e[2])
		var h: float = e[3]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var info := _info("edge", "massy:edge", "", String(_M["names"].get({"glass": "lien", "panel": "hist",
				"balustrade": "atlantis"}.get(kind, ""), "")))
		match kind:
			"glass":
				var kick := _beam(a, z, b, z, 0.12, 0.0, 0.25)
				m.box(kick[0], kick[1], WHITE)
				if h > 1.0:
					_vquad(g, a, b, z + 0.25, z + h, z + 0.25, z + h, GLASS, false)
					var head := _beam(a, z + h - 0.12, b, z + h - 0.12, 0.14, 0.0, 0.14)
					m.box(head[0], head[1], WHITE)
					var n := maxi(1, ceili(length / 1.5))
					for k in n + 1:
						var p := a.lerp(b, float(k) / n)
						m.box(Transform3D(Basis.IDENTITY, _gp(p, z + h * 0.5)), Vector3(0.07, h, 0.07), WHITE)
				# the vault's glass stands on these low walls: the collision goes up its sides
				_wall_shape(a, b, z, z + maxf(h, 2.6), 0.15, info)
			"panel":
				var low := _beam(a, z, b, z, 0.12, 0.0, 1.1)
				m.box(low[0], low[1], PANEL)
				_vquad(g, a, b, z + 1.1, z + h - 0.45, z + 1.1, z + h - 0.45, GLASS, false)
				var up := _beam(a, z + h - 0.45, b, z + h - 0.45, 0.12, 0.0, 0.45)
				m.box(up[0], up[1], ROOF)
				var n := maxi(1, ceili(length / 2.0))
				for k in n + 1:
					var p := a.lerp(b, float(k) / n)
					m.box(Transform3D(Basis.IDENTITY, _gp(p, z + h * 0.5)), Vector3(0.08, h, 0.08), STEEL)
				_wall_shape(a, b, z, z + h, 0.15, info)
			"balustrade":
				_balustrade(m, g, a, z, b, z, h, WHITE, info)
			_:
				_railing(m, a, z, b, z, h, STEEL, info)


# ---------------------------------------------------------------- le Lien's vault

## The pointed arch across the vault: (offset across, height) from one springing to the other. Two arcs centred on
## the springing line, each past the axis by c (an ogive: as the photo of its Vilmorin end), meeting at the apex.
static func _ogive(hw: float, spring: float, apex: float, n: int) -> PackedVector2Array:
	var rise := apex - spring
	var c := maxf((rise * rise - hw * hw) / (2.0 * hw), 0.0)
	var r := hw + c
	var out := PackedVector2Array()
	for s: float in [-1.0, 1.0]:
		var cx := -s * c
		var f0 := atan2(0.0, s * hw - cx)
		var f1 := atan2(rise, -cx)
		var pts := PackedVector2Array()
		for k in n + 1:
			var f := lerpf(f0, f1, float(k) / n)
			pts.append(Vector2(cx + r * cos(f), spring + r * sin(f)))
		if s > 0.0:
			pts.reverse()
		out.append_array(pts if s < 0.0 else pts.slice(1))
	return out


func _vault() -> void:
	var v: Dictionary = _M["roofs"]["vault"]
	var a := _v2(v["a"])
	var b := _v2(v["b"])
	var hw: float = float(v["width"]) * 0.5 - 0.1
	var spring: float = v["spring"]
	var apex: float = v["apex"]
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var length := a.distance_to(b)
	var prof := _ogive(hw, spring, apex, 8)
	var m := _mesher("Footbridges")
	var g := _mesher("Footbridges_Glass")
	# the glass skin, one strip per profile segment along the whole tube
	for k in prof.size() - 1:
		var p0 := prof[k]
		var p1 := prof[k + 1]
		var mid := (p0 + p1) * 0.5
		var out := Vector3(n.x * mid.x, mid.y - spring - 0.001, -n.y * mid.x).normalized()
		g.quad(_gp(a + n * p0.x, p0.y), _gp(b + n * p0.x, p0.y), _gp(b + n * p1.x, p1.y), _gp(a + n * p1.x, p1.y),
				out if out.length() > 0.5 else Vector3.UP, GLASS)
	# white ribs every rib_step, thicker at the ends; purlins along the springings, the haunches and the apex
	var step: float = v["rib_step"]
	var count := maxi(1, ceili(length / step))
	for i in count + 1:
		var t := length * i / count
		var o := a + d * t
		var w := 0.45 if i == 0 or i == count else 0.16
		for k in prof.size() - 1:
			var bm := _beam(o + n * prof[k].x, prof[k].y, o + n * prof[k + 1].x, prof[k + 1].y, w, 0.12, 0.12)
			m.box(bm[0], bm[1], WHITE)
	for k: int in [0, 3, 8, 13, prof.size() - 1]:
		var pk := prof[k]
		var bm := _beam(a + n * pk.x, pk.y, b + n * pk.x, pk.y, 0.12, 0.08, 0.08)
		m.box(bm[0], bm[1], WHITE)
	# glazed ends above the doors' height (the edges below are the deck's)
	var door := _level + 3.0
	for end: Vector2 in [a, b]:
		for k in prof.size() - 1:
			var p0 := prof[k]
			var p1 := prof[k + 1]
			if maxf(p0.y, p1.y) <= door:
				continue
			var q0 := Vector2(p0.x, maxf(p0.y, door))
			var q1 := Vector2(p1.x, maxf(p1.y, door))
			g.quad(_gp(end + n * q0.x, door), _gp(end + n * q1.x, door), _gp(end + n * q1.x, q1.y),
					_gp(end + n * q0.x, q0.y), _gd(d), GLASS)
		var tr := _beam(end - n * hw, door, end + n * hw, door, 0.25, 0.12, 0.12)
		m.box(tr[0], tr[1], WHITE)


# ---------------------------------------------------------------- roofs, canopies, piers

func _flat_roofs() -> void:
	var m := _mesher("Footbridges")
	for r: Dictionary in _M["roofs"]["flat"]:
		var top: float = float(r["z"]) + 0.35
		_slab(m, r, top, 0.35, ROOF, Color(SOFFIT, 0.85), FASCIA)
		# the fascia band round its edge, a little deeper than the slab
		for ring: Array in [r["rings"][0]]:
			for k in ring.size():
				var p := _v2(ring[k])
				var q := _v2(ring[(k + 1) % ring.size()])
				var bm := _beam(p, top + 0.15, q, top + 0.15, 0.1, 0.65, 0.0)
				m.box(bm[0], bm[1], FASCIA)


## The walkway's canopy (photo of the Atlantis bus station): a white slab on white portal frames every frame_step m,
## their legs down to the ground (or to the deck over a road, the railway or a platform), red girders under the deck.
func _canopies() -> void:
	var m := _mesher("Footbridges")
	var step: float = _M["roofs"]["frame_step"]
	for c: Dictionary in _M["roofs"]["canopy"]:
		var top: float = float(c["z"]) + 0.3
		_slab(m, c, top, 0.3, WHITE, Color("#d5d8d9"), WHITE)
		var a := _v2(c["a"])
		var b := _v2(c["b"])
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var hw: float = float(c["width"]) * 0.5
		var length := a.distance_to(b)
		var count := maxi(1, ceili(length / step))
		for i in count + 1:
			var o := a + d * (length * i / count)
			var beam := _beam(o - n * hw, top + 0.6, o + n * hw, top + 0.6, 0.5, 0.9, 0.0)
			m.box(beam[0], beam[1], WHITE)
			for s: float in [-1.0, 1.0]:
				var q := o + n * s * (hw - 0.3)
				var gz := _ground.at(q.x, q.y)
				var pk: int = _map.piece_at(q.x, q.y) if _map else -1
				var base := gz
				if (pk >= 0 and _map.pieces[pk][0] in NO_LEG) or gz > _level - 1.0:
					base = _level
				var leg := Transform3D(Basis.IDENTITY, _gp(q, (base + top) * 0.5))
				m.box(leg, Vector3(0.55, top - base, 0.55), WHITE)
				MeshUtils.shape_box(_body, leg, Vector3(0.55, top - base, 0.55), _info("frame", "massy:canopy-frame"))
		# the red girders under the walkway's deck
		for s: float in [-1.0, 1.0]:
			var off := n * s * maxf(hw - 2.0, 0.5)
			var gb := _beam(a + off, _level - _depth, b + off, _level - _depth, 0.45, 0.6, 0.0)
			m.box(gb[0], gb[1], RED)


func _piers() -> void:
	var m := _mesher("Footbridges")
	var s: float = _M["pier_size"]
	var top := _level - _depth
	for p: Array in _M["piers"]:
		var gz: float = p[2]
		if top - gz < 0.5:
			continue
		var xf := Transform3D(Basis.IDENTITY, _g(p[0], p[1], (gz + top) * 0.5))
		m.box(xf, Vector3(s, top - gz, s), WHITE)
		MeshUtils.shape_box(_body, xf, Vector3(s, top - gz, s), _info("pier", "massy:pier"))


# ---------------------------------------------------------------- stairs, escalators, lifts

## A flight along f.pts with a height per point (f.zs): flat runs are landings, sloped runs carry their share of
## f.steps steps. Stairs: stone treads on steel stringers, railings; escalators: metal steps, a truss under them,
## glass balustrades with black handrails. A ramp collision under the nosings, boxes under the landings.
func _flight(m: RailBuilder.Mesher, g: RailBuilder.Mesher, f: Dictionary, info: Dictionary) -> void:
	var pts: Array = f["pts"]
	var zs: Array = f["zs"]
	var w: float = f["width"]
	var esc: bool = f["escalator"]
	var total := 0.0
	for i in pts.size() - 1:
		total += absf(float(zs[i + 1]) - float(zs[i]))
	if total < 0.05:
		return
	var nsteps: int = f["steps"]
	for i in pts.size() - 1:
		var a := _v2(pts[i])
		var b := _v2(pts[i + 1])
		var za: float = zs[i]
		var zb: float = zs[i + 1]
		if a.distance_to(b) < 0.05:
			continue
		var d := (b - a).normalized()
		var nn := Vector2(-d.y, d.x)
		if absf(zb - za) < 0.02:
			var pl := _beam(a, za, b, zb, w + 0.2, 0.3, 0.0)
			m.box(pl[0], pl[1], STEP_METAL if esc else STONE)
			MeshUtils.shape_box(_body, pl[0], pl[1], info)
		else:
			var k := maxi(1, roundi(nsteps * absf(zb - za) / total))
			for j in k:
				var p0 := a.lerp(b, float(j) / k)
				var p1 := a.lerp(b, float(j + 1) / k)
				var top := za + (zb - za) * (j + 1) / k if zb > za else za + (zb - za) * j / k
				var bm := _beam(p0, top, p1, top, w, absf(zb - za) / k + 0.08, 0.0)
				m.box(bm[0], bm[1], STEP_METAL if esc else STONE)
			if esc:
				var tr := _beam(a, za - 0.15, b, zb - 0.15, w + 0.25, 1.0, 0.0)
				m.box(tr[0], tr[1], TRUSS)
			var ramp := _beam(a, za, b, zb, w, 0.3, 0.0)
			MeshUtils.shape_box(_body, ramp[0], ramp[1], info)
		for side: float in [1.0, -1.0]:
			var off := nn * side * (w * 0.5 + 0.06)
			if esc:
				_balustrade(m, g, a + off, za, b + off, zb, 1.0, DARK, info)
			else:
				var st := _beam(a + off, za, b + off, zb, 0.12, 0.35, 0.05)
				m.box(st[0], st[1], RED if _is_atlantis(a) else STEEL)
				_railing(m, a + off, za, b + off, zb, 1.1, STEEL, info)


## Whether map point p is by the Atlantis walkway (its stairs are red, photo).
func _is_atlantis(p: Vector2) -> bool:
	for c: Dictionary in _M["roofs"]["canopy"]:
		var ring := PackedVector2Array()
		for q: Array in c["rings"][0]:
			ring.append(_v2(q))
		var cen := Vector2.ZERO
		for q in ring:
			cen += q
		cen /= ring.size()
		if Geometry2D.is_point_in_polygon(p, ring) or p.distance_to(cen) < 25.0 and Geometry2D.is_point_in_polygon(
				p + (cen - p).normalized() * minf(p.distance_to(cen), 14.0), ring):
			return true
	return false


func _lifts() -> void:
	var m := _mesher("Footbridges")
	var g := _mesher("Footbridges_Glass")
	for lf: Dictionary in _M["lifts"]:
		var r: Array = lf["ring"]
		var z0: float = lf["bottom"]
		var z1: float = lf["top"]
		var info := _info("lift", lf["id"], lf["osm"])
		for k in 4:
			var a := _v2(r[k])
			var b := _v2(r[(k + 1) % 4])
			_vquad(g, a, b, z0 + 0.2, z1 - 0.3, z0 + 0.2, z1 - 0.3, GLASS, false)
			m.box(Transform3D(Basis.IDENTITY, _gp(a, (z0 + z1) * 0.5)), Vector3(0.14, z1 - z0, 0.14), STEEL)
			for zz: float in [z0 + 0.1, _level + 0.1, z1 - 0.15]:
				var bm := _beam(a, zz, b, zz, 0.12, 0.1, 0.1)
				m.box(bm[0], bm[1], STEEL)
		var c := (_v2(r[0]) + _v2(r[2])) * 0.5
		var e0 := _v2(r[1]) - _v2(r[0])
		var e1 := _v2(r[2]) - _v2(r[1])
		var basis := Basis(_gd(e0.normalized()), Vector3.UP, _gd(e0.normalized()).cross(Vector3.UP).normalized())
		var xf := Transform3D(basis, _gp(c, (z0 + z1) * 0.5))
		m.box(Transform3D(basis, _gp(c, z1 - 0.1)), Vector3(e0.length() + 0.2, 0.25, e1.length() + 0.2), STEEL)
		MeshUtils.shape_box(_body, xf, Vector3(e0.length(), z1 - z0, e1.length()), info)


# ---------------------------------------------------------------- Massy TGV

func _tgv() -> void:
	var T: Dictionary = _M["tgv"]
	var c: Array = T["corners"]
	var fa := _v2(c[0])
	var fb := _v2(c[1])
	var bb := _v2(c[2])
	var ba := _v2(c[3])
	var g0: float = T["ground"]
	var low: float = T["low"]
	var E: float = T["eaves"]
	var R: float = T["ridge"]
	var m := _mesher("TGV")
	var gl := _mesher("TGV_Glass")
	var info := _info("hall", T["id"], T["osm"], T["name"])
	var fm := (fa + fb) * 0.5
	var bm_ := (ba + bb) * 0.5
	var back := (bm_ - fm).normalized()                 # from the front into the hall
	var right := (fb - fa).normalized()
	# the plinth down to the trench beside the hall
	if low < g0 - 0.3:
		for e: Array in [[fa, fb], [fb, bb], [bb, ba], [ba, fa]]:
			_vquad(m, e[0], e[1], low, g0, low, g0, CONCRETE)
	# the side walls: shopfronts between concrete pillars, white cladding up to the eaves
	for e: Array in [[fb, bb], [ba, fa]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		_vquad(gl, a, b, g0, g0 + 4.5, g0, g0 + 4.5, GLASS, false)
		_vquad(m, a, b, g0 + 4.5, E, g0 + 4.5, E, CREAM)
		var n := maxi(1, ceili(a.distance_to(b) / 6.0))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			m.box(Transform3D(Basis.IDENTITY, _gp(p, g0 + 2.25)), Vector3(0.8, 4.5, 0.8), CONCRETE)
	# the back wall and its gable
	_vquad(m, bb, ba, g0, E, g0, E, CREAM)
	m.tri(_gp(bb, E), _gp(ba, E), _gp(bm_, R), _gd(back), CREAM)
	m.tri(_gp(bb, E), _gp(ba, E), _gp(bm_, R), -_gd(back), CREAM)
	# the glazed front and gable, on a grid of white mullions, open at the two doors under the canopies
	var width := fa.distance_to(fb)
	var doors := [width * 0.25, width * 0.75]
	var runs := [[0.0, doors[0] - TGV_DOOR.x * 0.5], [doors[0] + TGV_DOOR.x * 0.5, doors[1] - TGV_DOOR.x * 0.5],
			[doors[1] + TGV_DOOR.x * 0.5, width]]
	for rn: Array in runs:
		var p0: Vector2 = fa + right * float(rn[0])
		var p1: Vector2 = fa + right * float(rn[1])
		_vquad(gl, p0, p1, g0, g0 + TGV_DOOR.y, g0, g0 + TGV_DOOR.y, GLASS, false)
		_wall_shape(p0, p1, g0 - 1.0, g0 + TGV_DOOR.y, 0.3, info)
	_vquad(gl, fa, fb, g0 + TGV_DOOR.y, E, g0 + TGV_DOOR.y, E, GLASS, false)
	_wall_shape(fa, fb, g0 + TGV_DOOR.y, E, 0.3, info)
	gl.tri(_gp(fa, E), _gp(fb, E), _gp(fm, R), -_gd(back), GLASS)
	for dx: float in doors:
		for s: float in [-0.5, 0.5]:
			var post := fa + right * (dx + s * TGV_DOOR.x)
			m.box(Transform3D(Basis.IDENTITY, _gp(post, g0 + TGV_DOOR.y * 0.5)), Vector3(0.2, TGV_DOOR.y, 0.2), DARK)
		var lt := _beam(fa + right * (dx - TGV_DOOR.x * 0.5), g0 + TGV_DOOR.y, fa + right * (dx + TGV_DOOR.x * 0.5),
				g0 + TGV_DOOR.y, 0.25, 0.0, 0.3)
		m.box(lt[0], lt[1], DARK)
	var cols := maxi(2, roundi(width / 2.6))
	for k in cols + 1:
		var t := float(k) / cols
		var p := fa.lerp(fb, t)
		var top := E + (R - E) * (1.0 - absf(t - 0.5) * 2.0)
		m.box(Transform3D(Basis.IDENTITY, _gp(p - back * 0.05, (g0 + top) * 0.5)), Vector3(0.12, top - g0, 0.12), WHITE)
	var z := g0 + 4.6
	while z < R - 0.5:
		var half := 0.5 if z <= E else 0.5 * (R - z) / (R - E)
		var pa := fm + (fa - fm) * half * 2.0
		var pb := fm + (fb - fm) * half * 2.0
		var tb := _beam(pa - back * 0.05, z, pb - back * 0.05, z, 0.1, 0.06, 0.06)
		m.box(tb[0], tb[1], WHITE)
		z += 2.6
	# the tent roof: two slopes from the eaves to the ridge, past the front and the sides, its dark verges
	var ov := 1.6
	var drop := ov * (R - E) / (width * 0.5)
	var fa_e := fa - back * ov - right * ov
	var fb_e := fb - back * ov + right * ov
	var ba_e := ba + back * 0.6 - right * ov
	var bb_e := bb + back * 0.6 + right * ov
	var fm_r := fm - back * ov
	var bm_r := bm_ + back * 0.6
	for s: Array in [[fa_e, ba_e], [fb_e, bb_e]]:
		var p0: Vector2 = s[0]
		var p1: Vector2 = s[1]
		var q0 := _gp(p0, E - drop)
		var q1 := _gp(p1, E - drop)
		var r0 := _gp(fm_r, R)
		var r1 := _gp(bm_r, R)
		var up := (r0 - q0).cross(q1 - q0).normalized()
		if up.y < 0.0:
			up = -up
		m.quad(q0, q1, r1, r0, up, FABRIC)
		m.quad(q0 + Vector3(0, -0.2, 0), q1 + Vector3(0, -0.2, 0), r1 + Vector3(0, -0.2, 0), r0 + Vector3(0, -0.2, 0),
				-up, Color(FABRIC, 0.75))
		var vg := _beam(p0, E - drop, fm_r, R, 0.35, 0.3, 0.05)
		m.box(vg[0], vg[1], DARK)
	# arches across the hall under the roof, seen through the glass (photo)
	for i in range(1, 5):
		var o := fm.lerp(bm_, i / 5.0)
		var prev := Vector2.ZERO
		var prev_z := 0.0
		for k in 13:
			var t := float(k) / 12.0
			var p := o.lerp(o + (fa - fm), 1.0 - t * 2.0) if t <= 0.5 else o.lerp(o + (fb - fm), t * 2.0 - 1.0)
			var zz := E - 0.6 + (R - E - 1.6) * sin(PI * t)
			if k > 0:
				var bm2 := _beam(prev, prev_z, p, zz, 0.2, 0.2, 0.2)
				m.box(bm2[0], bm2[1], DARK)
			prev = p
			prev_z = zz
	# the masts at the front corners and their stays (photo)
	var mast: float = T["mast"]
	for s: float in [-1.0, 1.0]:
		var corner := fa if s < 0.0 else fb
		var base := corner - back * 2.5 + right * s * 1.5
		m.box(Transform3D(Basis.IDENTITY, _gp(base, (g0 + mast) * 0.5)), Vector3(0.5, mast - g0, 0.5), WHITE)
		MeshUtils.shape_box(_body, Transform3D(Basis.IDENTITY, _gp(base, (g0 + mast) * 0.5)), Vector3(0.5, mast - g0, 0.5), info)
		for to: Array in [[fm_r, R], [corner - back * ov + right * s * ov, E - drop], [corner + back * 12.0, E]]:
			var st := _beam(base, mast - 0.3, to[0], to[1], 0.05, 0.025, 0.025)
			m.box(st[0], st[1], DARK)
	# the canopies over the doors, rising to the gap in the middle (photo)
	var cz: float = g0 + float(T["canopy"][0])
	var depth: float = T["canopy"][1]
	for s: Array in [[fa - right * 1.0, fm - right * 1.8], [fb + right * 1.0, fm + right * 1.8]]:
		var p0: Vector2 = s[0]
		var p1: Vector2 = s[1]
		var o0 := p0 - back * depth
		var o1 := p1 - back * depth
		var q := [_gp(p0, cz), _gp(p1, cz + 0.9), _gp(o1, cz + 0.9), _gp(o0, cz)]
		m.quad(q[0], q[1], q[2], q[3], Vector3.UP, DARK)
		var dn := Vector3(0, -0.3, 0)
		m.quad(q[0] + dn, q[1] + dn, q[2] + dn, q[3] + dn, Vector3.DOWN, Color("#50565e"))
		m.quad(q[3], q[2], q[2] + dn, q[3] + dn, -_gd(back), DARK)
		for p: Vector2 in [o0.lerp(o1, 0.15), o0.lerp(o1, 0.85)]:
			var post := Transform3D(Basis.IDENTITY, _gp(p + back * 0.4, (g0 + cz) * 0.5))
			m.box(post, Vector3(0.3, cz - g0, 0.3), WHITE)
			MeshUtils.shape_box(_body, post, Vector3(0.3, cz - g0, 0.3), info)
	# its walls' collision (the front's is above, open at the doors), the hall inside, the ways down to the platforms
	for e: Array in [[fb, bb], [bb, ba], [ba, fa]]:
		_wall_shape(e[0], e[1], minf(low, g0) - 1.0, E, 0.4, info)
	_tgv_interior(T, fa, fb, ba, right, back, info)
	_tgv_accesses(T)
	# its name over the doors and the clock in the gable, on the glass, facing the forecourt
	var holder := Node3D.new()
	holder.name = "TGV_Signs"
	var face := -back
	var fb_ := _facing(_gd(face))
	holder.transform = Transform3D(fb_, _gp(fm + face * 0.12, 0.0))
	holder.set_meta("plateau", info)
	_node.add_child(holder)
	var l := _label(holder, "GARE DE MASSY TGV", Vector3(0.0, g0 + 7.6, 0.0), 900, Color("#f1f1f1"), width * 0.6)
	LabelFit.fit(l, Vector2(width * 0.6, 1.4))
	var cc := _gp(fm + face * 0.15, g0 + 12.4)
	for k in 12:
		var ang := TAU * k / 12.0
		var p := cc + fb_.x * sin(ang) * 1.7 + Vector3.UP * cos(ang) * 1.7
		m.box(Transform3D(fb_, p), Vector3(0.28 if k % 3 else 0.12, 0.28 if k % 3 else 0.55, 0.06), WHITE)
	m.box(Transform3D(fb_.rotated(fb_.z, -0.5), cc + fb_.x * 0.3 + Vector3.UP * 0.55), Vector3(0.12, 1.3, 0.06), WHITE)
	m.box(Transform3D(fb_.rotated(fb_.z, 1.9), cc + fb_.x * 0.42 - Vector3.UP * 0.12), Vector3(0.12, 0.95, 0.06), WHITE)


## Inside Massy TGV's hall (OSM's indoor rooms: Paul, Relay, Monop'daily, the SNCF shop, the waiting rooms, the
## toilets and Sixt upstairs): a stone floor on the repaired ground's plane, shops along both side walls (lit fronts,
## their names), benches, two departure boards facing the doors, a mezzanine along the back wall with its stairs, the
## two lifts down to the TGV platforms (OSM), lamps under the arches. Local frame: x from the front-left corner fa along
## the front (`right`), y into the hall (`back`).
func _tgv_interior(T: Dictionary, fa: Vector2, fb: Vector2, ba: Vector2, right: Vector2, back: Vector2,
		info: Dictionary) -> void:
	var m := _mesher("TGV")
	var gl := _mesher("TGV_Glass")
	var lights := _mesher("TGV_Lights", 400.0)
	var W := fa.distance_to(fb)
	var D := fa.distance_to(ba)
	var f: Array = T["floor"]                       # the floor at fa, fb, bb, ba (a plane)
	var P := func(x: float, y: float) -> Vector2: return fa + right * x + back * y
	var Z := func(x: float, y: float) -> float:
		var u := clampf(x / W, 0.0, 1.0)
		var v := clampf(y / D, 0.0, 1.0)
		return lerpf(lerpf(float(f[0]), float(f[1]), u), lerpf(float(f[3]), float(f[2]), u), v) + 0.06
	var hb := Basis(_gd(right), Vector3.UP, _gd(right).cross(Vector3.UP).normalized())    # the hall's axes
	# the floor: stone slabs, walkable
	var q := [_gp(P.call(0.0, 0.0), Z.call(0.0, 0.0)), _gp(P.call(W, 0.0), Z.call(W, 0.0)),
			_gp(P.call(W, D), Z.call(W, D)), _gp(P.call(0.0, D), Z.call(0.0, D))]
	m.quad(q[0], q[1], q[2], q[3], Vector3.UP, Color("#d6d0c4"))
	_shape_faces("TGV_Floor", PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]), info)
	var k_ := 6.0
	while k_ < D:                                   # joints between the slab rows
		var j := _beam(P.call(0.2, k_), Z.call(0.2, k_) + 0.003, P.call(W - 0.2, k_), Z.call(W - 0.2, k_) + 0.003, 0.06, 0.0, 0.002)
		m.box(j[0], j[1], Color("#bdb6a8"))
		k_ += 6.0
	# the lifts (OSM: down to the platforms and up to the mezzanine): kept clear of the shops
	var lift_xy: Array[Vector2] = []
	for lf: Dictionary in T["lifts"]:
		var c := Vector2.ZERO
		for p: Array in lf["ring"]:
			c += _v2(p)
		c /= 4.0
		lift_xy.append(Vector2((c - fa).dot(right), (c - fa).dot(back)))
	# the mezzanine along the back wall, its glass balustrade and the stairs up to it in the middle
	var mz0 := D - 8.0
	var z_m: float = maxf(float(f[2]), float(f[3])) + 5.2
	var stair_w := 3.2
	var mq := [_gp(P.call(0.4, mz0), z_m), _gp(P.call(W - 0.4, mz0), z_m), _gp(P.call(W - 0.4, D - 0.4), z_m),
			_gp(P.call(0.4, D - 0.4), z_m)]
	m.quad(mq[0], mq[1], mq[2], mq[3], Vector3.UP, Color("#d6d0c4"))
	var dn := Vector3(0.0, -0.5, 0.0)
	m.quad(mq[0] + dn, mq[1] + dn, mq[2] + dn, mq[3] + dn, Vector3.DOWN, Color(SOFFIT, 0.85))
	m.quad(mq[0], mq[1], mq[1] + dn, mq[0] + dn, -_gd(back), FASCIA)
	_shape_faces("TGV_Mezzanine", PackedVector3Array([mq[0], mq[1], mq[2], mq[0], mq[2], mq[3]]), info)
	_balustrade(m, gl, P.call(0.4, mz0), z_m, P.call(W * 0.5 - stair_w * 0.5 - 0.1, mz0), z_m, 1.1, STEEL, info)
	_balustrade(m, gl, P.call(W * 0.5 + stair_w * 0.5 + 0.1, mz0), z_m, P.call(W - 0.4, mz0), z_m, 1.1, STEEL, info)
	var zb: float = Z.call(W * 0.5, mz0 - 10.0)
	var n := roundi((z_m - zb) / 0.17)
	var run := n * 0.30
	_flight(m, gl, {"pts": [_xy(P.call(W * 0.5, mz0 - run)), _xy(P.call(W * 0.5, mz0))],
			"zs": [Z.call(W * 0.5, mz0 - run), z_m], "width": stair_w, "steps": n, "escalator": false}, info)
	for i in range(1, 6):                           # the mezzanine's columns
		var cx := W * i / 6.0
		if absf(cx - W * 0.5) < stair_w:
			continue
		var cz: float = Z.call(cx, mz0 + 0.4)
		var col := Transform3D(Basis.IDENTITY, _gp(P.call(cx, mz0 + 0.4), (cz + z_m) * 0.5))
		m.box(col, Vector3(0.4, z_m - cz, 0.4), WHITE)
		MeshUtils.shape_box(_body, col, Vector3(0.4, z_m - cz, 0.4), info)
	for i in lift_xy.size():
		var c: Vector2 = lift_xy[i]
		var p: Vector2 = P.call(c.x, c.y)
		var z0: float = Z.call(c.x, c.y)
		var lb := Transform3D(hb, _gp(p, (z0 + z_m + 3.0) * 0.5))
		m.box(Transform3D(hb, _gp(p, z_m + 2.9)), Vector3(2.2, 0.2, 2.2), STEEL)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var corner: Vector2 = P.call(c.x + sx * 1.0, c.y + sy * 1.0)
				m.box(Transform3D(Basis.IDENTITY, _gp(corner, (z0 + z_m + 3.0) * 0.5)), Vector3(0.1, z_m + 3.0 - z0, 0.1), STEEL)
		for e: Array in [[-1.0, -1.0, 1.0, -1.0], [1.0, -1.0, 1.0, 1.0], [1.0, 1.0, -1.0, 1.0], [-1.0, 1.0, -1.0, -1.0]]:
			_vquad(gl, P.call(c.x + e[0], c.y + e[1]), P.call(c.x + e[2], c.y + e[3]), z0, z_m + 2.8, z0, z_m + 2.8, GLASS, false)
		MeshUtils.shape_box(_body, lb, Vector3(2.0, z_m + 3.0 - z0, 2.0), _info("lift", "massy:tgv-lift", T["lifts"][i]["osm"]))
	# the shops along both side walls: a box, its lit front behind glass, its name on a coloured band
	var names := [["Paul", Color("#2b2522")], ["Relay", Color("#c8102e")], ["Monop'daily", Color("#d6006e")],
			["Boutique SNCF", Color("#3c3c46")], ["Salle d'attente", Color("#4a5a6a")],
			["Billets", Color("#3c3c46")], ["Toilettes", Color("#4a5a6a")], ["Point info", Color("#1f5fa8")],
			["Presse", Color("#c8102e")], ["Café", Color("#5a3b2a")]]
	var ni := 0
	var depth := 5.0
	for side: float in [0.0, 1.0]:
		var y := 4.0
		while y + 7.5 <= D - 0.5:
			var x0 := 0.3 if side == 0.0 else W - 0.3 - depth
			var cx := x0 + depth * 0.5
			var cy := y + 3.75
			var clear := true
			for c: Vector2 in lift_xy:
				if absf(c.x - cx) < depth * 0.5 + 1.5 and absf(c.y - cy) < 3.75 + 1.5:
					clear = false
			if absf(cx - W * 0.5) < stair_w and cy > mz0 - run - 1.0:
				clear = false
			if clear:
				var nm: Array = names[ni % names.size()]
				ni += 1
				_tgv_shop(m, gl, lights, P.call(cx, cy), Z.call(cx, cy) - 0.1, hb, depth, 7.5, side, right, String(nm[0]),
						nm[1], info)
			y += 8.5
	# benches in the middle, facing the departure boards
	for row in 3:
		var y := 16.0 + row * 4.0
		for bx: float in [W * 0.38, W * 0.62]:
			var p: Vector2 = P.call(bx, y)
			var z0: float = Z.call(bx, y)
			m.box(Transform3D(hb, _gp(p, z0 + 0.45)), Vector3(4.0, 0.08, 0.5), Color("#8a8f96"))
			m.box(Transform3D(hb, _gp(p + back * 0.25, z0 + 0.75)), Vector3(4.0, 0.6, 0.06), Color("#8a8f96"))
			for s: float in [-1.6, 1.6]:
				m.box(Transform3D(hb, _gp(p + right * s, z0 + 0.22)), Vector3(0.08, 0.44, 0.45), STEEL)
			MeshUtils.shape_box(_body, Transform3D(hb, _gp(p, z0 + 0.45)), Vector3(4.0, 0.9, 0.6), info)
	# the departure boards, hanging from the arches, facing the doors
	var boards := "Départs\n14:12  Bordeaux  V3\n14:26  Nantes  V1\n14:41  Lyon  V4\n15:03  Rennes  V2\n" \
			+ "15:18  Marseille  V3"
	var face := _facing(_gd(-back))
	for bx: float in [W * 0.33, W * 0.67]:
		var p: Vector2 = P.call(bx, 10.0)
		var z0: float = Z.call(bx, 10.0) + 4.6
		m.box(Transform3D(face, _gp(p, z0)), Vector3(4.2, 1.9, 0.18), Color("#15181d"))
		for s: float in [-1.6, 1.6]:            # the rods it hangs from
			m.box(Transform3D(Basis.IDENTITY, _gp(p + right * s, z0 + 2.7)), Vector3(0.04, 3.5, 0.04), STEEL)
		var holder := Node3D.new()
		holder.name = "TGV_Board_%d" % roundi(bx)
		holder.transform = Transform3D(face, _gp(p - back * 0.1, z0))
		holder.set_meta("plateau", info)
		_node.add_child(holder)
		var l := _label(holder, boards, Vector3.ZERO, 40, Color("#ffb347"), 3.6)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.visibility_range_end = 120.0
		LabelFit.fit(l, Vector2(3.6, 1.7))
	# lamps under the arches
	for lx: float in [W * 0.25, W * 0.5, W * 0.75]:
		var lb := _beam(P.call(lx, 3.0), float(T["eaves"]) - 1.4, P.call(lx, D - 9.0), float(T["eaves"]) - 1.4, 0.3, 0.06, 0.0)
		lights.box(lb[0], lb[1], GLOW)


## A shop against a side wall of Massy TGV's hall: its body, the lit room seen through its glazed front (towards the
## hall's middle), its name on a coloured band over the front; its collision.
func _tgv_shop(m: RailBuilder.Mesher, gl: RailBuilder.Mesher, lights: RailBuilder.Mesher, c: Vector2, z0: float,
		hb: Basis, depth: float, length: float, side: float, right: Vector2, name: String, band: Color, info: Dictionary) -> void:
	var h := 3.7
	var into := right if side == 0.0 else -right        # from the wall towards the hall's middle
	m.box(Transform3D(hb, _gp(c, z0 + h * 0.5)), Vector3(depth, h, 7.5), CREAM)
	MeshUtils.shape_box(_body, Transform3D(hb, _gp(c, z0 + h * 0.5)), Vector3(depth, h, 7.5), info)
	var fr := c + into * (depth * 0.5 + 0.02)
	var face := _facing(_gd(into))
	lights.box(Transform3D(face, _gp(fr, z0 + 1.45)), Vector3(length - 1.2, 2.3, 0.02), Color("#ffe2b0"))
	gl.box(Transform3D(face, _gp(fr + into * 0.05, z0 + 1.45)), Vector3(length - 0.8, 2.5, 0.02), GLASS)
	m.box(Transform3D(face, _gp(fr + into * 0.06, z0 + 3.15)), Vector3(length - 0.4, 0.7, 0.08), band)
	var holder := Node3D.new()
	holder.name = "TGV_Shop_%s" % name.validate_node_name()
	holder.transform = Transform3D(face, _gp(fr + into * 0.11, z0 + 3.15))
	holder.set_meta("plateau", info)
	_node.add_child(holder)
	var l := _label(holder, name, Vector3.ZERO, 160, Color.WHITE, length - 1.0)
	l.visibility_range_end = 120.0
	LabelFit.fit(l, Vector2(length - 1.0, 0.55))


## The ways down to the TGV platforms under the forecourt's canopy (OSM step ways between levels -1 and 0): the TGV is
## not drawn, so each is a dark opening behind glass balustrades, closed by a gate at its top, with its sign.
func _tgv_accesses(T: Dictionary) -> void:
	var m := _mesher("TGV")
	var gl := _mesher("TGV_Glass")
	for a: Dictionary in T["down"]:
		var top := _v2(a["top"])
		var d := _v2(a["dir"]).normalized()
		var n := Vector2(-d.y, d.x)
		var hw: float = float(a["width"]) * 0.5 + 0.4
		var g: float = a["ground"]
		var info := _info("tgv_access", "massy:tgv-access", a["osm"], "Accès aux quais TGV")
		var length := 5.0
		var q := [_gp(top + n * hw, g + 0.03), _gp(top - n * hw, g + 0.03), _gp(top - n * hw + d * length, g + 0.03),
				_gp(top + n * hw + d * length, g + 0.03)]
		m.quad(q[0], q[1], q[2], q[3], Vector3.UP, BLACK)
		for s: float in [-1.0, 1.0]:
			_balustrade(m, gl, top + n * hw * s, g, top + n * hw * s + d * length, g, 1.1, STEEL, info)
		_balustrade(m, gl, top + n * hw + d * length, g, top - n * hw + d * length, g, 1.1, STEEL, info)
		var gate := _beam(top + n * hw, g, top - n * hw, g, 0.08, 0.0, 1.0)
		m.box(gate[0], gate[1], Color("#6a7079"))
		MeshUtils.shape_box(_body, gate[0], gate[1], info)
		# the sign on a post beside the gate, facing the way in
		var post := top + n * (hw + 0.4) - d * 0.3
		m.box(Transform3D(Basis.IDENTITY, _gp(post, g + 1.3)), Vector3(0.1, 2.6, 0.1), DARK)
		var face := _facing(_gd(-d))
		m.box(Transform3D(face, _gp(post, g + 2.4)), Vector3(1.6, 0.45, 0.05), Color("#2b2f36"))
		var holder := Node3D.new()
		holder.name = "TGV_Access_%s" % String(a["osm"])
		holder.transform = Transform3D(face, _gp(post - d * 0.04, g + 2.4))
		holder.set_meta("plateau", info)
		_node.add_child(holder)
		var l := _label(holder, "Accès aux quais", Vector3.ZERO, 90, Color.WHITE, 1.5)
		l.visibility_range_end = 100.0
		LabelFit.fit(l, Vector2(1.5, 0.38))


func _label(parent: Node3D, text: String, pos: Vector3, size: int, color: Color, width: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = LABEL_PIXEL * 4.0
	l.font_size = size
	l.outline_size = 0
	l.modulate = color
	l.width = width / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.visibility_range_end = 400.0
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- line 18: the surface hall

func _l18_hall() -> void:
	var S: Dictionary = _M["l18"]
	var H: Dictionary = S["hall"]
	var a := _v2(H["a"])
	var b := _v2(H["b"])
	var hw: float = float(H["width"]) * 0.5
	var f: float = H["floor"]
	var zl: float = H["roof"][0]
	var zh: float = H["roof"][1]
	var length := a.distance_to(b)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var eb: float = H["end_block"]
	var m := _mesher("L18")
	var g := _mesher("L18_Glass")
	var info := _info("l18_hall", S["id"], S["osm"], S["name"])
	var roof_at := func(t: float) -> float: return zl + (zh - zl) * clampf(t / length, 0.0, 1.0)
	# the roof: three bands across, the middle one higher, each rising to the north-east; clerestories between them
	var bands := [[-1.0, -1.0 / 3.0, 0.0], [-1.0 / 3.0, 1.0 / 3.0, 0.9], [1.0 / 3.0, 1.0, 0.35]]
	for bd: Array in bands:
		var c0: float = bd[0] * hw
		var c1: float = bd[1] * hw
		var rise: float = bd[2]
		var q := [_gp(a + n * c0, zl + rise * 0.3), _gp(b + n * c0, zh + rise), _gp(b + n * c1, zh + rise),
				_gp(a + n * c1, zl + rise * 0.3)]
		var up: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
		if up.y < 0.0:
			up = -up
		m.quad(q[0], q[1], q[2], q[3], up, Color("#cdd1d5"))
		var dn := Vector3(0, -0.4, 0)
		m.quad(q[0] + dn, q[1] + dn, q[2] + dn, q[3] + dn, -up, Color(SOFFIT, 0.85))
		for e: Array in [[0, 1, n * -1.0], [2, 3, n], [3, 0, -d], [1, 2, d]]:
			var e0: Vector3 = q[e[0]]
			var e1: Vector3 = q[e[1]]
			m.quad(e0, e1, e1 + dn, e0 + dn, _gd(e[2]), WHITE)
	for s: float in [-1.0 / 3.0, 1.0 / 3.0]:
		var lo := 0.0 if s < 0.0 else 0.35
		g.quad(_gp(a + n * s * hw, zl + lo * 0.3), _gp(b + n * s * hw, zh + lo), _gp(b + n * s * hw, zh + 0.9),
				_gp(a + n * s * hw, zl + 0.27), _gd(n), GLASS_GREEN)
	# the long walls: curtain walls behind vertical brise-soleil fins, the white block's last eb m
	var glass_end := length - eb
	for s: float in [-1.0, 1.0]:
		var off := n * s * hw
		var top_s := 0.0 if s < 0.0 else 0.35
		var pa := a + off
		var pg := a + d * glass_end + off
		var pb := b + off
		var ra: float = roof_at.call(0.0)
		var rg: float = roof_at.call(glass_end)
		_vquad(g, pa, pg, f + 0.4, ra + top_s * 0.3 - 0.4, f + 0.4, rg + top_s * glass_end / length - 0.4, GLASS_GREEN, false)
		var plinth := _beam(pa, f, pg, f, 0.3, 0.0, 0.4)
		m.box(plinth[0], plinth[1], WHITE)
		var k := 0.0
		var i := 0
		while k <= glass_end:
			var p := a + d * k + off
			var top: float = roof_at.call(k) - 0.4
			m.box(Transform3D(Basis.IDENTITY, _gp(p, (f + top) * 0.5)), Vector3(0.06, top - f, 0.06), STEEL)
			if i % 2 == 0:                      # a brise-soleil fin on every other mullion
				var fin := Transform3D(Basis(_gd(d), Vector3.UP, _gd(n * s)), _gp(p + n * s * 0.3, (f + 0.4 + top) * 0.5))
				m.box(fin, Vector3(0.05, top - f - 0.4, 0.42), Color("#c3c8cd"))
			k += 1.5
			i += 1
		_vquad(m, pg, pb, f, rg - 0.4, f, zh + top_s - 0.4, WHITE)
		_wall_shape(pa, pb, f, zh + 1.0, 0.3, info)
	# the low (south-west) end: glazed between white frames; its name and the line's sign
	_vquad(g, a - n * hw, a + n * hw, f + 0.4, zl - 0.4, f + 0.4, zl - 0.4, GLASS_GREEN, false)
	for k in 9:
		var p := (a - n * hw).lerp(a + n * hw, k / 8.0)
		m.box(Transform3D(Basis.IDENTITY, _gp(p, (f + zl) * 0.5)), Vector3(0.12, zl - f, 0.12), WHITE)
	_wall_shape(a - n * hw, a + n * hw, f, zl, 0.3, info)
	var holder := Node3D.new()
	holder.name = "L18_Signs"
	var sb := _facing(_gd(-d))
	var sx := _md(sb.x)                             # the signs' left-to-right, on the map
	holder.transform = Transform3D(sb, _gp(a - d * 0.2, 0.0))
	holder.set_meta("plateau", info)
	_node.add_child(holder)
	m.box(Transform3D(sb, _gp(a - d * 0.15 - sx * 1.0, zl - 1.5)), Vector3(hw * 1.2, 1.3, 0.1), SIGN_DARK)
	var l := _label(holder, "Massy-Palaiseau", Vector3(-1.0, zl - 1.5, 0.08), 260, Color.WHITE, hw * 1.0)
	LabelFit.fit(l, Vector2(hw * 1.0, 1.0))
	m.box(Transform3D(sb, _gp(a - d * 0.15 + sx * (hw * 0.62), zl - 1.5)), Vector3(1.1, 1.1, 0.14), L18_GREEN)
	_label(holder, "18", Vector3(hw * 0.62, zl - 1.5, 0.1), 220, Color.WHITE, 1.0)
	# the high (north-east) end: the white block's end wall, open where the stairs from le Lien come through
	var link: Dictionary = {}
	for fl: Dictionary in _M["flights"]:
		if fl["id"] == "flight:l18-link":
			link = fl
	var cut := Vector2(INF, -INF)
	if not link.is_empty():
		for q: Array in link["pts"]:
			var o := (_v2(q) - b).dot(n)
			cut = Vector2(minf(cut.x, o - float(link["width"]) * 0.5 - 0.4), maxf(cut.y, o + float(link["width"]) * 0.5 + 0.4))
	var spans: Array = [[-hw, hw]] if cut.x > cut.y else [[-hw, maxf(cut.x, -hw)], [minf(cut.y, hw), hw]]
	for sp: Array in spans:
		if sp[1] - sp[0] < 0.1:
			continue
		var p0: Vector2 = b + n * float(sp[0])
		var p1: Vector2 = b + n * float(sp[1])
		_vquad(m, p0, p1, f, zh - 0.4, f, zh - 0.4, WHITE)
		_wall_shape(p0, p1, f, zh, 0.3, info)
	if cut.x <= cut.y:
		var lintel := _beam(b + n * maxf(cut.x, -hw), _level + 2.8, b + n * minf(cut.y, hw), _level + 2.8, 0.3, 0.0,
				zh - 0.4 - _level - 2.8)
		m.box(lintel[0], lintel[1], WHITE)
	# corten posts along the tracks (photo)
	for p: Array in H["posts"]:
		var xf := Transform3D(Basis.IDENTITY, _g(p[0], p[1], float(p[2]) + 1.3))
		m.box(xf, Vector3(0.22, 2.6, 0.22), CORTEN)
		MeshUtils.shape_box(_body, xf, Vector3(0.22, 2.6, 0.22), _info("post", "massy:l18-posts"))


# ---------------------------------------------------------------- line 18: the station box

func _l18_box() -> void:
	var S: Dictionary = _M["l18"]
	var c := _v2(S["frame"]["c"])
	var u := _v2(S["frame"]["u"])
	var v := Vector2(-u.y, u.x)
	var L: float = S["box"][0]
	var W: float = S["box"][1]
	var tr: float = S["track"]
	var ed: float = tr + float(S["edge"])
	var P: float = minf(float(S["platforms"]), L)
	var z_rail: float = S["rail"]
	var z_tb := z_rail - 0.2
	var z_plat: float = S["platform"]
	var z_mezz: float = S["mezzanine"]
	var z_ceil: float = S["ceiling"]
	var m0: float = S["mezz"][0]
	var m1: float = S["mezz"][1]
	var s0: float = S["shaft"][0]
	var s1: float = S["shaft"][1]
	var sh: float = S["shaft"][2]
	var f: float = S["hall"]["floor"]
	var at := func(al: float, ac: float) -> Vector2: return c + u * al + v * ac
	var m := _mesher("L18_Box", 260.0)
	var g := _mesher("L18_Box_Glass", 260.0)
	var lights := _mesher("L18_Box_Lights", 260.0)
	var info := _info("l18_box", "massy:l18-box", "", "Massy-Palaiseau, line 18 (underground)")
	_box_faces = PackedVector3Array()
	# an axis-aligned (in the box's frame) horizontal rectangle at z, facing up or down; its collision if asked
	var rect := func(mm: RailBuilder.Mesher, a0: float, a1: float, b0: float, b1: float, z: float, up: bool, col: Color,
			collide: bool) -> void:
		var q := [_gp(at.call(a0, b0), z), _gp(at.call(a1, b0), z), _gp(at.call(a1, b1), z), _gp(at.call(a0, b1), z)]
		mm.quad(q[0], q[1], q[2], q[3], Vector3.UP if up else Vector3.DOWN, col)
		if collide:
			_box_faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	# a vertical rectangle across the box's frame: along a at ac, or across b at al (`along`), facing `nrm` (map)
	var wall := func(mm: RailBuilder.Mesher, p0: Vector2, p1: Vector2, z0: float, z1: float, col: Color, collide: bool) -> void:
		var dd := (p1 - p0).normalized()
		var nrm := _gd(Vector2(-dd.y, dd.x))
		var q := [_gp(p0, z0), _gp(p1, z0), _gp(p1, z1), _gp(p0, z1)]
		mm.quad(q[0], q[1], q[2], q[3], nrm, col)
		mm.quad(q[0], q[1], q[2], q[3], -nrm, col)
		if collide:
			_box_faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	# the trackbed, the rails into the tunnels, the platforms with their edge band and tactile strip
	var tl := 30.0                                  # m of tunnel drawn beyond each end
	rect.call(m, -L - tl, L + tl, -ed, ed, z_tb, true, TRACK_BED, true)
	for s: float in [-1.0, 1.0]:
		for rr: float in [-0.7175, 0.7175]:
			var off: float = s * tr + rr
			var rb := _beam(at.call(-L - tl, off), z_rail - 0.17, at.call(L + tl, off), z_rail - 0.17, 0.07, 0.0, 0.17)
			m.box(rb[0], rb[1], RAIL)
		var e0: float = s * ed
		var e1: float = s * W
		rect.call(m, -P, P, minf(e0, e1), maxf(e0, e1), z_plat, true, Color("#d9d6cf"), true)
		var band0: float = s * (ed + 0.05)
		var band1: float = s * (ed + 0.55)
		rect.call(m, -P, P, minf(band0, band1), maxf(band0, band1), z_plat + 0.005, true, Color("#f0efe9"), false)
		var tac0: float = s * (ed + 0.6)
		var tac1: float = s * (ed + 1.0)
		rect.call(m, -P, P, minf(tac0, tac1), maxf(tac0, tac1), z_plat + 0.005, true, Color("#e6e1d2"), false)
		wall.call(m, at.call(-P, e0), at.call(P, e0), z_tb, z_plat, Color("#8d8f91"), true)
		# the half-height platform doors: glass panels on a steel frame, a gap at each car door (every 7.5 m)
		var pd: float = s * (ed + 0.3)
		var doors := [-18.75, -11.25, -3.75, 3.75, 11.25, 18.75]
		var runs := []
		var start := -P
		for dz: float in doors:
			runs.append([start, dz - 0.9])
			start = dz + 0.9
		runs.append([start, P])
		for rn: Array in runs:
			var p0: Vector2 = at.call(rn[0], pd)
			var p1: Vector2 = at.call(rn[1], pd)
			_vquad(g, p0, p1, z_plat + 0.1, z_plat + 1.6, z_plat + 0.1, z_plat + 1.6, GLASS, false)
			var top := _beam(p0, z_plat + 1.6, p1, z_plat + 1.6, 0.12, 0.05, 0.05)
			m.box(top[0], top[1], STEEL)
			for p: Vector2 in [p0, p1]:
				m.box(Transform3D(Basis.IDENTITY, _gp(p, z_plat + 0.8)), Vector3(0.12, 1.6, 0.12), L18_GREEN)
			_wall_shape(p0, p1, z_plat, z_plat + 1.6, 0.1, info)
		# the side wall behind the platform: white panels, the line's green band, the station's name
		wall.call(m, at.call(-L, e1), at.call(L, e1), z_plat, z_ceil, Color("#ecebe7"), true)
		wall.call(m, at.call(-L, e1 - s * 0.02), at.call(L, e1 - s * 0.02), z_plat + 2.6, z_plat + 2.9, L18_GREEN, false)
		var holder := Node3D.new()
		holder.name = "L18_Box_Signs_%d" % int(s)
		var hb := _facing(_gd(v * -s))
		var hx := _md(hb.x).dot(u)                  # +1 or -1: the signs' left-to-right along the box's axis
		holder.transform = Transform3D(hb, _gp(at.call(0.0, e1 - s * 0.06), 0.0))
		holder.set_meta("plateau", info)
		_node.add_child(holder)
		for al: float in [-30.0, -15.0, 15.0, 30.0]:
			var sp: Vector2 = at.call(al, e1 - s * 0.05)
			m.box(Transform3D(hb, _gp(sp, z_plat + 3.6)), Vector3(4.2, 0.8, 0.06), SIGN_DARK)
			var l := _label(holder, "Massy-Palaiseau", Vector3(al * hx, z_plat + 3.6, 0.03), 120, Color.WHITE, 3.9)
			l.visibility_range_end = 120.0
			LabelFit.fit(l, Vector2(3.9, 0.6))
		# a light strip over the platform
		var lb := _beam(at.call(-P + 2.0, s * (ed + 2.5)), z_ceil - 0.05, at.call(P - 2.0, s * (ed + 2.5)), z_ceil - 0.05,
				0.3, 0.05, 0.0)
		lights.box(lb[0], lb[1], GLOW)
	# the end walls and the tunnel mouths: a box opening over the tracks, the tunnel's walls and roof, dark beyond
	for e: float in [-1.0, 1.0]:
		var ae := e * L
		var open := ed - 0.1
		var top_open := z_rail + 4.7
		for sp: Array in [[-W, -open], [open, W]]:
			wall.call(m, at.call(ae, sp[0]), at.call(ae, sp[1]), z_tb, z_ceil, Color("#e4e3df"), true)
		wall.call(m, at.call(ae, -open), at.call(ae, open), top_open, z_ceil, Color("#e4e3df"), true)
		var frame := _beam(at.call(ae, -open), top_open, at.call(ae, open), top_open, 0.5, 0.4, 0.0)
		m.box(frame[0], frame[1], L18_GREEN)
		var far := e * (L + tl)
		for s: float in [-1.0, 1.0]:
			wall.call(m, at.call(ae, s * open), at.call(far, s * open), z_tb, top_open, TUNNEL, true)
		rect.call(m, ae, far, -open, open, top_open, false, TUNNEL, false)
		wall.call(m, at.call(far, -open), at.call(far, open), z_tb, top_open, BLACK, true)
	# the ceiling round the shaft (its walls are the patched ground's, from the ceiling up)
	for r: Array in [[-L, s0, -W, W], [s1, L, -W, W], [s0, s1, -W, -sh], [s0, s1, sh, W]]:
		rect.call(m, r[0], r[1], r[2], r[3], z_ceil, false, Color("#f0f0ec"), false)
	# the mezzanine: its floor round the shaft (the shaft's floor is the ground's), the slab's soffit and edges
	for r: Array in [[m0, s0, -W, W], [s1, m1, -W, W], [s0, s1, -W, -sh], [s0, s1, sh, W]]:
		rect.call(m, r[0], r[1], r[2], r[3], z_mezz, true, FLOOR, true)
	rect.call(m, m0, m1, -W, W, z_mezz - 0.6, false, Color(SOFFIT, 0.85), false)
	for al: float in [m0, m1]:
		wall.call(m, at.call(al, -W), at.call(al, W), z_mezz - 0.6, z_mezz, FASCIA, false)
	for s: float in [-1.0, 1.0]:
		var lb := _beam(at.call(m0 + 1.0, s * 5.0), z_mezz - 0.65, at.call(m1 - 1.0, s * 5.0), z_mezz - 0.65, 0.3, 0.05, 0.0)
		lights.box(lb[0], lb[1], GLOW)
	# glass balustrades along the mezzanine's two edges, open at the stairs down to the platforms
	var stair_c := 7.0
	var stair_w := 3.0
	for al: float in [m0, m1]:
		var runs := [[-W, W]] if al == m0 else [[-W, -stair_c - stair_w * 0.5 - 0.2], [-stair_c + stair_w * 0.5 + 0.2,
				stair_c - stair_w * 0.5 - 0.2], [stair_c + stair_w * 0.5 + 0.2, W]]
		for rn: Array in runs:
			_balustrade(m, g, at.call(al, rn[0]), z_mezz, at.call(al, rn[1]), z_mezz, 1.1, STEEL, info)
	# the stairs down to each platform
	var nst := roundi((z_mezz - z_plat) / 0.17)
	var run := nst * 0.30
	for s: float in [-1.0, 1.0]:
		_flight(m, g, {"pts": [[at.call(m1 + run, s * stair_c).x, at.call(m1 + run, s * stair_c).y],
				[at.call(m1, s * stair_c).x, at.call(m1, s * stair_c).y]], "zs": [z_plat, z_mezz], "width": stair_w,
				"steps": nst, "escalator": false}, info)
	# the shaft: up from the mezzanine (flight A, along +a on one side), a landing, up to the hall (flight B, back)
	var nb := roundi((f - z_mezz) / 0.17)
	var half := nb / 2
	var z_mid := z_mezz + half * 0.17
	var run_b := (nb - half) * 0.30
	var run_a := half * 0.30
	var land0 := s0 + run_b
	var ca := -sh + 1.9
	var cb := sh - 1.9
	_flight(m, g, {"pts": [_xy(at.call(land0 - run_a, ca)), _xy(at.call(land0, ca))], "zs": [z_mezz, z_mid],
			"width": 3.0, "steps": half, "escalator": false}, info)
	_flight(m, g, {"pts": [_xy(at.call(land0, cb)), _xy(at.call(s0, cb))], "zs": [z_mid, f], "width": 3.0,
			"steps": nb - half, "escalator": false}, info)
	var land1 := minf(s1 - 0.3, land0 + 4.5)
	var lp := _beam(at.call(land0, 0.0), z_mid, at.call(land1, 0.0), z_mid, sh * 2.0 - 0.4, 0.4, 0.0)
	m.box(lp[0], lp[1], STONE)
	MeshUtils.shape_box(_body, lp[0], lp[1], info)
	_balustrade(m, g, at.call(land0, ca + 1.6), z_mid, at.call(land0, cb - 1.6), z_mid, 1.1, STEEL, info)
	# the shaft's rim in the hall: glass balustrades, open where flight B comes up
	var rim := [[at.call(s0, -sh), at.call(s0, cb - 1.7)], [at.call(s0, cb + 1.7), at.call(s0, sh)],
			[at.call(s0, sh), at.call(s1, sh)], [at.call(s1, sh), at.call(s1, -sh)], [at.call(s1, -sh), at.call(s0, -sh)]]
	for e: Array in rim:
		_balustrade(_mesher("L18"), _mesher("L18_Glass"), e[0], f, e[1], f, 1.1, STEEL, info)
	_shape_faces("L18_Box", _box_faces, info)


static func _xy(p: Vector2) -> Array:
	return [p.x, p.y]
