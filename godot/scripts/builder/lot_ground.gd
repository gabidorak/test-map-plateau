extends RefCounted
## A lot's own ground (its lot's "ground": data/<lot>/ground.json and ground.bin, made by its tool with
## tools/common/lot_ground.py): its zones (polygons on the map, [outer, holes...] each) with their heights on grids, the
## material each lays (or the map's), and its repairs (the map's ground reshaped round them). Python designs it; here it
## is laid into the map when the map is built (builder/lots.gd, builder/world_builder.gd):
## - its owned zones cut out of the map's ground (owned(): builder/ground_cut.gd) and their heights stamped into the
##   heightmap (stamp(): what the trees, props, the ground the game reads stand on), its repairs terraformed
##   (terraform_zones(): builder/terraform.gd);
## - its zones' materials in the ground the game reads (lay(): builder/ground_bake.gd);
## - drawn (draw()): each zone on its heights in the toy ground's material (its own or the map's there), in SQUARE m
##   squares; where it meets the map's ground no further than its "snap" m apart, its edge comes onto the map's ground;
##   where it meets its neighbour (another zone, or the map's ground further) more than CLIFF m apart, a wall between
##   them, in its "wall" material, its 2 m cells cliffs in the ground the game reads (no grass on them); all of it
##   collides (exact faces). The materials it brings (its "palette": the railway's ballast) join the map's.
## Map coordinates x east, y north; Godot (x, z, -y).

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const SQUARE := 2.0                         # m: a zone drawn in squares so (it follows its heights)
const CLIFF := 0.02                         # m: two grounds further apart than this meet with a wall
const WALL_STEP := 2.0                      # m: outlines cut so
const OUT := 0.05                           # m outside an outline where its neighbour is looked for
const BUCKET := 64.0                        # m: the zones' index (their polygons cut into such tiles)
const EDGE_BAND := 4.0                      # m: their edges by band of y (rows' spans)
const CHUNK := 64.0                         # m: the meshes and collision shapes cut so
const ON_EDGE := 0.001                      # m: a point this close to a zone's outline is on it
const PORTAL_NEAR := 0.35                   # m: a wall this close to a zone's portal is under it
const GROUND_BUILDER := "res://scripts/builder/ground_builder.gd"   # (its MATERIALS: the toy ground shader's ids)

static var _cache := {}

var dir := ""
var cell := 1.0
var tile := 16
var zones: Array = []                       # {id, kind, material, piece, owned, wall, snap, portals: [[a, b, z open]...],
											#  polys: [[outer, holes...]...], box, tiles}
var palette := {}                           # material -> colour: those it brings
var repairs: Array = []                     # {id, ring, grid: [x0, y0, w, h, z min, offset]}
var _data := PackedByteArray()              # the heights (u16, mm over their grid's lowest)
var _n := 17
var _index := {}                            # Vector2i bucket -> [[zone index, outers, holes]...]: its pieces there
var _edges: Array = []                      # per zone: {band (int): PackedFloat32Array [ax, ay, bx, by...]}


## The lot ground in `path` (data/<lot>/, or its ground.json), read once.
static func of(path: String) -> RefCounted:
	var d := path if path.ends_with("/") else path.get_base_dir() + "/"
	if not _cache.has(d):
		_cache[d] = load("res://scripts/builder/lot_ground.gd").new(d)
	return _cache[d]


func _init(d: String) -> void:
	dir = d
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(d + "ground.json"))
	cell = float(index["cell"])
	tile = int(index["tile"])
	_n = tile + 1
	_data = FileAccess.get_file_as_bytes(d + str(index["file"])).decompress(int(index["raw"]), FileAccess.COMPRESSION_DEFLATE)
	for z: Dictionary in index["zones"]:
		var polys := []
		var outer := PackedVector2Array()
		for pg: Array in z["polygons"]:
			var rings: Array = pg.map(func(r: Array) -> PackedVector2Array: return _ring(r))
			polys.append(rings)
			outer.append_array(rings[0])
		var box := Rect2(outer[0], Vector2.ZERO)
		for q in outer:
			box = box.expand(q)
		var tiles := {}
		for t: Array in z["tiles"]:
			tiles[Vector2i(int(t[0]), int(t[1]))] = [float(t[2]), int(t[3])]
		zones.append({"id": str(z["id"]), "kind": str(z["kind"]), "material": _str(z.get("material")),
				"piece": _str(z.get("piece")), "owned": bool(z["owned"]), "wall": str(z.get("wall", "concrete")),
				"snap": float(z.get("snap", 0.0)), "polys": polys, "box": box, "tiles": tiles,
				"portals": (z.get("portals", []) as Array).map(func(p: Dictionary) -> Array:
					return [Vector2(p["a"][0], p["a"][1]), Vector2(p["b"][0], p["b"][1]), float(p["z_open"])])})
		var k := zones.size() - 1
		for rings: Array in polys:
			var pieces := tile_pieces(rings, BUCKET)
			for key: Vector2i in pieces:
				if not _index.has(key):
					_index[key] = []
				_index[key].append([k, pieces[key][0], pieces[key][1]])
		_edges.append(_edge_table(polys))
	for r: Dictionary in index["repairs"]:
		repairs.append({"id": str(r["id"]), "ring": _ring(r["ring"]), "grid": r["grid"]})
	palette = index.get("palette", {})


static func _str(v: Variant) -> String:
	return "" if v == null else str(v)


static func _ring(r: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in r:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


# ---------------------------------------------------------------- heights, zones

## Zone z's height at map point p (its grids reach MARGIN m round it; NAN beyond).
func height(z: Dictionary, p: Vector2) -> float:
	var side := tile * cell
	var key := Vector2i(floori(p.x / side), floori(p.y / side))
	var tiles: Dictionary = z["tiles"]
	if not tiles.has(key):                          # (on a tile's edge: the one beside)
		for k: Vector2i in [key - Vector2i(1, 0), key - Vector2i(0, 1), key - Vector2i(1, 1)]:
			if tiles.has(k) and p.x <= (k.x + 1) * side + 1e-6 and p.y >= k.y * side - 1e-6:
				key = k
				break
		if not tiles.has(key):
			return NAN
	var t: Array = tiles[key]
	var fx := clampf((p.x - key.x * side) / cell, 0.0, tile)
	var fy := clampf(((key.y + 1) * side - p.y) / cell, 0.0, tile)
	var i := mini(floori(fx), tile - 1)
	var j := mini(floori(fy), tile - 1)
	var u := fx - i
	var v := fy - j
	var o: int = t[1] + (j * _n + i) * 2
	var z00 := _data.decode_u16(o)
	var z10 := _data.decode_u16(o + 2)
	var z01 := _data.decode_u16(o + _n * 2)
	var z11 := _data.decode_u16(o + _n * 2 + 2)
	return float(t[0]) + 0.001 * lerpf(lerpf(z00, z10, u), lerpf(z01, z11, u), v)


## Whether map point p is in zone k (in one of its polygons, out of their holes).
func inside(k: int, p: Vector2) -> bool:
	for e: Array in _index.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)), []):
		if e[0] == k and _in_piece(p, e):
			return true
	return false


## The zone at map point p (its index; -1 none); `owned_only`: of the owned ones.
func zone_at(p: Vector2, owned_only := true) -> int:
	for e: Array in _index.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)), []):
		if (not owned_only or zones[e[0]]["owned"]) and _in_piece(p, e):
			return e[0]
	return -1


static func _in_piece(p: Vector2, e: Array) -> bool:
	if not (e[1] as Array).any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, o)):
		return false
	return not (e[2] as Array).any(func(h: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, h))


## A polygon ([outer, holes...]) cut into `side` m tiles: {Vector2i tile: [outer pieces, hole pieces]}.
static func tile_pieces(rings: Array, side: float) -> Dictionary:
	var outer: PackedVector2Array = rings[0]
	var r := Rect2(outer[0], Vector2.ZERO)
	for q in outer:
		r = r.expand(q)
	var out := {}
	for tx in range(floori(r.position.x / side), floori(r.end.x / side) + 1):
		var col := PackedVector2Array([Vector2(tx * side, r.position.y - 1.0), Vector2((tx + 1) * side, r.position.y - 1.0),
				Vector2((tx + 1) * side, r.end.y + 1.0), Vector2(tx * side, r.end.y + 1.0)])
		var strips := Geometry2D.intersect_polygons(outer, col)         # (a column first, its tiles cut from it)
		if strips.is_empty():
			continue
		var hstrips := []
		for h in range(1, rings.size()):
			hstrips.append_array(Geometry2D.intersect_polygons(rings[h], col))
		for ty in range(floori(r.position.y / side), floori(r.end.y / side) + 1):
			var sq := PackedVector2Array([Vector2(tx * side, ty * side), Vector2((tx + 1) * side, ty * side),
					Vector2((tx + 1) * side, (ty + 1) * side), Vector2(tx * side, (ty + 1) * side)])
			var outs := []
			for s: PackedVector2Array in strips:
				outs.append_array(Geometry2D.intersect_polygons(s, sq))
			if outs.is_empty():
				continue
			var holes := []
			for s: PackedVector2Array in hstrips:
				holes.append_array(Geometry2D.intersect_polygons(s, sq))
			out[Vector2i(tx, ty)] = [outs, holes]
	return out


## Zone polygons' edges by EDGE_BAND m band of y: {band: [ax, ay, bx, by...]} (the rows' spans: spans()).
static func _edge_table(polys: Array) -> Dictionary:
	var out := {}
	for rings: Array in polys:
		for r: PackedVector2Array in rings:
			for i in r.size():
				var a := r[i]
				var b := r[(i + 1) % r.size()]
				for band in range(floori(minf(a.y, b.y) / EDGE_BAND), floori(maxf(a.y, b.y) / EDGE_BAND) + 1):
					if not out.has(band):
						out[band] = PackedFloat32Array()
					out[band].append_array([a.x, a.y, b.x, b.y])
	return out


## The owned zones' polygons ([outer, holes...] each): the map's ground cut out there (builder/ground_cut.gd).
func owned() -> Array:
	var out := []
	for z: Dictionary in zones:
		if z["owned"]:
			out.append_array(z["polys"])
	return out


# ---------------------------------------------------------------- into the map

## The owned zones' heights into the heightmap (world.json "terrain" t: its 0.5 m samples inside them): what stands on
## them stands on the zone. How many samples.
func stamp(heights: PackedFloat32Array, t: Dictionary) -> int:
	var w := int(t["w"])
	var hh := int(t["h"])
	var c := float(t["cell"])
	var ox := float(t["origin_xy"][0])
	var oy := float(t["origin_xy"][1])
	var count := 0
	for k in zones.size():
		var z: Dictionary = zones[k]
		if not z["owned"]:
			continue
		var box: Rect2 = z["box"]
		var r0 := clampi(ceili((oy - box.end.y) / c), 0, hh - 1)
		var r1 := clampi(floori((oy - box.position.y) / c), 0, hh - 1)
		for r in range(r0, r1 + 1):
			var y := oy - r * c
			for span: Vector2 in spans(k, y):
				var c0 := clampi(ceili((span.x - ox) / c), 0, w - 1)
				var c1 := clampi(floori((span.y - ox) / c), 0, w - 1)
				for col in range(c0, c1 + 1):
					var hz := height(z, Vector2(ox + col * c, y))
					if not is_nan(hz):
						heights[r * w + col] = hz
						count += 1
	return count


## The x spans of row y inside zone k (even-odd over all its rings: holes out).
func spans(k: int, y: float) -> Array:
	var xs := PackedFloat32Array()
	var e: PackedFloat32Array = (_edges[k] as Dictionary).get(floori(y / EDGE_BAND), PackedFloat32Array())
	for i in range(0, e.size(), 4):
		var ay := e[i + 1]
		var by := e[i + 3]
		if (ay <= y and by > y) or (by <= y and ay > y):
			xs.append(e[i] + (y - ay) / (by - ay) * (e[i + 2] - e[i]))
	xs.sort()
	var out := []
	for i in range(0, xs.size() - 1, 2):
		out.append(Vector2(xs[i], xs[i + 1]))
	return out


## Its repairs as terraforming zones (builder/terraform.gd): the ground in each ring on its grid.
func terraform_zones() -> Array:
	var out := []
	for rp: Dictionary in repairs:
		var g: Array = rp["grid"]
		var gx0 := float(g[0])
		var gy0 := float(g[1])
		var w := int(g[2])
		var h := int(g[3])
		var wt := PackedByteArray()
		wt.resize(w * h)
		var sf := PackedFloat32Array()
		sf.resize(w * h)
		for j in h:
			for i in w:
				var k := j * w + i
				sf[k] = float(g[4]) + 0.001 * _data.decode_u16(int(g[5]) + k * 2)
				wt[k] = 255 if Geometry2D.is_point_in_polygon(Vector2(gx0 + i * cell, gy0 - j * cell), rp["ring"]) else 0
		# (terraform.gd's samples sit at their cells' middles: the grid half a cell over, on its nodes)
		out.append({"box": Rect2(gx0 - cell * 0.5, gy0 + cell * 0.5 - h * cell, w * cell, h * cell),
				"x0": gx0 - cell * 0.5, "y0": gy0 + cell * 0.5, "cell": cell, "w": w, "h": h, "wt": wt, "s": sf})
	return out


## Its zones' materials into the ground the game reads (builder/ground_bake.gd: `map`, a GroundMap being baked), row
## by row of its ids' grid inside each zone laying one; `kinds`: a material's piece kind. How many samples.
func lay(map: RefCounted, lot: String, kinds: Dictionary) -> int:
	var g: Dictionary = map.ids_grid()
	var c: float = g["cell"]
	var o: Vector2 = g["origin"]
	var made := {}
	var n := 0
	for k in zones.size():
		var z: Dictionary = zones[k]
		var mat: String = z["material"]
		if mat == "":
			continue
		var kind: String = z["piece"] if z["piece"] != "" else kinds.get(mat, "pedestrian")
		if not made.has(kind + ":" + mat):
			if palette.has(mat):
				map.add_material(mat, str(palette[mat]))
			made[kind + ":" + mat] = map.add_piece(kind, mat, "lot:" + lot)
		var box: Rect2 = z["box"]
		var r0 := clampi(ceili((o.y - box.end.y) / c), 0, int(g["h"]) - 1)
		var r1 := clampi(floori((o.y - box.position.y) / c), 0, int(g["h"]) - 1)
		for r in range(r0, r1 + 1):
			var y := o.y - r * c
			for span: Vector2 in spans(k, y):
				for col in range(clampi(ceili((span.x - o.x) / c), 0, int(g["w"]) - 1),
						clampi(floori((span.y - o.x) / c), 0, int(g["w"]) - 1) + 1):
					map.set_piece_at_sample(col, r, made[kind + ":" + mat])
					n += 1
	return n


# ---------------------------------------------------------------- drawn

## Its owned zones drawn under `root` (a node `name`), on the toy ground's material (mesh_dir/ground_material.tres),
## the map's ground there read from `gm` (GroundMap: the materials of the zones laying none), `shared` the map's ground
## round them (GroundHeights of the heightmap before stamp()): meshes and collision in CHUNK m cells.
func draw(root: Node3D, world: Dictionary, mesh_dir: String, gm: RefCounted, shared: RefCounted, name: String) -> float:
	var mats: Array = load(GROUND_BUILDER).MATERIALS
	var pal: Dictionary = (world["palette"]["ground"] as Dictionary).merged(palette)
	var chunks := {}                                # Vector2i -> [vertices, normals, colours, custom, faces]
	var lost := 0.0                                 # m² it could not draw (none expected)
	for k in zones.size():
		var z: Dictionary = zones[k]
		if not z["owned"]:
			continue
		for rings: Array in z["polys"]:
			for piece: PackedVector2Array in _squares(rings):
				var tri := triangulate(piece)
				if tri.is_empty():
					lost += absf(signed_area(piece))
				for t in range(0, tri.size() - 2, 3):
					var q := [piece[tri[t]], piece[tri[t + 1]], piece[tri[t + 2]]]
					var g := q.map(func(m: Vector2) -> Vector3: return Vector3(m.x, edge_height(k, m, shared), -m.y))
					if (g as Array).any(func(v: Vector3) -> bool: return is_nan(v.y)):
						lost += absf((q[1] - q[0]).cross(q[2] - q[0])) * 0.5
						continue
					var cols := []
					var ids := []
					for m: Vector2 in q:
						var mat: String = z["material"] if z["material"] != "" else _map_material(gm, m)
						ids.append(maxi(mats.find(mat), 0))
						cols.append(Color.html(str(pal.get(mat, pal["grass"]))))
					_tri(chunks, g[0], g[1], g[2], cols, ids, true)
			for r: PackedVector2Array in rings:              # its outline: walls where it meets another ground
				for i in r.size():
					_walls(chunks, k, r[i], r[(i + 1) % r.size()], shared, gm, mats, pal)
	var node := Node3D.new()
	node.name = name
	root.add_child(node)
	var body := StaticBody3D.new()
	body.name = name + "Collision"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "ground", "id": "lot_ground:" + name})
	root.add_child(body)
	var mat: Material = load(mesh_dir + "ground_material.tres")
	for key: Vector2i in chunks:
		var c: Array = chunks[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = c[0]
		arrays[Mesh.ARRAY_NORMAL] = c[1]
		arrays[Mesh.ARRAY_COLOR] = c[2]
		arrays[Mesh.ARRAY_CUSTOM0] = c[3]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, mat)
		var tag := "%s_%d_%d" % [name.to_lower(), key.x, key.y]
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [key.x, key.y]
		mi.mesh = MeshUtils.save(mesh, mesh_dir + "lotground_%s.res" % tag)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("plateau", {"type": "ground", "id": "lot_ground:" + tag})
		node.add_child(mi)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(c[4])
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.name = "Chunk_%d_%d" % [key.x, key.y]
		cs.shape = MeshUtils.save(shape, mesh_dir + "lotground_col_%s.res" % tag)
		body.add_child(cs)
	return lost


## The map's ground's material at map point m (the ground the game reads, `gm`), grass if none.
static func _map_material(gm: RefCounted, m: Vector2) -> String:
	var id: int = gm.material_at(m.x, m.y) if gm else -1
	return str(gm.materials[id]) if id >= 0 and id < gm.materials.size() else "grass"


## Zone k's height at map point p, but on its outline where the map's ground is beside it (`shared`) no further than
## its snap m: the map's ground's height there (its edge comes onto it).
func edge_height(k: int, p: Vector2, shared: RefCounted) -> float:
	var z: Dictionary = zones[k]
	var h := height(z, p)
	if float(z["snap"]) <= 0.0 or shared == null or is_nan(h) or not on_outline(k, p):
		return h
	var o := float(shared.at(p.x, p.y))
	if absf(o - h) > float(z["snap"]):
		return h
	for e: Vector2 in [Vector2(OUT, 0.0), Vector2(-OUT, 0.0), Vector2(0.0, OUT), Vector2(0.0, -OUT)]:
		if not inside(k, p + e) and zone_at(p + e) >= 0:
			return h                                # (another zone beside it there: their heights meet as designed)
	return o


## Whether map point p is on zone k's outline (within ON_EDGE m).
func on_outline(k: int, p: Vector2) -> bool:
	var e: PackedFloat32Array = (_edges[k] as Dictionary).get(floori(p.y / EDGE_BAND), PackedFloat32Array())
	for i in range(0, e.size(), 4):
		var a := Vector2(e[i], e[i + 1])
		var b := Vector2(e[i + 2], e[i + 3])
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= ON_EDGE:
			return true
	return false


## Where zone k's outline a -> b meets another ground more than CLIFF m apart: a wall between them (the higher side's
## draws it, or the zone when the other is the map's ground), in WALL_STEP m pieces, in its wall's material; its cells
## cliffs in `gm` (the ground the game reads, being baked).
func _walls(chunks: Dictionary, k: int, a: Vector2, b: Vector2, shared: RefCounted, gm: RefCounted, mats: Array,
		pal: Dictionary) -> void:
	var z: Dictionary = zones[k]
	var id := maxi(mats.find(z["wall"]), 0)
	var col := Color.html(str(pal.get(z["wall"], pal["concrete"])))
	var length := a.distance_to(b)
	if length < 1e-4:
		return
	var d := (b - a) / length
	var nrm := Vector2(-d.y, d.x)
	var mid := (a + b) * 0.5
	if inside(k, mid + nrm * OUT):                  # (the outward side)
		nrm = -nrm
	var other := zone_at(mid + nrm * OUT)
	var steps := maxi(1, ceili(length / WALL_STEP))
	for s in steps:
		var p0 := a + d * length * s / steps
		var p1 := a + d * length * (s + 1) / steps
		var h0 := edge_height(k, p0, shared)
		var h1 := edge_height(k, p1, shared)
		var o0 := edge_height(other, p0, shared) if other >= 0 else float(shared.at(p0.x, p0.y))
		var o1 := edge_height(other, p1, shared) if other >= 0 else float(shared.at(p1.x, p1.y))
		if is_nan(h0) or is_nan(h1) or is_nan(o0) or is_nan(o1):
			continue
		var up := h0 - o0 > CLIFF or h1 - o1 > CLIFF
		var down := o0 - h0 > CLIFF or o1 - h1 > CLIFF
		if not up and not (down and other < 0):
			continue                                    # (none, or the other zone, higher, draws it)
		var lo0 := minf(h0, o0)
		var lo1 := minf(h1, o1)
		var hi0 := maxf(h0, o0)
		var hi1 := maxf(h1, o1)
		var low := k if h0 + h1 < o0 + o1 else other     # (a portal of the lower side's: the wall above its opening)
		if low >= 0:
			for pt: Array in zones[low]["portals"]:
				if Geometry2D.get_closest_point_to_segment(p0, pt[0], pt[1]).distance_to(p0) < PORTAL_NEAR \
						and Geometry2D.get_closest_point_to_segment(p1, pt[0], pt[1]).distance_to(p1) < PORTAL_NEAR:
					lo0 = maxf(lo0, minf(pt[2], hi0))
					lo1 = maxf(lo1, minf(pt[2], hi1))
					break
		if hi0 - lo0 < CLIFF and hi1 - lo1 < CLIFF:
			continue
		var q := [Vector3(p0.x, lo0, -p0.y), Vector3(p1.x, lo1, -p1.y), Vector3(p1.x, hi1, -p1.y), Vector3(p0.x, hi0, -p0.y)]
		var cols := [col, col, col]
		var ids := [id, id, id]
		_tri(chunks, q[0], q[1], q[2], cols, ids, false)
		_tri(chunks, q[0], q[2], q[3], cols, ids, false)
		_tri(chunks, q[0], q[2], q[1], cols, ids, false)    # (both faces)
		_tri(chunks, q[0], q[3], q[2], cols, ids, false)
		if gm != null and gm.has_method("add_cliff"):     # (no grass where the ground steps)
			var n := ceili(p0.distance_to(p1) / 0.5)
			for j in n + 1:
				var c := p0.lerp(p1, float(j) / n)
				gm.add_cliff(c.x, c.y)


## A triangle into its chunk (Godot points; `up`: turned to face up, Godot's fronts being clockwise from above).
static func _tri(chunks: Dictionary, a: Vector3, b: Vector3, c: Vector3, cols: Array, ids: Array, up: bool) -> void:
	var n := (b - a).cross(c - a)
	if up and n.y > 0.0:                            # (counter-clockwise from above: turned)
		var t := b
		b = c
		c = t
		var tc: Color = cols[1]
		cols = [cols[0], cols[2], tc]
		var ti: int = ids[1]
		ids = [ids[0], ids[2], ti]
		n = -n
	var nn := -n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	if up and nn.y < 0.0:
		nn = -nn
	var m := (a + b + c) / 3.0
	var key := Vector2i(floori(m.x / CHUNK), floori(-m.z / CHUNK))
	if not chunks.has(key):
		chunks[key] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedByteArray(), PackedVector3Array()]
	var c0: Array = chunks[key]
	for i in 3:
		var v: Vector3 = [a, b, c][i]
		c0[0].append(v)
		c0[1].append(nn)
		c0[2].append(cols[i])
		c0[3].append_array(PackedByteArray([ids[i], 0, 128, 0]))
		c0[4].append(v)


## Polygons ps minus polygon cut.
static func minus_all(ps: Array, cut: PackedVector2Array) -> Array:
	var out := []
	for p: PackedVector2Array in ps:
		out.append_array(minus(p, cut))
	return out


## Polygon p minus polygon cut (its holes cut out too: a piece left with one inside is split in four first).
static func minus(p: PackedVector2Array, cut: PackedVector2Array, depth := 0) -> Array:
	var res := Geometry2D.clip_polygons(p, cut)
	if res.size() <= 1 or depth > 4 or not res.any(func(q: PackedVector2Array) -> bool:
			return Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(p)):
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
			out.append_array(minus(part, cut, depth + 1))
	return out


## A polygon ([outer, holes...]) cut into SQUARE m squares, its holes out (its BUCKET m tile pieces cut again).
static func _squares(rings: Array) -> Array:
	var out := []
	var tiles := tile_pieces(rings, BUCKET)
	var n := int(BUCKET / SQUARE)
	for key: Vector2i in tiles:
		var outs: Array = tiles[key][0]
		var holes: Array = tiles[key][1]
		for i in n:
			for j in n:
				var x0 := key.x * BUCKET + i * SQUARE
				var y0 := key.y * BUCKET + j * SQUARE
				var sq := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + SQUARE, y0), Vector2(x0 + SQUARE, y0 + SQUARE),
						Vector2(x0, y0 + SQUARE)])
				for o: PackedVector2Array in outs:
					for piece: PackedVector2Array in Geometry2D.intersect_polygons(o, sq):
						var parts: Array = [piece]
						for h: PackedVector2Array in holes:
							parts = minus_all(parts, h)
						out.append_array(parts)
	return out


## Polygon p's area, signed (counter-clockwise positive), from its first point (Vector2 is single precision: in map
## coordinates a thin piece's would be lost).
static func signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(1, p.size() - 1):
		a += (p[i] - p[0]).cross(p[i + 1] - p[0])
	return a * 0.5


## Geometry2D.triangulate_polygon() of p, on its points less its first (as for signed_area()).
static func triangulate(p: PackedVector2Array) -> PackedInt32Array:
	var local := PackedVector2Array()
	for q in p:
		local.append(q - p[0])
	return Geometry2D.triangulate_polygon(local)
