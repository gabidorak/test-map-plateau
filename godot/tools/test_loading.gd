extends SceneTree
## Headless checks of the loading screen (scripts/loading_screen.gd): its status line, progress bar easing to the
## figure set and creeping on, percentage, the error state with its Try again button, and closing (fades out and frees
## itself); its map's data (scripts/loading_map.gd); the Pacer (scripts/pacer.gd); and the loader
## (scripts/loading_scene.gd) putting the game in the tree a slice at a time, then back to the main menu: the same
## world as main.tscn instanced at once, its bodies' shapes all enabled again, the ground under a ray, the welcome
## menu up, the tree running and the 3D view on, the old game freed.
## godot --headless --path godot --script res://tools/test_loading.gd

const LoadingScreen = preload("res://scripts/loading_screen.gd")
const LoadingMap = preload("res://scripts/loading_map.gd")
const Loader = preload("res://scripts/loading_scene.gd")
const Pacer = preload("res://scripts/pacer.gd")

var _screen: LoadingScreen
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _run() -> void:
	await _screen_checks()
	await _pacer_checks()
	_map_checks()
	await _loader_checks()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _screen_checks() -> void:
	_screen = LoadingScreen.new()
	root.add_child(_screen)
	await process_frame
	_check(_screen._status.text == "Waking up the plateau…", "starts with the loading status")
	_check(_screen._bar.visible and not _screen._retry.visible, "progress bar up, Try again hidden")

	_screen.set_status("Connecting to 192.168.1.42:7777…")
	_screen.set_progress(0.5)
	await create_timer(0.8).timeout
	_check(_screen._status.text == "Connecting to 192.168.1.42:7777…", "status line follows the game")
	_check(absf(_screen._bar.value - 0.5) < 0.01, "the bar eases to the progress set (%.3f)" % _screen._bar.value)
	_check(_screen._percent.text == "50 %", "the percentage too (%s)" % _screen._percent.text)
	_screen.set_progress(0.5, 0.8)
	await create_timer(1.0).timeout
	_check(_screen._bar.value > 0.55 and _screen._bar.value < 0.8, "it creeps on towards the next figure (%.3f)" %
			_screen._bar.value)
	var crept: float = _screen._bar.value
	_screen.set_progress(0.3)
	await create_timer(0.3).timeout
	_check(_screen._bar.value >= crept - 0.001, "and never goes back (%.3f)" % _screen._bar.value)

	var retried := [false]
	_screen.retry.connect(func() -> void: retried[0] = true)
	_screen.show_error("The game's world could not be loaded.")
	_check(_screen._retry.visible and not _screen._bar.visible, "an error shows Try again, hides the bar")
	_screen._retry.pressed.emit()
	_check(retried[0], "Try again asks for a retry")
	_screen.reset()
	_check(_screen._bar.visible and not _screen._retry.visible and _screen._percent.text == "0 %", "reset clears the error")

	_screen.set_progress(1.0)
	_check(_screen._bar.value == 1.0 and _screen._percent.text == "100 %", "1 fills the bar at once (Ready)")
	_screen.set_indeterminate()
	_check(_screen._bar.indeterminate and not _screen._percent.visible, "indeterminate: no percentage")
	_screen.close()
	await create_timer(0.6).timeout
	_check(not is_instance_valid(_screen), "closing frees the screen")

	var overlay := LoadingScreen.new()
	overlay.fade_in = false
	var shown := [false]
	overlay.shown.connect(func() -> void: shown[0] = true)
	root.add_child(overlay)
	await process_frame
	_check(is_equal_approx(overlay.modulate.a, 1.0) and shown[0], "fade_in = false: opaque at once")
	overlay.queue_free()


func _pacer_checks() -> void:
	var pacer := Pacer.new(self, 5.0)
	var frame := Engine.get_process_frames()
	var steps := 0
	while steps < 40:
		OS.delay_usec(1000)                 # a 1 ms step of work
		steps += 1
		if pacer.due():
			await pacer.wait()
	var frames := Engine.get_process_frames() - frame
	_check(frames >= 5 and frames <= 12, "the pacer spreads 40 ms of work over frames of 5 ms (%d frames)" % frames)


func _map_checks() -> void:
	var data := LoadingMap.parse()
	_check(data.has("box") and (data["box"] as Rect2).has_area(), "the map has a frame")
	_check(data.get("lines", []).size() >= 4, "the map has the bus lines (%d)" % data.get("lines", []).size())
	_check(not data.get("rail", []).is_empty() and not data.get("roads", []).is_empty(), "and the RER B and the roads")
	var names: Array = data.get("stations", []).map(func(s: Array) -> String: return s[0])
	_check("Lozère" in names and names.size() >= 4, "and the stations (%s)" % ", ".join(names))


## The loader, as game.gd's back_to_menu starts it: frees a stand-in for the old game, then puts main.tscn in the tree.
func _loader_checks() -> void:
	var reference := (load(Loader.GAME) as PackedScene).instantiate()
	var expected := reference.find_children("*", "", true, true).size()
	var bodies := {}
	for b: CollisionObject3D in reference.get_node("Neighborhood").find_children("*", "CollisionObject3D", true, false):
		if b.get_script() == null:          # (the scripted ones make their shapes in the tree)
			bodies[reference.get_path_to(b)] = _enabled(b)
	reference.free()

	var old := Node3D.new()
	for i in 50:
		old.add_child(Node3D.new())
	root.add_child(old)
	current_scene = old
	var loader := Loader.new()
	loader.old_scene = old
	root.add_child(loader)
	var frames := 0
	while is_instance_valid(loader) and frames < 20000:
		await process_frame
		frames += 1
	_check(not is_instance_valid(loader), "the loader is done and gone (%d frames)" % frames)
	_check(not is_instance_valid(old), "the old game was freed")
	var main := current_scene
	_check(main != null and main.name == "Main", "the game is the current scene")
	if main == null or main.name != "Main":
		return
	_check(not paused and not root.disable_3d, "the tree runs and the 3D view is on again")
	_check(main.find_children("*", "", true, true).size() >= expected,
			"the whole world is in, owned as in main.tscn (%d nodes)" % expected)
	var wrong := 0
	for path: NodePath in bodies:
		var b := main.get_node_or_null(path) as CollisionObject3D
		if b == null or _enabled(b) != bodies[path]:
			wrong += 1
	_check(wrong == 0, "every body has its shapes enabled again (%d of %d differ)" % [wrong, bodies.size()])
	await physics_frame
	var spawn: Vector3 = main.player.global_position
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			spawn + Vector3.UP * 50.0, spawn + Vector3.DOWN * 50.0))
	_check(not hit.is_empty(), "the ground is under the spawn point")
	_check(main.menu != null and main.mode == "", "the welcome menu is up")
	_check(not Loader._models.is_empty(), "the vehicles' models are kept (%d)" % Loader._models.size())
	var screen := LoadingScreen.new()
	root.add_child(screen)
	for i in 3:
		await process_frame
	_check(screen._map._fit != Transform2D.IDENTITY and screen._map._fit_size == screen._map.size,
			"a later screen fits the map read before it to itself")
	screen.free()


static func _enabled(b: CollisionObject3D) -> int:
	var n := 0
	for o in b.get_shape_owners():
		if not b.is_shape_owner_disabled(o):
			n += 1
	return n
