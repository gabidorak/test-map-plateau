extends Node3D
## Game controller on scenes/main.tscn: spawns the player, switches between the player and the
## fly camera (F1), owns the HUD and the debug picker (F). Click captures the mouse, Esc frees it.
## Debug cars (scripts/car.gd) are parked next to the spawn point; C parks another one next to the
## player, E gets into the nearest car and Space gets out. The bus is walkable: the player standing in it
## is carried along (also while it moves), E near its driver seat takes the wheel, and Space leaves the
## seat into the aisle (the bus rolls on, handbrake once slow); O (driver) opens and closes its doors.
## The mouse wheel zooms the camera, all the way in is first person (walking) or the cab view (driving the bus);
## first person and the cab view carry over when taking and leaving the driver seat. The articulated bus carries the
## player in whichever of its two sections they stand (Car.carrier_at).
## Graphics: "low" (no SSIL/SSAO/glow, FXAA instead of MSAA) keeps 60 fps on an integrated GPU; it is
## the default there, "high" elsewhere. PLATEAU_QUALITY=low|high overrides, F2 switches.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Picker = preload("res://scripts/picker.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Car = preload("res://scripts/car.gd")
const ENTER_RANGE := 3.0                    # metres from the car body
const SEAT_RANGE := 1.6                     # metres from the driver seat, from inside a walkable vehicle

## Spawn point in pipeline coordinates (x east, y north): the street in front of the
## Télécom Paris main entrance, facing it (south).
@export var spawn_xy := Vector2(-34, 55.0)
@export var spawn_yaw_deg := 180.0
@export var debug_cars := true              # park a few cars next to the player at start

var flying := false
var driving: Car                            # the car the player is in, or null
var cars: Array[Car] = []
var _next_model := 0
var picker: Picker
var hud: CanvasLayer
var _help: Label
var _dash: Label                            # speed, gear, indicators, doors while driving
var low_quality := false
var _high := {}                             # the scene's own settings, restored by "high"

@onready var player: CharacterBody3D = $Player
@onready var fly_camera: Camera3D = $Camera
@onready var world_root: Node3D = $Neighborhood


func _ready() -> void:
	picker = Picker.new()
	picker.world_root = world_root
	add_child(picker)
	_build_hud()
	var env: Environment = $WorldEnvironment.environment
	_high = {"ssil": env.ssil_enabled, "ssao": env.ssao_enabled, "glow": env.glow_enabled,
			"msaa": get_viewport().msaa_3d, "aa": get_viewport().screen_space_aa}
	var q := OS.get_environment("PLATEAU_QUALITY")
	set_low_quality(q == "low" if q in ["low", "high"] \
			else RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU)
	fly_camera.active = false
	player.camera.current = true
	await get_tree().physics_frame
	spawn_at(spawn_xy, deg_to_rad(spawn_yaw_deg))
	if debug_cars:
		for i in 4:
			spawn_car_near_player()


func _physics_process(_delta: float) -> void:
	if driving or flying:
		return
	# a car, or the rear section of an articulated one (car_trailer.gd)
	var c: Node3D = player.carrier if is_instance_valid(player.carrier) else null
	# leave with a small margin so the doorway does not flicker
	if c and not c.carries(player.global_position, 0.1):
		c = null
	if c == null:
		for car in cars:
			c = car.carrier_at(player.global_position)
			if c:
				break
	player.set_carrier(c)


func _process(_delta: float) -> void:
	_dash.visible = driving != null
	if driving:
		var arrows := ["  ", "  "]
		if driving.indicator != 0 and fmod(Time.get_ticks_msec() / 1000.0, Car.BLINK) < Car.BLINK * 0.5:
			arrows[0 if driving.indicator == 1 else 1] = "◀" if driving.indicator == 1 else "▶"
		var line := "%s  %3d km/h   gear %s  %s" % [arrows[0], roundi(absf(driving.speed()) * 3.6),
				"R" if driving.speed() < -0.5 else str(driving.audio.gear + 1), arrows[1]]
		if driving.has_doors:
			line += "\ndoors " + ("OPEN" if driving.doors_open else "closed")
		_dash.text = line


## Puts the player on the ground at pipeline (x, y).
func spawn_at(xy: Vector2, yaw := 0.0) -> void:
	var g := WorldQuery.ground_y(get_world_3d(), xy.x, -xy.y, Layers.SOLID)
	player.teleport(MeshUtils.to_godot(xy.x, xy.y, 0.0 if is_nan(g) else g + 0.1), yaw)


func set_flying(on: bool) -> void:
	if on == flying:
		return
	if on and driving:
		exit_car()
	if on:
		player.set_carrier(null)
	flying = on
	if on:
		fly_camera.global_transform = player.camera.global_transform
		fly_camera.make_current()
	else:
		# land the player under the fly camera, facing the same way
		var p := fly_camera.global_position
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, p.y)
		if not is_nan(g):
			player.teleport(Vector3(p.x, g + 0.1, p.z), fly_camera.global_rotation.y)
		player.camera.make_current()
	fly_camera.active = on
	player.active = not on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_help()


## Low (true) or high graphics settings (see the header).
func set_low_quality(on: bool) -> void:
	low_quality = on
	var env: Environment = $WorldEnvironment.environment
	env.ssil_enabled = _high["ssil"] and not on
	env.ssao_enabled = _high["ssao"] and not on
	env.glow_enabled = _high["glow"] and not on
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if on else _high["msaa"]
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else _high["aa"]
	if _help:
		_update_help()


## For tools/screenshot*.gd: fly camera, no HUD, no player.
func set_screenshot_mode() -> void:
	set_flying(true)
	hud.visible = false
	player.visible = false
	debug_cars = false
	for car in cars:
		car.queue_free()
	cars.clear()


## Parks the next car model near the player on the first free spot: on a road or asphalt within
## ~20 m, lined up with it, when there is one; else anywhere beside the player, parallel to where the
## player looks. Returns the car, or null when no spot is free.
func spawn_car_near_player() -> Car:
	var model: String = Car.MODELS[_next_model % Car.MODELS.size()]
	_next_model += 1
	var car := Car.new()
	car.setup(model)
	var yaw: float = player.camera.global_rotation.y
	var spot: Variant = _find_car_spot(yaw, car.half_extents, true)
	if spot == null:
		spot = _find_car_spot(yaw, car.half_extents, false)
	if spot != null:
		spot = spot.translated_local(-car.extents_center)  # the spot is the footprint centre, not the car origin
	if spot == null:
		print("no free spot for a %s near the player" % model)
		car.free()
		return null
	add_child(car)
	car.place(spot)
	if car.inside:
		for body in car.bodies():
			player.add_collision_exception_with(body)   # the player collides with its walkable hull instead
	cars.append(car)
	return car


## Car transform (+Z forward, origin on the ground) for a free spot around the player for a vehicle of
## `half` extents, or null. `on_road`: the footprint must lie on road/parking ground; the heading is then
## searched in 15° steps from the player's (so the car lines up with the road), and the search reaches
## further out.
func _find_car_spot(yaw: float, half: Vector3, on_road: bool) -> Variant:
	var map: GroundMap = GroundMap.get_map() if on_road else null
	if on_road and map == null:
		return null
	var space := get_world_3d().direct_space_state
	var probe := BoxShape3D.new()
	probe.size = Vector3(half.x * 2.0 + 0.3, 2.0, half.z * 2.0 + 0.3)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.PLAYER
	var offsets: Array[Vector2] = []            # (side, along) in the player's frame, nearest first
	var s0 := half.x + 3.0                      # beside the player, room to walk between
	var sides := [0.0] if on_road else []
	for k in (5 if on_road else 3):
		sides.append_array([s0 + 3.0 * k, -(s0 + 3.0 * k)])
	var step := half.z * 2.0 + 0.6
	for side: float in sides:
		for along: float in [0.0, -1.0, 1.0, -2.0, 2.0, -3.0, 3.0]:
			offsets.append(Vector2(side, along * step))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	var turns := [0.0]
	if on_road:
		for k in range(1, 7):
			turns.append_array([deg_to_rad(15.0 * k), deg_to_rad(-15.0 * k)])
	var origin := player.global_position
	for o in offsets:
		var p := origin + Basis(Vector3.UP, yaw) * Vector3(o.x, 0.0, o.y)
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, origin.y + 3.0)
		if is_nan(g) or absf(g - origin.y) > 2.0 or _near_a_car(p, half.z + 0.5):
			continue
		for turn: float in turns:
			# the model faces +Z: yaw + PI points it where the player looks (-Z of the camera)
			var b := Basis(Vector3.UP, yaw + PI + turn)
			if on_road and not _on_road(map, p, b, half):
				continue
			q.transform = Transform3D(b, Vector3(p.x, g + 1.3, p.z))
			if not space.intersect_shape(q, 1):
				return Transform3D(b, Vector3(p.x, g + 0.3, p.z))
	return null


## True when a grid over the footprint of a vehicle of `half` extents at `p` (Godot) facing `b` is on road,
## parking or other asphalt ground.
func _on_road(map: GroundMap, p: Vector3, b: Basis, half: Vector3) -> bool:
	var hx := half.x - 0.15
	var n := ceili(half.z / 1.5)                # every ~1.5 m along long vehicles
	for i in range(-n, n + 1):
		for x: float in [-hx, 0.0, hx]:
			if not _paved(map, p + b * Vector3(x, 0.0, (half.z - 0.15) * i / n)):
				return false
	return true


func _paved(map: GroundMap, w: Vector3) -> bool:
	var k := map.piece_at(w.x, -w.z)
	return k >= 0 and (map.pieces[k][0] in ["road", "parking"] or map.pieces[k][1] == "asphalt")


## True when a car stands within `d` metres (horizontally, plus that car's half length) of `p`; cars
## parked this frame are not in the physics space yet, so the shape query alone misses them.
func _near_a_car(p: Vector3, d: float) -> bool:
	for car in cars:
		var c := car.to_global(car.extents_center)
		if Vector2(c.x - p.x, c.z - p.z).length() < d + car.half_extents.z:
			return true
	return false


## Nearest car within ENTER_RANGE of the player, or null.
func nearest_car() -> Car:
	var best: Car = null
	var best_d := ENTER_RANGE
	for car in cars:
		var p := car.to_local(player.global_position) - car.extents_center
		var d := Vector2(maxf(absf(p.x) - car.half_extents.x, 0.0), maxf(absf(p.z) - car.half_extents.z, 0.0)).length()
		if d < best_d:
			best = car
			best_d = d
	return best


## Car to get into with E: from inside a walkable vehicle, that one when the player is near its driver
## seat; else the nearest car.
func car_to_enter() -> Car:
	var carrier: Node3D = player.carrier if is_instance_valid(player.carrier) else null
	if carrier:
		var c: Car = carrier as Car if carrier is Car else carrier.head as Car
		return c if c.to_local(player.global_position).distance_to(c.driver_seat) < SEAT_RANGE else null
	return nearest_car()


func enter_car(car: Car) -> void:
	driving = car
	player.set_carrier(null)
	player.active = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("CollisionShape3D").set_deferred("disabled", true)
	if car.has_cab():
		car.cab_view = player.first_person
	car.set_driving(true)
	_update_help()


## Puts the player beside the car (driver side first, then passenger side, then on the roof), or in the
## aisle of a walkable vehicle.
func exit_car() -> void:
	var car := driving
	driving = null
	car.set_driving(false)
	if car.interior.size != Vector3.ZERO:
		_leave_seat(car)
		return
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	var target := car.to_global(Vector3(0.0, car.half_extents.y * 2.0 + 0.3, 0.0))
	for side: float in [1.0, -1.0]:
		var p := car.to_global(Vector3(side * (car.half_extents.x + 0.7), 0.0, 0.3))
		var g := WorldQuery.ground_y(get_world_3d(), p.x, p.z, Layers.SOLID, car.global_position.y + 2.5)
		if is_nan(g):
			continue
		q.transform = Transform3D(Basis(), Vector3(p.x, g + 1.05, p.z))
		if not space.intersect_shape(q, 1):
			target = Vector3(p.x, g + 0.1, p.z)
			break
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("CollisionShape3D").set_deferred("disabled", false)
	player.visible = true
	player.active = true
	player.wait_jump_release = true
	player.teleport(target, car.camera.global_rotation.y)
	player.camera.make_current()
	_update_help()


## From the driver seat into the aisle beside it, facing the back of the vehicle, carried by it.
func _leave_seat(car: Car) -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("CollisionShape3D").set_deferred("disabled", false)
	player.visible = true
	player.active = true
	player.wait_jump_release = true
	player.set_carrier(car)
	player.set_first_person(car.cab_view)
	player.teleport(car.to_global(car.driver_exit), car.global_rotation.y)
	player.camera.make_current()
	_update_help()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not flying:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F1:
				set_flying(not flying)
			KEY_E:
				if not flying and not driving:
					var car := car_to_enter()
					if car:
						enter_car(car)
			KEY_SPACE:
				if driving:
					exit_car()
			KEY_C:
				if not flying and not driving:
					spawn_car_near_player()
			KEY_F:
				picker.pick_and_show(get_viewport().get_camera_3d())
			KEY_H:
				_help.visible = not _help.visible
			KEY_F2:
				set_low_quality(not low_quality)
			KEY_X:
				picker.hide_overlay()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	for size: Vector2 in [Vector2(14, 2), Vector2(2, 14)]:   # crosshair
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.anchor_left = 0.5
		r.anchor_right = 0.5
		r.anchor_top = 0.5
		r.anchor_bottom = 0.5
		r.offset_left = -size.x / 2.0
		r.offset_right = size.x / 2.0
		r.offset_top = -size.y / 2.0
		r.offset_bottom = size.y / 2.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(r)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.8)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
	hud.add_child(panel)
	picker.panel = panel
	picker.label = label

	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 4)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(_help)
	_dash = Label.new()
	_dash.add_theme_font_size_override("font_size", 22)
	_dash.add_theme_color_override("font_outline_color", Color.BLACK)
	_dash.add_theme_constant_override("outline_size", 5)
	_dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dash.visible = false
	hud.add_child(_dash)
	_dash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_dash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_update_help()
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


func _update_help() -> void:
	if flying:
		_help.text = "FLY CAMERA · hold right mouse to look · WASD/ZQSD move · Q/E (A/E on AZERTY) down/up\n" + \
				"Shift faster · wheel speed · F1 land the player here · F inspect · X close · H hide help"
	elif driving:
		_help.text = "DRIVE · WASD/ZQSD: W throttle, S brake then reverse, A/D steer · Q/E (A/E on AZERTY) turn signals\n" + \
				"mouse look · wheel zoom%s · R back on wheels · %sSpace %s\nF inspect · X close · F1 fly camera · H hide help" % [
				" (all the way in: cab view)" if driving.has_cab() else "", "O doors · V cab view · " if driving.has_doors else "",
				"leave the seat" if driving.has_doors else "get out"]
	else:
		_help.text = "WALK · click to capture the mouse, Esc to free it · WASD/ZQSD move · Shift run · Space jump\n" + \
				"wheel zoom (all the way in: first person) · V first/third person · E get in the nearest car (in the bus: near the driver seat)\n" + \
				"C park a car here · F inspect · X close · F1 fly camera · H hide help"
	_help.text += "\nF2 graphics: %s" % ("low" if low_quality else "high")
