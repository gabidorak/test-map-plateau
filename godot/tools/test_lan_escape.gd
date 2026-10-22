extends SceneTree
## Headless check of Escape from Plateau in a LAN game (scripts/escape/escape_mode.gd): run as a host and a client at
## once (tools/test_lan_escape.sh, port 7795):
## - the client joining plays the host's mode and gets its mission: the same survivors at the same hideouts, the
##   helicopter's field, the supplies; the host gets the client's state (where they are);
## - the host puts a zombie in front of the client, which shoots it dead: the host counts the kill;
## - a zombie's blow from the host hurts the client (its own peer's health, seen back on the host);
## - the client picks a survivor up (the host sees them carried by the client) and carries them into the helicopter's
##   circle (rescued, everywhere);
## - the client is knocked down (the host sees it lying), the host holds E by them and they are up again.
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

const Zombie = preload("res://scripts/escape/zombie.gd")
const Survivors = preload("res://scripts/escape/survivors.gd")
var _ready_file := OS.get_temp_dir().path_join("test_lan_escape_ready")

var _main: Node
var _m: Node
var _failures: PackedStringArray = []
var _hosting := false


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	if _hosting:
		DirAccess.remove_absolute(_ready_file)
	OS.set_environment("PLATEAU_ESCAPE_SURVIVORS", "4")
	_main = load("res://scenes/main.tscn").instantiate()
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


func _aim_at(target: Vector3) -> void:
	var p: CharacterBody3D = _main.player
	var d: Vector3 = target - p.camera.global_position
	p.teleport(p.global_position, atan2(-d.x, -d.z))
	p.kick(atan2(d.y, Vector2(d.x, d.z).length()) - p.view_pitch())


func _finish() -> void:
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _run() -> void:
	if not await _until(func() -> bool: return _main.game_mode != null and _main.mode != "" \
			and _main.game_mode.get("survivors") != null and not _main.game_mode.survivors.list.is_empty() \
			and _main.game_mode.evac != null, 60.0):
		_check(false, "the mission started")
		_finish()
		return
	_m = _main.game_mode
	if _hosting:
		await _host()
	else:
		await _client()
	_finish()


func _host() -> void:
	_m.zombies._spawn_t = 1e9                   # no risers: the zombie here is the test's
	var f := FileAccess.open(_ready_file, FileAccess.WRITE)
	f.store_string("ready")
	f.close()
	var joined := await _until(func() -> bool: return _main.net.players.size() == 2, 60.0)
	_check(joined, "the client joined")
	if not joined:
		return
	var guest: int = _main.net.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	_check(await _until(func() -> bool: return _m.vitals.has(guest), 15.0), "the client's state comes in")
	await _frames(30)
	_m.phase_until = _m.clock() - 1.0
	await _until(func() -> bool: return _m.phase == _m.RESCUE, 5.0)
	# a zombie in front of the client, which shoots it
	await _frames(60)
	var at: Vector3 = _m.vitals[guest]["pos"]
	var z: Zombie = _m.zombies.spawn(_m.ground_at(Vector2(at.x, -(at.z - 8.0))), Zombie.SHAMBLER, false, true)
	_check(await _until(func() -> bool: return _m.zombies.kills >= 1, 30.0) and z.state == Zombie.DEAD,
			"the client shot the zombie dead (the host counts %d kill)" % _m.zombies.kills)
	# a blow on the client
	await _frames(60)
	var hp: float = _m.vitals[guest]["health"]
	_m.zombie_hit(guest, 20.0, at)
	_check(await _until(func() -> bool: return _m.vitals[guest]["health"] < hp, 10.0),
			"a zombie's blow hurts the client (%.0f -> %.0f)" % [hp, _m.vitals[guest]["health"]])
	# the client carries a survivor to the helicopter
	var s: Dictionary = _m.survivors.list[0]
	_check(await _until(func() -> bool: return s["state"] == Survivors.CARRIED and s["peer"] == guest, 30.0),
			"the client carries %s" % s["name"])
	_check(await _until(func() -> bool: return s["state"] == Survivors.RESCUED, 30.0), "the client rescued %s" % s["name"])
	# knocked down, helped up
	await _frames(60)
	_m.zombie_hit(guest, 500.0, at)
	_check(await _until(func() -> bool: return _m.vitals[guest]["flags"] & _m.FLAG_DOWN != 0, 10.0), "the client is down")
	var r: Node = _main.net.avatar(guest)
	await _frames(10)
	_check(r != null and r.body().rotation.x < -1.0, "the client's avatar lies on the ground")
	var where: Vector3 = _m.vitals[guest]["pos"]
	_main.player.teleport(where + Vector3(1.0, 0.3, 0.0))
	await _frames(10)
	Input.action_press("interact")
	var up := await _until(func() -> bool: return _m.vitals[guest]["flags"] & _m.FLAG_DOWN == 0, 12.0)
	Input.action_release("interact")
	_check(up, "holding E by the client helps them up")
	await _until(func() -> bool: return _main.net.players.size() == 1, 60.0)


func _client() -> void:
	_check(_m.id == "escape", "the client plays the host's mode")
	_check(_m.survivors.list.size() == 4 and _m.loot.items.size() > 20, "the client has the mission: %d survivors, %d supplies" % [
			_m.survivors.list.size(), _m.loot.items.size()])
	_check(_main.night.dread, "the client's night is in dread")
	_m.assume_captured = true
	await _until(func() -> bool: return _m.phase == _m.RESCUE, 30.0)
	_check(_m.phase == _m.RESCUE, "the rescue starts on the client too")
	_main.player.set_first_person(true)
	# the zombie the host puts in front of us
	var found := []                             # (lambdas capture variables by value: the zombie goes in here)
	var seen := await _until(func() -> bool:
		for o: Zombie in _m.zombies.zombies.values():
			if o.state != Zombie.DEAD and o.global_position.distance_to(_main.player.global_position) < 20.0:
				found.append(o)
				return true
		return false, 30.0)
	_check(seen, "a zombie shows up in front of the client")
	if seen:
		var z: Zombie = found[0]
		for k in 16:
			if z.state == Zombie.DEAD:
				break
			_aim_at(z.global_position + Vector3.UP * 1.2)
			await _frames(1)
			_trigger(true)
			await _frames(2)
			_trigger(false)
			await _frames(14)
		_check(await _until(func() -> bool: return not is_instance_valid(z) or z.state == Zombie.DEAD, 5.0),
				"the client's rounds killed it")
	# the host's blow
	_check(await _until(func() -> bool: return _m.health < 100.0, 15.0), "the client is hurt (%.0f)" % _m.health)
	# a survivor to the helicopter
	var s: Dictionary = _m.survivors.list[0]
	_main.player.teleport((s["pos"] as Vector3) + Vector3(1.0, 0.3, 0.0))
	await _frames(20)
	_press(KEY_E)
	_check(await _until(func() -> bool: return s["state"] == Survivors.CARRIED and s["peer"] == _m.me(), 10.0),
			"E picks %s up" % s["name"])
	await _frames(30)
	_main.player.teleport(_m.evac.global_position + Vector3(4.0, 0.3, 0.0))
	_check(await _until(func() -> bool: return s["state"] == Survivors.RESCUED, 10.0), "rescued in Dragon 91's circle")
	# knocked down by the host, helped up
	_check(await _until(func() -> bool: return _m.downed, 15.0), "the client is down")
	_check(await _until(func() -> bool: return not _m.downed, 20.0) and _m.health == _m.REVIVE_HEALTH,
			"the host helped the client up (%.0f health)" % _m.health)
	await _frames(30)
