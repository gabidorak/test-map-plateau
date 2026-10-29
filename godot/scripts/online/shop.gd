extends Node
## PTA Online's shop (ONLINE_MILESTONES.md O4, ONLINE_MODE.md 4): a child of the PTA Online mode (scripts/modes/
## online_mode.gd) on every peer, with its own RPCs. Buying, repairing and painting are asked by the player and judged
## by the host (the official server), which charges the price through the accounts service (economy.gd vehicle_change:
## the vehicle and the money change in one go) and only then answers; prices are data/prices.json's
## (scripts/online/prices.gd), the same in every build, but only the server's count.
## - Prestige Motors (the showroom of scripts/dealership.gd): E by Jean-Claude or at a podium's price stand opens the
##   catalogue (the cars, the biplane, the horse, the jet-ski, the truck: by tier). A vehicle bought goes in the
##   player's garage and comes out on the shop's bays by the door (garage DELIVERY), sending their vehicle out back;
##   when it can't (the bays taken, the jet-ski: no lake there), it waits in the garage. The stands and Jean-Claude
##   quote the online prices.
## - The bus depot and the fire station sell their work vehicles at their terminal (the garage panel's "Buy" rows),
##   out on their own bays.
## - At any garage terminal: repair a wrecked vehicle (Prices.repair), paint one (Prices.repaint a coat, a colour of
##   scripts/paint.gd); a vehicle out shows its new colour on every peer at once.
## - Wrecks (online_mode.gd: a player's vehicle broken on the map): an owned one is marked wrecked in the garage.
## Played solo by the tools, the garage and the money are the mode's test_garage and test_money.

const Prices = preload("res://scripts/online/prices.gd")
const Paint = preload("res://scripts/paint.gd")
const Car = preload("res://scripts/car.gd")
const Economy = preload("res://scripts/economy.gd")
const LabelFit = preload("res://scripts/label_fit.gd")

signal answered(ok: bool, text: String)     # the host's answer to our last purchase, repair or repaint

const PRESTIGE := "prestige"                # Prices place of Prestige Motors' catalogue
const PRESTIGE_NAME := "Prestige Motors"    # its showroom's dealer
const DELIVERY := "prestige-motors"         # the garage of its bays (world/garages.json)
const TALK_REACH := 3.0                     # m from Jean-Claude for E
const STAND_REACH := 1.8                    # m from a podium's price stand for E
const STAND_OUT := 3.6                      # m from a podium's centre to its price stand (interior_builder.gd PODIUM + 0.6)

var mode: Node                              # online_mode.gd, which makes this node
var _busy := {}                             # host: peer -> true while the accounts service is asked for them


func begin() -> void:
	for s in _showrooms():                  # online prices on the stands and in Jean-Claude's mouth
		for c: Dictionary in s.cars:
			var old := "%s\n%s" % [Car.display_name(c["model"]), c["price"]]
			var price := Prices.price(c["model"])
			c["price"] = Economy.money(price) if price > 0 else "not sold in PTA Online"
			for l: Label3D in s.find_children("*", "Label3D", false, false):
				if l.text == old:
					LabelFit.set_text(l, "%s\n%s" % [Car.display_name(c["model"]), c["price"]])


func _showrooms() -> Array:
	return get_tree().get_nodes_in_group("showroom").filter(func(s: Node) -> bool: return s.dealer == PRESTIGE_NAME)


# ---------------------------------------------------------------- the local player

## Whether E opens Prestige Motors' catalogue: on foot in the showroom, by Jean-Claude or a podium's price stand.
func catalogue_at_hand() -> bool:
	var game: Node = mode.game
	if game.driving or game.riding or game.flying or game.mode == "server":
		return false
	var p: Vector3 = game.player.global_position
	for s in _showrooms():
		if not s.is_inside(p):
			continue
		if s.salesman and s.salesman.visible and _flat(s.salesman.global_position, p) <= TALK_REACH:
			return true
		for c: Dictionary in s.cars:
			var xf: Transform3D = c["xf"]
			if _flat(xf * Vector3(0.0, 0.0, STAND_OUT), p) <= STAND_REACH:
				return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func open_catalogue() -> void:
	mode.open_panel()
	mode._panel.open_catalogue(PRESTIGE_NAME, "Bonjour! Everything here is for sale. A vehicle bought comes out on the "
			+ "bays by the door, and stays in your garage.", Settings.key_text("interact"))
	mode.game.update_controls()
	mode.to_host(self, "_h_catalogue", [])


## Buys `model` at `where` (PRESTIGE, or the bus depot's or fire station's garage id).
func buy(where: String, model: String) -> void:
	mode.to_host(self, "_h_buy", [where, model])


## Repairs our wrecked garage vehicle `vehicle`, at garage `gid`'s terminal.
func repair(gid: String, vehicle: int) -> void:
	mode.to_host(self, "_h_repair", [gid, vehicle])


## Paints our garage vehicle `vehicle` in paint `colour` ("" its own), at garage `gid`'s terminal.
func repaint(gid: String, vehicle: int, colour: String) -> void:
	mode.to_host(self, "_h_paint", [gid, vehicle, colour])


# ---------------------------------------------------------------- host

## Prestige Motors' catalogue for account `acc`: [{"model", "label", "price", "tier", "owned"}].
func catalogue(acc: Dictionary) -> Array:
	var out := []
	for m: String in Prices.catalogue(PRESTIGE):
		var owned := 0
		for v: Dictionary in acc.get("vehicles", []):
			owned += 1 if v["model"] == m else 0
		out.append({"model": m, "label": Car.display_name(m), "price": Prices.price(m), "tier": Prices.tier(m),
				"owned": owned})
	return out


## Whether the host sees player `peer` inside Prestige Motors.
func in_showroom(peer: int) -> bool:
	var p: Variant = mode.position_of(peer)
	if p == null:
		return false
	for s in _showrooms():
		if s.is_inside(p):
			return true
	return false


## Host: player `peer` buys `model` at `where`: [ok, text].
func buy_for(peer: int, where: String, model: String) -> Array:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return [false, "Not logged in."]
	var g: Dictionary = {} if where == PRESTIGE else mode.garages.get_garage(where)
	var place: String = PRESTIGE if where == PRESTIGE else str(g.get("kind", ""))
	var price := Prices.price(model)
	if price <= 0 or Prices.sold_at(model) != place or model in mode.ARMED:
		return [false, "That isn't sold here."]
	if where == PRESTIGE and not in_showroom(peer):
		return [false, "Walk into Prestige Motors to buy it."]
	if where != PRESTIGE and not mode.near(peer, g):
		return [false, "Walk up to the terminal to buy it."]
	var balance := int(acc.get("balance", 0))
	if balance < price:
		return [false, _too_poor(model, price, balance)]
	var r := await _change(peer, acc, {"action": "add", "model": model, "price": price})
	if not r["ok"]:
		return [false, _too_poor(model, price, int(r["data"].get("balance", balance))) if r["error"] == "too_poor"
				else str(r["message"])]
	var name := Car.common_name(model)
	var paid := "the %s is yours (−%s)" % [name, Economy.money(price)]
	_log("%s bought a %s for %d €" % [acc["username"], model, price])
	var problem: String = mode.spawn_for(peer, DELIVERY if where == PRESTIGE else where, int(r["data"]["vehicle"]), model,
			false)
	if problem == "":
		return [true, "Félicitations, %s! Out on a bay: %s to get in." % [paid, Settings.key_text("interact")]]
	if model == "jet-ski":
		problem = "it goes on a lake: get it out at %s" % _lake_garage()
	else:
		problem = problem.trim_suffix(".").to_lower() + ": get it out at a garage terminal"
	return [true, "Félicitations, %s! It waits in your garage (%s)." % [paid, problem]]


## Host: player `peer` repairs their wrecked vehicle `vehicle` at garage `gid`: [ok, text].
func repair_for(peer: int, gid: String, vehicle: int) -> Array:
	var acc: Dictionary = mode.account(peer)
	var v := _at_terminal(peer, acc, gid, vehicle)
	if v.has("problem"):
		return [false, v["problem"]]
	if not v.get("wrecked", false):
		return [false, "It isn't wrecked."]
	var price := Prices.repair(v["model"])
	if int(acc.get("balance", 0)) < price:
		return [false, "Not enough money: the repair costs %s." % Economy.money(price)]
	var r := await _change(peer, acc, {"action": "repair", "vehicle": vehicle, "price": price})
	if not r["ok"]:
		return [false, str(r["message"])]
	_log("%s repaired their %s for %d €" % [acc["username"], v["model"], price])
	return [true, "Your %s is repaired (−%s)." % [Car.common_name(v["model"]), Economy.money(price)]]


## Host: player `peer` paints their vehicle `vehicle` in `colour` at garage `gid`: [ok, text].
func paint_for(peer: int, gid: String, vehicle: int, colour: String) -> Array:
	var acc: Dictionary = mode.account(peer)
	var v := _at_terminal(peer, acc, gid, vehicle)
	if v.has("problem"):
		return [false, v["problem"]]
	var model := str(v["model"])
	if not Paint.can_paint(model):
		return [false, "This one keeps its own colours."]
	if colour != "" and Paint.colour(model, colour) == null:
		return [false, "No such colour."]
	if colour == str(v.get("colour", "")):
		return [false, "It is that colour already."]
	var price := Prices.repaint(model)
	if int(acc.get("balance", 0)) < price:
		return [false, "Not enough money: a coat costs %s." % Economy.money(price)]
	var r := await _change(peer, acc, {"action": "colour", "vehicle": vehicle, "colour": colour, "price": price})
	if not r["ok"]:
		return [false, str(r["message"])]
	var id: String = mode.out_on_map(int(acc["account"]), vehicle)
	if id != "" and mode.vehicles.has(id):
		mode.vehicles[id]["colour"] = colour
		mode.share(id)
	_log("%s painted their %s %s for %d €" % [acc["username"], model, colour if colour != "" else "back", price])
	return [true, "Your %s is %s now (−%s)." % [Car.common_name(model),
			Paint.label(model, colour).to_lower() if colour != "" else "in its own colour again", Economy.money(price)]]


## Host: player vehicle `id` (online_mode.gd vehicles) broke on the map: an owned one is wrecked in its garage; its
## driver or owner hears about it.
func wrecked(id: String) -> void:
	var v: Dictionary = mode.vehicles[id]
	var name := Car.common_name(v["model"])
	var text := "The lent %s is wrecked: it goes back in %d s, take another one at its garage." % [name, roundi(mode.tow_time)]
	if int(v["vehicle"]) > 0:
		var r := await _ledger(int(v["account"]), {"action": "wreck", "vehicle": int(v["vehicle"])})
		if not r["ok"]:
			push_warning("Could not mark %s's %s wrecked: %s" % [v["owner"], v["model"], r["message"]])
		text = "Your %s is wrecked: towed back to your garage in %d s. Repair it at a garage terminal (%s)." % [name,
				roundi(mode.tow_time), Economy.money(Prices.repair(v["model"]))]
	_log("%s's %s is wrecked" % [v["owner"], v["model"]])
	var told := {}
	for peer: int in [int(v["peer"]), int(mode.game.net.driver_of.get(id, 0))]:
		if peer != 0 and not told.has(peer):
			told[peer] = true
			mode.send_to(peer, self, "_c_notice", [text])


## The garage vehicle `vehicle` of account `acc` if player `peer` may work on it at garage `gid`'s terminal, else
## {"problem": why not}.
func _at_terminal(peer: int, acc: Dictionary, gid: String, vehicle: int) -> Dictionary:
	if acc.is_empty():
		return {"problem": "Not logged in."}
	var g: Dictionary = mode.garages.get_garage(gid)
	if g.is_empty():
		return {"problem": "No such garage."}
	if not mode.near(peer, g):
		return {"problem": "Walk up to the garage's terminal."}
	for v: Dictionary in acc.get("vehicles", []):
		if int(v["id"]) == vehicle:
			return v
	return {"problem": "That vehicle isn't in your garage."}


func _too_poor(model: String, price: int, balance: int) -> String:
	return "Not enough money: the %s costs %s, you have %s." % [Car.common_name(model),
			Economy.money(price), Economy.money(balance)]


## The public garage whose terminal has a lake within the jet-ski's reach.
func _lake_garage() -> String:
	for g: Dictionary in mode.garages.list:
		if g["kind"] == "public" and mode._water_spot(g) != null:
			return str(g["name"])
	return "a garage by a lake"


## Host: a change of player `peer`'s garage (one request at a time per player).
func _change(peer: int, acc: Dictionary, change: Dictionary) -> Dictionary:
	if _busy.has(peer):
		return {"ok": false, "error": "busy", "message": "One thing at a time.", "data": {}}
	_busy[peer] = true
	var r := await _ledger(int(acc["account"]), change)
	_busy.erase(peer)
	return r


## Host: changes a garage vehicle of account `account_id`, charging `change["price"]` (economy.gd vehicle_change);
## played solo, the mode's test garage and money.
func _ledger(account_id: int, change: Dictionary) -> Dictionary:
	if mode.game.economy.official:
		return await mode.game.economy.vehicle_change(account_id, change)
	var price := int(change.get("price", 0))
	if price > mode.test_money:
		return {"ok": false, "error": "too_poor", "message": "Not enough money.", "data": {"balance": mode.test_money}}
	var vehicle := int(change.get("vehicle", 0))
	if change["action"] == "add":
		for v: Dictionary in mode.test_garage:
			vehicle = maxi(vehicle, int(v["id"]))
		vehicle += 1
		mode.test_garage.append({"id": vehicle, "model": change["model"], "colour": "", "wrecked": false, "upgrades": {}})
	else:
		var found := {}
		for v: Dictionary in mode.test_garage:
			if int(v["id"]) == vehicle:
				found = v
		if found.is_empty():
			return {"ok": false, "error": "no_vehicle", "message": "No such vehicle in this garage.", "data": {}}
		match change["action"]:
			"repair":
				found["wrecked"] = false
			"wreck":
				found["wrecked"] = true
			"colour":
				found["colour"] = change["colour"]
	mode.test_money -= price
	mode.game.economy.balance = mode.test_money
	mode.game.economy.wallet_changed.emit()
	return {"ok": true, "error": "", "message": "", "data": {"vehicle": vehicle, "balance": mode.test_money}}


func _log(text: String) -> void:
	if mode.game.net.dedicated:
		print(text)


# ---------------------------------------------------------------- messages

@rpc("any_peer", "call_remote", "reliable")
func _h_catalogue() -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	if mode.game.economy.official:
		await mode.game.economy.refresh(peer)
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return
	mode.send_to(peer, self, "_c_catalogue", [catalogue(acc), int(acc.get("balance", 0)), "" if in_showroom(peer)
			else "Walk into Prestige Motors to buy."])


@rpc("any_peer", "call_remote", "reliable")
func _h_buy(where: String, model: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r: Array = await buy_for(peer, where, model)
	if not r[0]:
		var p: Variant = mode.position_of(peer)
		_log("%s: no %s bought at %s (%s) seen at %s" % [mode.game.net.player_name(peer), model, where, r[1],
				"(%.0f, %.1f, %.0f)" % [p.x, p.y, p.z] if p != null else "nowhere"])
	mode.send_to(peer, self, "_c_done", [r[0], r[1], r[0]])


@rpc("any_peer", "call_remote", "reliable")
func _h_repair(gid: String, vehicle: int) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r: Array = await repair_for(peer, gid, vehicle)
	mode.send_to(peer, self, "_c_done", [r[0], r[1], false])
	if r[0]:
		mode.send_garage(peer, gid, r[1])


@rpc("any_peer", "call_remote", "reliable")
func _h_paint(gid: String, vehicle: int, colour: String) -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	var r: Array = await paint_for(peer, gid, vehicle, colour)
	if not r[0]:
		_log("%s: no repaint at %s (%s)" % [mode.game.net.player_name(peer), gid, r[1]])
	mode.send_to(peer, self, "_c_done", [r[0], r[1], false])
	if r[0]:
		mode.send_garage(peer, gid, r[1])


@rpc("authority", "call_remote", "reliable")
func _c_catalogue(entries: Array, balance: int, message: String) -> void:
	var panel: Node = mode._panel
	if panel and panel.kind == "catalogue":
		panel.show_catalogue(entries, balance, message)


## The host's answer to a purchase, repair or repaint (`close`: the panel closes, the vehicle is out).
@rpc("authority", "call_remote", "reliable")
func _c_done(ok: bool, text: String, close: bool) -> void:
	answered.emit(ok, text)
	if close and mode.ui_open():
		mode.close_ui()
	if not mode.ui_open() or ok:
		mode.game.toast(text)
	if mode.ui_open():
		mode._panel.set_status(text)


@rpc("authority", "call_remote", "reliable")
func _c_notice(text: String) -> void:
	mode.game.toast(text)
