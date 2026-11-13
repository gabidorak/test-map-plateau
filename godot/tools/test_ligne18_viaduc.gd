extends "res://tools/test_base.gd"
## Lot ligne18-viaduc (scripts/ligne18/viaduc/) against the line's master plan (ligne18_plan.gd): its joints with the
## stations' lots and the ground. Every cell built with its meshes (headless: the builder's, not the game's), then:
## the deck's top at rail_z - RAIL_OVER_DECK (rays on its collision), none over the stations' zones, its end faces at
## exactly zone_s (and s_edge) with section()'s outline, the piers' heads at soffit - BEARING (rays) and their feet
## under the game's ground, the rails at rail_z and unbroken through the zones, the cells; drop() on a small world.
## Exit 1 on failure.
##   godot --headless --path godot --script res://tools/test_ligne18_viaduc.gd

const Plan = preload("res://scripts/ligne18/ligne18_plan.gd")
const Layout = preload("res://scripts/ligne18/viaduc/viaduc_layout.gd")
const Builder = preload("res://scripts/ligne18/viaduc/viaduc_builder.gd")
const Lot = preload("res://scripts/ligne18/viaduc/ligne18_viaduc.gd")
const Layers = preload("res://scripts/physics_layers.gd")

var _failures: PackedStringArray = []
var _cells: Array[Node3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var b := Builder.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var tris := 0
	var per := {}
	for k in Layout.cell_count():
		var c := b.build_cell(k, true)
		holder.add_child(c)
		_cells.append(c)
	print("%d cells' collision in %d ms (the ground map read too)" % [_cells.size(), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	for k in _cells.size():
		for mi: MeshInstance3D in Builder.fill(_cells[k], b.mesh_arrays(k)):
			var n: int = mi.mesh.surface_get_array_len(0) / 3
			tris += n
			per[mi.name] = per.get(mi.name, 0) + n
	print("their meshes in %d ms: %d triangles near %s" % [Time.get_ticks_msec() - t0, tris, per])
	t0 = Time.get_ticks_msec()
	b.build_cell(5, false)
	print("a cell headless (collision only): %d ms" % (Time.get_ticks_msec() - t0))
	for i in 3:
		await physics_frame
	_check_cells()
	_check_deck_top()
	_check_ends()
	_check_piers(b)
	_check_rails()
	_check_drop()
	print("test_ligne18_viaduc: %s" % ("OK" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.BUILDINGS)
	return root.get_world_3d().direct_space_state.intersect_ray(q)


## The cells: contiguous from s_start to s_edge, each with near meshes, a far shape, its collision, streamed alone.
func _check_cells() -> void:
	var n := Layout.cell_count()
	_check(n == _cells.size() and n >= 20 and n <= 35, "%d cells of about %.0f m" % [n, Layout.CELL])
	var r0: Vector2 = _cells[0].get_meta("s")
	var r1: Vector2 = _cells[n - 1].get_meta("s")
	var joined := true
	for k in range(1, n):
		joined = joined and (_cells[k].get_meta("s") as Vector2).x == (_cells[k - 1].get_meta("s") as Vector2).y
	_check(joined and r0.x == Layout.s_start() and r1.y == Layout.s_edge(),
			"cells from s %.1f to %.1f, joined" % [r0.x, r1.y])
	var whole := true
	var longest := 0.0
	for c in _cells:
		var r: Vector2 = c.get_meta("s")
		longest = maxf(longest, r.y - r.x)
		whole = whole and not (c.get_meta("near", []) as Array).is_empty() and c.get_meta("far", null) != null \
				and c.get_node_or_null("Collision") != null and c.is_in_group(Builder.OWN_VISIBILITY)
	_check(whole, "each cell: near meshes, its far shape, its collision, its own visibility, a streaming box round them")
	_check(longest < 320.0, "the longest cell %.0f m" % longest)


## The deck's top face at rail_z - 0.47 (rays at v +-4.0, between the plinths and the troughs); nothing of ours there
## over the stations' zones.
func _check_deck_top() -> void:
	var worst := 0.0
	var count := 0
	for s: float in [3660.0, 3900.0, 4250.0, 4590.0, 4605.0, 4700.0, 4720.0, 4824.3, 5000.0, 5500.0, 6100.0,
			6446.3, 6800.0, 6820.0, 6916.0, 6930.0, 7500.0, 8200.0, 9000.0, 9070.0]:
		for v: float in [4.0, -4.0]:
			var top := Plan.rail_z(s) - Plan.RAIL_OVER_DECK
			var hit := _ray(Plan.godot_at(s, v, top + 3.0), Plan.godot_at(s, v, top - 3.0))
			if hit.is_empty():
				_check(false, "the deck at s %.1f v %.1f" % [s, v])
				continue
			worst = maxf(worst, absf(hit["position"].y - top))
			count += 1
	_check(worst < 0.002, "the deck's top at rail_z - 0.47 (%d rays, off %.4f m at most)" % [count, worst])
	# its soffit at rail_z - 1.78 on the axis (mid-span, away from the ribs: rays up)
	worst = 0.0
	for s: float in [3700.0, 5000.0, 7000.0]:
		var so := Plan.soffit_z(s)
		var hit := _ray(Plan.godot_at(s, 0.0, so - 3.0), Plan.godot_at(s, 0.0, so + 0.5))
		worst = maxf(worst, absf(hit["position"].y - so) if not hit.is_empty() else 9.0)
	_check(worst < 0.002, "the soffit at rail_z - 1.78 on the axis (off %.4f m)" % worst)
	var over := []
	for z: Vector2 in Layout.zones():
		for s: float in [z.x + 0.05, (z.x + z.y) * 0.5, z.y - 0.05]:
			for v: float in [4.0, -4.0, 0.0, 4.9]:
				var hit := _ray(Plan.godot_at(s, v, Plan.rail_z(s) + 3.0), Plan.godot_at(s, v, Plan.rail_z(s) - 8.0))
				if not hit.is_empty():
					over.append("s %.2f v %.1f" % [s, v])
	_check(over.is_empty(), "nothing of the viaduct's over the stations' zones but the tracks %s" % [over])


## The deck's end faces: at exactly zone_s on each side of each zone, and at s_edge, each section()'s outline.
func _check_ends() -> void:
	var sec := {}
	for q in Plan.section():
		sec[Vector2i(roundi(q.x * 1000.0), roundi(q.y * 1000.0))] = true
	var ends := []
	for z: Vector2 in Layout.zones():
		ends.append_array([z.x, z.y])
	ends.append(Layout.s_edge())
	var pieces := Layout.pieces()
	for s: float in ends:
		var at := pieces.filter(func(p: Dictionary) -> bool: return p["s0"] == s or p["s1"] == s)
		_check(at.size() == 1, "a deck piece ends at exactly s %.1f" % s)
		var c := _cells[Layout.cell_of(s - 0.01 if s == Layout.s_edge() else s)]
		var got := {}
		var f := Builder.frame_at(s)
		var cells := [c] if s == Layout.s_edge() else [_cells[Layout.cell_of(s - 0.5)], _cells[Layout.cell_of(s + 0.5)]]
		for cc: Node3D in cells:
			for mi: MeshInstance3D in cc.get_meta("near", []):
				if not (mi.name in ["M_concrete", "M_walkway", "M_coffer"]):
					continue
				var arr := mi.mesh.surface_get_arrays(0)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in vs.size():
					var d := vs[i] - f.o
					if absf(d.dot(f.t)) > 0.001 or d.length() > 6.0 or absf(ns[i].dot(f.t)) < 0.99:
						continue                                # (the end faces' corners only)
					var v := d.dot(f.l)
					if absf(v) > Plan.DECK_HALF + 0.001:
						continue                                # (the fascias, beyond the outline)
					got[Vector2i(roundi(v * 1000.0), roundi(d.y * 1000.0))] = true
		var extra := got.keys().filter(func(k: Vector2i) -> bool: return not sec.has(k))
		var missing := sec.keys().filter(func(k: Vector2i) -> bool: return not got.has(k))
		_check(extra.is_empty() and missing.is_empty(), "the end face at s %.1f is section()'s outline (%d points%s%s)" % [
				s, got.size(), " extra %s" % [extra] if not extra.is_empty() else "",
				" missing %s" % [missing] if not missing.is_empty() else ""])


## The piers: as many as the plan's, heads at soffit - 0.30 (rays down from under the deck), feet 1 m under the game's
## ground at every shaft's edge.
func _check_piers(b: Builder) -> void:
	var built: Array = []
	for c in _cells:
		built.append_array(c.get_meta("piers", []))
	_check(built.size() == Plan.piers().size(), "%d piers built (the plan's %d)" % [built.size(), Plan.piers().size()])
	var worst_head := 0.0
	var worst_plan := 0.0
	var worst_ray := 0.0
	var feet_ok := true
	var by_s := {}
	for p: Dictionary in Plan.piers():
		by_s[float(p["s"])] = p
	for q: Dictionary in built:
		var p: Dictionary = by_s[q["s"]]
		var soffit := Plan.soffit_z(q["s"])
		worst_head = maxf(worst_head, absf(q["top"] - (soffit - Plan.BEARING)))
		worst_plan = maxf(worst_plan, absf(soffit - float(p["soffit_z"])))
		if q["type"] == "abutment":
			continue
		for m: Vector2 in q["shafts"]:
			var hit := _ray(Vector3(m.x, soffit - 0.05, -m.y), Vector3(m.x, soffit - 3.0, -m.y))
			worst_ray = maxf(worst_ray, absf(hit["position"].y - q["top"]) if not hit.is_empty() else 9.0)
			var lm := Layout.pier_local(p, m)
			var axes: Vector2 = Layout.SHAFT if q["type"] == "double" else Layout.SHAFT_SINGLE
			for k in 16:
				var a := TAU * k / 16.0
				var e := Layout.pier_map(p, lm + Vector2(axes.x * cos(a), axes.y * sin(a)))
				if q["bottom"] > Builder.ground(e.x, e.y) - 0.99:
					feet_ok = false
					print("  pier %.1f: its foot %.2f, the ground %.2f at %s" % [q["s"], q["bottom"], Builder.ground(e.x, e.y), e])
	_check(worst_head < 0.001 and worst_plan < 0.011, ("the piers' heads at the deck's soffit (rail_z - 1.78) - 0.30 " +
			"(off %.4f m at most; the plan's soffit_z %.4f m off it)") % [worst_head, worst_plan])
	_check(worst_ray < 0.002, "their tops' collision there (rays down from under the deck: off %.4f m)" % worst_ray)
	_check(feet_ok, "their feet 1 m under the game's ground all round each shaft")


## The rails: their top at rail_z, through the stations' zones unbroken (the four of them, every 5 m at most); the
## tracks' cells covering s_start .. s_edge.
func _check_rails() -> void:
	for id: String in Plan.stations_built():
		var st := Plan.station(id)
		var s0: float = st["zone_s"][0]
		var s1: float = st["zone_s"][1]
		var per_rail := {}
		var worst := 0.0
		var cells := {}
		for s in range(int(s0) - 10, int(s1) + 11, 5):
			cells[Layout.cell_of(s)] = true
		for k: int in cells:
			for mi: MeshInstance3D in _cells[k].get_meta("near", []):
				if mi.name != "M_rail_top":
					continue
				var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for p in vs:
					var uv := Plan.station_from_map(id, Vector2(p.x, -p.z))
					if uv.x < -55.0 or uv.x > 55.0:
						continue
					var s := float(st["s"]) + uv.x
					worst = maxf(worst, absf(p.y - Plan.rail_z(s)))
					var rail := roundi(uv.y / 0.5)               # (the rails' head's sides at +-2.65 +-0.7525 +-0.035)
					if not per_rail.has(rail):
						per_rail[rail] = PackedFloat64Array()
					per_rail[rail].append(s)
		var gaps := []
		for rail: int in per_rail:
			var a: PackedFloat64Array = per_rail[rail]
			a.sort()
			var gap := 0.0
			for i in range(1, a.size()):
				gap = maxf(gap, a[i] - a[i - 1])
			if a[0] > s0 - 5.0 or a[a.size() - 1] < s1 + 5.0 or gap > 5.01:
				gaps.append("%d: %.1f..%.1f gap %.2f" % [rail, a[0], a[a.size() - 1], gap])
		_check(per_rail.size() == 4 and gaps.is_empty() and worst < 0.001,
				"%s: the 4 rails through its zone s %.1f..%.1f unbroken (every 5 m), their top at rail_z (off %.4f m) %s" % [
				id, s0, s1, worst, gaps])


## drop() on a small world: trees along the line out (not further off, nor beyond s_edge), a prop on a pier's
## footprint out, one beside kept, the fence crossing pier 4254.9 cut round it.
func _check_drop() -> void:
	var t := func(s: float, v: float) -> Dictionary:
		var m := Plan.at(s, v)
		return {"id": "t%.0f_%.0f" % [s, v], "x": m.x, "y": m.y}
	var pier: Dictionary = Plan.piers().filter(func(p: Dictionary) -> bool: return absf(p["s"] - 5093.2) < 0.01)[0]
	var on := Layout.pier_map(pier, Vector2(0.5, 1.75))
	var off := Layout.pier_map(pier, Vector2(1.49, -2.95))           # (the traffic light by it: kept)
	var world := {
		"trees": [t.call(5000.0, 5.0), t.call(5000.0, -7.9), t.call(5000.0, 9.0), t.call(4650.0, 0.0), t.call(3000.0, 0.0)],
		"props": [{"id": "on", "x": on.x, "y": on.y, "kind": "bench"},
				{"id": "off", "x": off.x, "y": off.y, "kind": "traffic_light"}],
		"fences": [{"id": "fence:16", "pts": [[325.26, 471.24], [340.9, 499.43], [348.79, 536.14], [334.98, 538.5]]},
				{"id": "far", "pts": [[0.0, -500.0], [10.0, -500.0]]}],
		"hedges": [],
	}
	Lot.drop(world)
	var ids: Array = world["trees"].map(func(r: Dictionary) -> String: return r["id"])
	_check(ids == ["t5000_9", "t3000_0"], "trees out within 8 m of the axis from s_start to s_edge: kept %s" % [ids])
	ids = world["props"].map(func(r: Dictionary) -> String: return r["id"])
	_check(ids == ["off"], "a prop on a pier's shafts out, the traffic light beside them kept: %s" % [ids])
	var fences: Array = world["fences"]
	var clear := true
	for f: Dictionary in fences:
		for q: Array in f["pts"]:
			clear = clear and not Layout.on_footprint(Vector2(q[0], q[1]), Lot.FOOTPRINT_MARGIN)
	_check(fences.size() == 3 and clear, "fence:16 cut round pier 4254.9's shafts (%d runs, none on them)" % [
			fences.size() - 1])
