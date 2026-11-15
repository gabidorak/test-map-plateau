extends RefCounted
## What someone carries: HOTBAR slots in reach of the keys 1 to 5 (the hotbar), then BAG slots (the bag), each empty or
## one stack of one item kind (data/items.json, item_db.gd: up to its `stack`). Only data, no node: the host keeps the
## true one of each player (scripts/items/items.gd), their own game a copy to show (rows: to_rows / from_rows).
## The same container will hold a car's boot, a flat's safe or a bag dropped on the ground: taking, buying, finding,
## losing on an arrest are all moves between containers.
## A slot is {"kind", "n"} and what that one item keeps of its own (a weapon: "loaded", the rounds in it).

signal changed

const ItemDb = preload("res://scripts/items/item_db.gd")

const HOTBAR := 5
const BAG := 20

var slots: Array = []                       # Dictionary per slot, {} when empty

var _hotbar := HOTBAR


func _init(hotbar := HOTBAR, bag := BAG) -> void:
	slots.resize(hotbar + bag)
	for i in slots.size():
		slots[i] = {}
	_hotbar = hotbar


func size() -> int:
	return slots.size()


func hotbar_size() -> int:
	return _hotbar


func is_hotbar(i: int) -> bool:
	return i >= 0 and i < _hotbar


## Slot `i`'s stack ({} when empty, or out of range). Not a copy: change it through the functions below.
func slot(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < slots.size() else {}


func kind_at(i: int) -> String:
	return str(slot(i).get("kind", ""))


func count_at(i: int) -> int:
	return int(slot(i).get("n", 0))


## Items of `kind` carried, all slots together.
func count(kind: String) -> int:
	var n := 0
	for s: Dictionary in slots:
		if s.get("kind", "") == kind:
			n += int(s["n"])
	return n


func has(kind: String) -> bool:
	return count(kind) > 0


## The first slot holding `kind`, -1 none.
func find(kind: String) -> int:
	for i in slots.size():
		if slots[i].get("kind", "") == kind:
			return i
	return -1


## Room left for `kind` (stacks topped up and empty slots).
func room_for(kind: String) -> int:
	if not ItemDb.exists(kind):
		return 0
	var per := ItemDb.stack(kind)
	var n := 0
	for s: Dictionary in slots:
		if s.is_empty():
			n += per
		elif s["kind"] == kind:
			n += per - int(s["n"])
	return n


## Puts up to `n` of `kind` in: the stacks of it first, then empty slots (the hotbar's first for what is used from the
## hand, the bag's first for the rest); a new stack gets `data` (a weapon: {"loaded": 1}). Returns how many went in.
func add(kind: String, n: int, data := {}) -> int:
	if n <= 0 or not ItemDb.exists(kind):
		return 0
	var per := ItemDb.stack(kind)
	var left := n
	for s: Dictionary in slots:
		if left > 0 and s.get("kind", "") == kind and int(s["n"]) < per:
			var k := mini(per - int(s["n"]), left)
			s["n"] = int(s["n"]) + k
			left -= k
	var order := range(slots.size())
	if not ItemDb.hotbar_first(kind):
		order = range(_hotbar, slots.size()) + range(_hotbar)
	for i: int in order:
		if left <= 0:
			break
		if slots[i].is_empty():
			var k := mini(per, left)
			var s := data.duplicate()
			s["kind"] = kind
			s["n"] = k
			slots[i] = s
			left -= k
	if left != n:
		changed.emit()
	return n - left


## Takes up to `n` of `kind` out (the bag's last stacks first). Returns how many came out.
func remove(kind: String, n: int) -> int:
	var left := n
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		if slots[i].get("kind", "") == kind:
			left -= take(i, left, false)
	if left != n:
		changed.emit()
	return n - left


## Takes up to `n` out of slot `i`. Returns how many came out.
func take(i: int, n: int, notify := true) -> int:
	var s := slot(i)
	if s.is_empty() or n <= 0:
		return 0
	var k := mini(n, int(s["n"]))
	s["n"] = int(s["n"]) - k
	if int(s["n"]) <= 0:
		slots[i] = {}
	if notify:
		changed.emit()
	return k


## Moves slot `from` onto slot `to`: into it when empty, onto its stack when the same kind (as much as fits), else the
## two swap. False when nothing moved.
func move(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size() or slots[from].is_empty():
		return false
	var a: Dictionary = slots[from]
	var b: Dictionary = slots[to]
	if b.is_empty():
		slots[to] = a
		slots[from] = {}
	elif b["kind"] == a["kind"] and ItemDb.stack(a["kind"]) > 1:
		var k := mini(ItemDb.stack(a["kind"]) - int(b["n"]), int(a["n"]))
		if k <= 0:
			slots[to] = a
			slots[from] = b
		else:
			b["n"] = int(b["n"]) + k
			a["n"] = int(a["n"]) - k
			if int(a["n"]) <= 0:
				slots[from] = {}
	else:
		slots[to] = a
		slots[from] = b
	changed.emit()
	return true


## Sets what slot `i`'s item keeps of its own (`key`: "loaded"...).
func set_field(i: int, key: String, value: Variant) -> void:
	var s := slot(i)
	if not s.is_empty() and key not in ["kind", "n"]:
		s[key] = value
		changed.emit()


## Takes out every stack `keep_out` says (a Callable(kind) -> bool: what the police seize...): [[kind, n], ...].
func remove_where(keep_out: Callable) -> Array:
	var out := []
	for i in slots.size():
		var s: Dictionary = slots[i]
		if not s.is_empty() and keep_out.call(s["kind"]):
			out.append([s["kind"], int(s["n"])])
			slots[i] = {}
	if not out.is_empty():
		changed.emit()
	return out


func clear() -> void:
	for i in slots.size():
		slots[i] = {}
	changed.emit()


## The slots for the network or a save: a copy, {} for an empty one.
func to_rows() -> Array:
	var out := []
	for s: Dictionary in slots:
		out.append(s.duplicate())
	return out


## Takes `rows` (to_rows) in: unknown kinds left out, counts kept within their stack.
func from_rows(rows: Array) -> void:
	for i in slots.size():
		var r: Variant = rows[i] if i < rows.size() else {}
		var s: Dictionary = (r as Dictionary).duplicate() if r is Dictionary else {}
		if s.is_empty() or not ItemDb.exists(str(s.get("kind", ""))):
			slots[i] = {}
			continue
		s["n"] = clampi(int(s.get("n", 1)), 1, ItemDb.stack(s["kind"]))
		slots[i] = s
	changed.emit()

