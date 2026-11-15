extends RefCounted
## The items a player can carry (data/items.json), read once on every peer: the inventories (inventory.gd), the screens
## (hotbar_hud.gd, inventory_panel.gd) and the host's checks (items.gd) go by the same file. An item not in it does not
## exist: an inventory refuses it.
## A new item is a row in the file; a new way to use one is a script in scripts/items/weapons/ (or, for the food and
## medical kit to come, a use of its own) named by its `behaviour`.

const DATA := "res://data/items.json"

static var _items := {}
static var _effects := {}


static func _load() -> void:
	if not _items.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not parsed is Dictionary:
		push_error("No items: %s missing" % DATA)
		return
	_items = parsed.get("items", {})
	_effects = parsed.get("effects", {})


## Whether `kind` is an item.
static func exists(kind: String) -> bool:
	_load()
	return _items.has(kind)


## Every item kind, in the file's order.
static func kinds() -> Array:
	_load()
	return _items.keys()


## The row of `kind` ({} when it is none).
static func get_item(kind: String) -> Dictionary:
	_load()
	return _items.get(kind, {})


## Field `field` of `kind`'s row, `fallback` when it has none.
static func field(kind: String, field_name: String, fallback: Variant = null) -> Variant:
	return get_item(kind).get(field_name, fallback)


static func item_name(kind: String) -> String:
	return str(field(kind, "name", kind))


static func category(kind: String) -> String:
	return str(field(kind, "category", ""))


static func is_weapon(kind: String) -> bool:
	return category(kind) == "weapon"


## How many fit in one slot.
static func stack(kind: String) -> int:
	return maxi(int(field(kind, "stack", 1)), 1)


## Put on the hotbar first when picked up.
static func hotbar_first(kind: String) -> bool:
	return bool(field(kind, "hotbar", false))


static func color(kind: String) -> Color:
	return Color.from_string(str(field(kind, "color", "#cccccc")), Color(0.8, 0.8, 0.8))


## The effect `effect` (data/items.json "effects": its name, its look): {} when unknown.
static func effect(effect_id: String) -> Dictionary:
	_load()
	return _effects.get(effect_id, {})
