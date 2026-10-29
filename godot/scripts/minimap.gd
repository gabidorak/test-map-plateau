extends Control
## The HUD's minimap (top left, K on / off): a round map of the ground around the player (scripts/map_ground.gd),
## seen from above and turned with the view (straight ahead is up, a red N on the rim points north), the player an
## arrow in the middle, the other players dots of their colour and the waypoint a gold diamond (both held on the rim
## when out of reach), and the places of game.gd map_places (Prestige Motors, PTA Online's garages) as small badges
## when in reach. It zooms out with speed.

const MapGround = preload("res://scripts/map_ground.gd")
const SIZE := 210.0                         # px across
const MARGIN := 12.0
const ZOOM_SLOW := 1.3                      # px per m on foot...
const ZOOM_FAST := 0.35                     # ...and from FAST on (cars, the plane)
const FAST := 45.0                          # m/s
const WAYPOINT := Color(1.0, 0.8, 0.25)
const INK := Color(0.05, 0.05, 0.07, 0.92)
## The places' badges (game.gd map_places), by kind: their colour and glyph.
const PLACES := {
	"garage": {"colour": Color("#2f6fd6"), "glyph": "P"},
	"depot": {"colour": Color("#2e9d57"), "glyph": "bus"},
	"fire": {"colour": Color("#d23b2f"), "glyph": "flame"},
	"shop": {"colour": Color("#c9a043"), "glyph": "€"},
	"stunt": {"colour": Color("#e0662a"), "glyph": "ramp"},
}

var game: Node                              # game.gd
var _map_rect: ColorRect
var _marks: Control
var _mat: ShaderMaterial
var _zoom := ZOOM_SLOW
var _last := Vector3.INF                    # the eye's last position, for its speed
var _speed := 0.0
var _forward := Vector2.UP                  # the view's heading (pipeline x east, y north)
var _eye := Vector2.ZERO                    # pipeline (x, y) under the middle
var _places: Array = []                     # game.map_places(), read again every PLACES_EVERY s
var _places_t := 0.0
const PLACES_EVERY := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, MARGIN)
	_map_rect = ColorRect.new()
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_rect.visible = false               # until its textures are made
	add_child(_map_rect)
	_marks = Control.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


func _exit_tree() -> void:
	MapGround.wait()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or game == null or game.mode == "":
		return
	if _mat == null:
		if not MapGround.ready():
			return
		_mat = MapGround.material(true)
		_map_rect.material = _mat
		_map_rect.visible = true
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = game.map_eye()
	if _last != Vector3.INF and delta > 0.0:
		var v := Vector2(eye.x - _last.x, eye.z - _last.z).length() / delta
		_speed = lerpf(_speed, minf(v, 200.0), 1.0 - exp(-delta * 2.0))
	_last = eye
	var want := lerpf(ZOOM_SLOW, ZOOM_FAST, clampf(_speed / FAST, 0.0, 1.0))
	_zoom = lerpf(_zoom, want, 1.0 - exp(-delta * 1.5))
	var f3 := -cam.global_basis.z
	var f := Vector2(f3.x, -f3.z)           # pipeline x east, y north
	if f.length() > 0.05:                   # (looking straight down: keep the last heading)
		_forward = f.normalized()
	_eye = Vector2(eye.x, -eye.z)
	_places_t -= delta
	if _places_t <= 0.0:
		_places_t = PLACES_EVERY
		_places = game.map_places()
	var half := SIZE * 0.5 / _zoom
	MapGround.view(_mat, _eye, _forward, Vector2(half, half))
	_marks.queue_redraw()


## Pipeline (x, y) to pixels in this Control.
func _to_px(xy: Vector2) -> Vector2:
	var d := (xy - _eye) * _zoom
	var right := Vector2(_forward.y, -_forward.x)
	return size * 0.5 + Vector2(d.dot(right), -d.dot(_forward))


## `xy` in pixels, held `inset` px inside the rim when it is further.
func _on_disc(xy: Vector2, inset: float) -> Vector2:
	var mid := size * 0.5
	var d := _to_px(xy) - mid
	var reach := SIZE * 0.5 - inset
	return mid + (d.normalized() * reach if d.length() > reach else d)


func _draw_marks() -> void:
	if _mat == null:
		return
	var mid := size * 0.5
	var radius := SIZE * 0.5
	_marks.draw_arc(mid, radius - 1.0, 0.0, TAU, 64, INK, 3.0, true)
	_marks.draw_arc(mid, radius - 1.0, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 1.2, true)
	# The places in reach.
	var font := get_theme_default_font()
	for place: Array in _places:
		var p := _to_px(place[2])
		if p.distance_to(mid) < radius - 10.0:
			draw_place(_marks, font, p, place[1], 6.5)
	# The other players (LAN games): dots.
	var net: Node = game.net
	if net and net.active:
		for id: int in net.players:
			var avatar: Node3D = net.avatar(id)
			if avatar == null or not avatar.is_inside_tree():
				continue
			var p := _on_disc(Vector2(avatar.global_position.x, -avatar.global_position.z), 8.0)
			_marks.draw_circle(p, 5.5, INK)
			_marks.draw_circle(p, 4.0, net.players[id]["color"])
	if game.waypoint != null:
		draw_waypoint(_marks, _on_disc(game.waypoint, 9.0), 7.0)
	# North on the rim.
	var north := mid + (_to_px(_eye + Vector2(0.0, 1.0)) - mid).normalized() * (radius - 1.0)
	_marks.draw_circle(north, 9.0, INK)
	_marks.draw_string(get_theme_default_font(), north + Vector2(-5.0, 5.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(1.0, 0.4, 0.35))
	draw_player(_marks, mid, 0.0)


## The player's arrow at `p`, turned `angle` (rad, clockwise from up).
static func draw_player(canvas: CanvasItem, p: Vector2, angle: float) -> void:
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -9), Vector2(6.5, 7), Vector2(0, 3.5), Vector2(-6.5, 7)]:
		arrow.append(p + v.rotated(angle))
	canvas.draw_colored_polygon(arrow, Color.WHITE)
	arrow.append(arrow[0])
	canvas.draw_polyline(arrow, INK, 1.6, true)


## A place's badge (PLACES) of kind `kind` at `p`, `r` px its radius: a disc of its colour with its glyph in white.
static func draw_place(canvas: CanvasItem, font: Font, p: Vector2, kind: String, r: float) -> void:
	var look: Dictionary = PLACES.get(kind, PLACES["garage"])
	canvas.draw_circle(p, r + 2.0, INK)
	canvas.draw_circle(p, r, look["colour"])
	match look["glyph"]:
		"bus":
			canvas.draw_rect(Rect2(p + Vector2(-0.62, -0.5) * r, Vector2(1.24, 0.8) * r), Color.WHITE)
			canvas.draw_rect(Rect2(p + Vector2(-0.48, -0.36) * r, Vector2(0.96, 0.3) * r), look["colour"])
			for x: float in [-0.35, 0.35]:
				canvas.draw_circle(p + Vector2(x, 0.38) * r, 0.17 * r, Color.WHITE)
		"ramp":
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.62, 0.42) * r, p + Vector2(0.5, 0.42) * r,
					p + Vector2(0.5, -0.12) * r]), Color.WHITE)
			canvas.draw_circle(p + Vector2(0.18, -0.48) * r, 0.17 * r, Color.WHITE)
		"flame":
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -0.72) * r, p + Vector2(0.45, -0.05) * r,
					p + Vector2(0.4, 0.38) * r, p + Vector2(0.0, 0.62) * r, p + Vector2(-0.4, 0.38) * r,
					p + Vector2(-0.45, 0.0) * r, p + Vector2(-0.18, -0.25) * r]), Color.WHITE)
		_:
			var fs := roundi(r * 1.55)
			var w := font.get_string_size(look["glyph"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			canvas.draw_string(font, p + Vector2(-w.x * 0.5, fs * 0.36), look["glyph"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color.WHITE)


## The waypoint's gold diamond at `p`, `r` px from its middle to a corner.
static func draw_waypoint(canvas: CanvasItem, p: Vector2, r: float) -> void:
	var outer := PackedVector2Array([p + Vector2(0, -r - 2.0), p + Vector2(r + 2.0, 0), p + Vector2(0, r + 2.0),
			p + Vector2(-r - 2.0, 0)])
	canvas.draw_colored_polygon(outer, INK)
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r),
			p + Vector2(-r, 0)]), WAYPOINT)
	canvas.draw_circle(p, r * 0.3, INK)
