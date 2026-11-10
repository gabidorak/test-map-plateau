extends SceneTree
## Frame rate at a site, vsync off: the camera over it, at eye level in it, then moving through it (the grass and the
## world streaming in), N frames each: mean fps, worst frame, draw calls, primitives; and the restyled buildings'
## build times and triangles. Windowed (it renders):
##   PERF_X=-275 PERF_Y=400 PERF_R=125 godot --path . --script res://tools/perf_site.gd -- --online-test

const Marks = preload("res://scripts/race_marks.gd")
const FRAMES := 240

var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	while not (_main.mode == "solo" and _main.game_mode != null):
		await process_frame
	var c := Vector2(float(OS.get_environment("PERF_X")), float(OS.get_environment("PERF_Y")))
	var r := float(OS.get_environment("PERF_R")) if OS.get_environment("PERF_R") != "" else 100.0
	var mid := Vector3(c.x, Marks.ground(c.x, c.y), -c.y)
	_main.player.teleport(mid + Vector3(0, 0.5, r * 0.3))
	for i in 120:
		await process_frame
	var restyle: Node = _main.get("restyle")
	if restyle:
		for slug: String in restyle.built:
			var b: Dictionary = restyle.built[slug]
			var tris := 0
			var meshes := 0
			for n: Node in (b["node"] as Node).find_children("*", "MeshInstance3D", true, false):
				var m: Mesh = (n as MeshInstance3D).mesh
				meshes += 1
				for s in m.get_surface_count():
					tris += m.surface_get_array_len(s) / 3
			print("PERF restyle %-14s %5d ms  %7d triangles  %3d meshes" % [slug, b.get("ms", 0), tris, meshes])
	_main.hud.visible = false
	var cam := Camera3D.new()
	cam.far = 2000.0
	root.add_child(cam)
	cam.make_current()
	cam.global_transform = Transform3D(Basis.IDENTITY, mid + Vector3(-r, r * 0.55, r)).looking_at(mid, Vector3.UP)
	await _sample("over", cam, Vector3.ZERO)
	cam.global_transform = Transform3D(Basis.IDENTITY, mid + Vector3(0, 1.7, r * 0.5)).looking_at(mid + Vector3(0, 5, 0),
			Vector3.UP)
	await _sample("eye", cam, Vector3.ZERO)
	# moving through it at 15 m/s, the player along (the world streams round the player)
	cam.global_transform = Transform3D(Basis.IDENTITY, mid + Vector3(-r, 1.8, r * 0.2)).looking_at(mid + Vector3(r, 1.8,
			r * 0.2), Vector3.UP)
	await _sample("move", cam, Vector3(15.0, 0, 0))
	quit(0)


func _sample(what: String, cam: Camera3D, speed: Vector3) -> void:
	for i in 60:
		await process_frame
	var worst := 0.0
	var total := 0.0
	var calls := 0.0
	var prims := 0.0
	var t := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - t) / 1000.0
		t = now
		worst = maxf(worst, ms)
		total += ms
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		if speed != Vector3.ZERO:
			cam.global_position += speed * ms / 1000.0
			_main.player.teleport(cam.global_position - Vector3(0, 1.3, 0))
	print("PERF %-5s %6.1f fps  worst %6.1f ms  %6.0f draw calls  %8.0f primitives" % [what, 1000.0 * FRAMES / total,
			worst, calls / FRAMES, prims / FRAMES])
