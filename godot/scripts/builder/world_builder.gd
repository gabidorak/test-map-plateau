@tool
extends RefCounted
## Builds res://scenes/generated/neighborhood.tscn from the pipeline output in res://world/.
## Run from the editor (Project > Tools > Rebuild Plateau world) or headless via tools/build_world.gd.

const GroundBuilder = preload("res://scripts/builder/ground_builder.gd")
const BuildingBuilder = preload("res://scripts/builder/building_builder.gd")
const CollisionBuilder = preload("res://scripts/builder/collision_builder.gd")
const VegetationBuilder = preload("res://scripts/builder/vegetation_builder.gd")
const PropPlacer = preload("res://scripts/builder/prop_placer.gd")
const FarBuilder = preload("res://scripts/builder/far_builder.gd")
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

	var heights := FileAccess.get_file_as_bytes(WORLD_PATH.get_base_dir().path_join(world["terrain"]["file"])).to_float32_array()
	if heights.size() != int(world["terrain"]["w"]) * int(world["terrain"]["h"]):
		push_error("heightmap size mismatch")
		return ERR_INVALID_DATA

	var root := Node3D.new()
	root.name = "Neighborhood"
	var m: Dictionary = world["meta"]
	root.set_meta("world", {"area": m["area"], "origin": m["origin"], "playable": m["playable"], "built_at": m["built_at"]})
	var err := GroundBuilder.new().build(root, world, WORLD_PATH.get_base_dir(), MESH_DIR)
	if err != OK:
		root.free()
		return err
	BuildingBuilder.new().build(root, world, MESH_DIR)
	err = VegetationBuilder.new().build(root, world, heights, MESH_DIR)
	if err != OK:
		root.free()
		return err
	err = PropPlacer.new().build(root, world, heights, MESH_DIR)
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

	var packed := PackedScene.new()
	err = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE_PATH)
	root.free()
	print("built %s: %d buildings, %d ground chunks, %d trees, %d hedges, %d props, %d fences (%s)" % [SCENE_PATH,
			world["buildings"].size(), world["ground_mesh"]["chunks"].size(), world["trees"].size(),
			world["hedges"].size(), world["props"].size(), world["fences"].size(), error_string(err)])
	return err


func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)
