extends SceneTree
## godot --headless --path godot --script res://tools/build_world.gd

const WorldBuilder = preload("res://scripts/builder/world_builder.gd")


func _initialize() -> void:
	quit(0 if WorldBuilder.new().build_and_save() == OK else 1)
