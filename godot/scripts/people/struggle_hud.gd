extends Control
## Struggling free of whoever carries us (scripts/people/people.gd puts it on game.gd's HUD while we are carried, once
## the stun is over): the host's arrow keys, one at a time. Only the key to press now shows; the next one pops in once
## it is pressed right (no reading ahead, harder than a carjacking's). A bar runs down the time given for them all; a
## wrong key, or the time out, and it is over (`finished`); the host then answers (show_result) and, failed, sends
## another go a moment later.
## While it waits for keys it takes the keys (not the mouse: the player still looks around), not Esc (the menu).

const Hud = preload("res://scripts/carjack/carjack_hud.gd")

signal finished(typed: Array)               # the keys pressed (indices into Hud.ARROWS), a wrong one last

const POP := 0.12                           # s a key takes to pop in
const END_SHOW := 1.0                       # s the outcome stays up
const BOX := 74.0                           # px, the key's box at 1080 px high
const DOT := 16.0                           # px, the progress dots
const PANEL := Color(0.06, 0.07, 0.1, 0.88)

var sequence: Array = []
var time_limit := 4.0
var typed: Array = []
var state := ""                             # "input", "wait" (for the host's word), "done", "" (hidden)

var _t := 0.0                               # s in the state
var _pop := 0.0                             # s since the key shown came up
var _ok := false
var _wrong := false
var _shake := 0.0
var _line := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func start(seq: Array, limit: float) -> void:
	sequence = seq
	time_limit = limit
	typed = []
	_wrong = false
	_shake = 0.0
	_line = ""
	_pop = 0.0
	state = "input"
	_t = 0.0
	visible = true
	queue_redraw()


func taking_keys() -> bool:
	return state in ["input", "wait"]


## The host's word: free (`ok`) or not, `text` under it.
func show_result(ok: bool, text: String) -> void:
	_ok = ok
	_line = text
	if not ok:
		_shake = 1.0
	state = "done"
	_t = 0.0
	queue_redraw()


func hide_now() -> void:
	state = ""
	visible = false


func _process(delta: float) -> void:
	if state == "":
		return
	_t += delta
	_pop += delta
	_shake = maxf(_shake - delta * 2.5, 0.0)
	if state == "input" and _t >= time_limit:
		_finish()
	elif state == "done" and _t >= END_SHOW:
		hide_now()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not taking_keys() or not event is InputEventKey:
		return
	var e := event as InputEventKey
	var code := e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	if code == KEY_ESCAPE:
		return                              # (the in-game menu)
	get_viewport().set_input_as_handled()
	if not e.pressed or e.echo or state != "input":
		return
	var k := Hud.ARROWS.find(code)
	if k < 0:
		return
	typed.append(k)
	if k != sequence[typed.size() - 1]:
		_wrong = true
		_shake = 1.0
		_finish()
		return
	_pop = 0.0
	if typed.size() == sequence.size():
		_finish()


func _finish() -> void:
	state = "wait"
	_t = 0.0
	finished.emit(typed.duplicate())


func _draw() -> void:
	if state == "":
		return
	var view := get_viewport_rect().size
	var k := view.y / 1080.0
	var font := get_theme_default_font()
	var w := 460.0 * k
	var h := 230.0 * k
	var top := view.y * 0.6
	var left := (view.x - w) * 0.5
	var fade := 1.0 - clampf((_t - END_SHOW + 0.3) / 0.3, 0.0, 1.0) if state == "done" else 1.0
	var shake := sin(_t * 70.0) * 10.0 * k * _shake
	draw_rect(Rect2(left, top, w, h), Color(PANEL, PANEL.a * fade))
	var title := "Struggle free: press each arrow as it shows" if state != "done" \
			else ("Free!" if _ok else "Still held…")
	var colour := Hud.TEXT if state != "done" else (Hud.GOOD if _ok else Hud.BAD)
	draw_string(font, Vector2(left, top + 38.0 * k), title, HORIZONTAL_ALIGNMENT_CENTER, w, int(26 * k), Color(colour, fade))
	# the key to press now (the last pressed, once over)
	var n := sequence.size()
	var at := mini(typed.size(), n - 1) if state == "input" else maxi(typed.size() - 1, 0)
	var centre := Vector2(view.x * 0.5 + shake, top + 100.0 * k)
	var s := Hud.back_out(clampf(_pop / POP, 0.0, 1.0)) if state == "input" else 1.0
	var half := BOX * 0.5 * k * s
	var box_colour := Hud.KEY_BG
	if state != "input":
		box_colour = Hud.GOOD if _ok else (Hud.BAD if _wrong or not _ok else Hud.KEY_BG)
	var rect := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_rect(rect, Color(box_colour, fade))
	draw_rect(rect, Color(Hud.CURRENT if state == "input" else Hud.KEY_EDGE, fade), false, 3.0 * k)
	if n > 0 and (state == "input" or not typed.is_empty()):
		Hud.draw_arrow(self, centre, half * 0.62, int(typed[at]) if state != "input" else int(sequence[at]),
				Color(Hud.TEXT, fade))
	# how far: a dot per key, the ones done green
	var dots := n * DOT * k + (n - 1) * 6.0 * k
	var x0 := (view.x - dots) * 0.5
	var y0 := top + 150.0 * k
	for i in n:
		var c := Hud.GOOD if i < typed.size() and not (_wrong and i == typed.size() - 1) else Color(1, 1, 1, 0.18)
		if _wrong and i == typed.size() - 1:
			c = Hud.BAD
		draw_rect(Rect2(x0 + i * (DOT + 6.0) * k, y0, DOT * k, DOT * k), Color(c, c.a * fade))
	var bar_y := y0 + 28.0 * k
	if state == "input":
		var share := clampf(1.0 - _t / time_limit, 0.0, 1.0)
		draw_rect(Rect2(x0, bar_y, dots, 7.0 * k), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(x0, bar_y, dots * share, 7.0 * k), Hud.GOOD.lerp(Hud.BAD, 1.0 - share))
	elif _line != "":
		draw_string(font, Vector2(left, bar_y + 16.0 * k), _line, HORIZONTAL_ALIGNMENT_CENTER, w, int(20 * k),
				Color(Hud.TEXT, fade))
