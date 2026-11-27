extends Control
## PTA Online: our lent work vehicle wrecked (a bus, a fire truck, a tow truck: online_mode.gd _c_wreck). A bar fills
## while it waits to be towed back (the host's tow time, online_mode.gd TOW: 15 s), then a lift back to the garage it was
## lent from is offered for OFFER s: the interact key (E) takes it, Esc says no. online_mode.gd takes those keys
## (handle_input, close_ui) and puts the player there (to_garage_id); this only draws.

const OFFER := 30.0                         # s the lift is offered once the bar is full
const PANEL := Color(0.06, 0.07, 0.1, 0.88)
const TEXT := Color(0.95, 0.95, 0.95)
const DIM := Color(1, 1, 1, 0.6)
const WAIT := Color(0.95, 0.55, 0.15)
const READY := Color(0.45, 0.85, 0.45)

var state := ""                             # "wait" (the bar fills), "offer" (the lift), "" (hidden)
var garage_id := ""                         # the garage the vehicle was lent from
var title := ""                             # "Your lent bus is wrecked"
var place := ""                             # the garage's name
var key := "E"                              # the interact key's name
var wait_time := 15.0

var _t := 0.0                               # s in the state


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## The bar for `wait` s, then the lift to garage `gid` (named `where`) offered with key `key_text`.
func start(gid: String, what: String, where: String, wait: float, key_text: String) -> void:
	garage_id = gid
	title = what
	place = where
	key = key_text
	wait_time = maxf(wait, 0.0)
	state = "wait" if wait_time > 0.0 else "offer"
	_t = 0.0
	visible = true
	queue_redraw()


func offering() -> bool:
	return state == "offer"


## How far the bar is (0..1).
func progress() -> float:
	return 1.0 if state == "offer" else clampf(_t / wait_time, 0.0, 1.0) if wait_time > 0.0 else 1.0


func hide_now() -> void:
	state = ""
	visible = false


func _process(delta: float) -> void:
	if state == "":
		return
	_t += delta
	if state == "wait" and _t >= wait_time:
		state = "offer"
		_t = 0.0
	elif state == "offer" and _t >= OFFER:
		hide_now()
		return
	queue_redraw()


func _draw() -> void:
	if state == "":
		return
	var view := get_viewport_rect().size
	var k := view.y / 1080.0
	var font := get_theme_default_font()
	var w := 560.0 * k
	var h := 132.0 * k
	var top := view.y * 0.6
	var left := (view.x - w) * 0.5
	draw_rect(Rect2(left, top, w, h), PANEL)
	draw_string(font, Vector2(left, top + 36.0 * k), title, HORIZONTAL_ALIGNMENT_CENTER, w, int(25 * k), TEXT)
	var bar := Rect2(left + 40.0 * k, top + 56.0 * k, w - 80.0 * k, 16.0 * k)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress(), bar.size.y)), READY if state == "offer" else WAIT)
	var line := "Being towed away… %d s" % ceili(wait_time - _t) if state == "wait" \
			else "%s  Back to %s   ·   Esc  stay here (%d s)" % [key, place, ceili(OFFER - _t)]
	draw_string(font, Vector2(left, top + 108.0 * k), line, HORIZONTAL_ALIGNMENT_CENTER, w, int(21 * k),
			TEXT if state == "offer" else DIM)
