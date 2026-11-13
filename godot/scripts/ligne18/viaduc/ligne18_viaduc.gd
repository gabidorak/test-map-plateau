extends Node3D
## Lot ligne18-viaduc (data/lots/ligne18-viaduc.json, a child of ligne18): line 18's viaduct on the plateau, on the
## line's master plan (scripts/ligne18/ligne18_plan.gd, frozen): the ramp from s_start between its retaining walls to
## the abutment, the deck on every span from there to s_edge but over the stations' zones (each station's lot builds
## its deck there, face to face with ours at zone_s), the parapets, the piers where the plan puts them, and the two
## tracks along the whole line, through the stations too (viaduc_builder.gd; what goes where: viaduc_layout.gd).
## Built at start, cell by cell (about 200 m of s each, cut at piers): their collision at once, their meshes (near
## and far) on a worker thread, the cells nearest the player first (about 1.5 s for them all).
## Each cell its own streaming cell: full detail near the camera, its own far shape beyond (world_streamer.gd's
## add_cell(), as builder/lot_far.gd does for the lots' buildings; the cells are in its group lot_own_visibility: the
## generic far shapes, surveyed buildings lit at night, would not read as a viaduct). Out of the map when it is built (drop()): the trees within TREE_V m of the axis from
## s_start to s_edge; the props, fences and hedges on the piers' footprints (and the ramp's), FOOTPRINT_MARGIN m round.

const Plan = preload("res://scripts/ligne18/ligne18_plan.gd")
const Layout = preload("res://scripts/ligne18/viaduc/viaduc_layout.gd")
const Builder = preload("res://scripts/ligne18/viaduc/viaduc_builder.gd")
const TREE_V := 8.0                         # m off the axis: the map's trees out
const FOOTPRINT_MARGIN := 0.3               # m round the piers' shafts: the props, fences, hedges out

signal done                                 # every cell's meshes in place

var game: Node                              # game.gd (null in the tools)
var cells: Array[Node3D] = []
var _task := -1
var _stop := false
var _left := 0


## The world without the map's trees along the line, nor what stands on the piers' footprints.
static func drop(world: Dictionary) -> void:
	var s0 := Layout.s_start()
	var s1 := Layout.s_edge()
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool:
		var sv := Plan.project(Vector2(t["x"], t["y"]), TREE_V + 1.0)
		return is_nan(sv.x) or sv.x < s0 or sv.x > s1 or absf(sv.y) > TREE_V)
	world["props"] = world["props"].filter(func(p: Dictionary) -> bool:
		return not Layout.on_footprint(Vector2(p["x"], p["y"]), FOOTPRINT_MARGIN))
	for key: String in ["fences", "hedges"]:                 # (their lines cut: their runs off the footprints kept)
		var kept := []
		for rec: Dictionary in world.get(key, []):
			var runs := _runs_off(rec["pts"])
			if runs.size() == 1 and (runs[0] as Array).size() == (rec["pts"] as Array).size():
				kept.append(rec)
				continue
			for k in runs.size():
				var r: Dictionary = rec.duplicate()
				r["pts"] = runs[k]
				if r.has("id") and runs.size() > 1:
					r["id"] = "%s~%d" % [rec["id"], k]
				kept.append(r)
		world[key] = kept


## A line's runs off the footprints (points [x, y] or [x, y, z]): cut where it goes on one (looked at every 0.25 m
## along the segments near the line).
static func _runs_off(pts: Array) -> Array:
	var runs := []
	var run := []
	for i in pts.size():
		var a: Array = pts[i]
		var pa := Vector2(a[0], a[1])
		var was := Layout.on_footprint(pa, FOOTPRINT_MARGIN)
		if was:
			if run.size() >= 2:
				runs.append(run)
			run = []
		else:
			run.append(a)
		if i == pts.size() - 1:
			break
		var b: Array = pts[i + 1]
		var pb := Vector2(b[0], b[1])
		if not _near_line(pa, pb):
			continue
		var n := ceili(pa.distance_to(pb) / 0.25)
		for k in range(1, n + 1):
			var on := Layout.on_footprint(pa.lerp(pb, float(k) / n), FOOTPRINT_MARGIN)
			if on == was:
				continue
			var j := k - 1 if on else k                     # (the cut: its last point off it, or its first)
			var m := pa.lerp(pb, float(j) / n)
			var cut: Array = [m.x, m.y]
			if a.size() > 2 and b.size() > 2:
				cut.append(lerpf(float(a[2]), float(b[2]), float(j) / n))
			if on:
				if j > 0:
					run.append(cut)
				if run.size() >= 2:
					runs.append(run)
				run = []
			elif k < n:
				run = [cut]
			was = on
	if run.size() >= 2:
		runs.append(run)
	return runs


## Whether segment a b comes within 40 m of the axis.
static func _near_line(a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 20.0))
	for k in n + 1:
		if not is_nan(Plan.project(a.lerp(b, float(k) / n), 40.0).x):
			return true
	return false


func _ready() -> void:
	name = "Ligne18Viaduc"
	var t0 := Time.get_ticks_msec()
	var meshes := DisplayServer.get_name() != "headless"
	var b := Builder.new()
	for k in Layout.cell_count():
		var c := b.build_cell(k, meshes)
		add_child(c)
		cells.append(c)
	if not meshes:
		return
	_stream()
	# the meshes (near and far) on a worker thread, the cells nearest the player first
	var from := Vector3.ZERO
	var player: Node3D = game.get("player") if game and "player" in game else null
	if player:
		from = player.global_position
	var order := range(cells.size())
	order.sort_custom(func(i: int, j: int) -> bool: return _dist(cells[i], from) < _dist(cells[j], from))
	_left = order.size()
	_task = WorkerThreadPool.add_task(_work.bind(order), false, "ligne18-viaduc: meshes")
	print("ligne18-viaduc: %d cells' collision in %d ms (their meshes on a worker thread)" % [cells.size(),
			Time.get_ticks_msec() - t0])


static func _dist(c: Node3D, p: Vector3) -> float:
	var box: AABB = c.get_meta("box")
	return p.distance_to(p.clamp(box.position, box.end))


func _exit_tree() -> void:
	_stop = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## On a worker thread: the cells' meshes computed, each put in place on the main thread.
func _work(order: Array) -> void:
	var b := Builder.new()
	for k: int in order:
		if _stop:
			return
		_fill.call_deferred(k, b.mesh_arrays(k))


func _fill(k: int, arrays: Dictionary) -> void:
	if is_inside_tree():
		Builder.fill(cells[k], arrays)
	_left -= 1
	if _left == 0:
		done.emit()


## Each cell one of the world streamer's (as builder/lot_far.gd does): its near meshes (all under "Near"), its far
## shape, its box (made before them: viaduc_builder.gd).
func _stream() -> void:
	var root: Node = game.get("world_root") if game else null
	var streamer: Node = root.get_node_or_null("Streamer") if root else null
	if streamer == null:
		return                                              # (no streamer: full detail, the far shapes hidden)
	for c in cells:
		var near: Array[Node3D] = [c.get_node("Near") as Node3D]
		streamer.add_cell(near, c.get_meta("far", null), c.get_meta("box"))
