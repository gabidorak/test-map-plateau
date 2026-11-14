extends RefCounted
## The map's ground cut out where a lot owns its ground (builder/lots.gd: its script's ground_owned() or its "ground"
## data, polygons on the map: each an outer ring, or [outer, holes...]): the lot draws its own there, steps, walls and
## all, and collides with it, as a building does. When the map is built:
## - the ground mesh (builder/ground_builder.gd): its triangles inside them out, those across their outline cut, their
##   outer part kept (its points on the old triangle's plane, its colour and material as there);
## - the terrain's collision (builder/collision_builder.gd): its samples inside them and within HOLE_REACH m round them
##   holes; the ground mesh's triangles kept round them, within BAND m, collide exactly instead (raised faces).
## The polygons are cut into TILE m tiles first (builder/lot_ground.gd tile_pieces()): a triangle meets only those of
## its tiles. Map coordinates x east, y north (Godot (x, z, -y)).

const LotGround = preload("res://scripts/builder/lot_ground.gd")
const HOLE_REACH := 1.0                     # m round an owned polygon where the terrain's height field is a hole
const BAND := 2.0                           # m round it where the ground mesh's triangles collide exactly
const TILE := 64.0

var _tiles := {}                            # Vector2i -> [[outer pieces, hole pieces, their box grown by BAND]...]
var lost := 0.0                             # m² of the map's ground the cut could not triangulate (none expected)


func _init(polys: Array) -> void:
	for p: Variant in polys:
		var rings: Array = [p] if p is PackedVector2Array else p
		var pieces := LotGround.tile_pieces(rings, TILE)
		for key: Vector2i in pieces:
			var outs: Array = pieces[key][0]
			var r := Rect2((outs[0] as PackedVector2Array)[0], Vector2.ZERO)
			for o: PackedVector2Array in outs:
				for q in o:
					r = r.expand(q)
			if not _tiles.has(key):
				_tiles[key] = []
			_tiles[key].append([outs, pieces[key][1], r.grow(BAND)])


func is_empty() -> bool:
	return _tiles.is_empty()


## Whether Godot box `aabb` ([x, y, z, sx, sy, sz]) reaches an owned polygon (or its band).
func touches(aabb: Array) -> bool:
	var r := Rect2(float(aabb[0]), -float(aabb[2]) - float(aabb[5]), float(aabb[3]), float(aabb[5]))
	return not _near(r).is_empty()


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
		var near := _near(Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]))
		var area := absf(_area(tri[0], tri[1], tri[2])) * 0.5
		var flat := area < 1e-9                             # (a seam of the pipeline's: kept as it is, off the lots')
		if flat and not near.is_empty() and _inside((tri[0] + tri[1] + tri[2]) / 3.0):
			continue
		var pieces := _pieces(tri, near) if not near.is_empty() and not flat else []
		if near.is_empty() or flat or (pieces.size() == 1
				and absf(absf(LotGround.signed_area(pieces[0])) - area) <= 1e-6 * maxf(1.0, area)):
			for i: int in k:                                # (untouched: kept as it was, its points exactly)
				if not kept.has(i):
					kept[i] = v.size()
					v.append(verts[i])
					n.append(normals[i])
					c.append(colours[i])
					cu.append_array(custom.slice(i * 4, i * 4 + 4))
				idx.append(kept[i])
			if not near.is_empty() and not flat:            # (round the owned ground: collision)
				band.append_array([verts[k[0]], verts[k[1]], verts[k[2]]])
			continue
		var turn := signf(_area(tri[0], tri[1], tri[2]))      # (the pieces turn as the triangle did: its face up)
		for p0: PackedVector2Array in pieces:
			var p := _snapped(p0, tri)
			var tris := LotGround.triangulate(p)
			if tris.is_empty():                             # (its snapped outline folds on itself: as clipped)
				p = p0
				tris = LotGround.triangulate(p)
			if tris.is_empty():
				lost += absf(LotGround.signed_area(p))
			for i in range(0, tris.size() - 2, 3):
				var corners := [p[tris[i]], p[tris[i + 1]], p[tris[i + 2]]]
				if absf(_area(corners[0], corners[1], corners[2])) < 1e-10:
					continue                                # (flat: none)
				if signf(_area(corners[0], corners[1], corners[2])) != turn:
					corners = [corners[0], corners[2], corners[1]]
				for q: Vector2 in corners:                  # (on the old triangle's plane: its point exactly, its
					var w := _bary(tri, q)                  # height, normal, colour from its corners')
					var g := Vector3(q.x, verts[k[0]].y * w.x + verts[k[1]].y * w.y + verts[k[2]].y * w.z, -q.y)
					idx.append(v.size())
					v.append(g)
					n.append((normals[k[0]] * w.x + normals[k[1]] * w.y + normals[k[2]] * w.z).normalized())
					c.append(colours[k[0]] * w.x + colours[k[1]] * w.y + colours[k[2]] * w.z)
					var src: int = k[0] if w.x >= w.y and w.x >= w.z else (k[1] if w.y >= w.z else k[2])
					cu.append_array(custom.slice(src * 4, src * 4 + 4))
					band.append(g)                          # (round the owned ground: collision)
	return [v, n, c, cu, idx, band]


## Map triangle tri less the owned polygons near it (`near`: _near()'s), their holes kept but for another owned
## polygon in them: its pieces.
static func _pieces(tri: PackedVector2Array, near: Array) -> Array:
	var pieces: Array = [tri]
	for e: Array in near:
		for o: PackedVector2Array in e[0]:
			pieces = LotGround.minus_all(pieces, o)
	for i in near.size():
		for hole: PackedVector2Array in near[i][1]:
			var parts: Array = Geometry2D.intersect_polygons(tri, hole)
			for j in near.size():
				if j != i:
					for o: PackedVector2Array in near[j][0]:
						parts = LotGround.minus_all(parts, o)
			pieces.append_array(parts)
	return pieces


## Piece p of map triangle tri with the triangle's corners exactly where the clipping rounded them (its neighbours
## have them so), its points that came to coincide once.
static func _snapped(p: PackedVector2Array, tri: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		for c in tri:
			if q.distance_squared_to(c) < 1e-8:
				q = c
		if out.is_empty() or out[out.size() - 1] != q:
			out.append(q)
	if out.size() > 1 and out[0] == out[out.size() - 1]:
		out.resize(out.size() - 1)
	return out


## Godot triangles (faces, 3 points each) without those inside an owned polygon (their middle there).
func outside(faces: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var m := (_m(faces[i]) + _m(faces[i + 1]) + _m(faces[i + 2])) / 3.0
		if not _inside(m):
			out.append_array([faces[i], faces[i + 1], faces[i + 2]])
	return out


## The terrain collision's samples (heightmap row, column, every `step`-th) inside the owned polygons or within
## HOLE_REACH m of them: holes (builder/collision_builder.gd).
func hole_samples(t: Dictionary, step: int) -> Array:
	var cell: float = t["cell"]
	var ox: float = t["origin_xy"][0]
	var oy: float = t["origin_xy"][1]
	var found := {}
	for key: Vector2i in _tiles:
		for e: Array in _tiles[key]:
			var grown: Array = []
			for o: PackedVector2Array in e[0]:
				grown.append_array(Geometry2D.offset_polygon(o, HOLE_REACH))
			var holes: Array = []
			for hole: PackedVector2Array in e[1]:
				holes.append_array(Geometry2D.offset_polygon(hole, -HOLE_REACH))
			var r: Rect2 = (e[2] as Rect2).grow(HOLE_REACH - BAND)
			var c0 := maxi(0, floori((r.position.x - ox) / cell / step) * step)
			var c1 := ceili((r.end.x - ox) / cell / step) * step
			var r0 := maxi(0, floori((oy - r.end.y) / cell / step) * step)
			var r1 := ceili((oy - r.position.y) / cell / step) * step
			for row in range(r0, r1 + 1, step):
				for col in range(c0, c1 + 1, step):
					var p := Vector2(ox + col * cell, oy - row * cell)
					if grown.any(func(g: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, g)) \
							and not holes.any(func(g: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, g)):
						found[Vector2i(row, col)] = true
	return found.keys().map(func(k: Vector2i) -> Array: return [k.x, k.y])


## The owned pieces near map rectangle r (within BAND of it): [[outer pieces, hole pieces, box]...].
func _near(r: Rect2) -> Array:
	var out := []
	var g := r.grow(BAND)
	for tx in range(floori(g.position.x / TILE), floori(g.end.x / TILE) + 1):
		for ty in range(floori(g.position.y / TILE), floori(g.end.y / TILE) + 1):
			for e: Array in _tiles.get(Vector2i(tx, ty), []):
				if (e[2] as Rect2).intersects(r):
					out.append(e)
	return out


## Whether map point m is on owned ground (in a piece of its tile, in none of its holes).
func _inside(m: Vector2) -> bool:
	for e: Array in _tiles.get(Vector2i(floori(m.x / TILE), floori(m.y / TILE)), []):
		if (e[0] as Array).any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(m, o)) \
				and not (e[1] as Array).any(func(h: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(m, h)):
			return true
	return false


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
