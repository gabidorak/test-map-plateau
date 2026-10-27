extends Control
## Full-screen loading screen, shared by the startup scene (scripts/loading_scene.gd) and game.gd's overlay while a
## LAN game is hosted or joined. Built in code like the other menus (scripts/ui_style.gd): a dark sky, the game's
## name, an animated orbit, what is loading, a progress bar and a tip that changes while it waits. `set_progress` is
## 0..1 (the bar eases towards it, so a coarse ResourceLoader progress still reads as smooth motion); `set_status`
## says what is happening. show_error keeps the screen up with a message and a Try again button (startup failures)
## and close fades it out and frees it. `fade_in = false` shows it at once (game.gd's host/join overlay), so a step
## that blocks cannot freeze on a half-transparent screen. Its callers put it on a CanvasLayer (layer 50) above the
## menus but below the updater's own screen (layer 100), and it keeps the mouse from reaching the menu behind it.

signal retry                                  # the Try again button (only shown by show_error)

const UiStyle = preload("res://scripts/ui_style.gd")
const ACCENT := Color(1.0, 0.62, 0.25)        # the welcome menu's orange
const TEXT := Color(0.93, 0.94, 0.97)
const FADE_TIME := 0.3
const CLOSE_TIME := 0.32
const TIP_EVERY := 7.0
const TIPS := [
	"Tip: press E next to a vehicle to get in, and Space to get out.",
	"Tip: press F1 for the free fly camera, all the way up over the plateau.",
	"Tip: press N to switch between day and night.",
	"Tip: hold Tab to see who is playing, and their ping.",
	"Tip: press Enter to chat in a LAN game.",
	"Tip: press F3 to show the frame rate, and the network timings.",
	"Tip: press F2 to switch between low and high graphics.",
	"Tip: the RER B stops at Lozère; its doors open for a moment.",
	"Tip: host a game on your network, then pick a game mode together.",
]

var _bar: ProgressBar
var _status: Label
var _percent: Label
var _tip: Label
var _retry: Button
var _orbit: Orbit
var _content: VBoxContainer
var _target := 0.0
var _shown := 0.0
var _tip_i := 0
var _tip_t := 0.0
var _tip_tween: Tween
var _closing := false
var fade_in := true                           # the startup scene fades in; game.gd's overlay covers the menu at once


## The little atom-like mark: two rings and a dot going round, drawn in code (no texture to load before the game).
class Orbit extends Control:
	var phase := 0.0
	var accent := Color(1, 1, 1, 1)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 86)

	func _process(delta: float) -> void:
		phase += delta * 0.9
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x * 0.44, size.y * 0.9)
		_ring(c, r, r * 0.4, 0.35, Color(accent, 0.28), 1.3)
		_ring(c, r * 0.76, r * 0.32, -0.55, Color(1, 1, 1, 0.14), 1.0)
		var dot := c + Vector2(cos(phase) * r, sin(phase) * r * 0.4).rotated(0.35)
		draw_circle(dot, 3.0, accent)
		draw_circle(dot, 5.5, Color(accent, 0.18))
		draw_circle(c, 2.0, Color(accent, 0.55))

	## One ellipse through 72 points, rotated by `rot` around `c`.
	func _ring(c: Vector2, rx: float, ry: float, rot: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for i in 73:
			var a := TAU * float(i) / 72.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
		draw_polyline(pts, col, width, true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_tip.text = TIPS[0]
	modulate.a = 1.0
	if fade_in:
		modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)


## "Loading the plateau…", "Connecting to 192.168.1.42:7777…", "Ready"...
func set_status(text: String) -> void:
	if _status:
		_status.text = text


## 0..1 (the bar eases towards it); the percentage under it follows. 1 fills it at once, so "Ready" is not shown
## with a half-empty bar while the screen fades out.
func set_progress(fraction: float) -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if _target >= 1.0:
		_shown = 1.0
		if _bar:
			_bar.value = 1.0
			_percent.text = "100 %"


## No progress to report (returning to the main menu): the status line and the moving orbit only.
func set_indeterminate() -> void:
	_bar.visible = false
	_percent.visible = false


## Keeps the screen up with `message` and a Try again button (the startup scene could not load the game).
func show_error(message: String) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", UiStyle.TEXT_WARN)
	_bar.visible = false
	_percent.visible = false
	_retry.visible = true
	_retry.grab_focus()


## Back from an error: the bar and the status line again.
func reset() -> void:
	_status.add_theme_color_override("font_color", TEXT)
	_bar.visible = true
	_percent.visible = true
	_retry.visible = false
	_target = 0.0
	_shown = 0.0
	_bar.value = 0.0
	_percent.text = "0 %"


## Fades the screen out and frees it (the game carries on behind).
func close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	tween.tween_callback(queue_free)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# A soft glow behind the title, so the flat background reads as sky rather than a blank window.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.12, 0.16, 0.23))
	grad.set_color(1, Color(0.025, 0.032, 0.048))
	var glow := GradientTexture2D.new()
	glow.gradient = grad
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.38)
	glow.fill_to = Vector2(1.0, 1.0)
	glow.width = 256
	glow.height = 256
	var sky := TextureRect.new()
	sky.texture = glow
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.custom_minimum_size.x = 480
	centre.add_child(_content)

	_orbit = Orbit.new()
	_orbit.accent = ACCENT
	var mark := CenterContainer.new()
	mark.add_child(_orbit)
	_content.add_child(mark)
	var title := UiStyle.label("Plateau Map", 54, Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("outline_size", 7)
	_content.add_child(title)
	var subtitle := UiStyle.label("The Saclay plateau, from Télécom Paris to ENSTA Paris", 16, UiStyle.TEXT_DIM)
	_content.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 16
	_content.add_child(gap)

	var row := HBoxContainer.new()
	row.custom_minimum_size.x = 480
	_status = UiStyle.label("Loading the plateau…", 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_status)
	_percent = UiStyle.label("0 %", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_percent)
	_content.add_child(row)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(480, 8)
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.1)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	_content.add_child(_bar)

	_retry = UiStyle.button("Try again", UiStyle.button_looks(), Vector2(180, 40), 17)
	_retry.visible = false
	_retry.pressed.connect(func() -> void: retry.emit())
	var retry_row := CenterContainer.new()
	retry_row.add_child(_retry)
	_content.add_child(retry_row)

	# Bottom: the build at the left, a changing tip in the middle.
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if version != "":
		var build := UiStyle.label("Plateau Map  ·  " + version, 13, Color(0.55, 0.58, 0.66), HORIZONTAL_ALIGNMENT_LEFT)
		build.anchor_left = 0.0
		build.anchor_right = 0.0
		build.anchor_top = 1.0
		build.anchor_bottom = 1.0
		build.offset_left = 26
		build.offset_right = 420
		build.offset_top = -34
		build.offset_bottom = -14
		build.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		build.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(build)
	_tip = UiStyle.label("", 15, Color(0.6, 0.63, 0.71))
	_tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_left = 80
	_tip.offset_right = -80
	_tip.offset_top = -42
	_tip.offset_bottom = -18
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)


func _process(delta: float) -> void:
	if _closing:
		return
	# Ease the bar towards the loader's figure: its progress moves in steps, the bar follows smoothly.
	_shown = lerpf(_shown, _target, 1.0 - exp(-delta / 0.12))
	if absf(_shown - _target) < 0.0005:
		_shown = _target
	if _bar.visible:
		_bar.value = _shown
		_percent.text = "%d %%" % roundi(_shown * 100.0)
	_tip_t += delta
	if _tip_t >= TIP_EVERY:
		_tip_t = 0.0
		_next_tip()


## Fades the current tip out, swaps it, and fades the next one in.
func _next_tip() -> void:
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip, "modulate:a", 0.0, 0.3)
	_tip_tween.tween_callback(func() -> void:
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = TIPS[_tip_i])
	_tip_tween.tween_property(_tip, "modulate:a", 1.0, 0.45)
