extends PanelContainer
## PTA Online's panels (scripts/modes/online_mode.gd, scripts/online/shop.gd), centred on the HUD:
## - a garage terminal's (E at the terminal): the player's vehicles that this garage takes, and the vehicles it lends
##   (the bus depot's buses, the fire station's truck); one click gets it out on a free bay (the server's word comes
##   back as a status line). Those it can't get out stay listed, greyed, with the reason (not allowed online, too big
##   for this garage, kept at the bus depot, wrecked...). Beside each of the player's own: "Repair" (a wrecked one, its
##   price) and "Paint" (the palette view: one swatch per colour, the price of a coat). The bus depot and the fire
##   station also sell their work vehicles ("Buy" rows), and the depot lists the bus lines to go on duty on (the bus
##   job, scripts/online/bus_job.gd: "Duty" rows, and "Go off duty" while on duty);
## - Prestige Motors' catalogue (E by Jean-Claude or a podium terminal): the vehicles it sells by tier, their prices,
##   how many of each the player has; one click buys it;
## - the player's vehicle's (U): what and where it is, lock / unlock (locked: others ride along, never drive), send it
##   back to the garage, and off duty while on duty.

const UiStyle = preload("res://scripts/ui_style.gd")
const Paint = preload("res://scripts/paint.gd")
const Economy = preload("res://scripts/economy.gd")
const Car = preload("res://scripts/car.gd")

signal spawn(vehicle: int, model: String)   # garage: the vehicle picked (vehicle 0: one the garage lends)
signal buy(model: String)                   # garage (work vehicles) or catalogue: buy one
signal repair(vehicle: int)                 # garage: repair this wrecked vehicle
signal repaint(vehicle: int, colour: String)    # garage, palette view: paint it ("" its own colour)
signal lock(on: bool)                       # vehicle: lock or unlock it
signal send_back                            # vehicle: back to the garage
signal duty(line: String)                   # garage (the bus depot): on duty on this line ("": off duty); vehicle: off

var kind := ""                              # "garage", "catalogue" or "vehicle" while shown
var view := ""                              # garage: "list" or "paint"
var garage_id := ""                         # the garage shown
var rows: VBoxContainer                     # one row per vehicle: [Button, note Label, ...] (named after the vehicle)
var swatches: GridContainer                 # palette view: one button per colour (named after the colour id)
var entries: Array = []                     # garage: the list shown last
var _title: Label
var _sub: Label
var _status: Label
var _hint: Label
var _scroll: ScrollContainer
var _looks: Dictionary
var _lock: Button
var _back: Button
var _off: Button
var _to_list: Button
var _locked := true
var _close_keys := ""


func _ready() -> void:
	name = "OnlinePanel"
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(0.92, 12, 22))
	_looks = UiStyle.button_looks()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 600
	add_child(box)
	_title = UiStyle.label("", 26)
	box.add_child(_title)
	_sub = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_sub)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(580, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	swatches = GridContainer.new()
	swatches.columns = 5
	swatches.add_theme_constant_override("h_separation", 10)
	swatches.add_theme_constant_override("v_separation", 10)
	box.add_child(_centred(swatches))
	_to_list = UiStyle.button("Back to the list", _looks, Vector2(220, 38), 16)
	_to_list.pressed.connect(func() -> void: show_entries(entries, ""))
	box.add_child(_centred(_to_list))
	_lock = UiStyle.button("", _looks, Vector2(300, 42), 18)
	_lock.pressed.connect(func() -> void: lock.emit(not _locked))
	box.add_child(_centred(_lock))
	_back = UiStyle.button("Send it back to the garage", _looks, Vector2(300, 40), 17)
	_back.pressed.connect(func() -> void: send_back.emit())
	box.add_child(_centred(_back))
	_off = UiStyle.button("Go off duty", _looks, Vector2(300, 40), 17)
	_off.pressed.connect(func() -> void: duty.emit(""))
	box.add_child(_centred(_off))
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


## Shows only the parts of the panel `parts` names: "rows", "swatches", "to_list", "vehicle".
func _parts(parts: Array) -> void:
	_scroll.visible = "rows" in parts
	swatches.get_parent().visible = "swatches" in parts
	_to_list.get_parent().visible = "to_list" in parts
	_lock.get_parent().visible = "vehicle" in parts
	_back.get_parent().visible = "vehicle" in parts
	_off.get_parent().visible = "duty" in parts


## A garage terminal's panel while its list comes from the server.
func open_garage(id: String, title: String, sub: String, close_keys: String) -> void:
	kind = "garage"
	view = "list"
	garage_id = id
	entries = []
	_close_keys = close_keys
	_title.text = title
	_sub.text = sub
	_clear_rows()
	_status.text = "Reading your garage…"
	_hint.text = "click: get it out on a free bay · %s / Esc close" % close_keys
	_parts(["rows"])
	_show()


## The garage's list: [{"vehicle", "model", "label", "note"; the player's own also "colour", "repair" (€, 0: not
## wrecked), "repaint" (€ a coat, 0: can't be painted); a vehicle on sale "buy" (€)}]; a note says why it can't come
## out. `message` goes in the status line.
func show_entries(list: Array, message: String) -> void:
	entries = list
	view = "list"
	_title.text = _title.text.trim_prefix("Paint · ")
	_parts(["rows"])
	_clear_rows()
	var sections := list.any(func(e: Dictionary) -> bool: return e.has("duty") or int(e.get("buy", 0)) > 0)
	var section := ""
	for e: Dictionary in list:
		if sections:
			var now := "duty" if e.has("duty") else ("buy" if int(e.get("buy", 0)) > 0 else "out")
			if now != section:
				section = now
				_heading(now, list)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		if e.has("duty"):
			_duty_row(row, e)
			rows.add_child(row)
			continue
		var buying := int(e.get("buy", 0)) > 0
		row.name = "Buy_%s" % e["model"] if buying else "Vehicle_%d_%s" % [int(e["vehicle"]), str(e["model"])]
		var b := UiStyle.button("%s · %s" % [e["label"], Economy.money(int(e["buy"]))] if buying else str(e["label"]),
				_looks, Vector2(250, 40), 17)
		b.name = "Buy" if buying else "Get"
		b.disabled = str(e["note"]) != "" and not buying
		b.pressed.connect(func() -> void:
			if buying:
				buy.emit(str(e["model"]))
			else:
				spawn.emit(int(e["vehicle"]), str(e["model"])))
		row.add_child(b)
		var note := UiStyle.label(str(e["note"]), 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.custom_minimum_size.x = 140
		if str(e.get("colour", "")) != "" and str(e["note"]) == "":
			note.text = Paint.label(str(e["model"]), str(e["colour"]))
		row.add_child(note)
		if int(e.get("repair", 0)) > 0:
			var r := UiStyle.button("Repair · %s" % Economy.money(int(e["repair"])), _looks, Vector2(150, 40), 15)
			r.name = "Repair"
			r.pressed.connect(func() -> void:
				set_status("Repairing…")
				repair.emit(int(e["vehicle"])))
			row.add_child(r)
		if int(e.get("repaint", 0)) > 0:
			var p := UiStyle.button("Paint", _looks, Vector2(80, 40), 15)
			p.name = "Paint"
			p.pressed.connect(func() -> void: open_palette(e))
			row.add_child(p)
		rows.add_child(row)
	_scroll.custom_minimum_size.y = minf(rows.get_child_count() * 46.0, 420.0)
	_status.text = message
	_hint.text = "click: get it out on a free bay · %s / Esc close" % _close_keys
	var first := _first_enabled()
	if first:
		first.grab_focus()


## The heading of a part of a garage's list (`part`: "duty" the bus lines, "out" the vehicles to get out, "buy" those
## on sale), in the garages whose list has more than one part (the bus depot, the fire station).
func _heading(part: String, list: Array) -> void:
	var job := list.any(func(e: Dictionary) -> bool: return e.has("duty"))
	var fire := list.any(func(e: Dictionary) -> bool: return str(e.get("duty", "")) == "fire")
	var vehicle := "fire truck" if fire else "bus"
	var head: String = {"duty": "FIREFIGHTER JOB · go on duty: a fire truck comes with it" if fire
			else "BUS JOB · pick a line: you are on duty, and a bus comes with it",
			"out": "Or just take a %s out (no job, no pay)" % vehicle if job else "Take one out",
			"buy": "For sale (your own pays ×1.5 on the job)" if job else "For sale"}[part]
	var l := UiStyle.label(head, 17, Color(1.0, 0.86, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	l.name = "Heading_" + part
	rows.add_child(l)
	if part == "duty":
		var text := "Then follow the waypoint to the line, stop in each stop's bay, open the doors (%s) " % \
				Settings.key_text("doors") + "until the pay pops in. Any bus does any line."
		if fire:
			text = "Alarms come in while you are on duty (the waypoint, the map): drive there, aim at the flames and " + \
					"hold %s until they are out. Each fire pays, shared by who hosed it; a quick answer pays more." % \
					Settings.key_text("fire")
		var how := UiStyle.label(text, 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		how.name = "Heading_how"
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = 560
		rows.add_child(how)


## A bus line's row at the depot: {"duty": its ref ("" off duty), "label", "note", "on" (our duty now)}.
func _duty_row(row: HBoxContainer, e: Dictionary) -> void:
	var ref := str(e["duty"])
	row.name = "Duty_" + (ref if ref != "" else "off")
	var b := UiStyle.button(str(e["label"]), _looks, Vector2(330, 40), 15)
	b.name = "Duty"
	b.disabled = e.get("on", false)
	b.pressed.connect(func() -> void: duty.emit(ref))
	row.add_child(b)
	var note := UiStyle.label(str(e["note"]), 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)


## The palette view of garage entry `e` (one of the player's own vehicles).
func open_palette(e: Dictionary) -> void:
	view = "paint"
	var model := str(e["model"])
	var now := str(e.get("colour", ""))
	_title.text = "Paint · " + _title.text.trim_prefix("Paint · ")
	_parts(["swatches", "to_list"])
	for c in swatches.get_children():
		c.free()
	var options: Array = [["", "Its own colour", null]] + Paint.palette(model)
	for p: Array in options:
		var b := UiStyle.button("" if p[2] != null else "Own", _looks, Vector2(96, 60), 14)
		b.name = "Colour_" + (str(p[0]) if p[0] != "" else "own")
		b.tooltip_text = p[1]
		b.disabled = p[0] == now
		if p[2] != null:
			var chip := ColorRect.new()
			chip.color = p[2]
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
			b.add_child(chip)
		b.pressed.connect(func() -> void:
			set_status("Painting it %s…" % str(p[1]).to_lower())
			repaint.emit(int(e["vehicle"]), str(p[0])))
		swatches.add_child(b)
	_status.text = ""
	_sub.text = "Your %s, now %s. A coat: %s (hover a colour for its name)." % [Car.common_name(model),
			Paint.label(model, now).to_lower() if now != "" else "in its own colour", Economy.money(int(e["repaint"]))]
	_hint.text = "click a colour: paint it · %s / Esc close" % _close_keys
	for b: Button in swatches.get_children():
		if not b.disabled:
			b.grab_focus()
			break


## Prestige Motors' catalogue while its list comes from the server.
func open_catalogue(title: String, sub: String, close_keys: String) -> void:
	kind = "catalogue"
	view = ""
	garage_id = ""
	_close_keys = close_keys
	_title.text = title
	_sub.text = sub
	_clear_rows()
	_status.text = "Opening the catalogue…"
	_hint.text = "click: buy it · %s / Esc close" % close_keys
	_parts(["rows"])
	_show()


## The catalogue: [{"model", "label", "price", "tier", "owned"}] in order; `balance` the player's money now.
func show_catalogue(list: Array, balance: int, message: String) -> void:
	_clear_rows()
	var tier := ""
	var n := 0
	for e: Dictionary in list:
		if str(e["tier"]) != tier:
			tier = str(e["tier"])
			var head := UiStyle.label(tier, 18, Color(1.0, 0.86, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
			rows.add_child(head)
			n += 1
		var row := HBoxContainer.new()
		row.name = "Buy_%s" % e["model"]
		row.add_theme_constant_override("separation", 12)
		var b := UiStyle.button("%s · %s" % [e["label"], Economy.money(int(e["price"]))], _looks, Vector2(330, 40), 17)
		b.name = "Buy"
		b.pressed.connect(func() -> void:
			set_status("Buying the %s…" % str(e["label"]).to_lower())
			buy.emit(str(e["model"])))
		row.add_child(b)
		var owned := int(e["owned"])
		var note := UiStyle.label("You have %d" % owned if owned > 0 else ("" if int(e["price"]) <= balance
				else "%s short" % Economy.money(int(e["price"]) - balance)), 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(note)
		rows.add_child(row)
		n += 1
	_scroll.custom_minimum_size.y = minf(n * 46.0, 440.0)
	_status.text = message
	var first := _first_enabled()
	if first:
		first.grab_focus()


## The player's vehicle's panel: `what` says which and where; `locked` its lock (null: no vehicle out); `on_duty` the
## bus job's line ("" off duty).
func open_vehicle(what: String, sub: String, locked: Variant, close_keys: String, on_duty := "") -> void:
	kind = "vehicle"
	view = ""
	garage_id = ""
	_title.text = what
	_sub.text = sub
	_clear_rows()
	_status.text = ""
	_hint.text = "%s / Esc close" % close_keys
	_parts((["vehicle"] if locked != null else []) + (["duty"] if on_duty != "" else []))
	if on_duty != "":
		_sub.text += "  ·  " + on_duty
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
	view = ""
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
		for b in row.get_children():
			if b is Button and not (b as Button).disabled:
				return b
	return null
