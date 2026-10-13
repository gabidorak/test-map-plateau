extends VBoxContainer
## LAN game chat (game.gd adds it to the HUD, bottom left above the help): the recent messages, and a line to type in
## while it is open (Enter opens it, Enter sends, Esc closes). Closed, new messages show for SHOW_FOR s, then fade.

const UiStyle = preload("res://scripts/ui_style.gd")

signal sent(text: String)                   # Enter on a non-empty line
signal closed                               # Enter or Esc: the line is gone

const MAX_LINES := 50
const SHOW_FOR := 10.0                      # s a message shows while the chat is closed
const MAX_LENGTH := 200                     # characters per message (net.gd cuts longer ones too)

var _log: RichTextLabel
var _log_panel: PanelContainer
var _line: LineEdit
var _lines := []                            # [name or "", colour, text], oldest first; "" name: a game message
var _shown_t := 0.0                         # s left showing the log while closed


func _ready() -> void:
	name = "Chat"
	custom_minimum_size.x = 480
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel = PanelContainer.new()
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_panel)
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(480, 180)
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 16)
	_log.add_theme_color_override("font_outline_color", Color.BLACK)
	_log.add_theme_constant_override("outline_size", 4)
	_log_panel.add_child(_log)
	_line = UiStyle.line_edit("", "Say something… (Enter send · Esc close)", 480)
	_line.max_length = MAX_LENGTH
	_line.visible = false
	_line.text_submitted.connect(_on_submitted)
	add_child(_line)
	_set_panel(false)
	_log_panel.modulate.a = 0.0


func _process(delta: float) -> void:
	if is_open():
		return
	_shown_t = maxf(_shown_t - delta, 0.0)
	_log_panel.modulate.a = clampf(_shown_t, 0.0, 1.0)


func is_open() -> bool:
	return _line.visible


## Shows the line to type in and the whole log.
func open() -> void:
	_line.text = ""
	_line.visible = true
	_set_panel(true)
	_log_panel.modulate.a = 1.0
	_line.grab_focus()


func close() -> void:
	if not is_open():
		return
	_line.release_focus()
	_line.visible = false
	_set_panel(false)
	_shown_t = 0.0
	closed.emit()


## A message from player `who` (shown in `color`), or a game message ("X joined the game") when `who` is "".
func add(who: String, color: Color, text: String) -> void:
	_lines.append([who, color, text])
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_redraw()
	_shown_t = SHOW_FOR
	if not is_open():
		_log_panel.modulate.a = 1.0


func _redraw() -> void:
	_log.clear()
	for i in _lines.size():
		var l: Array = _lines[i]
		if i > 0:
			_log.newline()
		if l[0] == "":
			_log.push_color(UiStyle.TEXT_DIM)
			_log.add_text(l[2])                 # add_text: no BBCode in what players type
			_log.pop()
		else:
			_log.push_color((l[1] as Color).lightened(0.3))
			_log.add_text(l[0] + ": ")
			_log.pop()
			_log.add_text(l[2])


func _on_submitted(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		sent.emit(text)
	close()


## A dark background behind the log while typing, none otherwise (the outlined text reads over the world).
func _set_panel(on: bool) -> void:
	_log_panel.add_theme_stylebox_override("panel", UiStyle.panel(0.6, 8, 8) if on else StyleBoxEmpty.new())
