extends SceneTree
## All Suites Study (scripts/allsuites/), in place of building #184: no z-fighting anywhere in its meshes (no two
## triangles facing the same way overlap in one plane, within 4 mm: drawn the same, the depth test flickers between
## them), every material known; in the game (the PTA Online test) its roofs over the old footprint, its walls stopping
## rays at the street, the courtyard and the gables, its threshold and colonnades' paving solid, its ground floor over
## the ground along the street. ~1 min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_allsuites.gd -- --online-test

const Layers = preload("res://scripts/physics_layers.gd")
const Builder = preload("res://scripts/allsuites/allsuites_builder.gd")
const WorldQuery = preload("res://scripts/world_query.gd")

const PLANE := 0.004                        # m: faces this close are in one plane
const OVERLAP := 2e-5                       # m², an overlap that flickers (0.2 cm²)

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started, "the game started")
	if not started:
		quit(1)
		return
	await _frames(5)
	var res: Node = _main.allsuites
	_check(res != null and res.residence != null, "All Suites Study is in the world")
	if res == null:
		quit(1)
		return

	# the meshes, built again here (headless, the game draws none): no z-fighting, every material known
	var b := Builder.new()
	b.build(func(u: float, v: float) -> float: return res.ground_at(u, v), res.foot, true)
	var tris: Dictionary = b.triangles()
	var count := 0
	for mat: String in tris:
		count += (tris[mat] as PackedVector3Array).size() / 3
		var m: StandardMaterial3D = b._mat(mat)
		_check(m.albedo_color != Color("#ff00ff"), "material %s defined" % mat)
	print("%d triangles in %d materials" % [count, tris.size()])
	var fights := _z_fights(tris)
	for f: String in fights.slice(0, 40):
		print("     " + f)
	_check(fights.is_empty(), "no z-fighting (%d coplanar overlaps)" % fights.size())

	# in the game: what rays find
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var ours := func(from: Vector3, to: Vector3) -> Dictionary:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID))
		if hit.is_empty() or hit["collider"] == null:
			return {}
		var info: Dictionary = WorldQuery.hit_info(hit)
		info["at"] = hit["position"]
		return info
	# the roofs over the old footprint: ours, at the roof's height
	for p: Vector2 in [Vector2(10, 7), Vector2(34, 6), Vector2(60, 9), Vector2(7, 30), Vector2(60, 45), Vector2(1.2, 15.0)]:
		var info: Dictionary = ours.call(res.at(p.x, 40, p.y), res.at(p.x, -3, p.y))
		var y: float = (res.frame.affine_inverse() * info.get("at", Vector3.ZERO)).y
		_check(info.get("type", "") == "allsuites" and y > Builder.ROOF - 0.05, "its roof over %s (%s, y %.2f)" % [p,
				info.get("type", info.get("id", "nothing")), y])
	# the walls: from the street, the lane, the north, the courtyard
	for ray: Array in [[Vector3(20.0, 1.5, -6.0), Vector3(20.0, 1.5, 4.0), "the south facade's glazing"],
			[Vector3(-8.0, 1.5, 30.0), Vector3(4.0, 1.5, 30.0), "the west colonnade's glazing"],
			[Vector3(76.0, 1.5, 22.0), Vector3(62.0, 1.5, 22.0), "the east colonnade's glazing"],
			[Vector3(-8.0, 12.0, 30.0), Vector3(4.0, 12.0, 30.0), "the west sawtooth"],
			[Vector3(6.0, 8.0, 60.0), Vector3(6.0, 8.0, 44.0), "the west gable"],
			[Vector3(34.0, 1.5, 30.0), Vector3(34.0, 1.5, 10.0), "the courtyard's south side"],
			[Vector3(34.0, 9.0, 30.0), Vector3(10.0, 9.0, 30.0), "the courtyard's west side"],
			[Vector3(34.0, 9.0, -6.0), Vector3(34.0, 9.0, 4.0), "the south facade's upper floors"]]:
		var a: Vector3 = ray[0]
		var c: Vector3 = ray[1]
		var info: Dictionary = ours.call(res.at(a.x, a.y, a.z), res.at(c.x, c.y, c.z))
		_check(info.get("type", "") == "allsuites", "%s stops a ray (%s)" % [ray[2], info.get("type", info.get("id", "nothing"))])
	# the threshold and the colonnades' paving: solid, at the floor or just over the ground
	var step: Vector3 = res.at(Builder.COL - 0.17, 0.0, Builder.NORTH - Builder.TOOTH * 4.5)    # (before the west colonnade's door)
	for p: Vector2 in [Vector2(12.3, 0.17), Vector2(0.77, 30.3), Vector2(66.7, 22.2)]:
		var info: Dictionary = ours.call(res.at(p.x, 3.0, p.y), res.at(p.x, -3.0, p.y))
		_check(info.get("type", "") == "allsuites", "solid underfoot at %s (%s)" % [p, info.get("type", "nothing")])
	var info_step: Dictionary = ours.call(step + Vector3.UP * 3.0, step + Vector3.DOWN * 3.0)
	var step_y: float = (res.frame.affine_inverse() * info_step.get("at", Vector3.ZERO)).y
	_check(info_step.get("type", "") == "allsuites" and step_y > res.ground_at(Builder.COL - 0.17,
			Builder.NORTH - Builder.TOOTH * 4.5) + 0.03, "a step before the colonnade's door (headless too): y %.2f" % step_y)
	var core: Dictionary = ours.call(res.at(34, 40, 6), res.at(34, 10, 6))
	_check(core.get("type", "") == "allsuites" and (res.frame.affine_inverse() * core.get("at", Vector3.ZERO)).y > Builder.ROOF + 2.9,
			"the stair core on the roof (headless too)")
	# the ground floor over the ground along the street
	var worst := -INF
	for i in 68:
		worst = maxf(worst, res.ground_at(float(i), -0.4))
	_check(worst < 0.0, "the sidewalk under the threshold everywhere (%.2f m at most)" % worst)
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## The pairs of triangles facing the same way in one plane that overlap: "material A / material B at (x, y, z)".
static func _z_fights(by_mat: Dictionary) -> PackedStringArray:
	var groups := {}                        # snapped normal -> [[offset, i], ...]
	var all: Array = []                     # [a, b, c, material]
	for mat: String in by_mat:
		var v: PackedVector3Array = by_mat[mat]
		for k in range(0, v.size(), 3):
			var n := (v[k + 1] - v[k]).cross(v[k + 2] - v[k])
			if n.length() < 1e-6:
				continue
			n = n.normalized()
			var key := n.snapped(Vector3(0.002, 0.002, 0.002))
			if not groups.has(key):
				groups[key] = []
			groups[key].append([n.dot(v[k]), all.size()])
			all.append([v[k], v[k + 1], v[k + 2], mat, n])
	var out := PackedStringArray()
	for key: Vector3 in groups:
		var g: Array = groups[key]
		g.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for i in g.size():
			var j := i + 1
			while j < g.size() and float(g[j][0]) - float(g[i][0]) < PLANE:
				var area := _overlap(all[g[i][1]], all[g[j][1]])
				if area > OVERLAP:
					var ta: Array = all[g[i][1]]
					var tb: Array = all[g[j][1]]
					var c: Vector3 = (ta[0] + ta[1] + ta[2]) / 3.0
					out.append("%s / %s at (%.2f, %.2f, %.2f) facing %s: %.4f m²" % [ta[3], tb[3], c.x, c.y, -c.z,
							(ta[4] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)), area])
				j += 1
	return out


## The area two triangles in one plane share.
static func _overlap(ta: Array, tb: Array) -> float:
	var n: Vector3 = ta[4]
	var ax := 0
	if absf(n.y) >= absf(n.x) and absf(n.y) >= absf(n.z):
		ax = 1
	elif absf(n.z) >= absf(n.x):
		ax = 2
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for k in 3:
		pa.append(_drop(ta[k], ax))
		pb.append(_drop(tb[k], ax))
	var ra := Rect2(pa[0], Vector2.ZERO).expand(pa[1]).expand(pa[2])
	var rb := Rect2(pb[0], Vector2.ZERO).expand(pb[1]).expand(pb[2])
	if not ra.grow(-0.0005).intersects(rb.grow(-0.0005)):
		return 0.0
	var area := 0.0
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(pa, pb):
		var s := 0.0
		for k in poly.size():
			s += poly[k].cross(poly[(k + 1) % poly.size()])
		area += absf(s) * 0.5
	# (the area in the plane: the projection shrinks it by the normal's kept component)
	return area / maxf(absf(n[ax]), 1e-3)


static func _drop(p: Vector3, ax: int) -> Vector2:
	match ax:
		0: return Vector2(p.y, p.z)
		1: return Vector2(p.x, p.z)
		_: return Vector2(p.x, p.y)
