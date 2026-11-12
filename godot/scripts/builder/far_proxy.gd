extends RefCounted
## Far shapes (performance, the far half of the world's streaming: scripts/world_streamer.gd): one tool for every
## building seen from afar, the map's (builder/far_builder.gd), the railway's structures (Massy-Palaiseau, the
## Logements de l'X: their builders put them in the group GROUP) and the lots' (builder/lot_far.gd).
## Two ways, one result (the same Shapes, the same material, one mesh per cell): add_shell() for buildings already
## made of plain volumes (the map's: footprints raised in tiers), simplified as they are by vertex clustering (corners
## snapped to a SNAP m grid, the triangles that collapse dropped); add() for buildings with details, surveyed so that
## their far shape keeps their form and nothing of their details: their meshes are surveyed from above on a CELL m grid
## set square to the building (its walls' main direction), each cell a column from the ground to the highest surface
## facing up over it (heights in STEP m), or a slab under that surface where the cell is open at the ground (outside the
## walls closing the building BAND m over the ground: a canopy, a footbridge, a gallery on pillars); tops lower than LOW
## over the ground (asphalt, kerbs, paint, lawns) and anything thin and upright (louvres, frames, railings, masts) are
## gone. The columns are meshed as large rectangles: their tops and undersides merged where alike, their sides where
## they show. Colours: a top the colour of the surface over it (the mesh's vertex colour, or its material's: a texture's
## average), the walls the average of the building's facades; at night they glow with lit rooms (far_proxy.gdshader).

const GROUP := "far_proxy"                  # nodes whose meshes are one building each, streamed by far_builder.gd
const SNAP := 1.5                           # m: add_shell()'s grid
const CELL := 1.0                           # m: the survey's grid (coarser for very large buildings: MAX_CELLS)
const MAX_CELLS := 250000
const STEP := 0.5                           # m: heights rounded to it (flat roofs stay flat, pitched ones step)
const LOW := 0.6                            # m over the ground: lower tops are not part of the shape
const BAND := Vector2(2.6, 3.4)             # m over the ground: walls there close a building (doors are lower)
const OVERHANG := 2.0                       # m over the ground: an underside higher is an overhang's
const SHADER := preload("res://shaders/far_proxy.gdshader")
const DEFAULT := Color("#9a9a9a")

static var _material: ShaderMaterial
static var _colours := {}                   # Material -> its colour from afar (sRGB)


## Far shapes being made (world coordinates): add() to them, then mesh().
class Shapes:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()


## Their mesh (null if none).
static func mesh(out: Shapes) -> ArrayMesh:
	if out.v.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = out.v
	a[Mesh.ARRAY_NORMAL] = out.n
	a[Mesh.ARRAY_COLOR] = out.c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, material())
	return m


## The far shapes' material.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## The visible meshes under `node` (MeshInstance3D, global transforms) as parts for add(); nodes in the group
## `skip` (a lot's own: lot_far.gd) and their children left out.
static func parts_of(node: Node, skip := "") -> Array:
	var out := []
	_collect(node, skip, out)
	return out


static func _collect(n: Node, skip: String, out: Array) -> void:
	if (skip != "" and n.is_in_group(skip)) or (n is Node3D and not (n as Node3D).visible):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		out.append([mi.mesh, mi.global_transform if mi.is_inside_tree() else _transform(mi), mi.material_override])
	for c in n.get_children():
		_collect(c, skip, out)


static func _transform(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Adds the far shape of a building made of plain volumes (or of several) to `out`: its meshes `parts` (as for add())
## clustered on the SNAP grid, its walls in its facades' average colour.
static func add_shell(out: Shapes, parts: Array) -> void:
	var tp := PackedVector3Array()
	var tn := PackedVector3Array()
	var tc := PackedColorArray()
	for part: Array in parts:
		_triangles(part[0], part[1], part[2], tp, tn, tc)
	var snap := Vector3.ONE * SNAP
	for t in tn.size():
		var a := tp[t * 3].snapped(snap)
		var b := tp[t * 3 + 1].snapped(snap)
		var c := tp[t * 3 + 2].snapped(snap)
		if a == b or b == c or a == c or (b - a).cross(c - a).length_squared() < 1e-6:
			continue
		var n := tn[t]
		if (b - a).cross(c - a).dot(n) > 0.0:
			var sw := b
			b = c
			c = sw
		out.v.append_array(PackedVector3Array([a, b, c]))
		out.n.append_array(PackedVector3Array([n, n, n]))
		out.c.append_array(PackedColorArray([tc[t], tc[t], tc[t]]))


## Adds the far shape of one building to `out`, surveyed: its meshes `parts` ([Mesh, Transform3D (to the map), Material or
## null]), on the ground `ground` (map x, y -> height).
static func add(out: Shapes, parts: Array, ground: Callable) -> void:
	# its triangles: corners (world), facing, colour
	var tp := PackedVector3Array()
	var tn := PackedVector3Array()
	var tc := PackedColorArray()
	for part: Array in parts:
		_triangles(part[0], part[1], part[2], tp, tn, tc)
	if tp.is_empty():
		return
	# set square to its walls; the facades' average colour
	var hist := PackedFloat32Array()
	hist.resize(90)
	var wall := Color(0, 0, 0)
	var wall_area := 0.0
	for t in tn.size():
		var n := tn[t]
		if absf(n.y) < 0.3:
			var area := (tp[t * 3 + 1] - tp[t * 3]).cross(tp[t * 3 + 2] - tp[t * 3]).length() * 0.5
			hist[int(fposmod(atan2(n.x, n.z), PI * 0.5) / (PI * 0.5) * 90.0) % 90] += area
			wall += Color(tc[t].r * area, tc[t].g * area, tc[t].b * area)
			wall_area += area
	var best := 0
	var best_w := -1.0
	for b in 90:
		var w := hist[(b + 89) % 90] + hist[b] + hist[(b + 1) % 90]
		if w > best_w:
			best_w = w
			best = b
	var theta := (best + 0.5) / 90.0 * PI * 0.5
	var wall_colour := DEFAULT if wall_area <= 0.0 else Color(wall.r / wall_area, wall.g / wall_area, wall.b / wall_area)
	var to_local := Basis(Vector3.UP, -theta)
	var to_world := Basis(Vector3.UP, theta)
	var lp := PackedVector3Array()
	lp.resize(tp.size())
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in tp.size():
		var p := to_local * tp[k]
		lp[k] = p
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var cell := maxf(CELL, sqrt((hi.x - lo.x) * (hi.y - lo.y) / MAX_CELLS))
	var x0 := floorf(lo.x / cell) * cell - cell
	var z0 := floorf(lo.y / cell) * cell - cell
	var nx := int(ceilf((hi.x - x0) / cell)) + 2
	var nz := int(ceilf((hi.y - z0) / cell)) + 2
	var size := nx * nz
	# the ground under each cell
	var g := PackedFloat32Array()
	g.resize(size)
	var base := INF
	for j in nz:
		for i in nx:
			var w := to_world * Vector3(x0 + (i + 0.5) * cell, 0.0, z0 + (j + 0.5) * cell)
			g[j * nx + i] = float(ground.call(w.x, -w.z))
	# the survey: tops (facing up), undersides (facing down, over OVERHANG), walls in the BAND
	var top := PackedFloat32Array()
	top.resize(size)
	top.fill(-INF)
	var top_c := PackedColorArray()
	top_c.resize(size)
	var under := PackedFloat32Array()
	under.resize(size)
	under.fill(INF)
	var walls := PackedByteArray()
	walls.resize(size)
	for t in tn.size():
		var a := lp[t * 3]
		var b := lp[t * 3 + 1]
		var c := lp[t * 3 + 2]
		if absf(tn[t].y) >= 0.3:
			_raster(a, b, c, tn[t].y > 0.0, tc[t], x0, z0, cell, nx, nz, g, top, top_c, under)
		else:
			_wall(a, b, c, x0, z0, cell, nx, nz, g, walls)
	# open cells: reached from the edge without crossing a wall
	var open := PackedByteArray()
	open.resize(size)
	var todo := PackedInt32Array()
	for i in nx:
		todo.append_array([i, (nz - 1) * nx + i])
	for j in nz:
		todo.append_array([j * nx, j * nx + nx - 1])
	while not todo.is_empty():
		var k := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if open[k] == 1 or walls[k] == 1:
			continue
		open[k] = 1
		var i := k % nx
		var j := k / nx
		if i > 0:
			todo.append(k - 1)
		if i < nx - 1:
			todo.append(k + 1)
		if j > 0:
			todo.append(k - nx)
		if j < nz - 1:
			todo.append(k + nx)
	# the columns: [bottom, top] (NAN where none)
	var bot := PackedFloat32Array()
	bot.resize(size)
	var tops := PackedFloat32Array()
	tops.resize(size)
	for k in size:
		if top[k] == -INF or top[k] < g[k] + LOW:
			tops[k] = NAN
			continue
		base = minf(base, g[k])
	base = floorf((base - 0.5) / STEP) * STEP
	for k in size:
		if is_nan(tops[k]) or top[k] == -INF:
			tops[k] = NAN
			bot[k] = NAN
			continue
		var t := snappedf(top[k], STEP)
		var b := base
		if open[k] == 1 and under[k] < top[k] - 0.2:
			b = minf(snappedf(under[k], STEP), t - STEP)
		tops[k] = maxf(t, b + STEP)
		bot[k] = b
	var emit := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		_quad(out, to_world * a, to_world * b, to_world * c, to_world * d, to_world * n, col)
	# tops and undersides: rectangles of alike cells
	_rects(tops, top_c, nx, nz, func(i0: int, j0: int, i1: int, j1: int, h: float, col: Color) -> void:
		var xa := x0 + i0 * cell
		var xb := x0 + i1 * cell
		var za := z0 + j0 * cell
		var zb := z0 + j1 * cell
		emit.call(Vector3(xa, h, za), Vector3(xb, h, za), Vector3(xb, h, zb), Vector3(xa, h, zb), Vector3.UP, col))
	var slabs := PackedFloat32Array()
	slabs.resize(size)
	var under_c := PackedColorArray()
	under_c.resize(size)
	for k in size:
		slabs[k] = bot[k] if not is_nan(bot[k]) and bot[k] > base + 0.01 else NAN
		under_c[k] = wall_colour.darkened(0.25)
	_rects(slabs, under_c, nx, nz, func(i0: int, j0: int, i1: int, j1: int, h: float, col: Color) -> void:
		var xa := x0 + i0 * cell
		var xb := x0 + i1 * cell
		var za := z0 + j0 * cell
		var zb := z0 + j1 * cell
		emit.call(Vector3(xa, h, za), Vector3(xb, h, za), Vector3(xb, h, zb), Vector3(xa, h, zb), Vector3.DOWN, col))
	# the sides where they show: runs of alike edges along each grid line
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_sides(dir, tops, bot, nx, nz, x0, z0, cell, wall_colour, emit)


## A mesh's triangles: corners in the map, facing (their normals', or their winding's), colour (their vertex colours',
## or the material's).
static func _triangles(mesh: Mesh, xf: Transform3D, override: Material, tp: PackedVector3Array, tn: PackedVector3Array,
		tc: PackedColorArray) -> void:
	var nb := xf.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue                                  # (a primitive mesh, a box, a cylinder: triangles)
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var vn: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var vc: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var mc := _colour(override if override else mesh.surface_get_material(s))
		var count := idx.size() if not idx.is_empty() else v.size()
		for k in range(0, count - 2, 3):
			var i0 := idx[k] if not idx.is_empty() else k
			var i1 := idx[k + 1] if not idx.is_empty() else k + 1
			var i2 := idx[k + 2] if not idx.is_empty() else k + 2
			var p0 := xf * v[i0]
			var p1 := xf * v[i1]
			var p2 := xf * v[i2]
			tp.append(p0)
			tp.append(p1)
			tp.append(p2)
			var n := (nb * (vn[i0] + vn[i1] + vn[i2])).normalized() if not vn.is_empty() else (p2 - p0).cross(p1 - p0).normalized()
			tn.append(n)
			if not vc.is_empty():
				var c := (vc[i0] + vc[i1] + vc[i2]) / 3.0
				c.a = 1.0
				tc.append(c)
			else:
				tc.append(mc)


## A surface's triangle a b c (local) surveyed: the cells whose middles it covers, its height there: a top (`up`) or an
## underside (over OVERHANG).
static func _raster(a: Vector3, b: Vector3, c: Vector3, up: bool, col: Color, x0: float, z0: float, cell: float,
		nx: int, nz: int, g: PackedFloat32Array, top: PackedFloat32Array, top_c: PackedColorArray,
		under: PackedFloat32Array) -> void:
	var d := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if absf(d) < 1e-6:
		return
	var i0 := maxi(0, int(floorf((minf(a.x, minf(b.x, c.x)) - x0) / cell - 0.5)))
	var i1 := mini(nx - 1, int(ceilf((maxf(a.x, maxf(b.x, c.x)) - x0) / cell - 0.5)))
	var j0 := maxi(0, int(floorf((minf(a.z, minf(b.z, c.z)) - z0) / cell - 0.5)))
	var j1 := mini(nz - 1, int(ceilf((maxf(a.z, maxf(b.z, c.z)) - z0) / cell - 0.5)))
	for j in range(j0, j1 + 1):
		var pz := z0 + (j + 0.5) * cell
		for i in range(i0, i1 + 1):
			var px := x0 + (i + 0.5) * cell
			var u := ((b.x - px) * (c.z - pz) - (c.x - px) * (b.z - pz)) / d
			var v := ((c.x - px) * (a.z - pz) - (a.x - px) * (c.z - pz)) / d
			var w := 1.0 - u - v
			if u < -1e-4 or v < -1e-4 or w < -1e-4:
				continue
			var h := u * a.y + v * b.y + w * c.y
			var k := j * nx + i
			if up:
				if h > top[k]:
					top[k] = h
					top_c[k] = col
			elif h > g[k] + OVERHANG and h < under[k]:
				under[k] = h


## An upright triangle a b c (local): the cells along it where it stands in the BAND over the ground.
static func _wall(a: Vector3, b: Vector3, c: Vector3, x0: float, z0: float, cell: float, nx: int, nz: int,
		g: PackedFloat32Array, walls: PackedByteArray) -> void:
	var y0 := minf(a.y, minf(b.y, c.y))
	var y1 := maxf(a.y, maxf(b.y, c.y))
	var pts := [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]
	var p: Vector2 = pts[0]
	var q: Vector2 = pts[1]
	for e: Array in [[pts[0], pts[2]], [pts[1], pts[2]]]:
		if (e[0] as Vector2).distance_squared_to(e[1]) > p.distance_squared_to(q):
			p = e[0]
			q = e[1]
	var n := maxi(1, ceili(p.distance_to(q) / (cell * 0.5)))
	for s in n + 1:
		var m := p.lerp(q, float(s) / n)
		var i := int(floorf((m.x - x0) / cell))
		var j := int(floorf((m.y - z0) / cell))
		if i < 0 or j < 0 or i >= nx or j >= nz:
			continue
		var k := j * nx + i
		if y0 < g[k] + BAND.y and y1 > g[k] + BAND.x:
			walls[k] = 1


## Rectangles of cells alike (height h, colour col; NAN: none), each passed to `emit` (i0, j0, i1, j1, h, col).
static func _rects(h: PackedFloat32Array, col: PackedColorArray, nx: int, nz: int, emit: Callable) -> void:
	var done := PackedByteArray()
	done.resize(h.size())
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if done[k] == 1 or is_nan(h[k]):
				continue
			var i1 := i + 1
			while i1 < nx and done[j * nx + i1] == 0 and h[j * nx + i1] == h[k] and col[j * nx + i1] == col[k]:
				i1 += 1
			var j1 := j + 1
			while j1 < nz:
				var row := true
				for ii in range(i, i1):
					var kk := j1 * nx + ii
					if done[kk] == 1 or h[kk] != h[k] or col[kk] != col[k]:
						row = false
						break
				if not row:
					break
				j1 += 1
			for jj in range(j, j1):
				for ii in range(i, i1):
					done[jj * nx + ii] = 1
			emit.call(i, j, i1, j1, h[k], col[k])


## The columns' sides facing `dir` where they show over their neighbours', in runs along the grid lines.
static func _sides(dir: Vector2i, tops: PackedFloat32Array, bot: PackedFloat32Array, nx: int, nz: int, x0: float,
		z0: float, cell: float, col: Color, emit: Callable) -> void:
	var along_x := dir.y != 0                       # (faces facing ±z run along x)
	var lines := nz if along_x else nx
	var steps := nx if along_x else nz
	var n := Vector3(dir.x, 0.0, dir.y)
	for line in lines:
		var run_start := -1
		var run_spans := []
		for s in steps + 1:
			var spans := []
			if s < steps:
				var i := s if along_x else line
				var j := line if along_x else s
				var k := j * nx + i
				if not is_nan(tops[k]):
					var ni := i + dir.x
					var nj := j + dir.y
					var t0 := bot[k]
					var t1 := tops[k]
					if ni < 0 or nj < 0 or ni >= nx or nj >= nz or is_nan(tops[nj * nx + ni]):
						spans = [[t0, t1]]
					else:
						var o0 := bot[nj * nx + ni]
						var o1 := tops[nj * nx + ni]
						if o0 > t0:
							spans.append([t0, minf(t1, o0)])
						if t1 > o1:
							spans.append([maxf(t0, o1), t1])
			if s < steps and spans == run_spans and run_start >= 0:
				continue
			if run_start >= 0 and not run_spans.is_empty():       # (the run ends: its faces)
				var e0 := run_start
				var e1 := s
				var off := (line + (1 if (dir.x > 0 or dir.y > 0) else 0)) * cell
				for sp: Array in run_spans:
					if sp[1] - sp[0] < 0.01:
						continue
					var a: Vector3
					var b: Vector3
					if along_x:
						a = Vector3(x0 + e0 * cell, 0.0, z0 + off)
						b = Vector3(x0 + e1 * cell, 0.0, z0 + off)
					else:
						a = Vector3(x0 + off, 0.0, z0 + e0 * cell)
						b = Vector3(x0 + off, 0.0, z0 + e1 * cell)
					emit.call(Vector3(a.x, sp[0], a.z), Vector3(b.x, sp[0], b.z), Vector3(b.x, sp[1], b.z),
							Vector3(a.x, sp[1], a.z), n, col)
			run_start = s
			run_spans = spans


## A quad facing n (Godot: front faces wind clockwise seen from the front).
static func _quad(out: Shapes, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for t: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			var sw := p1
			p1 = p2
			p2 = sw
		out.v.append_array(PackedVector3Array([p0, p1, p2]))
		out.n.append_array(PackedVector3Array([n, n, n]))
		out.c.append_array(PackedColorArray([col, col, col]))


## A material's colour from afar: its albedo (times its texture's average), a shader's "colour", or grey.
static func _colour(m: Material) -> Color:
	if m == null:
		return DEFAULT
	if _colours.has(m):
		return _colours[m]
	var c := DEFAULT
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		c = s.albedo_color
		if s.albedo_texture:
			var img := s.albedo_texture.get_image()
			if img:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				img.clear_mipmaps()
				img.resize(4, 4, Image.INTERPOLATE_CUBIC)
				var sum := Color(0, 0, 0)
				for y in 4:
					for x in 4:
						sum += img.get_pixel(x, y)
				c *= Color(sum.r / 16.0, sum.g / 16.0, sum.b / 16.0)
	elif m is ShaderMaterial:
		var p: Variant = (m as ShaderMaterial).get_shader_parameter("colour")
		if p is Vector3:
			c = Color(p.x, p.y, p.z)
		elif p is Color:
			c = p
	c.a = 1.0
	_colours[m] = c
	return c
