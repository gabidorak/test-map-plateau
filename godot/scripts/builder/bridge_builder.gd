@tool
extends RefCounted
## Bridge decks (world.json "bridges", pipeline/plateau/bridges.py): the highways OSM maps as bridges, which the ground
## mesh leaves out (the ground runs on under them, down to the road, railway or stream they cross). Per bridge, in the
## toy prop style: the deck slab along its points (top at the deck height, the way's material), parapets on car
## roads and railings on paths, a dashed centre line on two-way roads, and piers where the ground falls away under
## it. Collision: the deck top, its edges and the parapets, on the terrain layer (one StaticBody3D "BridgeCollision",
## each shape tagged for the picker), so vehicles drive and players walk on it.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
const PROP_SHADER := "res://shaders/toy_prop.gdshader"
const ROAD_DECK := 0.9              # m, slab depth under a car road
const PATH_DECK := 0.45             # m, under a footbridge
const PARAPET := Vector2(0.3, 0.9)  # m, width and height above the deck (car roads)
const RAILING := 1.1                # m, footbridge handrail height
const POST_STEP := 2.0              # m between railing posts
const PIER_STEP := 18.0             # m between piers along the deck
const PIER_GAP := 1.2               # m of clear height under the deck that calls for a pier
const PIER_END := 4.0               # m from the ends with no pier (the abutments)
const DASH := Vector2(3.0, 3.0)     # m, centre line dash and gap
const LINE_WIDTH := 0.12
const PAINT_LIFT := 0.015
const SHOW_RANGE := 900.0           # m: no far version (cheap, and seen from afar over valleys)
const CONCRETE := Color("#cfc9bd")
const RAIL_METAL := Color("#5b616b")
const PAINT := Color("#f4f1e8")

var _ground: GroundHeights


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> void:
	var bridges: Array = world.get("bridges", [])
	if bridges.is_empty():
		return
	var t: Dictionary = world["terrain"]
	_ground = GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	var mat := ShaderMaterial.new()
	mat.shader = load(PROP_SHADER)
	mat.set_shader_parameter("mode", 0)
	MeshUtils.save(mat, mesh_dir + "bridge_material.tres")
	var ground_pal: Dictionary = world["palette"]["ground"]
	var node := Node3D.new()
	node.name = "Bridges"
	root.add_child(node)
	var body := StaticBody3D.new()
	body.name = "BridgeCollision"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "bridge", "id": "bridges"})
	root.add_child(body)
	for b: Dictionary in bridges:
		var info := {"type": "bridge", "id": b["id"], "name": b.get("name", ""), "kind": b["hw"],
				"osm": b["osm"], "width": b["width"]}
		var m := RailBuilder.Mesher.new()
		var faces := PackedVector3Array()
		var top := Color.html(ground_pal.get(b["material"], ground_pal["asphalt"]))
		_deck(m, faces, b, top)
		if m.is_empty():
			continue
		var tag: String = String(b["id"]).replace(":", "_")
		var mi := MeshInstance3D.new()
		mi.name = tag
		mi.mesh = MeshUtils.save(m.commit(mat), mesh_dir + "%s.res" % tag)
		mi.visibility_range_end = SHOW_RANGE
		mi.visibility_range_end_margin = 20.0
		mi.set_meta("plateau", info)
		node.add_child(mi)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		MeshUtils.save(shape, mesh_dir + "%s_col.res" % tag)
		var cs := CollisionShape3D.new()
		cs.name = tag
		cs.shape = shape
		cs.set_meta("plateau", info)
		body.add_child(cs)
	print("bridges: %d decks" % node.get_child_count())


static func _g(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, z, -p.y)


## Per point: the map position, deck height, distance along, and the left offset of the edges at a joint (the
## mitre: both segments' edges meet there), scaled so the deck keeps its width.
static func _frames(pts: Array) -> Array:
	var out := []
	var n := pts.size()
	var d := 0.0
	for i in n:
		var p := Vector2(pts[i][0], pts[i][1])
		if i > 0:
			d += p.distance_to(Vector2(pts[i - 1][0], pts[i - 1][1]))
		var din := Vector2.ZERO
		var dout := Vector2.ZERO
		if i > 0:
			din = (p - Vector2(pts[i - 1][0], pts[i - 1][1])).normalized()
		if i < n - 1:
			dout = (Vector2(pts[i + 1][0], pts[i + 1][1]) - p).normalized()
		var dir := (din + dout).normalized() if din != Vector2.ZERO and dout != Vector2.ZERO else (din + dout).normalized()
		var left := Vector2(-dir.y, dir.x)
		var seg := dout if dout != Vector2.ZERO else din
		var k := clampf(left.dot(Vector2(-seg.y, seg.x)), 0.5, 1.0)
		out.append({"p": p, "z": float(pts[i][2]), "d": d, "left": left / k, "dir": dir})
	return out


func _deck(m: RailBuilder.Mesher, faces: PackedVector3Array, b: Dictionary, top: Color) -> void:
	var fr := _frames(b["pts"])
	if fr.size() < 2:
		return
	var road: bool = b["kind"] == "road"
	var w: float = b["width"] * 0.5 + (PARAPET.x if road else 0.15)      # the parapets stand on the deck's edges
	var depth := ROAD_DECK if road else PATH_DECK
	var side_col := CONCRETE
	for i in fr.size() - 1:
		var a: Dictionary = fr[i]
		var c: Dictionary = fr[i + 1]
		var al: Vector3 = _g(a["p"] + a["left"] * w, a["z"])
		var ar: Vector3 = _g(a["p"] - a["left"] * w, a["z"])
		var cl: Vector3 = _g(c["p"] + c["left"] * w, c["z"])
		var cr: Vector3 = _g(c["p"] - c["left"] * w, c["z"])
		var down := Vector3(0.0, -depth, 0.0)
		var up := (cl - al).cross(ar - al).normalized()
		if up.y < 0.0:
			up = -up
		m.quad(al, ar, cr, cl, up, Color(top.r, top.g, top.b, 1.0))
		faces.append_array([al, ar, cr, al, cr, cl])
		var lout := _g(a["left"], 0.0).normalized()
		var lout2 := _g(c["left"], 0.0).normalized()
		m.quad(al, cl, cl + down, al + down, (lout + lout2).normalized(), side_col)
		m.quad(ar, cr, cr + down, ar + down, -(lout + lout2).normalized(), side_col)
		m.quad(al + down, ar + down, cr + down, cl + down, Vector3.DOWN, Color(side_col.r, side_col.g, side_col.b, 0.6))
		faces.append_array([al, cl, cl + down, al, cl + down, al + down, ar, cr, cr + down, ar, cr + down, ar + down])
		if road:
			_parapet(m, faces, a, c, w, 1.0)
			_parapet(m, faces, a, c, w, -1.0)
		else:
			_rail_strip(m, faces, a, c, w - 0.05, 1.0)
			_rail_strip(m, faces, a, c, w - 0.05, -1.0)
	if road and not b.get("oneway", false) and float(b["width"]) >= 5.0:
		_centre_line(m, fr)
	if not road:
		_posts(m, fr, w - 0.05)
	_piers(m, fr, b["width"], depth)


## A parapet along one edge (`side` +1 left, -1 right) of segment a -> c: inner and outer faces, its top.
func _parapet(m: RailBuilder.Mesher, faces: PackedVector3Array, a: Dictionary, c: Dictionary, w: float, side: float) -> void:
	var h := Vector3(0.0, PARAPET.y, 0.0)
	var oa: Vector3 = _g(a["p"] + a["left"] * w * side, a["z"])
	var oc: Vector3 = _g(c["p"] + c["left"] * w * side, c["z"])
	var ia: Vector3 = _g(a["p"] + a["left"] * (w - PARAPET.x) * side, a["z"])
	var ic: Vector3 = _g(c["p"] + c["left"] * (w - PARAPET.x) * side, c["z"])
	var outward := _g(a["left"], 0.0).normalized() * side
	m.quad(oa, oc, oc + h, oa + h, outward, CONCRETE)
	m.quad(ia, ic, ic + h, ia + h, -outward, CONCRETE)
	m.quad(oa + h, oc + h, ic + h, ia + h, Vector3.UP, Color(CONCRETE.r, CONCRETE.g, CONCRETE.b, 1.0))
	faces.append_array([ia, ic, ic + h, ia, ic + h, ia + h, oa + h, oc + h, ic + h, oa + h, ic + h, ia + h])


## A footbridge railing's handrail and mid rail along one edge (thin strips), and its collision wall.
func _rail_strip(m: RailBuilder.Mesher, faces: PackedVector3Array, a: Dictionary, c: Dictionary, w: float, side: float) -> void:
	var pa: Vector3 = _g(a["p"] + a["left"] * w * side, a["z"])
	var pc: Vector3 = _g(c["p"] + c["left"] * w * side, c["z"])
	var outward := _g(a["left"], 0.0).normalized() * side
	for h in [RAILING, RAILING * 0.5]:
		var lo := Vector3(0.0, h - 0.05, 0.0)
		var hi := Vector3(0.0, h, 0.0)
		m.quad(pa + lo, pc + lo, pc + hi, pa + hi, outward, RAIL_METAL)
		m.quad(pa + lo, pc + lo, pc + hi, pa + hi, -outward, RAIL_METAL)
		m.quad(pa + hi, pc + hi, pc + hi - outward * 0.05, pa + hi - outward * 0.05, Vector3.UP, RAIL_METAL)
	var top := Vector3(0.0, RAILING, 0.0)
	faces.append_array([pa, pc, pc + top, pa, pc + top, pa + top])


func _posts(m: RailBuilder.Mesher, fr: Array, w: float) -> void:
	var length: float = fr[-1]["d"]
	var n := maxi(int(length / POST_STEP), 1)
	for k in n + 1:
		var f := _at(fr, length * k / n)
		for side in [1.0, -1.0]:
			var p: Vector2 = f["p"] + f["left"] * w * side
			var xf := Transform3D(Basis(), _g(p, f["z"] + RAILING * 0.5))
			m.box(xf, Vector3(0.06, RAILING, 0.06), RAIL_METAL)


func _centre_line(m: RailBuilder.Mesher, fr: Array) -> void:
	var length: float = fr[-1]["d"]
	var d := DASH.y * 0.5
	while d + DASH.x < length:
		var a := _at(fr, d)
		var c := _at(fr, d + DASH.x)
		var la: Vector2 = a["left"] * LINE_WIDTH * 0.5
		var lc: Vector2 = c["left"] * LINE_WIDTH * 0.5
		m.quad(_g(a["p"] + la, a["z"] + PAINT_LIFT), _g(a["p"] - la, a["z"] + PAINT_LIFT),
				_g(c["p"] - lc, c["z"] + PAINT_LIFT), _g(c["p"] + lc, c["z"] + PAINT_LIFT), Vector3.UP, PAINT)
		d += DASH.x + DASH.y


func _piers(m: RailBuilder.Mesher, fr: Array, width: float, depth: float) -> void:
	var length: float = fr[-1]["d"]
	if length < 2.0 * PIER_END + 2.0:
		return
	var n := maxi(int(ceil((length - 2.0 * PIER_END) / PIER_STEP)), 1)
	for k in n + 1:
		var f := _at(fr, PIER_END + (length - 2.0 * PIER_END) * k / n)
		var bottom: float = f["z"] - depth
		var g := _ground.at(f["p"].x, f["p"].y)
		if bottom - g < PIER_GAP:
			continue
		var h := bottom - g + 0.3
		var dir := _g(f["dir"], 0.0)
		var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP, dir) if dir.length() > 0.5 else Basis()
		var xf := Transform3D(basis, _g(f["p"], g - 0.3 + h * 0.5))
		m.box(xf, Vector3(maxf(width * 0.6, 0.8), h, 0.9), CONCRETE)


## The frame at distance `d` along the deck (interpolated).
static func _at(fr: Array, d: float) -> Dictionary:
	for i in fr.size() - 1:
		var a: Dictionary = fr[i]
		var c: Dictionary = fr[i + 1]
		if d <= float(c["d"]) or i == fr.size() - 2:
			var t := clampf((d - float(a["d"])) / maxf(float(c["d"]) - float(a["d"]), 1e-6), 0.0, 1.0)
			return {"p": (a["p"] as Vector2).lerp(c["p"], t), "z": lerpf(a["z"], c["z"], t),
					"left": (a["left"] as Vector2).lerp(c["left"], t), "dir": (a["dir"] as Vector2).lerp(c["dir"], t)}
	return fr[0]
