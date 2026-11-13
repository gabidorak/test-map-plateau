extends RefCounted
## A fast lookup for a lot's grass override (scripts/grass_field.gd calls overrides up to five times per tuft, some
## thousands per 16 m chunk, six chunks a frame): the lot's exact function f(x, y) -> material id (or -2) depends only
## on which of its polygons hold the point, so it is the same all over a CELL m square that none of their edges
## crosses: computed once there (at its middle), kept; in the squares an edge crosses, f itself.

const CELL := 1.0

var _f: Callable
var _box: Rect2
var _edge := {}                             # Vector2i -> true: the squares an edge crosses
var _val := {}                              # Vector2i -> int: the others' value, once asked


## f: the exact function (map x, y); box: where it may answer other than -2; polygons: every polygon f tests (map).
func _init(f: Callable, box: Rect2, polygons: Array) -> void:
	_f = f
	_box = box
	for poly: PackedVector2Array in polygons:
		for i in poly.size():
			_mark(poly[i], poly[(i + 1) % poly.size()])


func at(x: float, y: float) -> int:
	if not _box.has_point(Vector2(x, y)):
		return -2
	var k := Vector2i(floori(x / CELL), floori(y / CELL))
	if _edge.has(k):
		return _f.call(x, y)
	var v: Variant = _val.get(k)
	if v == null:
		v = _f.call((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
		_val[k] = v
	return v


## The squares segment a -> b crosses (a grid walk), and their neighbours across a corner it passes close by.
func _mark(a: Vector2, b: Vector2) -> void:
	var c := Vector2i(floori(a.x / CELL), floori(a.y / CELL))
	var end := Vector2i(floori(b.x / CELL), floori(b.y / CELL))
	var d := b - a
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tx := INF if is_zero_approx(d.x) else ((c.x + (1 if d.x > 0.0 else 0)) * CELL - a.x) / d.x
	var ty := INF if is_zero_approx(d.y) else ((c.y + (1 if d.y > 0.0 else 0)) * CELL - a.y) / d.y
	var dx := INF if is_zero_approx(d.x) else CELL / absf(d.x)
	var dy := INF if is_zero_approx(d.y) else CELL / absf(d.y)
	_edge[c] = true
	var n := absi(end.x - c.x) + absi(end.y - c.y)
	for i in n:
		if absf(tx - ty) < 1e-6:                # through a corner: the squares either side too
			_edge[c + Vector2i(sx, 0)] = true
			_edge[c + Vector2i(0, sy)] = true
		if tx < ty:
			tx += dx
			c.x += sx
		else:
			ty += dy
			c.y += sy
		_edge[c] = true
		if c == end:
			break
	_edge[end] = true
