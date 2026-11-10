extends "res://tools/test_base.gd"
## Screenshots of a site, to check a restyled building (data/restyle/, scripts/restyle/): one from above and four
## oblique views from its corners, plus one at eye level from the south. Windowed (it renders):
##   CAP_X=585 CAP_Y=-262 CAP_R=80 CAP_OUT=C:/tmp/shots/ensae_ godot --path . --script res://tools/capture_site.gd -- --online-test
## CAP_X, CAP_Y: the site's middle (map x east, y north); CAP_R: its half size (m); CAP_OUT: the files' prefix;
## CAP_SHOTS: which ones (top,sw,se,ne,nw,eye; all by default).

const Marks = preload("res://scripts/race_marks.gd")

var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var c := Vector2(float(OS.get_environment("CAP_X")), float(OS.get_environment("CAP_Y")))
	var r := float(OS.get_environment("CAP_R")) if OS.get_environment("CAP_R") != "" else 60.0
	var out := OS.get_environment("CAP_OUT")
	var only: Array = OS.get_environment("CAP_SHOTS").split(",", false)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	await _until(func() -> bool: return _main.mode == "solo" and _main.game_mode != null, 120.0)
	var g := Marks.ground(c.x, c.y)
	var mid := Vector3(c.x, g, -c.y)
	_main.player.teleport(mid + Vector3(0, 0.5, r * 1.5))         # (the world streams in round the player)
	for i in 60:
		await process_frame
	_main.player.visible = false
	_main.hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	root.add_child(cam)
	cam.make_current()
	var views := {
		"sw": [mid + Vector3(-r, r * 0.55, r), mid], "se": [mid + Vector3(r, r * 0.55, r), mid],
		"ne": [mid + Vector3(r, r * 0.55, -r), mid], "nw": [mid + Vector3(-r, r * 0.55, -r), mid],
		"eye": [mid + Vector3(0, 1.7, r * 0.9), mid + Vector3(0, 6.0, 0)],
	}
	for k: String in views:
		if only.is_empty() or k in only:
			cam.global_transform = Transform3D(Basis.IDENTITY, views[k][0]).looking_at(views[k][1], Vector3.UP)
			await _save(out + k + ".png")
	if only.is_empty() or "top" in only:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = r * 2.0
		cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), mid + Vector3(0, r * 1.2, 0))   # (near: the detailed ground)
		await _save(out + "top.png")
	quit(0)


func _save(path: String) -> void:
	for i in 45:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
