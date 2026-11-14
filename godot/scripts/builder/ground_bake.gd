extends RefCounted
## The ground the game reads (ground_map.gd), baked when the map is built (builder/world_builder.gd): the map's own
## (world/ground_index.json) on the heightmap as built, the lots' terraforming in it (builder/terraform.gd), with the
## lots' surfaces among its pieces. Each lot's script (builder/lots.gd), and the restyled buildings', may give:
##   surface_boxes() -> Array                       [Rect2] where (map x, y) it lays surfaces of its own
##   surface_at(x, y, current: String) -> String    the surface's material at map (x, y), a name of the index's
##                                                  "materials"; "" where the map's (`current`) stays
## laid in the lots' order (a later lot over an earlier one) at each sample of the ids' grid (0.5 m). In the game they
## are the map's ground like any other: the grass grows on the lawns only, the bots see the roads, the picker names
## them. Saved to res://scenes/generated/ (ground_map.gd DEFAULT_INDEX) with the scene.

const GroundMap = preload("res://scripts/ground_map.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const Lots = preload("res://scripts/builder/lots.gd")
## A surface's piece kind by its material (the bots drive on "road"s: game.gd _paved(), races.gd); others "pedestrian".
const KIND := {"asphalt": "road", "grass": "landcover", "tall_grass": "landcover", "gravel": "landcover",
		"building": "building"}
const ABOUT := "The ground the game reads, baked by builder/ground_bake.gd when the map was built: the map's own " \
		+ "(world/ground_index.json) with the lots' terraforming in its heights and their surfaces among its pieces."


## The ground being built: the map's (world/ground_index.json) on `heights` (the heightmap, terraformed: world.json
## "terrain"), the lots' surfaces laid. It is the ground every reader gets while the map is built (a lot's surfaces may
## read it: the villa's steps follow it).
static func make(world: Dictionary, world_dir: String, heights: PackedFloat32Array) -> RefCounted:
	var t: Dictionary = world["terrain"]
	var h := GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"])
	var map: RefCounted = GroundMap.from_map_index(world_dir.path_join(String(world["ground_mesh"]["index"])), h)
	if map == null:
		return null
	GroundMap.install(map)
	var layers := []                                         # [name, script]
	for lot: Dictionary in Lots.all():
		if lot.has("script"):
			layers.append([str(lot["id"]), load(str(lot["script"]))])
	if not Lots.restyle_slugs().is_empty():
		layers.append(["restyle", load(Lots.RESTYLE)])
	for l: Array in layers:
		if (l[1] as Script).has_method("surface_at"):
			var t0 := Time.get_ticks_msec()
			var n := _lay(map, l[0], l[1])
			print("ground: lot %s, %d samples (%d ms)" % [l[0], n, Time.get_ticks_msec() - t0])
	return map


## Lot `id`'s surfaces (its script's) into the map's pieces: how many samples it took.
static func _lay(map: RefCounted, id: String, script: Script) -> int:
	var g: Dictionary = map.ids_grid()
	var cell: float = g["cell"]
	var o: Vector2 = g["origin"]
	var mats: Array = map.materials
	var piece_mat: PackedByteArray = map.piece_material
	var made := {}                                            # material -> its piece
	var n := 0
	for box: Rect2 in script.surface_boxes():
		var c0 := maxi(0, ceili((box.position.x - o.x) / cell))
		var c1 := mini(int(g["w"]) - 1, floori((box.end.x - o.x) / cell))
		var r0 := maxi(0, ceili((o.y - box.end.y) / cell))
		var r1 := mini(int(g["h"]) - 1, floori((o.y - box.position.y) / cell))
		for r in range(r0, r1 + 1):
			var y := o.y - r * cell
			for c in range(c0, c1 + 1):
				var k: int = map.piece_at_sample(c, r)
				var mi := int(piece_mat[k]) if k >= 0 and k < piece_mat.size() else -1
				var current := str(mats[mi]) if mi >= 0 and mi < mats.size() else ""
				var m: String = script.surface_at(o.x + c * cell, y, current)
				if m == "" or m == current:
					continue
				if not made.has(m):
					if not m in mats:
						push_error("lot %s: no ground material %s" % [id, m])
						return n
					made[m] = map.add_piece(KIND.get(m, "pedestrian"), m, "lot:" + id)
					piece_mat = map.piece_material
				map.set_piece_at_sample(c, r, made[m])
				n += 1
	return n
