extends SceneTree
## godot --headless --path godot --script res://tools/prepare_packed.gd -- --in-place
##
## Shrinks the game data in place before the packed release export (.github/workflows/build.yml, scripts/boot.gd).
## CI only: never commit the result.
## - Every compressed binary resource under res://scenes/generated (ResourceSaver.FLAG_COMPRESS, builder/mesh_utils.gd)
##   is rewritten plain: Godot compresses resources in independent 4 KB blocks, which zstd over the whole exported pack
##   beats by far once they are stored plain (the meshes go from 119 MB to 75 MB instead of staying 119 MB).
## - The heightmap keeps only the samples the game reads: ground_heights.gd uses one sample every `mesh_cell` metres
##   (1 in 16 of the 0.5 m samples), so the 57 MB file becomes 4 MB with the exact same heights at runtime. The
##   builders, which need every sample, only run in the editor.

const GENERATED := "res://scenes/generated"
const GROUND_INDEX := "res://world/ground_index.json"


func _initialize() -> void:
	if not "--in-place" in OS.get_cmdline_user_args():
		printerr("rewrites project files in place (CI only): pass -- --in-place")
		quit(1)
		return
	quit(0 if _decompress_resources() and _thin_heightmap() else 1)


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


## Keeps rows and columns 0, step, 2 step... plus the last one, which ground_heights.gd clamps to past the edge: with
## `cell` = `mesh_cell` (step 1) it builds the same nodes, and one more edge row and column of the same values.
func _thin_heightmap() -> bool:
	var index = JSON.parse_string(FileAccess.get_file_as_string(GROUND_INDEX))
	if not index is Dictionary:
		printerr("cannot read %s" % GROUND_INDEX)
		return false
	var hm: Dictionary = index["heights"]
	var path := GROUND_INDEX.get_base_dir().path_join(hm["file"])
	var w := int(hm["w"])
	var h := int(hm["h"])
	var step := roundi(hm["mesh_cell"] / hm["cell"])
	if step <= 1:
		return true
	var heights := FileAccess.get_file_as_bytes(path).to_float32_array()
	if heights.size() != w * h:
		printerr("heightmap size mismatch")
		return false
	var cols := _kept(w, step)
	var rows := _kept(h, step)
	var out := PackedFloat32Array()
	out.resize(cols.size() * rows.size())
	var k := 0
	for r in rows:
		for c in cols:
			out[k] = heights[r * w + c]
			k += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(out.to_byte_array())
	f.close()
	hm["w"] = cols.size()
	hm["h"] = rows.size()
	hm["cell"] = hm["mesh_cell"]
	f = FileAccess.open(GROUND_INDEX, FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "", false, true))
	f.close()
	print("heightmap: %d x %d -> %d x %d samples" % [w, h, cols.size(), rows.size()])
	return true


func _kept(n: int, step: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(0, n, step):
		out.append(i)
	if out[-1] != n - 1:
		out.append(n - 1)
	return out
