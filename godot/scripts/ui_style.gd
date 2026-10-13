extends RefCounted
## Look shared by the game's menus (game.gd's vehicle menu, main_menu.gd, pause_menu.gd): dark rounded panels and
## buttons, a white outline on the focused one.

const TEXT_DIM := Color(0.7, 0.72, 0.78)
const TEXT_WARN := Color(1.0, 0.75, 0.4)


static func panel(alpha := 0.9, radius := 10, margin := 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, alpha)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


## Button state -> background.
static func button_looks() -> Dictionary:
	var looks := {}
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.2, 0.22, 0.28), "hover": Color(0.3, 0.34, 0.44),
				"pressed": Color(0.16, 0.42, 0.7), "focus": Color(0, 0, 0, 0), "disabled": Color(0.14, 0.15, 0.18)}[state]
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		if state == "focus":
			sb.draw_center = false
			sb.set_border_width_all(2)
			sb.border_color = Color(1, 1, 1, 0.85)
		looks[state] = sb
	return looks


static func button(text: String, looks: Dictionary, min_size := Vector2(210, 40), font_size := 17) -> Button:
	var b := Button.new()
	for state: String in looks:
		b.add_theme_stylebox_override(state, looks[state])
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b


static func label(text: String, font_size := 17, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func line_edit(text: String, placeholder: String, min_width := 160.0) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(min_width, 38)
	e.add_theme_font_size_override("font_size", 17)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.2, 0.25)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	e.add_theme_stylebox_override("normal", sb)
	var focus := sb.duplicate() as StyleBoxFlat
	focus.set_border_width_all(2)
	focus.border_color = Color(1, 1, 1, 0.85)
	e.add_theme_stylebox_override("focus", focus)
	return e


## A panel centred on the screen, growing both ways around its content.
static func centre(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
