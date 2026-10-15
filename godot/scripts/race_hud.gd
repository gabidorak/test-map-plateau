extends Control
## On-screen side of the races (scripts/races.gd adds it to game.gd's HUD): the offer to race while in a start circle
## (and an invitation to join one), the race banner at the top right (time, checkpoints, place, the bus race's
## off-road warning), the 3-2-1 countdown, short notices in the middle ("Checkpoint 4/18"), an arrow at the top
## pointing to the next checkpoint with its distance, and the results at the end.

const UiStyle = preload("res://scripts/ui_style.gd")
const GOLD := Color(1.0, 0.82, 0.3)
const WARN := Color(1.0, 0.4, 0.3)

var _prompt: PanelContainer
var _prompt_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _banner_warn: Label
var _count: Label
var _count_t := 0.0                         # s the big text stays (0: until replaced)
var _flash: Label
var _flash_t := 0.0
var _results: PanelContainer
var _results_box: VBoxContainer
var _results_t := 0.0
var _arrow: Control
var _arrow_angle := 0.0                     # rad, clockwise from straight ahead (the camera's)
var _arrow_label: Label


func _ready() -> void:
	name = "RaceHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", UiStyle.panel(0.75, 10, 14))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label = UiStyle.label("", 19)
	_prompt.add_child(_prompt_label)
	add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 170)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.visible = false

	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UiStyle.panel(0.7, 10, 12))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bbox := VBoxContainer.new()
	_banner.add_child(bbox)
	_banner_label = UiStyle.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	bbox.add_child(_banner_label)
	_banner_warn = UiStyle.label("", 20, WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	_banner_warn.visible = false
	bbox.add_child(_banner_warn)
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_banner.offset_top = 48.0                   # under the host's address
	_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_banner.visible = false

	_count = _big_label(110)
	add_child(_count)
	_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_count.offset_top -= 120.0
	_count.offset_bottom -= 120.0
	_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count.grow_vertical = Control.GROW_DIRECTION_BOTH
	_flash = _big_label(30)
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_flash.offset_top += 70.0
	_flash.offset_bottom += 70.0
	_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flash.grow_vertical = Control.GROW_DIRECTION_BOTH

	_results = PanelContainer.new()
	_results.add_theme_stylebox_override("panel", UiStyle.panel(0.85))
	_results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 6)
	_results.add_child(_results_box)
	add_child(_results)
	UiStyle.centre(_results)
	_results.visible = false

	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(64, 64)
	_arrow.size = Vector2(64, 64)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 0)
	_arrow.offset_top = 112.0
	_arrow.offset_bottom = 176.0
	_arrow.offset_left = -32.0
	_arrow.offset_right = 32.0
	_arrow.visible = false
	_arrow_label = UiStyle.label("", 17)
	_arrow_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_arrow_label.add_theme_constant_override("outline_size", 5)
	add_child(_arrow_label)
	_arrow_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 178)
	_arrow_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arrow_label.visible = false


func _big_label(size: int) -> Label:
	var l := UiStyle.label("", size, GOLD)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10 if size > 60 else 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	return l


func _process(delta: float) -> void:
	if _count_t > 0.0:
		_count_t -= delta
		_count.modulate.a = clampf(_count_t * 2.0, 0.0, 1.0)
		if _count_t <= 0.0:
			_count.visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.modulate.a = clampf(_flash_t * 2.0, 0.0, 1.0)
		if _flash_t <= 0.0:
			_flash.visible = false
	if _results_t > 0.0:
		_results_t -= delta
		if _results_t <= 0.0:
			_results.visible = false


func show_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt.visible = text != ""


func prompt_text() -> String:
	return _prompt_label.text if _prompt.visible else ""


func set_banner(text: String, warn := "") -> void:
	_banner.visible = text != ""
	_banner_label.text = text
	_banner_warn.text = warn
	_banner_warn.visible = warn != ""


func banner_text() -> String:
	return _banner_label.text if _banner.visible else ""


## The big text in the middle ("3", "GO!"), for `seconds` (0: until the next one).
func count(text: String, seconds := 0.0, color := GOLD) -> void:
	_count.text = text
	_count.add_theme_color_override("font_color", color)
	_count.add_theme_font_size_override("font_size", 110 if text.length() <= 4 else 64)
	_count.visible = text != ""
	_count.modulate.a = 1.0
	_count_t = seconds


func flash(text: String, seconds := 2.0, color := Color.WHITE) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash.visible = true
	_flash.modulate.a = 1.0
	_flash_t = seconds


func flash_text() -> String:
	return _flash.text if _flash.visible else ""


## The end of a race: `title`, rows of [place text, name, time or what happened, vehicle, colour], a `footer`; shown
## for `seconds`.
func show_results(title: String, rows: Array, footer: String, seconds := 14.0) -> void:
	for c in _results_box.get_children():
		c.queue_free()
	_results_box.add_child(UiStyle.label(title, 24, GOLD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	for r: Array in rows:
		for k in 4:
			var l := UiStyle.label(str(r[k]), 19, r[4] if k < 3 else UiStyle.TEXT_DIM,
					HORIZONTAL_ALIGNMENT_RIGHT if k == 2 else HORIZONTAL_ALIGNMENT_LEFT)
			grid.add_child(l)
	_results_box.add_child(grid)
	if footer != "":
		_results_box.add_child(UiStyle.label(footer, 17, UiStyle.TEXT_DIM))
	_results.visible = true
	_results_t = seconds


func results_visible() -> bool:
	return _results.visible


func hide_results() -> void:
	_results.visible = false
	_results_t = 0.0


## The arrow to the next checkpoint: `angle` rad clockwise from where the camera looks, `dist` m away; NAN hides it.
func set_arrow(angle: float, dist: float) -> void:
	var on := not is_nan(angle)
	_arrow.visible = on
	_arrow_label.visible = on
	if on:
		_arrow_angle = angle
		_arrow.queue_redraw()
		_arrow_label.text = "%d m" % roundi(dist)


func _draw_arrow() -> void:
	var c := _arrow.size * 0.5
	var pts := PackedVector2Array([Vector2(0, -26), Vector2(18, 16), Vector2(0, 6), Vector2(-18, 16)])
	var rot := Transform2D(_arrow_angle, c)
	var p := rot * pts
	_arrow.draw_colored_polygon(p, GOLD)
	p.append(p[0])
	_arrow.draw_polyline(p, Color(0, 0, 0, 0.8), 3.0, true)
