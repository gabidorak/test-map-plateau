extends CanvasLayer
## In-game menu (Esc, game.gd): Resume, Back to main menu (leaves the LAN game, or closes it for everyone when
## hosting), Quit. In a LAN game it also shows how to join and who is playing. The world keeps going behind it.

const UiStyle = preload("res://scripts/ui_style.gd")

signal resume
signal leave
signal quit

var _info: Label
var _players: HFlowContainer
var _leave: Button
var _resume: Button


func _ready() -> void:
	layer = 4
	visible = false
	var looks := UiStyle.button_looks()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(0.9, 12, 24))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 460
	panel.add_child(box)
	box.add_child(UiStyle.label("Menu", 32))
	_info = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_players = HFlowContainer.new()
	_players.alignment = FlowContainer.ALIGNMENT_CENTER
	_players.add_theme_constant_override("h_separation", 16)
	box.add_child(_players)
	_resume = UiStyle.button("Resume", looks, Vector2(320, 46), 19)
	_resume.pressed.connect(func() -> void: resume.emit())
	_leave = UiStyle.button("Back to main menu", looks, Vector2(320, 46), 19)
	_leave.pressed.connect(func() -> void: leave.emit())
	var q := UiStyle.button("Quit game", looks, Vector2(320, 40), 17)
	q.pressed.connect(func() -> void: quit.emit())
	for b in [_resume, _leave, q]:
		var c := CenterContainer.new()
		c.add_child(b)
		box.add_child(c)
	box.add_child(UiStyle.label("Esc resume", 14, UiStyle.TEXT_DIM))
	UiStyle.centre(panel)


## Shows the menu: `info` says what game this is, `players` lists [nickname, colour] (empty when solo),
## `leave_text` names what Back to main menu does.
func open(info: String, players: Array, leave_text: String) -> void:
	_info.text = info
	_info.visible = info != ""
	for c in _players.get_children():
		c.free()
	for p: Array in players:
		_players.add_child(UiStyle.label("● " + p[0], 17, (p[1] as Color).lightened(0.3)))
	_players.visible = not players.is_empty()
	_leave.text = leave_text
	visible = true
	_resume.grab_focus()


func close() -> void:
	visible = false
	var focus := _resume.get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()
