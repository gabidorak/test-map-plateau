extends SceneTree
## Line 18's master plan (lots/ligne18/ligne18_plan.gd, lots/ligne18/plan.json): its frames agree.
##   godot --headless --path godot --script res://tools/test_ligne18_plan.gd

const Plan = preload("res://lots/ligne18/ligne18_plan.gd")


func _initialize() -> void:
	var bad := 0
	for id: String in Plan.stations_built():
		var st := Plan.station(id)
		var s := float(st["s"])
		var lv: Dictionary = st["levels"]
		for u: float in [-45.0, -20.0, 0.0, 30.0, 45.0]:
			var a := Plan.station_to_map(id, u, 3.0)
			var b := Plan.at(s + u, 3.0)
			var dz := absf(Plan.rail_z(s + u) - float(lv["rail_z"]))
			if a.distance_to(b) > 0.05 or dz > 0.01:
				print("%s u %.0f: frame %s, line %s (%.3f m off), rail %.3f m off" % [id, u, a, b, a.distance_to(b), dz])
				bad += 1
			var sv := Plan.project(b)
			if absf(sv.x - (s + u)) > 0.05 or absf(sv.y - 3.0) > 0.05:
				print("%s u %.0f: project %s" % [id, u, sv])
				bad += 1
		var t := Plan.station_transform(id)
		var p := t * Vector3(10.0, 0.0, -2.0)                # u 10, v 2, at the hall
		var m := Plan.station_to_map(id, 10.0, 2.0)
		if Vector2(p.x, -p.z).distance_to(m) > 0.01 or absf(p.y - float(lv["hall_z"])) > 0.001:
			print("%s: station_transform %s vs %s" % [id, p, m])
			bad += 1
		var f := Plan.frame(s)
		var q := f * Vector3(0.0, 0.0, -3.0)                 # 3 m left of the axis at the rails
		if Vector2(q.x, -q.z).distance_to(Plan.at(s, 3.0)) > 0.01:
			print("%s: frame's left %s vs %s" % [id, q, Plan.at(s, 3.0)])
			bad += 1
		print("%s: s %.1f centre %s heading %.2f° hall %.2f rail %.2f platforms %.2f" % [id, s, st["centre"],
				rad_to_deg(float(st["heading"])), lv["hall_z"], lv["rail_z"], lv["platform_z"]])
	print("section: %s" % Plan.section())
	print("piers: %d; test_ligne18_plan: %s" % [Plan.piers().size(), "OK" if bad == 0 else "%d FAILED" % bad])
	quit(0 if bad == 0 else 1)
