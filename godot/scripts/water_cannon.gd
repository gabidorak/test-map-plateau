extends Node3D
## Roof water cannon of the fire truck (scripts/fire_truck.gd): while `firing`, the nozzle (`nozzle`, a node at the tip
## of the barrel, which the truck turns and raises) shoots RATE packets of water a second at SPEED plus the truck's
## own speed. Each packet flies under gravity and air drag and is traced by a ray every physics tick; it is drawn as
## a bright core ribbon through the young packets and a widening mist puff on every packet. Where one lands: a splash
## of droplets, a wet patch on the ground (a fading decal) and, on the peer simulating the truck (`live`), the `hit`
## signal with the push the packet gives: game.gd shoves a vehicle (and puts out a burning one, car.gd douse), a
## player, a piece of debris, or soaks a light breakable prop until it falls over (breakables.gd soak). A water roar
## plays at the nozzle and a splatter where the jet lands.
## Remote copies of the truck spray the same jet from its LAN state, for show only.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")

const SPEED := 34.0                         # m/s out of the nozzle...
const DRAG := 0.15                          # ...slowed by the air (1/s): ~80 m of reach at 38°
const G := 9.8
const RATE := 30.0                          # packets per second
const LIFE := 5.0                           # s
const SPREAD := 0.012                       # rad, scatter of each packet
const PUSH := 300.0                         # N·s a packet gives what it hits at full speed: ~9,000 N for the jet,
											# about four times a real one; a braked car's tyres still hold it
const MAX_DV := 3.0                         # m/s, the most a packet changes the speed of a light body
const MASK := Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.DEBRIS | Layers.REMOTE_PLAYER
const CORE_AGE := 1.5                       # s: the solid-looking core ribbon, then mist only
const CORE_WIDTH := Vector2(0.09, 0.5)      # m, ribbon half width at the nozzle and at CORE_AGE
const MIST_SIZE := Vector2(0.12, 1.1)       # m, mist puff half size at the nozzle and at LIFE
const CORE_ANGLE := 0.003                   # rad: the ribbon is at least this wide seen from the camera (far jets)
const COLOR := Color(0.86, 0.93, 1.0)
const MAX_DROPS := 400                      # splash droplets at once
const DROP_LIFE := 0.6                      # s
const MAX_WET := 20                         # wet patches on the ground at once...
const WET_LIFE := 25.0                      # s, ...drying out over this
const WET_SIZE := 2.4                       # m

## A packet of a `live` cannon hit `collider` (its shape `shape`) at `point`, giving it `impulse` (N·s).
signal hit(collider: Object, shape: int, point: Vector3, impulse: Vector3)
## A packet landed at `point`, live or not (a remote copy's too): the host's fires judge the water from these
## (scripts/online/fires.gd), each truck's jet flown from the states it gets.
signal splashed(point: Vector3)

var firing := false
var live := true                            # its hits count (the truck is simulated here)
var nozzle: Node3D                          # tip of the barrel, +Z out of it (set by the truck)
var packets_fired := 0
var hits := 0                               # packets that hit something (on this peer, live or not)

var _packets: Array = []                    # [position, velocity, age, sequence number]
var _seq := 0
var _cool := 0.0                            # s until the next packet goes
var _drops: Array = []                      # splash droplets: [position, velocity, age]
var _wet: Array[Decal] = []
var _wet_t: Array[float] = []               # s each patch has been drying
var _wet_next := 0
var _mesh: MeshInstance3D
var _im := ImmediateMesh.new()
var _roar: AudioStreamPlayer3D              # at the nozzle
var _splatter: AudioStreamPlayer3D          # where the jet lands
var _roar_gain := 0.0
var _land := Vector3.INF                    # where the jet lands lately (smoothed), INF: nowhere yet
var _land_t := 0.0                          # s since a packet last landed
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()

static var _shared := {}


func _ready() -> void:
	name = "WaterCannon"
	_query.collision_mask = MASK
	_query.hit_back_faces = false
	var own: Array[RID] = []
	for b: CollisionObject3D in get_parent().bodies():     # the truck's own bodies (car.gd)
		own.append(b.get_rid())
	_query.exclude = own
	_mesh = MeshInstance3D.new()
	_mesh.name = "Jet"
	_mesh.top_level = true
	_mesh.mesh = _im
	_mesh.material_override = _water_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.custom_aabb = AABB(Vector3(-1e4, -1e3, -1e4), Vector3(2e4, 4e3, 2e4))    # water anywhere
	add_child(_mesh)
	_mesh.global_transform = Transform3D.IDENTITY
	_roar = AudioStreamPlayer3D.new()
	_roar.stream = VehicleAudio.one_shot("gush")
	_roar.unit_size = 10.0
	_roar.max_distance = 150.0
	_roar.pitch_scale = 1.35                # a tighter hiss than a broken hydrant
	_roar.volume_db = -80.0
	add_child(_roar)
	_splatter = AudioStreamPlayer3D.new()
	_splatter.stream = VehicleAudio.one_shot("gush")
	_splatter.top_level = true
	_splatter.unit_size = 8.0
	_splatter.max_distance = 120.0
	_splatter.pitch_scale = 0.8
	_splatter.volume_db = -80.0
	add_child(_splatter)


## Packets in the air.
func packets_in_flight() -> int:
	return _packets.size()


## Where the jet lands lately (global), or null when it has not landed for a while.
func landing() -> Variant:
	return _land if _land != Vector3.INF and _land_t < 0.5 else null


func _physics_process(delta: float) -> void:
	_cool -= delta
	if firing and nozzle:
		while _cool <= 0.0:
			_fire(-_cool)
			_cool += 1.0 / RATE
	else:
		_cool = maxf(_cool, 0.0)            # the first packet goes as soon as the trigger is pressed
	_fly(delta)
	_land_t += delta


## One packet out of the nozzle, fired `late` s ago (a tick may fire two).
func _fire(late: float) -> void:
	var truck := get_parent() as RigidBody3D
	var xf := nozzle.global_transform
	var dir := xf.basis.z.normalized()
	dir = (dir + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * SPREAD).normalized()
	var v := dir * SPEED + truck.linear_velocity
	_packets.append([xf.origin + v * late, v, late, _seq])
	_seq += 1
	packets_fired += 1


## Moves the packets on by a tick; those hitting something splash there.
func _fly(delta: float) -> void:
	if _packets.is_empty() and _drops.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _packets.size():
		var p: Array = _packets[i]
		var v: Vector3 = p[1]
		var q: Vector3 = p[0] + v * delta
		_query.from = p[0]
		_query.to = q
		var h := space.intersect_ray(_query)
		if h:
			_packets.remove_at(i)
			_impact(h, v)
			continue
		v.y -= G * delta
		v -= v * DRAG * delta
		p[0] = q
		p[1] = v
		p[2] += delta
		if p[2] > LIFE:
			_packets.remove_at(i)
			continue
		i += 1
	i = 0
	while i < _drops.size():
		var d: Array = _drops[i]
		d[1].y -= G * delta
		d[0] += d[1] * delta
		d[2] += delta
		if d[2] > DROP_LIFE:
			_drops.remove_at(i)
			continue
		i += 1


func _impact(h: Dictionary, v: Vector3) -> void:
	var p: Vector3 = h["position"]
	var n: Vector3 = h["normal"]
	hits += 1
	_land = p if _land == Vector3.INF or _land_t > 0.5 else _land.lerp(p, 0.15)
	_land_t = 0.0
	_splash(p, n, v)
	var collider: Object = h["collider"]
	if collider is StaticBody3D and (collider as CollisionObject3D).collision_layer & Layers.SOLID:
		_wet_patch(p, n)
	splashed.emit(p)
	if live:
		hit.emit(collider, h["shape"], p, v * (PUSH / SPEED))


## Droplets thrown back off the surface at `p` (normal `n`) by a packet arriving at `v`.
func _splash(p: Vector3, n: Vector3, v: Vector3) -> void:
	var bounce := (v - 2.0 * v.dot(n) * n) * 0.25 + n * 1.5
	for k in 4:
		if _drops.size() >= MAX_DROPS:
			_drops.pop_front()
		var dv := bounce + Vector3(_rng.randfn(), _rng.randfn() * 0.5 + 0.5, _rng.randfn()) * 2.0
		_drops.append([p + n * 0.05, dv, _rng.randf() * 0.15])


## Darkens the ground around `p`: a new patch unless a fresh one is close by, which is refreshed instead.
func _wet_patch(p: Vector3, n: Vector3) -> void:
	if n.y < 0.5:
		return
	for k in _wet.size():
		if _wet_t[k] < WET_LIFE * 0.8 and _wet[k].global_position.distance_to(p) < WET_SIZE * 0.4:
			_wet_t[k] = minf(_wet_t[k], 1.0)
			return
	var decal: Decal
	if _wet.size() < MAX_WET:
		decal = Decal.new()
		decal.name = "Wet"
		decal.top_level = true
		decal.size = Vector3(WET_SIZE, 1.2, WET_SIZE)
		decal.texture_albedo = _wet_texture()
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		add_child(decal)
		_wet.append(decal)
		_wet_t.append(0.0)
		_wet_next = _wet.size() % MAX_WET
	else:
		decal = _wet[_wet_next]
		_wet_t[_wet_next] = 0.0
		_wet_next = (_wet_next + 1) % MAX_WET
	decal.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p)
	decal.visible = true
	decal.modulate.a = 1.0


func _process(delta: float) -> void:
	_roar_gain = move_toward(_roar_gain, 1.0 if firing else 0.0, delta / (0.15 if firing else 0.5))
	_set_loop(_roar, _roar_gain, -2.0)
	var landing_gain := clampf(1.0 - _land_t * 2.0, 0.0, 1.0) * (1.0 if hits > 0 else 0.0)
	if _land != Vector3.INF:
		_splatter.global_position = _land
	_set_loop(_splatter, landing_gain, -6.0)
	for k in _wet.size():
		if not _wet[k].visible:
			continue
		_wet_t[k] += delta
		_wet[k].modulate.a = clampf(1.0 - (_wet_t[k] - WET_LIFE * 0.4) / (WET_LIFE * 0.6), 0.0, 1.0)
		_wet[k].visible = _wet_t[k] < WET_LIFE
	_draw()


static func _set_loop(p: AudioStreamPlayer3D, gain: float, db: float) -> void:
	if gain > 0.0 and not p.playing:
		p.play()
	elif gain == 0.0 and p.playing:
		p.stop()
	p.volume_db = db + linear_to_db(maxf(gain, 0.0001))


# ---------------------------------------------------------------- drawing

## Core ribbon through the young packets (broken where a packet hit something), a mist puff on every packet and a
## dot on every droplet; all facing the camera, the packets moved on to this frame.
func _draw() -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or (_packets.is_empty() and _drops.is_empty()):
		return
	var eye := cam.global_position
	var ahead := Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# ribbon: from the nozzle through the packets, youngest first
	var prev := Vector3.INF
	var prev_seq := -2
	var prev_w := CORE_WIDTH.x
	if firing and nozzle:
		prev = nozzle.global_position
		prev_seq = _seq
	for k in range(_packets.size() - 1, -1, -1):
		var pk: Array = _packets[k]
		var age: float = pk[2] + ahead
		if age > CORE_AGE:
			break
		var p: Vector3 = pk[0] + pk[1] * ahead
		var w := maxf(lerpf(CORE_WIDTH.x, CORE_WIDTH.y, age / CORE_AGE), eye.distance_to(p) * CORE_ANGLE)
		if pk[3] == prev_seq - 1 and prev != Vector3.INF:
			var a := 0.9 * (1.0 - age / CORE_AGE * 0.8)
			_strip(prev, p, prev_w, w, eye, Color(COLOR, a))
		prev = p
		prev_seq = pk[3]
		prev_w = w
	# mist puffs, densest near the nozzle, fading and swelling with age
	for pk: Array in _packets:
		var age: float = pk[2] + ahead
		var t := clampf(age / LIFE, 0.0, 1.0)
		var s := lerpf(MIST_SIZE.x, MIST_SIZE.y, sqrt(t))
		_puff(pk[0] + pk[1] * ahead, s, eye, Color(COLOR, 0.55 * (1.0 - t) * smoothstep(0.0, 0.08, age)))
	for d: Array in _drops:
		var t: float = d[2] / DROP_LIFE
		_puff(d[0] + d[1] * ahead, lerpf(0.1, 0.32, t), eye, Color(COLOR, 0.6 * (1.0 - t)))
	_im.surface_end()


## Quad from a (half width wa) to b (wb) turned to face the camera at `eye`, the soft profile across it.
func _strip(a: Vector3, b: Vector3, wa: float, wb: float, eye: Vector3, c: Color) -> void:
	var along := b - a
	if along.length_squared() < 1e-8:
		return
	var look := ((a + b) * 0.5 - eye).normalized()
	var side := look.cross(along).normalized()
	var quad := [[a + side * wa, Vector2(0, 0.5)], [a - side * wa, Vector2(1, 0.5)], [b - side * wb, Vector2(1, 0.5)],
			[b + side * wb, Vector2(0, 0.5)]]
	for k: int in [0, 1, 2, 0, 2, 3]:
		_im.surface_set_color(c)
		_im.surface_set_uv(quad[k][1])
		_im.surface_add_vertex(quad[k][0])


## Soft round puff of half size `s` at `p`, facing the camera at `eye`.
func _puff(p: Vector3, s: float, eye: Vector3, c: Color) -> void:
	if c.a <= 0.01:
		return
	var look := (p - eye).normalized()
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	var up := right.cross(look)
	right *= s
	up *= s
	var quad := [[p - right - up, Vector2(0, 1)], [p + right - up, Vector2(1, 1)], [p + right + up, Vector2(1, 0)],
			[p - right + up, Vector2(0, 0)]]
	for k: int in [0, 1, 2, 0, 2, 3]:
		_im.surface_set_color(c)
		_im.surface_set_uv(quad[k][1])
		_im.surface_add_vertex(quad[k][0])


static func _water_material() -> StandardMaterial3D:
	if _shared.has("mat"):
		return _shared["mat"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = _soft_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shared["mat"] = mat
	return mat


## White soft blob, a little lumpy (spray, not a ball).
static func _soft_texture() -> Texture2D:
	if _shared.has("soft"):
		return _shared["soft"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4
	noise.frequency = 0.09
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 32.0 - 1.0
			var v := (y + 0.5) / 32.0 - 1.0
			var r := sqrt(u * u + v * v) * (1.0 + 0.3 * noise.get_noise_2d(x, y))
			var a := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	var tex := ImageTexture.create_from_image(img)
	_shared["soft"] = tex
	return tex


## Dark blotch with a ragged soft edge: the wet patch decal.
static func _wet_texture() -> Texture2D:
	if _shared.has("wet"):
		return _shared["wet"]
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 8
	noise.frequency = 0.04
	for y in 128:
		for x in 128:
			var u := (x + 0.5) / 64.0 - 1.0
			var v := (y + 0.5) / 64.0 - 1.0
			var r := sqrt(u * u + v * v) + 0.35 * noise.get_noise_2d(x, y)
			var a := clampf((0.85 - r) / 0.3, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.03, 0.035, 0.04, 0.5 * a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_shared["wet"] = tex
	return tex
