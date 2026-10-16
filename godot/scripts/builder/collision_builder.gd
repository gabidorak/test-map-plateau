@tool
extends RefCounted
## Static collision for the generated world: terrain height-field tiles, the invisible
## boundary around the playable area. Building shapes come from building_builder.gd, raised
## sidewalks from ground_builder.gd.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
const TILE := 128           # metres per terrain tile (square, power of two: Jolt's fast path)
const STEP := 2             # heightmap samples are 0.5 m, collision uses every 2nd (1 m)
const WALL_THICKNESS := 2.0
const WALL_HEIGHT := 400.0


## One StaticBody3D with a HeightMapShape3D per tile, sampled every 1 m on the ground as the ground
## mesh draws it (ground_heights.gd), so the player's feet stay on the visible ground. Where the ground steps (the
## railway's walls, platform edges, stairwells and trench: tools/rail/patch_world.py) the height field cannot follow
## it: world.json ground_mesh.holes lists those samples (heightmap row, column), left out as holes (NAN, which Jolt
## takes as a hole), and the ground mesh's raised collision faces cover them exactly (ground_builder.gd).
func terrain(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String) -> void:
	var t: Dictionary = world["terrain"]
	var w: int = t["w"]
	var h: int = t["h"]
	var cell: float = t["cell"]
	var ox: float = t["origin_xy"][0]
	var oy: float = t["origin_xy"][1]
	assert(is_equal_approx(cell * STEP, 1.0), "HeightMapShape3D samples must be 1 m apart")
	var span := TILE * STEP                 # heightmap cells per tile side
	var n := TILE + 1                       # samples per tile side
	var ground := GroundHeights.new(heights, w, h, cell, ox, oy, world["ground_mesh"]["cell"])
	var holes := {}                         # Vector2i(tile row, tile column) -> PackedInt32Array of sample rows, columns
	for hs: Array in world["ground_mesh"].get("holes", {}).get("samples", []):
		var r: int = hs[0]
		var c: int = hs[1]
		# a sample on a tile's edge belongs to both tiles sharing it
		for tr in [r / span, (r - 1) / span]:
			for tc in [c / span, (c - 1) / span]:
				var key := Vector2i(tr, tc)
				if r >= tr * span and r <= (tr + 1) * span and c >= tc * span and c <= (tc + 1) * span:
					if not holes.has(key):
						holes[key] = PackedInt32Array()
					if not (holes[key] as PackedInt32Array).has(r * 65536 + c):
						holes[key].append(r * 65536 + c)

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "terrain", "id": "terrain"})
	root.add_child(body)
	for r0 in range(0, h - 1, span):
		for c0 in range(0, w - 1, span):
			var data := PackedFloat32Array()
			data.resize(n * n)
			for i in n:
				var y := oy - (r0 + i * STEP) * cell
				for j in n:
					data[i * n + j] = ground.at(ox + (c0 + j * STEP) * cell, y)
			for rc: int in holes.get(Vector2i(r0 / span, c0 / span), PackedInt32Array()):
				var i := (rc / 65536 - r0) / STEP
				var j := (rc % 65536 - c0) / STEP
				if i >= 0 and i < n and j >= 0 and j < n:
					data[i * n + j] = NAN
			var shape := HeightMapShape3D.new()
			shape.map_width = n
			shape.map_depth = n
			shape.map_data = data
			var tag := "%d_%d" % [r0 / span, c0 / span]
			MeshUtils.save(shape, mesh_dir + "terrain_col_%s.res" % tag)
			var cs := CollisionShape3D.new()
			cs.name = "Tile_" + tag
			cs.shape = shape
			# HeightMapShape3D is centred on its node: sample (i, j) sits at (j - TILE/2, -, i - TILE/2)
			var mid := TILE / 2 * STEP
			cs.position = MeshUtils.to_godot(ox + (c0 + mid) * cell, oy - (r0 + mid) * cell, 0.0)
			cs.set_meta("plateau", {"type": "terrain", "id": "terrain:" + tag})
			body.add_child(cs)


## Invisible walls on the four sides of world.json `playable`.
func boundary(root: Node3D, world: Dictionary) -> void:
	var p: Array = world["meta"]["playable"]
	var x0: float = p[0]
	var y0: float = p[1]
	var x1: float = p[2]
	var y1: float = p[3]
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = Layers.BOUNDARY
	body.collision_mask = 0
	body.set_meta("plateau", {"type": "boundary", "id": "boundary"})
	root.add_child(body)
	var t := WALL_THICKNESS
	var sides := {
		"West": [Vector2(x0 - t / 2, (y0 + y1) / 2), Vector2(t, y1 - y0 + 2 * t)],
		"East": [Vector2(x1 + t / 2, (y0 + y1) / 2), Vector2(t, y1 - y0 + 2 * t)],
		"South": [Vector2((x0 + x1) / 2, y0 - t / 2), Vector2(x1 - x0 + 2 * t, t)],
		"North": [Vector2((x0 + x1) / 2, y1 + t / 2), Vector2(x1 - x0 + 2 * t, t)],
	}
	for side: String in sides:
		var centre: Vector2 = sides[side][0]
		var size: Vector2 = sides[side][1]
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, WALL_HEIGHT, size.y)
		var cs := CollisionShape3D.new()
		cs.name = side
		cs.shape = box
		cs.position = MeshUtils.to_godot(centre.x, centre.y, 0.0)
		body.add_child(cs)
