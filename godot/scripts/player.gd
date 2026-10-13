extends CharacterBody3D
## Street-level player. Movement keys are physical positions (WASD on QWERTY = ZQSD on AZERTY).
## Shift runs, Space jumps, the mouse looks around once captured. The mouse wheel zooms the third-person camera;
## zooming all the way in goes first person and zooming out of it comes back (like Roblox); V toggles too.
## Steps up to step_height onto vehicle floors (the bus). Inside a walkable vehicle (game.gd calls set_carrier)
## the player moves in the vehicle's frame: each frame first follows the vehicle's motion since the last
## one, then walks; leaving it keeps the vehicle's velocity. In there it collides with the walkable hulls only: what
## the vehicle drives through (a tree it bends, a kerb, a pole another peer's copy of it has not knocked down yet)
## would shove it about in the vehicle.

const Layers = preload("res://scripts/physics_layers.gd")

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
@export var kill_depth := -80.0             # below this (Godot y) the player is put back
@export var step_height := 0.42

var first_person := false
var active := true                          # false while the fly camera is in use
## Scripted movement for tests: Vector2(right, forward) in [-1, 1], or null for the keyboard.
var scripted_input: Variant = null
var scripted_run := false
var scripted_jump := false
var rescues := 0                            # times the player fell out of the world
var wait_jump_release := false              # set on getting out of a car with Space: no jump until released
var carrier: Node3D                         # the vehicle the player stands in (car.gd), or null

var _yaw := 0.0
var _pitch := -0.12
var _last_floor := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _carrier_last := Transform3D.IDENTITY   # carrier transform when last followed
var _world_mask := 0                        # collision mask outside the vehicles
var _step_offset := 0.0                     # camera/body lag after a step up, eased to 0
var _zoom := 4.5                            # third-person camera distance the arm eases to

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
	_pivot.position.y = eye_height if first_person else eye_height - 0.1
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
	for mesh: GeometryInstance3D in _body.get_children():
		mesh.transparency = fade


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.45, 1.2)
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom((1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * (event.factor if event.factor > 0.0 else 1.0))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		toggle_view()


func _move_input() -> Vector2:
	if scripted_input != null:
		return scripted_input
	if not active:
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): v.y += 1.0
	if Input.is_physical_key_pressed(KEY_S): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	_follow_carrier()
	var scripted := scripted_input != null
	var input := _move_input()
	var running := scripted_run if scripted else (active and Input.is_physical_key_pressed(KEY_SHIFT))
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	wait_jump_release = wait_jump_release and space_down
	var jumping := scripted_jump if scripted else (active and space_down and not wait_jump_release)

	var dir := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, -input.y)
	var target := dir * (run_speed if running else walk_speed)
	var rate := accel * (1.0 if is_on_floor() else air_control) * delta
	var h := Vector2(velocity.x, velocity.z).lerp(Vector2(target.x, target.z), minf(rate, 1.0))
	velocity.x = h.x
	velocity.z = h.y
	if is_on_floor():
		if jumping:
			velocity.y = jump_speed
	else:
		velocity.y -= _gravity * delta
	var was_on_floor := is_on_floor()
	var start := global_position
	move_and_slide()
	if was_on_floor and target.length_squared() > 0.01:
		_try_step(start, target * delta)
	_step_offset = move_toward(_step_offset, 0.0, delta * 2.5)
	_pivot.position.y = (eye_height if first_person else eye_height - 0.1) - _step_offset
	_body.position.y = -_step_offset

	if is_on_floor():
		_last_floor = global_position
	elif global_position.y < kill_depth:
		rescues += 1
		teleport(_last_floor + Vector3.UP)

	if first_person:
		_body.rotation.y = _yaw
	elif dir.length_squared() > 0.01:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.z), minf(12.0 * delta, 1.0))


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
