extends RefCounted
## Edits of the map's world (world.json) before it is built (builder/world_builder.gd), by the lots (builder/lots.gd
## drop()): what they take over.
## - drop_buildings(): buildings out with their name signs and kit modules (a lot's code: Losplatos Custom, All Suites
##   Study, the Villa de charme, the restyled buildings...);
## - apply(): a lot's changes as its tool decided them (its "drop": data/<lot>/drop.json, or its plan's;
##   tools/common/world_edits.py has the keys and does the same in Python), in this order:
##   trees_gone [id], trees_add [tree], hedges_add [hedge]
##   props_gone [id], props_moved {id: [x, y]}, props_lift {id: lift}, props_add [prop]
##   fences_gone [id], fences_add [fence]
##   kerbs_clear [ring]: the kerbs cut back out of these polygons (what is left under KERB_MIN m dropped)
##   kerbs_cut [{from, to, runs}]: the kerb running from -> to (its first and last points) replaced by these runs
##   modules_clear [ring]: the kit modules standing inside them out; modules_gone [[m, x, y, z]]: those out
##   buildings_gone [id] (and their name signs), buildings [building]: each replacing the building of its id
##   bridges_gone [id]
##   markings_cut [{src, first, verts, tris}]: the marking of that src whose first vertex is `first` replaced (no
##   tris: gone)
## Adds skip an id the world has already: applying them twice changes nothing.

const KERB_MIN := 0.3


## The buildings `ids` ("osm:w123", their "_rest" parts too) out of the world, their name signs, and the kit modules
## standing in `area` (a map polygon; none: no modules out).
static func drop_buildings(world: Dictionary, ids: Array, area := PackedVector2Array()) -> void:
	var osm: Array = ids.map(func(i: Variant) -> String: return str(i).trim_prefix("osm:"))
	world["buildings"] = world["buildings"].filter(func(b: Dictionary) -> bool:
		return not (str(b["id"]).split("_rest")[0] in ids))
	world["building_signs"] = world["building_signs"].filter(func(s: Dictionary) -> bool:
		return not (str(s.get("building", "")) in osm))
	if area.size() >= 3:
		world["building_modules"] = world["building_modules"].filter(func(m: Dictionary) -> bool:
			return not Geometry2D.is_point_in_polygon(Vector2(m["x"], m["y"]), area))


## `poly` grown by `d` m (itself when it cannot be).
static func grown(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var g := Geometry2D.offset_polygon(poly, d)
	return g[0] if not g.is_empty() else poly


## The edits in file `path` (a lot's drop.json) applied to world.
static func apply_file(world: Dictionary, path: String) -> void:
	var e = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not e is Dictionary:
		push_error("cannot read %s" % path)
		return
	apply(world, e)


static func apply(world: Dictionary, e: Dictionary) -> void:
	world["trees"] = _add(_without(world["trees"], e.get("trees_gone", [])), e.get("trees_add", []))
	world["hedges"] = _add(world["hedges"], e.get("hedges_add", []))
	var gone := _id_set(e.get("props_gone", []))
	var moved: Dictionary = e.get("props_moved", {})
	var lift: Dictionary = e.get("props_lift", {})
	var props := []
	for p: Dictionary in world["props"]:
		var id := str(p["id"])
		if gone.has(id):
			continue
		if moved.has(id) or lift.has(id):
			p = p.duplicate()
			if moved.has(id):
				p["x"] = moved[id][0]
				p["y"] = moved[id][1]
			if lift.has(id):
				p["lift"] = lift[id]
		props.append(p)
	world["props"] = _add(props, e.get("props_add", []))
	world["fences"] = _add(_without(world["fences"], e.get("fences_gone", [])), e.get("fences_add", []))
	if e.has("kerbs_clear"):
		world["kerbs"] = _clear_kerbs(world["kerbs"], e["kerbs_clear"].map(_ring))
	if e.has("kerbs_cut"):
		var cuts := {}
		for c: Dictionary in e["kerbs_cut"]:
			cuts[_key([c["from"][0], c["from"][1], c["to"][0], c["to"][1]])] = c["runs"]
		var kerbs := []
		for kb: Dictionary in world["kerbs"]:
			var pts: Array = kb["pts"]
			var k := _key([pts[0][0], pts[0][1], pts[-1][0], pts[-1][1]]) if not pts.is_empty() else ""
			if not cuts.has(k):
				kerbs.append(kb)
				continue
			for r: Array in cuts[k]:
				var part := kb.duplicate()
				part["pts"] = r
				kerbs.append(part)
		world["kerbs"] = kerbs
	if e.has("modules_clear"):
		var clear: Array = e["modules_clear"].map(_ring)
		world["building_modules"] = world["building_modules"].filter(func(m: Dictionary) -> bool:
			var q := Vector2(m["x"], m["y"])
			return not clear.any(func(c: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(q, c)))
	if e.has("modules_gone"):
		var out := {}
		for k: Array in e["modules_gone"]:
			out[_key(k)] = true
		world["building_modules"] = world["building_modules"].filter(func(m: Dictionary) -> bool:
			return not out.has(_key([m["m"], m["x"], m["y"], m["z"]])))
	var gone_b := _id_set(e.get("buildings_gone", []))
	var swap := {}
	for b: Dictionary in e.get("buildings", []):
		swap[str(b["id"])] = b
	if not gone_b.is_empty() or not swap.is_empty():
		var buildings := []
		for b: Dictionary in world["buildings"]:
			if not gone_b.has(str(b["id"])):
				buildings.append(swap.get(str(b["id"]), b))
		world["buildings"] = buildings
		if not gone_b.is_empty():
			world["building_signs"] = world["building_signs"].filter(func(s: Dictionary) -> bool:
				return not gone_b.has("osm:" + str(s.get("building", ""))))
	world["bridges"] = _without(world.get("bridges", []), e.get("bridges_gone", []))
	if e.has("markings_cut"):
		var cuts := {}
		for c: Dictionary in e["markings_cut"]:
			cuts[_key([c["src"], c["first"][0], c["first"][1]])] = c
		var marks := []
		for mk: Dictionary in world["markings"]:
			var v: Array = mk["verts"]
			var k := _key([mk.get("src", ""), v[0][0], v[0][1]]) if not v.is_empty() else ""
			if not cuts.has(k):
				marks.append(mk)
			elif not (cuts[k]["tris"] as Array).is_empty():
				var m := mk.duplicate()
				m["verts"] = cuts[k]["verts"]
				m["tris"] = cuts[k]["tris"]
				marks.append(m)
		world["markings"] = marks


## The kerbs cut back out of polygons `clear` (map rings).
static func _clear_kerbs(kerbs_in: Array, clear: Array) -> Array:
	var kerbs := []
	for kb: Dictionary in kerbs_in:
		if (kb["pts"] as Array).size() < 2:
			kerbs.append(kb)
			continue
		var runs := [_ring(kb["pts"])]
		for c: PackedVector2Array in clear:
			var cut := []
			for r: PackedVector2Array in runs:
				cut.append_array(Geometry2D.clip_polyline_with_polygon(r, c))
			runs = cut
		if runs.size() == 1 and runs[0].size() == (kb["pts"] as Array).size():
			kerbs.append(kb)                                            # (untouched)
			continue
		for r: PackedVector2Array in runs:
			var length := 0.0
			for i in r.size() - 1:
				length += r[i].distance_to(r[i + 1])
			if length > KERB_MIN:
				var k := kb.duplicate()
				k["pts"] = Array(r).map(func(q: Vector2) -> Array: return [snappedf(q.x, 0.001), snappedf(q.y, 0.001)])
				kerbs.append(k)
	return kerbs


static func _without(items: Array, ids: Array) -> Array:
	if ids.is_empty():
		return items
	var gone := _id_set(ids)
	return items.filter(func(i: Dictionary) -> bool: return not gone.has(str(i["id"])))


static func _add(items: Array, new: Array) -> Array:
	if new.is_empty():
		return items
	var have := {}
	for i: Dictionary in items:
		have[str(i.get("id", ""))] = true
	for i: Dictionary in new:
		if not have.has(str(i.get("id", ""))):
			items.append(i)
	return items


static func _id_set(ids: Array) -> Dictionary:
	var out := {}
	for id: Variant in ids:
		out[str(id)] = true
	return out


## A key of values read from JSON on both sides (the same text, the same floats): their exact text.
static func _key(values: Array) -> String:
	return var_to_str(values)


static func _ring(r: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in r:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out
