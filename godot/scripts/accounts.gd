extends Node
## PTA Online accounts client: HTTPS calls to the accounts service (server/accounts/, ONLINE_MODE.md 3), one
## HTTPRequest per call, each `await`ed for a result {"ok": bool, "status": HTTP code (0: no answer), "error": the
## service's code ("down" when it can't be reached), "message": text to show, "data": the answer}.
## The game keeps the session token, never the password: in user://account.cfg when "remember me" is on (the default),
## else for this run only. The official game server uses the same calls with its secret (server_get/server_post,
## scripts/economy.gd).
## Addresses: the build's res://data/online.json, "accounts_url" and "server" (the official game server, "host:port"),
## overridden by PLATEAU_ACCOUNTS_URL and PLATEAU_ONLINE_SERVER (tests, the game server's container).

const CFG := "user://account.cfg"
const ADDRESSES := "res://data/online.json"
const API := 1                              # the service refuses older games with "please update" (Plateau-Api)
const TIMEOUT := 8.0                        # s per call
const DOWN := "The PTA Online accounts service can't be reached: check your connection, or try again later."

static var _session := {}                   # {"token", "username"} when "remember me" is off (this run only)


static func _address(key: String, env_name: String) -> String:
	var env := OS.get_environment(env_name)
	if env != "":
		return env
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ADDRESSES))
	return str(data.get(key, "")) if data is Dictionary else ""


static func accounts_url() -> String:
	return _address("accounts_url", "PLATEAU_ACCOUNTS_URL").trim_suffix("/")


## The official game server, ["host", port], or [] when this build has none.
static func official_server() -> Array:
	var where := _address("server", "PLATEAU_ONLINE_SERVER")
	if where == "":
		return []
	if where.contains(":") and where.get_slice(":", 1).is_valid_int():
		return [where.get_slice(":", 0), int(where.get_slice(":", 1))]
	return [where, 7777]


## {"token", "username", "remember"}: the login kept on this computer (or this run), token "" when logged out.
static func saved() -> Dictionary:
	if not _session.is_empty():
		return {"token": _session["token"], "username": _session["username"], "remember": false}
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	return {"token": str(cfg.get_value("account", "token", "")), "username": str(cfg.get_value("account", "username", "")),
			"remember": bool(cfg.get_value("account", "remember", true))}


static func token() -> String:
	return saved()["token"]


## Keeps a login: on disk when `remember`, else until the game closes (and the file forgets any older one).
static func keep(new_token: String, username: String, remember: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("account", "remember", remember)
	cfg.set_value("account", "username", username)   # pre-filled at the next login either way
	cfg.set_value("account", "token", new_token if remember else "")
	cfg.save(CFG)
	_session = {} if remember else {"token": new_token, "username": username}


## Forgets the token (logged out, or the service no longer knows it); the username stays to pre-fill the form.
static func forget() -> void:
	_session = {}
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("account", "token", "")
	cfg.save(CFG)


func signup(username: String, password: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/signup", {"username": username, "password": password})


func login(username: String, password: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/login", {"username": username, "password": password})


func me() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/me", {}, ["Authorization: Bearer " + token()])


func rename(new_name: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/rename", {"username": new_name}, ["Authorization: Bearer " + token()])


## Logs this token out on the service (or every device's, `everywhere`) and forgets it here whatever the answer.
func logout(everywhere := false) -> Dictionary:
	var r := await _call(HTTPClient.METHOD_POST, "/v1/logout-all" if everywhere else "/v1/logout", {},
			["Authorization: Bearer " + token()])
	forget()
	return r


## The official game server's calls: the internal API, with the server secret.
func server_get(path: String, secret: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, path, {}, ["X-Server-Secret: " + secret])


func server_post(path: String, body: Dictionary, secret: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, path, body, ["X-Server-Secret: " + secret])


func _call(method: int, path: String, body: Dictionary, headers: Array = []) -> Dictionary:
	var base := accounts_url()
	if base == "":
		return {"ok": false, "status": 0, "error": "down", "message": "PTA Online isn't set up in this build.", "data": {}}
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	var h := PackedStringArray(["Content-Type: application/json", "Plateau-Api: %d" % API])
	h.append_array(headers)
	var err := req.request(base + path, h, method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if err != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "error": "down", "message": DOWN, "data": {}}
	var res: Array = await req.request_completed   # result, code, headers, body
	req.queue_free()
	var code: int = res[1]
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if res[0] != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500 or (data.is_empty() and code != 200):
		return {"ok": false, "status": code, "error": "down", "message": DOWN, "data": {}}
	if code == 200:
		return {"ok": true, "status": code, "error": "", "message": "", "data": data}
	return {"ok": false, "status": code, "error": str(data.get("error", "")),
			"message": str(data.get("message", "Something went wrong (HTTP %d)." % code)), "data": data}
