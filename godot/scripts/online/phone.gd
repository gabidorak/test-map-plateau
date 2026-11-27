extends Control
## PTA Online: the smartphone (the phone key, P). A home screen of apps; most are placeholders for now:
## - Jobs: the job garages (bus depot, fire station, tow trucks), each with a lift there. The lift takes STILL s of
##   standing (or sitting) still, so it is no escape: moving more than DRIFT m, or the police after us, calls it off.
## - Map: opens the world map. Bank: the wallet. Messages, Contacts, Settings: not done yet.
## online_mode.gd makes it (_build_hud), toggles it (handle_input), closes it on Esc (close_ui) and counts it in ui_open.

const STILL := 15.0                         # s to stay still before a lift to a job
const DRIFT := 1.0                          # m moved that calls the lift off
const JOBS := [["depot", "Bus driver", "the bus depot"], ["fire", "Firefighter", "the fire station"],
		["tow", "Tow truck driver", "Losplatos Custom's yard"]]
const APPS := [["jobs", "Jobs", Color("#2e9d57")], ["map", "Map", Color("#2f6fd6")], ["bank", "Bank", Color("#c9a043")],
		["messages", "Messages", Color("#3aa0e0")], ["contacts", "Contacts", Color("#7a4fc4")],
		["settings", "Settings", Color("#6b7280")]]

var mode: Node                              # online_mode.gd
var game: Node3D

var _phone: PanelContainer
var _title: Label
var _body: VBoxContainer
var _back: Button
var _status: Label                          # the lift's countdown, shown with the phone closed too
var _app := ""
var _mouse := Input.MOUSE_MODE_VISIBLE

var _going := {}                            # the lift under way: {"garage": id, "name", "t": s left, "from": Vector3,
											# "body": the node that must stay still}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_phone = PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	frame.border_color = Color(0.02, 0.02, 0.03)
	frame.set_border_width_all(10)
	frame.set_corner_radius_all(28)
	frame.set_content_margin_all(22)
	_phone.add_theme_stylebox_override("panel", frame)
	_phone.custom_minimum_size = Vector2(340, 600)
	_phone.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	_phone.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_phone.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_phone.visible = false
	add_child(_phone)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_phone.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_back = Button.new()
	_back.text = "‹"
	_back.flat = true
	_back.add_theme_font_size_override("font_size", 26)
	_back.pressed.connect(_show_app.bind(""))
	top.add_child(_back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	top.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(close_phone)
	top.add_child(close)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	col.add_child(_body)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 120)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.visible = false
	add_child(_status)


func is_open() -> bool:
	return _phone.visible


func toggle() -> void:
	if is_open():
		close_phone()
	else:
		open_phone()


func open_phone() -> void:
	if not is_open():
		_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_phone.visible = true
	_show_app("")
	game.update_controls()


func close_phone() -> void:
	if not is_open():
		return
	_phone.visible = false
	Input.mouse_mode = _mouse
	game.update_controls()


func _show_app(app: String) -> void:
	_app = app
	for c in _body.get_children():
		c.queue_free()
	_back.visible = app != ""
	match app:
		"":
			_title.text = "PTA Phone"
			_home()
		"jobs":
			_title.text = "Jobs"
			_jobs()
		"bank":
			_title.text = "Bank"
			_text("Balance: %s" % mode.Economy.money(int(game.economy.balance)), 24)
			_text("Transfers and history: coming soon.")
		_:
			for a: Array in APPS:
				if a[0] == app:
					_title.text = a[1]
			_text("Coming soon.")


func _home() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	for a: Array in APPS:
		var b := Button.new()
		b.text = a[1]
		b.custom_minimum_size = Vector2(88, 88)
		var box := StyleBoxFlat.new()
		box.bg_color = a[2]
		box.set_corner_radius_all(18)
		b.add_theme_stylebox_override("normal", box)
		var hover := box.duplicate() as StyleBoxFlat
		hover.bg_color = (a[2] as Color).lightened(0.15)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_open_app.bind(a[0]))
		grid.add_child(b)


func _open_app(app: String) -> void:
	if app == "map":
		close_phone()
		game.set_world_map_open(true)
		return
	_show_app(app)


func _jobs() -> void:
	_text("A lift to a job's garage: stay still %d s once asked (no lift with the police after you)." % int(STILL))
	var here: Vector3 = game.player.global_position
	for j: Array in JOBS:
		var g: Dictionary = mode.garages.nearest(here, [j[0]])
		if g.is_empty():
			continue
		var t: Vector3 = g["terminal"]
		var row := HBoxContainer.new()
		_body.add_child(row)
		var l := Label.new()
		l.text = "%s\n%s · %.1f km" % [j[1], j[2], Vector2(t.x - here.x, t.z - here.z).length() / 1000.0]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "Cancel" if _going.get("garage", "") == g["id"] else "Go"
		b.custom_minimum_size = Vector2(80, 0)
		b.pressed.connect(_ask_lift.bind(g["id"], j[2]))
		row.add_child(b)


func _text(s: String, size := 16) -> void:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	_body.add_child(l)


## The thing that must not move while the lift is waited for: our vehicle at the wheel, else us.
func _body_now() -> Node3D:
	return game.driving if game.driving else game.player


func _ask_lift(gid: String, where: String) -> void:
	if _going.get("garage", "") == gid:
		_cancel("Lift called off.")
		_show_app("jobs")
		return
	var why := _refusal()
	if why != "":
		game.toast(why)
		return
	var body := _body_now()
	_going = {"garage": gid, "name": where, "t": STILL, "from": body.global_position, "body": body}
	game.toast("Lift to %s in %d s: stay still." % [where, int(STILL)])
	_show_app("jobs")


## Why no lift now ("" one may go).
func _refusal() -> String:
	if mode.police and mode.police.level > 0:
		return "No lift with the police after you."
	if mode.bus_job.on_duty() or mode.fire_job.on_duty() or mode.tow_job.on_duty():
		return "Go off duty first."
	if game.riding or game.flying:
		return "No lift from here."
	return ""


func _cancel(why: String) -> void:
	_going = {}
	_status.visible = false
	if why != "":
		game.toast(why)


func _process(delta: float) -> void:
	if _going.is_empty():
		return
	var body: Node3D = _going["body"]
	if not is_instance_valid(body) or body != _body_now() \
			or body.global_position.distance_to(_going["from"]) > DRIFT:
		_cancel("You moved: lift called off.")
		if _app == "jobs":
			_show_app("jobs")
		return
	var why := _refusal()
	if why != "":
		_cancel(why)
		return
	_going["t"] -= delta
	_status.visible = true
	_status.text = "Lift to %s in %d s · stay still" % [_going["name"], ceili(_going["t"])]
	if _going["t"] > 0.0:
		return
	var g: Dictionary = mode.garages.get_garage(_going["garage"])
	var where: String = _going["name"]
	_cancel("")
	close_phone()
	if g.is_empty():
		return
	mode.to_garage(g["xy"], [g["kind"]])
	game.toast("At %s: %s at the terminal to go on duty." % [where, Settings.key_text("interact")])
