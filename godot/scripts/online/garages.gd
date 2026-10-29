extends Node3D
## PTA Online's garages (world/garages.json, tools/online/garages.py; scripts/modes/online_mode.gd makes this node): the
## only places a player's vehicle appears. Each one is a row of spawn bays painted on the ground and a terminal beside
## the first bay (a kiosk with a glowing screen under a sign on a pole, its name floating above): a player walks up to
## it and presses E to pick one of their vehicles, which the server parks on a free bay that fits it.
## Kinds: "public" (car parks spread over the map: any vehicle but the work ones; a "big" bay takes the truck with its
## trailer and the biplane), "depot" (the bus depot at Massy-Palaiseau: buses only), "fire" (the fire station at
## Polytechnique: fire trucks only), "shop" (Prestige Motors' delivery bays by its door: a vehicle bought there comes
## out on them; otherwise a public garage).
## Positions in the file are map coordinates (x east, y north; Godot = (x, height, -y)) and yaws in degrees (0 north,
## clockwise); heights come from the ground (scripts/ground_map.gd), so the server has them too. The dedicated server
## makes no meshes, only the kiosks' collision.

const Car = preload("res://scripts/car.gd")
const Marks = preload("res://scripts/race_marks.gd")
const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const LabelFit = preload("res://scripts/label_fit.gd")
const DATA := "res://world/garages.json"
const KINDS := {
	"public": {"title": "Garage", "colour": Color("#2f6fd6"), "sign": "P", "paint": Color(0.93, 0.93, 0.9)},
	"depot": {"title": "Bus depot", "colour": Color("#2e9d57"), "sign": "BUS", "paint": Color(1.0, 0.82, 0.2)},
	"fire": {"title": "Fire station", "colour": Color("#d23b2f"), "sign": "18", "paint": Color(0.92, 0.25, 0.2)},
	"shop": {"title": "Deliveries", "colour": Color("#c9a043"), "sign": "€", "paint": Color(1.0, 0.82, 0.42)},
}
const PUBLIC := ["public", "shop"]          # kinds any of a player's vehicles but the work ones come out at
const LINE := 0.12                          # m, painted bay lines
const LIFT := 0.035                         # m over the ground
const BAY_MARGIN := 0.15                    # m a vehicle keeps from its bay's lines
const STAND := 1.5                          # m from the terminal a player is put, facing it

var list: Array = []                        # {"id", "name", "kind", "xy" (terminal, map), "terminal" (Godot), "facing"
											#  (Godot, towards the bays), "bays": [{"xf": Transform3D, "w", "l"}]}
var by_id := {}
static var _sizes := {}                     # model -> [half extents, extents centre] (game.gd new_vehicle, measured once)


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not data is Dictionary:
		push_error("No PTA Online garages: %s missing" % DATA)
		return
	for g: Dictionary in data["garages"]:
		var t: Dictionary = g["terminal"]
		var face := deg_to_rad(float(t["yaw"]))
		var entry := {"id": str(g["id"]), "name": str(g["name"]), "kind": str(g["kind"]), "xy": Vector2(t["x"], t["y"]),
				"terminal": _at(t["x"], t["y"]), "facing": Vector3(sin(face), 0.0, -cos(face)), "bays": []}
		for b: Dictionary in g["bays"]:
			var a := deg_to_rad(float(b["yaw"]))
			entry["bays"].append({"xf": Transform3D(Basis(Vector3.UP, PI - a), _at(b["x"], b["y"])),
					"w": float(b["w"]), "l": float(b["l"])})
		list.append(entry)
		by_id[entry["id"]] = entry


## Puts the garages in the world: the kiosks (with collision everywhere) and, `meshes`, their looks.
func build(meshes: bool) -> void:
	for g: Dictionary in list:
		var node := Node3D.new()
		node.name = "Garage_" + str(g["id"]).replace("-", "_")
		add_child(node)
		_kiosk(node, g, meshes)
		if meshes:
			_paint_bays(node, g)


static func _at(x: float, y: float) -> Vector3:
	return MeshUtils.to_godot(x, y, Marks.ground(x, y))


## The garage `id`, or {}.
func get_garage(id: String) -> Dictionary:
	return by_id.get(id, {})


## The garage whose terminal is within `reach` m of `p` (Godot), nearest first, or {}.
func terminal_near(p: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for g: Dictionary in list:
		var t: Vector3 = g["terminal"]
		var d := Vector2(t.x - p.x, t.z - p.z).length()
		if d <= best_d and absf(t.y - p.y) < 3.0:
			best = g
			best_d = d
	return best


## The garage of one of `kinds` nearest to `p` (Godot), or {}.
func nearest(p: Vector3, kinds := PUBLIC) -> Dictionary:
	var best := {}
	var best_d := INF
	for g: Dictionary in list:
		var d := (g["terminal"] as Vector3).distance_squared_to(p)
		if g["kind"] in kinds and d < best_d:
			best = g
			best_d = d
	return best


## Where a player is put at garage `g`: [position, yaw] in front of its terminal, facing it and the bays behind it.
func stand_spot(g: Dictionary) -> Array:
	var f: Vector3 = g["facing"]
	var p: Vector3 = g["terminal"] - f * STAND
	p.y = Marks.ground(p.x, -p.z) + 0.1
	return [p, atan2(-f.x, -f.z)]


## [half extents, extents centre] of `model` (measured on a vehicle made once, never put in the tree).
static func size_of(model: String) -> Array:
	if not _sizes.has(model):
		var car: Car = load("res://scripts/game.gd").new_vehicle(model)
		_sizes[model] = [car.half_extents, car.extents_center]
		car.free()
	return _sizes[model]


## Whether `model` fits a bay of `bay` (its lines kept clear by BAY_MARGIN).
static func fits(model: String, bay: Dictionary) -> bool:
	var half: Vector3 = size_of(model)[0]
	return half.x * 2.0 + BAY_MARGIN * 2.0 <= bay["w"] and half.z * 2.0 + BAY_MARGIN * 2.0 <= bay["l"]


## Whether any bay of garage `g` fits `model`.
static func any_fits(g: Dictionary, model: String) -> bool:
	for bay: Dictionary in g["bays"]:
		if fits(model, bay):
			return true
	return false


## Server: the transform to park `model` at in garage `g` (game.gd park_vehicle: +Z forward, on the ground), on the
## smallest free bay that fits it; null when every such bay is taken. A bay is taken by a vehicle overlapping it
## (`cars`, even one parked this frame and not in the physics space yet), a player standing in it (`people`, Godot
## positions) or anything else solid in it (fallen props...).
func free_bay(g: Dictionary, model: String, cars: Array, people: Array) -> Variant:
	var bays: Array = g["bays"].duplicate()
	bays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["w"] * a["l"] < b["w"] * b["l"])
	for bay: Dictionary in bays:
		if fits(model, bay) and bay_free(bay, cars, people):
			return bay["xf"]
	return null


func bay_free(bay: Dictionary, cars: Array, people: Array) -> bool:
	var xf: Transform3D = bay["xf"]
	var inv := xf.affine_inverse()
	var hw: float = bay["w"] * 0.5
	var hl: float = bay["l"] * 0.5
	for car: Car in cars:
		if not is_instance_valid(car) or car.stowed:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := inv * car.to_global(car.extents_center + Vector3(sx * car.half_extents.x, 0.0,
						sz * car.half_extents.z))
				lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
				hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
		var dy := absf((inv * car.global_position).y)
		if lo.x < hw and hi.x > -hw and lo.y < hl and hi.y > -hl and dy < 6.0:
			return false
	for p: Vector3 in people:
		var l := inv * p
		if absf(l.x) < hw + 0.5 and absf(l.z) < hl + 0.5 and absf(l.y) < 3.0:
			return false
	var probe := BoxShape3D.new()
	probe.size = Vector3(bay["w"] - 0.3, 2.0, bay["l"] - 0.3)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = xf.translated_local(Vector3(0.0, 1.3, 0.0))
	q.collision_mask = Layers.VEHICLES | Layers.DEBRIS | Layers.PROPS | Layers.BUILDINGS | Layers.VEGETATION
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ---------------------------------------------------------------- looks

## The terminal: a kiosk with a glowing screen facing the player's spot, a sign on a pole with the kind's mark, the
## garage's name floating above; collision on the PROPS layer.
func _kiosk(node: Node3D, g: Dictionary, meshes: bool) -> void:
	var look: Dictionary = KINDS.get(g["kind"], KINDS["public"])
	var f: Vector3 = g["facing"]
	var k := Node3D.new()
	k.name = "Terminal"
	k.transform = Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), g["terminal"])   # +Z towards the bays
	node.add_child(k)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.PROPS
	body.collision_mask = 0
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = Vector3(0.6, 1.4, 0.36)
	box.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(box)
	var pole := CollisionShape3D.new()
	pole.shape = CylinderShape3D.new()
	(pole.shape as CylinderShape3D).radius = 0.07
	(pole.shape as CylinderShape3D).height = 3.0
	pole.position = Vector3(0.55, 1.5, 0.0)
	body.add_child(pole)
	k.add_child(body)
	if not meshes:
		return
	var dark := _material(Color(0.15, 0.16, 0.19), 0.6, 0.35)
	var colour := _material(look["colour"], 0.1, 0.5)
	_box(k, Vector3(0.55, 1.25, 0.32), Vector3(0.0, 0.625, 0.0), dark)
	_box(k, Vector3(0.6, 0.12, 0.36), Vector3(0.0, 1.31, 0.0), colour)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.3)
	screen.mesh = quad
	var glow := StandardMaterial3D.new()
	glow.albedo_color = (look["colour"] as Color).lightened(0.35)
	glow.emission_enabled = true
	glow.emission = (look["colour"] as Color).lightened(0.2)
	glow.emission_energy_multiplier = 1.6
	screen.material_override = glow
	# on the face away from the bays (where the player stands), tilted back
	screen.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Vector3(0.0, 1.0, -0.175))
	k.add_child(screen)
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 3.0
	stick.mesh = cyl
	stick.material_override = dark
	stick.position = Vector3(0.55, 1.5, 0.0)
	k.add_child(stick)
	_box(k, Vector3(1.05, 1.05, 0.08), Vector3(0.55, 3.45, 0.0), colour)
	for side: float in [-1.0, 1.0]:
		var mark := Label3D.new()
		mark.text = look["sign"]
		mark.font_size = 96
		mark.pixel_size = 0.008
		mark.outline_size = 0
		mark.modulate = Color.WHITE
		mark.shaded = false
		mark.double_sided = false
		LabelFit.fit(mark, Vector2(0.9, 0.9))   # on the 1.05 m panel
		mark.transform = Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI), Vector3(0.55, 3.45, side * 0.045))
		k.add_child(mark)
	var title := Label3D.new()
	title.text = "%s\n%s" % [look["title"], g["name"]] if g["kind"] in PUBLIC else str(g["name"])
	title.font_size = 44
	title.pixel_size = 0.01
	title.outline_size = 12
	title.outline_modulate = Color(0, 0, 0, 0.85)
	title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	title.position = Vector3(0.55, 4.45, 0.0)
	title.visibility_range_end = 140.0
	k.add_child(title)


## The bays' lines on the ground in the kind's paint, draped over it, with a mark at each bay's front end.
func _paint_bays(node: Node3D, g: Dictionary) -> void:
	var look: Dictionary = KINDS.get(g["kind"], KINDS["public"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for bay: Dictionary in g["bays"]:
		n += 1
		var xf: Transform3D = bay["xf"]
		var hw: float = bay["w"] * 0.5
		var hl: float = bay["l"] * 0.5
		var corners := [Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(hw, 0, hl), Vector3(-hw, 0, hl)]
		for e in 4:
			_line(st, xf * corners[e], xf * corners[(e + 1) % 4])
		var text: String = "%s %d" % [look["sign"], n] if g["kind"] in PUBLIC else str(look["sign"]) if g["kind"] == "depot" \
				else "POMPIERS"
		for end: float in [-1.0, 1.0]:      # readable from either end of the bay
			var mark := Label3D.new()
			mark.text = text
			mark.font_size = 72
			mark.pixel_size = 0.012
			mark.outline_size = 0
			mark.modulate = Color(look["paint"], 0.9)
			mark.shaded = false
			mark.double_sided = false
			LabelFit.fit(mark, Vector2(bay["w"] - 0.8, 2.0))      # across the bay
			var p: Vector3 = xf * Vector3(0.0, 0.0, end * (hl - 1.1))
			p.y = Marks.ground(p.x, -p.z) + LIFT + 0.01
			var turn: float = xf.basis.get_euler().y + (PI if end < 0.0 else 0.0)   # read from beyond that end
			mark.transform = Transform3D(Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, -PI * 0.5), p)
			node.add_child(mark)
	var mesh := st.commit()
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = look["paint"]
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lines := MeshInstance3D.new()
	lines.name = "Bays"
	lines.mesh = mesh
	lines.material_override = paint
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(lines)


## A painted line from `a` to `b` (Godot, heights ignored), draped on the ground every ~0.75 m.
func _line(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var steps := maxi(1, ceili(d.length() / 0.75))
	var side := Vector3(-d.z, 0.0, d.x).normalized() * LINE * 0.5
	var prev := []
	for i in steps + 1:
		var p := a + d * (float(i) / steps)
		p.y = Marks.ground(p.x, -p.z) + LIFT
		var pair := [p - side, p + side]
		if not prev.is_empty():
			st.add_vertex(prev[0])
			st.add_vertex(pair[0])
			st.add_vertex(pair[1])
			st.add_vertex(prev[0])
			st.add_vertex(pair[1])
			st.add_vertex(prev[1])
		prev = pair


static func _material(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
