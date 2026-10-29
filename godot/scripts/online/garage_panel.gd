extends PanelContainer
## PTA Online's panels (scripts/modes/online_mode.gd), centred on the HUD:
## - a garage terminal's (E at the terminal): the player's vehicles that this garage takes, and the vehicles it lends
##   (the bus depot's buses, the fire station's truck); one click gets it out on a free bay (the server's word comes
##   back as a status line). Those it can't get out stay listed, greyed, with the reason (not allowed online, too big
##   for this garage, kept at the bus depot...);
## - the player's vehicle's (U): what and where it is, lock / unlock (locked: others ride along, never drive), send it
##   back to the garage.

const UiStyle = preload("res://scripts/ui_style.gd")

signal spawn(vehicle: int, model: String)   # garage: the vehicle picked (vehicle 0: one the garage lends)
signal lock(on: bool)                       # vehicle: lock or unlock it
signal send_back                            # vehicle: back to the garage

var kind := ""                              # "garage" or "vehicle" while shown
var garage_id := ""                         # the garage shown
var rows: VBoxContainer                     # one row per vehicle: [Button, note Label] (named after the vehicle id)
var _title: Label
var _sub: Label
var _status: Label
var _hint: Label
var _scroll: ScrollContainer
var _looks: Dictionary
var _lock: Button
var _back: Button
var _locked := true


func _ready() -> void:
	name = "OnlinePanel"
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(0.92, 12, 22))
	_looks = UiStyle.button_looks()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 480
	add_child(box)
	_title = UiStyle.label("", 26)
	box.add_child(_title)
	_sub = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_sub)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(460, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	_lock = UiStyle.button("", _looks, Vector2(300, 42), 18)
	_lock.pressed.connect(func() -> void: lock.emit(not _locked))
	box.add_child(_centred(_lock))
	_back = UiStyle.button("Send it back to the garage", _looks, Vector2(300, 40), 17)
	_back.pressed.connect(func() -> void: send_back.emit())
	box.add_child(_centred(_back))
	_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	box.add_child(_hint)
	UiStyle.centre(self)


static func _centred(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


## A garage terminal's panel while its list comes from the server.
func open_garage(id: String, title: String, sub: String, close_keys: String) -> void:
	kind = "garage"
	garage_id = id
	_title.text = title
	_sub.text = sub
	_clear_rows()
	_status.text = "Reading your garage…"
	_hint.text = "click: get it out on a free bay · %s / Esc close" % close_keys
	_lock.get_parent().visible = false
	_back.get_parent().visible = false
	_scroll.visible = true
	_show()


## The garage's list: [{"vehicle", "model", "label", "note"}] (a note says why it can't come out).
func show_entries(entries: Array, message: String) -> void:
	_clear_rows()
	for e: Dictionary in entries:
		var row := HBoxContainer.new()
		row.name = "Vehicle_%d_%s" % [int(e["vehicle"]), str(e["model"])]
		row.add_theme_constant_override("separation", 12)
		var b := UiStyle.button(str(e["label"]), _looks, Vector2(250, 40), 17)
		b.name = "Get"
		b.disabled = str(e["note"]) != ""
		b.pressed.connect(func() -> void: spawn.emit(int(e["vehicle"]), str(e["model"])))
		row.add_child(b)
		var note := UiStyle.label(str(e["note"]), 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.custom_minimum_size.x = 180
		row.add_child(note)
		rows.add_child(row)
	_scroll.custom_minimum_size.y = minf(entries.size() * 48.0, 360.0)
	_status.text = message
	var first := _first_enabled()
	if first:
		first.grab_focus()


## The player's vehicle's panel: `what` says which and where; `locked` its lock (null: no vehicle out).
func open_vehicle(what: String, sub: String, locked: Variant, close_keys: String) -> void:
	kind = "vehicle"
	garage_id = ""
	_title.text = what
	_sub.text = sub
	_clear_rows()
	_scroll.visible = false
	_status.text = ""
	_hint.text = "%s / Esc close" % close_keys
	_lock.get_parent().visible = locked != null
	_back.get_parent().visible = locked != null
	if locked != null:
		set_locked(locked)
		_lock.grab_focus()
	_show()


func set_locked(on: bool) -> void:
	_locked = on
	_lock.text = "Locked: only you drive it  ·  unlock" if on else "Unlocked: anyone may drive it  ·  lock"


func set_status(text: String) -> void:
	_status.text = text


func close() -> void:
	visible = false
	kind = ""
	garage_id = ""
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus:
		focus.release_focus()


func _show() -> void:
	visible = true


func _clear_rows() -> void:
	for c in rows.get_children():
		c.free()
	_scroll.custom_minimum_size.y = 0.0


func _first_enabled() -> Button:
	for row in rows.get_children():
		var b := row.get_node("Get") as Button
		if not b.disabled:
			return b
	return null
