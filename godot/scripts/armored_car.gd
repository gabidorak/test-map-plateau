extends "res://scripts/car.gd"
## Armoured car with a machine gun on its roof hatch (Car.SPECS "roof_gun": the GAZ Tiger-M, converted by
## blender/vehicles/import_car.py), driven like the other realistic cars (cab view with the turning steering wheel). Its
## passenger seat is the gunner's place: E from its right side (or while another player drives it) stands the player
## in the roof hatch, behind the gun, as in the two-seat biplane (scripts/plane.gd). The ring turns all the way round
## at TURRET_RATE, the gun pitches from PITCH_DOWN to PITCH_UP about its trunnion, both towards what the middle of the
## gunner's screen shows (up to TURRET_RANGE: chase camera), and the left mouse button (held) fires it
## (scripts/plane_guns.gd, one muzzle that moves with the barrel). The turret view (V, or the mouse wheel zoomed all the
## way in) looks over the gun from the gunner's eye, the mouse turning it; game.gd rings where the gun is aimed
## (turret_aim_point). The cab file's "turret" names the turning ring and the gun (their origins on the ring's pivot and
## the trunnion), the muzzle, and the gunner's feet and eye. The hull is armoured: rounds do a third of their damage.
## LAN games: the gunner's own player state carries the gun (gunner_state, as the biplane's turret), so the hits count
## on the gunner's peer, whoever drives the car, and the other peers fire it for show (set_gunner_state).

const Guns = preload("res://scripts/plane_guns.gd")
const TURRET_RATE := 2.2                    # rad/s, the ring and the gun towards the aim
const PITCH_DOWN := 0.2                     # rad below level (the barrel clears the roof all round)
const PITCH_UP := 0.9                       # rad above level
const TURRET_RANGE := 600.0                 # m, how far the gunner's line of sight is followed
const ARMOUR := 3.0                         # rounds do this much less damage
const GUNNER_LOOK_PITCH := -0.1             # rad, the gunner's chase camera on getting on: the middle of the screen far
											# enough ahead for the gun to reach

var turret_guns: Guns                       # the roof gun (live while the gunner is the player here)
var turret_dir := Vector3.BACK              # where the gun points, car frame (unit; +Z ahead)
var gun_look := Vector2(0.0, 0.0)           # turret view: yaw (+ to the left) and pitch (+ up) of the gunner's eye
var gunner_target := Vector3.INF            # global, what the gunner looks at (INF: none yet)

var _aim_dist := 200.0                      # m along the barrel where its rounds are aimed (the target's distance)
var _out_of_arc := false                    # the gunner looks lower than the gun can point
var _ring: Node3D                           # turns about the pivot (yaw)
var _gun: Node3D                            # child of the ring: pitches about the trunnion
var _pivot := Vector3.ZERO                  # car frame
var _ring_rest := Transform3D.IDENTITY
var _gun_rest := Transform3D.IDENTITY
var _muzzle := Vector3.ZERO                 # gun frame
var _eye := Vector3.ZERO                    # gunner's eye, ring frame
var _turret_camera: Camera3D
var _turret_query := PhysicsRayQueryParameters3D.new()


func setup(model: String) -> void:
	super(model)
	name = "ArmoredCar_" + model.replace("-", "_")
	var t: Dictionary = _cab_file["turret"]
	_ring = find_child(t["ring"], true, false) as Node3D
	_gun = find_child(t["gun"], true, false) as Node3D
	var m := _ring.owner as Node3D              # the model (its glTF scene)
	var v := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2]) * m.scale + m.position
	var pose := _ring.transform.affine_inverse() * _gun.transform     # (siblings: the trunnion in the ring's frame)
	_gun.owner = null
	_gun.reparent(_ring, false)
	_gun.transform = pose
	_ring_rest = _ring.transform
	_gun_rest = _gun.transform
	_pivot = v.call(t["pivot"])
	_muzzle = _in_car(_gun).affine_inverse() * v.call(t["muzzle"])
	_eye = _in_car(_ring).affine_inverse() * v.call(t["gunner_eye"])
	_build_gunner(_in_car(_ring).affine_inverse() * v.call(t["gunner"]))

	turret_guns = Guns.new()
	var muzzle: Array[Vector3] = [_muzzle_point()]
	turret_guns.setup(muzzle, _muzzle_point() + turret_dir * _aim_dist)
	turret_guns.name = "TurretGun"
	turret_guns.live = false
	add_child(turret_guns)
	_turret_query.collision_mask = Guns.MASK
	_turret_query.exclude = [get_rid()]
	_turret_camera = Camera3D.new()
	_turret_camera.name = "TurretCamera"
	_turret_camera.fov = 70.0
	_turret_camera.near = 0.05
	_turret_camera.far = 1500.0
	add_child(_turret_camera)
	_pose_turret()


## The gunner's look-alike (the car's passenger), standing in the hatch from `feet` (ring frame) and turning with the
## ring: a body out to the chest above the ring, a helmet.
func _build_gunner(feet: Vector3) -> void:
	if _passenger:
		_passenger.free()                       # (car.gd's seated one)
	var height := _eye.y - feet.y + 0.14        # to the top of the head
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.24
	capsule.height = height
	capsule.material = _passenger_skin
	_passenger = MeshInstance3D.new()
	_passenger.name = "Gunner"
	_passenger.mesh = capsule
	_passenger.position = Vector3(_eye.x, feet.y + height * 0.5, _eye.z - 0.06)
	_passenger.visible = false
	_ring.add_child(_passenger)
	var helmet := SphereMesh.new()
	helmet.radius = 0.2
	helmet.height = 0.24
	helmet.is_hemisphere = true
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.29, 0.33, 0.2)
	olive.roughness = 0.8
	helmet.material = olive
	var mi := MeshInstance3D.new()
	mi.mesh = helmet
	mi.position = Vector3(0.0, height * 0.5 - 0.2, 0.0)
	_passenger.add_child(mi)


func _physics_process(delta: float) -> void:
	super(delta)
	_update_turret(delta)


func damage(amount: float) -> void:
	super(amount / ARMOUR)


# ---------------------------------------------------------------- turret

## The gunner here turns the gun towards what they look at and fires it; elsewhere it points as their states say
## (set_gunner_state). The round's muzzle and aim follow the barrel.
func _update_turret(delta: float) -> void:
	if riding:
		var want := _gunner_aim() if controls else turret_dir
		var a := turret_dir.angle_to(want)
		turret_dir = clamp_aim(want if a <= TURRET_RATE * delta else turret_dir.slerp(want, TURRET_RATE * delta / a))
		turret_guns.firing = controls and Input.is_action_pressed("fire")
	_pose_turret()


## The ring and the gun along turret_dir, the gun's muzzle and aim after them, the turret view's camera on the
## gunner's eye.
func _pose_turret() -> void:
	_ring.transform = Transform3D(Basis(Vector3.UP, atan2(turret_dir.x, turret_dir.z)), Vector3.ZERO) * _ring_rest
	_ring.position = _ring_rest.origin
	_gun.transform = _gun_rest * Transform3D(Basis(Vector3.RIGHT, -asin(clampf(turret_dir.y, -1.0, 1.0))), Vector3.ZERO)
	var muzzle := _muzzle_point()
	turret_guns.move_muzzle(0, muzzle, turret_dir)
	turret_guns.aim = muzzle + turret_dir * _aim_dist
	_turret_camera.position = _in_car(_ring) * _eye
	_turret_camera.rotation = Vector3(gun_look.y, PI + gun_look.x, 0.0)


## The muzzle now, car frame.
func _muzzle_point() -> Vector3:
	return _in_car(_gun) * _muzzle


## What the middle of the gunner's screen shows (up to TURRET_RANGE), and the gun direction (car frame, within reach)
## that points at it from the trunnion.
func _gunner_aim() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return turret_dir
	_turret_query.from = cam.global_position
	_turret_query.to = cam.global_position - cam.global_basis.z * TURRET_RANGE
	var h := get_world_3d().direct_space_state.intersect_ray(_turret_query)
	gunner_target = h["position"] if h else _turret_query.to
	var d := to_local(gunner_target) - _in_car(_gun).origin
	_aim_dist = clampf(d.length(), 20.0, TURRET_RANGE)
	var want := clamp_aim(d.normalized())
	_out_of_arc = want.angle_to(d) > 0.03
	return want


## `d` (car frame, unit) within the gun's reach: any bearing, from PITCH_DOWN below level to PITCH_UP above.
static func clamp_aim(d: Vector3) -> Vector3:
	var flat := Vector2(d.x, d.z)
	flat = flat.normalized() if flat.length_squared() > 1e-8 else Vector2(0.0, 1.0)
	var pitch := clampf(asin(clampf(d.y, -1.0, 1.0)), -PITCH_DOWN, PITCH_UP)
	return Vector3(flat.x * cos(pitch), sin(pitch), flat.y * cos(pitch))


## Turret view: the mouse moved the gunner's eye by `look` (rad: right, down), within the gun's reach.
func look_turret(look: Vector2) -> void:
	gun_look = Vector2(wrapf(gun_look.x - look.x, -PI, PI), clampf(gun_look.y - look.y, -PITCH_DOWN, PITCH_UP))


## Where the gun's rounds are aimed (global), for the ring on the gunner's screen.
func turret_aim_point() -> Vector3:
	return to_global(_muzzle_point() + turret_dir * _aim_dist)


## LAN games: the gunner's gun for the other peers (game.gd net_player_state): where it points (car frame, as long as
## the distance its rounds are aimed at) and the trigger.
func gunner_state() -> Array:
	return [turret_dir * _aim_dist, turret_guns.firing]


## LAN games: another player's gun (gunner_state), fired here for show.
func set_gunner_state(aim: Vector3, firing: bool) -> void:
	if riding:
		return
	if aim.length_squared() > 1e-6:
		turret_dir = clamp_aim(aim.normalized())
		_aim_dist = clampf(aim.length(), 20.0, TURRET_RANGE)
	turret_guns.firing = firing


## The player stands at the gun (on) or gets out: the chase camera or the turret view.
func set_riding(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	riding = on
	turret_guns.live = on
	if on:
		_passenger_skin.albedo_color = color
		_look_pitch = GUNNER_LOOK_PITCH
		_reset_camera()
	else:
		turret_guns.firing = false
		_out_of_arc = false
	_update_passenger()


## LAN games: another player at the gun (on) or nobody; leaving, their gun stops firing.
func show_passenger(on: bool, color := Color(1, 0.55, 0.2)) -> void:
	super(on, color)
	if not on and not riding:
		turret_guns.firing = false


## The gunner's turret view (over the gun, looking where the mouse turns it) or the chase camera; the driver's cab view
## as before.
func set_cab_view(on: bool) -> void:
	if not riding:
		super(on)
		return
	cab_view = on
	_update_passenger()
	if on:
		gun_look = Vector2(atan2(turret_dir.x, turret_dir.z), asin(turret_dir.y))
	(_turret_camera if on else camera).make_current()


func _unhandled_input(event: InputEvent) -> void:
	if riding and controls and cab_view and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_turret(event.screen_relative * sensitivity * Prefs.mouse_scale)
		get_viewport().set_input_as_handled()
		return
	super(event)                                # driving; the gunner's chase camera look, zoom, turret view


## The gunner's dashboard line.
func gunner_dash() -> String:
	var line := "GUNNER · %d m" % roundi(_aim_dist)
	if _out_of_arc:
		line += "\nOUT OF THE GUN'S REACH"
	if broken:
		line += "\nBROKEN · repaired in %d s" % ceili(repair_in())
	return line
