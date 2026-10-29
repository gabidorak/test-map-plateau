extends RefCounted
## PTA Online's prices (data/prices.json, ONLINE_MODE.md 4.1): what each vehicle costs and where it is sold, what a
## repair and a repaint cost. The official server charges them (scripts/online/shop.gd); the players' games show them
## (the same file is in every build). A model not in the file is not sold.

const DATA := "res://data/prices.json"
const PLACES := {"prestige": "Prestige Motors", "depot": "the bus depot", "fire": "the fire station"}

static var _data := {}
static var _models := {}                    # model -> {"price", "tier", "at"}


static func _load() -> void:
	if not _models.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not parsed is Dictionary:
		push_error("No PTA Online prices: %s missing" % DATA)
		return
	_data = parsed
	for t: Dictionary in _data["tiers"]:
		for m: String in t["models"]:
			_models[m] = {"price": int(t["models"][m]), "tier": str(t["tier"]), "at": str(t["at"])}


## € of `model`, 0 when it is not sold.
static func price(model: String) -> int:
	_load()
	return int(_models.get(model, {}).get("price", 0))


## The catalogue tier of `model` ("Starter", "Work"...), "" when not sold.
static func tier(model: String) -> String:
	_load()
	return str(_models.get(model, {}).get("tier", ""))


## Where `model` is sold (a PLACES key), "" nowhere.
static func sold_at(model: String) -> String:
	_load()
	return str(_models.get(model, {}).get("at", ""))


## The models sold at `place` (a PLACES key), in catalogue order.
static func catalogue(place: String) -> Array:
	_load()
	var out := []
	for m: String in _models:
		if _models[m]["at"] == place:
			out.append(m)
	return out


## € to repair `model` once wrecked (0 when it has no price: nothing to repair, e.g. the admin gave it).
static func repair(model: String) -> int:
	_load()
	return _round(price(model) * float(_data.get("repair", 0.03)))


## € to repaint `model`.
static func repaint(model: String) -> int:
	_load()
	return maxi(_round(price(model) * float(_data.get("repaint", 0.02))), int(_data.get("repaint_min", 200)))


## Euros a new account starts with (the accounts service gives them; shown in the docs and the catalogue's hint).
static func start_money() -> int:
	_load()
	return int(_data.get("start", 5000))


static func _round(euros: float) -> int:
	return roundi(euros / 10.0) * 10
