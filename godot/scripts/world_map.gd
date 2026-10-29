extends Control
## The full-screen map (M; Esc or M closes it): the ground from above, north up (scripts/map_ground.gd), with the
## RER B and its stations, the schools and the lakes (world/map_labels.json, pipeline/plateau/map_labels.py), the bus
## stops (world/bus_routes.json, through the loading screen's map: scripts/loading_map.gd), the players and the
## waypoint. Drag to move, wheel to zoom about the pointer, click to put the waypoint (game.gd set_waypoint: a beam
## in the world, a marker on the screen), right click to take it away.
## Not to crowd it: the big schools, the lakes and the stations show at every zoom, the other schools and the ponds
## from SHOW_TIER1, the bus stops from SHOW_STOPS and their names from SHOW_STOP_NAMES; and a name that would overlap
## one already placed is left out (they are placed most important first).

const MapGround = preload("res://scripts/map_ground.gd")
const LoadingMap = preload("res://scripts/loading_map.gd")
const Minimap = preload("res://scripts/minimap.gd")
const LABELS := "res://world/map_labels.json"
const ZOOM_OPEN := 0.8                      # px per m when it opens
const ZOOM_MAX := 5.0
const ZOOM_STEP := 1.25                     # per wheel notch
const SHOW_TIER1 := 0.5                     # px per m
const SHOW_STOPS := 0.7
const SHOW_STOP_NAMES := 1.8
const DRAG_PX := 5.0                        # a press that moves less than this is a click
const INK := Color(0.04, 0.05, 0.08, 0.92)
const RER_B := Color("#5291ce")
const SCHOOL := Color("#f29f3a")
const SCHOOL_SMALL := Color("#f5c27a")
const WATER_TEXT := Color("#d6f1ff")
const WATER_INK := Color(0.05, 0.2, 0.35, 0.9)

var game: Node                              # game.gd
var _map_rect: ColorRect
var _marks: Control
var _mat: ShaderMaterial
var _centre := Vector2.ZERO                 # pipeline (x, y) under the middle of the screen
var _zoom := ZOOM_OPEN
var _labels: Array = []                     # [name, kind, tier, Vector2]
var _press := Vector2.INF                   # where the left button went down, while it is down
var _dragged := false
var _placed: Array[Rect2] = []              # the names drawn this frame, most important first


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = MapGround.BACKGROUND
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_map_rect = ColorRect.new()
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_rect.visible = false
	add_child(_map_rect)
	_marks = Control.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LABELS)) if FileAccess.file_exists(LABELS) \
			else null
	if data is Dictionary:
		for l: Dictionary in data.get("labels", []):
			_labels.append([str(l["name"]), str(l["kind"]), int(l["tier"]), Vector2(l["x"], l["y"])])


func _exit_tree() -> void:
	MapGround.wait()


## Shows it centred on the player.
func open() -> void:
	var eye: Vector3 = game.map_eye()
	_centre = Vector2(eye.x, -eye.z)
	_zoom = ZOOM_OPEN
	_press = Vector2.INF
	visible = true


func _process(_delta: float) -> void:
	if not visible:
		return
	if _mat == null and MapGround.ready():
		_mat = MapGround.material(false)
		_map_rect.material = _mat
		_map_rect.visible = true
	if _mat:
		_centre = _centre.clamp(MapGround.extent.position, MapGround.extent.end)
		MapGround.view(_mat, _centre, Vector2(0.0, 1.0), size * 0.5 / _zoom)   # north up (pipeline y)
	_marks.queue_redraw()                   # (the players move)


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b and b.button_index == MOUSE_BUTTON_LEFT:
		if b.pressed:
			_press = b.position
			_dragged = false
		elif _press != Vector2.INF:
			if not _dragged:
				game.set_waypoint(_to_world(b.position))
			_press = Vector2.INF
	elif b and b.pressed and b.button_index == MOUSE_BUTTON_RIGHT:
		game.set_waypoint(null)
	elif b and b.pressed and b.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var under := _to_world(b.position)
		var k := ZOOM_STEP if b.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
		_zoom = clampf(_zoom * k, _zoom_min(), ZOOM_MAX)
		_centre = under - Vector2(b.position.x - size.x * 0.5, size.y * 0.5 - b.position.y) / _zoom
	var m := event as InputEventMouseMotion
	if m and _press != Vector2.INF:
		_dragged = _dragged or m.position.distance_to(_press) > DRAG_PX
		if _dragged:
			_centre -= Vector2(m.relative.x, -m.relative.y) / _zoom
	accept_event()


## The whole map on the screen, all the way out.
func _zoom_min() -> float:
	var e: Rect2 = MapGround.extent
	if e.size.x <= 0.0:
		return 0.1
	return minf(size.x / e.size.x, size.y / e.size.y) * 0.95


func _to_px(xy: Vector2) -> Vector2:
	return size * 0.5 + Vector2(xy.x - _centre.x, _centre.y - xy.y) * _zoom


func _to_world(px: Vector2) -> Vector2:
	return _centre + Vector2(px.x - size.x * 0.5, size.y * 0.5 - px.y) / _zoom


## Whether a name in `r` fits (overlaps no name placed yet); places it if it does.
func _room(r: Rect2) -> bool:
	for p in _placed:
		if p.intersects(r):
			return false
	_placed.append(r)
	return true


func _draw_marks() -> void:
	var font := get_theme_default_font()
	var screen := Rect2(Vector2.ZERO, size).grow(40.0)
	var fit := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, -_zoom), size * 0.5 + Vector2(-_centre.x, _centre.y) * _zoom)
	_placed.clear()
	var map := LoadingMap.shared()
	# The RER B.
	for path: Dictionary in map.get("rail", []):
		_marks.draw_polyline(fit * (path["pts"] as PackedVector2Array), Color(RER_B, 0.35), 7.0, true)
		_marks.draw_polyline(fit * (path["pts"] as PackedVector2Array), RER_B, 3.0, true)
	# Most important first: what is placed first keeps its name. Drawn last (on top), so gathered in `ops`.
	var ops: Array = []                     # Callables, drawn in reverse
	var eye3: Vector3 = game.map_eye()
	var eye := _to_px(Vector2(eye3.x, -eye3.z))
	_placed.append(Rect2(eye - Vector2(12, 12), Vector2(24, 24)))
	if game.waypoint != null:
		var wp := _to_px(game.waypoint)
		var text := _distance_text((game.waypoint as Vector2).distance_to(Vector2(eye3.x, -eye3.z)))
		_placed.append(Rect2(wp - Vector2(12, 12), Vector2(24, 24)))
		ops.append(func() -> void:
			Minimap.draw_waypoint(_marks, wp, 10.0)
			_text(font, wp + Vector2(16, 6), text, 16, Minimap.WAYPOINT, INK))
		_room(Rect2(wp + Vector2(14, -12), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16) + Vector2(4, 6)))
	for st: Array in map.get("stations", []):
		var p := _to_px(st[1])
		if screen.has_point(p):
			_placed.append(Rect2(p - Vector2(10, 10), Vector2(20, 20)))
			ops.append(_station.bind(p))
			_label(ops, font, p + Vector2(13, 6), st[0], 16, Color.WHITE, INK)
	for tier in 2:
		if tier == 1 and _zoom < SHOW_TIER1:
			break
		for l: Array in _labels:
			if l[2] != tier:
				continue
			var p := _to_px(l[3])
			if not screen.has_point(p):
				continue
			if l[1] == "water":
				var w := font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15 - tier)
				_label(ops, font, p - Vector2(w.x * 0.5, -5.0), l[0], 15 - tier, WATER_TEXT, WATER_INK)
			else:
				var s := 1.0 if tier == 0 else 0.75
				_placed.append(Rect2(p - Vector2(9, 7) * s, Vector2(18, 14) * s))
				ops.append(_school.bind(p, s, SCHOOL if tier == 0 else SCHOOL_SMALL))
				_label(ops, font, p + Vector2(12 * s, 5), l[0], 15 if tier == 0 else 13, Color.WHITE, INK)
	if _zoom >= SHOW_STOPS:
		var named := _zoom >= SHOW_STOP_NAMES
		for stop: Array in map.get("stops", []):
			var p := _to_px(stop[1])
			if not screen.has_point(p):
				continue
			ops.append(func() -> void:
				_marks.draw_circle(p, 4.5, INK)
				_marks.draw_circle(p, 3.0, Color.WHITE))
			if named:
				_label(ops, font, p + Vector2(8, 5), stop[0], 12, Color(0.92, 0.94, 1.0), INK)
	ops.reverse()
	for op: Callable in ops:
		op.call()
	# The other players, then us on top of it all.
	var net: Node = game.net
	if net and net.active:
		for id: int in net.players:
			var avatar: Node3D = net.avatar(id)
			if avatar == null or not avatar.is_inside_tree():
				continue
			var p := _to_px(Vector2(avatar.global_position.x, -avatar.global_position.z))
			_marks.draw_circle(p, 7.0, INK)
			_marks.draw_circle(p, 5.0, net.players[id]["color"])
			_text(font, p + Vector2(10, 5), net.players[id]["name"], 14, Color.WHITE, INK)
	var cam := get_viewport().get_camera_3d()
	var f := -cam.global_basis.z if cam else Vector3.FORWARD
	Minimap.draw_player(_marks, eye, atan2(f.x, -f.z) if Vector2(f.x, f.z).length() > 0.05 else 0.0)
	_draw_scale(font)
	_draw_hint(font)


## A name at `at` (its baseline's left end), if it has room; drawn with the rest (`ops`).
func _label(ops: Array, font: Font, at: Vector2, text: String, fs: int, colour: Color, ink: Color) -> void:
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if _room(Rect2(at - Vector2(2, s.y * 0.8), s + Vector2(4, 2))):
		ops.append(_text.bind(font, at, text, fs, colour, ink))


func _text(font: Font, at: Vector2, text: String, fs: int, colour: Color, ink: Color) -> void:
	_marks.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, ink)
	_marks.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


## An RER B station: a blue disc with a white ring and a B.
func _station(p: Vector2) -> void:
	_marks.draw_circle(p, 10.0, INK)
	_marks.draw_circle(p, 8.5, RER_B)
	_marks.draw_circle(p, 8.5, Color.WHITE, false, 2.0, true)
	_marks.draw_string(get_theme_default_font(), p + Vector2(-4.5, 5.0), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color.WHITE)


## A school: a mortarboard, `s` its scale.
func _school(p: Vector2, s: float, colour: Color) -> void:
	var board := PackedVector2Array([p + Vector2(0, -6) * s, p + Vector2(10, -1) * s, p + Vector2(0, 4) * s,
			p + Vector2(-10, -1) * s])
	var cap := PackedVector2Array([p + Vector2(-5.5, 1) * s, p + Vector2(5.5, 1) * s, p + Vector2(5.5, 7) * s,
			p + Vector2(-5.5, 7) * s])
	for poly: PackedVector2Array in [cap, board]:
		var ring := poly.duplicate()
		ring.append(poly[0])
		_marks.draw_polyline(ring, INK, 3.5, true)
		_marks.draw_colored_polygon(poly, colour)
	_marks.draw_line(p + Vector2(8, -1) * s, p + Vector2(8, 6) * s, INK, 1.5, true)


## A scale bar, bottom left: a round length 60 to 160 px long.
func _draw_scale(font: Font) -> void:
	var metres := 50.0
	for m: float in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		metres = m
		if m * _zoom >= 60.0:
			break
	var a := Vector2(24, size.y - 28)
	var b := a + Vector2(metres * _zoom, 0)
	for k in 2:
		var c := INK if k == 0 else Color.WHITE
		var w := 5.0 if k == 0 else 2.0
		_marks.draw_line(a, b, c, w)
		_marks.draw_line(a, a + Vector2(0, -7), c, w)
		_marks.draw_line(b, b + Vector2(0, -7), c, w)
	_text(font, a + Vector2(0, -12), _distance_text(metres), 14, Color.WHITE, INK)


func _draw_hint(font: Font) -> void:
	var text := "drag: move · wheel: zoom · click: set a waypoint · right click: remove it · %s / Esc: close" % \
			game.letter_key("world_map", "M")
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var at := Vector2((size.x - s.x) * 0.5, size.y - 20.0)
	_marks.draw_rect(Rect2(at - Vector2(12, s.y), s + Vector2(24, 12)), Color(INK, 0.75))
	_text(font, at, text, 15, Color.WHITE, INK)


static func _distance_text(m: float) -> String:
	return "%d m" % roundi(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)
