extends Control
## The loading screen's animated map (scripts/loading_screen.gd): the plateau drawn as a transit map from the game's
## own route data. The roads the bot cars drive (world/car_routes.json) as a faint web, the RER B (world/rail.json)
## and the four bus lines in their colours (world/bus_routes.json), with their stops and stations, and buses and
## trains running along them. Nothing to load before it can draw: the files are read and thinned out on a worker thread
## the first time a screen asks (MAP.parse below), the map fades in once they are, and the result is kept for the
## rest of the session, so the screen shown when going back to the menu has its map at once.
## The lines draw themselves in the first time the map shows (once per session); the vehicles' positions come from
## the clock alone (_clock: the frames' deltas, not the time the frame's work happens to end, which moved them by
## up to the loader's budget), so two screens shown one over the other (the startup screen fading out over game.gd's
## own while a game starts) show the same frame and cross-fade without a jump. The whole map drifts slowly (the
## transform of a Node2D holding the layers: no redraw; a Control's position would be snapped to whole pixels, the map
## jumping a pixel at a time while its scale changed smoothly); only the vehicles and the station pulses are redrawn
## every frame.

const BUS_ROUTES := "res://world/bus_routes.json"
const CAR_ROUTES := "res://world/car_routes.json"
const RAIL := "res://world/rail.json"
const RER_B := Color("#5291ce")               # the RER B's blue on the Île-de-France maps
const ROAD := Color(1, 1, 1, 0.07)
const THIN_M := 9.0                           # m between the points kept from the 1 m route samples
const REVEAL := 1.6                           # s for the lines to draw in, the first time
const BUS_GAP_M := 1700.0                     # m between two buses of a line on the map
const BUS_SPEED := 380.0                      # m/s on the map: a line crossed in ~20 s
const TRAIN_SPEED := 520.0
const BUS_LEN_M := 70.0
const TRAIN_LEN_M := 200.0
const PULSE_EVERY := 2.6                      # s between two rings round a station
const GRID_M := 500.0

## Shared by every screen of the session: the parsed map, and the worker task parsing it.
static var _data := {}
static var _task := -1
static var _parsed := {}                      # written by the task, read once it is done
static var _revealed_at := -1.0               # clock (s) when the lines first drew in
static var _now := 0.0                        # the clock (s): the frames' deltas added up, once a frame
static var _now_frame := -1

var _fit := Transform2D.IDENTITY              # world metres (x east, y north) -> this Control's pixels
var _fit_size := Vector2.ZERO                 # the size _fit is for
var _shown := 0.0                             # 0..1 while the map fades in
var _roads: Control                           # drawn once (per size)
var _lines: Control                           # redrawn while the lines draw in
var _moving: Control                          # vehicles and pulses, every frame
var _drift: Node2D                            # the three, drifting


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drift = Node2D.new()
	add_child(_drift)
	for layer in 3:
		var c := Control.new()                  # (sized in _refit: a Control is culled outside its rect)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drift.add_child(c)
	_roads = _drift.get_child(0)
	_lines = _drift.get_child(1)
	_moving = _drift.get_child(2)
	_roads.draw.connect(_draw_roads)
	_lines.draw.connect(_draw_lines)
	_moving.draw.connect(_draw_moving)
	modulate.a = 0.0
	if not ready_to_draw():
		_start_parse()


## The map data is here (parsed in an earlier screen, or just now).
static func ready_to_draw() -> bool:
	return not _data.is_empty()


static func _clock() -> float:
	return _now


static func _start_parse() -> void:
	if _task >= 0 or not _data.is_empty():
		return
	_task = WorkerThreadPool.add_task(_parse_task, false, "Loading screen map")


static func _parse_task() -> void:
	_parsed = parse()


## Picks up the worker's result once it is done (main thread).
static func _poll_parse() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_data = _parsed if not _parsed.is_empty() else {"empty": true}
	_parsed = {}


## The map's shapes, in world metres: {"roads": [PackedVector2Array], "rail": [path], "lines": [{"colour", "ref",
## "paths": [path], "stops": PackedVector2Array}], "stations": [[name, Vector2]], "box": Rect2}, a path being
## {"pts": PackedVector2Array, "cum": PackedFloat32Array (m along it), "length": float}. Runs on a worker thread:
## files and JSON only, no node.
static func parse() -> Dictionary:
	var out := {"roads": [], "rail": [], "lines": [], "stations": []}
	var box := Rect2()
	var bus: Variant = _read(BUS_ROUTES)
	if bus is Dictionary:
		var gare := {}                          # station name -> [sum, count]
		for line: Dictionary in bus.get("lines", []):
			var entry := {"colour": Color.html(str(line.get("colour", "#ffffff"))), "ref": str(line.get("ref", "")),
					"paths": [], "stops": PackedVector2Array()}
			for id: String in line.get("routes", []):
				var route: Dictionary = bus["routes"].get(id, {})
				var pts: Array = route.get("pts", [])
				if pts.size() < 2:
					continue
				var path := _path(pts, float(route.get("step", 1.0)))
				entry["paths"].append(path)
				for stop: Dictionary in route.get("stops", []):
					var k := clampi(roundi(float(stop["s"]) / float(route.get("step", 1.0))), 0, pts.size() - 1)
					var p := Vector2(pts[k][0], pts[k][1])
					entry["stops"].append(p)
					var name := str(stop.get("name", ""))
					if name.begins_with("Gare "):
						var key := name.replace("Gare de ", "").replace("Gare du ", "Le ").replace(" - ", "-")
						var acc: Array = gare.get(key, [Vector2.ZERO, 0])
						gare[key] = [acc[0] + p, acc[1] + 1]
			if not entry["paths"].is_empty():
				out["lines"].append(entry)
		for key: String in gare:
			out["stations"].append([key, gare[key][0] / float(gare[key][1])])
	var cars: Variant = _read(CAR_ROUTES)
	if cars is Dictionary:
		for route: Dictionary in cars.get("routes", {}).values():
			var pts: Array = route.get("pts", [])
			if pts.size() >= 2:
				out["roads"].append(_path(pts, float(route.get("step", 1.0)), 1.5)["pts"])
	var rail: Variant = _read(RAIL)
	if rail is Dictionary:
		for service: Dictionary in rail.get("services", []):
			var pts: Array = service.get("pts", [])
			if pts.size() >= 2:
				out["rail"].append(_path(pts, float(service.get("step", 1.0))))
		var named := {}
		for st: Array in out["stations"]:
			named[st[0]] = true
		var services: Array = rail.get("services", [])
		for platform: Dictionary in rail.get("platforms", []):
			var name := str(platform.get("name", ""))
			if name == "" or named.has(name):
				continue
			for service: Dictionary in services:
				if str(service.get("track", "")) != str(platform.get("track", "")):
					continue
				var pts: Array = service["pts"]
				var mid := (float(platform.get("s0", 0.0)) + float(platform.get("s1", 0.0))) * 0.5
				var k := clampi(roundi(mid / float(service.get("step", 1.0))), 0, pts.size() - 1)
				out["stations"].append([name, Vector2(pts[k][0], pts[k][1])])
				named[name] = true
				break
	# The frame: everything drawn but the roads, which reach out to the map's edges.
	var first := true
	for group: Array in [out["rail"]] + out["lines"].map(func(l: Dictionary) -> Array: return l["paths"]):
		for path: Dictionary in group:
			for p: Vector2 in path["pts"]:
				if first:
					box = Rect2(p, Vector2.ZERO)
					first = false
				else:
					box = box.expand(p)
	if first:
		return {}
	out["box"] = box.grow(box.size.x * 0.03)
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The route's points one every THIN_M * `thin` m (and its last), with the distance along it at each.
static func _path(pts: Array, step: float, thin := 1.0) -> Dictionary:
	var every := maxi(1, roundi(THIN_M * thin / maxf(step, 0.01)))
	var out := PackedVector2Array()
	var cum := PackedFloat32Array()
	var total := 0.0
	for i in range(0, pts.size(), every):
		var p := Vector2(pts[i][0], pts[i][1])
		if not out.is_empty():
			total += p.distance_to(out[-1])
		out.append(p)
		cum.append(total)
	var last := Vector2(pts[-1][0], pts[-1][1])
	if out[-1] != last:
		total += last.distance_to(out[-1])
		out.append(last)
		cum.append(total)
	return {"pts": out, "cum": cum, "length": total}


func _process(delta: float) -> void:
	if _now_frame != Engine.get_process_frames():
		_now_frame = Engine.get_process_frames()
		_now += delta
	if _data.is_empty():
		_poll_parse()
		if _data.is_empty():
			return
	if _data.has("empty"):
		return
	if size != _fit_size:
		_refit()
	if _shown < 1.0:
		_shown = minf(1.0, _shown + delta / 0.6)
		modulate.a = _shown * _shown * (3.0 - 2.0 * _shown)
	if _revealed_at < 0.0:
		_revealed_at = _clock()
	if _clock() - _revealed_at < REVEAL + 0.1:
		_lines.queue_redraw()
	# A slow drift over the map, as if a camera hovered over it.
	var t := _clock()
	var k := 1.035 + 0.025 * sin(t * 0.07)    # scaled about the middle
	var shift := Vector2(sin(t * 0.045) * size.x * 0.012, cos(t * 0.06) * size.y * 0.01)
	_drift.transform = Transform2D(0.0, Vector2(k, k), 0.0, shift + size * 0.5 * (1.0 - k))
	_moving.queue_redraw()


## Fits the map's box in this Control, north up, with room left for the title above and the status below.
func _refit() -> void:
	for c: Control in _drift.get_children():
		c.size = size
	if not _data.has("box") or size.x < 2.0 or size.y < 2.0:
		return
	_fit_size = size
	var box: Rect2 = _data["box"]
	var area := Rect2(size * Vector2(0.06, 0.2), size * Vector2(0.88, 0.56))
	var k := minf(area.size.x / box.size.x, area.size.y / box.size.y)
	var centre := box.get_center()
	# x' = area centre + (x - centre.x) * k, y' = area centre - (y - centre.y) * k
	_fit = Transform2D(Vector2(k, 0.0), Vector2(0.0, -k), area.get_center() - Vector2(centre.x, -centre.y) * k)
	_roads.queue_redraw()
	_lines.queue_redraw()


func _px(path: PackedVector2Array) -> PackedVector2Array:
	return _fit * path


func _draw_roads() -> void:
	if not _data.has("box"):
		return
	# A faint 500 m grid under it all, as on a survey map.
	var inv := _fit.affine_inverse()
	var lo := inv * Vector2(-size.x * 0.1, size.y * 1.1)
	var hi := inv * Vector2(size.x * 1.1, -size.y * 0.1)
	var grid := Color(1, 1, 1, 0.025)
	for gx in range(floori(lo.x / GRID_M), ceili(hi.x / GRID_M) + 1):
		_roads.draw_line(_fit * Vector2(gx * GRID_M, lo.y), _fit * Vector2(gx * GRID_M, hi.y), grid, 1.0)
	for gy in range(floori(lo.y / GRID_M), ceili(hi.y / GRID_M) + 1):
		_roads.draw_line(_fit * Vector2(lo.x, gy * GRID_M), _fit * Vector2(hi.x, gy * GRID_M), grid, 1.0)
	for road: PackedVector2Array in _data["roads"]:
		_roads.draw_polyline(_px(road), ROAD, 1.2, true)


## The rail and the lines, drawn in from their start the first time (`f` of each path, the later ones later).
func _draw_lines() -> void:
	if not _data.has("box"):
		return
	var t := (_clock() - _revealed_at) / REVEAL if _revealed_at >= 0.0 else 0.0
	var f := func(order: float) -> float:
		var x := clampf((t - order * 0.35) / 0.65, 0.0, 1.0)
		return 1.0 - pow(1.0 - x, 3.0)
	for path: Dictionary in _data["rail"]:
		_stroke(_lines, path, f.call(0.0), Color(RER_B, 0.35), 7.0)
		_stroke(_lines, path, f.call(0.0), RER_B, 3.2)
	var n: int = _data["lines"].size()
	for i in n:
		var line: Dictionary = _data["lines"][i]
		var c: Color = line["colour"]
		var order := 0.25 + 0.75 * float(i) / maxf(1.0, n - 1.0)
		for path: Dictionary in line["paths"]:
			_stroke(_lines, path, f.call(order), c, 2.4)
		if f.call(order) >= 1.0:
			for p: Vector2 in line["stops"]:
				_lines.draw_circle(_fit * p, 2.2, Color(0.95, 0.96, 1.0, 0.85))
	if f.call(1.0) < 1.0:
		return
	var font := get_theme_default_font()
	for st: Array in _data["stations"]:
		var p: Vector2 = _fit * (st[1] as Vector2)
		_lines.draw_circle(p, 6.0, Color(0.04, 0.05, 0.08))
		_lines.draw_circle(p, 6.0, Color.WHITE, false, 2.0, true)
		_lines.draw_string_outline(font, p + Vector2(10, -8), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5,
				Color(0.03, 0.04, 0.07, 0.9))
		_lines.draw_string(font, p + Vector2(10, -8), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.9, 0.95))


## The first `f` (0..1) of `path`, as a polyline.
func _stroke(canvas: Control, path: Dictionary, f: float, colour: Color, width: float) -> void:
	if f <= 0.0:
		return
	var pts: PackedVector2Array = path["pts"]
	if f < 1.0:
		var cut := float(path["length"]) * f
		var cum: PackedFloat32Array = path["cum"]
		var k := maxi(1, cum.bsearch(cut))
		pts = pts.slice(0, k)
		pts.append(_at(path, cut))
	if pts.size() >= 2:
		canvas.draw_polyline(_px(pts), colour, width, true)


## The point `d` m along `path` (world metres).
static func _at(path: Dictionary, d: float) -> Vector2:
	var cum: PackedFloat32Array = path["cum"]
	var pts: PackedVector2Array = path["pts"]
	d = clampf(d, 0.0, float(path["length"]))
	var k := clampi(cum.bsearch(d), 1, pts.size() - 1)
	var span := cum[k] - cum[k - 1]
	return pts[k - 1].lerp(pts[k], (d - cum[k - 1]) / span if span > 0.0 else 0.0)


## The piece of `path` from `d0` to `d1` m, in pixels.
func _piece(path: Dictionary, d0: float, d1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in 4:
		out.append(_fit * _at(path, lerpf(d0, d1, j / 3.0)))
	return out


func _draw_moving() -> void:
	if not _data.has("box"):
		return
	var t := _clock()
	var since := t - _revealed_at
	if since < REVEAL * 0.6:
		return
	var a := clampf((since - REVEAL * 0.6) / 0.6, 0.0, 1.0)
	# The RER B: a train each way, a long white-and-blue capsule.
	for i in _data["rail"].size():
		var path: Dictionary = _data["rail"][i]
		var length: float = path["length"]
		var d := fposmod(t * TRAIN_SPEED + i * length * 0.5, length + 2400.0) - 1200.0
		if d < 0.0 or d > length:
			continue                            # waits a moment off the map before its next run
		var piece := _piece(path, maxf(0.0, d - TRAIN_LEN_M), d)
		_moving.draw_polyline(piece, Color(RER_B, 0.3 * a), 11.0, true)
		_moving.draw_polyline(piece, Color(0.92, 0.95, 1.0, a), 5.0, true)
	# The buses: a few per route, evenly spaced, in their line's colour with a white nose.
	for li in _data["lines"].size():
		var line: Dictionary = _data["lines"][li]
		var c: Color = line["colour"]
		for pi in line["paths"].size():
			var path: Dictionary = line["paths"][pi]
			var length: float = path["length"]
			var count := maxi(1, floori(length / BUS_GAP_M))
			for b in count:
				var d := fposmod(t * BUS_SPEED + (b + 0.37 * li + 0.5 * pi) * length / count, length)
				var piece := _piece(path, maxf(0.0, d - BUS_LEN_M), d)
				_moving.draw_polyline(piece, Color(c, 0.25 * a), 9.0, true)
				_moving.draw_polyline(piece, Color(c, a), 4.5, true)
				_moving.draw_circle(piece[-1], 1.8, Color(1, 1, 1, a))
	# Rings spreading round the stations, one after the other.
	var n: int = _data["stations"].size()
	for i in n:
		var u := fposmod(t / PULSE_EVERY - float(i) / maxf(1.0, n), 1.0)
		var p: Vector2 = _fit * (_data["stations"][i][1] as Vector2)
		_moving.draw_circle(p, 6.0 + 22.0 * u, Color(1, 1, 1, 0.35 * (1.0 - u) * a), false, 1.5, true)
