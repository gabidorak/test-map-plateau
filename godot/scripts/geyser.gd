extends Node3D
## Water gushing out of a knocked-over fire hydrant or tap (scripts/breakables.gd): a white column of spray shooting
## `height` m up and falling back around it as droplets, mist rolling over the ground at its foot, and a roar.
## Breakables frees it when the hydrant is repaired, easing it off first with set_strength().

const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const G := 9.8

var height := 10.0                          # m, top of the column

var _systems: Array[GPUParticles3D] = []
var _sound: AudioStreamPlayer3D
var _volume_db := 0.0

static var _shared := {}                    # draw meshes and process materials, built once per height


func _ready() -> void:
	var v := sqrt(2.0 * G * height)             # m/s out of the pipe
	# dense fast core low down, the full column spreading into a crown at the top
	_add("core", 360, 0.6, _process_material("core", v, 1.5, 0.95, 0.05, 0.5, 0.9, 1.0),
			_quad(0.4, Color(0.97, 0.98, 1.0)))
	_add("jet", 520, 2.0 * v / G, _process_material("jet", v, 3.0, 0.9, 0.06, 0.5, 1.6, 0.95),
			_quad(0.6, Color(0.95, 0.97, 1.0)))
	_add("drops", 220, 2.2 * v / G, _process_material("drops", v * 0.85, 14.0, 0.75, 0.08, 0.6, 0.6, 0.9),
			_quad(0.18, Color(0.85, 0.92, 1.0)))
	var mist := _process_material("mist", 1.6, 80.0, 0.0, 0.35, 1.0, 3.0, 0.3)
	mist.direction = Vector3(1.0, 0.25, 0.0)
	mist.gravity = Vector3.ZERO
	_add("mist", 40, 1.6, mist, _quad(1.2, Color(0.9, 0.94, 1.0)))
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = VehicleAudio.one_shot("gush")
	_sound.unit_size = 4.0 + height
	_sound.max_distance = 60.0 + 4.0 * height
	_volume_db = linear_to_db(clampf(height / 10.0, 0.4, 1.0))
	_sound.volume_db = _volume_db
	_sound.position = Vector3.UP * 0.5
	add_child(_sound)
	_sound.play()


## 0 (off) to 1 (full): the last seconds before the repair.
func set_strength(s: float) -> void:
	for p in _systems:
		p.amount_ratio = s
	_sound.volume_db = _volume_db + linear_to_db(maxf(s, 0.001))


func _add(name_: String, amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh) -> void:
	var p := GPUParticles3D.new()
	p.name = name_
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = process
	p.draw_pass_1 = mesh
	p.preprocess = minf(lifetime, 1.0)          # already gushing on the first frame
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := 2.0 + height * 0.3
	p.visibility_aabb = AABB(Vector3(-r, -1.0, -r), Vector3(2.0 * r, height + 3.0, 2.0 * r))
	add_child(p)
	_systems.append(p)


## Particles shot up at `speed` (m/s) within `spread`° (with `randomness` of it lost), from a sphere `radius` m,
## growing from `scale0` to `scale1` and fading out from `alpha`.
func _process_material(kind: String, speed: float, spread: float, randomness: float, radius: float, scale0: float,
		scale1: float, alpha: float) -> ParticleProcessMaterial:
	var key := "%s_%.1f" % [kind, height]
	if _shared.has(key):
		return _shared[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed * randomness
	m.initial_velocity_max = speed
	m.gravity = Vector3(0.0, -G, 0.0)
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.scale_min = 0.7
	m.scale_max = 1.3
	var curve := Curve.new()
	curve.max_value = maxf(scale0, scale1)
	curve.add_point(Vector2(0.0, scale0))
	curve.add_point(Vector2(1.0, scale1))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, alpha))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.7, Color(1.0, 1.0, 1.0, alpha * 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	m.angle_min = 0.0
	m.angle_max = 360.0
	_shared[key] = m
	return m


## Camera-facing soft round blob of `size` m tinted `tint`.
static func _quad(size: float, tint: Color) -> QuadMesh:
	var key := "quad_%.2f_%s" % [size, tint.to_html()]
	if _shared.has(key):
		return _shared[key]
	var dot := Gradient.new()
	dot.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	dot.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = dot
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.albedo_texture = tex
	mat.roughness = 0.3
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	_shared[key] = q
	return q
