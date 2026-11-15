extends RefCounted
## The items' icons, drawn (no picture to ship, sharp at any size): the glyph data/items.json names (`icon`) in the
## item's colour, in a square. The hotbar (hotbar_hud.gd) and the inventory panel (inventory_panel.gd) draw them.

const ItemDb = preload("res://scripts/items/item_db.gd")

const DARK := Color(0.1, 0.1, 0.12)
const OLIVE := Color(0.33, 0.4, 0.27)


## Item `kind`'s icon in `r` on `ci`.
static func draw(ci: CanvasItem, kind: String, r: Rect2) -> void:
	var c := ItemDb.color(kind)
	var u := r.size.x / 10.0                # the glyphs are drawn on a 10 x 10 grid
	var o := r.position
	match str(ItemDb.field(kind, "icon", "")):
		"taser":
			_poly(ci, o, u, [Vector2(1.2, 3.2), Vector2(8.8, 3.2), Vector2(8.8, 5.6), Vector2(1.2, 5.6)], c)
			_poly(ci, o, u, [Vector2(7.6, 3.0), Vector2(9.2, 3.0), Vector2(9.2, 5.8), Vector2(7.6, 5.8)], DARK)
			_poly(ci, o, u, [Vector2(2.0, 5.6), Vector2(4.0, 5.6), Vector2(3.3, 8.6), Vector2(1.3, 8.6)], DARK)
			ci.draw_circle(o + Vector2(9.2, 4.0) * u, 0.35 * u, Color(0.45, 0.7, 1.0))
		"net_gun":
			_poly(ci, o, u, [Vector2(0.4, 3.8), Vector2(7.4, 3.8), Vector2(7.4, 5.0), Vector2(0.4, 5.0)], DARK)
			_poly(ci, o, u, [Vector2(7.2, 3.2), Vector2(9.6, 3.2), Vector2(9.6, 5.6), Vector2(7.2, 5.6)], c)
			_poly(ci, o, u, [Vector2(4.2, 4.9), Vector2(6.6, 4.9), Vector2(6.6, 5.9), Vector2(4.2, 5.9)], OLIVE)
			_poly(ci, o, u, [Vector2(0.2, 4.4), Vector2(2.4, 4.4), Vector2(2.4, 6.6), Vector2(0.2, 7.2)], OLIVE)
			_poly(ci, o, u, [Vector2(2.6, 5.0), Vector2(3.6, 5.0), Vector2(3.2, 7.0), Vector2(2.2, 7.0)], DARK)
		"cartridge":
			_poly(ci, o, u, [Vector2(2.6, 2.6), Vector2(7.4, 2.6), Vector2(7.4, 7.4), Vector2(2.6, 7.4)], c)
			_poly(ci, o, u, [Vector2(2.6, 2.6), Vector2(7.4, 2.6), Vector2(7.4, 4.0), Vector2(2.6, 4.0)], DARK)
			ci.draw_circle(o + Vector2(4.0, 5.6) * u, 0.55 * u, DARK)
			ci.draw_circle(o + Vector2(6.0, 5.6) * u, 0.55 * u, DARK)
		"net_shell":
			_poly(ci, o, u, [Vector2(3.0, 1.8), Vector2(7.0, 1.8), Vector2(7.0, 8.2), Vector2(3.0, 8.2)], c)
			_poly(ci, o, u, [Vector2(3.0, 7.0), Vector2(7.0, 7.0), Vector2(7.0, 8.2), Vector2(3.0, 8.2)], Color(0.75, 0.6, 0.25))
			for k in 4:
				ci.draw_line(o + Vector2(3.0, 2.6 + k * 1.1) * u, o + Vector2(7.0, 3.5 + k * 1.1) * u, Color(DARK, 0.6), maxf(u * 0.18, 1.0))
		_:
			ci.draw_circle(r.get_center(), r.size.x * 0.32, c)
			var font := ThemeDB.fallback_font
			var letter := ItemDb.item_name(kind).left(1).to_upper()
			ci.draw_string(font, Vector2(r.position.x, r.get_center().y + r.size.y * 0.13), letter,
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.y * 0.38), DARK)


static func _poly(ci: CanvasItem, o: Vector2, u: float, pts: Array, c: Color) -> void:
	var p := PackedVector2Array()
	for v: Vector2 in pts:
		p.append(o + v * u)
	ci.draw_colored_polygon(p, c)
