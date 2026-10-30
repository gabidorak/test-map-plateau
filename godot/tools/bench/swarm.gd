extends SceneTree
## Load generator of the player capacity benchmark (tools/bench/README.md): one process playing many PTA Online players
## over the real protocol, without the game: each bot is a branch of the tree with its own SceneMultiplayer and ENet
## client, holding stub nodes at the real paths (Main/Net, Main/Mode/Shop...). The stubs' RPCs are generated at start
## from the real scripts' @rpc lines, as the node checksum and method ids need them the same.
## A bot joins, logs in, gets its car out at a garage, then drives up and down a route (make_routes.gd) sending what a
## driving player sends: player states SEATED_RATE times a second, vehicle states CAR_RATE times a second.
## Every WINDOW s one line "SWARM {json}": what the bots here received, and how long other bots' states took through
## the server (states are stamped with the system clock, so only meaningful with all the swarm on one machine).
##
## godot --headless --path godot --script res://tools/bench/swarm.gd -- --server=HOST:PORT --tokens=tokens.json
##     --routes=routes.json --bots=FIRST,COUNT --start=UNIX --stages=4,8,16 --hold=60 [--build=COMMIT] [--walk=SHARE]
##     [--net=PATH]
## --bots: which tokens of the file are this process's. --start and --stages say when each bot joins: the bots of stage k
## within the first JOIN_SPREAD share of it. --build: the server's commit stamp ("": a local export).

const NetCodec = preload("res://scripts/net_codec.gd")
const OLD_PLAYER_RATE := 60.0               # a server before PROTOCOL 18
const SEATED_RATE := 5.0                    # a driving player's states (net.gd SEATED_SEND_EVERY)
const CAR_RATE := 30.0
const WINDOW := 5.0                         # s
const JOIN_SPREAD := 0.4
const HIST_MS := 1000
const STUBS := {                            # path under Main -> the real script
	"Net": "res://scripts/net.gd",
	"Economy": "res://scripts/economy.gd",
	"Races": "res://scripts/races.gd",
	"Mode": "res://scripts/modes/online_mode.gd",
	"Mode/Shop": "res://scripts/online/shop.gd",
	"Mode/BusJob": "res://scripts/online/bus_job.gd",
	"Mode/Stunts": "res://scripts/online/stunts.gd",
	"Mode/Fires": "res://scripts/online/fires.gd",
	"Mode/FireJob": "res://scripts/online/fire_job.gd",
}
const FAST := {                             # RPCs handled without building an args array
	"_player_state": "swarm.got_player(a0)",
	"_cars_state": "swarm.got_cars()",
	"_relayed": "swarm.got_relayed(a0)",
	"_trains_state": "swarm.got_trains(a1)",
	"_signal_clock": "pass",
	"_ping_list": "pass",
}

var host := ""
var port := 0
var build := 0
var walk_share := 0.0
var routes: Array = []
var bots: Array = []
var waiting: Array = []                     # bots not joined yet: [unix time, Bot], soonest first
var stub_scripts := {}
var player_rate := 30.0                     # on foot, net.gd PLAYER_SEND_RATE
var relays := false                         # the real net.gd has _relayed: states in bytes, to the server alone
var garages: Array = []                     # the public garages: {"id", "terminal"}

# this window
var rx_player := 0
var rx_cars := 0
var rx_relay_bytes := 0
var rx_train_bytes := 0
var hist := PackedInt32Array()
var kicked := 0
var failed := 0
var frames := 0
var slow_frames := 0
var _window_t := 0.0
var _last_usec := 0


func _initialize() -> void:
	_setup.call_deferred()                  # (the root isn't in the tree yet)


func _setup() -> void:
	Engine.max_fps = 250
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var where: PackedStringArray = args["server"].rsplit(":", true, 1)
	host = where[0]
	port = int(where[1])
	var net_path: String = args.get("net", "res://scripts/net.gd")    # (another build's net.gd, to test an older server)
	var net_source := FileAccess.get_file_as_string(net_path)
	var protocol := int(RegEx.create_from_string("const PROTOCOL := (\\d+)").search(net_source).get_string(1))
	build = hash([protocol, str(args.get("build", ""))])   # the same as net.gd build_id()
	walk_share = float(args.get("walk", "0"))
	relays = net_source.contains("func _relayed(")
	player_rate = float(RegEx.create_from_string("const PLAYER_SEND_RATE := ([\\d.]+)").search(net_source).get_string(1))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args["routes"]))
	routes = world["routes"]
	for g: Dictionary in world["garages"]:
		garages.append({"id": g["id"], "terminal": Vector3(g["x"], g["z"] + 0.1, -g["y"])})
	var tokens: Array = JSON.parse_string(FileAccess.get_file_as_string(args["tokens"]))
	hist.resize(HIST_MS + 1)
	for path: String in STUBS:
		stub_scripts[path] = _stub_script(net_path if path == "Net" else STUBS[path])
	var first_count: PackedStringArray = args["bots"].split(",")
	var stages: PackedStringArray = args["stages"].split(",")
	var start := float(args["start"])
	var hold := float(args["hold"])
	var before := 0
	for k in stages.size():
		var upto := int(stages[k])
		for i in range(before, upto):
			if i >= int(first_count[0]) and i < int(first_count[0]) + int(first_count[1]):
				var at := start + k * hold + hold * JOIN_SPREAD * float(i - before) / maxi(upto - before, 1)
				waiting.append([at, _make_bot(i, tokens[i])])
		before = upto
	_last_usec = Time.get_ticks_usec()


## The script of a stub of real script `path`: the same RPCs, each passing on to its bot.
func _stub_script(path: String) -> GDScript:
	var source := "extends Node\nvar bot\nvar swarm\n"
	var src := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string("(?m)^@rpc\\(([^)]*)\\)\\s*\\n(?:\\s*##.*\\n)*func\\s+(\\w+)\\(([^)]*)\\)")
	var count := 0
	for m in re.search_all(src):
		var params := m.get_string(3).strip_edges()
		var n := 0 if params == "" else params.split(",").size()
		var names := PackedStringArray()
		for i in n:
			names.append("a%d = null" % i)
		var fn := m.get_string(2)
		source += "@rpc(%s)\nfunc %s(%s):\n" % [m.get_string(1), fn, ", ".join(names)]
		var list := PackedStringArray()
		for i in n:
			list.append("a%d" % i)
		source += "\t%s\n" % (FAST[fn] if FAST.has(fn) else "bot.on(&\"%s\", [%s])" % [fn, ", ".join(list)])
		count += 1
	if src.count("@rpc(") != count:
		push_error("%s: %d @rpc lines, %d understood" % [path, src.count("@rpc("), count])
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		push_error("Stub of %s does not compile" % path)
	return script


func _make_bot(index: int, account: Dictionary) -> Bot:
	var b := Bot.new()
	b.swarm = self
	b.index = index
	b.token = account["token"]
	b.account = account["name"]
	b.name = "Bot%d" % index
	root.add_child(b)
	var main := Node.new()
	main.name = "Main"
	b.add_child(main)
	for path: String in STUBS:
		var node := Node.new()
		node.set_script(stub_scripts[path])
		node.name = path.get_file()
		node.set("bot", b)
		node.set("swarm", self)
		var parent: Node = main if not path.contains("/") else main.get_node(path.get_base_dir())
		parent.add_child(node)
		b.stubs[path] = node
	set_multiplayer(SceneMultiplayer.new(), b.get_path())
	return b


func got_player(t: Variant) -> void:
	rx_player += 1
	hist[clampi(int((Time.get_unix_time_from_system() - t) * 1000.0), 0, HIST_MS)] += 1


func got_cars() -> void:
	rx_cars += 1


## (net.gd _relayed.) Only the fresh ones say how long they took: the others waited for their turn on the server.
func got_relayed(data: PackedByteArray) -> void:
	var now := Time.get_unix_time_from_system()
	rx_relay_bytes += data.size()
	var at := 0
	while at + 14 <= data.size():
		var head := data.decode_u16(at + 12)
		var end := at + 14 + (head & 0x3fff)
		if head & 0x4000 and data.decode_u32(at) != 1:    # (the server's clock isn't the system's)
			hist[clampi(int((now - data.decode_double(at + 4)) * 1000.0), 0, HIST_MS)] += 1
		at += 14
		var count := 0
		while at < end:
			at += data[at]
			count += 1
		if head & 0x8000:
			rx_player += count
		else:
			rx_cars += count
		at = end


func got_trains(data: Variant) -> void:
	rx_train_bytes += var_to_bytes(data).size()


func _process(delta: float) -> bool:
	var now := Time.get_unix_time_from_system()
	while not waiting.is_empty() and waiting[0][0] <= now:
		var b: Bot = waiting.pop_front()[1]
		b.connect_now()
		bots.append(b)
	for b: Bot in bots:
		b.step(now)
	frames += 1
	var usec := Time.get_ticks_usec()
	if usec - _last_usec > 12000:
		slow_frames += 1
	_last_usec = usec
	_window_t += delta
	if _window_t >= WINDOW:
		_report(now)
		_window_t = 0.0
	return false


func _report(now: float) -> void:
	var driving := 0
	var rtt := 0.0
	var linked := 0
	var rx_bytes := 0.0
	for b: Bot in bots:
		if b.state == Bot.DRIVING or b.state == Bot.WALKING:
			driving += 1
		var peer: ENetMultiplayerPeer = b.peer
		if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			var link := peer.get_peer(1)
			if link:
				rtt += link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
				linked += 1
			rx_bytes += peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var sparse := {}
	for i in hist.size():
		if hist[i] > 0:
			sparse[i] = hist[i]
	print("SWARM " + JSON.stringify({"t": now, "bots": bots.size(), "driving": driving, "linked": linked,
			"rtt_sum": rtt, "rx_player": rx_player, "rx_cars": rx_cars, "rx_kb": rx_bytes / 1024.0, "relay_kb": rx_relay_bytes / 1024.0, "train_kb": rx_train_bytes / 1024.0, "hist": sparse,
			"kicked": kicked, "failed": failed, "frames": frames, "slow": slow_frames, "wall": _window_t,
			"waiting": waiting.size()}))
	hist.fill(0)
	rx_player = 0
	rx_cars = 0
	rx_relay_bytes = 0
	rx_train_bytes = 0
	frames = 0
	slow_frames = 0
	kicked = 0
	failed = 0


## One player.
class Bot extends Node:
	enum { IDLE, JOINING, LOGIN, GARAGE, SPAWNED, DRIVING, WALKING, GONE }
	var swarm: SceneTree
	var index := 0
	var token := ""
	var account := ""
	var stubs := {}
	var state := IDLE
	var peer: ENetMultiplayerPeer
	var gid := ""
	var terminal := Vector3.ZERO
	var my_car := ""
	var health := 100.0
	var route: Array = []
	var along := 0.0                        # m along the route
	var direction := 1.0
	var pos := Vector3.ZERO
	var yaw := 0.0
	var _player_t := 0.0                    # unix time of the next state
	var _car_t := 0.0
	var _last := 0.0
	var _retry_t := 0.0
	var _garage_tries := 0
	var _empty_xf := Transform3D()

	func connect_now() -> void:
		peer = ENetMultiplayerPeer.new()
		if peer.create_client(swarm.host, swarm.port) != OK:
			swarm.failed += 1
			state = GONE
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_lost.bind("no connection"))
		multiplayer.server_disconnected.connect(_on_lost.bind("server disconnected"))
		state = JOINING

	func _on_connected() -> void:
		stubs["Net"].rpc_id(1, &"_register", swarm.build, account, Color(0.2, 0.6, 1.0))

	func _on_lost(why: String) -> void:
		if state != GONE:
			print("BOT %d lost: %s (was in state %d)" % [index, why, state])
		swarm.failed += 1
		state = GONE

	func on(fn: StringName, a: Array) -> void:
		match fn:
			&"_welcome":
				state = LOGIN
				stubs["Economy"].rpc_id(1, &"_login", token)
			&"_account":
				_go_to_garage()
			&"_kicked":
				print("BOT %d kicked: %s" % [index, a[1]])
				swarm.kicked += 1
			&"_refused":
				print("BOT %d refused: %s" % [index, a[0]])
				swarm.kicked += 1
			&"_c_garage":
				_garage_list(a[0], a[1], a[2])
			&"_c_result":
				if not a[0]:
					_retry_t = Time.get_unix_time_from_system() + 2.0
			&"_c_mine":
				my_car = a[0]
				state = SPAWNED
				stubs["Net"].rpc_id(1, &"_ask_drive", my_car)
			&"_spawn_car":
				health = a[2][6]
			&"_car_control":
				if a[0] == my_car and a[1] == multiplayer.get_unique_id() and a[2] == multiplayer.get_unique_id():
					_start_driving()

	func _go_to_garage() -> void:
		state = GARAGE
		var g: Dictionary = swarm.garages[index % swarm.garages.size()]
		gid = g["id"]
		terminal = g["terminal"]
		pos = terminal
		_retry_t = Time.get_unix_time_from_system() + 1.0   # (the server judges range from our newest state)
		_last = 0.0

	func _garage_list(g: String, entries: Array, message: String) -> void:
		for e: Dictionary in entries:
			if e.has("vehicle") and int(e["vehicle"]) >= 0 and e.get("model", "") != "":
				stubs["Mode"].rpc_id(1, &"_h_spawn", g, int(e["vehicle"]), str(e["model"]))
				return
		if message != "":
			print("BOT %d at %s: %s" % [index, g, message])
		_retry_t = Time.get_unix_time_from_system() + 3.0

	func _start_driving() -> void:
		route = swarm.routes[index * 7 % swarm.routes.size()]
		along = randf() * (route.size() - 2) * 10.0
		direction = 1.0 if index % 2 == 0 else -1.0
		state = DRIVING if float(index % 100) / 100.0 >= swarm.walk_share else WALKING
		_last = Time.get_unix_time_from_system()
		_player_t = _last + randf() / _player_rate()
		_car_t = _last + randf() / CAR_RATE

	func step(now: float) -> void:
		match state:
			GARAGE:
				_player_at(now, pos, 0.0, 0)
				if _retry_t > 0.0 and now >= _retry_t:
					_retry_t = 0.0
					_garage_tries += 1
					stubs["Mode"].rpc_id(1, &"_h_open", gid)
			DRIVING, WALKING:
				var dt := now - _last
				_last = now
				_drive(dt)
				var sent := false
				if now >= _player_t:
					_player_t += 1.0 / _player_rate()
					if _player_t < now:
						_player_t = now + 1.0 / _player_rate()
					_send_player(now, pos, yaw, 1 if state == DRIVING else 0)
					sent = true
				if state == DRIVING and now >= _car_t:
					_car_t += 1.0 / CAR_RATE
					if _car_t < now:
						_car_t = now + 1.0 / CAR_RATE
					var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 0.5)
					var car_state := [xf, _empty_xf, 0.0, 0.5, 2, 0, health]
					if swarm.relays:
						stubs["Net"].rpc_id(1, &"_cars_state", now, NetCodec.car(my_car, car_state))
					else:
						stubs["Net"].rpc(&"_cars_state", now, [[my_car, car_state]])
					sent = true
				if sent:
					peer.host.flush()

	## As net.gd _send: in bytes to the server alone where it relays them itself (PROTOCOL 18), else one copy per other player.
	func _send_player(t: float, at: Vector3, y: float, flags: int) -> void:
		var s := ["", 0, at, y, flags]
		if swarm.relays:
			stubs["Net"].rpc_id(1, &"_player_state", t, NetCodec.player(s))
		else:
			stubs["Net"].rpc(&"_player_state", t, s)

	func _player_rate() -> float:
		if not swarm.relays:
			return OLD_PLAYER_RATE
		return SEATED_RATE if state == DRIVING else swarm.player_rate

	func _player_at(now: float, at: Vector3, y: float, flags: int) -> void:
		if now >= _player_t:
			_player_t = now + 1.0 / _player_rate()
			_send_player(now, at, y, flags)
			peer.host.flush()

	func _drive(dt: float) -> void:
		var n: int = route.size() - 1
		var i := clampi(int(along / 10.0), 0, n - 1)
		var a: Array = route[i]
		var b: Array = route[i + 1]
		var speed: float = (a[3] as float) * (1.0 if state == DRIVING else 0.2)
		along += direction * speed * dt
		if along <= 0.0 or along >= n * 10.0:
			direction = -direction
			along = clampf(along, 0.0, n * 10.0)
		var w := along / 10.0 - i
		var dir := Vector3(b[0] - a[0], 0.0, -(b[1] - a[1])) * direction
		pos = Vector3(lerpf(a[0], b[0], w), lerpf(a[2], b[2], w) + 0.1, -lerpf(a[1], b[1], w))
		yaw = atan2(dir.x, dir.z)
