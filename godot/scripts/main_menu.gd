extends CanvasLayer
## Welcome menu, over the campus flyover (game.gd shows it when the game starts). The player picks a nickname, a
## colour and a game mode (scripts/modes/modes.gd: Sandbox, Escape from Plateau; all kept in user://settings.cfg),
## then one of three ways to play: Solo (Explore solo / Play solo), LAN: Host a game on LAN (in that mode) or Join a
## game (a page with the games found on the LAN by scripts/lan_discovery.gd, their mode too, and an address + port
## field: a client plays the host's mode), or PTA Online (the account page: log in, create an account, log out, change
## the username, with the rules of scripts/account_rules.gd checked while typing; then Play joins the official server,
## as the username). Settings (scripts/settings_menu.gd), or Quit. game.gd does the rest and
## reports back with set_status. The bottom row shows the build and what the updater (scripts/updater.gd) is doing:
## downloading the latest release, then "Restart now".

const UiStyle = preload("res://scripts/ui_style.gd")
const LanDiscovery = preload("res://scripts/lan_discovery.gd")
const Updater = preload("res://scripts/updater.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const Modes = preload("res://scripts/modes/modes.gd")
const Accounts = preload("res://scripts/accounts.gd")
const AccountRules = preload("res://scripts/account_rules.gd")
const Economy = preload("res://scripts/economy.gd")
const SETTINGS := "user://settings.cfg"
const COLORS: Array[Color] = [Color(1, 0.55, 0.2), Color(0.25, 0.55, 1.0), Color(0.3, 0.8, 0.35), Color(0.95, 0.3, 0.35),
		Color(0.7, 0.4, 0.95), Color(1.0, 0.85, 0.2), Color(0.2, 0.8, 0.8), Color(1.0, 0.5, 0.75)]

signal solo
signal host
signal mode_picked(id: String)              # the game mode chosen (game.gd previews its night behind the menu)
signal join(address: String, port: int)
signal online                               # PTA Online: join the official server with the login kept (accounts.gd)
signal quit

## Shown once by the next menu: why the last game ended ("The host closed the game.").
static var notice := ""
static var notice_page := ""                # "online": the next menu opens on the PTA Online page (with the notice)

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
var _accounts: Accounts                     # HTTPS calls of the PTA Online page
var _online_page: VBoxContainer
var _online_status: Label
var _signed_box: VBoxContainer              # logged in: who, Play, log out...
var _who: Label
var _play_button: Button
var _rename_row: HBoxContainer
var _rename_edit: LineEdit
var _rename_hint: Label
var _form_box: VBoxContainer                # logged out: log in / create an account
var _signup := false                        # the form creates an account
var _tab_login: Button
var _tab_signup: Button
var _user_edit: LineEdit
var _user_hint: Label
var _pass_edit: LineEdit
var _pass_hint: Label
var _confirm_edit: LineEdit
var _confirm_hint: Label
var _confirm_label: Label
var _no_email: Label
var _remember: CheckBox
var _submit: Button
var _online_busy := false                   # a call to the accounts service is under way


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
	_accounts = Accounts.new()
	add_child(_accounts)
	_online_page = _build_online_page()
	_online_page.visible = false
	pages.add_child(_online_page)
	UiStyle.centre(panel)
	_panel = panel
	_settings = SettingsMenu.new()
	root.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_panel.visible = true
		_solo_button.grab_focus())
	var page := notice_page
	notice_page = ""
	if page == "online":
		show_online_page.call_deferred(true)
	if notice != "":
		set_status(notice, true)
		notice = ""
	if page != "online":
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
	_solo_button = UiStyle.button("Explore solo", _looks, Vector2(420, 48), 20)
	_solo_button.pressed.connect(func() -> void: if not _busy: solo.emit())
	buttons.add_child(_solo_button)
	var lan := HBoxContainer.new()
	lan.add_theme_constant_override("separation", 10)
	lan.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("Host a game on LAN", _looks, Vector2(205, 48), 20)
	b.tooltip_text = "Host a game on your network, in the game mode picked above"
	b.pressed.connect(func() -> void: if not _busy: host.emit())
	lan.add_child(b)
	b = UiStyle.button("Join a game", _looks, Vector2(205, 48), 20)
	b.tooltip_text = "Join a game on your network, or a server by its address"
	b.pressed.connect(_show_join_page.bind(true))
	lan.add_child(b)
	buttons.add_child(lan)
	b = UiStyle.button("PTA Online", _looks, Vector2(420, 52), 21)
	b.tooltip_text = "The official server: jobs, money, your own garage"
	b.pressed.connect(show_online_page.bind(true))
	buttons.add_child(b)
	b = UiStyle.button("Settings", _looks, Vector2(420, 44), 18)
	b.pressed.connect(func() -> void:
		if not _busy:
			_panel.visible = false
			_settings.open())
	buttons.add_child(b)
	b = UiStyle.button("Quit", _looks, Vector2(420, 40), 17)
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


## Gives the keyboard back to the menu (game.gd hid it while a LAN game started, then the join or host failed).
func focus_default() -> void:
	if _online_page.visible:
		(_play_button if _signed_box.visible else _submit).grab_focus()
	elif _join_page.visible:
		(_address if _address.text == "" else _join_button).grab_focus()
	else:
		_solo_button.grab_focus()


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
	for l: Label in [_status, _join_status, _online_status]:
		l.text = text
		l.add_theme_color_override("font_color", UiStyle.TEXT_WARN if warn else UiStyle.TEXT_DIM)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE \
			and (_join_page.visible or _online_page.visible):
		if _join_page.visible:
			_show_join_page(false)
		else:
			show_online_page(false)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- PTA Online

## The PTA Online page: the login kept on this computer (checked with the accounts service when the page opens), Play
## and the account's buttons; or the form to log in or create an account.
func _build_online_page() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 560
	box.add_child(UiStyle.label("PTA Online", 36))
	var about := UiStyle.label("The official server, shared by everyone: earn money in jobs and buy your own vehicles. "
			+ "Your solo and LAN games don't change.", 16, UiStyle.TEXT_DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(about)

	_signed_box = VBoxContainer.new()
	_signed_box.add_theme_constant_override("separation", 10)
	_who = UiStyle.label("", 20)
	_signed_box.add_child(_who)
	_play_button = UiStyle.button("Play PTA Online", _looks, Vector2(320, 50), 21)
	_play_button.pressed.connect(func() -> void:
		if not _busy and not _online_busy:
			online.emit())
	var c := CenterContainer.new()
	c.add_child(_play_button)
	_signed_box.add_child(c)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("Change username", _looks, Vector2(0, 36), 15)
	b.pressed.connect(func() -> void:
		_rename_row.visible = not _rename_row.visible
		if _rename_row.visible:
			_rename_edit.grab_focus())
	row.add_child(b)
	b = UiStyle.button("Log out", _looks, Vector2(0, 36), 15)
	b.pressed.connect(_logout.bind(false))
	row.add_child(b)
	b = UiStyle.button("Log out everywhere", _looks, Vector2(0, 36), 15)
	b.tooltip_text = "Logs out every computer this account is logged in on"
	b.pressed.connect(_logout.bind(true))
	row.add_child(b)
	_signed_box.add_child(row)
	_rename_row = HBoxContainer.new()
	_rename_row.add_theme_constant_override("separation", 8)
	_rename_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rename_edit = UiStyle.line_edit("", "New username", 220.0)
	_rename_edit.max_length = 16
	_rename_edit.text_changed.connect(func(t: String) -> void:
		_hint(_rename_hint, AccountRules.username_problem(t) if t != "" else "", "Once every 30 days."))
	_rename_edit.text_submitted.connect(func(_t: String) -> void: _rename())
	_rename_row.add_child(_rename_edit)
	b = UiStyle.button("Rename", _looks, Vector2(110, 36), 15)
	b.pressed.connect(_rename)
	_rename_row.add_child(b)
	_rename_hint = UiStyle.label("Once every 30 days.", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_rename_row.add_child(_rename_hint)
	_rename_row.visible = false
	_signed_box.add_child(_rename_row)
	box.add_child(_signed_box)

	_form_box = VBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	_tab_login = UiStyle.button("Log in", _looks, Vector2(200, 38), 17)
	_tab_signup = UiStyle.button("Create an account", _looks, Vector2(200, 38), 17)
	for t: Button in [_tab_login, _tab_signup]:
		t.toggle_mode = true
		t.button_group = group
		t.focus_mode = Control.FOCUS_NONE
		tabs.add_child(t)
	_tab_login.pressed.connect(_set_signup.bind(false))
	_tab_signup.pressed.connect(_set_signup.bind(true))
	_form_box.add_child(tabs)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	_user_edit = UiStyle.line_edit(str(Accounts.saved()["username"]), "3 to 16 letters, digits, _ - .", 300.0)
	_user_edit.max_length = 16
	_user_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_pass_edit = UiStyle.line_edit("", "At least 8 characters", 300.0)
	_pass_edit.secret = true
	_pass_edit.max_length = 128
	_pass_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_confirm_edit = UiStyle.line_edit("", "The same password again", 300.0)
	_confirm_edit.secret = true
	_confirm_edit.max_length = 128
	_confirm_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	for e: Array in [["Username", _user_edit, _user_hint], ["Password", _pass_edit, _pass_hint],
			["Again", _confirm_edit, _confirm_hint]]:
		var l := UiStyle.label(e[0], 17, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		grid.add_child(l)
		_confirm_label = l
		grid.add_child(e[1])
		grid.add_child(Control.new())
		grid.add_child(e[2])
		(e[1] as LineEdit).text_changed.connect(func(_t: String) -> void: _check_form())
		(e[1] as LineEdit).text_submitted.connect(func(_t: String) -> void: _submit_form())
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_form_box.add_child(gc)
	_remember = CheckBox.new()
	_remember.text = "Remember me on this computer"
	_remember.button_pressed = bool(Accounts.saved()["remember"])
	_remember.focus_mode = Control.FOCUS_NONE
	_remember.add_theme_font_size_override("font_size", 16)
	var rc := CenterContainer.new()
	rc.add_child(_remember)
	_form_box.add_child(rc)
	_submit = UiStyle.button("Log in", _looks, Vector2(240, 44), 19)
	_submit.pressed.connect(_submit_form)
	var sc := CenterContainer.new()
	sc.add_child(_submit)
	_form_box.add_child(sc)
	_no_email = UiStyle.label("No email: keep your password safe. A forgotten one is reset by the server's admin.", 14,
			UiStyle.TEXT_DIM)
	_form_box.add_child(_no_email)
	box.add_child(_form_box)

	_online_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_online_status)
	var back := UiStyle.button("Back", _looks, Vector2(140, 38))
	back.pressed.connect(show_online_page.bind(false))
	var bc := CenterContainer.new()
	bc.add_child(back)
	box.add_child(bc)
	_set_signup(false)
	return box


func show_online_page(on: bool) -> void:
	if _busy:
		return
	_main_page.visible = not on
	_online_page.visible = on
	_online_status.text = ""
	if not on:
		_solo_button.grab_focus()
		return
	if Accounts.official_server().is_empty() or Accounts.accounts_url() == "":
		_show_signed(false)
		_form_box.visible = false
		_online_message("PTA Online isn't set up in this build of the game.", true)
		return
	if Accounts.token() == "":
		_show_signed(false)
		return
	_show_signed(true, Accounts.saved()["username"])
	_who.text = "Logged in as %s" % Accounts.saved()["username"]
	_play_button.grab_focus()
	_online_busy = true
	var r: Dictionary = await _accounts.me()
	_online_busy = false
	if not _online_page.visible:
		return
	if r["ok"]:
		_show_signed(true, str(r["data"]["username"]), int(r["data"]["balance"]))
	elif r["error"] in ["token", "banned"]:
		Accounts.forget()
		_show_signed(false)
		_online_message(r["message"], true)
	else:
		_online_message(r["message"], true)  # the service can't be reached: Play may still get a clearer answer


## The logged-in part (who, balance, Play...) or the form.
func _show_signed(on: bool, username := "", balance := -1) -> void:
	_signed_box.visible = on
	_form_box.visible = not on
	_rename_row.visible = false
	if on:
		_who.text = "Logged in as %s" % username + ("  ·  %s" % Economy.money(balance) if balance >= 0 else "")
		_play_button.grab_focus()
	else:
		_pass_edit.text = ""
		_confirm_edit.text = ""
		_check_form()
		(_pass_edit if _user_edit.text != "" else _user_edit).grab_focus()


func _set_signup(on: bool) -> void:
	_signup = on
	_tab_login.set_pressed_no_signal(not on)
	_tab_signup.set_pressed_no_signal(on)
	_submit.text = "Create the account" if on else "Log in"
	_confirm_edit.visible = on
	_confirm_hint.visible = on
	_confirm_label.visible = on
	_no_email.visible = on
	_online_status.text = ""
	_check_form()


## Signing up: the rules' verdict under each field as the player types; the button waits for a valid form.
func _check_form() -> bool:
	var user := _user_edit.text
	var pw := _pass_edit.text
	if not _signup:
		_hint(_user_hint, "", "")
		_hint(_pass_hint, "", "")
		_submit.disabled = user.strip_edges() == "" or pw == ""
		return not _submit.disabled
	var user_problem := AccountRules.username_problem(user) if user != "" else ""
	var pass_problem := AccountRules.password_problem(pw, user) if pw != "" else ""
	var confirm_problem := "Not the same password." if _confirm_edit.text != "" and _confirm_edit.text != pw else ""
	_hint(_user_hint, user_problem, "Shown to other players. Letters, digits, _ - . (3 to 16).")
	_hint(_pass_hint, pass_problem, "8 characters or more: a few words make a good one.")
	_hint(_confirm_hint, confirm_problem, "")
	_submit.disabled = user == "" or pw == "" or _confirm_edit.text != pw or user_problem != "" or pass_problem != ""
	return not _submit.disabled


func _hint(l: Label, problem: String, otherwise: String) -> void:
	l.text = problem if problem != "" else otherwise
	l.add_theme_color_override("font_color", UiStyle.TEXT_WARN if problem != "" else UiStyle.TEXT_DIM)


func _online_message(text: String, warn := false) -> void:
	_online_status.text = text
	_online_status.add_theme_color_override("font_color", UiStyle.TEXT_WARN if warn else UiStyle.TEXT_DIM)


func _submit_form() -> void:
	if _online_busy or _busy or not _check_form():
		return
	_online_busy = true
	_submit.disabled = true
	_online_message("Creating the account…" if _signup else "Logging in…")
	var user := _user_edit.text.strip_edges()
	var r: Dictionary
	if _signup:
		r = await _accounts.signup(user, _pass_edit.text)
	else:
		r = await _accounts.login(user, _pass_edit.text)
	_online_busy = false
	_check_form()
	if not r["ok"]:
		_online_message(r["message"], true)
		return
	Accounts.keep(str(r["data"]["token"]), str(r["data"]["username"]), _remember.button_pressed)
	_online_message("Welcome, %s! You start with %s." % [r["data"]["username"], Economy.money(int(r["data"]["balance"]))] \
			if _signup else "")
	_show_signed(true, str(r["data"]["username"]), int(r["data"]["balance"]))


func _logout(everywhere: bool) -> void:
	if _online_busy:
		return
	_online_busy = true
	var r: Dictionary = await _accounts.logout(everywhere)
	_online_busy = false
	_show_signed(false)
	_online_message("Logged out everywhere." if everywhere and r["ok"] else "Logged out." if r["ok"] \
			else "Logged out on this computer (%s)" % r["message"], not r["ok"])


func _rename() -> void:
	var new_name := _rename_edit.text.strip_edges()
	if _online_busy or AccountRules.username_problem(new_name) != "":
		return
	_online_busy = true
	var r: Dictionary = await _accounts.rename(new_name)
	_online_busy = false
	if not r["ok"]:
		_hint(_rename_hint, r["message"], "")
		return
	var saved := Accounts.saved()
	Accounts.keep(saved["token"], str(r["data"]["username"]), saved["remember"])
	_show_signed(true, str(r["data"]["username"]), int(r["data"]["balance"]))
	_online_message("You are now %s." % r["data"]["username"])
