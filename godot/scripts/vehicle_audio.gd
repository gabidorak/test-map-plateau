extends Node3D
## Vehicle sounds synthesized at runtime (no audio files): an engine modelled from its firing pulses, revved by a toy
## automatic gearbox, with tyre roar; a two-tone horn held as long as `horn` is on, indicator relay ticks, bus door chime with air hiss, the bus's RATP
## stop-request gong (ring()), and the air-brake sigh when a bus stops; also the
## knocks of scripts/breakables.gd (a sign pole's clang, a sapling's swish, a broken hydrant's gush), the armed
## biplane's gunshots and their pings on vehicles (scripts/plane_guns.gd), the boom of a vehicle breaking down, the
## two-tone sirens of the fire truck (scripts/fire_truck.gd) and the police car (scripts/police_car.gd), sounding as
## long as `siren` is on, the electric car's motor whine and pedestrian warning hum, and the horse's hoofbeats, neigh,
## snort and landing thud (scripts/horse.gd).
## Each sound is generated once per kind and cached. scripts/car.gd adds one as a child and calls
## update() every physics frame and play() for one-shots.

const RATE := 22050
## Per kind: each gear's top speed as a share of max_speed, the engine speed at the top of a gear (pitch_top, times
## idle), loudness (engine at idle, tyres at max_speed), horn, and the engine model of _engine_take(): cylinders,
## firing frequency at idle (Hz), engine speeds recorded from idle to pitch_top (layers), loudness off the throttle,
## then [on, off the throttle] pairs: combustion pulse sharpness (Hz), combustion noise, valve clatter, intake roar;
## exhaust resonances [Hz, Q, gain], exhaust pipe [delay s, feedback], clatter and intake pitch (Hz), turbo whine
## [Hz at idle, gain], uneven cylinders, propeller beat (two blades) and saturation.
const KINDS := {
	# city bus: rear 6-cylinder diesel, ~660 rpm at idle, rattling, with a turbo's whistle
	"bus": {"pitch_top": 3.0, "gears": [0.1, 0.2, 0.33, 0.5, 0.72, 1.0], "unit_size": 11.0, "idle_db": -1.0,
			"road_db": -2.0, "road_pitch": 0.8, "horn": [277, 349], "horn_harmonics": 14,
			"engine": {"cyl": 6, "idle_hz": 33.0, "layers": 5, "off": 0.4, "pulse": [1600.0, 1000.0],
				"burst": [0.12, 0.1], "clatter": [3.4, 4.0], "intake": [0.6, 0.1],
				"formants": [[75.0, 1.0, 3.0], [190.0, 1.8, 1.5], [430.0, 2.5, 0.6], [950.0, 2.0, 0.25]],
				"pipe": [0.0065, 0.45], "clatter_hz": 2100.0, "intake_hz": 550.0, "turbo": [2300.0, 0.026],
				"rough": 0.08, "prop": 0.0, "drive": 1.6}},
	# car: 4-cylinder petrol, ~840 rpm at idle, muffled exhaust, intake roar when pushed
	"car": {"pitch_top": 3.8, "gears": [0.16, 0.3, 0.46, 0.64, 0.82, 1.0], "unit_size": 7.0, "idle_db": -5.0,
			"road_db": -1.0, "road_pitch": 1.0, "horn": [415, 523], "horn_harmonics": 9,
			"engine": {"cyl": 4, "idle_hz": 28.0, "layers": 6, "off": 0.35, "pulse": [1900.0, 700.0],
				"burst": [0.15, 0.05], "clatter": [0.55, 0.5], "intake": [0.85, 0.08],
				"formants": [[110.0, 1.2, 3.0], [260.0, 2.0, 1.5], [540.0, 3.0, 0.6], [1300.0, 2.0, 0.2]],
				"pipe": [0.0042, 0.45], "clatter_hz": 2900.0, "intake_hz": 750.0, "turbo": [0.0, 0.0],
				"rough": 0.12, "prop": 0.0, "drive": 1.5}},
	# electric car (the Renault Zoe): single-speed, the motor's whine is held to the wheels' speed (_motor_take()), from
	# a hum moving off to ~1.4 kHz at top speed, and a pedestrian warning hum ("avas": Hz at rest, fades out between
	# the two speeds in km/h, _avas_loop()); silent when stopped
	"electric": {"pitch_top": 24.0, "gears": [1.0], "unit_size": 6.0, "idle_db": -4.0,
			"road_db": -1.0, "road_pitch": 1.0, "horn": [415, 523], "horn_harmonics": 9, "avas": [196.0, 20.0, 30.0],
			"engine": {"motor": true, "idle_hz": 60.0, "layers": 8, "off": 0.45,
				# whine harmonics [order, gain]; reduction gear mesh [order, gain on, gain off]; air and bearing hiss
				"orders": [[1.0, 1.0], [2.0, 0.3], [3.0, 0.22], [6.0, 0.1]], "gear": [2.72, 0.3, 0.4],
				"hiss": [2600.0, 0.6]}},
	# fire truck (scripts/fire_truck.gd): big V8 diesel, burbling (uneven banks), deep air horn
	"truck": {"pitch_top": 2.8, "gears": [0.08, 0.16, 0.26, 0.38, 0.52, 0.7, 1.0], "unit_size": 12.0, "idle_db": 0.0,
			"road_db": -1.0, "road_pitch": 0.7, "horn": [185, 233], "horn_harmonics": 16,
			"engine": {"cyl": 8, "idle_hz": 40.0, "layers": 5, "off": 0.4, "pulse": [1400.0, 900.0],
				"burst": [0.13, 0.1], "clatter": [3.8, 4.4], "intake": [0.7, 0.1],
				"formants": [[65.0, 1.0, 3.0], [160.0, 1.6, 1.6], [380.0, 2.5, 0.6], [850.0, 2.0, 0.25]],
				"pipe": [0.008, 0.5], "clatter_hz": 1800.0, "intake_hz": 480.0, "turbo": [1900.0, 0.026],
				"rough": 0.2, "prop": 0.0, "drive": 1.7}},
	# biplane (scripts/plane.gd): one "gear", the engine speed follows the throttle lever; 9-cylinder radial with short
	# open stacks (popping, rough) and a two-blade propeller
	"plane": {"pitch_top": 4.0, "gears": [1.0], "unit_size": 16.0, "idle_db": -3.0,
			"road_db": 0.0, "road_pitch": 0.0, "horn": [523, 659], "horn_harmonics": 6,
			"engine": {"cyl": 9, "idle_hz": 36.0, "layers": 5, "off": 0.45, "pulse": [2400.0, 1400.0],
				"burst": [0.19, 0.13], "clatter": [1.2, 1.2], "intake": [0.66, 0.1],
				"formants": [[150.0, 1.5, 2.5], [400.0, 2.0, 1.4], [900.0, 2.0, 0.6], [2000.0, 2.0, 0.25]],
				"pipe": [0.0018, 0.35], "clatter_hz": 2600.0, "intake_hz": 900.0, "turbo": [0.0, 0.0],
				"rough": 0.25, "prop": 0.35, "drive": 1.8}},
}
const SHIFT_LIFT := 0.3                     # s the throttle eases off while the gearbox shifts up
const HEARD := 160.0                        # m: farther from the camera, the engine and tyres are stopped

static var _cache := {}
static var _users := 0                      # nodes in the tree; the cache is dropped with the last one
static var _tasks := {}                     # kind -> WorkerThreadPool task synthesizing its engine (~0.3 s)
static var _made := {}                      # kind -> its engine takes, handed over by the task (under _mutex)
static var _mutex := Mutex.new()

var kind := "car"
var engine_on := false
var gear := 0                               # 0-based, shown on the HUD
var horn := false                           # sounds while on (fades in and out in update())
var siren := false                          # likewise (the fire truck's, the police car's)
var siren_tone := "fire"                    # "fire": the fire brigade's la-si, "police": the police's la-ré
var _layers: Array[AudioStreamSynchronized] = []   # per recorded engine speed: its on and off the throttle loops
var _engines: Array[AudioStreamPlayer3D] = []      # two: layer i plays on _engines[i % 2], so neighbours cross-fade
var _road: AudioStreamPlayer3D              # tyre roar (none for the plane)
var _horn: AudioStreamPlayer3D
var _horn_gain := 0.0
var _siren: AudioStreamPlayer3D             # made when first switched on
var _avas: AudioStreamPlayer3D              # the electric car's pedestrian warning hum
var _avas_gain := 0.0
var _fx: AudioStreamPlayer3D                # doors, air brake
var _bell: AudioStreamPlayer3D              # own player: a gong neither cuts nor is cut by the doors
var _cabin: AudioStreamPlayer               # indicator relay, heard only by the driver
var _rpm := 0.0                             # 0 idle .. 1 top of the gear
var _load := 0.0                            # smoothed throttle
var _gain := 0.0                            # engine on/off fade
var _shift := 0.0                           # s left of the throttle lift of an upshift
var _was_moving := false


func setup(vehicle_kind: String) -> void:
	kind = vehicle_kind if KINDS.has(vehicle_kind) else "car"
	var k: Dictionary = KINDS[kind]
	_take_layers()
	for i in 2:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = k["unit_size"]
		p.max_distance = 150.0
		add_child(p)
		_engines.append(p)
	if k["road_db"] != 0.0:
		_road = AudioStreamPlayer3D.new()
		_road.stream = _road_loop()
		_road.unit_size = k["unit_size"] * 0.7
		_road.max_distance = 90.0
		add_child(_road)
	_horn = AudioStreamPlayer3D.new()
	_horn.stream = _horn_loop(kind)
	_horn.unit_size = k["unit_size"] * 2.0
	_horn.max_distance = 250.0
	_horn.volume_db = -80.0
	add_child(_horn)
	if k.has("avas"):
		_avas = AudioStreamPlayer3D.new()
		_avas.stream = _avas_loop(kind)
		_avas.unit_size = k["unit_size"]
		_avas.max_distance = 60.0
		add_child(_avas)
	_fx = AudioStreamPlayer3D.new()
	_fx.unit_size = 9.0
	_fx.max_distance = 80.0
	add_child(_fx)
	_bell = AudioStreamPlayer3D.new()
	_bell.unit_size = 10.0
	_bell.max_distance = 120.0
	_bell.max_polyphony = 4                 # quick taps ring over each other
	add_child(_bell)
	_cabin = AudioStreamPlayer.new()
	_cabin.volume_db = -8.0
	add_child(_cabin)


func _enter_tree() -> void:
	_users += 1


func _exit_tree() -> void:
	_users -= 1
	if _users == 0:
		_cache.clear()


## Called every physics frame. `speed` m/s (signed), `throttle` -1..1 (pedal, not engine force).
func update(speed: float, throttle: float, max_speed: float, delta: float) -> void:
	var k: Dictionary = KINDS[kind]
	var gears: Array = k["gears"]
	var v := absf(speed)
	if v > gears[gear] * max_speed * 0.97 and gear < gears.size() - 1:
		gear += 1
		_shift = SHIFT_LIFT
	elif gear > 0 and v < gears[gear - 1] * max_speed * 0.55:
		gear -= 1
	_shift = maxf(_shift - delta, 0.0)
	var lo: float = gears[gear - 1] * max_speed * 0.5 if gear > 0 else 0.0
	var r := clampf((v - lo) / (gears[gear] * max_speed - lo), 0.0, 1.0)
	if not k["engine"].has("motor"):
		r = maxf(r, 0.3 * absf(throttle) if v < 2.0 else 0.0)  # clutch slip when pulling away
	_rpm = lerpf(_rpm, r, 1.0 - exp(-6.0 * delta))
	var pull := absf(throttle) if throttle * speed >= 0.0 or v < 1.0 else 0.0   # braking is no load
	_load = lerpf(_load, pull * (0.2 if _shift > 0.0 else 1.0), 1.0 - exp(-8.0 * delta))
	_gain = move_toward(_gain, 1.0 if engine_on else 0.0, delta / (0.4 if engine_on else 1.2))
	var cam := get_viewport().get_camera_3d()
	var heard := cam != null and cam.global_position.distance_squared_to(global_position) < HEARD * HEARD
	_update_engine(k, heard)
	if _avas:
		var a: Array = k["avas"]
		var kmh := v * 3.6
		var moving := engine_on and (v > 0.2 or absf(throttle) > 0.05)
		_avas_gain = move_toward(_avas_gain, 1.0 if moving else 0.0, delta / 0.5)
		var level := _avas_gain * clampf((a[2] - kmh) / (a[2] - a[1]), 0.0, 1.0)
		if level > 0.0 and heard and not _avas.playing:
			_avas.play()
		elif (level == 0.0 or not heard) and _avas.playing:
			_avas.stop()
		_avas.volume_db = -10.0 + linear_to_db(maxf(level, 0.0001))
		_avas.pitch_scale = 1.0 + 0.5 * minf(kmh / a[2], 1.0)
	if _road:
		var share := clampf(v / maxf(max_speed, 1.0), 0.0, 1.0)
		if v > 0.6 and heard and not _road.playing:
			_road.play()
		elif (v < 0.3 or not heard) and _road.playing:
			_road.stop()
		_road.volume_db = k["road_db"] + 20.0 * log(maxf(share, 0.01)) / log(10.0)
		_road.pitch_scale = k["road_pitch"] * (0.75 + 0.5 * share)
	_horn_gain = move_toward(_horn_gain, 1.0 if horn else 0.0, delta / (0.02 if horn else 0.06))
	if _horn_gain > 0.0 and not _horn.playing:
		_horn.play()
	elif _horn_gain == 0.0 and _horn.playing:
		_horn.stop()
	_horn.volume_db = linear_to_db(maxf(_horn_gain, 0.0001))
	if siren and _siren == null:
		_siren = AudioStreamPlayer3D.new()
		_siren.stream = _siren_loop(siren_tone)
		_siren.unit_size = 25.0
		_siren.max_distance = 400.0
		add_child(_siren)
	if _siren and siren != _siren.playing:
		if siren:
			_siren.play()
		else:
			_siren.stop()
	# buses and trucks sigh when they come to a stop
	if kind in ["bus", "truck"]:
		if _was_moving and v < 0.3:
			play("air_brake")
		_was_moving = v > 1.5 or (_was_moving and v >= 0.3)


## Picks up the engine's layers once synthesized (on a worker thread, started by the first vehicle of the kind);
## until then the engine is silent.
func _take_layers() -> void:
	var takes: Array = _cache.get("engine_" + kind, [])
	if takes.is_empty():
		if not _tasks.has(kind):
			_tasks[kind] = WorkerThreadPool.add_task(_make_engine.bind(kind), false, "engine sound")
			return
		if not WorkerThreadPool.is_task_completed(_tasks[kind]):
			return
		WorkerThreadPool.wait_for_task_completion(_tasks[kind])
		_tasks.erase(kind)
		_mutex.lock()
		takes = _made[kind]
		_made.erase(kind)
		_mutex.unlock()
		_cache["engine_" + kind] = takes
	for take: Array in takes:
		var s := AudioStreamSynchronized.new()  # own copy: the on/off volumes live on the stream
		s.stream_count = 2
		s.set_sync_stream(0, take[0])
		s.set_sync_stream(1, take[1])
		_layers.append(s)


static func _make_engine(vehicle_kind: String) -> void:
	var takes := _engine_takes(vehicle_kind)
	_mutex.lock()
	_made[vehicle_kind] = takes
	_mutex.unlock()


## Engine speed `_rpm` between two recorded layers: both play, pitched to it (never more than a layer's step away, so
## the exhaust resonances stay put) and cross-faded at equal power; within each, on and off the throttle cross-fade by
## `_load`. A layer whose share is nil is stopped, which frees its player for the next layer of the same parity; out
## of earshot (not `heard`) both are, saving the mixing of far bot traffic.
func _update_engine(k: Dictionary, heard: bool) -> void:
	if _layers.is_empty():
		_take_layers()
		return
	var top: float = k["pitch_top"]
	var ratio := 1.0 + _rpm * (top - 1.0)
	var n := _layers.size()
	var pos := clampf(log(ratio) / log(top) * (n - 1), 0.0, n - 1.0)
	var i := mini(int(pos), n - 2)
	var frac := pos - i
	# an engine roars a little louder revved; an electric motor's whine fades in from nothing at rest
	var rev := linear_to_db(0.06 + _rpm) if k["engine"].has("motor") else 3.0 * _rpm
	var base: float = k["idle_db"] + rev + linear_to_db(maxf(_gain, 0.0001))
	for layer in [i, i + 1]:
		var p := _engines[layer % 2]
		var share := cos(frac * PI * 0.5) if layer == i else sin(frac * PI * 0.5)
		if share < 0.03 or _gain == 0.0 or not heard:
			if p.playing:
				p.stop()
			continue
		var s := _layers[layer]
		s.set_sync_stream_volume(0, linear_to_db(maxf(sqrt(_load), 0.0001)))
		s.set_sync_stream_volume(1, linear_to_db(maxf(sqrt(1.0 - _load), 0.0001)))
		p.pitch_scale = ratio / layer_ratio(kind, layer)
		p.volume_db = base + linear_to_db(share)
		if p.stream != s:
			p.stream = s
			p.play()
		elif not p.playing:
			p.play()


func play(sound: String) -> void:
	var p: Node = _cabin if sound in ["tick", "tock"] else _fx
	p.stream = one_shot(sound)
	p.play()


## One RATP stop-request gong (ding-dong).
func ring() -> void:
	_bell.stream = one_shot("bell")         # made on first use: most vehicles never ring
	_bell.play()


## Engine speed of recorded layer `i`, times idle.
static func layer_ratio(vehicle_kind: String, i: int) -> float:
	var k: Dictionary = KINDS[vehicle_kind]
	return pow(k["pitch_top"], float(i) / (k["engine"]["layers"] - 1))


## The engine recorded at each layer's speed: [on the throttle, off the throttle] loops from idle to pitch_top, scaled
## together so their loudness keeps the model's. Thread-safe (touches no shared state).
static func _engine_takes(vehicle_kind: String) -> Array:
	var e: Dictionary = KINDS[vehicle_kind]["engine"]
	var bufs := []
	var peak := 0.0001
	for li in int(e["layers"]):
		var f: float = e["idle_hz"] * layer_ratio(vehicle_kind, li)
		var share: float = li / (e["layers"] - 1.0)
		var pair := [_motor_take(e, f, 0, share), _motor_take(e, f, 1, share)] if e.has("motor") \
				else [_engine_take(e, f, 0), _engine_take(e, f, 1)]
		for b: PackedFloat32Array in pair:
			for x in b:
				peak = maxf(peak, absf(x))
		bufs.append(pair)
	var takes := []
	for pair: Array in bufs:
		takes.append([_to_wav(pair[0], true, peak), _to_wav(pair[1], true, peak)])
	return takes


## One engine loop at firing frequency `f` (Hz), on (`off` 0) or off (1) the throttle: a whole number of engine cycles,
## so it loops seamlessly. Every firing is a sharp pulse with a burst of combustion noise, rung through the exhaust's
## resonances and pipe, which keep their pitch whatever the engine speed (a single loop pitched up drags them along:
## rubbery); plus the valve train's clatter, the intake roar, a turbo's whine and a propeller's beat. Each cylinder
## fires a little stronger or weaker than the others, and every firing a little differently. Both loops of a layer
## share the timing of every firing (same seed), so they cross-fade in step. The filters ring in over the end of the
## loop before it is kept.
static func _engine_take(e: Dictionary, f: float, off: int) -> PackedFloat32Array:
	var cyl: int = e["cyl"]
	var cycles := maxi(1, roundi(f / cyl))      # ~1 s
	var pulses := cycles * cyl
	var period := roundi(pulses / f * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cyl_amp: Array[float] = []
	for c in cyl:
		cyl_amp.append(1.0 + e["rough"] * rng.randf_range(-1.0, 1.0))
	var amp: float = 1.0 if off == 0 else e["off"]
	var imp := PackedFloat32Array()
	imp.resize(period)
	var spacing := float(period) / pulses
	for p in pulses:
		imp[roundi((p + rng.randf_range(-0.03, 0.03)) * spacing) % period] += \
				amp * cyl_amp[p % cyl] * rng.randf_range(0.9, 1.1)
	var noise := PackedFloat32Array()
	noise.resize(period)
	for i in period:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var lp := _lowpass(e["pulse"][off])
	var fm: Array = e["formants"]               # four, unrolled below (GDScript loops are slow)
	var fa := _bandpass(fm[0][0], fm[0][1])
	var fb := _bandpass(fm[1][0], fm[1][1])
	var fcc := _bandpass(fm[2][0], fm[2][1])
	var fd := _bandpass(fm[3][0], fm[3][1])
	var ga: float = fm[0][2]
	var gb: float = fm[1][2]
	var gc: float = fm[2][2]
	var gd: float = fm[3][2]
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var d1 := 0.0
	var d2 := 0.0
	var e1 := 0.0
	var e2 := 0.0
	var cl := _bandpass(e["clatter_hz"], 2.5)
	var it := _bandpass(e["intake_hz"], 1.0)
	var burst: float = e["burst"][off]
	var clatter: float = e["clatter"][off]
	var intake: float = e["intake"][off]
	var pipe_d := roundi(e["pipe"][0] * RATE)
	var pipe_fb: float = e["pipe"][1]
	var pipe := PackedFloat32Array()
	pipe.resize(period * 2)
	var turbo_cycles := roundi(e["turbo"][0] * sqrt(f / e["idle_hz"]) * period / RATE)   # whole cycles per loop
	var turbo: float = e["turbo"][1] * (1.0 if off == 0 else 0.3)
	var prop: float = e["prop"]
	var blades := cycles * 4                    # two blades, two turns per engine cycle
	var drive: float = e["drive"]
	var out := PackedFloat32Array()
	out.resize(period)
	var l1 := 0.0
	var l2 := 0.0
	var benv := 0.0
	var cenv := 0.0
	var slow := 0.0
	var nlp := 0.0
	var plp := 0.0
	var c1 := 0.0
	var c2 := 0.0
	var i1 := 0.0
	var i2 := 0.0
	var dcx := 0.0
	var dcy := 0.0
	var bdec := exp(-1.0 / (0.0025 * RATE))
	var cdec := exp(-1.0 / (0.0012 * RATE))
	var start := maxi(period - roundi(0.2 * RATE), 0)
	for i in range(start, period * 2):
		var j := i % period
		var x := imp[j]
		var ps := lp[0] * x + l1                # pulse, shaped (2-pole low-pass)
		l1 = lp[1] * x - lp[3] * ps + l2
		l2 = lp[2] * x - lp[4] * ps
		benv = benv * bdec + x
		cenv = cenv * cdec + x
		slow += (benv - slow) * 0.003
		var nz := noise[j]
		nlp += (nz - nlp) * 0.15
		var exc := ps + (nz - nlp) * benv * burst
		var ya := fa[0] * exc + a1              # the exhaust's resonances (band-passes, transposed form II)
		a1 = -fa[1] * ya + a2
		a2 = -fa[0] * exc - fa[2] * ya
		var yb := fb[0] * exc + b1
		b1 = -fb[1] * yb + b2
		b2 = -fb[0] * exc - fb[2] * yb
		var yc := fcc[0] * exc + d1
		d1 = -fcc[1] * yc + d2
		d2 = -fcc[0] * exc - fcc[2] * yc
		var yd := fd[0] * exc + e1
		e1 = -fd[1] * yd + e2
		e2 = -fd[0] * exc - fd[2] * yd
		# the exhaust leads; the other gains are relative to it
		var y := (exc * 0.1 + ya * ga + yb * gb + yc * gc + yd * gd) * 20.0
		plp += ((pipe[i - pipe_d] if i - pipe_d >= start else 0.0) - plp) * 0.5
		y += pipe_fb * plp
		pipe[i] = y
		var cx := noise[(j + 7919) % period] * cenv
		var cy := cl[0] * cx + c1
		c1 = -cl[1] * cy + c2
		c2 = -cl[0] * cx - cl[2] * cy
		var ix := noise[(j + 15401) % period] * (0.4 + slow)
		var iy := it[0] * ix + i1
		i1 = -it[1] * iy + i2
		i2 = -it[0] * ix - it[2] * iy
		var s := y + cy * clatter + iy * intake
		if turbo > 0.0:
			s += turbo * sin(TAU * turbo_cycles * j / period)
		if prop > 0.0:
			var beat := 0.5 + 0.5 * cos(TAU * blades * j / period)
			s *= 1.0 - prop + prop * 2.0 * beat
			s += noise[(j + 3301) % period] * beat * beat * prop * 0.15
		s = tanh(drive * s)
		dcy = s - dcx + 0.995 * dcy             # DC blocker
		dcx = s
		if i >= period:
			out[j] = dcy
	return out


## One electric motor loop with its whine's fundamental at `f` (Hz), on (`off` 0) or off (1) the throttle (coasting,
## regenerating), `share` of the way from rest to top speed: the whine's orders, one beating a hertz above the
## fundamental, roughened by the torque ripple; the reduction gear's mesh whine, louder coasting (the teeth's slack);
## air and bearing hiss growing with the speed. Whole-number frequencies over a 1 s loop: seamless. Orders that would
## alias once pitched up to the next layer are left out.
static func _motor_take(e: Dictionary, f: float, off: int, share: float) -> PackedFloat32Array:
	var period := RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var amp: float = 1.0 if off == 0 else e["off"]
	var partials: Array[Vector3] = []           # Hz (whole), amplitude, phase
	for o: Array in e["orders"]:
		if f * o[0] * 1.7 < RATE * 0.45:
			partials.append(Vector3(roundi(f * o[0]), o[1] * amp, rng.randf() * TAU))
	partials.append(Vector3(roundi(f) + 1, 0.25 * amp, 0.0))
	var g: Array = e["gear"]
	var gear := Vector3(roundi(f * g[0]), g[1 + off], 0.0)
	var ripple := maxi(1, roundi(f / 8.0))      # Hz, whole
	var depth := 0.15 if off == 0 else 0.08
	var noise := PackedFloat32Array()
	noise.resize(period)
	for i in period:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var hb := _bandpass(e["hiss"][0], 0.8)
	var hiss: float = e["hiss"][1] * (0.15 + share) * (1.0 if off == 0 else 0.7)
	var h1 := 0.0
	var h2 := 0.0
	var out := PackedFloat32Array()
	out.resize(period)
	var start := period - roundi(0.2 * RATE)
	for i in range(start, period * 2):
		var j := i % period
		var nz := noise[j]
		var h := hb[0] * nz + h1                # band-passed hiss, rung in over the loop's end
		h1 = -hb[1] * h + h2
		h2 = -hb[0] * nz - hb[2] * h
		if i < period:
			continue
		var t := float(j) / RATE
		var w := 0.0
		for p in partials:
			w += sin(TAU * p.x * t + p.z) * p.y
		w *= 1.0 + depth * sin(TAU * ripple * t)
		if gear.x * 1.7 < RATE * 0.45:
			w += sin(TAU * gear.x * t) * gear.y
		out[j] = tanh(0.8 * (w + h * hiss))
	return out


## The Zoe's pedestrian warning hum: a soft chord on `avas`' note (root beating a hertz above, fifth, octave), its
## upper partials swelling three times a second. Whole-number frequencies: the 1 s loop is seamless.
static func _avas_loop(vehicle_kind: String) -> AudioStreamWAV:
	var key := "avas_" + vehicle_kind
	if _cache.has(key):
		return _cache[key]
	var b := roundi(KINDS[vehicle_kind]["avas"][0])
	var buf := _silence(1.0)
	for i in buf.size():
		var t := float(i) / RATE
		var swell := 0.75 + 0.25 * sin(TAU * 3.0 * t)
		buf[i] = tanh(sin(TAU * b * t) + 0.5 * sin(TAU * (b + 1) * t + 1.0) + 0.45 * sin(TAU * roundi(b * 1.5) * t + 2.0)
				+ swell * (0.3 * sin(TAU * b * 2 * t + 0.5) + 0.12 * sin(TAU * b * 3 * t + 1.5)
				+ 0.1 * sin(TAU * b * 4 * t + 2.5)))
	var s := _to_wav(buf, true)
	_cache[key] = s
	return s


## RBJ low-pass (Q 0.707) at `f` Hz: b0, b1, b2, a1, a2 (a0 = 1).
static func _lowpass(f: float) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var a := sin(w) / sqrt(2.0)
	var a0 := 1.0 + a
	var c := cos(w)
	return PackedFloat64Array([(1.0 - c) * 0.5 / a0, (1.0 - c) / a0, (1.0 - c) * 0.5 / a0, -2.0 * c / a0, (1.0 - a) / a0])


## RBJ band-pass (0 dB peak) at `f` Hz: b0, a1, a2 (a0 = 1, b1 = 0, b2 = -b0).
static func _bandpass(f: float, q: float) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var a := sin(w) / (2.0 * q)
	var a0 := 1.0 + a
	return PackedFloat64Array([a / a0, -2.0 * cos(w) / a0, (1.0 - a) / a0])


## Tyre roar on the road: broadband hiss peaking around 700 Hz over a low rumble of the road texture. 2 s loop, its end
## cross-faded into its start; pitched and turned up with the speed.
static func _road_loop() -> AudioStreamWAV:
	if _cache.has("road"):
		return _cache["road"]
	var fade := int(0.05 * RATE)
	var buf := _silence(2.0)
	buf.resize(buf.size() + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var hiss := _bandpass(700.0, 0.7)
	var sizzle := _bandpass(1900.0, 1.2)
	var h1 := 0.0
	var h2 := 0.0
	var z1 := 0.0
	var z2 := 0.0
	var rumble := 0.0
	var rumble2 := 0.0
	for i in buf.size():
		var x := rng.randf_range(-1.0, 1.0)
		var h := hiss[0] * x + h1
		h1 = -hiss[1] * h + h2
		h2 = -hiss[0] * x - hiss[2] * h
		var z := sizzle[0] * x + z1
		z1 = -sizzle[1] * z + z2
		z2 = -sizzle[0] * x - sizzle[2] * z
		rumble += (x - rumble) * 0.02
		rumble2 += (rumble - rumble2) * 0.02
		var t := float(i) / RATE
		buf[i] = (h + 0.35 * z) * (0.9 + 0.1 * sin(TAU * 1.5 * t)) + rumble2 * 6.0
	var n := buf.size() - fade
	for j in fade:
		var a := float(j) / fade
		buf[j] = buf[j] * a + buf[n + j] * (1.0 - a)
	buf.resize(n)
	var s := _to_wav(buf, true)
	_cache["road"] = s
	return s


## Two horns a third apart, buzzy (bright harmonics, soft-clipped), their flares ringing around 2.4 kHz (brassy), with
## a little flutter. Whole-number frequencies: the 1 s loop is seamless.
static func _horn_loop(vehicle_kind: String) -> AudioStreamWAV:
	var key := "horn_" + vehicle_kind
	if _cache.has(key):
		return _cache[key]
	var k: Dictionary = KINDS[vehicle_kind]
	var partials: Array[Vector2] = []           # Hz, amplitude
	for f: int in k["horn"]:
		for h in range(1, int(k["horn_harmonics"]) + 1):
			partials.append(Vector2(f * h, (1.0 + 2.0 * exp(-pow((f * h - 2400.0) / 900.0, 2.0))) / pow(h, 0.8)))
	var buf := _silence(1.0)
	for i in buf.size():
		var t := float(i) / RATE
		var x := 0.0
		for j in partials.size():
			x += sin(TAU * partials[j].x * t + j) * partials[j].y
		x *= 1.0 + 0.04 * sin(TAU * 9.0 * t)
		buf[i] = tanh(x * 0.6)
	var s := _to_wav(buf, true)
	_cache[key] = s
	return s


## French two-tone sirens (arrêtés of 30 October, 2 and 3 November 1987): two notes, each with harmonics between 1 and
## 4 kHz louder than its fundamental, as the rules ask; per tone (vehicle's `siren_tone`): the notes (Hz), cycles a
## minute, the source's even harmonics against its odd ones, the horn (_horn_response: throat cut-off Hz, bell rings
## [Hz, width, gain], roll-off Hz), the glide between the notes (s) and the soft clipping.
const SIRENS := {
	# fire brigade: la-si, 25 to 30 cycles a minute; compressor horns, a buzzing reed (every harmonic) in brassy trumpets
	"fire": {"notes": [435.0, 488.0], "per_minute": 27.5, "even": 0.7, "throat": 600.0,
			"rings": [[1300.0, 450.0, 1.2], [2400.0, 700.0, 1.6]], "top": 5000.0, "glide": 0.012, "drive": 1.6},
	# police: la-ré, 50 to 60 cycles a minute; an electronic siren's square wave (odd harmonics, a little of the even
	# ones) through a horn loudspeaker
	"police": {"notes": [435.0, 580.0], "per_minute": 55.0, "even": 0.15, "throat": 800.0,
			"rings": [[1500.0, 450.0, 1.2], [2900.0, 600.0, 0.8]], "top": 4500.0, "glide": 0.004, "drive": 1.3},
}


## The two-tone siren `tone` (SIRENS): its source through its horn, pushed into soft clipping, the notes switching with
## a short glide. One period of each note is tabulated, the two tables cross-fading with the glide. The loop is one
## cycle, its notes nudged (under 0.1 %) to a whole number of periods so that it is seamless.
static func _siren_loop(tone: String) -> AudioStreamWAV:
	if _cache.has("siren_" + tone):
		return _cache["siren_" + tone]
	const TABLE := 2048
	var k: Dictionary = SIRENS[tone]
	var notes: Array = k["notes"]
	var tables: Array[PackedFloat32Array] = []
	for f: float in notes:
		var t := PackedFloat32Array()
		t.resize(TABLE + 1)
		for h in range(1, int(7000.0 / f) + 1):
			var a := _horn_response(f * h, k) * (1.0 if h % 2 == 1 else float(k["even"])) / h
			for i in TABLE:
				t[i] += a * sin(TAU * h * i / TABLE)
		var peak := 0.0
		for i in TABLE:
			peak = maxf(peak, absf(t[i]))
		for i in TABLE:
			t[i] /= peak
		t[TABLE] = t[0]
		tables.append(t)
	var n := roundi(RATE * 60.0 / float(k["per_minute"]))
	var glide := 1.0 - exp(-1.0 / (float(k["glide"]) * RATE))
	var drive: float = k["drive"]
	var scale := 1.0
	var buf := PackedFloat32Array()
	buf.resize(n)
	for pass_ in 2:                             # the first only measures the phase the loop ends on
		var f: float = notes[1] * scale         # the loop starts as the second note gives way to the first
		var phase := 0.0
		for i in n:
			f += ((notes[0] if i * 2 < n else notes[1]) * scale - f) * glide
			if pass_ == 1:
				var x := fmod(phase, 1.0) * TABLE
				var j := int(x)
				var w := clampf((f / scale - notes[0]) / (notes[1] - notes[0]), 0.0, 1.0)
				buf[i] = tanh(drive * lerpf(lerpf(tables[0][j], tables[0][j + 1], x - j),
						lerpf(tables[1][j], tables[1][j + 1], x - j), w))
			phase += f / RATE
		scale = roundf(phase) / phase
	var s := _to_wav(buf, true)
	_cache["siren_" + tone] = s
	return s


## Gain of the siren `k`'s horn at f Hz: its throat cuts the low notes (fourth order), its bell rings, the driver rolls
## off.
static func _horn_response(f: float, k: Dictionary) -> float:
	var hp := pow(f / float(k["throat"]), 4.0)
	var bell := 1.0
	for r: Array in k["rings"]:
		bell += r[2] * exp(-pow((f - r[0]) / r[1], 2.0))
	return hp / (1.0 + hp) * bell / (1.0 + pow(f / float(k["top"]), 4.0))


static func one_shot(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var buf := PackedFloat32Array()
	match sound:
		"tick", "tock":
			var f := 2600.0 if sound == "tick" else 1900.0
			buf = _silence(0.05)
			var rng := RandomNumberGenerator.new()
			for i in buf.size():
				var t := float(i) / RATE
				buf[i] = (sin(TAU * f * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * exp(-t * 160.0)
		"door_open":
			buf = _silence(1.1)
			_add_hiss(buf, 0.0, 0.8, 0.02, 0.9)
			_add_thump(buf, 0.75, 0.8)
		"door_close":
			buf = _silence(1.6)
			for b in 3:                                     # closing chime
				_add_tone(buf, 0.22 * b, 0.13, 1150.0, 0.45)
			_add_hiss(buf, 0.7, 0.6, 0.02, 0.7)
			_add_thump(buf, 1.3, 1.0)
		"bell":                                             # RATP stop-request gong: soft electronic ding-dong
			buf = _silence(2.4)
			for n: Vector2 in [Vector2(0.0, 659.3), Vector2(0.38, 523.3)]:   # mi then do, a falling major third
				var i0 := int(n.x * RATE)
				var f := n.y
				for j in buf.size() - i0:
					var t := float(j) / RATE
					var x := sin(TAU * f * t) + 0.18 * sin(TAU * 2.0 * f * t) * exp(-t * 3.0) \
							+ 0.06 * sin(TAU * 3.0 * f * t) * exp(-t * 6.0)      # mellow: overtones fade first
					buf[i0 + j] += x * minf(t / 0.006, 1.0) * exp(-t * 2.2) * 0.6
			for i in buf.size():                            # gentle vibrato of the chime speaker
				buf[i] *= 1.0 + 0.05 * sin(TAU * 5.0 * float(i) / RATE)
		"air_brake":
			buf = _silence(0.9)
			_add_hiss(buf, 0.0, 0.85, 0.005, 1.0)
		"clang":                                            # metal pole knocked over: thump, crack, ringing
			buf = _silence(1.0)
			_add_thump(buf, 0.0, 1.0)
			_add_hiss(buf, 0.0, 0.08, 0.001, 0.9)
			for p: Vector2 in [Vector2(430.0, 0.5), Vector2(1170.0, 0.35), Vector2(2050.0, 0.25), Vector2(3130.0, 0.15)]:
				_add_ring(buf, 0.005, 0.95, p.x, p.y, 6.0 + p.x / 400.0)
		"swish":                                            # sapling pushed over: leaves and twigs
			buf = _silence(0.7)
			_add_hiss(buf, 0.0, 0.65, 0.04, 0.8)
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			for c in 14:                                    # twig snaps
				var i0 := int(rng.randf_range(0.0, 0.3) * RATE)
				for j in int(0.004 * RATE):
					buf[i0 + j] += rng.randf_range(-1.0, 1.0) * exp(-float(j) / RATE * 900.0) * 0.8
		"gunshot":                                          # one round of a machine gun: crack, muzzle thump
			buf = _silence(0.2)
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			for i in buf.size():
				var t := float(i) / RATE
				buf[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 140.0) * 0.9
			_add_hiss(buf, 0.0, 0.12, 0.0005, 1.2)
			_add_thump(buf, 0.0, 1.1)
		"bullet_hit":                                       # a round on a vehicle's body: a tinny ping
			buf = _silence(0.35)
			_add_hiss(buf, 0.0, 0.03, 0.0005, 0.7)
			for p: Vector2 in [Vector2(1870.0, 0.5), Vector2(3150.0, 0.35), Vector2(4730.0, 0.2)]:
				_add_ring(buf, 0.002, 0.33, p.x, p.y, 14.0 + p.x / 200.0)
		"boom":                                             # a vehicle breaking down: a dull bang and a rumble
			buf = _silence(2.2)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var lp1 := 0.0
			var lp2 := 0.0
			for i in buf.size():
				var t := float(i) / RATE
				var noise := rng.randf_range(-1.0, 1.0)
				lp1 += (noise - lp1) * 0.04
				lp2 += (noise - lp2) * 0.5
				buf[i] = lp1 * 5.0 * exp(-t * 2.0) + lp2 * 0.6 * exp(-t * 8.0) \
						+ sin(TAU * (60.0 - 12.0 * t) * t) * exp(-t * 4.0) * 0.9
		"hoof":                                             # a hoof on the road: hollow clop
			buf = _silence(0.14)
			var rng := RandomNumberGenerator.new()
			rng.seed = 13
			for i in buf.size():
				var t := float(i) / RATE
				buf[i] = rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t * 300.0) + sin(TAU * 480.0 * t) * exp(-t * 55.0) * 0.8 \
						+ sin(TAU * 1150.0 * t) * exp(-t * 80.0) * 0.45 + sin(TAU * 150.0 * t) * exp(-t * 40.0) * 0.5
		"neigh":                                            # whinny: a nasal cry rising, then trilling down
			buf = _silence(1.5)
			var rng := RandomNumberGenerator.new()
			rng.seed = 17
			var phase := 0.0
			var lp1 := 0.0
			var lp2 := 0.0
			for i in buf.size():
				var t := float(i) / RATE
				var base := lerpf(600.0, 1150.0, t / 0.15) if t < 0.15 else lerpf(1150.0, 420.0, pow((t - 0.15) / 1.2, 0.8))
				var trill := 0.02 + 0.1 * smoothstep(0.1, 0.5, t) * (1.0 - smoothstep(1.0, 1.35, t))
				phase += base * (1.0 + trill * sin(TAU * 11.0 * t)) / RATE
				var x := 0.0
				for h in range(1, 7):
					x += sin(TAU * phase * h) / pow(h, 1.2)
				var noise := rng.randf_range(-1.0, 1.0)
				lp1 += (noise - lp1) * 0.5
				lp2 += (noise - lp2) * 0.05
				var env := minf(t / 0.04, 1.0) * (1.0 - smoothstep(1.05, 1.35, t))
				buf[i] = (tanh(x * 0.9) + (lp1 - lp2) * 0.25) * env
			_add_hiss(buf, 1.3, 0.2, 0.01, 0.6)             # and a breath out
		"snort":                                            # air blown through the nostrils, lips fluttering
			buf = _silence(0.5)
			var rng := RandomNumberGenerator.new()
			rng.seed = 19
			var lp1 := 0.0
			var lp2 := 0.0
			for i in buf.size():
				var t := float(i) / RATE
				var noise := rng.randf_range(-1.0, 1.0)
				lp1 += (noise - lp1) * 0.15
				lp2 += (noise - lp2) * 0.01
				var env := minf(t / 0.02, 1.0) * pow(1.0 - t / 0.5, 2.0)
				buf[i] = (lp1 - lp2) * env * (0.7 + 0.3 * sin(TAU * 32.0 * t))
		"land":                                             # a horse landing a jump: thud and two clops
			buf = _silence(0.4)
			_add_thump(buf, 0.0, 1.2)
			for c: float in [0.0, 0.07]:
				for j in int(0.1 * RATE):
					var t := float(j) / RATE
					buf[int(c * RATE) + j] += sin(TAU * 480.0 * t) * exp(-t * 55.0) * 0.6
		"gush":                                             # broken hydrant: steady roar of water (loops)
			buf = _silence(2.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var lp1 := 0.0
			var lp2 := 0.0
			var rumble := 0.0
			for i in buf.size():
				var noise := rng.randf_range(-1.0, 1.0)
				lp1 += (noise - lp1) * 0.35
				lp2 += (noise - lp2) * 0.04
				rumble += (noise - rumble) * 0.01
				var t := float(i) / RATE
				buf[i] = (lp1 - lp2) * (0.8 + 0.2 * sin(TAU * 3.0 * t)) + rumble * 3.0
			var fade := int(0.05 * RATE)            # seamless loop: cross-fade the end into the start
			for j in fade:
				var a := float(j) / fade
				buf[j] = buf[j] * a + buf[buf.size() - fade + j] * (1.0 - a)
			buf.resize(buf.size() - fade)
	var s := _to_wav(buf, sound == "gush")
	_cache[sound] = s
	return s


static func _silence(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Band-passed noise starting at `start` s, `length` s long, `attack` s fade-in, then a slow decay.
static func _add_hiss(buf: PackedFloat32Array, start: float, length: float, attack: float, gain: float) -> void:
	var rng := RandomNumberGenerator.new()
	var lp1 := 0.0
	var lp2 := 0.0
	var i0 := int(start * RATE)
	for j in int(length * RATE):
		if i0 + j >= buf.size():
			break
		var t := float(j) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 += (noise - lp1) * 0.6
		lp2 += (noise - lp2) * 0.08
		var env := minf(t / attack, 1.0) * pow(1.0 - t / length, 1.5)
		buf[i0 + j] += (lp1 - lp2) * env * gain


static func _add_thump(buf: PackedFloat32Array, start: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(0.18 * RATE):
		if i0 + j >= buf.size():
			break
		var t := float(j) / RATE
		buf[i0 + j] += sin(TAU * (95.0 - 120.0 * t) * t) * exp(-t * 28.0) * gain


static func _add_tone(buf: PackedFloat32Array, start: float, length: float, f: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(length * RATE):
		if i0 + j >= buf.size():
			break
		var t := float(j) / RATE
		var env := minf(t / 0.005, 1.0) * minf((length - t) / 0.01, 1.0)
		buf[i0 + j] += (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)) * env * gain


## Decaying sine from `start` s: one partial of a struck metal part.
static func _add_ring(buf: PackedFloat32Array, start: float, length: float, f: float, gain: float, decay: float) -> void:
	var i0 := int(start * RATE)
	for j in int(length * RATE):
		if i0 + j >= buf.size():
			break
		var t := float(j) / RATE
		buf[i0 + j] += sin(TAU * f * t) * exp(-t * decay) * gain


## 16-bit mono WAV, normalized to 0.8 of full scale (its `peak` there, if given).
static func _to_wav(buf: PackedFloat32Array, loop: bool, peak := 0.0) -> AudioStreamWAV:
	if peak == 0.0:
		peak = 0.0001
		for x in buf:
			peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = buf.size()
	return s
