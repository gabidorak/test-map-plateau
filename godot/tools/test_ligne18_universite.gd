extends SceneTree
## Lot ligne18-universite (scripts/ligne18/universite/): the station meets the line's plan at its joints, as its
## collision shows (built headless, alone: rays and shapes against it): its deck's top at deck_top_z = rail_z - 0.47 at
## the zone's ends and middle, its end faces at u = +-45 (s = zone_s) exactly the line's section (in it: met at the
## face; out of it by 4 cm: nothing), the platforms' top at platform_z and their edge at |v| 4.00, the hall's floor at
## hall_z, the end supports' top at rail_z - 1.78 - 0.30; nothing of it (collision, trees, furniture) on the viaduct's
## piers' footprints (1 m round them); the doors' paving at hall_z; a walk from rue Sophie Germain and from the TCSP
## through the hall, up the flights, to each platform (floors found every 0.25 m, no step over 0.2 m, 1.9 m of head
## room, nothing in the way). Exit 1 on failure.
##   godot --headless --path godot --script res://tools/test_ligne18_universite.gd

const L18 = preload("res://scripts/ligne18/ligne18_plan.gd")
const Plan = preload("res://scripts/ligne18/universite/universite_plan.gd")
const Lot = preload("res://scripts/ligne18/universite/universite.gd")
const Station = preload("res://scripts/ligne18/universite/station_builder.gd")
const Grounds = preload("res://scripts/ligne18/universite/grounds_builder.gd")

const TOL := 0.005

var _bad := 0
var _space: PhysicsDirectSpaceState3D
var _rid: RID


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_bad += 1


## Godot point of the station's (u, v) at map height z.
func _g(u: float, v: float, z: float) -> Vector3:
	var m := Plan.to_map(Vector2(u, v))
	return Vector3(m.x, z, -m.y)


## The map height where a ray from (u, v, z0) down to z1 meets the lot (NAN: nothing).
func _down(u: float, v: float, z0: float, z1: float) -> float:
	var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(_g(u, v, z0), _g(u, v, z1)))
	return NAN if hit.is_empty() else float((hit["position"] as Vector3).y)


func _hits(from: Vector3, to: Vector3) -> bool:
	return not _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var lot: Node3D = Lot.new()
	root.add_child(lot)
	print("built in %d ms" % (Time.get_ticks_msec() - t0))
	for i in 3:
		await physics_frame
	_space = lot.get_world_3d().direct_space_state
	var st := L18.station(Plan.ID)
	var lv: Dictionary = st["levels"]
	var rail := float(lv["rail_z"])
	var deck := float(lv["deck_top_z"])
	var s0 := float(st["s"])
	_check(absf(deck - (rail - L18.RAIL_OVER_DECK)) < 0.001, "deck_top_z %.2f = rail_z %.2f - 0.47" % [deck, rail])

	# the deck's top at the zone's ends and middle
	for u: float in [-44.9, -30.0, 0.0, 30.0, 44.9]:
		for v: float in [-3.0, 3.0]:
			var z := _down(u, v, rail - 0.1, rail - 1.0)
			_check(absf(z - deck) < TOL, "deck top at u %.1f v %.1f: %.3f (%.2f)" % [u, v, z, deck])
	# its end faces: s = zone_s, the section's outline exactly
	for su: float in [-1.0, 1.0]:
		var e := su * L18.HALF_ZONE
		var at := Plan.to_map(Vector2(e, 0.0))
		var sz := s0 + e
		_check(at.distance_to(L18.at(sz, 0.0)) < 0.01 and absf(sz - float(st["zone_s"][0 if su < 0.0 else 1])) < 0.01,
				"end face at s %.1f (zone_s %s)" % [sz, st["zone_s"]])
		var sec := L18.section()
		var c := Vector2.ZERO
		for q in sec:
			c += q
		c /= sec.size()
		var in_ok := 0
		var out_ok := 0
		for q in sec:
			var inner := q + (c - q).normalized() * 0.03
			var outer := q - (c - q).normalized() * 0.04
			var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(_g(e + su * 0.3, inner.x, rail + inner.y),
					_g(e - su * 0.05, inner.x, rail + inner.y)))
			var m := Vector2(hit["position"].x, -hit["position"].z) if not hit.is_empty() else Vector2(INF, INF)
			if not hit.is_empty() and absf(Plan.to_local(m).x - e) < TOL:
				in_ok += 1
			else:
				print("     in  (v %.2f z %+.2f): %s" % [inner.x, inner.y, hit.get("position", "nothing")])
			if not _hits(_g(e + su * 0.3, outer.x, rail + outer.y), _g(e - su * 0.05, outer.x, rail + outer.y)):
				out_ok += 1
			else:
				print("     out (v %.2f z %+.2f) hits" % [outer.x, outer.y])
		_check(in_ok == sec.size() and out_ok == sec.size(), "end face u %+.0f (collision): the section's %d corners in %d/out %d" %
				[e, sec.size(), in_ok, out_ok])
	_end_meshes(rail)
	# the platforms
	var plat := float(lv["platform_z"])
	for u: float in [-29.0, 0.0, 29.0]:
		for s: float in [-1.0, 1.0]:
			var on := _down(u, s * (L18.PLATFORM_EDGE_V + 0.03), plat + 1.0, deck - 1.0)
			var off := _down(u, s * (L18.PLATFORM_EDGE_V - 0.03), plat + 1.0, deck - 1.0)
			_check(absf(on - plat) < TOL and absf(off - deck) < TOL,
					"platform at u %.0f v %+.2f: top %.3f (%.2f), beyond its edge %.3f" % [u, s * 4.0, on, plat, off])
	# the hall's floor, the end supports
	var hall := float(lv["hall_z"])
	for p: Vector2 in [Vector2(-20.0, 0.0), Vector2(25.0, -6.0), Vector2(0.0, 12.0)]:
		var z := _down(p.x, p.y, hall + 3.0, hall - 1.0)
		_check(absf(z - hall) < TOL, "hall floor at %s: %.3f (%.2f)" % [p, z, hall])
	var support := rail - L18.SOFFIT_UNDER_RAIL - L18.BEARING
	for su: float in [-1.0, 1.0]:
		for v: float in [-3.0, 3.0]:
			var z := _down(su * L18.HALF_ZONE, v, rail - L18.SOFFIT_UNDER_RAIL - 0.02, support - 2.0)
			_check(absf(z - support) < TOL, "end support u %+.0f v %+.0f: top %.3f (%.2f)" % [su * 45.0, v, z, support])
	# the doors' paving at hall_z
	for p: Vector2 in [Vector2(33.0, 0.0), Vector2(-33.0, 0.0), Vector2(0.0, 17.0)]:
		var z := Plan.height(p) + Plan.lift(p)
		_check(absf(z - hall) < TOL, "paving at the door %s: %.3f" % [p, z])
	# the viaduct's piers: clear
	for pr: Array in Plan.piers():
		var c: Vector2 = pr[0]
		if absf(c.x) > 130.0:
			continue
		var hu: float = float(pr[1]) + Plan.PIER_MARGIN
		var hv: float = float(pr[2]) + Plan.PIER_MARGIN
		var ground := Plan.height(c)
		var soffit := L18.soffit_z(float(pr[3]))
		var q := PhysicsShapeQueryParameters3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(hu * 2.0, soffit - 1.0 - ground - 0.3, hv * 2.0)
		q.shape = b
		var m := Plan.to_map(c)
		q.transform = Transform3D(Basis(Vector3.UP, float(st["heading"])), Vector3(m.x, (ground + 0.3 + soffit - 1.0) * 0.5, -m.y))
		var hits := _space.intersect_shape(q, 8)
		var things := 0
		for t: Array in Plan.trees():
			things += 1 if absf((t[0] as Vector2).x - c.x) <= hu and absf((t[0] as Vector2).y - c.y) <= hv else 0
		for p: Array in Plan.props():
			things += 1 if absf((p[1] as Vector2).x - c.x) <= hu and absf((p[1] as Vector2).y - c.y) <= hv else 0
		_check(hits.is_empty() and things == 0, "pier s %.1f (u %.1f v %.1f): %d shapes, %d trees or props on it" %
				[pr[3], c.x, c.y, hits.size(), things])
	for t: Array in Plan.trees():
		if absf((t[0] as Vector2).y) < 7.0:
			_check(false, "a tree within 7 m of the axis at %s" % t[0])
	# walks to the platforms
	var walks := {
		"west (rue Sophie Germain) to the south platform": [Vector2(59.0, 0.0), Vector2(36.0, 0.0), Vector2(20.0, 2.0),
				Vector2(-11.0, 7.5), Vector2(-11.0, 10.2), Vector2(-2.0, 10.2), Vector2(4.0, 10.2), Vector2(12.7, 10.2), Vector2(13.6, 10.2),
				Vector2(13.6, 6.5), Vector2(0.0, 6.5)],
		"east (rue Nicolas Appert) to the north platform": [Vector2(-118.0, 8.2), Vector2(-62.0, 8.2), Vector2(-36.0, 2.0),
				Vector2(-20.0, -2.0), Vector2(-11.0, -7.5), Vector2(-11.0, -10.2), Vector2(-2.0, -10.2), Vector2(4.0, -10.2), Vector2(12.7, -10.2),
				Vector2(13.6, -10.2), Vector2(13.6, -6.5), Vector2(-10.0, -6.5)],
		"south (the TCSP) to the hall": [Vector2(0.0, 27.4), Vector2(0.0, 17.0), Vector2(0.0, 14.0), Vector2(1.0, 8.0)],
	}
	for w: String in walks:
		_walk(w, walks[w])
	print("test_ligne18_universite: %s" % ("OK" if _bad == 0 else "%d FAILED" % _bad))
	quit(0 if _bad == 0 else 1)


## The deck's end faces as drawn (the station built with its meshes): the concrete's vertices on each face (u = +-45,
## over the soffit) are the line's section's corners, all of them.
func _end_meshes(rail: float) -> void:
	var b = Station.new()
	var n: Node3D = b.build(true)
	var meshes: Array[Mesh] = []
	for c in n.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("M_l18_concrete"):
			meshes.append((c as MeshInstance3D).mesh)
	var sec := L18.section()
	var hall := Plan.level("hall_z")
	for su: float in [-1.0, 1.0]:
		var found := {}
		var stray := 0
		for mesh in meshes:
			for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if absf(v.x - su * L18.HALF_ZONE) > 0.0005 or v.y + hall < rail - L18.SOFFIT_UNDER_RAIL - 0.001:
					continue
				var q := Vector2(-v.z, v.y + hall - rail)
				var k := -1
				for i in sec.size():
					if q.distance_to(sec[i]) < 0.001:
						k = i
				if k < 0:
					stray += 1
				else:
					found[k] = true
		_check(found.size() == sec.size() and stray == 0, "end face u %+.0f (mesh): %d/%d of the section's corners, %d other points" %
				[su * L18.HALF_ZONE, found.size(), sec.size(), stray])
	var tris := 0
	var mats := 0
	var g: Node3D = Grounds.new().build(true)
	for node: Node3D in [n, g]:
		for c in node.get_children():
			if c is MeshInstance3D:
				mats += 1
				for surf in (c as MeshInstance3D).mesh.get_surface_count():
					tris += (c as MeshInstance3D).mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX].size() / 3
	print("     the station and its grounds: %d meshes (one a material), %d triangles" % [mats, tris])
	n.free()
	g.free()


## A walk along the legs of `pts` (local): a floor under every 0.25 m, no step over 0.2 m, head room, nothing across.
func _walk(name: String, pts: Array) -> void:
	var prev := NAN
	var prev_p := Vector3.ZERO
	var worst := 0.0
	var fails := []
	var top := -INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / 0.25))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			var z0 := (prev if not is_nan(prev) else Plan.height(p) + 1.0) + 1.2
			var z := _down(p.x, p.y, z0, z0 - 2.5)
			if is_nan(z):
				fails.append("no floor at %s" % p)
				continue
			if not is_nan(prev):
				var step := absf(z - prev)
				worst = maxf(worst, step)
				if step > 0.2:
					fails.append("a step of %.2f m at %s" % [step, p])
				var here := _g(p.x, p.y, z + 0.5)
				if _hits(prev_p, here):
					fails.append("something in the way at %s" % p)
			if _hits(_g(p.x, p.y, z + 0.1), _g(p.x, p.y, z + 1.9)):
				fails.append("no head room at %s (floor %.2f)" % [p, z])
			prev = z
			prev_p = _g(p.x, p.y, z + 0.5)
			top = maxf(top, z)
	for f: String in fails.slice(0, 6):
		print("     " + f)
	_check(fails.is_empty(), "walk %s: up to %.2f, steps at most %.2f m" % [name, top, worst])
