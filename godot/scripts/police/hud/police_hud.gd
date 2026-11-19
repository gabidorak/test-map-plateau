extends Control
## The wanted level on the screen (police.gd puts it on game.gd's HUD, PTA Online): MAX_STARS stars top right, under
## the wallet, the first `level` lit; shown only while the player is wanted. While the police do not see them (the
## time to lose them runs), the lit stars blink. Drawn when the level changes, every frame only while blinking.

const MAX_STARS := 5
const SIZE := 26.0                          # px, a star's width
const GAP := 4.0
const MARGIN := 14.0                        # px from the right edge (the wallet's)
const TOP := 50.0                           # px from the top, under the wallet
const LIT := Color(1.0, 0.86, 0.3)
const DARK := Color(1.0, 1.0, 1.0, 0.18)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.75)

var police: Node                            # police.gd


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if police.level > 0 and not police.seen:
		queue_redraw()                      # (blinking)


func _draw() -> void:
	var n: int = police.level
	if n <= 0:
		return
	var blink := 1.0
	if not police.seen:
		blink = 0.35 + 0.65 * (0.5 + 0.5 * cos(Time.get_ticks_msec() / 1000.0 * TAU * 1.5))
	var right := get_viewport_rect().size.x - MARGIN
	for k in MAX_STARS:
		var centre := Vector2(right - SIZE * 0.5 - (MAX_STARS - 1 - k) * (SIZE + GAP), TOP + SIZE * 0.5)
		var lit := k < n
		var pts := _star(centre, SIZE * 0.5)
		var outline := _star(centre, SIZE * 0.5 + 2.0)
		draw_colored_polygon(outline, Color(OUTLINE, OUTLINE.a * (blink if lit else 1.0)))
		draw_colored_polygon(pts, Color(LIT, blink) if lit else DARK)


## A five-pointed star of outer radius `r` round `c`, a point up.
static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		out.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return out
