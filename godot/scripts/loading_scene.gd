extends CanvasLayer
## The loader: puts the game (scenes/main.tscn, the 84 MB generated world, 58k nodes) on screen behind
## scripts/loading_screen.gd without ever holding the window still. It is the startup scene
## (application/run/main_scene), and game.gd's back_to_menu adds one with `old_scene` set to leave a game for the welcome
## menu. Each step keeps the screen's animation going:
## - leaving (back to the menu): the game is paused and taken out of the tree, then freed a few hundred nodes a frame
##   (in one go it held the window ~1 s);
## - reading main.tscn on a worker thread (the first time only: the PackedScene is kept for the session), its progress
##   filling the bar;
## - instancing it (one pause of ~0.4 s left: on a worker thread it held the main thread longer, on the servers' locks);
## - putting it in the tree a slice at a time: the world's groups are taken out of their parents first, the scene goes
##   in nearly empty (game.gd's _ready waits for world_staged, see `staged` there), and the groups and their children
##   go back in their order, a frame's budget (BUDGET_MS) at a time, with the tree paused so nothing runs on a
##   half-built world. The bodies of many shapes (terrain, buildings) go in with their shapes disabled, which are
##   then enabled by batches (_enable_shapes). Godot used to do all this in one frame: the window froze for seconds.
##   The ground map grass reads is loaded on a worker thread meanwhile (2 s of the main thread in grass_field.gd's
##   _ready), and the vehicles' models are read a slice each (_model_files);
## - then the game carries on (welcome menu, or a command line start) and the screen fades out once it has drawn a few
##   frames behind it (the first frames compile the world's shaders).
## On a read failure the screen says so and offers Try again. A dedicated server (headless) has no screen: it reads
## and opens the game in one go, as it always did. Packed builds start scripts/boot.gd, which opens this scene once
## their data is unpacked and mounted. Tools and tests instance main.tscn themselves and never see it.

const LoadingScreen = preload("res://scripts/loading_screen.gd")
const Pacer = preload("res://scripts/pacer.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const GAME := "res://scenes/main.tscn"
const MIN_SHOW := 0.8                         # s: long enough that a warm start does not flash the screen
const BUDGET_MS := 12.0                       # ms of work per frame: the screen keeps ~40-60 fps
const SETTLE_FRAMES := 4                      # frames the game draws behind the screen before it fades
const NEEDS_GROUND := ["res://scripts/grass_field.gd"]   # scripts reading GroundMap in _ready

## main.tscn once read, and the vehicles' models, for the rest of the session: going back to the menu does not read
## them again.
static var _packed: PackedScene
static var _models: Array[Resource] = []
static var _tracing := OS.get_environment("PLATEAU_LOAD_TRACE") == "1"

var old_scene: Node                           # back_to_menu: the game left, freed here first

var _screen: LoadingScreen
var _started := 0.0
var _running := false
var _hid_3d := false                          # the 3D view is off while the screen covers it


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = LoadingScreen.new()
	add_child(_screen)
	_screen.retry.connect(_run)
	if DisplayServer.get_name() == "headless" and old_scene == null:
		# A dedicated server has no screen to keep alive, and threaded resource loading can be much slower under the
		# dummy renderer: read the world on this thread, as the game did before the loading scene existed.
		_screen.visible = false
		_open_sync.call_deferred()
		return
	_run()


func _run() -> void:
	if _running:
		return
	_running = true
	_screen.reset()
	_started = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	if old_scene:
		_screen.set_status("Back to the main menu…")
		await _screen.shown
	_hide_3d(true)
	if old_scene:
		await _free_old()
	if _packed == null:
		_packed = await _read()
		if _packed == null:
			_running = false
			return
	var main := await _instance()
	if main == null:
		_running = false
		return
	await _enter(main)
	await _settle()


## The old game out of the tree, then freed a slice at a time (the bar's first 30 %).
func _free_old() -> void:
	var old := old_scene
	old_scene = null
	var t0 := Time.get_ticks_usec()
	if old.get_parent():
		old.get_parent().remove_child(old)
	_trace(old, "out of the tree", t0)
	var parts: Array[Node] = []
	_collect(old, parts, 3)
	var pacer := Pacer.new(get_tree(), BUDGET_MS)
	for i in parts.size():
		if is_instance_valid(parts[i]):
			parts[i].free()
		if pacer.due():
			_screen.set_progress(0.3 * i / parts.size(), 0.3)
			await pacer.wait()
	if is_instance_valid(old):
		old.free()
	_screen.set_progress(0.3, 0.4)


## `n`'s descendants to free one by one, deepest first, down `depth` levels under the nodes with many children.
static func _collect(n: Node, out: Array[Node], depth: int) -> void:
	for c in n.get_children():
		if depth > 0 and c.get_child_count() > 8:
			_collect(c, out, depth - 1)
		out.append(c)


## Reads main.tscn on a worker thread (the bar up to 50 %), or null after showing the error.
func _read() -> PackedScene:
	_screen.set_status("Waking up the plateau…")
	var err := ResourceLoader.load_threaded_request(GAME, "PackedScene", false)
	if err != OK:
		_fail("The game's world could not be loaded (error %d)." % err)
		return null
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(GAME, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_fail("The game's world could not be loaded. Is the game data complete?")
			return null
		var fraction: float = progress[0] if not progress.is_empty() else 0.0
		_screen.set_progress(0.5 * fraction, 0.5 * minf(1.0, fraction + 0.05))
		_screen.set_status(_stage_for(fraction))
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(GAME) as PackedScene
	if packed == null:
		_fail("The game's world could not be loaded.")
	return packed


## What the loader is doing, from how far it is: it loads the scene file, then every mesh, material and shape it
## references, roughly in the order they are written (water, ground, buildings, vegetation, props).
static func _stage_for(fraction: float) -> String:
	if fraction < 0.03:
		return "Waking up the plateau…"
	if fraction < 0.35:
		return "Loading the map…"
	if fraction < 0.7:
		return "Placing the buildings…"
	return "Growing the trees…"


## The game's scene, built once the screen says so.
func _instance() -> Node:
	_screen.set_status("Unfolding the map…")
	_screen.set_progress(0.3, 0.55)            # (the bar never goes back: still 50 % after the first read)
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var main := _packed.instantiate()
	_trace(self, "instantiate", t0)
	if main == null:
		_fail("The game could not be started.")
	return main


## Puts `main` in the tree a slice at a time (the bar from 55 to 95 %), then lets its _ready carry on.
func _enter(main: Node) -> void:
	_screen.set_status("Putting the plateau together…")
	var world := main.get_node_or_null("Neighborhood")
	var parts: Array = []                     # [parent, node], or [body, [its shapes]], in the order they go back
	if world:
		var groups := world.get_children()
		for g in groups:
			world.remove_child(g)
		for g in groups:
			parts.append([world, g])
			if g.get_script():
				continue                        # its _ready may want its children
			var kids := g.get_children()
			if g.get_class() == "Node3D":
				for k in kids:                  # a plain group: its children one by one
					g.remove_child(k)
					parts.append([g, k])
			elif g is CollisionObject3D and kids.size() > 16:
				# A body of many shapes (terrain, buildings): in with them disabled, then enabled by batches. (Taken
				# out of it one by one, they cost more than they saved: Godot renumbers all the shapes on each.)
				var shapes := kids.filter(func(k: Node) -> bool: return k is CollisionShape3D and not k.disabled)
				for k: CollisionShape3D in shapes:
					k.disabled = true
				parts.append([g, shapes])
	if _models.is_empty():
		# The vehicles' models, one a slice, before the showrooms want theirs. (Read on worker threads, their textures
		# held the main thread longer than this.)
		var at := maxi(0, parts.find_custom(func(p: Array) -> bool: return p[1] is Node and p[1].name == "Interiors"))
		for path in _model_files():
			parts.insert(at, [self, path])
			at += 1
	var ground := WorkerThreadPool.add_task(func() -> void: GroundMap.get_map(), false, "Read the ground map")
	var total := 0.0
	var weights := PackedFloat32Array()
	for p: Array in parts:
		var w := _weight(p[1])
		weights.append(w)
		total += w
	main.set("staged", true)
	var t0 := Time.get_ticks_usec()
	get_tree().root.add_child(main)
	_trace(get_tree().root, main, t0)
	get_tree().current_scene = main
	total = maxf(total, 1.0)
	var pacer := Pacer.new(get_tree(), BUDGET_MS)
	var done := [0.0, 0.0]                    # weight in, weight of the part going in (an array: the lambda sees it)
	pacer.on_wait = func() -> void:
		_screen.set_progress(lerpf(0.55, 0.95, done[0] / total), lerpf(0.55, 0.95, (done[0] + done[1]) / total))
	for i in parts.size():
		done[1] = maxf(weights[i], 20.0)
		t0 = Time.get_ticks_usec()
		if parts[i][1] is String:
			var model := load(parts[i][1])
			if model:
				_models.append(model)
			_trace(self, parts[i][1], t0)
		elif parts[i][1] is Array:
			await _enable_shapes(parts[i][0], parts[i][1], pacer)
		else:
			var node: Node = parts[i][1]
			if ground >= 0 and node.get_script() and (node.get_script() as Script).resource_path in NEEDS_GROUND:
				while not WorkerThreadPool.is_task_completed(ground):
					await get_tree().process_frame
				WorkerThreadPool.wait_for_task_completion(ground)
				ground = -1
			_put(parts[i][0], node)
			_trace(parts[i][0], node, t0)
		done[0] += weights[i]
		if pacer.due():
			await pacer.wait()
	if ground >= 0:
		WorkerThreadPool.wait_for_task_completion(ground)
	_screen.set_status("Setting the game up…")
	_screen.set_progress(0.95, 0.99)
	await pacer.wait()
	if main.has_signal("set_up"):
		# Its _ready (menus, traffic, trains...) carries on over a few frames, the tree still paused.
		main.emit_signal("world_staged")
		await Signal(main, "set_up")
	get_tree().paused = false


## `node` back under `parent`. Its owner stays the world's root: unset while it goes back in, as Godot asks.
static func _put(parent: Node, node: Node) -> void:
	var o := node.owner
	node.owner = null
	parent.add_child(node)
	node.owner = o


## A body's disabled `shapes` enabled by batches, each sized to a frame's budget: the body leaves the physics space
## while a batch is enabled and comes back with it, so Jolt builds its compound shape once per batch (not per shape:
## quadratic, see tree_collision.gd), and the shapes' own meshes (the slow part, the first time) a batch at a time.
func _enable_shapes(body: CollisionObject3D, shapes: Array, pacer: Pacer) -> void:
	var rid := body.get_rid()
	var space := PhysicsServer3D.body_get_space(rid)
	var batch := 8
	var i := 0
	while i < shapes.size():
		var t0 := Time.get_ticks_usec()
		var end := mini(i + batch, shapes.size())
		PhysicsServer3D.body_set_space(rid, RID())
		for j in range(i, end):
			shapes[j].disabled = false
		PhysicsServer3D.body_set_space(rid, space)
		_trace(body, "%d shapes" % (end - i), t0)
		var per := float(Time.get_ticks_usec() - t0) / (end - i)
		batch = clampi(int(pacer.budget_usec * 0.8 / maxf(per, 1.0)), 4, 1024)
		i = end
		if pacer.due() and i < shapes.size():
			await pacer.wait()


## A rough cost of putting a part in the tree, for the bar: scripts and shapes are the slow ones.
static func _weight(part: Variant) -> float:
	if part is String:
		return 15.0                             # a vehicle model
	if part is Array:
		return 1.5 * part.size()
	var n: Node = part
	if n.get_script():
		return 40.0
	if n is CollisionObject3D:
		return 3.0
	return 0.05 + 0.05 * n.get_child_count()


## The vehicles' model files (car.gd SPECS), read while the world goes in, and kept for the session: they were read
## as the showrooms and the first vehicles of a game were set up, a pause each.
static func _model_files() -> PackedStringArray:
	var car := load("res://scripts/car.gd") as GDScript   # (already read: game.gd preloads it)
	var specs: Dictionary = car.get_script_constant_map().get("SPECS", {})
	var out := PackedStringArray()
	for model: String in specs:
		var path := "res://assets/cars/" + String(specs[model].get("file", model + ".glb"))
		if path not in out and ResourceLoader.exists(path):
			out.append(path)
	return out


## PLATEAU_LOAD_TRACE=1: the parts that held the main thread more than 30 ms, to find the next pause to spread out.
static func _trace(parent: Variant, part: Variant, t0: int) -> void:
	if not _tracing:
		return
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 30.0:
		print("Loading: %6.0f ms  %s / %s" % [ms, parent.name if parent is Node else str(parent),
				part.name if part is Node else str(part)])


## The game draws a few frames behind the screen, which then fades out and goes.
func _settle() -> void:
	_screen.set_status("Almost there…")
	await get_tree().process_frame
	_hide_3d(false)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var left := MIN_SHOW - (Time.get_ticks_msec() / 1000.0 - _started)
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	_screen.set_status("Ready")
	_screen.set_progress(1.0)
	_screen.close()
	await _screen.tree_exited
	queue_free()


## Headless: no screen, so no progress to report; load and open the game in one go (as main.tscn used to be started).
func _open_sync() -> void:
	var packed := load(GAME) as PackedScene
	if packed == null:
		_fail("The game's world could not be loaded.")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		_fail("The game could not be started (error %d)." % err)


## Nothing 3D drawn under the opaque screen: each frame of the work stays short (the screen's animation smooth, the
## work done sooner), and the world's shaders compile in the few frames before it fades (_settle). Left alone when the
## updater's page hid it already.
func _hide_3d(on: bool) -> void:
	var root := get_tree().root
	if on and not root.disable_3d:
		root.disable_3d = true
		_hid_3d = true
	elif not on and _hid_3d:
		root.disable_3d = false
		_hid_3d = false


func _fail(message: String) -> void:
	printerr("Loading: " + message)
	_hide_3d(false)
	get_tree().paused = false
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	_screen.show_error(message)
