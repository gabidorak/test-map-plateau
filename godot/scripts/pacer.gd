extends RefCounted
## Spreads a long piece of main-thread work over frames, so the window keeps drawing (the loading screen's animation)
## while a game starts or the world is put together: between two steps the work calls
## `if pacer and pacer.due(): await pacer.wait()`, which carries on in the next frame once `budget_ms` of this one
## are used. A null pacer never waits: the tools, the tests and the dedicated server run the same code in one go.

var budget_usec := 0
var waits := 0                                # frames waited so far
var on_wait := Callable()                     # called before each wait (the overlay's progress)
var _tree: SceneTree
var _since := 0


func _init(tree: SceneTree, budget_ms := 12.0) -> void:
	_tree = tree
	budget_usec = int(budget_ms * 1000.0)
	_since = Time.get_ticks_usec()


## This frame's share of the work is used up.
func due() -> bool:
	return Time.get_ticks_usec() - _since >= budget_usec


## Lets a frame be drawn, then carries on.
func wait() -> void:
	if on_wait.is_valid():
		on_wait.call()
	waits += 1
	await _tree.process_frame
	_since = Time.get_ticks_usec()
