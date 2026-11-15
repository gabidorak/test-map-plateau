extends Node3D
## What a stunned person looks like (Main/People/Fx on every peer but a dedicated server): built from a few shared
## meshes and two shaders, so that a stun costs one or two draw calls and no work per frame from the CPU but its light:
## - "arcs" (tased): small electric arcs crawling over the body, a new shape 16 times a second, drawn by the arcs
##   shader alone (ARCS ribbons facing the camera, jagged in the vertex shader); a flickering blue light (not on the
##   low graphics); the body shaking; a crackle.
## - "net" (netted): a net wrapped round the body lying on the ground, wobbling as they struggle.
## - The taser's wires (wire()): two thin lines from the shooter's hand to the darts in the body, for the stun's length.
## - The net in flight (net_shot.gd) uses the same net shader on an open hemisphere (flying_net()).
## Everything hangs on the person's body node (people.gd person_body), so it lies, and is carried, with them.

const ItemsAudio = preload("res://scripts/items/items_audio.gd")

const ARCS := 10                            # arcs on a body
const ARC_JOINTS := 8                       # joints per arc
const ARC_LIGHT := Color(0.55, 0.75, 1.0)
const ROPE := Color(0.86, 0.8, 0.62)

const ARC_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float energy = 5.0;
uniform float width = 0.016;
uniform float jag = 0.07;
uniform float rate = 16.0;
uniform float lit_share = 0.6;

varying float v_side;
varying float v_lit;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	float seed = UV2.x;
	float joint = UV2.y;
	float frame = floor(TIME * rate + seed * 17.0);
	float ends = sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
	vec3 off = (vec3(hash(vec2(seed + joint, frame)), hash(vec2(seed * 3.1 + joint, frame + 7.0)),
			hash(vec2(seed * 5.7 + joint, frame + 3.0))) - 0.5) * 2.0 * jag * ends;
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX + off, 1.0)).xyz;
	vec3 t = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 across = normalize(cross(t, normalize(p)));
	v_lit = step(hash(vec2(seed * 9.3, frame + 11.0)), lit_share);
	v_side = UV.x;
	p += across * UV.x * width;
	VERTEX = p;
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float core = 1.0 - abs(v_side);
	ALBEDO = mix(tint.rgb, vec3(1.0), core * core) * energy;
	ALPHA = core * v_lit;
}
"""

const NET_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 rope : source_color = vec4(0.86, 0.8, 0.62, 1.0);
uniform vec2 cells = vec2(16.0, 10.0);
uniform float thickness = 0.06;
uniform float wobble = 0.0;

void vertex() {
	VERTEX += NORMAL * wobble * 0.025 * sin(TIME * 11.0 + VERTEX.y * 9.0 + VERTEX.x * 6.0);
}

void fragment() {
	vec2 f = fract(UV * cells);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	if (d > thickness) {
		discard;
	}
	ALBEDO = rope.rgb;
	ROUGHNESS = 0.95;
}
"""

var low_quality := false                    # no lights (game.gd low_quality)

var _on := {}                               # person id -> {"node", "body", "effect", "light", "sound", "fx"}
var _rng := RandomNumberGenerator.new()

static var _shared := {}


func _ready() -> void:
	_rng.randomize()
	set_process(false)


## Shows `effect` ("tased", "netted": data/items.json effects) on `person` (a node of people.gd's group), under `id`.
func start(id: String, person: Node3D, effect: String, fx: String) -> void:
	stop(id)
	var body: Node3D = person.person_body()
	if body == null:
		return
	var holder := Node3D.new()
	holder.name = "StunFx"
	body.add_child(holder)
	var entry := {"node": person, "body": body, "effect": effect, "holder": holder, "fx": fx}
	if fx == "arcs":
		var mi := MeshInstance3D.new()
		mi.mesh = _arc_mesh()
		mi.material_override = arc_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 0.3
		holder.add_child(mi)
		if not low_quality:
			var light := OmniLight3D.new()
			light.light_color = ARC_LIGHT
			light.omni_range = 3.5
			light.light_energy = 1.5
			light.position = Vector3(0.0, 0.9, 0.0)
			holder.add_child(light)
			entry["light"] = light
		var sound := AudioStreamPlayer3D.new()
		sound.stream = ItemsAudio.sound("crackle")
		sound.unit_size = 6.0
		sound.max_distance = 60.0
		sound.volume_db = -4.0
		sound.position = Vector3(0.0, 0.9, 0.0)
		holder.add_child(sound)
		if sound.stream:
			sound.play()
		entry["sound"] = sound
	elif fx == "net":
		var mi := MeshInstance3D.new()
		mi.mesh = _wrap_mesh()
		mi.material_override = net_material(0.6)
		mi.position = Vector3(0.0, 0.88, 0.0)
		holder.add_child(mi)
	_on[id] = entry
	set_process(true)


## Takes `id`'s effect off.
func stop(id: String) -> void:
	var entry: Dictionary = _on.get(id, {})
	if entry.is_empty():
		return
	_on.erase(id)
	if is_instance_valid(entry["holder"]):
		(entry["holder"] as Node).queue_free()
	if is_instance_valid(entry["body"]):
		(entry["body"] as Node3D).rotation.z = 0.0
	set_process(not _on.is_empty())


func stop_all() -> void:
	for id: String in _on.keys():
		stop(id)


func showing(id: String) -> bool:
	return _on.has(id)


func _process(_delta: float) -> void:
	for id: String in _on.keys():
		var entry: Dictionary = _on[id]
		if not is_instance_valid(entry["holder"]):
			_on.erase(id)
			continue
		if entry["fx"] != "arcs":
			continue
		# a body shaking, a light flickering: a few nodes, only while someone is tased
		var body: Node3D = entry["body"]
		if is_instance_valid(body) and not entry["node"].person_carried():
			body.rotation.z = _rng.randf_range(-0.07, 0.07)
		var light: OmniLight3D = entry.get("light")
		if light:
			light.light_energy = _rng.randf_range(0.3, 2.6) if _rng.randf() < 0.7 else 0.0
	if _on.is_empty():
		set_process(false)


# ---------------------------------------------------------------- shared looks

static func arc_material() -> ShaderMaterial:
	if not _shared.has("arc_mat"):
		var sh := Shader.new()
		sh.code = ARC_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_shared["arc_mat"] = m
	return _shared["arc_mat"]


## The net's material, `wobble` 0 (still) to 1 (struggling).
static func net_material(wobble := 0.0) -> ShaderMaterial:
	var key := "net_mat_%d" % roundi(wobble * 10.0)
	if not _shared.has(key):
		if not _shared.has("net_shader"):
			var sh := Shader.new()
			sh.code = NET_SHADER
			_shared["net_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _shared["net_shader"]
		m.set_shader_parameter("rope", ROPE)
		m.set_shader_parameter("wobble", wobble)
		_shared[key] = m
	return _shared[key]


## Arcs crawling over a standing body (feet at 0, ~1.8 m tall, ~0.35 m round), lying with it when it lies: ARCS
## ribbons of ARC_JOINTS joints, each from one point of the body's surface to another, bowing out. Per vertex: NORMAL
## the arc's direction there, UV (side -1/1, along 0..1), UV2 (the arc's seed, the joint): the shader does the rest.
static func _arc_mesh() -> ArrayMesh:
	if _shared.has("arc_mesh"):
		return _shared["arc_mesh"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for a in ARCS:
		var seed := rng.randf()
		var y0 := rng.randf_range(0.15, 1.65)
		var y1 := clampf(y0 + rng.randf_range(-0.6, 0.6), 0.1, 1.75)
		var t0 := rng.randf() * TAU
		var t1 := t0 + rng.randf_range(0.6, 2.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		var bow := rng.randf_range(0.05, 0.16)
		var pts: Array[Vector3] = []
		for j in ARC_JOINTS + 1:
			var u := float(j) / ARC_JOINTS
			var t := lerpf(t0, t1, u)
			var r := 0.36 + bow * sin(u * PI)
			pts.append(Vector3(cos(t) * r, lerpf(y0, y1, u), sin(t) * r))
		for j in ARC_JOINTS + 1:
			var dir: Vector3 = (pts[mini(j + 1, ARC_JOINTS)] - pts[maxi(j - 1, 0)]).normalized()
			for side: float in [-1.0, 1.0]:
				verts.append(pts[j])
				normals.append(dir)
				uvs.append(Vector2(side, float(j) / ARC_JOINTS))
				uv2s.append(Vector2(seed, float(j)))
		var base := a * (ARC_JOINTS + 1) * 2
		for j in ARC_JOINTS:
			var k := base + j * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-0.7, -0.2, -0.7), Vector3(1.4, 2.2, 1.4))
	_shared["arc_mesh"] = mesh
	return mesh


## The net wrapped round a body: a capsule a little bigger than it (the body's centre at the origin).
static func _wrap_mesh() -> Mesh:
	if not _shared.has("wrap_mesh"):
		var c := CapsuleMesh.new()
		c.radius = 0.43
		c.height = 1.95
		c.radial_segments = 16
		c.rings = 6
		_shared["wrap_mesh"] = c
	return _shared["wrap_mesh"]


## The net in flight: an open hemisphere, its mouth along -Z, 1 m across (net_shot.gd scales it), weights on its rim.
static func flying_net() -> Node3D:
	var root := Node3D.new()
	root.name = "Net"
	if not _shared.has("fly_mesh"):
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 0.5
		s.is_hemisphere = true
		s.radial_segments = 16
		s.rings = 5
		_shared["fly_mesh"] = s
		var w := SphereMesh.new()
		w.radius = 0.045
		w.height = 0.09
		w.radial_segments = 8
		w.rings = 4
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.2, 0.2, 0.22)
		wm.metallic = 0.6
		w.material = wm
		_shared["weight_mesh"] = w
	var mi := MeshInstance3D.new()
	mi.mesh = _shared["fly_mesh"]
	mi.material_override = net_material(0.0)
	mi.rotation.x = PI * 0.5               # its mouth (the rim, the weights) ahead along -Z, the dome trailing
	mi.scale = Vector3(1.0, 0.6, 1.0)
	root.add_child(mi)
	for k in 6:
		var a := TAU * k / 6.0
		var w := MeshInstance3D.new()
		w.mesh = _shared["weight_mesh"]
		w.position = Vector3(cos(a) * 0.5, sin(a) * 0.5, 0.0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)
	return root


## The taser's two wires, from `from` to `to` (global; wire_pose moves them), as one node.
static func wire() -> Node3D:
	if not _shared.has("wire_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(0.006, 0.006, 1.0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.75, 0.55, 0.3)
		b.material = m
		_shared["wire_mesh"] = b
	var root := Node3D.new()
	root.name = "TaserWires"
	root.top_level = true
	for side: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = _shared["wire_mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(side * 0.025, 0.0, -0.5)
		root.add_child(mi)
	return root


## Stretches wires `w` (wire()) from `from` to `to`.
static func wire_pose(w: Node3D, from: Vector3, to: Vector3) -> void:
	var l := from.distance_to(to)
	if l < 0.05:
		w.visible = false
		return
	w.visible = true
	var up := Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	w.global_transform = Transform3D(Basis.looking_at(to - from, up), from).scaled_local(Vector3(1.0, 1.0, l))
