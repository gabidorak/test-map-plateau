extends Node
## Stealing a car from its bot driver (game.gd makes it as Main/Carjack on every peer, so its RPCs have the same path
## everywhere). The car must stand still (STILL: at a red light, in a jam, stopped for someone in its way).
## - E by a bot car (game.gd interact: request) asks the host (or solo player, or dedicated server), which checks it
##   (_refusal: the game mode allows("carjack"), a bot car and not a bus, still, the player on foot by its driver's
##   door: at_door, nobody else at it, not tried in the last COOLDOWN s), holds it where it is (BusBot `seized`: the
##   driver frozen, the light may turn green) and hands the player SEQUENCE arrow keys drawn at random.
## - The player presses them in order (carjack_hud.gd: they pop in, then TIME s run down; a wrong key or Esc ends it)
##   and sends what they pressed; the host judges it against what it drew and the time it took (TIME and the keys'
##   popping in, plus LAG for the way there and back): a patched client cannot steal a car faster or blind.
## - Right: the car is theirs (traffic.gd release_car: its bot gone, a new bot car in the traffic out of sight; net.gd
##   give_drive, or straight into it solo) and its driver runs off crying out, on every peer (ejected_driver.gd).
##   Wrong, late or given up: the driver comes to and drives on; the car cannot be tried again for COOLDOWN s.
## - Stolen cars (`stolen`) are anyone's to drive (PTA Online too: online_mode.gd refuse_drive). One standing ABANDON s
##   with nobody at its wheel and no player within ABANDON_SEEN m leaves the map (host).
## Cars are named by their net id in LAN games, by their instance id solo (key_of, car_of).

const Car = preload("res://scripts/car.gd")
const Hud = preload("res://scripts/carjack/carjack_hud.gd")
const EjectedDriver = preload("res://scripts/carjack/ejected_driver.gd")

const SEQUENCE := 5                         # arrow keys to press
const TIME := 2.5                           # s to press them, once they have all popped in
const LAG := 0.8                            # s more the host allows (the keys' way there and back)
const STILL := 0.5                          # m/s: slower than this, a car stands still
const DOOR_REACH := 1.8                     # m out from its left side (car.gd: +X) the driver's door is in reach...
const DOOR_ALONG := 1.6                     # ...within this many m before or behind the driver's seat
const COOLDOWN := 10.0                      # s after a failed try before the same car may be tried again
const ABANDON := 300.0                      # s a stolen car may stand with nobody at its wheel...
const ABANDON_SEEN := 150.0                 # ...and no player this close, before it leaves the map
const STUCK := 2.0                          # s more than its time a try may last before the host ends it (player gone)

var game: Node3D                            # game.gd
var stolen := {}                            # car key -> s it has stood with nobody at its wheel (counted by the host)
var tries := 0                              # host: tries handed out (tests)

var _hud: Hud
var _key := ""                              # the car we are trying, "" none
var _attempts := {}                         # host: car key -> {"peer", "seq", "t" (s since handed out), "bot"}
var _cooldown := {}                         # host: car key -> s left
var _rng := RandomNumberGenerator.new()
var _abandon_look := 0.0


func _ready() -> void:
	_rng.randomize()


## Whether the player tries a car now (game.gd ui_open: they and the vehicles take no keys meanwhile).
func busy() -> bool:
	return _hud != null and _hud.taking_keys()


## E by bot car `car` (game.gd): asks to steal it. False when it is not one to steal (a bus, a game mode without it):
## game.gd then tells the player a bot drives it.
func request(car: Car) -> bool:
	if not game.allows("carjack") or not car.is_bot() or car.has_doors or car.interior.size != Vector3.ZERO:
		return false
	if _key == "" and not busy():
		_to_host("_h_start", [key_of(car)])
	return true


## Whether the car of key `key` was stolen (anyone may drive it).
func is_stolen(key: String) -> bool:
	return stolen.has(key)


## `car`'s name between the peers: its net id in a LAN game, its instance id solo.
func key_of(car: Node3D) -> String:
	return car.net_id if game.net.active else str(car.get_instance_id())


func car_of(key: String) -> Car:
	if game.net.active:
		return game.net.cars.get(key) as Car
	var o: Object = instance_from_id(int(key)) if key.is_valid_int() else null
	return o as Car if is_instance_valid(o) else null


## Whether `p` (global) is by `car`'s driver's door: out from its left side (+X, car.gd) up to DOOR_REACH m, within
## DOOR_ALONG m of its driver's seat along it.
static func at_door(car: Car, p: Vector3) -> bool:
	var l := car.to_local(p) - car.extents_center
	var seat := (car.driver_seat if car.driver_seat != Vector3.ZERO else car.extents_center) - car.extents_center
	return l.x > car.half_extents.x - 0.5 and l.x < car.half_extents.x + DOOR_REACH \
			and absf(l.z - seat.z) < DOOR_ALONG and absf(l.y) < car.half_extents.y + 1.5


# ---------------------------------------------------------------- host

func _physics_process(delta: float) -> void:
	if not _hosting():
		return
	for key: String in _cooldown.keys():
		_cooldown[key] -= delta
		if _cooldown[key] <= 0.0:
			_cooldown.erase(key)
	for key: String in _attempts.keys():
		var a: Dictionary = _attempts[key]
		a["t"] += delta
		if a["t"] > _allowed() + STUCK or (game.net.active and not game.net.players.has(a["peer"])
				and a["peer"] != game.net.me()):
			_attempts.erase(key)
			_end(key, a, false, "Too slow: the driver came to.")
	_abandon_look -= delta
	if _abandon_look <= 0.0:
		_abandon_look = 1.0
		_abandoned(1.0)


## s a try may take: the keys popping in, TIME, and LAG.
func _allowed() -> float:
	return Hud.REVEAL * SEQUENCE + Hud.POP + TIME + LAG


@rpc("any_peer", "call_remote", "reliable")
func _h_start(key: String) -> void:
	if not _hosting():
		return
	var peer := _sender()
	var car := car_of(key)
	var why := _refusal(car, key, peer)
	if why != "":
		_to_peer(peer, "_c_refused", [why])
		return
	var bot: Object = game.traffic.car_bot(car)
	bot.seized = true
	var seq := []
	for i in SEQUENCE:
		seq.append(_rng.randi() % Hud.ARROWS.size())
	_attempts[key] = {"peer": peer, "seq": seq, "t": 0.0, "bot": bot}
	tries += 1
	_to_peer(peer, "_c_start", [key, seq, TIME])


## Why player `peer` may not try `car` now ("" they may).
func _refusal(car: Car, key: String, peer: int) -> String:
	if not game.allows("carjack"):
		return "No stealing cars here."
	if car == null or car.stowed:
		return "Too late: it's gone."
	var bot: Object = game.traffic.car_bot(car)
	if bot == null:
		return "A bot drives it: nothing to steal."
	if _attempts.has(key):
		return "Someone is already at its door."
	for a: Dictionary in _attempts.values():
		if a["peer"] == peer:
			return "One car at a time."
	if _cooldown.has(key):
		return "Its driver is on their guard now: try another car."
	if absf(car.speed()) > STILL or bot.gliding:
		return "It's moving: wait for it to stop (a red light, a jam)."
	var p: Variant = _position_of(peer)
	if p == null:
		return "Get out first."
	if not at_door(car, p):
		return "Go to its driver's door (its left side)."
	return ""


## Where player `peer` stands on foot (global), or null (driving, riding, flying, not here).
func _position_of(peer: int) -> Variant:
	if peer == game.net.me():
		if game.mode == "server" or game.driving or game.riding or game.flying:
			return null
		return game.player.global_position
	var avatar: Node3D = game.net.avatar(peer)
	if avatar == null or not avatar.visible or avatar.riding_in() != null:
		return null
	return avatar.global_position


@rpc("any_peer", "call_remote", "reliable")
func _h_keys(key: String, typed: Array, gave_up: bool) -> void:
	if not _hosting():
		return
	var a: Dictionary = _attempts.get(key, {})
	if a.is_empty() or a["peer"] != _sender():
		return
	_attempts.erase(key)
	var seq: Array = a["seq"]
	var wrong := typed.size() > seq.size()
	for i in mini(typed.size(), seq.size()):
		wrong = wrong or int(typed[i]) != int(seq[i])
	var why := ""
	if gave_up:
		why = "You gave up: the driver drives off."
	elif wrong:
		why = "Wrong key: the driver came to."
	elif typed.size() < seq.size() or a["t"] > _allowed():
		why = "Too slow: the driver came to."
	_end(key, a, why == "", why)


## Try `a` on the car of key `key` over: stolen (`ok`) or not (`why`).
func _end(key: String, a: Dictionary, ok: bool, why: String) -> void:
	var car := car_of(key)
	var bot: Object = a["bot"]
	var peer: int = a["peer"]
	var driving: bool = bot != null and game.traffic.bots.has(bot) and car != null and bot.car == car
	if not ok or not driving:
		if driving:
			bot.seized = false              # the driver comes to
		_cooldown[key] = COOLDOWN
		_to_peer(peer, "_c_result", [key, false, why if why != "" else "Too late: it's gone."])
		return
	game.traffic.release_car(bot)
	stolen[key] = 0.0
	_to_all("_c_stolen", [key, _rng.randi()])
	_to_peer(peer, "_c_result", [key, true, "The car is yours: drive!"])
	if game.net.active:
		game.net.give_drive(key, peer)
	elif game.mode != "server":
		game.enter_car(car)


## Every `dt` s: a stolen car nobody drives stands longer; ABANDON s of it and no player within ABANDON_SEEN m, it goes.
func _abandoned(dt: float) -> void:
	var gone: Array = []
	for key: String in stolen.keys():
		var car := car_of(key)
		if car == null:
			stolen.erase(key)
			continue
		var driven: bool = game.driving == car or (game.net.active and int(game.net.driver_of.get(key, 0)) != 0)
		stolen[key] = 0.0 if driven else float(stolen[key]) + dt
		if stolen[key] > ABANDON and not game.traffic.player_within(car.global_position, ABANDON_SEEN):
			stolen.erase(key)
			gone.append(car)
	if not gone.is_empty():
		game.remove_vehicles(gone)


# ---------------------------------------------------------------- players

@rpc("authority", "call_remote", "reliable")
func _c_start(key: String, seq: Array, time_limit: float) -> void:
	_key = key
	if game.net.active:
		game.net.await_drive(key)           # (game.drive_granted puts us at the wheel if we get it)
	_hud_up().start(seq, time_limit)
	game.update_controls()


@rpc("authority", "call_remote", "reliable")
func _c_refused(text: String) -> void:
	game.toast(text)


@rpc("authority", "call_remote", "reliable")
func _c_result(key: String, ok: bool, text: String) -> void:
	if key != _key:
		return
	_key = ""
	if not ok and game.net.active:
		game.net.await_drive("")
	_hud_up().show_result(ok, text)
	game.update_controls()
	game.toast(text)


## Everyone: the car of key `key` was stolen; its driver runs off (`seed`: the same way on every peer).
@rpc("authority", "call_local", "reliable")
func _c_stolen(key: String, seed: int) -> void:
	if not stolen.has(key):
		stolen[key] = 0.0
	var car := car_of(key)
	if car == null or game.mode == "server":
		return
	var driver := EjectedDriver.new()
	driver.setup(game, car, seed)
	game.add_child(driver)


func _on_typed(typed: Array, gave_up: bool) -> void:
	if _key != "":
		_to_host("_h_keys", [_key, typed, gave_up])


func _hud_up() -> Hud:
	if _hud == null:
		_hud = Hud.new()
		_hud.name = "Carjack"
		_hud.finished.connect(_on_typed)
		game.hud.add_child(_hud)
	return _hud


# ---------------------------------------------------------------- the way between the peers

func _hosting() -> bool:
	return not game.net.active or multiplayer.is_server()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else game.net.me()


func _to_host(method: StringName, args: Array) -> void:
	if _hosting():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


func _to_peer(peer: int, method: StringName, args: Array) -> void:
	if not game.net.active or peer == game.net.me():
		if game.mode != "server":
			callv(method, args)
	elif game.net.players.has(peer):
		callv("rpc_id", [peer, method] + args)


func _to_all(method: StringName, args: Array) -> void:
	if game.net.active:
		callv("rpc", [method] + args)       # (call_local: here too)
	else:
		callv(method, args)
