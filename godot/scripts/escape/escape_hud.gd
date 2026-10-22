extends Control
## Escape from Plateau's screen (escape_mode.gd adds it to game.gd's HUD on each player's peer): the objective and the
## survivors' whereabouts (top left), the time to dawn or to the helicopter's take-off (top), health (bottom right,
## the time left to bleed out when knocked down) over the weapon, its rounds and the kit, markers over the survivors,
## the helicopter, the safehouse and the teammates knocked down (at the screen's edge when out of view, their labels
## kept apart), what E or G would do (bottom, over the help lines), a progress bar (helping someone up, a bandage...),
## a red edge when hurt over a dark one always there, a hit marker at the crosshair, subtitles (what a survivor says
## when picked up, the radio), and the big titles (the briefing, the end).

const MARGIN := 14.0

var mode: Node                              # escape_mode.gd

var _objective: Label
var _timer: Label
var _health_back: ColorRect
var _health_bar: ColorRect
var _health_label: Label
var _ammo: Label
var _kit: Label
var _prompt: Label
var _progress_back: ColorRect
var _progress_bar: ColorRect
var _progress_label: Label
var _title: Label
var _subtitle: Label
var _line: Label
var _line_t := 0.0
var _vignette: ColorRect
var _markers: Control
var _hit: Control
var _hit_t := 0.0
var _kill := false
var _hurt := 0.0
var _title_t := 0.0                         # s the title stays (<0: until cleared)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := ShaderMaterial.new()
	sh.shader = _vignette_shader()
	_vignette.material = sh
	add_child(_vignette)
	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	_objective = _label(16, HORIZONTAL_ALIGNMENT_LEFT)
	_objective.position = Vector2(MARGIN, MARGIN)
	add_child(_objective)
	_timer = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_timer)
	_health_back = ColorRect.new()
	_health_back.color = Color(0, 0, 0, 0.55)
	_health_back.size = Vector2(300, 16)
	_health_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_back)
	_health_bar = ColorRect.new()
	_health_bar.color = Color(0.85, 0.15, 0.12)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_back.add_child(_health_bar)
	_health_label = _label(15, HORIZONTAL_ALIGNMENT_CENTER)
	_health_back.add_child(_health_label)
	_ammo = _label(24, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_ammo)
	_kit = _label(16, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_kit)
	_prompt = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_prompt)
	_progress_back = ColorRect.new()
	_progress_back.color = Color(0, 0, 0, 0.55)
	_progress_back.size = Vector2(260, 10)
	_progress_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_back)
	_progress_bar = ColorRect.new()
	_progress_bar.color = Color(0.95, 0.85, 0.4)
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_back.add_child(_progress_bar)
	_progress_label = _label(16, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_progress_label)
	_title = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_color_override("font_color", Color(0.9, 0.12, 0.08))
	add_child(_title)
	_subtitle = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size.x = 760
	add_child(_subtitle)
	_line = _label(19, HORIZONTAL_ALIGNMENT_CENTER)
	_line.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 700
	add_child(_line)
	_hit = Control.new()
	_hit.size = Vector2(36, 36)
	_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit.draw.connect(_draw_hit)
	add_child(_hit)


func _label(font: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A big title (red) over a smaller line, for `seconds` (< 0: until the next one, or clear_title).
func show_title(title: String, subtitle: String, seconds := 6.0) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_title_t = seconds


func clear_title() -> void:
	_title_t = 0.0
	_title.text = ""
	_subtitle.text = ""


## What survivor `who` says when picked up.
func say_line(who: String, line: String) -> void:
	subtitle("%s: \"%s\"" % [who, line], Color(0.75, 1.0, 0.75))


## A subtitle at the bottom for a few seconds (a survivor speaking, the radio).
func subtitle(text: String, color: Color, seconds := 6.0) -> void:
	_line.text = text
	_line.add_theme_color_override("font_color", color)
	_line_t = seconds


## Hurt by `damage`: the red edge flares.
func hurt(damage: float) -> void:
	_hurt = minf(_hurt + damage / 30.0, 1.0)


## A round hit a zombie (`kill`: it went down).
func hit_marker(kill: bool) -> void:
	_hit_t = 0.18
	_kill = kill
	_hit.queue_redraw()


func _process(delta: float) -> void:
	var view := get_viewport_rect().size
	_hurt = maxf(_hurt - delta * 0.6, 0.0)
	var low := clampf(1.0 - float(mode.health) / 45.0, 0.0, 1.0) if not mode.dead else 0.0
	var mat := _vignette.material as ShaderMaterial
	mat.set_shader_parameter("hurt", maxf(_hurt, low * (0.35 + 0.15 * sin(Time.get_ticks_msec() / 160.0))))
	mat.set_shader_parameter("dark", 0.55 if not mode.downed else 0.85)
	if _title_t > 0.0:
		_title_t -= delta
		if _title_t <= 0.0:
			clear_title()
	_line_t -= delta
	_line.visible = _line_t > 0.0
	_hit_t -= delta
	_hit.visible = _hit_t > 0.0
	_hit.position = view * 0.5 - _hit.size * 0.5
	_objective.text = mode.objective_text()
	_timer.text = mode.timer_text()
	_timer.reset_size()
	_timer.position = Vector2(view.x * 0.5 - _timer.size.x * 0.5, MARGIN)
	var in_vehicle: bool = mode.game.driving != null or mode.game.riding != null
	# health
	var h: float = clampf(float(mode.health) / float(mode.MAX_HEALTH), 0.0, 1.0)
	_health_back.position = Vector2(view.x - _health_back.size.x - MARGIN - 4.0, view.y - 104.0)
	_health_back.visible = not mode.dead and not mode.escaped
	if mode.downed:
		var b: float = clampf(float(mode.bleed) / float(mode.BLEED_TIME), 0.0, 1.0)
		_health_bar.size = Vector2(_health_back.size.x * b, _health_back.size.y)
		_health_bar.color = Color(0.55, 0.05, 0.05) if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color(0.8, 0.1, 0.08)
		_health_label.text = "DOWN · bleeding out in %d s" % ceili(mode.bleed)
	else:
		_health_bar.size = Vector2(_health_back.size.x * h, _health_back.size.y)
		_health_bar.color = Color(0.85, 0.15, 0.12).lerp(Color(0.3, 0.8, 0.3), h)
		_health_label.text = "%d" % ceili(mode.health)
	_health_label.size = _health_back.size
	_health_label.position = Vector2(0, -2)
	# weapon and kit
	var arsenal: Node = mode.arsenal
	_ammo.visible = arsenal != null and not in_vehicle and not mode.dead
	_kit.visible = arsenal != null and not mode.dead
	if arsenal:
		_ammo.text = arsenal.ammo_text()
		_kit.text = "bandages %d · medkits %d · flashlight %d %%%s" % [arsenal.bandages, arsenal.medkits,
				roundi(arsenal.battery * 100.0), " (+%d)" % arsenal.batteries if arsenal.batteries > 0 else ""]
		_ammo.reset_size()
		_kit.reset_size()
		_ammo.position = Vector2(view.x - _ammo.size.x - MARGIN - 4.0, view.y - _ammo.size.y - 44.0)
		_kit.position = Vector2(view.x - _kit.size.x - MARGIN - 4.0, view.y - _kit.size.y - 20.0)
	# prompt and progress
	_prompt.text = mode.prompt_text()
	_prompt.reset_size()
	_prompt.position = Vector2(view.x * 0.5 - _prompt.size.x * 0.5, view.y - 158.0)
	var prog: Array = mode.progress()
	_progress_back.visible = not prog.is_empty()
	_progress_label.visible = not prog.is_empty()
	if not prog.is_empty():
		_progress_back.position = Vector2(view.x * 0.5 - _progress_back.size.x * 0.5, view.y * 0.5 + 60.0)
		_progress_bar.size = Vector2(_progress_back.size.x * clampf(prog[1], 0.0, 1.0), _progress_back.size.y)
		_progress_label.text = prog[0]
		_progress_label.reset_size()
		_progress_label.position = Vector2(view.x * 0.5 - _progress_label.size.x * 0.5, view.y * 0.5 + 32.0)
	# titles
	_title.reset_size()
	_title.position = Vector2(view.x * 0.5 - _title.size.x * 0.5, view.y * 0.28)
	_subtitle.reset_size()
	_subtitle.position = Vector2(view.x * 0.5 - _subtitle.size.x * 0.5, view.y * 0.28 + _title.size.y + 8.0)
	_line.reset_size()
	_line.position = Vector2(view.x * 0.5 - _line.size.x * 0.5, view.y - 205.0 - maxf(_line.size.y - 30.0, 0.0))
	_markers.queue_redraw()


func _draw_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := get_viewport_rect().size
	var font := get_theme_default_font()
	var eye := cam.global_position
	var placed: Array[Rect2] = []               # labels drawn so far: the next ones keep clear of them
	for m: Array in mode.markers():
		var p: Vector3 = m[0]
		var col: Color = m[1]
		var text: String = m[2]
		var d := eye.distance_to(p)
		var label := "%s · %d m" % [text, roundi(d)] if text != "" else "%d m" % roundi(d)
		var behind := cam.is_position_behind(p)
		var s := cam.unproject_position(p)
		var inside := not behind and s.x > 40.0 and s.x < view.x - 40.0 and s.y > 40.0 and s.y < view.y - 40.0
		if inside:
			draw_diamond(s, 8.0, col)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var lp := _keep_clear(s + Vector2(-w * 0.5, -14.0), Vector2(w, 16.0), placed)
			_markers.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
			_markers.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		else:
			# at the screen's edge, pointing the way
			var c := view * 0.5
			var dir := (s - c) if not behind else (c - s)
			if dir.length_squared() < 1.0:
				dir = Vector2.DOWN
			dir = dir.normalized()
			var k := minf((view.x * 0.5 - 50.0) / maxf(absf(dir.x), 0.001), (view.y * 0.5 - 50.0) / maxf(absf(dir.y), 0.001))
			var at := c + dir * k
			var tri := PackedVector2Array([at + dir * 14.0, at + dir.orthogonal() * 8.0, at - dir.orthogonal() * 8.0])
			_markers.draw_colored_polygon(tri, col)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var lp := at - dir * 18.0 + Vector2(-w * 0.5, 5.0)
			lp.x = clampf(lp.x, 6.0, view.x - w - 6.0)
			lp = _keep_clear(lp, Vector2(w, 15.0), placed)
			_markers.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
			_markers.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


## Where a label of `size` (its baseline at `at`) goes clear of the `placed` ones (moved down a line at a time); it is
## added to them.
static func _keep_clear(at: Vector2, size: Vector2, placed: Array[Rect2]) -> Vector2:
	var r := Rect2(at - Vector2(0.0, size.y), size)
	for k in 8:
		var hit := false
		for o in placed:
			if o.intersects(r):
				hit = true
				break
		if not hit:
			break
		r.position.y += size.y + 1.0
	placed.append(r)
	return r.position + Vector2(0.0, size.y)


func draw_diamond(at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	_markers.draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	var inner := PackedVector2Array()
	for q in pts:
		inner.append(at + (q - at) * 0.7)
	_markers.draw_colored_polygon(inner, col)


func _draw_hit() -> void:
	var c := _hit.size * 0.5
	var col := Color(1.0, 0.25, 0.2) if _kill else Color(1, 1, 1, 0.95)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_hit.draw_line(c + d * 5.0, c + d * 13.0, Color(0, 0, 0, 0.6), 4.0, true)
		_hit.draw_line(c + d * 5.0, c + d * 13.0, col, 2.0, true)


static func _vignette_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
// A dark edge always (the night closing in), red over it when hurt.
uniform float dark = 0.55;
uniform float hurt = 0.0;
void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.7, 1.0);
	float r = length(d);
	float edge = smoothstep(0.32, 1.0, r);
	vec3 col = mix(vec3(0.0), vec3(0.55, 0.0, 0.0), clamp(hurt * 1.5, 0.0, 1.0));
	COLOR = vec4(col, clamp(edge * dark + edge * hurt * 0.9, 0.0, 0.95));
}
"""
	return s
