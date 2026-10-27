extends CanvasLayer
## Startup scene (application/run/main_scene): shows scripts/loading_screen.gd at once, while scenes/main.tscn (the
## 84 MB generated world, 58k nodes) loads on a worker thread, then changes to it. Without this, Godot builds the
## whole world before drawing the first frame: the window stays black (or on the last boot frame) for seconds, with
## no idea whether the game is starting. The progress the loader reports fills the bar; the orbit and the tips keep
## moving meanwhile, so a stall in ResourceLoader's own progress still looks alive. On failure the screen says so and
## offers Try again (the release page is not needed for a local read error).
## Packed builds start scripts/boot.gd instead (application/run/main_scene.packed, after the data pack is unpacked and
## mounted); boot.gd opens this scene, which is part of the mounted game pack. Tools and tests start main.tscn
## themselves (--script) and never see this scene.

const LoadingScreen = preload("res://scripts/loading_screen.gd")
const GAME := "res://scenes/main.tscn"
const MIN_SHOW := 0.8                         # s: long enough that a warm start does not flash the screen

enum Phase { LOADING, OPENING, FAILED }

var _screen: LoadingScreen
var _phase := Phase.LOADING
var _started := 0.0
var _stage := ""


func _ready() -> void:
	layer = 50
	_screen = LoadingScreen.new()
	add_child(_screen)
	_screen.retry.connect(_retry)
	_started = Time.get_ticks_msec() / 1000.0
	if DisplayServer.get_name() == "headless":
		# A dedicated server has no screen to keep alive, and threaded resource loading can be much slower under the
		# dummy renderer: read the world on this thread, as the game did before the loading scene existed.
		_screen.visible = false
		_phase = Phase.OPENING               # before the deferred call, so _process does not poll a request never made
		_open_sync.call_deferred()
		return
	_start_loading()


func _start_loading() -> void:
	_phase = Phase.LOADING
	_stage = ""
	_screen.reset()
	_screen.set_status("Waking up the plateau…")
	var err := ResourceLoader.load_threaded_request(GAME, "PackedScene", false)
	if err != OK:
		_fail("The game's world could not be loaded (error %d)." % err)


func _process(_delta: float) -> void:
	if _phase != Phase.LOADING:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var fraction: float = progress[0] if not progress.is_empty() else 0.0
		_screen.set_progress(fraction)
		var stage := _stage_for(fraction)
		if stage != _stage:
			_stage = stage
			_screen.set_status(stage)
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_phase = Phase.OPENING
		_screen.set_progress(1.0)
		_screen.set_status("Building the world…")
		_open.call_deferred()
	else:
		_fail("The game's world could not be loaded. Is the game data complete?")


## What the loader is doing, from how far it is: it loads the scene file, then every mesh, material and shape it
## references, roughly in the order they are written (water, ground, buildings, vegetation, props).
func _stage_for(fraction: float) -> String:
	if fraction < 0.03:
		return "Waking up the plateau…"
	if fraction < 0.35:
		return "Loading the map…"
	if fraction < 0.7:
		return "Placing the buildings…"
	if fraction < 0.99:
		return "Growing the trees…"
	return "Building the world…"


## Headless: no screen, so no progress to report; load and open the game in one go (as main.tscn used to be started).
func _open_sync() -> void:
	_phase = Phase.OPENING
	var packed := load(GAME) as PackedScene
	if packed == null:
		_fail("The game's world could not be loaded.")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		_fail("The game could not be started (error %d)." % err)


## Once the scene is read: hold the screen for MIN_SHOW, then swap it for the game in one frame.
func _open() -> void:
	var left := MIN_SHOW - (Time.get_ticks_msec() / 1000.0 - _started)
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	_screen.set_status("Almost there…")
	await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(GAME) as PackedScene
	if packed == null:
		_fail("The game's world could not be loaded.")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		_fail("The game could not be started (error %d)." % err)


func _fail(message: String) -> void:
	_phase = Phase.FAILED
	printerr("Loading: " + message)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	_screen.show_error(message)


func _retry() -> void:
	_start_loading()
