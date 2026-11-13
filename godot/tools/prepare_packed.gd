extends SceneTree
## godot --headless --path godot --script res://tools/prepare_packed.gd -- --in-place
##
## Shrinks the game data in place before the packed release export (.github/workflows/build.yml, scripts/boot.gd).
## CI only: never commit the result.
## - Every compressed binary resource under res://scenes/generated (ResourceSaver.FLAG_COMPRESS, builder/mesh_utils.gd)
##   is rewritten plain: Godot compresses resources in independent 4 KB blocks, which zstd over the whole exported pack
##   beats by far once they are stored plain (the meshes go from 119 MB to 75 MB instead of staying 119 MB).
## (The game reads the ground baked with the scene, scenes/generated/ground*: builder/ground_bake.gd. The map's
## heightmap, which only the builders read, is not exported.)

const GENERATED := "res://scenes/generated"


func _initialize() -> void:
	if not "--in-place" in OS.get_cmdline_user_args():
		printerr("rewrites project files in place (CI only): pass -- --in-place")
		quit(1)
		return
	quit(0 if _decompress_resources() else 1)


func _decompress_resources() -> bool:
	var count := 0
	var before := 0
	var after := 0
	for path in _files(GENERATED):
		var size := FileAccess.get_size(path)
		var f := FileAccess.open(path, FileAccess.READ)
		var compressed := f.get_buffer(4).get_string_from_ascii() == "RSCC"
		f.close()
		if not compressed:
			continue
		var err := ResourceSaver.save(load(path), path)
		if err != OK:
			printerr("cannot save %s: %s" % [path, error_string(err)])
			return false
		count += 1
		before += size
		after += FileAccess.get_size(path)
	print("decompressed %d resources: %.1f MB -> %.1f MB" % [count, before / 1e6, after / 1e6])
	return true


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".res"):
			out.append(dir.path_join(name))
	for name in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(name)))
	return out
