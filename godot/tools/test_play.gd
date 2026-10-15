extends SceneTree
## Headless gameplay checks (milestone 2). Exit code 0 when everything passes.
##  1. Picker: a ray down onto each roof, and one at each walled mass's longest wall, must return
##     that mass's metadata (or a mass in front of / above it), never nothing or a wrong record.
##  2. Walking: the player starts from a grid of points around Télécom Paris and walks in several
##     directions; it must never sink below the terrain nor end up stuck inside geometry.
##  3. Walls: walking straight at the longest wall of every building stops at the wall.
##  4. Boundary: walking out of the playable area is blocked.
##  5. Kerbs (M4): walking from the road onto a raised sidewalk across its kerb, and back, works (not on the
##     Lozère hillside banks the LiDAR smears onto the sidewalk: see BANK_SLOPE).
##  6. Trees (M5): a ray at a trunk identifies that tree, a ray down onto a crown finds it, and
##     walking into a trunk stops at it.
##  7. Street furniture (M6): a ray down onto every prop and fence identifies it (or something above
##     it), and walking into poles, shelters and fences stops at them.
##  8. Toy buildings (M7): under every wall-less slab (canopies, covered passages) and through every
##     building passage there is open space down to the ground.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_play.gd
## (--fixed-fps makes the simulation run as fast as the machine allows.)

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")

const WALK_AREA := Rect2(-100, -140, 300, 240)      # pipeline x, y, w, h around Télécom Paris
const WALK_STEP := 20.0
const SEGMENT_TIME := 1.2                            # seconds walked per direction
const MIN_MOVE := 0.3
## Kerbs with ground steeper than this (degrees) beside them are not walked: on the Lozère hillside the LiDAR
## smears the bank behind the sidewalk onto it, and the kerb ramp on that slope is above the player's floor
## limit (known issue, MILESTONES.md `campus` note). The tested kerbs on ordinary ground stay below 28°.
const BANK_SLOPE := 30.0

var _main: Node
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _world: Dictionary
var _failures: PackedStringArray = []
var _footprints: Array = []      # [Rect2, Array[PackedVector2Array]] of walled masses on the ground
var _passages: Array[PackedVector2Array] = []   # building passages (open ground through a footprint)


func _initialize() -> void:
	_world = JSON.parse_string(FileAccess.get_file_as_string("res://world/world.json"))
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await physics_frame
	_player = _main.get_node("Player")
	_space = _main.get_world_3d().direct_space_state
	for b: Dictionary in _world["buildings"]:
		if not (b["walls"] and b["min_height"] < 1.0):
			continue
		# the toy outline (rounded corners, cut by passages) of the tiers standing on the ground (M7)
		for t: Dictionary in b["toy"]["tiers"]:
			if t["kind"] != "body" or t["floating"]:
				continue
			var rings: Array[PackedVector2Array] = []
			for ring: Array in t["rings"]:
				var poly := PackedVector2Array()
				for pt: Array in ring:
					poly.append(Vector2(pt[0], pt[1]))
				rings.append(poly)
			var rect := Rect2(rings[0][0], Vector2.ZERO)
			for pt in rings[0]:
				rect = rect.expand(pt)
			_footprints.append([rect, rings])
		for ring: Array in b["toy"]["passages"]:
			var poly := PackedVector2Array()
			for pt: Array in ring:
				poly.append(Vector2(pt[0], pt[1]))
			_passages.append(poly)
	_test_picker()
	await _test_walk()
	await _test_walls()
	await _test_boundary()
	await _test_kerbs()
	await _test_trees()
	await _test_props()
	_test_open_spaces()
	if _failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d FAILURES" % _failures.size())
		for f in _failures.slice(0, 40):
			print("  ", f)
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ray(from: Vector3, to: Vector3, mask := Layers.SOLID) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


## True when the mass's outline reaches into the playable area. Masses in the margin between
## `playable` and `bounds` are scenery the player cannot reach (some are clipped by the box edge).
func _reachable(b: Dictionary) -> bool:
	var p: Array = _world["meta"]["playable"]
	var area := Rect2(p[0], p[1], p[2] - p[0], p[3] - p[1])
	var ring: Array = b["rings"][0]
	var rect := Rect2(ring[0][0], ring[0][1], 0, 0)
	for pt: Array in ring:
		rect = rect.expand(Vector2(pt[0], pt[1]))
	return area.intersects(rect)


## Top of the mass's ground tier, whose walls follow the outline (higher tiers may be set back from it).
func _wall_top(b: Dictionary) -> float:
	var tiers: Array = b["toy"]["tiers"]
	return tiers[0]["top"] if tiers else b["base_z"] + b["height"]


# --- 1. picker ---------------------------------------------------------------------------------

func _test_picker() -> void:
	var by_id := {}
	for b: Dictionary in _world["buildings"]:
		by_id[b["id"]] = b
	var stats := {"roof ok": 0, "roof covered": 0, "wall ok": 0, "wall occluded": 0, "wall slope": 0}
	for b: Dictionary in _world["buildings"]:
		if not _reachable(b):
			continue
		var top: float = b["base_z"] + b["height"]
		# roof: centroid of the largest cap triangle
		var flat: Array[Vector2] = []
		for ring: Array in b["rings"]:
			for p: Array in ring:
				flat.append(Vector2(p[0], p[1]))
		var tris: Array = b["roof"]["tris"]
		var best := Vector2.ZERO
		var best_area := -1.0
		for k in range(0, tris.size(), 3):
			var a := flat[tris[k]]
			var c1 := flat[tris[k + 1]]
			var c2 := flat[tris[k + 2]]
			var area := absf((c1 - a).cross(c2 - a)) / 2.0
			if area > best_area:
				best_area = area
				best = (a + c1 + c2) / 3.0
		# down to the base: the roof under this point may be a lower tier of the mass (M7)
		var hit := _ray(MeshUtils.to_godot(best.x, best.y, top + 50.0), MeshUtils.to_godot(best.x, best.y, b["base_z"] - 1.0))
		var info := WorldQuery.hit_info(hit)
		if info.get("id") == b["id"]:
			stats["roof ok"] += 1
		elif info.get("type") == "building" and (info["base_z"] + info["height"] >= top - 0.05 or hit["position"].y >= top - 0.05):
			stats["roof covered"] += 1
		else:
			_fail("roof of #%d %s: got %s" % [b["num"], b["id"], info.get("id", "nothing")])

		if not b["walls"] or b["height"] - b["min_height"] < 2.0:
			continue
		# wall: from 3 m outside the middle of the longest outer edge, straight at it
		var ring: Array = b["rings"][0]
		var p := Vector2.ZERO
		var q := Vector2.ZERO
		for i in ring.size():
			var a := Vector2(ring[i][0], ring[i][1])
			var c := Vector2(ring[(i + 1) % ring.size()][0], ring[(i + 1) % ring.size()][1])
			if a.distance_to(c) > p.distance_to(q):
				p = a
				q = c
		var mid := (p + q) / 2.0
		var out := Vector2(q.y - p.y, p.x - q.x).normalized()   # CCW outer ring: outward normal
		if _in_passage(mid - out * 0.5):
			stats["wall slope"] += 1
			continue
		var start := mid + out * 3.0
		var g := WorldQuery.ground_y(_main.get_world_3d(), start.x, -start.y)
		var z := maxf(g, b["base_z"] + b["min_height"]) + 1.2
		if z > minf(top, _wall_top(b)) - 0.2:
			stats["wall slope"] += 1
			continue
		var end := mid - out * 1.0
		hit = _ray(MeshUtils.to_godot(start.x, start.y, z), MeshUtils.to_godot(end.x, end.y, z))
		info = WorldQuery.hit_info(hit)
		if info.get("id") == b["id"]:
			stats["wall ok"] += 1
		elif info.get("type") == "building":
			stats["wall occluded"] += 1     # an adjacent mass in front of this wall
		elif info.get("type") in ["terrain", "ground"]:
			stats["wall slope"] += 1         # the ground (or a raised sidewalk) rises to the wall
		else:
			_fail("wall of #%d %s: ray hit nothing" % [b["num"], b["id"]])
	print("picker: ", stats)


# --- 2. walking --------------------------------------------------------------------------------

## True when pipeline point xy is inside the toy footprint of a walled mass standing on the ground.
func _inside_building(xy: Vector2) -> bool:
	if _in_passage(xy):
		return false
	for f: Array in _footprints:
		if not f[0].grow(0.01).has_point(xy):
			continue
		var rings: Array[PackedVector2Array] = f[1]
		if not Geometry2D.is_point_in_polygon(xy, rings[0]):
			continue
		var in_hole := false
		for k in range(1, rings.size()):
			in_hole = in_hole or Geometry2D.is_point_in_polygon(xy, rings[k])
		if not in_hole:
			return true
	return false


func _in_passage(xy: Vector2) -> bool:
	for poly in _passages:
		if Geometry2D.is_point_in_polygon(xy, poly):
			return true
	return false


func _blocked_by_geometry(pos: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.9)
	q.collision_mask = Layers.BUILDINGS | Layers.VEGETATION | Layers.PROPS
	return not _space.intersect_shape(q, 1).is_empty()


func _walk(dir: Vector2, seconds: float, run := false, jump := false) -> Dictionary:
	_player.scripted_input = dir
	_player.scripted_run = run
	_player.scripted_jump = jump
	var start: Vector3 = _player.global_position
	var lowest := INF
	for i in int(seconds * 60.0):
		await physics_frame
		var pos: Vector3 = _player.global_position
		var g := WorldQuery.ground_y(_main.get_world_3d(), pos.x, pos.z)
		if not is_nan(g):
			lowest = minf(lowest, pos.y - g)
	_player.scripted_input = Vector2.ZERO
	_player.scripted_jump = false
	return {"moved": start.distance_to(_player.global_position), "lowest": lowest}


func _test_walk() -> void:
	var starts := 0
	var segments := 0
	var blocked := 0
	var dirs: Array[Vector2] = []
	for k in 8:
		dirs.append(Vector2.from_angle(k * PI / 4.0))
	var y := WALK_AREA.position.y
	while y <= WALK_AREA.end.y:
		var x := WALK_AREA.position.x
		while x <= WALK_AREA.end.x:
			var g := WorldQuery.ground_y(_main.get_world_3d(), x, -y)
			var pos := MeshUtils.to_godot(x, y, g + 0.05)
			if not is_nan(g) and not _inside_building(Vector2(x, y)) and not _blocked_by_geometry(pos + Vector3.UP * 0.1):
				starts += 1
				_player.teleport(pos, 0.0)
				var rescues_before: int = _player.rescues
				for k in 4:
					var d := dirs[(k * 2 + starts) % 8]
					var r := await _walk(d, SEGMENT_TIME, k == 1, k == 2)
					segments += 1
					var here: Vector3 = _player.global_position
					var where := "(%.0f, %.0f) dir %.0f°" % [here.x, -here.z, rad_to_deg(d.angle())]
					if r["lowest"] < -0.25:
						_fail("sank %.2f m below the terrain near %s" % [-r["lowest"], where])
					if r["moved"] < MIN_MOVE:
						blocked += 1
						var back := await _walk(-d, SEGMENT_TIME)
						if back["moved"] < MIN_MOVE:
							_fail("stuck near %s" % where)
					if _inside_building(Vector2(here.x, -here.z)):
						_fail("walked into a building near %s" % where)
				if _player.rescues != rescues_before:
					_fail("fell out of the world near (%.0f, %.0f)" % [x, y])
			x += WALK_STEP
		y += WALK_STEP
	print("walk: %d starts, %d segments, %d blocked by walls (then walked back out)" % [starts, segments, blocked])
	if starts < 50:
		_fail("only %d walkable start points" % starts)


# --- 3. walls ----------------------------------------------------------------------------------

func _test_walls() -> void:
	var tested := 0
	var pl: Array = _world["meta"]["playable"]
	var area := Rect2(pl[0], pl[1], pl[2] - pl[0], pl[3] - pl[1])
	for b: Dictionary in _world["buildings"]:
		if not b["walls"] or b["min_height"] > 0.0 or b["height"] < 2.5 or not _reachable(b):
			continue
		var ring: Array = b["rings"][0]
		var p := Vector2.ZERO
		var q := Vector2.ZERO
		for i in ring.size():
			var a := Vector2(ring[i][0], ring[i][1])
			var c := Vector2(ring[(i + 1) % ring.size()][0], ring[(i + 1) % ring.size()][1])
			if a.distance_to(c) > p.distance_to(q):
				p = a
				q = c
		var mid := (p + q) / 2.0
		var out := Vector2(q.y - p.y, p.x - q.x).normalized()
		if _in_passage(mid - out * 0.5):
			continue
		var start := mid + out * 2.5
		if not area.has_point(start):
			continue                          # the wall faces the boundary
		var g := WorldQuery.ground_y(_main.get_world_3d(), start.x, -start.y)
		var pos := MeshUtils.to_godot(start.x, start.y, g + 0.05)
		if is_nan(g) or _inside_building(start) or _blocked_by_geometry(pos + Vector3.UP * 0.1):
			continue
		if _wall_top(b) - g < 0.5:
			continue                          # a shed dug into the slope: from uphill the player steps onto it
		tested += 1
		_player.teleport(pos, 0.0)
		_player.scripted_input = -out
		var closest := INF
		for i in 90:
			await physics_frame
			var here := Vector2(_player.global_position.x, -_player.global_position.z)
			closest = minf(closest, (here - mid).dot(out))
		_player.scripted_input = Vector2.ZERO
		if closest < 0.2:
			_fail("walked through the wall of #%d %s (%.2f m past it)" % [b["num"], b["id"], -closest])
	print("walls: walked into %d walls" % tested)
	if tested < 150:
		_fail("only %d walls could be tested" % tested)


# --- 4. boundary -------------------------------------------------------------------------------

func _test_boundary() -> void:
	var p: Array = _world["meta"]["playable"]
	var cases := [
		[Vector2(p[0] + 3, -100), Vector2.LEFT], [Vector2(p[2] - 3, -100), Vector2.RIGHT],
		[Vector2(500, p[3] - 3), Vector2(0, 1)], [Vector2(500, p[1] + 3), Vector2(0, -1)],
	]
	for c: Array in cases:
		var xy: Vector2 = c[0]
		var g := WorldQuery.ground_y(_main.get_world_3d(), xy.x, -xy.y, Layers.SOLID, 200.0)
		_player.teleport(MeshUtils.to_godot(xy.x, xy.y, g + 0.05), 0.0)
		await _walk(c[1], 3.0, true)
		var pos: Vector3 = _player.global_position
		var x := pos.x
		var y := -pos.z
		if x < p[0] - 0.01 or x > p[2] + 0.01 or y < p[1] - 0.01 or y > p[3] + 0.01:
			_fail("left the playable area at (%.1f, %.1f)" % [x, y])
	print("boundary: checked %d sides" % cases.size())


# --- 5. kerbs ----------------------------------------------------------------------------------

func _test_kerbs() -> void:
	var p: Array = _world["meta"]["playable"]
	var raised: Array = []
	for k: Dictionary in _world["kerbs"]:
		var a: Array = k["pts"][0]
		var b: Array = k["pts"][-1]
		if k["kind"] == "raised" and Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])) > 3.0 \
				and a[0] > p[0] + 5 and a[0] < p[2] - 5 and a[1] > p[1] + 5 and a[1] < p[3] - 5:
			raised.append(k)
	var step := maxi(1, raised.size() / 60)
	var tested := 0
	var skipped := 0
	var on_banks := 0
	for i in range(0, raised.size(), step):
		var pts: Array = raised[i]["pts"]
		var j := pts.size() / 2
		var a := Vector2(pts[maxi(j - 1, 0)][0], pts[maxi(j - 1, 0)][1])
		var b := Vector2(pts[mini(j, pts.size() - 1)][0], pts[mini(j, pts.size() - 1)][1])
		if a.distance_to(b) < 0.5:
			b = Vector2(pts[-1][0], pts[-1][1])
			a = Vector2(pts[0][0], pts[0][1])
		var mid := (a + b) / 2.0
		if mid.x < p[0] + 5 or mid.x > p[2] - 5 or mid.y < p[1] + 5 or mid.y > p[3] - 5:
			skipped += 1                      # the run starts inside but this point is at the boundary
			continue
		var n := (b - a).normalized().orthogonal() * -1.0       # left of the point order: raised side
		var start := mid - n * 1.5
		var g := WorldQuery.ground_y(_main.get_world_3d(), start.x, -start.y)
		var pos := MeshUtils.to_godot(start.x, start.y, g + 0.05)
		# a wall, hedge or prop on the way is not a kerb test
		var probe := _ray(pos + Vector3.UP, MeshUtils.to_godot(mid.x + n.x * 2.5, mid.y + n.y * 2.5, g + 1.0),
				Layers.BUILDINGS | Layers.VEGETATION | Layers.PROPS) \
			or _ray(pos + Vector3.UP * 0.4, MeshUtils.to_godot(mid.x + n.x * 2.5, mid.y + n.y * 2.5, g + 0.4),
				Layers.VEGETATION | Layers.PROPS)                     # bike racks, bollards
		var furniture := false                # a bike rack or bollard on the kerb is not a kerb test
		for pr: Dictionary in _world["props"]:
			if Vector2(pr["x"], pr["y"]).distance_to(mid) < 1.0:
				furniture = true
				break
		if is_nan(g) or probe or furniture or _inside_building(start) or _blocked_by_geometry(pos + Vector3.UP * 0.1):
			skipped += 1
			continue
		if _bank_slope(mid, n, g) > BANK_SLOPE:
			on_banks += 1
			continue
		tested += 1
		_player.teleport(pos, 0.0)
		await physics_frame
		await _walk(n, 0.7)
		var here := Vector2(_player.global_position.x, -_player.global_position.z)
		var up := (here - mid).dot(n)
		if up < 0.5:
			_fail("could not step up the kerb at (%.1f, %.1f): stopped %.2f m before it" % [mid.x, mid.y, -up])
			continue
		await _walk(-n, 0.9)
		here = Vector2(_player.global_position.x, -_player.global_position.z)
		if (here - mid).dot(n) > -0.5:
			_fail("could not step down the kerb at (%.1f, %.1f)" % [mid.x, mid.y])
	print("kerbs: walked up and down %d raised kerbs (%d skipped near buildings, %d on hillside banks)" \
			% [tested, skipped, on_banks])
	if tested < 20:
		_fail("only %d kerbs could be tested" % tested)


## Steepest ground within 1.5 m of the kerb at `mid` along `n`, the kerb ramp itself left out.
func _bank_slope(mid: Vector2, n: Vector2, g: float) -> float:
	var steepest := 0.0
	for k in 31:
		var t := -1.5 + k * 0.1
		if absf(t) < 0.4:
			continue
		var q := mid + n * t
		var hit := _ray(MeshUtils.to_godot(q.x, q.y, g + 5.0), MeshUtils.to_godot(q.x, q.y, g - 5.0), Layers.TERRAIN)
		if hit:
			steepest = maxf(steepest, rad_to_deg(hit.normal.angle_to(Vector3.UP)))
	return steepest


# --- 6. trees ----------------------------------------------------------------------------------

func _test_trees() -> void:
	var data = _main.get_node("Neighborhood/TreeCollision").data
	var p: Array = _world["meta"]["playable"]
	var stats := {"trunk ok": 0, "trunk occluded": 0, "crown ok": 0, "crown covered": 0}
	var step := maxi(1, data.size() / 300)
	for k in range(0, data.size(), step):
		var base: Vector3 = data.base[k]
		# trunk: horizontal ray at 1 m from 3 m away (several directions until one is clear of the start)
		var ok := false
		var y := minf(1.0, data.trunk[k].y * 0.5)      # saplings and columnar trees have short trunks
		for a in [0.0, PI / 2.0, PI, 1.5 * PI]:
			var from := base + Vector3(cos(a) * 3.0, y, sin(a) * 3.0)
			if _ray(from + Vector3.UP * 0.01, from, Layers.PICKABLE):
				continue
			var hit := _ray(from, base + Vector3.UP * y - Vector3(cos(a), 0, sin(a)) * 0.5, Layers.PICKABLE)
			var info := WorldQuery.hit_info(hit)
			if info.get("id") == data.ids[k]:
				stats["trunk ok"] += 1
			elif hit:
				stats["trunk occluded"] += 1
			else:
				_fail("ray at the trunk of %s hit nothing" % data.ids[k])
			ok = true
			break
		if not ok:
			stats["trunk occluded"] += 1
		# crown: straight down from above it
		var c: Vector3 = data.crown_center[k]
		var r: Vector2 = data.crown_radii[k]
		var top := c + Vector3.UP * (r.y + 30.0)
		var crown: Vector2 = data.ray_crown(top, Vector3.DOWN, 100.0)
		if int(crown.x) == k:
			stats["crown ok"] += 1
		elif crown.x >= 0 and crown.y < 30.0 + 1e-3:
			stats["crown covered"] += 1     # a taller neighbour's crown above it
		else:
			_fail("ray down onto the crown of %s found %s" % [data.ids[k], data.ids[int(crown.x)] if crown.x >= 0 else "nothing"])
	print("trees: ", stats)
	if stats["trunk ok"] < 100:
		_fail("only %d trunks identified" % stats["trunk ok"])

	# walking into trunks inside the playable area
	var walked := 0
	for k in range(0, data.size(), maxi(1, data.size() / 400)):
		if walked >= 20:
			break
		var base: Vector3 = data.base[k]
		var r: float = maxf(data.trunk[k].x, 0.12)
		if r < 0.15 or base.x < p[0] + 5 or base.x > p[2] - 5 or -base.z < p[1] + 5 or -base.z > p[3] - 5:
			continue
		var start := base + Vector3(2.0, 0.05, 0.0)
		var g := WorldQuery.ground_y(_main.get_world_3d(), start.x, start.z)
		if is_nan(g):
			continue
		start.y = g + 0.05
		if _blocked_by_geometry(start + Vector3.UP * 0.1) or _ray(start + Vector3.UP, base + Vector3.UP, Layers.SOLID | Layers.VEGETATION).get("collider") != _main.get_node("Neighborhood/TreeCollision"):
			continue
		walked += 1
		_player.teleport(start, 0.0)
		_player.scripted_input = Vector2(-1, 0)
		var closest := INF
		for i in 90:
			await physics_frame
			var d := Vector2(_player.global_position.x - base.x, _player.global_position.z - base.z).length()
			closest = minf(closest, d)
		_player.scripted_input = Vector2.ZERO
		if closest < r + 0.15:
			_fail("walked through the trunk of %s (%.2f m from its axis, radius %.2f)" % [data.ids[k], closest, r])
	print("trees: walked into %d trunks" % walked)
	if walked < 10:
		_fail("only %d trunks could be walked into" % walked)


# --- 7. street furniture ------------------------------------------------------------------------

func _test_props() -> void:
	var body: StaticBody3D = _main.get_node("Neighborhood/PropCollision")
	var data = body.data
	var stats := {"picked": 0, "covered": 0}
	var first_shape := {}
	for i in data.shape_record.size():
		var k: int = data.shape_record[i]
		if first_shape.has(k):
			continue
		first_shape[k] = i
		var c: Vector3 = data.shape_pos[i]
		var h: float = data.shape_size[i].y
		var hit := _ray(c + Vector3.UP * (h / 2.0 + 4.0), c - Vector3.UP * (h / 2.0 + 1.0), Layers.PICKABLE)
		var info := WorldQuery.hit_info(hit)
		if info.get("id") == data.ids[k]:
			stats["picked"] += 1
		elif hit and hit["position"].y >= c.y + h / 2.0 - 0.02:
			stats["covered"] += 1           # a roof, canopy slab or another prop above it
		else:
			_fail("ray down onto %s found %s" % [data.ids[k], info.get("id", "nothing")])
	print("props: ", stats, " of ", first_shape.size(), " records with collision")
	if stats["picked"] < first_shape.size() * 0.9:
		_fail("only %d of %d props identified from above" % [stats["picked"], first_shape.size()])

	# walking into poles (lamps, signs, signals, bus poles), shelter walls and fences
	var p: Array = _world["meta"]["playable"]
	var walked := {"pole": 0, "box": 0}
	for i in data.shape_record.size():
		if walked["pole"] >= 15 and walked["box"] >= 10:
			break
		var c: Vector3 = data.shape_pos[i]
		var s: Vector3 = data.shape_size[i]
		var cyl: bool = data.shape_kind[i] == 1
		var kind := "pole" if cyl else "box"
		if walked[kind] >= (15 if cyl else 10) or s.y < 1.5 or (cyl and s.x < 0.04) or (not cyl and minf(s.x, s.z) > 0.6):
			continue
		if c.x < p[0] + 5 or c.x > p[2] - 5 or -c.z < p[1] + 5 or -c.z > p[3] - 5:
			continue
		var yaw: float = data.shape_yaw[i]
		# approach across the thin side of boxes (shelter walls, fence panels)
		var across := Vector3(0, 0, 1).rotated(Vector3.UP, yaw) if not cyl and s.z < s.x else Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
		var start := c + across * 2.2
		var g := WorldQuery.ground_y(_main.get_world_3d(), start.x, start.z)
		if is_nan(g) or absf(g - (c.y - s.y / 2.0)) > 0.5:
			continue
		start.y = g + 0.05
		if _blocked_by_geometry(start + Vector3.UP * 0.1):
			continue
		var los := _ray(start + Vector3.UP * 1.0, Vector3(c.x, start.y + 1.0, c.z), Layers.SOLID | Layers.VEGETATION | Layers.PROPS)
		if los.get("collider") != body or WorldQuery.hit_info(los).get("id") != data.ids[data.shape_record[i]]:
			continue
		walked[kind] += 1
		_player.teleport(start, 0.0)
		var dir := Vector2(-across.x, -across.z)
		_player.scripted_input = Vector2(dir.dot(Vector2(1, 0)), dir.dot(Vector2(0, -1)))
		var worst := INF
		for f in 90:
			await physics_frame
			var local := Basis(Vector3.UP, yaw).inverse() * (_player.global_position - c)
			var gap := Vector2(local.x, local.z).length() - s.x if cyl else maxf(absf(local.x) - s.x / 2.0, absf(local.z) - s.z / 2.0)
			worst = minf(worst, gap)
		_player.scripted_input = Vector2.ZERO
		if worst < 0.1:
			_fail("walked into %s %s (%.2f m from its surface)" % [data.ids[data.shape_record[i]], kind, worst])
	print("props: walked into ", walked)
	if walked["pole"] < 8 or walked["box"] < 5:
		_fail("only %s props could be walked into" % walked)


# --- 8. open spaces under slabs and through passages ---------------------------------------------

## A ray down from just under each wall-less slab (away from its pillars), and down the middle of each
## building passage from below its bridge, must reach the ground without meeting the building.
func _test_open_spaces() -> void:
	var stats := {"slabs open": 0, "slabs low": 0, "passages open": 0}
	for b: Dictionary in _world["buildings"]:
		for t: Dictionary in b["toy"]["tiers"]:
			if t["kind"] != "slab" and t["kind"] != "bridge":
				continue
			var flat: Array[Vector2] = []
			for ring: Array in t["rings"]:
				for pt: Array in ring:
					flat.append(Vector2(pt[0], pt[1]))
			var tris: Array = t["tris"]
			var best := Vector2.ZERO
			var best_score := -1.0
			for k in range(0, tris.size(), 3):
				var c := (flat[tris[k]] + flat[tris[k + 1]] + flat[tris[k + 2]]) / 3.0
				var clear := INF
				for pl: Array in b["pillars"]:
					clear = minf(clear, c.distance_to(Vector2(pl[0], pl[1])))
				var area := absf((flat[tris[k + 1]] - flat[tris[k]]).cross(flat[tris[k + 2]] - flat[tris[k]]))
				var score := minf(clear, 3.0) * 100.0 + area
				if clear > 1.0 and score > best_score:
					best_score = score
					best = c
			if best_score < 0.0:
				continue
			var g := WorldQuery.ground_y(_main.get_world_3d(), best.x, -best.y)
			if is_nan(g) or float(t["z0"]) - g < 2.2:
				stats["slabs low"] += 1
				continue
			var hit := _ray(MeshUtils.to_godot(best.x, best.y, float(t["z0"]) - 0.1), MeshUtils.to_godot(best.x, best.y, g - 1.0))
			var info := WorldQuery.hit_info(hit)
			if info.get("type") == "building":
				_fail("%s under the %s of #%d %s at (%.1f, %.1f): hit %s" % ["no open space", t["kind"], b["num"], b["id"],
						best.x, best.y, info.get("id")])
			else:
				stats["slabs open" if t["kind"] == "slab" else "passages open"] += 1
	print("open spaces: ", stats)
