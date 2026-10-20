@tool
extends Node3D
## Real water (the Lac de l'X, ponds, fountain basins): world.json's water ground pieces become bodies of water, one per
## OSM source, each with a level and a bed. At build time (scripts/builder/world_builder.gd, setup) the ground under
## them is dug out (carve: the ground mesh in ground_builder.gd, the terrain collision in collision_builder.gd and the far
## ground in far_builder.gd), sloping from the shore down to the body's depth, and a see-through animated surface
## (shaders/water.gdshader) is laid at the level over the water pieces' own triangles (add_surface). At run time this
## node (the scene's "Water", registered as `current`) tells where the water is (surface_at): the player swims
## (player.gd), vehicles float a moment then fill and sink (car.gd _water_physics), the horse swims (horse.gd) and the
## jet-ski rides on it (jet_ski.gd); splash() throws up spray where something falls in.
## Level: low on the shore (SHORE_PERCENTILE of the drawn ground heights along it), so the water never hangs over its
## bank. Depth from the size of the body (OSM has no depths here): DEPTH_PER_M per metre of the square root of its area,
## MIN_DEPTH..MAX_DEPTH, reached SHELF_PER_M metres from the shore per metre of depth, the bed easing out flat.
## Coordinates: the bodies are in pipeline x (east), y (north); heights are Godot y.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const SHADER := "res://shaders/water.gdshader"
const MAX_DEPTH := 2.5                      # m
const MIN_DEPTH := 0.5
const DEPTH_PER_M := 0.1                    # m of depth per m of the square root of the area
const SHELF_PER_M := 3.0                    # m from the shore to full depth, per m of depth
const SHORE_PERCENTILE := 0.1
const SHORE_STEP := 0.5                     # m between the shore height samples
const ON_SHORE := 0.02                      # m: a point this close to the shore is on it
const BUCKET := 8.0                         # m, cells of the shore segment index (carve)
const CELL := 32.0                          # m, cells of the lookup grid (surface_at)
const SPLASH_MIN := 2.5                     # m/s into the water: smaller hits make no splash

## Per body: {"src": OSM id, "level": Godot y of the surface, "depth": m, "shelf": m, "area": m²,
## "polys": [[outer ring, hole rings...] as PackedVector2Array (pipeline x, y)], "box": Rect2}.
@export var bodies: Array = []

static var current: Variant                 # the world's water, once in the tree (null in tools without the world)

var _grid := {}                             # Vector2i lookup cell -> PackedInt32Array of body indices
var _shores := []                           # per body: {"segs": PackedVector2Array (pairs), "cells": {Vector2i: PackedInt32Array}}
var _material: ShaderMaterial
var _splashes: Array[CPUParticles3D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	current = self
	_index()


func _exit_tree() -> void:
	if current == self:
		current = null


# ---------------------------------------------------------------- build time

## Bodies from world.json's water pieces (grouped by OSM source), levels from `ground` (GroundHeights, as drawn).
func setup(world: Dictionary, ground: RefCounted) -> void:
	var by_src := {}
	for p: Dictionary in world["ground"]:
		if p["kind"] != "water":
			continue
		var src: String = p["src"][0] if not p["src"].is_empty() else "water:%d" % by_src.size()
		if not by_src.has(src):
			by_src[src] = []
		var poly := []
		for ring: Array in p["rings"]:
			var r := PackedVector2Array()
			for q: Array in ring:
				r.append(Vector2(q[0], q[1]))
			poly.append(r)
		by_src[src].append(poly)
	for src: String in by_src:
		var area := 0.0
		var shore := PackedFloat32Array()
		var box := Rect2(by_src[src][0][0][0], Vector2.ZERO)
		for poly: Array in by_src[src]:
			for k in poly.size():
				var r: PackedVector2Array = poly[k]
				area += absf(_signed_area(r)) * (1.0 if k == 0 else -1.0)
				for i in r.size():
					var a := r[i]
					var b := r[(i + 1) % r.size()]
					box = box.expand(a)
					var n := maxi(1, ceili(a.distance_to(b) / SHORE_STEP))
					for s in n:
						var q := a.lerp(b, float(s) / n)
						shore.append(ground.at(q.x, q.y))
		shore.sort()
		var depth := clampf(DEPTH_PER_M * sqrt(area), MIN_DEPTH, MAX_DEPTH)
		bodies.append({"src": src, "level": shore[int(SHORE_PERCENTILE * (shore.size() - 1))], "depth": depth,
				"shelf": depth * SHELF_PER_M, "area": area, "polys": by_src[src], "box": box})
	_index()
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER)


static func _signed_area(r: PackedVector2Array) -> float:
	var s := 0.0
	for i in r.size():
		var a := r[i]
		var b := r[(i + 1) % r.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Ground height `h` at pipeline (x, y) once the water's beds are dug: unchanged out of the water, at most the level on
## the shore, sinking to the body's depth inside.
func carve(x: float, y: float, h: float) -> float:
	var k := _body_index(x, y, ON_SHORE)
	if k < 0:
		return h
	var b: Dictionary = bodies[k]
	var lvl: float = b["level"]
	var shelf: float = b["shelf"]
	var d := _shore_distance(k, Vector2(x, y), shelf)
	if d <= ON_SHORE:
		return minf(h, lvl)
	if not _inside(b, Vector2(x, y)):
		return h
	var s := clampf(d / shelf, 0.0, 1.0)
	return minf(h, lvl) - float(b["depth"]) * s * (2.0 - s)


## True when the Godot AABB `box` reaches a body (with the shore margin): only then is carving worth it.
func touches(box: AABB) -> bool:
	var r := Rect2(box.position.x, -box.end.z, box.size.x, box.size.z).grow(ON_SHORE)
	for b: Dictionary in bodies:
		if (b["box"] as Rect2).grow(ON_SHORE).intersects(r):
			return true
	return false


## Digs the beds under one ground chunk's vertices (Godot coordinates, ground_builder.gd), their normals following.
## `ground` gives the drawn height for the normals' slopes. Returns how many vertices moved.
func carve_vertices(verts: PackedVector3Array, normals: PackedVector3Array) -> int:
	var moved := 0
	for i in verts.size():
		var v := verts[i]
		var h := carve(v.x, -v.z, v.y)
		if h == v.y:
			continue
		moved += 1
		verts[i] = Vector3(v.x, h, v.z)
		var e := 0.5
		var hx := carve(v.x + e, -v.z, v.y) - carve(v.x - e, -v.z, v.y)
		var hy := carve(v.x, -v.z + e, v.y) - carve(v.x, -v.z - e, v.y)
		# only the dug-out part of the slope: the drawn ground's own is in the old normal
		var old := normals[i]
		var n := Vector3(-hx / (2.0 * e), 1.0, hy / (2.0 * e)).normalized()
		normals[i] = n if old.y > 0.9 else (old + n).normalized()
	return moved


## The surface over one ground chunk's water triangles (`verts` already dug, `index` theirs): flat at each body's
## level, one mesh per chunk (frustum culling). Saved in `mesh_dir`.
func add_surface(chunk: String, verts: PackedVector3Array, index: PackedInt32Array, water: PackedByteArray,
		mesh_dir: String) -> void:
	var out_v := PackedVector3Array()
	var out_i := PackedInt32Array()
	var remap := {}
	for t in range(0, index.size(), 3):
		var ia := index[t]
		var ib := index[t + 1]
		var ic := index[t + 2]
		if not (water[ia] and water[ib] and water[ic]):
			continue
		var c := (verts[ia] + verts[ib] + verts[ic]) / 3.0
		var k := _body_index(c.x, -c.z, ON_SHORE)
		if k < 0:
			continue
		var lvl: float = bodies[k]["level"]
		for i in [ia, ib, ic]:
			var key := Vector3i(i, k, 0)
			if not remap.has(key):
				remap[key] = out_v.size()
				out_v.append(Vector3(verts[i].x, lvl, verts[i].z))
			out_i.append(remap[key])
	if out_i.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(out_v.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = out_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _material.resource_path == "":
		MeshUtils.save(_material, mesh_dir + "water_material.tres")
	mesh.surface_set_material(0, _material)
	MeshUtils.save(mesh, mesh_dir + "water_%s.res" % chunk)
	var mi := MeshInstance3D.new()
	mi.name = "Surface_" + chunk
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("plateau", {"type": "water", "id": "water:" + chunk})
	add_child(mi)


# ---------------------------------------------------------------- queries

## Godot y of the water surface over global `p` (its x, z), or NAN where there is no water.
static func surface_at(p: Vector3) -> float:
	if current == null or not is_instance_valid(current):
		return NAN
	return current.level_at(p.x, -p.z)


## Instance side of surface_at, pipeline (x, y).
func level_at(x: float, y: float) -> float:
	var k := _body_index(x, y, 0.0)
	return bodies[k]["level"] if k >= 0 else NAN


## How deep the water is over global `p` (surface minus `p.y`; negative above it), or NAN with no water there.
static func depth_at(p: Vector3) -> float:
	return surface_at(p) - p.y


## A spot on the water within `reach` m of global `p` with at least `room` m of water to the shore all round, in a body
## of `min_area` m² or more, as a global transform facing away from the nearest shore (the nearest such spot), or null.
func spot_near(p: Vector3, reach: float, room: float, min_area: float) -> Variant:
	var at := Vector2(p.x, -p.z)
	var best: Variant = null
	var best_d := INF
	for k in bodies.size():
		var b: Dictionary = bodies[k]
		if float(b["area"]) < min_area or not (b["box"] as Rect2).grow(reach).has_point(at):
			continue
		var box: Rect2 = (b["box"] as Rect2).intersection(Rect2(at - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))
		var step := 2.0
		for j in ceili(box.size.y / step) + 1:
			for i in ceili(box.size.x / step) + 1:
				var q := box.position + Vector2(i, j) * step
				var d := q.distance_to(at)
				if d >= best_d or d > reach or not _inside(b, q) or _shore_distance(k, q, room) < room:
					continue
				best_d = d
				best = q
	if best == null:
		return null
	var q: Vector2 = best
	var lvl := level_at(q.x, q.y)
	var away := (q - at).normalized() if q.distance_to(at) > 0.5 else Vector2(0.0, 1.0)
	var fwd := Vector3(away.x, 0.0, -away.y)
	return Transform3D(Basis.looking_at(-fwd), Vector3(q.x, lvl, -q.y))


## A burst of spray at global `p` for something hitting the water at `speed` m/s (bigger: `size` ~ its width in m).
func splash(p: Vector3, speed: float, size := 1.0) -> void:
	if speed < SPLASH_MIN or not is_inside_tree():
		return
	var s: CPUParticles3D = null
	for c in _splashes:
		if not c.emitting:
			s = c
			break
	if s == null:
		if _splashes.size() >= 6:
			return
		s = _make_splash()
		_splashes.append(s)
	var k := clampf(speed / 10.0, 0.3, 1.5)
	s.global_position = Vector3(p.x, surface_at(p), p.z)
	s.emission_box_extents = Vector3(size * 0.5, 0.05, size * 0.5)
	s.initial_velocity_min = 2.0 * k
	s.initial_velocity_max = 6.0 * k
	s.amount = 48
	s.restart()


func _make_splash() -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.name = "Splash"
	s.one_shot = true
	s.emitting = false
	s.explosiveness = 0.9
	s.lifetime = 1.2
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	s.direction = Vector3.UP
	s.spread = 35.0
	s.gravity = Vector3(0.0, -9.8, 0.0)
	s.scale_amount_min = 0.5
	s.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	s.scale_amount_curve = curve
	s.mesh = spray_mesh()
	add_child(s)
	return s


## A soft white droplet blob for spray particles (also the jet-ski's).
static func spray_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.97, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.material = mat
	return m


# ---------------------------------------------------------------- lookups

## The lookup grid and the shore segment index (from `bodies`, also after loading the scene).
func _index() -> void:
	_grid.clear()
	_shores.clear()
	for k in bodies.size():
		var b: Dictionary = bodies[k]
		var box: Rect2 = (b["box"] as Rect2).grow(ON_SHORE)
		for cy in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				_grid[key].append(k)
		_shores.append(null)                # built on first use (carve, spot_near)


func _body_index(x: float, y: float, margin: float) -> int:
	var cands: Variant = _grid.get(Vector2i(floori(x / CELL), floori(y / CELL)))
	if cands == null:
		return -1
	var q := Vector2(x, y)
	for k: int in cands:
		var b: Dictionary = bodies[k]
		if not (b["box"] as Rect2).grow(margin).has_point(q):
			continue
		if _inside(b, q) or (margin > 0.0 and _shore_distance(k, q, margin) <= margin):
			return k
	return -1


static func _inside(b: Dictionary, q: Vector2) -> bool:
	for poly: Array in b["polys"]:
		if not Geometry2D.is_point_in_polygon(q, poly[0]):
			continue
		var in_hole := false
		for h in range(1, poly.size()):
			if Geometry2D.is_point_in_polygon(q, poly[h]):
				in_hole = true
				break
		if not in_hole:
			return true
	return false


## Distance from `q` to body `k`'s shore when under `reach` (else `reach` or more).
func _shore_distance(k: int, q: Vector2, reach: float) -> float:
	var sh: Variant = _shores[k]
	if sh == null:
		sh = _shore_index(bodies[k])
		_shores[k] = sh
	var segs: PackedVector2Array = sh["segs"]
	var cell := Vector2i(floori(q.x / BUCKET), floori(q.y / BUCKET))
	var r := ceili(maxf(reach - float(sh["reach"]), 0.0) / BUCKET)   # past the indexed reach: look further
	var best := INF
	for cy in range(cell.y - r, cell.y + r + 1):
		for cx in range(cell.x - r, cell.x + r + 1):
			for s: int in sh["cells"].get(Vector2i(cx, cy), PackedInt32Array()):
				var c := Geometry2D.get_closest_point_to_segment(q, segs[s], segs[s + 1])
				best = minf(best, c.distance_to(q))
	return best


## Each shore segment listed in every BUCKET cell within the body's shelf of it.
func _shore_index(b: Dictionary) -> Dictionary:
	var segs := PackedVector2Array()
	var cells := {}
	var reach := maxf(float(b["shelf"]), ON_SHORE)
	for poly: Array in b["polys"]:
		for r: PackedVector2Array in poly:
			for i in r.size():
				var a := r[i]
				var c := r[(i + 1) % r.size()]
				var s := segs.size()
				segs.append(a)
				segs.append(c)
				var lo := Vector2(minf(a.x, c.x), minf(a.y, c.y)) - Vector2.ONE * reach
				var hi := Vector2(maxf(a.x, c.x), maxf(a.y, c.y)) + Vector2.ONE * reach
				for cy in range(floori(lo.y / BUCKET), floori(hi.y / BUCKET) + 1):
					for cx in range(floori(lo.x / BUCKET), floori(hi.x / BUCKET) + 1):
						# skip the cells of a long diagonal's box that are out of its reach
						var centre := Vector2(cx + 0.5, cy + 0.5) * BUCKET
						if Geometry2D.get_closest_point_to_segment(centre, a, c).distance_to(centre) \
								> reach + BUCKET * 0.71:
							continue
						var key := Vector2i(cx, cy)
						if not cells.has(key):
							cells[key] = PackedInt32Array()
						cells[key].append(s)
	return {"segs": segs, "cells": cells, "reach": reach}
