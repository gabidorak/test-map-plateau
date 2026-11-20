extends Node
## The police's officers on foot and the arrests (police.gd makes it as Police/Arrest on every peer, so that its RPCs
## have the same path everywhere; the host runs it).
## - Out of the car: a police car on the case of someone wanted (police.gd units; not a roadblock's) within OUT_RANGE m
##   of them, in sight, while they are seen and slow (on foot, or their vehicle under SLOW m/s), is braked (police.gd
##   officer_out: unit.gd OUT); once it stands, its officer gets out (officer.gd; OFFICERS at most after anyone), the
##   siren left on. The suspect away (GIVE_UP m, driving off faster than ESCAPE m/s, lost), or out OUT_MAX s, they walk
##   back and get in; the car goes on (police.gd resume).
## - On foot: they run after them; within reach and in sight they aim AIM s, then fire: the taser within TASER m, the
##   net gun within NET m while the taser reloads. A hit is likelier near and on someone slow (_hit_chance). The shots
##   are items.gd's (bot_fire): everyone sees them, the host stuns. Never in a safe place (game_mode safe_place).
## - In a vehicle nearly stopped: to its driver's door, and they pull: the suspect gets PULL_KEYS arrows, shown one at a
##   time, in PULL_TIME s (people.gd's struggle screen, here); right, they hold on and the officer staggers back
##   (SHOVED s); wrong or late, they are dragged out and tased on the spot.
## - Down: picked up (people.gd npc_pick) and carried to the officer's car (they struggle as anyone carried: people.gd);
##   at its door: arrested (_arrest): the stars off, their weapons seized (items.gd confiscate), the fine of their level
##   (data/prices.json fines; online_mode.gd fine, whatever the wallet holds), and let go before the commissariat
##   (police.gd release: lot sousPrefecture's places).
## - What they cannot get to (no headway for UNREACHABLE s: a fence, a hedge between): a door within PULL_ANYWAY m,
##   they pull from there all the same (through the window); else they go back, and their car lets them out again only
##   REDEPLOY s later.
## - The others see the officers from the host's states (SEND s apart, unreliable); they are made and taken back by
##   reliable calls; a newcomer gets those out (player_registered).
## The officer of police car `unit` is person "o:<unit>", carrier -1 - unit (people.gd).

const Officer = preload("res://scripts/police/foot/officer.gd")
const People = preload("res://scripts/people/people.gd")
const StruggleHud = preload("res://scripts/people/struggle_hud.gd")
const ArrowHud = preload("res://scripts/carjack/carjack_hud.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const Prices = preload("res://scripts/online/prices.gd")
const Car = preload("res://scripts/car.gd")
const Unit = preload("res://scripts/police/unit.gd")

enum { STOPPING, OUT, PURSUE, AIMING, PULL, CARRY, STAGGER, BACK }

const OFFICERS := 2                         # out after one suspect at most
const OUT_RANGE := 22.0                     # m from the suspect a car stops for its officer to get out
const SLOW := 2.0                           # m/s: the suspect slower than this (or their vehicle)
const STOP_SPEED := 0.8                     # m/s: the car about stopped, the officer gets out...
const OUT_TIME := 0.9                       # ...taking this long
const OUT_MAX := 120.0                      # s out at most
const GIVE_UP := 70.0                       # m: the suspect further, they go back
const ESCAPE := 7.0                         # m/s: the suspect's vehicle faster, they go back
const TASER := 11.0                         # m they fire the taser within...
const NET := 8.0                            # ...the net gun
const AIM := 0.7                            # s aiming before a shot
const HIT_NEAR := 0.9                       # chance to hit someone still, point blank...
const HIT_FAR := 0.5                        # ...at the weapon's reach
const HIT_MOVING := 0.6                     # times that on someone running (MOVING m/s or more)
const MOVING := 2.5
const DOOR := 0.9                           # m from the door they pull from
const PULL_KEYS := 6
const PULL_TIME := 3.5                      # s for them all
const LAG := 0.8                            # s more the host allows (the keys' way there and back)
const STUCK := 2.0                          # s more than that before it gives up waiting for an answer
const SHOVED := 2.0                         # s staggering back once the suspect held on
const SEE := 30.0                           # m an officer on foot recognises the suspect (in sight)
const UNREACHABLE := 5.0                    # s without headway to a door (twice that to the suspect): out of reach
const PULL_ANYWAY := 3.5                    # m from the door they pull from all the same
const REDEPLOY := 20.0                      # s before a car whose officer could not get there lets them out again
const SEND := 0.1                           # s between the officers' states to the others
const DEPLOY_EVERY := 0.1                   # s between two looks for cars whose officer gets out

var police: Node                            # police.gd
var mode: Node                              # online_mode.gd
var game: Node3D
var people: Node
var hosting := false
var officers := {}                          # unit -> officer.gd node (every peer)
## host: unit -> {"peer" (suspect), "state", "t" (s in it), "out_t" (s out), "reload" {kind: s}}
var out := {}
var arrests := 0                            # host: how many (tests)

var _pulls := {}                            # host: peer -> {"unit", "seq", "t"}
var _rest := {}                             # host: unit -> s before it lets its officer out again
var _send_t := 0.0
var _deploy_t := 0.0
var _hud: StruggleHud
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_physics_process(false)


func begin(host: bool) -> void:
	hosting = host
	game = mode.game
	people = game.people
	set_physics_process(host)


## Whether an officer on foot sees `target` (global) now (police.gd's look for the suspects).
func sees(target: Vector3, exclude: Array) -> bool:
	for unit: int in out:
		var n: Officer = officers.get(unit)
		if n == null or not n.person_up():
			continue
		var eye := n.global_position + Vector3.UP * 1.6
		if eye.distance_squared_to(target) < SEE * SEE and police.in_sight(eye, target, exclude):
			return true
	return false


# ---------------------------------------------------------------- host

func _physics_process(delta: float) -> void:
	for unit: int in _rest.keys():
		_rest[unit] -= delta
		if _rest[unit] <= 0.0:
			_rest.erase(unit)
	_deploy_t -= delta
	if _deploy_t <= 0.0:                    # (who gets out: DEPLOY_EVERY s apart, not every tick)
		_deploy_t = DEPLOY_EVERY
		for peer: int in police.cases:
			_deploy(peer)
	for unit: int in out.keys():
		_tick(unit, delta)
	for peer: int in _pulls.keys():
		_pulls[peer]["t"] += delta
		if _pulls[peer]["t"] > PULL_TIME + LAG + STUCK:
			_pulled(peer, false, "Too slow: they pull you out!")
	_send_t -= delta
	if _send_t <= 0.0 and not officers.is_empty() and game.net.active:
		_send_t = SEND
		var a := PackedFloat32Array()
		for unit: int in officers:
			a.append(unit)
			a.append_array(PackedFloat32Array((officers[unit] as Officer).state()))
		mode.send_all(self, "_c_states", [a])


## The cars on player `peer`'s case near them while they are slow: stopping, their officers to get out.
func _deploy(peer: int) -> void:
	if not police.cases[peer].seen:
		return
	var s: Dictionary = police.suspect(peer)
	if s.is_empty() or float(s["speed"]) > SLOW or people.is_carried(People.id_of_peer(peer)):
		return
	var after := 0
	for unit: int in out:
		after += 1 if out[unit]["peer"] == peer else 0
	var target: Vector3 = s["pos"]
	for u: Unit in police.units:
		if after >= OFFICERS:
			return
		if out.has(u.index) or _rest.has(u.index) or u.case != peer or u.job in [Unit.OUT, Unit.ROADBLOCK]:
			continue
		var car: Car = u.car
		if car.global_position.distance_squared_to(target) > OUT_RANGE * OUT_RANGE \
				or not police.in_sight(car.global_position + Vector3.UP * 1.4, target + Vector3.UP,
				[car.get_rid()] + ([s["car"].get_rid()] if s["car"] else [])):
			continue
		police.officer_out(u, peer)
		out[u.index] = {"peer": peer, "state": STOPPING, "t": 0.0, "out_t": 0.0,
				"reload": {"taser": 0.0, "net_gun": 0.0}}
		after += 1


func _tick(unit: int, delta: float) -> void:
	var o: Dictionary = out[unit]
	o["t"] += delta
	for k: String in o["reload"]:
		o["reload"][k] = maxf(float(o["reload"][k]) - delta, 0.0)
	var car: Car = police.units[unit].car
	if o["state"] == STOPPING:
		if car.linear_velocity.length() < STOP_SPEED or o["t"] > 6.0:
			_get_out(unit)
		return
	o["out_t"] += delta
	var n: Officer = officers.get(unit)
	if n == null:
		out.erase(unit)
		return
	var peer: int = o["peer"]
	var sid := People.id_of_peer(peer)
	if people.is_down(n.person_id):     # stunned (a player's shot): they drop whoever they carried
		n.aiming = false
		n.stop()
		if o["state"] in [AIMING, PULL, CARRY, STAGGER]:
			_to_state(o, PURSUE)
		_end_pull_of(unit)
		return
	var wanted: bool = police.cases.has(peer)
	var s: Dictionary = police.suspect(peer) if wanted else {}
	var carrying: bool = people.carried_by(-1 - unit) == sid
	if o["state"] != BACK and not carrying and (not wanted or o["out_t"] > OUT_MAX \
			or (s.is_empty() and not people.is_down(sid))):
		_back(unit)
	match o["state"]:
		OUT:
			n.stop()
			if o["t"] > OUT_TIME:
				_to_state(o, PURSUE)
		PURSUE:
			_pursue(unit, o, n, s, sid)
		AIMING:
			_aim(o, n, s, sid)
		PULL:
			if not s.is_empty():
				n.face(s["pos"])
				if float(s["speed"]) > ESCAPE:
					_end_pull_of(unit)
					_to_state(o, PURSUE)
		CARRY:
			if not carrying:
				_to_state(o, PURSUE)
				return
			n.go_to(_door(car), Officer.WALK, 0.2)
			if n.there(0.6) or n.stuck_time() > UNREACHABLE * 3.0:
				_arrest(unit)               # (at its door, or as near as they could get)
		STAGGER:
			n.stop()
			if o["t"] > SHOVED:
				_to_state(o, PURSUE)
		BACK:
			n.weapon = "taser"
			n.go_to(_door(car), Officer.RUN * 0.6, 0.2)
			if n.there(0.5) or n.stuck_time() > UNREACHABLE * 3.0:
				_get_in(unit)


func _pursue(unit: int, o: Dictionary, n: Officer, s: Dictionary, sid: String) -> void:
	if people.is_carried(sid):
		_back(unit)                         # (another officer has them)
		return
	if people.is_down(sid):
		var at: Variant = people.feet(sid)
		if at == null:
			return
		n.weapon = ""
		n.go_to(at, Officer.RUN, 0.7)
		if n.global_position.distance_to(at) < People.CARRY_REACH and people.npc_pick(sid, -1 - unit):
			_to_state(o, CARRY)
		elif n.stuck_time() > UNREACHABLE * 2.0:
			_give_up(unit)
		return
	if s.is_empty():
		return
	var target: Vector3 = s["pos"]
	var d := n.global_position.distance_to(target)
	var veh: Car = s["car"]
	if veh:
		if float(s["speed"]) > ESCAPE or d > GIVE_UP:
			_back(unit)
			return
		n.weapon = "taser"
		var door := _door(veh)
		n.go_to(door, Officer.RUN, 0.2)
		var at_door := n.there(DOOR) or (n.stuck_time() > UNREACHABLE \
				and n.global_position.distance_to(door) < PULL_ANYWAY)
		if at_door and float(s["speed"]) < SLOW and veh.interior.size == Vector3.ZERO and not _pulls.has(o["peer"]):
			_start_pull(unit, o["peer"])
		elif n.stuck_time() > UNREACHABLE and not at_door:
			_give_up(unit)
		return
	if d > GIVE_UP:
		_back(unit)
		return
	var w := _ready_weapon(o, d)
	if w != "" and _sees(n, target) and mode.safe_place(o["peer"], target) == "":
		n.weapon = w
		n.aiming = true
		n.stop()
		n.face(target)
		_to_state(o, AIMING)
		return
	if n.weapon == "":
		n.weapon = "taser"
	n.go_to(target, Officer.RUN, 2.5)
	if n.stuck_time() > UNREACHABLE * 2.0:
		_give_up(unit)


func _aim(o: Dictionary, n: Officer, s: Dictionary, sid: String) -> void:
	if s.is_empty() or s["car"] != null or people.is_down(sid):
		n.aiming = false
		_to_state(o, PURSUE)
		return
	var target: Vector3 = s["pos"]
	n.face(target)
	var d := n.global_position.distance_to(target)
	if d > (TASER if n.weapon == "taser" else NET) + 2.0 or not _sees(n, target):
		n.aiming = false
		_to_state(o, PURSUE)
		return
	if o["t"] < AIM:
		return
	var chest := target + Vector3.UP * 1.0
	var kind := n.weapon
	if _rng.randf() < _hit_chance(d, float(s["speed"]), TASER if kind == "taser" else NET):
		game.items.bot_fire(n.person_id, kind, n.muzzle(), chest, sid)
	else:
		var side := (chest - n.muzzle()).cross(Vector3.UP).normalized()
		var miss := chest + side * _rng.randf_range(1.0, 2.0) * (1.0 if _rng.randf() < 0.5 else -1.0) \
				+ Vector3.UP * _rng.randf_range(-0.6, 0.6)
		game.items.bot_fire(n.person_id, kind, n.muzzle(), miss, "")
	o["reload"][kind] = float(ItemDb.field(kind, "reload", 2.0))
	n.aiming = false
	_to_state(o, PURSUE)


## The chance a shot at `d` m hits someone going at `speed` m/s, with a weapon reaching `reach` m.
static func _hit_chance(d: float, speed: float, reach: float) -> float:
	var p := lerpf(HIT_NEAR, HIT_FAR, clampf(d / reach, 0.0, 1.0))
	return p * (HIT_MOVING if speed >= MOVING else 1.0)


## The weapon loaded that reaches `d` m ("" none): the taser first, the net gun while it reloads.
func _ready_weapon(o: Dictionary, d: float) -> String:
	if float(o["reload"]["taser"]) <= 0.0 and d < TASER:
		return "taser"
	if float(o["reload"]["net_gun"]) <= 0.0 and d < NET:
		return "net_gun"
	return ""


func _sees(n: Officer, target: Vector3) -> bool:
	return police.in_sight(n.muzzle(), target + Vector3.UP * 1.0, [])


## Where an officer gets in and out of `car`, and pulls a driver out: by its driver's door (its left, +X), on the ground.
static func _door(car: Car) -> Vector3:
	var seat: Vector3 = car.driver_seat if car.driver_seat != Vector3.ZERO else car.extents_center
	return car.to_global(Vector3(car.extents_center.x + car.half_extents.x + 0.45, 0.0, seat.z))


func _to_state(o: Dictionary, state: int) -> void:
	o["state"] = state
	o["t"] = 0.0


## Officer `unit` cannot get where they would: back to the car, which lets them out again only REDEPLOY s later.
func _give_up(unit: int) -> void:
	_rest[unit] = REDEPLOY
	_back(unit)


func _back(unit: int) -> void:
	var o: Dictionary = out[unit]
	_end_pull_of(unit)
	var n: Officer = officers.get(unit)
	if n:
		n.aiming = false
	_to_state(o, BACK)


# ---------------------------------------------------------------- out, in

func _get_out(unit: int) -> void:
	var car: Car = police.units[unit].car
	car.driver_away = true
	_to_state(out[unit], OUT)
	var at := _door(car)
	var f: Vector3 = car.global_basis.x
	_to_all("_c_out", [unit, at, atan2(f.x, f.z)])


func _get_in(unit: int) -> void:
	out.erase(unit)
	_to_all("_c_in", [unit])
	police.units[unit].car.driver_away = false
	police.resume(police.units[unit])


@rpc("authority", "call_remote", "reliable")
func _c_out(unit: int, at: Vector3, facing: float) -> void:
	if officers.has(unit):
		return
	var n := Officer.new()
	n.setup(unit, at, facing, hosting)
	game.add_child(n)
	officers[unit] = n
	people.register_carrier(-1 - unit, n)


@rpc("authority", "call_remote", "reliable")
func _c_in(unit: int) -> void:
	var n: Officer = officers.get(unit)
	officers.erase(unit)
	people.register_carrier(-1 - unit, null)
	if n:
		n.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _c_states(a: PackedFloat32Array) -> void:
	var k := 0
	while k + 6 < a.size():
		var n: Officer = officers.get(int(a[k]))
		if n:
			n.apply_state([a[k + 1], a[k + 2], a[k + 3], a[k + 4], a[k + 5], int(a[k + 6])])
		k += 7


## Host: player `peer` came in: the officers out.
func player_registered(peer: int) -> void:
	if not hosting:
		return
	for unit: int in officers:
		var n: Officer = officers[unit]
		mode.send_to(peer, self, "_c_out", [unit, n.global_position, n.yaw])


# ---------------------------------------------------------------- pulled out of the vehicle

func _start_pull(unit: int, peer: int) -> void:
	var seq := []
	for i in PULL_KEYS:
		seq.append(_rng.randi() % ArrowHud.ARROWS.size())
	_pulls[peer] = {"unit": unit, "seq": seq, "t": 0.0}
	_to_state(out[unit], PULL)
	mode.send_to(peer, self, "_c_pull", [seq, PULL_TIME])


@rpc("any_peer", "call_remote", "reliable")
func _h_pull(typed: Array) -> void:
	if not hosting:
		return
	var peer := _sender()
	var a: Dictionary = _pulls.get(peer, {})
	if a.is_empty():
		return
	var seq: Array = a["seq"]
	var wrong := typed.size() > seq.size()
	for i in mini(typed.size(), seq.size()):
		wrong = wrong or int(typed[i]) != int(seq[i])
	if wrong:
		_pulled(peer, false, "Wrong key: they pull you out!")
	elif typed.size() < seq.size() or a["t"] > PULL_TIME + LAG:
		_pulled(peer, false, "Too slow: they pull you out!")
	else:
		_pulled(peer, true, "You held on!")


## Host: player `peer`'s pull is over: held on (`ok`: the officer staggers back) or dragged out and tased.
func _pulled(peer: int, ok: bool, text: String) -> void:
	var a: Dictionary = _pulls.get(peer, {})
	_pulls.erase(peer)
	if a.is_empty():
		return
	mode.send_to(peer, self, "_c_pulled", [ok, text])
	var unit: int = a["unit"]
	if not out.has(unit):
		return
	_to_state(out[unit], STAGGER if ok else PURSUE)
	if ok:
		return
	var n: Officer = officers.get(unit)
	mode.send_to(peer, self, "_c_drag_out", [])
	if n:
		var sid := People.id_of_peer(peer)
		n.weapon = "taser"
		var ahead := Vector3(sin(n.yaw), 0.0, cos(n.yaw))
		game.items.bot_fire(n.person_id, "taser", n.muzzle(), n.global_position + ahead * 0.6 + Vector3.UP * 0.9, sid)
		out[unit]["reload"]["taser"] = float(ItemDb.field("taser", "reload", 2.0))


## Host: the pull officer `unit` was at, if any, called off (the suspect hears no more of it).
func _end_pull_of(unit: int) -> void:
	for peer: int in _pulls.keys():
		if _pulls[peer]["unit"] == unit:
			_pulls.erase(peer)
			mode.send_to(peer, self, "_c_pull_off", [])


@rpc("authority", "call_remote", "reliable")
func _c_pull(seq: Array, limit: float) -> void:
	if game.mode == "server":
		return
	if _hud == null:
		_hud = StruggleHud.new()
		_hud.name = "PulledOut"
		_hud.finished.connect(func(typed: Array) -> void:
			mode.to_host(self, "_h_pull", [typed])
			game.update_controls())
		game.hud.add_child(_hud)
	_hud.start(seq, limit)
	game.toast("A police officer is pulling you out: hold on!")
	game.update_controls()


@rpc("authority", "call_remote", "reliable")
func _c_pulled(ok: bool, text: String) -> void:
	if _hud:
		_hud.show_result(ok, text)
	game.update_controls()


@rpc("authority", "call_remote", "reliable")
func _c_pull_off() -> void:
	if _hud and _hud.state != "":
		_hud.hide_now()
	game.update_controls()


## Dragged out of the vehicle we drive or ride in.
@rpc("authority", "call_remote", "reliable")
func _c_drag_out() -> void:
	if game.driving:
		game.exit_car()
	elif game.riding:
		game.leave_ride()
	game.update_controls()


## Whether the pull screen takes the keys now (online_mode.gd ui_open: the vehicle takes none meanwhile).
func struggling() -> bool:
	return _hud != null and _hud.taking_keys()


# ---------------------------------------------------------------- the arrest

## Host: officer `unit` puts the suspect they carry in their car: arrested.
func _arrest(unit: int) -> void:
	var o: Dictionary = out[unit]
	var peer: int = o["peer"]
	var sid := People.id_of_peer(peer)
	var level: int = police.cases[peer].level if police.cases.has(peer) else 1
	_to_state(o, BACK)
	arrests += 1
	people.take_away(sid)
	var seized: Array = game.items.confiscate(peer)
	police.arrested(peer)
	var release: Transform3D = police.release
	var f := release.basis.z                # (the player walks and looks along -Z of their yaw)
	mode.send_to(peer, self, "_c_arrested", [release.origin, atan2(-f.x, -f.z)])
	var fine := Prices.fine(level)
	var paid := 0
	if fine > 0:
		paid = await mode.fine(peer, fine, "Fine: arrested by the police")
	var lines := PackedStringArray()
	for row: Array in seized:
		if ItemDb.is_weapon(str(row[0])):
			lines.append(ItemDb.item_name(str(row[0])))
	var text := "Arrested. Fine: %d €" % paid
	if not lines.is_empty():
		text += " · seized: %s" % ", ".join(lines)
	mode.send_to(peer, self, "_c_note", [text])


## Arrested: let go by the sous-préfecture, at `pos` facing `facing`.
@rpc("authority", "call_remote", "reliable")
func _c_arrested(pos: Vector3, facing: float) -> void:
	if game.mode == "server":
		return
	if game.driving:
		game.exit_car()
	elif game.riding:
		game.leave_ride()
	game.player.teleport(pos, facing)
	game.update_controls()


@rpc("authority", "call_remote", "reliable")
func _c_note(text: String) -> void:
	if game.mode != "server":
		game.toast(text)


# ---------------------------------------------------------------- the way between the peers

## Here (the host makes the officers too, a dedicated server as well) and on every player's game.
func _to_all(method: StringName, args: Array) -> void:
	callv(method, args)
	mode.send_all(self, method, args)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else mode.me()
