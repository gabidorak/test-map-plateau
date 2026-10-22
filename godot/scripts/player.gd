extends CharacterBody3D
## Street-level player. Keys are the Settings actions (scripts/settings.gd): by default physical positions, WASD on
## QWERTY = ZQSD on AZERTY, Shift runs, Space jumps. The mouse looks around once captured. The mouse wheel zooms the
## third-person camera; zooming all the way in goes first person and zooming out of it comes back (like Roblox); V
## toggles too.
## Steps up to step_height onto vehicle floors (the bus). Inside a walkable vehicle (game.gd calls set_carrier)
## the player moves in the vehicle's frame: each frame first follows the vehicle's motion since the last
## one, then walks; leaving it keeps the vehicle's velocity. In there it collides with the walkable hulls only: what
## the vehicle drives through (a tree it bends, a kerb, a pole another peer's copy of it has not knocked down yet)
## would shove it about in the vehicle.
## In the lakes and ponds (scripts/water.gd) the player wades slower the deeper it gets, then swims with the head and
## shoulders out (float_depth): slower, Shift a little faster, Space kicks up to climb out over a bank; falling in
## splashes.
## A game mode can slow the player (speed_scale: carrying someone), stop running or jumping, turn the body with the
## view (face_aim: a gun in hand), lay it down crawling (set_crawling) and kick the view up (kick: recoil).

const Layers = preload("res://scripts/physics_layers.gd")
const Prefs = preload("res://scripts/settings.gd")
const Water = preload("res://scripts/water.gd")

@export var walk_speed := 4.5
@export var run_speed := 9.0
@export var jump_speed := 5.0
@export var accel := 10.0                   # how fast the velocity reaches its target (1/s)
@export var air_control := 0.3
@export var sensitivity := 0.0025
@export var third_person_distance := 4.5    # camera distance at start
@export var min_zoom := 1.2                 # zooming in closer than this goes first person
@export var max_zoom := 15.0
@export var zoom_step := 1.2                # distance factor per mouse wheel notch
@export var shoulder_offset := 0.6          # third person: camera right of the head so the crosshair is free
@export var eye_height := 1.6
@export var kill_depth := -80.0             # below this (Godot y) the player is put back (game.gd lowers it under the
                                            # world's lowest ground)
@export var step_height := 0.42
@export var swim_speed := 1.8               # m/s swimming, Shift: swim_fast
@export var swim_fast := 3.2
@export var float_depth := 1.1              # m: the feet this deep under the surface, the player swims
@export var wade_depth := 0.4               # m: deeper than this, walking slows down (half speed at float_depth)
@export var swim_kick := 4.0                # m/s up, Space while swimming (once per SWIM_KICK_EVERY)
const SWIM_KICK_EVERY := 0.8

var first_person := false
var active := true                          # false while the fly camera is in use
## Scripted movement for tests: Vector2(right, forward) in [-1, 1], or null for the keyboard.
var scripted_input: Variant = null
var scripted_run := false
var scripted_jump := false
var rescues := 0                            # times the player fell out of the world
var wait_jump_release := false              # set on getting out of a car with Space: no jump until released
var carrier: Node3D                         # the vehicle the player stands in (car.gd), or null
var swimming := false
var water_depth := NAN                      # m of water over the feet (NAN out of the water)
var speed_scale := 1.0                      # times the walking, running and swimming speeds
var can_run := true
var can_jump := true
var face_aim := false                       # third person: the body faces where the camera looks, not where it walks
var crawling := false                       # lying on the ground (set_crawling)

var _yaw := 0.0
var _pitch := -0.12
var _last_floor := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _carrier_last := Transform3D.IDENTITY   # carrier transform when last followed
var _world_mask := 0                        # collision mask outside the vehicles
var _step_offset := 0.0                     # camera/body lag after a step up, eased to 0
var _zoom := 4.5                            # third-person camera distance the arm eases to
var _kick_t := 0.0                          # s since the last swim kick
var _swim_t := 0.0                          # bobbing clock

@onready var _pivot: Node3D = $Pivot
@onready var _arm: SpringArm3D = $Pivot/SpringArm3D
@onready var camera: Camera3D = $Pivot/SpringArm3D/Camera3D
@onready var _body: Node3D = $Body


func _ready() -> void:
	_last_floor = global_position
	_zoom = third_person_distance
	# vehicles are followed by set_carrier, not by the built-in moving-platform velocity
	platform_floor_layers = 0xFFFFFFFF & ~(Layers.VEHICLES | Layers.VEHICLE_INSIDE)
	collision_mask |= Layers.VEHICLE_INSIDE
	_world_mask = collision_mask
	_apply_view()


## Starts (vehicle) or stops (null) following a vehicle's motion.
func set_carrier(vehicle: Node3D) -> void:
	if vehicle == carrier:
		return
	if is_instance_valid(carrier):
		_follow_carrier()                   # its last move first (it may have moved since this tick's follow)
	if is_instance_valid(carrier) and vehicle == null:
		var v: Vector3 = carrier.velocity_at(global_position)
		velocity += Vector3(v.x, 0.0, v.z)
	carrier = vehicle
	if carrier:
		_carrier_last = carrier.global_transform
	collision_mask = Layers.VEHICLE_INSIDE if carrier else _world_mask
	# the third-person camera stays inside the vehicle
	_arm.collision_mask = Layers.SOLID | (Layers.VEHICLE_INSIDE if carrier else 0)


func _follow_carrier() -> void:
	if not is_instance_valid(carrier):
		carrier = null
		return
	var now := carrier.global_transform
	var d := now * _carrier_last.affine_inverse()
	_carrier_last = now
	global_position = d * global_position
	var f := d.basis * Vector3.FORWARD
	var turn := atan2(-f.x, -f.z)
	_yaw += turn
	_body.rotation.y += turn
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	velocity = Basis(Vector3.UP, turn) * velocity


## The carrier's transform when the player last followed it: the frame the player's position is up to date in (the
## carrier may have moved since, in this physics tick before the player's turn, or in the physics step).
func carrier_frame() -> Transform3D:
	return _carrier_last


## Where the player is once it has followed its carrier's latest move (its position now without a carrier).
func followed_position() -> Vector3:
	if not is_instance_valid(carrier):
		return global_position
	return carrier.global_transform * (_carrier_last.affine_inverse() * global_position)


## A shove of `dv` (m/s) by something hitting the player (the fire truck's water jet, game.gd / net.gd); walking eases
## it off again.
func push(dv: Vector3) -> void:
	velocity += dv


## Puts the player's feet at `pos` (Godot coordinates) facing `yaw` radians.
func teleport(pos: Vector3, yaw := _yaw) -> void:
	global_position = pos
	if is_instance_valid(carrier):
		_carrier_last = carrier.global_transform
	velocity = Vector3.ZERO
	_last_floor = pos
	_yaw = yaw
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


## Facing of the body (radians about Y, world frame): where it walks, or looks in first person.
func body_yaw() -> float:
	return _body.rotation.y


## The view's pitch (radians, up positive).
func view_pitch() -> float:
	return _pitch


## Collides with `layers` too (outside vehicles): Escape from Plateau's zombies.
func collide_with(layers: int) -> void:
	_world_mask |= layers
	if not is_instance_valid(carrier):
		collision_mask = _world_mask


## Kicks the view up by `pitch` radians and aside by `yaw` (a gun's recoil).
func kick(pitch: float, yaw := 0.0) -> void:
	_pitch = clampf(_pitch + pitch, -1.45, 1.2)
	_yaw += yaw
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


## Lying on the ground, crawling (`on`: the eye low, the body flat) or up again.
func set_crawling(on: bool) -> void:
	crawling = on
	_body.rotation.x = -PI * 0.5 if on else 0.0
	_body.position.y = 0.33 if on else 0.0
	_apply_view()


func toggle_view() -> void:
	set_first_person(not first_person)


func set_first_person(on: bool) -> void:
	first_person = on
	_apply_view()


## Mouse wheel: `notches` > 0 zooms out, < 0 in. Zooming in past min_zoom goes first person, zooming out of
## first person comes back at min_zoom.
func zoom(notches: float) -> void:
	if first_person:
		if notches > 0.0:
			_zoom = min_zoom
			set_first_person(false)
		return
	_zoom *= pow(zoom_step, notches)
	if _zoom < min_zoom:
		set_first_person(true)
	_zoom = clampf(_zoom, min_zoom, max_zoom)


## First person snaps to the eye; third person eases out from there (_process).
func _apply_view() -> void:
	if first_person:
		_arm.spring_length = 0.0
		_arm.position.x = 0.0
	_pivot.position.y = _eye()
	_body.visible = not first_person
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if first_person:
		return
	_arm.spring_length = lerpf(_arm.spring_length, _zoom, 1.0 - exp(-10.0 * delta))
	# over the shoulder, less so close up
	_arm.position.x = shoulder_offset * clampf(_arm.spring_length / third_person_distance, 0.0, 1.0)
	# the body fades out when the camera comes close (zoomed in, or pushed in by walls)
	var fade := clampf((1.8 - _arm.get_hit_length()) / 0.8, 0.0, 0.8)
	for mesh in _body.get_children():
		if mesh is GeometryInstance3D:           # (not what a game mode put in its hand)
			(mesh as GeometryInstance3D).transparency = fade


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look: Vector2 = event.screen_relative * sensitivity * Prefs.mouse_scale
		_yaw -= look.x
		_pitch = clampf(_pitch - look.y, -1.45, 1.2)
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom((1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * (event.factor if event.factor > 0.0 else 1.0))
	elif event.is_action_pressed("toggle_view"):
		toggle_view()


func _move_input() -> Vector2:
	if scripted_input != null:
		return scripted_input
	if not active:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")


func _physics_process(delta: float) -> void:
	_follow_carrier()
	var scripted := scripted_input != null
	var input := _move_input()
	var running := (scripted_run if scripted else (active and Input.is_action_pressed("run"))) and can_run
	var space_down := Input.is_action_pressed("jump")
	wait_jump_release = wait_jump_release and space_down
	var jumping := (scripted_jump if scripted else (active and space_down and not wait_jump_release)) and can_jump

	var water_y := NAN if is_instance_valid(carrier) else Water.surface_at(global_position)
	var was_wet := water_depth > 0.0
	water_depth = water_y - global_position.y
	if not was_wet and water_depth > 0.0 and velocity.y < -Water.SPLASH_MIN and Water.current:
		Water.current.splash(global_position, -velocity.y, 0.8)
	swimming = water_depth > float_depth - (0.15 if swimming else 0.0)
	var wade := clampf((water_depth - wade_depth) / (float_depth - wade_depth), 0.0, 1.0) if water_depth > 0.0 else 0.0
	_kick_t += delta

	var dir := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, -input.y)
	var target := dir * (run_speed if running else walk_speed) * (1.0 - 0.5 * wade) * speed_scale
	if swimming:
		target = dir * (swim_fast if running else swim_speed) * speed_scale
	var rate := accel * (0.4 if swimming else 1.0 if is_on_floor() else air_control) * delta
	var h := Vector2(velocity.x, velocity.z).lerp(Vector2(target.x, target.z), minf(rate, 1.0))
	velocity.x = h.x
	velocity.z = h.y
	if swimming and (not is_on_floor() or water_depth > float_depth + 0.1):
		# float with the head out, bobbing a little; a kick up out over a bank
		_swim_t += delta
		var rise := (water_y - float_depth + 0.04 * sin(_swim_t * 2.2)) - global_position.y
		velocity.y = move_toward(velocity.y, clampf(rise * 2.5, -2.5, 1.5), (30.0 if velocity.y < -2.5 else 12.0) * delta)
		if jumping and _kick_t > SWIM_KICK_EVERY:
			velocity.y = swim_kick
			_kick_t = 0.0
	elif is_on_floor():
		if jumping:
			velocity.y = jump_speed * (1.0 - 0.4 * wade)
	else:
		velocity.y -= _gravity * delta
	var was_on_floor := is_on_floor()
	var start := global_position
	move_and_slide()
	if was_on_floor and target.length_squared() > 0.01:
		_try_step(start, target * delta)
	_step_offset = move_toward(_step_offset, 0.0, delta * 2.5)
	_pivot.position.y = _eye() - _step_offset
	_body.position.y = (0.33 if crawling else 0.0) - _step_offset

	if is_on_floor():
		_last_floor = global_position
	elif global_position.y < kill_depth:
		rescues += 1
		teleport(_last_floor + Vector3.UP)

	if first_person or face_aim:
		_body.rotation.y = _yaw
	elif dir.length_squared() > 0.01:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.z), minf(12.0 * delta, 1.0))


## Height of the camera pivot: the eye in first person, a little lower in third, near the ground crawling.
func _eye() -> float:
	if crawling:
		return 0.45
	return eye_height if first_person else eye_height - 0.1


## After move_and_slide fell short of `motion` against a low obstacle: lifts the player onto it when there
## is head room, room ahead at that height, and a walkable vehicle floor below (only vehicles: elsewhere,
## e.g. on hillside roofs that end a few decimetres above the uphill ground, walls must stay walls).
func _try_step(start: Vector3, motion: Vector3) -> void:
	var h := Vector3(motion.x, 0.0, motion.z)
	var moved := global_position - start
	if Vector3(moved.x, 0.0, moved.z).length() > h.length() * 0.7:
		return                              # not blocked
	var ahead := h.normalized() * maxf(h.length(), 0.12)
	var t := global_transform
	if test_move(t, Vector3.UP * step_height):
		return
	t.origin += Vector3.UP * step_height
	if test_move(t, ahead):
		return
	t.origin += ahead
	var hit := KinematicCollision3D.new()
	if not test_move(t, Vector3.DOWN * (step_height + 0.05), hit):
		return
	var floor_body := hit.get_collider() as CollisionObject3D
	if hit.get_normal().angle_to(Vector3.UP) > floor_max_angle or floor_body == null \
			or not floor_body.collision_layer & Layers.VEHICLE_INSIDE:
		return
	t.origin += hit.get_travel()
	var rise := t.origin.y - global_position.y
	if rise < 0.05:
		return
	global_position = t.origin
	velocity.y = 0.0
	_step_offset = minf(_step_offset + rise, step_height)
	apply_floor_snap()
