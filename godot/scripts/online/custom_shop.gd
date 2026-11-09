extends Node
## PTA Online at Losplatos Custom (scripts/losplatos/losplatos.gd: the shop in place of building #758), Main/Mode/
## CustomShop under scripts/modes/online_mode.gd: a player who stops their own vehicle in the workshop's service bay
## and presses U (the vehicle menu's key: E is a turn signal at the wheel) gets its panel (scripts/online/custom_panel.gd):
## - Repair: the bodywork back to new (car.gd health), paid by the damage: Prices.repair (what a wreck costs) times
##   the share of health lost, FIX_MIN at least; nothing to pay when like new. The host charges it (the accounts
##   server's "repair" action: shop.gd _change) and tells the peer simulating the car to mend it.
## - Paint: any of its palette's paints (scripts/paint.gd), at Prices.repaint a coat, as at a garage terminal
##   (shop.gd paint_for at the hidden garage GID, whose terminal is the bay).
## Solo (the PTA Online test), the test wallet pays.

const Car = preload("res://scripts/car.gd")
const Prices = preload("res://scripts/online/prices.gd")
const Paint = preload("res://scripts/paint.gd")
const Economy = preload("res://scripts/economy.gd")
const CustomPanel = preload("res://scripts/online/custom_panel.gd")
const GID := "losplatos"                    # its hidden garage (mode.garages): the bay as the terminal
const FIX_MIN := 50                         # € the least repair
const STILL := 1.5                          # m/s under which a car counts as stopped in the bay

var mode: Node                              # scripts/modes/online_mode.gd
var _panel: CustomPanel
var _mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	var shop: Node = _shop()
	if shop == null or mode == null:
		return
	var g := {"id": GID, "name": shop.NAME, "kind": "custom", "hidden": true, "xy": shop.map_xy(),
			"terminal": shop.bay_point(), "facing": Vector3.FORWARD, "bays": []}
	mode.garages.list.append(g)
	mode.garages.by_id[GID] = g


func _shop() -> Node:
	return mode.game.losplatos if mode and mode.game else null


func _exit_tree() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()


## After the world is in (not on the dedicated server): the panel.
func begin() -> void:
	_panel = CustomPanel.new()
	mode.game.hud.add_child(_panel)
	_panel.fix.connect(func() -> void: request_fix())
	_panel.paint.connect(request_paint)
	_panel.closed.connect(close)


## € to mend `model` from `health` of `max_health` (0: like new).
static func fix_price(model: String, health: float, max_health: float) -> int:
	if max_health <= 0.0 or health >= max_health * 0.995:
		return 0
	var lost := 1.0 - clampf(health / max_health, 0.0, 1.0)
	return maxi(roundi(Prices.repair(model) * lost / 10.0) * 10, FIX_MIN)


# ---------------------------------------------------------------- the local player

## Our vehicle, stopped in the bay with us at the wheel, or null.
func car_in_bay() -> Car:
	var g: Node = mode.game
	var car: Car = g.driving
	var shop: Node = _shop()
	if car == null or shop == null or car.net_id != mode.mine or mode.mine == "":
		return null
	if not shop.in_bay(car.global_position) or car.linear_velocity.length() > STILL:
		return null
	return car


func at_hand() -> bool:
	return car_in_bay() != null


## The line over the bottom of the screen ("" none).
func prompt() -> String:
	var g: Node = mode.game
	var shop: Node = _shop()
	if g.driving == null or shop == null or not shop.in_workshop(g.driving.global_position):
		return ""
	if at_hand():
		return "%s  Losplatos Custom: repair · paint" % Settings.key_text("vehicle_menu")
	if g.driving.net_id != mode.mine:
		return "Losplatos Custom works on your own vehicle"
	return "Losplatos Custom: stop in the yellow bay"


func ui_open() -> bool:
	return _panel != null and _panel.visible


## U in the bay: the panel for our car.
func open() -> void:
	var car := car_in_bay()
	if car == null or _panel == null:
		return
	if not _panel.visible:
		_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show(car)
	mode.game.update_controls()


func _show(car: Car) -> void:
	var model := car.model_name
	_panel.open(Car.display_name(model), roundi(100.0 * car.health / maxf(car.max_health, 1.0)),
			fix_price(model, car.health, car.max_health), Paint.palette(model), car.paint, Prices.repaint(model),
			Settings.key_text("vehicle_menu"))


func close() -> void:
	if not ui_open():
		return
	_panel.close()
	Input.mouse_mode = _mouse
	mode.game.update_controls()


func request_fix() -> void:
	if mode.mine != "":
		mode.to_host(self, "_h_fix", [mode.mine])


func request_paint(colour: String) -> void:
	if mode.mine != "":
		mode.to_host(self, "_h_paint", [mode.mine, colour])


# ---------------------------------------------------------------- host

## Player `peer`'s vehicle `net_id` if it stands in the bay and is theirs (their garage's: not a lent one), else
## {"problem": why not}. With "car" and "vehicle" (its garage id).
func _theirs_in_bay(peer: int, net_id: String) -> Dictionary:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return {"problem": "Not logged in."}
	var v: Dictionary = mode.vehicles.get(net_id, {})
	if v.is_empty() or int(v.get("account", -1)) != int(acc["account"]):
		return {"problem": "Losplatos Custom works on your own vehicle."}
	if int(v.get("vehicle", 0)) <= 0:
		return {"problem": "Lent vehicles are looked after where they were lent."}
	var car: Car = mode.car_of(net_id)
	if car == null or _shop() == null or not _shop().in_bay(car.global_position):
		return {"problem": "Drive it into the yellow bay first."}
	return {"acc": acc, "car": car, "vehicle": int(v["vehicle"]), "model": str(v["model"])}


## Host: player `peer` has their vehicle `net_id` mended: [ok, text].
func fix_for(peer: int, net_id: String) -> Array:
	var t := _theirs_in_bay(peer, net_id)
	if t.has("problem"):
		return [false, t["problem"]]
	var car: Car = t["car"]
	if car.broken:
		return [false, "It's wrecked: it goes back to your garage, repair it there."]
	var price := fix_price(t["model"], car.health, car.max_health)
	if price <= 0:
		return [false, "Its bodywork is like new."]
	var acc: Dictionary = t["acc"]
	if int(acc.get("balance", 0)) < price:
		return [false, "Not enough money: the repair costs %s." % Economy.money(price)]
	var r: Dictionary = await mode.shop._change(peer, acc, {"action": "repair", "vehicle": t["vehicle"], "price": price})
	if not r["ok"]:
		return [false, str(r["message"])]
	car.set_health(car.max_health)
	var sim: int = int(mode.game.net.owner_of.get(net_id, peer)) if mode.game.net.active else peer
	mode.send_to(sim, self, "_c_fixed", [net_id])
	if mode.game.net.dedicated:
		print("%s had their %s mended at Losplatos Custom for %d €" % [acc["username"], t["model"], price])
	return [true, "Your %s is like new (−%s)." % [Car.common_name(t["model"]), Economy.money(price)]]


## Host: player `peer` has their vehicle `net_id` painted `colour`: [ok, text].
func paint_for(peer: int, net_id: String, colour: String) -> Array:
	var t := _theirs_in_bay(peer, net_id)
	if t.has("problem"):
		return [false, t["problem"]]
	return await mode.shop.paint_for(peer, GID, t["vehicle"], colour)


@rpc("any_peer", "call_remote", "reliable")
func _h_fix(net_id: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r: Array = await fix_for(peer, net_id)
	mode.send_to(peer, self, "_c_done", [r[0], r[1]])


@rpc("any_peer", "call_remote", "reliable")
func _h_paint(net_id: String, colour: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r: Array = await paint_for(peer, net_id, colour)
	mode.send_to(peer, self, "_c_done", [r[0], r[1]])


@rpc("authority", "call_remote", "reliable")
func _c_fixed(net_id: String) -> void:
	var car: Car = mode.car_of(net_id)
	if car:
		car.set_health(car.max_health)


@rpc("authority", "call_remote", "reliable")
func _c_done(ok: bool, text: String) -> void:
	if not ui_open():
		mode.game.toast(text)
		return
	var car := car_in_bay()
	if ok and car:
		for i in 3:                         # (a new colour comes with the vehicle's info: online_mode _sync_looks)
			await get_tree().process_frame
		if is_instance_valid(car) and ui_open():
			_show(car)
	_panel.set_status(text)
