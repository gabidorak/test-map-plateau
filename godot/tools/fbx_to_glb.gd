extends SceneTree
## Converts an FBX that Blender cannot read (FBX 6.1, "Version 6100 unsupported": the GAZ Tiger of ref/gaz_tiger) to a
## glTF binary with Godot's own FBX reader (ufbx), for blender/vehicles/import_car.py to load:
##   godot --headless --path godot --script res://tools/fbx_to_glb.gd -- <in.fbx> <out.glb>
## (absolute paths, or relative to the project folder). Node names, meshes and material names come through; textures
## are not looked for.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <in.fbx> <out.glb>")
		quit(1)
		return
	var fbx := FBXDocument.new()
	var state := FBXState.new()
	var err := fbx.append_from_file(args[0], state)
	if err != OK:
		printerr("cannot read %s: %s" % [args[0], error_string(err)])
		quit(1)
		return
	var scene := fbx.generate_scene(state)
	var gltf := GLTFDocument.new()
	var out := GLTFState.new()
	err = gltf.append_from_scene(scene, out)
	if err == OK:
		err = gltf.write_to_filesystem(out, args[1])
	scene.free()
	if err != OK:
		printerr("cannot write %s: %s" % [args[1], error_string(err)])
		quit(1)
		return
	print("%s: %d meshes" % [args[1], out.meshes.size()])
	quit()
