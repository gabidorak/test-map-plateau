extends "res://scripts/online/job.gd"
## PTA Online's tow truck job (ONLINE_MILESTONES.md O10), a child of the PTA Online mode (scripts/modes/online_mode.gd)
## on every peer, with its own RPCs; the host calls the breakdowns, judges the deliveries and pays.
## - Duty: at Losplatos Custom's tow terminal (the yard behind the shop: a garage of kind "tow", its bay painted there,
##   scripts/losplatos/losplatos_builder.gd), "Tow truck duty": a lent tow truck (scripts/tow_truck.gd) comes out on the
##   bay. Off duty: at the terminal, the truck gone or wrecked, leaving the game.
## - Breakdowns: for each tow driver on duty, one at a time, `first` s after going on duty then `gap` s after each
##   delivery: a car broken down (grey smoke, hazard lights) on the shoulder of a bot car route (world/car_routes.json),
##   min_m to max_m from Losplatos Custom; the waypoint shows it.
## - Hook it (O, back up to its front or back), tow it to Losplatos Custom's yard and set it down there (O): paid
##   `base` + `per_km` a km of the way from where it broke down (straight line, times WAY), the car taken away.
## - Online, the tow truck's driver simulates the car they hook: the host hands it to them (net.gd _car_control) when
##   they ask (_h_hook), if it is a breakdown by their truck's hook.
## Played solo (the PTA Online test), the money is the mode's test_money (the bus job's solo_pay, the hourly cap).

const Car = preload("res://scripts/car.gd")
const Economy = preload("res://scripts/economy.gd")
const Marks = preload("res://scripts/race_marks.gd")
const GroundMap = preload("res://scripts/ground_map.gd")


const DATA := "res://data/jobs.json"
const ROUTES := "res://world/car_routes.json"
const GID := "losplatos-tow"
const TRUCKS := ["tow-truck"]
const MODELS := ["sedan", "hatchback-sports", "suv", "kaykit-hatchback", "family-suv", "compact-hatchback", "renault-zoe",
		"taxi", "van"]
const WAY := 1.3                            # the road's way over the straight line, for the pay
const YARD := 14.0                          # m from the tow bay's middle: delivered there
const HOOK_NEAR := 6.0                      # m from the truck's hook, for the host

var pay := {"base": 300, "per_km": 400, "first": 6.0, "gap": 15.0, "min_m": 250.0, "max_m": 1400.0}
var cap := 30000
var events: Array = []                      # host: [peer, €, text] paid (tests)
var info := {}                              # client: our duty as the host sent it, {} off duty
var _routes: Array = []                     # [[Vector2...]] the bot car routes' points (map)
var _rng := RandomNumberGenerator.new()


## A tow driver on duty (host).
class Duty:
	var peer := 0
	var account := 0
	var username := ""
	var car_id := ""                        # their tow truck (online_mode.gd vehicles)
	var earned := 0
	var towed := 0
	var wait := 0.0                         # s until the next breakdown
	var target: Node3D = null               # the broken-down car
	var from := Vector3.ZERO                # where it broke down
	var hooked := false


func _ready() -> void:
	_rng.randomize()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if data is Dictionary and data.has("tow"):
		for k: String in data["tow"]:
			if k != "about":
				pay[k] = data["tow"][k]
		cap = int(data.get("hour_cap", cap))
	var r: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES)) if FileAccess.file_exists(ROUTES) else null
	if r is Dictionary:
		for k: String in r["routes"]:
			var pts := []
			for p: Array in r["routes"][k]["pts"]:
				pts.append(Vector2(p[0], p[1]))
			_routes.append(pts)
	_register()
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if duties.has(id):
			end_duty(id, "left the game"))


## Its terminal and bay at Losplatos Custom's yard: a garage of kind "tow" (its bay painted by the shop's builder).
func _register() -> void:
	var lp: Node = mode.game.losplatos if mode and mode.game else null
	if lp == null or mode.garages == null:
		return
	var shop: Node3D = lp.shop
	var t: Vector3 = lp.frame * (shop.get_meta("tow_terminal") as Vector3)
	var bay: Transform3D = lp.frame * (shop.get_meta("tow_bay") as Transform3D)
	var size: Vector2 = shop.get_meta("tow_bay_size")
	var facing := (bay.origin - t)
	facing.y = 0.0
	var g := {"id": GID, "name": "Losplatos Custom · towing", "kind": "tow", "no_paint": true, "xy": Vector2(t.x, -t.z),
			"terminal": t, "facing": facing.normalized(), "bays": [{"xf": bay, "w": size.x, "l": size.y}]}
	mode.garages.list.append(g)
	mode.garages.by_id[GID] = g


## Where tow drivers bring the breakdowns (global): the tow bay's middle.
func yard() -> Vector3:
	var g: Dictionary = mode.garages.get_garage(GID)
	return (g["bays"][0]["xf"] as Transform3D).origin if not g.is_empty() else Vector3.ZERO


# ---------------------------------------------------------------- host: duty

func offer(peer: int, _gid: String) -> Array:
	var on: Duty = duties.get(peer)
	var out := [{"duty": "tow", "label": "Tow truck duty", "on": on != null, "note": "On duty now" if on
			else "A lent tow truck comes out on the yellow bay"}]
	if on:
		out.append({"duty": "", "label": "Go off duty", "note": "%s paid this duty, %d cars towed" % [
				Economy.money(on.earned), on.towed]})
	return out


## Host: player `peer` goes on duty at the tow terminal `gid`: [ok, text].
func duty_for(peer: int, gid: String) -> Array:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return [false, "Not logged in."]
	var g: Dictionary = mode.garages.get_garage(gid)
	if g.get("kind", "") != "tow":
		return [false, "Duty starts at Losplatos Custom's tow terminal."]
	if not mode.near(peer, g):
		return [false, "Walk up to the terminal."]
	if duties.has(peer):
		return [false, "You are on duty already."]
	var problem: String = mode.spawn_for(peer, gid, 0, TRUCKS[0])
	if problem != "":
		return [false, problem]
	var d := Duty.new()
	d.peer = peer
	d.account = int(acc["account"])
	d.username = str(acc["username"])
	d.car_id = mode.vehicle_of(d.account)
	d.wait = float(pay["first"])
	duties[peer] = d
	_log("%s is on duty as a tow truck driver" % d.username)
	_watch_truck(d)
	_send_info(d)
	return [true, "On duty: %s to get in; breakdowns come in on the map and the waypoint. Back up to one, %s to hook it." % [
			Settings.key_text("interact"), Settings.key_text("doors")]]


## Host: player `peer` goes off duty (`why` told them).
func end_duty(peer: int, why: String, tell := true) -> void:
	var d: Duty = duties.get(peer)
	if d == null:
		return
	duties.erase(peer)
	if d.target and is_instance_valid(d.target):
		mode.game.remove_vehicles([d.target])
	_log("%s is off duty as a tow truck driver (%s): %d € for %d cars" % [d.username, why if why != "" else "asked",
			d.earned, d.towed])
	if tell:
		mode.send_to(peer, self, "_c_duty", [{}])
		if why != "" and why != "left the game":
			mode.send_to(peer, self, "_c_notice", ["Off duty: %s. %s paid." % [why, Economy.money(d.earned)]])


## Solo / host's own truck: its hook's signals keep `hooked` (online, the driver's messages do).
func _watch_truck(d: Duty) -> void:
	var truck: Node = mode.car_of(d.car_id)
	if truck == null or not truck.has_signal("hooked_car"):
		return
	truck.hooked_car.connect(func(car: Node3D) -> void:
		if duties.get(d.peer) == d and car == d.target:
			d.hooked = true)
	truck.unhooked_car.connect(func(car: Node3D) -> void:
		if duties.get(d.peer) == d and car == d.target:
			d.hooked = false)


func _physics_process(delta: float) -> void:
	if mode == null or not mode.hosting:
		return
	for peer: int in duties.keys():
		var d: Duty = duties[peer]
		var truck: Car = mode.car_of(d.car_id)
		if truck == null or truck.broken:
			end_duty(peer, "your tow truck is gone" if truck == null else "your tow truck is wrecked")
			continue
		if d.target != null and not is_instance_valid(d.target):
			d.target = null
			d.hooked = false
			d.wait = float(pay["gap"])
			_send_info(d)
		if d.target == null:
			d.wait -= delta
			if d.wait <= 0.0:
				breakdown(d)
				d.wait = float(pay["gap"])
			continue
		# delivered: set down (not hooked) in the yard, stopped
		var car: Node3D = d.target
		if not d.hooked and not car.get("towed") and car.global_position.distance_to(yard()) < YARD \
				and (car as RigidBody3D).linear_velocity.length() < 1.0:
			_delivered(d)


## Host: a breakdown for `d` (at `xf` when given: the tests), its car parked there; whether one could be found.
func breakdown(d: Duty, xf: Variant = null) -> bool:
	if xf == null:
		xf = _spot()
	if xf == null:
		return false
	var car: Car = mode.game.park_vehicle(MODELS[_rng.randi() % MODELS.size()], xf)
	car.repairs_itself = false
	car.set_health(car.max_health * 0.4)
	car.set_indicator(2)
	car.set_meta("breakdown", true)
	d.target = car
	d.from = car.global_position
	d.hooked = false
	_log("%s: a breakdown called in at (%.0f, %.0f)" % [d.username, d.from.x, -d.from.z])
	_send_info(d)
	mode.send_to(d.peer, self, "_c_notice", ["Breakdown called in: %d m away (the waypoint)." % roundi(
			d.from.distance_to(yard()))])
	return true


## A spot on a bot car route's shoulder, min_m to max_m from the yard, on asphalt: its transform, or null.
func _spot() -> Variant:
	if _routes.is_empty():
		return null
	var y := yard()
	var home := Vector2(y.x, -y.z)
	var gm: RefCounted = GroundMap.get_map()
	var asphalt: int = gm.materials.find("asphalt") if gm else -1
	for i in 60:
		var pts: Array = _routes[_rng.randi() % _routes.size()]
		if pts.size() < 3:
			continue
		var k := _rng.randi_range(1, pts.size() - 2)
		var p: Vector2 = pts[k]
		var dist := p.distance_to(home)
		if dist < float(pay["min_m"]) or dist > float(pay["max_m"]):
			continue
		var dir: Vector2 = (pts[k + 1] - pts[k - 1]).normalized()
		var s := p + Vector2(dir.y, -dir.x) * 2.4             # on the right, the shoulder
		if gm and gm.material_at(s.x, s.y) != asphalt:
			continue
		var fwd := Vector3(dir.x, 0.0, -dir.y)
		return Transform3D(Basis.looking_at(-fwd, Vector3.UP), Vector3(s.x, Marks.ground(s.x, s.y) + 0.3, -s.y))
	return null


func _delivered(d: Duty) -> void:
	var km := d.from.distance_to(yard()) * WAY / 1000.0
	var due := roundi((float(pay["base"]) + float(pay["per_km"]) * km) / 10.0) * 10
	var car := d.target
	d.target = null
	d.hooked = false
	d.wait = float(pay["gap"])
	mode.game.remove_vehicles([car])
	var text := "Car towed to Losplatos Custom (%.1f km)" % km
	var paid := due
	if mode.game.economy.official:
		var r: Dictionary = await mode.game.economy.pay(d.account, due, text, "tow", cap)
		paid = int(r["data"].get("paid", 0)) if r["ok"] else 0
	elif d.peer == mode.me():
		paid = mode.bus_job.solo_pay(due)
	d.earned += paid
	d.towed += 1
	events.append([d.peer, paid, text])
	_log("%s: %s, %d €" % [d.username, text, paid])
	mode.send_to(d.peer, self, "_c_notice", ["%s: +%s%s" % [text, Economy.money(paid),
			" (hourly cap reached)" if paid < due else ""]])
	_send_info(d)


func _send_info(d: Duty) -> void:
	var t: Variant = d.target.global_position if d.target and is_instance_valid(d.target) else null
	mode.send_to(d.peer, self, "_c_duty", [{"car": d.car_id, "target": t, "target_id": d.target.net_id if t != null
			else "", "earned": d.earned, "towed": d.towed, "yard": yard()}])


func _log(text: String) -> void:
	if mode.game.net.dedicated or OS.get_environment("PLATEAU_JOB_LOG") == "1":
		print(text)


# ---------------------------------------------------------------- the local player

func ask_duty(gid: String, what: String) -> void:
	if what == "":
		mode.to_host(self, "_h_off", [])
	else:
		mode.to_host(self, "_h_duty", [gid])


func on_duty() -> bool:
	return not info.is_empty()


## Our tow truck when we drive it, or null.
func _our_truck() -> Node:
	var c: Node = mode.game.driving
	return c if c and c.has_method("toggle_hook") and on_duty() and c.net_id == str(info.get("car", "")) else null


## The line over the bottom of the screen while on duty in our truck ("" none).
func hint_text() -> String:
	var truck := _our_truck()
	if truck == null:
		return ""
	var k := Settings.key_text("doors")
	if truck.towing:
		var d: float = truck.global_position.distance_to(info.get("yard", Vector3.ZERO))
		if d < YARD:
			return "%s  set it down here, in Losplatos Custom's yard" % k
		return "Towing: bring it to Losplatos Custom's yard (%d m, the waypoint) · %s to set it down" % [roundi(d), k]
	if info.get("target") == null:
		return "Tow truck duty: wait for a breakdown call"
	var tgt: Vector3 = info["target"]
	var dist: float = truck.global_position.distance_to(tgt)
	if dist < 20.0:
		return "Back up to the car: its front or back by the hook, %s to hook it" % k
	return "Breakdown %d m away (the waypoint)" % roundi(dist)


func _process(_delta: float) -> void:
	if mode == null or mode.game.mode == "server" or not on_duty():
		return
	var truck := _our_truck()
	if truck and mode.game.net.active and not truck.hook_gate.is_valid():
		truck.hook_gate = func(car: Node3D) -> void: mode.to_host(self, "_h_hook", [car.net_id])
	# the waypoint: the breakdown, then the yard
	var want: Variant = null
	if truck and truck.towing:
		var y: Vector3 = info.get("yard", Vector3.ZERO)
		want = Vector2(y.x, -y.z)
	elif info.get("target") != null:
		var t: Vector3 = info["target"]
		want = Vector2(t.x, -t.z)
	if want != null and (mode.game.waypoint == null or (mode.game.waypoint as Vector2).distance_to(want) > 3.0):
		mode.game.set_waypoint(want)


## The breakdown on the maps, for tow drivers on duty.
func map_places() -> Array:
	if not on_duty() or info.get("target") == null:
		return []
	var t: Vector3 = info["target"]
	return [["Breakdown", "breakdown", Vector2(t.x, -t.z)]]


# ---------------------------------------------------------------- messages

@rpc("any_peer", "call_remote", "reliable")
func _h_duty(gid: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	mode.send_to(peer, self, "_c_answer", duty_for(peer, gid))


@rpc("any_peer", "call_remote", "reliable")
func _h_off() -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	if duties.has(peer):
		end_duty(peer, "", false)
		mode.send_to(peer, self, "_c_duty", [{}])
		mode.send_to(peer, self, "_c_answer", [true, "Off duty."])


## Online: the tow driver asks to hook car `net_id`: theirs to simulate if it is their breakdown by their hook.
@rpc("any_peer", "call_remote", "reliable")
func _h_hook(net_id: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var d: Duty = duties.get(peer)
	var truck: Node = mode.car_of(d.car_id) if d else null
	if d == null or d.target == null or d.target.net_id != net_id or truck == null \
			or truck.hook_point().distance_to(d.target.global_position) > HOOK_NEAR:
		mode.send_to(peer, self, "_c_notice", ["Only your breakdown can be hooked, by your truck's hook."])
		return
	d.hooked = true
	mode.game.net._car_control.rpc(net_id, peer, 0)
	mode.send_to(peer, self, "_c_hook", [net_id])


@rpc("any_peer", "call_remote", "reliable")
func _h_unhooked(net_id: String) -> void:
	var d: Duty = duties.get(mode._sender())
	if mode.hosting and d and d.target and d.target.net_id == net_id:
		d.hooked = false


@rpc("authority", "call_remote", "reliable")
func _c_hook(net_id: String) -> void:
	var truck := _our_truck()
	var car: Node3D = mode.game.net.cars.get(net_id)
	if truck and car:
		await get_tree().physics_frame          # (ours to simulate from this tick)
		truck.hook(car)
		if not truck.unhooked_car.is_connected(_on_unhooked):
			truck.unhooked_car.connect(_on_unhooked)


func _on_unhooked(car: Node3D) -> void:
	if mode.game.net.active:
		mode.to_host(self, "_h_unhooked", [car.net_id])


@rpc("authority", "call_remote", "reliable")
func _c_duty(now: Dictionary) -> void:
	info = now


@rpc("authority", "call_remote", "reliable")
func _c_notice(text: String) -> void:
	mode.game.toast(text)
