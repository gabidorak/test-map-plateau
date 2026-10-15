extends Node
## Races (game.gd makes it as Main/Races: its RPCs need the same path on every peer), from world/races.json
## (pipeline/plateau/races.py, pipeline/races.toml):
## - The campus lap: from its start circle in the big parking of Polytechnique by the lake, round the campus through
##   its checkpoints and back into the circle, in any vehicle but the planes, alone or with the other drivers in the
##   circle.
## - The bus race: from the stop ENSTA - Les Joncherettes (towards Polytechnique) to Place Marguerite Perey, alone, in
##   a 12 m or an 18 m bus (a leaderboard each), staying on the road: once a wheel is over OFF_DIST m off the road
##   surface (the ground map's carriageways and roadside asphalt, bus bays included) for over OFF_TIME s on end, or
##   over OFF_FAR m off it at all, the bus is out.
## Each start circle glows for everyone; a driver in one is offered to race: the race key alone, the invite key with the
## other drivers in the circle (they get an invitation: the race key joins, the invite key declines; the race starts
## once all have answered, after INVITE_TIME s, or when the one who invited presses the race key). A 3-2-1 countdown
## holds the vehicles still (car.gd `hold`), then the clock runs from the same GO on every screen (the game's shared
## clock, net.gd clock()). The checkpoints show only to their racer (the next one bright, the one after dim, an arrow on
## the screen pointing to the next; the finish chequered). Getting out of the vehicle, or the race key twice, gives up.
## - The host (or the solo game, or the dedicated server) runs the races: it starts them, takes each racer's time
##   (timed on the racer's screen, at the tick its vehicle got into the finish circle with every checkpoint passed),
##   ends a race once every racer is in or out (or FINISH_WAIT s after the first finished), sends the results to the
##   racers and says them in every player's chat.
## - Records: the host keeps each player's best time per board (by nickname) in a JSON file: RECORDS, in user://, which
##   on the VPS server (server/) is in the container's /data volume, so it outlives restarts and updates; --records=PATH
##   or PLATEAU_RECORDS overrides it. It is written to a temporary file first, then renamed over the old one. Every
##   player gets the top BOARD_ROWS of each board (newcomers too); the leaderboards stand next to the start circles.
## Positions are pipeline x/y (x east, y north; Godot = (x, height, -y)).

const Car = preload("res://scripts/car.gd")
const Biplane = preload("res://scripts/plane.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Marks = preload("res://scripts/race_marks.gd")
const RaceHud = preload("res://scripts/race_hud.gd")

enum { IDLE, INVITED, LOBBY, COUNTDOWN, RACING, FINISHED }

const RACES := "res://world/races.json"
const RECORDS := "user://race_records.json"
const BUSES := ["bus-idfm", "bus-idfm-artic"]
const COUNTDOWN_TIME := 3.0                 # s of 3, 2, 1
const LEAD := 0.6                           # s more before it: the start reaching every racer
const INVITE_TIME := 15.0                   # s an invitation waits for its answers
const FINISH_WAIT := 90.0                   # s the others have once the first racer finished
const MAX_RACE := 1200.0                    # s a race may last
const BOARD_ROWS := 10                      # rows on a leaderboard
const KEEP := 100                           # best times kept per board
const OFF_DIST := 3.0                       # m off the road a bus's wheel may go any time (bus race)...
const OFF_TIME := 3.0                       # ...and further for this many seconds on end
const OFF_FAR := 12.0                       # m off it: out at once
const OFF_EVERY := 0.1                      # s between road checks
const OFF_RINGS := [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 15.0]   # m searched round a wheel
const GIVE_UP_TIME := 3.0                   # s to press the race key again to give up
const MIN_TIME_SPEED := 60.0                # m/s: a time shorter than the route at this speed is refused
const START_COLOURS := {"lap": Color(0.3, 0.9, 1.0), "bus": Color(0.4, 1.0, 0.5)}
const GATE := Color(1.0, 0.8, 0.2)
const GATE_HEIGHT := 6.0                    # m, the checkpoints' walls of light
const START_HEIGHT := 1.2                   # m, the start circles'
const GOLD := Color(1.0, 0.82, 0.3)
const RATE := 22050                         # Hz, the beeps

var game: Node3D                            # game.gd
var defs: Array = []                        # races.json "races"
var boards := {}                            # board key -> top rows [name, time, model], as the host sent them
var records_path := RECORDS
var hosting := false                        # this peer runs the races (solo, host, dedicated server)
var hud: RaceHud
var state := IDLE
var run := -1                               # the race we are in (or invited to, or starting: -1 until the host says)
var race := -1                              # its index in defs
var vehicle: Car                            # the vehicle raced
var next_cp := 0                            # checkpoints passed
var go_at := 0.0                            # GO, on the shared clock
var finish_time := 0.0
var racers: Array = []                      # peer ids in our race
var off_road := 0.0                         # s on end a wheel has been over OFF_DIST m off the road (bus race)
var off_dist := 0.0                         # m, the furthest wheel's distance off it at the last check

var _invite_from := 0
var _invite_until := 0.0                    # our clock
var _waiting: Array = []                    # names of the invited who have not answered (we invited them)
var _inviter := false
var _progress := {}                         # peer -> checkpoints passed (our race)
var _results := {}                          # peer -> [what happened ("done" or why out), time, place] (our race)
var _gates: Array = []                      # marks of the next checkpoint and the one after
var _circles := {}                          # race id -> start circle label (Label3D)
var _boards3d := {}                         # race id -> leaderboard (Node3D)
var _give_up_t := 0.0
var _off_t := 0.0
var _finished_t := 0.0                      # s since we finished or went out
var _last_count := -1
var _road := PackedByteArray()              # per ground piece: 1 where a bus is on the road
var _audio: AudioStreamPlayer
var _sounds := {}

# host
var _records := {}                          # board key -> [[name, time, model, unix time]], best first
var _runs := {}                             # race run id -> its state (see _h_start)
var _next_run := 0


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RACES)) if FileAccess.file_exists(RACES) else null
	if data is Dictionary:
		defs = data["races"]
	var arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--records="):
			arg = a.trim_prefix("--records=")
	var env := OS.get_environment("PLATEAU_RECORDS")
	records_path = arg if arg != "" else env if env != "" else RECORDS
	hud = RaceHud.new()
	if game and game.hud:
		game.hud.add_child(hud)
	else:
		add_child(hud)
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -8.0
	add_child(_audio)
	for d: Dictionary in defs:
		var s: Dictionary = d["start"]
		var col: Color = START_COLOURS.get(d["id"], GATE)
		add_child(Marks.ring(s["x"], s["y"], s["r"], START_HEIGHT, col, 0, true))
		var label := Marks.sign_text(s["x"], s["y"], 4.0, "", 80, Color.WHITE)
		label.visibility_range_end = 160.0
		add_child(label)
		_circles[d["id"]] = label
		var b: Dictionary = d["board"]
		var board := Marks.board(b["x"], b["y"], b["facing"], d["name"], d.get("subtitle", ""),
				2 if d["vehicles"] == "bus" else 1)
		add_child(board)
		_boards3d[d["id"]] = board
	_refresh_boards()
	multiplayer.peer_disconnected.connect(_on_peer_left)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(_refresh_boards)      # the start circles' signs name the race key


## Solo, hosting, dedicated server: this peer runs the races, from its records file.
func start_hosting() -> void:
	hosting = true
	_load_records()
	boards = {}
	for key: String in _records:
		boards[key] = _top(_records[key])
	_refresh_boards()


func _clock() -> float:
	return game.net.clock()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _me() -> int:
	return game.net.me()


func _name(id: int) -> String:
	return game.nickname if not game.net.active else game.net.player_name(id)


func _key(action: String) -> String:
	var s := get_node_or_null("/root/Settings")
	return s.key_text(action) if s else action


# ---------------------------------------------------------------- messages

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else _me()


func _is_host() -> bool:
	return hosting and (not game.net.active or multiplayer.is_server())


## Calls `method` on the host (here when we host or play solo).
func _to_host(method: StringName, args: Array) -> void:
	if not game.net.active or multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


## Calls `method` on peer `peer` (host side).
func _to(peer: int, method: StringName, args: Array) -> void:
	if peer == _me() or not game.net.active:
		if game.mode != "server":
			callv(method, args)
	elif game.net.players.has(peer):
		callv("rpc_id", [peer, method] + args)


## Calls `method` everywhere, here too (host side).
func _to_all(method: StringName, args: Array) -> void:
	if game.net.active:
		callv("rpc", [method] + args)
	callv(method, args)


# ---------------------------------------------------------------- the local player

func _process(delta: float) -> void:
	if _is_host():
		_watch_runs()
	if game.mode == "" or game.mode == "server":
		return
	_give_up_t = maxf(_give_up_t - delta, 0.0)
	match state:
		IDLE:
			_offer()
		INVITED:
			if _now() > _invite_until:
				state = IDLE
				hud.show_prompt("")
			else:
				hud.show_prompt("%s invites you to race the %s (%d s)\n%s join · %s no thanks%s" % [_name(_invite_from),
						defs[race]["name"], ceili(_invite_until - _now()), _key("race"), _key("race_invite"),
						"" if _circle_here() == race else " · drive into the start circle to join"])
		LOBBY:
			if run < 0:
				hud.show_prompt("Starting the %s…" % defs[race]["name"])
			elif _inviter and not _waiting.is_empty():
				hud.show_prompt("Waiting for %s… · %s start now" % [", ".join(_waiting), _key("race")])
			else:
				hud.show_prompt("Waiting for the start…")
		COUNTDOWN:
			_count_down()
		RACING:
			_show_race()
		FINISHED:
			_finished_t += delta
			if racers.size() > 1 and race >= 0:
				var mine: Array = _results.get(_me(), [])
				hud.set_banner("%s\n%s\nWaiting for the others…" % [defs[race]["name"], "Finished in %s" % format_time(
						finish_time) if not mine.is_empty() and mine[0] == "done" else "Out of the race"])
			if _finished_t > MAX_RACE:
				_reset()


## Idle: the offer to race while driving in a start circle.
func _offer() -> void:
	var k := _circle_here()
	if k < 0:
		hud.show_prompt("")
		return
	var d: Dictionary = defs[k]
	var text := "%s · %s race alone" % [d["name"], _key("race")]
	var others := _drivers_in_circle(k)
	if not others.is_empty() and not d.get("alone", false):
		text += " · %s race with %s" % [_key("race_invite"), ", ".join(others.map(_name))]
	var best := _best_line(d, game.driving.model_name)
	if best != "":
		text += "\n" + best
	hud.show_prompt(text)


## "Record 2:31.42 by Alice" for the board a vehicle of `model` races on in `d`.
func _best_line(d: Dictionary, model: String) -> String:
	var rows: Array = boards.get(board_key(d, model), [])
	if rows.is_empty():
		return "No time yet: set the first!"
	return "Record %s by %s" % [format_time(rows[0][1]), rows[0][0]]


## Index of the race whose start circle the vehicle we drive is in (and may race in), or -1.
func _circle_here() -> int:
	var car: Car = game.driving
	if car == null:
		return -1
	for k in defs.size():
		if fits(defs[k], car) and in_circle(car, defs[k]["start"]):
			return k
	return -1


## True when `car` may race in `d`: a bus for the bus race, anything but a plane for the others.
static func fits(d: Dictionary, car: Car) -> bool:
	if d["vehicles"] == "bus":
		return car.model_name in BUSES
	return not car is Biplane


static func in_circle(car: Car, c: Dictionary) -> bool:
	var p := car.to_global(car.extents_center)
	return Vector2(p.x - float(c["x"]), -p.z - float(c["y"])).length() < float(c["r"])


## The other players driving in race `k`'s start circle (LAN games).
func _drivers_in_circle(k: int) -> Array:
	var out := []
	if not game.net.active:
		return out
	for car: Car in game.cars:
		if car == game.driving or car.is_bot() or car.stowed:
			continue
		var driver: int = game.net.driver_of.get(car.net_id, 0)
		if driver != 0 and driver != _me() and not driver in out and fits(defs[k], car) \
				and in_circle(car, defs[k]["start"]):
			out.append(driver)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if game.mode == "" or game.mode == "server" or game.ui_open():
		return
	if event.is_action_pressed("race"):
		race_key()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("race_invite"):
		invite_key()
		get_viewport().set_input_as_handled()


## The race key: race alone (idle in a start circle), join (invited), start now (waiting for the invited), give up
## (racing: twice).
func race_key() -> void:
	match state:
		IDLE:
			var k := _circle_here()
			if k >= 0:
				_start(k, [])
		INVITED:
			if _circle_here() != race:
				hud.flash("Drive into the start circle to join", 2.0)
				return
			state = LOBBY
			_inviter = false
			_to_host("_h_answer", [run, true, game.driving.model_name])
		LOBBY:
			if _inviter and run >= 0:
				_to_host("_h_go_now", [run])
		COUNTDOWN, RACING:
			if _give_up_t > 0.0:
				_give_up("gave up")
			else:
				_give_up_t = GIVE_UP_TIME
				hud.flash("%s again to give up" % _key("race"), GIVE_UP_TIME)


## The invite key: race with the other drivers in the circle (idle), decline (invited).
func invite_key() -> void:
	if state == IDLE:
		var k := _circle_here()
		if k >= 0 and not defs[k].get("alone", false):
			var others := _drivers_in_circle(k)
			if others.is_empty():
				hud.flash("Nobody else is driving in the circle", 2.0)
			else:
				_start(k, others)
	elif state == INVITED:
		_to_host("_h_answer", [run, false, ""])
		_reset()


func _start(k: int, invited: Array) -> void:
	state = LOBBY
	run = -1
	race = k
	_inviter = true
	_waiting = invited.map(_name)
	hud.show_prompt("")
	_to_host("_h_start", [k, game.driving.model_name, invited])


func _count_down() -> void:
	if not _still_driving():
		_give_up("left the vehicle")
		return
	vehicle.hold = true
	var left := go_at - _clock()
	if left > 0.0:
		var n := ceili(left)
		if n != _last_count:
			_last_count = n
			if n <= int(COUNTDOWN_TIME):
				hud.count(str(n))
				_beep("count")
			else:
				hud.count("Get ready", 0.0, Color.WHITE)
		hud.show_prompt("")
		return
	vehicle.hold = false
	state = RACING
	hud.count("GO!", 1.2, Color(0.5, 1.0, 0.5))
	_beep("go")
	_show_gates()


func _still_driving() -> bool:
	return is_instance_valid(vehicle) and game.driving == vehicle


## Racing: the banner and the arrow to the next checkpoint.
func _show_race() -> void:
	if not _still_driving():
		return
	var d: Dictionary = defs[race]
	var n: int = d["checkpoints"].size()
	var lines := "%s\n%s\n%s" % [d["name"], format_time(_clock() - go_at),
			"Checkpoint %d/%d" % [next_cp, n] if next_cp < n else "To the finish!"]
	if racers.size() > 1:
		lines += "\n%s of %d" % [ordinal(_place()), racers.size()]
	var warn := ""
	if off_road > 0.0:
		warn = "BACK ON THE ROAD! %.1f s" % maxf(OFF_TIME - off_road, 0.0)
	hud.set_banner(lines, warn)
	var t: Dictionary = d["checkpoints"][next_cp] if next_cp < n else d["finish"]
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_transform.affine_inverse() * Vector3(float(t["x"]), cam.global_position.y, -float(t["y"]))
		var v := vehicle.to_global(vehicle.extents_center)
		hud.set_arrow(atan2(p.x, -p.z), Vector2(v.x - float(t["x"]), -v.z - float(t["y"])).length())


## Our place in the race now: racers ahead have passed more checkpoints or finished.
func _place() -> int:
	var place := 1
	for p: int in racers:
		if p == _me():
			continue
		var r: Array = _results.get(p, [])
		if (not r.is_empty() and r[0] == "done") or (r.is_empty() and _progress.get(p, 0) > next_cp):
			place += 1
	return place


func _physics_process(delta: float) -> void:
	if state != RACING:
		return
	if not _still_driving():
		_give_up("left the vehicle")
		return
	var d: Dictionary = defs[race]
	var c := vehicle.to_global(vehicle.extents_center)
	var p := Vector2(c.x, -c.z)
	var cps: Array = d["checkpoints"]
	if next_cp < cps.size():
		var g: Dictionary = cps[next_cp]
		if p.distance_to(Vector2(g["x"], g["y"])) < float(g["r"]):
			next_cp += 1
			_to_host("_h_passed", [run, next_cp])
			_beep("gate")
			hud.flash("Checkpoint %d/%d · %s" % [next_cp, cps.size(), format_time(_clock() - go_at)], 1.5)
			_show_gates()
	elif p.distance_to(Vector2(d["finish"]["x"], d["finish"]["y"])) < float(d["finish"]["r"]):
		finish_time = _clock() - go_at
		_end_race()
		_beep("finish")
		hud.count(format_time(finish_time), 4.0)
		_to_host("_h_finish", [run, finish_time])
		return
	if d["vehicles"] == "bus":
		_check_road(delta)


## The bus race: out once a wheel stays over OFF_DIST m off the road for over OFF_TIME s, or goes over OFF_FAR m.
func _check_road(delta: float) -> void:
	_off_t += delta
	if _off_t < OFF_EVERY:
		return
	var dt := _off_t
	_off_t = 0.0
	off_dist = road_distance(vehicle)
	if off_dist > OFF_FAR:
		_give_up("left the road", true)
	elif off_dist > OFF_DIST:
		off_road += dt
		if off_road > OFF_TIME:
			_give_up("left the road", true)
	else:
		off_road = 0.0


## How far the wheel of `car` furthest from the road is off it (m, 0 when they all are on it; INF beyond the search).
func road_distance(car: Car) -> float:
	var map: GroundMap = GroundMap.get_map()
	if map == null:
		return 0.0
	if _road.is_empty():
		_road.resize(map.pieces.size())
		for k in map.pieces.size():
			var piece: Array = map.pieces[k]
			_road[k] = 1 if piece[0] == "road" or (piece[0] == "landcover" and piece[1] == "asphalt") else 0
	var worst := 0.0
	for b: Node in car.bodies():
		for w in b.get_children():
			if w is VehicleWheel3D:
				var g := (w as Node3D).global_position
				worst = maxf(worst, _off_road(map, g.x, -g.z))
	return worst


func _off_road(map: GroundMap, x: float, y: float) -> float:
	if _on_road(map, x, y):
		return 0.0
	for r: float in OFF_RINGS:
		var n := clampi(ceili(TAU * r / 0.75), 8, 96)
		for k in n:
			var a := TAU * k / n
			if _on_road(map, x + cos(a) * r, y + sin(a) * r):
				return r
	return INF


func _on_road(map: GroundMap, x: float, y: float) -> bool:
	var k := map.piece_at(x, y)
	return k >= 0 and _road[k] == 1


func _give_up(why: String, disqualified := false) -> void:
	var r := run
	_end_race()
	hud.count("DISQUALIFIED" if disqualified else "Out of the race", 3.0, Color(1.0, 0.45, 0.35))
	if disqualified:
		hud.flash("You %s" % why, 3.0)
	_to_host("_h_out", [r, why])


## Done racing, waiting for the results.
func _end_race() -> void:
	if is_instance_valid(vehicle):
		vehicle.hold = false
	_hide_gates()
	hud.set_banner("")
	hud.set_arrow(NAN, 0.0)
	state = FINISHED
	_finished_t = 0.0
	off_road = 0.0


func _reset() -> void:
	if state in [COUNTDOWN, RACING] and is_instance_valid(vehicle):
		vehicle.hold = false
	_hide_gates()
	state = IDLE
	run = -1
	race = -1
	vehicle = null
	next_cp = 0
	racers = []
	_progress = {}
	_results = {}
	_waiting = []
	_last_count = -1
	off_road = 0.0
	off_dist = 0.0
	hud.show_prompt("")
	hud.set_banner("")
	hud.set_arrow(NAN, 0.0)


## The next checkpoint (bright) and the one after (dim), or the finish (chequered).
func _show_gates() -> void:
	_hide_gates()
	var d: Dictionary = defs[race]
	var cps: Array = d["checkpoints"]
	for k in [next_cp, next_cp + 1]:
		var finish: bool = k == cps.size()
		if k > cps.size():
			break
		var g: Dictionary = d["finish"] if finish else cps[k]
		var m := Marks.ring(g["x"], g["y"], g["r"], GATE_HEIGHT, GATE, 2 if finish else 1)
		if k > next_cp:
			Marks.set_strength(m, 0.35)
		add_child(m)
		_gates.append(m)
		var label := Marks.sign_text(g["x"], g["y"], GATE_HEIGHT + 1.2, "FINISH" if finish else "%d/%d" % [k + 1, cps.size()],
				110 if k == next_cp else 70, GATE.lightened(0.3) if k == next_cp else Color(1, 1, 1, 0.6))
		add_child(label)
		_gates.append(label)


func _hide_gates() -> void:
	for g: Node in _gates:
		g.queue_free()
	_gates = []


# ---------------------------------------------------------------- what the host tells us

@rpc("authority", "call_remote", "reliable")
func _c_invite(run_id: int, race_idx: int, from_id: int, seconds: float) -> void:
	if state != IDLE or race_idx < 0 or race_idx >= defs.size():
		_to_host("_h_answer", [run_id, false, ""])
		return
	state = INVITED
	run = run_id
	race = race_idx
	_invite_from = from_id
	_invite_until = _now() + seconds
	_beep("gate")


## We invited: who has not answered yet.
@rpc("authority", "call_remote", "reliable")
func _c_lobby(run_id: int, race_idx: int, waiting: Array) -> void:
	if state == LOBBY and (run == -1 or run == run_id) and race == race_idx:
		run = run_id
		_waiting = waiting


## The invitation is over: the race went without us.
@rpc("authority", "call_remote", "reliable")
func _c_closed(run_id: int) -> void:
	if run == run_id and state in [INVITED, LOBBY]:
		_reset()


@rpc("authority", "call_remote", "reliable")
func _c_refused(why: String) -> void:
	if state == LOBBY:
		_reset()
		hud.flash(why, 3.0)


## The race starts: GO at `at` on the shared clock, `ids` racing.
@rpc("authority", "call_remote", "reliable")
func _c_go(run_id: int, race_idx: int, ids: Array, at: float) -> void:
	if not (state == LOBBY and (run == -1 or run == run_id) and race == race_idx) or game.driving == null:
		_to_host("_h_out", [run_id, "was not ready"])
		return
	state = COUNTDOWN
	run = run_id
	vehicle = game.driving
	racers = ids
	go_at = at
	next_cp = 0
	_progress = {}
	_results = {}
	_last_count = -1
	off_road = 0.0
	off_dist = 0.0
	_off_t = 0.0
	hud.show_prompt("")
	hud.hide_results()


@rpc("authority", "call_remote", "reliable")
func _c_progress(run_id: int, peer: int, cps: int) -> void:
	if run_id == run:
		_progress[peer] = cps


## A racer is in (what: "done", its time and place) or out (what: why).
@rpc("authority", "call_remote", "reliable")
func _c_result(run_id: int, peer: int, what: String, time: float, place: int) -> void:
	if run_id != run:
		return
	_results[peer] = [what, time, place]
	if peer != _me():
		hud.flash("%s %s" % [_name(peer), "finished %s in %s" % [ordinal(place), format_time(time)] if what == "done" \
				else "is out (%s)" % what], 3.0)
	elif what == "done" and racers.size() > 1:
		hud.flash("%s place!" % ordinal(place), 3.0, GOLD)


## The race is over: rows of [peer, name, what ("done" or why out), time, model, place, board rank (0: no personal
## best)].
@rpc("authority", "call_remote", "reliable")
func _c_over(run_id: int, race_idx: int, rows: Array) -> void:
	if run_id != run:
		return
	var d: Dictionary = defs[race_idx]
	var table := []
	var footer := ""
	for r: Array in rows:
		var done: bool = r[2] == "done"
		var colour := GOLD if done and r[5] == 1 else Color.WHITE if done else Color(0.75, 0.75, 0.8)
		if r[0] == _me():
			colour = colour.lerp(Color(0.6, 1.0, 0.6), 0.5)
			if r[6] == 1:
				footer = "New record!"
			elif r[6] > 0:
				footer = "Personal best: %s on the board" % ordinal(r[6])
		table.append([ordinal(r[5]) if done else "—", r[1], format_time(r[3]) if done else r[2],
				Car.display_name(r[4]), colour])
	hud.show_results("%s · results" % d["name"], table, footer)
	_reset()


@rpc("authority", "call_remote", "reliable")
func _c_board(key: String, rows: Array) -> void:
	boards[key] = rows
	_refresh_boards()


@rpc("authority", "call_remote", "reliable")
func _c_boards(all: Dictionary) -> void:
	boards = all
	_refresh_boards()


## A message for everyone's chat (a race's results).
@rpc("authority", "call_remote", "reliable")
func _c_announce(text: String) -> void:
	if game.mode == "server":
		print("Race: " + text)
	elif game.chat:
		game.chat.add("Race", GOLD, text)


## The leaderboards and the start circles' signs, from `boards`.
func _refresh_boards() -> void:
	for d: Dictionary in defs:
		var b: Node3D = _boards3d.get(d["id"])
		if b == null:
			continue
		if d["vehicles"] == "bus":
			for c in BUSES.size():
				Marks.set_board(b, c, Car.display_name(BUSES[c]), _rows(boards.get(board_key(d, BUSES[c]), []), false))
		else:
			Marks.set_board(b, 0, "Best laps", _rows(boards.get(board_key(d, ""), []), true))
		var label: Label3D = _circles.get(d["id"])
		if label:
			var best := ""
			if d["vehicles"] == "bus":
				for m: String in BUSES:
					var rows: Array = boards.get(board_key(d, m), [])
					if not rows.is_empty():
						best += "\n%s: %s by %s" % [Car.display_name(m), format_time(rows[0][1]), rows[0][0]]
			else:
				var rows: Array = boards.get(board_key(d, ""), [])
				if not rows.is_empty():
					best = "\nRecord %s by %s" % [format_time(rows[0][1]), rows[0][0]]
			label.text = "%s%s\nStop here %s, then %s to race" % [d["name"].to_upper(), best,
					"in a bus" if d["vehicles"] == "bus" else "in a vehicle", _key("race")]


func _rows(rows: Array, vehicles: bool) -> Array:
	var out := []
	for i in rows.size():
		var r: Array = rows[i]
		var who: String = "%d. %s" % [i + 1, str(r[0]).left(16)]
		if vehicles:
			who += "  · " + Car.display_name(r[2]).left(18)
		out.append([who, format_time(r[1])])
	if out.is_empty():
		out.append(["No time yet", ""])
	return out


# ---------------------------------------------------------------- host

func _player(id: int) -> bool:
	return game.net.players.has(id) if game.net.active else id == _me()


## The race player `id` is in or invited to, or -1.
func _run_of(id: int) -> int:
	for run_id: int in _runs:
		var r: Dictionary = _runs[run_id]
		if id in r["waiting"] or (r["racers"].has(id) and r["racers"][id]["what"] == ""):
			return run_id
	return -1


@rpc("any_peer", "call_remote", "reliable")
func _h_start(race_idx: int, model: String, invited: Array) -> void:
	var id := _sender()
	if not _is_host():
		return
	if race_idx < 0 or race_idx >= defs.size() or not Car.SPECS.has(model):
		_to(id, "_c_refused", ["This race cannot start"])
		return
	if _run_of(id) >= 0:
		_to(id, "_c_refused", ["You are already in a race"])
		return
	var d: Dictionary = defs[race_idx]
	_next_run += 1
	var r := {"race": race_idx, "phase": "invite", "by": id, "racers": {id: _racer(model)}, "waiting": [],
			"until": _now() + INVITE_TIME, "go_at": 0.0, "first": -1.0, "started": _now()}
	if not d.get("alone", false):
		for p: Variant in invited:
			if p is int and p != id and _player(p) and _run_of(p) < 0 and not p in r["waiting"]:
				r["waiting"].append(p)
	_runs[_next_run] = r
	if r["waiting"].is_empty():
		_go(_next_run)
		return
	for p: int in r["waiting"]:
		_to(p, "_c_invite", [_next_run, race_idx, id, INVITE_TIME])
	_to(id, "_c_lobby", [_next_run, race_idx, r["waiting"].map(_name)])


func _racer(model: String) -> Dictionary:
	return {"model": model, "cp": 0, "what": "", "time": 0.0, "place": 0, "rank": 0}


@rpc("any_peer", "call_remote", "reliable")
func _h_answer(run_id: int, yes: bool, model: String) -> void:
	var id := _sender()
	var r: Dictionary = _runs.get(run_id, {})
	if not _is_host() or r.is_empty() or r["phase"] != "invite" or not id in r["waiting"]:
		return
	r["waiting"].erase(id)
	if yes and Car.SPECS.has(model):
		r["racers"][id] = _racer(model)
	if r["waiting"].is_empty():
		_go(run_id)
	else:
		_to(r["by"], "_c_lobby", [run_id, r["race"], r["waiting"].map(_name)])


@rpc("any_peer", "call_remote", "reliable")
func _h_go_now(run_id: int) -> void:
	var r: Dictionary = _runs.get(run_id, {})
	if _is_host() and not r.is_empty() and r["phase"] == "invite" and r["by"] == _sender():
		_go(run_id)


func _go(run_id: int) -> void:
	var r: Dictionary = _runs[run_id]
	r["phase"] = "race"
	r["go_at"] = _clock() + LEAD + COUNTDOWN_TIME
	r["started"] = _now()
	for p: int in r["waiting"]:
		_to(p, "_c_closed", [run_id])
	r["waiting"] = []
	var ids: Array = r["racers"].keys()
	for p: int in ids:
		_to(p, "_c_go", [run_id, r["race"], ids, r["go_at"]])


@rpc("any_peer", "call_remote", "reliable")
func _h_passed(run_id: int, cps: int) -> void:
	var id := _sender()
	var r: Dictionary = _runs.get(run_id, {})
	if not _is_host() or r.is_empty() or not r["racers"].has(id) or r["racers"][id]["what"] != "":
		return
	var racer: Dictionary = r["racers"][id]
	racer["cp"] = clampi(cps, racer["cp"], defs[r["race"]]["checkpoints"].size())
	for p: int in r["racers"]:
		if p != id:
			_to(p, "_c_progress", [run_id, id, racer["cp"]])


@rpc("any_peer", "call_remote", "reliable")
func _h_finish(run_id: int, time: float) -> void:
	var id := _sender()
	var r: Dictionary = _runs.get(run_id, {})
	if not _is_host() or r.is_empty() or r["phase"] != "race" or not r["racers"].has(id) \
			or r["racers"][id]["what"] != "":
		return
	var d: Dictionary = defs[r["race"]]
	var racer: Dictionary = r["racers"][id]
	if racer["cp"] < d["checkpoints"].size() or time < float(d["length"]) / MIN_TIME_SPEED or time > MAX_RACE:
		_out(run_id, id, "time refused")
		return
	var place := 1
	for p: int in r["racers"]:
		if r["racers"][p]["what"] == "done":
			place += 1
	racer["what"] = "done"
	racer["time"] = time
	racer["place"] = place
	racer["rank"] = _record(board_key(d, racer["model"]), _name(id), time, racer["model"])
	if r["first"] < 0.0:
		r["first"] = _now()
	for p: int in r["racers"]:
		_to(p, "_c_result", [run_id, id, "done", time, place])
	_check_over(run_id)


@rpc("any_peer", "call_remote", "reliable")
func _h_out(run_id: int, why: String) -> void:
	if _is_host():
		_out(run_id, _sender(), why.left(40))


func _out(run_id: int, id: int, why: String) -> void:
	var r: Dictionary = _runs.get(run_id, {})
	if r.is_empty():
		return
	if id in r["waiting"]:
		r["waiting"].erase(id)
		if r["waiting"].is_empty() and r["phase"] == "invite":
			_go(run_id)
		return
	if not r["racers"].has(id) or r["racers"][id]["what"] != "":
		return
	r["racers"][id]["what"] = why if why != "" and why != "done" else "out"
	if r["phase"] == "race":
		for p: int in r["racers"]:
			_to(p, "_c_result", [run_id, id, r["racers"][id]["what"], 0.0, 0])
	_check_over(run_id)


## Ends race `run_id` once every racer is in or out (`force`: now, the ones still racing did not finish).
func _check_over(run_id: int, force := false) -> void:
	var r: Dictionary = _runs[run_id]
	for p: int in r["racers"]:
		if r["racers"][p]["what"] == "":
			if not force:
				return
			r["racers"][p]["what"] = "did not finish"
	var rows := []
	for p: int in r["racers"]:
		var x: Dictionary = r["racers"][p]
		rows.append([p, _name(p), x["what"], x["time"], x["model"], x["place"], x["rank"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if (a[2] == "done") != (b[2] == "done"):
			return a[2] == "done"
		return a[5] < b[5])
	_runs.erase(run_id)
	for p: int in r["racers"]:
		if _player(p):
			_to(p, "_c_over", [run_id, r["race"], rows])
	var text := results_text(defs[r["race"]], rows)
	if text != "":
		_to_all("_c_announce", [text])


## The chat line for a race's results (rows as _c_over's), "" when nobody finished.
static func results_text(d: Dictionary, rows: Array) -> String:
	var done := rows.filter(func(r: Array) -> bool: return r[2] == "done")
	if done.is_empty():
		return ""
	var what: String = d["name"] + (" (%s)" % d["subtitle"] if d.get("subtitle", "") != "" else "")
	var text := ""
	if rows.size() == 1:
		text = "%s finished the %s in %s · %s" % [rows[0][1], what, format_time(rows[0][3]), Car.display_name(rows[0][4])]
	else:
		text = "%s won the %s in %s" % [done[0][1], what, format_time(done[0][3])]
		for r: Array in done.slice(1):
			text += ", %s %s in %s" % [r[1], ordinal(r[5]), format_time(r[3])]
		var out := rows.filter(func(r: Array) -> bool: return r[2] != "done")
		if not out.is_empty():
			text += " (%s: out)" % ", ".join(out.map(func(r: Array) -> String: return r[1]))
	var board := " for the %s" % Car.display_name(done[0][4]) if d["vehicles"] == "bus" else ""
	for r: Array in done:
		var who: String = "" if rows.size() == 1 else " for %s" % r[1]
		if r[6] == 1:
			text += " · New record%s%s!" % [board, who]
		elif r[6] > 1 and r[6] <= BOARD_ROWS:
			text += " · %s on the leaderboard%s" % [ordinal(r[6]), who]
	return text


## Host, each frame: invitations that ran out of time start, races past their time end.
func _watch_runs() -> void:
	for run_id: int in _runs.keys():
		var r: Dictionary = _runs.get(run_id, {})
		if r.is_empty():
			continue
		if r["phase"] == "invite":
			if _now() > r["until"]:
				_go(run_id)
		elif (r["first"] >= 0.0 and _now() - r["first"] > FINISH_WAIT) or _now() - r["started"] > MAX_RACE:
			_check_over(run_id, true)


func _on_peer_left(id: int) -> void:
	if not _is_host():
		return
	for run_id: int in _runs.keys():
		if _runs.has(run_id):
			_out(run_id, id, "left the game")


## Host: a player joined (net.gd `registered`): the leaderboards.
func send_boards(id: int) -> void:
	if _is_host():
		_to(id, "_c_boards", [boards])


static func board_key(d: Dictionary, model: String) -> String:
	return "%s:%s" % [d["id"], model] if d["vehicles"] == "bus" else d["id"]


## Player `name`'s time on board `key`: kept when it beats their best. Returns its rank there, 0 when it did not.
func _record(key: String, player: String, time: float, model: String) -> int:
	var rows: Array = _records.get(key, [])
	for i in rows.size():
		if rows[i][0] == player:
			if rows[i][1] <= time:
				return 0
			rows.remove_at(i)
			break
	rows.append([player, snappedf(time, 0.001), model, int(Time.get_unix_time_from_system())])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	if rows.size() > KEEP:
		rows.resize(KEEP)
	_records[key] = rows
	save_records()
	_to_all("_c_board", [key, _top(rows)])
	for i in rows.size():
		if rows[i][0] == player:
			return i + 1
	return 0


func _top(rows: Array) -> Array:
	return rows.slice(0, BOARD_ROWS).map(func(r: Array) -> Array: return [r[0], r[1], r[2]])


func _load_records() -> void:
	_records = {}
	for path: String in [records_path, records_path + ".tmp"]:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary and data.get("boards") is Dictionary):
			push_warning("unreadable race records in %s" % path)
			continue
		for key: String in data["boards"]:
			var rows := []
			for r: Variant in data["boards"][key]:
				if r is Array and r.size() >= 3 and r[0] is String and (r[1] is float or r[1] is int):
					rows.append([r[0], float(r[1]), str(r[2]), int(r[3]) if r.size() > 3 else 0])
			rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
			_records[key] = rows
		return


## Writes the records (a temporary file, then renamed over the old one: a crash never leaves half a file).
func save_records() -> void:
	var path := ProjectSettings.globalize_path(records_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write the race records to %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"schema": 1, "boards": _records}, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(tmp, path) != OK:
			push_warning("cannot write the race records to %s" % path)


# ---------------------------------------------------------------- text and sounds

## "2:31.42"
static func format_time(t: float) -> String:
	var cs := roundi(maxf(t, 0.0) * 100.0)
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


static func ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	return "%d%s" % [n, {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")]


func _beep(kind: String) -> void:
	if not _sounds.has(kind):
		var notes: Array = {"count": [[0.0, 660.0, 0.16]], "go": [[0.0, 1320.0, 0.45]],
				"gate": [[0.0, 880.0, 0.09], [0.09, 1320.0, 0.14]],
				"finish": [[0.0, 784.0, 0.14], [0.14, 988.0, 0.14], [0.28, 1175.0, 0.14], [0.42, 1568.0, 0.5]]}[kind]
		var length := 0.0
		for n: Array in notes:
			length = maxf(length, n[0] + n[2] + 0.05)
		var data := PackedByteArray()
		data.resize(int(length * RATE) * 2)
		for n: Array in notes:
			var i0 := int(n[0] * RATE)
			for j in int(n[2] * RATE):
				var t := float(j) / RATE
				var env := minf(t / 0.005, 1.0) * exp(-t * 4.0) * minf((n[2] - t) / 0.02, 1.0)
				var x := (sin(TAU * n[1] * t) + 0.25 * sin(TAU * 2.0 * n[1] * t)) * env * 0.45
				var k := (i0 + j) * 2
				if k + 1 < data.size():
					data.encode_s16(k, clampi(data.decode_s16(k) + int(x * 32767.0), -32768, 32767))
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = RATE
		s.data = data
		_sounds[kind] = s
	_audio.stream = _sounds[kind]
	_audio.play()
