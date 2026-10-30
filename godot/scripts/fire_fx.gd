extends Node3D
## One fire of PTA Online's firefighter job as every peer but the dedicated server draws it (scripts/online/fires.gd
## makes them from the host's word): flames and a column of smoke (GPU particles, cheap), an orange glow at night and
## a crackling roar, all as strong as the fire's `heat` (0..1). Its kind sets the shape: a bin's small blaze, a parked
## car's (a burnt-out car shell stands there, solid), the foot of a building's facade (`width` m of it, the node's +Z
## out of the wall), a patch of grass or a wood's floor. Put out (put_out), the flames die
## and white steam rises for STEAM s.
## Level of detail by the distance to the camera, looked at every LOD_EVERY s: the flames, the sound and (at night,
## scripts/night.gd) the glow within FLAME_FAR m, the smoke within SMOKE_FAR m (a column on the horizon shows where the
## fire is), nothing further. Cheap on purpose (measured on an Iris Xe, PERFORMANCE.md's probe): the smoke is lit per
## vertex (lit per pixel, 5 fires' smoke cost ~1 ms), no scorched decal on the ground (4 of them: ~0.8 ms), and no light:
## at night a single extra omni light over the street lamps cost ~1 ms, so the glow is an additive halo sprite instead.
## Positions: the node stands on the ground at the fire's foot.

const WreckSmoke = preload("res://scripts/wreck_smoke.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const Car = preload("res://scripts/car.gd")

const FLAME_FAR := 320.0
const SMOKE_FAR := 2200.0
const LOD_EVERY := 0.3
const STEAM := 6.0                          # s of steam once put out
const CARS := ["sedan", "suv", "van", "taxi", "hatchback-sports", "delivery"]   # the burnt-out car shells
## Per kind: flames' emission box half size (m), how many flame and smoke particles, the smoke's darkness (0 black),
## the glow's size (m).
const LOOK := {
	"bin": {"box": Vector3(0.35, 0.35, 0.35), "y": 0.8, "flames": 14, "smoke": 10, "grey": 0.12, "glow": 5.0,
			"size": 0.7},
	"car": {"box": Vector3(0.9, 0.5, 2.0), "y": 1.0, "flames": 30, "smoke": 20, "grey": 0.06, "glow": 7.0, "size": 1.3},
	"building": {"box": Vector3(3.0, 1.2, 0.35), "y": 1.3, "flames": 36, "smoke": 26, "grey": 0.08, "glow": 8.0,
			"size": 1.5},
	"grass": {"box": Vector3(2.4, 0.15, 2.4), "y": 0.25, "flames": 26, "smoke": 16, "grey": 0.45, "glow": 6.0,
			"size": 1.0},
	"wood": {"box": Vector3(2.8, 0.6, 2.8), "y": 0.6, "flames": 32, "smoke": 20, "grey": 0.3, "glow": 7.5, "size": 1.3},
}

var kind := "bin"
var width := 4.0                            # m of facade (buildings)
var heat := 1.0
var out := false
var seed_ := 0                              # picks the car shell

var _flames: GPUParticles3D
var _smoke: GPUParticles3D
var _steam: GPUParticles3D
var _glow: MeshInstance3D
var _sound: AudioStreamPlayer3D
var _shell: Node3D
var _lod_t := 0.0
var _dist := 0.0
var _out_t := 0.0
var _flicker := 0.0
var _rng := RandomNumberGenerator.new()

static var _shared := {}


func _ready() -> void:
	_rng.seed = seed_
	var look: Dictionary = LOOK[kind]
	var s: float = look["size"]
	var box: Vector3 = look["box"]
	if kind == "building":
		box.x = maxf(width * 0.5 - 0.4, 1.0)
	var mid := Vector3(0.0, float(look["y"]), 0.0)
	if kind == "car":
		_shell = _car_shell()
	_flames = _particles("Flames", int(look["flames"]), 0.9, _flame_material(box, s), _flame_quad(), mid)
	_smoke = _particles("Smoke", int(look["smoke"]), 6.0, _smoke_material(box, s), _puff(
			Color(float(look["grey"]), float(look["grey"]), float(look["grey"]))), mid + Vector3.UP * 0.6 * s)
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	_glow.mesh = _halo(float(look["glow"]))
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = mid + Vector3(0.0, 0.5, 0.6 if kind == "building" else 0.0)
	_glow.visible = false
	add_child(_glow)
	_sound = AudioStreamPlayer3D.new()
	_sound.name = "Roar"
	_sound.stream = VehicleAudio.one_shot("fire")
	_sound.unit_size = 4.0 + 3.0 * s
	_sound.max_distance = 140.0
	_sound.position = mid
	add_child(_sound)
	set_heat(heat)
	_lod()


## How strong it burns (0..1): the flames, the smoke, the light and the sound with it.
func set_heat(h: float) -> void:
	heat = clampf(h, 0.0, 1.0)
	if _flames == null or out:
		return
	_flames.amount_ratio = clampf(0.15 + 0.85 * heat, 0.0, 1.0)
	_smoke.amount_ratio = clampf(0.3 + 0.7 * heat, 0.0, 1.0)
	_sound.volume_db = linear_to_db(maxf(0.15 + 0.85 * heat, 0.001)) - 4.0


## Put out: no more flames, steam for STEAM s (then the owner frees it).
func put_out() -> void:
	if out:
		return
	out = true
	_out_t = 0.0
	if _flames == null:
		return
	_flames.emitting = false
	_smoke.emitting = false
	_glow.visible = false
	_sound.stop()
	_steam = _particles("Steam", 24, 4.0, _smoke_material(LOOK[kind]["box"], float(LOOK[kind]["size"]) * 0.8),
			_puff(Color(0.85, 0.85, 0.85)), Vector3(0.0, float(LOOK[kind]["y"]), 0.0))
	_steam.emitting = _dist < FLAME_FAR
	get_tree().create_timer(STEAM * 0.6).timeout.connect(func() -> void:
		if is_instance_valid(_steam):
			_steam.emitting = false)


func _process(delta: float) -> void:
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = LOD_EVERY + _rng.randf() * 0.05
		_lod()
	if out:
		_out_t += delta
		return
	if _glow.visible:
		_flicker -= delta
		if _flicker <= 0.0:
			_flicker = _rng.randf_range(0.05, 0.12)
			_glow.transparency = 1.0 - clampf((0.35 + 0.65 * heat) * _rng.randf_range(0.75, 1.0), 0.0, 1.0)


## Shows what is worth drawing at its distance from the camera.
func _lod() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_dist = cam.global_position.distance_to(global_position) if cam else 0.0
	if out:
		return
	var near := _dist < FLAME_FAR
	_flames.emitting = near
	_flames.visible = near
	_smoke.emitting = _dist < SMOKE_FAR
	_smoke.visible = _dist < SMOKE_FAR + 200.0
	var night: Object = get_parent().get("night") if get_parent() else null
	_glow.visible = near and night != null and night.get("on") == true
	if near and not _sound.playing:
		_sound.play(_rng.randf() * 1.5)
	elif not near and _sound.playing:
		_sound.stop()


func _particles(name_: String, amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh,
		at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name_
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.process_material = process
	p.draw_pass_1 = mesh
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.randomness = 0.3
	p.preprocess = lifetime * 0.5
	p.visibility_aabb = AABB(Vector3(-15.0, -3.0, -15.0), Vector3(30.0, 45.0, 30.0))
	add_child(p)
	return p


## Flames out of a box of half size `box`: up fast, short-lived (some much shorter: a ragged top, not a box of flames),
## shrinking, yellow to red.
static func _flame_material(box: Vector3, s: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.6 * s
	m.initial_velocity_max = 3.0 * s
	m.lifetime_randomness = 0.6
	m.gravity = Vector3(0.0, 1.5, 0.0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 1.3 * s
	m.scale_max = 2.0 * s
	m.scale_curve = _curve(1.0, 0.25)
	var g := Gradient.new()                 # yellow core, orange, dark red, gone
	g.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	g.set_color(1, Color(0.55, 0.08, 0.02, 0.0))
	g.add_point(0.3, Color(1.0, 0.45, 0.06, 0.85))
	g.add_point(0.7, Color(0.85, 0.2, 0.03, 0.5))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	return m


## Smoke rising from the top of the flames, swelling and drifting, fading out.
static func _smoke_material(box: Vector3, s: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box * 0.7
	m.direction = Vector3.UP
	m.spread = 10.0
	m.initial_velocity_min = 1.5 * s
	m.initial_velocity_max = 2.8 * s
	m.gravity = Vector3(0.6, 0.8, 0.3)
	m.damping_min = 0.3
	m.damping_max = 0.6
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -25.0
	m.angular_velocity_max = 25.0
	m.scale_min = 0.8 * s
	m.scale_max = 1.2 * s
	m.scale_curve = _curve(1.2, 5.5)
	m.color_ramp = _ramp(Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0))
	return m


## A flame: a soft blob, unshaded and blended over what is behind it (added on, it faded away in daylight), its colour
## from the particles' (yellow to red).
static func _flame_quad() -> QuadMesh:
	if _shared.has("flame"):
		return _shared["flame"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = _soft(0.9)
	var q := QuadMesh.new()
	q.material = mat
	_shared["flame"] = q
	return q


## The glow round a fire at night: a soft orange halo `size` m across, added onto what is behind it, facing the camera.
static func _halo(size: float) -> QuadMesh:
	var key := "halo_%s" % size
	if _shared.has(key):
		return _shared[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.42, 0.1, 0.4)
	mat.albedo_texture = _soft(2.5)
	var q := QuadMesh.new()
	q.material = mat
	q.size = Vector2(size, size)
	_shared[key] = q
	return q


## White round blob fading out to its rim (`power`: the higher, the tighter its middle), transparent in the corners.
static func _soft(power: float) -> Texture2D:
	var key := "soft_%s" % power
	if _shared.has(key):
		return _shared[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2((x + 0.5) / 32.0 - 1.0, (y + 0.5) / 32.0 - 1.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - r, 0.0, 1.0), power)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_shared[key] = tex
	return tex


## A smoke puff 1 m across tinted `tint`: WreckSmoke's soft blob, lit per vertex.
static func _puff(tint: Color) -> QuadMesh:
	var key := "puff_" + tint.to_html()
	if _shared.has(key):
		return _shared[key]
	var q: QuadMesh = WreckSmoke._blob(tint, false).duplicate()
	var mat: StandardMaterial3D = q.material.duplicate()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	q.material = mat
	_shared[key] = q
	return q


static func _curve(a: float, b: float) -> CurveTexture:
	var key := "curve_%s_%s" % [a, b]
	if _shared.has(key):
		return _shared[key]
	var curve := Curve.new()
	curve.max_value = maxf(a, b)
	curve.add_point(Vector2(0.0, a))
	curve.add_point(Vector2(1.0, b))
	var ct := CurveTexture.new()
	ct.curve = curve
	_shared[key] = ct
	return ct


static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var key := "ramp_%s_%s" % [a.to_html(), b.to_html()]
	if _shared.has(key):
		return _shared[key]
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	g.add_point(0.35, a.lerp(b, 0.2))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_shared[key] = gt
	return gt


## A burnt-out car (one of CARS, sooty), solid: the water splashes on it, players and vehicles bump into it.
func _car_shell() -> Node3D:
	var model: String = CARS[seed_ % CARS.size()]
	var spec: Dictionary = Car.SPECS[model]
	var m: Node3D = load("res://assets/cars/" + spec.get("file", model + ".glb")).instantiate()
	m.name = "BurntCar"
	m.scale = Vector3.ONE * float(spec.get("scale", 1.5))
	add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _soot()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: AABB = global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()   # in the fire's frame
		box = b if first else box.merge(b)
		first = false
	var body := StaticBody3D.new()
	body.name = "BurntCarBody"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 1.5), maxf(box.size.y * 0.8, 1.0), maxf(box.size.z, 3.0))
	cs.shape = shape
	cs.position = box.get_center() - Vector3(0.0, box.size.y * 0.1, 0.0)
	body.add_child(cs)
	add_child(body)
	return m


static func _soot() -> StandardMaterial3D:
	if _shared.has("soot"):
		return _shared["soot"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.035, 0.03, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	_shared["soot"] = mat
	return mat
