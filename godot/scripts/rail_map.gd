extends RefCounted
## Runtime railway lookups from world/rail.json (tools/rail/build_rail.py): the centreline of the RER B at any
## distance s from its west end (point, heading, rail level, cant), the projection of a map point onto it (s, u),
## which track a point is on, the kilometre point (PK) and the speed limit there. Pipeline coordinates (x east,
## y north, z up). Shared by the rail builder, the picker, the trains and the tests.

const DEFAULT_PATH := "res://world/rail.json"
const BUCKET := 20.0                    # m, grid of centreline points for project()
const LINE_SPEED := 90.0                # km/h, OSM maxspeed of the line (rail.json tracks[].maxspeed)

static var _cache := {}

var data: Dictionary                    # rail.json as parsed
var step := 1.0                         # m between centreline points
var length := 0.0
var spacing := 0.0                      # m between the track centres
var tracks: Array = []                  # rail.json tracks: ref, side, offset (u), direction, maxspeed
var _pts := PackedVector2Array()
var _heading := PackedFloat32Array()
var _z := PackedFloat32Array()
var _cant := PackedFloat32Array()       # m, signed: positive raises the north rails
var _grid := {}                         # Vector2i -> PackedInt32Array of point indices
var _pk_a := 0.0                        # PK (km) = a + b * s (rail.json pk, fitted on the OSM posts)
var _pk_b := 0.0
var _limits: Array = []                 # [s0, s1, km/h]: curves and speed signs


## Loaded once per file and shared; null when the map has no railway.
static func get_map(path := DEFAULT_PATH) -> RefCounted:
	if not _cache.has(path):
		if not FileAccess.file_exists(path):
			return null
		var m = load("res://scripts/rail_map.gd").new()
		if not m._load(path):
			return null
		_cache[path] = m
	return _cache[path]


func _load(path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_error("cannot read %s" % path)
		return false
	data = d
	var a: Dictionary = d["alignment"]
	step = a["step"]
	length = a["length"]
	spacing = a["spacing"]
	tracks = d["tracks"]
	for i in (a["pts"] as Array).size():
		var p: Array = a["pts"][i]
		_pts.append(Vector2(p[0], p[1]))
		_heading.append(a["heading"][i])
		_z.append(a["z"][i])
		_cant.append(float(a["cant"][i]) / 1000.0)
		var key := Vector2i(floori(p[0] / BUCKET), floori(p[1] / BUCKET))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)
	_pk_a = d["pk"]["a"]
	_pk_b = d["pk"]["b"]
	for c: Dictionary in a["curves"]:
		_limits.append([float(c["s0"]), float(c["s1"]), float(c["speed"])])
	for sg: Dictionary in a.get("speed_signs", []):
		_limits.append([float(sg["s0"]), float(sg["s1"]), float(sg["kmh"])])
	return true


func _at(s: float) -> Vector2:          # (index, fraction)
	var f := clampf(s / step, 0.0, _pts.size() - 1.000001)
	return Vector2(floorf(f), f - floorf(f))


## Map point at s along the centreline, u to its left (north side positive).
func point(s: float, u := 0.0) -> Vector2:
	var k := _at(s)
	var i := int(k.x)
	var p := _pts[i].lerp(_pts[i + 1], k.y)
	var th := lerpf(_heading[i], _heading[i + 1], k.y)
	return p + Vector2(-sin(th), cos(th)) * u


## Heading at s, radians from east (map), anticlockwise.
func heading(s: float) -> float:
	var k := _at(s)
	return lerpf(_heading[int(k.x)], _heading[int(k.x) + 1], k.y)


## Rail level at s: top of the inner (lower) rail.
func level(s: float) -> float:
	var k := _at(s)
	return lerpf(_z[int(k.x)], _z[int(k.x) + 1], k.y)


## Cant at s in metres (rail height difference), signed: positive raises the north rails.
func cant(s: float) -> float:
	var k := _at(s)
	return lerpf(_cant[int(k.x)], _cant[int(k.x) + 1], k.y)


## Top of a rail whose head is at u (the rails of a canted track rise on the high side).
func rail_top(s: float, u: float, track_offset: float) -> float:
	var c := cant(s)
	var side := signf(u - track_offset)
	return level(s) + maxf(0.0, c * side)


## (s, u) of map point p: distance along the centreline and offset to its left. s is clamped to the line.
func project(p: Vector2) -> Vector2:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	var best := -1
	var best_d := INF
	for r in range(1, 4):               # widen until some centreline point is found
		for i in range(-r, r + 1):
			for j in range(-r, r + 1):
				for k: int in _grid.get(key + Vector2i(i, j), PackedInt32Array()):
					var d := p.distance_squared_to(_pts[k])
					if d < best_d:
						best_d = d
						best = k
		if best >= 0:
			break
	if best < 0:
		return Vector2(NAN, NAN)
	var out := Vector2(NAN, INF)
	for a in [best - 1, best]:
		if a < 0 or a >= _pts.size() - 1:
			continue
		var ab := _pts[a + 1] - _pts[a]
		var t := clampf((p - _pts[a]).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var c := _pts[a] + ab * t
		var d := p.distance_to(c)
		if d < absf(out.y):
			out = Vector2((a + t) * step, d * signf(ab.cross(p - c)))
	return out


## The track (rail.json tracks entry) whose centre is nearest to offset u, or {} beyond max_off of any.
func track_at(u: float, max_off := 2.5) -> Dictionary:
	var best := {}
	var best_d := max_off
	for t: Dictionary in tracks:
		var d := absf(u - float(t["offset"]))
		if d < best_d:
			best_d = d
			best = t
	return best


## Kilometre point at s (km from Paris along the line).
func pk(s: float) -> float:
	return _pk_a + _pk_b * s


## Speed limit at s in km/h: the line speed, or less in a curve or under a speed sign.
func limit_kmh(s: float) -> float:
	var v := LINE_SPEED
	for l: Array in _limits:
		if s >= l[0] and s <= l[1]:
			v = minf(v, l[2])
	return v
