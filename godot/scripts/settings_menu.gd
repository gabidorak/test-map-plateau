extends PanelContainer
## Settings page (scripts/settings.gd, the "Settings" autoload), opened from the welcome menu (main_menu.gd) and the
## in-game menu (pause_menu.gd): a Graphics tab (display mode, quality, resolution, vsync, UI scale, time of day,
## and a note on what saves the most) and a Controls tab (mouse sensitivity, then every
## rebindable action with two bindings each). Click a binding, then press the new key or mouse button (Esc cancels);
## right click clears it. Esc or Back closes the page.

const UiStyle = preload("res://scripts/ui_style.gd")
const WIDTH := 820.0
const PAGE_HEIGHT := 480.0                  # both tabs, so the panel keeps its size

signal closed

var _looks := UiStyle.button_looks()
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _refresh: Array[Callable] = []          # update the shown values from the settings
var _hint: Label
var _reset: Button
var _capture := {}                          # binding waiting for a key: {action, slot, button}


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(0.94, 14, 26))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = WIDTH
	add_child(box)
	box.add_child(UiStyle.label("Settings", 34))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for t: String in ["Graphics", "Controls"]:
		var b := UiStyle.button(t, _looks, Vector2(180, 40), 18)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_show_tab.bind(_tabs.size()))
		tabs.add_child(b)
		_tabs.append(b)
	_pages.append(_build_graphics())
	_pages.append(_build_controls())
	for p in _pages:
		box.add_child(p)
	_hint = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(WIDTH, 44)  # a wrapping label's height is per word until it has a width
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_reset = UiStyle.button("Reset the keys", _looks, Vector2(200, 40))
	_reset.pressed.connect(func() -> void:
		_cancel_capture()
		Settings.reset_bindings())
	row.add_child(_reset)
	var back := UiStyle.button("Back", _looks, Vector2(200, 40))
	back.pressed.connect(close)
	row.add_child(back)
	box.add_child(row)
	Settings.changed.connect(_update)
	_show_tab(0)


func open() -> void:
	visible = true
	_update()
	UiStyle.centre(self)
	_tabs[_pages.find(_visible_page())].grab_focus()


func close() -> void:
	_cancel_capture()
	visible = false
	closed.emit()


func _visible_page() -> Control:
	for p in _pages:
		if p.visible:
			return p
	return _pages[0]


func _show_tab(i: int) -> void:
	_cancel_capture()
	for k in _pages.size():
		_pages[k].visible = k == i
		_tabs[k].set_pressed_no_signal(k == i)
	_reset.visible = i == 1
	_set_hint()


func _set_hint() -> void:
	if not _capture.is_empty():
		_hint.text = "Press the new key or mouse button for \"%s\" · Esc cancel" % _capture["label"]
	elif _pages[1].visible:
		_hint.text = "Click a binding, then press the new key or mouse button · right click a binding to clear it · " + \
				"keys follow your keyboard's layout"
	else:
		_hint.text = "F11 switches fullscreen at any time · Esc back"


func _update() -> void:
	for f in _refresh:
		f.call()
	_set_hint()


func _build_graphics() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	_choice(grid, "Display", "fullscreen", [[false, "Window"], [true, "Fullscreen"]])
	_choice(grid, "Graphics", "quality", [["auto", ""], ["low", "Low (fast, for integrated GPUs)"],
			["medium", "Medium (no indirect light, FXAA)"], ["high", "High (shadows, ambient occlusion, glow)"]],
			func(v: Variant, text: String) -> String:
				return text if v != "auto" else "Auto (%s)" % ("low: integrated GPU" if Settings.integrated_gpu() else "high"))
	_choice(grid, "Resolution", "resolution", Settings.RESOLUTIONS, _resolution_text)
	_choice(grid, "Vertical sync", "vsync", [[true, "On"], [false, "Off"]])
	_choice(grid, "Interface size", "ui_scale", [[0.75, "75 %"], [0.85, "85 %"], [1.0, "100 %"], [1.15, "115 %"],
			[1.3, "130 %"], [1.5, "150 %"]])
	_choice(grid, "Time of day", "night", [[false, "Day"], [true, "Night (moonlight, headlights)"]])
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 28)
	page.add_child(grid)
	page.add_child(_performance_note())
	var c := CenterContainer.new()
	c.custom_minimum_size.y = PAGE_HEIGHT
	c.add_child(page)
	return c


## A resolution preset as shown: its name (Auto: the height it picks here) and the size the 3D is drawn at.
func _resolution_text(v: Variant, text: String) -> String:
	var size := Settings.render_size()
	var native := Settings.get_tree().root.size.y
	if v == 0:
		text = "Auto (%s)" % ("native" if size.y >= native else "%dp" % size.y)
	elif v < 0 or v >= native:
		text = (text + ", native here") if v > 0 else text
	return "%s · %d × %d" % [text, size.x, size.y] if size.y > 0 else text


## The Graphics tab's info block: on a large screen the resolution costs the most, then the bot traffic (the host's
## in-game menu switches it).
func _performance_note() -> Control:
	var note := PanelContainer.new()
	var style := UiStyle.panel(1.0, 8, 14)
	style.bg_color = Color(0.16, 0.2, 0.3)
	style.border_width_left = 4
	style.border_color = Color(0.45, 0.65, 1.0)
	note.add_theme_stylebox_override("panel", style)
	var text := UiStyle.label("Lagging? On a large screen, lower the resolution first: 1080p draws a quarter of the " +
			"pixels of 4K, and on a laptop it leaves the processor the power it needs for the traffic. Medium graphics " +
			"save a third more. Then switch bot traffic off (bot buses, cars and RER B trains): Esc in game → " +
			"\"Bot traffic: off\", when you play solo or host. \"Clear all vehicles\" also helps when many are " +
			"parked around.", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = WIDTH - 80.0      # a wrapping label's height is per word until it has a width
	note.add_child(text)
	return note


## A row of `grid`: `title`, then ◀ value ▶ cycling setting `key` through `options` ([value, text]); `describe` may
## rewrite the text of a value.
func _choice(grid: GridContainer, title: String, key: String, options: Array, describe := Callable()) -> void:
	grid.add_child(UiStyle.label(title, 18, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var value := UiStyle.label("", 18)
	value.custom_minimum_size.x = 380
	var step := func(d: int) -> void:
		var i := 0
		for k in options.size():
			if options[k][0] == Settings.values[key]:
				i = k
		Settings.set_value(key, options[posmod(i + d, options.size())][0])
	for d: int in [-1, 1]:
		var b := UiStyle.button("◀" if d < 0 else "▶", _looks, Vector2(44, 38), 17)
		b.pressed.connect(step.bind(d))
		row.add_child(b)
		if d < 0:
			row.add_child(value)
	grid.add_child(row)
	_refresh.append(func() -> void:
		var text := str(Settings.values[key])
		for o: Array in options:
			if o[0] == Settings.values[key]:
				text = describe.call(o[0], o[1]) if describe.is_valid() else o[1]
		value.text = text)


func _build_controls() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, PAGE_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var grid := _grid(box)
	grid.add_child(UiStyle.label("Mouse sensitivity", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var sens := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(260, 34)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := UiStyle.label("", 17)
	pct.custom_minimum_size.x = 80
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d %%" % roundi(v * 100.0)
		if not is_equal_approx(v, Settings.values["mouse"]):
			Settings.set_value("mouse", v))
	_refresh.append(func() -> void:
		slider.set_value_no_signal(Settings.values["mouse"])
		pct.text = "%d %%" % roundi(Settings.values["mouse"] * 100.0))
	sens.add_child(slider)
	sens.add_child(pct)
	grid.add_child(sens)
	var group := ""
	for action: Array in Settings.ACTIONS:
		if action[2] != group:
			group = action[2]
			box.add_child(_header(group))
			grid = _grid(box)
		var label := UiStyle.label(action[1], 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 340.0
		grid.add_child(label)
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 8)
		var buttons: Array[Button] = []
		for slot in 2:
			var b := UiStyle.button("", _looks, Vector2(150, 34), 16)
			b.clip_text = true
			b.pressed.connect(_start_capture.bind(action[0], action[1], slot, b))
			b.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
					_cancel_capture()
					Settings.set_binding(action[0], slot, 0)
					accept_event())
			keys.add_child(b)
			buttons.append(b)
		grid.add_child(keys)
		_refresh.append(_show_bindings.bind(action[0], action[1], label, buttons))
	box.add_child(_header("Fixed keys"))
	grid = _grid(box)
	for f: Array in Settings.FIXED:
		grid.add_child(UiStyle.label(f[1], 17, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiStyle.label(f[0], 17, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	return scroll


func _header(text: String) -> Label:
	var l := UiStyle.label(text, 20, Color(0.65, 0.8, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size.y = 36
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid


func _show_bindings(action: String, title: String, label: Label, buttons: Array[Button]) -> void:
	var list := Settings.bindings(action)
	var clash := PackedStringArray()
	for slot in buttons.size():
		var b: Button = buttons[slot]
		b.text = Settings.binding_text(list[slot]) if slot < list.size() else "—"
		if slot < list.size():
			clash.append_array(Settings.conflicts(action, list[slot]))
	label.text = title + ("   (same key as: %s)" % ", ".join(clash) if not clash.is_empty() else "")
	label.add_theme_color_override("font_color", UiStyle.TEXT_WARN if not clash.is_empty() else Color.WHITE)


func _start_capture(action: String, title: String, slot: int, button: Button) -> void:
	_cancel_capture()
	_capture = {"action": action, "label": title, "slot": slot, "button": button}
	button.text = "press a key…"
	_set_hint()


func _cancel_capture() -> void:
	if _capture.is_empty():
		return
	_capture = {}
	_update()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _capture.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
		else:
			_bind(Settings.event_binding(event))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var b := Settings.event_binding(event)
		if b != 0:
			_bind(b)
			get_viewport().set_input_as_handled()


func _bind(b: int) -> void:
	if b == 0:
		return
	var c := _capture
	_capture = {}
	(c["button"] as Button).grab_focus()
	Settings.set_binding(c["action"], c["slot"], b)
