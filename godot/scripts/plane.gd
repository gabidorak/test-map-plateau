extends "res://scripts/car.gd"
## Small toy biplane (Car.SPECS "biplane"), built from primitive shapes at runtime: a taildragger VehicleBody3D whose
## three wheels roll it on the ground, with arcade aerodynamics on top (lift with a stall, drag, propeller thrust that
## fades with the airspeed) and rate-hold controls: released keys keep the attitude, the nose follows the airflow
## (weathervane) and the wings level themselves gently from a shallow bank. game.gd gets in and out of it like a car,
## LAN games sync it like a car (net_state also carries the throttle lever and the control surfaces).
## Keys while flying (the Settings actions, scripts/settings.gd; defaults on physical positions): Shift / Ctrl throttle
## up / down, W / S nose down / up (a stick: S pulls), A / D roll (steer on the ground), Q / E rudder (A / E on AZERTY),
## Ctrl at idle brakes on the ground, R levels the wings in the air (back on the wheels on the ground), V or the mouse
## wheel zoomed all the way in: cockpit view; L (game.gd) switches the landing lights in the lower wing (car.gd headlights).
## The upper wing tips leave a thin white trail at flying speed (WingTrail), on every peer.
## The armed version (Car.SPECS "guns": "biplane-armed") wears a khaki livery with French roundels and has two machine
## guns under the lower wing (scripts/plane_guns.gd), fired with the left mouse button (held), converging AIM_DISTANCE
## ahead on the line through the ring sight; game.gd shows where on the screen (aim_point). Shot down (car.gd health),
## its engine dies and it glides down trailing black smoke.
## The two-seater (Car.SPECS "turret": "biplane-gunner", navy and cream) has no wing guns: its gunner, in the rear
## cockpit (the car's passenger seat: E from the plane's right side, or while another player flies it), works a ball
## turret under the belly. The barrel swings at most TURRET_CONE (45°) off the nose and no higher than TURRET_UP (the
## lower wing is just above it); it turns at TURRET_RATE towards what the middle of the gunner's screen shows (up to
## TURRET_RANGE ahead), and the left mouse button (held) fires it. The turret view (V, or the mouse wheel zoomed all
## the way in) looks down the barrel from the ball, the mouse turning it within its reach; game.gd rings where the
## barrel points (turret_aim_point). LAN games: the gunner's own player state carries the turret (gunner_state), so
## the hits count on the gunner's peer, whoever simulates the plane, and the other peers fire it for show.
## Frame: like the cars, +Z forward, +X the left wing, origin on the ground under the main wheels with the fuselage
## level; parked, the plane rests on its tail wheel, nose up by ~11°.

const MASS := 500.0                         # kg
const THRUST := 3600.0                      # N at a standstill, full throttle...
const PROP_MAX := 62.0                      # ...fading to nothing at this airspeed (m/s)
const LIFT_K := 13.0                        # ½ρS: lift = LIFT_K · CL · v², drag likewise
const CL0 := 0.3                            # lift coefficient at zero angle of attack: level at ~35 m/s
const CL_SLOPE := 4.5                       # per rad
const STALL := 0.26                         # rad of angle of attack where the lift breaks down
const CD0 := 0.035                          # drag coefficients: parasitic, induced (· CL²), flat plate (· sin² of
const CDI := 0.05                           # the air hitting the wings from below)
const CD_FLAT := 1.0
const SIDE_K := 20.0                        # sideways force per m/s of side slip, per m/s of airspeed
const PITCH_RATE := 1.5                     # rad/s at full stick
const ROLL_RATE := 2.8
const YAW_RATE := 0.7
const GROUND_YAW_RATE := 0.9                # rad/s turning on the ground (tail wheel + rudder)
const RATE_GAIN := 6.0                      # /s: how hard the controls chase the wanted rates
const WEATHERVANE := Vector2(0.05, 0.1)     # rad/s per (m/s · rad): the nose turning into the airflow, pitch and yaw
											# (pitch weaker: the nose keeps a climb the stick set)
const SELF_LEVEL := 0.5                     # /s, roll back towards wings level when A/D are released (bank < 60°)
const LEVER_RATE := 0.7                     # throttle lever travel per second (Shift / Ctrl)
const CEILING := 190.0                      # m (Godot y): the engine fades out over the last 60 m below it (the map's
											# boundary walls stop at y = 200)
const TRAIL_SPEED := 15.0                   # m/s from which the wing tips leave trails
const MAIN_GEAR := Vector3(0.85, 0.3, 0.55) # main wheel centre (left one; mirrored), and its radius is the y
const TAIL_WHEEL := Vector3(0.0, 0.86, -3.35)
const TAIL_WHEEL_RADIUS := 0.11
const UPPER_WING := Vector4(3.3, 2.25, 0.75, 1.15)     # half span, height, chord centre z, chord
const LOWER_WING := Vector4(3.0, 0.86, 0.45, 1.1)
const PROP_HUB := Vector3(0.0, 1.3, 2.18)
const PROP_RADIUS := 0.95
const PILOT_SEAT := Vector3(0.0, 1.3, -0.6)            # cockpit opening, on the fuselage axis
const GUN := Vector3(1.55, 0.76, 1.72)      # armed: left wing gun's barrel axis (x, height) and muzzle z; mirrored
const AIM_DISTANCE := 200.0                 # m ahead where the two guns' rounds cross...
const EYE_HEIGHT := 2.08                    # ...on the pilot's line of sight through the ring sight
const REAR_SEAT := Vector3(0.0, 1.26, -1.55)           # two-seater: the gunner's cockpit opening
const TURRET := Vector3(0.0, 0.62, -0.3)    # ball turret under the belly: its centre, where the barrel pivots
const TURRET_BALL := 0.2                    # m, radius
const TURRET_BARREL := 0.78                 # m from the pivot to the muzzle
const TURRET_CONE := PI / 4.0               # rad, furthest the barrel swings off the nose...
const TURRET_UP := 0.12                     # ...and above the plane's axis (rad)
const TURRET_RATE := 3.5                    # rad/s
const TURRET_RANGE := 600.0                 # m, how far the gunner's line of sight is followed
const TURRET_LAYER := 1 << 19               # render layer the turret view leaves out: the ball, its neck, the landing
											# gear right in front of it
const COLORS := {"body": Color(0.86, 0.22, 0.2), "wing": Color(0.98, 0.82, 0.3), "trim": Color(0.96, 0.95, 0.9),
		"metal": Color(0.75, 0.77, 0.8), "dark": Color(0.16, 0.16, 0.18), "wood": Color(0.55, 0.33, 0.16)}
const ARMED_COLORS := {"body": Color(0.36, 0.43, 0.22), "wing": Color(0.66, 0.62, 0.4), "trim": Color(0.93, 0.9, 0.78),
		"blue": Color(0.1, 0.24, 0.62), "white": Color(0.97, 0.97, 0.95), "red": Color(0.86, 0.13, 0.12)}
const GUNNER_COLORS := {"body": Color(0.17, 0.3, 0.52), "wing": Color(0.94, 0.88, 0.7), "trim": Color(0.86, 0.22, 0.2)}
const Guns = preload("res://scripts/plane_guns.gd")

var lever := 0.0                            # throttle lever 0..1
var surfaces := Vector3.ZERO                # control surfaces -1..1: pitch up, roll left, yaw left (smoothed keys)
var on_ground := false
var height := 0.0                           # m above the ground or roof below
var stalled := false
var _main_wheels: Array[VehicleWheel3D] = []
var _tail_wheel: VehicleWheel3D
var _prop: Node3D
var _prop_disc: MeshInstance3D
var _prop_angle := 0.0
var _elevator: Node3D
var _rudder: Node3D
var _ailerons: Array[Node3D] = []           # left, right
var _trails: Array[WingTrail] = []
var _tips: Array[Vector3] = []              # upper wing tips, plane frame
var _last_pos := Vector3.INF                # for the trails' speed (remote planes too)
var _trail_time := 0.0                      # s of game time, the trails' clock
var _cam_q := Quaternion.IDENTITY           # chase camera orientation, eased towards the plane's
var _mats := {}
var armed := false
var guns: Guns                              # armed version only
var turret := false                         # two-seater with a belly turret
var turret_guns: Guns                       # its gun (live while the gunner is the player here)
var turret_dir := Vector3.BACK              # where the barrel points, plane frame (unit)
var gun_look := Vector2(0.0, -0.1)          # turret view: yaw (+ to the left) and pitch (+ up) of the gunner's eye
var gunner_target := Vector3.INF            # global, what the gunner looks at (INF: none yet)
var _aim_dist := AIM_DISTANCE               # m along the barrel where its rounds are aimed (the target's distance)
var _out_of_arc := false                    # the gunner looks where the turret cannot point
var _turret_yaw: Node3D
var _turret_pitch: Node3D
var _turret_camera: Camera3D
var _turret_query := PhysicsRayQueryParameters3D.new()


func setup(model: String) -> void:
	var spec: Dictionary = SPECS[model]
	model_name = model
	name = "Plane_" + model.replace("-", "_")
	mass = MASS
	max_speed = PROP_MAX
	camera_distance = 11.0
	_configure_body(self)
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.6
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # the air drag is ours
	linear_damp = 0.0
	continuous_cd = true                    # 45 m/s is most of a metre per physics tick
	set_meta("plateau", {"type": "car", "id": "%s vehicle (%s)" % [model, spec.get("credit", "")]})
	armed = spec.get("guns", false)
	turret = spec.get("turret", false)
	var colors: Dictionary = COLORS.merged(ARMED_COLORS, true) if armed \
			else COLORS.merged(GUNNER_COLORS, true) if turret else COLORS
	for k: String in colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[k]
		m.roughness = 0.55 if k != "metal" else 0.35
		m.metallic = 0.4 if k == "metal" else 0.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # lofts whatever their winding: back faces flip their normals
		_mats[k] = m
	var model_root := Node3D.new()
	model_root.name = "Model"
	add_child(model_root)
	_build_model(model_root)
	_build_wheels()
	# landing lights in the lower wing's leading edge (the headlights, L)
	var edge := LOWER_WING.z + LOWER_WING.w * 0.5
	var lights: Array[Vector3] = [Vector3(2.2, LOWER_WING.y, edge), Vector3(-2.2, LOWER_WING.y, edge)]
	add_headlights(lights, Vector3(0.26, 0.07, 0.05))
	# collision boxes (breakables.gd sweeps them too): front and rear fuselage, both wings, tail
	_add_box(self, Vector3(0.0, 1.32, 0.45), Vector3(0.95, 1.05, 3.3))
	_add_box(self, Vector3(0.0, 1.45, -2.3), Vector3(0.6, 0.6, 2.2))
	_add_box(self, Vector3(0.0, UPPER_WING.y, UPPER_WING.z), Vector3(UPPER_WING.x * 2.0, 0.16, UPPER_WING.w))
	_add_box(self, Vector3(0.0, LOWER_WING.y, LOWER_WING.z), Vector3(LOWER_WING.x * 2.0, 0.14, LOWER_WING.w))
	_add_box(self, Vector3(0.0, 1.92, -3.2), Vector3(2.3, 0.95, 0.7))
	half_extents = Vector3(UPPER_WING.x, 1.25, 2.9)
	extents_center = Vector3(0.0, 0.0, -0.62)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.95, 0.0)
	inertia = Vector3(700.0, 1100.0, 650.0)  # pitch, yaw, roll
	_total_mass = mass
	_wheel_count = 3
	_set_max_health()
	smoke_spot = Vector3(0.0, 1.5, 1.7)     # the engine, behind the cowling
	if armed:
		guns = Guns.new()
		var muzzles: Array[Vector3] = [Vector3(GUN.x, GUN.y, GUN.z), Vector3(-GUN.x, GUN.y, GUN.z)]
		guns.setup(muzzles, Vector3(0.0, EYE_HEIGHT, AIM_DISTANCE))
		add_child(guns)
	if turret:
		has_passenger_seat = true
		passenger_seat = REAR_SEAT
		turret_guns = Guns.new()
		var muzzle: Array[Vector3] = [TURRET + turret_dir * TURRET_BARREL]
		turret_guns.setup(muzzle, TURRET + turret_dir * _aim_dist)
		turret_guns.name = "TurretGun"
		turret_guns.live = false
		add_child(turret_guns)
		_turret_query.collision_mask = Guns.MASK
		_turret_query.exclude = [get_rid()]
		_turret_camera = Camera3D.new()
		_turret_camera.name = "TurretCamera"
		_turret_camera.fov = 65.0
		_turret_camera.near = 0.05
		_turret_camera.far = 1500.0
		_turret_camera.cull_mask = 0xFFFFF & ~TURRET_LAYER
		_turret_camera.position = TURRET + Vector3(0.0, 0.15, -0.05)
		add_child(_turret_camera)

	audio = VehicleAudio.new()
	audio.position = PROP_HUB - Vector3(0.0, 0.0, 0.6)
	audio.setup("plane")
	add_child(audio)

	_build_chase_camera(camera_distance, 1.2)
	_cab_camera = Camera3D.new()
	_cab_camera.fov = 80.0
	_cab_camera.near = 0.05
	_cab_camera.far = 1500.0
	_cab_camera.position = PILOT_SEAT + Vector3(0.0, 0.78, 0.05)
	_cab_camera.rotation = Vector3(-0.1, PI, 0.0)
	add_child(_cab_camera)

	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side: float in [1.0, -1.0]:
		_tips.append(Vector3(side * (UPPER_WING.x - 0.04), UPPER_WING.y, UPPER_WING.z - UPPER_WING.w * 0.2))
		var trail := WingTrail.new(trail_mat)
		trail.name = "Trail"
		add_child(trail)
		_trails.append(trail)


# ---------------------------------------------------------------- model

func _build_model(root: Node3D) -> void:
	# fuselage: rounded sections from the cowling to the tail post (z, centre height, half width, half height)
	var fus := []
	for s: Vector4 in [Vector4(2.1, 1.3, 0.3, 0.3), Vector4(2.02, 1.3, 0.4, 0.4), Vector4(1.7, 1.29, 0.47, 0.47),
			Vector4(0.9, 1.3, 0.49, 0.52), Vector4(-0.2, 1.33, 0.47, 0.5), Vector4(-1.2, 1.37, 0.37, 0.41),
			Vector4(-2.4, 1.43, 0.23, 0.27), Vector4(-3.3, 1.48, 0.09, 0.11), Vector4(-3.42, 1.48, 0.03, 0.04)]:
		fus.append([Vector3(0.0, s.y, s.x), Vector3(s.z, 0.0, 0.0), Vector3(0.0, s.w, 0.0)])
	_mesh(root, _loft(fus, 3.0), "body")
	# cowling ring and the trim stripe along the fuselage
	_mesh(root, _loft([[Vector3(0.0, 1.3, 2.13), Vector3(0.33, 0.0, 0.0), Vector3(0.0, 0.33, 0.0)],
			[Vector3(0.0, 1.3, 1.62), Vector3(0.495, 0.0, 0.0), Vector3(0.0, 0.495, 0.0)]], 3.0), "metal")
	for side: float in [1.0, -1.0]:
		_mesh(root, _loft([[Vector3(side * 0.47, 1.33, 1.2), Vector3(0.0, 0.0, 0.02), Vector3(0.0, 0.06, 0.0)],
				[Vector3(side * 0.43, 1.37, -0.8), Vector3(0.0, 0.0, 0.02), Vector3(0.0, 0.055, 0.0)],
				[Vector3(side * 0.22, 1.44, -2.4), Vector3(0.0, 0.0, 0.02), Vector3(0.0, 0.04, 0.0)]], 2.0, 8), "trim")
	# cockpit rim, windscreen
	var rim := TorusMesh.new()
	rim.inner_radius = 0.3
	rim.outer_radius = 0.38
	_mesh(root, rim, "dark").transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.25)), PILOT_SEAT + Vector3(0.0, 0.5, 0.0))
	var screen := BoxMesh.new()
	screen.size = Vector3(0.5, 0.26, 0.02)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var ws := MeshInstance3D.new()
	ws.mesh = screen
	ws.material_override = glass
	ws.transform = Transform3D(Basis(Vector3.RIGHT, -0.5), PILOT_SEAT + Vector3(0.0, 0.62, 0.52))
	ws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ws)

	# wings, struts
	for w: Vector4 in [UPPER_WING, LOWER_WING]:
		_mesh(root, _wing(w.x, w.y, w.z, w.w, 0.07 if w == UPPER_WING else 0.065), "wing")
	for side: float in [1.0, -1.0]:
		var x := side * (LOWER_WING.x - 0.65)
		for dz: float in [0.3, -0.3]:       # interplane struts, leaning forward with the upper wing's stagger
			_rod(root, Vector3(x, LOWER_WING.y, LOWER_WING.z + dz), Vector3(x, UPPER_WING.y, UPPER_WING.z + dz), 0.035, "dark")
			_rod(root, Vector3(side * 0.28, 1.72, UPPER_WING.z + dz), Vector3(side * 0.5, UPPER_WING.y, UPPER_WING.z + dz), 0.03, "dark")
		# landing gear: a V from the fuselage to the axle
		var axle := Vector3(side * MAIN_GEAR.x, MAIN_GEAR.y, MAIN_GEAR.z)
		_rod(root, Vector3(side * 0.3, 0.85, 1.05), axle, 0.035, "dark").layers = TURRET_LAYER
		_rod(root, Vector3(side * 0.3, 0.85, 0.05), axle, 0.035, "dark").layers = TURRET_LAYER
	_rod(root, Vector3(MAIN_GEAR.x, MAIN_GEAR.y, MAIN_GEAR.z), Vector3(-MAIN_GEAR.x, MAIN_GEAR.y, MAIN_GEAR.z), 0.03,
			"dark").layers = TURRET_LAYER
	_rod(root, Vector3(0.0, 1.38, -3.05), TAIL_WHEEL + Vector3(0.0, 0.03, 0.0), 0.03, "dark")     # tail wheel leg
	# ailerons behind the outer upper wing, hinged on its trailing edge
	var te := UPPER_WING.z - UPPER_WING.w * 0.5
	for side: float in [1.0, -1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 2.15, UPPER_WING.y, te + 0.02)
		root.add_child(hinge)
		_mesh(hinge, _flap(Vector3(1.3, 0.05, 0.3)), "trim").position = Vector3(0.0, 0.0, -0.15)
		_ailerons.append(hinge)

	# tail: stabilizer + elevator, fin + rudder
	_mesh(root, _wing(1.05, 1.5, -2.95, 0.5, 0.04), "wing")
	_elevator = Node3D.new()
	_elevator.position = Vector3(0.0, 1.5, -3.2)
	root.add_child(_elevator)
	for side: float in [1.0, -1.0]:         # two halves, clear of the rudder
		_mesh(_elevator, _flap(Vector3(0.9, 0.045, 0.32)), "trim").position = Vector3(side * 0.54, 0.0, -0.16)
	var fin := []
	for s: Vector3 in [Vector3(1.45, -2.95, 0.33), Vector3(1.55, -2.95, 0.36), Vector3(2.2, -3.1, 0.24),
			Vector3(2.38, -3.18, 0.12), Vector3(2.42, -3.2, 0.04)]:     # height, chord centre z, half chord
		fin.append([Vector3(0.0, s.x, s.y), Vector3(0.0, 0.0, s.z), Vector3(0.04, 0.0, 0.0)])
	_mesh(root, _loft(fin, 2.5), "body")
	_rudder = Node3D.new()
	_rudder.position = Vector3(0.0, 1.5, -3.27)
	root.add_child(_rudder)
	var rudder := _mesh(_rudder, _loft([[Vector3(0.0, 0.0, -0.2), Vector3(0.0, 0.0, 0.2), Vector3(0.035, 0.0, 0.0)],
			[Vector3(0.0, 0.85, -0.14), Vector3(0.0, 0.0, 0.14), Vector3(0.03, 0.0, 0.0)],
			[Vector3(0.0, 0.92, -0.05), Vector3(0.0, 0.0, 0.05), Vector3(0.02, 0.0, 0.0)]], 2.5), "trim")
	rudder.position = Vector3(0.0, -0.05, 0.0)

	# propeller: spinner, two blades, and a faint disc once it spins fast
	_prop = Node3D.new()
	_prop.position = PROP_HUB
	root.add_child(_prop)
	var spinner := SphereMesh.new()
	spinner.radius = 0.17
	spinner.height = 0.45
	_mesh(_prop, spinner, "trim").rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for side: float in [1.0, -1.0]:
		_mesh(_prop, _loft([[Vector3(0.0, side * 0.12, 0.0), Vector3(0.07, 0.0, 0.0), Vector3(0.0, 0.0, 0.035)],
				[Vector3(0.0, side * 0.5, 0.0), Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.0, 0.025)],
				[Vector3(0.0, side * (PROP_RADIUS - 0.05), 0.0), Vector3(0.07, 0.0, 0.0), Vector3(0.0, 0.0, 0.02)],
				[Vector3(0.0, side * PROP_RADIUS, 0.0), Vector3(0.02, 0.0, 0.0), Vector3(0.0, 0.0, 0.01)]], 2.5, 10), "wood")
	var disc := CylinderMesh.new()
	disc.top_radius = PROP_RADIUS
	disc.bottom_radius = PROP_RADIUS
	disc.height = 0.005
	disc.radial_segments = 32
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.55, 0.4, 0.25, 0.0)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_prop_disc = MeshInstance3D.new()
	_prop_disc.mesh = disc
	_prop_disc.material_override = disc_mat
	_prop_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop_disc.position = PROP_HUB + Vector3(0.0, 0.0, 0.02)
	_prop_disc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	root.add_child(_prop_disc)

	# the pilot (the driver look-alike of car.gd: shown while someone flies, in their colour) in a leather helmet
	_driver_dummy = Node3D.new()
	_driver_dummy.visible = false
	add_child(_driver_dummy)
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = Color(1, 0.55, 0.2)
	_skin.roughness = 0.6
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.24
	capsule.height = 0.95
	capsule.material = _skin
	_driver_body = MeshInstance3D.new()
	_driver_body.mesh = capsule
	_driver_body.position = PILOT_SEAT + Vector3(0.0, 0.38, 0.0)
	_driver_dummy.add_child(_driver_body)
	var helmet := SphereMesh.new()
	helmet.radius = 0.215
	helmet.height = 0.3
	helmet.is_hemisphere = true
	var cap := _mesh(_driver_body, helmet, "wood")
	cap.position = Vector3(0.0, 0.3, 0.0)
	var goggles := TorusMesh.new()
	goggles.inner_radius = 0.2
	goggles.outer_radius = 0.235
	_mesh(_driver_body, goggles, "dark").transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3(0.0, 0.3, 0.0))
	if armed:
		_build_armament(root)
	if turret:
		_build_turret(root)


## Armed version: a machine gun under each lower wing (receiver, cooling jacket, barrel), roundels on the upper wing and
## the fuselage sides, a ring sight ahead of the windscreen.
func _build_armament(root: Node3D) -> void:
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.13, 0.11, 0.5)
	for side: float in [1.0, -1.0]:
		var x := side * GUN.x
		_mesh(root, receiver, "dark").position = Vector3(x, GUN.y + 0.02, 0.8)
		_rod(root, Vector3(x, GUN.y, 1.05), Vector3(x, GUN.y, 1.38), 0.045, "dark")         # jacket
		_rod(root, Vector3(x, GUN.y, 1.38), Vector3(x, GUN.y, GUN.z), 0.022, "metal")       # barrel
		_rod(root, Vector3(x, GUN.y, GUN.z - 0.07), Vector3(x, GUN.y, GUN.z), 0.034, "dark")  # muzzle
		# roundels: blue, white, red discs, on top of the upper wing and on the fuselage sides
		for k in 3:
			var c := ["blue", "white", "red"][k] as String
			var disc := CylinderMesh.new()
			disc.top_radius = 0.42 * (1.0 - k / 3.0)
			disc.bottom_radius = disc.top_radius
			disc.height = 0.006
			disc.radial_segments = 32
			disc.rings = 1
			_mesh(root, disc, c).position = Vector3(side * 2.45, UPPER_WING.y + 0.072 + 0.004 * k, UPPER_WING.z)
			var side_disc := CylinderMesh.new()
			side_disc.top_radius = 0.22 * (1.0 - k / 3.0)
			side_disc.bottom_radius = side_disc.top_radius
			side_disc.height = 0.006
			side_disc.radial_segments = 32
			side_disc.rings = 1
			_mesh(root, side_disc, c).transform = Transform3D(Basis(Vector3.BACK, PI * 0.5),
					Vector3(side * (0.35 + 0.004 * k), 1.4, -1.45))
	# ring sight with cross wires on a post, on the line of sight
	var sight := Vector3(0.0, EYE_HEIGHT, 0.35)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.085
	ring.outer_radius = 0.1
	ring.rings = 24
	_mesh(root, ring, "dark").transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), sight)
	_rod(root, sight + Vector3(-0.09, 0.0, 0.0), sight + Vector3(0.09, 0.0, 0.0), 0.004, "dark")
	_rod(root, sight + Vector3(0.0, -0.09, 0.0), sight + Vector3(0.0, 0.09, 0.0), 0.004, "dark")
	_rod(root, Vector3(0.0, 1.8, 0.35), sight + Vector3(0.0, -0.095, 0.0), 0.012, "dark")


## Two-seater: the gunner's cockpit and their look-alike (the car's passenger), the ball turret under the belly.
func _build_turret(root: Node3D) -> void:
	var rim := TorusMesh.new()
	rim.inner_radius = 0.28
	rim.outer_radius = 0.36
	_mesh(root, rim, "dark").transform = Transform3D(Basis.from_scale(Vector3(0.85, 0.6, 1.05)), REAR_SEAT + Vector3(0.0, 0.5, 0.0))
	_passenger_skin = _skin.duplicate()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 0.9
	capsule.material = _passenger_skin
	_passenger = MeshInstance3D.new()
	_passenger.name = "Passenger"
	_passenger.mesh = capsule
	_passenger.position = REAR_SEAT + Vector3(0.0, 0.36, 0.0)
	_passenger.visible = false
	add_child(_passenger)
	var helmet := SphereMesh.new()
	helmet.radius = 0.2
	helmet.height = 0.28
	helmet.is_hemisphere = true
	_mesh(_passenger, helmet, "wood").position = Vector3(0.0, 0.28, 0.0)
	var goggles := TorusMesh.new()
	goggles.inner_radius = 0.185
	goggles.outer_radius = 0.22
	_mesh(_passenger, goggles, "dark").transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3(0.0, 0.28, 0.0))
	# the turret: a neck and a flange under the fuselage, the ball turning on it, the gun through the ball
	var neck := CylinderMesh.new()
	neck.top_radius = 0.16
	neck.bottom_radius = 0.13
	neck.height = 0.16
	neck.radial_segments = 16
	var mi := _mesh(root, neck, "metal")
	mi.position = TURRET + Vector3(0.0, 0.17, 0.0)
	mi.layers = TURRET_LAYER
	_turret_yaw = Node3D.new()
	_turret_yaw.name = "Turret"
	_turret_yaw.position = TURRET
	root.add_child(_turret_yaw)
	_turret_pitch = Node3D.new()
	_turret_yaw.add_child(_turret_pitch)
	var ball := SphereMesh.new()
	ball.radius = TURRET_BALL
	ball.height = TURRET_BALL * 2.0
	mi = _mesh(_turret_pitch, ball, "body")
	mi.layers = TURRET_LAYER
	var window := BoxMesh.new()                 # the gunner's sight glass on the side of the ball
	window.size = Vector3(0.02, 0.09, 0.12)
	mi = _mesh(_turret_pitch, window, "dark")
	mi.position = Vector3(TURRET_BALL - 0.01, 0.05, 0.04)
	mi.layers = TURRET_LAYER
	_rod(_turret_pitch, Vector3(0.0, 0.0, TURRET_BALL - 0.04), Vector3(0.0, 0.0, 0.3), 0.04, "dark").layers = TURRET_LAYER
	_rod(_turret_pitch, Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.0, 0.48), 0.032, "dark")                  # jacket
	_rod(_turret_pitch, Vector3(0.0, 0.0, 0.48), Vector3(0.0, 0.0, TURRET_BARREL), 0.024, "metal")       # barrel
	_rod(_turret_pitch, Vector3(0.0, 0.0, TURRET_BARREL - 0.07), Vector3(0.0, 0.0, TURRET_BARREL), 0.036, "dark")


func _mesh(parent: Node3D, mesh: Mesh, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	parent.add_child(mi)
	return mi


## A rod of radius `r` from `a` to `b`.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: String) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 8
	cm.rings = 1
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var mi := _mesh(parent, cm, mat)
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return mi


## Wing of half span `hs` at height `y`, chord centre `zc`, with rounded tips; thick ± `t`.
static func _wing(hs: float, y: float, zc: float, chord: float, t: float) -> ArrayMesh:
	var sections := []
	for k: Vector2 in [Vector2(-1.0, 0.25), Vector2(-0.985, 0.7), Vector2(-0.94, 0.95), Vector2(-0.88, 1.0),
			Vector2(0.88, 1.0), Vector2(0.94, 0.95), Vector2(0.985, 0.7), Vector2(1.0, 0.25)]:  # (span share, chord share)
		var c := chord * 0.5 * k.y
		sections.append([Vector3(k.x * hs, y, zc + chord * 0.5 * (1.0 - k.y) * 0.3), Vector3(0.0, 0.0, c),
				Vector3(0.0, t * (0.4 + 0.6 * k.y), 0.0)])
	return _loft(sections, 2.6)


## A control surface `size` across (x, thickness, chord) centred on the origin, tapering to its trailing edge.
static func _flap(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var sections := []
	for x: float in [-hx, -hx + 0.03, hx - 0.03, hx]:
		var shrink := 0.6 if absf(x) == hx else 1.0
		sections.append([Vector3(x, 0.0, 0.0), Vector3(0.0, 0.0, size.z * 0.5 * shrink), Vector3(0.0, size.y * 0.5 * shrink, 0.0)])
	return _loft(sections, 2.2, 10)


## Closed tube through `sections` ([centre, u, v]: a superellipse of exponent `n` with half axes u and v), capped at
## both ends, smooth-shaded.
static func _loft(sections: Array, n := 4.0, segs := 20) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for s: Array in sections:
		var ring := PackedVector3Array()
		for j in segs:
			var a := TAU * j / segs
			var c := cos(a)
			var sn := sin(a)
			ring.append(s[0] + s[1] * signf(c) * pow(absf(c), 2.0 / n) + s[2] * signf(sn) * pow(absf(sn), 2.0 / n))
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			for p: Vector3 in [rings[k][j], rings[k + 1][j], rings[k + 1][j2], rings[k][j], rings[k + 1][j2], rings[k][j2]]:
				st.add_vertex(p)
	st.set_smooth_group(0xFFFFFFFF)             # flat caps
	for k: int in [0, rings.size() - 1]:
		var centre: Vector3 = sections[k][0]
		for j in segs:
			var a := rings[k][j]
			var b := rings[k][(j + 1) % segs]
			for p: Vector3 in ([centre, b, a] if k == 0 else [centre, a, b]):
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func _build_wheels() -> void:
	for side: float in [1.0, -1.0]:
		_main_wheels.append(_wheel(Vector3(side * MAIN_GEAR.x, MAIN_GEAR.y, MAIN_GEAR.z), MAIN_GEAR.y, 0.15, false))
	_tail_wheel = _wheel(TAIL_WHEEL, TAIL_WHEEL_RADIUS, 0.07, true)


func _wheel(centre: Vector3, r: float, width: float, steer: bool) -> VehicleWheel3D:
	var vw := VehicleWheel3D.new()
	vw.name = "Wheel%d" % get_child_count()
	vw.position = centre + Vector3.UP * REST_LENGTH
	vw.wheel_radius = r
	vw.wheel_rest_length = REST_LENGTH
	vw.suspension_travel = 0.2
	vw.suspension_stiffness = 50.0
	vw.suspension_max_force = 40.0 * mass
	vw.damping_compression = 4.0
	vw.damping_relaxation = 6.0
	vw.wheel_friction_slip = 2.0 if not steer else 1.5
	vw.wheel_roll_influence = 0.1
	vw.use_as_steering = steer
	vw.use_as_traction = false
	add_child(vw)
	var tyre := CylinderMesh.new()
	tyre.top_radius = r
	tyre.bottom_radius = r
	tyre.height = width
	tyre.radial_segments = 20
	tyre.rings = 1
	var mi := _mesh(vw, tyre, "dark")
	mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	mi.layers = TURRET_LAYER
	var hub := CylinderMesh.new()
	hub.top_radius = r * 0.45
	hub.bottom_radius = r * 0.45
	hub.height = width + 0.02
	hub.radial_segments = 12
	hub.rings = 1
	mi = _mesh(vw, hub, "trim")
	mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	mi.layers = TURRET_LAYER
	return vw


# ---------------------------------------------------------------- flight

func set_driving(on: bool) -> void:
	super(on)
	can_sleep = not on                      # a resting body ignores forces: the propeller's would never move it
	if not on:
		lever = 0.0                         # whoever gets out cuts the engine: the plane glides on
		if guns:
			guns.firing = false
	audio.engine_on = on and not broken


## R: in the air, wings level along the current heading, at no less than a gliding speed; on the ground, back on the
## wheels like a car.
func _put_back_on_wheels() -> void:
	if on_ground or height < 4.0:
		super()
		return
	var f := global_basis.z
	var b := Basis(Vector3.UP, atan2(f.x, f.z))
	global_basis = b
	linear_velocity = b.z * maxf(linear_velocity.length(), 25.0)
	angular_velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if riding and controls:
		if cab_view and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look_turret(event.screen_relative * sensitivity * Prefs.mouse_scale)
			get_viewport().set_input_as_handled()
		else:
			super(event)                        # chase camera look, zoom, turret view
		return
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


func _physics_process(delta: float) -> void:
	if turret:
		_update_turret(delta)
	if remote:
		_remote_process(delta)
		return
	_water_physics(delta)                   # ditched in a lake: floats a moment, then sinks (car.gd)
	var keys := Vector3.ZERO                # pitch up, roll left, yaw left
	var lever_in := 0.0
	var braking := false
	var trigger := false
	if driving and controls:
		keys = Vector3(Input.get_axis("plane_nose_down", "plane_nose_up"),
				Input.get_axis("plane_roll_right", "plane_roll_left"),
				Input.get_axis("plane_rudder_right", "plane_rudder_left"))
		lever_in = Input.get_axis("plane_throttle_down", "plane_throttle_up")
		braking = lever == 0.0 and lever_in < 0.0
		trigger = Input.is_action_pressed("fire")
	if guns:
		guns.firing = trigger
	lever = clampf(lever + lever_in * LEVER_RATE * delta, 0.0, 1.0)
	surfaces = surfaces.move_toward(keys, 6.0 * delta)
	_throttle = lever
	on_ground = _tail_wheel.is_in_contact()
	for w in _main_wheels:
		on_ground = on_ground or w.is_in_contact()
	_measure_height()

	var b := global_basis.orthonormalized()
	var v := linear_velocity
	var air := v.length()
	var vl := b.transposed() * v           # in the plane frame
	var fwd := maxf(vl.z, 0.0)
	var alpha := atan2(-vl.y, maxf(vl.z, 1.0))     # angle of attack: the air hitting the wings from below
	var beta := atan2(vl.x, maxf(vl.z, 1.0))       # side slip: moving towards the left wing
	var cl := CL0 + CL_SLOPE * alpha
	var cl_max := CL0 + CL_SLOPE * STALL
	stalled = absf(alpha) > STALL and not on_ground and air > 3.0
	if absf(cl) > cl_max:                   # past the stall the lift drops off
		cl = signf(cl) * cl_max * (1.0 - 0.5 * smoothstep(STALL, STALL + 0.35, absf(alpha)))
	var force := Vector3.ZERO
	if air > 0.5:
		var vdir := v / air
		var lift_dir := vdir.cross(b.x)
		if lift_dir.length_squared() > 0.01:
			force += lift_dir.normalized() * LIFT_K * cl * fwd * fwd
		var flat := vl.y / air
		force -= vdir * LIFT_K * (CD0 + CDI * cl * cl + CD_FLAT * flat * flat) * air * air
		force -= b.x * SIDE_K * vl.x * air
	force += b.z * thrust(fwd)
	apply_central_force(force)

	# controls: wanted rates in the plane frame (x pitch: + nose down; y yaw: + nose left; z roll: + right wing down)
	var auth := smoothstep(3.0, 20.0, fwd)
	var want := Vector3(-surfaces.x * PITCH_RATE, surfaces.z * YAW_RATE, -surfaces.y * ROLL_RATE) * auth
	if on_ground:
		# A/D steer like Q/E (tail wheel, and the rudder in the prop wash); the wheels hold the wings level
		want.y = clampf(surfaces.y + surfaces.z, -1.0, 1.0) * GROUND_YAW_RATE * clampf(fwd / 4.0, 0.3, 1.0)
		want.z = 0.0
	else:
		want.x += WEATHERVANE.x * fwd * alpha
		want.y += WEATHERVANE.y * fwd * beta
		var bank := atan2(b.x.y, b.y.y)
		if keys.y == 0.0 and absf(bank) < 1.05:
			want.z -= SELF_LEVEL * bank * auth
	var wl := b.transposed() * angular_velocity
	var gain := Vector3(auth, maxf(auth, 1.0 if on_ground else 0.0), 0.0 if on_ground else auth) * RATE_GAIN
	apply_torque(b * (inertia * (want - wl) * gain))
	steering = -clampf(surfaces.y + surfaces.z, -1.0, 1.0) * 0.5   # the tail wheel turns against the turn
	engine_force = 0.0
	if not driving:
		brake = 0.6 if absf(vl.z) > 1.0 else 12.0     # the parking brake once slow
	else:
		brake = 12.0 if braking else 0.15
	audio.horn = false
	_update_damage(delta)
	audio.update(_rpm() * max_speed, lever, max_speed, delta)


## Propeller thrust (N) at forward airspeed `fwd`: the lever's share, fading with the speed and near the ceiling; none
## once broken.
func thrust(fwd: float) -> float:
	if broken:
		return 0.0
	var thin := 1.0 - smoothstep(CEILING - 60.0, CEILING, global_position.y)
	return THRUST * lever * clampf(1.0 - fwd / PROP_MAX, 0.0, 1.0) * thin


## Engine speed for the sound, 0..1: the lever, plus a little windmilling with the airspeed.
func _rpm() -> float:
	return clampf(lerpf(0.25, 1.0, lever) + 0.15 * speed() / PROP_MAX, 0.0, 1.0) \
			if (audio.engine_on or lever > 0.0) and not broken else 0.0


# ---------------------------------------------------------------- turret

## The gunner here turns the turret towards what they look at and fires it; elsewhere it points as their states say
## (set_gunner_state). The gun's muzzle and aim follow the barrel.
func _update_turret(delta: float) -> void:
	if riding:
		var want := _gunner_aim() if controls else turret_dir
		var a := turret_dir.angle_to(want)
		turret_dir = clamp_aim(want if a <= TURRET_RATE * delta else turret_dir.slerp(want, TURRET_RATE * delta / a))
		turret_guns.firing = controls and Input.is_action_pressed("fire")
	turret_guns.move_muzzle(0, TURRET + turret_dir * TURRET_BARREL, turret_dir)
	turret_guns.aim = TURRET + turret_dir * _aim_dist
	_turret_yaw.rotation.y = atan2(turret_dir.x, turret_dir.z)
	_turret_pitch.rotation.x = -asin(clampf(turret_dir.y, -1.0, 1.0))


## What the middle of the gunner's screen shows (up to TURRET_RANGE), and the barrel direction (plane frame, within
## reach) that points at it.
func _gunner_aim() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return turret_dir
	_turret_query.from = cam.global_position
	_turret_query.to = cam.global_position - cam.global_basis.z * TURRET_RANGE
	var h := get_world_3d().direct_space_state.intersect_ray(_turret_query)
	gunner_target = h["position"] if h else _turret_query.to
	var d := to_local(gunner_target) - TURRET
	_aim_dist = clampf(d.length(), 30.0, TURRET_RANGE)
	var want := clamp_aim(d.normalized())
	_out_of_arc = want.angle_to(d) > 0.03
	return want


## `d` (plane frame, unit) brought within the turret's reach: at most TURRET_CONE off the nose, no higher than
## TURRET_UP above the plane's axis.
static func clamp_aim(d: Vector3) -> Vector3:
	var up := sin(TURRET_UP)
	if d.y > up:
		var flat := Vector2(d.x, d.z)
		flat = flat.normalized() if flat.length_squared() > 1e-8 else Vector2(0.0, 1.0)
		flat *= sqrt(1.0 - up * up)
		d = Vector3(flat.x, up, flat.y)
	var off := Vector2(d.x, d.y)
	if atan2(off.length(), d.z) > TURRET_CONE:
		off = (off.normalized() if off.length_squared() > 1e-8 else Vector2(0.0, -1.0)) * sin(TURRET_CONE)
		d = Vector3(off.x, off.y, cos(TURRET_CONE))
	return d


## Turret view: the mouse moved the gunner's eye by `look` (rad: right, down), within the turret's reach.
func look_turret(look: Vector2) -> void:
	var yaw := gun_look.x - look.x
	var pitch := gun_look.y - look.y
	var d := clamp_aim(Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)))
	gun_look = Vector2(atan2(d.x, d.z), asin(d.y))


## Where the turret's rounds are aimed (global), for the ring on the gunner's screen.
func turret_aim_point() -> Vector3:
	return to_global(TURRET + turret_dir * _aim_dist)


## LAN games: the gunner's turret for the other peers (game.gd net_player_state): where it points (plane frame, as
## long as the distance its rounds are aimed at) and the trigger.
func gunner_state() -> Array:
	return [turret_dir * _aim_dist, turret_guns.firing]


## LAN games: another player's turret (gunner_state), fired here for show.
func set_gunner_state(aim: Vector3, firing: bool) -> void:
	if riding or not turret:
		return
	if aim.length_squared() > 1e-6:
		turret_dir = clamp_aim(aim.normalized())
		_aim_dist = clampf(aim.length(), 30.0, TURRET_RANGE)
	turret_guns.firing = firing


## The player sits in the gunner's seat (on) or gets up: the chase camera or the turret view.
func set_riding(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	riding = on
	turret_guns.live = on
	if on:
		_passenger_skin.albedo_color = color
		_reset_camera()
	else:
		turret_guns.firing = false
		_out_of_arc = false
	_update_passenger()


## LAN games: another player in the gunner's seat (on) or nobody; leaving, their turret stops firing.
func show_passenger(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	super(on, color)
	if not on and turret_guns and not riding:
		turret_guns.firing = false


## The gunner's turret view (looking down the barrel, the eye where it points) or the chase camera; the pilot's cockpit
## view as before.
func set_cab_view(on: bool) -> void:
	if not (riding and _turret_camera):
		super(on)
		return
	cab_view = on
	_update_passenger()
	if on:
		gun_look = Vector2(atan2(turret_dir.x, turret_dir.z), asin(turret_dir.y))
	(_turret_camera if on else camera).make_current()


func _measure_height() -> void:
	var p := global_transform * center_of_mass
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 2000.0, Layers.SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	height = p.y - hit["position"].y - center_of_mass.y if hit else 999.0


func _remote_process(delta: float) -> void:
	audio.update(_rpm() * max_speed, lever, max_speed, delta)


## LAN games: the car's state with the throttle lever as the pedal, and the control surfaces and the trigger after it.
func net_state() -> Array:
	var s := super()
	s.append(surfaces)
	s.append(guns != null and guns.firing)
	return s


func apply_net_state(a: Array, b: Array, w: float) -> void:
	super(a, b, w)
	lever = b[3]
	if b.size() > 7:
		surfaces = a[7].lerp(b[7], minf(w, 1.0)) if a.size() > 7 else b[7]
	if guns and b.size() > 8:
		guns.firing = b[8]
	audio.engine_on = (b[4] & 2 != 0 or lever > 0.0) and not broken


## A remote copy's guns fire for show only: the hits count on the peer flying it.
func set_remote(on: bool) -> void:
	super(on)
	if guns:
		guns.live = not on
		guns.firing = false


## Where the guns' rounds converge (global), for the gunsight on the screen.
func aim_point() -> Vector3:
	return to_global(guns.aim if guns else Vector3(0.0, EYE_HEIGHT, AIM_DISTANCE))


func dash_text() -> String:
	var line := "%3d km/h   alt %d m   throttle %d%%" % [roundi(linear_velocity.length() * 3.6), roundi(height),
			roundi(lever * 100.0)]
	if broken:
		line += "\nENGINE DEAD · repaired in %d s" % ceili(repair_in())
	elif stalled:
		line += "\nSTALL"
	elif not on_ground and height < 15.0 and linear_velocity.y < -6.0:
		line += "\nPULL UP"
	if riding and _out_of_arc:
		line += "\nOUT OF THE TURRET'S REACH"
	return line


# ---------------------------------------------------------------- looks

func _process(delta: float) -> void:
	super(delta)
	# propeller: visibly turning when idle, a blur disc at full power
	var spin := 0.0 if not audio.engine_on and lever == 0.0 else lerpf(14.0, 70.0, lever)
	if broken:
		spin = maxf(speed(), 0.0) * 0.4     # windmilling
	_prop_angle = fmod(_prop_angle + spin * delta, TAU)
	_prop.rotation.z = _prop_angle
	(_prop_disc.material_override as StandardMaterial3D).albedo_color.a = 0.22 * smoothstep(20.0, 60.0, spin)
	_elevator.rotation.x = -surfaces.x * 0.4
	_rudder.rotation.y = -surfaces.z * 0.45
	_ailerons[0].rotation.x = -surfaces.y * 0.35
	_ailerons[1].rotation.x = surfaces.y * 0.35
	# trails, from how fast the plane really moves (remote planes are posed, not simulated)
	var p := global_position
	var moving := 0.0 if _last_pos == Vector3.INF or delta <= 0.0 else p.distance_to(_last_pos) / delta
	_last_pos = p
	var cam := get_viewport().get_camera_3d()
	_trail_time += delta
	for i in _trails.size():
		_trails[i].update(global_transform * _tips[i], moving > TRAIL_SPEED and is_visible_in_tree(), _trail_time, cam)


## Chase camera: behind the plane, turning with it (rolls and loops too) once it flies; taxiing it stays level.
func _update_camera(delta: float) -> void:
	var b := global_basis.orthonormalized()
	var level := Basis(Vector3.UP, atan2(b.z.x, b.z.z))
	var target := Quaternion(level).slerp(Quaternion(b), smoothstep(6.0, 18.0, linear_velocity.length()))
	_cam_q = target if delta >= 1.0 else _cam_q.slerp(target, 1.0 - exp(-4.0 * delta))
	var cb := Basis(_cam_q)
	if linear_velocity.length() > 2.0 and not riding and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look_yaw = lerp_angle(_look_yaw, 0.0, 1.0 - exp(-1.5 * delta))     # (the gunner aims with it: no easing)
	_arm.spring_length = lerpf(_arm.spring_length, _cam_zoom, 1.0 - exp(-10.0 * delta))
	_cam_pivot.global_position = to_global(Vector3(0.0, 1.3, -0.6)) + cb.y * _cam_height
	_cam_pivot.global_basis = cb * Basis(Vector3.UP, PI) * Basis.from_euler(Vector3(_look_pitch, _look_yaw, 0.0))
	_cab_camera.rotation = Vector3(clampf(_look_pitch + 0.12, -1.0, 0.8), PI + _look_yaw, 0.0)
	if _turret_camera:
		_turret_camera.rotation = Vector3(gun_look.y, PI + gun_look.x, 0.0)


## Thin ribbon behind a wing tip: points dropped every STEP s while emitting, fading out and widening over LIFE s,
## drawn facing the camera. Top level, so its vertices are global.
class WingTrail extends MeshInstance3D:
	const LIFE := 0.8
	const STEP := 0.03
	const WIDTH := Vector2(0.03, 0.1)       # half width at the tip and at the end of its life
	const ALPHA := 0.6
	var _points: Array = []                 # [position, time, starts a new run]
	var _im := ImmediateMesh.new()
	var _gap := true

	func _init(mat: Material) -> void:
		top_level = true
		mesh = _im
		material_override = mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _ready() -> void:
		global_transform = Transform3D.IDENTITY

	func point_count() -> int:
		return _points.size()

	func update(tip: Vector3, emit: bool, now: float, cam: Camera3D) -> void:
		while not _points.is_empty() and now - _points[0][1] > LIFE:
			_points.pop_front()
		if emit:
			if _gap or _points.is_empty() or now - _points[-1][1] >= STEP:
				_points.append([tip, now, _gap])
			_gap = false
		else:
			_gap = true
		_im.clear_surfaces()
		var pts := _points.duplicate()
		if emit:
			pts.append([tip, now, false])   # the ribbon reaches the tip between drops
		var quads := 0
		for i in range(1, pts.size()):
			if not pts[i][2]:
				quads += 1
		if quads == 0 or cam == null:
			return
		var eye := cam.global_position
		var sides := PackedVector3Array()
		var colors := PackedColorArray()
		for i in pts.size():
			var p: Vector3 = pts[i][0]
			var along: Vector3 = pts[mini(i + 1, pts.size() - 1)][0] - pts[maxi(i - 1, 0)][0]
			var side := along.cross(eye - p)
			var age := clampf((now - pts[i][1]) / LIFE, 0.0, 1.0)
			sides.append(side.normalized() * lerpf(WIDTH.x, WIDTH.y, age) if side.length_squared() > 1e-8 else Vector3.ZERO)
			colors.append(Color(1, 1, 1, ALPHA * pow(1.0 - age, 1.5)))
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1, pts.size()):
			if pts[i][2]:
				continue
			var a: Vector3 = pts[i - 1][0]
			var b: Vector3 = pts[i][0]
			var quad := [[a + sides[i - 1], i - 1], [a - sides[i - 1], i - 1], [b - sides[i], i],
					[a + sides[i - 1], i - 1], [b - sides[i], i], [b + sides[i], i]]
			for q: Array in quad:
				_im.surface_set_color(colors[q[1]])
				_im.surface_add_vertex(q[0])
		_im.surface_end()
