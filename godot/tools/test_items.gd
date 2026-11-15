extends "res://tools/test_base.gd"
## Headless checks for the items, the weapons and the stuns (scripts/items/, scripts/people/), solo in Sandbox:
## - the inventory alone (inventory.gd): stacks, the hotbar first for weapons and the bag first for ammunition, moves
##   (into, onto a stack, swapped), takes, rows from the network cleaned up;
## - Sandbox starts with nothing and the panel's free items (I) fill the hotbar and the bag; I opens and Esc closes it,
##   the player standing still meanwhile;
## - the taser in hand (1), fired at a bot on foot (a stolen car's driver, ejected_driver.gd) 6 m ahead: they drop,
##   tased (the arcs, the wires), the weapon reloads by itself from the cartridges (one used); up after the stun, a shot
##   in the next IMMUNE s does nothing, after that it stuns again;
## - E by them picks them up (the player slower, no running, no weapon out), they follow the player, G puts them down,
##   still down for what is left of their stun; carried again past their stun, a bot wriggles free by itself;
## - the net gun (2): its net flies and wraps them (netted, 5 s);
## - our player stunned: on the ground, the weapon put away and none drawn, walking does nothing; up again after;
## - carried (a carrier faked), once the stun is over the struggle's arrows come one at a time: a wrong key fails and
##   another go comes; the right keys free us.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_items.gd

const Inventory = preload("res://scripts/items/inventory.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const EjectedDriver = preload("res://scripts/carjack/ejected_driver.gd")
const ArrowHud = preload("res://scripts/carjack/carjack_hud.gd")

var People: Script                          # people.gd, loaded once the autoloads are there (it uses Settings)
var _main: Node
var _failures: PackedStringArray = []
var _toast := ""


func _initialize() -> void:
	People = load("res://scripts/people/people.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(t: float) -> void:
	await _frames(roundi(t * 60.0))


func _run() -> void:
	_inventory_alone()
	await _frames(60)
	_main.toast_shown.connect(func(text: String) -> void: _toast = text)
	var items: Node = _main.items
	var people: Node = _main.people
	var player: CharacterBody3D = _main.player
	items.assume_captured = true
	_check(items.enabled and items.hud != null and items.panel != null, "Sandbox has the items, the hotbar, the panel")
	_check(items.inventory.count("taser") == 0, "Sandbox starts with nothing")

	# the panel: open, free items, closed
	_key(KEY_I, true)
	_key(KEY_I, false)
	await _frames(2)
	_check(items.ui_open() and not player.active, "I opens the inventory; the player stands still")
	for kind: String in ["taser", "taser_cartridge", "net_gun", "net_shell"]:
		items.take_free(kind)
	await _frames(2)
	var inv: RefCounted = items.inventory
	_check(inv.kind_at(0) == "taser" and inv.kind_at(1) == "net_gun", "the weapons go on the hotbar")
	_check(inv.count("taser_cartridge") == 20 and inv.find("taser_cartridge") >= inv.hotbar_size(),
			"the cartridges go in the bag (a stack of 20)")
	_check(int(inv.slot(0).get("loaded", 0)) == 1, "a taser comes loaded")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check(not items.ui_open() and player.active and not _main.pause.visible, "Esc closes it (not the menu)")

	# a bot on foot 6 m ahead, the player facing them, first person
	var car: Node3D = _main.spawn_car_near_player("sedan")
	var driver: Node3D = EjectedDriver.new()
	driver.setup(_main, car, 4242)
	_main.add_child(driver)
	driver._t = 20.0                        # (out of the car, done running: standing there)
	var here: Vector3 = player.global_position
	var fwd := Vector3(0.0, 0.0, -1.0)
	var spot := here + fwd * 6.0
	await _frames(2)
	driver.put_at(spot)
	player.set_first_person(true)
	player.teleport(here, 0.0)              # (yaw 0: facing -Z)
	await _frames(10)
	var id: String = driver.person_id
	_check(driver.person_up() and people.person(id) == driver, "the driver is a person standing (%s)" % id)

	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(2)
	_check(items.held == 0 and items.hands.kind == "taser" and player.face_aim, "1 takes the taser in hand")
	await _fire()
	_check(items.shots == 1, "the left mouse fires")
	_check(people.is_down(id) and people.effect_of(id)[0] == "tased" and driver._down, "the driver drops, tased")
	_check(people.fx.showing(id), "arcs crackle round them")
	_check(_count_named(items.hands, "TaserWires") > 0, "the taser's wires reach them")
	_check(int(inv.slot(0).get("loaded", 0)) == 0 and items.reload_t > 0.0, "fired: empty, reloading by itself")
	await _seconds(2.2)
	_check(int(inv.slot(0).get("loaded", 0)) == 1 and inv.count("taser_cartridge") == 19,
			"reloaded from a cartridge (19 left)")
	await _seconds(1.0)
	_check(not people.is_down(id) and driver.person_up(), "up again after the stun (3 s)")
	await _fire()
	_check(not people.is_down(id), "a shot within %d s of getting up does nothing" % People.IMMUNE)
	await _seconds(2.5)
	await _fire()
	_check(people.is_down(id), "after that it stuns again")

	# picked up, carried, put down
	player.teleport(spot + Vector3(1.2, 0.0, 0.0), 0.0)
	await _frames(3)
	_check(people.prompt().contains("pick"), "by them, the screen says E picks them up")
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	_check(people.carried_by(1) == id and driver.person_carried(), "E picks them up")
	_check(is_equal_approx(player.speed_scale, People.CARRY_SPEED) and not player.can_run and not player.can_jump,
			"carrying: slower, no running nor jumping")
	_check(items.held == -1 and items.hands.kind == "", "carrying: the taser is put away")
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(2)
	_check(items.held == -1, "...and none comes out")
	player.scripted_input = Vector2(0.0, 1.0)
	await _seconds(1.0)
	player.scripted_input = null
	var flat := Vector2(driver.global_position.x - player.global_position.x, driver.global_position.z - player.global_position.z)
	_check(flat.length() < 0.3 and player.global_position.distance_to(spot + Vector3(1.2, 0.0, 0.0)) > 1.0,
			"they go where the player goes")
	_key(KEY_G, true)
	_key(KEY_G, false)
	await _frames(3)
	_check(people.carried_by(1) == "" and not driver.person_carried() and people.is_down(id),
			"G puts them down, still down")
	_check(is_equal_approx(player.speed_scale, 1.0) and player.can_run, "the player walks as before")
	_check(driver.global_position.distance_to(player.global_position) < 2.0, "put down beside the player")

	# carried past the stun: a bot wriggles free by itself
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	_check(people.carried_by(1) == id, "picked up again")
	await _seconds(3.0 + People.NPC_STRUGGLE + 0.5)
	_check(people.carried_by(1) == "" and not people.is_down(id) and driver.person_up(), "a bot wriggles free")

	# the net gun
	await _seconds(People.IMMUNE + 0.2)
	player.teleport(here, 0.0)
	driver.put_at(spot)
	await _frames(5)
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _frames(2)
	_check(items.hands.kind == "net_gun", "2 takes the net gun")
	await _fire()
	_check(_count_named(items, "Net") > 0, "a net flies")
	await _seconds(0.6)
	_check(people.effect_of(id)[0] == "netted" and people.fx.showing(id), "it wraps them: netted")
	_check(items.reload_t > 3.0, "the net gun reloads longer (%.1f s)" % items.reload_t)
	await _seconds(5.2)
	_check(not people.is_down(id), "up after 5 s")

	# our player stunned
	people.hit(people.my_id(), "tased", 3.0, 0)
	await _frames(3)
	_check(player.held and player.crawling and items.held == -1, "stunned: on the ground, the weapon put away")
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(2)
	_check(items.held == -1, "...and none comes out")
	var at := player.global_position
	player.scripted_input = Vector2(0.0, 1.0)
	await _seconds(1.0)
	player.scripted_input = null
	_check(player.global_position.distance_to(at) < 0.3, "walking does nothing")
	await _seconds(2.5)
	_check(not player.held and not player.crawling and not people.is_down(people.my_id()), "up again")

	# carried (a carrier faked: peer 2), the struggle
	await _seconds(People.IMMUNE + 0.2)
	people._c_down(people.my_id(), "tased", 0.3, 2)
	people._c_carry(people.my_id(), 2)
	await _seconds(0.6)
	var hud: Control = people._hud
	_check(hud != null and hud.state == "input" and hud.sequence.size() == People.STRUGGLE_KEYS,
			"carried past the stun: %d arrows to press" % People.STRUGGLE_KEYS)
	var wrong: int = (int(hud.sequence[0]) + 1) % 4
	_key(ArrowHud.ARROWS[wrong], true)
	_key(ArrowHud.ARROWS[wrong], false)
	await _frames(3)
	_check(people.is_carried(people.my_id()) and hud.state == "done" and not hud._ok, "a wrong key: still held")
	await _seconds(People.STRUGGLE_RETRY + 0.3)
	_check(hud.state == "input" and hud.typed.is_empty(), "another go comes")
	for k: int in hud.sequence.duplicate():
		_key(ArrowHud.ARROWS[k], true)
		_key(ArrowHud.ARROWS[k], false)
		await _frames(4)
	await _frames(3)
	_check(not people.is_carried(people.my_id()) and not player.held, "the right keys: free, up")
	_finish()


## Holds the fire key a moment.
func _fire() -> void:
	_trigger(true)
	await _frames(3)
	_trigger(false)
	await _frames(3)


func _count_named(node: Node, prefix: String) -> int:
	var n := 0
	for c: Node in node.get_children():
		if String(c.name).begins_with(prefix):
			n += 1
	return n


func _inventory_alone() -> void:
	var inv := Inventory.new()
	_check(inv.size() == Inventory.HOTBAR + Inventory.BAG, "an inventory: %d hotbar slots and a bag of %d" % [
			Inventory.HOTBAR, Inventory.BAG])
	_check(inv.add("taser", 1, {"loaded": 1}) == 1 and inv.kind_at(0) == "taser", "a weapon goes on the hotbar")
	_check(inv.add("taser_cartridge", 25) == 25 and inv.count_at(Inventory.HOTBAR) == 20
			and inv.count_at(Inventory.HOTBAR + 1) == 5, "ammunition in the bag, in stacks of 20")
	_check(inv.add("nothing_at_all", 3) == 0, "no such item: nothing goes in")
	_check(inv.remove("taser_cartridge", 7) == 7 and inv.count("taser_cartridge") == 18, "taking 7 out")
	_check(inv.move(Inventory.HOTBAR, 1) and inv.kind_at(1) == "taser_cartridge" and inv.slot(Inventory.HOTBAR).is_empty(),
			"moved into an empty slot")
	inv.add("taser_cartridge", 15)          # 18 + 2 on slot 1, 13 in the bag
	_check(inv.count_at(1) == 20 and inv.count_at(Inventory.HOTBAR) == 13, "added: the stack topped up first")
	inv.take(1, 5)
	_check(inv.move(Inventory.HOTBAR, 1) and inv.count_at(1) == 20 and inv.count_at(Inventory.HOTBAR) == 8,
			"moved onto a stack: as much as fits")
	_check(inv.count("taser_cartridge") == 28, "nothing lost moving stacks")
	_check(inv.move(0, 1) and inv.kind_at(0) == "taser_cartridge" and inv.kind_at(1) == "taser", "two kinds swap")
	_check(int(inv.slot(1).get("loaded", 0)) == 1, "a weapon keeps its rounds when moved")
	inv.from_rows([{"kind": "taser", "n": 9}, {"kind": "bogus", "n": 1}, "junk", {"kind": "net_shell", "n": 99}])
	_check(inv.count_at(0) == 1 and inv.slot(1).is_empty() and inv.slot(2).is_empty() and inv.count_at(3) == 10,
			"rows from the network: counts kept within a stack, unknown items out")
	var taken: Array = inv.remove_where(func(kind: String) -> bool: return bool(ItemDb.field(kind, "confiscable", false)))
	_check(taken.size() == 2 and inv.count("taser") == 0, "everything confiscable can be taken at once")


func _finish() -> void:
	if _failures.is_empty():
		print("ALL ITEM CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
