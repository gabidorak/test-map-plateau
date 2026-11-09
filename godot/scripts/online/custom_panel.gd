extends PanelContainer
## Losplatos Custom's panel (scripts/online/custom_shop.gd): U with one's car stopped in its service bay. The car, its
## bodywork, "Repair" (its price, by the damage), its paints (a swatch each, the one it wears marked; a coat's price),
## "Leave".

const UiStyle = preload("res://scripts/ui_style.gd")
const Economy = preload("res://scripts/economy.gd")

signal fix
signal paint(colour: String)
signal closed

var _title: Label
var _sub: Label
var _fix: Button
var _coat: Label
var _swatches: GridContainer
var _status: Label
var _hint: Label
var _looks: Dictionary


func _ready() -> void:
	name = "CustomPanel"
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(0.92, 12, 22))
	_looks = UiStyle.button_looks()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 640
	add_child(box)
	_title = UiStyle.label("LOSPLATOS CUSTOM", 28, Color("#f2c230"))
	box.add_child(_title)
	_sub = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	box.add_child(_sub)
	_fix = UiStyle.button("Repair", _looks, Vector2(360, 46), 18)
	_fix.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fix.pressed.connect(func() -> void: fix.emit())
	box.add_child(_fix)
	_coat = UiStyle.label("", 16)
	box.add_child(_coat)
	_swatches = GridContainer.new()
	_swatches.columns = 4
	_swatches.add_theme_constant_override("h_separation", 8)
	_swatches.add_theme_constant_override("v_separation", 8)
	_swatches.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_swatches)
	var leave := UiStyle.button("Leave", _looks, Vector2(160, 42), 17)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func() -> void: closed.emit())
	box.add_child(leave)
	_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	box.add_child(_hint)
	UiStyle.centre(self)


## Shows the car: `car_name`, its `health_pct` bodywork, the repair's `fix_price` (0: nothing to repair), its
## `palette` ([[id, label, Color]]; [] it keeps its own colours), the `current` paint ("" its own), a coat's
## `coat_price`, `close_keys` the keys that close.
func open(car_name: String, health_pct: int, fix_price: int, palette: Array, current: String, coat_price: int,
		close_keys: String) -> void:
	_sub.text = "%s · bodywork %d %%" % [car_name, health_pct]
	_fix.disabled = fix_price <= 0
	_fix.text = "Repair the bodywork · %s" % Economy.money(fix_price) if fix_price > 0 else "Bodywork like new"
	for c: Node in _swatches.get_children():
		c.queue_free()
	_coat.visible = not palette.is_empty()
	_coat.text = "Paint · %s a coat" % Economy.money(coat_price)
	if not palette.is_empty():
		_swatches.add_child(_swatch("", "Its own colour", Color(0.32, 0.33, 0.36), current == ""))
		for p: Array in palette:
			_swatches.add_child(_swatch(str(p[0]), str(p[1]), p[2], current == str(p[0])))
	else:
		_coat.visible = true
		_coat.text = "This one keeps its own colours."
	_status.text = ""
	_hint.text = "%s or Esc to leave" % close_keys
	visible = true


func _swatch(id: String, text: String, colour: Color, worn: bool) -> Button:
	var b := Button.new()
	b.name = "Paint_" + (id if id != "" else "own")
	b.text = ("✓ " if worn else "") + text
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 14)
	var light := colour.get_luminance() > 0.55
	b.add_theme_color_override("font_color", Color.BLACK if light else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.BLACK if light else Color.WHITE)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = colour.lightened(0.12) if state == "hover" else colour
		sb.set_corner_radius_all(6)
		sb.border_color = Color("#f2c230") if worn or state == "hover" else Color(0, 0, 0, 0.5)
		sb.set_border_width_all(3 if worn else 1)
		b.add_theme_stylebox_override(state, sb)
	b.disabled = worn
	b.pressed.connect(func() -> void: paint.emit(id))
	return b


func set_status(text: String) -> void:
	_status.text = text


func close() -> void:
	visible = false
