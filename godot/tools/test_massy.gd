extends SceneTree
## Headless checks of Massy-Palaiseau's station (rail.json massy, scripts/builder/massy_builder.gd). Exit code 0 when
## everything passes.
##  1. The concourse deck: a ray down onto it lands on the deck's level (le Lien, the historic footbridge, the walkway).
##  2. Clearance: between the piers under each footbridge's spine, a ray up from the ground meets nothing before the
##     deck's underside (trains, buses and players pass under).
##  3. The line 18 station: rays down find the platforms, the mezzanine and the shaft's floor at their levels.
##  4. Walking: up one of le Lien's stairs from the forecourt to the deck, down the stairs from the mezzanine to a
##     platform, up the shaft's first flight from the mezzanine.
##  5. The Atlantis bus station (rail.json massy bus_station, tools/rail/bus_station.py): rays down find its lanes on
##     their profile (flat across, no bump), the quays a bus kerb over them; the bus depot (bus_depot.py): its floor
##     flat, its ramps no steeper than 9.5 % over a metre, its sides open (rays across them under the roof meet
##     nothing: no walls).
##  6. Driving (the depot's ways, rail.json depot paths): an 18 m and a 12 m bus from a bay out down the ramp onto the
##     Massy side lane to the bus station's end, and in from the RER side lane round the turnaround up the ramp to the
##     passage lane and each lane: never stuck, never far off the path, on their wheels. (PLATEAU_TEST_ONLY=bus runs 5
##     and 6 only.)
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_massy.gd

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const BusBot = preload("res://scripts/bus_bot.gd")
const Layers = preload("res://scripts/physics_layers.gd")

var _main: Node
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _M: Dictionary
var _failures: PackedStringArray = []


func _initialize() -> void:
	var rail = JSON.parse_string(FileAccess.get_file_as_string("res://world/rail.json"))
	_M = rail["massy"]
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _ray(x: float, y: float, z_from: float, z_to: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(MeshUtils.to_godot(x, y, z_from), MeshUtils.to_godot(x, y, z_to),
			Layers.SOLID)
	var hit := _space.intersect_ray(q)
	return NAN if hit.is_empty() else float(hit["position"].y)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL ", msg)


func _run() -> void:
	for i in 5:
		await physics_frame
	_player = _main.get_node("Player")
	_space = _main.get_world_3d().direct_space_state
	if OS.get_environment("PLATEAU_TEST_ONLY") == "bus":
		await _bus_station()
		print("%d failure(s)" % _failures.size())
		quit(0 if _failures.is_empty() else 1)
		return
	var level: float = _M["level"]
	var depth: float = _M["deck_depth"]
	# 1. the deck, at the centroids of its triangles (every fifth)
	var ok := 0
	var n := 0
	for d: Dictionary in _M["deck"]:
		var verts: Array = []
		for r: Array in d["rings"]:
			verts.append_array(r)
		var t: Array = d["tris"]
		for k in range(0, t.size() - 2, 15):
			var c := (_v(verts[t[k]]) + _v(verts[t[k + 1]]) + _v(verts[t[k + 2]])) / 3.0
			var h := _ray(c.x, c.y, level + 2.4, level - 3.0)
			n += 1
			if not is_nan(h) and absf(h - level) < 0.12:
				ok += 1
		print("deck: %d of %d rays land on the concourse level (%.2f m)" % [ok, n, level])
	if ok < n * 0.85:
		_fail("only %d of %d rays found the deck at its level" % [ok, n])
	# 2. clearance under the spines, halfway between consecutive piers
	var low := 0
	var tested := 0
	var piers: Array = _M["piers"]
	for i in range(0, piers.size() - 3, 2):
		var a := (_v(piers[i]) + _v(piers[i + 1])) * 0.5
		var b := (_v(piers[i + 2]) + _v(piers[i + 3])) * 0.5
		if a.distance_to(b) > 40.0:
			continue
		var mid := (a + b) * 0.5
		var g: float = (float(piers[i][2]) + float(piers[i + 2][2])) * 0.5
		var h := _ray(mid.x, mid.y, g + 0.3, level + 0.5)
		tested += 1
		if not is_nan(h) and h < level - depth - 0.15:
			low += 1
			print("  something at %.2f m (ground %.2f) under the deck at (%.1f, %.1f)" % [h, g, mid.x, mid.y])
	print("clearance: %d of %d spans clear up to the deck's underside (%.2f m)" % [tested - low, tested, level - depth])
	if low > tested / 5:
		_fail("%d of %d spans have something under the deck" % [low, tested])
	# 3. line 18
	var S: Dictionary = _M["l18"]
	var c := _v(S["frame"]["c"])
	var u := _v(S["frame"]["u"])
	var v := Vector2(-u.y, u.x)
	var ed: float = float(S["track"]) + float(S["edge"])
	var at := func(al: float, ac: float) -> Vector2: return c + u * al + v * ac
	var checks := [["platform", at.call(25.0, ed + 3.0), S["ceiling"], S["platform"]],
			["platform", at.call(-30.0, -(ed + 3.0)), S["ceiling"], S["platform"]],
			["mezzanine", at.call(float(S["mezz"][0]) + 1.0, 8.0), S["ceiling"], S["mezzanine"]],
			["shaft floor", at.call(float(S["shaft"][0]) + 6.0, 0.0), float(S["hall"]["floor"]) + 3.0, S["mezzanine"]],
			["track bed", at.call(30.0, float(S["track"])), S["platform"], float(S["rail"]) - 0.2]]
	for ch: Array in checks:
		var p: Vector2 = ch[1]
		var h := _ray(p.x, p.y, float(ch[2]) - 0.3, float(ch[3]) - 2.0)
		print("line 18 %s: %.2f m (expected %.2f m)" % [ch[0], h, ch[3]])
		if is_nan(h) or absf(h - float(ch[3])) > 0.25:
			_fail("line 18 %s at %.2f m, expected %.2f m" % [ch[0], h, ch[3]])
	# 4. walking
	# le Lien's 48 steps from the RER C side, and its 43 from an RER B island up through its main hall's floor
	for osm: String in ["w417349930", "w417349890"]:
		for f: Dictionary in _M["flights"]:
			if f["osm"] == osm:
				var p: Array = f["pts"]
				await _walk_flight("le Lien's stairs %s" % osm, _v(p[0]), _v(p[-1]), float(f["zs"][0]), level, 1.5)
	var ms: float = S["mezz"][1]
	var run: float = roundi((float(S["mezzanine"]) - float(S["platform"])) / 0.17) * 0.30
	await _walk_flight("line 18 stairs down to a platform", at.call(ms - 1.0, 7.0), at.call(ms + run + 1.5, 7.0),
			S["mezzanine"], S["platform"], 0.0)
	var s0: float = S["shaft"][0]
	var sh: float = S["shaft"][2]
	var half := roundi((float(S["hall"]["floor"]) - float(S["mezzanine"])) / 0.17) / 2
	var land0 := s0 + (roundi((float(S["hall"]["floor"]) - float(S["mezzanine"])) / 0.17) - half) * 0.30
	await _walk_flight("line 18 shaft, first flight", at.call(s0 - 1.5, -sh + 1.9), at.call(land0 + 0.8, -sh + 1.9),
			S["mezzanine"], float(S["mezzanine"]) + half * 0.17, 0.0)
	await _bus_station()
	print("%d failure(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------- the Atlantis bus station and the hangar

var _o := Vector2.ZERO
var _d := Vector2.RIGHT
var _n := Vector2.UP


func _st(s: float, t: float) -> Vector2:
	return _o + _d * s + _n * t


func _profile(B: Dictionary, s: float) -> float:
	var ks: Array = B["profile"]["s"]
	var kz: Array = B["profile"]["z"]
	for i in ks.size() - 1:
		if s <= float(ks[i + 1]) or i == ks.size() - 2:
			var f := clampf((s - float(ks[i])) / (float(ks[i + 1]) - float(ks[i])), 0.0, 1.0)
			return lerpf(float(kz[i]), float(kz[i + 1]), f)
	return float(kz[0])


func _bus_station() -> void:
	if not _M.has("bus_station"):
		_fail("rail.json massy has no bus_station")
		return
	var B: Dictionary = _M["bus_station"]
	_o = _v(B["frame"]["o"])
	_d = _v(B["frame"]["d"]).normalized()
	_n = Vector2(-_d.y, _d.x)
	# 5. the lanes on their profile, the quays a kerb over them
	var lanes := {"RER side": (float(B["lanes"]["rer"][0]) + float(B["lanes"]["rer"][1])) * 0.5 + 1.5,
			"Massy side": (float(B["lanes"]["massy"][0]) + float(B["lanes"]["massy"][1])) * 0.5}
	for name: String in lanes:
		var n := 0
		var ok := 0
		var worst := 0.0
		var at := Vector2.ZERO
		for s in range(-225, 226, 5):
			var p := _st(s, lanes[name])
			var z := _profile(B, s)
			var h := _ray(p.x, p.y, z + 2.0, z - 2.0)
			n += 1
			if not is_nan(h) and absf(h - z) < 0.04:
				ok += 1
			elif is_nan(h) or absf(h - z) > worst:
				worst = INF if is_nan(h) else absf(h - z)
				at = p
		print("bus station %s lane: %d of %d rays on the profile (worst %.2f m at (%.0f, %.0f))" % [name, ok, n, worst,
				at.x, at.y])
		if ok < n * 0.95:
			_fail("the %s lane is off its profile: %d of %d rays on it" % [name, ok, n])
	for q: Dictionary in B["quays"]:
		var n := 0
		var ok := 0
		var kerb: float = q["kerb"]
		for s in range(int(q["s"][0]) + 6, int(q["s"][1]) - 5, 6):
			for t: float in [float(q["t"][0]) + 0.6, float(q["t"][1]) - 0.6]:
				var p := _st(s, t)
				var z := _profile(B, s) + kerb
				var h := _ray(p.x, p.y, z + 1.6, z - 1.0)
				n += 1
				if not is_nan(h) and absf(h - z) < 0.04:
					ok += 1
		print("bus station %s: %d of %d rays on its top (%.2f m over the lanes)" % [q["name"], ok, n, kerb])
		if ok < n * 0.8:
			_fail("%s's top is off: %d of %d rays at the kerb's height" % [q["name"], ok, n])
	# the bus depot (tools/rail/bus_depot.py): its floor flat, its ramps' grades, open sides
	if not B.has("depot"):
		_fail("rail.json bus_station has no depot")
		return
	var Dp: Dictionary = B["depot"]
	var s0: float = Dp["s0"]
	var t0: float = Dp["t0"]
	var uvp := func(u: float, v: float) -> Vector2: return _st(u + s0, v + t0)
	var r: Array = Dp["roof"]
	var floor_z: float = Dp["floor"]
	var n_f := 0
	var ok_f := 0
	for u in range(int(r[0]) + 1, int(r[1]), 3):
		for v: float in [float(Dp["passage"][0]) + 1.0, 14.85, 19.35, 23.85]:
			var p: Vector2 = uvp.call(float(u), v)
			var h := _ray(p.x, p.y, floor_z + 2.5, floor_z - 1.5)
			n_f += 1
			if not is_nan(h) and absf(h - floor_z) < 0.03:
				ok_f += 1
	print("depot: %d of %d rays on its floor (%.2f m)" % [ok_f, n_f, floor_z])
	if ok_f < n_f * 0.95:
		_fail("the depot's floor: %d of %d rays at %.2f m" % [ok_f, n_f, floor_z])
	for which: String in ["out", "in"]:
		var ru: Array = Dp["ramps"][which]
		var worst := 0.0
		var last := NAN
		var bad := 0
		var u := float(ru[0]) - 6.0
		while u <= float(ru[1]) + 6.0:
			var p: Vector2 = uvp.call(u, 26.5)     # on the ramps' lane side (clear of the kerbs at their feet)
			var h := _ray(p.x, p.y, floor_z + 3.0, floor_z - 4.0)
			if is_nan(h):
				bad += 1
			elif not is_nan(last):
				worst = maxf(worst, absf(h - last))
			last = h
			u += 1.0
		print("depot ramp %s: steepest %.1f %% over 1 m (%d rays missed)" % [which, worst * 100.0, bad])
		if worst > 0.095 or bad > 0:
			_fail("the depot's ramp %s: %.1f %% at most, %d rays missed" % [which, worst * 100.0, bad])
	# open sides: rays across the roof's long sides and gables, over the wall and fence, between the columns
	var shut := 0
	var n_open := 0
	for u in range(int(r[0]) + 4, int(r[1]) - 3, 6):
		if absf(float(u) - 24.75) < 2.0 or absf(float(u) - 13.0) < 2.0 or absf(float(u) - 36.5) < 2.0:
			continue
		for zz: float in [3.0, 4.5]:
			for side: Array in [[float(r[3]) + 4.0, float(r[3]) - 3.0], [float(r[2]) - 1.0, float(r[2]) + 3.0]]:
				var a: Vector2 = uvp.call(float(u), side[0])
				var b: Vector2 = uvp.call(float(u), side[1])
				n_open += 1
				var q := PhysicsRayQueryParameters3D.create(MeshUtils.to_godot(a.x, a.y, floor_z + zz),
						MeshUtils.to_godot(b.x, b.y, floor_z + zz), Layers.SOLID)
				if not _space.intersect_ray(q).is_empty():
					shut += 1
	print("depot: %d of %d rays across its open sides stopped" % [shut, n_open])
	if shut > 0:
		_fail("the depot's sides: %d of %d rays stopped (no walls)" % [shut, n_open])
	# 6. driving: out of a bay down the ramp onto the bus lane, in up the ramp to each lane
	var outs: Array = Dp["paths"]["out"]
	var ins: Array = Dp["paths"]["in"]
	await _drive(outs[1], "bus-idfm-artic", "out of bay 2 (lane 1, north-east)")
	await _drive(outs[5], "bus-idfm", "out of bay 6 (lane 3, north-east)")
	for k in ins.size():
		await _drive(ins[k], "bus-idfm-artic" if k % 2 == 1 else "bus-idfm", "in to %s" % ("the passage lane" if k == 0
				else "lane %d" % k))


## A bot drives a `model` bus along the map polyline `pts` (the depot's ways, rail.json massy bus_station depot
## paths) to its end: never stuck, never far off the path, on its wheels.
func _drive(pts: Array, model: String, name: String) -> void:
	var step := 1.0
	var P := PackedVector2Array()
	for q: Array in pts:
		P.append(Vector2(q[0], q[1]))
	var res: Array = []
	var acc := 0.0
	res.append([P[0].x, P[0].y])
	for i in P.size() - 1:
		var a := P[i]
		var b := P[i + 1]
		var L := a.distance_to(b)
		var d := step - acc
		while d <= L:
			var p := a.lerp(b, d / L)
			res.append([p.x, p.y])
			d += step
		acc = L - (d - step)
	var n := res.size()
	var v: Array = []
	for i in n:
		v.append(4.5)
	var route := {"step": step, "length": float(n - 1) * step, "pts": res, "v": v, "stops": [], "lights": [],
			"yields": [], "turns": [], "room": [[n, 2.0]], "start": "terminus", "end": "terminus", "then": "respawn",
			"dest": "test", "name": name}
	var length: float = route["length"]
	var traffic: Node = _main.traffic
	var rid := "test:depot:" + name + model
	traffic.routes[rid] = route
	var line := {"ref": "test", "model": model, "routes": [rid], "headway": 9999.0, "phase": 0.0, "colour": "#3bb2ff",
			"text": "#000000"}
	var car: Node3D = _main.new_vehicle(model)
	var bot := BusBot.new()
	bot.setup(traffic, car, line, 0)
	bot.may_glide = false
	var d0: float = bot.tail + 1.0
	_main.add_bot_bus(car, bot.pose_at(d0), bot)
	bot.put(0, d0)
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var still := 0.0
	var tilt := 1.0
	var done := false
	for i in 60 * 240:
		await physics_frame
		var c: Vector3 = car.global_position
		var p: Vector2 = bot.project(bot.flat(car.to_global(Vector3(0.0, 0.0, bot._ref_z))), bot.s - 6.0, bot.s + 6.0)
		if absf(p.y) > worst:
			worst = absf(p.y)
			worst_at = Vector2(c.x, -c.z)
		tilt = minf(tilt, car.global_basis.y.y)
		if bot.state == BusBot.DRIVE and (car as RigidBody3D).linear_velocity.length() < 0.3:
			still += 1.0 / 60.0
		else:
			still = 0.0
		if bot.s + bot.nose > length - 4.0 or bot.state == BusBot.TERMINUS or bot.state == BusBot.STOWED:
			done = true
			break
		if still > 20.0:
			break
	var c: Vector3 = car.global_position
	print("depot: %s %s: %s at s %.0f of %.0f, %.2f m off the path at worst (%.0f, %.0f), upright %.2f" % [model, name,
			"through" if done else "STUCK", bot.s + bot.nose, length, worst, worst_at.x, worst_at.y, tilt])
	if not done:
		_fail("a %s driven %s stopped at (%.0f, %.0f), s %.0f of %.0f" % [model, name, c.x, -c.z, bot.s + bot.nose, length])
	if worst > 2.5:
		_fail("a %s driven %s strayed %.1f m off its path at (%.0f, %.0f)" % [model, name, worst, worst_at.x, worst_at.y])
	if tilt < 0.9:
		_fail("a %s driven %s tipped (up %.2f)" % [model, name, tilt])
	if car.has_method("set_pilot"):
		car.set_pilot(null)
	_main.remove_vehicles([car])
	await physics_frame

## Puts the player at `from` (height z0) and walks it towards `to`, then `past` m beyond it (onto the deck past the top
## of a flight), until it gets there or stops; it must end within 0.4 m of z1.
func _walk_flight(name: String, from: Vector2, to: Vector2, z0: float, z1: float, past: float) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = MeshUtils.to_godot(from.x, from.y, z0 + 0.1)
	_player.set("_yaw", 0.0)
	var dir := (to - from).normalized()
	_player.scripted_input = dir
	var dist := from.distance_to(to) + past
	var frames := int((dist / 1.0 + 4.0) * 60.0)      # walking pace, slower on stairs
	for i in frames:
		await physics_frame
		var p: Vector3 = _player.global_position
		if Vector2(p.x, -p.z).distance_to(from) >= dist - 0.2:
			break
	_player.scripted_input = Vector2.ZERO
	for i in 10:
		await physics_frame
	var p: Vector3 = _player.global_position
	print("walk %s: at (%.1f, %.1f) %.2f m, wanted %.2f m (%.1f m of %.1f m)" % [name, p.x, -p.z, p.y, z1,
			Vector2(p.x, -p.z).distance_to(from), dist])
	if absf(p.y - z1) > 0.4:
		_fail("walk %s ended at %.2f m, not %.2f m" % [name, p.y, z1])


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
