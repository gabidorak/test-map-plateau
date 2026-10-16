extends Node
## Player settings (autoload "Settings"), saved in user://settings.cfg next to main_menu.gd's profile: key bindings,
## mouse sensitivity, graphics quality, display mode, vsync, 3D resolution, UI scale and day or night
## (scripts/settings_menu.gd edits them). F11 switches between a window and borderless fullscreen anywhere.
## Key bindings are InputMap actions (ACTIONS) on physical key positions, so the defaults are WASD on QWERTY and ZQSD on
## AZERTY; key_text() names a binding as the keyboard shows it. The UI scales with the window (project.godot: stretch
## mode canvas_items over 1600 x 900), times ui_scale. Tools (--script) run on the default bindings and leave the
## window as it is.

signal changed

const FILE := "user://settings.cfg"
const BASE_SIZE := Vector2(1600, 900)       # project.godot viewport size: the UI's design size
const WINDOW_FILL := 0.8                    # first window: this much of the screen

## Rebindable actions: [name, label, group, default bindings]. A binding is a KEY_* physical key position, or a negative
## mouse button (-MOUSE_BUTTON_LEFT).
const ACTIONS := [
	["move_forward", "Forward", "Walking", [KEY_W]],
	["move_back", "Back", "Walking", [KEY_S]],
	["move_left", "Left", "Walking", [KEY_A]],
	["move_right", "Right", "Walking", [KEY_D]],
	["run", "Run (horse: gallop)", "Walking", [KEY_SHIFT]],
	["jump", "Jump (also the horse)", "Walking", [KEY_SPACE]],
	["interact", "Get in a vehicle, on and off a horse (bus: near the driver seat; fire truck: from its right side, the passenger seat)", "Walking", [KEY_E]],
	["park_car", "Park a car here", "Walking", [KEY_C]],
	["vehicle_menu", "Vehicle menu", "Walking", [KEY_U]],
	["throttle", "Throttle", "Driving", [KEY_W]],
	["brake", "Brake, then reverse", "Driving", [KEY_S]],
	["steer_left", "Steer left", "Driving", [KEY_A]],
	["steer_right", "Steer right", "Driving", [KEY_D]],
	["drift", "Drift (held)", "Driving", [KEY_X]],
	["signal_left", "Left turn signal", "Driving", [KEY_Q]],
	["signal_right", "Right turn signal", "Driving", [KEY_E]],
	["horn", "Horn (horse: neigh)", "Driving", [KEY_G]],
	["doors", "Doors (bus)", "Driving", [KEY_O]],
	["bell", "Gong (bus), siren (fire truck, police car)", "Driving", [KEY_B]],
	["race", "Race in a start circle alone, join a race you are invited to, give up (twice)", "Driving", [KEY_T]],
	["race_invite", "Race with the other drivers in the start circle, decline an invitation", "Driving", [KEY_Y]],
	["headlights", "Headlights (plane: landing light)", "Vehicles and plane", [KEY_L]],
	["exit_vehicle", "Get out (bus: leave the seat)", "Vehicles and plane", [KEY_SPACE]],
	["reset_vehicle", "Back on the wheels / level the wings", "Vehicles and plane", [KEY_R]],
	["plane_nose_down", "Nose down", "Plane", [KEY_W, KEY_UP]],
	["plane_nose_up", "Nose up", "Plane", [KEY_S, KEY_DOWN]],
	["plane_roll_left", "Roll left (on the ground: steer)", "Plane", [KEY_A, KEY_LEFT]],
	["plane_roll_right", "Roll right (on the ground: steer)", "Plane", [KEY_D, KEY_RIGHT]],
	["plane_rudder_left", "Rudder left", "Plane", [KEY_Q]],
	["plane_rudder_right", "Rudder right", "Plane", [KEY_E]],
	["plane_throttle_up", "Throttle up", "Plane", [KEY_SHIFT]],
	["plane_throttle_down", "Throttle down (at idle: brake)", "Plane", [KEY_CTRL]],
	["fire", "Fire the guns (armed plane, gunner's turret), water cannon (fire truck)", "Plane", [-MOUSE_BUTTON_LEFT]],
	["cam_up", "Up (moves with the walking keys, Run: faster)", "Fly camera", [KEY_E]],
	["cam_down", "Down", "Fly camera", [KEY_Q]],
	["toggle_view", "First / third person, cab view", "General", [KEY_V]],
	["fly_camera", "Fly camera on / off", "General", [KEY_F1]],
	["inspect", "Inspect what is under the crosshair", "General", [KEY_F]],
	["inspect_close", "Close the inspection", "General", [KEY_X]],
	["toggle_help", "Show / hide the help", "General", [KEY_H]],
	["toggle_quality", "Graphics low / high", "General", [KEY_F2]],
	["night", "Day / night", "General", [KEY_N]],
	["toggle_stats", "Frame rate and network", "General", [KEY_F3]],
]
## Keys that cannot be changed, for the controls page.
const FIXED := [["Esc", "Menu, close"], ["Enter", "Chat (LAN games)"], ["Tab (held)", "Players (LAN games)"],
		["F11", "Fullscreen"], ["Mouse wheel", "Zoom (all the way in: first person, cab view)"],
		["Right mouse (held)", "Look around (fly camera, vehicles)"]]

## Defaults of the other settings (section "settings" of the file).
const DEFAULTS := {"quality": "auto", "fullscreen": false, "vsync": true, "scale_3d": 0.0, "ui_scale": 1.0,
		"mouse": 1.0, "night": false, "traffic": true}

## Mouse look factor (values["mouse"]) for car.gd, player.gd and fly_camera.gd: the tools preload those before the
## autoload's name exists, so they read it here (preload this script) instead of through "Settings".
static var mouse_scale := 1.0

var values := DEFAULTS.duplicate()
var _bindings := {}                         # action -> Array of bindings
var _tool := false                          # run by a tool (--script): defaults, window untouched
var _env_quality := ""                      # PLATEAU_QUALITY, until the quality is changed here
var _env_night := ""                        # PLATEAU_NIGHT (1 or 0), until night is switched here


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tool = "--script" in OS.get_cmdline_args() or "-s" in OS.get_cmdline_args()
	var q := OS.get_environment("PLATEAU_QUALITY")
	_env_quality = q if q in ["low", "high"] else ""
	var n := OS.get_environment("PLATEAU_NIGHT")
	_env_night = n if n in ["0", "1"] else ""
	register_actions()
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	for action: Array in ACTIONS:
		var saved: Variant = cfg.get_value("keys", action[0]) if cfg.has_section_key("keys", action[0]) else null
		_bindings[action[0]] = saved if saved is Array and not _tool else action[3].duplicate()
	if not _tool:
		for k: String in DEFAULTS:
			var v: Variant = cfg.get_value("settings", k, DEFAULTS[k])
			values[k] = v if typeof(v) == typeof(DEFAULTS[k]) else DEFAULTS[k]
	mouse_scale = values["mouse"]
	for action: String in _bindings:
		_apply_binding(action)
	if _tool or DisplayServer.get_name() == "headless":
		return
	if not values["fullscreen"] and not Engine.is_embedded_in_editor():
		_fit_window()
	get_tree().root.size_changed.connect(_apply_scale_3d)
	_apply_display()


## Adds the ACTIONS to the InputMap with their default bindings (Settings applies the saved ones over them).
static func register_actions() -> void:
	for action: Array in ACTIONS:
		if InputMap.has_action(action[0]):
			continue
		InputMap.add_action(action[0])
		for b: int in action[3]:
			InputMap.action_add_event(action[0], binding_event(b))


static func binding_event(b: int) -> InputEvent:
	if b < 0:
		var m := InputEventMouseButton.new()
		m.button_index = -b as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = b as Key
	return k


## The binding of a key or mouse button event, 0 for anything else (the mouse wheel too).
static func event_binding(event: InputEvent) -> int:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index not in [MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return -(event as InputEventMouseButton).button_index
	return 0


## A binding as this keyboard's layout shows it ("Z" for the physical W on AZERTY), or the mouse button.
static func binding_text(b: int) -> String:
	if b < 0:
		return {MOUSE_BUTTON_LEFT: "Left click", MOUSE_BUTTON_RIGHT: "Right click",
				MOUSE_BUTTON_MIDDLE: "Middle click"}.get(-b, "Mouse %d" % -b)
	var label := DisplayServer.keyboard_get_label_from_physical(b as Key) \
			if DisplayServer.get_name() != "headless" else b as Key
	var text := OS.get_keycode_string(label if label != KEY_NONE else b as Key)
	return {"Up": "↑", "Down": "↓", "Left": "←", "Right": "→"}.get(text, text)


func bindings(action: String) -> Array:
	return _bindings.get(action, [])


## The first key of `action`, for the help lines: "W" ("Z" on AZERTY), "?" when unbound.
func key_text(action: String) -> String:
	var list := bindings(action)
	return binding_text(list[0]) if not list.is_empty() else "?"


## Sets binding `slot` (0 or 1) of `action`; b == 0 clears it.
func set_binding(action: String, slot: int, b: int) -> void:
	var list: Array = bindings(action).duplicate()
	if b != 0 and list.has(b):
		list.erase(b)
	if slot < list.size():
		if b == 0:
			list.remove_at(slot)
		else:
			list[slot] = b
	elif b != 0:
		list.append(b)
	_bindings[action] = list
	_apply_binding(action)
	_save()
	changed.emit()


func reset_bindings() -> void:
	for action: Array in ACTIONS:
		_bindings[action[0]] = action[3].duplicate()
		_apply_binding(action[0])
	_save()
	changed.emit()


## Other actions of the same group bound to `b`.
func conflicts(action: String, b: int) -> PackedStringArray:
	var group := ""
	for a: Array in ACTIONS:
		if a[0] == action:
			group = a[2]
	var out := PackedStringArray()
	for a: Array in ACTIONS:
		if a[0] != action and a[2] == group and bindings(a[0]).has(b):
			out.append(a[1])
	return out


func set_value(key: String, value: Variant) -> void:
	if key == "quality":
		_env_quality = ""
	elif key == "night":
		_env_night = ""
	values[key] = value
	mouse_scale = values["mouse"]
	_apply_display()
	_save()


## The low graphics settings (game.gd): asked for, or "auto" on an integrated GPU.
func low_quality() -> bool:
	var q: String = _env_quality if _env_quality != "" else values["quality"]
	return q == "low" if q != "auto" else integrated_gpu()


## Night (game.gd, scripts/night.gd): the setting, or PLATEAU_NIGHT=1 / 0.
func night() -> bool:
	return _env_night == "1" if _env_night != "" else values["night"]


static func integrated_gpu() -> bool:
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU


## The 3D resolution: the setting, or in "auto" with the low graphics settings, at most 1920 pixels wide (a 4K screen
## on an integrated GPU).
func scale_3d() -> float:
	var s: float = values["scale_3d"]
	if s > 0.0:
		return s
	var width := float(get_tree().root.size.x)
	return clampf(1920.0 / width, 0.5, 1.0) if low_quality() and width > 0.0 else 1.0


func toggle_fullscreen() -> void:
	set_value("fullscreen", not values["fullscreen"])


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11 \
			and not _tool and DisplayServer.get_name() != "headless":
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _apply_binding(action: String) -> void:
	InputMap.action_erase_events(action)
	for b: int in _bindings[action]:
		InputMap.action_add_event(action, binding_event(b))


func _apply_display() -> void:
	if not _tool and DisplayServer.get_name() != "headless":
		var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if full != values["fullscreen"] and not Engine.is_embedded_in_editor():   # a maximised window stays so
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] \
					else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
		get_tree().root.content_scale_factor = values["ui_scale"]
		_apply_scale_3d()
	changed.emit()


func _apply_scale_3d() -> void:
	var root := get_tree().root
	var s := scale_3d()
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = s


## The first window: WINDOW_FILL of the screen it opens on, centred (the project's 1600 x 900 is a quarter of a 4K
## screen, and too big for a small one).
func _fit_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	var k := minf(area.size.x / BASE_SIZE.x, area.size.y / BASE_SIZE.y) * WINDOW_FILL
	var size := Vector2i((BASE_SIZE * k).round())
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(area.position + (area.size - size) / 2)


func _save() -> void:
	if _tool:
		return
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	for action: Array in ACTIONS:
		var list: Array = _bindings[action[0]]
		if list == action[3]:
			if cfg.has_section_key("keys", action[0]):
				cfg.erase_section_key("keys", action[0])
		else:
			cfg.set_value("keys", action[0], list)
	cfg.save(FILE)
