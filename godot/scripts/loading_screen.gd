extends Control
## Full-screen loading screen, shared by the loader (scripts/loading_scene.gd: the game's start, and going back to the
## main menu) and game.gd's overlay while a game starts (solo, hosted or joined). Built in code like the other menus
## (scripts/ui_style.gd): a night-blue background under the plateau's animated transit map (scripts/loading_map.gd),
## the game's name at the top left, the lines' legend at the top right, and at the bottom what is happening, a progress
## bar and a tip that changes while it waits.
## `set_progress(fraction, up_to)` is 0..1: the bar eases towards `fraction`, then creeps on towards `up_to` while
## nothing new is reported (a long step still moves the bar a little); a sheen keeps running along it in any case.
## `set_status` says what is happening. show_error keeps the screen up with a message and a Try again button (startup
## failures) and close fades it out and frees it. It fades in (`shown` once opaque) unless `fade_in` is false. Its
## callers put it on a CanvasLayer (layer 50) above the menus but below the updater's own screen (layer 100), and it
## keeps the mouse from reaching the menu behind it. It runs while the tree is paused (the loader pauses the game).

signal retry                                  # the Try again button (only shown by show_error)
signal shown                                  # fully opaque (at once when fade_in is false)

const UiStyle = preload("res://scripts/ui_style.gd")
const LoadingMap = preload("res://scripts/loading_map.gd")
const ACCENT := Color(1.0, 0.62, 0.25)        # the welcome menu's orange
const TEXT := Color(0.93, 0.94, 0.97)
const FADE_TIME := 0.25
const CLOSE_TIME := 0.35
const TIP_EVERY := 6.5
const CREEP_TIME := 2.5                       # s: time constant of the creep towards `up_to`
const MARGIN := Vector2(48, 40)
const TIPS := [
	"Press E next to a vehicle to get in, and Space to get out.",
	"Press F1 for the free fly camera, all the way up over the plateau.",
	"Press N to switch between day and night, and L for the headlights.",
	"Hold Tab to see who is playing, and their ping.",
	"Press Enter to chat in a LAN game.",
	"Press F3 to show the frame rate, and the network timings.",
	"Press U to park any vehicle next to you.",
	"The RER B stops at Lozère: its doors open for a moment.",
	"Host a game on your network, then pick a game mode together.",
	"Press F2 to switch between low and high graphics.",
	"The bot buses drive the real lines: 4606, 4619, L and Z.",
]

var fade_in := true                           # false: opaque at once
var _bar: Bar
var _status: Label
var _percent: Label
var _tip: Label
var _retry: Button
var _map: LoadingMap
var _legend: HBoxContainer
var _target := 0.0                            # what the loader reported
var _ceiling := 0.0                           # where the bar may creep to meanwhile
var _shown := 0.0                             # what the bar shows
var _tip_i := 0
var _tip_t := 0.0
var _tip_tween: Tween
var _closing := false


## The bar: a rounded track, the filled part, and a sheen running along it. Indeterminate: a segment going to and fro.
class Bar extends Control:
	var value := 0.0
	var indeterminate := false
	var accent := Color.WHITE
	var _track: StyleBoxFlat
	var _fill: StyleBoxFlat
	var _t := 0.0                               # s: the frames' deltas (the clock read after the loader's work jitters)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 6)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		var t := _t
		if _track == null:
			_track = _box(Color(1, 1, 1, 0.1), r)
			_fill = _box(accent, r)
		draw_style_box(_track, Rect2(Vector2.ZERO, size))
		var from := 0.0
		var to := clampf(value, 0.0, 1.0) * size.x
		if indeterminate:
			var u := 0.5 - 0.5 * cos(t * 2.2)
			from = u * size.x * 0.72
			to = from + size.x * 0.28
		if to - from < size.y:
			return
		draw_style_box(_fill, Rect2(from, 0.0, to - from, size.y))
		# The sheen: a soft light sliding over the filled part, every 1.6 s.
		var w := 90.0
		var x := from + fposmod(t / 1.6, 1.0) * (to - from + w) - w
		var a := maxf(from, x)
		var b := minf(to, x + w)
		if b - a > 1.0:
			var mid := x + w * 0.5
			for k in 6:
				var x0 := lerpf(a, b, k / 6.0)
				var x1 := lerpf(a, b, (k + 1) / 6.0)
				var glow := 1.0 - absf((x0 + x1) * 0.5 - mid) / (w * 0.5)
				draw_rect(Rect2(x0, 1.0, x1 - x0, size.y - 2.0), Color(1, 1, 1, 0.35 * maxf(glow, 0.0)))

	func _box(c: Color, r: float) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		return sb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_tip_i = randi() % TIPS.size()
	_tip.text = TIPS[_tip_i]
	modulate.a = 1.0
	if fade_in:
		modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
		tween.tween_callback(shown.emit)
	else:
		shown.emit.call_deferred()


## "Waking up the plateau…", "Connecting to 192.168.1.42:7777…", "Ready"...
func set_status(text: String) -> void:
	if _status:
		_status.text = text


## 0..1 (the bar eases towards it), then creeping towards `up_to` (>= fraction) until the next figure. 1 fills it at
## once, so "Ready" is not shown with a half-empty bar while the screen fades out. The bar never goes back, but for
## reset.
func set_progress(fraction: float, up_to := -1.0) -> void:
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	_ceiling = maxf(_target, clampf(up_to, 0.0, 1.0))
	if _target >= 1.0:
		_shown = 1.0
		if _bar:
			_bar.value = 1.0
			_percent.text = "100 %"


## No progress to report: a segment going to and fro instead of the filled bar, no percentage.
func set_indeterminate(on := true) -> void:
	_bar.indeterminate = on
	_percent.visible = not on


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
	_bar.indeterminate = false
	_percent.visible = true
	_retry.visible = false
	_target = 0.0
	_ceiling = 0.0
	_shown = 0.0
	_bar.value = 0.0
	_percent.text = "0 %"


## Fades the screen out and frees it (the game carries on behind).
func close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)


func _build() -> void:
	# Night-blue sky, a little lighter in the middle where the map is.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.075, 0.105, 0.16))
	grad.set_color(1, Color(0.02, 0.028, 0.045))
	var glow := GradientTexture2D.new()
	glow.gradient = grad
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.48)
	glow.fill_to = Vector2(1.05, 1.1)
	glow.width = 256
	glow.height = 256
	var sky := TextureRect.new()
	sky.texture = glow
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	_map = LoadingMap.new()
	add_child(_map)

	# Top left: the name, what it is, the build.
	var head := VBoxContainer.new()
	head.position = MARGIN
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var title := UiStyle.label("Plateau Map", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("outline_size", 8)
	head.add_child(title)
	head.add_child(UiStyle.label("The Saclay plateau, from Télécom Paris to ENSTA Paris", 16, UiStyle.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if version != "":
		head.add_child(UiStyle.label(version, 13, Color(0.5, 0.53, 0.6), HORIZONTAL_ALIGNMENT_LEFT))

	# Top right: the lines on the map (filled in once it is read).
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 8)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_legend.offset_right = -MARGIN.x
	_legend.offset_top = MARGIN.y + 14
	_legend.modulate.a = 0.0
	add_child(_legend)

	# Bottom left: what is happening, the bar, Try again.
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = MARGIN.x
	foot.offset_right = MARGIN.x + 560
	foot.offset_bottom = -MARGIN.y
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(foot)
	var row := HBoxContainer.new()
	_status = UiStyle.label("Waking up the plateau…", 19, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_status.add_theme_constant_override("outline_size", 5)
	row.add_child(_status)
	_percent = UiStyle.label("0 %", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_percent.custom_minimum_size.x = 56
	row.add_child(_percent)
	foot.add_child(row)
	_bar = Bar.new()
	_bar.accent = ACCENT
	foot.add_child(_bar)
	_retry = UiStyle.button("Try again", UiStyle.button_looks(), Vector2(180, 40), 17)
	_retry.visible = false
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_retry.pressed.connect(func() -> void: retry.emit())
	foot.add_child(_retry)

	# Bottom right: a tip.
	_tip = UiStyle.label("", 15, Color(0.62, 0.65, 0.73), HORIZONTAL_ALIGNMENT_RIGHT)
	_tip.anchor_left = 1.0
	_tip.anchor_right = 1.0
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_left = -MARGIN.x - 520
	_tip.offset_right = -MARGIN.x
	_tip.offset_top = -MARGIN.y - 44
	_tip.offset_bottom = -MARGIN.y + 2
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)


## The legend's pills: the RER B, then each bus line in its colour.
func _build_legend() -> void:
	var lines: Array = [["RER B", LoadingMap.RER_B]]
	for line: Dictionary in LoadingMap._data.get("lines", []):
		lines.append([("Bus " if line["ref"].is_valid_int() else "Line ") + line["ref"], line["colour"]])
	for l: Array in lines:
		var c: Color = l[1]
		var pill := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(11)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		sb.content_margin_bottom = 3
		pill.add_theme_stylebox_override("panel", sb)
		pill.add_child(UiStyle.label(l[0], 13, Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE))
		_legend.add_child(pill)
	create_tween().tween_property(_legend, "modulate:a", 1.0, 0.6)


func _process(delta: float) -> void:
	if _closing:
		return
	if _legend.get_child_count() == 0 and LoadingMap.ready_to_draw() and not LoadingMap._data.has("empty"):
		_build_legend()
	# Creep towards the ceiling while nothing new comes in, and ease the bar towards that.
	_target = lerpf(_target, _ceiling, 1.0 - exp(-delta / CREEP_TIME))
	_shown = lerpf(_shown, _target, 1.0 - exp(-delta / 0.15))
	if absf(_shown - _target) < 0.0005:
		_shown = _target
	_bar.value = _shown
	if _percent.visible:
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
