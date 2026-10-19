extends SceneTree
## godot --headless --path godot --script res://tools/verify_patch.gd -- <prev.pck> <patch.pck> <game.pck> <scratch.pck>
##
## Does what a player's updater does with a data patch (scripts/delta.gd: mount over the previous build's data, merge
## into one pack) and checks the result is this build's exported data <game.pck>: same files, same md5. Exits 1 when
## not, after listing the files that differ. CI (.github/workflows/build.yml) publishes only the patches that pass:
## `--export-patch` is a second export, and a file the exporter does not write the same twice (a scene node without
## unique_id gets a new id at each export) would make every player's update fail after downloading it. The merged pack
## goes to <scratch.pck>, deleted afterwards.

const Delta = preload("res://scripts/delta.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		printerr("usage: -- <prev.pck> <patch.pck> <game.pck> <scratch.pck>")
		quit(1)
		return
	var files: Variant = Delta.mount(args[0], [args[1]])
	if files is String:
		printerr(files)
		quit(1)
		return
	var err := Delta.merge(args[3], files, func(_f: float) -> void: pass)
	var got := _md5s(args[3]) if err == "" else {}
	DirAccess.remove_absolute(args[3])
	if err != "":
		printerr(err)
		quit(1)
		return
	var want := _md5s(args[2])
	var bad := PackedStringArray()
	for path: String in want:
		if got.get(path) != want[path]:
			bad.append(("differs: " if got.has(path) else "missing: ") + path)
	for path: String in got:
		if not want.has(path):
			bad.append("extra: " + path)
	if bad.is_empty():
		print("previous data + patch = this build's data (%d files)" % want.size())
		quit(0)
		return
	printerr("previous data + patch != this build's data, %d files:\n  %s" % [bad.size(), "\n  ".join(bad.slice(0, 50))])
	quit(1)


## path -> md5 of a pack's files.
func _md5s(pck: String) -> Dictionary:
	var out := {}
	for e: Array in Delta.pack_entries(pck):
		if not e[2] & Delta.REMOVED:
			out[e[0]] = e[1]
	return out
