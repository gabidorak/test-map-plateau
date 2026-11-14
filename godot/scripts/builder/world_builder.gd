@tool
extends RefCounted
## Builds res://scenes/generated/neighborhood.tscn from the pipeline output in res://world/ (and the lots: their
## ground, removals, builds, builder/lots.gd, the railway's among them; the building
## interiors, world/interiors.json: builder/interior_builder.gd), and the ground the game reads,
## res://scenes/generated/ground.json (builder/ground_bake.gd: the map's with the lots' terraforming and surfaces).
## Run from the editor (Project > Tools > Rebuild Plateau world) or headless via tools/build_world.gd.

const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
const BuildingBuilder = preload("res://scripts/builder/building_builder.gd")
const Terraform = preload("res://scripts/builder/terraform.gd")
const GroundBake = preload("res://scripts/builder/ground_bake.gd")
const LotBake = preload("res://scripts/builder/lot_bake.gd")
const GroundCut = preload("res://scripts/builder/ground_cut.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Lots = preload("res://scripts/builder/lots.gd")
const CollisionBuilder = preload("res://scripts/builder/collision_builder.gd")
const VegetationBuilder = preload("res://scripts/builder/vegetation_builder.gd")
const PropPlacer = preload("res://scripts/builder/prop_placer.gd")
const FarBuilder = preload("res://scripts/builder/far_builder.gd")
const BridgeBuilder = preload("res://scripts/builder/bridge_builder.gd")
const InteriorBuilder = preload("res://scripts/builder/interior_builder.gd")
const Water = preload("res://scripts/water.gd")
const GroundHeights = preload("res://scripts/ground_heights.gd")
## 3 adds ground[], kerbs[], markings[] (M3); 4 adds ground_mesh, palette, drops the ortho (M4);
## 5 adds trees[], hedges[], tree_archetypes (M5); 6 adds props[], fences[], prop_models, sign_faces (M6);
## 7 adds buildings[].toy, building_kit, building_modules[], building_signs[] (M7);
## 8 adds buildings[].facade photo colours and toy.style wall_src (M8)
const SCHEMA := 9

const WORLD_PATH := "res://world/world.json"
const SCENE_PATH := "res://scenes/generated/neighborhood.tscn"
const MESH_DIR := "res://scenes/generated/meshes/"


func build_and_save() -> Error:
	var text := FileAccess.get_file_as_string(WORLD_PATH)
	var world = JSON.parse_string(text)
	if not world is Dictionary:
		push_error("cannot parse %s" % WORLD_PATH)
		return ERR_PARSE_ERROR
	if int(world["meta"]["schema"]) != SCHEMA:
		push_error("unsupported world.json schema %s" % world["meta"]["schema"])
		return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	for f in DirAccess.get_files_at(MESH_DIR):  # drop meshes from a previous, possibly larger build
		DirAccess.remove_absolute(MESH_DIR.path_join(f))

	var heights := GroundHeights.read_heightmap(WORLD_PATH.get_base_dir(), world["terrain"])
	if heights.size() != int(world["terrain"]["w"]) * int(world["terrain"]["h"]):
		push_error("heightmap size mismatch")
		return ERR_INVALID_DATA
	# terraforming first (builder/terraform.gd, data/terraform/): the heightmap here, the ground's mesh alike
	Terraform.patch(heights, world["terrain"])
	# the lots' own ground (builder/lot_ground.gd): the map's round it as it is, then their zones' heights stamped in
	var t0: Dictionary = world["terrain"]
	var shared := GroundHeights.new(heights, t0["w"], t0["h"], t0["cell"], t0["origin_xy"][0], t0["origin_xy"][1],
			world["ground_mesh"]["cell"])
	var ts := Time.get_ticks_msec()
	print("lots' own ground: %d samples stamped (%d ms)" % [Lots.stamp_grounds(heights, t0), Time.get_ticks_msec() - ts])
	# the ground the game reads, baked (builder/ground_bake.gd): the map's with the lots' surfaces, on these heights;
	# every builder below reads it (GroundMap.get_map())
	var ground: RefCounted = GroundBake.make(world, WORLD_PATH.get_base_dir(), heights)
	if ground == null:
		return ERR_CANT_OPEN

	var root := Node3D.new()
	root.name = "Neighborhood"
	var m: Dictionary = world["meta"]
	# the lowest drawn ground (Godot y, the chunks' boxes): game.gd puts the player's fall-out depth under it
	var ground_min := INF
	for c: Dictionary in world["ground_mesh"]["chunks"]:
		ground_min = minf(ground_min, float(c["aabb"][1]))
	root.set_meta("world", {"area": m["area"], "origin": m["origin"], "playable": m["playable"], "built_at": m["built_at"],
			"ground_min": ground_min})
	# the lakes and ponds first: the ground, its collision and the far ground are dug out under them (scripts/water.gd)
	var t: Dictionary = world["terrain"]
	var water := Water.new()
	water.name = "Water"
	water.setup(world, GroundHeights.new(heights, t["w"], t["h"], t["cell"], t["origin_xy"][0], t["origin_xy"][1],
			world["ground_mesh"]["cell"]))
	root.add_child(water)
	var err := GroundBuilder.new().build(root, world, WORLD_PATH.get_base_dir(), MESH_DIR)
	if err != OK:
		root.free()
		return err
	Lots.drop(world)                                # the lots replace what they take over (builder/lots.gd)
	BuildingBuilder.new().build(root, world, MESH_DIR)
	InteriorBuilder.new().build(root, world, heights, MESH_DIR)
	err = VegetationBuilder.new().build(root, world, heights, MESH_DIR)
	if err != OK:
		root.free()
		return err
	err = PropPlacer.new().build(root, world, heights, MESH_DIR)
	if err != OK:
		root.free()
		return err
	BridgeBuilder.new().build(root, world, heights, MESH_DIR)
	err = Lots.build(root, world, heights, MESH_DIR, shared)  # the lots built with the map: the railway's (builder/lots.gd)
	if err != OK:
		root.free()
		return err
	LotBake.bake(root, MESH_DIR)                    # the finished lots' builds (builder/lot_bake.gd), streamed with the map's
	# the terrain's collision holed where the lots own the ground (builder/ground_cut.gd: they collide themselves)
	var holes: Dictionary = world["ground_mesh"].get_or_add("holes", {})
	holes["samples"] = holes.get("samples", []) + GroundCut.new(Lots.owned_ground()).hole_samples(world["terrain"],
			CollisionBuilder.STEP)
	var collision := CollisionBuilder.new()
	collision.terrain(root, world, heights, MESH_DIR)
	collision.boundary(root, world)
	err = FarBuilder.new().build(root, world, MESH_DIR)
	if err != OK:
		root.free()
		return err
	_own(root, root)

	var waters: int = water.bodies.size()
	var packed := PackedScene.new()
	err = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE_PATH)
	if err == OK:
		err = ground.save(GroundMap.DEFAULT_INDEX, GroundBake.ABOUT)
	root.free()
	print("built %s: %d buildings, %d ground chunks, %d trees, %d hedges, %d props, %d fences, %d bodies of water (%s)" % [
			SCENE_PATH, world["buildings"].size(), world["ground_mesh"]["chunks"].size(), world["trees"].size(),
			world["hedges"].size(), world["props"].size(), world["fences"].size(), waters, error_string(err)])
	return err


func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)
