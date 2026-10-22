extends SceneTree
## Headless checks of Escape from Plateau (scripts/escape/escape_mode.gd), played solo:
## - the mode: night in dread (fog, power cut), no bots, trains, races, salesman or showroom cars, no vehicle menu;
## - a mission: survivors spread out at their hideouts, the helicopter's circle, supplies, abandoned vehicles, zombies
##   guarding the hideouts; the briefing gives way to the rescue; zombies rise round the player; the sounds are made;
## - weapons: the pistol kills a zombie in front (rounds used, a kill counted), the crowbar hits one beside, a vehicle
##   running through one kills it; a supply walked over is taken;
## - a zombie's blows hurt; at 0 health the player is knocked down (crawling), a carried survivor is dropped; bled out,
##   dead, a life gone, back at the safehouse later;
## - survivors: E picks one up (slower, no running), G sits them in a vehicle and takes them out again, carried into
##   the helicopter's circle they are rescued; all rescued, the extraction starts, and the take-off with the player in
##   the circle wins the mission;
## - a new mission resets everything; dawn with nobody in the circle loses it, as does everyone dead with no life left;
## - back in Sandbox, everything is as it was (no dread, races, the start cars).
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_escape.gd

const Zombie = preload("res://scripts/escape/zombie.gd")
const Survivors = preload("res://scripts/escape/survivors.gd")
const EscapeAudio = preload("res://scripts/escape/escape_audio.gd")

var _main: Node
var _m: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_MODE", "escape")
	OS.set_environment("PLATEAU_ESCAPE_SURVIVORS", "4")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _trigger(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The player's view on `target` (global): facing it, pitched at it.
func _aim_at(target: Vector3) -> void:
	var p: CharacterBody3D = _main.player
	var d: Vector3 = target - p.camera.global_position
	p.teleport(p.global_position, atan2(-d.x, -d.z))
	p.kick(atan2(d.y, Vector2(d.x, d.z).length()) - p.view_pitch())


func _put_player(at: Vector3) -> void:
	var p: CharacterBody3D = _main.player
	p.teleport(at + Vector3.UP * 0.2)


func _run() -> void:
	while _main.game_mode == null or _main.game_mode.survivors.list.is_empty():
		await physics_frame
	_m = _main.game_mode
	var p: CharacterBody3D = _main.player
	await _frames(20)

	# the mode
	_check(_m.id == "escape", "the game mode is Escape from Plateau")
	_check(_main.night.on and _main.night.dread, "night in dread")
	var env: Environment = _main.get_node("WorldEnvironment").environment
	_check(env.fog_enabled and env.fog_density > 0.015, "thick fog (%.4f)" % env.fog_density)
	_check(not _main.allows("vehicle_menu") and not _main.allows("races") and not _main.allows("bot_traffic"),
			"no vehicle menu, races or bot traffic")
	_check(_main.races.process_mode == Node.PROCESS_MODE_DISABLED, "the races are off")
	_check(_main.cars.all(func(c: Node) -> bool: return not c.is_bot()), "no bot vehicles")
	var salesman_hidden := true
	for s in _main.get_tree().get_nodes_in_group("showroom"):
		salesman_hidden = salesman_hidden and not s.salesman.visible
	_check(salesman_hidden, "the showroom's salesman is gone")

	# the mission
	var list: Array = _m.survivors.list
	_check(list.size() == 4 and list.all(func(s: Dictionary) -> bool: return s["state"] == Survivors.WAITING),
			"%d survivors waiting" % list.size())
	var spread := INF
	for a in list.size():
		for b in range(a + 1, list.size()):
			spread = minf(spread, (list[a]["pos"] as Vector3).distance_to(list[b]["pos"]))
	_check(spread > 70.0, "the hideouts are spread out (%.0f m at least)" % spread)
	_check(list.all(func(s: Dictionary) -> bool: return not is_nan((s["pos"] as Vector3).y)), "every hideout is on the ground")
	_check(_m.evac != null, "Dragon 91 waits at %s" % _m._evac_spot().get("name", "?"))
	_check(_m.loot.items.size() > 30, "%d supplies lying about" % _m.loot.items.size())
	_check(_main.cars.size() >= 10, "%d abandoned vehicles" % _main.cars.size())
	_check(_m.zombies.zombies.size() >= 4 * 5, "%d zombies guard the hideouts" % _m.zombies.zombies.size())
	_check(_m.phase == _m.BRIEFING and p.global_position.distance_to(_m.safehouse_pos) < 6.0, "briefing, at the safehouse")
	_m.phase_until = _m.clock() - 1.0
	await _frames(5)
	_check(_m.phase == _m.RESCUE, "the rescue starts")
	_m.assume_captured = true
	var guards: int = _m.zombies.zombies.size()
	await _frames(400)
	var near := 0
	for z: Zombie in _m.zombies.zombies.values():
		if not z.guard and z.global_position.distance_to(p.global_position) < 110.0:
			near += 1
	_check(near > 0, "zombies rise round the player (%d new, %d near)" % [_m.zombies.zombies.size() - guards, near])
	var waited := 0
	while not EscapeAudio.bank_ready() and waited < 600:
		await physics_frame
		waited += 1
	_check(EscapeAudio.bank_ready() and EscapeAudio.sound("groan1") != null and EscapeAudio.sound("rotor") != null,
			"the sounds are made")

	# weapons: the pistol
	_m.zombies.clear()
	_m.zombies._spawn_t = 1e9                   # no more risers: these checks place their own
	p.set_first_person(true)
	var here := p.global_position
	var fwd := Vector3(0.0, 0.0, -1.0)
	var spot: Vector3 = _m.ground_at(Vector2(here.x, -(here.z - 9.0)))
	var z: Zombie = _m.zombies.spawn(spot, Zombie.SHAMBLER, false)
	await _frames(3)
	var rounds: int = _m.arsenal.mag["pistol"]
	for k in 12:
		if not is_instance_valid(z) or z.state == Zombie.DEAD:
			break
		_aim_at(z.global_position + Vector3.UP * 1.2)
		await _frames(1)
		_trigger(true)
		await _frames(2)
		_trigger(false)
		await _frames(12)
	_check(is_instance_valid(z) and z.state == Zombie.DEAD, "the pistol killed the zombie in front (%d hits of %d shots)" % [
			_m.arsenal.zombie_hits, _m.arsenal.shots])
	_check(_m.arsenal.mag["pistol"] < rounds and _m.zombies.kills == 1, "rounds used, a kill counted")
	_check(z.collision_layer == 0, "a dead zombie no longer blocks")
	# the crowbar
	_press(KEY_1)
	await _frames(2)
	_check(_m.arsenal.weapon == "crowbar", "1 takes the crowbar")
	here = p.global_position
	z = _m.zombies.spawn(_m.ground_at(Vector2(here.x, -(here.z - 1.3))), Zombie.BRUTE, false)
	await _frames(2)
	var hp := z.health
	_aim_at(z.global_position + Vector3.UP * 1.2)
	_trigger(true)
	await _frames(30)
	_trigger(false)
	_check(z.health < hp, "the crowbar hits the zombie beside (%.0f -> %.0f)" % [hp, z.health])
	# a zombie's blows
	_m.health = 100.0
	var waited_hit := 0
	while _m.health >= 100.0 and waited_hit < 300:
		await physics_frame
		waited_hit += 1
	_check(_m.health < 100.0, "the zombie's blow hurts (%.0f)" % _m.health)
	_m.zombies.clear()
	_press(KEY_2)
	# a vehicle running one over
	var car: Node = _main.cars[0]
	_put_player(car.to_global(car.extents_center + Vector3(car.half_extents.x + 4.0, 0.0, 0.0)))
	await _frames(2)
	var zc: Zombie = _m.zombies.spawn(car.to_global(car.extents_center + Vector3(0.0, 0.1, car.half_extents.z - 0.5)),
			Zombie.SHAMBLER, false)
	car.linear_velocity = car.global_basis.z * 9.0
	await _frames(2)
	_check(zc.state == Zombie.DEAD, "a vehicle at speed runs a zombie over")
	car.linear_velocity = Vector3.ZERO
	_m.zombies.clear()

	# a supply
	var item_id: int = _m.loot.items.keys()[0]
	var item: Dictionary = _m.loot.items[item_id]
	var kind: String = item["kind"]
	var before := [_m.arsenal.reserve.duplicate(), _m.arsenal.bandages, _m.arsenal.medkits, _m.arsenal.batteries,
			_m.arsenal.owned.duplicate()]
	_put_player(item["pos"])
	await _frames(20)
	var after := [_m.arsenal.reserve, _m.arsenal.bandages, _m.arsenal.medkits, _m.arsenal.batteries, _m.arsenal.owned]
	_check(not _m.loot.items.has(item_id) and str(after) != str(before), "walking over the %s takes it" % kind)

	# survivors: E, G into a vehicle and out, rescued in the circle
	var s: Dictionary = list[0]
	_put_player((s["pos"] as Vector3) + Vector3(1.0, 0.0, 0.0))
	await _frames(10)
	_press(KEY_E)
	await _frames(5)
	_check(s["state"] == Survivors.CARRIED and s["peer"] == _m.me(), "E picks %s up" % s["name"])
	_check(p.speed_scale < 1.0 and not p.can_run, "carrying slows the player, no running")
	_check(_m.arsenal.one_hand and _m.arsenal.weapon == "pistol", "one hand: the pistol only")
	var van: Node = null
	for c: Node in _main.cars:
		if Survivors.seats(c) > 0:
			van = c
			break
	_put_player(van.to_global(van.extents_center + Vector3(van.half_extents.x + 1.0, 0.0, 0.0)))
	await _frames(10)
	_press(KEY_G)
	await _frames(5)
	_check(s["state"] == Survivors.IN_CAR and _m.survivors.in_car(_m.car_key(van)) == 1, "G sits them in the %s" % van.model_name)
	_press(KEY_G)
	await _frames(5)
	_check(s["state"] == Survivors.CARRIED, "G takes them out again")
	_put_player(_m.evac.global_position + Vector3(4.0, 0.0, 0.0))
	await _frames(10)
	_check(s["state"] == Survivors.RESCUED, "carried into Dragon 91's circle: rescued")
	_check(p.speed_scale == 1.0 and p.can_run, "free hands again")

	# knocked down, dead, back at the safehouse
	var s2: Dictionary = list[1]
	_put_player((s2["pos"] as Vector3) + Vector3(1.0, 0.0, 0.0))
	await _frames(10)
	_press(KEY_E)
	await _frames(5)
	var lives: int = _m.lives
	_m.zombie_hit(_m.me(), 500.0, p.global_position + Vector3(1, 0, 0))
	await _frames(5)
	_check(_m.downed and p.crawling and p.speed_scale < 0.3, "at 0 health the player is down, crawling")
	_check(s2["state"] == Survivors.SET_DOWN, "the survivor carried is dropped")
	_m.bleed = 0.05
	await _frames(10)
	_check(_m.dead and not p.visible and _m.lives == lives - 1 and _m.respawn_at > _m.clock(),
			"bled out: dead, a life gone (%d left), coming back" % _m.lives)
	_m.respawn_at = _m.clock()
	await _frames(10)
	_check(not _m.dead and p.visible and _m.health == _m.MAX_HEALTH and p.global_position.distance_to(_m.safehouse_pos) < 6.0,
			"back at the safehouse, healed")

	# the extraction and the win
	for i in list.size():
		if list[i]["state"] != Survivors.RESCUED:
			_m.survivors.set_state(i, Survivors.RESCUED, 0, _m.evac.global_position, "")
	await _frames(5)
	_check(_m.phase == _m.EXTRACTION and _m.phase_until > _m.clock(), "everyone rescued: the extraction starts")
	_put_player(_m.evac.global_position + Vector3(3.0, 0.0, 2.0))
	await _frames(20)
	_m.phase_until = _m.clock()
	await _frames(5)
	_check(_m.phase == _m.WON and _m.escaped and not p.visible, "Dragon 91 lifts off with the player: won")
	_check(_m.evac.flying, "the helicopter flies off")

	# a new mission, then dawn
	_m.new_mission()
	await _frames(10)
	_check(_m.phase == _m.BRIEFING and not _m.escaped and p.visible and _m.health == _m.MAX_HEALTH, "a new mission resets the player")
	_check(_m.survivors.list.all(func(x: Dictionary) -> bool: return x["state"] == Survivors.WAITING), "fresh survivors")
	_m.phase_until = _m.clock() - 1.0
	await _frames(5)
	_m.zombies._spawn_t = 1e9
	_m.dawn_at = _m.clock() - 1.0
	await _frames(5)
	_check(_m.phase == _m.LOST, "dawn with nobody in the circle: lost (%s)" % _m.result)

	# everyone dead, no life left
	_m.new_mission()
	await _frames(5)
	_m.phase_until = _m.clock() - 1.0
	await _frames(5)
	_m.zombies._spawn_t = 1e9
	_m.lives = 0
	_m._set_phase(_m.phase, _m.phase_until)
	_m.zombie_hit(_m.me(), 500.0, p.global_position)
	await _frames(3)
	_m.bleed = 0.0
	await _frames(20)
	_check(_m.phase == _m.LOST and _m.no_life, "dead with no life left: lost (%s)" % _m.result)

	# back to Sandbox
	_main.queue_free()
	await _frames(5)
	OS.set_environment("PLATEAU_MODE", "")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	while _main.game_mode == null:
		await physics_frame
	await _frames(30)
	env = _main.get_node("WorldEnvironment").environment
	_check(_main.game_mode.id == "sandbox" and not _main.night.dread, "Sandbox: no dread")
	_check(not env.fog_enabled or env.fog_density < 0.01, "Sandbox: the fog is gone")
	_check(_main.races.process_mode != Node.PROCESS_MODE_DISABLED and _main.allows("vehicle_menu"), "Sandbox: races, vehicle menu")
	_check(_main.cars.size() == 4, "Sandbox: the 4 cars parked at start")
	print("%d failures" % _failures.size())
	for f in _failures:
		print("  " + f)
	quit(1 if _failures.size() > 0 else 0)
