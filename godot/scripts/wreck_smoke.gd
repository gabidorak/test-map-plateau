extends Node3D
## Smoke out of a damaged vehicle (scripts/car.gd set_health), at its engine: grey wisps once it has taken half the
## damage it can (level 1), a thick column of black smoke over a few flames once it is broken (level 2), and a ball of
## fire and smoke the moment it breaks (burst). The particles stay where they were emitted (global coordinates), so a
## wreck on the move, a falling plane, trails its smoke. `size` scales it all (a bus smokes more than a car).

var level := 0                              # 0 none, 1 damaged, 2 broken
var size := 1.0

var _wisps: GPUParticles3D
var _smoke: GPUParticles3D
var _flames: GPUParticles3D

static var _shared := {}                    # draw meshes, built once


func _ready() -> void:
	_wisps = _system("Wisps", 24, 3.0, _material(Vector2(1.5, 2.5), 15.0, Vector3(0.3, 0.9, 0.2), 0.25,
			Vector2(0.6, 2.4), Color(1, 1, 1, 0.75)), _blob(Color(0.42, 0.42, 0.42), false))
	_smoke = _system("Smoke", 90, 5.0, _material(Vector2(2.5, 4.0), 12.0, Vector3(0.5, 1.2, 0.25), 0.35,
			Vector2(0.9, 5.0), Color(1, 1, 1, 0.9)), _blob(Color(0.05, 0.05, 0.05), false))
	_flames = _system("Flames", 32, 0.5, _material(Vector2(1.0, 2.5), 25.0, Vector3(0.0, 2.0, 0.0), 0.35,
			Vector2(0.8, 0.25), Color(1.0, 0.85, 0.3, 0.95), Color(0.9, 0.2, 0.05, 0.0)), _blob(Color(1.0, 0.55, 0.15), true))
	set_level(level)


## 0 no smoke, 1 grey wisps, 2 black smoke and flames. Particles already out live on.
func set_level(l: int) -> void:
	level = l
	if _wisps == null:
		return
	_wisps.emitting = l == 1
	_smoke.emitting = l == 2
	_flames.emitting = l == 2


func emitting_black() -> bool:
	return _smoke != null and _smoke.emitting


## The moment it breaks: a ball of fire and a puff of black smoke, freed once they are over.
func burst() -> void:
	var fire := _system("Fireball", 40, 0.8, _material(Vector2(3.0, 8.0), 180.0, Vector3(0.0, 2.0, 0.0), 0.6,
			Vector2(1.2, 2.5), Color(1.0, 0.9, 0.4, 1.0), Color(0.8, 0.15, 0.05, 0.0)), _blob(Color(1.0, 0.6, 0.2), true))
	var puff := _system("Puff", 24, 2.5, _material(Vector2(2.0, 5.0), 180.0, Vector3(0.0, 1.5, 0.0), 0.6,
			Vector2(1.5, 5.0), Color(1, 1, 1, 0.9)), _blob(Color(0.06, 0.06, 0.06), false))
	for p in [fire, puff]:
		p.one_shot = true
		p.explosiveness = 0.9
		p.emitting = true
		get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


func _system(name_: String, amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name_
	p.amount = maxi(1, roundi(amount * size))
	p.lifetime = lifetime
	p.process_material = process
	p.draw_pass_1 = mesh
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := 40.0 * size                    # global particles: room for the trail of a moving wreck
	p.visibility_aabb = AABB(Vector3(-r, -r * 0.5, -r), Vector3(2.0 * r, 1.5 * r, 2.0 * r))
	add_child(p)
	return p


## Puffs going up at `speed` (min, max, m/s) within `spread`°, pushed by `gravity` (buoyancy and drift), out of a
## sphere of `radius` m, growing from `scales`.x to .y (m) and fading from `color` to `end` (default: transparent).
func _material(speed: Vector2, spread: float, gravity: Vector3, radius: float, scales: Vector2, color: Color,
		end := Color(1, 1, 1, 0)) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed.x * size
	m.initial_velocity_max = speed.y * size
	m.gravity = gravity
	m.damping_min = 0.4
	m.damping_max = 0.8
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius * size
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	m.scale_min = 0.8 * size
	m.scale_max = 1.2 * size
	var curve := Curve.new()
	curve.max_value = maxf(scales.x, scales.y)
	curve.add_point(Vector2(0.0, scales.x))
	curve.add_point(Vector2(1.0, scales.y))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, end)
	ramp.add_point(0.4, color.lerp(end, 0.25))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	return m


## Camera-facing soft round blob 1 m across tinted `tint`: lit smoke, or glowing (`fire`: added onto what is behind).
static func _blob(tint: Color, fire: bool) -> QuadMesh:
	var key := "%s_%s" % [tint.to_html(), fire]
	if _shared.has(key):
		return _shared[key]
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	dot.add_point(0.45, Color(1, 1, 1, 0.75))
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
	if fire:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.roughness = 1.0
	var q := QuadMesh.new()
	q.material = mat
	_shared[key] = q
	return q
