extends Node
## PTA Online's firefighter job (ONLINE_MILESTONES.md O7, ONLINE_MODE.md 5): a child of the PTA Online mode (scripts/
## modes/online_mode.gd) on every peer, with its own RPCs. The host (the official server) sends the alarms, judges the
## water and pays through the accounts service; the player's game only asks and shows. The fires themselves are
## scripts/online/fires.gd's.
## - Duty: at the fire station's terminal (Polytechnique), "Firefighter duty": the fire truck they have out, else one of
##   theirs, else a lent one comes out on a bay (_truck_for, the row says which). Off duty: at the terminal, with U,
##   another vehicle taken out (the truck goes back), the truck wrecked, leaving the game.
## - Alarms: while anyone is on duty, up to `alarms_per_firefighter` per firefighter (at most `max_alarms`) burn at once;
##   a new one goes `alarm_first` s after the first goes on duty, then `alarm_gap` s after the last one was lit or
##   ended. Its spot (world/fires.json) is a kind drawn by `kinds` weights, ALARM_MIN m or more from every firefighter
##   and at most ALARM_MAX m from the nearest one. Nobody on duty: no alarms, and the fires die down (fires.gd CALM).
## - Pay for each fire put out (data/jobs.json "fire"): its kind's price (a fire that spread from another: times
##   `spread_share`), + `quick_bonus` when the first water came within `quick_base` s + `quick_speed` m/s for the way
##   from the nearest firefighter when it was lit (none for a spread one), down to nothing at twice that; shared by the
##   firefighters on duty who sprayed it as their packets of water on it (under `min_share` of it: nothing, the rest
##   shared out), each times up to `owned` as much of their water came from their own truck. Water from players off
##   duty helps put fires out, and pays nobody.
## - Checks against a patched game (the truck is simulated by its driver, ONLINE_MODE.md 6.1): a jump of over TELEPORT m
##   in a tick or a speed over the truck's top speed: their water counts for nothing VOID s. The water itself is flown
##   on the host from the truck's pose and aim (fires.gd). The accounts service cuts what an account earns from all
##   jobs to `hour_cap` an hour.
## The player's game shows the job top right (under the wallet: the nearest fire, how far, how long it has burnt, fires
## burning and put out, money this duty), the money popping in, the waypoint on the nearest fire, the fires on the maps
## (map_places, firefighters only), and a hint over the bottom of the screen (get in the truck, drive to the fire, hose
## it). Played solo (the tools), the money is the mode's test_money (the bus job's solo_pay, the shared hourly cap);
## PLATEAU_JOB_LOG=1 prints the log lines a dedicated server prints.

const Car = preload("res://scripts/car.gd")
const Economy = preload("res://scripts/economy.gd")
const UiStyle = preload("res://scripts/ui_style.gd")

signal answered(ok: bool, text: String)     # the host's answer to our last duty request

const DATA := "res://data/jobs.json"
const TRUCKS := ["fire-truck"]
const ALARM_MIN := 120.0                    # m from every firefighter
const ALARM_MAX := 1500.0                   # m from the nearest one at most
const TELEPORT := 25.0                      # m in a tick
const SPEED_MARGIN := 1.2                   # times the truck's top speed...
const SPEED_SLACK := 3.0                    # ...+ this, m/s...
const TOO_FAST := 0.5                       # ...for this many s
const VOID := 10.0                          # s their water counts for nothing after either
const SPRAY_NEAR := 75.0                    # m from the fire the hint says to hose it
const POP_TIME := 3.5

var mode: Node                              # online_mode.gd, which makes this node
var pay := {}                               # data/jobs.json "fire"
var cap := 30000
var duties := {}                            # host: peer -> Duty
var events: Array = []                      # host: [peer, fire id, €, text] of every share paid (tests)
var info := {}                              # client: our duty as the host sent it, {} off duty
var alarm_first := 10.0
var alarm_gap := 45.0
var _alarm_t := 0.0                         # host: s until an alarm may go
var _alarms := 0                            # host: alarms burning last tick
var _by_kind := {}                          # host: kind -> [spots]
var _rng := RandomNumberGenerator.new()
var _hud: PanelContainer
var _head: Label
var _next: Label
var _stats: Label
var _pops: VBoxContainer
var _hint: Label
var _waypoint: Variant = null
var _target := 0                            # client: id of the fire the waypoint is on
var _look_t := 0.0


## A player on duty (host).
class Duty:
	var peer := 0
	var account := 0
	var username := ""
	var car_id := ""                        # their truck (online_mode.gd vehicles)
	var owned := false
	var earned := 0
	var put_out := 0
	var last := Vector3.ZERO
	var has_last := false
	var fast_t := 0.0
	var void_t := 0.0


func _ready() -> void:
	_rng.randomize()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if data is Dictionary and data.has("fire"):
		pay = data["fire"]
		cap = int(data["hour_cap"])
		alarm_first = float(pay["alarm_first"])
		alarm_gap = float(pay["alarm_gap"])
	else:
		push_error("No PTA Online fire pay: %s missing" % DATA)
	if OS.get_environment("PLATEAU_JOB_CAP") != "":
		cap = int(OS.get_environment("PLATEAU_JOB_CAP"))
	if OS.get_environment("PLATEAU_FIRE_FIRST") != "":
		alarm_first = float(OS.get_environment("PLATEAU_FIRE_FIRST"))
	if OS.get_environment("PLATEAU_FIRE_GAP") != "":
		alarm_gap = float(OS.get_environment("PLATEAU_FIRE_GAP"))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if duties.has(id):
			end_duty(id, "left the game"))


func _exit_tree() -> void:
	for n: Control in [_hud, _hint]:
		if n and is_instance_valid(n):
			n.queue_free()


# ---------------------------------------------------------------- host: duty

## The fire station's (garage `gid`) duty rows for player `peer`: [{"duty": "fire", "label", "note", "on"}], then "Go off
## duty" when they are on duty.
func offer(peer: int, gid: String) -> Array:
	var on: Duty = duties.get(peer)
	var out := [{"duty": "fire", "label": "Firefighter duty", "on": on != null, "note": "On duty now" if on
			else _truck_note(peer, _truck_for(peer, gid))}]
	if on:
		out.append({"duty": "", "label": "Go off duty", "note": "%s paid this duty, %d fires put out" % [
				Economy.money(on.earned), on.put_out]})
	return out


## The truck player `peer` goes on duty in at garage `gid`: the one they have out ("out"), else one of theirs that can
## come out there ("own"), else a lent one ("lent"): {"use", "model", "vehicle" (garage id, 0 lent), "id" (net id of
## the one out, else "")}.
func _truck_for(peer: int, gid: String) -> Dictionary:
	var acc: Dictionary = mode.account(peer)
	var id: String = mode.vehicle_of(int(acc.get("account", -1)))
	var car: Car = mode.car_of(id) if id != "" else null
	if car and car.model_name in TRUCKS and not car.broken:
		return {"use": "out", "model": car.model_name, "vehicle": int(mode.vehicles[id].get("vehicle", 0)), "id": id}
	for v: Dictionary in acc.get("vehicles", []):
		var m := str(v["model"])
		if m in TRUCKS and mode.spawn_problem(peer, gid, int(v["id"]), m, false) == "":
			return {"use": "own", "model": m, "vehicle": int(v["id"]), "id": ""}
	return {"use": "lent", "model": TRUCKS[0], "vehicle": 0, "id": ""}


func _truck_note(peer: int, plan: Dictionary) -> String:
	var more := " · pay ×%s" % str(pay.get("owned", 1.5))
	if plan["use"] == "out":
		return "In the fire truck you have out%s" % (more if int(plan["vehicle"]) > 0 else "")
	var back := ""
	var acc: Dictionary = mode.account(peer)
	var id: String = mode.vehicle_of(int(acc.get("account", -1)))
	if id != "":
		back = " (your %s goes back)" % Car.common_name(str(mode.vehicles[id]["model"]))
	if plan["use"] == "own":
		return "Your fire truck comes out%s%s" % [more, back]
	return "A lent fire truck comes out%s" % back


## Host: player `peer` goes on duty at garage `gid` (the fire station): [ok, text].
func duty_for(peer: int, gid: String) -> Array:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return [false, "Not logged in."]
	var g: Dictionary = mode.garages.get_garage(gid)
	if g.get("kind", "") != "fire":
		return [false, "Duty starts at the fire station."]
	if not mode.near(peer, g):
		return [false, "Walk up to the terminal."]
	if duties.has(peer):
		return [false, "You are on duty already."]
	var plan := _truck_for(peer, gid)
	var id: String = plan["id"]
	if plan["use"] != "out":
		var problem: String = mode.spawn_for(peer, gid, int(plan["vehicle"]), str(plan["model"]))
		if problem != "":
			return [false, problem]
		id = mode.vehicle_of(int(acc["account"]))
	var d := Duty.new()
	d.peer = peer
	d.account = int(acc["account"])
	d.username = str(acc["username"])
	d.car_id = id
	d.owned = int(mode.vehicles[id].get("vehicle", 0)) > 0
	if duties.is_empty():
		_alarm_t = alarm_first
	duties[peer] = d
	_log("%s is on duty as a firefighter (%s fire truck)" % [d.username, "their" if d.owned else "a lent"])
	_send_info(d)
	var keys := "%s to get in, " % Settings.key_text("interact") if plan["use"] != "out" else ""
	return [true, "On duty: %salarms come in on the map and the waypoint; hold %s to hose the flames." % [keys,
			Settings.key_text("fire")]]


## Host: player `peer` goes off duty (`why` told them; "" says nothing).
func end_duty(peer: int, why: String, tell := true) -> void:
	var d: Duty = duties.get(peer)
	if d == null:
		return
	duties.erase(peer)
	_log("%s is off duty as a firefighter (%s): %d € for %d fires" % [d.username, why if why != "" else "asked", d.earned,
			d.put_out])
	if tell:
		mode.send_to(peer, self, "_c_duty", [{}])
		if why != "" and why != "left the game":
			mode.send_to(peer, self, "_c_notice", ["Off duty: %s. %s paid." % [why, Economy.money(d.earned)]])


## Who drives `car`: a peer, 0 nobody (played solo: us when we do).
func driver(car: Car) -> int:
	if mode.game.net.active:
		return int(mode.game.net.driver_of.get(car.net_id, 0))
	return mode.me() if mode.game.driving == car else 0


## Whether player `peer`'s water counts now (not after a teleport or too fast).
func counts(peer: int) -> bool:
	var d: Duty = duties.get(peer)
	return d == null or d.void_t <= 0.0


func _physics_process(delta: float) -> void:
	if mode == null or not mode.hosting:
		return
	for peer: int in duties.keys():
		if duties.has(peer):
			_tick(duties[peer], delta)
	_alarm_tick(delta)


func _tick(d: Duty, delta: float) -> void:
	var car: Car = mode.car_of(d.car_id)
	if car == null or not mode.vehicles.has(d.car_id):
		end_duty(d.peer, "your fire truck went back")
		return
	if car.broken:
		end_duty(d.peer, "your fire truck is wrecked")
		return
	d.void_t -= delta
	var mid := car.to_global(car.extents_center)
	if d.has_last and driver(car) == d.peer:
		var jump := Vector2(mid.x - d.last.x, mid.z - d.last.z).length()
		if jump > maxf(TELEPORT, car.max_speed * delta * 3.0):
			_cheat(d, "teleport", "a jump of %d m" % roundi(jump))
		else:
			d.fast_t = d.fast_t + delta if jump / delta > car.max_speed * SPEED_MARGIN + SPEED_SLACK else 0.0
			if d.fast_t > TOO_FAST:
				d.fast_t = 0.0
				_cheat(d, "too fast", "%d km/h" % roundi(jump / delta * 3.6))
	d.last = mid
	d.has_last = true


func _cheat(d: Duty, kind: String, what: String) -> void:
	if d.void_t <= 0.0:
		_log("%s's fire truck: %s (%s), their water counts for nothing %d s" % [d.username, kind, what, roundi(VOID)])
		mode.send_to(d.peer, self, "_c_event", ["void", "Refused: %s (%s), your water won't count for %d s" % [kind, what,
				roundi(VOID)], 0])
	d.void_t = VOID


## The alarms: as many burning as the firefighters on duty call for, one every alarm_gap s at most.
func _alarm_tick(delta: float) -> void:
	if duties.is_empty():
		_alarms = 0
		return
	var burning := {}
	for f in mode.fires.burning():
		burning[f.alarm] = true
	if burning.size() < _alarms:           # one ended: a breather before the next
		_alarm_t = maxf(_alarm_t, alarm_gap)
	_alarms = burning.size()
	_alarm_t -= delta
	var wanted := mini(duties.size() * int(pay.get("alarms_per_firefighter", 1)), int(pay.get("max_alarms", 6)))
	if _alarms < wanted and _alarm_t <= 0.0:
		_alarm_t = alarm_gap if alarm() != null else 5.0


## Host: lights an alarm: a spot drawn as the job says (or `spot`, the tests), the firefighters told. The fire, or null.
func alarm(spot := {}) -> Object:
	var at: Array = []                      # where the firefighters are (their truck, else them)
	for d: Duty in duties.values():
		var car: Car = mode.car_of(d.car_id)
		var p: Variant = car.global_position if car else mode.position_of(d.peer)
		if p != null:
			at.append(Vector2(p.x, -p.z))
	if spot.is_empty() and OS.get_environment("PLATEAU_FIRE_SPOT") != "":
		spot = nearest_spot(OS.get_environment("PLATEAU_FIRE_SPOT"))
	elif spot.is_empty():
		spot = _draw_spot(at)
	if spot.is_empty():
		return null
	var p := Vector2(spot["x"], spot["y"])
	var near := INF
	for q: Vector2 in at:
		near = minf(near, q.distance_to(p))
	var quick := float(pay["quick_base"]) + (near if near < INF else 0.0) / float(pay["quick_speed"])
	var f = mode.fires.light(spot, quick)
	if f == null:
		return null
	for d: Duty in duties.values():
		mode.send_to(d.peer, self, "_c_event", ["alarm", "ALARM · %s" % f.label(), 0])
	return f


## The free spot of kind `kind` nearest to the fire station, or {} (the tests: PLATEAU_FIRE_SPOT=kind makes every
## alarm go there).
func nearest_spot(kind: String) -> Dictionary:
	var g: Dictionary = mode.garages.get_garage("fire-station")
	var at := Vector2(g["xy"]) if not g.is_empty() else Vector2.ZERO
	var best := {}
	var best_d := INF
	for s: Dictionary in mode.fires.spots:
		var d := at.distance_to(Vector2(s["x"], s["y"]))
		if s["kind"] == kind and d < best_d and mode.fires.free_spot(s):
			best = s
			best_d = d
	return best


## A spot for an alarm: of a kind drawn by the `kinds` weights, ALARM_MIN..ALARM_MAX m from the firefighters at `at`
## (map xy), free (fires.gd free_spot); {} none.
func _draw_spot(at: Array) -> Dictionary:
	if _by_kind.is_empty():
		for s: Dictionary in mode.fires.spots:
			if not _by_kind.has(s["kind"]):
				_by_kind[s["kind"]] = []
			_by_kind[s["kind"]].append(s)
	var weights: Dictionary = pay.get("kinds", {})
	var kinds := weights.keys().filter(func(k: String) -> bool: return _by_kind.has(k))
	for attempt in 6:
		var total := 0.0
		for k: String in kinds:
			total += float(weights[k])
		var r := _rng.randf() * total
		var kind: String = kinds[-1] if not kinds.is_empty() else ""
		for k: String in kinds:
			r -= float(weights[k])
			if r <= 0.0:
				kind = k
				break
		if kind == "":
			return {}
		var list: Array = _by_kind[kind]
		for k in 60:
			var s: Dictionary = list[_rng.randi() % list.size()]
			var p := Vector2(s["x"], s["y"])
			var near := INF
			for q: Vector2 in at:
				near = minf(near, q.distance_to(p))
			if near >= ALARM_MIN and (near <= ALARM_MAX or at.is_empty()) and mode.fires.free_spot(s):
				return s
	return {}


# ---------------------------------------------------------------- host: paying

## Host: fire `f` (fires.gd) was put out: the firefighters who sprayed it are paid their share.
func fire_out(f: Object) -> void:
	var spread: bool = f.alarm != f.id
	var base := float(pay[f.kind]) * (float(pay["spread_share"]) if spread else 1.0)
	var quick := 0.0
	if not spread and f.first_water >= 0.0 and f.quick > 0.0:
		quick = float(pay["quick_bonus"]) * clampf(1.0 - (f.first_water - f.quick) / f.quick, 0.0, 1.0)
	var on := {}                            # peer -> [packets, own packets], firefighters on duty
	var total := 0
	for peer: int in f.water:
		if duties.has(peer):
			on[peer] = f.water[peer]
			total += int(f.water[peer][0])
	for peer: int in on.keys():             # too little water: no share
		if on.size() > 1 and float(on[peer][0]) / total < float(pay["min_share"]):
			total -= int(on[peer][0])
			on.erase(peer)
	if total <= 0:
		_log("Fire %d (%s) put out by nobody on duty: nothing paid" % [f.id, f.label()])
		return
	for peer: int in on:
		var d: Duty = duties[peer]
		var share := float(on[peer][0]) / total
		var own := float(on[peer][1]) / maxf(float(on[peer][0]), 1.0)
		var due := roundi(base * (1.0 + quick) * share * lerpf(1.0, float(pay["owned"]), own))
		var parts := []
		if quick > 0.0:
			parts.append("quick +%d %%" % roundi(quick * 100.0))
		if on.size() > 1:
			parts.append("your share %d %%" % roundi(share * 100.0))
		if own > 0.5:
			parts.append("your truck")
		if spread:
			parts.append("spread")
		var text := "%s out" % f.label() + (" (%s)" % ", ".join(parts) if not parts.is_empty() else "")
		_pay(d, due, text, f)


func _pay(d: Duty, due: int, text: String, f: Object) -> void:
	var paid := due
	if due > 0:
		if mode.game.economy.official:
			var r: Dictionary = await mode.game.economy.pay(d.account, due, text, "fire", cap)
			paid = int(r["data"].get("paid", 0)) if r["ok"] else 0
			if not r["ok"]:
				push_warning("Could not pay %s: %s" % [d.username, r["message"]])
		elif d.peer == mode.me():
			paid = mode.bus_job.solo_pay(due)
	_log("%s: %s, %d €%s" % [d.username, text, paid, " (hourly cap: %d € due)" % due if paid < due else ""])
	d.earned += paid
	d.put_out += 1
	events.append([d.peer, f.id, paid, text])
	mode.send_to(d.peer, self, "_c_event", ["out", text + (" · hourly cap reached" if paid < due else ""), paid])
	_send_info(d)


func _send_info(d: Duty) -> void:
	mode.send_to(d.peer, self, "_c_duty", [{"car": d.car_id, "owned": d.owned, "earned": d.earned, "out": d.put_out}])


func _log(text: String) -> void:
	if mode.game.net.dedicated or OS.get_environment("PLATEAU_JOB_LOG") == "1":
		print(text)


# ---------------------------------------------------------------- the local player

## Asks to go on duty at garage `gid`'s terminal ("" `what`: off duty).
func ask_duty(gid: String, what: String) -> void:
	if what == "":
		mode.to_host(self, "_h_off", [])
	else:
		mode.to_host(self, "_h_duty", [gid])


func on_duty() -> bool:
	return not info.is_empty()


## The fires on the maps, for firefighters on duty: [name, "blaze", map xy].
func map_places() -> Array:
	if not on_duty():
		return []
	return mode.fires.burning().map(func(f: Object) -> Array: return [f.label(), "blaze", f.xy()])


## The burning fire nearest to the player (their truck), or null.
func nearest_fire() -> Object:
	var here: Vector3 = mode.game.driving.global_position if mode.game.driving else mode.game.map_eye()
	var best: Object = null
	var best_d := INF
	for f in mode.fires.burning():
		var d: float = f.pos.distance_to(here)
		if d < best_d:
			best = f
			best_d = d
	return best


func _build_hud() -> void:
	_hud = PanelContainer.new()
	_hud.name = "FireJob"
	_hud.add_theme_stylebox_override("panel", UiStyle.panel(0.72, 10, 12))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size.x = 330
	_hud.add_child(box)
	_head = UiStyle.label("", 20, Color(1.0, 0.6, 0.45), HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(_head)
	_next = UiStyle.label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_next)
	_stats = UiStyle.label("", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(_stats)
	_pops = VBoxContainer.new()
	_pops.add_theme_constant_override("separation", 2)
	box.add_child(_pops)
	mode.game.hud.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_hud.offset_top = 54.0
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.visible = false
	_hint = Label.new()
	_hint.name = "FireJobHint"
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode.game.hud.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 190)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.visible = false


func _process(delta: float) -> void:
	if _hud == null or info.is_empty():
		return
	var f: Object = nearest_fire()
	var here: Vector3 = mode.game.driving.global_position if mode.game.driving else mode.game.map_eye()
	var dist: float = f.pos.distance_to(here) if f else INF
	_look_t -= delta
	if _look_t <= 0.0:                      # the waypoint on the nearest fire
		_look_t = 1.0
		var id: int = f.id if f else 0
		if id != _target:
			_target = id
			if f:
				_waypoint = f.xy()
				mode.game.set_waypoint(_waypoint)
			elif _waypoint != null:
				if mode.game.waypoint == _waypoint:
					mode.game.set_waypoint(null)
				_waypoint = null
	if f:
		var far := "%d m" % roundi(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
		_next.text = "%s · %s · burning %d:%02d" % [f.label(), far, int(f.t) / 60, int(f.t) % 60]
	else:
		_next.text = "No fire now: the next alarm comes soon"
	var n: int = mode.fires.burning().size()
	_stats.text = "%d burning  ·  %d put out  ·  %s this duty" % [n, int(info["out"]), Economy.money(int(info["earned"]))]
	_hint.text = _hint_text(f, dist)
	_hint.visible = _hint.text != "" and not mode.game.ui_open()
	for p in _pops.get_children():
		p.set_meta("t", float(p.get_meta("t")) + delta)
		p.modulate.a = clampf((POP_TIME - float(p.get_meta("t"))) / 0.6, 0.0, 1.0)
		if float(p.get_meta("t")) > POP_TIME:
			p.queue_free()


## What to do now: `f` the nearest fire, `dist` m to it.
func _hint_text(f: Object, dist: float) -> String:
	var car: Car = mode.car_of(str(info.get("car", "")))
	if car == null or f == null:
		return ""
	if mode.game.driving != car:
		var away := car.global_position.distance_to(mode.game.map_eye())
		if away > 15.0:
			return "Walk back to your fire truck (%d m)" % roundi(away)
		return "Get in your fire truck (%s)" % Settings.key_text("interact")
	if dist > SPRAY_NEAR:
		return "Drive to the fire (the waypoint)"
	if car.get("cannon") and car.cannon.firing:
		return "Keep hosing it: %d %% left" % ceili(f.heat * 100.0)
	return "Aim at the flames and hold %s to hose them" % Settings.key_text("fire")


## The hint shown now (tests): "" none.
func hint_text() -> String:
	return _hint.text if _hint and _hint.visible else ""


## The HUD's lines (tests).
func hud_text() -> String:
	if _hud == null or not _hud.visible:
		return ""
	return "%s\n%s\n%s" % [_head.text, _next.text, _stats.text]


# ---------------------------------------------------------------- messages

@rpc("any_peer", "call_remote", "reliable")
func _h_duty(gid: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r := duty_for(peer, gid)
	if not r[0]:
		_log("%s: no fire duty (%s)" % [mode.game.net.player_name(peer), r[1]])
	mode.send_to(peer, self, "_c_answer", r)


@rpc("any_peer", "call_remote", "reliable")
func _h_off() -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	if duties.has(peer):
		end_duty(peer, "you asked")
		mode.send_to(peer, self, "_c_answer", [true, "Off duty."])
	else:
		mode.send_to(peer, self, "_c_answer", [false, "You aren't on duty."])


@rpc("authority", "call_remote", "reliable")
func _c_answer(ok: bool, text: String) -> void:
	answered.emit(ok, text)
	if ok and mode.ui_open():
		mode.close_ui()
	if ok or not mode.ui_open():
		mode.game.toast(text)
	else:
		mode._panel.set_status(text)


@rpc("authority", "call_remote", "reliable")
func _c_duty(now: Dictionary) -> void:
	info = now
	if _hud == null and mode.game.mode != "server":
		_build_hud()
	if _hud == null:
		return
	_hud.visible = not now.is_empty()
	if now.is_empty():
		_hint.visible = false
		if _waypoint != null and mode.game.waypoint == _waypoint:
			mode.game.set_waypoint(null)
		_waypoint = null
		_target = 0
		for p in _pops.get_children():
			p.queue_free()
		return
	_head.text = "FIREFIGHTER · on duty" + ("  ·  your truck ×%s" % str(pay.get("owned", 1.5)) if now["owned"] else "")
	_look_t = 0.0


@rpc("authority", "call_remote", "reliable")
func _c_event(kind: String, text: String, amount: int) -> void:
	if _hud == null:
		if mode.game.mode == "server":
			return
		_build_hud()
	var l := UiStyle.label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	if kind == "out":
		l.text = "+%s  %s" % [Economy.money(amount), text]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.5))
	elif kind == "alarm":
		l.text = text
		l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		_look_t = 0.0
	else:
		l.text = text
		l.add_theme_color_override("font_color", UiStyle.TEXT_WARN)
	l.set_meta("t", 0.0)
	_pops.add_child(l)
	_pops.move_child(l, 0)
	while _pops.get_child_count() > 4:
		_pops.get_child(_pops.get_child_count() - 1).free()


@rpc("authority", "call_remote", "reliable")
func _c_notice(text: String) -> void:
	mode.game.toast(text)
