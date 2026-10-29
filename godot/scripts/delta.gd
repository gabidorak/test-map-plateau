extends RefCounted
## Game data and launcher identity for the delta updates (scripts/updater.gd, scripts/boot.gd). Static helpers only: it
## goes into the packed executables (the "... Packed" export presets list it) next to the autoloads.
##
## A packed executable is a launcher (engine + boot pack, res://pack/launcher.json holds its id) and, for the full
## downloads, the game data as zstd chunks (res://pack/manifest.json: data id, tag, run, commit, chunks). The data lives
## unpacked in the user data folder: data/game-<id>.pck, and data/current-<launcher id>.json says which one the
## launcher uses. An update with the same launcher id only changes the data: Godot delta patches (one per build,
## exported by .github/workflows/build.yml against the previous build, kept on the "store" release with chain.json),
## mounted over the current pack and merged into a new one with PCKPacker. Another launcher id also rebuilds the
## executable from launcher2-<platform>.bin: the blocks of this executable it keeps, the ones it ships (launcher()).
## Data ids hash the packs' file lists (path and md5), not their layout: a merged pack has the id of the exported one
## (tools/pck_tool.py content-id).

const LAUNCHER := "res://pack/launcher.json"
const MANIFEST := "res://pack/manifest.json"
const REMOVED := 2                          # pack directory flag of a file a patch deletes


static func data_dir() -> String:
	return OS.get_user_data_dir().path_join("data")


## The file is there with that size (FileAccess.get_size() complains about missing files).
static func has_file(path: String, size: int) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_size(path) == size


static func read_json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return v if v is Dictionary else {}


## The data this executable runs: {launcher, id, tag, run, commit, path, size, embedded}. `embedded`: the executable's
## own chunks (to unpack when `path` is not there yet); else the data a delta update made for this launcher. Empty
## launcher: not a published build (local exports: no updates, editor runs: no data of their own either). Empty id: a
## launcher without data (rebuilt by an update whose data is gone since).
static func installed() -> Dictionary:
	var out := {"launcher": str(read_json(LAUNCHER).get("id", "")), "id": "", "tag": "", "run": 0, "commit": "",
			"path": "", "size": 0, "embedded": false}
	var m := read_json(MANIFEST)
	var has_chunks := m.has("chunks") and not (m["chunks"] as Array).is_empty()
	for chunk: Dictionary in m.get("chunks", []):
		has_chunks = has_chunks and FileAccess.file_exists("res://pack/" + str(chunk["file"]))
	var p := read_json(pointer(out["launcher"]))
	var p_path := data_dir().path_join(str(p.get("file", "-")))
	var p_ok := not p.is_empty() and has_file(p_path, int(p.get("size", -1)))
	if p_ok and (not has_chunks or int(p.get("run", 0)) >= int(m.get("run", 0)) or p.get("id") == m.get("id")):
		for k in ["id", "tag", "run", "commit", "size"]:
			out[k] = p.get(k, out[k])
		out["path"] = p_path
	elif has_chunks:
		for k in ["id", "tag", "run", "commit", "size"]:
			out[k] = m.get(k, out[k])
		out["path"] = data_dir().path_join("game-%s.pck" % m["id"])
		out["embedded"] = true
	return out


## Where downloaded patches wait to be merged (the next start, when the update went on behind the game).
static func patch_dir() -> String:
	return data_dir().path_join("patches")


static func pointer(launcher: String) -> String:
	return data_dir().path_join("current-%s.json" % (launcher if launcher != "" else "local"))


## Says that `launcher` runs the data at `path` (written to a temporary file first, then renamed). `exe`: the executable
## that runs it, this one (the updater swaps a rebuilt launcher in at the same path), for cleanup().
static func write_pointer(launcher: String, path: String, id: String, tag: String, run: int, commit: String) -> bool:
	var tmp := pointer(launcher) + ".%d.tmp" % OS.get_process_id()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"id": id, "tag": tag, "run": run, "commit": commit, "file": path.get_file(),
			"size": FileAccess.get_size(path), "exe": OS.get_executable_path()}, " "))
	f.close()
	DirAccess.remove_absolute(pointer(launcher))
	return DirAccess.rename_absolute(tmp, pointer(launcher)) == OK


## Writes the executable's chunks (manifest.json) to `target`; "" when done, else why not. `progress` gets the fraction.
## On a thread (scripts/boot.gd, scripts/updater.gd).
static func unpack(target: String, progress: Callable) -> String:
	var m := read_json(MANIFEST)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var part := "%s.%d.part" % [target, OS.get_process_id()]
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (%s)" % [part, error_string(FileAccess.get_open_error())]
	var done := 0
	for chunk: Dictionary in m["chunks"]:
		var size := int(chunk["size"])
		var data := FileAccess.get_file_as_bytes("res://pack/" + chunk["file"]).decompress(size,
				FileAccess.COMPRESSION_ZSTD)
		if data.size() != size:
			f.close()
			DirAccess.remove_absolute(part)
			return "damaged game data (%s)" % chunk["file"]
		if not f.store_buffer(data):
			f.close()
			DirAccess.remove_absolute(part)
			return "cannot write %s (disk full?)" % part
		done += size
		progress.call(float(done) / int(m["size"]))
	f.close()
	DirAccess.remove_absolute(target)          # a damaged one, or another instance just unpacked it too
	var ok := DirAccess.rename_absolute(part, target) == OK
	DirAccess.remove_absolute(part)
	return "" if ok or has_file(target, int(m["size"])) else "cannot write %s" % target


## [[path, md5 hex, flags]] of a pack's directory (format 4), [] when it is not one.
static func pack_entries(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 112 or f.get_buffer(4).get_string_from_ascii() != "GDPC" or f.get_32() != 4:
		return []
	f.seek(32)
	f.seek(f.get_64())
	var out := []
	for i in f.get_32():
		var name := f.get_buffer(f.get_32())
		var end := name.find(0)
		var file := (name.slice(0, end) if end >= 0 else name).get_string_from_utf8()
		f.get_64()
		f.get_64()
		var md5 := f.get_buffer(16).hex_encode()
		out.append([file, md5, f.get_32()])
	return out


## The data id of a full pack (tools/pck_tool.py content-id): sha256 of its sorted "path md5" lines, 16 digits.
static func content_id(path: String) -> String:
	var lines := PackedStringArray()
	for e: Array in pack_entries(path):
		if not e[2] & REMOVED:
			lines.append("%s %s\n" % [e[0], e[1]])
	if lines.is_empty():
		return ""
	lines.sort()
	return "".join(lines).sha256_text().left(16)


## Mounts the base pack and the patches in order (main thread, before anything of the game is loaded): the files the
## merged pack holds, or an error String.
static func mount(base: String, patches: Array) -> Variant:
	var files := {}
	for p: String in [base] + patches:
		var entries := pack_entries(p)
		if entries.is_empty() or not ProjectSettings.load_resource_pack(p):
			return "cannot read " + p.get_file()
		for e: Array in entries:
			if e[2] & REMOVED:
				files.erase(e[0])
			else:
				files[e[0]] = true
	return files.keys()


## Writes the mounted files (mount()) into one pack (on a thread); "" when done. Delta-encoded files are read through
## the patch over the base, so the new pack holds them whole.
static func merge(target: String, files: Array, progress: Callable) -> String:
	var part := "%s.%d.part" % [target, OS.get_process_id()]
	var pk := PCKPacker.new()
	if pk.pck_start(part) != OK:
		return "cannot write " + part
	for i in files.size():
		if pk.add_file("res://" + files[i], "res://" + files[i]) != OK:
			return "cannot read " + files[i]
		if i % 200 == 0:
			progress.call(float(i) / files.size())
	if pk.flush() != OK:
		DirAccess.remove_absolute(part)
		return "cannot write %s (disk full?)" % part
	DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(part, target) != OK:
		DirAccess.remove_absolute(part)
		return "cannot write " + target
	return ""


## Rebuilds a thin executable from `exe` (this one) and a launcher delta (tools/pck_tool.py launcher): a u32 header
## length, the JSON header {size, sha256, block, template, hashes, ship}, the shipped template blocks, then the rest of
## the file (its boot pack). Every block not shipped must hash as in the header. "" when `out` is written and checked.
static func launcher(exe: String, delta: String, out: String) -> String:
	var d := FileAccess.open(delta, FileAccess.READ)
	var src := FileAccess.open(exe, FileAccess.READ)
	if d == null or src == null:
		return "cannot read the launcher update"
	var h: Variant = JSON.parse_string(d.get_buffer(d.get_32()).get_string_from_utf8())
	if not h is Dictionary:
		return "damaged launcher update"
	var block := int(h["block"])
	var template := int(h["template"])
	var hashes: Array = h["hashes"]
	var ship := {}
	for i: float in h["ship"]:
		ship[int(i)] = true
	var o := FileAccess.open(out, FileAccess.WRITE)
	if o == null:
		return "can't write next to the game"
	var whole := HashingContext.new()
	whole.start(HashingContext.HASH_SHA256)
	var err := ""
	for i in hashes.size():
		var n := mini(block, template - i * block)
		var b: PackedByteArray
		if ship.has(i):
			b = d.get_buffer(n)
		else:
			src.seek(i * block)
			b = src.get_buffer(n)
			var bh := HashingContext.new()
			bh.start(HashingContext.HASH_SHA256)
			bh.update(b)
			if b.size() != n or bh.finish().hex_encode().left(32) != hashes[i]:
				err = "this executable is another engine build"
				break
		o.store_buffer(b)
		whole.update(b)
	if err == "":
		var tail := d.get_buffer(d.get_length() - d.get_position())
		o.store_buffer(tail)
		whole.update(tail)
	o.close()
	if err == "" and (FileAccess.get_size(out) != int(h["size"]) or whole.finish().hex_encode() != h["sha256"]):
		err = "rebuilt launcher does not match"
	if err != "":
		DirAccess.remove_absolute(out)
	return err


## Packs in the data folder that no launcher uses any more (and leftovers of interrupted writes), but `keep` (the data of
## this executable, build `run`); the packs of the cache folder older builds unpacked to. Windows can't delete a pack
## another instance has open: next time then. Each new launcher id writes a pointer of its own, so the pointers of the
## launchers gone since are dropped too (stale()), else every one of them keeps a 1-2 GB pack.
static func cleanup(keep: String, run: int) -> void:
	var dir := data_dir()
	var own := pointer(str(read_json(LAUNCHER).get("id", ""))).get_file()
	var used := {keep.get_file(): true}
	for name in DirAccess.get_files_at(dir):
		if name.begins_with("current-") and name.ends_with(".json"):
			var p := read_json(dir.path_join(name))
			if name != own and stale(p, run):
				DirAccess.remove_absolute(dir.path_join(name))
			else:
				used[str(p.get("file", ""))] = true
	for name in DirAccess.get_files_at(dir):
		if name.begins_with("game-") and not used.has(name):
			DirAccess.remove_absolute(dir.path_join(name))
	var old := OS.get_cache_dir().path_join("plateau-map")
	if OS.get_cache_dir() != "" and DirAccess.dir_exists_absolute(old):
		for name in DirAccess.get_files_at(old):
			DirAccess.remove_absolute(old.path_join(name))
		DirAccess.remove_absolute(old)


## Another launcher's pointer `p` whose launcher is gone, seen from this executable (build `run`): its executable is
## deleted, or it was this one before an update replaced it (an older build at this path). Pointers from before "exe"
## was recorded: any older build. A copy of the game kept elsewhere loses its data then, and takes the full download.
static func stale(p: Dictionary, run: int) -> bool:
	var exe := str(p.get("exe", ""))
	if exe != "" and not FileAccess.file_exists(exe):
		return true
	return int(p.get("run", 0)) < run and (exe == "" or exe == OS.get_executable_path())
