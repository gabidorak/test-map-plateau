extends Control
## The hotbar on the screen (items.gd puts it on game.gd's HUD): the HOTBAR slots bottom right (their key, the item's
## icon, how many), the one in hand lit; over it the weapon in hand, its rounds loaded, the ammunition left and the
## reload's bar; and, below the crosshair, what E or G would do (people.gd prompt: pick someone up, put them down) or how
## long we are down. Drawn in one go, redrawn a few times a second (or when the inventory changes).

const ItemDb = preload("res://scripts/items/item_db.gd")
const Icons = preload("res://scripts/items/item_icons.gd")

const SLOT := 58.0                          # px at 1080 px high
const GAP := 6.0
const MARGIN := 18.0
const BG := Color(0.06, 0.07, 0.1, 0.7)
const EDGE := Color(1, 1, 1, 0.16)
const LIT := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.95, 0.95, 0.97)
const DIM := Color(0.7, 0.72, 0.78)

var items: Node                             # items.gd

var _t := 0.0
var _prompt := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_t -= delta
	var game: Node = items.game
	visible = not game.flying and game.hud.visible
	if not visible:
		return
	var p: String = items.people.prompt()
	if items.reload_t > 0.0 or p != _prompt or _t <= 0.0:
		_prompt = p
		_t = 0.2
		queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var k := view.y / 1080.0
	var font := get_theme_default_font()
	var inv: RefCounted = items.inventory
	var n: int = inv.hotbar_size()
	var slot := SLOT * k
	var gap := GAP * k
	var w := n * slot + (n - 1) * gap
	var x0 := view.x - MARGIN * k - w
	var y0 := view.y - MARGIN * k - slot
	var driving: bool = items.game.driving != null or items.game.riding != null
	var alpha := 0.45 if driving else 1.0
	for i in n:
		var r := Rect2(x0 + i * (slot + gap), y0, slot, slot)
		var lit: bool = i == items.held
		draw_rect(r, Color(BG, BG.a * alpha))
		draw_rect(r, Color(LIT, alpha) if lit else Color(EDGE, EDGE.a * alpha), false, (3.0 if lit else 1.5) * k)
		var kind: String = inv.kind_at(i)
		if kind != "":
			Icons.draw(self, kind, r.grow(-slot * 0.12))
			var count: int = inv.count_at(i)
			if count > 1:
				draw_string(font, Vector2(r.position.x, r.end.y - 5.0 * k), str(count), HORIZONTAL_ALIGNMENT_RIGHT,
						slot - 5.0 * k, int(16 * k), Color(TEXT, alpha))
		draw_string(font, Vector2(r.position.x + 4.0 * k, r.position.y + 15.0 * k), str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * k), Color(DIM, 0.8 * alpha))
	# the weapon in hand
	var kind: String = items.held_kind()
	if kind != "" and not driving:
		var line := ItemDb.item_name(kind)
		if ItemDb.is_weapon(kind):
			var r: Array = items.rounds()
			line += "   %d · %d %s" % [r[0], r[1], ItemDb.item_name(str(ItemDb.field(kind, "ammo", ""))).to_lower() + \
					("s" if r[1] != 1 else "")]
		var ly := y0 - 12.0 * k
		draw_string(font, Vector2(x0 - 200.0 * k, ly), line, HORIZONTAL_ALIGNMENT_RIGHT, w + 200.0 * k, int(19 * k), TEXT)
		if items.reload_t > 0.0 and items.reload_total > 0.0:
			var share := 1.0 - clampf(items.reload_t / items.reload_total, 0.0, 1.0)
			var bar := Rect2(x0, ly + 6.0 * k, w, 5.0 * k)
			draw_rect(bar, Color(1, 1, 1, 0.15))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), LIT)
	# what E or G would do, or how long we are down
	if _prompt != "":
		var py := view.y * 0.62
		draw_string(font, Vector2(0.0, py), _prompt, HORIZONTAL_ALIGNMENT_CENTER, view.x, int(22 * k),
				Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0.0, py - 2.0 * k), _prompt, HORIZONTAL_ALIGNMENT_CENTER, view.x, int(22 * k), TEXT)
