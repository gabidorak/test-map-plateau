extends Node
## People and what happens to them (game.gd makes it as Main/People on every peer, so that its RPCs have the same path
## everywhere): stunned on the ground by a weapon (scripts/items/items.gd), carried over someone's shoulders, struggling
## free. The police (handcuffs, a car's back seat, a boot) will build on it.
## - Persons (person.gd: what they have): the player (player.gd), the other players (remote_player.gd), the bots on foot
##   (scripts/carjack/ejected_driver.gd).
## - Stunned (hit: the host's call, on a shot items.gd judged): they drop to the ground for the weapon's time, unable to
##   move or act (the mouse still looks around), its effect on them (people_fx.gd: arcs, a net); then they get up and
##   nothing stuns them for IMMUNE s.
## - E by someone down (CARRY_REACH m) picks them up over the shoulders: the carrier walks slower, cannot run, jump,
##   draw a weapon nor get into a vehicle; G puts them down (still down for what is left of their stun). The one
##   carried, once their stun is over, struggles: the host's STRUGGLE_KEYS arrow keys, shown one at a time
##   (struggle_hud.gd), all within STRUGGLE_TIME s: right, they are free (up at once); wrong or late, another go
##   STRUGGLE_RETRY s later. A bot wriggles free NPC_STRUGGLE s after its stun. Nobody is carried more than CARRY_MAX s
##   (a player away from the keys). A carrier stunned, or leaving the game, drops them.
## - The host decides and tells everyone (_c_down, _c_carry, _c_release); every peer counts the stuns down itself, from
##   the time given. A newcomer gets everything as it is (player_registered).
## Ids: "p:<peer>" for the players, so that the host knows whose peer a person is (peer_of).

const Person = preload("res://scripts/people/person.gd")
const Fx = preload("res://scripts/people/people_fx.gd")
const StruggleHud = preload("res://scripts/people/struggle_hud.gd")
const ArrowHud = preload("res://scripts/carjack/carjack_hud.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")

signal changed(id: String)                  # person `id` went down, was picked up, put down, got up (every peer)

const GROUP := Person.GROUP
const IMMUNE := 2.0                         # s after getting up when nothing stuns them
const CARRY_REACH := 2.2                    # m from someone down to pick them up
const REACH_SLACK := 1.5                    # m more the host allows (the positions it has are a little late)
const CARRY_SPEED := 0.65                   # times the walking speed, carrying someone
const CARRY_MAX := 45.0                     # s at most carried
const STRUGGLE_KEYS := 8
const STRUGGLE_TIME := 4.5                  # s for them all
const STRUGGLE_RETRY := 1.2                 # s after a failed go before the next
const NPC_STRUGGLE := 6.0                   # s a bot carried takes to wriggle free once its stun is over
const LAG := 0.8                            # s more the host allows a struggle (the keys' way there and back)
const STUCK := 2.0                          # s more than that before the host gives up waiting for an answer

var game: Node3D                            # game.gd
## person id -> {"effect", "t" (s still down), "carrier" (peer, 0 none), "held" (s carried), "immune" (s left), "npc_t"}
var states := {}
var fx: Fx                                  # not on a dedicated server

var _hud: StruggleHud
var _carrying_me := false                   # our player carries someone (the slower walk is on)
var _attempts := {}                         # host: person id -> {"seq", "t"}
var _retry := {}                            # host: person id -> s before their next go
var _cache := {}                            # person id -> node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## The game started here (game.gd, after the game mode's begin).
func begin() -> void:
	if game.mode != "server" and fx == null:
		fx = Fx.new()
		fx.name = "Fx"
		add_child(fx)
	if fx:
		fx.low_quality = game.low_quality
	game.player.person_id = my_id()
	if not game.net.registered.is_connected(_on_registered):
		game.net.registered.connect(_on_registered)
		multiplayer.peer_disconnected.connect(_on_left)


func my_id() -> String:
	return "p:%d" % game.net.me()


static func id_of_peer(peer: int) -> String:
	return "p:%d" % peer


## The peer of person `id`, 0 for a bot.
static func peer_of(id: String) -> int:
	return int(id.substr(2)) if id.begins_with("p:") else 0


## The node of person `id` here, or null.
func person(id: String) -> Node3D:
	var n: Node3D = _cache.get(id)
	if is_instance_valid(n) and n.is_inside_tree() and n.person_id == id:
		return n
	_cache.erase(id)
	for p: Node in get_tree().get_nodes_in_group(GROUP):
		if p.person_id == id:
			_cache[id] = p
			return p as Node3D
	return null


## The persons standing on the map (shots may stun them).
func up_people() -> Array:
	return get_tree().get_nodes_in_group(GROUP).filter(func(p: Node) -> bool: return p.person_up())


func is_down(id: String) -> bool:
	return states.has(id) and (float(states[id]["t"]) > 0.0 or int(states[id]["carrier"]) != 0)


func is_carried(id: String) -> bool:
	return states.has(id) and int(states[id]["carrier"]) != 0


## Whom player `peer` carries ("" nobody).
func carried_by(peer: int) -> String:
	for id: String in states:
		if int(states[id]["carrier"]) == peer:
			return id
	return ""


## Player `peer` may use their hands (fire, draw, get in a vehicle): not down, carried, nor carrying.
func can_act(peer: int) -> bool:
	return not is_down(id_of_peer(peer)) and carried_by(peer) == ""


## The effect `id` is under while their stun lasts ("" none), and how long it has left.
func effect_of(id: String) -> Array:
	var s: Dictionary = states.get(id, {})
	if s.is_empty() or float(s["t"]) <= 0.0:
		return ["", 0.0]
	return [s["effect"], float(s["t"])]


## Someone down on the ground within CARRY_REACH m of `pos` (not carried, not us): their id, "" none.
func down_near(pos: Vector3) -> String:
	var best := ""
	var d := CARRY_REACH
	for id: String in states:
		if id == my_id() or not is_down(id) or is_carried(id):
			continue
		var n := person(id)
		if n and n.global_position.distance_to(pos) < d:
			d = n.global_position.distance_to(pos)
			best = id
	return best


## Host: whether `id` may be stunned now (standing, not down, not just up).
func stunnable(id: String) -> bool:
	var s: Dictionary = states.get(id, {})
	return s.is_empty() or (not is_down(id) and float(s["immune"]) <= 0.0)


## Host: where person `id`'s feet are (global), on foot; null when not (in a vehicle, hidden, gone, a bot on a
## dedicated server, which makes none).
func feet(id: String) -> Variant:
	var peer := peer_of(id)
	if peer == 0:
		var n := person(id)
		return n.global_position if n else null
	if peer == game.net.me():
		if game.mode == "server" or game.driving or game.riding or not game.player.visible:
			return null
		return game.player.global_position
	var a: Node3D = game.net.avatar(peer)
	if a == null or not a.visible or a.riding_in() != null:
		return null
	return a.global_position


## The body of player `peer` here (ours, or their avatar's), or null.
func body_of_peer(peer: int) -> Node3D:
	if peer == game.net.me():
		return game.player.get_node("Body") if game.mode != "server" else null
	var a: Node = game.net.avatar(peer)
	return a.body() if a else null


# ---------------------------------------------------------------- host

## Host: `id` hit by `effect` (data/items.json effects) for `seconds`, by player `by`. False when it does not take.
func hit(id: String, effect: String, seconds: float, by: int) -> bool:
	if not _hosting() or not stunnable(id) or seconds <= 0.0:
		return false
	var peer := peer_of(id)
	if peer != 0:
		var dropped := carried_by(peer)
		if dropped != "":
			_release(dropped, 0.0, "")      # (a carrier stunned drops who they carry)
	_to_all("_c_down", [id, effect, seconds, by])
	return true


func _physics_process(delta: float) -> void:
	var hosting := _hosting()
	for id: String in states.keys():
		var s: Dictionary = states[id]
		var was_down := float(s["t"]) > 0.0
		s["t"] = float(s["t"]) - delta
		s["immune"] = float(s["immune"]) - delta
		if int(s["carrier"]) != 0:
			s["held"] = float(s["held"]) + delta
		if was_down and float(s["t"]) <= 0.0:
			_stun_over(id)
		if hosting and int(s["carrier"]) != 0:
			_host_carried(id, s, delta)
		if float(s["t"]) <= 0.0 and int(s["carrier"]) == 0 and float(s["immune"]) <= 0.0:
			states.erase(id)
	if hosting:
		for id: String in _retry.keys():
			_retry[id] -= delta
			if _retry[id] <= 0.0:
				_retry.erase(id)
		for id: String in _attempts.keys():
			_attempts[id]["t"] += delta
			if _attempts[id]["t"] > STRUGGLE_TIME + LAG + STUCK:
				_attempts.erase(id)
				_retry[id] = STRUGGLE_RETRY
	_update_carrying()


## Host, every tick: `id` carried (state `s`): struggles once the stun is over, too long carried.
func _host_carried(id: String, s: Dictionary, delta: float) -> void:
	if float(s["held"]) > CARRY_MAX:
		_release(id, 0.0, "Too heavy to carry any longer: you put them down.")
		return
	var carrier := int(s["carrier"])
	if carrier != game.net.me() and game.net.active and not game.net.players.has(carrier):
		_release(id, float(s["t"]), "")
		return
	if float(s["t"]) > 0.0:
		return
	var peer := peer_of(id)
	if peer == 0:
		s["npc_t"] = float(s.get("npc_t", 0.0)) + delta
		if s["npc_t"] > NPC_STRUGGLE:
			_release(id, 0.0, "")
	elif not _attempts.has(id) and not _retry.has(id):
		var seq := []
		for i in STRUGGLE_KEYS:
			seq.append(_rng.randi() % ArrowHud.ARROWS.size())
		_attempts[id] = {"seq": seq, "t": 0.0}
		_to_peer(peer, "_c_struggle", [seq, STRUGGLE_TIME])


## Host: `id` put down where their carrier stands, still down for `t_left` s (0: up at once). `text` to the carrier.
func _release(id: String, t_left: float, text: String) -> void:
	var s: Dictionary = states.get(id, {})
	if s.is_empty() or int(s["carrier"]) == 0:
		return
	var carrier := int(s["carrier"])
	var pos: Variant = feet(id_of_peer(carrier))
	var body := body_of_peer(carrier)
	if pos == null:
		var n := person(id)
		pos = n.global_position if n else Vector3.ZERO
	elif body:
		pos = (pos as Vector3) + body.global_basis.x.normalized() * 0.8   # on their right, where the head was
	_attempts.erase(id)
	_retry.erase(id)
	_to_all("_c_release", [id, pos, maxf(t_left, 0.0)])
	if text != "":
		_to_peer(carrier, "_c_note", [text])


@rpc("any_peer", "call_remote", "reliable")
func _h_pick(id: String) -> void:
	if not _hosting():
		return
	var peer := _sender()
	var me := id_of_peer(peer)
	if not can_act(peer) or not is_down(id) or is_carried(id) or id == me:
		return
	var at: Variant = feet(me)
	if at == null:
		_to_peer(peer, "_c_note", ["Get out first."])
		return
	var them: Variant = feet(id)
	if them != null and (at as Vector3).distance_to(them) > CARRY_REACH + REACH_SLACK:
		_to_peer(peer, "_c_note", ["Too far: go up to them."])
		return
	_to_all("_c_carry", [id, peer])


@rpc("any_peer", "call_remote", "reliable")
func _h_put_down() -> void:
	if not _hosting():
		return
	var id := carried_by(_sender())
	if id != "":
		_release(id, float(states[id]["t"]), "")


@rpc("any_peer", "call_remote", "reliable")
func _h_struggle(typed: Array) -> void:
	if not _hosting():
		return
	var id := id_of_peer(_sender())
	var a: Dictionary = _attempts.get(id, {})
	if a.is_empty():
		return
	_attempts.erase(id)
	var seq: Array = a["seq"]
	var wrong := typed.size() > seq.size()
	for i in mini(typed.size(), seq.size()):
		wrong = wrong or int(typed[i]) != int(seq[i])
	var why := ""
	if wrong:
		why = "Wrong key: they hold on."
	elif typed.size() < seq.size() or a["t"] > STRUGGLE_TIME + LAG:
		why = "Too slow: they hold on."
	if why == "":
		_to_peer(_sender(), "_c_struggled", [true, "You broke free!"])
		_release(id, 0.0, "They broke free.")
	else:
		_retry[id] = STRUGGLE_RETRY
		_to_peer(_sender(), "_c_struggled", [false, why])


func _on_registered(peer: int) -> void:
	if not _hosting():
		return
	var rows := []
	for id: String in states:
		var s: Dictionary = states[id]
		if float(s["t"]) > 0.0 or int(s["carrier"]) != 0:
			rows.append([id, s["effect"], maxf(float(s["t"]), 0.01), s["carrier"]])
	if not rows.is_empty():
		_to_peer(peer, "_c_snapshot", [rows])


func _on_left(peer: int) -> void:
	if not _hosting():
		return
	var carried := carried_by(peer)
	if carried != "":
		_release(carried, float(states[carried]["t"]), "")
	var id := id_of_peer(peer)
	if states.has(id):
		_to_all("_c_gone", [id])


# ---------------------------------------------------------------- everyone

@rpc("authority", "call_local", "reliable")
func _c_down(id: String, effect: String, seconds: float, _by: int) -> void:
	var s: Dictionary = states.get(id, {"carrier": 0, "held": 0.0})
	s["effect"] = effect
	s["t"] = seconds
	s["immune"] = 0.0
	states[id] = s
	var n := person(id)
	if n == null:
		return
	n.set_down(true)
	if fx:
		fx.start(id, n, effect, str(ItemDb.effect(effect).get("fx", "")))
	changed.emit(id)


@rpc("authority", "call_local", "reliable")
func _c_carry(id: String, carrier: int) -> void:
	var s: Dictionary = states.get(id, {})
	if s.is_empty():
		return
	s["carrier"] = carrier
	s["held"] = 0.0
	s["npc_t"] = 0.0
	var n := person(id)
	var body := body_of_peer(carrier)
	if n and body:
		n.carry_on(body)
	changed.emit(id)
	if id == my_id() and game.mode != "server":
		game.toast("%s picked you up: struggle free once you come to!" % game.net.player_name(carrier) \
				if game.net.active else "Someone picked you up!")


@rpc("authority", "call_local", "reliable")
func _c_release(id: String, pos: Vector3, t_left: float) -> void:
	var s: Dictionary = states.get(id, {})
	if s.is_empty():
		return
	s["carrier"] = 0
	s["held"] = 0.0
	s["t"] = t_left
	var n := person(id)
	if n:
		n.carry_on(null)
		n.put_at(pos)
	if t_left <= 0.0:
		_stun_over(id)
	changed.emit(id)
	if id == my_id() and _hud:
		if _hud.state != "done":
			_hud.hide_now()


@rpc("authority", "call_local", "reliable")
func _c_gone(id: String) -> void:
	states.erase(id)
	if fx:
		fx.stop(id)
	changed.emit(id)


@rpc("authority", "call_remote", "reliable")
func _c_snapshot(rows: Array) -> void:
	for r: Array in rows:
		_c_down(r[0], r[1], r[2], 0)
		if int(r[3]) != 0:
			_c_carry(r[0], int(r[3]))


## `id`'s stun ran out (or they broke free): the effect off, up again unless still carried, nothing stuns them a while.
func _stun_over(id: String) -> void:
	var s: Dictionary = states.get(id, {})
	if fx:
		fx.stop(id)
	if s.is_empty() or int(s["carrier"]) != 0:
		return
	s["t"] = 0.0
	s["immune"] = IMMUNE
	var n := person(id)
	if n:
		n.set_down(false)
	changed.emit(id)


## Our player carrying someone: slower, no running nor jumping (set and undone only when it changes: Escape from
## Plateau uses the same switches).
func _update_carrying() -> void:
	if game.mode == "server" or game.mode == "":
		return
	var on := carried_by(game.net.me()) != ""
	if on == _carrying_me:
		return
	_carrying_me = on
	var p: CharacterBody3D = game.player
	p.speed_scale = CARRY_SPEED if on else 1.0
	p.can_run = not on
	p.can_jump = not on


@rpc("authority", "call_remote", "reliable")
func _c_struggle(seq: Array, limit: float) -> void:
	if game.mode == "server":
		return
	if _hud == null:
		_hud = StruggleHud.new()
		_hud.name = "Struggle"
		_hud.finished.connect(func(typed: Array) -> void: _to_host("_h_struggle", [typed]))
		game.hud.add_child(_hud)
	_hud.start(seq, limit)


@rpc("authority", "call_remote", "reliable")
func _c_struggled(ok: bool, text: String) -> void:
	if _hud:
		_hud.show_result(ok, text)


@rpc("authority", "call_remote", "reliable")
func _c_note(text: String) -> void:
	if game.mode != "server":
		game.toast(text)


## Whether the struggle screen takes the keys now.
func struggling() -> bool:
	return _hud != null and _hud.taking_keys()


# ---------------------------------------------------------------- the player's keys

## Keys while playing (game.gd, before the game mode's): E picks up someone down, G puts them down; down or carried,
## the hands do nothing. True when taken.
func handle_input(event: InputEvent) -> bool:
	if game.mode == "server" or game.driving or game.riding or game.flying or game.ui_open():
		return false
	var me := my_id()
	if is_down(me):
		# lying there: only looking around (and the menus, the chat, the help...)
		return event.is_action_pressed("interact") or event.is_action_pressed("drop") or event.is_action_pressed("fire") \
				or event.is_action_pressed("jump") or event.is_action_pressed("park_car") \
				or event.is_action_pressed("vehicle_menu") or event.is_action_pressed("inventory")
	var carrying := carried_by(game.net.me())
	if carrying != "":
		if event.is_action_pressed("drop"):
			_to_host("_h_put_down", [])
			return true
		if event.is_action_pressed("interact") or event.is_action_pressed("park_car") \
				or event.is_action_pressed("vehicle_menu"):
			game.toast("Put them down first (%s)." % Settings.key_text("drop"))
			return true
		return false
	if event.is_action_pressed("interact"):
		var id := down_near(game.player.global_position)
		if id != "":
			_to_host("_h_pick", [id])
			return true
	return false


## The line over the hotbar (hotbar_hud.gd): what E or G would do here, or how long we are down.
func prompt() -> String:
	if game.mode == "server" or game.driving or game.riding:
		return ""
	var me := my_id()
	if is_carried(me):
		return "Carried by %s" % game.net.player_name(int(states[me]["carrier"])) if game.net.active else "Carried"
	var e: Array = effect_of(me)
	if e[0] != "":
		return "%s · %.1f s" % [ItemDb.effect(e[0]).get("name", "Stunned"), e[1]]
	var carrying := carried_by(game.net.me())
	if carrying != "":
		var n := person(carrying)
		return "%s put %s down" % [Settings.key_text("drop"), n.person_name() if n else "them"]
	var id := down_near(game.player.global_position)
	if id != "":
		var n := person(id)
		return "%s pick %s up" % [Settings.key_text("interact"), n.person_name() if n else "them"]
	return ""


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
