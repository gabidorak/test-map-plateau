extends Control
## First scene of the packed release builds (application/run/main_scene.packed: the "... Packed" export presets have
## the "packed" feature). To keep the download small, their executable does not carry the game's pack as it is:
## .github/workflows/build.yml exports it, tools/pack_game.sh compresses it into zstd chunks (res://pack/, with
## manifest.json), and only the chunks, this scene and the updater go into the executable. At the first start of each
## build the chunks are unpacked into the cache folder (game-<id>.pck; the other builds' packs are deleted), then the
## pack is mounted and the game opens. Editor runs and the other exports start main.tscn directly.

const UiStyle = preload("res://scripts/ui_style.gd")
const MANIFEST := "res://pack/manifest.json"
const GAME := "res://scenes/main.tscn"

var _manifest: Dictionary
var _target := ""                           # the unpacked pack
var _thread: Thread
var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) \
			if FileAccess.file_exists(MANIFEST) else null
	if not manifest is Dictionary:
		_open_game.call_deferred()
		return
	_manifest = manifest
	var dir := OS.get_cache_dir().path_join("plateau-map") if OS.get_cache_dir() != "" else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_target = dir.path_join("game-%s.pck" % _manifest["id"])
	if _unpacked():
		_mount.call_deferred()
		return
	_build_ui()
	print("Unpacking the game data to %s" % _target)
	_thread = Thread.new()
	_thread.start(_unpack)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(1.0, 10, 24))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiStyle.label("Plateau Map", 26))
	_label = UiStyle.label("Unpacking the game (once per update)...", 17, UiStyle.TEXT_DIM)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 22)
	_bar.max_value = 1.0
	box.add_child(_bar)
	UiStyle.centre(panel)


func _unpacked() -> bool:
	var f := FileAccess.open(_target, FileAccess.READ)
	return f != null and f.get_length() == int(_manifest["size"])


## On the thread: the chunks one after the other into a ".part" file, renamed when complete.
func _unpack() -> void:
	var part := "%s.%d.part" % [_target, OS.get_process_id()]
	var err := _write(part)
	if err == "":
		DirAccess.remove_absolute(_target)      # a damaged one, or another instance just unpacked it too
		if DirAccess.rename_absolute(part, _target) != OK and not _unpacked():
			err = "cannot write %s" % _target
	DirAccess.remove_absolute(part)
	_unpack_done.call_deferred(err)


func _write(part: String) -> String:
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (%s)" % [part, error_string(FileAccess.get_open_error())]
	var done := 0
	for chunk: Dictionary in _manifest["chunks"]:
		var size := int(chunk["size"])
		var data := FileAccess.get_file_as_bytes("res://pack/" + chunk["file"]).decompress(size,
				FileAccess.COMPRESSION_ZSTD)
		if data.size() != size:
			return "damaged game data (%s)" % chunk["file"]
		if not f.store_buffer(data):
			return "cannot write %s (disk full?)" % part
		done += size
		_progress.call_deferred(float(done) / int(_manifest["size"]))
	return ""


func _progress(fraction: float) -> void:
	_bar.value = fraction


func _unpack_done(err: String) -> void:
	_thread.wait_to_finish()
	if err != "":
		_fail(err)
		return
	_mount()


func _mount() -> void:
	_remove_other_builds()
	if not ProjectSettings.load_resource_pack(_target):
		DirAccess.remove_absolute(_target)
		_fail("cannot load %s, start the game again to unpack it again" % _target)
		return
	_open_game()


## Packs (and leftover .part files) of other builds: each update unpacks its own.
func _remove_other_builds() -> void:
	var dir := _target.get_base_dir()
	var own := _target.get_file()
	for name in DirAccess.get_files_at(dir):
		if name.begins_with("game-") and not name.begins_with(own):
			DirAccess.remove_absolute(dir.path_join(name))


func _open_game() -> void:
	get_tree().change_scene_to_file(GAME)


func _fail(err: String) -> void:
	printerr("Boot: " + err)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	if _label == null:
		_build_ui()
	_label.text = err
	_label.add_theme_color_override("font_color", UiStyle.TEXT_WARN)
	_bar.hide()
