extends "res://scripts/car.gd"
## Ridable toy horse (Car.SPECS "horse"), built from primitive shapes at runtime like the biplane: a chestnut with a
## black mane and tail, a white blaze and hind socks, saddle, saddle cloth, stirrups and reins, and its rider in the
## player's colour. game.gd parks it from the vehicle menu and gets on it like a car (E), but off it with E too: Space
## jumps. LAN games sync it like a car (net_state also carries whether it is in the air).
## Keys while riding (the Settings actions, scripts/settings.gd; defaults on physical positions): W canters, W with
## Shift gallops, S stops then backs up slowly, A / D turn (on the spot too), Space jumps, G neighs, R puts it back on
## its feet, V or the mouse wheel zoomed all the way in: the rider's view.
## Physics: one upright rigid body (only its yaw turns) that only collides with its barrel and its neck and head: the
## legs are drawn, not simulated. A spring on rays down from the front and the hind hooves holds it at leg height over
## the ground, so it steps up kerbs and low steps (STEP_UP) like a car's suspension; on the ground it eases its speed
## towards the gait's and does not slip sideways, in the air it flies on. A jump goes the higher the faster it runs
## (JUMP_UP) and carries a moving horse forward at least JUMP_FORWARD: from a canter its belly clears the map's 2 m mesh
## fences, from a trot the 1.6 m bar fences; the 3.5 m fences around pitches and high walls hold it.
## The legs move in the gait of the speed (walk, trot, canter, gallop; GAITS), stepping on the spot while it turns in
## place, tuck over a jump and fold under it when it is down; the body bobs and pitches with the gait, the slope and the
## jump, the rider leans forward at speed and over jumps, and the hooves clop on every footfall. Remote copies animate
## from how fast their pose moves. Its rounds-and-water health is the cars' (car.gd): at 0 the horse lies down (no fire,
## no smoke) until it gets up REPAIR_AFTER s later or after EXTINGUISH s of the fire truck's water. Vehicles do not
## knock props over with it (breakables.gd skips "knocks_props" = false).
## In deep water (scripts/water.gd) it swims: held with its back at the surface (SWIM_DRAFT), slowly (SWIM_SPEED), no
## jumps; the legs paddle in a walk.
## Frame: like the cars, +Z forward, +X its left, origin on the ground between the hooves.

const Biplane = preload("res://scripts/plane.gd")
const SWIM_DRAFT := 1.45                    # m of its legs and barrel under the surface while it swims
const SWIM_SPEED := 2.2                     # m/s
const MASS := 500.0                         # kg
const CANTER := 7.5                         # m/s with W...
const GALLOP := 13.0                        # ...and with Shift too
const BACK_SPEED := 0.9                     # m/s backing up: under car.gd REVERSE_VIEW_SPEED, the camera stays behind
const ACCEL := 4.0                          # m/s² speeding up...
const DECEL := 8.0                          # ...and slowing down
const SIDE_GRIP := 10.0                     # /s: sideways slip eased off this fast
const TURN_RATE := Vector2(2.2, 0.9)        # rad/s standing and at a gallop
const AIR_TURN := 0.25                      # share of it in the air
const STEP_UP := 0.6                        # m: ground this far above the hooves is stepped onto
const REACH := 0.3                          # m: the hooves within this of the ground stand on it
const RIDE_K := 150.0                       # spring (/s²) and damper (/s) holding the body at leg height
const RIDE_C := 24.0
const HOOF_Z := 0.68                        # front and hind hooves (ground rays), either side of the origin
const JUMP_UP := Vector3(3.2, 5.4, 6.0)     # m/s up for a jump standing, at a canter, at a gallop
const JUMP_FORWARD := 7.0                   # m/s ahead a moving horse jumps at least
const JUMP_BUFFER := 0.2                    # s a jump pressed before landing waits
const COYOTE := 0.12                        # s after leaving the ground a jump still takes off
const BODY_Y := 1.2                         # barrel centre height (the pose pivot)
const LEG_LENGTH := 1.15                    # hip to ground
## Per gait: stride (m), duty (share of the stride a hoof is on the ground), lift (knee flex in the air, rad), offsets
## (stride phase of the front left, front right, hind left, hind right footfalls), bob (m) and bobs per stride, rock
## (body pitch, rad).
const GAITS := {
	"walk": {"stride": 1.6, "duty": 0.62, "lift": 1.0, "offsets": [0.25, 0.75, 0.0, 0.5], "bob": 0.02, "bobs": 2.0,
			"rock": 0.0},
	"trot": {"stride": 2.7, "duty": 0.45, "lift": 1.4, "offsets": [0.0, 0.5, 0.5, 0.0], "bob": 0.05, "bobs": 2.0,
			"rock": 0.0},
	"canter": {"stride": 3.4, "duty": 0.4, "lift": 1.5, "offsets": [0.3, 0.55, 0.0, 0.3], "bob": 0.06, "bobs": 1.0,
			"rock": 0.07},
	"gallop": {"stride": 5.2, "duty": 0.32, "lift": 1.7, "offsets": [0.45, 0.58, 0.0, 0.12], "bob": 0.05, "bobs": 1.0,
			"rock": 0.06},
}
const GAIT_ORDER := ["stand", "walk", "trot", "canter", "gallop"]
const GAIT_SPEEDS := [0.2, 2.6, 5.6, 9.5]   # m/s from which the next gait takes over (±10 % either way)
const GAIT_NAMES := {"stand": "standing", "walk": "walk", "trot": "trot", "canter": "canter", "gallop": "gallop"}
const COLORS := {"coat": Color(0.66, 0.34, 0.15), "dark": Color(0.17, 0.1, 0.07), "hoof": Color(0.2, 0.19, 0.19),
		"white": Color(0.96, 0.94, 0.9), "eye": Color(0.04, 0.03, 0.03), "saddle": Color(0.4, 0.2, 0.09),
		"cloth": Color(0.12, 0.3, 0.78), "metal": Color(0.78, 0.79, 0.82), "nose": Color(0.2, 0.25, 0.35)}
const SEAT := Vector3(0.0, 0.47, -0.06)     # rider's seat, pose frame
const BIT := Vector3(0.09, -0.32, 0.36)     # left end of the bit, head frame (mirrored)
const HAND := Vector3(0.13, 0.32, 0.45)     # rider's left hand, rider frame (mirrored)

var on_ground := false
var swimming := false
var gait := "stand"
var _airborne := false                      # jumping or falling (LAN: from the state)
var _ground_y := NAN                        # under the hooves (mean of the front and the hind ones)
var _gap := 99.0                            # hooves above it
var _slope := 0.0                           # rad, nose up
var _jump_buffer := 0.0
var _since_jump := 9.0
var _since_ground := 0.0
var _air_time := 0.0
var _last_pos := Vector3.INF
var _last_yaw := NAN
var _move_v := Vector3.ZERO                 # how fast it moves (remote copies: measured from their poses)
var _fwd_speed := 0.0
var _yaw_rate := 0.0
var _phase := 0.0                           # stride phase 0..1
var _moving_w := 0.0                        # 0 standing .. 1 in its gait
var _air_w := 0.0                           # jump pose
var _down_w := 0.0                          # lying down (broken)
var _model: Node3D
var _pose: Node3D                           # the body: bobs and pitches about its centre
var _neck: Node3D
var _head: Node3D
var _tail: Node3D
var _rider: Node3D
var _hips: Array[Node3D] = []               # front left, front right, hind left, hind right
var _knees: Array[Node3D] = []
var _hoof_nodes: Array[Node3D] = []
var _leg_now: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]    # swing, knee flex
var _last_psi: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _reins: Array[MeshInstance3D] = []
var _hooves: AudioStreamPlayer3D
var _mats := {}
var _clock := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "Horse_" + model.replace("-", "_")
	mass = MASS
	max_speed = GALLOP
	camera_distance = 6.0
	_configure_body(self)
	set_meta("knocks_props", false)
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "")]})
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # the gait's speed is ours, the air flies on
	linear_damp = 0.0
	axis_lock_angular_x = true              # always upright: only the drawn body pitches
	axis_lock_angular_z = true
	for k: String in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[k]
		m.roughness = 0.25 if k == "eye" else (0.4 if k == "metal" else 0.65)
		m.metallic = 0.6 if k == "metal" else 0.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # lofts whatever their winding (plane.gd)
		_mats[k] = m
	_skin = StandardMaterial3D.new()        # the rider, in the player's colour (set_driver_color)
	_skin.albedo_color = Color(1, 0.55, 0.2)
	_skin.roughness = 0.6
	_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["skin"] = _skin
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_pose = Node3D.new()
	_pose.position = Vector3(0.0, BODY_Y, 0.0)
	_model.add_child(_pose)
	_build_body()
	_build_legs()
	_build_rider()
	# collision: the barrel, and the neck and head; nothing under the belly (the legs), so a jump clears a fence once
	# the belly is over it
	_add_box(self, Vector3(0.0, 1.2, -0.05), Vector3(0.7, 0.72, 1.85))
	_add_box(self, Vector3(0.0, 1.86, 1.2), Vector3(0.34, 0.68, 0.9))
	half_extents = Vector3(0.45, 1.12, 1.55)
	extents_center = Vector3(0.0, 0.0, 0.15)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, BODY_Y, 0.0)
	_total_mass = mass
	_set_max_health()
	smoke_spot = Vector3(0.0, 1.6, 0.8)

	audio = VehicleAudio.new()              # neighs, snorts and landings (no engine: it never runs)
	audio.position = Vector3(0.0, 1.8, 1.2)
	audio.setup("horse")
	add_child(audio)
	_hooves = AudioStreamPlayer3D.new()
	_hooves.stream = VehicleAudio.one_shot("hoof")
	_hooves.unit_size = 5.0
	_hooves.max_distance = 60.0
	_hooves.max_polyphony = 6
	_hooves.position = Vector3(0.0, 0.2, 0.0)
	add_child(_hooves)

	_build_chase_camera(camera_distance, 2.6)
	_cab_camera = Camera3D.new()            # the rider's eyes: bobs and pitches with the horse
	_cab_camera.fov = 75.0
	_cab_camera.near = 0.05
	_cab_camera.far = 1500.0
	_cab_camera.position = SEAT + Vector3(0.0, 0.72, 0.12)
	_cab_camera.rotation = Vector3(-0.1, PI, 0.0)
	_pose.add_child(_cab_camera)


# ---------------------------------------------------------------- model

func _mesh(parent: Node3D, mesh: Mesh, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	parent.add_child(mi)
	return mi


## A smooth tube through `points` (in a plane across x): half widths `wx` across it (x) and `wv` across it in that
## plane, superellipse sections of exponent `n`.
func _tube(parent: Node3D, points: Array, wx: Array, wv: Array, mat: String, n := 2.4) -> MeshInstance3D:
	var sections := []
	for i in points.size():
		var t: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		sections.append([points[i], Vector3(wx[i], 0.0, 0.0), t.cross(Vector3.RIGHT).normalized() * wv[i]])
	return _mesh(parent, Biplane._loft(sections, n), mat)


func _sphere(parent: Node3D, at: Vector3, r: float, mat: String, squash := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var mi := _mesh(parent, sm, mat)
	mi.transform = Transform3D(Basis.from_scale(squash), at)
	return mi


## A rod of radius `r` from `a` to `b`.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: String) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 1
	var mi := _mesh(parent, cm, mat)
	_stretch(mi, a, b)
	return mi


## Puts a unit rod along Y (mi) from `a` to `b`.
static func _stretch(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, d, x.cross(y)), (a + b) * 0.5)


## Barrel, neck, head, mane, tail, saddle and tack, in the pose frame (origin at the barrel centre, BODY_Y up).
func _build_body() -> void:
	var y0 := -BODY_Y
	# barrel from the rump to the chest: (z, centre height, half width, half height)
	var pts := []
	var wx := []
	var wv := []
	for s: Vector4 in [Vector4(-1.1, 1.3, 0.06, 0.07), Vector4(-1.03, 1.27, 0.24, 0.27), Vector4(-0.8, 1.25, 0.34, 0.34),
			Vector4(-0.35, 1.2, 0.36, 0.36), Vector4(0.2, 1.21, 0.35, 0.37), Vector4(0.65, 1.28, 0.32, 0.37),
			Vector4(0.92, 1.33, 0.22, 0.27), Vector4(1.0, 1.36, 0.07, 0.08)]:
		pts.append(Vector3(0.0, s.y + y0, s.x))
		wx.append(s.z)
		wv.append(s.w)
	_tube(_pose, pts, wx, wv, "coat")
	# neck, from inside the chest up to the poll
	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0.0, 0.25, 0.75)
	_pose.add_child(_neck)
	var neck := [Vector3(0.0, -0.08, -0.08), Vector3(0.0, 0.25, 0.2), Vector3(0.0, 0.52, 0.38), Vector3(0.0, 0.68, 0.47)]
	var neck_wv := [0.3, 0.22, 0.17, 0.14]
	_tube(_neck, neck, [0.25, 0.17, 0.135, 0.12], neck_wv, "coat")
	var crest := Vector3(0.0, 0.6, -0.8)                # the back of the neck
	var mane := []
	for i in neck.size():
		mane.append(neck[i] + crest * neck_wv[i] * 0.85)
	mane.append(Vector3(0.0, 0.8, 0.42))
	_tube(_neck, mane, [0.05, 0.055, 0.05, 0.045, 0.03], [0.1, 0.1, 0.09, 0.08, 0.04], "dark", 2.0)
	# head, from the poll down to the muzzle
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.66, 0.46)
	_neck.add_child(_head)
	var head := [Vector3(0.0, 0.04, -0.06), Vector3(0.0, -0.06, 0.08), Vector3(0.0, -0.25, 0.27), Vector3(0.0, -0.38, 0.4),
			Vector3(0.0, -0.43, 0.46)]
	var head_wv := [0.12, 0.15, 0.11, 0.095, 0.05]
	_tube(_head, head, [0.11, 0.125, 0.1, 0.085, 0.05], head_wv, "coat")
	var face := Vector3(0.0, 0.707, 0.707)              # the front of the head
	_tube(_head, [head[1] + face * head_wv[1] * 0.9, head[2] + face * head_wv[2] * 0.97,
			head[3] + face * head_wv[3] * 0.97], [0.035, 0.03, 0.04], [0.012, 0.012, 0.012], "white", 2.0)
	for side: float in [1.0, -1.0]:
		_sphere(_head, Vector3(side * 0.105, -0.03, 0.09), 0.034, "eye")
		_sphere(_head, Vector3(side * 0.045, -0.37, 0.46), 0.022, "eye")
		var ear := CylinderMesh.new()
		ear.top_radius = 0.0
		ear.bottom_radius = 0.045
		ear.height = 0.16
		ear.radial_segments = 8
		ear.rings = 1
		_mesh(_head, ear, "coat").transform = Transform3D(Basis.from_euler(Vector3(-0.15, 0.0, -side * 0.3)),
				Vector3(side * 0.07, 0.15, -0.05))
		_rod(_head, Vector3(side * 0.09, -0.32, 0.36), Vector3(side * 0.11, -0.05, 0.02), 0.012, "dark")   # bridle
	_sphere(_head, Vector3(0.0, 0.1, 0.04), 0.07, "dark", Vector3(0.8, 0.6, 1.0))     # forelock
	_rod(_head, Vector3(0.1, -0.32, 0.36), Vector3(-0.1, -0.32, 0.36), 0.012, "metal")   # bit
	# tail, hanging from the rump
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.2, -1.02)
	_pose.add_child(_tail)
	_tube(_tail, [Vector3.ZERO, Vector3(0.0, -0.06, -0.14), Vector3(0.0, -0.3, -0.27), Vector3(0.0, -0.65, -0.3),
			Vector3(0.0, -0.92, -0.26), Vector3(0.0, -1.0, -0.24)], [0.06, 0.07, 0.1, 0.11, 0.08, 0.03],
			[0.06, 0.07, 0.09, 0.1, 0.07, 0.03], "dark", 2.0)
	# saddle cloth, saddle (pommel and cantle up), stirrups
	_tube(_pose, [Vector3(0.0, 0.22, -0.42), Vector3(0.0, 0.22, 0.35)], [0.375, 0.375], [0.19, 0.19], "cloth", 4.0)
	_tube(_pose, [Vector3(0.0, 0.43, -0.37), Vector3(0.0, 0.41, -0.25), Vector3(0.0, 0.4, 0.05), Vector3(0.0, 0.42, 0.22),
			Vector3(0.0, 0.45, 0.3)], [0.16, 0.24, 0.26, 0.22, 0.12], [0.08, 0.05, 0.045, 0.05, 0.06], "saddle", 2.6)
	for side: float in [1.0, -1.0]:
		_rod(_pose, Vector3(side * 0.3, 0.38, 0.0), Vector3(side * 0.43, -0.2, 0.06), 0.015, "dark")
		var ring := TorusMesh.new()
		ring.inner_radius = 0.035
		ring.outer_radius = 0.055
		ring.rings = 12
		ring.ring_segments = 6
		_mesh(_pose, ring, "metal").transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.43, -0.25, 0.06))
		var rein := _rod(_pose, Vector3.ZERO, Vector3.UP, 0.012, "dark")
		_reins.append(rein)


## Four legs, each a hip node (swings about x) with the upper leg and a knee node (flexes) with the lower leg, the
## fetlock and the hoof.
func _build_legs() -> void:
	for i in 4:
		var front := i < 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var upper := 0.5 if front else 0.55
		var hip := Node3D.new()
		hip.name = "Leg%d" % i
		hip.position = Vector3(side * 0.19, -0.05 if front else 0.0, 0.62 if front else -0.66)
		_pose.add_child(hip)
		if front:
			_tube(hip, [Vector3(0.0, 0.12, 0.0), Vector3(0.0, -upper * 0.5, 0.0), Vector3(0.0, -upper, 0.0)],
					[0.13, 0.105, 0.08], [0.15, 0.12, 0.085], "coat", 2.2)
		else:                               # the hind leg's thigh and gaskin are deeper
			_tube(hip, [Vector3(0.0, 0.15, 0.03), Vector3(0.0, -upper * 0.5, -0.02), Vector3(0.0, -upper, 0.0)],
					[0.16, 0.125, 0.085], [0.24, 0.15, 0.09], "coat", 2.2)
		var knee := Node3D.new()
		knee.position = Vector3(0.0, -upper, 0.0)
		hip.add_child(knee)
		_sphere(knee, Vector3.ZERO, 0.085, "coat")
		_tube(knee, [Vector3.ZERO, Vector3(0.0, -0.5, 0.0)], [0.065, 0.065], [0.065, 0.065], "coat", 2.0)
		if not front:                       # white socks
			_tube(knee, [Vector3(0.0, -0.27, 0.0), Vector3(0.0, -0.5, 0.0)], [0.072, 0.074], [0.072, 0.074], "white", 2.0)
		_sphere(knee, Vector3(0.0, -0.5, 0.0), 0.076, "white" if not front else "coat")
		var hoof := CylinderMesh.new()
		hoof.top_radius = 0.07
		hoof.bottom_radius = 0.09
		hoof.height = 0.13
		hoof.radial_segments = 12
		hoof.rings = 1
		var h := _mesh(knee, hoof, "hoof")
		h.position = Vector3(0.0, -0.565, 0.01)
		_hips.append(hip)
		_knees.append(knee)
		_hoof_nodes.append(h)


## The rider: the player's capsule and nose (scenes/player.tscn) sitting in the saddle, legs down to the stirrups,
## hands forward on the reins; hidden until someone rides (car.gd shows _driver_dummy), and in the rider's view.
func _build_rider() -> void:
	_rider = Node3D.new()
	_rider.name = "Rider"
	_rider.position = SEAT
	_rider.visible = false
	_pose.add_child(_rider)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.0
	_mesh(_rider, capsule, "skin").position = Vector3(0.0, 0.42, 0.0)
	_sphere(_rider, Vector3(0.0, 0.68, 0.27), 0.12, "nose")
	for side: float in [1.0, -1.0]:
		var foot := Vector3(side * 0.43, -0.62, 0.1)
		_tube(_rider, [Vector3(side * 0.15, 0.02, 0.06), Vector3(side * 0.4, -0.27, 0.2), foot], [0.11, 0.09, 0.08],
				[0.11, 0.09, 0.08], "skin", 2.0)
		_sphere(_rider, foot + Vector3(0.0, -0.02, 0.05), 0.085, "skin", Vector3(0.9, 0.8, 1.3))
		var hand := Vector3(side * HAND.x, HAND.y, HAND.z)
		_tube(_rider, [Vector3(side * 0.25, 0.62, 0.04), Vector3(side * 0.2, 0.42, 0.25), hand], [0.065, 0.06, 0.055],
				[0.065, 0.06, 0.055], "skin", 2.0)
		_sphere(_rider, hand, 0.065, "skin")
	_driver_dummy = _rider


# ---------------------------------------------------------------- riding

func set_driving(on: bool) -> void:
	super(on)
	can_sleep = not on                      # a resting body ignores forces: the gait's would never move it
	audio.engine_on = false
	if on and not broken:
		audio.play("snort")


func _unhandled_input(event: InputEvent) -> void:
	if not driving or not controls:
		return
	if event.is_action_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("horn"):
		ring_bell()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_vehicle"):
		_put_back_on_wheels()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		set_cab_view(not cab_view)
		get_viewport().set_input_as_handled()
	elif not event is InputEventKey:
		super(event)                        # mouse look and zoom


## The rider's view (true) or the chase camera; the rider hides in the rider's view.
func set_cab_view(on: bool) -> void:
	super(on)
	if driving:
		_rider.visible = not cab_view


## G: a neigh (counted in `bells`, whose parity tells the other peers, like the bus's gong).
func ring_bell() -> void:
	bells += 1
	audio.play("neigh")


func _physics_process(delta: float) -> void:
	_measure_ground()
	_float()
	_measure_motion(delta)
	if remote:
		return
	var fwd_in := 0.0
	var turn_in := 0.0
	var fast := false
	if driving and controls and not broken and not hold:
		fwd_in = Input.get_axis("brake", "throttle")
		turn_in = Input.get_axis("steer_right", "steer_left")
		fast = Input.is_action_pressed("run")
	_throttle = fwd_in
	_jump_buffer -= delta
	_since_jump += delta
	var b := global_basis
	var f := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var r := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var v := linear_velocity
	var vf := v.dot(f)
	var target := 0.0
	if fwd_in > 0.0:
		target = (SWIM_SPEED if swimming else GALLOP if fast else CANTER) * fwd_in
	elif fwd_in < 0.0:
		target = 0.0 if vf > 0.3 else -BACK_SPEED
	on_ground = not is_nan(_ground_y) and _gap < REACH and not (_since_jump < 0.3 and v.y > 0.0)
	_since_ground = 0.0 if on_ground else _since_ground + delta
	# a short drop off a kerb or a crest is no jump
	_airborne = not on_ground and (_since_jump < 0.3 or _since_ground > 0.12 or _gap > 0.5)
	var force := Vector3.ZERO
	if on_ground:
		var dv := target - vf
		var lim := ACCEL if absf(target) > absf(vf) and target * vf >= 0.0 else DECEL
		var a_f := clampf(dv * 3.0, -lim, lim)
		var a_s := clampf(-v.dot(r) * SIDE_GRIP, -15.0, 15.0)
		var a_y := clampf(_gravity + RIDE_K * (_ground_y - global_position.y) - RIDE_C * v.y, 0.0, _gravity * 16.0)
		force = (f * a_f + r * a_s + Vector3.UP * a_y) * mass
	if _jump_buffer > 0.0 and _since_jump > 0.3 and (on_ground or _since_ground < COYOTE) and not swimming:
		_jump(f, r, vf)
		force = Vector3.ZERO
	apply_central_force(force)
	var want := turn_in * lerpf(TURN_RATE.x, TURN_RATE.y, clampf(absf(vf) / GALLOP, 0.0, 1.0)) \
			* (1.0 if on_ground else AIR_TURN)
	if driving or absf(angular_velocity.y - want) > 0.001:  # setting it wakes the body: not while it rests
		angular_velocity = Vector3(0.0, move_toward(angular_velocity.y, want, 10.0 * delta), 0.0)
	_update_damage(delta)


## Takes off: up the more the faster it runs (JUMP_UP), ahead at least JUMP_FORWARD when moving.
func _jump(f: Vector3, r: Vector3, vf: float) -> void:
	var up := lerpf(JUMP_UP.x, JUMP_UP.y, clampf(vf / CANTER, 0.0, 1.0)) \
			+ (JUMP_UP.z - JUMP_UP.y) * clampf((vf - CANTER) / (GALLOP - CANTER), 0.0, 1.0)
	var along := maxf(vf, JUMP_FORWARD) if vf > 1.0 else vf
	linear_velocity = f * along + r * linear_velocity.dot(r) * 0.5 + Vector3.UP * up
	_jump_buffer = 0.0
	_since_jump = 0.0
	_airborne = true


## The ground under the front and the hind hooves (up to STEP_UP above them): its mean height, the hooves' gap to it
## and the slope.
func _measure_ground() -> void:
	var space := get_world_3d().direct_space_state
	var top := global_position.y + STEP_UP
	var hs: Array[float] = []
	for z: float in [HOOF_Z, -HOOF_Z]:
		var p := to_global(Vector3(0.0, 0.0, z))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z),
				Vector3(p.x, top - 4.0, p.z), Layers.SOLID))
		hs.append(hit["position"].y if hit else NAN)
	if is_nan(hs[0]) and is_nan(hs[1]):
		_ground_y = NAN
		_gap = 99.0
		return
	var front := hs[1] if is_nan(hs[0]) else hs[0]
	var back := hs[0] if is_nan(hs[1]) else hs[1]
	_ground_y = (front + back) * 0.5
	_gap = global_position.y - _ground_y
	_slope = atan2(front - back, 2.0 * HOOF_Z)


## Deep water: the surface less SWIM_DRAFT is the "ground" its spring holds it at (it swims); a splash going in.
func _float() -> void:
	var lvl := Water.surface_at(global_position)
	var was := swimming
	swimming = not is_nan(lvl) and (is_nan(_ground_y) or lvl - SWIM_DRAFT > _ground_y)
	if not swimming:
		return
	_ground_y = lvl - SWIM_DRAFT
	_gap = global_position.y - _ground_y
	_slope = 0.0
	if not was and Water.current:
		Water.current.splash(global_position + Vector3.UP * SWIM_DRAFT, maxf(absf(linear_velocity.y), 3.0), 1.2)


## Speed and turn rate for the animation: the body's own, or for a remote copy how fast its pose moves.
func _measure_motion(delta: float) -> void:
	var p := global_position
	if remote:
		var mv := Vector3.ZERO if _last_pos == Vector3.INF else (p - _last_pos) / delta
		_move_v = _move_v.lerp(mv if mv.length() < 30.0 else Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	else:
		_move_v = linear_velocity
	_last_pos = p
	var yaw := global_rotation.y
	if not is_nan(_last_yaw):
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-12.0 * delta))
	_last_yaw = yaw
	var f := global_basis.z
	_fwd_speed = _move_v.dot(Vector3(f.x, 0.0, f.z).normalized())


## Forward speed in m/s (negative backing up), also for remote copies.
func speed() -> float:
	return _fwd_speed


## Down (broken) or up again, without the cars' fire and smoke: a neigh as it goes down, a snort as it gets up.
func set_health(h: float, effects := true) -> void:
	h = clampf(h, 0.0, max_health)
	if h == health:
		return
	health = h
	var was_broken := broken
	broken = h <= 0.0
	if broken == was_broken:
		return
	if broken:
		_broken_t = 0.0
		_doused = 0.0
	if effects:
		audio.play("neigh" if broken else "snort")


## LAN games: the car's state and whether it is in the air (the jump pose).
func net_state() -> Array:
	var s := super()
	s.append(_airborne)
	return s


func apply_net_state(a: Array, b: Array, w: float) -> void:
	super(a, b, w)
	if b.size() > 7:
		_airborne = b[7]
	audio.engine_on = false


func dash_text() -> String:
	var line := "%3d km/h   %s" % [roundi(absf(_fwd_speed) * 3.6), "swimming" if swimming else "backing up"
			if _fwd_speed < -0.2 else GAIT_NAMES[gait]]
	if broken:
		line += "\nDOWN · back on its feet in %d s" % ceili(repair_in())
	return line


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	super(delta)
	_animate(delta)


func _pick_gait(av: float) -> String:
	var k := GAIT_ORDER.find(gait)
	while k < GAIT_ORDER.size() - 1 and av > GAIT_SPEEDS[k] * 1.1:
		k += 1
	while k > 0 and av < GAIT_SPEEDS[k - 1] * 0.9:
		k -= 1
	return GAIT_ORDER[k]


func _animate(delta: float) -> void:
	_clock += delta
	gait = _pick_gait(absf(_fwd_speed))
	var g: Dictionary = GAITS.get(gait, GAITS["walk"])
	var freq: float = absf(_fwd_speed) / g["stride"] if gait != "stand" else 0.0
	if gait == "stand" and absf(_yaw_rate) > 0.3:
		freq = 0.6 + 0.3 * absf(_yaw_rate)  # stepping round on the spot
	if broken or _airborne:
		freq = 0.0
	var dir := -1.0 if _fwd_speed < -0.05 else 1.0
	_phase = fposmod(_phase + freq * delta * dir, 1.0)
	_moving_w = move_toward(_moving_w, 1.0 if freq > 0.0 else 0.0, delta * 4.0)
	_air_w = move_toward(_air_w, 1.0 if _airborne else 0.0, delta * 7.0)
	_down_w = move_toward(_down_w, 1.0 if broken else 0.0, delta * 1.2)
	var vy := _move_v.y
	var amp := asin(clampf(g["duty"] * g["stride"] / (2.0 * LEG_LENGTH), 0.0, 0.95))
	if gait == "stand":
		amp = 0.15
	var clop := not _airborne and not broken and _moving_w > 0.5 and is_visible_in_tree()
	for i in 4:
		var psi := fposmod(_phase + g["offsets"][i], 1.0)
		if clop and absf(psi - _last_psi[i]) > 0.5:     # crossing 0: the hoof comes down
			_clop(i)
		_last_psi[i] = psi
		var duty: float = g["duty"]
		var pose := Vector2.ZERO
		if psi < duty:                      # on the ground, sweeping back
			pose = Vector2(lerpf(amp, -amp, psi / duty), 0.08 * sin(PI * psi / duty))
		else:                               # in the air, swinging forward with the knee flexed
			var u := (psi - duty) / (1.0 - duty)
			pose = Vector2(lerpf(-amp, amp, smoothstep(0.0, 1.0, u)), sin(PI * u) * g["lift"])
		pose *= _moving_w
		if i >= 2:
			pose += Vector2(-0.05, 0.12)    # the hind legs stand a little bent at the hock
		pose = pose.lerp(_jump_pose(i, vy), _air_w).lerp(_lying_pose(i), _down_w)
		_leg_now[i] = _leg_now[i].lerp(pose, 1.0 - exp(-30.0 * delta))
		_hips[i].rotation.x = -_leg_now[i].x
		_knees[i].rotation.x = _leg_now[i].y if i < 2 else -_leg_now[i].y
	# body: gait bob and rock, the slope, the jump (nose up rising, down falling), lying down
	var bob: float = g["bob"] * cos(TAU * _phase * g["bobs"]) * _moving_w
	var rock: float = g["rock"] * sin(TAU * _phase) * _moving_w
	var jump_pitch := clampf(atan2(vy, maxf(Vector2(_move_v.x, _move_v.z).length(), 4.0)) * 0.8, -0.4, 0.4)
	var pitch := _slope * (1.0 - _air_w) + jump_pitch * _air_w + rock
	_pose.position.y = BODY_Y + bob - 0.6 * _down_w
	_pose.rotation = Vector3(-pitch * (1.0 - _down_w), 0.0, 0.1 * _down_w)
	var fast := clampf((absf(_fwd_speed) - CANTER * 0.6) / (GALLOP - CANTER * 0.6), 0.0, 1.0)
	var nod := 0.06 * sin(TAU * _phase * (2.0 if gait in ["walk", "trot"] else 1.0)) * _moving_w
	var idle := 0.04 * sin(_clock * 0.7) * (1.0 - _moving_w)
	_neck.rotation.x = 0.25 * fast + nod + idle + 0.2 * _air_w + 0.35 * _down_w
	_head.rotation.x = -0.15 * fast - 0.1 * _air_w
	_tail.rotation = Vector3(-0.35 * fast - 0.5 * _air_w, 0.18 * sin(_clock * 1.3) * (1.0 - 0.6 * _moving_w), 0.0)
	_rider.rotation.x = 0.05 + 0.2 * fast + 0.35 * _air_w * smoothstep(-2.0, 1.0, vy)
	_update_reins()
	if _airborne:
		_air_time += delta
	elif _air_time > 0.0:
		if _air_time > 0.3 and not broken:
			audio.play("land")
		_air_time = 0.0


## Leg pose (swing forward, knee flex) over a jump: rising, the forelegs tucked and the hind legs pushing back;
## falling, the forelegs reaching for the ground and the hind legs tucked.
func _jump_pose(i: int, vy: float) -> Vector2:
	var fall := smoothstep(1.5, -2.0, vy)
	if i < 2:
		return Vector2(1.0, 2.1).lerp(Vector2(0.45, 0.2), fall)
	return Vector2(-0.65, 0.25).lerp(Vector2(0.45, 1.3), fall)


## Leg pose lying down: the forelegs folded back under the chest, the hind legs forward under the belly.
func _lying_pose(i: int) -> Vector2:
	return Vector2(0.35, 2.7) if i < 2 else Vector2(0.9, 0.6)


## The reins from the bit to the rider's hands, or lying on the withers with nobody in the saddle.
func _update_reins() -> void:
	var head := _neck.transform * _head.transform
	for k in 2:
		var side := 1.0 if k == 0 else -1.0
		var bit := head * Vector3(side * BIT.x, BIT.y, BIT.z)
		var hand := _rider.transform * Vector3(side * HAND.x, HAND.y, HAND.z) if _rider.visible or (driving and cab_view) \
				else Vector3(side * 0.12, 0.44, 0.38)
		_stretch(_reins[k], bit, hand)


func _clop(leg: int) -> void:
	_hooves.pitch_scale = (1.08 if leg < 2 else 0.94) * randf_range(0.95, 1.05)
	_hooves.volume_db = {"walk": -9.0, "trot": -5.0, "canter": -2.0, "gallop": 0.0}.get(gait, -12.0)
	_hooves.play()
