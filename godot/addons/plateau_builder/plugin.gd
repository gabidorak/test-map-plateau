@tool
extends EditorPlugin

const WorldBuilder = preload("res://scripts/builder/world_builder.gd")
const MENU := "Rebuild Plateau world"


func _enter_tree() -> void:
	add_tool_menu_item(MENU, _rebuild)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU)


func _rebuild() -> void:
	if WorldBuilder.new().build_and_save() == OK:
		EditorInterface.get_resource_filesystem().scan()
		if WorldBuilder.SCENE_PATH in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(WorldBuilder.SCENE_PATH)
