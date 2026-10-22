extends CanvasLayer
## Welcome menu, over the campus flyover (game.gd shows it when the game starts). The player picks a nickname, a
## colour and a game mode (scripts/modes/modes.gd: Sandbox, Escape from Plateau; all kept in user://settings.cfg),
## then: Explore solo (Play solo), Host a game on LAN (in that mode), Join a game (a page with the games found on the
## LAN by scripts/lan_discovery.gd, their mode too, and an address + port field: a client plays the host's mode),
## Settings (scripts/settings_menu.gd), or Quit. game.gd does the rest and
## reports back with set_status. The bottom row shows the build and what the updater (scripts/updater.gd) is doing:
## downloading the latest release, then "Restart now".

const UiStyle = preload("res://scripts/ui_style.gd")
const LanDiscovery = preload("res://scripts/lan_discovery.gd")
const Updater = preload("res://scripts/updater.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const Modes = preload("res://scripts/modes/modes.gd")
const SETTINGS := "user://settings.cfg"
const COLORS: Array[Color] = [Color(1, 0.55, 0.2), Color(0.25, 0.55, 1.0), Color(0.3, 0.8, 0.35), Color(0.95, 0.3, 0.35),
		Color(0.7, 0.4, 0.95), Color(1.0, 0.85, 0.2), Color(0.2, 0.8, 0.8), Color(1.0, 0.5, 0.75)]

signal solo
signal host
signal mode_picked(id: String)              # the game mode chosen (game.gd previews its night behind the menu)
signal join(address: String, port: int)
signal quit

## Shown once by the next menu: why the last game ended ("The host closed the game.").
static var notice := ""

var nickname := ""
var color_index := 0
var mode_id := Modes.DEFAULT                # the game mode picked for playing solo or hosting
var default_port := 7777
var protocol := 0                           # Net.build_id(): games of another build are listed but cannot be joined
var discovery: LanDiscovery                 # set by game.gd before adding the menu

var _looks := UiStyle.button_looks()
var _main_page: VBoxContainer
var _join_page: VBoxContainer
var _name_edit: LineEdit
var _swatches: Array[Button] = []
var _status: Label
var _join_status: Label
var _found: VBoxContainer
var _address: LineEdit
var _port: LineEdit
var _join_button: Button
var _solo_button: Button
var _busy := false
var _updater: Updater
var _update_label: Label
var _update_button: Button
var _panel: PanelContainer
var _settings: SettingsMenu
var _mode_buttons := {}                     # mode id -> its toggle button
var _mode_about: Label


func _ready() -> void:
	layer = 5
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var profile := saved_profile()
	nickname = profile[0]
	color_index = profile[1]
	mode_id = profile[2]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(0.86, 14, 28))
	root.add_child(panel)
	var pages := VBoxContainer.new()
	panel.add_child(pages)
	_main_page = _build_main_page(cfg)
	pages.add_child(_main_page)
	_join_page = _build_join_page(cfg)
	_join_page.visible = false
	pages.add_child(_join_page)
	UiStyle.centre(panel)
	_panel = panel
	_settings = SettingsMenu.new()
	root.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_panel.visible = true
		_solo_button.grab_focus())
	if notice != "":
		set_status(notice, true)
		notice = ""
	_solo_button.grab_focus.call_deferred()


func _build_main_page(cfg: ConfigFile) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.add_child(UiStyle.label("Plateau Map", 46))
	box.add_child(UiStyle.label("Welcome! The Saclay plateau awaits, from Télécom Paris to ENSTA Paris.", 17, UiStyle.TEXT_DIM))
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_child(UiStyle.label("Nickname", 17, UiStyle.TEXT_DIM))
	_name_edit = UiStyle.line_edit(nickname, "Your nickname", 190.0)
	_name_edit.max_length = 20
	_name_edit.text_changed.connect(func(t: String) -> void:
		nickname = t.strip_edges()
		_save())
	who.add_child(_name_edit)
	for i in COLORS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(28, 28)
		sw.tooltip_text = "Your colour"
		sw.focus_mode = Control.FOCUS_NONE
		sw.pressed.connect(_pick_color.bind(i))
		who.add_child(sw)
		_swatches.append(sw)
	_pick_color(color_index)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_child(UiStyle.label("Game mode", 17, UiStyle.TEXT_DIM))
	var group := ButtonGroup.new()
	for id: String in Modes.ids():
		var mb := UiStyle.button(Modes.title(id), _looks, Vector2(200, 40), 17)
		mb.toggle_mode = true
		mb.button_group = group
		mb.focus_mode = Control.FOCUS_NONE
		mb.pressed.connect(_pick_mode.bind(id))
		modes.add_child(mb)
		_mode_buttons[id] = mb
	_mode_about = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	_mode_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_about.custom_minimum_size.x = 560
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_solo_button = UiStyle.button("Explore solo", _looks, Vector2(320, 48), 20)
	_solo_button.pressed.connect(func() -> void: if not _busy: solo.emit())
	buttons.add_child(_solo_button)
	var b := UiStyle.button("Host a game on LAN", _looks, Vector2(320, 48), 20)
	b.pressed.connect(func() -> void: if not _busy: host.emit())
	buttons.add_child(b)
	b = UiStyle.button("Join a game", _looks, Vector2(320, 48), 20)
	b.pressed.connect(_show_join_page.bind(true))
	buttons.add_child(b)
	b = UiStyle.button("Settings", _looks, Vector2(320, 44), 18)
	b.pressed.connect(func() -> void:
		if not _busy:
			_panel.visible = false
			_settings.open())
	buttons.add_child(b)
	b = UiStyle.button("Quit", _looks, Vector2(320, 40), 17)
	b.pressed.connect(func() -> void: quit.emit())
	buttons.add_child(b)
	var centre := CenterContainer.new()
	centre.add_child(buttons)
	box.add_child(who)
	box.add_child(modes)
	box.add_child(_mode_about)
	box.add_child(centre)
	_pick_mode(mode_id)
	_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 520
	box.add_child(_status)
	box.add_child(_build_update_row())
	return box


## Build name, update progress and the button the update state asks for (hidden in editor runs).
func _build_update_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_update_label = UiStyle.label("", 15, UiStyle.TEXT_DIM)
	row.add_child(_update_label)
	_update_button = UiStyle.button("", _looks, Vector2(0, 32), 15)
	_update_button.focus_mode = Control.FOCUS_NONE
	_update_button.pressed.connect(_on_update_pressed)
	row.add_child(_update_button)
	_updater = get_node_or_null("/root/AutoUpdater") as Updater
	row.visible = _updater != null and _updater.version != ""
	if row.visible:
		_updater.changed.connect(_show_update)
		_show_update()
	return row


func _show_update() -> void:
	var u := _updater
	var mine := Updater.pretty(u.version)
	var theirs := Updater.pretty(u.latest)
	_update_button.visible = u.state in [Updater.State.READY, Updater.State.MANUAL, Updater.State.FAILED]
	_update_label.add_theme_color_override("font_color",
			UiStyle.TEXT_WARN if u.state == Updater.State.FAILED else UiStyle.TEXT_DIM)
	match u.state:
		Updater.State.CHECKING:
			_update_label.text = mine + "  ·  looking for updates…"
		Updater.State.UP_TO_DATE:
			_update_label.text = mine + "  ·  up to date"
		Updater.State.DOWNLOADING:
			_update_label.text = "%s  ·  downloading %s… %d %%" % [mine, theirs, roundi(100.0 * u.progress())]
		Updater.State.INSTALLING:
			_update_label.text = "%s  ·  installing %s…" % [mine, theirs]
		Updater.State.READY:
			_update_label.text = "%s  ·  %s is downloaded (installed at the next start)" % [mine, theirs]
			_update_button.text = "Restart now"
		Updater.State.MANUAL:
			_update_label.text = "%s  ·  %s is out" % [mine, theirs]
			_update_button.text = "Download page"
		Updater.State.FAILED:
			_update_label.text = "%s  ·  update failed: %s" % [mine, u.error]
			_update_button.text = "Download page"
		_:
			_update_label.text = mine


func _on_update_pressed() -> void:
	if _updater.state == Updater.State.READY:
		_updater.restart_now()
	else:
		OS.shell_open(_updater.release_page if _updater.release_page != "" \
				else "https://github.com/%s/releases/latest" % Updater.REPO)


func _process(_delta: float) -> void:
	if _updater and _updater.state == Updater.State.DOWNLOADING:
		_show_update()


func _build_join_page(cfg: ConfigFile) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 560
	box.add_child(UiStyle.label("Join a game", 32))
	box.add_child(UiStyle.label("Games on your network", 17, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	_found = VBoxContainer.new()
	_found.add_theme_constant_override("separation", 6)
	_found.custom_minimum_size.y = 120
	box.add_child(_found)
	box.add_child(UiStyle.label("Or enter the host's address", 17, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_address = UiStyle.line_edit(cfg.get_value("join", "address", ""), "IP address or domain, e.g. 192.168.1.42", 300.0)
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _join_typed())
	row.add_child(_address)
	row.add_child(UiStyle.label(":", 20))
	_port = UiStyle.line_edit(str(cfg.get_value("join", "port", default_port)), "port", 90.0)
	_port.max_length = 5
	_port.text_submitted.connect(func(_t: String) -> void: _join_typed())
	row.add_child(_port)
	_join_button = UiStyle.button("Join", _looks, Vector2(100, 38))
	_join_button.pressed.connect(_join_typed)
	row.add_child(_join_button)
	box.add_child(row)
	_join_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_join_status)
	var back := UiStyle.button("Back", _looks, Vector2(140, 38))
	back.pressed.connect(_show_join_page.bind(false))
	var c := CenterContainer.new()
	c.add_child(back)
	box.add_child(c)
	return box


func _pick_color(i: int) -> void:
	color_index = i
	for k in _swatches.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLORS[k]
		sb.set_corner_radius_all(14)
		if k == i:
			sb.set_border_width_all(3)
			sb.border_color = Color.WHITE
		for state: String in ["normal", "hover", "pressed"]:
			_swatches[k].add_theme_stylebox_override(state, sb)
	_save()


## [nickname, colour index, game mode] from user://settings.cfg (the system user name, the first colour and the
## default mode at first).
static func saved_profile() -> Array:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var user := OS.get_environment("USER") if OS.has_environment("USER") else OS.get_environment("USERNAME")
	var mode := str(cfg.get_value("player", "mode", Modes.DEFAULT))
	return [str(cfg.get_value("player", "name", user.capitalize() if user != "" else "Player")),
			clampi(int(cfg.get_value("player", "color", 0)), 0, COLORS.size() - 1),
			mode if Modes.valid(mode) else Modes.DEFAULT]


## The game mode played solo or hosted: its button down, its line under the row, the solo button named after it.
func _pick_mode(id: String) -> void:
	mode_id = id if Modes.valid(id) else Modes.DEFAULT
	for other: String in _mode_buttons:
		(_mode_buttons[other] as Button).set_pressed_no_signal(other == mode_id)
	_mode_about.text = Modes.about(mode_id)
	_solo_button.text = Modes.solo_text(mode_id)
	_save()
	mode_picked.emit(mode_id)


func color() -> Color:
	return COLORS[color_index]


func player_name() -> String:
	return nickname if nickname != "" else "Player"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("player", "name", nickname)
	cfg.set_value("player", "color", color_index)
	cfg.set_value("player", "mode", mode_id)
	if _address:
		cfg.set_value("join", "address", _address.text.strip_edges())
		cfg.set_value("join", "port", int(_port.text) if _port.text.is_valid_int() else default_port)
	cfg.save(SETTINGS)


func _show_join_page(on: bool) -> void:
	if _busy:
		return
	_main_page.visible = not on
	_join_page.visible = on
	_join_status.text = ""
	if on:
		if not discovery.start_listening():
			_join_status.text = "Can't look for games on this computer (port %d is busy, maybe another copy of the game is " \
					% LanDiscovery.PORT + "on this page): enter the host's address."
		if not discovery.hosts_changed.is_connected(_list_hosts):
			discovery.hosts_changed.connect(_list_hosts)
		_list_hosts()
		(_address if _address.text == "" else _join_button).grab_focus()
	else:
		discovery.stop()
		_solo_button.grab_focus()


func _list_hosts() -> void:
	for c in _found.get_children():
		c.queue_free()
	if discovery.hosts.is_empty():
		_found.add_child(UiStyle.label("Looking for games… (the host must have picked \"Host a game on LAN\")", 16,
				UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
		return
	for id: String in discovery.hosts:
		var h: Dictionary = discovery.hosts[id]
		var text := "%s's game   ·   %s   ·   %s:%d   ·   %d/%d players" % [h["name"],
				Modes.title(str(h.get("mode", Modes.DEFAULT))), h["ip"], h["port"], h["players"], h["max"]]
		var b := UiStyle.button(text, _looks, Vector2(0, 40), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if h["version"] != protocol:
			b.text += "   (another build of the game)"
			b.disabled = true
		b.pressed.connect(_join_found.bind(h["ip"], h["port"]))
		_found.add_child(b)


func _join_found(address: String, port: int) -> void:
	if _busy:
		return
	_address.text = address
	_port.text = str(port)
	_save()
	join.emit(address, port)


func _join_typed() -> void:
	if _busy:
		return
	var address := _address.text.strip_edges()
	var port_text := _port.text.strip_edges()
	# "192.168.1.42:7777" typed in the address field
	if address.count(":") == 1 and address.get_slice(":", 1).is_valid_int():
		port_text = address.get_slice(":", 1)
		address = address.get_slice(":", 0)
		_address.text = address
		_port.text = port_text
	if address == "":
		set_status("Enter the host's IP address (shown at the top right of their screen) or the server's domain.", true)
		return
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
		set_status("The port is a number between 1 and 65535 (%d unless the host changed it)." % default_port, true)
		return
	_save()
	join.emit(address, int(port_text))


## Message under the buttons of the current page; `busy` greys the menu out while connecting.
func set_status(text: String, warn := false, busy := false) -> void:
	_busy = busy
	for l: Label in [_status, _join_status]:
		l.text = text
		l.add_theme_color_override("font_color", UiStyle.TEXT_WARN if warn else UiStyle.TEXT_DIM)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE \
			and _join_page.visible:
		_show_join_page(false)
		get_viewport().set_input_as_handled()
