extends PanelContainer
## The inventory (I; items.gd puts it on game.gd's HUD): the hotbar's slots, then the bag's, each with its item's icon
## and count. Click an item, then a slot: it goes there (onto a stack of the same, or the two swap: items.gd move). The
## item under the mouse (or picked) is described beside: what it is, a weapon's numbers. In a game mode that hands items
## out for nothing (Sandbox, the PTA Online test: free_items), a button per item takes a stack of it.
## The player stands still while it is open (game.gd ui_open); I or Esc closes it.

const ItemDb = preload("res://scripts/items/item_db.gd")
const Icons = preload("res://scripts/items/item_icons.gd")
const UiStyle = preload("res://scripts/ui_style.gd")

const SLOT := 64.0
const GAP := 8.0
const COLUMNS := 5
const LIT := Color(1.0, 0.82, 0.3)
const EDGE := Color(1, 1, 1, 0.18)
const BG := Color(0.16, 0.18, 0.23)

var items: Node                             # items.gd

var _grid: Control
var _about: Label
var _free: VBoxContainer
var _free_title: Label
var _picked := -1                           # the slot whose item is being moved, -1 none
var _hover := -1


func _ready() -> void:
	name = "Inventory"
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.label("Inventory", 24))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	_grid.mouse_exited.connect(func() -> void:
		_hover = -1
		_describe()
		_grid.queue_redraw())
	row.add_child(_grid)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	_about = UiStyle.label("", 16, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(300, 120)
	_about.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	side.add_child(_about)
	_free_title = UiStyle.label("Take for free", 18)
	side.add_child(_free_title)
	_free = VBoxContainer.new()
	_free.add_theme_constant_override("separation", 6)
	side.add_child(_free)
	var looks := UiStyle.button_looks()
	for kind: String in ItemDb.kinds():
		var n := 1 if ItemDb.is_weapon(kind) else ItemDb.stack(kind)
		var b := UiStyle.button(ItemDb.item_name(kind) + ("" if n == 1 else "  ×%d" % n), looks, Vector2(300, 36), 16)
		b.name = kind
		b.pressed.connect(func() -> void: items.take_free(kind))
		_free.add_child(b)
	box.add_child(UiStyle.label("Click an item, then a slot to move it there · 1-5 take a hotbar item in hand · " +
			"I / Esc close", 15, UiStyle.TEXT_DIM))
	_size_grid()


func _size_grid() -> void:
	var rows := ceili(float(items.inventory.size() - items.inventory.hotbar_size()) / COLUMNS) + 1
	_grid.custom_minimum_size = Vector2(COLUMNS * SLOT + (COLUMNS - 1) * GAP, rows * (SLOT + GAP) + 26.0)


## Opens it, the free items shown when the game mode hands them out.
func open() -> void:
	_picked = -1
	_hover = -1
	var free: bool = items.game.game_mode.free_items()
	_free.visible = free
	_free_title.visible = free
	_describe()
	visible = true
	UiStyle.centre(self)
	_grid.queue_redraw()


## The rectangle of slot `i` in the grid: the hotbar's row first, a gap, then the bag's rows.
func _slot_rect(i: int) -> Rect2:
	var hb: int = items.inventory.hotbar_size()
	var col := i if i < hb else (i - hb) % COLUMNS
	var line := 0 if i < hb else 1 + (i - hb) / COLUMNS
	return Rect2(col * (SLOT + GAP), line * (SLOT + GAP) + (26.0 if line > 0 else 0.0), SLOT, SLOT)


func _slot_at(p: Vector2) -> int:
	for i in items.inventory.size():
		if _slot_rect(i).has_point(p):
			return i
	return -1


func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _slot_at(event.position)
		if h != _hover:
			_hover = h
			_describe()
			_grid.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var i := _slot_at(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT or i < 0:
			_picked = -1
		elif _picked < 0:
			_picked = i if not items.inventory.slot(i).is_empty() else -1
		else:
			if i != _picked:
				items.move(_picked, i)
			_picked = -1
		_describe()
		_grid.queue_redraw()


func _draw_grid() -> void:
	var inv: RefCounted = items.inventory
	var font := get_theme_default_font()
	_grid.draw_string(font, Vector2(0, -6), "Hotbar", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT_DIM)
	var bag_top := _slot_rect(inv.hotbar_size()).position.y
	_grid.draw_string(font, Vector2(0, bag_top - 8.0), "Bag", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT_DIM)
	for i in inv.size():
		var r := _slot_rect(i)
		_grid.draw_rect(r, BG.lightened(0.08) if i == _hover else BG)
		var lit: bool = i == _picked or i == items.held
		_grid.draw_rect(r, LIT if i == _picked else (LIT.darkened(0.3) if lit else EDGE), false, 3.0 if lit else 1.5)
		var kind: String = inv.kind_at(i)
		if kind != "":
			Icons.draw(_grid, kind, r.grow(-SLOT * 0.12))
			if inv.count_at(i) > 1:
				_grid.draw_string(font, Vector2(r.position.x, r.end.y - 5.0), str(inv.count_at(i)),
						HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 5.0, 16, Color.WHITE)
		if i < inv.hotbar_size():
			_grid.draw_string(font, r.position + Vector2(4, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(1, 1, 1, 0.5))


## What the item under the mouse (or picked) is.
func _describe() -> void:
	var i := _picked if _picked >= 0 else _hover
	var kind: String = items.inventory.kind_at(i) if i >= 0 else ""
	if kind == "":
		_about.text = "%d / %d slots used." % [_used(), items.inventory.size()]
		return
	var text := "%s\n%s" % [ItemDb.item_name(kind), ItemDb.field(kind, "about", "")]
	if ItemDb.is_weapon(kind):
		var s: Dictionary = items.inventory.slot(i)
		text += "\n\nRange %d m · stuns %s s · reloads in %s s\nLoaded: %d · fires %s" % [
				int(ItemDb.field(kind, "range", 0)), str(ItemDb.field(kind, "stun", 0)), str(ItemDb.field(kind, "reload", 0)),
				int(s.get("loaded", 0)), ItemDb.item_name(str(ItemDb.field(kind, "ammo", ""))).to_lower() + "s"]
	elif items.inventory.count_at(i) > 1:
		text += "\n\n×%d (up to %d a slot)" % [items.inventory.count_at(i), ItemDb.stack(kind)]
	_about.text = text


func _used() -> int:
	var n := 0
	for s: Dictionary in items.inventory.slots:
		if not s.is_empty():
			n += 1
	return n
