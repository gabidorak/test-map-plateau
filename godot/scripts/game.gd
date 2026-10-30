extends Node3D
## Game controller on scenes/main.tscn: spawns the player, switches between the player and the
## fly camera (F1), owns the HUD and the debug picker (F). Click captures the mouse; Esc opens the in-game menu
## (scripts/pause_menu.gd: resume, back to the main menu, quit), which frees it.
## Launched as the main scene it first shows the welcome menu (scripts/main_menu.gd) over a slow flight around the
## campus: Explore solo, Host a game on LAN (the host's address shows at the top right), Join a game. Hosting or joining
## puts the loading overlay (scripts/loading_screen.gd) over the menu while the server, the world's vehicles and bots,
## or the host's snapshot, are prepared; the startup scene (scripts/loading_scene.gd) loads this whole scene behind the
## same screen, and leaving for the welcome menu shows it while the scene reloads. LAN games are scripts/net.gd's:
## the other players show as scripts/remote_player.gd, vehicles are
## simulated by whoever drives them, and a player can walk in a bus another one drives; holding Tab lists the players
## and their ping, Enter opens the chat (scripts/chat.gd, scripts/player_list.gd). Command line (after `--`): --solo,
## --host, --join=IP[:PORT], --name=NICK, --color=N skip the menu. --dedicated [--port=N] [--name=GAME] runs a server
## without a player (headless, server/ at the repository root): it quits once a newer release is out and nobody plays
## (or UPDATE_WAIT s on). Instanced by the tools, it starts solo at once as before.
## Debug cars (scripts/car.gd) are parked next to the spawn point; C parks another one next to the
## player, E gets into the nearest car and Space gets out. U opens the vehicle menu, which parks any model (Car.MODELS)
## next to the player. The bus is walkable: the player standing in it
## is carried along (also while it moves), E near its driver seat takes the wheel, and Space leaves the
## seat into the aisle (the bus rolls on, handbrake once slow); O (driver) opens and closes its doors.
## The mouse wheel zooms the camera, all the way in is first person (walking) or the cab view (driving the bus);
## first person and the cab view carry over when taking and leaving the driver seat. The articulated bus carries the
## player in whichever of its two sections they stand (Car.carrier_at).
## The horse (scripts/horse.gd, in the vehicle menu) is got on and off with E: Space jumps, over fences too.
## The lakes and ponds are water (scripts/water.gd): the player swims, vehicles float a moment then sink, the horse swims.
## The jet-ski (scripts/jet_ski.gd, in the vehicle menu) is parked on the nearest lake or pond (JET_SKI_REACH; on land
## beside the player when there is none), got on with E and off with Space, into the water.
## The biplane (scripts/plane.gd, in the vehicle menu) is got in and out of like a car, and flies. The armed one fires
## its machine guns with the left mouse button (scripts/plane_guns.gd; a ring on the screen shows where the rounds
## converge): a vehicle hit takes damage (net.gd hit_vehicle, car.gd damage) and smokes black once broken, a breakable
## prop hit falls over (breakables.gd shoot).
## The police car (scripts/police_car.gd) switches its two-tone siren and blue lights with B.
## The fire truck (scripts/fire_truck.gd) sprays its roof water cannon where the driver looks while the left mouse button
## is held (a dashed blue ring shows where the jet lands): the water pushes vehicles and puts out burning ones (net.gd
## water_vehicle, car.gd hose), shoves other players (water_player), and knocks light props over (breakables.gd soak).
## Its cab has a passenger seat: E from the truck's right side, or while another player drives it, sits the player
## there (`riding`: looking around with the truck's cameras, the cab view from the passenger's eye); E there takes the
## wheel if nobody has it, Space gets out on the right.
## The two-seat biplane's passenger seat is its gunner's (same E rule): the mouse aims its belly turret, which fires
## forward only (up to 45° off the nose) with the left mouse button; V or the mouse wheel goes to the turret view, and a
## ring shows where the barrel points. So is the GAZ Tiger's (scripts/armored_car.gd): the gunner stands in its roof
## hatch and the mouse turns the machine gun on the hatch's ring all the way round.
## Vehicles bend thin trees and knock over sign poles, bollards and the like (scripts/breakables.gd).
## Bot buses and bot cars (scripts/traffic.gd, scripts/bus_bot.gd) drive their lines and routes when playing solo,
## hosting, or on a dedicated server: the player can ride the buses (in through the open doors at a stop) but drive
## none of them. The host (or solo player) switches them and the RER B trains off and on in the in-game menu
## (remembered, Settings "traffic"; --no-bots on the command line), and can clear the map of every vehicle there.
## Instanced by the tools they stay off unless PLATEAU_BUSES=1. The traffic lights cycle on the game's shared clock (the same on every screen).
## The RER B trains (scripts/train_traffic.gd, scripts/train.gd) run both ways through Lozère likewise (PLATEAU_TRAINS=1
## for the tools): the player gets on at the station while the doors are open, walks through the cars of a unit and is
## carried like in a bus; riding one off the map puts them down by the line at that end.
## Graphics: "low" (no SSIL/SSAO/glow, FXAA instead of MSAA) keeps 60 fps on an integrated GPU; it is
## the default there, "high" elsewhere; "medium" keeps the SSAO, glow and shadows but drops the SSIL and MSAA (FXAA),
## a third less GPU time at 4K. PLATEAU_QUALITY=low|medium|high overrides, F2 cycles them, the settings page
## (scripts/settings_menu.gd, from either menu) sets it. Keys are the Settings actions (scripts/settings.gd): the
## letters above are their defaults, on physical key positions, and the help lines show the current ones.
## N switches night and day (scripts/night.gd: moonlight, a starry sky, lit windows and street lamps; also on the
## settings page); at night the bots drive with their headlights on and the player's switch on as they get in. L
## switches the headlights of the vehicle driven (the plane's landing lights), which the other players see too.
## Races (scripts/races.gd): a driver stopped in a glowing start circle (the campus lap in the big parking by the lake,
## the bus race at the stop ENSTA - Les Joncherettes) is offered to race with T (alone) or Y (with the other drivers in
## the circle); the leaderboards stand beside the circles, the host keeps the records.
## Showrooms (scripts/dealership.gd: the Institut d'Optique is now a luxury car dealership, world/interiors.json): the
## host (or solo player, or dedicated server) parks their drivable display cars at start and again after clearing the
## map; their salesman (scripts/salesman.gd) follows the player around. Instanced by the tools, the display cars stay
## off unless PLATEAU_SHOWROOM=1.
## Game modes (scripts/modes/modes.gd): the welcome menu picks the one hosted or played solo (--mode=ID on the command
## line, PLATEAU_MODE for the tools; clients play the host's). game.gd makes it as Main/Mode (scripts/modes/game_mode.gd):
## it says which of the features above stay on (allows), takes keys first and adds help lines. Sandbox
## (scripts/modes/sandbox_mode.gd) is all of the above; Escape from Plateau (scripts/escape/escape_mode.gd) is a co-op
## survival night: zombies, survivors to carry to a rescue helicopter, weapons.
## PTA Online (ONLINE_MODE.md): the welcome menu's account page (scripts/main_menu.gd, scripts/accounts.gd) logs in, then
## start_online joins the official server, whose address is in the build (--online on the command line, with the login
## kept from the menu). That server runs with --dedicated --official and checks every player's login (scripts/
## economy.gd, Main/Economy): their name is their username, and it sends away those without one, with a message.
## It plays only PTA Online (scripts/modes/online_mode.gd), a mode the welcome menu doesn't offer for solo or LAN games:
## vehicles belong to accounts and come out at garages (E at a terminal), one per player, locked to others (U); no
## vehicle menu, no C, no fly camera, no armed vehicles; the wallet shows top right. The maps mark Prestige Motors and the
## game mode's places (map_places: the garages).

signal world_staged                         # the loader has put the whole world in the tree (see `staged`)
signal set_up                               # _ready has done all but placing the player: the loader lets it run
signal toast_shown(text: String)            # a line at the top of the screen (toast; the tests read them)

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Picker = preload("res://scripts/picker.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Car = preload("res://scripts/car.gd")
const Biplane = preload("res://scripts/plane.gd")
const Horse = preload("res://scripts/horse.gd")
const JetSki = preload("res://scripts/jet_ski.gd")
const Water = preload("res://scripts/water.gd")
const PlaneGuns = preload("res://scripts/plane_guns.gd")
const FireTruck = preload("res://scripts/fire_truck.gd")
const ArmoredCar = preload("res://scripts/armored_car.gd")
const PoliceCar = preload("res://scripts/police_car.gd")
const WaterCannon = preload("res://scripts/water_cannon.gd")
const Breakables = preload("res://scripts/breakables.gd")
const Net = preload("res://scripts/net.gd")
const MainMenu = preload("res://scripts/main_menu.gd")
const PauseMenu = preload("res://scripts/pause_menu.gd")
const RemotePlayer = preload("res://scripts/remote_player.gd")
const UiStyle = preload("res://scripts/ui_style.gd")
const Chat = preload("res://scripts/chat.gd")
const PlayerList = preload("res://scripts/player_list.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Night = preload("res://scripts/night.gd")
const Races = preload("res://scripts/races.gd")
const Economy = preload("res://scripts/economy.gd")
const Accounts = preload("res://scripts/accounts.gd")
const Modes = preload("res://scripts/modes/modes.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const Loader = preload("res://scripts/loading_scene.gd")
const Pacer = preload("res://scripts/pacer.gd")
const Minimap = preload("res://scripts/minimap.gd")
const WorldMap = preload("res://scripts/world_map.gd")
const WaypointBeacon = preload("res://scripts/waypoint_beacon.gd")
const WATER_SHOVE := 0.7                    # m/s a full-power water packet shoves a player along the jet
const ENTER_RANGE := 3.0                    # metres from the car body
const KILL_MARGIN := 20.0                   # m under the lowest ground where a falling player is put back
const LOAD_MIN_SHOW := 0.7                  # s the loading overlay stays up, even when hosting starts at once
const LOAD_BUDGET_MS := 12.0                # ms of vehicle setting up per frame while the overlay is up (Pacer)
const JET_SKI_REACH := 200.0                # m: the jet-ski is parked on water this near the player...
const JET_SKI_ROOM := 4.0                   # ...with this much water round it...
const JET_SKI_LAKE := 300.0                 # ...in a body of water this big (m²): no fountain basins
const SEAT_RANGE := 1.6                     # metres from the driver seat, from inside a walkable vehicle
const UPDATE_POLL := 300.0                  # s between release checks (dedicated server)
const UPDATE_WAIT := 1800.0                 # s a dedicated server waits for its players to leave before updating

## Spawn point in pipeline coordinates (x east, y north): the street in front of the
## Télécom Paris main entrance, facing it (south).
@export var spawn_xy := Vector2(-34, 55.0)
@export var spawn_yaw_deg := 180.0
@export var debug_cars := true              # park a few cars next to the player at start (solo and hosting)
@export var bus_bots := true                # bot buses on their lines and bot cars (solo, hosting, dedicated server)
@export var train_bots := true              # the RER B trains (scripts/train_traffic.gd), likewise
@export var showroom_cars := true           # the showrooms' display cars (scripts/dealership.gd), likewise
## Welcome menu flight: circles this point (pipeline x, y) at MENU_ORBIT radius and height above it.
const MENU_ORBIT_CENTRE := Vector2(260.0, -120.0)
const MENU_ORBIT := Vector2(330.0, 140.0)
const MENU_ORBIT_SPEED := 0.02              # rad/s

var flying := false
var driving: Car                            # the car the player is in, or null
var riding: Car                             # the car whose passenger seat the player sits in, or null
var cars: Array[Car] = []
var _next_model := 0
var picker: Picker
var breakables: Breakables
var traffic: Traffic
var night: Night
var races: Races
var economy: Economy                        # Main/Economy: PTA Online logins (and money, later)
var online := false                         # client: playing PTA Online on the official server (start_online)
var hud: CanvasLayer
var _help: Label
var _dash: Label                            # speed, gear, indicators, doors while driving
var _gunsight: Control                      # armed plane: where its rounds converge
var _water_sight: Control                   # fire truck: where its water jet lands
var _menu: PanelContainer                   # vehicle menu (U)
var _menu_buttons: GridContainer            # one per model, named after it
var _menu_status: Label
var _menu_hint: Label
var _menu_mouse := Input.MOUSE_MODE_VISIBLE # mouse mode to restore when the menu closes
var low_quality := false
var quality := "high"                       # "low", "medium" or "high" (set_quality)
var _high := {}                             # the scene's own settings, restored by "high"
var mode := ""                              # "solo", "host", "client", "server" (dedicated); "" in the welcome menu
var mode_id := Modes.DEFAULT                # the game mode played (scripts/modes/modes.gd)
var game_mode: Node                         # Main/Mode (scripts/modes/game_mode.gd), once a game started
var net: Net
var nickname := "Player"
var color := MainMenu.COLORS[0]
var menu: MainMenu                          # welcome menu, while it is up
var pause: PauseMenu
var loading: LoadingScreen                  # full-screen overlay while a game starts
var staged := false                         # in the tree before its world (the loader): _ready waits for world_staged
var _loading_started := 0.0                 # Time.get_ticks_msec() / 1000.0 when the overlay went up
var _loading_menu_shown := false            # the overlay hid the welcome menu; show it again on failure
var _loading_hid_3d := false                # the overlay turned the 3D view off (scripts/loading_scene.gd _hide_3d)
var _returning_to_menu := false             # back_to_menu is under way (pause menu and the host's exit can coincide)
var _pause_mouse := Input.MOUSE_MODE_VISIBLE
var _args := {}                             # command line options after "--"
var _host_label: Label                      # top right while hosting: the address to join
var _host_label_t := 0.0
var _toast: Label                           # "X joined the game"...
var _toast_t := 0.0
var minimap: Minimap                        # top left (K), in the HUD
var world_map: WorldMap                     # full screen (M), in the HUD
var waypoint: Variant = null                # pipeline (x, y) put on the full-screen map, or null (set_waypoint)
var _beacon: WaypointBeacon                 # the waypoint's beam and marker
var _map_mouse := Input.MOUSE_MODE_VISIBLE  # mouse mode to restore when the full-screen map closes
var _stats: Label                           # F3: frame rate, CPU and GPU times, network timings (net.gd debug_text)
var _stats_t := 0.0
var _stats_frames := 0                      # frames since the last F3 update, and their summed times
var _stats_sum := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])   # frame, physics tick, (first physics frame), GPU
var chat: Chat                              # LAN games: Enter
var _player_list: PlayerList                # LAN games: while Tab is held
var _player_list_t := 1.0
var _orbit_angle := 0.0
var _orbit_ground := NAN                    # ground height under MENU_ORBIT_CENTRE
var _update_poll_t := 0.0                   # dedicated server: s since the last release check
var _outdated_t := 0.0                      # dedicated server: s since a newer release was found

@onready var player: CharacterBody3D = $Player
@onready var fly_camera: Camera3D = $Camera
@onready var world_root: Node3D = $Neighborhood


func _ready() -> void:
	if staged:
		await world_staged
	# the map's valleys (Lozère, Massy) lie below the player's default fall-out depth: jumping there put it back
	var ground_min: Variant = world_root.get_meta("world", {}).get("ground_min")
	if ground_min != null:
		player.kill_depth = minf(player.kill_depth, float(ground_min) - KILL_MARGIN)
	picker = Picker.new()
	picker.world_root = world_root
	add_child(picker)
	breakables = Breakables.new()
	breakables.name = "Breakables"
	breakables.world_root = world_root
	add_child(breakables)
	net = Net.new()
	net.name = "Net"
	net.game = self
	add_child(net)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	traffic.game = self
	add_child(traffic)
	if staged:
		await get_tree().process_frame      # (the loader's screen moves on: the trains have read the whole line)
	net.message.connect(_show_toast)
	net.message.connect(func(text: String) -> void: chat.add("", Color.WHITE, text))
	net.chat.connect(_on_chat)
	net.joined.connect(_on_joined)
	net.failed.connect(_on_join_failed)
	net.ended.connect(back_to_menu)
	breakables.broke.connect(net.broke)
	_build_hud()
	races = Races.new()
	races.name = "Races"
	races.game = self
	add_child(races)
	economy = Economy.new()
	economy.name = "Economy"
	economy.game = self
	add_child(economy)
	economy.account_changed.connect(func() -> void:
		_show_toast("Logged in as %s  ·  %s" % [economy.username, Economy.money(economy.balance)]))
	economy.kicked.connect(func(message: String) -> void:
		MainMenu.notice_page = "online"
		back_to_menu(message))
	net.registered.connect(races.send_boards)
	net.registered.connect(func(id: int) -> void:
		if game_mode:
			game_mode.player_registered(id))
	pause = PauseMenu.new()
	add_child(pause)
	pause.resume.connect(set_pause_open.bind(false))
	pause.leave.connect(back_to_menu.bind(""))
	pause.quit.connect(get_tree().quit)
	pause.traffic_toggled.connect(set_bot_traffic)
	pause.clear_vehicles.connect(clear_vehicles)
	var env: Environment = $WorldEnvironment.environment
	_high = {"ssil": env.ssil_enabled, "ssao": env.ssao_enabled, "glow": env.glow_enabled,
			"msaa": get_viewport().msaa_3d, "aa": get_viewport().screen_space_aa}
	set_quality(Settings.quality())
	night = Night.new()
	night.name = "Night"
	night.game = self
	night.env = $WorldEnvironment.environment
	night.sun = $Sun
	night.world_root = world_root
	add_child(night)
	night.set_night(Settings.night())
	Settings.changed.connect(_on_settings_changed)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var profile := MainMenu.saved_profile()
	mode_id = _args.get("mode", OS.get_environment("PLATEAU_MODE") if get_tree().current_scene != self else profile[2])
	if not Modes.valid(mode_id):
		mode_id = Modes.DEFAULT
	# PTA Online is the official server's mode, and its only one (the tools may play it solo: PLATEAU_MODE)
	if _args.has("official"):
		mode_id = Modes.ONLINE
	elif mode_id == Modes.ONLINE and get_tree().current_scene == self:
		mode_id = Modes.DEFAULT
	nickname = _args.get("name", profile[0])
	color = MainMenu.COLORS[clampi(int(_args.get("color", profile[1])), 0, MainMenu.COLORS.size() - 1)]
	# the tools instance the scene themselves: no menu for them, no bot buses unless asked
	if get_tree().current_scene != self:
		bus_bots = OS.get_environment("PLATEAU_BUSES") == "1"
		train_bots = OS.get_environment("PLATEAU_TRAINS") == "1"
		showroom_cars = OS.get_environment("PLATEAU_SHOWROOM") == "1"
	else:
		bus_bots = Settings.values["traffic"] and not _args.has("no-bots")
		train_bots = bus_bots               # the host's bot traffic switch takes the trains too (set_bot_traffic)
	for s in get_tree().get_nodes_in_group("showroom"):
		s.game = self
	var welcome := get_tree().current_scene == self and not (_args.has("solo") or _args.has("host") or _args.has("join") \
			or _args.has("dedicated") or _args.has("online"))
	fly_camera.active = false
	if welcome:
		_open_main_menu()
	else:
		player.camera.current = true
	set_up.emit()
	await get_tree().physics_frame
	spawn_at(spawn_xy, deg_to_rad(spawn_yaw_deg))
	if welcome:
		return
	if _args.has("dedicated"):
		start_dedicated()
	elif _args.has("host"):
		start_host()
	elif _args.has("join"):
		var where: String = _args["join"]
		start_join(where.get_slice(":", 0), int(where.get_slice(":", 1)) if where.contains(":") else Net.PORT)
	elif _args.has("online"):
		start_online()
	else:
		start_solo()


## The welcome menu over the campus flight; the player waits, hidden, at the spawn point.
func _open_main_menu() -> void:
	mode = ""
	hud.visible = false
	_set_player_enabled(false)
	fly_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MainMenu.new()
	menu.discovery = net.discovery
	menu.protocol = Net.build_id()
	menu.default_port = Net.PORT
	add_child(menu)
	menu.solo.connect(func() -> void: _take_profile(); start_solo())
	menu.host.connect(func() -> void: _take_profile(); start_host())
	menu.join.connect(func(address: String, port: int) -> void: _take_profile(); start_join(address, port))
	menu.online.connect(func() -> void: _take_profile(); start_online())
	menu.quit.connect(get_tree().quit)
	menu.mode_picked.connect(_preview_mode)
	_preview_mode(menu.mode_id)


## Welcome menu: the flight behind it under the night of the game mode picked (Escape from Plateau's dread).
func _preview_mode(id: String) -> void:
	night.set_dread(id == "escape")
	if id != "escape":
		night.set_night(Settings.night())


func _take_profile() -> void:
	nickname = menu.player_name()
	color = menu.color()
	mode_id = menu.mode_id


## Whether a loading overlay makes sense here: the game runs as the current scene (the menu or a command line start).
## The tools instantiate the scene themselves to test the game; they should not wait for a screen.
func _loading_wanted() -> bool:
	return get_tree().current_scene == self


## Fades the full-screen loading overlay (scripts/loading_screen.gd) in over the menu, which takes no click (the
## overlay stops the mouse) nor key (the focus is taken from it) meanwhile, and is hidden once the overlay is opaque,
## when this returns. `fraction` is the bar's first figure (0..1), `up_to` where it may creep to until the next one.
func _show_loading(status: String, fraction := 0.0, up_to := -1.0) -> void:
	if loading:
		_update_loading(status, fraction, up_to)
		return
	var layer := CanvasLayer.new()
	layer.name = "Loading"
	layer.layer = 50
	add_child(layer)
	loading = LoadingScreen.new()
	layer.add_child(loading)
	_loading_started = Time.get_ticks_msec() / 1000.0
	_update_loading(status, fraction, up_to)
	# A menu button keeping the GUI focus: Enter or Space would press it again while the game starts.
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(LoadingScreen.FADE_TIME).timeout
	if loading and menu and menu.visible:
		menu.visible = false
		_loading_menu_shown = true
	if loading and not get_viewport().disable_3d:
		get_viewport().disable_3d = true    # nothing drawn under it: shorter frames, the work done sooner
		_loading_hid_3d = true


## What the overlay says now; `fraction` < 0 keeps the bar where it is.
func _update_loading(status: String, fraction := -1.0, up_to := -1.0) -> void:
	if loading == null:
		return
	loading.set_status(status)
	if fraction >= 0.0:
		loading.set_progress(fraction, up_to)


## The overlay over the menu while this peer sets its vehicles up, and the Pacer spreading that over frames (the
## overlay keeps moving); null when the scene is not the game played (the tools): all at once, as before.
func _start_pacer(status: String) -> Pacer:
	if not _loading_wanted():
		return null
	await _show_loading(status, 0.05, 0.12)
	return Pacer.new(get_tree(), LOAD_BUDGET_MS)


## net.gd, joining: a Pacer for the host's vehicles while the overlay says `status`, or null (all at once) without it.
func loading_pacer(status: String, fraction: float, up_to: float) -> Pacer:
	if loading == null:
		return null
	_update_loading(status, fraction, up_to)
	return Pacer.new(get_tree(), LOAD_BUDGET_MS)


## Keeps the overlay up for at least LOAD_MIN_SHOW (no flash) and a few frames of the game drawn behind it (the
## first ones compile the shaders of what just came in), then fades it out and frees it.
func _finish_loading() -> void:
	if loading == null:
		return
	if _loading_hid_3d:
		get_viewport().disable_3d = false   # the shaders of what came in compile under the overlay
		_loading_hid_3d = false
	for i in 3:
		await get_tree().process_frame
	var left := LOAD_MIN_SHOW - (Time.get_ticks_msec() / 1000.0 - _loading_started)
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	if loading == null:
		return
	var gone := loading
	loading = null
	var layer := gone.get_parent() as CanvasLayer
	gone.close()
	if layer:
		gone.tree_exited.connect(layer.queue_free)   # the screen frees itself after its fade; its layer goes too


## After a failed host or join: the menu comes back under the fading overlay.
func _reveal_menu() -> void:
	if menu and _loading_menu_shown:
		menu.visible = true
		_loading_menu_shown = false


## Makes `id` (scripts/modes/modes.gd) the game mode played: Main/Mode, in place of the one before. Clients get the
## host's from net.gd's welcome.
func set_game_mode(id: String) -> void:
	if game_mode:
		remove_child(game_mode)             # its name is free for the new one at once
		game_mode.queue_free()
	night.set_dread(false)                  # the player's own night (the welcome menu may have previewed another)
	night.set_night(Settings.night())
	mode_id = id if Modes.valid(id) else Modes.DEFAULT
	game_mode = Modes.make(mode_id)
	game_mode.game = self
	add_child(game_mode)
	races.set_enabled(allows("races"))
	for s in get_tree().get_nodes_in_group("showroom"):
		if s.salesman:
			s.salesman.visible = allows("showrooms")
			s.salesman.process_mode = Node.PROCESS_MODE_INHERIT if allows("showrooms") else Node.PROCESS_MODE_DISABLED
	_place_minimap()
	_update_help()


## Whether the game mode keeps the game's feature `feature` (scripts/modes/game_mode.gd allows).
func allows(feature: String) -> bool:
	return game_mode == null or game_mode.allows(feature)


## Plays alone. The loading overlay covers the menu while the world's vehicles, bots and trains are put in, a few
## per frame (it took seconds in one go, with the window frozen on the menu).
func start_solo() -> void:
	var pacer: Pacer = await _start_pacer("Getting the plateau ready…")
	mode = "solo"
	set_game_mode(mode_id)
	if allows("races"):
		races.start_hosting()
	_begin()
	await _start_world(pacer)
	game_mode.begin()
	if pacer:
		_update_loading("Ready", 1.0)
		await _finish_loading()


## Solo, hosting, dedicated server: the vehicles and trains this peer starts for everyone, as the game mode allows;
## with `pacer`, spread over frames under the loading overlay.
func _start_world(pacer: Pacer = null) -> void:
	if debug_cars and allows("debug_cars"):
		_update_loading("Parking a few cars next to you…", 0.08, 0.15)
		for i in 4:
			spawn_car_near_player()
			if pacer and pacer.due():
				await pacer.wait()
	_update_loading("Polishing the showroom cars…", 0.15, 0.3)
	await _stock_showrooms(pacer)
	if bus_bots and allows("bot_traffic"):
		_update_loading("Sending the buses and cars out…", 0.3, 0.8)
		await traffic.start_bots(pacer)
	if train_bots and allows("trains"):
		_update_loading("Running the RER B…", 0.8, 0.97)
	await _start_trains(pacer)


func _start_trains(pacer: Pacer = null) -> void:
	if train_bots and allows("trains"):
		await traffic.trains.start(pacer)


## Starts a LAN game hosted here: the server first, so the cars parked at start get their network ids. The loading
## overlay covers the menu while the server starts and the world's vehicles, bots and trains are put in (as solo).
func start_host() -> void:
	var pacer: Pacer = await _start_pacer("Starting the game on your network…")
	var err := net.host(nickname, color, int(_args.get("port", Net.PORT)))
	if err != "":
		_on_join_failed(err)
		return
	mode = "host"
	set_game_mode(mode_id)
	if allows("races"):
		races.start_hosting()
	_begin()
	await _start_world(pacer)
	game_mode.begin()
	if pacer:
		_update_loading("Ready", 1.0)
		await _finish_loading()


## A server without a player of its own (headless on a VPS): the player stays hidden at the spawn point, next to the
## cars parked at start.
func start_dedicated() -> void:
	Engine.max_fps = 60                     # nothing to draw: do not spin between physics ticks
	net.message.connect(func(text: String) -> void: print(text))
	net.chat.connect(func(id: int, text: String) -> void: print("%s: %s" % [net.player_name(id), text]))
	var err := economy.make_official() if _args.has("official") else ""
	if _args.has("max-players"):
		net.max_players = clampi(int(_args["max-players"]), 1, 4095)   # (ENet's limit)
	if err == "":
		err = net.host(_args.get("name", "Plateau server"), color, int(_args.get("port", Net.PORT)), true)
	if err != "":
		printerr(err)
		get_tree().quit(1)
		return
	mode = "server"
	set_game_mode(mode_id)
	if allows("races"):
		races.start_hosting()
	hud.visible = false
	_set_player_enabled(false)
	print("Dedicated server on UDP port %d, %s%s (%s)" % [net.port, Modes.title(mode_id),
			", official PTA Online server (logins checked at %s)" % Accounts.accounts_url() if economy.official else "",
			AutoUpdater.version if AutoUpdater.version != "" else "unversioned build: no update checks"])
	_update_poll_t = UPDATE_POLL
	_start_world()
	game_mode.begin()
	if _args.has("stats"):
		var stats: Node = preload("res://scripts/server_stats.gd").new()
		stats.name = "Stats"
		stats.game = self
		add_child(stats)


## Dedicated server: quits when a newer build is out, once nobody plays or after UPDATE_WAIT; its container restarts it
## on the new build.
func _watch_updates(delta: float) -> void:
	_update_poll_t += delta
	if _update_poll_t >= UPDATE_POLL:
		_update_poll_t = 0.0
		AutoUpdater.check_tag()
	if not AutoUpdater.outdated():
		return
	_outdated_t += delta
	if net.players.is_empty() or _outdated_t >= UPDATE_WAIT:
		print("Quitting for %s (%d players)" % [AutoUpdater.latest, net.players.size()])
		set_process(false)
		get_tree().quit()


## Connects to a LAN game; _on_joined starts playing once the host has sent its players and vehicles. The loading
## overlay stays up from the click until the host's world is here, covering the wait and the snapshot it sends.
func start_join(address: String, port: int) -> void:
	if _loading_wanted():
		await _show_loading("Connecting to %s:%d…" % [address, port], 0.1, 0.4)
	var err := net.join(address, port, nickname, color)
	if err != "":
		_on_join_failed(err)
		return
	_update_loading("Waiting for the host to send the world…", 0.4, 0.75)
	if menu:
		menu.set_status("Connecting to %s:%d…" % [address, port], false, true)


## PTA Online: joins the official server (its address is in the build, scripts/accounts.gd) with the login the account
## page keeps; the name played under is the username (the server confirms it, scripts/economy.gd).
func start_online() -> void:
	var where := Accounts.official_server()
	if where.is_empty() or Accounts.token() == "":
		_on_join_failed("PTA Online isn't set up in this build." if where.is_empty() else "Log in to PTA Online first.")
		return
	online = true
	nickname = Accounts.saved()["username"]
	start_join(where[0], where[1])


## What a failed PTA Online join means for the player (net.gd fail_kind).
func _online_failure(reason: String) -> String:
	match net.fail_kind:
		"timeout", "unreachable":
			return "The PTA Online server isn't answering: it may be down, or restarting for an update. Try again in " \
					+ "a few minutes."
		"build":
			return "The PTA Online server runs another build of the game: restart the game to update (if you just " \
					+ "did, the server is updating too: try again in a few minutes)."
		"closed":
			return "The PTA Online server closed the connection."
	return reason


func _on_joined() -> void:
	net.discovery.stop()
	mode = "client"
	_update_loading("Joining the game…", 0.95, 0.99)
	_begin()
	# a step aside per player, so newcomers do not all land in the same spot
	spawn_at(spawn_xy + Vector2(1.2 * (net.me() % 5 - 2), 0.0), deg_to_rad(spawn_yaw_deg))
	_show_toast("Joined PTA Online" if online else "Joined %s's game" % net.player_name(1) if net.players.has(1) \
			else "Joined the server")
	if game_mode == null:                   # (a host of an older build would have been refused)
		set_game_mode(Modes.DEFAULT)
	game_mode.begin()
	if loading:
		_update_loading("Ready", 1.0)
		_finish_loading()


func _on_join_failed(reason: String) -> void:
	if online:
		reason = _online_failure(reason)
		online = false
		if menu == null:
			MainMenu.notice_page = "online"     # the next menu opens on the account page
	var had_loading := loading != null
	if menu:
		_reveal_menu()
		menu.set_status(reason, true)
		if had_loading:
			await _finish_loading()
		menu.focus_default()
	else:
		if had_loading:
			await _finish_loading()
		back_to_menu(reason)


## Leaves the game (closing it for everyone when hosting) and starts the scene again on the welcome menu, showing
## `reason` there. The loader (scripts/loading_scene.gd) does it behind its screen, a slice per frame: this scene
## freed, a new one put in the tree (a plain reload froze the window for seconds). The reason waits in
## MainMenu.notice, which outlives the scene.
func back_to_menu(reason := "") -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	MainMenu.notice = reason
	net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _loading_wanted():
		get_tree().reload_current_scene()  # instanced by a tool: no screen, as before
		return
	var loader := Loader.new()
	loader.old_scene = self
	get_tree().root.add_child(loader)


## From the welcome menu into the game.
func _begin() -> void:
	if menu:
		menu.queue_free()
		menu = null
	hud.visible = true
	RemotePlayer.set_color(player.get_node("Body"), color)
	_set_player_enabled(true)
	player.camera.make_current()
	_host_label.visible = mode == "host"
	_host_label_t = 1.0
	_update_help()


## The player in the world (shown, moving, colliding) or out of it (a game mode's dead player, scripts/modes/).
func set_player_enabled(on: bool) -> void:
	_set_player_enabled(on)


func _set_player_enabled(on: bool) -> void:
	player.visible = on
	player.active = on
	player.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	player.get_node("CollisionShape3D").set_deferred("disabled", not on)


func _physics_process(_delta: float) -> void:
	if driving or flying or riding:
		return
	# a car, or the rear section of an articulated one (car_trailer.gd)
	var c: Node3D = player.carrier if is_instance_valid(player.carrier) else null
	# where the player is in it now: it may have moved since the player last followed it (a remote vehicle net.gd
	# posed this tick); against that the player would seem to slip out of its rear at speed
	var p: Vector3 = player.followed_position()
	# leave with a small margin so the doorway does not flicker
	if c and not c.carries(p, 0.1):
		c = null
	if c == null:
		for car in cars:
			c = car.carrier_at(p)
			if c:
				break
	if c == null:
		c = traffic.trains.carrier_at(p)    # an RER B car (scripts/train.gd)
	player.set_carrier(c)


func _process(delta: float) -> void:
	if mode == "":
		_fly_around(delta)
	elif mode == "server":
		_watch_updates(delta)
		return
	if mode == "host":
		_host_label_t += delta
		if _host_label_t >= 1.0:              # players come and go, the network may change
			_host_label_t = 0.0
			_host_label.text = net.lan_label()
	if _stats.visible:
		_sample_stats(delta)
	_player_list.visible = net.active and Input.is_physical_key_pressed(KEY_TAB) and not pause.visible
	if _player_list.visible:
		_player_list_t += delta
		if _player_list_t >= 0.5:
			_player_list_t = 0.0
			_update_player_list()
	else:
		_player_list_t = 1.0                # up to date as soon as Tab goes down
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_dash.visible = driving != null or riding is Biplane or riding is ArmoredCar
	_update_gunsight()
	if driving is Biplane:
		_dash.text = (driving as Biplane).dash_text()
	elif riding is Biplane:
		_dash.text = (riding as Biplane).dash_text()
	elif riding is ArmoredCar:
		_dash.text = (riding as ArmoredCar).gunner_dash()
	elif driving is Horse:
		_dash.text = (driving as Horse).dash_text()
	elif driving is JetSki:
		_dash.text = (driving as JetSki).dash_text()
	elif driving:
		var arrows := ["  ", "  "]
		if driving.indicator != 0 and fmod(Time.get_ticks_msec() / 1000.0, Car.BLINK) < Car.BLINK * 0.5:
			arrows[0 if driving.indicator == 1 else 1] = "◀" if driving.indicator == 1 else "▶"
		var line := "%s  %3d km/h   gear %s  %s" % [arrows[0], roundi(absf(driving.speed()) * 3.6),
				"R" if driving.speed() < -0.5 else "D" if driving.audio.kind == "electric"
				else str(driving.audio.gear + 1), arrows[1]]
		if driving.has_doors:
			line += "\ndoors " + ("OPEN" if driving.doors_open else "closed")
		if driving.broken:
			line += "\nBROKEN · repaired in %d s" % ceili(driving.repair_in())
		if driving.dash_line() != "":
			line += "\n" + driving.dash_line()
		_dash.text = line
	var seat: Car = driving if driving else riding
	if _dash.visible and seat and seat.camera_label() != "":
		_dash.text += "\n" + seat.camera_label()


## The armed plane's gunsight: a ring where its guns' rounds converge, on the screen; for the gunner of the two-seater,
## where its turret's are aimed, and for the armoured car's, its roof gun's.
func _update_gunsight() -> void:
	var plane := driving as Biplane
	var gunner := riding as Biplane
	var cam := get_viewport().get_camera_3d()
	var aim: Variant = plane.aim_point() if plane and plane.armed \
			else gunner.turret_aim_point() if gunner and gunner.turret \
			else (riding as ArmoredCar).turret_aim_point() if riding is ArmoredCar else null
	_gunsight.visible = aim != null and cam != null and not cam.is_position_behind(aim)
	if _gunsight.visible:
		_gunsight.position = cam.unproject_position(aim) - _gunsight.size * 0.5
	var truck := driving as FireTruck
	var spot: Variant = truck.sight_point() if truck else null
	_water_sight.visible = spot != null and cam != null and not cam.is_position_behind(spot)
	if _water_sight.visible:
		_water_sight.position = cam.unproject_position(spot) - _water_sight.size * 0.5


## Welcome menu: the fly camera circles the campus, looking at its middle.
func _fly_around(delta: float) -> void:
	if is_nan(_orbit_ground):
		_orbit_ground = WorldQuery.ground_y(get_world_3d(), MENU_ORBIT_CENTRE.x, -MENU_ORBIT_CENTRE.y, Layers.SOLID)
		if is_nan(_orbit_ground):
			_orbit_ground = 0.0 if Engine.get_physics_frames() > 2 else NAN
			return
	_orbit_angle += MENU_ORBIT_SPEED * delta
	var centre := MeshUtils.to_godot(MENU_ORBIT_CENTRE.x, MENU_ORBIT_CENTRE.y, _orbit_ground)
	var eye := centre + Vector3(cos(_orbit_angle) * MENU_ORBIT.x, MENU_ORBIT.y, sin(_orbit_angle) * MENU_ORBIT.x)
	fly_camera.look_at_from_position(eye, centre + Vector3.UP * 20.0)


## LAN games: our player's state for the other peers (net.gd _pose_remote): in a passenger seat, that vehicle, the seat
## and flag 2 (the vehicle shows the player seated); standing in a vehicle, the position and
## facing are in its frame. That frame is the vehicle's pose the player last followed, not its current one: net.gd
## sends this after moving the remote vehicles but before the player follows them, so the current pose would put the
## player behind by the vehicle's last step.
func net_player_state() -> Array:
	var flags := 1 if driving or not player.visible else 0
	if riding:
		var seated := [riding.net_id, 0, riding.passenger_seat, 0.0, flags | 2]
		if riding is Biplane and (riding as Biplane).turret:
			seated.append_array((riding as Biplane).gunner_state())
		elif riding is ArmoredCar:
			seated.append_array((riding as ArmoredCar).gunner_state())
		return seated
	var c: Node3D = player.carrier if is_instance_valid(player.carrier) else null
	if c and not driving and c.get("train") != null:   # an RER B car (train.gd TrainCar): its train and its index
		var tf: Transform3D = player.carrier_frame()
		return [c.train.net_id, c.index, tf.affine_inverse() * player.global_position,
				player.body_yaw() - tf.basis.get_euler().y, flags]
	if c and not driving:
		var car: Car = c as Car if c is Car else c.head as Car
		var frame: Transform3D = player.carrier_frame()
		return [car.net_id, 0 if c == car else 1, frame.affine_inverse() * player.global_position,
				player.body_yaw() - frame.basis.get_euler().y, flags]
	return ["", 0, player.global_position, player.body_yaw(), flags]


## Puts the player on the ground at pipeline (x, y).
func spawn_at(xy: Vector2, yaw := 0.0) -> void:
	var g := WorldQuery.ground_y(get_world_3d(), xy.x, -xy.y, Layers.SOLID)
	player.teleport(MeshUtils.to_godot(xy.x, xy.y, 0.0 if is_nan(g) else g + 0.1), yaw)


func set_flying(on: bool) -> void:
	if on == flying:
		return
	if on and driving:
		exit_car()
	elif on and riding:
		leave_ride()
	if on:
		player.set_carrier(null)
	flying = on
	if on:
		fly_camera.global_transform = player.camera.global_transform
		fly_camera.make_current()
	else:
		# land the player under the fly camera, facing the same way
		var p := fly_camera.global_position
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, p.y)
		if not is_nan(g):
			player.teleport(Vector3(p.x, g + 0.1, p.z), fly_camera.global_rotation.y)
		player.camera.make_current()
	fly_camera.active = on
	player.active = not on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_help()


## Low (true) or high graphics settings (see the header).
func set_low_quality(on: bool) -> void:
	set_quality("low" if on else "high")


## "low", "medium" or "high" graphics settings (see the header).
func set_quality(level: String) -> void:
	quality = level if level in Settings.QUALITIES else "high"
	low_quality = quality == "low"
	var high := quality == "high"
	var env: Environment = $WorldEnvironment.environment
	env.ssil_enabled = _high["ssil"] and high
	env.ssao_enabled = _high["ssao"] and not low_quality
	env.glow_enabled = _high["glow"] and not low_quality
	get_viewport().msaa_3d = _high["msaa"] if high else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = _high["aa"] if high else Viewport.SCREEN_SPACE_AA_FXAA
	if _help:
		_update_help()


## Settings page or F11: quality, night, and keys in the help lines.
func _on_settings_changed() -> void:
	if allows("night_toggle"):
		night.set_night(Settings.night())
	if Settings.quality() != quality:
		set_quality(Settings.quality())
	else:
		_update_help()


## F3: the frame rate, then per frame (means over STATS_EVERY s) the physics ticks' time (bots, trains, vehicles), the
## render's CPU and the GPU time, which of the two the frame waits on, the 3D resolution drawn and the quality; then the
## network timings (net.gd).
const STATS_EVERY := 0.5

func _sample_stats(delta: float) -> void:
	var vp := get_viewport().get_viewport_rid()
	if _stats_frames == 0:
		_stats_sum[2] = Engine.get_physics_frames()
	_stats_sum[0] += delta * 1000.0
	_stats_sum[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0     # one tick
	_stats_sum[3] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_stats_frames += 1
	_stats_t += delta
	if _stats_t < STATS_EVERY:
		return
	var n := float(_stats_frames)
	var frame := _stats_sum[0] / n
	var physics := _stats_sum[1] / n * (Engine.get_physics_frames() - _stats_sum[2]) / n       # per frame
	var render := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := _stats_sum[3] / n
	var bound := "GPU-bound" if gpu > frame * 0.85 else ("CPU-bound" if physics + render > frame * 0.7 			else "waiting for vsync" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "")
	var scale := get_viewport().scaling_3d_scale
	var size := Vector2i((Vector2(get_viewport().size) * scale).round())
	var net_text := net.debug_text()                # the frame rate, then a line per player
	var traffic_line := [traffic.stats_text()] if traffic.stats_text() != "" else []     # the bots' load
	var fps := net_text.get_slice("
", 0)
	_stats.text = "
".join(PackedStringArray([fps + " · %.1f ms%s" % [frame, " · " + bound if bound != "" else ""],
			"physics %.1f · render CPU %.1f · GPU %.1f ms per frame" % [physics, render, gpu],
			"3D %d × %d (%d %%) · %s · %d vehicles" % [size.x, size.y, roundi(scale * 100.0), quality, cars.size()]] + traffic_line)) 			+ net_text.substr(fps.length())
	_stats_t = 0.0
	_stats_frames = 0
	_stats_sum.fill(0.0)


## For tools/screenshot*.gd: fly camera, no HUD, no player.
func set_screenshot_mode() -> void:
	set_flying(true)
	hud.visible = false
	player.visible = false
	debug_cars = false
	for car in cars:
		car.queue_free()
	cars.clear()


## Parks `model` (the next one in Car.MODELS by default) near the player on the first free spot: on a road
## or asphalt within ~20 m, lined up with it, when there is one; else anywhere beside the player, parallel to
## where the player looks. Returns the car, or null when no spot is free.
func spawn_car_near_player(model := "") -> Car:
	if model == "":
		model = Car.MODELS[_next_model % Car.MODELS.size()]
		_next_model += 1
	var car := new_vehicle(model)
	var yaw: float = player.camera.global_rotation.y
	if car is JetSki and Water.current:
		var on_water: Variant = Water.current.spot_near(player.global_position, JET_SKI_REACH, JET_SKI_ROOM, JET_SKI_LAKE)
		if on_water != null:
			add_child(car)
			car.place(on_water)
			_add_car(car)
			net.car_parked(car)
			return car
		_show_toast("No lake within %d m: the jet-ski is parked on land (it only crawls there)" % roundi(JET_SKI_REACH))
	var spot: Variant = _find_car_spot(yaw, car.half_extents, true)
	if spot == null:
		spot = _find_car_spot(yaw, car.half_extents, false)
	if spot != null:
		spot = spot.translated_local(-car.extents_center)  # the spot is the footprint centre, not the car origin
	if spot == null:
		print("no free spot for a %s near the player" % model)
		car.free()
		return null
	add_child(car)
	car.place(spot)
	_add_car(car)
	net.car_parked(car)
	return car


## Host (or solo): the showrooms' display cars missing from their podiums (scripts/dealership.gd).
func _stock_showrooms(pacer: Pacer = null) -> void:
	if not showroom_cars or not allows("showrooms"):
		return
	for s in get_tree().get_nodes_in_group("showroom"):
		await s.stock(self, pacer)


## `model` parked at `xf` (+Z forward, on the ground: a showroom podium), the footprint centred there; `exact`: its
## origin right at `xf` (the jet-ski on the water, Water.spot_near).
func park_vehicle(model: String, xf: Transform3D, exact := false) -> Car:
	var car := new_vehicle(model)
	add_child(car)
	car.place(xf if exact else xf.translated_local(-car.extents_center).translated(Vector3.UP * 0.3))
	_add_car(car)
	net.car_parked(car)
	return car


## A bot bus or car (scripts/traffic.gd): `car` (new_vehicle, not in the tree yet) at `xf`, driven by `bot` (bus_bot.gd).
func add_bot_bus(car: Car, xf: Transform3D, bot: Object) -> void:
	add_child(car)
	car.place(xf)
	car.set_pilot(bot)
	_add_car(car)
	net.car_parked(car)


## Host (or solo): bot traffic on (the lines filled afresh) or off (every bot vehicle and RER B train off the map, on
## every peer).
func set_bot_traffic(on: bool) -> void:
	if mode not in ["solo", "host", "server"] or on == bus_bots or not allows("bot_traffic"):
		return
	bus_bots = on
	train_bots = on
	if get_tree().current_scene == self and mode != "server":
		Settings.set_value("traffic", on)
	if on:
		traffic.start_bots()
		_start_trains()
	else:
		remove_vehicles(traffic.stop_bots())
		traffic.trains.stop()


## Host (or solo): every vehicle off the map, on every peer (the bots come back at once when bot traffic is on, the
## showroom display cars too, and the RER B line is filled afresh: no train left waiting behind another).
## Returns how many were cleared.
func clear_vehicles() -> int:
	if mode not in ["solo", "host", "server"]:
		return 0
	var n := cars.size()
	traffic.stop_bots()
	remove_vehicles(cars.duplicate())
	_stock_showrooms()
	if bus_bots and allows("bot_traffic"):
		traffic.start_bots()
	if traffic.trains.running:
		traffic.trains.stop()
		_start_trains()
	_show_toast("Cleared %d vehicles" % n)
	return n


## Takes `gone` (Car) off the map here, the player out of them first; the host's net.gd takes them off the other
## peers' too.
func remove_vehicles(gone: Array) -> void:
	for car: Car in gone:
		if not is_instance_valid(car):
			continue
		if driving == car:
			exit_car()
		if riding == car:
			leave_ride()
		if is_instance_valid(player.carrier) and player.carrier in car.bodies():
			player.set_carrier(null)
		cars.erase(car)
		car.queue_free()
	net.cars_removed(gone)
	_update_controls()
	_update_help()


## How many players ride `car` (standing in it or in a seat), here and on the other peers.
func riders(car: Car) -> int:
	var n := 0
	var sections: Array = car.bodies()
	if mode != "server" and (riding == car or (is_instance_valid(player.carrier) and player.carrier in sections)):
		n += 1
	for r: RemotePlayer in net.avatars():
		if r.visible and r.riding_in() in sections:
			n += 1
	return n


## The sections players ride (a car, its rear section, an RER B car) with how many on each: riders() for every vehicle
## at once (scripts/traffic.gd, each tick).
func ridden_sections() -> Dictionary:
	var out := {}
	if mode != "server":
		var mine: Node3D = riding if riding else player.carrier if is_instance_valid(player.carrier) else null
		if mine:
			out[mine] = 1
	for r: RemotePlayer in net.avatars():
		var s: Node3D = r.riding_in() if r.visible else null
		if s:
			out[s] = out.get(s, 0) + 1
	return out


## Where the players are (global): on foot, or the vehicles they drive or sit in (`on_foot`: those on foot only). The
## player of a dedicated server does not count.
func player_spots(on_foot := false) -> Array:
	var out := []
	if mode != "server" and mode != "":
		if flying:
			out.append(fly_camera.global_position)
		elif not (driving or riding):
			out.append(player.global_position)
		elif not on_foot:
			out.append((driving if driving else riding).global_position)
	for r: RemotePlayer in net.avatars():
		if r.visible:
			out.append(r.global_position)
	if not on_foot and net.active:
		for id: String in net.driver_of:
			if net.driver_of[id] != 0 and net.driver_of[id] != net.me() and net.cars.has(id):
				out.append((net.cars[id] as Node3D).global_position)
	return out


## LAN games: a vehicle another peer parked, at `xf` (net.gd).
func add_net_car(model: String, xf: Transform3D) -> Car:
	var car := new_vehicle(model)
	add_child(car)
	car.place(xf)
	_add_car(car)
	return car


## A vehicle of `model`, set up but not in the tree yet: a Horse (Car.SPECS "horse"), a JetSki ("jet_ski"), a Biplane for the aircraft
## ("plane"), a FireTruck for the fire truck ("fittings"), a PoliceCar for the police car ("police"), an ArmoredCar for
## the GAZ Tiger ("roof_gun"), else a Car.
static func new_vehicle(model: String) -> Car:
	var spec: Dictionary = Car.SPECS[model]
	var car: Car = Horse.new() if spec.get("horse", false) else JetSki.new() if spec.get("jet_ski", false) \
			else Biplane.new() if spec.get("plane", false) \
			else FireTruck.new() if spec.has("fittings") else PoliceCar.new() if spec.get("police", false) \
			else ArmoredCar.new() if spec.get("roof_gun", false) else Car.new()
	car.setup(model)
	return car


func _add_car(car: Car) -> void:
	if car.inside:
		for body in car.bodies():
			player.add_collision_exception_with(body)   # the player collides with its walkable hull instead
	if car is Biplane and (car as Biplane).guns:
		(car as Biplane).guns.hit.connect(_on_round_hit)
	if car is Biplane and (car as Biplane).turret_guns:
		(car as Biplane).turret_guns.hit.connect(_on_round_hit)
	if car is ArmoredCar:
		(car as ArmoredCar).turret_guns.hit.connect(_on_round_hit)
	if car is FireTruck:
		(car as FireTruck).cannon.hit.connect(_on_water_hit)
	cars.append(car)


## A round of an armed plane simulated here hit something: a vehicle takes damage (on the peer simulating it), a
## breakable prop falls over.
func _on_round_hit(collider: Object, shape: int, point: Vector3, velocity: Vector3) -> void:
	if game_mode and game_mode.round_hit(collider, point, velocity):
		return
	var node := collider as Node
	if node and node.is_in_group("vehicles"):
		var car := node as Car if node is Car else node.get("head") as Car
		if car:
			net.hit_vehicle(car, PlaneGuns.DAMAGE)
	else:
		breakables.shoot(collider, shape, velocity)


## A packet of the water cannon of a fire truck simulated here hit something, giving it `impulse`: a vehicle is pushed
## and its fire hosed (on the peer simulating it), another player shoved (on theirs), debris pushed, a light breakable
## prop soaked until it falls over.
func _on_water_hit(collider: Object, shape: int, point: Vector3, impulse: Vector3) -> void:
	var node := collider as CollisionObject3D
	if node == null:
		return
	if node.is_in_group("vehicles"):
		var car := node as Car if node is Car else node.get("head") as Car
		if car:
			net.water_vehicle(car, node as RigidBody3D, impulse, point, 1.0 / WaterCannon.RATE)
	elif node.collision_layer & Layers.REMOTE_PLAYER:
		net.water_player(node, water_shove(impulse))
	elif node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.apply_impulse(impulse.limit_length(rb.mass * WaterCannon.MAX_DV), point - rb.global_position)
	else:
		breakables.soak(node, shape, impulse)


## How hard a water packet giving `impulse` shoves a player (m/s): along the jet, lifting a little off the feet.
static func water_shove(impulse: Vector3) -> Vector3:
	var k := impulse.length() / WaterCannon.PUSH
	return Vector3(impulse.x, 0.0, impulse.z).normalized() * WATER_SHOVE * k + Vector3.UP * 0.5 * k


## Another player's water jet hit us (net.gd).
func water_push(dv: Vector3) -> void:
	if not driving and not flying and not riding:
		player.push(dv)


## Car transform (+Z forward, origin on the ground) for a free spot around the player for a vehicle of
## `half` extents, or null. `on_road`: the footprint must lie on road/parking ground; the heading is then
## searched in 15° steps from the player's (so the car lines up with the road), and the search reaches
## further out.
func _find_car_spot(yaw: float, half: Vector3, on_road: bool) -> Variant:
	var map: GroundMap = GroundMap.get_map() if on_road else null
	if on_road and map == null:
		return null
	var space := get_world_3d().direct_space_state
	var probe := BoxShape3D.new()
	probe.size = Vector3(half.x * 2.0 + 0.3, 2.0, half.z * 2.0 + 0.3)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.PLAYER
	var offsets: Array[Vector2] = []            # (side, along) in the player's frame, nearest first
	var s0 := half.x + 3.0                      # beside the player, room to walk between
	var sides := [0.0] if on_road else []
	for k in (5 if on_road else 3):
		sides.append_array([s0 + 3.0 * k, -(s0 + 3.0 * k)])
	var step := half.z * 2.0 + 0.6
	for side: float in sides:
		for along: float in [0.0, -1.0, 1.0, -2.0, 2.0, -3.0, 3.0]:
			offsets.append(Vector2(side, along * step))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	var turns := [0.0]
	if on_road:
		for k in range(1, 7):
			turns.append_array([deg_to_rad(15.0 * k), deg_to_rad(-15.0 * k)])
	var origin := player.global_position
	for o in offsets:
		var p := origin + Basis(Vector3.UP, yaw) * Vector3(o.x, 0.0, o.y)
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, origin.y + 3.0)
		if is_nan(g) or absf(g - origin.y) > 2.0 or _near_a_car(p, half.z + 0.5) or Water.depth_at(Vector3(p.x, g, p.z)) > 0.3:
			continue
		for turn: float in turns:
			# the model faces +Z: yaw + PI points it where the player looks (-Z of the camera)
			var b := Basis(Vector3.UP, yaw + PI + turn)
			if on_road and not _on_road(map, p, b, half):
				continue
			q.transform = Transform3D(b, Vector3(p.x, g + 1.3, p.z))
			if not space.intersect_shape(q, 1):
				return Transform3D(b, Vector3(p.x, g + 0.3, p.z))
	return null


## True when a grid over the footprint of a vehicle of `half` extents at `p` (Godot) facing `b` is on road,
## parking or other asphalt ground.
func _on_road(map: GroundMap, p: Vector3, b: Basis, half: Vector3) -> bool:
	var hx := half.x - 0.15
	var n := ceili(half.z / 1.5)                # every ~1.5 m along long vehicles
	for i in range(-n, n + 1):
		for x: float in [-hx, 0.0, hx]:
			if not _paved(map, p + b * Vector3(x, 0.0, (half.z - 0.15) * i / n)):
				return false
	return true


func _paved(map: GroundMap, w: Vector3) -> bool:
	var k := map.piece_at(w.x, -w.z)
	return k >= 0 and (map.pieces[k][0] in ["road", "parking"] or map.pieces[k][1] == "asphalt")


## True when a car stands within `d` metres (horizontally, plus that car's half length) of `p`; cars
## parked this frame are not in the physics space yet, so the shape query alone misses them. (Bots off the map, hidden
## where they vanished, do not count.)
func _near_a_car(p: Vector3, d: float) -> bool:
	for car in cars:
		if car.stowed:
			continue
		var c := car.to_global(car.extents_center)
		if Vector2(c.x - p.x, c.z - p.z).length() < d + car.half_extents.z:
			return true
	return false


## Nearest car within ENTER_RANGE of the player, or null.
func nearest_car() -> Car:
	var best: Car = null
	var best_d := ENTER_RANGE
	for car in cars:
		if car.is_bot() or car.stowed:
			continue
		var p := car.to_local(player.global_position) - car.extents_center
		var d := Vector2(maxf(absf(p.x) - car.half_extents.x, 0.0), maxf(absf(p.z) - car.half_extents.z, 0.0)).length()
		if d < best_d:
			best = car
			best_d = d
	return best


## The bot vehicle the player stands in or next to, or null.
func _bot_near() -> Car:
	for car in cars:
		if car.is_bot() and not car.stowed:
			var p := car.to_local(player.global_position) - car.extents_center
			if absf(p.x) < car.half_extents.x + ENTER_RANGE and absf(p.z) < car.half_extents.z + ENTER_RANGE:
				return car
	return null


## Car to get into with E: from inside a walkable vehicle, that one when the player is near its driver
## seat; else the nearest car.
func car_to_enter() -> Car:
	var carrier: Node3D = player.carrier if is_instance_valid(player.carrier) else null
	if carrier:
		var c: Car = carrier as Car if carrier is Car else carrier.head as Car
		if c.is_bot():
			return null
		return c if c.to_local(player.global_position).distance_to(c.driver_seat) < SEAT_RANGE else null
	return nearest_car()


## LAN games: the host lets us drive `car` (net.gd), which we asked for with E.
func drive_granted(car: Car) -> void:
	if driving or flying or mode == "":
		net.release_drive(car)
	else:
		enter_car(car)


func enter_car(car: Car) -> void:
	if riding:                              # sliding over from the passenger seat
		riding.set_riding(false)
		riding = null
	driving = car
	car.set_driver_color(color)
	car.controls = not (pause.visible or chat.is_open())
	player.set_carrier(null)
	player.active = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("CollisionShape3D").set_deferred("disabled", true)
	if car.has_cab():
		car.cab_view = player.first_person
	if night.on:
		car.set_headlights(true)
	car.set_driving(true)
	_update_help()


## Puts the player beside the car (driver side first, then passenger side, then on the roof), or in the
## aisle of a walkable vehicle.
func exit_car() -> void:
	var car := driving
	driving = null
	car.set_driving(false)
	if net.active:
		net.release_drive(car)
	if car.interior.size != Vector3.ZERO:
		_leave_seat(car)
		return
	_put_beside(car, 1.0)


## True when E should sit the player in the passenger seat of `car` rather than at the wheel: it has a free one, and
## another player drives it or the player stands on its passenger side (the right, -X).
func wants_passenger_seat(car: Car) -> bool:
	if not car.has_passenger_seat or car.passenger_taken():
		return false
	var driver: int = net.driver_of.get(car.net_id, 0) if net.active else 0
	return (driver != 0 and driver != net.me()) or car.to_local(player.global_position).x < 0.0


## Sits the player in the passenger seat of `car`: hidden, looking around with the car's cameras.
func ride_car(car: Car) -> void:
	riding = car
	player.set_carrier(null)
	_set_player_enabled(false)
	if car.has_cab():
		car.cab_view = player.first_person
	car.controls = not (pause.visible or chat.is_open())
	car.set_riding(true, color)
	_update_help()


## Out of the passenger seat, beside the car on its passenger side.
func leave_ride() -> void:
	var car := riding
	riding = null
	car.set_riding(false)
	_put_beside(car, -1.0)


## Puts the player on the ground beside the car, on the `side` given first (1: left, the driver's side; -1: right),
## then the other one, else on the roof.
func _put_beside(car: Car, side: float) -> void:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	var target := car.to_global(Vector3(0.0, car.half_extents.y * 2.0 + 0.3, 0.0))
	for s: float in [side, -side]:
		var p := car.to_global(Vector3(s * (car.half_extents.x + 0.7), 0.0, 0.3))
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, car.global_position.y + 2.5)
		if is_nan(g):
			continue
		g = maxf(g, Water.surface_at(p) - player.float_depth) if not is_nan(Water.surface_at(p)) else g   # swimming
		q.transform = Transform3D(Basis(), Vector3(p.x, g + 1.05, p.z))
		if not space.intersect_shape(q, 1):
			target = Vector3(p.x, g + 0.1, p.z)
			break
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("CollisionShape3D").set_deferred("disabled", false)
	player.visible = true
	player.active = true
	player.wait_jump_release = true
	if car.has_cab():
		player.set_first_person(car.cab_view)
	player.teleport(target, car.camera.global_rotation.y)
	player.camera.make_current()
	_update_help()


## From the driver seat into the aisle beside it, facing the back of the vehicle, carried by it.
func _leave_seat(car: Car) -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("CollisionShape3D").set_deferred("disabled", false)
	player.visible = true
	player.active = true
	player.wait_jump_release = true
	player.set_carrier(car)
	player.set_first_person(car.cab_view)
	player.teleport(car.to_global(car.driver_exit), car.global_rotation.y)
	player.camera.make_current()
	_update_help()


## Opens (walking only) or closes the vehicle menu; the player stands still while it is open.
func set_menu_open(on: bool) -> void:
	if on == _menu.visible or (on and (flying or driving or riding or pause.visible or chat.is_open())):
		return
	_menu.visible = on
	_menu_status.text = ""
	_update_controls()
	if on:
		_menu_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_menu_buttons.get_child(0).grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus:
			focus.release_focus()
		Input.mouse_mode = _menu_mouse


## Opens or closes the in-game menu (Esc); the player and the vehicle driven stand still while it is open.
func set_pause_open(on: bool) -> void:
	if on == pause.visible or (on and mode == ""):
		return
	if on:
		set_menu_open(false)
		chat.close()
		_pause_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var info := "Exploring solo." if mode_id == Modes.DEFAULT else "Playing %s solo." % Modes.title(mode_id)
		var players := []
		if mode == "host":
			info = "Hosting a LAN game: others join with %s.\nGoing back to the main menu ends it for everyone." % \
					net.lan_label().get_slice("  ·  ", 1)
		elif mode == "client":
			info = "Playing in %s (%s:%d)." % ["%s's game" % net.player_name(1) if net.players.has(1) else "a server",
					net.host_address, net.port]
		if net.active:
			for id: int in net.players:
				players.append([net.player_name(id) + (" (you)" if id == net.me() else ""), net.player_color(id)])
		if game_mode and game_mode.pause_info() != "":
			info = game_mode.pause_info() + "\n" + info
		var hosting := mode == "solo" or mode == "host"
		var actions: Array = (game_mode.host_actions() if hosting else []) + game_mode.player_actions() if game_mode \
				else []
		pause.open(info, players, "Back to main menu", hosting, bus_bots, allows("bot_traffic"), allows("clear_vehicles"),
				actions)
	else:
		pause.close()
		Input.mouse_mode = _pause_mouse
	_update_controls()


## True while the vehicle menu, the in-game menu, the full-screen map, the chat line or a game mode's panel is open.
func ui_open() -> bool:
	return _menu.visible or pause.visible or chat.is_open() or (world_map != null and world_map.visible) \
			or (game_mode != null and game_mode.ui_open())


## Opens or closes the full-screen map (M); the player and the vehicle driven take no keys while it is open.
func set_world_map_open(on: bool) -> void:
	if on == world_map.visible or (on and (pause.visible or chat.is_open() or not allows("map"))):
		return
	if on:
		_map_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		world_map.open()
	else:
		world_map.visible = false
		Input.mouse_mode = _map_mouse
	_update_controls()


## Puts the waypoint at pipeline (x, y) (the full-screen map), or takes it away (null).
func set_waypoint(xy: Variant) -> void:
	waypoint = xy
	_beacon.place(xy)


## The places the full-screen map and the minimap mark: [[name, kind, pipeline Vector2]] (minimap.gd PLACES):
## the showrooms (Prestige Motors), and the game mode's (PTA Online's garages).
func map_places() -> Array:
	var out := []
	for s in get_tree().get_nodes_in_group("showroom"):
		if s.dealer != "" and not s.outline.is_empty():
			var mid := Vector2.ZERO
			for p: Vector2 in s.outline:
				mid += p
			out.append([s.dealer, "shop", mid / s.outline.size()])
	return out + (game_mode.map_places() if game_mode else [])


## Where the maps are centred: the player, the vehicle they are in, or the fly camera.
func map_eye() -> Vector3:
	if flying:
		return fly_camera.global_position
	if driving:
		return driving.global_position
	if riding:
		return riding.global_position
	return player.global_position


## The player, the fly camera or the vehicle driven take the keys and mouse unless a menu or the chat is open (a game
## mode calls it when its panels open and close).
func update_controls() -> void:
	_update_controls()


func _update_controls() -> void:
	var ui := ui_open()
	player.active = not ui and not flying and not driving and not riding
	fly_camera.active = flying and not ui
	if driving:
		driving.controls = not ui
	if riding:
		riding.controls = not ui


## Opens the chat line (LAN games, Enter); chat.gd closes it on Enter or Esc.
func set_chat_open(on: bool) -> void:
	if on == chat.is_open() or (on and (not net.active or _menu.visible or pause.visible)):
		return
	if on:
		chat.open()
	else:
		chat.close()
	_update_controls()


func _on_chat(id: int, text: String) -> void:
	chat.add(net.player_name(id), net.player_color(id), text)


## The players (Tab): us first, then the host, then the others as they joined.
func _update_player_list() -> void:
	var ids: Array = net.players.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return [a != net.me(), a != 1, a] < [b != net.me(), b != 1, b])
	var rows := []
	for id: int in ids:
		rows.append([net.player_name(id), net.player_color(id), net.ping(id), id == net.me()])
	var title := "%s · %s · %d/%d players" % ["Your game" if mode == "host" else ("%s's game" % net.player_name(1) \
			if net.players.has(1) else "Server %s" % net.host_address), Modes.title(mode_id), ids.size(), Net.MAX_PLAYERS]
	_player_list.show_players(title, rows)


## A line at the top of the screen for a few seconds (a game mode's news too).
func toast(text: String) -> void:
	_show_toast(text)


func _show_toast(text: String) -> void:
	toast_shown.emit(text)
	_toast.text = text
	_toast_t = 4.0
	_toast.modulate.a = 1.0


func _spawn_from_menu(model: String) -> void:
	if spawn_car_near_player(model):
		set_menu_open(false)
	else:
		_menu_status.text = "No free spot for the %s here: try somewhere more open." % Car.display_name(model).to_lower()


## The vehicle menu key, Tab and Esc are caught before the GUI: with a menu button focused, Tab would only move the focus. Tab (held) shows
## the player list (_process). While typing in the chat, only Esc (close it) is caught.
func _input(event: InputEvent) -> void:
	if loading or not (event is InputEventKey or event is InputEventMouseButton) or mode == "":
		return
	var key := (event as InputEventKey).physical_keycode if event is InputEventKey else KEY_NONE
	if key == KEY_TAB:
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo():
		return
	if chat.is_open():
		if key == KEY_ESCAPE:
			set_chat_open(false)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_map") and not pause.visible and not _menu.visible and allows("map") \
			or (key == KEY_ESCAPE and world_map.visible):
		set_world_map_open(not world_map.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vehicle_menu") and not pause.visible and not world_map.visible \
			and allows("vehicle_menu") or (key == KEY_ESCAPE and _menu.visible):
		set_menu_open(not _menu.visible)
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and not pause.visible and game_mode and game_mode.close_ui():
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE:
		set_pause_open(not pause.visible)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if loading or _menu.visible or pause.visible or chat.is_open() or world_map.visible or mode == "":
		return
	if game_mode and game_mode.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not flying:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		set_chat_open(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fly_camera") and allows("fly_camera"):
		set_flying(not flying)
	elif event.is_action_pressed("interact") and not flying and not driving:
		var car := riding if riding else car_to_enter()
		var bot := _bot_near() if car == null else null
		if bot:
			_show_toast("A bot drives this bus: get on at a stop, while its doors are open" if bot.has_doors \
					else "A bot drives this car")
		elif car == null and traffic.trains.train_near(player.global_position, ENTER_RANGE):
			_show_toast("A bot drives this train: get on at Lozère while its doors are open")
		if car and not riding and wants_passenger_seat(car):
			ride_car(car)
		elif car and net.active:
			net.request_drive(car)
		elif car:
			enter_car(car)
	elif driving and event.is_action_pressed("interact" if driving is Horse else "exit_vehicle"):   # Space: the horse jumps
		exit_car()
	elif event.is_action_pressed("exit_vehicle") and riding:
		leave_ride()
	elif event.is_action_pressed("park_car") and not flying and not driving and allows("park_car"):
		spawn_car_near_player()
	elif event.is_action_pressed("inspect") and allows("inspect"):
		picker.pick_and_show(get_viewport().get_camera_3d())
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_quality"):
		Settings.set_value("quality", Settings.QUALITIES[(Settings.QUALITIES.find(quality) + 1) % Settings.QUALITIES.size()])
	elif event.is_action_pressed("night") and allows("night_toggle"):
		Settings.set_value("night", not night.on)
	elif event.is_action_pressed("headlights") and driving:
		driving.set_headlights(not driving.headlights)
	elif event.is_action_pressed("minimap") and allows("map"):
		Settings.set_value("minimap", not minimap.visible)
		_place_minimap()
	elif event.is_action_pressed("toggle_stats"):
		_stats.visible = not _stats.visible
		_stats_t = 1.0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _stats.visible)
	# not elif: X closes the inspection, and drifts too by default
	if event.is_action_pressed("inspect_close"):
		picker.hide_overlay()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	for size: Vector2 in [Vector2(14, 2), Vector2(2, 14)]:   # crosshair
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.anchor_left = 0.5
		r.anchor_right = 0.5
		r.anchor_top = 0.5
		r.anchor_bottom = 0.5
		r.offset_left = -size.x / 2.0
		r.offset_right = size.x / 2.0
		r.offset_top = -size.y / 2.0
		r.offset_bottom = size.y / 2.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(r)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.8)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
	hud.add_child(panel)
	picker.panel = panel
	picker.label = label

	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 4)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(_help)
	_dash = Label.new()
	_dash.add_theme_font_size_override("font_size", 22)
	_dash.add_theme_color_override("font_outline_color", Color.BLACK)
	_dash.add_theme_constant_override("outline_size", 5)
	_dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dash.visible = false
	hud.add_child(_dash)
	_dash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_dash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gunsight = Control.new()
	_gunsight.size = Vector2(44, 44)
	_gunsight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gunsight.visible = false
	_gunsight.draw.connect(func() -> void:
		var c := _gunsight.size * 0.5
		for k in 2:                         # dark outline under a light ring and pips
			var col := Color(0, 0, 0, 0.6) if k == 0 else Color(1.0, 0.85, 0.5, 0.95)
			var w := 4.0 if k == 0 else 2.0
			_gunsight.draw_arc(c, 16.0, 0.0, TAU, 40, col, w, true)
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_gunsight.draw_line(c + d * 9.0, c + d * 21.0, col, w, true)
		_gunsight.draw_circle(c, 2.0, Color(1.0, 0.85, 0.5, 0.95)))
	hud.add_child(_gunsight)
	_water_sight = Control.new()
	_water_sight.size = Vector2(52, 52)
	_water_sight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_sight.visible = false
	_water_sight.draw.connect(func() -> void:
		var c := _water_sight.size * 0.5
		for k in 2:                         # dark outline under a light blue dashed ring
			var col := Color(0, 0, 0, 0.5) if k == 0 else Color(0.6, 0.85, 1.0, 0.95)
			var w := 4.0 if k == 0 else 2.0
			for a in 8:
				_water_sight.draw_arc(c, 20.0, TAU * a / 8.0, TAU * (a + 0.6) / 8.0, 6, col, w, true)
		_water_sight.draw_circle(c, 3.0, Color(0.6, 0.85, 1.0, 0.95)))
	hud.add_child(_water_sight)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_host_label = Label.new()
	_host_label.add_theme_font_size_override("font_size", 17)
	_host_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_host_label.add_theme_constant_override("outline_size", 5)
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_label.visible = false
	hud.add_child(_host_label)
	_host_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_host_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats.add_theme_constant_override("outline_size", 4)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.visible = false
	hud.add_child(_stats)
	_stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	minimap = Minimap.new()
	minimap.game = self
	hud.add_child(minimap)
	_place_minimap()
	_beacon = WaypointBeacon.new()
	_beacon.name = "Waypoint"
	_beacon.game = self
	add_child(_beacon)
	_build_menu()
	world_map = WorldMap.new()
	world_map.game = self
	hud.add_child(world_map)
	chat = Chat.new()
	chat.closed.connect(_update_controls)
	chat.sent.connect(net.say)
	hud.add_child(chat)
	_player_list = PlayerList.new()
	hud.add_child(_player_list)
	_player_list.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 60)
	_player_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_update_help()
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


## Centred panel with a button per vehicle model (set_menu_open).
func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.name = "VehicleMenu"
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", UiStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var title := Label.new()
	title.text = "Spawn a vehicle"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_menu_buttons = GridContainer.new()
	_menu_buttons.columns = 3
	_menu_buttons.add_theme_constant_override("h_separation", 8)
	_menu_buttons.add_theme_constant_override("v_separation", 8)
	box.add_child(_menu_buttons)
	var looks := UiStyle.button_looks()
	for model: String in Car.MODELS:
		var b := UiStyle.button(Car.display_name(model), looks)
		b.name = model
		b.pressed.connect(_spawn_from_menu.bind(model))
		_menu_buttons.add_child(b)
	_menu_status = UiStyle.label("", 16, UiStyle.TEXT_WARN)
	box.add_child(_menu_status)
	_menu_hint = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	box.add_child(_menu_hint)
	hud.add_child(_menu)
	UiStyle.centre(_menu)


func _update_help() -> void:
	var k := Settings.key_text
	var common := "%s inspect · %s close · %s fly camera · Esc menu · %s hide help" % [k.call("inspect"),
			k.call("inspect_close"), k.call("fly_camera"), k.call("toggle_help")]
	if not allows("inspect") or not allows("fly_camera"):
		common = ("%s fly camera · " % k.call("fly_camera") if allows("fly_camera") else "") + \
				"Esc menu · %s hide help" % k.call("toggle_help")
	var mode_walk: String = game_mode.walk_help(k) if game_mode else ""
	var moves := _keys(["move_forward", "move_left", "move_back", "move_right"])
	var look := "mouse look · %s camera free/auto · %s (held) look back" % [k.call("camera_mode"), k.call("look_back")]
	if flying:
		_help.text = "FLY CAMERA · hold right mouse to look · %s move · %s/%s down/up\n" % [moves, k.call("cam_down"),
				k.call("cam_up")] + "%s faster · wheel speed · %s land the player here · %s inspect · %s close · " % [
				k.call("run"), k.call("fly_camera"), k.call("inspect"), k.call("inspect_close")] + \
				"Esc menu · %s hide help" % k.call("toggle_help")
	elif driving is Biplane:
		_help.text = ("FLY · %s/%s throttle · %s/%s nose down/up · %s/%s roll (on the ground: steer) · %s/%s rudder\n" % [
				k.call("plane_throttle_up"), k.call("plane_throttle_down"), k.call("plane_nose_down"),
				k.call("plane_nose_up"), k.call("plane_roll_left"), k.call("plane_roll_right"), k.call("plane_rudder_left"),
				k.call("plane_rudder_right")]) + \
				("%s at idle brakes · %s level the wings (on the ground: back on the wheels) · %s · " % [
				k.call("plane_throttle_down"), k.call("reset_vehicle"), look]) + \
				"wheel zoom (all the way in: cockpit) · %s cockpit\n" % k.call("toggle_view") + \
				("%s (held) fire the guns · " % k.call("fire") if (driving as Biplane).armed else "") + \
				"%s landing lights · " % k.call("headlights") + \
				("your gunner boards from the right side · " if (driving as Biplane).turret else "") + \
				"%s get out · %s" % [k.call("exit_vehicle"), common]
	elif driving is Horse:
		_help.text = ("RIDE · %s go (canter), with %s gallop · %s stop, then back up · %s/%s turn · " % [k.call("throttle"),
				k.call("run"), k.call("brake"), k.call("steer_left"), k.call("steer_right")]) + \
				"%s jump (the faster, the higher: fences!) · %s neigh\n" % [k.call("jump"), k.call("horn")] + \
				("%s · wheel zoom (all the way in: rider's view) · %s rider's view · %s back on its feet · " % [look,
				k.call("toggle_view"), k.call("reset_vehicle")]) + "%s get off · %s" % [k.call("interact"), common]
	elif driving is JetSki:
		_help.text = ("JET-SKI · %s throttle · %s slow down, then reverse · %s/%s steer (with the throttle) · %s horn\n" % [
				k.call("throttle"), k.call("brake"), k.call("steer_left"), k.call("steer_right"), k.call("horn")]) + \
				("mouse look · wheel zoom (all the way in: rider's view) · %s rider's view · %s right it · " % [
				k.call("toggle_view"), k.call("reset_vehicle")]) + "%s get off (into the water: swim) · %s" % [
				k.call("exit_vehicle"), common]
	elif driving:
		_help.text = ("DRIVE · %s throttle, %s brake then reverse, %s/%s steer · %s/%s turn signals · %s horn · " % [
				k.call("throttle"), k.call("brake"), k.call("steer_left"), k.call("steer_right"), k.call("signal_left"),
				k.call("signal_right"), k.call("horn")]) + "%s headlights · %s (held) drift\n" % [k.call("headlights"),
				k.call("drift")] + \
				"%s · wheel zoom%s · %s back on wheels · %s%s %s · %s race (in a start circle)\n%s" % [look,
				" (all the way in: cab view)" if driving.has_cab() else "", k.call("reset_vehicle"),
				"%s doors · %s gong · %s cab view · " % [k.call("doors"), k.call("bell"), k.call("toggle_view")] \
				if driving.has_doors else ("%s cab view · " % k.call("toggle_view") if driving.has_cab() else ""),
				k.call("exit_vehicle"),
				"leave the seat" if driving.has_doors else "get out", k.call("race"), common]
	elif riding is Biplane:
		_help.text = ("GUNNER · mouse aims the belly turret (forward only, up to 45° off the nose) · %s (held) fire · " % \
				k.call("fire")) + "wheel zoom (all the way in: turret view) · %s turret view\n" % k.call("toggle_view") + \
				"%s take the controls (if nobody flies) · %s get out\n%s" % [k.call("interact"), k.call("exit_vehicle"), common]
	elif riding is ArmoredCar:
		_help.text = ("GUNNER · mouse aims the roof gun (all round, from %d° down to %d° up) · %s (held) fire · " % [
				roundi(rad_to_deg(ArmoredCar.PITCH_DOWN)), roundi(rad_to_deg(ArmoredCar.PITCH_UP)), k.call("fire")]) + "wheel zoom (all the way in: turret view) · %s turret view\n" % k.call("toggle_view") + \
				"%s take the wheel (if nobody drives) · %s get out\n%s" % [k.call("interact"), k.call("exit_vehicle"), common]
	elif riding:
		_help.text = "PASSENGER · %s · wheel zoom (all the way in: cab view) · %s cab view · " % [look,
				k.call("toggle_view")] +"%s take the wheel (if nobody drives) · %s get out\n%s" % [k.call("interact"),
				k.call("exit_vehicle"), common]
	elif mode_walk != "":
		_help.text = mode_walk + "\n" + common
	else:
		_help.text = "WALK · click to capture the mouse · %s move · %s run · %s jump\n" % [moves, k.call("run"),
				k.call("jump")] + \
				"wheel zoom (all the way in: first person) · %s first/third person · %s get in the nearest car " % [
				k.call("toggle_view"), k.call("interact")] + "(in the bus: near the driver seat; fire truck: " + \
				"from its right side, the passenger seat; biplane with gunner: from its right side, the turret; " + \
				"GAZ Tiger: from its right side, the roof gun)\n" + \
				"%s park a car here · %s vehicle menu · %s" % [k.call("park_car"), k.call("vehicle_menu"), common]
	if driving is FireTruck:
		_help.text += "\n%s (held) water cannon, aimed where you look (the view holds while it sprays) · %s siren and beacons" % [
				k.call("fire"), k.call("bell")]
	elif driving is PoliceCar:
		_help.text += "\n%s siren and blue lights" % k.call("bell")
	elif driving is ArmoredCar:
		_help.text += "\nyour gunner boards from the right side and works the roof gun"
	var extra: String = game_mode.extra_help(k) if game_mode else ""
	if extra != "":
		_help.text += "\n" + extra
	_help.text += "\n%s graphics: %s · %s%s%s frame rate%s · F11 fullscreen" % [k.call("toggle_quality"),
			quality, "%s %s · " % [k.call("night"), "day" if night and night.on else "night"] \
			if allows("night_toggle") else "", "%s map · %s minimap · " % [letter_key("world_map", "M"),
			k.call("minimap")] if allows("map") else "", k.call("toggle_stats"), " and network" if net.active else ""]
	if net.active:
		_help.text += " · Enter chat · Tab players"
	if _menu_hint:
		_menu_hint.text = "click or arrows + Enter: park it next to you · %s / Esc close" % k.call("vehicle_menu")
	if chat:
		_place_chat()


## Keys of `actions` run together ("WASD", "ZQSD" on AZERTY), or with slashes when one is not a single letter.
func _keys(actions: Array) -> String:
	var names := PackedStringArray()
	var short := true
	for a: String in actions:
		names.append(Settings.key_text(a))
		short = short and names[-1].length() == 1
	return ("" if short else "/").join(names)


## The minimap as the settings and the game mode want it, the inspection panel beside it.
func _place_minimap() -> void:
	minimap.visible = Settings.values.get("minimap", true) and allows("map")
	if not allows("map") and world_map:
		set_world_map_open(false)
		set_waypoint(null)
	picker.panel.position.x = 12.0 + (Minimap.SIZE + 12.0 if minimap.visible else 0.0)


## `action`'s key for the help: `letter` if one of its keys reads so on this layout (the full-screen map is bound on
## M's spot on QWERTY and on AZERTY), else its first.
func letter_key(action: String, letter: String) -> String:
	for b: int in Settings.bindings(action):
		if Settings.binding_text(b) == letter:
			return letter
	return Settings.key_text(action)


## The chat sits bottom left, just above the help.
func _place_chat() -> void:
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat.offset_bottom = -12.0 - _help.get_combined_minimum_size().y - 8.0
