extends RefCounted
## PTA Online's username and password rules (ONLINE_MODE.md 3.4), checked while the player types on the account page
## (scripts/main_menu.gd) so they see the problem before sending. The accounts service (server/accounts/plateau_accounts/
## rules.py) checks the same rules with the same messages, from the same lists (res://data/account_rules.json, written
## by server/accounts/sync_client_rules.py); server/accounts/rule_vectors.json holds examples both must judge alike
## (tools/test_online_login.gd --rules). Uniqueness, look-alikes of other names, lockouts and the sign-up limit are only
## the service's.

const DATA := "res://data/account_rules.json"
const SEPARATORS := "_-."
const LOOKALIKES := {"0": "o", "1": "i", "l": "i", "3": "e", "4": "a", "5": "s", "7": "t"}

static var _data := {}
static var _banned := PackedStringArray()     # skeletons
static var _reserved := {}                    # skeleton -> true
static var _common := {}                      # lowercase password -> true


static func _load() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_data = parsed if parsed is Dictionary else {"name_min": 3, "name_max": 16, "password_min": 8,
			"password_max": 128, "short_word": 3, "reserved": [], "banned": [], "common_passwords": []}
	for w: String in _data["banned"]:
		_banned.append(skeleton(w))
	for r: String in _data["reserved"]:
		_reserved[skeleton(r)] = true
	for p: String in _data["common_passwords"]:
		_common[p.to_lower()] = true


## The form two names are compared in: lowercase, look-alike digits mapped to letters, separators dropped.
static func skeleton(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		if c in SEPARATORS:
			continue
		out += LOOKALIKES.get(c, c)
	return out


static func _name_char(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 0x61 and u <= 0x7a) or (u >= 0x41 and u <= 0x5a) or (u >= 0x30 and u <= 0x39) or c in SEPARATORS


## Why `name` can't be a username, or "".
static func username_problem(name: String) -> String:
	_load()
	var lo: int = _data["name_min"]
	var hi: int = _data["name_max"]
	if name.length() < lo or name.length() > hi:
		return "A username has %d to %d characters." % [lo, hi]
	for c in name:
		if not _name_char(c):
			return "Only letters without accents, digits, _ - and . (no spaces)."
	if name[0] in SEPARATORS:
		return "A username starts with a letter or a digit."
	if name[-1] in SEPARATORS:
		return "A username doesn't end with _ - or ."
	for i in name.length() - 1:
		if name[i] in SEPARATORS and name[i + 1] in SEPARATORS:
			return "No two of _ - . in a row."
	var sk := skeleton(name)
	if _reserved.has(sk):
		return "This name is reserved."
	for w in _banned:
		if (sk == w) if w.length() <= int(_data["short_word"]) else sk.contains(w):
			return "This name isn't allowed."
	return ""


## Why `password` can't be used (for `username`), or "".
static func password_problem(password: String, username := "") -> String:
	_load()
	if password.length() < int(_data["password_min"]):
		return "A password has at least %d characters." % int(_data["password_min"])
	if password.length() > int(_data["password_max"]):
		return "A password has at most %d characters." % int(_data["password_max"])
	if username != "" and password.to_lower() == username.to_lower():
		return "The password can't be the username."
	if _common.has(password.to_lower()):
		return "This password is one of the most common ones: pick another."
	return ""
