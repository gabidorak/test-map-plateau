extends Camera3D
## Free-flying debug camera: hold right mouse to look, WASD to move, Q/E down/up (physical key
## positions, so ZQSD + A/E on AZERTY), Shift for speed, mouse wheel changes base speed.

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
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.55, 1.55)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not active:
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		position += dir.normalized() * s * delta
