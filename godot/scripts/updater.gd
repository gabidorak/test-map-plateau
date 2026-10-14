extends Node
## Auto-updater (autoload "AutoUpdater") for the builds published by .github/workflows/build.yml: every GitHub release
## (build-N for each push to main, vX for pushed tags) carries one file per platform, and the workflow stamps the
## release tag and commit into application/config/version and application/config/commit before exporting. Editor
## runs and local exports have no version: no check.
## At start the updater asks GitHub for the latest release; when it is another build, it downloads this platform's file
## next to the game (a hidden ".update" file, ".part" while downloading) in the foreground: a full-screen progress bar
## over the game, which restarts on the new build once it is downloaded. Esc skips: the download goes on in the
## background, and the swap happens on "Restart now" in the welcome menu (scripts/main_menu.gd) or at the next start.
## The packed builds' boot scene (scripts/boot.gd) waits for the foreground update before unpacking the game. The game reads its embedded pack by
## path while it runs, so the files are swapped only right before the process ends: the new build is launched and
## this one killed at once. Windows and Linux rename the running executable aside (".old", deleted at the next start),
## macOS unzips the new .app with ditto and swaps the bundles. Where the game's folder is not writable, or when anything
## fails, the menu offers the release page instead.

signal changed

const REPO := "gabidorak/test-map-plateau"
const API := "https://api.github.com/repos/" + REPO + "/releases/latest"
const ASSETS := {"Windows": "plateau-map-windows.exe", "Linux": "plateau-map-linux.x86_64",
		"macOS": "plateau-map-macos.zip"}
const STATE_FILE := "user://update.cfg"     # tag and commit of the downloaded update
const USER_AGENT := "User-Agent: plateau-map-updater"
const UiStyle = preload("res://scripts/ui_style.gd")
const SHOW_CHECK_AFTER := 0.4               # s: a quick check does not flash the screen

enum State { OFF, CHECKING, UP_TO_DATE, DOWNLOADING, READY, MANUAL, FAILED }

var state := State.OFF
var version := ""                           # this build's release tag, "" when not a published build
var latest := ""                            # tag of the newest release
var release_page := ""
var error := ""                             # why the update failed (State.FAILED)

var _commit := ""
var _target := ""                           # the executable (Windows, Linux) or the .app bundle (macOS)
var _http: HTTPRequest
var _size := 0
var _latest_commit := ""
var _skipped := false                       # Esc: the update goes on behind the game
var _check_t := 0.0                         # s since the check started
var _rate := 0.0                            # download speed, bytes/s
var _rate_t := 0.0
var _rate_bytes := 0
var _screen: CanvasLayer
var _title: Label
var _detail: Label
var _bar: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	version = str(ProjectSettings.get_setting("application/config/version", ""))
	_commit = str(ProjectSettings.get_setting("application/config/commit", ""))
	if version == "" or not OS.has_feature("template") or not ASSETS.has(OS.get_name()) \
			or DisplayServer.get_name() == "headless":
		return
	_target = OS.get_executable_path()
	if OS.get_name() == "macOS":
		_target = _target.get_base_dir().get_base_dir().get_base_dir()   # .app/Contents/MacOS/<exe>
		if not _target.ends_with(".app"):
			return
	_remove(_old())
	_remove(_part())
	var cfg := ConfigFile.new()
	cfg.load(STATE_FILE)
	if FileAccess.file_exists(_pending()) and cfg.get_value("update", "tag", version) != version \
			and cfg.get_value("update", "commit", _commit) != _commit:
		var err := _install()
		if err == "":
			_relaunch()
			return
		push_warning("Updater: " + err)
	_remove(_pending())
	check()


## Asks GitHub for the latest release (State.CHECKING), then downloads it when it is another build.
func check() -> void:
	_check_t = 0.0
	set_process(true)
	_set_state(State.CHECKING)
	_new_request(10.0).request_completed.connect(_on_release, CONNECT_ONE_SHOT)
	if _http.request(API, [USER_AGENT, "Accept: application/vnd.github+json"]) != OK:
		_set_state(State.OFF)


## Dedicated server (game.gd --dedicated, headless: no download here): only fetches the latest release's tag and
## commit, for outdated(). The server's container (server/ at the repository root) fetches the new build when it quits.
func check_tag() -> void:
	if version == "":
		return
	_new_request(15.0).request_completed.connect(
			func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
				var rel: Variant = JSON.parse_string(body.get_string_from_utf8()) \
						if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
				if rel is Dictionary:
					latest = str(rel.get("tag_name", ""))
					_latest_commit = str(rel.get("target_commitish", "")),
			CONNECT_ONE_SHOT)
	_http.request(API, [USER_AGENT, "Accept: application/vnd.github+json"])


## A published build whose newest release (check_tag) is another build.
func outdated() -> bool:
	return version != "" and latest != "" and latest != version and _latest_commit != _commit


## True while the update screen is up, or about to be: checking, downloading, restarting (not skipped).
func foreground() -> bool:
	return not _skipped and state in [State.CHECKING, State.DOWNLOADING, State.READY]


## Downloaded fraction (State.DOWNLOADING).
func progress() -> float:
	return clampf(_http.get_downloaded_bytes() / float(maxi(_size, 1)), 0.0, 1.0) if _http else 0.0


## Installs the downloaded update and starts it (State.READY); on failure the state goes to FAILED.
func restart_now() -> void:
	var err := _install()
	if err != "":
		_fail(err)
		return
	_relaunch()


## "build-12" -> "Build 12", "v1.2" stays.
static func pretty(tag: String) -> String:
	return "Build " + tag.trim_prefix("build-") if tag.begins_with("build-") else tag


func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var rel: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS \
			and code == 200 else null
	if not rel is Dictionary:
		push_warning("Updater: no release information (result %d, HTTP %d)" % [result, code])
		_set_state(State.OFF)                 # offline: say nothing
		return
	latest = str(rel.get("tag_name", ""))
	_latest_commit = str(rel.get("target_commitish", ""))
	release_page = str(rel.get("html_url", "https://github.com/%s/releases/latest" % REPO))
	# a pushed tag and the push to main of the same commit make two releases of one build
	if latest == "" or latest == version or _latest_commit == _commit:
		_set_state(State.UP_TO_DATE)
		return
	var url := ""
	for asset: Dictionary in rel.get("assets", []):
		if asset.get("name") == ASSETS[OS.get_name()]:
			url = str(asset.get("browser_download_url", ""))
			_size = int(asset.get("size", 0))
	var probe := FileAccess.open(_part(), FileAccess.WRITE)
	if url == "" or probe == null:
		_set_state(State.MANUAL)
		return
	probe.close()
	_new_request(0.0).request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	_http.download_file = _part()
	_http.download_chunk_size = 1 << 18
	if _http.request(url, [USER_AGENT]) != OK:
		_fail("can't start the download")
		return
	_set_state(State.DOWNLOADING)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var got := FileAccess.get_size(_part()) if FileAccess.file_exists(_part()) else -1
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or (_size > 0 and got != _size):
		_remove(_part())
		_fail("download failed (result %d, HTTP %d, %d of %d bytes)" % [result, code, got, _size])
		return
	_remove(_pending())
	if DirAccess.rename_absolute(_part(), _pending()) != OK:
		_remove(_part())
		_fail("can't write next to the game")
		return
	var cfg := ConfigFile.new()
	cfg.set_value("update", "tag", latest)
	cfg.set_value("update", "commit", _latest_commit)
	cfg.save(STATE_FILE)
	_set_state(State.READY)
	if not _skipped:
		_show_screen()                      # "Restarting…" drawn before the swap
		await get_tree().process_frame
		await get_tree().process_frame
		restart_now()


## Puts the downloaded build in place of this one; "" when done, else why not (this one is then left as it was).
func _install() -> String:
	var pending := _pending()
	var fresh := pending
	if OS.get_name() == "macOS":
		var tmp := _target.get_base_dir().path_join(".plateau-map-update")
		OS.execute("rm", ["-rf", tmp])
		if OS.execute("ditto", ["-x", "-k", pending, tmp]) != 0:
			OS.execute("rm", ["-rf", tmp])
			return "can't unzip the update"
		fresh = ""
		for d in DirAccess.get_directories_at(tmp):
			if d.ends_with(".app"):
				fresh = tmp.path_join(d)
		if fresh == "":
			OS.execute("rm", ["-rf", tmp])
			return "no app in the update"
		OS.execute("xattr", ["-dr", "com.apple.quarantine", fresh])
	elif OS.get_name() == "Linux":
		FileAccess.set_unix_permissions(pending, 493)           # 0755
	_remove(_old())
	if DirAccess.rename_absolute(_target, _old()) != OK:
		return "can't move the game aside"
	if DirAccess.rename_absolute(fresh, _target) != OK:
		DirAccess.rename_absolute(_old(), _target)
		return "can't put the update in place"
	if OS.get_name() == "macOS":
		OS.execute("rm", ["-rf", _target.get_base_dir().path_join(".plateau-map-update"), pending])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_FILE))
	return ""


## Starts the installed build with the same arguments and ends this process at once: from now on its pack path
## leads to the new build's files.
func _relaunch() -> void:
	var args := OS.get_cmdline_args()
	if OS.get_name() == "macOS":
		OS.create_process("open", PackedStringArray(["-n", _target, "--args"]) + args)
	else:
		OS.create_process(_target, args)
	OS.kill(OS.get_process_id())


func _new_request(timeout: float) -> HTTPRequest:
	if _http:
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = timeout
	add_child(_http)
	return _http


func _fail(why: String) -> void:
	push_warning("Updater: " + why)
	error = why
	_set_state(State.FAILED)


func _set_state(s: State) -> void:
	state = s
	_show_screen()
	changed.emit()


func _process(delta: float) -> void:
	_check_t += delta
	if state == State.DOWNLOADING:
		_rate_t += delta
		if _rate_t >= 0.5:
			var got := _http.get_downloaded_bytes()
			_rate = lerpf(float(got - _rate_bytes) / _rate_t, _rate, 0.5 if _rate > 0.0 else 0.0)
			_rate_bytes = got
			_rate_t = 0.0
	_show_screen()


## The full-screen update page, while foreground(): over everything (the boot screen, the welcome menu), with the 3D
## world not drawn behind it.
func _show_screen() -> void:
	var on := foreground() and (state != State.CHECKING or _check_t >= SHOW_CHECK_AFTER)
	if on and _screen == null:
		_build_screen()
	if _screen and _screen.visible != on:
		_screen.visible = on
		get_tree().root.disable_3d = on
	if not on:
		set_process(foreground())           # still checking: the screen may come up
		return
	match state:
		State.CHECKING:
			_title.text = "Looking for updates…"
			_bar.indeterminate = true
			_detail.text = pretty(version)
		State.DOWNLOADING:
			_title.text = "Updating to %s" % pretty(latest)
			_bar.indeterminate = false
			_bar.value = progress()
			var got := _http.get_downloaded_bytes() / 1048576.0
			_detail.text = "%.0f of %.0f MB" % [got, _size / 1048576.0] + \
					("  ·  %.1f MB/s" % (_rate / 1048576.0) if _rate > 0.0 else "")
		State.READY:
			_title.text = "Restarting on %s…" % pretty(latest)
			_bar.indeterminate = false
			_bar.value = 1.0
			_detail.text = ""


func _build_screen() -> void:
	_screen = CanvasLayer.new()
	_screen.layer = 100
	_screen.visible = false
	add_child(_screen)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(bg)                   # stops the mouse from reaching the menus behind
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size.x = 640
	_screen.add_child(box)
	box.add_child(UiStyle.label("Plateau Map", 40))
	_title = UiStyle.label("", 22)
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(640, 26)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.55, 1.0)
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.16, 0.18, 0.23)
	back.set_corner_radius_all(6)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_detail = UiStyle.label("", 17, UiStyle.TEXT_DIM)
	box.add_child(_detail)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	box.add_child(gap)
	box.add_child(UiStyle.label("Esc  skip: play %s now, the update installs at the next start" % pretty(version), 16,
			UiStyle.TEXT_DIM))
	UiStyle.centre(box)


## While the update screen is up the game behind it gets no keys or clicks; Esc skips the update (F11 still switches
## fullscreen: Settings).
func _input(event: InputEvent) -> void:
	if _screen == null or not _screen.visible or not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and event.physical_keycode == KEY_F11:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and state != State.READY:
		_skipped = true
		_show_screen()
		changed.emit()


func _hidden(suffix: String) -> String:
	return _target.get_base_dir().path_join("." + _target.get_file() + suffix)


func _pending() -> String:
	return _hidden(".update")


func _part() -> String:
	return _hidden(".update.part")


func _old() -> String:
	return _hidden(".old")


## Deletes a file, or a whole folder (the old .app on macOS).
func _remove(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		OS.execute("rm", ["-rf", path])
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
