extends CharacterBody3D
## One zombie of Escape from Plateau (scripts/escape/zombies.gd makes and runs them): a toy figure of the plateau's
## people gone wrong, grey-green skin, torn clothes, arms reaching out and eyes glowing red through the fog.
## - Simulated on the host (or solo, or the dedicated server): zombies.gd gives it its senses (think) and calls step()
##   each tick it is awake. It wanders round where it rose, walks to a noise it heard (a gunshot), chases the player it
##   senses, swings once within reach (zombies.gd then hurts the player, or the vehicle they are in), staggers when
##   hit, and steps aside a moment when a wall stops it. Three kinds: shamblers, runners (faster, frailer), brutes
##   (big, slow, hard to put down).
## - On the other peers it is posed from the host's states (`remote`, push_state), INTERP s in the past, between the two
##   states around that time on the host's clock.
## Everywhere it is animated from what it does and how fast it goes (shamble, run, swing, stagger, climb out of the
## ground, fall dead), and its body blocks the players and takes their rounds (layer ZOMBIE). A dead one lies a while,
## then sinks into the ground.

const Layers = preload("res://scripts/physics_layers.gd")

enum { IDLE, WALK, CHASE, ATTACK, STAGGER, RISE, DEAD }
enum { SHAMBLER, RUNNER, BRUTE }

## kind -> health, walking and chasing speeds (m/s), damage per swing, size
const KINDS := {
	SHAMBLER: {"health": 100.0, "walk": 1.0, "chase": 2.6, "damage": 12.0, "scale": 1.0},
	RUNNER: {"health": 70.0, "walk": 1.4, "chase": 5.3, "damage": 9.0, "scale": 0.95},
	BRUTE: {"health": 340.0, "walk": 0.9, "chase": 2.2, "damage": 26.0, "scale": 1.32},
}
const RISE_TIME := 1.6                      # s to climb out of the ground
const WINDUP := 0.45                        # s from the start of a swing to the blow
const SWING := 1.05                         # s a swing lasts
const STAGGER_TIME := 0.35                  # s a hit holds it back
const REACH := 1.45                         # m between centres (horizontally) to start a swing...
const HIT_REACH := 2.1                      # ...and still this near at the blow for it to land
const LIE_TIME := 9.0                       # s a dead one lies...
const SINK_TIME := 2.5                      # ...then sinks into the ground
const INTERP := 0.15                        # s, remote ones shown this late
const ACCEL := 9.0                          # m/s² towards the wanted velocity
const SEEN := 120.0                         # m from the camera beyond which the body is not drawn
const SKIN := [Color(0.47, 0.56, 0.42), Color(0.55, 0.58, 0.47), Color(0.42, 0.5, 0.46), Color(0.6, 0.6, 0.52)]
const CLOTHES := [Color(0.36, 0.3, 0.27), Color(0.22, 0.28, 0.42), Color(0.5, 0.18, 0.16), Color(0.3, 0.38, 0.25),
		Color(0.62, 0.58, 0.5), Color(0.16, 0.16, 0.18), Color(0.55, 0.42, 0.2), Color(0.42, 0.45, 0.5)]
const TROUSERS := [Color(0.18, 0.2, 0.26), Color(0.28, 0.26, 0.22), Color(0.12, 0.12, 0.13)]

var zid := 0
var kind := SHAMBLER
var state := RISE
var health := 100.0
var remote := false                         # posed from the host's states
var guard := false                          # host: watches a survivor's hideout (never despawned)
var home := Vector3.ZERO                    # host: where it wanders round
var goal := Vector3.ZERO                    # host: where it walks to (WALK), the last place its target was seen
var target := 0                             # host: the peer it chases (0: nobody)
var audio: Node                             # escape_audio.gd, or null (dedicated server)
var last_seen := 0.0                        # remote: when its last state came (our clock)
var awake := true                           # host: thinking and moving (a player within zombies.gd ACTIVE)

var _spec: Dictionary
var _t_state := 0.0                         # s in the current state
var _think_t := 0.0
var _hit_done := false
var _avoid_t := 0.0                         # s left stepping aside
var _avoid_side := 1.0
var _stuck_t := 0.0
var _yaw := 0.0
var _phase := 0.0
var _speed := 0.0                           # m/s shown (animation)
var _last_pos := Vector3.ZERO
var _fall := 1.0                            # dead: falls backwards (1) or forwards (-1)
var _fling := Vector3.ZERO                  # dead: thrown by a vehicle, m/s
var _groan_t := 0.0
var _tilt := 0.0                            # its head's lean, its own
var _buf_t := PackedFloat64Array()          # remote: states' times (host clock)
var _buf_p: Array[Vector3] = []
var _buf_y := PackedFloat32Array()
var _buf_s := PackedInt32Array()
var _rng := RandomNumberGenerator.new()

var _rig: Node3D
var _hips: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _shape: CollisionShape3D

static var _shared := {}


## Kind, look (`seed`) and whether it is posed from the host's states; before adding it to the tree.
func setup(id: int, zombie_kind: int, look: int, is_remote: bool) -> void:
	zid = id
	kind = zombie_kind
	remote = is_remote
	name = "Zombie%d" % id
	_spec = KINDS[kind]
	health = _spec["health"]
	_rng.seed = look
	_tilt = _rng.randf_range(-0.35, 0.35)
	_groan_t = _rng.randf_range(1.0, 8.0)
	_think_t = _rng.randf_range(0.0, 0.4)
	collision_layer = Layers.ZOMBIE
	collision_mask = 0 if remote else Layers.SOLID | Layers.BOUNDARY | Layers.PROPS | Layers.VEGETATION \
			| Layers.VEHICLES | Layers.ZOMBIE | Layers.PLAYER | Layers.REMOTE_PLAYER
	floor_max_angle = 0.9
	floor_snap_length = 0.6
	safe_margin = 0.02
	_build(look)


func _ready() -> void:
	_last_pos = global_position
	_yaw = rotation.y


# ---------------------------------------------------------------- host

## A tick of its own (host), `delta` s since the last one; `mgr` is zombies.gd.
func step(delta: float, mgr: Node) -> void:
	if state == DEAD:
		return
	_t_state += delta
	if state == RISE:
		if _t_state >= RISE_TIME:
			set_state(IDLE)
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(0.25, 0.45)
		mgr.think(self)
	var want := Vector3.ZERO
	var speed := 0.0
	match state:
		CHASE:
			var tp: Variant = mgr.target_pos(target)
			if tp == null:
				set_state(IDLE)
			else:
				goal = tp
				want = tp - global_position
				var flat := Vector2(want.x, want.z).length()
				if flat < REACH + mgr.target_reach(target) and absf(want.y) < 1.9:
					set_state(ATTACK)
					want = Vector3.ZERO
				else:
					speed = _spec["chase"]
		WALK:
			want = goal - global_position
			if Vector2(want.x, want.z).length() < 1.5:
				set_state(IDLE)
				want = Vector3.ZERO
			else:
				speed = _spec["walk"]
		ATTACK:
			var tp: Variant = mgr.target_pos(target)
			if tp != null:
				var d: Vector3 = tp - global_position
				_turn_to(d, delta * 3.0)
				if not _hit_done and _t_state >= WINDUP:
					_hit_done = true
					if Vector2(d.x, d.z).length() < HIT_REACH + mgr.target_reach(target) and absf(d.y) < 2.0:
						mgr.swing_landed(self, target)
			if _t_state >= SWING:
				set_state(CHASE if target != 0 else IDLE)
		STAGGER:
			if _t_state >= STAGGER_TIME:
				set_state(CHASE if target != 0 else IDLE)
	want.y = 0.0
	if want.length_squared() > 0.0001:
		want = want.normalized()
		if _avoid_t > 0.0:
			_avoid_t -= delta
			want = want.rotated(Vector3.UP, _avoid_side * 1.15)
	want += mgr.separation(self)
	var hv := want.normalized() * speed if speed > 0.0 and want.length_squared() > 0.0001 else Vector3.ZERO
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2(hv.x, hv.z), ACCEL * delta)
	velocity.x = h.x
	velocity.z = h.y
	velocity.y = -1.0 if is_on_floor() else velocity.y - 9.8 * delta
	var k := delta / get_physics_process_delta_time()   # several ticks at once (asleep, far)
	velocity *= k
	var start := global_position
	move_and_slide()
	velocity /= k
	var moved := Vector2(global_position.x - start.x, global_position.z - start.z).length() / maxf(delta, 0.001)
	if speed > 0.5 and moved < speed * 0.3:
		_stuck_t += delta
		if _stuck_t > 0.5:
			_stuck_t = 0.0
			_avoid_t = _rng.randf_range(0.8, 1.6)
			_avoid_side = -_avoid_side if _rng.randf() < 0.6 else _avoid_side
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	if hv.length_squared() > 0.04:
		_turn_to(hv, delta * 6.0)


func _turn_to(d: Vector3, rate: float) -> void:
	if Vector2(d.x, d.z).length_squared() < 1e-4:
		return
	_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), minf(rate, 1.0))
	rotation.y = _yaw


## Host: what it does now (the others see it in its states).
func set_state(s: int) -> void:
	if s == state:
		return
	var was := state
	state = s
	_t_state = 0.0
	_hit_done = false
	if s == ATTACK and audio:
		audio.play_at("snarl", global_position + Vector3.UP * 1.6, -2.0, _rng.randf_range(0.85, 1.15), 8.0, 60.0)
	elif s == CHASE and was in [IDLE, WALK] and audio and _rng.randf() < 0.5:
		_groan(2.0)


## Host: hit by `damage` coming along `dir`; true when it killed it.
func take_hit(damage: float, dir: Vector3, stagger := true) -> bool:
	if state == DEAD:
		return false
	health -= damage
	if health <= 0.0:
		return true
	if stagger and state != RISE and (kind != BRUTE or damage >= 40.0):
		set_state(STAGGER)
		velocity += Vector3(dir.x, 0.0, dir.z).normalized() * (1.5 if kind != BRUTE else 0.5)
	return false


# ---------------------------------------------------------------- everyone

## Dead: falls away from `dir` (where the blow came from to it), thrown at `fling` m/s by a vehicle.
func die(dir: Vector3, fling := Vector3.ZERO) -> void:
	if state == DEAD:
		return
	state = DEAD
	_t_state = 0.0
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	var fwd := -global_basis.z
	_fall = 1.0 if fwd.dot(dir) < 0.0 else -1.0
	_fling = fling
	if audio:
		audio.play_at("zombie_die", global_position + Vector3.UP * 1.5, 0.0, _rng.randf_range(0.85, 1.15), 8.0, 70.0)


## True once it has lain and sunk away.
func gone() -> bool:
	return state == DEAD and _t_state > LIE_TIME + SINK_TIME


## True when `point` (global) is on its head.
func is_head(point: Vector3) -> bool:
	return point.y - global_position.y > 1.42 * float(_spec["scale"])


## Remote: a state from the host at `t` on its clock.
func push_state(t: float, pos: Vector3, yaw: float, s: int) -> void:
	if not _buf_t.is_empty() and t <= _buf_t[-1]:
		return
	if _buf_t.is_empty():
		global_position = pos
		rotation.y = yaw
		_last_pos = pos
	_buf_t.append(t)
	_buf_p.append(pos)
	_buf_y.append(yaw)
	_buf_s.append(s)
	if _buf_t.size() > 8:
		_buf_t = _buf_t.slice(1)
		_buf_p.pop_front()
		_buf_y = _buf_y.slice(1)
		_buf_s = _buf_s.slice(1)


func _process(delta: float) -> void:
	if remote and state != DEAD and not _buf_t.is_empty():
		_play_back(get_parent().clock() - INTERP)
	if state == DEAD:
		_t_state += delta
		_dead_motion(delta)
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_squared_to(global_position) < SEEN * SEEN
	_rig.visible = near
	var moved := global_position - _last_pos
	_last_pos = global_position
	var v := Vector2(moved.x, moved.z).length() / maxf(delta, 0.001)
	_speed = lerpf(_speed, minf(v, 8.0), 1.0 - exp(-10.0 * delta))
	if near:
		_animate(delta)
		_groan_t -= delta
		if _groan_t <= 0.0 and state not in [DEAD, RISE]:
			_groan_t = _rng.randf_range(4.0, 11.0)
			if cam.global_position.distance_to(global_position) < 45.0:
				_groan(0.0)


func _groan(db: float) -> void:
	if audio:
		audio.play_at("groan%d" % (1 + _rng.randi() % 3), global_position + Vector3.UP * 1.6, db - 3.0,
				_rng.randf_range(0.8, 1.15) / float(_spec["scale"]), 6.0, 55.0)


## Remote: posed at time `t` on the host's clock, between the two states around it (the nearest one out of their span).
func _play_back(t: float) -> void:
	var n := _buf_t.size()
	var a := n - 1
	var b := n - 1
	var w := 0.0
	if t <= _buf_t[0]:
		a = 0
		b = 0
	elif t < _buf_t[n - 1]:
		b = n - 1
		while _buf_t[b - 1] > t:
			b -= 1
		a = b - 1
		w = (t - _buf_t[a]) / maxf(_buf_t[b] - _buf_t[a], 0.001)
	global_position = _buf_p[a].lerp(_buf_p[b], w)
	rotation.y = lerp_angle(_buf_y[a], _buf_y[b], w)
	var s := _buf_s[a]
	if s != state:
		if s == ATTACK and audio:
			audio.play_at("snarl", global_position + Vector3.UP * 1.6, -2.0, _rng.randf_range(0.85, 1.15), 8.0, 60.0)
		state = s
		_t_state = 0.0


## Dead: thrown, falling over, lying, then sinking.
func _dead_motion(delta: float) -> void:
	if _fling.length_squared() > 0.01:
		global_position += _fling * delta
		_fling.y -= 9.8 * delta
		_fling.x *= 1.0 - 1.5 * delta
		_fling.z *= 1.0 - 1.5 * delta
		if _fling.y < 0.0 and _ground_below(delta):
			_fling = Vector3.ZERO


## True when the ground is within this tick's fall (it lands).
func _ground_below(delta: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5,
			global_position + Vector3.DOWN * (0.1 - _fling.y * delta), Layers.SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		global_position.y = hit["position"].y
		return true
	return false


# ---------------------------------------------------------------- looks

func _animate(delta: float) -> void:
	var sc: float = _spec["scale"]
	var run := _speed > 3.2
	_phase += delta * (1.4 + _speed * (2.6 if run else 2.0)) / sc
	var amp := clampf(_speed / 2.2, 0.12, 1.0)
	var stride := sin(_phase) * amp * (0.75 if run else 0.5)
	_legs[0].rotation.x = stride
	_legs[1].rotation.x = -stride
	var lean := 0.42 if run else 0.2
	var arms := -1.35 + sin(_phase * 0.5) * 0.12
	var flail := sin(_phase) * (0.55 if run else 0.1)
	_rig.position = Vector3.ZERO
	_rig.rotation = Vector3.ZERO
	match state:
		ATTACK:
			var p := _t_state / SWING
			var w := _t_state / WINDUP
			arms = lerpf(-1.35, -2.5, minf(w, 1.0)) if w < 1.0 else lerpf(-2.5, -0.5, minf((_t_state - WINDUP) / 0.2, 1.0))
			lean = 0.2 + (0.35 if w >= 1.0 and p < 0.8 else 0.0)
			flail = 0.0
		STAGGER:
			lean = -0.4 * (1.0 - _t_state / STAGGER_TIME)
		RISE:
			var p := clampf(_t_state / RISE_TIME, 0.0, 1.0)
			_rig.position.y = lerpf(-1.8 * sc, 0.0, 1.0 - pow(1.0 - p, 2.0))
			_rig.rotation.z = sin(_t_state * 23.0) * 0.06 * (1.0 - p)
			arms = -2.6 + p * 1.25
		DEAD:
			var p := clampf(_t_state / 0.55, 0.0, 1.0)
			_rig.rotation.x = _fall * PI * 0.5 * p * p
			_rig.position.y = 0.12 * p - maxf(_t_state - LIE_TIME, 0.0) / SINK_TIME * 0.9
			arms = -1.35 - p * 0.6
			stride = 0.0
			_legs[0].rotation.x = 0.2 * p
			_legs[1].rotation.x = -0.15 * p
	_hips.rotation = Vector3(lean, 0.0, sin(_phase) * 0.07 * amp)
	_arms[0].rotation = Vector3(arms + flail, 0.0, 0.12)
	_arms[1].rotation = Vector3(arms - flail, 0.0, -0.12)
	_head.rotation = Vector3(0.15, sin(_phase * 0.37) * 0.15, _tilt + sin(_phase * 0.5) * 0.08)


func _build(look: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = look * 7919 + 13
	var sc: float = _spec["scale"]
	var skin := _mat("skin%d" % (look % SKIN.size()), SKIN[look % SKIN.size()], 0.85)
	var shirt := _mat("shirt%d" % rng.randi_range(0, CLOTHES.size() - 1), CLOTHES[rng.randi_range(0, CLOTHES.size() - 1)], 0.9)
	var legs := _mat("legs%d" % (look % TROUSERS.size()), TROUSERS[look % TROUSERS.size()], 0.9)
	var blood := _mat("blood", Color(0.35, 0.04, 0.03), 0.6)
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.scale = Vector3.ONE * sc
	add_child(_rig)
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, 0.9, 0.0)
		_rig.add_child(hip)
		_part(hip, _capsule(0.1, 0.92), legs, Vector3(0.0, -0.44, 0.0))
		_legs.append(hip)
	_hips = Node3D.new()
	_hips.position = Vector3(0.0, 0.9, 0.0)
	_rig.add_child(_hips)
	_part(_hips, _capsule(0.25, 0.82), shirt, Vector3(0.0, 0.33, 0.0))
	_part(_hips, _box(Vector3(0.2, 0.16, 0.05)), blood, Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.25, 0.5), -0.24))
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.76, -0.03)
	_hips.add_child(_head)
	_part(_head, _sphere(0.17), skin, Vector3(0.0, 0.08, 0.0))
	var eye := _eye_mat()
	for side: float in [-1.0, 1.0]:
		var e := _part(_head, _sphere(0.032), eye, Vector3(0.065 * side, 0.11, -0.15))
		e.visibility_range_end = 70.0
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_part(_head, _box(Vector3(0.12, 0.03, 0.04)), blood, Vector3(0.0, 0.0, -0.15))      # the mouth
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.3 * side, 0.6, 0.0)
		_hips.add_child(shoulder)
		_part(shoulder, _capsule(0.075, 0.68), shirt if rng.randf() < 0.6 else skin, Vector3(0.0, -0.3, 0.0))
		_part(shoulder, _sphere(0.08), skin, Vector3(0.0, -0.66, 0.0))
		_arms.append(shoulder)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32 * sc
	cap.height = 1.75 * sc
	_shape.shape = cap
	_shape.position = Vector3(0.0, 0.875 * sc, 0.0)
	add_child(_shape)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = SEEN
	parent.add_child(mi)
	return mi


static func _mat(key: String, c: Color, rough: float) -> StandardMaterial3D:
	if _shared.has(key):
		return _shared[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_shared[key] = m
	return m


## The eyes: glowing red, through the fog.
static func _eye_mat() -> StandardMaterial3D:
	if _shared.has("eye"):
		return _shared["eye"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.7, 0.12, 0.04)
	m.disable_fog = true
	_shared["eye"] = m
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var key := "cap%.3f_%.3f" % [r, h]
	if not _shared.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 10
		m.rings = 4
		_shared[key] = m
	return _shared[key]


static func _sphere(r: float) -> SphereMesh:
	var key := "sph%.3f" % r
	if not _shared.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 6
		_shared[key] = m
	return _shared[key]


static func _box(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _shared.has(key):
		var m := BoxMesh.new()
		m.size = size
		_shared[key] = m
	return _shared[key]
