extends "res://tools/test_base.gd"
## Headless check of the weapons and stuns between two players (scripts/items/, scripts/people/), in a Sandbox LAN game:
## run it twice at once, as the host and as a client on this machine (tools/test_lan_items.sh, port 7791):
##   godot --headless --path godot --script res://tools/test_lan_items.gd -- --host --port=7791 --name=Host
##   godot --headless --path godot --script res://tools/test_lan_items.gd -- --join=127.0.0.1:7791 --name=Guest
## - Both take their weapons from the free items (the host's word: their inventories come from it). The client sees the
##   host's taser in the host's hand.
## - The host tases the client 6 m away: the client drops, held, on both screens; the host picks them up (E) and walks
##   off with them: the client goes along, over the host's shoulders on both screens.
## - Once the stun is over, the client struggles: a wrong key first (still held), then the right keys on the next go:
##   free, up, put down by the host, on both screens.
## - The client then nets the host (its shot checked by the host, its net's hit reported to it): the host is down,
##   netted, on both screens.
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

const ArrowHud = preload("res://scripts/carjack/carjack_hud.gd")
const Weapon = preload("res://scripts/items/weapons/weapon.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")

var People: Script                          # people.gd, loaded once the autoloads are there
var _main: Node
var _failures: PackedStringArray = []
var _hosting := false


func _initialize() -> void:
	People = load("res://scripts/people/people.gd")
	_hosting = "--host" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + ("[host] " if _hosting else "[client] ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await physics_frame
	return true


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _fire() -> void:
	_trigger(true)
	await _frames(3)
	_trigger(false)
	await _frames(3)


## Our player faces `target` (global) from where it stands, first person.
func _face(target: Vector3) -> void:
	var p: CharacterBody3D = _main.player
	var d := target - p.global_position
	p.set_first_person(true)
	p.teleport(p.global_position, atan2(-d.x, -d.z))


## A spot `dist` m from `target` (feet, global) on the ground, from where the eye sees its chest with nothing between
## (the street furniture round the spawn point), or `target` + `dist` south when none is.
func _clear_spot(target: Vector3, dist := 6.0) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for k in 12:
		var a := TAU * k / 12.0
		var p := target + Vector3(sin(a), 0.0, cos(a)) * dist
		var g := WorldQuery.ground_y(_main.get_world_3d(), p.x, p.z, Layers.SOLID, target.y + 3.0)
		if is_nan(g) or absf(g - target.y) > 0.5:
			continue
		var eye := Vector3(p.x, g + 1.55, p.z)
		var q := PhysicsRayQueryParameters3D.create(eye, target + Vector3.UP * 1.1, Weapon.WORLD_MASK)
		if not space.intersect_ray(q):
			return Vector3(p.x, g + 0.1, p.z)
	return target + Vector3(0.0, 0.3, dist)


func _run() -> void:
	if _hosting:
		await _run_host()
	else:
		await _run_client()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _run_host() -> void:
	var net: Node = _main.net
	var items: Node = _main.items
	var people: Node = _main.people
	items.assume_captured = true
	_check(await _until(func() -> bool: return _main.mode == "host" and items.enabled, 60.0), "hosting, the items on")
	items.take_free("taser")
	items.take_free("taser_cartridge")
	_check(await _until(func() -> bool: return net.players.size() == 2, 90.0), "the client joined")
	var guest: int = net.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	var them := "p:%d" % guest
	_check(await _until(func() -> bool: return net.avatar(guest) != null and net.avatar(guest).visible, 30.0),
			"the client's player is here")
	var avatar: Node3D = net.avatar(guest)     # (a lambda only gets a copy of a variable: read it after)
	await _frames(120)                      # (the client settles where it stands)
	_press(KEY_1)
	await _frames(2)
	_check(items.hands.kind == "taser", "the taser in hand")
	_main.player.teleport(_clear_spot(avatar.global_position))
	await _frames(20)
	_face(avatar.global_position)
	await _frames(5)
	await _fire()
	_check(await _until(func() -> bool: return people.is_down(them), 3.0), "the client is down, tased")
	_check(await _until(func() -> bool: return avatar._down, 3.0), "...lying here")
	_main.player.teleport(avatar.global_position + Vector3(1.0, 0.3, 0.0))
	await _frames(10)
	_press(KEY_E)
	_check(await _until(func() -> bool: return people.carried_by(1) == them and avatar.person_carried(), 3.0),
			"picked up: over our shoulders")
	_main.player.scripted_input = Vector2(0.0, 1.0)
	await _frames(90)
	_main.player.scripted_input = null
	var flat := Vector2(avatar.global_position.x - _main.player.global_position.x,
			avatar.global_position.z - _main.player.global_position.z)
	_check(flat.length() < 0.3, "the client goes where we go")
	_check(await _until(func() -> bool: return people.carried_by(1) == "" and not people.is_down(them), 25.0),
			"the client struggled free")
	_check(not avatar.person_carried() and not avatar._down, "...up here")
	_press(KEY_1)                           # (put away: the taser)
	# now the client nets us
	_check(await _until(func() -> bool: return people.effect_of(people.my_id())[0] == "netted", 30.0),
			"the client's net caught us")
	_check(_main.player.held and people.fx.showing(people.my_id()), "...down, wrapped in it")
	await _frames(60)


func _run_client() -> void:
	var net: Node = _main.net
	var items: Node = _main.items
	var people: Node = _main.people
	var player: CharacterBody3D = _main.player
	items.assume_captured = true
	_check(await _until(func() -> bool: return _main.mode == "client" and items.enabled, 90.0), "joined, the items on")
	items.take_free("net_gun")
	items.take_free("net_shell")
	_check(await _until(func() -> bool: return (items.inventory.kind_at(0) == "net_gun"
			and items.inventory.count("net_shell") == 10), 10.0), "our net gun and shells, from the host")
	var me: String = people.my_id()
	var host: Node3D = net.avatar(1)
	_check(await _until(func() -> bool: return items.shown.get(1, "") == "taser" and items._models.has(1), 30.0),
			"the host's taser in its hand here")
	_check(await _until(func() -> bool: return people.is_down(me) and player.held, 30.0), "tased: down, held")
	_check(people.fx.showing(me), "...arcs on us")
	_check(await _until(func() -> bool: return people.is_carried(me) and player.person_carried(), 10.0),
			"picked up by the host")
	await _frames(30)
	var flat := Vector2(host.global_position.x - player.global_position.x, host.global_position.z - player.global_position.z)
	_check(flat.length() < 0.4, "we go where the host goes")
	_check(await _until(func() -> bool: return people._hud != null and people._hud.state == "input", 10.0),
			"the stun over: the struggle's arrows")
	var hud: Control = people._hud
	if hud == null:
		return
	_press(ArrowHud.ARROWS[(int(hud.sequence[0]) + 1) % 4])
	_check(await _until(func() -> bool: return hud.state == "done", 3.0) and not hud._ok and people.is_carried(me),
			"a wrong key: still held")
	_check(await _until(func() -> bool: return hud.state == "input" and hud.typed.is_empty(), 5.0), "another go")
	for k: int in hud.sequence.duplicate():
		_press(ArrowHud.ARROWS[k])
		await _frames(3)
	_check(await _until(func() -> bool: return not people.is_carried(me) and not player.held, 5.0), "free, up")
	_check(player.global_position.distance_to(host.global_position) < 3.0, "put down by the host")
	# we net the host
	await _frames(60)
	player.teleport(_clear_spot(host.global_position))
	await _frames(20)
	_press(KEY_1)
	await _frames(3)
	_check(items.hands.kind == "net_gun", "the net gun in hand")
	_face(host.global_position)
	await _frames(5)
	await _fire()
	_check(await _until(func() -> bool: return people.effect_of("p:1")[0] == "netted", 4.0), "the host is netted")
	_check(await _until(func() -> bool: return host._down, 2.0), "...lying here")
	await _frames(60)
