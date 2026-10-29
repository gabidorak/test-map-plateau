extends "res://scripts/modes/game_mode.gd"
## PTA Online (ONLINE_MODE.md, ONLINE_MILESTONES.md O3): the mode of the official server (game.gd plays it there, and
## only there: --official). The world is Sandbox's (bot traffic, the RER B, races, Prestige Motors...), but vehicles
## belong to accounts (scripts/economy.gd reads them from the accounts service) and only come out at garages:
## - No vehicle menu, no parking with C, no clearing the map, no cars parked at start, no fly camera (it puts the
##   player down anywhere), no armed vehicle (ARMED), not even from a patched client: the server judges every request,
##   and net.gd ignores a vehicle a client parks itself.
## - Garages (scripts/online/garages.gd, world/garages.json): E at a terminal lists the player's vehicles this garage
##   takes (the public ones: all but the work vehicles; the bus depot: buses; the fire station: fire trucks, both of
##   which they also lend), and the server parks the one picked on a free bay that fits it (the jet-ski on the
##   nearest lake, when the garage has one within reach). One vehicle out per player: getting another out sends the
##   first back (it leaves the map).
## - Locks: a player's vehicle is locked when it comes out: the others may ride in it (walk in a bus, sit in the
##   passenger seat), not drive it, until its owner unlocks it (U: the vehicle's panel). Vehicles of nobody's garage
##   (Prestige Motors' display cars) are never driven.
## - Leaving: a player's vehicle stays KEEP s after they disconnect, and is theirs again if they log in within that
##   time (they appear beside it); then it leaves the map.
## - Players join on foot by the garage nearest to the game's spawn point (beside their vehicle when it waited for
##   them); the in-game menu takes them back to the nearest garage.
## - The wallet shows top right (the server's word, economy.gd); the garages are on the maps (map_places).
## The host (the official server) keeps who owns which vehicle; every peer gets it (`vehicles`) to show the prompts.
## Played solo (the tools: PLATEAU_MODE=online), the player's garage is PLATEAU_ONLINE_VEHICLES (models, comma-separated).

const Garages = preload("res://scripts/online/garages.gd")
const GaragePanel = preload("res://scripts/online/garage_panel.gd")
const Economy = preload("res://scripts/economy.gd")
const Car = preload("res://scripts/car.gd")
const Marks = preload("res://scripts/race_marks.gd")
const Water = preload("res://scripts/water.gd")

signal answered(ok: bool, text: String)     # the host's answer to our last request at a garage terminal

const ARMED := ["biplane-armed", "biplane-gunner", "gaz-tiger"]
const WORK := {"depot": ["bus-idfm", "bus-idfm-artic"], "fire": ["fire-truck"]}   # lent there, and only out there
const KEEP := 30.0                          # s a player's vehicle waits for them after they leave (PLATEAU_ONLINE_KEEP)
const REACH := 2.5                          # m from a terminal for E
const SERVER_REACH := 8.0                   # m the server allows (the player's position reaches it a little late)
const PROMPT_REACH := 3.0                   # m from a vehicle for its owner's prompt
const PLACE_KINDS := {"public": "garage", "depot": "depot", "fire": "fire"}

var hosting := false                        # this peer keeps the garages (solo, host, official server)
var garages: Garages
var vehicles := {}                          # net id -> {"owner": username, "model", "locked"}; the host's also have
											# "account", "peer" (0: left) and "vehicle" (garage id, 0 lent)
var mine := ""                              # net id of our vehicle out, "" none
var keep_time := KEEP
var test_garage: Array = []                 # played solo by the tools: the player's vehicles (models)
var _leaving := {}                          # host: account -> [net id, s left]
var _panel: GaragePanel
var _wallet: Label
var _prompt: Label
var _mouse := Input.MOUSE_MODE_VISIBLE
var _beside := ""                           # client: net id of our vehicle to put us beside once it's here
var _beside_t := 0.0
var _check_t := 0.0
var _next_solo := 0


func allows(feature: String) -> bool:
	return feature not in ["debug_cars", "vehicle_menu", "park_car", "clear_vehicles", "fly_camera", "armed_vehicles"]


func _ready() -> void:
	garages = Garages.new()
	garages.name = "Garages"
	add_child(garages)
	if OS.get_environment("PLATEAU_ONLINE_KEEP") != "":
		keep_time = float(OS.get_environment("PLATEAU_ONLINE_KEEP"))
	for m in OS.get_environment("PLATEAU_ONLINE_VEHICLES").split(",", false):
		test_garage.append(m.strip_edges())
	multiplayer.peer_disconnected.connect(_on_left)
	game.economy.logged_in.connect(_on_login)


func _exit_tree() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	if _wallet and is_instance_valid(_wallet):
		_wallet.queue_free()
	if _prompt and is_instance_valid(_prompt):
		_prompt.queue_free()


func begin() -> void:
	hosting = game.mode in ["solo", "host", "server"]
	garages.build(game.mode != "server")
	if game.mode == "server":
		return
	_build_hud()
	game.economy.wallet_changed.connect(_show_wallet)
	_show_wallet()
	if _beside == "":
		to_garage(game.spawn_xy)


func pause_info() -> String:
	var who: String = game.economy.username if game.economy.username != "" else game.nickname
	return "PTA Online · %s · %s" % [who, Economy.money(game.economy.balance)]


func player_actions() -> Array:
	return [["Back to the nearest garage", func() -> void:
		var here: Vector3 = game.map_eye()
		to_garage(Vector2(here.x, -here.z))]]


func walk_help(k: Callable) -> String:
	return "WALK · click to capture the mouse · %s move · %s run · %s jump\n" % [
			game._keys(["move_forward", "move_left", "move_back", "move_right"]), k.call("run"), k.call("jump")] + \
			"wheel zoom (all the way in: first person) · %s first/third person · %s at a garage terminal: your " % [
			k.call("toggle_view"), k.call("interact")] + "vehicles · %s get in your vehicle (or one unlocked; ride along in the others)" % \
			k.call("interact")


func extra_help(k: Callable) -> String:
	return "%s your vehicle (lock, send back) · the garages are on the map (%s)" % [k.call("vehicle_menu"),
			game.letter_key("world_map", "M")]


func map_places() -> Array:
	var out := []
	for g: Dictionary in garages.list:
		out.append([g["name"], PLACE_KINDS.get(g["kind"], "garage"), g["xy"]])
	return out


func ui_open() -> bool:
	return _panel != null and _panel.visible


func close_ui() -> bool:
	if not ui_open():
		return false
	_close_panel()
	return true


# ---------------------------------------------------------------- the local player

## The garage whose terminal E uses now: within REACH, and nearer than the vehicle E would get in (the first bay is
## beside the terminal), or {}.
func terminal_at_hand() -> Dictionary:
	var here: Vector3 = game.player.global_position
	var g := garages.terminal_near(here, REACH)
	var car: Car = game.car_to_enter() if not g.is_empty() else null
	if car:
		var p := car.to_local(here) - car.extents_center
		var to_car := Vector2(maxf(absf(p.x) - car.half_extents.x, 0.0), maxf(absf(p.z) - car.half_extents.z, 0.0)).length()
		var t: Vector3 = g["terminal"]
		if to_car < Vector2(t.x - here.x, t.z - here.z).length():
			return {}
	return g


## Puts the player on foot by the public garage nearest to map point `xy`, facing its terminal.
func to_garage(xy: Vector2) -> void:
	if game.driving:
		game.exit_car()
	if game.riding:
		game.leave_ride()
	var g := garages.nearest(Vector3(xy.x, 0.0, -xy.y))
	if g.is_empty():
		return
	var spot := garages.stand_spot(g)
	game.player.set_carrier(null)
	game.player.teleport(spot[0], spot[1])


func handle_input(event: InputEvent) -> bool:
	if game.mode == "server" or _panel == null:
		return false
	var keys := event.is_action_pressed("interact") or event.is_action_pressed("vehicle_menu")
	if ui_open():
		if keys:
			_close_panel()
		return keys
	var on_foot: bool = game.driving == null and game.riding == null and not game.flying
	if event.is_action_pressed("interact") and on_foot:
		var g := terminal_at_hand()
		if not g.is_empty():
			open_garage(g["id"])
			return true
	if event.is_action_pressed("vehicle_menu"):
		open_vehicle()
		return true
	return false


## E at garage `id`'s terminal: its panel, filled when the host answers.
func open_garage(id: String) -> void:
	var g := garages.get_garage(id)
	var look: Dictionary = Garages.KINDS[g["kind"]]
	var sub := {"public": "Your vehicles (not the work ones: buses at the bus depot, fire trucks at the fire station)",
			"depot": "Bus drivers: a lent bus, or one of yours", "fire": "Firefighters: a lent fire truck, or yours"}
	_open_panel()
	_panel.open_garage(id, "%s · %s" % [look["title"], g["name"]] if g["kind"] == "public" else str(g["name"]),
			sub[g["kind"]], Settings.key_text("interact"))
	game.update_controls()
	to_host(self, "_h_open", [id])


## U: our vehicle's panel.
func open_vehicle() -> void:
	_open_panel()
	var car := car_of(mine)
	if car == null:
		var g := garages.nearest(game.map_eye())
		var d := Vector2(g["terminal"].x - game.map_eye().x, g["terminal"].z - game.map_eye().z).length() \
				if not g.is_empty() else 0.0
		_panel.open_vehicle("No vehicle out", "Get one out at a garage terminal: the nearest is %s, %d m away (on the map)." % [
				g.get("name", "?"), roundi(d)], null, Settings.key_text("vehicle_menu"))
		game.update_controls()
		return
	var d := car.global_position.distance_to(game.map_eye())
	_panel.open_vehicle("Your %s" % Car.display_name(car.model_name).to_lower(), "%d m away" % roundi(d) if d > 8.0
			else "Right here", vehicles.get(mine, {}).get("locked", true), Settings.key_text("vehicle_menu"))
	game.update_controls()


## Frees the mouse for a panel about to show (its open_* call, then game.update_controls()).
func _open_panel() -> void:
	if not _panel.visible:
		_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_panel() -> void:
	_panel.close()
	Input.mouse_mode = _mouse
	game.update_controls()


## Asks to lock (or unlock) our vehicle.
func set_locked(on: bool) -> void:
	if mine != "":
		to_host(self, "_h_lock", [mine, on])


func _build_hud() -> void:
	_panel = GaragePanel.new()
	game.hud.add_child(_panel)
	_panel.spawn.connect(func(vehicle: int, model: String) -> void:
		_panel.set_status("Getting it out…")
		to_host(self, "_h_spawn", [_panel.garage_id, vehicle, model]))
	_panel.lock.connect(set_locked)
	_panel.send_back.connect(func() -> void:
		to_host(self, "_h_back", [])
		_close_panel())
	_wallet = Label.new()
	_wallet.name = "Wallet"
	_wallet.add_theme_font_size_override("font_size", 24)
	_wallet.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7))
	_wallet.add_theme_color_override("font_outline_color", Color.BLACK)
	_wallet.add_theme_constant_override("outline_size", 6)
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.add_child(_wallet)
	_wallet.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.add_theme_font_size_override("font_size", 19)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 150)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _show_wallet() -> void:
	if _wallet:
		_wallet.text = Economy.money(game.economy.balance)
		_wallet.visible = game.economy.username != "" or not game.net.active


func _process(delta: float) -> void:
	if hosting:
		_host_tick(delta)
	if _prompt == null:
		return
	if _beside != "":
		_beside_t += delta
		var car := car_of(_beside)
		if car and game.mode == "client":
			_put_beside(car)
			_beside = ""
		elif _beside_t > 20.0:
			_beside = ""
	_prompt.text = prompt_text()


## The line over the bottom of the screen: the terminal at hand, or whose the vehicle at hand is.
func prompt_text() -> String:
	if game.ui_open() or game.flying or game.riding:
		return ""
	if game.driving:
		var v: Dictionary = vehicles.get(game.driving.net_id, {})
		return "" if v.is_empty() or game.driving.net_id == mine else "%s's %s (unlocked)" % [v["owner"],
				Car.display_name(v["model"]).to_lower()]
	var g := terminal_at_hand()
	if not g.is_empty():
		return "%s  %s · your vehicles" % [Settings.key_text("interact"), g["name"]]
	var car: Car = game.nearest_car()
	if car == null:
		return ""
	var v: Dictionary = vehicles.get(car.net_id, {})
	if v.is_empty():
		return "Not for driving: online, you drive your own vehicles (garages on the map)"
	if car.net_id == mine:
		return "Your %s · %s · %s lock/unlock" % [Car.display_name(v["model"]).to_lower(), "locked" if v["locked"]
				else "unlocked", Settings.key_text("vehicle_menu")]
	return "%s's %s · %s" % [v["owner"], Car.display_name(v["model"]).to_lower(),
			"locked: you can ride along, not drive" if v["locked"] else "unlocked: you may drive it"]


func _put_beside(car: Car) -> void:
	var p := car.to_global(car.extents_center + Vector3(car.half_extents.x + 1.2, 0.0, 0.0))
	p.y = Marks.ground(p.x, -p.z) + 0.1
	var to := car.global_position - p
	game.player.set_carrier(null)
	game.player.teleport(p, atan2(-to.x, -to.z))
	game.toast("Your %s waited for you" % Car.display_name(car.model_name).to_lower())


# ---------------------------------------------------------------- host

## Player `peer`'s account: {"account", "username", "vehicles": [{"id", "model", "wrecked"...}]}, {} when not logged
## in. Solo (the tools), the player's own made-up one (test_garage).
func account(peer: int) -> Dictionary:
	if game.economy.official:
		return game.economy.account_of(peer)
	if not game.net.active and peer == me():
		var list := []
		for i in test_garage.size():
			list.append({"id": i + 1, "model": test_garage[i], "colour": "", "wrecked": false, "upgrades": {}})
		return {"account": 0, "username": game.nickname, "vehicles": list}
	return {}


## What garage `g` offers player account `acc`: [{"vehicle" (garage id, 0 lent), "model", "label", "note"}]; a note
## says why it can't come out here.
func offer(g: Dictionary, acc: Dictionary) -> Array:
	var kind: String = g["kind"]
	var out := []
	for m: String in WORK.get(kind, []):
		out.append({"vehicle": 0, "model": m, "label": "%s (lent)" % Car.display_name(m), "note": ""})
	for v: Dictionary in acc.get("vehicles", []):
		var m := str(v["model"])
		if not Car.SPECS.has(m):
			continue
		var note := ""
		if kind != "public" and m not in WORK[kind]:
			continue                        # the depot and the fire station only show their own kind
		if kind == "public" and m in WORK["depot"]:
			note = "At the bus depot (Massy-Palaiseau)"
		elif kind == "public" and m in WORK["fire"]:
			note = "At the fire station (Polytechnique)"
		elif m in ARMED:
			note = "Not allowed in PTA Online"
		elif v.get("wrecked", false):
			note = "Wrecked"
		elif m == "jet-ski" and _water_spot(g) == null:
			note = "No lake near this garage"
		elif m != "jet-ski" and not Garages.any_fits(g, m):
			note = "Too big for this garage"
		out.append({"vehicle": int(v["id"]), "model": m, "label": Car.display_name(m), "note": note})
	return out


## Host: why player `peer` can't get vehicle (`vehicle`, `model`) out at garage `gid`, or "" when they can.
func spawn_problem(peer: int, gid: String, vehicle: int, model: String) -> String:
	var acc := account(peer)
	if acc.is_empty():
		return "Not logged in."
	var g := garages.get_garage(gid)
	if g.is_empty():
		return "No such garage."
	if model in ARMED:
		return "Armed vehicles aren't allowed in PTA Online."
	if not _near(peer, g):
		return "Walk up to the garage's terminal."
	for e: Dictionary in offer(g, acc):
		if int(e["vehicle"]) == vehicle and e["model"] == model:
			return str(e["note"])
	return "That vehicle isn't in your garage." if vehicle != 0 else "This garage doesn't lend that."


## Whether player `peer` stands by garage `g`'s terminal (as the host sees them).
func _near(peer: int, g: Dictionary) -> bool:
	var p: Variant = _position_of(peer)
	if p == null:
		return false
	var t: Vector3 = g["terminal"]
	return Vector2(t.x - p.x, t.z - p.z).length() <= SERVER_REACH and absf(t.y - p.y) < 4.0


func _position_of(peer: int) -> Variant:
	if peer == me() and game.mode != "server":
		return game.map_eye()
	return game.net.player_position(peer)


## Host: gets vehicle (`vehicle`, `model`) out at garage `gid` for player `peer`, sending their vehicle out before
## back first. "" when done, else why not.
func spawn_for(peer: int, gid: String, vehicle: int, model: String) -> String:
	var problem := spawn_problem(peer, gid, vehicle, model)
	if problem != "":
		return problem
	var acc := account(peer)
	var g := garages.get_garage(gid)
	var old := _vehicle_of(int(acc["account"]))
	var others: Array = game.cars.filter(func(c: Car) -> bool: return c.net_id != old)
	var on_water: bool = model == "jet-ski"
	var xf: Variant = _water_spot(g) if on_water else garages.free_bay(g, model, others, game.player_spots(true))
	if xf == null:
		return "Every bay that fits it is taken: wait for one to clear."
	if old != "":
		_send_back(old)
	var car: Car = game.park_vehicle(model, xf, on_water)
	if car.net_id == "":                    # solo: no network id
		_next_solo += 1
		car.net_id = "solo:%d" % _next_solo
	vehicles[car.net_id] = {"owner": str(acc["username"]), "model": model, "locked": true,
			"account": int(acc["account"]), "peer": peer, "vehicle": vehicle}
	_share(car.net_id)
	send_to(peer, self, "_c_mine", [car.net_id, false])
	if game.net.dedicated:
		print("%s got their %s out at %s" % [acc["username"], model, gid])
	return ""


## Where a jet-ski comes out for garage `g`: on the nearest lake within the game's jet-ski reach of its terminal, or
## null.
func _water_spot(g: Dictionary) -> Variant:
	if Water.current == null:
		return null
	return Water.current.spot_near(g["terminal"], game.JET_SKI_REACH, game.JET_SKI_ROOM, game.JET_SKI_LAKE)


## The net id of account `account`'s vehicle out, or "".
func _vehicle_of(account_id: int) -> String:
	for id: String in vehicles:
		if vehicles[id].get("account", -1) == account_id:
			return id
	return ""


## Host: takes vehicle `id` back to its garage (off the map, everywhere).
func _send_back(id: String) -> void:
	var car := car_of(id)
	vehicles.erase(id)
	_share(id)
	if car and is_instance_valid(car):
		game.remove_vehicles([car])


## The vehicle of net id `id` (solo: the id this mode gave it), or null.
func car_of(id: String) -> Car:
	if id == "":
		return null
	if game.net.active:
		return game.net.cars.get(id)
	for c: Car in game.cars:
		if c.net_id == id:
			return c
	return null


## Host: tells everyone what vehicle `id` is now (nothing: gone).
func _share(id: String) -> void:
	var info := _public(id)
	send_all(self, "_c_vehicle", [id, info])
	if game.mode != "server":
		_c_vehicle(id, info)


func _public(id: String) -> Dictionary:
	if not vehicles.has(id):
		return {}
	var v: Dictionary = vehicles[id]
	return {"owner": v["owner"], "model": v["model"], "locked": v["locked"]}


func refuse_drive(net_id: String, peer: int) -> bool:
	var v: Dictionary = vehicles.get(net_id, {})
	var acc := account(peer)
	if v.is_empty():
		var display := false
		for s in get_tree().get_nodes_in_group("showroom"):
			display = display or game.net.cars.get(net_id) in s.parked
		send_to(peer, self, "_c_notice", ["A display car of Prestige Motors: not for driving." if display
				else "Not yours: online, you drive the vehicles of your garage (and those their owners unlock)."])
		return true
	if not acc.is_empty() and int(acc["account"]) == int(v["account"]):
		return false
	if not v["locked"]:
		return false
	send_to(peer, self, "_c_notice", ["%s's %s is locked: you can ride along, not drive." % [v["owner"],
			Car.display_name(v["model"]).to_lower()]])
	return true


func player_registered(peer: int) -> void:
	var all := {}
	for id: String in vehicles:
		all[id] = _public(id)
	send_to(peer, self, "_c_vehicles", [all])


## Host: a player's login was checked: their vehicle waiting for them is theirs again.
func _on_login(peer: int) -> void:
	var acc := account(peer)
	var id := _vehicle_of(int(acc.get("account", -1)))
	if id == "":
		return
	_leaving.erase(int(acc["account"]))
	vehicles[id]["peer"] = peer
	send_to(peer, self, "_c_mine", [id, true])


## Host: player `peer` left: their vehicle waits KEEP s for them.
func _on_left(peer: int) -> void:
	if not hosting:
		return
	for id: String in vehicles:
		if vehicles[id]["peer"] == peer:
			vehicles[id]["peer"] = 0
			_leaving[int(vehicles[id]["account"])] = [id, keep_time]


func _host_tick(delta: float) -> void:
	for account_id: int in _leaving.keys():
		_leaving[account_id][1] -= delta
		if _leaving[account_id][1] <= 0.0:
			var id: String = _leaving[account_id][0]
			_leaving.erase(account_id)
			if vehicles.has(id) and vehicles[id]["peer"] == 0:
				if game.net.dedicated:
					print("%s's %s left the map (owner gone %d s)" % [vehicles[id]["owner"], vehicles[id]["model"],
							roundi(keep_time)])
				_send_back(id)
	_check_t += delta
	if _check_t >= 1.0 and game.net.active:   # vehicles gone some other way (sunk, the map cleared...)
		_check_t = 0.0
		for id: String in vehicles.keys():
			if not game.net.cars.has(id):
				vehicles.erase(id)
				_share(id)


# ---------------------------------------------------------------- messages

## Player: garage `gid`'s list, please.
@rpc("any_peer", "call_remote", "reliable")
func _h_open(gid: String) -> void:
	if not hosting:
		return
	var peer := _sender()
	if game.economy.official:
		await game.economy.refresh(peer)    # the garage may have changed (the admin, a purchase)
	var g := garages.get_garage(gid)
	var acc := account(peer)
	if g.is_empty() or acc.is_empty():
		return
	var message := "" if _near(peer, g) else "Walk up to the garage's terminal."
	send_to(peer, self, "_c_garage", [gid, offer(g, acc) if message == "" else [], message])


@rpc("any_peer", "call_remote", "reliable")
func _h_spawn(gid: String, vehicle: int, model: String) -> void:
	if not hosting:
		return
	var peer := _sender()
	var problem := spawn_for(peer, gid, vehicle, model)
	if problem != "" and game.net.dedicated:
		print("%s: no %s at %s (%s)" % [game.net.player_name(peer), model, gid, problem])
	send_to(peer, self, "_c_result", [problem == "", "Out on a bay: %s to get in." % Settings.key_text("interact")
			if problem == "" else problem])


@rpc("any_peer", "call_remote", "reliable")
func _h_lock(id: String, on: bool) -> void:
	var acc := account(_sender())
	if hosting and vehicles.has(id) and not acc.is_empty() and int(vehicles[id]["account"]) == int(acc["account"]):
		vehicles[id]["locked"] = on
		_share(id)


@rpc("any_peer", "call_remote", "reliable")
func _h_back() -> void:
	var acc := account(_sender())
	var id := _vehicle_of(int(acc.get("account", -1))) if hosting else ""
	if id != "":
		_send_back(id)


@rpc("authority", "call_remote", "reliable")
func _c_garage(gid: String, entries: Array, message: String) -> void:
	if _panel and _panel.kind == "garage" and _panel.garage_id == gid:
		_panel.show_entries(entries, message if message != "" or not entries.is_empty()
				else "Nothing here yet: Prestige Motors sells vehicles.")


@rpc("authority", "call_remote", "reliable")
func _c_result(ok: bool, text: String) -> void:
	answered.emit(ok, text)
	if ok and ui_open():
		_close_panel()
	if ok or not ui_open():
		game.toast(text)
	else:
		_panel.set_status(text)


@rpc("authority", "call_remote", "reliable")
func _c_vehicle(id: String, info: Dictionary) -> void:
	if info.is_empty():
		vehicles.erase(id)
		if id == mine:
			mine = ""
	elif hosting:
		vehicles[id].merge(info, true)
	else:
		vehicles[id] = info
	if _panel and _panel.kind == "vehicle" and id == mine:
		_panel.set_locked(info.get("locked", true))


@rpc("authority", "call_remote", "reliable")
func _c_vehicles(all: Dictionary) -> void:
	vehicles = all


@rpc("authority", "call_remote", "reliable")
func _c_mine(id: String, kept: bool) -> void:
	mine = id
	if kept:
		_beside = id
		_beside_t = 0.0


@rpc("authority", "call_remote", "reliable")
func _c_notice(text: String) -> void:
	game.toast(text)


# ---------------------------------------------------------------- network helpers (as Escape from Plateau's)

func me() -> int:
	return multiplayer.get_unique_id() if game.net.active else 1


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else me()


## Calls `method` of `node` on every welcomed player but us.
func send_all(node: Node, method: StringName, args: Array) -> void:
	if not game.net.active:
		return
	for peer: int in game.net.players:
		if peer != me():
			node.callv("rpc_id", [peer, method] + args)


## Calls `method` of `node` on player `peer` (here when it is us).
func send_to(peer: int, node: Node, method: StringName, args: Array) -> void:
	if peer == me() or not game.net.active:
		if game.mode != "server":
			node.callv(method, args)
	elif game.net.players.has(peer):
		node.callv("rpc_id", [peer, method] + args)


## Calls `method` of `node` on the host (here when we host or play solo).
func to_host(node: Node, method: StringName, args: Array) -> void:
	if not game.net.active or multiplayer.is_server():
		node.callv(method, args)
	else:
		node.callv("rpc_id", [1, method] + args)
