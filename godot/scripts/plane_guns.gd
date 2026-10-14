extends Node3D
## Machine guns of the armed biplane (scripts/plane.gd, Car.SPECS "guns"), WWII style: two Browning-like guns under the
## lower wing fire in turn, RATE rounds a second together, while `firing`; every round is a glowing tracer (a streak
## facing the camera, a glowing dot seen end-on from behind the plane) and a muzzle flash. Rounds leave at MUZZLE_SPEED plus the plane's own speed, converge on the plane's `aim` point, drop under
## gravity, and are traced by a ray each physics tick. Where one hits: sparks and a ping on a vehicle, a puff of dust
## anywhere else, and, on the peer simulating the plane (`live`), the `hit` signal: game.gd damages the vehicle
## (car.gd damage, through net.gd on the peer simulating it) or knocks the prop over (breakables.gd shoot).
## Remote copies of the plane fire the same rounds from its LAN state, for show only.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")

const RATE := 24.0                          # rounds per second, both guns together
const MUZZLE_SPEED := 760.0                 # m/s
const LIFE := 1.4                           # s of flight (~1 km)
const SPREAD := 0.004                       # rad, scatter of each round
const G := 9.8
const DAMAGE := 5.0                         # health per round on a vehicle (car.gd: a car has 100)
const MASK := Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.DEBRIS
const TRACER_LENGTH := 9.0                  # m: most of a tick of flight
const TRACER_WIDTH := 0.12                  # m, half width; more far away so a tracer stays a few pixels wide...
const TRACER_ANGLE := 0.004                 # rad: ...that half width, seen from the camera
const TRACER_COLOR := Color(2.4, 1.4, 0.35) # over 1: glows with the high graphics; drawn over (not added to) what is
											# behind, so it shows over pale roofs too
const MAX_ROUNDS := 64
const MAX_EFFECTS := 24                     # sparks and dust puffs at once
const FLASH_TIME := 0.05                    # s

## A round of a `live` plane hit `collider` (its shape `shape`) at `point`, flying at `velocity`.
signal hit(collider: Object, shape: int, point: Vector3, velocity: Vector3)

var firing := false
var live := true                            # its hits count (the plane is simulated here)
var muzzles: Array[Vector3] = []            # plane frame
var aim := Vector3.FORWARD                  # plane frame, where the guns converge
var rounds_fired := 0
var vehicle_hits := 0                       # rounds that hit a vehicle (on this peer, live or not)

var _rounds: Array = []                     # [position, velocity, age]
var _cool := 0.0                            # s until the next round may go
var _gun := 0                               # the gun firing next
var _tracers: MeshInstance3D
var _tracer_im := ImmediateMesh.new()
var _flashes: Array[MeshInstance3D] = []
var _flash_t: Array[float] = []
var _shot: AudioStreamPlayer3D
var _pings: Array[AudioStreamPlayer3D] = []
var _ping := 0
var _effects := 0
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()

static var _shared := {}


## Gun muzzles and the convergence point in the plane frame; before adding it to the plane.
func setup(muzzle_points: Array[Vector3], aim_point: Vector3) -> void:
	muzzles = muzzle_points
	aim = aim_point
	name = "Guns"


func _ready() -> void:
	_query.collision_mask = MASK
	_query.hit_back_faces = false
	_query.exclude = [(get_parent() as CollisionObject3D).get_rid()]
	_tracers = MeshInstance3D.new()
	_tracers.name = "Tracers"
	_tracers.top_level = true
	_tracers.mesh = _tracer_im
	var tracer_mat := _glow_material(TRACER_COLOR, false, false)
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_tracers.material_override = tracer_mat
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracers.custom_aabb = AABB(Vector3(-1e4, -1e3, -1e4), Vector3(2e4, 4e3, 2e4))    # rounds anywhere
	add_child(_tracers)
	_tracers.global_transform = Transform3D.IDENTITY
	for m in muzzles:
		var flash := MeshInstance3D.new()
		flash.mesh = _flash_mesh()
		flash.position = m + Vector3(0.0, 0.0, 0.2)
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		add_child(flash)
		_flashes.append(flash)
		_flash_t.append(0.0)
	_shot = AudioStreamPlayer3D.new()
	_shot.stream = VehicleAudio.one_shot("gunshot")
	_shot.unit_size = 20.0
	_shot.max_distance = 500.0
	_shot.max_polyphony = 8
	_shot.position = Vector3(0.0, muzzles[0].y, muzzles[0].z) if not muzzles.is_empty() else Vector3.ZERO
	add_child(_shot)
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.stream = VehicleAudio.one_shot("bullet_hit")
		p.top_level = true
		p.unit_size = 6.0
		p.max_distance = 120.0
		p.volume_db = -4.0
		add_child(p)
		_pings.append(p)


func _physics_process(delta: float) -> void:
	var plane := get_parent() as RigidBody3D
	_cool -= delta
	if firing and not muzzles.is_empty():
		while _cool <= 0.0:
			_fire(plane, -_cool)
			_cool += 1.0 / RATE
	else:
		_cool = maxf(_cool, 0.0)            # the first round goes as soon as the trigger is pressed
	_fly(delta)


## One round from the next gun, fired `late` s ago (several rounds can go in one tick).
func _fire(plane: RigidBody3D, late: float) -> void:
	var xf := plane.global_transform
	var muzzle := xf * muzzles[_gun]
	var dir := (xf * aim - muzzle).normalized()
	dir = (dir + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * SPREAD).normalized()
	var v := dir * MUZZLE_SPEED + plane.linear_velocity
	if _rounds.size() >= MAX_ROUNDS:
		_rounds.pop_front()
	_rounds.append([muzzle + v * late, v, late])
	_flash_t[_gun] = FLASH_TIME
	_gun = (_gun + 1) % muzzles.size()
	rounds_fired += 1
	_shot.pitch_scale = _rng.randf_range(0.92, 1.08)
	_shot.play()


## Moves the rounds on by a tick; those hitting something stop there.
func _fly(delta: float) -> void:
	if _rounds.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _rounds.size():
		var r: Array = _rounds[i]
		var p: Vector3 = r[0]
		var v: Vector3 = r[1]
		var q := p + v * delta
		_query.from = p
		_query.to = q
		var h := space.intersect_ray(_query)
		if h:
			_rounds.remove_at(i)
			_impact(h, v)
			continue
		v.y -= G * delta
		r[0] = q
		r[1] = v
		r[2] += delta
		if r[2] > LIFE:
			_rounds.remove_at(i)
			continue
		i += 1


func _impact(h: Dictionary, v: Vector3) -> void:
	var collider: Object = h["collider"]
	var metal := collider is Node and (collider as Node).is_in_group("vehicles")
	_effect(h["position"], h["normal"], metal)
	if metal:
		vehicle_hits += 1
		var ping := _pings[_ping]
		_ping = (_ping + 1) % _pings.size()
		ping.global_position = h["position"]
		ping.pitch_scale = _rng.randf_range(0.85, 1.2)
		ping.play()
	if live:
		hit.emit(collider, h["shape"], h["position"], v)


## Sparks (on metal) or a puff of dust at `p`, thrown out along `normal`.
func _effect(p: Vector3, normal: Vector3, metal: bool) -> void:
	if _effects >= MAX_EFFECTS:
		return
	var fx := CPUParticles3D.new()
	fx.top_level = true
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 10 if metal else 6
	fx.lifetime = 0.35 if metal else 1.0
	fx.mesh = _spark_mesh() if metal else _dust_mesh()
	fx.direction = Vector3.UP
	fx.spread = 55.0 if metal else 35.0
	fx.initial_velocity_min = 3.0 if metal else 0.8
	fx.initial_velocity_max = 9.0 if metal else 2.5
	fx.gravity = Vector3(0.0, -9.8 if metal else -0.6, 0.0)
	fx.damping_min = 0.0 if metal else 1.5
	fx.damping_max = 0.0 if metal else 2.5
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 if metal else 0.4))
	curve.add_point(Vector2(1.0, 0.2 if metal else 1.0))
	fx.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	fx.color_ramp = ramp
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx)
	var n := normal if normal.length_squared() > 0.5 else Vector3.UP
	fx.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, n)) if n.dot(Vector3.UP) > -0.99 else Basis.FLIP_Y, p + n * 0.05)
	fx.emitting = true
	_effects += 1
	fx.finished.connect(func() -> void:
		_effects -= 1
		fx.queue_free())


func _process(delta: float) -> void:
	for g in _flashes.size():
		_flash_t[g] -= delta
		var on := _flash_t[g] > 0.0
		_flashes[g].visible = on
		if on:
			_flashes[g].scale = Vector3.ONE * _rng.randf_range(0.7, 1.2)
	_draw_tracers()


## Each round: a quad from its head back TRACER_LENGTH along its path, turned to face the camera and padded by the
## half width all round, the soft dot texture stretched over it: a glowing streak, or a glowing dot seen end-on.
func _draw_tracers() -> void:
	_tracer_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if _rounds.is_empty() or cam == null:
		return
	var eye := cam.global_position
	var ahead := Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	_tracer_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: Array in _rounds:
		var v: Vector3 = r[1]
		var head: Vector3 = r[0] + v * ahead
		var d := v.normalized()
		var tail := head - d * minf(TRACER_LENGTH, (r[2] + ahead) * v.length())    # not behind the muzzle
		var look := (head - eye).normalized()
		var w := maxf(TRACER_WIDTH, eye.distance_to(head) * TRACER_ANGLE)
		var along := d - look * d.dot(look)                 # the path as seen from the camera
		along = along.normalized() if along.length_squared() > 1e-6 else cam.global_basis.x
		var side := look.cross(along).normalized() * w
		along *= w
		var quad := [[head + along + side, Vector2(1, 0)], [head + along - side, Vector2(0, 0)],
				[tail - along - side, Vector2(0, 1)], [tail - along + side, Vector2(1, 1)]]
		for k: int in [0, 1, 2, 0, 2, 3]:
			_tracer_im.surface_set_uv(quad[k][1])
			_tracer_im.surface_add_vertex(quad[k][0])
	_tracer_im.surface_end()


func rounds_in_flight() -> int:
	return _rounds.size()


# ---------------------------------------------------------------- looks

## Star-shaped burst of fire, facing the camera.
static func _flash_mesh() -> Mesh:
	if _shared.has("flash"):
		return _shared["flash"]
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	q.material = _glow_material(Color(3.0, 2.0, 0.7), true)
	_shared["flash"] = q
	return q


static func _spark_mesh() -> Mesh:
	if _shared.has("spark"):
		return _shared["spark"]
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = _glow_material(Color(2.5, 1.8, 0.7), false)
	_shared["spark"] = q
	return q


static func _dust_mesh() -> Mesh:
	if _shared.has("dust"):
		return _shared["dust"]
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.62, 0.57, 0.48, 0.8)
	mat.albedo_texture = _dot(false)
	mat.roughness = 1.0
	q.material = mat
	_shared["dust"] = q
	return q


## Unshaded, added onto what is behind (colour over 1: it glows); `star`: a four-pointed burst, else a round dot;
## `billboard`: facing the camera (as a particle, the star as a mesh).
static func _glow_material(c: Color, star: bool, billboard := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if star else BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true   # the particles' colour ramp
	mat.albedo_color = c
	mat.albedo_texture = _dot(star)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _dot(star: bool) -> Texture2D:
	var key := "dot_%s" % star
	if _shared.has(key):
		return _shared[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 32.0 - 1.0
			var v := (y + 0.5) / 32.0 - 1.0
			var r := sqrt(u * u + v * v)
			var a := clampf(1.0 - r, 0.0, 1.0)
			if star:                        # bright core with four rays
				a = clampf(1.0 - r * 2.2, 0.0, 1.0) + clampf(1.0 - absf(u) * 9.0, 0.0, 1.0) * (1.0 - absf(v)) \
						+ clampf(1.0 - absf(v) * 9.0, 0.0, 1.0) * (1.0 - absf(u))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * a * 1.5, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_shared[key] = tex
	return tex
