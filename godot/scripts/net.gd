extends Node
## LAN games (game.gd creates it as Main/Net: its RPCs need the same path on every peer). ENet through Godot's
## high-level multiplayer, the host being the server; the other peers reach each other through it.
## - Players: each peer sends its player SEND_RATE times a second (game.net_player_state: position, body facing,
##   driving or not). A player standing in a vehicle sends its position in that vehicle's frame, so on every screen it
##   stays inside it however that vehicle's motion is smoothed there. Others show it as a remote_player.gd, which the
##   vehicles they simulate collide with.
## - Vehicles: each one is simulated by a single peer, its owner: the one who parked it, then whoever drives it (the
##   host takes over the vehicles of a player who leaves). The other peers pose a frozen copy from the owner's states
##   (car.gd set_remote / apply_net_state). Getting in asks the host, which hands the vehicle to the new driver unless
##   someone else drives it.
## - States are played back INTERP_DELAY late, between the two received around that time on the sender's clock
##   (its offset from ours estimated from the quickest arrivals).
## - Trees bent and props broken by a vehicle simulated here (breakables.gd `broke`) bend and break everywhere.
## - The host announces the game on the LAN (lan_discovery.gd) and sends newcomers the players, the vehicles, and the
##   trees bent and props knocked down at that moment (breakables.gd net_snapshot).

const LanDiscovery = preload("res://scripts/lan_discovery.gd")
const RemotePlayer = preload("res://scripts/remote_player.gd")
const Car = preload("res://scripts/car.gd")

signal joined                               # client: the host welcomed us (the players, vehicles... are here)
signal failed(reason: String)               # client: could not join
signal ended(reason: String)                # client: the host closed the game
signal message(text: String)                # someone joined or left, a vehicle is taken...

const PORT := 7777                          # the host tries the next ones when it is taken
const PORT_TRIES := 10
const MAX_PLAYERS := 8
const PROTOCOL := 2                         # bump when the messages change: other versions are refused
const SEND_RATE := 30.0                     # states per second
const IDLE_SEND_EVERY := 0.5                # s, states of vehicles at rest
const INTERP_DELAY := 0.1                   # s
const CONNECT_TIMEOUT := 6.0                # s
const DEFAULT_COLOR := Color(1, 0.55, 0.2)

var game: Node3D                            # game.gd
var discovery: LanDiscovery
var active := false                         # hosting, or welcomed by a host
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
var _sent := {}                             # net id -> switches (flags, indicator) last sent
var _next_car := 0
var _send_t := 0.0
var _idle_t := 0.0
var _pending_drive := ""                    # net id of the vehicle we asked to drive
var _connect_t := -1.0                      # s since connecting, -1 when not waiting


## Recent states of one remote player or vehicle, stamped with the sender's clock.
class Track:
	var times := PackedFloat64Array()
	var states := []

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

	## [older state, newer state, weight] around time t; outside the states, the nearest one alone.
	func at(t: float) -> Array:
		if t >= times[-1]:
			return [states[-1], states[-1], 0.0]
		for i in range(times.size() - 1, 0, -1):
			if times[i - 1] <= t:
				return [states[i - 1], states[i], (t - times[i - 1]) / (times[i] - times[i - 1])]
		return [states[0], states[0], 0.0]


func _ready() -> void:
	process_physics_priority = -10          # remote vehicles move before the player follows the one it stands in
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func me() -> int:
	return multiplayer.get_unique_id()


## Starts a server on PORT (or the next free port) and announces it on the LAN. Returns an error message, or "".
func host(nickname: String, color: Color) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for k in PORT_TRIES:
		err = peer.create_server(PORT + k, MAX_PLAYERS - 1)
		if err == OK:
			port = PORT + k
			break
	if err != OK:
		return "Could not start the game: ports %d to %d are all taken." % [PORT, PORT + PORT_TRIES - 1]
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": nickname, "color": color}}
	active = true
	discovery.start_beacon(func() -> Dictionary:
		return {"port": port, "name": players[1]["name"], "players": players.size(), "max": MAX_PLAYERS,
				"version": PROTOCOL})
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
	for id: int in _remotes.keys():
		_remove_remote(id)
	players.clear()
	cars.clear()
	owner_of.clear()
	driver_of.clear()
	_car_tracks.clear()


func _process(delta: float) -> void:
	if _connect_t >= 0.0:
		_connect_t += delta
		if _connect_t > CONNECT_TIMEOUT:
			_fail("No answer from %s:%d. Check the address, and that the host's firewall lets the game through." % [
					host_address, port])


func _fail(reason: String) -> void:
	leave()
	failed.emit(reason)


func _on_connected() -> void:
	_register.rpc_id(1, PROTOCOL, _profile["name"], _profile["color"])


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
	if protocol != PROTOCOL:
		_refused.rpc_id(id, "The host runs another version of the game.")
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	nickname = nickname.strip_edges().left(20)
	players[id] = {"name": nickname if nickname != "" else "Player", "color": color}
	var snapshot := []
	for net_id: String in cars:
		snapshot.append([net_id, cars[net_id].model_name, owner_of[net_id], driver_of[net_id], cars[net_id].net_state()])
	_welcome.rpc_id(id, players, snapshot, game.breakables.net_snapshot())
	_player_joined.rpc(id, players[id])
	_add_remote(id)
	message.emit("%s joined the game" % players[id]["name"])


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	_fail(reason)


## Client: the host's players, vehicles, and what is bent or knocked over there.
@rpc("authority", "call_remote", "reliable")
func _welcome(all: Dictionary, snapshot: Array, broken: Array) -> void:
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
	_player_tracks[id] = Track.new()


func _remove_remote(id: int) -> void:
	if _remotes.has(id):
		(_remotes[id] as Node).queue_free()
	_remotes.erase(id)
	_player_tracks.erase(id)
	_offsets.erase(id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_state(t: float, s: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _player_tracks.has(id):
		_stamp(id, t)
		_player_tracks[id].add(t, s)


## Shows remote player `id` from its states around now: [vehicle net id or "", section (0 front, 1 rear), position
## (in that section's frame, else global), body yaw (relative to the section's), flags (1 hidden)].
func _pose_remote(id: int, a: Array, b: Array, w: float) -> void:
	var r: RemotePlayer = _remotes[id]
	if a[0] != b[0]:                        # got in or out of a vehicle in between: no blending across frames
		a = b
	var pos: Vector3 = (a[2] as Vector3).lerp(b[2], w)
	var yaw := lerp_angle(a[3], b[3], w)
	var shown: bool = b[4] & 1 == 0
	var car: Car = null
	if b[0] != "":
		car = cars.get(b[0])
		if car == null:
			shown = false
		else:
			var section: Node3D = car.trailer if b[1] == 1 and car.trailer else car
			pos = section.global_transform * pos
			yaw += section.global_rotation.y
	r.visible = shown
	r.show_at(Transform3D(Basis.IDENTITY, pos), yaw)
	r.update_collision(shown, car, game.cars)


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
		_car_tracks[net_id] = Track.new()
	car.apply_net_state(state, state, 0.0)
	_show_driver(net_id)


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
		message.emit("%s is driving it" % player_name(driver_id))


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
		_car_tracks[net_id] = Track.new()
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


# ---------------------------------------------------------------- states

func _physics_process(delta: float) -> void:
	if not active:
		return
	_play_back()
	_send_t += delta
	if _send_t < 1.0 / SEND_RATE - 0.001:
		return
	_idle_t += _send_t
	_send_t = 0.0
	var t := _now()
	_player_state.rpc(t, game.net_player_state())
	var idle := _idle_t >= IDLE_SEND_EVERY
	if idle:
		_idle_t = 0.0
	var states := []
	for net_id: String in cars:
		var car: Car = cars[net_id]
		if car.remote:
			continue
		var s := car.net_state()
		var switches := [s[4], s[5]]
		var moving := car.linear_velocity.length_squared() > 0.0025 or car.angular_velocity.length_squared() > 0.0025
		if idle or moving or car.driving or _sent.get(net_id) != switches:
			states.append([net_id, s])
			_sent[net_id] = switches
	if not states.is_empty():
		_cars_state.rpc(t, states)


## Poses the vehicles simulated elsewhere, then the remote players (who may stand in them).
func _play_back() -> void:
	var now := _now()
	for net_id: String in _car_tracks:
		var track: Track = _car_tracks[net_id]
		if not track.is_empty():
			var s := track.at(now - _offsets.get(owner_of[net_id], 0.0) - INTERP_DELAY)
			(cars[net_id] as Car).apply_net_state(s[0], s[1], s[2])
	for id: int in _player_tracks:
		var track: Track = _player_tracks[id]
		if not track.is_empty():
			var s := track.at(now - _offsets.get(id, 0.0) - INTERP_DELAY)
			_pose_remote(id, s[0], s[1], s[2])


## Clock offset of peer `id` from a state it sent at its time `t`: the quickest arrival so far, creeping up slowly
## so the estimate follows clock drift.
func _stamp(id: int, t: float) -> void:
	var off := _now() - t
	_offsets[id] = minf(_offsets.get(id, INF) + 0.0002, off)


func _now() -> float:
	return Time.get_ticks_usec() / 1e6


## What the host shows at the top right: how to join.
func lan_label() -> String:
	var ips := LanDiscovery.lan_addresses()
	var where := "  /  ".join(Array(ips).map(func(ip: String) -> String: return "%s:%d" % [ip, port])) if not ips.is_empty() \
			else "no network found (port %d)" % port
	return "LAN game  ·  %s  ·  %d player%s" % [where, players.size(), "" if players.size() == 1 else "s"]
