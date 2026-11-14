extends "res://tools/test_base.gd"
## Lot ligne18-polytechnique (lots/ligne18-polytechnique/) against the line's master plan (ligne18_plan.gd): its
## joints with the viaduc lot and the ground. Its four cells built with their meshes (headless), then: the deck's top
## at rail_z - RAIL_OVER_DECK (deck_top_z) at the zone's ends and middle (rays on its collision), its end faces at
## exactly zone_s with section()'s outline (the mesh's vertices there), the platforms' top at platform_z and their edge
## at PLAT_V.x, the hall's floor at hall_z, the end supports' top at rail_z - SOFFIT_UNDER_RAIL - BEARING, nothing of
## the lot's (meshes, trees, props) on the viaduct's piers' footprints, no tree within TREE_V of the axis; the walk from
## the forecourt to a platform (rays down along it, the doors open); the terraforming; drop() on a small world.
## Exit 1 on failure.
##   godot --headless --path godot --script res://tools/test_ligne18_polytechnique.gd

const Line = preload("res://lots/ligne18/ligne18_plan.gd")
const Plan = preload("res://lots/ligne18-polytechnique/polytechnique_plan.gd")
const StationBuilder = preload("res://lots/ligne18-polytechnique/station_builder.gd")
const GroundsBuilder = preload("res://lots/ligne18-polytechnique/grounds_builder.gd")
const Lot = preload("res://lots/ligne18-polytechnique/polytechnique.gd")
const Layers = preload("res://scripts/physics_layers.gd")

var _failures: PackedStringArray = []
var _cells := {}
var _st: Dictionary
var _lv: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _run() -> void:
	_st = Line.station(Plan.ID)
	_lv = _st["levels"]
	var t0 := Time.get_ticks_msec()
	var holder := Node3D.new()
	root.add_child(holder)
	for c: String in ["Deck", "Hall", "Envelope"]:
		var b := StationBuilder.new(c)
		_cells[c] = b.call(c.to_lower(), true)
		holder.add_child(_cells[c])
	_cells["Grounds"] = GroundsBuilder.new().build(true)
	holder.add_child(_cells["Grounds"])
	var tris := {}
	for c: String in _cells:
		var n := 0
		for mi in _meshes(_cells[c]):
			n += mi.mesh.surface_get_array_len(0) / 3
		tris[c] = n
	print("cells built in %d ms: triangles %s" % [Time.get_ticks_msec() - t0, tris])
	for i in 3:
		await physics_frame
	_check_levels()
	_check_deck()
	_check_ends()
	_check_platforms()
	_check_supports()
	_check_piers()
	_check_walk()
	_check_ground()
	_check_drop()
	print("test_ligne18_polytechnique: %s" % ("OK" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.BUILDINGS)
	return root.get_world_3d().direct_space_state.intersect_ray(q)


## The station's point (u, v) at map height z, in Godot.
func _at(u: float, v: float, z: float) -> Vector3:
	var m := Line.station_to_map(Plan.ID, u, v)
	return Vector3(m.x, z, -m.y)


## The height a ray straight down from z0 to z1 at station (u, v) meets (NAN: nothing).
func _down(u: float, v: float, z0: float, z1: float) -> float:
	var hit := _ray(_at(u, v, z0), _at(u, v, z1))
	return NAN if hit.is_empty() else float(hit["position"].y)


## The plan's levels agree with the line's.
func _check_levels() -> void:
	var rz := Line.rail_z(float(_st["s"]))
	_check(absf(Plan.HALL_Z - float(_lv["hall_z"])) < 0.001 and absf(Plan.RAIL_Y + Plan.HALL_Z - rz) < 0.001
			and absf(Plan.DECK_Y + Plan.HALL_Z - float(_lv["deck_top_z"])) < 0.001
			and absf(Plan.PLAT_Y + Plan.HALL_Z - float(_lv["platform_z"])) < 0.001
			and absf(Plan.PASS_Y + Plan.HALL_Z - float(_lv["passerelle_z"])) < 0.001
			and absf(Plan.ROOF_Y + Plan.HALL_Z - float(_lv["roof_max_z"])) < 0.001,
			"levels: hall %.2f, passerelle %.2f, deck %.2f, rail %.2f, platforms %.2f, roof %.2f (the plan's)" % [
			Plan.HALL_Z, Plan.PASS_Y + Plan.HALL_Z, Plan.DECK_Y + Plan.HALL_Z, rz, Plan.PLAT_Y + Plan.HALL_Z,
			Plan.ROOF_Y + Plan.HALL_Z])
	var top := -INF
	for c: String in ["Deck", "Hall", "Envelope"]:
		for mi in _meshes(_cells[c]):
			top = maxf(top, (_cells[c].transform * mi.mesh.get_aabb()).end.y)
	_check(top <= float(_lv["roof_max_z"]) + 0.01, "the station's top %.2f (roof max %.2f, its frames' thickness)" % [
			top, float(_lv["roof_max_z"])])


## The deck's top at deck_top_z = rail_z - RAIL_OVER_DECK at the zone's ends and middle (rays on the trackbed).
func _check_deck() -> void:
	var worst := 0.0
	var n := 0
	for u: float in [-44.8, -30.0, 0.0, 30.0, 44.8]:
		for v: float in [-3.2, 3.2]:
			var s := float(_st["s"]) + u
			var want := Line.rail_z(s) - Line.RAIL_OVER_DECK
			var h := _down(u, v, want + 1.0, want - 2.0)
			if is_nan(h):
				_check(false, "the deck at u %.1f v %.1f" % [u, v])
				continue
			worst = maxf(worst, absf(h - want))
			n += 1
	_check(n == 10 and worst < 0.005 and absf(float(_lv["deck_top_z"]) - (float(_lv["rail_z"]) - 0.47)) < 0.001,
			"the deck's top at %.2f = rail %.2f - 0.47 (%d rays at the zone's ends and middle, worst %.4f m)" % [
			float(_lv["deck_top_z"]), float(_lv["rail_z"]), n, worst])


## The deck's end faces: at u = +-45 (s = zone_s), the triangles in that plane inside section()'s outline cover it
## (their area its area), their corners its points, every point of it there.
func _check_ends() -> void:
	var sec := Line.section()
	var area := 0.0
	for i in sec.size():
		area += sec[i].x * sec[(i + 1) % sec.size()].y - sec[(i + 1) % sec.size()].x * sec[i].y
	area = absf(area) * 0.5
	var cell: Node3D = _cells["Deck"]
	for su: float in [-1.0, 1.0]:
		var pts := []
		var covered := 0.0
		for mi in _meshes(cell):
			var arr := mi.mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else vs.size()
			for t in range(0, n, 3):
				var tri := []
				for k in 3:
					var p := vs[idx[t + k] if not idx.is_empty() else t + k]
					tri.append(p)
				if tri.any(func(p: Vector3) -> bool: return absf(p.x - su * Line.HALF_ZONE) > 0.0005):
					continue
				var q: Array = tri.map(func(p: Vector3) -> Vector2: return Vector2(-p.z, p.y - Plan.RAIL_Y))
				var c: Vector2 = (q[0] + q[1] + q[2]) / 3.0
				if not Geometry2D.is_point_in_polygon(c, sec):
					continue
				covered += absf((q[1] - q[0]).cross(q[2] - q[0])) * 0.5
				pts.append_array(q)
		var worst := 0.0
		for q: Vector2 in pts:                                # each corner on the outline's points
			var best := INF
			for s: Vector2 in sec:
				best = minf(best, q.distance_to(s))
			worst = maxf(worst, best)
		var missing := 0
		for s: Vector2 in sec:
			var best := INF
			for q: Vector2 in pts:
				best = minf(best, q.distance_to(s))
			missing += 1 if best > 0.001 else 0
		var m := cell.transform * Vector3(su * Line.HALF_ZONE, 0.0, 0.0)
		var sv := Line.project(Vector2(m.x, -m.z))
		var zone: Array = _st["zone_s"]
		var want := float(zone[1]) if su > 0.0 else float(zone[0])
		_check(absf(covered - area) < 0.001 and worst < 0.001 and missing == 0 and absf(sv.x - want) < 0.01,
				"the deck's end face at s %.2f (zone_s %.1f): %.3f m² of %.3f, its corners section()'s %d points (worst %.4f), none missing" % [
				sv.x, want, covered, area, sec.size(), worst])


## The platforms: their top at platform_z, their edge at PLAT_V.x (the trackbed just inside it).
func _check_platforms() -> void:
	var pz := float(_lv["platform_z"])
	var worst := 0.0
	var edge_ok := true
	for side: float in [1.0, -1.0]:
		for u: float in [-29.5, -12.0, 0.0, 17.0, 29.5]:
			var h := _down(u, side * 6.5, pz + 1.0, pz - 2.0)
			worst = maxf(worst, absf(h - pz)) if not is_nan(h) else INF
			var inside := _down(u, side * (Plan.PLAT_V.x + 0.03), pz + 0.5, pz - 3.0)
			var outside := _down(u, side * (Plan.PLAT_V.x - 0.03), pz + 0.5, pz - 3.0)
			edge_ok = edge_ok and absf(inside - pz) < 0.005 and absf(outside - float(_lv["deck_top_z"])) < 0.005
	_check(worst < 0.005, "the platforms' top at %.2f (worst %.4f m)" % [pz, worst])
	_check(edge_ok and Plan.PLAT_V.x == float(_st["platforms"]["edge_v"]),
			"the platforms' edge at |v| %.2f: the platform at %.2f just behind it, the trackbed at %.2f just before" % [
			Plan.PLAT_V.x, pz, float(_lv["deck_top_z"])])
	var u0: float = _st["platforms"]["u"][0]
	var u1: float = _st["platforms"]["u"][1]
	_check(u0 == -Plan.PLAT_U and u1 == Plan.PLAT_U, "the platforms u %.0f..%.0f (60 m)" % [u0, u1])


## The end supports' cross-beams: their top at rail_z - SOFFIT_UNDER_RAIL - BEARING; the hall's floor at hall_z.
func _check_supports() -> void:
	var want := float(_lv["rail_z"]) - Line.SOFFIT_UNDER_RAIL - Line.BEARING
	var worst := 0.0
	for u: float in [-45.0, 45.0]:
		for v: float in [-2.6, 2.6]:
			var h := _down(u, v, want + 0.5, want - 1.0)
			worst = maxf(worst, absf(h - want)) if not is_nan(h) else INF
	_check(worst < 0.005, "the end supports' top at %.2f = rail - 1.78 - 0.30 (worst %.4f m)" % [want, worst])
	worst = 0.0
	for p: Vector2 in [Vector2(-28.0, -3.0), Vector2(20.0, 3.0), Vector2(30.0, -12.0), Vector2(-20.0, 14.0)]:
		var h := _down(p.x, p.y, Plan.HALL_Z + 1.5, Plan.HALL_Z - 1.0)
		worst = maxf(worst, absf(h - Plan.HALL_Z)) if not is_nan(h) else INF
	_check(worst < 0.005, "the hall's floor at %.2f (worst %.4f m)" % [Plan.HALL_Z, worst])


## Nothing of the lot's on the viaduct's piers' shafts' footprints (meshes), nor trees or props within PIER_CLEAR of
## them; no tree within TREE_V of the axis.
func _check_piers() -> void:
	var feet := Plan.pier_footprints()
	var near := []
	for f: Array in feet:
		near.append(f[2])
	var hits := 0
	for c: String in _cells:
		var cell: Node3D = _cells[c]
		for mi in _meshes(cell):
			var arr := mi.mesh.surface_get_arrays(0)
			for p: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				var g := cell.transform * p
				for f: Array in feet:
					if Geometry2D.is_point_in_polygon(Vector2(g.x, -g.z), f[0]):
						hits += 1
	_check(hits == 0, "no vertex of the lot's meshes on the piers' footprints (piers s %s): %d" % [near, hits])
	var bad := 0
	var axis := 0
	for t: Array in Plan.trees():
		var m := Plan.to_map(t[0])
		bad += 1 if Plan.on_pier(m) else 0
		var sv := Line.project(m)
		axis += 1 if not is_nan(sv.y) and absf(sv.y) < Plan.TREE_V else 0
	for p: Array in Plan.props():
		bad += 1 if Plan.on_pier(Plan.to_map(p[1])) else 0
	_check(bad == 0 and axis == 0, "%d trees, %d props: none within %.0f m of a pier's shafts (%d), none within %.0f m of the axis (%d)" % [
			Plan.trees().size(), Plan.props().size(), Plan.PIER_CLEAR, bad, Plan.TREE_V, axis])
	var gm := []                                              # the far piers: in the perimeter or not
	for pr: Dictionary in Line.piers():
		if float(pr["s"]) in [4538.9, 4573.3, 4731.6, 4765.4, 4803.3, 4854.3]:
			gm.append("%.1f %s" % [float(pr["s"]), "in" if Plan.in_perimeter(Plan.to_local(Vector2(pr["x"], pr["y"]))) else "out"])
	print("     piers and the perimeter: %s" % ", ".join(gm))


## The walk from the forecourt up to a platform: rays down along it (heights as expected, none missing), the doors open.
func _check_walk() -> void:
	var y := func(h: float) -> float: return Plan.HALL_Z + h
	var route := [[Vector2(11.6, 26.0), y.call(0.0), "the forecourt before the porch"],
			[Vector2(11.6, 18.5), y.call(0.0), "the porch"], [Vector2(11.6, 14.5), y.call(0.0), "the hall"],
			[Vector2(16.4, 10.0), y.call(0.17), "flight A's foot"], [Vector2(12.35, 10.0), y.call(2.5), "flight A"],
			[Vector2(8.3, 10.0), y.call(4.83), "flight A's head"], [Vector2(1.0, 11.0), y.call(Plan.PASS_Y), "level 1"],
			[Vector2(6.0, 0.0), y.call(Plan.PASS_Y), "the passerelle"], [Vector2(1.0, -11.0), y.call(Plan.PASS_Y), "level 1 north"],
			[Vector2(-10.7, 10.0), y.call(7.7), "flight B"], [Vector2(-17.5, 11.0), y.call(Plan.PLAT_Y), "the landing"],
			[Vector2(-17.5, 6.5), y.call(Plan.PLAT_Y), "the platform"]]
	for r: Array in route:
		var p: Vector2 = r[0]
		var h := _down(p.x, p.y, float(r[1]) + 1.2, float(r[1]) - 1.5)
		_check(not is_nan(h) and absf(h - float(r[1])) < 0.2, "the walk: %s at %.2f (%s)" % [r[2], h, "%.2f" % float(r[1])])
	for d: Array in [[Vector2(11.6, 26.0), Vector2(11.6, 13.0), "the main doors"],
			[Vector2(-40.0, 1.5), Vector2(-25.0, 1.5), "the east doors"], [Vector2(40.0, -1.5), Vector2(25.0, -1.5), "the west doors"]]:
		var a: Vector2 = d[0]
		var b: Vector2 = d[1]
		var hit := _ray(_at(a.x, a.y, Plan.HALL_Z + 1.2), _at(b.x, b.y, Plan.HALL_Z + 1.2))
		_check(hit.is_empty(), "%s open" % d[2])


## The terraforming: the ground FLAT at the doors, met at the TCSP's kerb, its zone.
func _check_ground() -> void:
	var z: Dictionary = Plan.terraform_zones()[0]
	_check(int(z["w"]) * int(z["h"]) == (z["wt"] as PackedByteArray).size(), "a terraforming zone of %d x %d m" % [z["w"], z["h"]])
	var door := Plan.st_to_local(Vector2(11.6, 18.0))
	_check(absf(Plan.height(door) + 0.15 - Plan.HALL_Z) < 0.001, "the forecourt's paving at the doors at %.2f" % (Plan.height(door) + 0.15))
	var worst := 0.0
	for a in range(-76, 70, 8):
		var k := Vector2(a, Plan.kerb_b(a) - 0.05)
		worst = maxf(worst, absf(Plan.height(k) - Plan._table(Plan.SOUTH_G, -88.0, a)))
	_check(worst < 0.03, "the ground at the TCSP's kerb as the map's (worst %.3f m)" % worst)


## drop() on a small world: the station building, a tree and a prop in the perimeter out; the lot's trees and props in.
func _check_drop() -> void:
	var c := Line.station_to_map(Plan.ID, 0.0, 30.0)
	var far := Vector2(-600.0, -600.0)
	var world := {"buildings": [{"id": Plan.OSM}, {"id": "osm:w1"}], "building_signs": [], "building_modules": [],
			"trees": [{"id": "t1", "x": c.x, "y": c.y}, {"id": "t2", "x": far.x, "y": far.y}],
			"props": [{"id": "p1", "x": c.x, "y": c.y, "kind": "bench"}], "hedges": [], "kerbs": [], "fences": [],
			"markings": [], "tree_archetypes": {"round": 3, "oval": 3, "columnar": 2}}
	Lot.drop(world)
	var ids: Array = world["buildings"].map(func(b: Dictionary) -> String: return b["id"])
	var tree_ids: Array = world["trees"].map(func(t: Dictionary) -> String: return t["id"])
	_check(not Plan.OSM in ids and "osm:w1" in ids and not "t1" in tree_ids and "t2" in tree_ids
			and world["trees"].size() == 1 + Plan.trees().size() and world["props"].size() == Plan.props().size(),
			"drop(): #394 out, the map's tree and prop in it out; %d trees, %d props in" % [Plan.trees().size(), Plan.props().size()])
