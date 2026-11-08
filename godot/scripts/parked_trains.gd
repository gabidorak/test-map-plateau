extends Node3D
## RER B trains stabled in Massy-Palaiseau's storage yard (the "Voie de Garage des trains de la ligne B du RER" and its
## fan of service=yard tracks south-west of the station: world/rail.json yard tracks, tools/rail/yard.py), standing
## still as at off-peak. train_traffic.gd makes it (Main/Traffic/Trains/Parked) on every peer, from the same rail.json,
## so every peer has the same trains without any network state.
## - Tracks: the yard tracks (not the running lines: `main`, `rer`) whose OSM track numbers (rail.json `ref`, OSM
##   railway:track_ref) are the RER B garage's (GARAGE_REFS, "4T"). Along each, the stretch clear of every other track
##   (CLEAR m between track centres, RUN_CLEAR from a running line: the fouling points of the switches and the
##   ladders are left out), less FOUL_MARGIN beyond the fouling points and END_MARGIN before a track's end (the buffer
##   stop). Trains are pushed against the buffer-stop end, front towards the switches, as stabled: an 8-car train (two
##   units) where one fits, else a 4-car unit, at most PER_TRACK a track. About EMPTY_SHARE of the tracks are left
##   empty (picked by a hash of where they are: the same tracks on every peer and at every start).
## - Cars: the MI 79 R of the running trains (train.gd, assets/cars/mi79.glb, mi79.json), each posed between its two
##   bogie pivots on the track's rail line (heading, grade; yard tracks have no cant), each bogie turned to the rail
##   under it. Lamps off, blank displays, doors shut, no cabin lights.
## - Drawing: per kind of car (cab, intermediate) the model's parts merged once into three meshes by material (the
##   body with its shut door leaves, pantograph and display; the interior; the light far shell), and one bogie mesh.
##   Each 4-car unit is one MultiMesh per mesh (7 draws), with the running trains' visibility ranges (train.gd FAR,
##   INSIDE; far shells to FAR_END): about 30 nodes for the whole yard, nothing per frame or per tick. Not drawn on a
##   headless peer.
## - Collision: one box per car (BUILDINGS layer: players, cars and the camera stop on it, it can be stood on), per
##   train one StaticBody3D; the picker names it (meta plateau).

const Train = preload("res://scripts/train.gd")
const Layers = preload("res://scripts/physics_layers.gd")

const GARAGE_REFS := Vector2i(46, 76)       # OSM railway:track_ref of the RER B's garage tracks at Massy-Palaiseau
const CLEAR := 4.0                          # m between track centres: closer is a switch's fouling zone (2.8 m cars)
const RUN_CLEAR := 4.3                      # m from a running line (RER B tracks 1, 2, A, B; the alignment's)
const FOUL_MARGIN := 4.0                    # m kept clear beyond a fouling point
const END_MARGIN := 5.0                     # m kept clear before a track's end (buffer stop)
const GAP := 10.0                           # m between two trains on one track
const PER_TRACK := 2
const EMPTY_SHARE := 0.25                   # of the usable tracks left empty
const CELL := 4.5                           # m, the clearance grid (not under RUN_CLEAR: 3 x 3 cells reach)
const FAR_END := 2000.0                     # m, the far shells' visibility range end
const BOX_BOTTOM := 0.35                    # m above the rail: the collision box (below the body, round the bogies)
const BOX_TOP := 3.85                       # m above the rail (the roof; the folded pantograph above it)

var trains: Array = []                      # {track, ref, cars, units: [[car transforms], ...], bogies, s0, s1, dir}
var tracks_used := 0                        # garage tracks with a usable stretch (tests)
var tracks_empty := 0                       # of them left empty (tests)

var _meshes := {}                           # "cab_near", "cab_inside", "cab_far", "mid_*", "bogie" -> Mesh


## Places the trains from rail.json (the parsed dictionary). Call before adding it to the tree.
func setup(rail: Dictionary) -> void:
	name = "Parked"
	var yard: Dictionary = rail.get("yard", {})
	var tracks: Array = yard.get("tracks", [])
	if tracks.is_empty():
		return
	var lay := Train.layout()
	var car_length: float = lay["car_length"]
	var unit_cars: int = (lay["unit"] as Array).size()
	var unit_len := car_length * unit_cars
	var grid := _grid(rail, tracks)
	var slots: Array = []
	for k in tracks.size():
		var t: Dictionary = tracks[k]
		if t.get("main", false) or t.get("rer", false) or not _garage(String(t.get("ref", ""))):
			continue
		var line := _line(t)
		if line.is_empty():
			continue
		var run := _longest_run(line, k, grid)
		if run.is_empty() or run[1] - run[0] < unit_len:
			continue
		var mid: Vector2 = _at(line, (run[0] + run[1]) * 0.5)[0]
		slots.append({"track": t, "line": line, "run": run, "key": "%d,%d" % [roundi(mid.x / 10.0), roundi(mid.y / 10.0)]})
	tracks_used = slots.size()
	for slot: Dictionary in slots:
		if float(absi(String(slot["key"]).hash()) % 1000) / 1000.0 < EMPTY_SHARE:
			tracks_empty += 1
			continue
		_fill(slot, car_length, unit_cars, lay)
	_build_collision(lay)
	if DisplayServer.get_name() != "headless":
		_build_meshes(lay)


## True when one of the track's OSM numbers is the RER B garage's.
static func _garage(ref: String) -> bool:
	for r in ref.split(",", false):
		var s := r.strip_edges()
		if s == "4T" or (s.is_valid_int() and int(s) >= GARAGE_REFS.x and int(s) <= GARAGE_REFS.y):
			return true
	return false


## A track's drawn run (its stretch on the map's ground) as {p: PackedVector2Array, z, d: distance along, i0: first
## index in the track}; empty if it has none.
static func _line(t: Dictionary) -> Dictionary:
	var pts: Array = t.get("pts", [])
	var zs: Array = t.get("z", [])
	var drawn: Array = t.get("drawn", [0, pts.size() - 1])
	var i0 := int(drawn[0])
	var i1 := mini(int(drawn[1]), mini(pts.size(), zs.size()) - 1)
	if i1 - i0 < 2:
		return {}
	var p := PackedVector2Array()
	var z := PackedFloat32Array()
	var d := PackedFloat32Array()
	var acc := 0.0
	for i in range(i0, i1 + 1):
		var q := Vector2(pts[i][0], pts[i][1])
		if not p.is_empty():
			acc += q.distance_to(p[p.size() - 1])
		p.append(q)
		z.append(zs[i])
		d.append(acc)
	return {"p": p, "z": z, "d": d, "i0": i0, "full": i0 == 0 and i1 == pts.size() - 1}


## The clearance grid: every yard track's points (owner: track index) and the alignment's two tracks near the yard
## (owner -1), in CELL m cells. Running lines (main, rer, the alignment) are flagged.
static func _grid(rail: Dictionary, tracks: Array) -> Dictionary:
	var pts := PackedVector2Array()
	var owner := PackedInt32Array()
	var running := PackedByteArray()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in tracks.size():
		var t: Dictionary = tracks[k]
		var run := 1 if t.get("main", false) or t.get("rer", false) else 0
		for q: Array in t.get("pts", []):
			var v := Vector2(q[0], q[1])
			pts.append(v)
			owner.append(k)
			running.append(run)
			lo = lo.min(v)
			hi = hi.max(v)
	var al: Dictionary = rail.get("alignment", {})
	var box := Rect2(lo, hi - lo).grow(20.0)
	var ap: Array = al.get("pts", [])
	var ah: Array = al.get("heading", [])
	for tr: Dictionary in rail.get("tracks", []):
		var u: float = tr.get("offset", 0.0)
		for i in mini(ap.size(), ah.size()):
			var c := Vector2(ap[i][0], ap[i][1])
			if not box.has_point(c):
				continue
			var h: float = ah[i]
			pts.append(c + Vector2(-sin(h), cos(h)) * u)
			owner.append(-1)
			running.append(1)
	var cells := {}
	for i in pts.size():
		var ck := Vector2i(floori(pts[i].x / CELL), floori(pts[i].y / CELL))
		if not cells.has(ck):
			cells[ck] = []                  # an Array (a packed array in a Dictionary is appended to as a copy)
		(cells[ck] as Array).append(i)
	return {"pts": pts, "owner": owner, "running": running, "cells": cells}


## The longest stretch [d0, d1] (distance along the line) of track k clear of every other track, less the margins;
## empty if none.
static func _longest_run(line: Dictionary, k: int, grid: Dictionary) -> Array:
	var p: PackedVector2Array = line["p"]
	var d: PackedFloat32Array = line["d"]
	var pts: PackedVector2Array = grid["pts"]
	var owner: PackedInt32Array = grid["owner"]
	var running: PackedByteArray = grid["running"]
	var cells: Dictionary = grid["cells"]
	var reach := ceili(RUN_CLEAR / CELL)
	var best := []
	var start := -1
	for i in p.size() + 1:
		var ok := false
		if i < p.size():
			ok = true
			var ck := Vector2i(floori(p[i].x / CELL), floori(p[i].y / CELL))
			for dx in range(-reach, reach + 1):
				for dy in range(-reach, reach + 1):
					var c = cells.get(ck + Vector2i(dx, dy))
					if c == null:
						continue
					for j: int in c:
						if owner[j] == k:
							continue
						var dd := p[i].distance_squared_to(pts[j])
						var need := RUN_CLEAR if running[j] == 1 else CLEAR
						if dd < need * need:
							ok = false
							break
					if not ok:
						break
				if not ok:
					break
		if ok and start < 0:
			start = i
		elif not ok and start >= 0:
			var a := d[start] + (END_MARGIN if start == 0 else FOUL_MARGIN)
			var b := d[i - 1] - (END_MARGIN if i - 1 == p.size() - 1 else FOUL_MARGIN)
			if b > a and (best.is_empty() or b - a > best[1] - best[0]):
				best = [a, b, start == 0, i - 1 == p.size() - 1]
			start = -1
	return best


## [map point, rail level, heading] at distance s along the line (clamped).
static func _at(line: Dictionary, s: float) -> Array:
	var p: PackedVector2Array = line["p"]
	var z: PackedFloat32Array = line["z"]
	var d: PackedFloat32Array = line["d"]
	s = clampf(s, 0.0, d[d.size() - 1])
	var i := d.bsearch(s, true) - 1
	i = clampi(i, 0, p.size() - 2)
	var f := (s - d[i]) / maxf(d[i + 1] - d[i], 1e-6)
	var dir := p[i + 1] - p[i]
	return [p[i].lerp(p[i + 1], f), lerpf(z[i], z[i + 1], f), atan2(dir.y, dir.x)]


## Godot position on the rails at distance s.
static func _g(line: Dictionary, s: float) -> Vector3:
	var a := _at(line, s)
	var q: Vector2 = a[0]
	return Vector3(q.x, a[1], -q.y)


## A frame on the rails between distances a (behind) and b (ahead): origin midway at rail level, +Z towards b, +X to
## the left (train.gd span_frame, without cant); turned round when `back`.
static func _frame(line: Dictionary, a: float, b: float, back := false) -> Transform3D:
	var pa := _g(line, a)
	var pb := _g(line, b)
	var z := (pb - pa).normalized() if pa.distance_squared_to(pb) > 1e-8 else Vector3.FORWARD
	var x := Vector3.UP.cross(z).normalized()
	var basis := Basis(x, z.cross(x), z)
	if back:
		basis = basis.rotated(basis.y, PI)
	return Transform3D(basis.orthonormalized(), (pa + pb) * 0.5)


## Stables trains along a slot's run, from its buffer-stop end (else from its far end), fronts towards the switches.
func _fill(slot: Dictionary, car_length: float, unit_cars: int, lay: Dictionary) -> void:
	var line: Dictionary = slot["line"]
	var run: Array = slot["run"]
	var t: Dictionary = slot["track"]
	# the buffer stop: the end of a run that reaches the track's end (on the map's ground); else the higher-d end
	var from_low: bool = run[2] and not run[3]
	var dir := 1.0 if from_low else -1.0     # towards the switches
	var edge: float = run[0] if from_low else run[1]
	var room: float = run[1] - run[0]
	var unit_len := car_length * unit_cars
	var b: float = absf(float(lay["cab"]["bogies"][0]))
	var formation := Train.formation()       # [kind, turned] from the front, two units
	var n := 0
	while n < PER_TRACK and room >= unit_len:
		var cars := formation.size() if room >= car_length * formation.size() else unit_cars
		var length := car_length * cars
		var front := edge + dir * length         # the front coupler, towards the switches
		var tr := {"track": String(t.get("id", "")), "ref": String(t.get("ref", "")), "cars": cars,
				"s0": minf(edge, front), "s1": maxf(edge, front), "dir": dir, "car_xf": [], "kinds": [], "bogies": [],
				"line": line}
		for c in cars:
			var kind: String = formation[c][0]
			var turned: bool = formation[c][1]
			var mid := front - dir * car_length * (c + 0.5)
			tr["car_xf"].append(_frame(line, mid - dir * b, mid + dir * b, turned))
			tr["kinds"].append(kind)
			for z: float in [b, -b]:
				var at := mid + dir * (-z if turned else z)
				tr["bogies"].append(_frame(line, at - dir * 1.2, at + dir * 1.2, turned))
		trains.append(tr)
		n += 1
		edge = front + dir * GAP
		room -= length + GAP


func _build_collision(lay: Dictionary) -> void:
	var w: float = lay["cab"]["width"]
	var body_len: float = float(lay["cab"]["body"][1]) - float(lay["cab"]["body"][0])
	var box := BoxShape3D.new()
	box.size = Vector3(w, BOX_TOP - BOX_BOTTOM, body_len)
	for k in trains.size():
		var tr: Dictionary = trains[k]
		var body := StaticBody3D.new()
		body.name = "Train%d" % k
		body.collision_layer = Layers.BUILDINGS
		body.collision_mask = 0
		body.set_meta("plateau", {"type": "parked_train", "id": "RER B MI 79 R, %d cars, stabled on track %s (%s), Massy-Palaiseau yard" % [
				tr["cars"], String(tr["ref"]).replace(",", "/"), tr["track"]]})
		for xf: Transform3D in tr["car_xf"]:
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.transform = xf * Transform3D(Basis(), Vector3(0.0, (BOX_TOP + BOX_BOTTOM) * 0.5, 0.0))
			body.add_child(cs)
		add_child(body)


# ---------------------------------------------------------------- drawing

## The model's parts merged per kind of car (once): near (body, shut door leaves, pantograph, display), inside
## (interior, ceiling lights), far (light shell), and the bogie.
func _parts(lay: Dictionary) -> Dictionary:
	if not _meshes.is_empty():
		return _meshes
	var model: Node = (load(Train.MODEL) as PackedScene).instantiate()
	for kind: String in ["cab", "mid"]:
		var nodes: Dictionary = lay[kind]["nodes"]
		var near: Array = []
		var inside: Array = []
		for n in model.get_children():
			var mi := n as MeshInstance3D
			var nm := String(n.name)
			if mi == null or not nm.begins_with(kind + "_"):
				continue
			if nm == nodes.get("body") or nm.contains("_door") or nm == nodes.get("pantograph") or nm == nodes.get("display"):
				near.append([mi.mesh, mi.transform])
			elif nm == nodes.get("interior") or nm == nodes.get("cabin_lights"):
				inside.append([mi.mesh, mi.transform])
		_meshes[kind + "_near"] = _merge(near)
		_meshes[kind + "_inside"] = _merge(inside)
		var far := model.get_node_or_null(String(nodes.get("far", ""))) as MeshInstance3D
		_meshes[kind + "_far"] = far.mesh if far else null          # one mesh at the car's origin
	var bogie := model.get_node_or_null(String(lay["cab"]["nodes"].get("bogie_front", ""))) as MeshInstance3D
	_meshes["bogie"] = bogie.mesh if bogie else null
	model.free()
	return _meshes


## Meshes (each [Mesh, Transform3D]) merged into one, a surface per material.
static func _merge(parts: Array) -> ArrayMesh:
	var groups := {}
	var order: Array = []
	var attrs := Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR \
			| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2
	for part: Array in parts:
		var mesh: Mesh = part[0]
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var key := "%d_%d" % [mat.get_instance_id() if mat else 0, mesh.surface_get_format(s) & attrs]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, mat]
				order.append(key)
			(groups[key][0] as SurfaceTool).append_from(mesh, s, part[1])
	var out := ArrayMesh.new()
	for key: String in order:
		(groups[key][0] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, groups[key][1])
	return out


## Per 4-car unit, one MultiMesh per merged mesh.
func _build_meshes(lay: Dictionary) -> void:
	var parts := _parts(lay)
	var unit_cars: int = (lay["unit"] as Array).size()
	var u := 0
	for tr: Dictionary in trains:
		var xfs: Array = tr["car_xf"]
		for first in range(0, xfs.size(), unit_cars):
			var unit := Node3D.new()
			unit.name = "Unit%d" % u
			u += 1
			add_child(unit)
			var by_kind := {"cab": [], "mid": []}
			for c in range(first, mini(first + unit_cars, xfs.size())):
				by_kind[tr["kinds"][c]].append(xfs[c])
			for kind: String in by_kind:
				_multimesh(unit, kind + "_near", parts.get(kind + "_near"), by_kind[kind], 0.0, Train.FAR, true)
				_multimesh(unit, kind + "_inside", parts.get(kind + "_inside"), by_kind[kind], 0.0, Train.INSIDE, false)
				_multimesh(unit, kind + "_far", parts.get(kind + "_far"), by_kind[kind], Train.FAR, FAR_END, true)
			var bogies: Array = (tr["bogies"] as Array).slice(first * 2, mini(first + unit_cars, xfs.size()) * 2)
			_multimesh(unit, "bogies", parts.get("bogie"), bogies, 0.0, Train.FAR, true)


func _multimesh(parent: Node3D, label: String, mesh: Mesh, xfs: Array, begin: float, end: float, shadows: bool) -> void:
	if mesh == null or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
