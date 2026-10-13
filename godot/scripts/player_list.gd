extends PanelContainer
## LAN games: who is playing and their ping to the host, shown at the top of the screen while Tab is held (game.gd).

const UiStyle = preload("res://scripts/ui_style.gd")

var _title: Label
var _grid: GridContainer


func _ready() -> void:
	name = "PlayerList"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiStyle.panel(0.85))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 360
	add_child(box)
	_title = UiStyle.label("Players", 22)
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 32)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)


## `rows`: [nickname, colour, ping in ms (-1 unknown), us]; `title` above them.
func show_players(title: String, rows: Array) -> void:
	_title.text = title
	for c in _grid.get_children():
		c.free()
	_grid.add_child(UiStyle.label("Player", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	_grid.add_child(UiStyle.label("Ping", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	for r: Array in rows:
		var who := UiStyle.label("● " + r[0] + (" (you)" if r[3] else ""), 18, (r[1] as Color).lightened(0.3),
				HORIZONTAL_ALIGNMENT_LEFT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(who)
		var ping: int = r[2]
		_grid.add_child(UiStyle.label("%d ms" % ping if ping >= 0 else "…", 18, Color.WHITE if ping < 150 \
				else UiStyle.TEXT_WARN, HORIZONTAL_ALIGNMENT_RIGHT))
