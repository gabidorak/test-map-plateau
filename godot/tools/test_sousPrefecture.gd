extends "res://tools/test_base.gd"
## The commissariat (lot sousPrefecture, lots/sousPrefecture/), in the PTA Online test (solo, offline): no z-fighting in
## its meshes, every material known; its heliport's deck solid at its height, the police helicopter standing on it;
## the ten police cars on their bays (public vehicles), upright; its walls and glazing stopping rays (the west facade,
## the north facade, the courtyard's south face), its name on them ("Commissariat"); where the arrested are let go
## before its entrance, on the ground, out of it; the sidewalk along the boulevard KERB high, lowered at the car
## park's way out (the bateau); the lift gates' arms across that way; its ground the plan's plane (terraformed). ~1
## min. Exit 1 on failure.
##   godot --headless --fixed-fps 60 --path godot --script res://tools/test_sousPrefecture.gd -- --online-test

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Marks = preload("res://scripts/race_marks.gd")
const Plan = preload("res://lots/sousPrefecture/commissariat_plan.gd")
const Building = preload("res://lots/sousPrefecture/commissariat_builder.gd")
const Grounds = preload("res://lots/sousPrefecture/grounds_builder.gd")

const PLANE := 0.004                        # m: faces this close are in one plane
const OVERLAP := 2e-5                       # m², an overlap that flickers (0.2 cm²)
const WINDOW := 0.5                         # m: offsets compared (a normal snapped to 0.002 shifts them that much
                                            # 120 m from the frame's origin), the planes then checked exactly

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	var started := await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 90.0)
	_check(started and _main.mode_id == "online", "the PTA Online test started")
	if not started:
		quit(1)
		return
	var lot: Node = _main.sousPrefecture
	_check(lot != null and lot.building != null and lot.grounds != null, "the commissariat is in the world")
	if lot == null:
		return _finish()

	# the meshes, built again here (headless, the game draws none): no z-fighting, every material known
	var by_mat := {}
	for n: Node3D in [Building.new().build(true), Grounds.new().build(true)]:
		for c in n.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var name := str(mi.name).trim_prefix("M_").split("|")[0]
				var m: Material = mi.material_override
				_check(not (m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color == Color("#ff00ff")),
						"material %s defined" % name)
				var faces: PackedVector3Array = by_mat.get(name, PackedVector3Array())
				faces.append_array(mi.mesh.get_faces())
				by_mat[name] = faces
		n.free()
	var fights := _z_fights(by_mat)
	for f: String in fights.slice(0, 30):
		print("     " + f)
	_check(fights.is_empty(), "no z-fighting (%d coplanar overlaps)" % fights.size())

	await _frames(240)                      # (the police and the public vehicles parked)
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var frame := Plan.frame()
	var at := func(x: float, y: float, z: float) -> Vector3: return frame * Vector3(x, z, -y)
	var ray := func(from: Vector3, to: Vector3) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(from, to, Layers.BUILDINGS)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var info: Dictionary = WorldQuery.hit_info(hit).duplicate()
		info["at"] = hit["position"]
		return info
	var ours := func(info: Dictionary) -> bool: return info.get("lot", "") == "sousPrefecture"

	# the heliport's deck, the helicopter on it
	var pad := Plan.HELIPAD.get_center()
	var deck_z := Plan.FLOOR + Plan.ROOFS[2] + Plan.PAD_UP
	var hit: Dictionary = ray.call(at.call(pad.x, pad.y, 40.0), at.call(pad.x, pad.y, 0.0))
	_check(ours.call(hit) and absf(float(hit.get("at", Vector3.ZERO).y) - deck_z) < 0.05,
			"the heliport's deck at %.2f (%s)" % [float(hit.get("at", Vector3.ZERO).y), hit.get("name", "nothing")])
	_check(hit.get("name", "") == "Commissariat", "its name: Commissariat (%s)" % hit.get("name", "-"))
	var police: Node = _main.game_mode.police
	var heli: Node3D = police.heli
	var p: Vector3 = at.call(pad.x, pad.y, deck_z)
	_check(heli != null and Vector2(heli.global_position.x - p.x, heli.global_position.z - p.z).length() < 1.5
			and absf(heli.global_position.y - p.y) < 0.6 and heli.on_ground,
			"the police helicopter stands on the heliport (%s)" % (heli.global_position if heli else "none"))

	# the police cars on their bays
	var pub: Node = _main.game_mode.public_vehicles
	var parked := 0
	for b: Array in Plan.bays():
		var k := Plan.bays().find(b) + 1
		var car: Node3D = pub._cars.get("commissariat-%d" % k)
		var c: Vector2 = b[1]
		var want: Vector3 = at.call(c.x, c.y, Plan.height(c))
		if car and Vector2(car.global_position.x - want.x, car.global_position.z - want.z).length() < 1.0 \
				and car.global_basis.y.y > 0.97 and absf(car.global_position.y - want.y) < 1.0:
			parked += 1
	_check(parked == 10, "ten police cars on their bays, upright (%d)" % parked)
	_check(pub.is_public(pub._cars.get("commissariat-1").net_id) or not _main.net.active,
			"they are public (anyone may take them)")

	# walls and glazing stop rays
	for r: Array in [[Vector3(-6, 80, 1.0), Vector3(5, 80, 1.0), "the west facade"],
			[Vector3(-6, 98, 1.0), Vector3(5, 98, 1.0), "the entrance's glazing"],
			[Vector3(15, 118, 2.0), Vector3(15, 100, 2.0), "the north facade's glazing"],
			[Vector3(10, 45, 1.5), Vector3(10, 70, 1.5), "the courtyard's south face"],
			[Vector3(-6, 30, 0.5), Vector3(5, 30, 0.5), "the courtyard's west wall"],
			[Vector3(60, 60, 1.0), Vector3(15, 60, 1.0), "the east facade"]]:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var info: Dictionary = ray.call(at.call(a.x, a.y, Plan.FLOOR + a.z), at.call(b.x, b.y, Plan.FLOOR + b.z))
		_check(ours.call(info), "%s stops a ray (%s)" % [r[2], info.get("name", "nothing")])

	# the arrested are let go before the entrance, on the ground, out of the building
	var rel: Vector3 = police.release.origin
	var local := Plan.to_local(Vector2(rel.x, -rel.z))
	_check(local.x < -0.5 and local.x > -4.0 and local.y > Plan.ENTRANCE.x and local.y < Plan.ENTRANCE.y,
			"let go before the entrance (local %s)" % local)
	_check(absf(rel.y - Marks.ground(rel.x, -rel.z)) < 0.2, "on the ground there")

	# the sidewalk: KERB high, lowered across the car park's way out (the bateau)
	var gate_y := (Plan.BAYS_S.y + Plan.BAYS_N.x) * 0.5
	for s: Array in [[Vector2(-2.0, 50.0), Plan.KERB, "the sidewalk along the facade"],
			[Vector2(-2.0, 98.0), Plan.KERB, "the sidewalk before the entrance"],
			[Vector2(-2.0, gate_y), Plan.LOW, "the bateau at the car park's way out"]]:
		var q: Vector2 = s[0]
		var top: Dictionary = ray.call(at.call(q.x, q.y, 5.0), at.call(q.x, q.y, -6.0))
		var want: float = Plan.height(q) + float(s[1])
		_check(ours.call(top) and absf(float(top.get("at", Vector3.ZERO).y) - want) < 0.02,
				"%s: %.2f m over the ground (%.3f)" % [s[2], float(s[1]), float(top.get("at", Vector3.ZERO).y) - Plan.height(q)])
	# the lift gates: their arms across the way out (a ray along it, at their height, hits them)
	var g_z := Plan.height(Vector2(0.5, gate_y)) + 0.04 + 0.92
	var arm := space.intersect_ray(PhysicsRayQueryParameters3D.create(at.call(-4.0, gate_y + 0.4, g_z),
			at.call(6.0, gate_y + 0.4, g_z), Layers.PROPS | Layers.BREAKABLE))
	_check(not arm.is_empty(), "the lift gates' arms across the way out")
	var along := space.intersect_ray(PhysicsRayQueryParameters3D.create(at.call(0.5, gate_y - 0.6, g_z + 2.0),
			at.call(0.5, gate_y - 0.6, g_z - 0.5), Layers.PROPS | Layers.BREAKABLE))
	_check(not along.is_empty(), "...over the middle of the way")

	# the ground: the plan's plane
	var worst := 0.0
	for q: Vector2 in [Vector2(30, 60), Vector2(20, 20), Vector2(10, 135), Vector2(45, 110), Vector2(5, 30)]:
		var m := Plan.to_map(q)
		worst = maxf(worst, absf(Marks.ground(m.x, m.y) - Plan.height(q)))
	_check(worst < 0.06, "the ground on the plan's plane (%.3f m off at most)" % worst)
	_finish()


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## The pairs of triangles of two materials facing the same way in one plane that overlap: "material A / material B at
## (x, y, z)".
static func _z_fights(by_mat: Dictionary) -> PackedStringArray:
	var groups := {}                        # snapped normal -> [[offset, i], ...]
	var all: Array = []                     # [a, b, c, material, normal]
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
			while j < g.size() and float(g[j][0]) - float(g[i][0]) < WINDOW:
				var same: bool = all[g[i][1]][3] == all[g[j][1]][3]   # (one material: drawn the same, no flicker)
				var area := 0.0 if same or not _coplanar(all[g[i][1]], all[g[j][1]]) \
						else _overlap(all[g[i][1]], all[g[j][1]])
				if area > OVERLAP:
					var ta: Array = all[g[i][1]]
					var tb: Array = all[g[j][1]]
					var c: Vector3 = (ta[0] + ta[1] + ta[2]) / 3.0
					out.append("%s / %s at (%.2f, %.2f, %.2f) facing %s: %.4f m²" % [ta[3], tb[3], c.x, -c.z, c.y,
							(ta[4] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)), area])
				j += 1
	return out


## Whether triangle tb lies in ta's plane (each corner within PLANE of it).
static func _coplanar(ta: Array, tb: Array) -> bool:
	var n: Vector3 = ta[4]
	var o := n.dot(ta[0])
	for k in 3:
		if absf(n.dot(tb[k]) - o) > PLANE:
			return false
	return true


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
	return area / maxf(absf(n[ax]), 1e-3)


static func _drop(p: Vector3, ax: int) -> Vector2:
	match ax:
		0: return Vector2(p.y, p.z)
		1: return Vector2(p.x, p.z)
		_: return Vector2(p.x, p.y)
