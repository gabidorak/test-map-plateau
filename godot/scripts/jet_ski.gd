extends "res://scripts/car.gd"
## Toy jet-ski (Car.SPECS "jet_ski"), a stand-up-free sit-down personal watercraft built from primitive shapes at
## runtime like the horse: white hull with a yellow deck, black seat, handlebar, the jet nozzle at the stern, and its
## rider in the player's colour. game.gd parks it on the nearest lake or pond from the vehicle menu (on land beside the
## player when there is none near), and the player gets on (E) and off (Space, into the water: they swim) like a car.
## LAN games sync it like a car; the other peers' copies throw their spray from how fast their pose moves.
## Keys while riding (the Settings actions, scripts/settings.gd): W throttle, S slows and backs up slowly, A / D steer,
## G horn, R rights it, V or the mouse wheel zoomed all the way in: the rider's view.
## Physics: one rigid body with no wheels. Floats (scripts/water.gd) on springs at FLOATS (each holds a quarter of its
## weight REST_SUB under the surface, damped), with a small swell; the jet pushes from under the stern while its intake
## is in the water, so it squats and the bow lifts as it pulls away; the hull drags little along it (quadratic, top
## speed TOP_SPEED) and a lot sideways (it carves turns); it steers by the jet (a yaw rate, more with speed, a little
## while idling) and rights itself in the water. The model leans into turns and pitches up at speed (drawn only). On land
## it crawls (LAND_SPEED) so it can be pushed back to the water. Its health is the cars' (car.gd): broken, the engine
## dies and it smokes.
## Frame: like the cars, +Z forward, +X its left, origin under the keel.

const Biplane = preload("res://scripts/plane.gd")
const MASS := 380.0                         # kg, rider included
const TOP_SPEED := 22.0                     # m/s (~80 km/h)
const THRUST := 6.5                         # m/s² of the jet at full throttle...
const REVERSE := 0.35                       # ...share of it backing up...
const REVERSE_SPEED := 3.0                  # ...up to this
const IDLE_DRAG := 0.12                     # /s, the hull's linear drag along it (it coasts to a stop)
const SIDE_DRAG := 3.5                      # /s, sideways: the hull grips the water like a keel
const TURN_RATE := 1.5                      # rad/s at speed...
const IDLE_TURN := 0.35                     # ...share of it while barely moving
const REST_SUB := 0.2                       # m each float sits under the surface at rest
const FLOAT_DAMP := 9.0                     # /s, the floats' vertical damping (per share of the mass)
const FLOAT_MAX := 0.7                      # m: a float deeper than this pushes no harder
const RIGHTING := 6.0                       # /s², torque per rad of tilt per kg·m² (it does not capsize)
const SWELL := 0.04                         # m, the small waves it bobs on
const LAND_SPEED := 2.0                     # m/s crawling on land
const FLOATS := [Vector3(0.42, 0.05, 1.0), Vector3(-0.42, 0.05, 1.0), Vector3(0.42, 0.05, -1.1),
		Vector3(-0.42, 0.05, -1.1)]
const NOZZLE := Vector3(0.0, 0.15, -1.62)   # where the jet pushes from (under the waterline at rest)
const SEAT := Vector3(0.0, 0.86, -0.42)     # rider's seat
const BARS := Vector3(0.0, 1.02, 0.42)      # handlebar pivot
const GRIP := Vector3(0.33, 0.0, -0.04)     # left grip, handlebar frame (mirrored)
const COLORS := {"hull": Color(0.95, 0.95, 0.93), "deck": Color(1.0, 0.78, 0.08), "trim": Color(0.08, 0.32, 0.72),
		"seat": Color(0.08, 0.08, 0.09), "dark": Color(0.22, 0.23, 0.25), "metal": Color(0.75, 0.77, 0.8),
		"glass": Color(0.15, 0.2, 0.25), "nose": Color(0.2, 0.25, 0.35)}

var floating := false                       # some float is in the water
var _mats := {}
var _model: Node3D
var _bars: Node3D
var _rider: Node3D
var _rider_arms: Array[MeshInstance3D] = []
var _rooster: CPUParticles3D                # the jet's spray behind
var _bow_spray: CPUParticles3D              # thrown up either side of the bow at speed
var _fwd_speed := 0.0
var _yaw_rate := 0.0
var _last_pos := Vector3.INF
var _last_yaw := NAN
var _move_v := Vector3.ZERO
var _lean := 0.0
var _pitch := 0.0
var _clock := 0.0
var _jet_in_water := false


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "JetSki_" + model.replace("-", "_")
	mass = MASS
	max_speed = TOP_SPEED
	camera_distance = 5.5
	_configure_body(self)
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "")]})
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # the water's drag is ours
	linear_damp = 0.0
	angular_damp = 0.5                      # the water's damping is ours (floats, righting)
	for k: String in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[k]
		m.roughness = 0.3 if k in ["hull", "deck", "trim"] else (0.35 if k == "metal" else 0.7)
		m.metallic = 0.7 if k == "metal" else 0.0
		m.clearcoat_enabled = k in ["hull", "deck", "trim"]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[k] = m
	_skin = StandardMaterial3D.new()        # the rider, in the player's colour (set_driver_color)
	_skin.albedo_color = Color(1, 0.55, 0.2)
	_skin.roughness = 0.6
	_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["skin"] = _skin
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_build_hull()
	_build_rider()
	_add_box(self, Vector3(0.0, 0.42, -0.05), Vector3(1.1, 0.8, 3.25))
	half_extents = Vector3(0.6, 0.6, 1.7)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.38, -0.15)
	_total_mass = mass
	_set_max_health()
	smoke_spot = Vector3(0.0, 0.9, -1.1)
	smoke_size = 0.8

	audio = VehicleAudio.new()
	audio.position = Vector3(0.0, 0.5, -0.8)
	audio.setup("jetski")
	add_child(audio)
	_rooster = _spray(Vector3(0.0, 0.25, -1.75), 140, 0.75)
	_bow_spray = _spray(Vector3(0.0, 0.15, 1.1), 50, 0.6)

	_build_chase_camera(camera_distance, 2.0)
	_cab_camera = Camera3D.new()            # the rider's eyes: leans and pitches with the model
	_cab_camera.fov = 75.0
	_cab_camera.near = 0.05
	_cab_camera.far = 1500.0
	_cab_camera.position = SEAT + Vector3(0.0, 0.78, 0.12)
	_cab_camera.rotation = Vector3(-0.12, PI, 0.0)
	_model.add_child(_cab_camera)


# ---------------------------------------------------------------- model

func _mesh(parent: Node3D, mesh: Mesh, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	parent.add_child(mi)
	return mi


## A loft through sections (z, centre height, half width, half height), superellipse exponent `n`, shifted by `dx`.
func _hull_part(parent: Node3D, rows: Array, mat: String, n := 3.0, dx := 0.0) -> MeshInstance3D:
	var sections := []
	for s: Vector4 in rows:
		sections.append([Vector3(dx, s.y, s.x), Vector3(s.z, 0.0, 0.0), Vector3(0.0, s.w, 0.0)])
	return _mesh(parent, Biplane._loft(sections, n, 24), mat)


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
	cm.radial_segments = 10
	cm.rings = 1
	var mi := _mesh(parent, cm, mat)
	_stretch(mi, a, b)
	return mi


static func _stretch(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, d, x.cross(y)), (a + b) * 0.5)


## Hull (white, a deep vee under a flat-sided topside), the yellow deck and hood, blue side stripes, the seat, the
## handlebar on its column, mirrors' stalks, the rubber bumper rail and the jet nozzle.
func _build_hull() -> void:
	# (z, centre height, half width, half height): stern to bow
	_hull_part(_model, [Vector4(-1.62, 0.36, 0.5, 0.3), Vector4(-1.5, 0.35, 0.56, 0.33), Vector4(-0.8, 0.35, 0.6, 0.35),
			Vector4(0.2, 0.36, 0.6, 0.36), Vector4(0.9, 0.42, 0.53, 0.35), Vector4(1.35, 0.5, 0.38, 0.3),
			Vector4(1.62, 0.58, 0.18, 0.18), Vector4(1.72, 0.62, 0.05, 0.06)], "hull", 2.6)
	# deck over the topside, the hood rising to the handlebar
	_hull_part(_model, [Vector4(-1.6, 0.66, 0.48, 0.06), Vector4(-0.9, 0.67, 0.55, 0.07), Vector4(0.0, 0.68, 0.55, 0.08),
			Vector4(0.6, 0.74, 0.5, 0.12), Vector4(1.1, 0.74, 0.38, 0.1), Vector4(1.5, 0.68, 0.18, 0.06),
			Vector4(1.62, 0.64, 0.06, 0.03)], "deck", 3.5)
	_hull_part(_model, [Vector4(0.15, 0.78, 0.22, 0.05), Vector4(0.35, 0.86, 0.34, 0.14), Vector4(0.75, 0.84, 0.36, 0.13),
			Vector4(1.15, 0.76, 0.24, 0.06), Vector4(1.3, 0.73, 0.08, 0.02)], "deck", 3.0)
	# a smoked windscreen strip on the hood
	_hull_part(_model, [Vector4(0.42, 0.98, 0.25, 0.015), Vector4(0.62, 0.97, 0.3, 0.02), Vector4(0.82, 0.93, 0.26, 0.015)],
			"glass", 3.0)
	for side: float in [1.0, -1.0]:
		# side stripe and bumper rail
		_hull_part(_model, [Vector4(-1.45, 0.47, 0.012, 0.035), Vector4(-0.4, 0.47, 0.012, 0.05),
				Vector4(0.6, 0.5, 0.012, 0.06), Vector4(1.2, 0.56, 0.012, 0.03)], "trim", 2.0, side * 0.59)
		_hull_part(_model, [Vector4(-1.55, 0.64, 0.03, 0.03), Vector4(-0.5, 0.64, 0.035, 0.035),
				Vector4(0.6, 0.66, 0.035, 0.035), Vector4(1.4, 0.64, 0.025, 0.025)], "dark", 2.0, side * 0.57)
		# footwells: dark pads either side of the seat
		var pad := BoxMesh.new()
		pad.size = Vector3(0.18, 0.02, 1.0)
		_mesh(_model, pad, "dark").position = Vector3(side * 0.37, 0.72, -0.55)
	# seat: a long padded saddle, a step at the passenger's part
	_hull_part(_model, [Vector4(-1.45, 0.78, 0.14, 0.06), Vector4(-1.3, 0.84, 0.2, 0.1), Vector4(-0.6, 0.86, 0.22, 0.11),
			Vector4(-0.1, 0.88, 0.2, 0.1), Vector4(0.12, 0.84, 0.13, 0.06)], "seat", 2.8)
	# jet nozzle and the ride plate under the stern
	var noz := CylinderMesh.new()
	noz.top_radius = 0.09
	noz.bottom_radius = 0.12
	noz.height = 0.2
	noz.radial_segments = 12
	_mesh(_model, noz, "dark").transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), NOZZLE + Vector3(0.0, 0.05, 0.0))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.5, 0.03, 0.35)
	_mesh(_model, plate, "metal").position = Vector3(0.0, 0.06, -1.5)
	# handlebar on its column (turns with the steering)
	_rod(_model, Vector3(0.0, 0.85, 0.5), BARS, 0.035, "dark")
	_bars = Node3D.new()
	_bars.name = "Handlebar"
	_bars.position = BARS
	_model.add_child(_bars)
	_rod(_bars, Vector3(GRIP.x + 0.05, 0.0, GRIP.z), Vector3(-GRIP.x - 0.05, 0.0, GRIP.z), 0.018, "metal")
	_sphere(_bars, Vector3.ZERO, 0.07, "deck", Vector3(1.4, 0.6, 1.0))
	for side: float in [1.0, -1.0]:
		_rod(_bars, Vector3(side * (GRIP.x - 0.06), 0.0, GRIP.z), Vector3(side * (GRIP.x + 0.07), 0.0, GRIP.z), 0.03, "seat")
		_rod(_model, Vector3(side * 0.28, 0.86, 0.68), Vector3(side * 0.42, 1.02, 0.6), 0.012, "dark")   # mirror stalk
		var mirror := BoxMesh.new()
		mirror.size = Vector3(0.14, 0.07, 0.02)
		_mesh(_model, mirror, "dark").position = Vector3(side * 0.44, 1.04, 0.6)


## The rider: the player's capsule and nose (scenes/player.tscn) astride the seat, feet in the footwells, hands on the
## grips; hidden until someone rides (car.gd shows _driver_dummy), and in the rider's view.
func _build_rider() -> void:
	_rider = Node3D.new()
	_rider.name = "Rider"
	_rider.position = SEAT
	_rider.visible = false
	_model.add_child(_rider)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.27
	capsule.height = 0.95
	var body := _mesh(_rider, capsule, "skin")
	body.position = Vector3(0.0, 0.45, 0.05)
	body.rotation.x = 0.25                  # leaning forward to the bars
	_sphere(_rider, Vector3(0.0, 0.72, 0.38), 0.12, "nose")
	for side: float in [1.0, -1.0]:
		var foot := Vector3(side * 0.37, -0.1, 0.0)
		var knee := Vector3(side * 0.3, 0.12, 0.35)
		_rod(_rider, Vector3(side * 0.13, 0.04, 0.0), knee, 0.09, "skin")
		_rod(_rider, knee, foot, 0.075, "skin")
		_sphere(_rider, foot + Vector3(0.0, 0.0, 0.06), 0.08, "skin", Vector3(0.9, 0.7, 1.4))
		_rider_arms.append(_rod(_rider, Vector3.ZERO, Vector3.UP, 0.055, "skin"))
	_driver_dummy = _rider


func _spray(at: Vector3, amount: int, size: float) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.position = at
	s.emitting = false
	s.amount = amount
	s.lifetime = 0.9
	s.local_coords = false
	s.mesh = Water.spray_mesh()
	s.gravity = Vector3(0.0, -9.8, 0.0)
	s.scale_amount_min = 0.6 * size
	s.scale_amount_max = 1.4 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	s.scale_amount_curve = curve
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	s.emission_box_extents = Vector3(0.12, 0.05, 0.1)
	add_child(s)
	return s


# ---------------------------------------------------------------- riding

func set_driving(on: bool) -> void:
	super(on)
	can_sleep = not on                      # a resting body ignores forces: the jet's would never move it


func _unhandled_input(event: InputEvent) -> void:
	if not driving or not controls:
		return
	if event.is_action_pressed("reset_vehicle"):
		_put_back_on_wheels()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		set_cab_view(not cab_view)
		get_viewport().set_input_as_handled()
	elif not event is InputEventKey:
		super(event)                        # mouse look and zoom


## Upright again where it is, on the water if it is in a lake.
func _put_back_on_wheels() -> void:
	var yaw := atan2(global_basis.z.x, global_basis.z.z)
	var lvl := Water.surface_at(global_position)
	var p := global_position + Vector3.UP * 0.5
	if not is_nan(lvl):
		p.y = maxf(p.y, lvl)
	place(Transform3D(Basis(Vector3.UP, yaw), p))


## The rider's view (true) or the chase camera; the rider hides in the rider's view.
func set_cab_view(on: bool) -> void:
	super(on)
	if driving:
		_rider.visible = not cab_view


func _physics_process(delta: float) -> void:
	_measure_motion(delta)
	if remote:
		_update_spray()
		audio.update(_engine_speed(_throttle), _throttle, max_speed, delta)
		return
	var throttle := 0.0
	var steer_in := 0.0
	if driving and controls and not broken and not hold:
		throttle = Input.get_axis("brake", "throttle")
		steer_in = Input.get_axis("steer_right", "steer_left")
	audio.horn = driving and controls and Input.is_action_pressed("horn")
	_throttle = throttle
	steering = move_toward(steering, steer_in * 0.45, 4.0 * delta)
	_clock += delta
	var g: float = get_gravity().length()
	var b := global_basis
	var f := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var r := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var v := linear_velocity
	var vf := v.dot(f)
	var vs := v.dot(r)

	# floats: springs holding each quarter of the weight REST_SUB under the (gently swelling) surface
	var wet := 0
	var was_floating := floating
	for p: Vector3 in FLOATS:
		var wp := to_global(p)
		var lvl := Water.surface_at(wp)
		if is_nan(lvl):
			continue
		lvl += SWELL * sin(_clock * 1.7 + wp.x * 0.35 + wp.z * 0.2)
		var sub := clampf(lvl - wp.y, 0.0, FLOAT_MAX)
		if sub <= 0.0:
			continue
		wet += 1
		var share := mass / FLOATS.size()
		var up := share * g * sub / REST_SUB - velocity_at(wp).y * share * FLOAT_DAMP
		apply_force(Vector3.UP * maxf(up, 0.0), wp - global_position)
	floating = wet > 0
	if floating and not was_floating and Water.current:
		Water.current.splash(global_position, maxf(-v.y, 0.0) + 0.5 * v.length(), 1.2)
	var nozzle := to_global(NOZZLE)
	_jet_in_water = floating and Water.surface_at(nozzle) > nozzle.y - 0.1

	var accel := Vector3.ZERO
	if floating:
		# the jet: forward, or a little backwards; the hull's drag along and across it
		var push := 0.0
		if throttle > 0.0:
			push = THRUST * throttle
		elif throttle < 0.0 and vf > -REVERSE_SPEED:
			push = THRUST * REVERSE * throttle
		var drag := IDLE_DRAG * vf + (THRUST - IDLE_DRAG * TOP_SPEED) / (TOP_SPEED * TOP_SPEED) * vf * absf(vf)
		accel += f * -drag + r * -vs * SIDE_DRAG * wet / FLOATS.size()
		if _jet_in_water and push != 0.0:
			apply_force(f * push * mass, nozzle - global_position)
		# steering is the jet's: a yaw rate, more with speed (backwards the other way)
		var want := steering / 0.45 * TURN_RATE * clampf(IDLE_TURN + absf(vf) / 8.0 + absf(throttle) * 0.3, 0.0, 1.0) \
				* (-1.0 if vf < -0.5 else 1.0)
		var inertia := mass * (3.3 * 3.3 + 1.1 * 1.1) / 12.0
		apply_torque(b.y * (want - angular_velocity.dot(b.y)) * inertia * 6.0)
		# rights itself: torque towards upright, and the water damps the roll and pitch
		var tilt := b.y.cross(Vector3.UP)
		apply_torque((tilt * RIGHTING - (angular_velocity - b.y * angular_velocity.dot(b.y)) * 1.5) * inertia)
	elif _on_land():
		# beached: it crawls slowly on its hull where the rider pushes it, else it stays put
		var target := LAND_SPEED * throttle
		accel += f * clampf((target - vf) * 3.0, -6.0, 6.0) - r * vs * 6.0
		var want := steering / 0.45 * 0.8 * (1.0 if absf(throttle) > 0.0 else 0.0)
		apply_torque(b.y * (want - angular_velocity.dot(b.y)) * mass * 2.0)
	apply_central_force(accel * mass)
	_update_spray()
	_update_damage(delta)
	audio.update(_engine_speed(throttle), throttle, max_speed, delta)


## The engine's speed as the gearbox model wants it (vehicle_audio.gd): the impeller revs with the throttle, not
## with the hull's speed.
func _engine_speed(throttle: float) -> float:
	return maxf(absf(_fwd_speed), absf(throttle) * 0.8 * max_speed) if floating or remote else absf(throttle) * 0.3 * max_speed


func _on_land() -> bool:
	var space := get_world_3d().direct_space_state
	var p := global_position + global_basis.y * 0.3
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - global_basis.y * 0.6, Layers.SOLID))
	return not hit.is_empty()


## Speed and turn rate: the body's own, or for a remote copy how fast its pose moves.
func _measure_motion(delta: float) -> void:
	var p := global_position
	if remote:
		var mv := Vector3.ZERO if _last_pos == Vector3.INF else (p - _last_pos) / delta
		_move_v = _move_v.lerp(mv if mv.length() < 40.0 else Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		floating = not is_nan(Water.surface_at(p))
	else:
		_move_v = linear_velocity
	_last_pos = p
	var yaw := global_rotation.y
	if not is_nan(_last_yaw):
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-10.0 * delta))
	_last_yaw = yaw
	var f := global_basis.z
	_fwd_speed = _move_v.dot(Vector3(f.x, 0.0, f.z).normalized())


func speed() -> float:
	return _fwd_speed


## The rooster tail behind while the jet pushes in the water, the bow spray at speed.
func _update_spray() -> void:
	var lvl := Water.surface_at(global_position)
	var in_water := not is_nan(lvl) and global_position.y < lvl + 0.3
	var jet := in_water and _throttle > 0.15 and not broken
	_rooster.emitting = jet
	if jet:
		var back := -global_basis.z
		_rooster.direction = (back * 1.0 + Vector3.UP * 0.9).normalized()
		_rooster.spread = 12.0
		_rooster.initial_velocity_min = 3.0 + 6.0 * _throttle
		_rooster.initial_velocity_max = 5.0 + 9.0 * _throttle
	var fast := in_water and _fwd_speed > 5.0
	_bow_spray.emitting = fast
	if fast:
		_bow_spray.direction = Vector3.UP
		_bow_spray.spread = 70.0
		_bow_spray.initial_velocity_min = 1.5
		_bow_spray.initial_velocity_max = 2.0 + _fwd_speed * 0.18


func dash_text() -> String:
	var line := "%3d km/h   %s" % [roundi(absf(_fwd_speed) * 3.6), "reverse" if _fwd_speed < -0.3 else "jet"]
	if not floating:
		line += "\nON LAND · it only crawls: push it back to the water"
	if broken:
		line += "\nBROKEN · repaired in %d s" % ceili(repair_in())
	return line


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	super(delta)
	_animate(delta)


func _animate(delta: float) -> void:
	var k := 1.0 - exp(-6.0 * delta)
	var fast := clampf(_fwd_speed / TOP_SPEED, 0.0, 1.0)
	# leaning into turns, the bow up at speed (planing)
	_lean = lerpf(_lean, clampf(-_yaw_rate * maxf(_fwd_speed, 0.0) * 0.035, -0.4, 0.4), k)
	_pitch = lerpf(_pitch, (0.07 * sin(fast * PI) + 0.03 * fast) if floating else 0.0, k)
	_model.rotation = Vector3(-_pitch, 0.0, _lean)
	_bars.rotation.y = steering * 1.2
	_rider.rotation.z = _lean * 0.6
	# arms from the shoulders to the grips (rider frame)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var grip := _bars.transform * Vector3(side * GRIP.x, 0.0, GRIP.z)
		var hand := _rider.transform.affine_inverse() * grip
		_stretch(_rider_arms[i], Vector3(side * 0.25, 0.72, 0.18), hand)
