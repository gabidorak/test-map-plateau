extends SceneTree
## The routes the swarm's bots drive (swarm.gd): the bot cars' routes (world/car_routes.json) thinned to 10 m points
## with their ground heights, and the public garages' terminals, so that each swarm process needn't load the heightmap.
## godot --headless --path godot --script res://tools/bench/make_routes.gd -- OUT.json

const GroundMap = preload("res://scripts/ground_map.gd")


func _initialize() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/car_routes.json"))
	var ground: RefCounted = GroundMap.get_map()
	var routes := []
	for r: Dictionary in data["routes"].values():
		var pts := []
		var i := 0
		while i < r["pts"].size():
			var p: Array = r["pts"][i]
			var h: float = ground.height(p[0], p[1])
			pts.append([p[0], p[1], 0.0 if is_nan(h) else snappedf(h, 0.01), r["v"][mini(i, r["v"].size() - 1)]])
			i += 5
		routes.append(pts)
	var garages := []
	var gdata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/garages.json"))
	for g: Dictionary in gdata["garages"]:
		if g["kind"] == "public":
			var t: Dictionary = g["terminal"]
			garages.append({"id": g["id"], "x": t["x"], "y": t["y"], "z": ground.height(t["x"], t["y"])})
	FileAccess.open(out_path, FileAccess.WRITE).store_string(JSON.stringify({"routes": routes, "garages": garages}))
	print("%d routes in %s" % [routes.size(), out_path])
	quit()
