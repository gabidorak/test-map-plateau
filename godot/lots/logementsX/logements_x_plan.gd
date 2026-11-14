extends RefCounted
## Lot logementsX's design (lots/logementsX/plan.json, made by godot/lots/logementsX/tool/build_plan.py: its docstring and
## logements_x.py's say what is in it), read once: the plots, the car park, the sidewalk's kerb, the site's changes to
## the world (`site`), its ground repair (`repairs`), its zones (`zones`: each a ground piece [kind, material] over
## polygons [outer ring, holes...]; the sidewalk's at its kerb's level along `axis`). Map metres, x east, y north.

const PATH := "res://lots/logementsX/plan.json"

static var _data: Dictionary
static var _zones: Array = []               # [material, [[outer, holes...]...], their box, axis, axis_z]
static var _box := Rect2()


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


## A ring of the plan ([[x, y]...]) as a polygon.
static func ring(r: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in r:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


## The zones: [source ("logx:road"...), material, kind, polygons [[outer, holes...]...], box, axis, axis_z].
static func zones() -> Array:
	if _zones.is_empty():
		for z: Dictionary in data()["zones"]:
			var polys := []
			var outer := PackedVector2Array()
			for pg: Array in z["polygons"]:
				var rings: Array = pg.map(func(r: Array) -> PackedVector2Array: return ring(r))
				polys.append(rings)
				outer.append_array(rings[0])
			var box := Rect2(outer[0], Vector2.ZERO)
			for q in outer:
				box = box.expand(q)
			var axis := ring(z.get("axis", []))
			var az := PackedFloat32Array(z.get("axis_z", []))
			_zones.append([str(z["source"]), str(z["piece"][1]), str(z["piece"][0]), polys, box, axis, az])
			_box = box if not _box.has_area() else _box.merge(box)
	return _zones


## The site's box (its zones').
static func box() -> Rect2:
	zones()
	return _box


## Whether map point p is in polygon pg ([outer, holes...]).
static func inside(p: Vector2, pg: Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, pg[0]):
		return false
	for k in range(1, pg.size()):
		if Geometry2D.is_point_in_polygon(p, pg[k]):
			return false
	return true


## The material of the zone at map point p ("" out of them).
static func material_at(p: Vector2) -> String:
	for z: Array in zones():
		if (z[4] as Rect2).has_point(p):
			for pg: Array in z[3]:
				if inside(p, pg):
					return z[1]
	return ""


## Whether the zones of material `mat` are drawn over the ground (logements_x_builder.gd); the lawns are the ground's
## own, the plots' under the buildings.
static func drawn(mat: String) -> bool:
	return mat != "" and mat != "grass" and mat != "building"


## A zone's height along its axis at map point p (the sidewalk: its kerb's level), at the nearest point of the axis.
static func axis_z(axis: PackedVector2Array, az: PackedFloat32Array, p: Vector2) -> float:
	var best := INF
	var z := 0.0
	for i in axis.size() - 1:
		var a := axis[i]
		var b := axis[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			z = lerpf(az[i], az[i + 1], t)
	return z
