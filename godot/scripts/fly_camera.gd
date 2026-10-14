extends Camera3D
## Free-flying debug camera: hold right mouse to look, the walking keys to move, cam_up / cam_down (Settings actions:
## physical key positions, WASD and Q/E by default, so ZQSD + A/E on AZERTY), Run for speed, mouse wheel changes base
## speed.

const Prefs = preload("res://scripts/settings.gd")

@export var speed := 12.0
@export var sensitivity := 0.003

var active := true                          # game.gd turns it off while walking

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_sync_angles()


func _sync_angles() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_sync_angles()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed *= 1.2
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed /= 1.2
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look: Vector2 = event.screen_relative * sensitivity * Prefs.mouse_scale
		_yaw -= look.x
		_pitch = clampf(_pitch - look.y, -1.55, 1.55)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not active:
		return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir -= basis.z
	if Input.is_action_pressed("move_back"): dir += basis.z
	if Input.is_action_pressed("move_left"): dir -= basis.x
	if Input.is_action_pressed("move_right"): dir += basis.x
	if Input.is_action_pressed("cam_up"): dir += Vector3.UP
	if Input.is_action_pressed("cam_down"): dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (4.0 if Input.is_action_pressed("run") else 1.0)
		position += dir.normalized() * s * delta
