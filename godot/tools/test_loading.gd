extends SceneTree
## Headless checks of the loading screen (scripts/loading_screen.gd): its status line, progress bar easing to the
## figure set, percentage, the error state with its Try again button, and closing (fades out and frees itself).
## godot --headless --path godot --script res://tools/test_loading.gd

const LoadingScreen = preload("res://scripts/loading_screen.gd")

var _screen: LoadingScreen
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _run() -> void:
	_screen = LoadingScreen.new()
	root.add_child(_screen)
	await process_frame
	_check(_screen._status.text == "Loading the plateau…", "starts with the loading status")
	_check(_screen._bar.visible and not _screen._retry.visible, "progress bar up, Try again hidden")

	_screen.set_status("Connecting to 192.168.1.42:7777…")
	_screen.set_progress(0.5)
	await create_timer(0.6).timeout
	_check(_screen._status.text == "Connecting to 192.168.1.42:7777…", "status line follows the game")
	_check(absf(_screen._bar.value - 0.5) < 0.01, "the bar eases to the progress set (%.3f)" % _screen._bar.value)
	_check(_screen._percent.text == "50 %", "the percentage too (%s)" % _screen._percent.text)

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
	_check(not _screen._bar.visible and not _screen._percent.visible, "indeterminate hides the bar")
	_screen.close()
	await create_timer(0.5).timeout
	_check(not is_instance_valid(_screen), "closing frees the screen")

	var overlay := LoadingScreen.new()
	overlay.fade_in = false
	root.add_child(overlay)
	await process_frame
	_check(is_equal_approx(overlay.modulate.a, 1.0), "the host/join overlay is opaque at once")
	overlay.queue_free()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
