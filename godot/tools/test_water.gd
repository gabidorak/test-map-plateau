extends SceneTree
## Headless checks for the water (scripts/water.gd) and the jet-ski (scripts/jet_ski.gd): the scene has its bodies of
## water, the Lac de l'X at its level with its bed dug out under the surface; a player dropped in it swims with the head
## out and moves at swimming speed. The vehicle code parks the jet-ski on the lake near a player on its shore, where it
## floats level at its waterline; E gets on, W takes it past 15 m/s still upright and floating, A turns it, letting go
## it coasts down, Space gets off into the water (swimming). Far from any lake it is parked on land, where it only
## crawls. A car driven into deep water floats a moment, then fills and sinks to the bed with its engine drowned; the
## horse swims there with its back at the surface.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_water.gd
## Without --headless it also saves shots to /tmp/water_*.png.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Water = preload("res://scripts/water.gd")
const LAKE := "r3259663"                    # Lac de l'X (OSM relation)
const LAKE_PROBE := Vector2(950.0, 300.0)   # pipeline x, y: in the lake's east basin

var _main: Node
var _failures: PackedStringArray = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


func _ground(p: Vector3) -> float:
	return WorldQuery.ground_y(_main.get_world_3d(), p.x, p.z, Layers.SOLID, p.y + 2.0)


func _run() -> void:
	await _frames(60)
	var player: CharacterBody3D = _main.player
	var water = Water.current
	_check(water != null and water.bodies.size() >= 10, "the scene has its bodies of water (%d)" % (water.bodies.size()
			if water else 0))
	if water == null:
		_finish()
		return
	var lake: Dictionary = {}
	for b: Dictionary in water.bodies:
		if b["src"] == LAKE:
			lake = b
	_check(not lake.is_empty() and float(lake["area"]) > 50000.0 and absf(float(lake["level"]) + 3.4) < 0.4,
			"the Lac de l'X is a body of water at its level (%.2f m, %.0f m²)" % [lake.get("level", NAN), lake.get("area", 0.0)])
	var level: float = lake["level"]
	var deep: Variant = water.spot_near(Vector3(LAKE_PROBE.x, 0.0, -LAKE_PROBE.y), 120.0, 12.0, 10000.0)
	_check(deep != null, "there is open water in the lake's east basin")
	if deep == null:
		_finish()
		return
	var spot: Vector3 = (deep as Transform3D).origin
	var bed := _ground(spot + Vector3.UP * 3.0)
	_check(absf(Water.surface_at(spot) - level) < 0.01 and bed < level - 2.0,
			"out in the lake the bed is dug %.2f m under the surface" % (level - bed))
	_check(is_nan(Water.surface_at(player.global_position)), "no water at the spawn point")

	# a player dropped in swims, head out, at swimming speed
	player.teleport(spot + Vector3.UP * 2.0)
	await _frames(240)
	var feet := player.global_position.y
	_check(player.swimming and absf(feet - (level - player.float_depth)) < 0.2,
			"dropped in the lake the player swims (feet %.2f m under the surface, the bed %.2f m)" % [level - feet, level - bed])
	player.scripted_input = Vector2(0.0, 1.0)
	await _frames(120)
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	_check(absf(hv - player.swim_speed) < 0.3 and player.swimming, "W swims at %.1f m/s" % hv)
	await _shot("water_swim.png")
	player.scripted_input = null

	# the jet-ski, parked from the shore
	var shore := _shore(spot, level)
	_check(shore != Vector3.INF, "a dry spot on the shore near it")
	player.teleport(shore)
	await _frames(10)
	var ski: VehicleBody3D = _main.spawn_car_near_player("jet-ski")
	_check(ski != null and ski.get_script() == _main.JetSki, "the vehicle code parks a jet-ski")
	if ski == null:
		_finish()
		return
	await _frames(240)
	var sit: float = level - ski.global_position.y
	_check(ski.floating and not is_nan(Water.surface_at(ski.global_position)) and absf(sit - ski.REST_SUB) < 0.1
			and ski.global_basis.y.y > 0.98 and ski.linear_velocity.length() < 0.3,
			"it floats on the lake, level, at its waterline (keel %.2f m under, %.2f m/s)" % [sit, ski.linear_velocity.length()])
	await _shot("water_jetski_parked.png")
	player.teleport(ski.to_global(Vector3(ski.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(5)
	_check(_main.driving == ski and ski._rider.visible, "E gets on, the rider shows")
	var run := _open_run(spot, level)
	ski.place(Transform3D(Basis.looking_at(-run[0]), spot))
	await _frames(60)
	var start := ski.global_position
	_key(KEY_W, true)
	var upright := true
	for i in 420:
		await physics_frame
		upright = upright and ski.global_basis.y.y > 0.85
		if i == 300:
			await _shot("water_jetski_fast.png")
	_check(ski.speed() > 15.0 and ski.floating and upright, "W takes it to %.1f m/s, upright and floating" % ski.speed())
	_key(KEY_A, true)
	var yaw0: float = ski.global_rotation.y
	await _frames(60)
	await _shot("water_jetski_turn.png")
	await _frames(30)
	_key(KEY_A, false)
	var turned := rad_to_deg(absf(wrapf(ski.global_rotation.y - yaw0, -PI, PI)))
	_check(turned > 50.0 and ski.floating, "A turns it (%.0f° in 1.5 s)" % turned)
	_key(KEY_W, false)
	var v0: float = ski.speed()
	await _frames(180)
	_check(ski.speed() < v0 * 0.6 and ski.speed() >= 0.0, "letting go it coasts down (%.1f -> %.1f m/s)" % [v0, ski.speed()])
	_check(ski.global_position.distance_to(start) > 40.0 and not is_nan(Water.surface_at(ski.global_position)),
			"still on the lake, %.0f m from where it started" % ski.global_position.distance_to(start))
	await _frames(120)
	_tap(KEY_SPACE)
	await _frames(5)
	var off := player.global_position.distance_to(ski.global_position)
	await _frames(120)
	_check(_main.driving == null and player.visible and player.swimming and off < 4.0,
			"Space gets off beside it (%.1f m) into the water, swimming" % off)

	# a car driven into deep water: floats a while, then sinks to the bed, engine drowned
	var car: VehicleBody3D = _main.new_vehicle("sedan")
	_main.add_child(car)
	_main._add_car(car)
	var car_at := spot + Vector3(12.0, 0.0, 0.0)
	if is_nan(Water.surface_at(car_at)):
		car_at = spot
	car.place(Transform3D(Basis(), car_at + Vector3.UP * 0.3))
	await _frames(180)
	var car_bed := _ground(car_at + Vector3.UP * 3.0)
	_check(car.in_water > 0.0 and car.global_position.y > car_bed + 0.8,
			"a car in deep water floats a moment (%.2f m over the bed)" % (car.global_position.y - car_bed))
	await _frames(roundi((car.FLOOD_TIME + 3.0) * 60.0))
	_check(car.flooded >= 1.0 and car.global_position.y - car_bed < 0.5 and car._water_physics(1.0 / 60.0),
			"then fills, sinks to the bed (%.2f m over it) and its engine drowns" % (car.global_position.y - car_bed))

	# the horse swims, its back at the surface
	var horse: VehicleBody3D = _main.new_vehicle("horse")
	_main.add_child(horse)
	_main._add_car(horse)
	horse.place(Transform3D(Basis(), spot + Vector3(-10.0, 0.5, 6.0)))
	await _frames(240)
	_check(horse.swimming and absf(horse.global_position.y - (level - horse.SWIM_DRAFT)) < 0.25,
			"the horse swims (%.2f m under the surface)" % (level - horse.global_position.y))

	# far from any lake the jet-ski is parked on land, where it only crawls
	player.teleport(_ground_point(_main.spawn_xy))
	await _frames(30)
	var dry: VehicleBody3D = _main.spawn_car_near_player("jet-ski")
	await _frames(60)
	_check(dry != null and not dry.floating and is_nan(Water.surface_at(dry.global_position)),
			"far from water it is parked on land")
	if dry:
		player.teleport(dry.to_global(Vector3(dry.half_extents.x + 1.0, 0.3, 0.0)))
		await _frames(5)
		_tap(KEY_E)
		await _frames(5)
		_key(KEY_W, true)
		await _frames(180)
		_key(KEY_W, false)
		_check(_main.driving == dry and dry.speed() > 0.5 and dry.speed() < dry.LAND_SPEED + 0.5,
				"on land W only crawls (%.1f m/s)" % dry.speed())
	_finish()


## [direction, metres] of the longest straight run of water at least 1 m deep from `spot` (16 headings).
func _open_run(spot: Vector3, level: float) -> Array:
	var best := [Vector3.FORWARD, 0.0]
	for a in 16:
		var dir := Vector3(cos(TAU * a / 16.0), 0.0, sin(TAU * a / 16.0))
		var d := 0.0
		while d < 400.0:
			var p := spot + dir * (d + 2.0)
			if is_nan(Water.surface_at(p)) or _ground(Vector3(p.x, level, p.z)) > level - 1.0:
				break
			d += 2.0
		if d > best[1]:
			best = [dir, d]
	return best


## A dry spot (Godot, on the ground) a few metres up the shore from `spot` (in the water at `level`), or INF.
func _shore(spot: Vector3, level: float) -> Vector3:
	for a in 16:
		var dir := Vector3(cos(TAU * a / 16.0), 0.0, sin(TAU * a / 16.0))
		for d in range(5, 120, 2):
			var p := spot + dir * d
			if is_nan(Water.surface_at(p)):
				var q := p + dir * 3.0
				var g := _ground(Vector3(q.x, level + 3.0, q.z))
				if not is_nan(g) and g > level and g < level + 2.0 and is_nan(Water.surface_at(q)):
					return Vector3(q.x, g + 0.1, q.z)
				break
	return Vector3.INF


func _ground_point(xy: Vector2) -> Vector3:
	var g := WorldQuery.ground_y(_main.get_world_3d(), xy.x, -xy.y, Layers.SOLID)
	return Vector3(xy.x, g + 0.1, -xy.y)


func _finish() -> void:
	print("%d failures" % _failures.size())
	for f in _failures:
		print("  - " + f)
	quit(1 if _failures.size() > 0 else 0)
