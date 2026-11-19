extends Node
## The items the players carry and use (game.gd makes it as Main/Items on every peer, so that its RPCs have the same path
## everywhere), in the game modes that allow("items") (scripts/modes/game_mode.gd): Sandbox, the PTA Online test.
## - The catalogue is data/items.json (item_db.gd); what someone carries an inventory (inventory.gd): HOTBAR slots on the
##   keys 1 to 5, then the bag (I: inventory_panel.gd). The host keeps each player's true inventory and sends it to them
##   whenever it changes (_c_inventory); their game shows that copy. What a player starts with is the game mode's
##   (starting_items); Sandbox hands out anything for nothing from the panel (free_items). Buying, finding, dropping,
##   losing them on an arrest will be moves of the same inventories.
## - 1 to 5 takes a hotbar slot's item in hand (again: puts it away); the others see it in their hand (_c_held). Weapons
##   (scripts/items/weapons/: the taser, the net gun) fire with the left mouse (the mouse captured), the right one aims.
##   A weapon holds `capacity` rounds; once fired it reloads by itself from the ammunition carried (`reload` s, R also),
##   on the host's clock. Each shot goes to the host (_h_fire), which checks it: the game mode allows weapons, the shooter
##   on foot, able to act (people.gd can_act), out of the safe places (game_mode safe_place), the weapon in hand and
##   loaded, not faster than its cooldown, from where they stand. A hit (at once for a hitscan weapon, when the projectile
##   lands for the net) is checked again (the person standing, not just stunned, in range of the shot, out of a safe
##   place) before people.gd stuns them; the others see the shot (_c_shot).
## - The hands (hands.gd) show the item in hand and fire it; the screen (hotbar_hud.gd) shows the hotbar, the rounds,
##   the reload and what E or G would do. A weapon goes away by itself in a vehicle, in a safe place, down or carrying.
## Players are known by their peer (1 solo).

const ItemDb = preload("res://scripts/items/item_db.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const Hands = preload("res://scripts/items/hands.gd")
const ItemsAudio = preload("res://scripts/items/items_audio.gd")
const HotbarHud = preload("res://scripts/items/hotbar_hud.gd")
const InventoryPanel = preload("res://scripts/items/inventory_panel.gd")
const Weapon = preload("res://scripts/items/weapons/weapon.gd")
const People = preload("res://scripts/people/people.gd")

## behaviour (data/items.json) -> its script
const BEHAVIOURS := {
	"taser": preload("res://scripts/items/weapons/taser.gd"),
	"net_gun": preload("res://scripts/items/weapons/net_gun.gd"),
}
const LAG := 0.8                            # s the host allows for the way there and back
const ORIGIN_SLACK := 4.0                   # m a shot may leave from beside where the host has the shooter
const RANGE_SLACK := 2.5                    # m more reach the host allows (the positions it has are a little late)
const CHECK_EVERY := 0.25                   # s between looks at the hands (a vehicle, a safe place...), and the others'
const KICK := 0.03                          # rad of view kick per shot

var game: Node3D                            # game.gd
var people: Node                            # people.gd (Main/People)
var enabled := false                        # the game mode allows("items")
var inventory := Inventory.new()            # ours: the host's copy
var held := -1                              # the hotbar slot in our hand, -1 none
var reload_t := 0.0                         # s left of our weapon's reload (as the host said), 0 none
var reload_total := 0.0
var shown := {}                             # peer -> the item kind in their hand ("" none)
var hands: Hands
var audio: Node                             # items_audio.gd
var hud: HotbarHud
var panel: InventoryPanel
var shots := 0                              # ours fired (tests)
var assume_captured := false                # tests: the mouse counts as captured (a headless run has none)

var _inv := {}                              # host: peer -> Inventory
var _held := {}                             # host: peer -> hotbar slot in hand
var _reload := {}                           # host: peer -> {"slot", "t"}
var _last := {}                             # host: peer -> when they last fired (s, _now)
var _shots := {}                            # host: peer -> {no -> {"kind", "origin", "at", "landed"}}
var _behaviours := {}                       # kind -> its Weapon
var _models := {}                           # peer -> [kind, node]: what the others hold, in their avatar's hand
var _shot_no := 0
var _check_t := 0.0
var _panel_mouse := Input.MOUSE_MODE_VISIBLE # the mouse as it was when the panel opened


func _ready() -> void:
	audio = ItemsAudio.new()
	audio.name = "Audio"
	add_child(audio)
	set_physics_process(false)
	set_process(false)


## The game started here (game.gd, after the game mode's begin).
func begin() -> void:
	enabled = game.allows("items")
	if not enabled:
		return
	if game.mode != "server":
		hands = Hands.new()
		hands.name = "Hands"
		hands.items = self
		hands.people = people
		hands.audio = audio
		hands.player = game.player
		add_child(hands)
		hud = HotbarHud.new()
		hud.name = "Hotbar"
		hud.items = self
		game.hud.add_child(hud)
		panel = InventoryPanel.new()
		panel.name = "Inventory"
		panel.items = self
		game.hud.add_child(panel)
	inventory.changed.connect(_on_inventory_changed)
	if game.mode != "server":
		people.changed.connect(func(_id: String) -> void: _check_hands())   # (down, carrying: put away at once)
	if _hosting() and game.mode != "server":
		_grant(game.net.me())
	if not game.net.registered.is_connected(_on_registered):
		game.net.registered.connect(_on_registered)
		multiplayer.peer_disconnected.connect(_on_left)
	set_physics_process(true)
	set_process(true)


## The Weapon of item `kind`, or null (not a weapon).
func behaviour(kind: String) -> Weapon:
	if _behaviours.has(kind):
		return _behaviours[kind]
	var script: Script = BEHAVIOURS.get(str(ItemDb.field(kind, "behaviour", "")))
	var b: Weapon = script.new() if script else null
	if b:
		b.setup(kind)
	_behaviours[kind] = b
	return b


## The kind in our hand, "" none.
func held_kind() -> String:
	return inventory.kind_at(held) if held >= 0 else ""


## Rounds loaded in our weapon in hand, and the ammunition left for it.
func rounds() -> Array:
	var kind := held_kind()
	if kind == "" or not ItemDb.is_weapon(kind):
		return [0, 0]
	return [int(inventory.slot(held).get("loaded", 0)), inventory.count(str(ItemDb.field(kind, "ammo", "")))]


# ---------------------------------------------------------------- our keys

## Keys while playing (game.gd, after people.gd's, before the game mode's): I the inventory, 1-5 the hotbar, the fire key,
## R reload. True when taken.
func handle_input(event: InputEvent) -> bool:
	if not enabled or game.mode == "server":
		return false
	if event.is_action_pressed("inventory") and not game.flying and (panel.visible or not game.ui_open()):
		set_panel_open(not panel.visible)
		return true
	if game.driving or game.riding or game.flying or (game.ui_open() and not panel.visible):
		return false
	for k in Inventory.HOTBAR:
		if event.is_action_pressed("weapon_%d" % (k + 1)):
			select(k)
			return true
	if event.is_action_pressed("fire") and held >= 0 and ItemDb.is_weapon(held_kind()) \
			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or assume_captured):
		hands.trigger = true
		return true
	if event.is_action_released("fire") and hands:
		hands.trigger = false
		return false
	if event.is_action_pressed("reload") and held >= 0 and ItemDb.is_weapon(held_kind()):
		_to_host("_h_reload", [held])
		return true
	return false


func ui_open() -> bool:
	return panel != null and panel.visible


func close_ui() -> bool:
	if ui_open():
		set_panel_open(false)
		return true
	return false


func set_panel_open(on: bool) -> void:
	if panel == null or on == panel.visible:
		return
	if on:
		_panel_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		panel.open()
	else:
		panel.visible = false
		Input.mouse_mode = _panel_mouse
	game.update_controls()


## Takes hotbar slot `slot`'s item in hand (the one in hand again, or an empty slot: puts it away).
func select(slot: int) -> void:
	if slot == held or (slot >= 0 and inventory.slot(slot).is_empty()):
		slot = -1
	if slot >= 0 and ItemDb.is_weapon(inventory.kind_at(slot)):
		var why := _cannot_draw()
		if why != "":
			game.toast(why)
			return
	_hold(slot)
	_to_host("_h_hold", [slot])


func _hold(slot: int) -> void:
	held = slot
	reload_t = 0.0
	if hands:
		hands.show_kind(held_kind())


## Why our player may not take a weapon out now ("" they may).
func _cannot_draw() -> String:
	if not people.can_act(game.net.me()):
		return "Not now."
	var place := _safe_place(game.net.me(), game.player.global_position)
	if place != "":
		return "No weapons in %s." % place
	return ""


## The safe place `pos` is in for player `peer` (the game mode's), "" none.
func _safe_place(peer: int, pos: Vector3) -> String:
	return game.game_mode.safe_place(peer, pos) if game.game_mode else ""


## The fire key (hands.gd): our weapon in hand fires, if it may.
func try_fire() -> void:
	var kind := held_kind()
	var b := behaviour(kind)
	if b == null or game.driving or game.riding or game.flying or not game.player.active \
			or not people.can_act(game.net.me()):
		return
	var slot := inventory.slot(held)
	if int(slot.get("loaded", 0)) <= 0:
		audio.play("empty", -6.0)
		if reload_t <= 0.0:
			if inventory.count(str(b.stats.get("ammo", ""))) > 0:
				_to_host("_h_reload", [held])
			else:
				game.toast("No %s left." % ItemDb.item_name(str(b.stats.get("ammo", ""))).to_lower())
		return
	if reload_t > 0.0:
		return
	hands.cool = b.stat("cooldown", 0.3)
	var muzzle := hands.muzzle_node().global_position
	var aim := hands.aim_point(b.stat("range", 10.0) + 30.0)
	_shot_no += 1
	shots += 1
	var r := b.fire(hands, muzzle, aim, _shot_no)
	slot["loaded"] = int(slot["loaded"]) - 1          # (the host's word follows)
	hands.recoil(KICK)
	_to_host("_h_fire", [held, _shot_no, muzzle, r["end"], r["target"]])


## Our net (net_shot.gd) caught person `id`.
func net_landed(no: int, id: String) -> void:
	_to_host("_h_hit", [no, id])


## Sandbox (free_items): a stack of `kind` for nothing (a weapon loaded).
func take_free(kind: String) -> void:
	_to_host("_h_free", [kind])


## The inventory panel: slot `from` onto slot `to` (inventory.gd move).
func move(from: int, to: int) -> void:
	if inventory.move(from, to):
		_to_host("_h_move", [from, to])


func _on_inventory_changed() -> void:
	if hud:
		hud.queue_redraw()
	if panel and panel.visible:
		panel.queue_redraw()


func _process(delta: float) -> void:
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			audio.play("reload", -6.0)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = CHECK_EVERY
	if game.mode != "server":
		_check_hands()
		_show_others()


## Our weapon goes away in a vehicle, a safe place, down or carrying.
func _check_hands() -> void:
	var kind := held_kind()
	if held >= 0 and kind == "":
		_hold(-1)                           # (the slot emptied)
	if held < 0 or not ItemDb.is_weapon(kind):
		return
	if game.driving or game.riding or not people.can_act(game.net.me()):
		select(-1)
		return
	var place := _safe_place(game.net.me(), game.player.global_position)
	if place != "":
		select(-1)
		game.toast("No weapons in %s: put away." % place)


## The item each other player holds, in their avatar's hand (hidden while they are down, carried or in a vehicle).
func _show_others() -> void:
	for peer: int in _models.keys():
		if not shown.has(peer) or game.net.avatar(peer) == null:
			if is_instance_valid(_models[peer][1]):
				(_models[peer][1] as Node).queue_free()
			_models.erase(peer)
	for peer: int in shown:
		var avatar: Node3D = game.net.avatar(peer)
		if avatar == null:
			continue
		var kind: String = shown[peer]
		var m: Array = _models.get(peer, ["", null])
		if m[0] != kind or (kind != "" and not is_instance_valid(m[1])):
			if is_instance_valid(m[1]):
				(m[1] as Node).queue_free()
			var b := behaviour(kind)
			var node: Node3D = b.model() if b else null
			if node:
				node.position = Hands.HAND
				avatar.body().add_child(node)
			m = [kind, node]
			_models[peer] = m
		if m[1]:
			(m[1] as Node3D).visible = avatar.person_up()


# ---------------------------------------------------------------- host

## Host: player `peer`'s inventory as the game mode starts them with it.
func _grant(peer: int) -> void:
	var inv := Inventory.new()
	for row: Array in game.game_mode.starting_items():
		var kind: String = row[0]
		inv.add(kind, int(row[1]) if row.size() > 1 else 1, _fresh(kind))
	_inv[peer] = inv
	_held[peer] = -1
	_send_inventory(peer)


## What a new stack of `kind` keeps: a weapon comes loaded.
static func _fresh(kind: String) -> Dictionary:
	return {"loaded": int(ItemDb.field(kind, "capacity", 1))} if ItemDb.is_weapon(kind) else {}


func _send_inventory(peer: int) -> void:
	var inv: Inventory = _inv.get(peer)
	if inv:
		_to_peer(peer, "_c_inventory", [inv.to_rows()])


func _on_registered(peer: int) -> void:
	if not _hosting() or not enabled:
		return
	_grant(peer)
	var hands_now := {}
	for p: int in _held:
		var inv: Inventory = _inv.get(p)
		if inv and int(_held[p]) >= 0 and p != peer:
			hands_now[p] = inv.kind_at(_held[p])
	if not hands_now.is_empty():
		_to_peer(peer, "_c_hands", [hands_now])


func _on_left(peer: int) -> void:
	shown.erase(peer)
	if not _hosting():
		return
	for d: Dictionary in [_inv, _held, _reload, _last, _shots]:
		d.erase(peer)


func _physics_process(delta: float) -> void:
	if not _hosting():
		return
	for peer: int in _reload.keys():
		var r: Dictionary = _reload[peer]
		r["t"] -= delta
		if r["t"] <= 0.0:
			_reload.erase(peer)
			_reloaded(peer, int(r["slot"]))
	var now := _now()
	for peer: int in _shots:
		var list: Dictionary = _shots[peer]
		for no: int in list.keys():
			if now - float(list[no]["at"]) > 5.0:
				list.erase(no)


## Host: player `peer`'s weapon in `slot` gets a round from their ammunition (and goes on until full).
func _reloaded(peer: int, slot: int) -> void:
	var inv: Inventory = _inv.get(peer)
	if inv == null:
		return
	var kind := inv.kind_at(slot)
	var ammo := str(ItemDb.field(kind, "ammo", ""))
	if not ItemDb.is_weapon(kind) or inv.remove(ammo, 1) < 1:
		return
	var s := inv.slot(slot)
	s["loaded"] = int(s.get("loaded", 0)) + 1
	_start_reload(peer, slot)               # (the next round, if there is room and ammunition)
	_send_inventory(peer)


## Host: player `peer`'s weapon in `slot` starts reloading, if it has room and they have ammunition for it.
func _start_reload(peer: int, slot: int) -> void:
	var inv: Inventory = _inv.get(peer)
	if inv == null or _reload.has(peer):
		return
	var kind := inv.kind_at(slot)
	if not ItemDb.is_weapon(kind):
		return
	var s := inv.slot(slot)
	if int(s.get("loaded", 0)) >= int(ItemDb.field(kind, "capacity", 1)) \
			or inv.count(str(ItemDb.field(kind, "ammo", ""))) <= 0:
		return
	var t := float(ItemDb.field(kind, "reload", 2.0))
	_reload[peer] = {"slot": slot, "t": t}
	_to_peer(peer, "_c_reload", [slot, t])


@rpc("any_peer", "call_remote", "reliable")
func _h_hold(slot: int) -> void:
	if not _hosting() or not enabled:
		return
	var peer := _sender()
	var inv: Inventory = _inv.get(peer)
	if inv == null or slot < -1 or slot >= inv.hotbar_size():
		return
	if slot >= 0 and inv.kind_at(slot) == "":
		slot = -1
	if slot >= 0 and ItemDb.is_weapon(inv.kind_at(slot)):
		var why := _hands_refusal(peer)
		if why != "":
			_to_peer(peer, "_c_hold", [-1, why])
			slot = -1
	if int(_held.get(peer, -1)) == slot:
		return
	_held[peer] = slot
	_reload.erase(peer)
	_to_others(peer, "_c_held", [peer, inv.kind_at(slot) if slot >= 0 else ""])
	if slot >= 0:
		_start_reload(peer, slot)


## Host: why player `peer` may not have a weapon out now ("" they may).
func _hands_refusal(peer: int) -> String:
	if not enabled:
		return "No weapons in this game."
	if not people.can_act(peer):
		return "Not now."
	var at: Variant = people.feet(People.id_of_peer(peer))
	if at == null:
		return "Get out first."
	var place := _safe_place(peer, at)
	if place != "":
		return "No weapons in %s." % place
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _h_fire(slot: int, no: int, origin: Vector3, end: Vector3, target: String) -> void:
	if not _hosting():
		return
	var peer := _sender()
	var inv: Inventory = _inv.get(peer)
	var kind := inv.kind_at(slot) if inv else ""
	var b := behaviour(kind)
	var why := "" if b else "No weapon."
	if why == "":
		why = _hands_refusal(peer)
	if why == "" and int(_held.get(peer, -1)) != slot:
		why = "Take it in hand first."
	if why == "" and int(inv.slot(slot).get("loaded", 0)) <= 0:
		why = "Empty."
	if why == "" and _reload.has(peer):
		why = "Still reloading."
	if why == "" and _now() - float(_last.get(peer, -INF)) < b.stat("cooldown", 0.3) * 0.5:
		why = "Too fast."
	var at: Variant = people.feet(People.id_of_peer(peer))
	if why == "" and at != null and origin.distance_to((at as Vector3) + Vector3.UP * 1.3) > ORIGIN_SLACK:
		why = "Out of place."
	if why != "":
		_to_peer(peer, "_c_refused", [why])
		_send_inventory(peer)
		return
	var s := inv.slot(slot)
	s["loaded"] = int(s["loaded"]) - 1
	_last[peer] = _now()
	if not _shots.has(peer):
		_shots[peer] = {}
	_shots[peer][no] = {"kind": kind, "origin": origin, "at": _now(), "landed": false}
	_to_others(peer, "_c_shot", [peer, kind, origin, end, target])
	if target != "" and str(b.stats.get("shot", "")) == "hitscan":
		_land(peer, no, target)
	_start_reload(peer, slot)
	_send_inventory(peer)


@rpc("any_peer", "call_remote", "reliable")
func _h_hit(no: int, target: String) -> void:
	if _hosting():
		_land(_sender(), no, target)


## Host: player `peer`'s shot `no` hit person `target`: stunned, if it holds.
func _land(peer: int, no: int, target: String) -> void:
	var shot: Dictionary = _shots.get(peer, {}).get(no, {})
	if shot.is_empty() or shot["landed"] or target == People.id_of_peer(peer):
		return
	shot["landed"] = true
	var b := behaviour(shot["kind"])
	if b == null or not people.stunnable(target):
		return
	var at: Variant = people.feet(target)
	if at == null and People.peer_of(target) != 0:
		return                              # (a player in a vehicle, hidden, gone)
	if at != null:
		if (shot["origin"] as Vector3).distance_to((at as Vector3) + Vector3.UP * 0.9) > b.stat("range", 10.0) + RANGE_SLACK:
			return
		if _safe_place(People.peer_of(target), at) != "":
			return
	if str(b.stats.get("shot", "")) != "hitscan" \
			and _now() - float(shot["at"]) > b.stat("range", 10.0) / maxf(b.stat("speed", 20.0), 1.0) + LAG + 0.5:
		return
	people.hit(target, str(b.stats.get("effect", "")), b.stat("stun", 3.0), peer)


## Host: a bot (a police officer, scripts/police/foot/arrest.gd), person `shooter`, fires a `kind` weapon from `origin`
## towards `end`; `target` the person it hits ("" a miss: it decided). Everyone sees the shot; the hit stuns them at
## once (hitscan) or once the net gets there, if they can be stunned then.
func bot_fire(shooter: String, kind: String, origin: Vector3, end: Vector3, target: String) -> void:
	var b := behaviour(kind)
	if not _hosting() or b == null:
		return
	if game.net.active:
		rpc("_c_bot_shot", shooter, kind, origin, end, target)
	else:
		_c_bot_shot(shooter, kind, origin, end, target)
	if target == "":
		return
	var effect := str(b.stats.get("effect", ""))
	var stun := b.stat("stun", 3.0)
	if str(b.stats.get("shot", "")) == "hitscan":
		people.hit(target, effect, stun, 0)
		return
	var flight := origin.distance_to(end) / maxf(b.stat("speed", 20.0), 1.0)
	get_tree().create_timer(flight, true, true).timeout.connect(func() -> void:
		if is_instance_valid(people) and people.stunnable(target):
			people.hit(target, effect, stun, 0))


## Host: the weapons and their ammunition (`confiscable`, data/items.json) taken from player `peer` (an arrest): out of
## their inventory, their hands empty: [[kind, n], ...].
func confiscate(peer: int) -> Array:
	var inv: Inventory = _inv.get(peer)
	if not _hosting() or inv == null:
		return []
	var out := inv.remove_where(func(kind: String) -> bool: return bool(ItemDb.field(kind, "confiscable", false)))
	if out.is_empty():
		return out
	_reload.erase(peer)
	if int(_held.get(peer, -1)) >= 0:
		_held[peer] = -1
		_to_peer(peer, "_c_hold", [-1, ""])
		_to_others(peer, "_c_held", [peer, ""])
	_send_inventory(peer)
	return out


@rpc("any_peer", "call_remote", "reliable")
func _h_reload(slot: int) -> void:
	if _hosting() and int(_held.get(_sender(), -1)) == slot:
		_start_reload(_sender(), slot)


@rpc("any_peer", "call_remote", "reliable")
func _h_move(from: int, to: int) -> void:
	if not _hosting():
		return
	var peer := _sender()
	var inv: Inventory = _inv.get(peer)
	if inv == null:
		return
	var slot := int(_held.get(peer, -1))
	var before := inv.kind_at(slot) if slot >= 0 else ""
	if inv.move(from, to) and slot >= 0:
		if inv.kind_at(slot) != before:
			_held[peer] = -1
			_reload.erase(peer)
			_to_others(peer, "_c_held", [peer, ""])
		elif _reload.has(peer) and int(_reload[peer]["slot"]) in [from, to]:
			_reload.erase(peer)
	_send_inventory(peer)


@rpc("any_peer", "call_remote", "reliable")
func _h_free(kind: String) -> void:
	if not _hosting() or not game.game_mode.free_items() or not ItemDb.exists(kind):
		return
	var peer := _sender()
	var inv: Inventory = _inv.get(peer)
	if inv == null:
		return
	var n := 1 if ItemDb.is_weapon(kind) else ItemDb.stack(kind)
	if inv.add(kind, n, _fresh(kind)) == 0:
		_to_peer(peer, "_c_refused", ["No room left."])
	_send_inventory(peer)


# ---------------------------------------------------------------- everyone

@rpc("authority", "call_remote", "reliable")
func _c_inventory(rows: Array) -> void:
	inventory.from_rows(rows)
	if hands and held >= 0 and hands.kind != held_kind():
		hands.show_kind(held_kind())
	if held >= 0 and held_kind() == "":
		_hold(-1)


@rpc("authority", "call_remote", "reliable")
func _c_hold(slot: int, why: String) -> void:
	_hold(slot)
	if why != "" and game.mode != "server":
		game.toast(why)


@rpc("authority", "call_remote", "reliable")
func _c_held(peer: int, kind: String) -> void:
	shown[peer] = kind
	if game.mode != "server":
		_show_others()


@rpc("authority", "call_remote", "reliable")
func _c_hands(all: Dictionary) -> void:
	for peer: int in all:
		shown[peer] = all[peer]


@rpc("authority", "call_remote", "reliable")
func _c_reload(slot: int, seconds: float) -> void:
	if slot == held:
		reload_t = seconds
		reload_total = seconds


@rpc("authority", "call_remote", "reliable")
func _c_refused(why: String) -> void:
	if game.mode != "server" and why not in ["Too fast.", "Out of place."]:
		game.toast(why)


@rpc("authority", "call_remote", "reliable")
func _c_shot(peer: int, kind: String, origin: Vector3, end: Vector3, target: String) -> void:
	if game.mode == "server":
		return
	var b := behaviour(kind)
	if b:
		b.show_shot(self, People.id_of_peer(peer), origin, end, target)


@rpc("authority", "call_local", "reliable")
func _c_bot_shot(shooter: String, kind: String, origin: Vector3, end: Vector3, target: String) -> void:
	if game.mode == "server":
		return
	var b := behaviour(kind)
	if b:
		b.show_shot(self, shooter, origin, end, target)


# ---------------------------------------------------------------- the way between the peers

func _hosting() -> bool:
	return not game.net.active or multiplayer.is_server()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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


## To every player but `peer` (here too, when we play and are not them).
func _to_others(peer: int, method: StringName, args: Array) -> void:
	if not game.net.active:
		return
	for other: int in game.net.players:
		if other != peer:
			_to_peer(other, method, args)
