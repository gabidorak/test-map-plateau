extends Node3D
## Restyled buildings: some of the map's large buildings redrawn with real facades, each after its spec
## (data/restyle/<slug>.json: restyle_spec.gd), made by restyle_building.gd; in every game mode (game.gd). The map's
## building leaves the world when it is built (drop, builder/world_builder.gd) and a garden's trees and hedges come
## in; the ground's paint in the grounds turns to lawn or meadow (repaint, builder/ground_builder.gd) and the grass field
## follows (grass_field.gd overrides); the ground is smoothed by restyle_ground.gd.

const Spec = preload("res://scripts/restyle/restyle_spec.gd")
const Building = preload("res://scripts/restyle/restyle_building.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const RestyleGround = preload("res://scripts/restyle/restyle_ground.gd")
const PATH_MATS := ["concrete", "paving", "sett", "gravel", "dirt", "wood"]
## A garden's ground (site.garden): what becomes its lawn or meadow (roads, water, courts, buildings stay).
const SOFT := ["concrete", "paving", "sett", "gravel", "dirt", "wood", "grass", "tall_grass", "sand", "forest_floor",
		"construction", "clay"]
const TREE_TINTS := ["leaf", "deep", "spring", "lime"]


var built := {}                              # slug -> {"node": Node3D, "floor": y of its ground floor, "ms"}


## The world without the restyled buildings (builder/world_builder.gd, before the buildings are made): their records,
## their name signs, the kit modules on them, the trees on them and on their walks.
static func drop(world: Dictionary) -> void:
	for s: Dictionary in Spec.specs():
		var ids: Array = s.get("replace", [])
		var osm: Array = ids.map(func(i: Variant) -> String: return str(i).trim_prefix("osm:"))
		var rings := Spec.rings_of(s)
		world["buildings"] = world["buildings"].filter(func(b: Dictionary) -> bool:
			return not (str(b["id"]).split("_rest")[0] in ids))
		world["building_signs"] = world["building_signs"].filter(func(x: Dictionary) -> bool:
			return not (str(x.get("building", "")) in osm))
		if not rings.is_empty():
			var grown := Geometry2D.offset_polygon(rings[0], 1.0)
			var near: PackedVector2Array = grown[0] if not grown.is_empty() else rings[0]
			world["building_modules"] = world["building_modules"].filter(func(m: Dictionary) -> bool:
				return not Geometry2D.is_point_in_polygon(Vector2(m["x"], m["y"]), near))
		var garden: Dictionary = s.get("site", {}).get("garden", {})
		if not garden.is_empty():
			_plant(s, garden, world)
		var walks := Spec.walk_polys(s, 1.0)
		world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool:
			var p := Vector2(t["x"], t["y"])
			if Spec.inside(rings, p):
				return false
			for w in walks:
				if Geometry2D.is_point_in_polygon(p, w):
					return false
			return true)


## A garden's trees and hedges (site.garden, read off an aerial image by tools/restyle.py garden) into the world, the
## map's in its grounds out ("replace").
static func _plant(s: Dictionary, garden: Dictionary, world: Dictionary) -> void:
	var area := Spec.poly(s["site"]["area"])
	if str(garden.get("trees_mode", "replace")) == "replace":
		world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool:
			return not Geometry2D.is_point_in_polygon(Vector2(t["x"], t["y"]), area))
	if str(garden.get("hedges_mode", "replace")) == "replace":
		world["hedges"] = world["hedges"].filter(func(h: Dictionary) -> bool:
			for q: Array in h["pts"]:
				if Geometry2D.is_point_in_polygon(Vector2(q[0], q[1]), area):
					return false
			return true)
	var arch: Dictionary = world["tree_archetypes"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s["slug"]) + ":garden")
	var k := 0
	for t: Array in garden.get("trees", []):
		var r := float(t[2])
		var kind := "sapling" if r < 1.6 and arch.has("sapling") else ("oval" if r < 2.8 else "round")
		world["trees"].append({"id": "restyle:%s:tree:%d" % [s["slug"], k], "x": float(t[0]), "y": float(t[1]),
				"h": clampf(2.4 * r + 2.0, 3.5, 19.0) * rng.randf_range(0.9, 1.1), "r": r, "arch": kind,
				"var": rng.randi() % maxi(1, int(arch.get(kind, 1))), "tint": TREE_TINTS[rng.randi() % TREE_TINTS.size()],
				"src": "restyle"})
		k += 1
	k = 0
	for hd: Dictionary in garden.get("hedges", []):
		world["hedges"].append({"id": "restyle:%s:hedge:%d" % [s["slug"], k], "pts": hd["pts"],
				"h": float(hd.get("h", 1.8)), "w": float(hd.get("w", 1.5)), "tint": "deep", "src": "restyle",
				"height_src": "restyle"})
		k += 1


## The ground's paint (builder/ground_builder.gd, a chunk's vertices): in the restyled buildings' grounds, the coarse
## paint of paths and paved patches turns to lawn (the spec's paths are drawn crisp over it, the rest goes); in a
## garden (site.garden) all its soft ground is its lawn ("grass": "mowed") or meadow ("meadow", and in its meadows).
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var grass := materials.find("grass")
	var tall := materials.find("tall_grass")
	var grass_colour := Color.html(str(palette.get("grass", "#7cb342")))
	var tall_colour := Color.html(str(palette.get("tall_grass", palette.get("grass", "#9aa84a"))))
	var path_ids: Array = PATH_MATS.map(func(m: String) -> int: return materials.find(m))
	var soft_ids: Array = SOFT.map(func(m: String) -> int: return materials.find(m))
	for s: Dictionary in Spec.specs():
		var area := Spec.poly(s.get("site", {}).get("area", []))
		if area.size() < 3:
			continue
		var garden: Dictionary = s["site"].get("garden", {})
		var meadows: Array[PackedVector2Array] = []
		for m: Array in garden.get("meadows", []):
			meadows.append(Spec.poly(m))
		var all_meadow := str(garden.get("grass", "mowed")) == "meadow"
		var box := Rect2(area[0], Vector2.ZERO)
		for p in area:
			box = box.expand(p)
		for k in verts.size():
			var p := Vector2(verts[k].x, -verts[k].z)
			if not box.has_point(p):
				continue
			var id := int(ids[k * 4])
			if not (id in (path_ids if garden.is_empty() else soft_ids)) or not Geometry2D.is_point_in_polygon(p, area):
				continue
			var meadow := all_meadow
			for m in meadows:
				meadow = meadow or Geometry2D.is_point_in_polygon(p, m)
			ids[k * 4] = tall if meadow else grass
			colours[k] = tall_colour if meadow else grass_colour
	return [ids, colours]


## A garden's ground for the grass field (grass_field.gd overrides), by its grid (site.garden.grid: 1 lawn, 2 meadow,
## 3 path): none on its paths, tall in its meadows, mown on the rest of its soft ground; -2 out of it (the map's).
static func _grass_at(x: float, y: float, z: Dictionary) -> int:
	if not (z["box"] as Rect2).has_point(Vector2(x, y)):
		return -2
	var w: int = z["w"]
	var i := clampi(floori((x - float(z["x0"])) / float(z["cell"])), 0, w - 1)
	var j := clampi(floori((float(z["y0"]) - y) / float(z["cell"])), 0, int(z["h"]) - 1)
	var kind: int = (z["kind"] as PackedByteArray)[j * w + i]
	if kind == 0:
		return -2
	var gm: GroundMap = GroundMap.get_map()
	if gm == null:
		return -2
	if kind == 3:
		return gm.materials.find("concrete")
	var id: int = gm.material_at(x, y)
	if id < 0 or not (str(gm.materials[id]) in SOFT):
		return -2
	return gm.materials.find("tall_grass" if kind == 2 else "grass")


## Spec s's garden for the grass field.
static func _grass_zone(s: Dictionary) -> void:
	var grid: Dictionary = s.get("site", {}).get("garden", {}).get("grid", {})
	if grid.is_empty():
		return
	var cell := float(grid["cell"])
	var x0 := float(grid["origin"][0])
	var y0 := float(grid["origin"][1])
	GrassField.overrides.append(_grass_at.bind({"box": Rect2(x0, y0 - cell * int(grid["h"]), cell * int(grid["w"]),
			cell * int(grid["h"])), "x0": x0, "y0": y0, "cell": cell, "w": int(grid["w"]), "h": int(grid["h"]),
			"kind": RestyleGround.layer(grid, "kind")}))


func _ready() -> void:
	name = "Restyle"
	var meshes := DisplayServer.get_name() != "headless"
	for s: Dictionary in Spec.specs():
		var t0 := Time.get_ticks_msec()
		_grass_zone(s)
		var b := Building.new()
		var node := b.build(s, meshes)
		add_child(node)
		built[s["slug"]] = {"node": node, "floor": b.floor_y(), "ms": Time.get_ticks_msec() - t0}
