extends Control
## The keys of a carjacking (scripts/carjack/carjack.gd puts it on game.gd's HUD while the player tries a car): the arrow
## keys to press in order pop in one by one (REVEAL s apart), then a bar runs down the time given. A right key turns
## green and bounces; a wrong one turns red and shakes the row: it is over (`finished`). Esc gives up. The host's word
## then shows (show_result: green or red, a line under it) for END_SHOW s.
## While it waits for keys (taking_keys) it takes every key first (game.gd ui_open: the player stands still). The arrows
## are drawn, not typed: the same on any keyboard, the arrow keys being where they are on all of them.

signal finished(typed: Array, gave_up: bool)    # the keys pressed (indices into ARROWS), a wrong one last

const ARROWS := [KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_LEFT]
const REVEAL := 0.12                        # s between two keys popping in
const POP := 0.18                           # s a key takes to pop in
const END_SHOW := 1.1                       # s the outcome stays up
const BOX := 66.0                           # px, a key's box at 1080 px high (scaled with the window)
const GAP := 14.0
const PANEL := Color(0.06, 0.07, 0.1, 0.88)
const KEY_BG := Color(0.16, 0.18, 0.23)
const KEY_EDGE := Color(1.0, 1.0, 1.0, 0.25)
const CURRENT := Color(1.0, 0.82, 0.3)
const GOOD := Color(0.35, 0.85, 0.45)
const BAD := Color(0.95, 0.3, 0.28)
const TEXT := Color(0.95, 0.95, 0.97)

var sequence: Array = []                    # indices into ARROWS
var time_limit := 2.5                       # s, from the end of the reveal (carjack.gd TIME, sent by the host)
var typed: Array = []
var state := ""                             # "reveal", "input", "wait" (for the host's word), "done", "" (hidden)

var _t := 0.0                               # s in the state
var _hit_t: Array = []                      # per key: s since it was pressed right (bounce), -1 not yet
var _wrong := -1                            # the key pressed wrong (index into the row), -1 none
var _shake := 0.0
var _ok := false
var _line := ""                             # under the row, once over


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Shows `seq` (indices into ARROWS) to be pressed within `limit` s once all have popped in.
func start(seq: Array, limit: float) -> void:
	sequence = seq
	time_limit = limit
	typed = []
	_hit_t = []
	_hit_t.resize(seq.size())
	_hit_t.fill(-1.0)
	_wrong = -1
	_shake = 0.0
	_line = ""
	state = "reveal"
	_t = 0.0
	visible = true
	queue_redraw()


## Waiting for keys (or for the host's word on them): the keys are ours, the player stands still.
func taking_keys() -> bool:
	return state in ["reveal", "input", "wait"]


## The host's word: stolen (`ok`) or not, `text` under the row.
func show_result(ok: bool, text: String) -> void:
	_ok = ok
	_line = text
	if not ok and _wrong < 0:
		_shake = 1.0
	state = "done"
	_t = 0.0
	queue_redraw()


## Seconds left to press the keys (the whole time while they pop in).
func time_left() -> float:
	return time_limit - (_t if state == "input" else 0.0)


func _process(delta: float) -> void:
	if state == "":
		return
	_t += delta
	_shake = maxf(_shake - delta * 2.5, 0.0)
	for k in _hit_t.size():
		if _hit_t[k] >= 0.0:
			_hit_t[k] += delta
	if state == "reveal" and _t >= REVEAL * sequence.size() + POP:
		state = "input"
		_t = 0.0
	elif state == "input" and _t >= time_limit:
		_finish(false)                      # too slow
	elif state == "done" and _t >= END_SHOW:
		state = ""
		visible = false
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not taking_keys() or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	var e := event as InputEventKey
	if not e.pressed or e.echo or state == "wait":
		return
	var code := e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	if code == KEY_ESCAPE:
		_finish(true)
		return
	var k := ARROWS.find(code)
	if k < 0 or state != "input":
		return                              # (only the arrows count, once they are all shown)
	var at := typed.size()
	typed.append(k)
	if k != sequence[at]:
		_wrong = at
		_shake = 1.0
		_finish(false)
		return
	_hit_t[at] = 0.0
	if typed.size() == sequence.size():
		_finish(false)


func _finish(gave_up: bool) -> void:
	state = "wait"
	_t = 0.0
	finished.emit([] if gave_up else typed.duplicate(), gave_up)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if state == "":
		return
	var view := get_viewport_rect().size
	var k := view.y / 1080.0
	var n := sequence.size()
	var box := BOX * k
	var gap := GAP * k
	var row := n * box + (n - 1) * gap
	var font := get_theme_default_font()
	var size_title := int(30 * k)
	var size_line := int(24 * k)
	var w := maxf(row, 420.0 * k) + 60.0 * k
	var h := box + 150.0 * k
	var top := view.y * 0.62
	var left := (view.x - w) * 0.5
	var shake := sin(_t * 70.0) * 10.0 * k * _shake
	var fade := 1.0 - clampf((_t - END_SHOW + 0.3) / 0.3, 0.0, 1.0) if state == "done" else 1.0
	draw_rect(Rect2(left, top, w, h), Color(PANEL, PANEL.a * fade))
	var title := "Breaking in: press the keys in order" if state != "done" else ("Got it!" if _ok else "Failed")
	var title_colour := TEXT if state != "done" else (GOOD if _ok else BAD)
	draw_string(font, Vector2(left, top + 40.0 * k), title, HORIZONTAL_ALIGNMENT_CENTER, w, size_title,
			Color(title_colour, fade))
	var x0 := (view.x - row) * 0.5 + shake
	var y0 := top + 60.0 * k
	for i in n:
		var pop := clampf((_t - i * REVEAL) / POP, 0.0, 1.0) if state == "reveal" else 1.0
		if pop <= 0.0:
			continue
		var s := back_out(pop)
		var bounce := 0.0
		if _hit_t[i] >= 0.0 and _hit_t[i] < 0.25:
			bounce = sin(_hit_t[i] / 0.25 * PI) * 0.15
		var centre := Vector2(x0 + i * (box + gap) + box * 0.5, y0 + box * 0.5)
		var half := box * 0.5 * (s + bounce)
		var colour := KEY_BG
		var arrow := TEXT
		if i == _wrong:
			colour = BAD
		elif _hit_t[i] >= 0.0:
			colour = GOOD
		elif state == "done" and _ok:
			colour = GOOD
		var edge := CURRENT if state == "input" and i == typed.size() else KEY_EDGE
		var rect := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, Color(colour, fade))
		draw_rect(rect, Color(edge, fade * edge.a), false, 3.0 * k)
		draw_arrow(self, centre, half * 0.62, int(sequence[i]), Color(arrow, fade))
	# the time left
	var bar_y := y0 + box + 18.0 * k
	var share := clampf(time_left() / time_limit, 0.0, 1.0) if state in ["reveal", "input"] else 0.0
	if state in ["reveal", "input"]:
		draw_rect(Rect2((view.x - row) * 0.5, bar_y, row, 8.0 * k), Color(1, 1, 1, 0.15))
		draw_rect(Rect2((view.x - row) * 0.5, bar_y, row * share, 8.0 * k), GOOD.lerp(BAD, 1.0 - share))
	elif _line != "":
		draw_string(font, Vector2(left, bar_y + 20.0 * k), _line, HORIZONTAL_ALIGNMENT_CENTER, w, size_line,
				Color(TEXT, fade))
	if state in ["reveal", "input"]:
		draw_string(font, Vector2(left, bar_y + 46.0 * k), "Esc: give up", HORIZONTAL_ALIGNMENT_CENTER, w,
				int(18 * k), Color(1, 1, 1, 0.5))


## An arrow `r` px from its middle to its tip, pointing like ARROWS[`k`] (0 up, then clockwise), drawn on `ci` (also
## scripts/people/struggle_hud.gd's).
static func draw_arrow(ci: CanvasItem, centre: Vector2, r: float, k: int, colour: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -1), Vector2(0.75, -0.1), Vector2(0.28, -0.1), Vector2(0.28, 0.9),
			Vector2(-0.28, 0.9), Vector2(-0.28, -0.1), Vector2(-0.75, -0.1)])
	var turn := k * PI * 0.5
	for i in pts.size():
		pts[i] = centre + pts[i].rotated(turn) * r
	ci.draw_colored_polygon(pts, colour)


## 0..1 overshooting a little before it settles (a pop).
static func back_out(x: float) -> float:
	var c := 1.70158
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)
