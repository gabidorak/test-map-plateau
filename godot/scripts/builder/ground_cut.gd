extends RefCounted
## The map's ground cut out where a lot owns its ground (builder/lots.gd: its script's ground_owned(), polygons on the
## map): the lot draws its own there, steps, walls and all, and collides with it, as a building does. When the map is
## built:
## - the ground mesh (builder/ground_builder.gd): its triangles inside them out, those across their outline cut, their
##   outer part kept (its points on the old triangle's plane, its colour and material as there);
## - the terrain's collision (builder/collision_builder.gd): its samples inside them and within HOLE_REACH m round them
##   holes; the ground mesh's triangles kept round them, within BAND m, collide exactly instead (raised faces).
## Map coordinates x east, y north (Godot (x, z, -y)).

const HOLE_REACH := 1.0                     # m round an owned polygon where the terrain's height field is a hole
const BAND := 2.0                           # m round it where the ground mesh's triangles collide exactly

var _polys: Array = []                      # [polygon (map), its box grown by BAND]


func _init(polys: Array) -> void:
	for p: PackedVector2Array in polys:
		var r := Rect2(p[0], Vector2.ZERO)
		for q in p:
			r = r.expand(q)
		_polys.append([p, r.grow(BAND)])


func is_empty() -> bool:
	return _polys.is_empty()


## Whether Godot box `aabb` ([x, y, z, sx, sy, sz]) reaches an owned polygon (or its band).
func touches(aabb: Array) -> bool:
	var r := Rect2(float(aabb[0]), -float(aabb[2]) - float(aabb[5]), float(aabb[3]), float(aabb[5]))
	return _polys.any(func(e: Array) -> bool: return (e[1] as Rect2).intersects(r))


## A chunk's triangles (Godot vertices, normals, colours, 4 bytes of custom per vertex, index) with the owned ground cut
## out: [vertices, normals, colours, custom, index, band faces (Godot triangles kept within BAND: collision)].
func cut(verts: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, custom: PackedByteArray,
		index: PackedInt32Array) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var cu := PackedByteArray()
	var idx := PackedInt32Array()
	var band := PackedVector3Array()
	var kept := {}                                          # old vertex -> new
	for t in range(0, index.size(), 3):
		var k: Array = [index[t], index[t + 1], index[t + 2]]
		var tri := PackedVector2Array([_m(verts[k[0]]), _m(verts[k[1]]), _m(verts[k[2]])])
		var near := _near(tri)
		if near.is_empty():                                 # (untouched: kept as it was)
			for i: int in k:
				if not kept.has(i):
					kept[i] = v.size()
					v.append(verts[i])
					n.append(normals[i])
					c.append(colours[i])
					cu.append_array(custom.slice(i * 4, i * 4 + 4))
				idx.append(kept[i])
			continue
		var pieces: Array = [tri]
		for e: Array in near:
			var next := []
			for p: PackedVector2Array in pieces:
				next.append_array(_minus(p, e[0]))
			pieces = next
		var turn := signf(_area(tri[0], tri[1], tri[2]))      # (the pieces turn as the triangle did: its face up)
		for p: PackedVector2Array in pieces:
			var tris := Geometry2D.triangulate_polygon(p)
			for i in range(0, tris.size() - 2, 3):
				var corners := [p[tris[i]], p[tris[i + 1]], p[tris[i + 2]]]
				if signf(_area(corners[0], corners[1], corners[2])) != turn:
					corners = [corners[0], corners[2], corners[1]]
				for q: Vector2 in corners:
					var w := _bary(tri, q)
					var g: Vector3 = verts[k[0]] * w.x + verts[k[1]] * w.y + verts[k[2]] * w.z
					idx.append(v.size())
					v.append(g)
					n.append((normals[k[0]] * w.x + normals[k[1]] * w.y + normals[k[2]] * w.z).normalized())
					c.append(colours[k[0]] * w.x + colours[k[1]] * w.y + colours[k[2]] * w.z)
					var src: int = k[0] if w.x >= w.y and w.x >= w.z else (k[1] if w.y >= w.z else k[2])
					cu.append_array(custom.slice(src * 4, src * 4 + 4))
					band.append(g)                          # (round the owned ground: collision)
	return [v, n, c, cu, idx, band]


## Godot triangles (faces, 3 points each) without those inside an owned polygon (their middle there).
func outside(faces: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var m := (_m(faces[i]) + _m(faces[i + 1]) + _m(faces[i + 2])) / 3.0
		if not _polys.any(func(e: Array) -> bool: return Geometry2D.is_point_in_polygon(m, e[0])):
			out.append_array([faces[i], faces[i + 1], faces[i + 2]])
	return out


## The terrain collision's samples (heightmap row, column, every `step`-th) inside the owned polygons or within
## HOLE_REACH m of them: holes (builder/collision_builder.gd).
func hole_samples(t: Dictionary, step: int) -> Array:
	var out := []
	var cell: float = t["cell"]
	var ox: float = t["origin_xy"][0]
	var oy: float = t["origin_xy"][1]
	for e: Array in _polys:
		var grown: Array = Geometry2D.offset_polygon(e[0], HOLE_REACH)
		var r: Rect2 = (e[1] as Rect2).grow(HOLE_REACH - BAND)
		var c0 := maxi(0, floori((r.position.x - ox) / cell / step) * step)
		var c1 := ceili((r.end.x - ox) / cell / step) * step
		var r0 := maxi(0, floori((oy - r.end.y) / cell / step) * step)
		var r1 := ceili((oy - r.position.y) / cell / step) * step
		for row in range(r0, r1 + 1, step):
			for col in range(c0, c1 + 1, step):
				var p := Vector2(ox + col * cell, oy - row * cell)
				if grown.any(func(g: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, g)):
					out.append([row, col])
	return out


## The owned polygons near triangle `tri` (within BAND of it): [[polygon, box]...].
func _near(tri: PackedVector2Array) -> Array:
	var r := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
	return _polys.filter(func(e: Array) -> bool: return (e[1] as Rect2).intersects(r))


## Polygon p minus polygon cut (its holes cut out too: a piece left with one inside is split in four first).
static func _minus(p: PackedVector2Array, cut: PackedVector2Array, depth := 0) -> Array:
	var res := Geometry2D.clip_polygons(p, cut)
	if res.size() <= 1 or depth > 4 or not res.any(func(q: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(p)):
		return res
	var out := []                                           # (cut inside p, a hole: p in four, each cut)
	var box := Rect2(p[0], Vector2.ZERO)
	for q in p:
		box = box.expand(q)
	var m := box.get_center()
	for quad: PackedVector2Array in [PackedVector2Array([box.position, Vector2(m.x, box.position.y), m, Vector2(box.position.x, m.y)]),
			PackedVector2Array([Vector2(m.x, box.position.y), Vector2(box.end.x, box.position.y), Vector2(box.end.x, m.y), m]),
			PackedVector2Array([m, Vector2(box.end.x, m.y), box.end, Vector2(m.x, box.end.y)]),
			PackedVector2Array([Vector2(box.position.x, m.y), m, Vector2(m.x, box.end.y), Vector2(box.position.x, box.end.y)])]:
		for part: PackedVector2Array in Geometry2D.intersect_polygons(p, quad):
			out.append_array(_minus(part, cut, depth + 1))
	return out


static func _area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b - a).cross(c - a)


## Barycentric weights of map point q in map triangle tri.
static func _bary(tri: PackedVector2Array, q: Vector2) -> Vector3:
	var a := tri[0]
	var b := tri[1]
	var c := tri[2]
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var wa := ((b.y - c.y) * (q.x - c.x) + (c.x - b.x) * (q.y - c.y)) / d
	var wb := ((c.y - a.y) * (q.x - c.x) + (a.x - c.x) * (q.y - c.y)) / d
	return Vector3(wa, wb, 1.0 - wa - wb)


static func _m(g: Vector3) -> Vector2:
	return Vector2(g.x, -g.z)
