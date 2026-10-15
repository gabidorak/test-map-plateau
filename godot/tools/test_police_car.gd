extends SceneTree
## Headless checks for the police car (scripts/police_car.gd, Car.SPECS "police-hatchback", built by
## blender/vehicles/build_car.py; its driving, lamps, cab view and passenger seat are checked with the other realistic
## cars by tools/test_real_cars.gd): the vehicle menu parks it with its livery, light bar and grille flashers, the bar
## outside the collision box; B sounds the siren and flashes the blue lights, three flashes a side in turn, never both
## sides at once; B again switches them off. The siren is the French police two-tone: la 435 Hz and ré 580 Hz, 50 to 60
## cycles a minute, each note with at least two harmonics between 1 and 4 kHz louder than its fundamental (the 1987
## rules). A remote copy takes the switch from the LAN state.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_police_car.gd
## Without --headless (add --disable-vsync) it also saves shots to /tmp/police_car_*.png.

const Car = preload("res://scripts/car.gd")
const PoliceCar = preload("res://scripts/police_car.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")

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
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/" + file)
	print("saved /tmp/", file)


## Looks at the car from `eye` (car frame) towards `at` with a free camera, for a shot.
func _look(car: VehicleBody3D, eye: Vector3, at: Vector3, file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.global_position = car.to_global(eye)
	cam.look_at(car.to_global(at))
	cam.make_current()
	await _shot(file)
	cam.queue_free()


func _run() -> void:
	await _frames(60)
	_siren_sound()
	var player: CharacterBody3D = _main.player
	_check(Car.MODELS.has("police-hatchback") and _main._menu_buttons.has_node("police-hatchback"),
			"the vehicle menu has the police car")
	var car: VehicleBody3D = _main.spawn_car_near_player("police-hatchback")
	_check(car is PoliceCar and car.find_children("*", "VehicleWheel3D", true, false).size() == 4
			and car.audio.siren_tone == "police", "it parks as a PoliceCar with four wheels and the police siren")
	if not car is PoliceCar:
		_finish()
		return
	var mats := {}
	var body := car.find_child("body", true, false) as MeshInstance3D
	for k in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(k)
		if m:
			mats[m.resource_name] = true
	_check(["paint_silver", "livery_blue", "livery_red", "livery_white", "livery_navy", "reflector"].all(
			func(n: String) -> bool: return mats.has(n)), "its body wears the grey paint and the livery")
	var bar := car.find_child("lightbar", true, false) as MeshInstance3D
	var beacons: Array = car._beacons["left"] + car._beacons["right"]
	_check(bar != null and beacons.size() == 4 and beacons.all(func(b: Variant) -> bool: return b is MeshInstance3D),
			"it has its light bar, the bar's two lenses and the two grille flashers")
	var shape := car.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	var box_top: float = shape.position.y + (shape.shape as BoxShape3D).size.y * 0.5
	var bar_top: float = (car._in_car(bar) * bar.get_aabb()).end.y
	_check(bar_top > box_top + 0.02, "the light bar is left out of the collision box (bar %.2f m, box %.2f m)" % [bar_top, box_top])
	await _frames(60)
	await _look(car, Vector3(3.2, 1.5, 4.6), Vector3(0.0, 0.6, 0.3), "police_car_front.png")
	await _look(car, Vector3(-3.0, 1.7, -4.8), Vector3(0.0, 0.7, -0.3), "police_car_rear.png")
	await _look(car, Vector3(-5.0, 1.1, 0.0), Vector3(0.0, 0.7, 0.0), "police_car_right.png")

	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	await process_frame
	_check(_main.driving == car, "E from the left side takes the wheel")
	_tap(KEY_B)
	await _frames(3)
	var lit := [0, 0]                           # rising edges per side
	var both := false
	var was := [false, false]
	var seconds := 0.0
	for i in 72:                                # 1.2 s: two flash cycles
		await process_frame
		seconds += car.get_process_delta_time()
		var now := [car._beacon_lights[0].visible, car._beacon_lights[1].visible]
		both = both or (now[0] and now[1])
		for k in 2:
			if now[k] and not was[k]:
				lit[k] += 1
		was = now
	var cycles := seconds / PoliceCar.FLASH
	_check(car.siren and car.audio.siren and car.audio._siren != null and car.audio._siren.playing
			and car.audio._siren.stream == VehicleAudio._siren_loop("police") and "SIREN" in _main._dash.text,
			"B sounds the police siren (SIREN on the dashboard)")
	_check(lit[0] >= roundi(cycles * 3.0) - 2 and lit[1] >= roundi(cycles * 3.0) - 2 and not both,
			"the blue lights flash three times a side in turn (%d and %d flashes in %.1f cycles), never both sides" % [lit[0],
			lit[1], cycles])
	var glowing := false
	while not glowing:
		await process_frame
		glowing = car._beacon_lights[0].visible
	_check(car._beacons["left"].all(func(b: MeshInstance3D) -> bool: return b.material_override == car._lit_beacon)
			and car._beacons["right"].all(func(b: MeshInstance3D) -> bool: return b.material_override == null),
			"a lit side's lenses glow, the other side's are dark")
	await _shot("police_car_lights_cab.png")
	_main.exit_car()
	await _frames(5)
	await _look(car, Vector3(3.2, 1.5, 4.6), Vector3(0.0, 0.6, 0.3), "police_car_lights.png")
	_check(car.siren, "the siren keeps going with the driver out")
	player.teleport(car.to_global(Vector3(car.half_extents.x + 1.0, 0.3, 0.0)))
	await _frames(5)
	_tap(KEY_E)
	await _frames(2)
	_tap(KEY_B)
	await _frames(3)
	_check(not car.siren and not car.audio._siren.playing and not car._beacon_lights[0].visible
			and not car._beacon_lights[1].visible and car._beacons["left"][0].material_override == null,
			"B again switches the siren and the lights off")
	_main.exit_car()
	await _frames(5)

	# LAN: a remote copy flashes and sounds from the state
	car.siren = true
	var s: Array = car.net_state()
	car.siren = false
	var copy: VehicleBody3D = _main.add_net_car("police-hatchback", car.global_transform.translated_local(Vector3(-6.0, 0.0, 0.0)))
	copy.set_remote(true)
	s[0] = copy.global_transform
	copy.apply_net_state(s, s, 1.0)
	var flashed := false
	for i in 40:
		await process_frame
		flashed = flashed or copy._beacon_lights[0].visible or copy._beacon_lights[1].visible
	_check(copy.siren and copy.audio.siren and flashed, "a remote copy takes the siren from the LAN state and flashes")
	s[4] = s[4] & ~PoliceCar.FLAGS_SIREN
	copy.apply_net_state(s, s, 1.0)
	await _frames(3)
	_check(not copy.siren and not copy.audio._siren.playing, "and stops with it")
	_main.cars.erase(copy)
	copy.queue_free()
	_main.cars.erase(car)
	car.queue_free()
	await _frames(5)
	_finish()


## The police siren's loop: its notes, cadence and timbre.
func _siren_sound() -> void:
	var wav: AudioStreamWAV = VehicleAudio._siren_loop("police")
	var rate := float(wav.mix_rate)
	var x := PackedFloat32Array()
	x.resize(wav.data.size() / 2)
	for i in x.size():
		x[i] = wav.data.decode_s16(i * 2) / 32768.0
	_check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == x.size(), "the siren loops")
	# which note sounds, every 10 ms: the stronger harmonic series
	var notes: Array[int] = []
	var win := int(0.04 * rate)
	for i in range(0, x.size() - win, int(0.01 * rate)):
		var la := 0.0
		var re := 0.0
		for h in range(1, 6):
			la += _level(x, i, win, 435.0 * h, rate)
			re += _level(x, i, win, 580.0 * h, rate)
		notes.append(435 if la > re else 580)
	var la_share := notes.count(435) / float(notes.size())
	var per_minute := 60.0 / (x.size() / rate)
	var switches := 0
	for i in range(1, notes.size()):
		if notes[i] != notes[i - 1]:
			switches += 1
	_check(switches <= 2 and absf(la_share - 0.5) < 0.05 and per_minute >= 50.0 and per_minute <= 60.0,
			"one loop is one cycle of la then ré, half each, %.1f cycles a minute" % per_minute)
	# each note in its steady part: the fundamental where it should be, the harmonics between 1 and 4 kHz
	for note: Array in [[435.0, 0.15], [580.0, 0.7]]:
		var f0: float = note[0]
		var start := int(float(note[1]) * rate)
		var n := int(0.3 * rate)
		var fund := _level(x, start, n, f0, rate)
		var off := maxf(_level(x, start, n, f0 * 0.97, rate), _level(x, start, n, f0 * 1.03, rate))
		var louder := 0
		for h in range(2, 10):
			if f0 * h >= 1000.0 and f0 * h <= 4000.0 and _level(x, start, n, f0 * h, rate) > fund:
				louder += 1
		_check(fund > 5.0 * off and louder >= 2,
				"the %d Hz note: its fundamental is there, %d harmonics between 1 and 4 kHz are louder" % [f0, louder])


## Amplitude of `x` at `f` Hz over n samples from `start` (Goertzel, Hann window).
func _level(x: PackedFloat32Array, start: int, n: int, f: float, rate: float) -> float:
	var w := TAU * f / rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var s0 := x[start + i] * (0.5 - 0.5 * cos(TAU * i / n)) + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) / n


func _finish() -> void:
	if _failures.is_empty():
		print("ALL POLICE CAR CHECKS PASSED")
	else:
		print("%d FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
