extends RefCounted
## The trees' crowns the police helicopter cannot see through (police.gd heli_sees): under the trees, it loses you.
## The crowns are VegetationData's ellipsoids (every tree of the map, the lots' and the restyled gardens' too: they go
## through world.json's trees); they have no collider (the player walks under them), so the sight ray misses them.
## Hidden: a crown over them (whatever the helicopter's angle: from aside, it would see under a lone tree, which the
## player cannot judge), or one between.
## A grid of CELL m squares (Godot x, z) holds the trees whose crown reaches over each; a sight line looks at the
## squares along it (every STEP m) and at their crowns, the segment against each ellipsoid.

const VegetationData = preload("res://scripts/vegetation_data.gd")
const CELL := 8.0                           # m: the grid's squares
const STEP := 2.0                           # m between the points looked at along a sight line
const OVER := 40.0                          # m above them a crown covers them

var trees := 0                              # crowns in the grid
var build_ms := 0

var _data: VegetationData
var _cells := {}                            # Vector2i -> Array of tree indices whose crown reaches over that square


func _init(data: VegetationData) -> void:
	var t0 := Time.get_ticks_msec()
	_data = data
	for k in data.crown_center.size():
		var c := data.crown_center[k]
		var r := data.crown_radii[k]
		if r.x <= 0.0 or r.y <= 0.0:
			continue
		trees += 1
		for i in range(floori((c.x - r.x) / CELL), floori((c.x + r.x) / CELL) + 1):
			for j in range(floori((c.z - r.x) / CELL), floori((c.z + r.x) / CELL) + 1):
				var key := Vector2i(i, j)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(k)
	build_ms = Time.get_ticks_msec() - t0


## Whether a tree's crown stands over `to` (OVER m) or between `from` and `to` (global).
func hides(from: Vector3, to: Vector3) -> bool:
	return covers(to) or _between(from, to)


## Whether a tree's crown stands over `p` (global), OVER m up at most.
func covers(p: Vector3) -> bool:
	var up := Vector3.UP * OVER
	for k: int in _cells.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)), []):
		if _through(k, p, up):
			return true
	return false


func _between(from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var flat := Vector2(seg.x, seg.z).length()
	var n := maxi(ceili(flat / STEP), 1)
	var looked := {}
	for s in n + 1:
		var p := from + seg * (float(s) / n)
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if looked.has(key):
			continue
		looked[key] = true
		for k: int in _cells.get(key, []):
			if _through(k, from, seg):
				return true
	return false


## Whether the segment from `from` along `seg` (its whole length) goes through tree k's crown.
func _through(k: int, from: Vector3, seg: Vector3) -> bool:
	var r := _data.crown_radii[k]
	var s := Vector3(1.0 / r.x, 1.0 / r.y, 1.0 / r.x)  # (the ellipsoid scaled to a unit sphere)
	var o := (from - _data.crown_center[k]) * s
	var d := seg * s
	var a := d.dot(d)
	var b := o.dot(d)
	var c := o.dot(o) - 1.0
	if c <= 0.0:
		return true                         # (from inside it)
	var disc := b * b - a * c
	if disc < 0.0 or a <= 0.0:
		return false
	var q := sqrt(disc)
	return (-b + q) / a >= 0.0 and (-b - q) / a <= 1.0
