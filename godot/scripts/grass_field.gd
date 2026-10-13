extends Node3D
## Grass tufts (milestone M4): MultiMesh clumps scattered at runtime around the camera on the grass,
## tall-grass and forest-floor ground pieces (world/ground_index.json), so the scene stays small.
## Scatter is deterministic per 16 m chunk; chunks are built as the camera moves and dropped behind
## it. Density, size and fade distance depend on the ground class.

const GroundMap = preload("res://scripts/ground_map.gd")
const SHADER := preload("res://shaders/toy_grass.gdshader")
const CHUNK := 16.0
const EDGE := 0.35                  # tufts stay this far inside their ground piece
const BUILD_PER_FRAME := 6
const JUMP := 24.0                  # camera moves farther than this in a frame: build everything now

## Per ground material: tufts per m², fade distances, blade count/segments, tuft height range (m),
## tuft radius, blade width, lean, ground pattern scale for the colour.
const KINDS := {
	"grass": {"density": 2.2, "fade": [24.0, 36.0], "blades": 10, "segments": 2, "height": [0.11, 0.2],
			"radius": 0.09, "width": 0.045, "lean": 0.5, "tone_scale": 1.0, "two_tone": true},
	"tall_grass": {"density": 1.8, "fade": [40.0, 58.0], "blades": 11, "segments": 2, "height": [0.3, 0.55],
			"radius": 0.14, "width": 0.05, "lean": 0.5, "tone_scale": 1.3, "two_tone": true},
	"forest_floor": {"density": 0.35, "fade": [30.0, 45.0], "blades": 8, "segments": 2, "height": [0.22, 0.4],
			"radius": 0.13, "width": 0.08, "lean": 0.7, "tone_scale": 1.0, "two_tone": false},
}

@export var index_path := GroundMap.DEFAULT_INDEX

var _map: RefCounted
var _kinds: Array = []              # [material id, settings, mesh, material, colour]
var _chunks := {}                   # Vector2i -> Node3D
var _last := Vector2(INF, INF)
var _radius := 0.0


func _ready() -> void:
	_map = GroundMap.get_map(index_path)
	if _map == null:
		set_process(false)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for name: String in KINDS:
		var k: Dictionary = KINDS[name]
		var id: int = _map.materials.find(name)
		if id < 0:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("fade_start", k["fade"][0])
		mat.set_shader_parameter("fade_end", k["fade"][1])
		mat.set_shader_parameter("tone_scale", k["tone_scale"])
		mat.set_shader_parameter("two_tone", k["two_tone"])
		var col := Color.html(_map.palette["ground"][name])
		if name == "forest_floor":
			col = col.lightened(0.15)
		_kinds.append([id, k, _tuft_mesh(k, rng, mat), col])
		_radius = maxf(_radius, k["fade"][1] + CHUNK)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := Vector2(cam.global_position.x, -cam.global_position.z)
	var jump := p.distance_to(_last) > JUMP
	_last = p
	var c0 := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var reach := ceili(_radius / CHUNK)
	var wanted: Array = []
	for j in range(c0.y - reach, c0.y + reach + 1):
		for i in range(c0.x - reach, c0.x + reach + 1):
			var key := Vector2i(i, j)
			var d := p.distance_to((Vector2(key) + Vector2(0.5, 0.5)) * CHUNK)
			if d < _radius and not _chunks.has(key):
				wanted.append([d, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	var budget := wanted.size() if jump else BUILD_PER_FRAME
	for w in wanted.slice(0, budget):
		_chunks[w[1]] = _build_chunk(w[1])
	for key: Vector2i in _chunks.keys():
		if p.distance_to((Vector2(key) + Vector2(0.5, 0.5)) * CHUNK) > _radius + CHUNK:
			var n: Node = _chunks[key]
			_chunks.erase(key)
			if n:
				n.queue_free()


func _build_chunk(key: Vector2i) -> Node3D:
	var node: Node3D = null
	var origin := Vector2(key) * CHUNK
	var centre := origin + Vector2(CHUNK, CHUNK) / 2.0
	for kind_index in _kinds.size():
		var kd: Array = _kinds[kind_index]
		var id: int = kd[0]
		var k: Dictionary = kd[1]
		var col: Color = kd[3]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(key.x, key.y, kind_index))
		var spacing := 1.0 / sqrt(float(k["density"]))
		var n := ceili(CHUNK / spacing)
		var buf := PackedFloat32Array()
		var count := 0
		for gj in n:
			for gi in n:
				var x := origin.x + (gi + rng.randf()) * spacing
				var y := origin.y + (gj + rng.randf()) * spacing
				var yaw := rng.randf() * TAU
				var s := rng.randf_range(0.8, 1.25)
				var phase := rng.randf()
				if x >= origin.x + CHUNK or y >= origin.y + CHUNK:
					continue
				if _map.material_at(x, y) != id or _map.material_at(x + EDGE, y) != id \
						or _map.material_at(x - EDGE, y) != id or _map.material_at(x, y + EDGE) != id \
						or _map.material_at(x, y - EDGE) != id:
					continue
				var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
				var z: float = _map.height(x, y) - 0.02
				# local to the chunk node (Godot axes): x, height, -y
				buf.append_array([b.x.x, b.y.x, b.z.x, x - centre.x, b.x.y, b.y.y, b.z.y, z,
						b.x.z, b.y.z, b.z.z, -(y - centre.y), col.r, col.g, col.b, phase])
				count += 1
		if count == 0:
			continue
		if node == null:
			node = Node3D.new()
			node.name = "Chunk_%d_%d" % [key.x, key.y]
			node.position = Vector3(centre.x, 0.0, -centre.y)
			add_child(node)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = kd[2]
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(k["fade"][1]) + CHUNK
		node.add_child(mmi)
	return node


## One tuft: blades in a ring, each a tapered strip leaning outwards. COLOR.r = height along the blade.
func _tuft_mesh(k: Dictionary, rng: RandomNumberGenerator, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = k["blades"]
	var segs: int = k["segments"]
	for b in blades:
		var a := TAU * b / blades + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x)
		var base := out * float(k["radius"]) * rng.randf_range(0.2, 1.0)
		var h := rng.randf_range(k["height"][0], k["height"][1])
		var lean := float(k["lean"]) * rng.randf_range(0.5, 1.2) * h
		var w := float(k["width"]) * rng.randf_range(0.8, 1.2)
		var rows: Array[Vector3] = []
		var ts: Array[float] = []
		for i in segs + 1:
			var t := float(i) / segs
			rows.append(base + out * lean * t * t + Vector3.UP * h * t)
			ts.append(t)
		var normal := (Vector3.UP * 0.85 + out * 0.15).normalized()
		for i in segs:
			var w0 := w * (1.0 - ts[i])
			var w1 := w * (1.0 - ts[i + 1])
			var p0l := rows[i] - side * w0
			var p0r := rows[i] + side * w0
			var p1l := rows[i + 1] - side * w1
			var p1r := rows[i + 1] + side * w1
			for v: Array in [[p0l, ts[i]], [p0r, ts[i]], [p1r, ts[i + 1]], [p0l, ts[i]], [p1r, ts[i + 1]], [p1l, ts[i + 1]]]:
				st.set_normal(normal)
				st.set_color(Color(v[1], 0.0, 0.0))
				st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh
