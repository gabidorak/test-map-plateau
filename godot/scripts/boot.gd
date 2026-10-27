extends Control
## First scene of the packed release builds (application/run/main_scene.packed: the "... Packed" export presets have
## the "packed" feature). To keep the download small, their executable does not carry the game's pack as it is:
## .github/workflows/build.yml exports it, tools/pack_game.sh compresses it into zstd chunks (res://pack/, with
## manifest.json), and only the chunks, this scene, scripts/delta.gd and the autoloads (scripts/settings.gd,
## scripts/updater.gd) go into the executable: the "Packed" presets' export_files list them. The game runs from an
## unpacked pack in the user data folder: the one the delta updates made for this launcher, or this executable's chunks,
## unpacked at the first start of each build (scripts/delta.gd, Delta.installed()); the packs no launcher uses any more
## are deleted. While the updater updates in the foreground (its own full-screen page), nothing is unpacked or loaded:
## the game restarts on the new build, or carries on once the update is skipped. Editor runs and the other exports start
## loading.tscn directly, which loads main.tscn behind its loading screen.

const Delta = preload("res://scripts/delta.gd")
const UiStyle = preload("res://scripts/ui_style.gd")
const GAME := "res://scenes/loading.tscn"

var _data: Dictionary                       # Delta.installed()
var _thread: Thread
var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	var updater := get_node_or_null("/root/AutoUpdater")
	while updater and updater.foreground():
		await updater.changed
	_data = Delta.installed()
	if _data["path"] == "":
		if _data["launcher"] == "" and not FileAccess.file_exists(Delta.MANIFEST):
			_open_game.call_deferred()          # not a packed build
		else:
			_fail("the game data is missing: download the game again from its release page")
		return
	if not _data["embedded"] or Delta.has_file(_data["path"], int(_data["size"])):
		_mount.call_deferred()
		return
	_build_ui()
	print("Unpacking the game data to %s" % _data["path"])
	_thread = Thread.new()
	_thread.start(func() -> void:
		var err := Delta.unpack(_data["path"], func(f: float) -> void: _progress.call_deferred(f))
		_unpack_done.call_deferred(err))


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


func _progress(fraction: float) -> void:
	_bar.value = fraction


func _unpack_done(err: String) -> void:
	_thread.wait_to_finish()
	if err != "":
		_fail(err)
		return
	Delta.write_pointer(_data["launcher"], _data["path"], _data["id"], _data["tag"], _data["run"], _data["commit"])
	_mount()


func _mount() -> void:
	Delta.cleanup(_data["path"])
	if not ProjectSettings.load_resource_pack(_data["path"]):
		DirAccess.remove_absolute(_data["path"])
		_fail("cannot load %s, start the game again to unpack it again" % _data["path"])
		return
	_open_game()


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
