extends RefCounted
## Edits of the map's world (world.json) before it is built (builder/world_builder.gd): what the runtime builds take
## over (Losplatos Custom, All Suites Study, the Villa de charme, the restyled buildings).


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
