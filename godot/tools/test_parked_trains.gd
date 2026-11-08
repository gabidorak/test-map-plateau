extends SceneTree
## Headless checks for the RER B trains stabled in Massy-Palaiseau's yard (scripts/parked_trains.gd; world/rail.json
## yard tracks), the running trains, bot buses and cars off:
## - they exist: several trains on several garage tracks, some tracks left empty;
## - each stands on a garage yard track (not a running line), every bogie pivot on the track's rail line (plan and
##   rail level), every car between its bogies;
## - none overlaps another, none stands over another track (a switch, its fouling zone, a running line);
## - their boxes collide: a ray down onto a roof and one across a car stop on them;
## - the model's parts merge into the meshes they are drawn with.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_parked_trains.gd

const ParkedTrains = preload("res://scripts/parked_trains.gd")
const Train = preload("res://scripts/train.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const ON_RAIL := 0.05                       # m: a bogie pivot from its track's rail line (plan and level)
const OFF_TRACK := 0.35                     # m: a car's middle from the rail line (the chord's offset on a curve)
const SLACK := 0.3                          # m under the placement clearances (the tracks' sampling)

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	OS.set_environment("PLATEAU_TRAINS", "0")
	OS.set_environment("PLATEAU_BUSES", "0")
	OS.set_environment("PLATEAU_CARS", "0")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _run() -> void:
	for i in 10:
		await physics_frame
	var parked = _main.traffic.trains.get_node_or_null("Parked")
	_check(parked != null, "the parked trains' node (Traffic/Trains/Parked)")
	if parked == null:
		_end()
		return
	var rail: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/rail.json"))
	var by_id := {}
	for t: Dictionary in rail["yard"]["tracks"]:
		by_id[t["id"]] = t
	var trains: Array = parked.trains
	var tracks := {}
	var cars := 0
	for tr: Dictionary in trains:
		tracks[tr["track"]] = true
		cars += int(tr["cars"])
	_check(trains.size() >= 6 and tracks.size() >= 5, "%d trains (%d cars) on %d tracks" % [trains.size(), cars, tracks.size()])
	_check(parked.tracks_empty >= 1 and parked.tracks_empty < parked.tracks_used,
			"%d of the %d usable garage tracks left empty" % [parked.tracks_empty, parked.tracks_used])

	# on garage yard tracks, bogies on the rails, cars between them
	var lay := Train.layout()
	var b: float = absf(float(lay["cab"]["bogies"][0]))
	var bad_track: PackedStringArray = []
	var worst_bogie := 0.0
	var worst_level := 0.0
	var worst_car := 0.0
	var worst_span := 0.0
	for tr: Dictionary in trains:
		var t: Dictionary = by_id.get(tr["track"], {})
		if t.is_empty() or t.get("main", false) or t.get("rer", false) or not ParkedTrains._garage(String(t.get("ref", ""))):
			bad_track.append(tr["track"])
			continue
		var line := ParkedTrains._line(t)
		for bg: Transform3D in tr["bogies"]:
			var near := _nearest(line, bg.origin)
			worst_bogie = maxf(worst_bogie, near[0])
			worst_level = maxf(worst_level, absf(bg.origin.y - near[1]))
		var bogies: Array = tr["bogies"]
		for c in (tr["car_xf"] as Array).size():
			var xf: Transform3D = tr["car_xf"][c]
			worst_car = maxf(worst_car, _nearest(line, xf.origin)[0])
			var mid: Vector3 = ((bogies[c * 2] as Transform3D).origin + (bogies[c * 2 + 1] as Transform3D).origin) * 0.5
			worst_span = maxf(worst_span, absf(mid.distance_to(xf.origin)))
			worst_span = maxf(worst_span, absf((bogies[c * 2] as Transform3D).origin.distance_to((bogies[c * 2 + 1] as Transform3D).origin) - 2.0 * b))
	_check(bad_track.is_empty(), "every train on a garage yard track, none on a running line (%s)" % ", ".join(bad_track))
	_check(worst_bogie < ON_RAIL and worst_level < ON_RAIL,
			"every bogie pivot on its rails: %.3f m off the line, %.3f m off the rail level at most" % [worst_bogie, worst_level])
	_check(worst_car < OFF_TRACK and worst_span < 0.05,
			"every car between its bogies (%.3f m off them), on the track (%.3f m off the line)" % [worst_span, worst_car])

	# no overlap; clear of the other tracks (switches, fouling zones, running lines)
	var w: float = lay["cab"]["width"]
	var half := Vector3(w * 0.5, 2.0, (float(lay["cab"]["body"][1]) - float(lay["cab"]["body"][0])) * 0.5)
	var boxes: Array = []                   # [train index, Transform3D]
	for k in trains.size():
		for xf: Transform3D in trains[k]["car_xf"]:
			boxes.append([k, xf])
	var overlaps := 0
	for i in boxes.size():
		for j in boxes.size():
			if i == j or (boxes[i][1] as Transform3D).origin.distance_to((boxes[j][1] as Transform3D).origin) > 30.0:
				continue
			if _corners_in(boxes[i][1], boxes[j][1], half):
				overlaps += 1
	_check(overlaps == 0, "no car overlaps another (%d corners inside another car)" % overlaps)
	var grid := ParkedTrains._grid(rail, rail["yard"]["tracks"])
	var pts: PackedVector2Array = grid["pts"]
	var owner: PackedInt32Array = grid["owner"]
	var running: PackedByteArray = grid["running"]
	var ids: Array = rail["yard"]["tracks"].map(func(t): return t["id"])
	var closest := INF
	var closest_running := INF
	for tr: Dictionary in trains:
		var own: int = ids.find(tr["track"])
		for xf: Transform3D in tr["car_xf"]:
			for f in range(-6, 7):
				var p3 := xf.origin + xf.basis.z * half.z * f / 6.0
				var p := Vector2(p3.x, -p3.z)
				for j in pts.size():
					if owner[j] == own or absf(pts[j].x - p.x) > 6.0 or absf(pts[j].y - p.y) > 6.0:
						continue
					var d := p.distance_to(pts[j])
					closest = minf(closest, d)
					if running[j] == 1:
						closest_running = minf(closest_running, d)
	_check(closest >= ParkedTrains.CLEAR - SLACK, "no other track within %.1f m of a parked car's axis (closest %.2f m)" % [
			ParkedTrains.CLEAR - SLACK, closest])
	_check(closest_running >= ParkedTrains.RUN_CLEAR - SLACK, "no running line within %.1f m (closest %.2f m)" % [
			ParkedTrains.RUN_CLEAR - SLACK, closest_running])

	# collision: down onto a roof, across a car
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var xf0: Transform3D = trains[0]["car_xf"][1]
	var top := xf0.origin + Vector3.UP * 20.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, xf0.origin, Layers.SOLID))
	var roof_ok: bool = not hit.is_empty() and hit["collider"].get_parent() == parked \
			and absf(float(hit["position"].y) - (xf0.origin.y + ParkedTrains.BOX_TOP)) < 0.1
	_check(roof_ok, "a ray down stops on the roof box (%s)" % [hit.get("position", "no hit")])
	var side := xf0.origin + Vector3.UP * 1.5 + xf0.basis.x * 4.0
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(side, side - xf0.basis.x * 8.0, Layers.PICKABLE))
	_check(not hit.is_empty() and hit["collider"].get_parent() == parked
			and String(hit["collider"].get_meta("plateau", {}).get("type", "")) == "parked_train",
			"a ray across a car stops on its side (%s)" % [hit.get("collider", "no hit")])

	# the meshes it draws with (not built on a headless peer: built here)
	var parts: Dictionary = parked._parts(lay)
	var counts: PackedStringArray = []
	var all_ok := true
	for key: String in ["cab_near", "mid_near", "cab_inside", "mid_inside", "cab_far", "mid_far", "bogie"]:
		var m: Mesh = parts.get(key)
		all_ok = all_ok and m != null and m.get_surface_count() > 0
		counts.append("%s %d" % [key, m.get_surface_count() if m else 0])
	var body: Mesh = parts.get("cab_near")
	var aabb := body.get_aabb() if body else AABB()
	_check(all_ok and aabb.size.z > 25.0 and aabb.size.x > 2.7 and aabb.size.x < 3.0,
			"merged meshes, surfaces per material (%s); cab %s" % [", ".join(counts), aabb])
	_end()


func _end() -> void:
	print("%d failures" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


## [plan distance from the line, rail level at the nearest point] of Godot point g.
func _nearest(line: Dictionary, g: Vector3) -> Array:
	var p: PackedVector2Array = line["p"]
	var z: PackedFloat32Array = line["z"]
	var q := Vector2(g.x, -g.z)
	var best := [INF, 0.0]
	for i in p.size() - 1:
		var ab := p[i + 1] - p[i]
		var f := clampf((q - p[i]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := q.distance_to(p[i] + ab * f)
		if d < best[0]:
			best = [d, lerpf(z[i], z[i + 1], f)]
	return best


## True when a corner of car box a (at the body's mid height) lies inside car box b.
func _corners_in(a: Transform3D, b: Transform3D, half: Vector3) -> bool:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := a * Vector3(sx * half.x, 2.0, sz * half.z)
			var l := b.affine_inverse() * c
			if absf(l.x) < half.x and absf(l.z) < half.z and l.y > 0.0 and l.y < 4.0:
				return true
	return false
