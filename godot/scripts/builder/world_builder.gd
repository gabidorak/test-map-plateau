@tool
extends RefCounted
## Builds res://scenes/generated/neighborhood.tscn from the pipeline output in res://world/ (and the railway,
## world/rail.json: builder/rail_builder.gd; the building interiors, world/interiors.json: builder/interior_builder.gd).
## Run from the editor (Project > Tools > Rebuild Plateau world) or headless via tools/build_world.gd.

const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
const BuildingBuilder = preload("res://scripts/builder/building_builder.gd")
const CollisionBuilder = preload("res://scripts/builder/collision_builder.gd")
const VegetationBuilder = preload("res://scripts/builder/vegetation_builder.gd")
const PropPlacer = preload("res://scripts/builder/prop_placer.gd")
const FarBuilder = preload("res://scripts/builder/far_builder.gd")
const RailBuilder = preload("res://scripts/builder/rail_builder.gd")
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
	err = RailBuilder.new().build(root, world, heights, MESH_DIR)
	if err != OK:
		root.free()
		return err
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
	root.free()
	print("built %s: %d buildings, %d ground chunks, %d trees, %d hedges, %d props, %d fences, %d bodies of water (%s)" % [
			SCENE_PATH, world["buildings"].size(), world["ground_mesh"]["chunks"].size(), world["trees"].size(),
			world["hedges"].size(), world["props"].size(), world["fences"].size(), waters, error_string(err)])
	return err


func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)
