extends "res://tools/test_base.gd"
## PTA Online's properties with two players (ONLINE_MILESTONES.md O9; scripts/online/properties.gd): the clients of
## tools/test_properties_online.sh (an official server whose PLATEAU_ONLINE_HOMES gives Owner_1 the studio of the
## Logements de l'X 19 with its garage; `--sync=DIR` holds the files the clients wait on each other with). The role is
## the first argument after `--`:
## - `--owner=TOKEN`: told what they own, goes in (the visitor outside no longer sees them, nor they the visitor),
##   opens the door once the visitor was refused, sees the visitor come in, leaves by the lift at the wheel of their
##   car;
## - `--visitor=TOKEN`: has no interior while out, is refused the locked flat, visits it once open (sees the owner
##   there, and no longer once the owner left by the lift), leaves.
## Exit code 1 on failure.

const ID := "logx-19-studio"

var _main: Node
var _mode: Node
var _what := ""
var _arg := ""
var _sync := ""
var _failures: PackedStringArray = []
var _toasts: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["owner", "visitor"]:
			_what = kv[0]
			_arg = kv[1] if kv.size() > 1 else ""
		elif kv[0] == "sync":
			_sync = kv[1]
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + "[%s] " % _what + what)
	if not ok:
		_failures.append(what)


func _mark(name: String) -> void:
	var f := FileAccess.open(_sync.path_join(name), FileAccess.WRITE)
	f.store_string("1")
	f.close()


func _await_mark(name: String, timeout := 180.0) -> bool:
	var path := _sync.path_join(name)
	var there := await _until(func() -> bool: return FileAccess.file_exists(path), timeout)
	_check(there, "the other side got to '%s'" % name)
	return there


func _run() -> void:
	var username := "Owner_1" if _what == "owner" else "Visitor_1"
	load("res://scripts/accounts.gd").keep(_arg, username, false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var joined := await _until(func() -> bool: return _main.mode == "client" and _main.game_mode != null, 90.0)
	_check(joined and _main.mode_id == "online", "joined PTA Online")
	var logged := joined and await _until(func() -> bool: return _main.economy.username == username, 20.0)
	_check(logged, "logged in as %s" % username)
	if logged:
		_mode = _main.game_mode
		_main.toast_shown.connect(func(text: String) -> void: _toasts.append(text))
		if _what == "owner":
			await _owner()
		else:
			await _visitor()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _toasted(part: String) -> bool:
	for t: String in _toasts:
		if t.contains(part):
			return true
	return false


## The peer id of player `name`, 0 when not in the game.
func _peer(name: String) -> int:
	for id: int in _main.net.players:
		if str(_main.net.players[id]["name"]) == name:
			return id
	return 0


## Whether player `name`'s avatar shows here (within `timeout` s).
func _sees(name: String, timeout := 6.0) -> bool:
	return await _until(func() -> bool:
		var r: Node3D = _main.net.avatar(_peer(name))
		return r != null and r.visible, timeout)


## Whether player `name`'s avatar stays hidden here for `seconds` (after a few frames: the change shows on the next one).
func _hidden(name: String, seconds := 2.0) -> bool:
	for i in 5:
		await process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		var r: Node3D = _main.net.avatar(_peer(name))
		if r != null and r.visible:
			return false
		await process_frame
	return true


func _owner() -> void:
	var props: Node = _mode.properties
	var told := await _until(func() -> bool: return props.is_owned(ID), 10.0)
	_check(told and props.has_garage(ID), "the host told us we own the studio, with its garage")
	props.go_to(ID)
	_mark("owner_at_door")
	await _await_mark("visitor_at_door")
	_check(await _sees("Visitor_1"), "both outside: we see the visitor")
	_check(props.enter(ID) or await _until(func() -> bool: return props.inside == ID, 10.0), "in our flat")
	_check(props.interior != null and props.inside_owner == "Owner_1", "its interior built here")
	_check(await _hidden("Visitor_1"), "inside: the visitor outside is out of sight")
	_mark("owner_in")
	await _await_mark("visitor_refused")
	props.set_door(ID, true)
	_check(await _until(func() -> bool: return props.door_open(ID), 5.0), "our door open to visitors")
	_mark("door_open")
	await _await_mark("visitor_in")
	_check(await _sees("Visitor_1"), "the visitor in our flat: we see them")
	# out by the lift, at the wheel of our car
	var frame: Transform3D = props.get_property(ID)["frame"]
	_main.player.teleport(frame * (props.StudioBuilder.LIFT + Vector3(-0.3, -0.95, 0.0)))
	await _until(func() -> bool: return props.lift_at_hand(), 3.0)
	_check(props.lift_at_hand(), "by the lift")
	props.take_lift()
	var listed := await _until(func() -> bool: return _mode._panel.rows.get_child_count() > 0, 10.0)
	_check(listed, "the lift lists our vehicles")
	var vehicle := -1
	for row in _mode._panel.rows.get_children():
		var parts: PackedStringArray = str(row.name).split("_", true, 2)
		if parts.size() == 3 and parts[2] == "sedan":
			vehicle = int(parts[1])
	_check(vehicle > 0, "our sedan in the list")
	if vehicle > 0:
		_mode.to_host(_mode, "_h_spawn", [props.garage_id(ID), vehicle, "sedan"])
		props._lift = true
		var drove := await _until(func() -> bool: return _main.driving != null, 15.0)
		_check(drove and props.inside == "", "down the lift, at the wheel")
		if drove:
			_check(_main.driving.net_id == _mode.mine, "in our own car")
	_mark("owner_out")
	await _await_mark("visitor_out")


func _visitor() -> void:
	var props: Node = _mode.properties
	await _await_mark("owner_at_door")
	props.go_to(ID)
	await _until(func() -> bool: return not props.door_at_hand().is_empty(), 5.0)
	_check(not props.is_owned(ID), "we own nothing")
	_mark("visitor_at_door")
	await _await_mark("owner_in")
	_check(await _hidden("Owner_1"), "the owner in their flat: out of sight")
	_check(props.interior == null and props.find_children("Interior_*", "", false, false).is_empty(),
			"no interior loaded here while we're out")
	_check(props.visits(ID).is_empty(), "their door locked: nothing to visit")
	props.enter(ID, "Owner_1")
	var refused := await _until(func() -> bool: return _toasted("locked"), 5.0)
	_check(refused and props.inside == "", "refused the locked flat")
	_mark("visitor_refused")
	await _await_mark("door_open")
	var listed := await _until(func() -> bool: return "Owner_1" in props.visits(ID), 5.0)
	_check(listed, "the panel offers a visit of Owner_1's flat")
	props.enter(ID, "Owner_1")
	var inside := await _until(func() -> bool: return props.inside == ID and props.inside_owner == "Owner_1", 10.0)
	_check(inside and props.interior != null, "visiting Owner_1's flat")
	_check(not props.lift_at_hand() and props.interior.has_meta("lift"), "their lift there, not ours to take")
	_check(await _sees("Owner_1"), "the owner there: we see them")
	_mark("visitor_in")
	await _await_mark("owner_out")
	_check(await _hidden("Owner_1"), "the owner gone by the lift: out of sight")
	props.leave()
	await _until(func() -> bool: return props.inside == "", 3.0)
	_check(props.inside == "" and not props.door_at_hand().is_empty(), "out at the entrance")
	_mark("visitor_out")
