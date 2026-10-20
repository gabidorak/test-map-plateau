@tool
extends RefCounted
## Building interiors (world/interiors.json, written by tools/dealership/dealership_layout.py): a building listed there
## is hollowed out on its ground floor. building_builder.gd starts its tiers at the interior's `ceiling` (reshape), and
## this builds what is under them, in world coordinates under Interiors/<building id>: a marble floor at `floor` over a
## granite plinth, glass walls `glass_inset` m behind the facade line between gold mullions and rails, open doorways
## (`doors`, gold portals, a ramp down to the ground outside when the floor is higher), a light ceiling with light
## panels, and the showroom: gold columns, podiums for the display cars, turntables, gold car statues on plinths, red
## carpets, crystal chandeliers, furniture (reception, logo wall, bar, sofas, desks, palms, trophies), spot lights over
## the cars, price stands, the dealer's name in gold letters on the facade. One concave collision shape (both faces) on
## the BUILDINGS layer holds the floor, plinth, glass, ramps and the solid furniture.
## The node runs scripts/dealership.gd: it parks the drivable display cars (game.gd), turns the turntables and keeps the
## salesman; the data it needs is exported on it (spots, outline, obstacles).
## Pipeline coordinates: x east, y north, z up; headings are map degrees counter-clockwise from east. Furniture is built
## in a local frame: +Z its front (the heading), +X its left, +Y up.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const Car = preload("res://scripts/car.gd")
const Dealership = preload("res://scripts/dealership.gd")
const SPECS_PATH := "res://world/interiors.json"
const FLOOR_SHADER := "res://shaders/showroom_floor.gdshader"
const PODIUM := 3.0                     # m, display podium radius (tools/dealership/dealership_layout.py PODIUM)
const PODIUM_H := 0.1
const TURNTABLE := 3.4
const TURNTABLE_H := 0.22
const MULLION_STEP := 2.6               # m of facade between mullions
const RAMP_SLOPE := 0.12                # rise per m
const DECOR_RANGE := 220.0              # m from the camera beyond which furniture and labels are not drawn
const LIGHT_FADE := 70.0                # m from the camera where the lights start fading out
const GOLD := Color(1.0, 0.78, 0.36)
const COLORS := {
	"granite": [Color(0.11, 0.11, 0.12), 0.3, 0.0], "gold": [GOLD, 0.22, 1.0], "carpet": [Color(0.5, 0.02, 0.05), 0.95, 0.0],
	"white": [Color(0.95, 0.94, 0.92), 0.18, 0.0], "black": [Color(0.035, 0.035, 0.04), 0.12, 0.0],
	"leather": [Color(0.42, 0.19, 0.08), 0.5, 0.0], "ceiling": [Color(0.94, 0.93, 0.9), 0.85, 0.0],
	"plant": [Color(0.16, 0.42, 0.17), 0.75, 0.0], "wood": [Color(0.36, 0.24, 0.15), 0.8, 0.0],
	"bottle": [Color(0.06, 0.2, 0.1), 0.1, 0.0], "soil": [Color(0.12, 0.09, 0.07), 1.0, 0.0],
}

var _mats := {}
var _mesh_dir := ""


## Mesh buffers per material (non-indexed triangles, world coordinates) and the collision faces.
class Geo:
	var tools := {}                     # material name -> SurfaceTool
	var col := PackedVector3Array()

	func _st(m: String) -> SurfaceTool:
		if not tools.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[m] = st
		return tools[m]

	## Triangle a, b, c facing `face`, with per-vertex normals (Godot: clockwise = front).
	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, face: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO,
			nc := Vector3.ZERO, solid := false) -> void:
		if na == Vector3.ZERO:
			na = face
			nb = face
			nc = face
		if (c - a).cross(b - a).dot(face) < 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		var st := _st(m)
		for v: Array in [[a, na], [b, nb], [c, nc]]:
			st.set_normal(v[1])
			st.set_uv(Vector2(v[0].x, -v[0].z))
			st.add_vertex(v[0])
		if solid:
			col.append_array([a, b, c])

	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: Vector3, solid := false) -> void:
		tri(m, a, b, c, face, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, solid)
		tri(m, a, c, d, face, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, solid)

	## Box of `size` centred on xf's origin (in xf's frame).
	func box(m: String, xf: Transform3D, size: Vector3, solid := false) -> void:
		var h := size * 0.5
		var c := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
		var b := xf.basis
		for axis in 3:
			for s: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				var v := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				v[(axis + 2) % 3] = 1.0
				var p := [n + u + v, n - u + v, n - u - v, n + u - v]
				quad(m, c.call(p[0].x, p[0].y, p[0].z), c.call(p[1].x, p[1].y, p[1].z), c.call(p[2].x, p[2].y, p[2].z),
						c.call(p[3].x, p[3].y, p[3].z), (b * n).normalized(), solid)

	## Surface of revolution around xf's Y axis: `profile` (radius, height) from the bottom outside up and inwards,
	## `segs` around; smooth around, faceted along the profile.
	func lathe(m: String, xf: Transform3D, profile: Array, segs := 16, solid := false) -> void:
		for i in profile.size() - 1:
			var p: Vector2 = profile[i]
			var q: Vector2 = profile[i + 1]
			var d := q - p
			if d.length() < 1e-5:
				continue
			var n2 := Vector2(d.y, -d.x).normalized()
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var r0 := Vector3(cos(a0), 0.0, sin(a0))
				var r1 := Vector3(cos(a1), 0.0, sin(a1))
				var p0 := xf * (r0 * p.x + Vector3.UP * p.y)
				var p1 := xf * (r1 * p.x + Vector3.UP * p.y)
				var q0 := xf * (r0 * q.x + Vector3.UP * q.y)
				var q1 := xf * (r1 * q.x + Vector3.UP * q.y)
				var n0 := (xf.basis * (r0 * n2.x + Vector3.UP * n2.y)).normalized()
				var n1 := (xf.basis * (r1 * n2.x + Vector3.UP * n2.y)).normalized()
				var face := (n0 + n1).normalized()
				if p.x > 1e-5:
					tri(m, p0, p1, q1, face, n0, n1, n1, solid)
				if q.x > 1e-5:
					tri(m, p0, q1, q0, face, n0, n1, n0, solid)

	## Collision only: an upright `segs`-gon prism of radius r from xf's origin up h.
	func prism(xf: Transform3D, r: float, h: float, segs := 8) -> void:
		for k in segs:
			var a := Vector3(cos(TAU * k / segs), 0.0, sin(TAU * k / segs)) * r
			var b := Vector3(cos(TAU * (k + 1) / segs), 0.0, sin(TAU * (k + 1) / segs)) * r
			col.append_array([xf * a, xf * b, xf * (b + Vector3.UP * h), xf * a, xf * (b + Vector3.UP * h), xf * (a + Vector3.UP * h)])
			col.append_array([xf * (Vector3.UP * h), xf * (a + Vector3.UP * h), xf * (b + Vector3.UP * h)])

	## Collision only: a box like box().
	func solid_box(xf: Transform3D, size: Vector3) -> void:
		var keep := tools.duplicate()
		box("_col", xf, size, true)
		tools = keep

	func commit(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var names := tools.keys()
		names.sort()
		for m: String in names:
			if m == "_col":
				continue
			mesh = (tools[m] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
		return mesh


static func load_specs() -> Dictionary:
	if not FileAccess.file_exists(SPECS_PATH):
		return {}
	var specs = JSON.parse_string(FileAccess.get_file_as_string(SPECS_PATH))
	return specs if specs is Dictionary else {}


## A copy of `toy` (a building's world.json toy) for its interior: the tiers that reach below the ceiling start at it,
## floating (a soffit under them), and the style takes the interior's.
static func reshape(toy: Dictionary, spec: Dictionary) -> Dictionary:
	var out := toy.duplicate(true)
	var ceiling: float = spec["ceiling"]
	var st: Dictionary = out["style"]
	st.merge(spec.get("style", {}), true)
	for s: Dictionary in out.get("styles", []):
		s.merge(spec.get("style", {}), true)
	var tiers: Array = []
	for t: Dictionary in out["tiers"]:
		if float(t["top"]) <= ceiling + 0.5:
			continue
		if float(t["z0"]) < ceiling:
			t["z0"] = ceiling
			t["floating"] = true
		tiers.append(t)
	out["tiers"] = tiers
	return out


## Callable(module: Dictionary) -> bool: true for the building kit modules (world.json building_modules) an interior
## building loses: on its facade (within 1.5 m of its footprint) below its ceiling or named in its `drop_modules`.
static func dropped_modules(world: Dictionary, specs: Dictionary) -> Callable:
	var feet := []                      # [footprint (map), ceiling, drop_modules]
	for b: Dictionary in world["buildings"]:
		if specs.has(b["id"]):
			var ring := PackedVector2Array()
			for p: Array in b["rings"][0]:
				ring.append(_v2(p))
			feet.append([ring, float(specs[b["id"]]["ceiling"]), specs[b["id"]].get("drop_modules", [])])
	return func(md: Dictionary) -> bool:
		var p := Vector2(float(md["x"]), float(md["y"]))
		for f: Array in feet:
			if not (float(md["z"]) < f[1] or md["m"] in f[2]):
				continue
			if Geometry2D.is_point_in_polygon(p, f[0]):
				return true
			var ring: PackedVector2Array = f[0]
			for i in ring.size():
				if Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()]).distance_to(p) < 1.5:
					return true
		return false


func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> void:
	var specs := load_specs()
	if specs.is_empty():
		return
	_mesh_dir = mesh_dir
	_make_materials()
	var t: Dictionary = world["terrain"]
	var ground := GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	var node := Node3D.new()
	node.name = "Interiors"
	root.add_child(node)
	for b: Dictionary in world["buildings"]:
		if specs.has(b["id"]):
			_build_one(node, b, specs[b["id"]], ground)


func _make_materials() -> void:
	for m: String in COLORS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[m][0]
		mat.roughness = COLORS[m][1]
		mat.metallic = COLORS[m][2]
		if m == "gold":
			mat.metallic_specular = 0.8
		_mats[m] = MeshUtils.save(mat, _mesh_dir + "interior_%s.tres" % m)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.78, 0.88, 0.9, 0.16)
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = MeshUtils.save(glass, _mesh_dir + "interior_glass.tres")
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.albedo_color = Color(1.0, 0.95, 0.85)
	light.emission_enabled = true
	light.emission = Color(1.0, 0.92, 0.78)
	light.emission_energy_multiplier = 2.5
	_mats["light"] = MeshUtils.save(light, _mesh_dir + "interior_light.tres")
	var marble := ShaderMaterial.new()
	marble.shader = load(FLOOR_SHADER)
	_mats["marble"] = MeshUtils.save(marble, _mesh_dir + "interior_marble.tres")


static func _g(p: Vector2, z: float) -> Vector3:
	return MeshUtils.to_godot(p.x, p.y, z)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Frame at map point `p` (height z) facing map heading `deg`.
static func _frame(p: Vector2, z: float, deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(deg) + PI / 2.0), _g(p, z))


func _build_one(parent: Node3D, b: Dictionary, spec: Dictionary, ground: GroundHeights) -> void:
	var id := String(b["id"]).replace(":", "_")
	var floor_z: float = spec["floor"]
	var ceil_z: float = spec["ceiling"]
	var inset: float = spec["glass_inset"]
	var body: Dictionary = b["toy"]["tiers"][0]
	for tier: Dictionary in b["toy"]["tiers"]:
		if tier["kind"] == "body":
			body = tier
			break
	var ring: Array[Vector2] = []
	var glass: Array[Vector2] = []
	for i in body["rings"][0].size():
		ring.append(_v2(body["rings"][0][i]))
		glass.append(ring[i] + _v2(body["w"][0][i]) * inset)
	var tris: Array = body["tris"]

	var node := Node3D.new()
	node.name = id
	node.set_script(Dealership)
	node.set_meta("plateau", {"type": "interior", "id": b["id"], "name": spec["name"], "kind": spec["kind"]})
	parent.add_child(node)
	var shell := Geo.new()
	var see := Geo.new()                # glass
	var decor := Geo.new()
	var fy := floor_z
	var obstacles := PackedVector3Array()   # (x, z, radius) in Godot, for the salesman

	# floor (to the facade line, under the overhang too), plinth down to the building's foot, ceiling, light panels
	for k in range(0, tris.size(), 3):
		shell.tri("marble", _g(ring[tris[k]], fy), _g(ring[tris[k + 1]], fy), _g(ring[tris[k + 2]], fy), Vector3.UP,
				Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, true)
		shell.tri("ceiling", _g(glass[tris[k]], ceil_z - 0.01), _g(glass[tris[k + 1]], ceil_z - 0.01),
				_g(glass[tris[k + 2]], ceil_z - 0.01), Vector3.DOWN)
	var n := ring.size()
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		var out := Vector3(q.y - p.y, 0.0, q.x - p.x).normalized()
		shell.quad("granite", _g(p, float(b["foot_z"])), _g(q, float(b["foot_z"])), _g(q, fy), _g(p, fy), out, true)
	var outline := PackedVector2Array()
	for p in glass:
		outline.append(Vector2(p.x, p.y))
	var fr: Dictionary = spec["frame"]
	var o := _v2(fr["origin"])
	var ang := deg_to_rad(float(fr["angle"]))
	var eu := Vector2(cos(ang), sin(ang))
	var ev := Vector2(-sin(ang), cos(ang))
	var span := 0.0
	for p in ring:
		span = maxf(span, p.distance_to(o))
	for iu in range(0, int(span / 4.8) + 2):
		for iv in range(-int(span / 4.8) - 2, int(span / 4.8) + 2):
			var c := o + eu * (2.4 + 4.8 * iu) + ev * (2.4 + 4.8 * iv)
			if not _inside(outline, c, 1.3):
				continue
			var a := 0.75
			var pts := [c + (eu + ev) * a, c + (eu - ev) * a, c - (eu + ev) * a, c - (eu - ev) * a]
			shell.quad("light", _g(pts[0], ceil_z - 0.03), _g(pts[1], ceil_z - 0.03), _g(pts[2], ceil_z - 0.03),
					_g(pts[3], ceil_z - 0.03), Vector3.DOWN)

	# doors: a gap in the glass, gold posts and lintel, open sliding leaves, a ramp outside
	var gaps := {}                      # glass edge index -> Array of [from, to] (m along it)
	for d: Dictionary in spec["doors"]:
		var at := _v2(d["at"])
		var w: float = d["width"]
		var e := _nearest_edge(glass, at)
		var p := glass[e]
		var q := glass[(e + 1) % n]
		var along := (q - p).normalized()
		var t := clampf((at - p).dot(along), w * 0.5, p.distance_to(q) - w * 0.5)
		if not gaps.has(e):
			gaps[e] = []
		gaps[e].append([t - w * 0.5, t + w * 0.5])
		var out2 := Vector2(along.y, -along.x)
		var heading := rad_to_deg(atan2(out2.y, out2.x))
		var mid := p + along * t
		for s: float in [-1.0, 1.0]:
			var post := _frame(mid + along * s * (w * 0.5 + 0.12), fy, heading)
			shell.box("gold", post.translated_local(Vector3(0.0, (ceil_z - fy) * 0.5, 0.0)), Vector3(0.24, ceil_z - fy, 0.3), true)
			# the sliding leaf, open: behind the glass beside the opening
			var leaf := _frame(mid + along * s * (w * 0.75 + 0.1) - out2 * 0.18, fy, heading)
			see.box("glass", leaf.translated_local(Vector3(0.0, 1.6, 0.0)), Vector3(w * 0.5, 3.2, 0.04))
			shell.box("gold", leaf.translated_local(Vector3(0.0, 3.22, 0.0)), Vector3(w * 0.5, 0.06, 0.06))
		var lintel := _frame(mid, ceil_z - 0.35, heading)
		shell.box("gold", lintel, Vector3(w + 0.48, 0.7, 0.3))
		_ramp(shell, decor, ring, at, w, fy, ground)
		obstacles.append(Vector3(_g(mid, fy).x, _g(mid, fy).z, -w))     # negative: a doorway, not an obstacle

	# glass walls between gold mullions, rails at the floor and the ceiling
	var h := ceil_z - fy
	var since := MULLION_STEP
	for i in n:
		var p := glass[i]
		var q := glass[(i + 1) % n]
		var length := p.distance_to(q)
		if length < 1e-3:
			continue
		var along := (q - p) / length
		var out2 := Vector2(along.y, -along.x)
		var heading := rad_to_deg(atan2(out2.y, out2.x))
		var cuts: Array = gaps.get(i, [])
		var spans := _spans(length, cuts)
		for sp: Array in spans:
			var a := p + along * float(sp[0])
			var c := p + along * float(sp[1])
			see.quad("glass", _g(a, fy), _g(c, fy), _g(c, ceil_z), _g(a, ceil_z), _g(out2, 0.0).normalized(), true)
			var mid := (a + c) * 0.5
			var len2 := float(sp[1]) - float(sp[0])
			shell.box("gold", _frame(mid, fy + 0.07, heading), Vector3(len2 + 0.02, 0.14, 0.16))
		shell.box("gold", _frame((p + q) * 0.5, ceil_z - 0.14, heading), Vector3(length + 0.02, 0.28, 0.18))
		# a mullion every MULLION_STEP m of facade, and at the sharp corners
		var prev := glass[(i + n - 1) % n]
		var turn := absf((p - prev).angle_to(q - p)) if p.distance_to(prev) > 1e-3 else 0.0
		if turn > deg_to_rad(25.0) and since > 0.6:
			since = MULLION_STEP
		var u := MULLION_STEP - since
		while u < length:
			var m := p + along * u
			if not _in_gaps(u, cuts, 0.3):
				shell.box("gold", _frame(m, fy + h * 0.5, heading), Vector3(0.1, h, 0.16))
			u += MULLION_STEP
		since = length - (u - MULLION_STEP)

	# the dealer's name in gold over each door, on the band above the glass
	for d: Dictionary in spec["doors"]:
		var at := _v2(d["at"])
		var e := _nearest_edge(ring, at)
		var p := ring[e]
		var q := ring[(e + 1) % n]
		var along := (q - p).normalized()
		var mid := p + along * clampf((at - p).dot(along), 0.0, p.distance_to(q))
		var out2 := Vector2(along.y, -along.x)
		var l := _label(spec["sign"], 150, 0.01, Color(1.0, 0.8, 0.38))
		l.transform = _frame(mid + out2 * 0.06, ceil_z + 1.25, rad_to_deg(atan2(out2.y, out2.x)))
		l.outline_size = 10
		l.outline_modulate = Color(0.25, 0.17, 0.03)
		l.visibility_range_end = 0.0
		node.add_child(l)

	# columns
	for c: Array in spec["columns"]:
		var xf := _frame(_v2(c), fy, 0.0)
		decor.lathe("granite", xf, [Vector2(0.48, 0.0), Vector2(0.48, 0.14), Vector2(0.38, 0.2), Vector2(0.0, 0.2)], 20)
		shell.lathe("gold", xf, [Vector2(0.3, 0.2), Vector2(0.3, h - 0.3), Vector2(0.38, h - 0.22), Vector2(0.44, h - 0.1),
				Vector2(0.44, h), Vector2(0.0, h)], 20)
		shell.prism(xf, 0.36, h)
		obstacles.append(Vector3(xf.origin.x, xf.origin.z, 0.5))

	# display cars: podium, spot light, ceiling ring, price stand
	var cars: Array = []
	for c: Dictionary in spec["cars"]:
		var at := _v2(c["at"])
		var xf := _frame(at, fy, float(c["yaw"]))
		_podium(shell, decor, xf)
		cars.append({"model": c["model"], "xf": xf.translated_local(Vector3(0.0, PODIUM_H, 0.0)),
				"label": Car.display_name(c["model"]), "price": c["price"], "pitch": c["pitch"]})
		_spot(node, decor, at, ceil_z, fy)
		var stand := xf.translated_local(Vector3(0.0, 0.0, PODIUM + 0.6))
		decor.lathe("gold", stand, [Vector2(0.18, 0.0), Vector2(0.18, 0.03), Vector2(0.03, 0.04), Vector2(0.03, 0.95), Vector2(0.0, 0.95)], 12)
		var plate := stand.translated_local(Vector3(0.0, 1.05, 0.0)) * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3.ZERO)
		decor.box("black", plate, Vector3(0.9, 0.5, 0.04))
		decor.box("gold", plate.translated_local(Vector3(0.0, 0.0, -0.005)), Vector3(0.96, 0.56, 0.035))
		var l := _label("%s\n%s" % [Car.display_name(c["model"]), c["price"]], 44, 0.004, Color(1.0, 0.86, 0.5))
		l.transform = plate.translated_local(Vector3(0.0, 0.0, 0.025))
		node.add_child(l)
		obstacles.append(Vector3(xf.origin.x, xf.origin.z, PODIUM + 0.3))

	# turntables (the rotating disc is its own node: dealership.gd turns it with the car on it), stanchions around
	var turntables: Array = []
	for k in spec["turntables"].size():
		var tt: Dictionary = spec["turntables"][k]
		var at := _v2(tt["at"])
		var xf := _frame(at, fy, 0.0)
		decor.lathe("granite", xf, [Vector2(TURNTABLE + 0.15, 0.0), Vector2(TURNTABLE + 0.15, 0.08), Vector2(0.0, 0.08)], 40)
		shell.prism(xf, TURNTABLE + 0.15, TURNTABLE_H, 16)
		var disc := Geo.new()
		var local := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.08, 0.0))
		disc.lathe("gold", local, [Vector2(TURNTABLE, 0.0), Vector2(TURNTABLE, TURNTABLE_H - 0.08), Vector2(TURNTABLE - 0.12, TURNTABLE_H - 0.08)], 48)
		disc.lathe("black", local, [Vector2(TURNTABLE - 0.12, TURNTABLE_H - 0.08), Vector2(0.0, TURNTABLE_H - 0.08)], 48)
		for s in 8:                     # gold spokes inlaid in the black top, to see it turn
			var sp := local * Transform3D(Basis(Vector3.UP, TAU * s / 8.0), Vector3(0.0, TURNTABLE_H - 0.075, 0.0))
			disc.box("gold", sp.translated_local(Vector3(0.0, 0.0, TURNTABLE * 0.5)), Vector3(0.06, 0.01, TURNTABLE - 0.3))
		var mi := MeshInstance3D.new()
		mi.name = "Turntable%d" % k
		mi.mesh = MeshUtils.save(disc.commit(_mats), _mesh_dir + "interior_%s_turntable%d.res" % [id, k])
		mi.transform = xf
		node.add_child(mi)
		turntables.append({"model": tt["model"], "node": mi.name, "top": TURNTABLE_H})
		_stanchions(decor, xf, _circle(TURNTABLE + 1.2, 14), true)
		_spot(node, decor, at, ceil_z, fy)
		obstacles.append(Vector3(xf.origin.x, xf.origin.z, TURNTABLE + 1.5))

	# gold car statues on granite plinths, roped off
	var statues: Array = []
	for s: Dictionary in spec["statues"]:
		var xf := _frame(_v2(s["at"]), fy, float(s["yaw"]))
		decor.box("granite", xf.translated_local(Vector3(0.0, 0.45, 0.0)), Vector3(2.6, 0.9, 5.4))
		decor.box("gold", xf.translated_local(Vector3(0.0, 0.92, 0.0)), Vector3(2.7, 0.05, 5.5))
		decor.box("gold", xf.translated_local(Vector3(0.0, 0.05, 0.0)), Vector3(2.7, 0.1, 5.5))
		shell.solid_box(xf.translated_local(Vector3(0.0, 0.47, 0.0)), Vector3(2.7, 0.94, 5.5))
		statues.append({"model": s["model"], "xf": xf.translated_local(Vector3(0.0, 0.945, 0.0))})
		var rect: Array[Vector3] = []
		for p: Vector2 in [Vector2(2.4, 3.9), Vector2(0.0, 3.9), Vector2(-2.4, 3.9), Vector2(-2.4, 1.3), Vector2(-2.4, -1.3),
				Vector2(-2.4, -3.9), Vector2(0.0, -3.9), Vector2(2.4, -3.9), Vector2(2.4, -1.3), Vector2(2.4, 1.3)]:
			rect.append(Vector3(p.x, 0.0, p.y))
		_stanchions(decor, xf, rect, true)
		_spot(node, decor, _v2(s["at"]), ceil_z, fy)
		obstacles.append(Vector3(xf.origin.x, xf.origin.z, 4.0))

	# red carpets with gold edges, each a little thicker than the one before (where two cross, the later one is on top)
	for k in spec["carpets"].size():
		var c: Dictionary = spec["carpets"][k]
		var a := _v2(c["a"])
		var e := _v2(c["b"])
		var w: float = c["width"]
		var along := (e - a).normalized()
		var xf := _frame((a + e) * 0.5, fy, rad_to_deg(atan2(along.y, along.x)))
		var length := a.distance_to(e)
		var t: float = 0.02 + 0.004 * k
		decor.box("carpet", xf.translated_local(Vector3(0.0, t * 0.5, 0.0)), Vector3(w, t, length))
		for s: float in [-1.0, 1.0]:
			decor.box("gold", xf.translated_local(Vector3(s * (w * 0.5 - 0.06), t * 0.5 + 0.001, 0.0)), Vector3(0.08, t, length))

	# chandeliers
	for c: Array in spec["chandeliers"]:
		_chandelier(node, decor, _v2(c), ceil_z)

	# furniture
	for f: Dictionary in spec["furniture"]:
		var xf := _frame(_v2(f["at"]), fy, float(f["yaw"]))
		var r := _furniture(node, shell, decor, xf, f, spec)
		if r > 0.0:
			obstacles.append(Vector3(xf.origin.x, xf.origin.z, r))

	# reflections of the showroom in the floor and the cars (captured once)
	var lo := Vector3(INF, fy, INF)
	var hi := Vector3(-INF, ceil_z, -INF)
	for p in ring:
		var g := _g(p, fy)
		lo = Vector3(minf(lo.x, g.x), fy, minf(lo.z, g.z))
		hi = Vector3(maxf(hi.x, g.x), ceil_z, maxf(hi.z, g.z))
	var probe := ReflectionProbe.new()
	probe.name = "Reflections"
	probe.position = (lo + hi) * 0.5
	probe.size = hi - lo + Vector3(1.0, 0.5, 1.0)
	probe.box_projection = true
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.95, 0.88, 0.78)
	probe.ambient_color_energy = 0.55
	probe.max_distance = 200.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	node.add_child(probe)

	for g: Array in [[shell, "Shell", 0.0, true], [see, "Glass", 0.0, false], [decor, "Decor", DECOR_RANGE, true]]:
		var mi := MeshInstance3D.new()
		mi.name = g[1]
		mi.mesh = MeshUtils.save((g[0] as Geo).commit(_mats), _mesh_dir + "interior_%s_%s.res" % [id, String(g[1]).to_lower()])
		mi.visibility_range_end = g[2]
		if not g[3]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	var faces := shell.col
	faces.append_array(see.col)
	faces.append_array(decor.col)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = Layers.BUILDINGS
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = MeshUtils.save(shape, _mesh_dir + "interior_%s_col.res" % id)
	cs.set_meta("plateau", node.get_meta("plateau"))
	sb.add_child(cs)
	node.add_child(sb)

	node.set("floor_y", fy)
	node.set("ceiling_y", ceil_z)
	node.set("outline", outline)
	node.set("cars", cars)
	node.set("statues", statues)
	node.set("turntables", turntables)
	node.set("obstacles", obstacles)
	var sm: Dictionary = spec["salesman"]
	node.set("salesman_xf", _frame(_v2(sm["at"]), fy, float(sm["yaw"])))
	node.set("dealer", spec["name"])
	print("interior %s (%s): %d display cars, %d furniture, %d collision faces" % [b["id"], spec["name"], cars.size(),
			spec["furniture"].size(), faces.size() / 3])


## True when map point `p` is inside `outline` (map coordinates) and at least `margin` m from its edges.
static func _inside(outline: PackedVector2Array, p: Vector2, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(p, outline):
		return false
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
			return false
	return true


static func _nearest_edge(ring: Array[Vector2], p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 1.0:
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## The parts of [0, length] outside the gaps ([from, to] each).
static func _spans(length: float, gaps: Array) -> Array:
	var out := []
	var t := 0.0
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for g: Array in sorted:
		if float(g[0]) > t:
			out.append([t, float(g[0])])
		t = maxf(t, float(g[1]))
	if t < length:
		out.append([t, length])
	return out


static func _in_gaps(u: float, gaps: Array, margin: float) -> bool:
	for g: Array in gaps:
		if u > float(g[0]) - margin and u < float(g[1]) + margin:
			return true
	return false


static func _circle(r: float, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in count:
		out.append(Vector3(cos(TAU * k / count), 0.0, sin(TAU * k / count)) * r)
	return out


## A ramp from the floor at the facade line down to the ground outside door `at` (`w` wide), when the floor is higher,
## with a red carpet up it.
func _ramp(shell: Geo, decor: Geo, ring: Array[Vector2], at: Vector2, w: float, fy: float, ground: GroundHeights) -> void:
	var e := _nearest_edge(ring, at)
	var p := ring[e]
	var q := ring[(e + 1) % ring.size()]
	var along := (q - p).normalized()
	var out := Vector2(along.y, -along.x)
	var mid := p + along * clampf((at - p).dot(along), 0.0, p.distance_to(q))
	var length := 2.0
	var gz := fy
	for k in 3:
		gz = ground.at(mid.x + out.x * length, mid.y + out.y * length)
		length = clampf((fy - gz) / RAMP_SLOPE, 1.5, 7.0)
	if fy - gz < 0.03:
		return
	var hw := w * 0.5 + 0.6
	var a := _g(mid - along * hw, fy)
	var b := _g(mid + along * hw, fy)
	var c := _g(mid + along * hw + out * length, gz - 0.03)
	var d := _g(mid - along * hw + out * length, gz - 0.03)
	var up := (b - a).cross(d - a).normalized()
	if up.y < 0.0:
		up = -up
	shell.quad("granite", a, b, c, d, up, true)
	for s: float in [-1.0, 1.0]:
		var top := _g(mid + along * s * hw, fy)
		var low := _g(mid + along * s * hw + out * length, gz - 0.03)
		var foot := _g(mid + along * s * hw, gz - 0.4)
		var foot2 := _g(mid + along * s * hw + out * length, gz - 0.4)
		var side := _g(along * s, 0.0).normalized()
		shell.quad("granite", top, low, foot2, foot, side, true)
	var cw := minf(w - 1.0, 3.0) * 0.5
	var lift := up * 0.012
	decor.quad("carpet", _g(mid - along * cw, fy) + lift, _g(mid + along * cw, fy) + lift,
			_g(mid + along * cw + out * length, gz - 0.03) + lift, _g(mid - along * cw + out * length, gz - 0.03) + lift, up)


func _podium(shell: Geo, decor: Geo, xf: Transform3D) -> void:
	shell.lathe("gold", xf, [Vector2(PODIUM + 0.12, 0.0), Vector2(PODIUM, PODIUM_H)], 48, true)
	shell.lathe("white", xf, [Vector2(PODIUM, PODIUM_H), Vector2(PODIUM - 0.3, PODIUM_H)], 48, true)
	shell.lathe("white", xf, [Vector2(PODIUM - 0.4, PODIUM_H), Vector2(0.0, PODIUM_H)], 48, true)
	shell.lathe("gold", xf, [Vector2(PODIUM - 0.3, PODIUM_H), Vector2(PODIUM - 0.4, PODIUM_H)], 48)


## A spot light from the ceiling down on map point `at`, in a gold ceiling ring.
func _spot(node: Node3D, decor: Geo, at: Vector2, ceil_z: float, fy: float) -> void:
	var l := SpotLight3D.new()
	l.position = _g(at, ceil_z - 0.15)
	l.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	l.spot_range = ceil_z - fy + 2.0
	l.spot_angle = 30.0
	l.spot_attenuation = 0.6
	l.light_energy = 4.0
	l.light_color = Color(1.0, 0.95, 0.86)
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = LIGHT_FADE
	l.distance_fade_length = 20.0
	node.add_child(l)
	var xf := _frame(at, ceil_z - 0.12, 0.0)
	decor.lathe("gold", xf, [Vector2(0.4, 0.0), Vector2(0.4, 0.11), Vector2(0.0, 0.11)], 20)
	decor.lathe("light", xf, [Vector2(0.0, -0.005), Vector2(0.3, -0.005)], 20)


## Gold posts at `posts` (xf's frame, on the floor), red velvet ropes sagging between them (`closed`: back to the first).
func _stanchions(decor: Geo, xf: Transform3D, posts: Array[Vector3], closed: bool) -> void:
	for p in posts:
		var t := xf.translated_local(p)
		decor.lathe("gold", t, [Vector2(0.17, 0.0), Vector2(0.17, 0.03), Vector2(0.035, 0.05), Vector2(0.035, 0.92),
				Vector2(0.06, 0.95), Vector2(0.06, 1.0), Vector2(0.0, 1.02)], 12)
	var count := posts.size() if closed else posts.size() - 1
	for k in count:
		var a := xf * (posts[k] + Vector3.UP * 0.9)
		var b := xf * (posts[(k + 1) % posts.size()] + Vector3.UP * 0.9)
		var prev := a
		for s in range(1, 7):
			var f := s / 6.0
			var p := a.lerp(b, f) + Vector3.DOWN * 0.22 * 4.0 * f * (1.0 - f)
			var d := p - prev
			var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
			decor.box("carpet", Transform3D(basis, (p + prev) * 0.5), Vector3(0.05, 0.05, d.length() + 0.02))
			prev = p


func _chandelier(node: Node3D, decor: Geo, at: Vector2, ceil_z: float) -> void:
	var top := _frame(at, ceil_z, 0.0)
	decor.lathe("gold", top.translated_local(Vector3(0.0, -0.08, 0.0)), [Vector2(0.35, 0.0), Vector2(0.35, 0.08), Vector2(0.0, 0.08)], 20)
	decor.lathe("gold", top.translated_local(Vector3(0.0, -1.9, 0.0)), [Vector2(0.03, 0.0), Vector2(0.03, 1.85), Vector2(0.0, 1.85)], 8)
	decor.lathe("gold", top.translated_local(Vector3(0.0, -2.1, 0.0)), [Vector2(0.0, 0.0), Vector2(0.18, 0.12), Vector2(0.12, 0.3), Vector2(0.0, 0.3)], 16)
	for ring: Array in [[1.5, -1.75, 16], [1.0, -1.4, 12], [0.55, -1.08, 8]]:
		var rr: float = ring[0]
		var y: float = ring[1]
		var torus: Array = []
		for k in 13:
			var t := TAU * k / 12.0 - PI / 2.0
			torus.append(Vector2(rr + 0.045 * cos(t), 0.045 * sin(t)))
		decor.lathe("gold", top.translated_local(Vector3(0.0, y, 0.0)), torus, 40)
		for k in int(ring[2]):
			var a := TAU * k / float(ring[2])
			var at3 := top.translated_local(Vector3(cos(a) * rr, y + 0.04, sin(a) * rr))
			decor.lathe("gold", at3, [Vector2(0.0, 0.0), Vector2(0.06, 0.05), Vector2(0.05, 0.07), Vector2(0.0, 0.07)], 8)
			decor.lathe("light", at3.translated_local(Vector3(0.0, 0.07, 0.0)), [Vector2(0.025, 0.0), Vector2(0.025, 0.1),
					Vector2(0.035, 0.14), Vector2(0.0, 0.22)], 8)
			# crystal drops
			decor.lathe("glass", at3.translated_local(Vector3(0.0, -0.32, 0.0)), [Vector2(0.0, 0.0), Vector2(0.04, 0.1), Vector2(0.0, 0.28)], 6)
		for k in 6:                     # spokes from the rod
			var a := TAU * k / 6.0
			var mid := top.translated_local(Vector3(cos(a) * rr * 0.5, y, sin(a) * rr * 0.5))
			decor.box("gold", Transform3D(Basis(Vector3.UP, -a), mid.origin), Vector3(rr, 0.03, 0.03))
	var l := OmniLight3D.new()
	l.position = _g(at, ceil_z - 1.7)
	l.omni_range = 15.0
	l.omni_attenuation = 0.8
	l.light_energy = 2.2
	l.light_color = Color(1.0, 0.86, 0.65)
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = LIGHT_FADE
	l.distance_fade_length = 20.0
	node.add_child(l)


func _label(text: String, size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 4
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.shaded = false
	l.visibility_range_end = DECOR_RANGE * 0.5
	return l


## One piece of furniture at xf (front +Z); returns the radius the salesman keeps from it (0: none).
func _furniture(node: Node3D, shell: Geo, decor: Geo, xf: Transform3D, f: Dictionary, spec: Dictionary) -> float:
	var at := func(x: float, y: float, z: float) -> Transform3D: return xf.translated_local(Vector3(x, y, z))
	match String(f["type"]):
		"reception":
			decor.box("white", at.call(0.0, 0.52, 0.0), Vector3(6.4, 1.04, 1.4))
			decor.box("black", at.call(0.0, 1.07, 0.05), Vector3(6.6, 0.06, 1.6))
			decor.box("gold", at.call(0.0, 0.75, 0.0), Vector3(6.42, 0.08, 1.42))
			decor.box("gold", at.call(0.0, 0.03, 0.0), Vector3(6.42, 0.06, 1.42))
			for x: float in [-1.6, 1.6]:
				decor.box("black", at.call(x, 1.33, -0.3) * Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3.ZERO), Vector3(0.6, 0.38, 0.03))
				decor.box("gold", at.call(x, 1.12, -0.3), Vector3(0.05, 0.06, 0.05))
			decor.lathe("gold", at.call(0.4, 1.1, 0.3), [Vector2(0.09, 0.0), Vector2(0.08, 0.02), Vector2(0.0, 0.1)], 16)
			shell.solid_box(at.call(0.0, 0.55, 0.05), Vector3(6.6, 1.1, 1.6))
			return 3.6
		"logo_wall":
			decor.box("black", at.call(0.0, 2.1, 0.0), Vector3(7.0, 4.2, 0.4))
			for e: Array in [[0.0, 4.22, 7.1, 0.06], [0.0, 0.03, 7.1, 0.06], [-3.53, 2.1, 0.06, 4.2], [3.53, 2.1, 0.06, 4.2]]:
				decor.box("gold", at.call(e[0], e[1], 0.0), Vector3(e[2], e[3], 0.44))
			for side: float in [1.0, -1.0]:
				var face := xf * Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI), Vector3.ZERO)
				var torus: Array = []
				for k in 13:
					var t := TAU * k / 12.0 - PI / 2.0
					torus.append(Vector2(0.62 + 0.06 * cos(t), 0.06 * sin(t)))
				decor.lathe("gold", face.translated_local(Vector3(0.0, 1.5, 0.23)) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), torus, 40)
				var pm := _label("PM", 105, 0.006, GOLD)
				pm.transform = face.translated_local(Vector3(0.0, 1.5, 0.215))
				node.add_child(pm)
				var name := _label(String(spec["sign"]), 110, 0.006, GOLD)
				name.transform = face.translated_local(Vector3(0.0, 2.95, 0.215))
				node.add_child(name)
			shell.solid_box(at.call(0.0, 2.1, 0.0), Vector3(7.1, 4.2, 0.44))
			return 3.8
		"bar":
			var length: float = f.get("length", 10.0)
			decor.box("black", at.call(0.0, 0.52, 0.0), Vector3(length, 1.04, 0.75))
			decor.box("white", at.call(0.0, 1.07, 0.05), Vector3(length + 0.1, 0.06, 0.9))
			decor.box("gold", at.call(0.0, 0.22, 0.5), Vector3(length, 0.05, 0.05))
			decor.box("gold", at.call(0.0, 0.9, 0.38), Vector3(length, 0.04, 0.02))
			decor.box("black", at.call(0.0, 1.1, -1.3), Vector3(length, 2.2, 0.4))
			for shelf_y: float in [1.0, 1.55]:
				decor.box("gold", at.call(0.0, shelf_y, -1.05), Vector3(length, 0.03, 0.12))
				var x := -length * 0.5 + 0.3
				while x < length * 0.5 - 0.2:
					_bottle(decor, at.call(x, shelf_y + 0.015, -1.05))
					x += 0.32
			var s := -length * 0.5 + 0.9
			while s < length * 0.5 - 0.5:
				var stool: Transform3D = at.call(s, 0.0, 0.95)
				decor.lathe("gold", stool, [Vector2(0.25, 0.0), Vector2(0.25, 0.02), Vector2(0.03, 0.04), Vector2(0.03, 0.72), Vector2(0.0, 0.72)], 12)
				decor.lathe("carpet", stool.translated_local(Vector3(0.0, 0.72, 0.0)), [Vector2(0.21, 0.0), Vector2(0.22, 0.06), Vector2(0.18, 0.1), Vector2(0.0, 0.1)], 16)
				s += 1.5
			for k in 3:
				var bucket: Transform3D = at.call(-length * 0.3 + k * length * 0.3, 1.1, 0.1)
				decor.lathe("gold", bucket, [Vector2(0.09, 0.0), Vector2(0.12, 0.22), Vector2(0.11, 0.22), Vector2(0.0, 0.2)], 16)
				_bottle(decor, bucket.translated_local(Vector3(0.0, 0.05, 0.0)) * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3.ZERO))
			shell.solid_box(at.call(0.0, 0.55, 0.05), Vector3(length + 0.1, 1.1, 0.9))
			shell.solid_box(at.call(0.0, 1.1, -1.3), Vector3(length, 2.2, 0.4))
			return 0.0
		"sofa", "armchair":
			var w := 3.0 if f["type"] == "sofa" else 1.1
			decor.box("leather", at.call(0.0, 0.25, 0.05), Vector3(w - 0.4, 0.3, 0.85))
			decor.box("leather", at.call(0.0, 0.62, -0.4), Vector3(w - 0.4, 0.75, 0.25))
			for s: float in [-1.0, 1.0]:
				decor.box("leather", at.call(s * (w * 0.5 - 0.11), 0.36, 0.0), Vector3(0.22, 0.52, 1.0))
				for z: float in [-0.4, 0.4]:
					decor.box("gold", at.call(s * (w * 0.5 - 0.12), 0.05, z), Vector3(0.06, 0.1, 0.06))
			decor.box("leather", at.call(0.0, 0.43, 0.08), Vector3(w - 0.46, 0.08, 0.78))
			shell.solid_box(at.call(0.0, 0.42, 0.0), Vector3(w, 0.84, 1.05))
			return w * 0.5 + 0.4
		"coffee_table":
			decor.box("glass", at.call(0.0, 0.42, 0.0), Vector3(2.2, 0.03, 1.2))
			for e: Array in [[0.0, 0.4, -0.58, 2.2, 0.04], [0.0, 0.4, 0.58, 2.2, 0.04]]:
				decor.box("gold", at.call(e[0], e[1], e[2]), Vector3(e[3], e[4], 0.04))
			for x: float in [-1.08, 1.08]:
				decor.box("gold", at.call(x, 0.4, 0.0), Vector3(0.04, 0.04, 1.2))
				for z: float in [-0.58, 0.58]:
					decor.box("gold", at.call(x, 0.2, z), Vector3(0.04, 0.4, 0.04))
			decor.lathe("gold", at.call(0.3, 0.44, 0.0), [Vector2(0.06, 0.0), Vector2(0.22, 0.08), Vector2(0.2, 0.09), Vector2(0.0, 0.03)], 20)
			_bottle(decor, at.call(-0.5, 0.44, 0.1))
			shell.solid_box(at.call(0.0, 0.22, 0.0), Vector3(2.2, 0.44, 1.2))
			return 1.6
		"planter":
			decor.lathe("gold", xf, [Vector2(0.38, 0.0), Vector2(0.52, 0.72), Vector2(0.58, 0.8), Vector2(0.5, 0.8), Vector2(0.48, 0.74)], 20)
			decor.lathe("soil", at.call(0.0, 0.72, 0.0), [Vector2(0.48, 0.0), Vector2(0.0, 0.02)], 20)
			decor.lathe("wood", at.call(0.0, 0.72, 0.0), [Vector2(0.11, 0.0), Vector2(0.09, 1.2), Vector2(0.08, 1.25), Vector2(0.07, 2.5), Vector2(0.0, 2.55)], 8)
			var top: Transform3D = at.call(0.0, 3.2, 0.0)
			for k in 9:
				var a := TAU * k / 9.0 + 0.3
				var droop := 0.25 + 0.15 * float(k % 3)
				var p := top.origin
				var dir := (xf.basis * Vector3(cos(a), droop, sin(a))).normalized()
				for seg in 3:
					var d := (dir + Vector3.DOWN * 0.35 * seg).normalized() * 0.55
					var basis := Basis.looking_at(d.normalized(), Vector3.UP)
					decor.box("plant", Transform3D(basis, p + d * 0.5), Vector3(0.42 - 0.1 * seg, 0.03, 0.6))
					p += d
			shell.prism(xf, 0.55, 0.8)
			return 1.1
		"desk":
			decor.box("white", at.call(0.0, 0.75, 0.0), Vector3(2.4, 0.05, 1.2))
			decor.box("gold", at.call(0.0, 0.72, 0.0), Vector3(2.42, 0.03, 1.22))
			for x: float in [-1.15, 1.15]:
				for z: float in [-0.55, 0.55]:
					decor.box("gold", at.call(x, 0.36, z), Vector3(0.05, 0.72, 0.05))
			decor.box("black", at.call(0.0, 0.5, -0.5), Vector3(2.2, 0.4, 0.03))
			decor.box("black", at.call(0.3, 0.785, -0.1), Vector3(0.36, 0.02, 0.25))
			decor.box("black", at.call(0.3, 0.9, -0.22) * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3.ZERO), Vector3(0.36, 0.24, 0.015))
			_chair(decor, at.call(0.0, 0.0, -0.95), "black")
			for x: float in [-0.6, 0.6]:
				_chair(decor, at.call(x, 0.0, 1.05) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), "leather")
			shell.solid_box(at.call(0.0, 0.39, 0.0), Vector3(2.4, 0.78, 1.2))
			return 2.0
		"trophy_cabinet":
			decor.box("black", at.call(0.0, 0.15, 0.0), Vector3(3.2, 0.3, 0.8))
			decor.box("glass", at.call(0.0, 1.25, 0.0), Vector3(3.1, 1.9, 0.72))
			for y: float in [0.3, 2.2]:
				for z: float in [-0.38, 0.38]:
					decor.box("gold", at.call(0.0, y, z), Vector3(3.2, 0.04, 0.04))
			for x: float in [-1.58, 1.58]:
				for z: float in [-0.38, 0.38]:
					decor.box("gold", at.call(x, 1.25, z), Vector3(0.04, 1.9, 0.04))
			for y: float in [0.95, 1.6]:
				decor.box("glass", at.call(0.0, y, 0.0), Vector3(3.08, 0.02, 0.7))
			for k in 9:
				var cup: Transform3D = at.call(-1.2 + 1.2 * (k % 3), [0.3, 0.96, 1.61][int(k / 3.0)], 0.0)
				_cup(decor, cup, 0.35 + 0.08 * (k % 2))
			shell.solid_box(at.call(0.0, 1.1, 0.0), Vector3(3.2, 2.2, 0.8))
			return 2.2
		"trophy":
			decor.box("black", at.call(0.0, 0.55, 0.0), Vector3(0.7, 1.1, 0.7))
			decor.box("gold", at.call(0.0, 1.11, 0.0), Vector3(0.74, 0.03, 0.74))
			_cup(decor, at.call(0.0, 1.12, 0.0), 1.0)
			shell.solid_box(at.call(0.0, 0.55, 0.0), Vector3(0.7, 1.1, 0.7))
			return 1.0
	push_warning("unknown furniture %s" % f["type"])
	return 0.0


func _bottle(decor: Geo, xf: Transform3D) -> void:
	decor.lathe("bottle", xf, [Vector2(0.04, 0.0), Vector2(0.042, 0.2), Vector2(0.015, 0.27), Vector2(0.014, 0.3)], 10)
	decor.lathe("gold", xf.translated_local(Vector3(0.0, 0.26, 0.0)), [Vector2(0.018, 0.0), Vector2(0.017, 0.06), Vector2(0.0, 0.065)], 10)


## A gold cup `s` m tall: foot, stem, bowl, two handles.
func _cup(decor: Geo, xf: Transform3D, s: float) -> void:
	decor.lathe("gold", xf, [Vector2(0.18, 0.0), Vector2(0.18, 0.04), Vector2(0.05, 0.1), Vector2(0.04, 0.4), Vector2(0.1, 0.45),
			Vector2(0.24, 0.62), Vector2(0.27, 0.95), Vector2(0.24, 0.96), Vector2(0.0, 0.7)].map(func(p: Vector2) -> Vector2: return p * s), 20)
	for side: float in [-1.0, 1.0]:
		var torus: Array = []
		for k in 13:
			var t := TAU * k / 12.0 - PI / 2.0
			torus.append(Vector2((0.13 + 0.025 * cos(t)) * s, 0.025 * sin(t) * s))
		decor.lathe("gold", xf.translated_local(Vector3(side * 0.27 * s, 0.75 * s, 0.0)) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), torus, 12)


func _chair(decor: Geo, xf: Transform3D, mat: String) -> void:
	var at := func(x: float, y: float, z: float) -> Transform3D: return xf.translated_local(Vector3(x, y, z))
	decor.box(mat, at.call(0.0, 0.47, 0.0), Vector3(0.55, 0.1, 0.52))
	decor.box(mat, at.call(0.0, 0.82, -0.24), Vector3(0.55, 0.6, 0.08))
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.22, 0.22]:
			decor.box("gold", at.call(x, 0.21, z), Vector3(0.035, 0.42, 0.035))
