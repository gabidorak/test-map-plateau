extends "res://scripts/car.gd"
## The police helicopter (Car.SPECS "helicopter-police"): an EC135 in the colours of a French police air unit, a
## ready-made textured model (assets/cars/ec135_police/, made by tools/vehicles/helicopter_police.py; credits in
## assets/cars/CREDITS.md). One rigid body standing on its skids, flown with arcade physics on top: the rotor lifts
## along its axis as much as it takes to climb or sink at the rate the collective asks (released: it holds its height),
## so tipping the nose or banking drives it that way; the attitude follows the cyclic on a damped spring and levels
## itself once the keys are released (and then it settles into a hover); the tail rotor turns it at a rate; at speed a
## bank turns it too (a coordinated turn); the air drags (top speed ~290 km/h at full tilt).
## Keys (the plane's actions, scripts/settings.gd): Shift / Ctrl climb / descend (the collective), W / S nose down / up
## (forward / back), A / D bank (sideways, and turning at speed), Q / E turn (A / E on AZERTY), R levels it, L the
## searchlight under the nose (the headlights), V or the mouse wheel all the way in: the cockpit view. The rotor spools
## up (SPOOL_UP s) once someone takes the controls and down (SPOOL_DOWN s) once nobody does: it lifts only spun up.
## On the ground with the collective down it sits on its skids; the pilot gets out only there (leave_problem).
## The rotors turn (a blurred disc over the blades at speed), red anti-collision beacons blink while it runs; a
## passenger rides in the left front seat (E from the right side). LAN games sync it like a car, with the rotor's speed
## (the others' copies spin and sound from it). Health, crash damage, water: car.gd's.
## A bot may fly it (the police's, scripts/police/air/heli_pilot.gd): with a `pilot` and nobody at the controls, it takes
## them from pilot.fly (the same keys, as -1..1 axes) and the rotor runs. Parked, its rotor still, it sleeps like a
## parked car (car.gd _sleep_parked): nothing of its flight is worked out until someone, a pilot or a knock wakes it.
## Frame: like the cars, +Z forward, +X its left, origin on the ground under the middle of the skids' length... at the
## model's own origin (the rotor mast at z 0.27).

const MASS := 2400.0                        # kg
const TOP_SPEED := 60.0                     # m/s, for the sound's scale and the network
const SPOOL_UP := 7.0                       # s for the rotor to reach flight speed once someone flies it
const SPOOL_DOWN := 14.0                    # s to wind down once nobody does (or the engine broke)
const LIFT_MAX := 1.75                      # the rotor's most lift at flight speed, times the weight
const CLIMB := 8.0                          # m/s up, Shift held...
const DESCENT := 6.0                        # ...down, Ctrl held (released: the height held)
const VZ_GAIN := 2.2                        # /s: how hard the lift chases the wanted climb rate
const TILT := Vector3(0.6, 0.35, 0.5)       # rad: the most the cyclic tips the nose down, up, and banks
const ATT_K := 14.0                         # /s², the attitude's spring per rad off...
const ATT_D := 6.5                          # /s, ...and its damper
const YAW_RATE := 1.3                       # rad/s, Q / E
const YAW_K := 5.0                          # /s: how hard the tail rotor chases it
const BANK_TURN := 0.9                      # rad/s of turn per rad of bank, at speed
const DRAG := 2.5                           # N per (m/s)², the airframe's
const DRIFT := 0.03                         # /s, a little linear damping always
const HOLD := 0.4                           # /s, horizontal braking with the cyclic centred (it settles to a hover)
const CEILING := 190.0                      # m (Godot y): the lift fades over the last 40 m below it (the map's
											# boundary walls stop at y = 200)
const GROUND := 0.35                        # m: the skids this near the ground below, it stands on it
const ROTOR_SPIN := 20.0                    # rad/s the main rotor is drawn turning at flight speed
const TAIL_SPIN := 4.5                      # times as fast, the tail's fenestron
const HUB := Vector3(0.0, 3.45, 0.27)       # the main rotor's disc centre
const ROTOR_RADIUS := 3.95
const SKID := Vector3(1.04, 0.06, 1.09)     # left skid's centre (mirrored)
const SKID_SIZE := Vector3(0.16, 0.12, 3.66)
const SEARCHLIGHT := Vector3(0.92, 0.5, 3.3)
const SEARCH_DOWN := 0.6                    # rad below the nose the searchlight points
const BEACONS := [Vector3(0.0, 3.86, -7.05), Vector3(0.0, 0.47, 0.6)]    # fin top, belly
const LEAVE_HEIGHT := 2.0                   # m: higher than this, the pilot cannot get out
## the cockpit: the pilot's seat and eye (front left: the game's driver side), the passenger's (front right)
const CAB := {"driver_seat": [0.4, 1.0, 2.25], "driver_eye": [0.4, 1.92, 2.42],
		"passenger_seat": [-0.4, 1.0, 2.25], "passenger_eye": [-0.4, 1.92, 2.42], "figure": 0.95}

var rotor := 0.0                            # 0 still .. 1 flight speed
var collective := 0.0                       # -1 down .. 1 up (Ctrl / Shift), eased
var cyclic := Vector2.ZERO                  # nose up (+) / down, bank left (+) / right, eased
var on_ground := true
var height := 0.0                           # m from the skids to the ground below
var _rotor_main: Node3D
var _rotor_tail: Node3D
var _disc_mat: StandardMaterial3D
var _main_angle := 0.0
var _tail_angle := 0.0
var _search: SpotLight3D
var _search_lamp: MeshInstance3D
var _lens_mats: Array[StandardMaterial3D] = []     # searchlight lens: off, on
var _beacon_nodes: Array[MeshInstance3D] = []
var _clock := 0.0
var _height_t := 0.0                        # remote copies measure their height now and then


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "Helicopter_" + model.replace("-", "_")
	mass = MASS
	max_speed = TOP_SPEED
	pose_asleep = true                      # LAN: watched from afar (car.gd)
	camera_distance = 14.0
	_configure_body(self)
	var skids := PhysicsMaterial.new()
	skids.friction = 0.9                    # it stays where it lands, even on a slope
	skids.bounce = 0.0
	physics_material_override = skids
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # the attitude's damping is ours
	angular_damp = 0.4
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE    # the air's drag is ours
	linear_damp = 0.0
	continuous_cd = true
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "")]})
	var m: Node3D = load("res://assets/cars/" + spec["file"]).instantiate()
	m.name = "Model"
	add_child(m)
	_rotor_main = m.find_child("rotor_main", true, false) as Node3D
	_rotor_tail = m.find_child("rotor_tail", true, false) as Node3D
	_build_disc()
	# collision: the cabin, the engine deck, the tail boom, its stabiliser and fin, the two skids (it rests on them)
	_add_box(self, Vector3(0.0, 1.75, 1.5), Vector3(1.7, 2.0, 5.0))
	_add_box(self, Vector3(0.0, 2.95, -0.2), Vector3(1.2, 0.5, 2.6))
	_add_box(self, Vector3(0.0, 1.7, -3.8), Vector3(0.6, 0.8, 5.0))
	_add_box(self, Vector3(0.0, 1.7, -4.2), Vector3(2.9, 0.15, 1.0))
	_add_box(self, Vector3(0.0, 2.3, -6.9), Vector3(0.5, 3.0, 1.4))
	for side: float in [1.0, -1.0]:
		_add_box(self, Vector3(SKID.x * side, SKID.y, SKID.z), SKID_SIZE)
	half_extents = Vector3(1.6, 1.9, 5.8)
	extents_center = Vector3(0.0, 0.0, -1.8)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 1.6, 0.5)
	inertia = Vector3(6000.0, 7000.0, 2000.0)  # pitch, yaw, roll
	_total_mass = mass
	_wheel_count = 1
	_set_max_health()
	smoke_spot = Vector3(0.0, 3.0, -0.6)    # the turbines, behind the mast
	smoke_size = 1.2
	_build_cab(m, CAB)
	_build_searchlight()
	_build_beacons()

	audio = VehicleAudio.new()
	audio.position = Vector3(0.0, 2.9, -0.4)
	audio.setup("helicopter")
	add_child(audio)
	_build_chase_camera(camera_distance, 3.2)


## A faint disc over the main rotor's blades, blurring them at speed (the blades themselves turn slower: the eye could
## not follow them anyway).
func _build_disc() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = ROTOR_RADIUS
	disc.bottom_radius = ROTOR_RADIUS
	disc.height = 0.02
	disc.radial_segments = 40
	disc.rings = 1
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.albedo_color = Color(0.12, 0.12, 0.13, 0.0)
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	disc.material = _disc_mat
	var mi := MeshInstance3D.new()
	mi.name = "RotorDisc"
	mi.mesh = disc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = HUB
	add_child(mi)


## The searchlight under the nose (the headlights, L): a narrow beam ahead and down, its lens glowing.
func _build_searchlight() -> void:
	_search = SpotLight3D.new()
	_search.name = "Searchlight"
	_search.light_color = Color(1.0, 0.96, 0.88)
	_search.light_energy = 30.0
	_search.light_specular = 0.2
	_search.spot_range = 160.0
	_search.spot_angle = 9.0
	_search.spot_angle_attenuation = 0.8
	_search.spot_attenuation = 0.4
	_search.distance_fade_enabled = true
	_search.distance_fade_begin = 300.0
	_search.distance_fade_length = 40.0
	_search.position = SEARCHLIGHT
	_search.basis = Basis.looking_at(Vector3(0.0, -sin(SEARCH_DOWN), cos(SEARCH_DOWN)), Vector3.UP)
	_search.visible = false
	add_child(_search)
	for lit in [false, true]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.85, 0.8) if not lit else Color(1.0, 0.97, 0.9)
		mat.emission_enabled = lit
		mat.emission = Color(1.0, 0.96, 0.85)
		mat.emission_energy_multiplier = 6.0
		_lens_mats.append(mat)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.11
	lens.bottom_radius = 0.11
	lens.height = 0.03
	lens.radial_segments = 16
	lens.rings = 1
	_search_lamp = MeshInstance3D.new()
	_search_lamp.mesh = lens
	_search_lamp.material_override = _lens_mats[0]
	_search_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_search_lamp.position = SEARCHLIGHT + _search.basis.z * -0.12
	_search_lamp.basis = _search.basis * Basis(Vector3.RIGHT, PI * 0.5)    # the disc faces along the beam
	add_child(_search_lamp)


func _build_beacons() -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 10
	bulb.rings = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.08, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 8.0
	bulb.material = mat
	for p: Vector3 in BEACONS:
		var mi := MeshInstance3D.new()
		mi.mesh = bulb
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = p
		mi.visible = false
		add_child(mi)
		_beacon_nodes.append(mi)


# ---------------------------------------------------------------- flying

func set_driving(on: bool) -> void:
	super(on)
	can_sleep = not on and pilot == null    # a resting body ignores forces: the rotor's would never lift it
	if not on:
		collective = 0.0
		cyclic = Vector2.ZERO


## A bot takes the controls (scripts/police/air/heli_pilot.gd) or leaves them (null: the rotor winds down).
func set_pilot(p: Object) -> void:
	super(p)
	can_sleep = p == null and not driving
	if p == null and not driving:
		collective = 0.0
		cyclic = Vector2.ZERO


## Why the pilot may not get out now ("" they may): only on the ground, or nearly (game.gd exit_car).
func leave_problem() -> String:
	if on_ground or height < LEAVE_HEIGHT:
		return ""
	return "Land first: %d m up" % roundi(height)


## In the air, out of the bots' way (scripts/traffic/perception.gd).
func flying() -> bool:
	return not on_ground and height > 4.0


## R: level, along its heading, where it is (on the ground: upright, like a car).
func _put_back_on_wheels() -> void:
	if on_ground or height < 1.0:
		super()
		return
	var f := global_basis.z
	global_basis = Basis(Vector3.UP, atan2(f.x, f.z))
	angular_velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if riding and controls:
		super(event)                        # the passenger looks around
		return
	if not driving or not controls:
		return
	if event.is_action_pressed("reset_vehicle"):
		_put_back_on_wheels()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		set_cab_view(not cab_view)
		get_viewport().set_input_as_handled()
	elif not event is InputEventKey or event.is_action("camera_mode"):
		super(event)                        # mouse look, zoom and the camera mode


func _physics_process(delta: float) -> void:
	_clock += delta
	if remote:
		_remote_process(delta)
		return
	if _carry_ticks > 0:                    # just taken over from another peer: it goes on as it went (car.gd)
		_carry_ticks -= 1
		for c: Array in _carried:
			c[0].linear_velocity = c[1]
			c[0].angular_velocity = c[2]
	if _parked(delta):
		return
	var drowned := _water_physics(delta)
	var keys := Vector3.ZERO                # nose up, bank left, turn left
	var lift_in := 0.0
	var piloted := pilot != null and not driving
	if driving and controls and not hold:
		keys = Vector3(Input.get_axis("plane_nose_down", "plane_nose_up"),
				Input.get_axis("plane_roll_right", "plane_roll_left"),
				Input.get_axis("plane_rudder_right", "plane_rudder_left"))
		lift_in = Input.get_axis("plane_throttle_down", "plane_throttle_up")
	elif piloted:
		var c: Array = pilot.fly(delta)
		keys = Vector3(c[0], c[1], c[2])
		lift_in = c[3]
	cyclic = cyclic.move_toward(Vector2(keys.x, keys.y), 4.0 * delta)
	collective = move_toward(collective, lift_in, 3.0 * delta)
	_throttle = collective
	var engine := (driving or piloted) and not broken and not drowned
	rotor = move_toward(rotor, 1.0 if engine else 0.0, delta / (SPOOL_UP if engine else SPOOL_DOWN))
	_measure_height()

	var b := global_basis.orthonormalized()
	var v := linear_velocity
	var g: float = get_gravity().length()
	var power := rotor * rotor * (1.0 - smoothstep(CEILING - 40.0, CEILING, global_position.y))
	# lift along the rotor's axis: what it takes to climb or sink at the wanted rate, none sitting with the
	# collective down
	var lift := 0.0
	if not (on_ground and collective <= 0.05):
		var want_vz := collective * (CLIMB if collective > 0.0 else DESCENT)
		lift = clampf(mass * (g + VZ_GAIN * (want_vz - v.y)) / maxf(b.y.y, 0.4), 0.0, LIFT_MAX * mass * g * power)
	var force := b.y * lift - v * (v.length() * DRAG + DRIFT * mass)
	if cyclic.length() < 0.05 and not on_ground:
		force -= Vector3(v.x, 0.0, v.z) * HOLD * mass * power      # settling into a hover
	apply_central_force(force)

	# attitude: pitch and bank chase the cyclic's (level when released), the tail rotor a turn rate; in the air only
	var pitch := asin(clampf(b.z.y, -1.0, 1.0))         # + nose up
	var bank := asin(clampf(b.x.y, -1.0, 1.0))          # + left side up
	var want_pitch := cyclic.x * (TILT.y if cyclic.x > 0.0 else TILT.x)
	var want_bank := -cyclic.y * TILT.z
	var wl := b.transposed() * angular_velocity
	var fast := smoothstep(5.0, 25.0, Vector2(v.x, v.z).length())
	var want_turn := keys.z * YAW_RATE - bank * BANK_TURN * fast
	var air := 0.0 if on_ground else power
	var acc := Vector3((-ATT_K * (want_pitch - pitch) - ATT_D * wl.x) * air, YAW_K * (want_turn - wl.y) * power,
			(ATT_K * (want_bank - bank) - ATT_D * wl.z) * air)
	apply_torque(b * (inertia * acc))
	_check_crash()
	_update_damage(delta)
	_rotor_sound()
	audio.update(rotor * TOP_SPEED, 0.4 + 0.6 * absf(collective), TOP_SPEED, delta)


## Parked: nobody at the controls nor flying it, its rotor still, at rest: asleep (true) after car.gd's PARK_SLEEP s.
func _parked(delta: float) -> bool:
	if driving or pilot != null or rotor > 0.0 or broken:
		_rest_t = 0.0
		return false
	_sleep_parked(linear_velocity.length(), delta)
	return _asleep()


## The sound follows the rotor, not who is at the controls: it goes on while the blades wind down after the pilot got
## out (and starts as they spin up), quieter and lower below ROTOR_HEARD of their speed, silent once they stand still.
const ROTOR_HEARD := 0.4

func _rotor_sound() -> void:
	var k := clampf(rotor / ROTOR_HEARD, 0.0, 1.0)
	audio.engine_on = rotor > 0.01
	audio.level = k
	audio.slow = lerpf(0.55, 1.0, k)


## From the skids to the ground (or a roof, a tree, a vehicle: whatever it may rest on) below.
func _measure_height() -> void:
	var p := global_position + global_basis.y * 0.5
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 600.0,
			Layers.SOLID | Layers.PROPS | Layers.VEHICLES | Layers.VEGETATION)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	height = global_position.y - hit["position"].y if hit else 999.0
	on_ground = height < GROUND


func _remote_process(delta: float) -> void:
	_height_t -= delta
	if _height_t <= 0.0:
		_height_t = 0.25
		_measure_height()
	if is_remote_asleep():
		return                              # far from the eye: hushed (car.gd)
	_rotor_sound()
	audio.update(rotor * TOP_SPEED, 0.4 + 0.6 * absf(_throttle), TOP_SPEED, delta)


## LAN games: the car's state (the collective as the pedal) and the rotor's speed after it.
func net_state() -> Array:
	var s := super()
	s.append(rotor)
	return s


func apply_net_state(a: Array, b: Array, w: float) -> void:
	super(a, b, w)
	if b.size() > 7:
		rotor = lerpf(a[7], b[7], minf(w, 1.0)) if a.size() > 7 else float(b[7])
	_rotor_sound()


## The searchlight (L, and at night when someone gets in, game.gd), its beam's shadows only for the pilot here.
func set_headlights(on: bool) -> void:
	if on == headlights:
		return
	headlights = on
	_search.visible = on
	_search.shadow_enabled = on and driving
	_search_lamp.material_override = _lens_mats[1 if on else 0]


func dash_text() -> String:
	var line := "%3d km/h   alt %d m   %+.1f m/s   rotor %d%%" % [roundi(linear_velocity.length() * 3.6),
			roundi(height), linear_velocity.y, roundi(rotor * 100.0)]
	if broken:
		line += "\nENGINE DEAD · repaired in %d s" % ceili(repair_in())
	elif rotor < 0.97 and driving:
		line += "\nROTOR SPOOLING UP"
	elif not on_ground and height < 12.0 and linear_velocity.y < -5.0:
		line += "\nSINKING FAST"
	if headlights:
		line += "\nsearchlight on"
	return line


# ---------------------------------------------------------------- looks

func _process(delta: float) -> void:
	super(delta)
	var spin := rotor * ROTOR_SPIN
	_main_angle = fmod(_main_angle + spin * delta, TAU)
	_tail_angle = fmod(_tail_angle + spin * TAIL_SPIN * delta, TAU)
	if _rotor_main:
		_rotor_main.rotation = Vector3(0.0, _main_angle, 0.0)
	if _rotor_tail:
		_rotor_tail.rotation = Vector3(_tail_angle, 0.0, 0.0)
	_disc_mat.albedo_color.a = 0.28 * smoothstep(0.5, 0.95, rotor)
	var blink := (rotor > 0.05 or driving) and fmod(_clock, 1.0) < 0.12
	for mi in _beacon_nodes:
		mi.visible = blink
