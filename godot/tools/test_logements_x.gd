extends SceneTree
## Headless checks of the École polytechnique's new housing (rail.json logements_x, tools/rail/logements_x.py,
## scripts/builder/logements_x_builder.gd). Exit code 0 when everything passes.
##  1. The six plots: world.json says 19.8 m and 6 levels; rays down land on the roof's collision (the parapet's top:
##     building_builder.gd collides the plain prism) inside and at the edge; rays across at mid height hit each face
##     (collision); under the overhang the recess is open (a ray into the porch reaches its inner wall ~4.85 m in).
##  2. The car park: rays down on a grid over its aisles and bays find its plane (flat across, 0.2 % along) within 3 cm,
##     never steeper than 1.5 % over 2 m.
##  3. The boulevard's sidewalk: rays down find its top on the kerb's level, the road 0.4 m off the kerb a kerb lower.
##  4. Walking: the promenade from the car park to the east path and the paths to the zebra and the ring residences,
##     never stuck, on the ground all the way.
##  5. Collision of the furniture: the light bollards, the benches (props).
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_logements_x.gd

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")

var _main: Node
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _L: Dictionary
var _failures: PackedStringArray = []


func _initialize() -> void:
	var rail = JSON.parse_string(FileAccess.get_file_as_string("res://world/rail.json"))
	_L = rail["logements_x"]
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _ray(x: float, y: float, z_from: float, z_to: float, mask := Layers.SOLID) -> float:
	var q := PhysicsRayQueryParameters3D.create(MeshUtils.to_godot(x, y, z_from), MeshUtils.to_godot(x, y, z_to), mask)
	var hit := _space.intersect_ray(q)
	return NAN if hit.is_empty() else float(hit["position"].y)


## Distance from map point a (height z) along d to the first hit, NAN when nothing within `reach`.
func _ray_h(a: Vector2, d: Vector2, z: float, reach: float, mask := Layers.SOLID) -> float:
	var q := PhysicsRayQueryParameters3D.create(MeshUtils.to_godot(a.x, a.y, z), MeshUtils.to_godot(a.x + d.x * reach,
			a.y + d.y * reach, z), mask)
	q.exclude = [_player.get_rid()]
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var p: Vector3 = hit["position"]
	return Vector2(p.x, -p.z).distance_to(a)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL ", msg)


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _run() -> void:
	for i in 5:
		await physics_frame
	_player = _main.get_node("Player")
	_space = _main.get_world_3d().direct_space_state
	_plots()
	_car_park()
	_sidewalk()
	await _walks()
	_furniture()
	print("%d failure(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------- 1. the plots

func _plots() -> void:
	var D: Dictionary = _L["dims"]
	var H: float = D["height"]
	var buildings := _main.find_child("Buildings", true, false)
	for pl: Dictionary in _L["plots"]:
		var R: Array[Vector2] = []
		for q: Array in pl["ring"]:
			R.append(_v(q))
		var zp: float = pl["zp"]
		var mi := buildings.get_node_or_null(String(pl["id"]).replace(":", "_")) if buildings else null
		var info: Dictionary = mi.get_meta("plateau", {}) if mi else {}
		if absf(float(info.get("height", 0.0)) - H) > 0.01 or int(info.get("levels", 0)) != 6:
			_fail("plot %s: world.json height %s, levels %s (want %.1f m, 6)" % [pl["num"], info.get("height"),
					info.get("levels"), H])
		var c := (R[0] + R[1] + R[2] + R[3]) * 0.25
		var e1 := (R[1] - R[0]).normalized()
		var e2 := Vector2(-e1.y, e1.x)
		var deck := zp + H
		var roof := _ray((c + e1 * 3.0 - e2 * 6.0).x, (c + e1 * 3.0 - e2 * 6.0).y, zp + 40.0, zp)
		if is_nan(roof) or absf(roof - deck) > 0.15:
			_fail("plot %s: roof at %s, want %.2f" % [pl["num"], roof, deck])
		var edge := R[0] + (R[1] - R[0]) * 0.5 + (c - R[0]).normalized() * 0.1
		var cop := _ray(edge.x, edge.y, zp + 40.0, zp)
		if is_nan(cop) or absf(cop - (zp + H)) > 0.12:
			_fail("plot %s: parapet top at %s, want %.2f" % [pl["num"], cop, zp + H])
		var hits := 0
		for i in 4:
			var p := R[i]
			var q := R[(i + 1) % 4]
			var out := Vector2((q - p).y, -(q - p).x).normalized()
			var mid := (p + q) * 0.5 + out * 6.0
			var d := _ray_h(mid, -out, zp + 10.0, 8.0)
			if not is_nan(d) and d > 4.5 and d < 6.1:
				hits += 1
		if hits < 4:
			_fail("plot %s: %d of 4 faces collide at mid height" % [pl["num"], hits])
		# the recess: from outside across the porch to its inner wall
		var P := R[int(pl["corner"])]
		var ea := _v(pl["ea"])
		var eb := _v(pl["eb"])
		var porch := P + ea * 7.2 - eb * 3.0
		var dr := _ray_h(porch, eb, zp + 1.3, 12.0)
		var want := 3.0 + float(pl["recess"][1]) + float(pl["core_in"])
		if is_nan(dr) or absf(dr - want) > 0.5:
			_fail("plot %s: the porch's wall at %s m, want %.2f (open recess)" % [pl["num"], dr, want])
		print("plot %s: roof %.2f (want %.2f), parapet %.2f, %d faces, porch wall %.2f m in" % [pl["num"], roof, deck,
				cop, hits, dr])


# ---------------------------------------------------------------- 2. the car park

func _car_park() -> void:
	if not _L.has("car_park"):
		_fail("rail.json logements_x has no car_park: rebuild with tools/rail/build_rail.py")
		return
	var C: Dictionary = _L["car_park"]
	var o := _v(C["o"])
	var d := _v(C["d"])
	var n := Vector2(d.y, -d.x)
	var a_range: Array = C["a"]
	var z: Array = C["z"]
	var worst := 0.0
	var steep := 0.0
	var n_rays := 0
	var aisles: Array = [[5.6, 11.6], [21.6, 27.6]]
	for b0: float in [3.0, 8.6, 14.0, 19.0, 24.6, 30.0]:
		var last := NAN
		var a: float = float(a_range[0]) + 1.0
		while a < float(a_range[1]) - 1.0:
			var p := o + d * a + n * b0
			var h := _ray(p.x, p.y, 5.0, -3.0)
			var want: float = float(z[0]) + (float(z[1]) - float(z[0])) * (a - float(a_range[0])) / (float(a_range[1]) - float(a_range[0]))
			var inside := false
			for isl: Array in C["islands"]:
				if a > float(isl[0]) - 0.6 and a < float(isl[1]) + 0.6:
					inside = true
			if not inside and not is_nan(h):
				worst = maxf(worst, absf(h - want))
				if not is_nan(last):
					steep = maxf(steep, absf(h - last) / 2.0)
				n_rays += 1
			last = NAN if inside else h
			a += 2.0
	print("car park: %d rays, worst %.3f m off its plane, steepest %.2f %% over 2 m" % [n_rays, worst, steep * 100.0])
	if worst > 0.03 or steep > 0.015 or n_rays < 200:
		_fail("car park not flat: %.3f m off, %.2f %% (%d rays)" % [worst, steep * 100.0, n_rays])


# ---------------------------------------------------------------- 3. the sidewalk

func _sidewalk() -> void:
	var K: Array = _L["kerb"]
	var bad := 0
	var steps := []
	for i in range(4, K.size() - 4, 10):
		var a := _v(K[i])
		var b := _v(K[i + 1])
		var t := (b - a).normalized()
		var nn := Vector2(-t.y, t.x)
		var top: float = K[i][2]
		var on := a + nn * 1.5
		var h := _ray(on.x, on.y, top + 3.0, top - 3.0)
		var road := a - nn * 0.4
		var hr := _ray(road.x, road.y, top + 3.0, top - 3.0)
		if is_nan(h) or absf(h - top) > 0.03:
			bad += 1
		steps.append(top - hr)
	var full := 0
	for s in steps:
		if s > 0.09 and s < 0.16:
			full += 1
	print("sidewalk: %d of %d rays off its top; %d of %d kerb steps 0.09-0.16 m" % [bad, steps.size(), full, steps.size()])
	if bad > 1 or full < steps.size() * 0.75:
		_fail("sidewalk: %d rays off its top, %d of %d kerb steps right" % [bad, full, steps.size()])


# ---------------------------------------------------------------- 4. walking

func _walks() -> void:
	for ln: Dictionary in _L.get("lines", []):
		if ln["kind"] == "entry":
			continue
		var pts: Array = ln["pts"]
		await _walk(String(ln["kind"]), pts)


func _walk(name: String, pts: Array) -> void:
	var start := _v(pts[0])
	var end := _v(pts[pts.size() - 1])
	var z0 := _ray(start.x, start.y, 30.0, -10.0)
	_player.velocity = Vector3.ZERO
	_player.global_position = MeshUtils.to_godot(start.x, start.y, z0 + 0.15)
	var total := 0.0
	for k in pts.size() - 1:
		total += _v(pts[k]).distance_to(_v(pts[k + 1]))
	var off := 0.0
	var air := 0
	var k := 1
	var frames := int((total / 1.0 + 6.0) * 60.0)
	for f in frames:
		var p3: Vector3 = _player.global_position
		var p := Vector2(p3.x, -p3.z)
		while k < pts.size() - 1 and p.distance_to(_v(pts[k])) < 1.5:
			k += 1
		var dir := (_v(pts[k]) - p).normalized()
		_player.set("_yaw", 0.0)
		_player.scripted_input = dir
		await physics_frame
		var g := _ray(p.x, p.y, p3.y + 1.0, p3.y - 3.0)
		if not is_nan(g) and p3.y - g > 0.6:
			air += 1
		var seg := INF
		for j in range(maxi(k - 2, 0), mini(k + 1, pts.size() - 1)):
			seg = minf(seg, Geometry2D.get_closest_point_to_segment(p, _v(pts[j]), _v(pts[j + 1])).distance_to(p))
		off = maxf(off, seg)
		if k == pts.size() - 1 and p.distance_to(end) < 1.0:
			break
	_player.scripted_input = Vector2.ZERO
	var p3e: Vector3 = _player.global_position
	var left := Vector2(p3e.x, -p3e.z).distance_to(end)
	print("walk %s: %.0f m, ended %.1f m from its end, %.2f m off the path at worst, %d frames in the air" % [
			name, total, left, off, air])
	if left > 2.0 or off > 2.0 or air > 30:
		_fail("walk %s: ended %.1f m from its end, %.2f m off, %d frames in the air" % [name, left, off, air])


# ---------------------------------------------------------------- 5. furniture

func _furniture() -> void:
	var n := 0
	var hit := 0
	for b: Array in _L["bollards"]:
		var p := _v(b)
		var g := _ray(p.x, p.y, 20.0, -10.0, Layers.TERRAIN)
		var d := _ray_h(p + Vector2(1.0, 0.0), Vector2(-1.0, 0.0), g + 0.5, 2.0)
		n += 1
		if not is_nan(d) and d > 0.8 and d < 1.0:
			hit += 1
	print("bollards: %d of %d collide" % [hit, n])
	if hit < n:
		_fail("bollards: %d of %d collide" % [hit, n])
