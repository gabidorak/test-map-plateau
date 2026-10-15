extends RefCounted
## The races' marks in the world (scripts/races.gd builds them): the animated circles (start circles everyone sees, and
## the checkpoint gates and finish only the racer sees), draped on the ground with a wall of light rising from them
## (shaders/race_ring.gdshader), and the leaderboards: a panel on two posts, one table per column of rows.
## Positions are pipeline x/y (x east, y north); Godot = (x, height, -y).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const RING_SHADER := preload("res://shaders/race_ring.gdshader")
const LIFT := 0.08                          # m the ring floats over the ground (kerbs and raised pavements: the wall)
const RING_WIDTH := 0.5                     # m, the ground ring's
const BOARD_SIZE := Vector2(4.2, 2.7)       # m, the leaderboard panel (width, height)
const BOARD_BOTTOM := 0.9                   # m above the ground
const BOARD_PIXEL := 0.0042                 # m per font pixel of its text


static func ground(x: float, y: float) -> float:
	var map: GroundMap = GroundMap.get_map()
	return map.height(x, y) if map else 0.0


## A circle of `radius` m round pipeline (x, y): a ring on the ground and a wall `height` m tall, in `color`;
## `pattern` as the shader's (0 chasing dashes, 1 plain, 2 chequered); `disc`: a faint disc fills it too.
static func ring(x: float, y: float, radius: float, height: float, color: Color, pattern := 0, disc := false) \
		-> MeshInstance3D:
	var h0 := ground(x, y)
	var n := clampi(roundi(radius * 6.0), 40, 160)
	var floor_st := SurfaceTool.new()
	var wall_st := SurfaceTool.new()
	var disc_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	disc_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := Vector3(0.0, LIFT * 0.5, 0.0)
	var rim: Array[Vector3] = []            # ground point under each step round, outer edge
	var inner: Array[Vector3] = []
	for k in n + 1:
		var a := TAU * k / n
		var d := Vector2(cos(a), sin(a))
		var o := d * radius
		var i := d * maxf(radius - RING_WIDTH, 0.1)
		rim.append(Vector3(o.x, ground(x + o.x, y + o.y) - h0 + LIFT, -o.y))
		inner.append(Vector3(i.x, ground(x + i.x, y + i.y) - h0 + LIFT, -i.y))
	for k in n:
		var u0 := float(k) / n
		var u1 := float(k + 1) / n
		_quad(floor_st, inner[k], rim[k], rim[k + 1], inner[k + 1], u0, u1, 0.0, 1.0)
		var b0 := rim[k] - Vector3(0, 0.3, 0)   # sunk a little: no gap over a slope between two steps
		var b1 := rim[k + 1] - Vector3(0, 0.3, 0)
		_quad(wall_st, b0, b0 + Vector3(0, height + 0.3, 0), b1 + Vector3(0, height + 0.3, 0), b1, u0, u1, 0.0, 1.0)
		if disc:                            # a fan: flat from the middle (the circles stand on flat ground)
			var lo := Vector3(inner[k].x, inner[k].y - LIFT * 0.5, inner[k].z)
			var hi := Vector3(inner[k + 1].x, inner[k + 1].y - LIFT * 0.5, inner[k + 1].z)
			for p: Array in [[mid, u0, 0.0], [lo, u0, 1.0], [hi, u1, 1.0]]:
				disc_st.set_uv(Vector2(p[1], p[2]))
				disc_st.add_vertex(p[0])
	var mesh := floor_st.commit()
	wall_st.commit(mesh)
	if disc:
		disc_st.commit(mesh)
	var segments := maxf(roundf(TAU * radius / 2.5), 8.0)
	for s in mesh.get_surface_count():
		var mat := ShaderMaterial.new()
		mat.shader = RING_SHADER
		mat.set_shader_parameter("color", color)
		mat.set_shader_parameter("part", s)
		mat.set_shader_parameter("pattern", pattern)
		mat.set_shader_parameter("segments", segments)
		mesh.surface_set_material(s, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = MeshUtils.to_godot(x, y, h0)
	return mi


## (corners a, b along v = 0..1 at u0; c, d at u1: a and d at v0, b and c at v1)
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, v0: float,
		v1: float) -> void:
	for p: Array in [[a, u0, v0], [b, u0, v1], [c, u1, v1], [a, u0, v0], [c, u1, v1], [d, u1, v0]]:
		st.set_uv(Vector2(p[1], p[2]))
		st.add_vertex(p[0])


## Dims or brightens a ring (the checkpoint after the next one is dimmer).
static func set_strength(r: MeshInstance3D, k: float) -> void:
	for s in r.mesh.get_surface_count():
		(r.mesh.surface_get_material(s) as ShaderMaterial).set_shader_parameter("strength", k)


## Text floating `up` m over pipeline (x, y), always facing the camera.
static func sign_text(x: float, y: float, up: float, text: String, size := 64, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.no_depth_test = false
	l.position = MeshUtils.to_godot(x, y, ground(x, y) + up)
	return l


## A leaderboard at pipeline (x, y) facing `facing` degrees (counter-clockwise from east): `columns` tables side by
## side under `title` (and `subtitle`, smaller), each filled by set_board.
static func board(x: float, y: float, facing: float, title: String, subtitle: String, columns: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Leaderboard"
	var a := deg_to_rad(facing)
	var front := Vector3(cos(a), 0.0, -sin(a))       # the face looks this way (Godot)
	root.transform = Transform3D(Basis.looking_at(-front), MeshUtils.to_godot(x, y, ground(x, y)))
	var w := BOARD_SIZE.x
	var h := BOARD_SIZE.y
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.22, 0.27)
	wood.roughness = 0.6
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.06, 0.12, 0.3)
	face.roughness = 0.5
	var body := StaticBody3D.new()
	body.collision_layer = Layers.PROPS
	body.collision_mask = 0
	root.add_child(body)
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = BOARD_BOTTOM + h + 0.3
		cyl.material = wood
		post.mesh = cyl
		post.position = Vector3(side * (w * 0.5 - 0.25), cyl.height * 0.5 - 0.2, -0.1)
		root.add_child(post)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.16, cyl.height, 0.16)
		shape.shape = box
		shape.position = post.position
		body.add_child(shape)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(w, h, 0.08)
	pm.material = face
	panel.mesh = pm
	panel.position = Vector3(0, BOARD_BOTTOM + h * 0.5, -0.04)
	root.add_child(panel)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(w + 0.12, 0.1, 0.12)
	tm.material = wood
	trim.mesh = tm
	trim.position = Vector3(0, BOARD_BOTTOM + h + 0.03, -0.04)
	root.add_child(trim)
	var top := BOARD_BOTTOM + h - 0.1
	var t := _text(title.to_upper(), 46, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.35))
	t.name = "Title"
	t.position = Vector3(0, top, 0.005)
	root.add_child(t)
	top -= 0.26
	if subtitle != "":
		var sub := _text(subtitle, 26, HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.88, 0.95))
		sub.name = "Subtitle"
		sub.position = Vector3(0, top, 0.005)
		root.add_child(sub)
		top -= 0.18
	var col_w := (w - 0.3) / columns
	for c in columns:
		var x0 := -w * 0.5 + 0.15 + col_w * c + 0.05
		var head := _text("", 34, HORIZONTAL_ALIGNMENT_LEFT, Color(0.65, 0.8, 1.0))
		head.name = "Head%d" % c
		head.position = Vector3(x0, top - 0.04, 0.005)
		root.add_child(head)
		for k: String in ["Left", "Right"]:
			var l := _text("", 30, HORIZONTAL_ALIGNMENT_LEFT if k == "Left" else HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE)
			l.name = "%s%d" % [k, c]
			l.position = Vector3(x0 if k == "Left" else x0 + col_w - 0.1, top - 0.26, 0.005)
			root.add_child(l)
	return root


static func _text(text: String, size: int, align: HorizontalAlignment, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = BOARD_PIXEL
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.modulate = color
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.double_sided = false
	l.line_spacing = 2.0
	l.visibility_range_end = 60.0
	return l


## Column `c` of a leaderboard: a heading and rows of [left text, right text].
static func set_board(b: Node3D, c: int, heading: String, rows: Array) -> void:
	(b.get_node("Head%d" % c) as Label3D).text = heading
	var left := PackedStringArray()
	var right := PackedStringArray()
	for r: Array in rows:
		left.append(r[0])
		right.append(r[1])
	(b.get_node("Left%d" % c) as Label3D).text = "\n".join(left)
	(b.get_node("Right%d" % c) as Label3D).text = "\n".join(right)
