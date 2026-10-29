extends Node
## PTA Online on the official server (ONLINE_MODE.md, ONLINE_MILESTONES.md): Main/Economy, made by game.gd on every
## peer (its RPCs live here so net.gd's don't move): logins and the wallet. The garages are PTA Online's game mode's
## (scripts/modes/online_mode.gd), which asks this node who a player is and what they own.
## - A client joining from PTA Online (game.gd start_online) sends its session token as soon as the host's welcome
##   comes in (net.gd `welcomed`), never its password. Only an official server (game.gd --dedicated --official) reads
##   it: it asks the accounts service who that is (scripts/accounts.gd, internal API with PLATEAU_SERVER_SECRET), then
##   the player's name everywhere is their username, and they get their balance.
## - The official server kicks with a message (shown on the welcome menu): a player with no valid login LOGIN_WAIT s
##   after joining, an unknown or expired token (the game then forgets it), a banned account, anyone while the accounts
##   service can't be reached, and the older connection of an account logging in again elsewhere.
## - The official server keeps each logged-in player's account, username, balance, vehicles and token (to read their
##   garage again: refresh); a player's wallet (top right of the screen, online_mode.gd) follows the server's word.
## - Other servers ignore tokens (they can't check them, and a LAN host must never get one: the game only sends it to
##   the official server's address).

const Accounts = preload("res://scripts/accounts.gd")

signal account_changed                      # client: `username` and `balance` came from the official server
signal wallet_changed                       # client: `balance` changed (the server's word), or came with the login
signal kicked(message: String)              # client: the official server sent us away (game.gd goes back to the menu)
signal logged_in(id: int)                   # official server: player `id`'s login was checked (account_of has it)

const LOGIN_WAIT := 10.0                    # s an official server waits for a joining player's login

var game: Node3D                            # game.gd
var official := false                       # this is the official PTA Online server (--official)
var secret := ""                            # official server: PLATEAU_SERVER_SECRET
var accounts: Accounts
var username := ""                          # client: logged in as (from the server)
var balance := 0                            # client: €

var _waiting := {}                          # server: peer -> s since it joined without a login yet
var _checking := {}                         # server: peer -> true while the accounts service is asked
var _logged := {}                           # server: peer -> {"account", "username", "balance", "vehicles", "token"}


func _ready() -> void:
	accounts = Accounts.new()
	accounts.name = "Accounts"
	add_child(accounts)
	game.net.registered.connect(_on_registered)
	game.net.welcomed.connect(_on_welcomed)
	multiplayer.peer_disconnected.connect(_forget)


## "12 500 €"
static func money(euros: int) -> String:
	var digits := str(absi(euros))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if euros < 0 else "") + out + " €"


## Server: becomes the official one; false with a message when the accounts service's address or secret is missing.
func make_official() -> String:
	secret = OS.get_environment("PLATEAU_SERVER_SECRET")
	if secret == "" or Accounts.accounts_url() == "":
		return "--official needs PLATEAU_ACCOUNTS_URL and PLATEAU_SERVER_SECRET (server/compose.yaml)."
	official = true
	return ""


## Server: player `id`'s account {"account", "username", "balance", "vehicles": [{"id", "model", "colour", "wrecked",
## "upgrades"}]}, or {} (not logged in, or not the official server).
func account_of(id: int) -> Dictionary:
	return _logged.get(id, {})


## Server: reads player `id`'s account again from the accounts service (their garage may have changed: the admin, a
## purchase); false when it could not.
func refresh(id: int) -> bool:
	if not _logged.has(id):
		return false
	var r: Dictionary = await accounts.server_get("/v1/server/who?token=" + str(_logged[id]["token"]).uri_encode(), secret)
	if not r["ok"] or not _logged.has(id):
		return false
	_logged[id]["balance"] = int(r["data"]["balance"])
	_logged[id]["vehicles"] = r["data"].get("vehicles", [])
	_wallet.rpc_id(id, _logged[id]["balance"])
	return true


## Server: changes a vehicle of account `account_id` through the accounts service, charging `change["price"]` € in the
## same go (`change`: action add / repair / wreck / colour, vehicle, model, colour, price: server/accounts VehicleChange).
## The answer as accounts.gd's ({"ok", "error", "message", "data": {"vehicle", "balance", "vehicles"}}); a logged-in
## player of that account sees their wallet follow.
func vehicle_change(account_id: int, change: Dictionary) -> Dictionary:
	var r: Dictionary = await accounts.server_post("/v1/server/vehicle", change.merged({"account": account_id}), secret)
	if r["ok"]:
		for id: int in _logged:
			if _logged[id]["account"] == account_id:
				_logged[id]["balance"] = int(r["data"]["balance"])
				_logged[id]["vehicles"] = r["data"]["vehicles"]
				_wallet.rpc_id(id, _logged[id]["balance"])
	return r


## Server: pays account `account_id` `amount` € for job `job` ("bus:4606"...), cut to the account's hourly cap `cap`
## (the accounts service counts every job's pay over the last hour: server/accounts db.earn). The answer as accounts.gd's,
## "data": {"balance", "paid", "hour"}; a logged-in player of that account sees their wallet follow.
func pay(account_id: int, amount: int, reason: String, job: String, cap: int) -> Dictionary:
	var r: Dictionary = await accounts.server_post("/v1/server/pay", {"account": account_id, "amount": amount,
			"reason": reason, "job": job, "cap": cap}, secret)
	if r["ok"]:
		for id: int in _logged:
			if _logged[id]["account"] == account_id:
				_logged[id]["balance"] = int(r["data"]["balance"])
				_wallet.rpc_id(id, _logged[id]["balance"])
	return r


func _on_registered(id: int) -> void:
	if official:
		_waiting[id] = 0.0


func _process(delta: float) -> void:
	for id: int in _waiting.keys():
		_waiting[id] += delta
		if _waiting[id] > LOGIN_WAIT:
			kick(id, "login", "This is the PTA Online server: join it from PTA Online in the main menu, logged in.")


func _forget(id: int) -> void:
	_waiting.erase(id)
	_checking.erase(id)
	_logged.erase(id)


## Server: sends player `id` away with `message` (`code` tells the game what to do: "token" forgets the login).
func kick(id: int, code: String, message: String) -> void:
	_forget(id)
	if game.net.dedicated:
		print("Kicked %s (%d): %s" % [game.net.player_name(id), id, message])
	_kicked.rpc_id(id, code, message)
	game.net.drop_peer(id)


func _on_welcomed() -> void:
	if game.online:
		_login.rpc_id(1, Accounts.token())


@rpc("any_peer", "call_remote", "reliable")
func _login(token: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not official or not _waiting.has(id):
		return
	_waiting.erase(id)
	_checking[id] = true
	var r: Dictionary = await accounts.server_get("/v1/server/who?token=" + token.uri_encode(), secret)
	if not _checking.has(id):
		return                              # left meanwhile
	_checking.erase(id)
	if not r["ok"]:
		match r["error"]:
			"token":
				kick(id, "token", "Your PTA Online login has expired: log in again.")
			"banned":
				kick(id, "banned", "This account is banned.")
			"down":
				kick(id, "down", "The PTA Online accounts service is down right now: try again later.")
			_:
				kick(id, "login", "PTA Online refused the login: %s" % r["message"])
		return
	var who: Dictionary = r["data"]
	for other: int in _logged.keys():
		if _logged[other]["account"] == int(who["account"]):
			kick(other, "elsewhere", "You joined PTA Online from another place.")
	_logged[id] = {"account": int(who["account"]), "username": str(who["username"]), "balance": int(who["balance"]),
			"vehicles": who.get("vehicles", []), "token": token}
	_named.rpc(id, str(who["username"]))
	_named(id, str(who["username"]))
	_account.rpc_id(id, str(who["username"]), int(who["balance"]))
	if game.net.dedicated:
		print("%s (%d) logged in as %s" % [game.net.player_name(id), id, who["username"]])
	logged_in.emit(id)


## Everyone: player `id`'s name is their username.
@rpc("authority", "call_remote", "reliable")
func _named(id: int, name_now: String) -> void:
	game.net.set_player_name(id, name_now)
	if id == game.net.me():
		game.nickname = name_now


@rpc("authority", "call_remote", "reliable")
func _account(name_now: String, money: int) -> void:
	username = name_now
	balance = money
	account_changed.emit()
	wallet_changed.emit()


## The wallet's balance now (the server's word).
@rpc("authority", "call_remote", "reliable")
func _wallet(money: int) -> void:
	balance = money
	wallet_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _kicked(code: String, message: String) -> void:
	if code in ["token", "banned"]:
		Accounts.forget()
	kicked.emit(message)
