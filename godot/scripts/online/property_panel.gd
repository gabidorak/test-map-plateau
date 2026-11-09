extends PanelContainer
## A property's panel (E at its front door, scripts/online/properties.gd), centred on the HUD: its name, what it is,
## its price, and "Buy" (with or without the garage option) for one the player doesn't own; "Go in" for one they do,
## "Add the garage" while it has none and a switch opening their flat to visitors or locking it; below, a "Visit"
## button for each other owner whose flat there is open now.

const UiStyle = preload("res://scripts/ui_style.gd")
const Economy = preload("res://scripts/economy.gd")

signal buy(id: String, garage: bool)
signal enter(id: String)
signal visit(id: String, owner: String)
signal door(id: String, open: bool)
signal closed

var property_id := ""                       # the property shown
var _title: Label
var _sub: Label
var _about: Label
var _price: Label
var _buy: Button
var _buy_garage: Button
var _enter: Button
var _door: Button
var _door_open := false
var _visits: VBoxContainer
var _looks: Dictionary
var _status: Label
var _hint: Label


func _ready() -> void:
	name = "PropertyPanel"
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(0.92, 12, 22))
	_looks = UiStyle.button_looks()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 760
	add_child(box)
	_title = UiStyle.label("", 26)
	box.add_child(_title)
	_sub = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	box.add_child(_sub)
	_about = UiStyle.label("", 16)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_about)
	_price = UiStyle.label("", 22, Color(0.75, 1.0, 0.7))
	box.add_child(_price)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buy = UiStyle.button("Buy", _looks, Vector2(230, 46), 18)
	_buy.pressed.connect(func() -> void: buy.emit(property_id, false))
	row.add_child(_buy)
	_buy_garage = UiStyle.button("Buy + garage", _looks, Vector2(280, 46), 18)
	_buy_garage.pressed.connect(func() -> void: buy.emit(property_id, true))
	row.add_child(_buy_garage)
	_enter = UiStyle.button("Go in", _looks, Vector2(200, 46), 19)
	_enter.pressed.connect(func() -> void: enter.emit(property_id))
	row.add_child(_enter)
	var close := UiStyle.button("Close", _looks, Vector2(140, 46), 17)
	close.pressed.connect(func() -> void: closed.emit())
	row.add_child(close)
	box.add_child(row)
	_door = UiStyle.button("", _looks, Vector2(420, 40), 16)
	_door.pressed.connect(func() -> void: door.emit(property_id, not _door_open))
	_door.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_door)
	_visits = VBoxContainer.new()
	_visits.add_theme_constant_override("separation", 6)
	box.add_child(_visits)
	_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	box.add_child(_hint)
	UiStyle.centre(self)


## Shows property `p` (properties.gd list entry): `owned` whether the player owns it, `garage` with its garage option,
## `close_keys` the keys that close, `visits` the other owners whose flat there is open, `door_open` whether the
## player's is.
func open(p: Dictionary, owned: bool, garage: bool, close_keys: String, visits := [], door_open := false) -> void:
	property_id = str(p["id"])
	var price := int(p["price"])
	var extra := int(p.get("garage_price", 0))
	_title.text = str(p["name"])
	_sub.text = "%s · %s" % [str(p["short"]), ("your home · garage" if garage else "your home") if owned else "for sale"]
	_about.text = str(p.get("about", ""))
	_price.text = ("You own it, with its garage" if garage else "You own it") if owned else \
			"%s · garage option +%s (a private lift down to your car)" % [Economy.money(price), Economy.money(extra)]
	_buy.visible = not owned
	_buy.text = "Buy · %s" % Economy.money(price)
	_buy_garage.visible = not garage
	_buy_garage.text = "Add the garage · %s" % Economy.money(extra) if owned else \
			"Buy + garage · %s" % Economy.money(price + extra)
	_enter.visible = owned
	_door_open = door_open
	_door.visible = owned
	_door.text = "Door open to visitors · lock it" if door_open else "Door locked · open it to visitors"
	for b: Node in _visits.get_children():
		b.queue_free()
	for owner: String in visits:
		var b := UiStyle.button("Visit %s's flat" % owner, _looks, Vector2(420, 40), 16)
		b.pressed.connect(func() -> void: visit.emit(property_id, owner))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_visits.add_child(b)
	_status.text = ""
	_hint.text = "%s or Esc to close" % close_keys
	visible = true


func set_status(text: String) -> void:
	_status.text = text


func status_text() -> String:
	return _status.text


func close() -> void:
	visible = false
	property_id = ""
