extends SceneTree
## Client side of tools/test_online_login.sh (PTA Online logins on an official server). One check per run, picked by
## the first argument after `--`:
## - `--rules`: scripts/account_rules.gd judges server/accounts/rule_vectors.json like the service (no server needed);
## - `--signup=NAME`: creates the account on the accounts service (and sees a taken name, a wrong password and a bad
##   name refused), then joins PTA Online: the server confirms the login, the name everywhere is the username;
## - `--remembered=NAME`: a new run, nothing typed: the login kept in user://account.cfg joins as NAME;
## - `--bad-token`: a made-up token kept: the server kicks with "expired" and the game forgets it;
## - `--no-login`: joins the official server like a LAN game (no token): kicked after Economy.LOGIN_WAIT s;
## - `--service-down`: the accounts service is gone: logging in says it can't be reached, and joining with a kept login
##   is refused by the server with "down";
## - `--server-down`: no game server at the official address: the message says it isn't answering.
## Exit code 1 on failure.

const Accounts = preload("res://scripts/accounts.gd")
const AccountRules = preload("res://scripts/account_rules.gd")
const PASSWORD := "a long test password"

var _main: Node
var _what := ""
var _arg := ""
var _failures: PackedStringArray = []


## The welcome menu's notice (why the game went back to it). main_menu.gd is loaded only now: preloaded, it would be
## compiled before the Settings autoload exists, and the scripts it depends on would stay broken for the game.
func _notice() -> String:
	return load("res://scripts/main_menu.gd").notice


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] in ["rules", "signup", "remembered", "bad-token", "no-login", "service-down", "server-down"]:
			_what = kv[0]
			_arg = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + "[%s] " % _what + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await process_frame
	return true


## The game, as the tools make it: main.tscn instanced (it reads --online / --join from the command line).
func _start_game() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)


func _client() -> Accounts:
	var a := Accounts.new()
	root.add_child(a)
	return a


func _run() -> void:
	match _what:
		"rules":
			_rules()
		"signup":
			await _signup()
		"remembered":
			_check(Accounts.token() != "" and Accounts.saved()["username"] == _arg, "a login is kept for %s" % _arg)
			await _join_online(_arg)
		"bad-token":
			Accounts.keep("made-up-token", "Nobody", true)
			await _kicked("Your PTA Online login has expired")
			_check(Accounts.token() == "", "the game forgot the bad token")
		"no-login":
			await _kicked("This is the PTA Online server")
		"service-down":
			var r: Dictionary = await _client().login("Whoever", PASSWORD)
			_check(not r["ok"] and r["error"] == "down" and r["message"] == Accounts.DOWN,
					"logging in with the service down: %s" % r["message"])
			if _arg != "":
				Accounts.keep(_arg, "Kept", true)
				await _kicked("The PTA Online accounts service is down")
		"server-down":
			Accounts.keep("some-token", "Someone", true)
			_start_game()
			var failed := await _until(func() -> bool: return _notice() != "", 20.0)
			_check(failed and _notice().begins_with("The PTA Online server isn't answering"),
					"no server: %s" % _notice())
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _rules() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../server/accounts/rule_vectors.json")
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(v != null and not v.is_empty(), "read %s" % path)
	for n: String in v["usernames_ok"]:
		_check(AccountRules.username_problem(n) == "", "username %s accepted (%s)" % [n, AccountRules.username_problem(n)])
	for e: Array in v["usernames_refused"]:
		var p := AccountRules.username_problem(e[0])
		_check(p.begins_with(e[1]), "username %s refused: %s" % [e[0], p])
	for e: Array in v["passwords_ok"]:
		_check(AccountRules.password_problem(e[0], e[1]) == "", "password %s accepted" % e[0])
	for e: Array in v["passwords_refused"]:
		var p := AccountRules.password_problem(e[0], e[1])
		_check(p.begins_with(e[2]), "password %s… refused: %s" % [e[0].left(12), p])
	_check(AccountRules.skeleton("Gabr1el") == AccountRules.skeleton("ga-briel"), "look-alikes have the same skeleton")


func _signup() -> void:
	var a := _client()
	var r: Dictionary = await a.signup("a__b", PASSWORD)
	_check(not r["ok"] and r["status"] == 400 and r["message"].begins_with("No two of"), "bad name refused: %s" % r["message"])
	r = await a.signup(_arg, PASSWORD)
	_check(r["ok"] and r["data"]["username"] == _arg and int(r["data"]["balance"]) == 5000,
			"signed up as %s with 5 000 € (%s)" % [_arg, r["message"]])
	if not r["ok"]:
		return
	Accounts.keep(r["data"]["token"], r["data"]["username"], true)
	var taken: Dictionary = await a.signup(_arg.to_lower(), PASSWORD)
	_check(taken["status"] == 409, "%s taken: %s" % [_arg.to_lower(), taken["message"]])
	var wrong: Dictionary = await a.login(_arg, "not the password")
	_check(wrong["status"] == 401 and wrong["message"] == "Wrong username or password.", "wrong password refused")
	var me: Dictionary = await a.me()
	_check(me["ok"] and me["data"]["username"] == _arg, "me: %s" % str(me["data"]))
	await _join_online(_arg)


## Joins PTA Online with the kept login and checks the server took it.
func _join_online(username: String) -> void:
	_start_game()
	var joined := await _until(func() -> bool: return _main.mode == "client", 40.0)
	_check(joined and _main.online, "joined the official server (%s)" % _notice())
	if not joined:
		return
	var economy: Node = _main.economy
	var logged := await _until(func() -> bool: return economy.username != "", 10.0)
	_check(logged and economy.username == username and economy.balance == 5000,
			"logged in as %s with %d € (got %s)" % [username, economy.balance, economy.username])
	var net: Node = _main.net
	_check(net.player_name(net.me()) == username and _main.nickname == username,
			"the name played under is the username (%s)" % net.player_name(net.me()))
	var still := true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 11000:       # past the server's LOGIN_WAIT: not kicked
		await process_frame
		still = still and net.active
	_check(still and _notice() == "", "still in the game after %d s" % 11)


func _kicked(start: String) -> void:
	_start_game()
	var kicked := await _until(func() -> bool: return _notice() != "", 40.0)
	_check(kicked and _notice().begins_with(start), "kicked: %s" % _notice())
	_check(not _main.net.active, "out of the game")
