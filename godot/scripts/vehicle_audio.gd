extends Node3D
## Vehicle sounds synthesized at runtime (no audio files): an engine loop pitched by a toy automatic
## gearbox, indicator relay ticks, bus door chime with air hiss, and the air-brake sigh when a bus stops.
## Each sound is generated once per kind and cached. scripts/car.gd adds one as a child and calls
## update() every physics frame and play() for one-shots.

const RATE := 22050
## Per kind: engine fundamental (Hz, whole number so the 1 s loop is seamless), harmonic amplitudes,
## combustion noise, pitch at the top of each gear, and each gear's top speed as a share of max_speed.
const KINDS := {
	"bus": {"f0": 32, "amps": [1.0, 0.8, 0.9, 0.5, 0.45, 0.35, 0.22, 0.2, 0.12, 0.1], "sub": 0.5, "noise": 0.8,
			"pitch_top": 2.6, "gears": [0.1, 0.2, 0.33, 0.5, 0.72, 1.0], "unit_size": 11.0, "idle_db": -6.0},
	"car": {"f0": 48, "amps": [1.0, 0.6, 0.55, 0.35, 0.3, 0.18, 0.12, 0.08], "sub": 0.15, "noise": 0.45,
			"pitch_top": 3.6, "gears": [0.16, 0.3, 0.46, 0.64, 0.82, 1.0], "unit_size": 7.0, "idle_db": -9.0},
}

static var _cache := {}
static var _users := 0                      # nodes in the tree; the cache is dropped with the last one

var kind := "car"
var engine_on := false
var gear := 0                               # 0-based, shown on the HUD
var _engine: AudioStreamPlayer3D
var _fx: AudioStreamPlayer3D                # doors, air brake
var _cabin: AudioStreamPlayer               # indicator relay, heard only by the driver
var _rpm := 0.0                             # 0 idle .. 1 top of the gear
var _load := 0.0                            # smoothed throttle
var _gain := 0.0                            # engine on/off fade
var _was_moving := false


func setup(vehicle_kind: String) -> void:
	kind = vehicle_kind if KINDS.has(vehicle_kind) else "car"
	var k: Dictionary = KINDS[kind]
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = _engine_loop(kind)
	_engine.unit_size = k["unit_size"]
	_engine.max_distance = 150.0
	_engine.volume_db = -80.0
	add_child(_engine)
	_fx = AudioStreamPlayer3D.new()
	_fx.unit_size = 9.0
	_fx.max_distance = 80.0
	add_child(_fx)
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
	elif gear > 0 and v < gears[gear - 1] * max_speed * 0.55:
		gear -= 1
	var lo: float = gears[gear - 1] * max_speed * 0.5 if gear > 0 else 0.0
	var r := clampf((v - lo) / (gears[gear] * max_speed - lo), 0.0, 1.0)
	r = maxf(r, 0.3 * absf(throttle) if v < 2.0 else 0.0)  # clutch slip when pulling away
	_rpm = lerpf(_rpm, r, 1.0 - exp(-6.0 * delta))
	_load = lerpf(_load, absf(throttle), 1.0 - exp(-5.0 * delta))
	_gain = move_toward(_gain, 1.0 if engine_on else 0.0, delta / (0.4 if engine_on else 1.2))
	if _gain > 0.0 and not _engine.playing:
		_engine.play()
	elif _gain == 0.0 and _engine.playing:
		_engine.stop()
	_engine.pitch_scale = 1.0 + _rpm * (k["pitch_top"] - 1.0)
	_engine.volume_db = k["idle_db"] + 7.0 * _load + 3.0 * _rpm + linear_to_db(maxf(_gain, 0.0001))
	# buses sigh when they come to a stop
	if kind == "bus":
		if _was_moving and v < 0.3:
			play("air_brake")
		_was_moving = v > 1.5 or (_was_moving and v >= 0.3)


func play(sound: String) -> void:
	var p: Node = _cabin if sound in ["tick", "tock"] else _fx
	p.stream = _one_shot(sound)
	p.play()


static func _engine_loop(vehicle_kind: String) -> AudioStreamWAV:
	var key := "engine_" + vehicle_kind
	if _cache.has(key):
		return _cache[key]
	var k: Dictionary = KINDS[vehicle_kind]
	var f0: float = k["f0"]
	var amps: Array = k["amps"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phases: Array[float] = []
	for a in amps:
		phases.append(rng.randf() * TAU)
	var n := RATE
	var fade := RATE / 10
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var lp := 0.0
	for i in n + fade:
		var t := float(i) / RATE
		var x: float = k["sub"] * sin(TAU * f0 * 0.5 * t)
		for h in amps.size():
			x += amps[h] * sin(TAU * f0 * (h + 1) * t + phases[h])
		var pulse := pow(maxf(sin(TAU * f0 * t), 0.0), 6.0)    # firing strokes
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		x += lp * k["noise"] * (1.0 + 4.0 * pulse)
		buf[i] = x
	for i in fade:                                          # loop the noise seamlessly
		var w := float(i) / fade
		buf[i] = buf[i] * w + buf[n + i] * (1.0 - w)
	buf.resize(n)
	var s := _to_wav(buf, true)
	_cache[key] = s
	return s


static func _one_shot(sound: String) -> AudioStreamWAV:
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
		"air_brake":
			buf = _silence(0.9)
			_add_hiss(buf, 0.0, 0.85, 0.005, 1.0)
	var s := _to_wav(buf, false)
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


## 16-bit mono WAV, normalized to 0.8 of full scale.
static func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
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
