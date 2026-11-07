extends SceneTree
## Headless checks of Massy-Palaiseau's station (rail.json massy, scripts/builder/massy_builder.gd). Exit code 0 when
## everything passes.
##  1. The concourse deck: a ray down onto it lands on the deck's level (le Lien, the historic footbridge, the walkway).
##  2. Clearance: between the piers under each footbridge's spine, a ray up from the ground meets nothing before the
##     deck's underside (trains, buses and players pass under).
##  3. The line 18 station: rays down find the platforms, the mezzanine and the shaft's floor at their levels.
##  4. Walking: up one of le Lien's stairs from the forecourt to the deck, down the stairs from the mezzanine to a
##     platform, up the shaft's first flight from the mezzanine.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_massy.gd

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
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
	print("%d failure(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


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
