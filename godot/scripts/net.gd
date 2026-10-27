extends Node
## LAN games (game.gd creates it as Main/Net: its RPCs need the same path on every peer). ENet through Godot's
## high-level multiplayer, the host being the server; the other peers reach each other through it.
## - Players: each peer sends its player PLAYER_SEND_RATE times a second (game.net_player_state: position, body facing,
##   driving or not). A player standing in a vehicle sends its position in that vehicle's frame, so on every screen it
##   stays inside it however that vehicle's motion is smoothed there; one in a vehicle's passenger seat (the fire
##   truck's) sends flag 2, and that vehicle shows them seated; in the gunner's seat of the two-seat biplane, also its
##   turret (plane.gd gunner_state; the GAZ Tiger's roof gun likewise, armored_car.gd), whose hits count on the gunner's
##   peer. Others show it as a remote_player.gd, which the
##   vehicles they simulate collide with.
## - Vehicles: each one is simulated by a single peer, its owner: the one who parked it, then whoever drives it (the
##   host takes over the vehicles of a player who leaves). The other peers pose a frozen copy from the owner's states
##   (car.gd set_remote / apply_net_state). Getting in asks the host, which hands the vehicle to the new driver unless
##   someone else drives it.
## - States are played back a little late, between the two received around that time on the sender's clock (its
##   offset from ours estimated from the quickest arrivals). How late adapts to each sender: one interval between its
##   states plus how much later than the quickest ones its states arrive (Track.delay; ~25 ms on a LAN). A state late
##   all the same is made up for a moment by carrying on the motion (Track.at). States are sent as soon as the player
##   has moved this tick (Sender) and read just before playing back (_physics_process): no frame waits in between.
## - Trees bent and props broken by a vehicle simulated here (breakables.gd `broke`) bend and break everywhere.
## - Damage: the rounds of an armed plane hit on the peer flying it (scripts/plane_guns.gd); a hit vehicle takes the
##   damage on the peer simulating it (hit_vehicle), whose states carry its health to the others. Remote copies of the
##   plane fire the same rounds for show (its states carry the trigger).
## - Water: the fire truck's jet hits on the peer simulating the truck (scripts/water_cannon.gd); a vehicle hit is
##   pushed (and its fire put out) by the peer simulating it (water_vehicle, batched WATER_SEND_RATE times a second),
##   a player hit is pushed by their own peer (water_player). Remote copies of the truck spray for show.
## - A dedicated server (game.gd --dedicated) hosts without playing: it is not in `players` and sends no player state,
##   but it still simulates the vehicles nobody else does.
## - Clock: the host's clock is the game's (clock(): the traffic lights' cycle, traffic.gd); it sends it every
##   CLOCK_EVERY s, and each client keeps its offset from its own clock from the quickest arrival.
## - Bot buses (traffic.gd) are the host's vehicles; their states say a bot drives them, and the host lets nobody take
##   their wheel.
## - RER B trains (scripts/train_traffic.gd): the host runs them and sends every train's compact state (train.gd
##   net_state: front along its route, speed, doors, lamps) TRAIN_SEND_RATE times a second, stamped with its clock;
##   the others make the train on first sight and pose it from the same route, carried on at its speed for the time
##   the state took (the shared clock), so it reaches the platform at the same moment on every screen. A player
##   standing in a train sends its position in that car's frame, like in a bus. With the host's bot traffic off the
##   trains are stowed and their states go once a second.
## - Chat: a message goes to the host, which sends it to everyone with who said it. The host also sends everyone each
##   player's ping to it every PING_EVERY s (the player list, game.gd Tab).
## - The host announces the game on the LAN (lan_discovery.gd), with its game mode, and sends newcomers the game mode
##   (game.gd makes it as Main/Mode before anything of the mode's comes in), the players, the vehicles, and the trees
##   bent and props knocked down at that moment (breakables.gd net_snapshot). A game mode's own messages
##   (scripts/modes/game_mode.gd) go through its node, and only to welcomed players.

const LanDiscovery = preload("res://scripts/lan_discovery.gd")
const RemotePlayer = preload("res://scripts/remote_player.gd")
const Car = preload("res://scripts/car.gd")
const Updater = preload("res://scripts/updater.gd")

signal joined                               # client: the host welcomed us (the players, vehicles... are here)
signal failed(reason: String)               # client: could not join
signal ended(reason: String)                # client: the host closed the game
signal message(text: String)                # someone joined or left, a vehicle is taken...
signal chat(id: int, text: String)          # player `id` said `text`
signal registered(id: int)                  # host: player `id` was let in (it has the players, vehicles... now)

const PORT := 7777                          # the host tries the next ones when it is taken
const PORT_TRIES := 10
const MAX_PLAYERS := 8
const PROTOCOL := 11                        # bump when the messages change (build_id: other builds are refused anyway)
const PLAYER_SEND_RATE := 60.0              # player states per second
const CAR_SEND_RATE := 30.0                 # vehicle states per second
const TRAIN_SEND_RATE := 10.0               # RER B train states per second (host)
const IDLE_SEND_EVERY := 0.5                # s, states of vehicles at rest
const FAR_SEND_EVERY := 3                   # vehicle sends between two of a bot gliding far from every player
const REMOTE_SLEEP_EVERY := 3               # ticks between poses of a remote vehicle asleep far from the camera (car.gd)
const MIN_DELAY := 0.02                     # s, bounds of the playback delay (Track.delay)
const MAX_DELAY := 0.15
const DELAY_MARGIN := 0.005                 # s
const DELAY_UP := 0.1                       # s per s the playback delay grows (states arrive later)...
const DELAY_DOWN := 0.02                    # ...and shrinks: playback runs at most 10% fast, 2% slow
const LATE_MEMORY := 3.0                    # s, time constant over which a late arrival is forgotten (_late)
const HITCH := 0.05                         # s between ticks: we stalled, states read now are late because of us
const CLOCK_CREEP := 0.005                  # s per s the clock offset estimate creeps up (_stamp)
const MAX_EXTRAPOLATION := 0.05             # s past the newest state the motion carries on (Track.at)
const CONNECT_TIMEOUT := 6.0                # s
const PING_EVERY := 1.0                     # s between the host's ping lists
const CHAT_LENGTH := 200                    # characters per chat message
const DEFAULT_COLOR := Color(1, 0.55, 0.2)
const WATER_SEND_RATE := 10.0               # water pushes on vehicles simulated elsewhere, batches per second
const CLOCK_EVERY := 0.5                    # s between the host's clock messages (the first ones come in while loading)
const CLOCK_CREEP_DOWN := 0.002             # s per s the clock offset estimate eases back (drift, a quick outlier)

var game: Node3D                            # game.gd
var discovery: LanDiscovery
var active := false                         # hosting, or welcomed by a host
var dedicated := false                      # hosting without a player of our own
var port := 0                               # the game's port (hosting) or the host's (client)
var host_address := ""                      # client: the address joined
var players := {}                           # peer id -> {"name": String, "color": Color}, ourselves included
var cars := {}                              # net id -> Car, all of them (simulated here or elsewhere)
var owner_of := {}                          # net id -> peer simulating it
var driver_of := {}                         # net id -> peer driving it, 0 nobody

var _profile := {}                          # client: our {"name", "color"} until the host welcomes us
var _remotes := {}                          # peer id -> RemotePlayer
var _player_tracks := {}                    # peer id -> Track
var _car_tracks := {}                       # net id -> Track (vehicles simulated elsewhere)
var _offsets := {}                          # peer id -> our clock minus its clock (s), estimated
var _stamped := {}                          # peer id -> when _offsets was last updated (our clock)
var _late := {}                             # peer id -> how much later than the quickest its states arrive (s)
var _last_tick := 0.0                       # when _physics_process last read the states (our clock)
var _after_hitch := false                   # reading the states that queued up while we stalled
var _sent := {}                             # net id -> switches (flags, indicator) last sent
var _next_car := 0
var _send_t := 0.0                          # s since the last player state
var _car_send_t := 0.0                      # s since the last vehicle states
var _train_send_t := 0.0                    # s since the last train states (host)
var _idle_t := 0.0
var _pending_drive := ""                    # net id of the vehicle we asked to drive
var _connect_t := -1.0                      # s since connecting, -1 when not waiting
var _pings := {}                            # client: peer id -> its round trip to the host (ms), from the host
var _ping_t := 0.0
var _water_out := {}                        # "net id|section" -> [owner, impulse, weighted offset, weight, seconds]
var _water_t := 0.0
var _clock_offset := NAN                    # client: the host's clock minus ours (s), from the quickest arrival
var _car_sends := 0                         # vehicle sends so far (FAR_SEND_EVERY)
var clock_shift := 0.0                      # s added to our clock when it is the game's (tests set the lights)
var _clock_t := 0.0


## Recent states of one remote player or vehicle, stamped with the sender's clock.
class Track:
	var times := PackedFloat64Array()
	var states := []
	var interval: float                     # s between states, as sent
	var delay := -1.0                       # s, how late they are played back (Net._playback_time); -1 not yet
	var starved := 0                        # playbacks past the newest state

	func _init(send_rate: float) -> void:
		interval = 1.0 / send_rate

	func add(t: float, s: Array) -> void:
		if not times.is_empty() and t <= times[-1]:
			return
		times.append(t)
		states.append(s)
		if times.size() > 30:
			times = times.slice(1)
			states.pop_front()

	func is_empty() -> bool:
		return states.is_empty()

	func latest() -> Array:
		return states[-1]

	## [older state, newer state, weight] around time t. Up to MAX_EXTRAPOLATION past the newest state, the last two
	## and a weight over 1: the motion carries on. Further past them or before them, the nearest one alone.
	func at(t: float) -> Array:
		if t >= times[-1]:
			starved += 1
			var n := times.size()
			if n >= 2 and times[-1] - times[-2] < 3.0 * interval:
				var past := minf(t - times[-1], MAX_EXTRAPOLATION)
				return [states[-2], states[-1], 1.0 + past / (times[-1] - times[-2])]
			return [states[-1], states[-1], 0.0]
		for i in range(times.size() - 1, 0, -1):
			if times[i - 1] <= t:
				return [states[i - 1], states[i], (t - times[i - 1]) / (times[i] - times[i - 1])]
		return [states[0], states[0], 0.0]


## Sends our states each tick once the player has moved (Net plays back before it: process_physics_priority).
class Sender extends Node:
	func _init() -> void:
		name = "Sender"
		process_physics_priority = 1000

	func _physics_process(delta: float) -> void:
		get_parent()._send(delta)


func _ready() -> void:
	process_physics_priority = -10          # remote vehicles move before the player follows the one it stands in
	add_child(Sender.new())
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## The protocol and this build's commit (stamped by CI, "" for editor runs and local exports) in one number, sent when
## joining and in the LAN beacon: the host refuses players running another build. Older builds sent PROTOCOL alone, so
## they get refused too.
static func build_id() -> int:
	return hash([PROTOCOL, str(ProjectSettings.get_setting("application/config/commit", ""))])


func me() -> int:
	return multiplayer.get_unique_id()


## The game's clock in seconds: the host's in a LAN game (as well as we know it), ours otherwise.
func clock() -> float:
	if active and not multiplayer.is_server() and not is_nan(_clock_offset):
		return _now() + _clock_offset
	return _now() + clock_shift


## The other players' avatars (remote_player.gd).
func avatars() -> Array:
	return _remotes.values()


## Player `id`'s avatar (remote_player.gd), or null (ourselves, or not in the game).
func avatar(id: int) -> RemotePlayer:
	return _remotes.get(id)


## Starts a server on `first_port` (or the next free port) and announces it on the LAN. Returns an error message, or "".
## `server_only`: a dedicated server, `nickname` names the game.
func host(nickname: String, color: Color, first_port := PORT, server_only := false) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for k in PORT_TRIES:
		err = peer.create_server(first_port + k, MAX_PLAYERS - 1)
		if err == OK:
			port = first_port + k
			break
	if err != OK:
		return "Could not start the game: ports %d to %d are all taken." % [first_port, first_port + PORT_TRIES - 1]
	multiplayer.multiplayer_peer = peer
	dedicated = server_only
	players = {} if dedicated else {1: {"name": nickname, "color": color}}
	active = true
	discovery.start_beacon(func() -> Dictionary:
		return {"port": port, "name": nickname, "players": players.size(), "max": MAX_PLAYERS,
				"version": build_id(), "mode": game.mode_id})
	return ""


## Connects to a host; `joined` or `failed` follows. Returns an error message, or "".
func join(address: String, host_port: int, nickname: String, color: Color) -> String:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, host_port) != OK:
		return "Could not connect to %s:%d." % [address, host_port]
	multiplayer.multiplayer_peer = peer
	_profile = {"name": nickname, "color": color}
	host_address = address
	port = host_port
	_connect_t = 0.0
	return ""


## Leaves the game (closes it for everyone when hosting) and forgets its players and vehicles.
func leave() -> void:
	discovery.stop()
	var peer := multiplayer.multiplayer_peer
	if peer and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	_connect_t = -1.0
	_pending_drive = ""
	_clock_offset = NAN
	for id: int in _remotes.keys():
		_remove_remote(id)
	players.clear()
	cars.clear()
	owner_of.clear()
	driver_of.clear()
	_car_tracks.clear()
	_pings.clear()


func _process(delta: float) -> void:
	if active and multiplayer.is_server():
		_clock_t += delta
		if _clock_t >= CLOCK_EVERY:
			_clock_t = 0.0
			_signal_clock.rpc(clock())
		_ping_t += delta
		if _ping_t >= PING_EVERY:
			_ping_t = 0.0
			var pings := {}
			for id: int in players:
				pings[id] = ping(id)
			_ping_list.rpc(pings)
	if _connect_t >= 0.0:
		_connect_t += delta
		if _connect_t > CONNECT_TIMEOUT:
			_fail("No answer from %s:%d. Check the address, and that the host's firewall lets the game through." % [
					host_address, port])


func _fail(reason: String) -> void:
	leave()
	failed.emit(reason)


func _on_connected() -> void:
	_register.rpc_id(1, build_id(), _profile["name"], _profile["color"])


func _on_connection_failed() -> void:
	_fail("Could not reach %s:%d. Is a game hosted there?" % [host_address, port])


func _on_server_disconnected() -> void:
	if active:
		leave()
		ended.emit("The host closed the game.")
	else:
		_fail("The host closed the connection.")


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else me()


func player_name(id: int) -> String:
	return players[id]["name"] if players.has(id) else "Someone"


func player_color(id: int) -> Color:
	return players[id]["color"] if players.has(id) else DEFAULT_COLOR


# ---------------------------------------------------------------- players

## Server: a client says who it is; it gets the players, vehicles and breakables, the others get the newcomer.
@rpc("any_peer", "call_remote", "reliable")
func _register(protocol: int, nickname: String, color: Color) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != build_id():
		var tag := str(ProjectSettings.get_setting("application/config/version", ""))
		_refused.rpc_id(id, "The host runs another build of the game (%s)." % [
				Updater.pretty(tag) if tag != "" else "unversioned"])
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	nickname = nickname.strip_edges().left(20)
	players[id] = {"name": nickname if nickname != "" else "Player", "color": color}
	var snapshot := []
	for net_id: String in cars:
		snapshot.append([net_id, cars[net_id].model_name, owner_of[net_id], driver_of[net_id], cars[net_id].net_state()])
	_welcome.rpc_id(id, players, snapshot, game.breakables.net_snapshot(), game.mode_id)
	_signal_clock.rpc_id(id, clock())
	_player_joined.rpc(id, players[id])
	_add_remote(id)
	registered.emit(id)
	message.emit("%s joined the game" % players[id]["name"])


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	var tag := str(ProjectSettings.get_setting("application/config/version", ""))
	_fail("%s You have %s: restart the game to update, or ask the host to." % [reason,
			Updater.pretty(tag) if tag != "" else "an unversioned build"])


## Client: the host's players, vehicles, what is bent or knocked over there, and its game mode.
@rpc("authority", "call_remote", "reliable")
func _welcome(all: Dictionary, snapshot: Array, broken: Array, mode_id: String) -> void:
	game.set_game_mode(mode_id)             # Main/Mode first: the mode's own messages follow this one
	players = all
	for id: int in players:
		if id != me():
			_add_remote(id)
	for c: Array in snapshot:
		_make_car(c[0], c[1], c[2], c[3], c[4])
	game.breakables.apply_net_snapshot(broken)
	active = true
	_connect_t = -1.0
	joined.emit()


@rpc("authority", "call_remote", "reliable")
func _player_joined(id: int, info: Dictionary) -> void:
	if id == me() or _remotes.has(id):
		return
	players[id] = info
	_add_remote(id)
	message.emit("%s joined the game" % info["name"])


@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	if not players.has(id):
		return
	message.emit("%s left the game" % player_name(id))
	players.erase(id)
	_remove_remote(id)


## Server: a client left; the host takes over its vehicles.
func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	for net_id: String in cars:
		if owner_of[net_id] == id or driver_of[net_id] == id:
			_car_control.rpc(net_id, 1 if owner_of[net_id] == id else owner_of[net_id], 0)
	_player_left.rpc(id)
	_player_left(id)


func _add_remote(id: int) -> void:
	if _remotes.has(id):
		return
	var r := RemotePlayer.new()
	r.setup(player_name(id), player_color(id))
	r.visible = false                       # until its first state
	game.add_child(r)
	_remotes[id] = r
	_player_tracks[id] = Track.new(PLAYER_SEND_RATE)


func _remove_remote(id: int) -> void:
	if _remotes.has(id):
		(_remotes[id] as RemotePlayer).sit_in(null)
		(_remotes[id] as Node).queue_free()
	_remotes.erase(id)
	_player_tracks.erase(id)
	_offsets.erase(id)
	_stamped.erase(id)
	_late.erase(id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_state(t: float, s: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _player_tracks.has(id):
		_stamp(id, t)
		_player_tracks[id].add(t, s)


## Shows remote player `id` from its states around now: [vehicle net id or "", section (0 front, 1 rear), position
## (in that section's frame, else global), body yaw (relative to the section's), flags (1 hidden, 2 in the vehicle's
## passenger seat), and in a plane's gunner seat its turret aim and trigger (plane.gd gunner_state)].
func _pose_remote(id: int, a: Array, b: Array, w: float) -> void:
	var r: RemotePlayer = _remotes[id]
	if a[0] != b[0]:                        # got in or out of a vehicle in between: no blending across frames
		a = b
	var pos: Vector3 = (a[2] as Vector3).lerp(b[2], w)
	var yaw := lerp_angle(a[3], b[3], minf(w, 1.0))
	var shown: bool = b[4] & 1 == 0
	var car: Car = null
	if String(b[0]).begins_with("train:"):          # standing in an RER B car: b[1] is the car
		var tr: Node3D = null
		for o: Node3D in game.traffic.trains.trains:
			if o.net_id == b[0]:
				tr = o
		r.visible = shown and tr != null and not tr.stowed
		r.sit_in(null)
		if tr and int(b[1]) < tr.cars.size():
			r.show_in(tr.cars[int(b[1])], pos, yaw)
		r.update_collision(r.visible, null, game.cars)
		return
	if b[0] != "":
		car = cars.get(b[0])
		if car == null:
			shown = false
	r.visible = shown
	r.sit_in(car if b[4] & 2 else null)
	if car and b[4] & 2 and b.size() > 6 and car.has_method("set_gunner_state"):
		car.set_gunner_state((a[5] as Vector3).lerp(b[5], minf(w, 1.0)) if a.size() > 6 else b[5], b[6])
	if car:
		r.show_in(car.trailer if b[1] == 1 and car.trailer else car, pos, yaw)
	else:
		r.show_at(Transform3D(Basis.IDENTITY, pos), yaw)
	r.update_collision(shown, car, game.cars)


## Round trip from player `id` to the host in ms (0 for the host itself), -1 when not known yet.
func ping(id: int) -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if id == 1 and multiplayer.is_server():
		return 0
	if id == me() or (id == 1 and not multiplayer.is_server()):
		var link: ENetPacketPeer = peer.get_peer(1) if peer else null
		return roundi(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if link else -1
	if multiplayer.is_server():
		var link: ENetPacketPeer = peer.get_peer(id) if peer else null
		return roundi(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if link else -1
	return _pings.get(id, -1)


@rpc("authority", "call_remote", "unreliable")
func _ping_list(pings: Dictionary) -> void:
	_pings = pings


## Client: the host's clock `t` when it sent this. The quickest arrival gives the offset (it creeps back slowly, so
## clock drift and a lucky outlier wear off). (Named to sort after _refused and _register, like _vehicle_hit.)
## Client: the host's trains at time `t` on its clock.
@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _trains_state(t: float, states: Array) -> void:
	var late := clock() - t
	for s: Array in states:
		var tr: Node3D = game.traffic.trains.ensure(s[0], s[1])
		if tr:
			tr.apply_net_state(s[2], late)


@rpc("authority", "call_remote", "unreliable")
func _signal_clock(t: float) -> void:
	var off := t - _now()
	if is_nan(_clock_offset) or off > _clock_offset:
		_clock_offset = off
	else:
		_clock_offset -= CLOCK_CREEP_DOWN * CLOCK_EVERY


# ---------------------------------------------------------------- chat

## Says `text` to everyone (game.gd's chat box), through the host.
func say(text: String) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_say(text)
	else:
		_say.rpc_id(1, text)


## Host: a player said something; everyone gets it with who said it.
@rpc("any_peer", "call_remote", "reliable")
func _say(text: String) -> void:
	var id := _sender()
	text = text.strip_edges().left(CHAT_LENGTH)
	if not multiplayer.is_server() or not players.has(id) or text == "":
		return
	_chat.rpc(id, text)


@rpc("authority", "call_local", "reliable")
func _chat(id: int, text: String) -> void:
	chat.emit(id, text)


# ---------------------------------------------------------------- vehicles

## A vehicle parked here (game.gd): gives it an id and parks it on the other peers too.
func car_parked(car: Car) -> void:
	if not active:
		return
	_next_car += 1
	car.net_id = "%d:%d" % [me(), _next_car]
	cars[car.net_id] = car
	owner_of[car.net_id] = me()
	driver_of[car.net_id] = 0
	_spawn_car.rpc(car.net_id, car.model_name, car.net_state())


@rpc("any_peer", "call_remote", "reliable")
func _spawn_car(net_id: String, model: String, state: Array) -> void:
	if active:
		_make_car(net_id, model, multiplayer.get_remote_sender_id(), 0, state)


func _make_car(net_id: String, model: String, owner_id: int, driver_id: int, state: Array) -> void:
	if cars.has(net_id) or not Car.SPECS.has(model):
		return
	var car: Car = game.add_net_car(model, state[0])
	car.net_id = net_id
	cars[net_id] = car
	owner_of[net_id] = owner_id
	driver_of[net_id] = driver_id
	if owner_id != me():
		car.set_remote(true)
		_car_tracks[net_id] = Track.new(CAR_SEND_RATE)
	car.apply_net_state(state, state, 0.0)
	_show_driver(net_id)


## Host: vehicles taken off the map here (game.gd remove_vehicles): off it on the other peers too.
func cars_removed(removed: Array) -> void:
	var ids := PackedStringArray()
	for car: Car in removed:
		if car.net_id != "":
			ids.append(car.net_id)
		forget_car(car)
	if active and multiplayer.is_server() and not ids.is_empty():
		_remove_cars.rpc(ids)


## A vehicle that left the map: no longer tracked.
func forget_car(car: Car) -> void:
	var id := car.net_id
	if id == "":
		return
	cars.erase(id)
	owner_of.erase(id)
	driver_of.erase(id)
	_car_tracks.erase(id)
	_sent.erase(id)
	if _pending_drive == id:
		_pending_drive = ""


## (Named to sort after _refused and _register, like _vehicle_hit.)
@rpc("authority", "call_remote", "reliable")
func _remove_cars(ids: PackedStringArray) -> void:
	var gone := []
	for id in ids:
		if cars.has(id):
			gone.append(cars[id])
	game.remove_vehicles(gone)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _cars_state(t: float, states: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	_stamp(id, t)
	for s: Array in states:
		if owner_of.get(s[0]) == id and _car_tracks.has(s[0]):
			_car_tracks[s[0]].add(t, s[1])


## Asks the host to drive `car`; game.drive_granted follows once it agrees.
func request_drive(car: Car) -> void:
	_pending_drive = car.net_id
	if multiplayer.is_server():
		_ask_drive(car.net_id)
	else:
		_ask_drive.rpc_id(1, car.net_id)


## Got out of `car` (game.gd): it stays ours to simulate, rolling on with its passengers.
func release_drive(car: Car) -> void:
	if multiplayer.is_server():
		_release(car.net_id)
	else:
		_release.rpc_id(1, car.net_id)


@rpc("any_peer", "call_remote", "reliable")
func _ask_drive(net_id: String) -> void:
	if not multiplayer.is_server() or not cars.has(net_id):
		return
	var id := _sender()
	var d: int = driver_of[net_id]
	if (cars[net_id] as Car).is_bot():
		if id == me():
			_drive_refused(net_id, 0)
		else:
			_drive_refused.rpc_id(id, net_id, 0)
		return
	if d != 0 and d != id and players.has(d):
		if id == me():
			_drive_refused(net_id, d)
		else:
			_drive_refused.rpc_id(id, net_id, d)
		return
	_car_control.rpc(net_id, id, id)


@rpc("any_peer", "call_remote", "reliable")
func _release(net_id: String) -> void:
	if multiplayer.is_server() and cars.has(net_id) and driver_of[net_id] == _sender():
		_car_control.rpc(net_id, owner_of[net_id], 0)


@rpc("authority", "call_remote", "reliable")
func _drive_refused(net_id: String, driver_id: int) -> void:
	if _pending_drive == net_id:
		_pending_drive = ""
		message.emit("A bot drives it" if driver_id == 0 else "%s is driving it" % player_name(driver_id))


## Everyone: who simulates and who drives vehicle `net_id` now.
@rpc("authority", "call_local", "reliable")
func _car_control(net_id: String, owner_id: int, driver_id: int) -> void:
	var car: Car = cars.get(net_id)
	if car == null:
		return
	owner_of[net_id] = owner_id
	driver_of[net_id] = driver_id
	if owner_id == me() and car.remote:
		# ours now: on from its newest state (a little ahead of the one shown), at the speed it was moving
		var track: Track = _car_tracks.get(net_id)
		if track and not track.is_empty():
			car.apply_net_state(track.latest(), track.latest(), 0.0)
		car.set_remote(false)
		_car_tracks.erase(net_id)
	elif owner_id != me() and not car.remote:
		car.set_remote(true)
		_car_tracks[net_id] = Track.new(CAR_SEND_RATE)
	_show_driver(net_id)
	if driver_id == me() and _pending_drive == net_id:
		_pending_drive = ""
		game.drive_granted(car)
	elif driver_id != me() and game.driving == car:
		game.exit_car()                     # the host gave it to someone else (should not happen)


func _show_driver(net_id: String) -> void:
	var d: int = driver_of[net_id]
	(cars[net_id] as Car).show_driver(d != 0 and d != me(), player_color(d))


# ---------------------------------------------------------------- breakables

## A vehicle simulated here bent a tree or broke a prop (breakables.gd `broke`): the same everywhere.
func broke(kind: String, k: int, push: Vector3) -> void:
	if active:
		_broke.rpc(kind, k, push)


@rpc("any_peer", "call_remote", "reliable")
func _broke(kind: String, k: int, push: Vector3) -> void:
	if kind == "bend":
		game.breakables.bend_tree(k, push)
	elif kind == "break":
		game.breakables.break_prop(k, push)


# ---------------------------------------------------------------- damage

## A round of a plane simulated here hit `car` (game.gd): the peer simulating `car` takes the damage.
func hit_vehicle(car: Car, damage: float) -> void:
	var owner_id: int = owner_of.get(car.net_id, 0)
	if not active or owner_id == me():
		car.damage(damage)
	elif owner_id != 0:
		_vehicle_hit.rpc_id(owner_id, car.net_id, damage)


## (Named to sort after _refused and _register: RPC ids follow the names, and those two must keep theirs for other
## builds to be refused cleanly.)
@rpc("any_peer", "call_remote", "reliable")
func _vehicle_hit(net_id: String, damage: float) -> void:
	var car: Car = cars.get(net_id)
	if car and owner_of.get(net_id) == me():
		car.damage(clampf(damage, 0.0, 50.0))


# ---------------------------------------------------------------- water

## A packet of a fire truck simulated here hit `body` (`car` or its rear section) at `point` (global) with `impulse`,
## standing for `seconds` of the jet (game.gd): the peer simulating `car` pushes it and hoses its fire (car.gd hose).
## Batched per vehicle section for the other peers (_send_water).
func water_vehicle(car: Car, body: RigidBody3D, impulse: Vector3, point: Vector3, seconds: float) -> void:
	var owner_id: int = owner_of.get(car.net_id, 0)
	if not active or owner_id == me():
		car.hose(body, impulse, point, seconds)
	elif owner_id != 0:
		var key := "%s|%d" % [car.net_id, 0 if body == car else 1]
		var w: Array = _water_out.get(key, [owner_id, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0])
		var k := impulse.length()
		w[1] += impulse
		w[2] += body.global_transform.affine_inverse() * point * k
		w[3] += k
		w[4] += seconds
		_water_out[key] = w


func _send_water(delta: float) -> void:
	_water_t += delta
	if _water_t < 1.0 / WATER_SEND_RATE - 0.001 or _water_out.is_empty():
		return
	_water_t = 0.0
	for key: String in _water_out:
		var w: Array = _water_out[key]
		var at := key.rfind("|")
		_water_on_vehicle.rpc_id(w[0], key.left(at), int(key.substr(at + 1)), w[1], w[2] / maxf(w[3], 0.001), w[4])
	_water_out.clear()


## (The RPCs are named to sort after _refused and _register, like _vehicle_hit.)
@rpc("any_peer", "call_remote", "reliable")
func _water_on_vehicle(net_id: String, section: int, impulse: Vector3, offset: Vector3, seconds: float) -> void:
	var car: Car = cars.get(net_id)
	if car == null or owner_of.get(net_id) != me():
		return
	var body: RigidBody3D = car.trailer if section == 1 and car.trailer else car
	car.hose(body, impulse.limit_length(20000.0), body.global_transform * offset.limit_length(20.0), clampf(seconds, 0.0, 1.0))


## A packet of a fire truck simulated here hit the remote player `collider` belongs to (game.gd): their own peer
## shoves them by `dv` (m/s).
func water_player(collider: Object, dv: Vector3) -> void:
	for id: int in _remotes:
		if (_remotes[id] as RemotePlayer).collider == collider:
			_water_on_player.rpc_id(id, dv)
			return


@rpc("any_peer", "call_remote", "unreliable")
func _water_on_player(dv: Vector3) -> void:
	game.water_push(dv.limit_length(5.0))


# ---------------------------------------------------------------- states

func _physics_process(_delta: float) -> void:
	if not active:
		return
	var now := _now()
	_after_hitch = now - _last_tick > HITCH
	_last_tick = now
	multiplayer.poll()                      # the states that came since the frame began, not next frame
	_after_hitch = false
	if multiplayer.is_server() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.flush()   # the states relayed between clients
	_play_back()


## Sender: our player's state every tick, those of the vehicles simulated here CAR_SEND_RATE times a second (at rest:
## every IDLE_SEND_EVERY s; bots gliding far from every player: every FAR_SEND_EVERY sends), straight onto the network.
func _send(delta: float) -> void:
	if not active:
		return
	var t := _now()
	_send_t += delta
	if _send_t >= 1.0 / PLAYER_SEND_RATE - 0.001:
		_send_t = 0.0
		if not dedicated:
			_player_state.rpc(t, game.net_player_state())
	_car_send_t += delta
	if _car_send_t >= 1.0 / CAR_SEND_RATE - 0.001:
		_idle_t += _car_send_t
		_car_send_t = 0.0
		var idle := _idle_t >= IDLE_SEND_EVERY
		if idle:
			_idle_t = 0.0
		_car_sends += 1
		var far_turn := _car_sends % FAR_SEND_EVERY == 0
		var states := []
		for net_id: String in cars:
			var car: Car = cars[net_id]
			if car.remote:
				continue
			if car.pilot != null and car.pilot.gliding and not (idle or far_turn):
				continue
			var s := car.net_state()
			var switches := [s[4], s[5], s[6]]      # flags, indicator, health
			# (a bot gliding far from the players is frozen: no velocity, yet it moves)
			var moving := car.linear_velocity.length_squared() > 0.0025 or car.angular_velocity.length_squared() > 0.0025 \
					or (car.pilot != null and not car.stowed)
			if idle or moving or car.driving or _sent.get(net_id) != switches:
				states.append([net_id, s])
				_sent[net_id] = switches
		if not states.is_empty():
			_cars_state.rpc(t, states)
	_send_water(delta)
	_train_send_t += delta
	var tt: Node = game.traffic.trains
	var every := 1.0 / TRAIN_SEND_RATE if tt.running else 1.0   # stopped: the stowed states, for any peer that missed one
	if multiplayer.is_server() and _train_send_t >= every - 0.001:
		_train_send_t = 0.0
		if not tt.trains.is_empty():
			var states := []
			for tr: Node3D in tt.trains:
				states.append([tr.net_id, tt.service_index(tr), tr.net_state()])
			_trains_state.rpc(clock(), states)
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer:
		peer.host.flush()                   # else ENet sends them at the next poll, a frame later


## Poses the vehicles simulated elsewhere, then the remote players (who may stand in them).
func _play_back() -> void:
	var now := _now()
	var dt := get_physics_process_delta_time()
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else game.player.global_position
	var tick := Engine.get_physics_frames()
	for net_id: String in _car_tracks:
		var track: Track = _car_tracks[net_id]
		if not track.is_empty():
			var car := cars[net_id] as Car
			car.update_remote_lod(eye)      # far from the eye: frozen STATIC, no cosmetic tick (car.gd)
			if car.is_remote_asleep() and (tick + car.get_instance_id()) % REMOTE_SLEEP_EVERY != 0:
				continue                    # asleep and far: it moves every REMOTE_SLEEP_EVERY ticks, like a gliding bot
			var s := track.at(_playback_time(track, owner_of[net_id], now, dt))
			car.apply_net_state(s[0], s[1], s[2])
	for id: int in _player_tracks:
		var track: Track = _player_tracks[id]
		if not track.is_empty():
			var s := track.at(_playback_time(track, id, now, dt))
			_pose_remote(id, s[0], s[1], s[2])


## The time on peer `id`'s clock to show `track` at: its delay eased towards one interval between states plus how
## late they arrive, so that the next state is there before it is needed.
func _playback_time(track: Track, id: int, now: float, dt: float) -> float:
	var target := clampf(track.interval + _late.get(id, 0.0) + DELAY_MARGIN, MIN_DELAY, MAX_DELAY)
	if track.delay < 0.0:
		track.delay = target
	elif target > track.delay:
		track.delay = minf(track.delay + DELAY_UP * dt, target)
	else:
		track.delay = maxf(track.delay - DELAY_DOWN * dt, target)
	return now - _offsets.get(id, 0.0) - track.delay


## Clock offset of peer `id` from a state it sent at its time `t`: the quickest arrival so far, creeping up slowly
## so the estimate follows clock drift. And how much later than that its states arrive: the latest of the recent
## ones, forgotten over LATE_MEMORY, but not those that waited for us through a stall of ours (a hitch here is not
## the network's doing, and would hold playback back for seconds).
func _stamp(id: int, t: float) -> void:
	var now := _now()
	var since: float = now - _stamped.get(id, now)
	_stamped[id] = now
	var off := now - t
	_offsets[id] = minf(_offsets.get(id, INF) + CLOCK_CREEP * since, off)
	var late: float = _late.get(id, 0.0) * exp(-since / LATE_MEMORY)
	_late[id] = late if _after_hitch else maxf(late, off - _offsets[id])


func _now() -> float:
	return Time.get_ticks_usec() / 1e6


## The F3 overlay (game.gd): frame rate, and for each other player the round trip to them, how late their states
## arrive and how late they are shown.
func debug_text() -> String:
	var text := "%d fps" % Engine.get_frames_per_second()
	if not active:
		return text
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for id: int in _player_tracks:
		var track: Track = _player_tracks[id]
		var via := id if multiplayer.is_server() else 1      # clients reach each other through the host
		var link: ENetPacketPeer = peer.get_peer(via) if peer else null
		var rtt := link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if link else -1.0
		var ahead := 0.0
		if not track.is_empty():
			ahead = track.times[-1] - (_now() - _offsets.get(id, 0.0) - track.delay)
		text += "\n%s: ping %d ms%s · late %d ms · shown %d ms late (+ half the ping) · buffer %d ms · starved %d" % [
				player_name(id), rtt, "" if via == id else " (host)", roundi(_late.get(id, 0.0) * 1000.0),
				roundi(track.delay * 1000.0), roundi(ahead * 1000.0), track.starved]
	return text


## What the host shows at the top right: how to join.
func lan_label() -> String:
	var ips := LanDiscovery.lan_addresses()
	var where := "  /  ".join(Array(ips).map(func(ip: String) -> String: return "%s:%d" % [ip, port])) if not ips.is_empty() \
			else "no network found (port %d)" % port
	return "LAN game  ·  %s  ·  %d player%s" % [where, players.size(), "" if players.size() == 1 else "s"]
