extends Node
## Sounds of Escape from Plateau (scripts/escape/escape_mode.gd makes it as Main/Mode/Audio on each player's peer),
## all synthesized at start on worker threads, one task per sound, like the vehicles' (scripts/vehicle_audio.gd): a sound
## asked for before its task is done is skipped.
## - Ambience: a cold wind and a low dread drone (two detuned A's under their tritone) whose swell follows `dread`
##   (zombies close by), and now and then, somewhere out in the fog 45-110 m away, something: a scream, a dog howling,
##   the church bell of Lozère, metal banging, glass breaking, a siren, a groan, rarely a whisper right behind.
## - Zombies: groans (a growling voice: glottal pulses through the formants of "uh" and "oh", with vocal fry), the
##   snarl of an attack, a gurgle when they die, earth crumbling as they climb out of the ground.
## - Weapons (pistol, shotgun, submachine gun, empty click, reload, pump, crowbar swing and hit), the player (grunt
##   when hurt, a heartbeat while badly hurt, a bandage torn), the rescue helicopter's rotor, the radio's squelch, a
##   stinger when a horde comes, and the end chords.
## play_at() plays one in the world, play() on the screen; the pool takes the oldest player when all are busy.

const RATE := 22050
const POOL_3D := 20
const POOL_UI := 6
const SCARES := ["scream", "howl", "bell", "metal_bang", "glass", "siren_far", "groan_far", "scream", "howl"]
const SCARE_EVERY := Vector2(9.0, 24.0)     # s between two far sounds
const WHISPER_EVERY := 120.0                # s, about
const LOOPS := ["heartbeat", "wind", "drone", "rotor"]
const SEAM := 0.08                          # s of a loop's end cross-faded into its start

static var _bank := {}                      # name -> AudioStreamWAV (under _mutex)
static var _tasks := {}                     # name -> WorkerThreadPool task
static var _mutex := Mutex.new()

var dread := 0.0                            # 0 calm .. 1 zombies all around (the drone's swell)
var ambience := true                        # wind, drone and the far sounds (off on a dedicated server)

var _p3d: Array[AudioStreamPlayer3D] = []
var _next3d := 0
var _pui: Array[AudioStreamPlayer] = []
var _nextui := 0
var _wind: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _rotor: AudioStreamPlayer3D
var _scare_t := 12.0
var _whisper_t := WHISPER_EVERY
var _rng := RandomNumberGenerator.new()
var _heart_level := 0.0


## Starts synthesizing every sound not made yet (each on its own worker thread).
static func make_bank() -> void:
	_mutex.lock()
	var todo := []
	for name: String in _recipes():
		if not _bank.has(name) and not _tasks.has(name):
			todo.append(name)
	_mutex.unlock()
	for name: String in todo:
		var id := WorkerThreadPool.add_task(_make_one.bind(name), false, "escape sound " + name)
		_mutex.lock()
		_tasks[name] = id
		_mutex.unlock()


static func _make_one(name: String) -> void:
	var s := _synth(name)
	_mutex.lock()
	_bank[name] = s
	_mutex.unlock()


## The sound `name`, or null while it is being made.
static func sound(name: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _bank.get(name)
	_mutex.unlock()
	return s


## True once every sound is made (tests).
static func bank_ready() -> bool:
	_mutex.lock()
	var n := _bank.size()
	_mutex.unlock()
	return n >= _recipes().size()


func _ready() -> void:
	make_bank()
	_rng.randomize()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 10.0
		p.max_distance = 220.0
		p.attenuation_filter_cutoff_hz = 3500.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_p3d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pui.append(p)
	_wind = AudioStreamPlayer.new()
	_wind.volume_db = -16.0
	add_child(_wind)
	_drone = AudioStreamPlayer.new()
	_drone.volume_db = -30.0
	add_child(_drone)
	_heart = AudioStreamPlayer.new()
	_heart.volume_db = -60.0
	add_child(_heart)


## Plays `name` at `pos` (global): `db` louder or softer, `pitch` times, heard to `far` m (louder ones: bigger `unit`).
func play_at(name: String, pos: Vector3, db := 0.0, pitch := 1.0, unit := 10.0, far := 220.0) -> void:
	var s := sound(name)
	if s == null or not is_inside_tree():
		return
	var p := _p3d[_next3d]
	_next3d = (_next3d + 1) % _p3d.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = far
	p.global_position = pos
	p.play()


## Plays `name` on the screen (not in the world).
func play(name: String, db := 0.0, pitch := 1.0) -> void:
	var s := sound(name)
	if s == null:
		return
	var p := _pui[_nextui]
	_nextui = (_nextui + 1) % _pui.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## The heartbeat: 0 silent .. 1 loud and fast (badly hurt).
func set_heartbeat(level: float) -> void:
	_heart_level = level


## The rescue helicopter `node`'s rotor turning (`on`), or stopped with it (a new mission's helicopter takes over).
func set_rotor(node: Node3D, on: bool) -> void:
	if is_instance_valid(_rotor) and (_rotor.get_parent() == node) == on:
		return
	if not on:
		if is_instance_valid(_rotor):
			_rotor.queue_free()
		_rotor = null
		return
	if is_instance_valid(_rotor):
		_rotor.queue_free()
	_rotor = AudioStreamPlayer3D.new()
	_rotor.unit_size = 22.0
	_rotor.max_distance = 400.0
	_rotor.volume_db = -2.0
	node.add_child(_rotor)


func _process(delta: float) -> void:
	if is_instance_valid(_rotor):
		_loop(_rotor, "rotor")
	_loop(_heart, "heartbeat")
	_heart.volume_db = linear_to_db(maxf(_heart_level, 0.001)) - 4.0
	_heart.pitch_scale = 1.0 + 0.6 * _heart_level
	if not ambience:
		return
	_loop(_wind, "wind")
	_loop(_drone, "drone")
	_drone.volume_db = lerpf(_drone.volume_db, lerpf(-24.0, -9.0, clampf(dread, 0.0, 1.0)), 1.0 - exp(-delta * 0.8))
	_scare_t -= delta
	_whisper_t -= delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _scare_t <= 0.0:
		_scare_t = _rng.randf_range(SCARE_EVERY.x, SCARE_EVERY.y)
		var name: String = SCARES[_rng.randi() % SCARES.size()]
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(45.0, 110.0)
		var p := cam.global_position + Vector3(cos(a) * d, _rng.randf_range(-2.0, 8.0), sin(a) * d)
		play_at(name, p, 4.0 if name in ["bell", "siren_far"] else 0.0, _rng.randf_range(0.9, 1.08), 40.0, 400.0)
	if _whisper_t <= 0.0:
		_whisper_t = _rng.randf_range(WHISPER_EVERY * 0.6, WHISPER_EVERY * 1.5)
		var back := cam.global_basis.z * 2.5 + cam.global_basis.x * _rng.randf_range(-1.0, 1.0)
		play_at("whisper", cam.global_position + back, -6.0, _rng.randf_range(0.9, 1.1), 2.0, 12.0)


## Keeps `player` playing the loop `name` (once it is made).
func _loop(player: Node, name: String) -> void:
	if player == null or player.playing:
		return
	var s := sound(name)
	if s != null:
		player.stream = s
		player.play()


# ---------------------------------------------------------------- synthesis

## Every sound and its length (s): the order the tasks go in.
static func _recipes() -> Dictionary:
	return {"pistol": 0.6, "shotgun": 1.0, "smg": 0.3, "empty": 0.08, "reload": 1.0, "pump": 0.5, "swing": 0.35,
			"hit_flesh": 0.35, "groan1": 1.7, "groan2": 1.4, "groan3": 2.0, "snarl": 0.8, "zombie_die": 1.1,
			"rise": 1.3, "hurt": 0.4, "heartbeat": 1.0, "bandage": 1.2, "pickup": 0.3, "click": 0.05, "wind": 6.0,
			"drone": 8.0, "scream": 2.4, "howl": 3.0, "bell": 4.5, "metal_bang": 1.6, "glass": 1.2,
			"siren_far": 5.0, "groan_far": 2.2, "whisper": 1.6, "rotor": 1.0, "radio": 0.7, "stinger": 2.8,
			"win": 3.5, "lose": 3.5}


static func _synth(name: String) -> AudioStreamWAV:
	var len: float = _recipes()[name]
	var loop := name in LOOPS
	var n := int(len * RATE)
	var b := PackedFloat32Array()
	b.resize(n + (int(SEAM * RATE) if loop else 0))     # a loop runs on past its end, for the seam
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	match name:
		"pistol":
			_crack(b, rng, 0.0, 130.0, 1.0)
			_thump(b, 0.0, 150.0, 30.0, 0.9)
			_tail(b, rng, 0.02, 0.55, 7.0, 0.35)
		"shotgun":
			_crack(b, rng, 0.0, 55.0, 1.0)
			_thump(b, 0.0, 85.0, 14.0, 1.4)
			_tail(b, rng, 0.03, 0.95, 4.5, 0.5)
		"smg":
			_crack(b, rng, 0.0, 170.0, 0.9)
			_thump(b, 0.0, 170.0, 40.0, 0.6)
			_tail(b, rng, 0.01, 0.28, 12.0, 0.25)
		"empty":
			_click(b, rng, 0.0, 3400.0, 0.8)
		"reload":
			_click(b, rng, 0.05, 1800.0, 1.0)
			_click(b, rng, 0.09, 2400.0, 0.6)
			_click(b, rng, 0.55, 2900.0, 0.9)
			_click(b, rng, 0.72, 2100.0, 1.0)
		"pump":
			_click(b, rng, 0.02, 1300.0, 1.0)
			_tail(b, rng, 0.02, 0.12, 30.0, 0.4)
			_click(b, rng, 0.24, 1600.0, 1.0)
		"swing":
			var bp := [0.0, 0.0, 0.0, 0.0]
			var c := PackedFloat64Array()
			for i in b.size():
				var t := float(i) / RATE
				if i % 64 == 0:
					c = _bandpass(400.0 + 1300.0 * sin(PI * t / len), 1.5)
				b[i] = _bp_step(c, bp, rng.randf_range(-1.0, 1.0)) * sin(PI * t / len)
		"hit_flesh":
			_thump(b, 0.0, 80.0, 25.0, 1.2)
			_tail(b, rng, 0.0, 0.25, 18.0, 0.7)
			_voice(b, rng, 0.03, 0.2, 70.0, 50.0, [400.0, 800.0, 2000.0], 0.5, 0.6)
		"groan1":
			_voice(b, rng, 0.0, len, 92.0, 70.0, [520.0, 880.0, 2350.0], 0.55, 1.0)
		"groan2":
			_voice(b, rng, 0.0, len, 118.0, 88.0, [450.0, 780.0, 2300.0], 0.7, 1.0)
		"groan3":
			_voice(b, rng, 0.0, len, 80.0, 105.0, [600.0, 1000.0, 2450.0], 0.45, 1.0)
		"groan_far":
			_voice(b, rng, 0.0, 1.6, 100.0, 75.0, [520.0, 880.0, 2350.0], 0.55, 1.0)
			_far(b, 0.12)
		"snarl":
			_voice(b, rng, 0.0, len, 150.0, 210.0, [760.0, 1250.0, 2600.0], 0.9, 1.0)
		"zombie_die":
			_voice(b, rng, 0.0, len, 120.0, 50.0, [480.0, 820.0, 2300.0], 1.0, 1.0)
			for i in b.size():                      # gurgling: the voice chopped by bubbles
				b[i] *= 0.4 + 0.6 * absf(sin(TAU * (9.0 + 6.0 * sin(float(i) / RATE * 7.0)) * float(i) / RATE))
		"rise":
			var lp := 0.0
			for i in b.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
				var crackle := 1.0 if rng.randf() < 0.004 else 0.0
				b[i] = (lp * 3.0 + crackle * rng.randf_range(-1.0, 1.0)) * minf(t / 0.2, 1.0) * (1.0 - t / len)
			_voice(b, rng, 0.4, 0.85, 85.0, 70.0, [500.0, 850.0, 2300.0], 0.6, 0.5)
		"hurt":
			_voice(b, rng, 0.0, len, 150.0, 120.0, [650.0, 1100.0, 2500.0], 0.3, 1.0)
		"heartbeat":
			_thump(b, 0.0, 55.0, 18.0, 1.0)
			_thump(b, 0.27, 50.0, 22.0, 0.7)
		"bandage":
			var lp := 0.0
			for i in b.size():
				var t := float(i) / RATE
				var x := rng.randf_range(-1.0, 1.0)
				lp += (x - lp) * 0.5
				var rip := 0.0 if rng.randf() > 0.15 else 1.0
				var env := minf(t / 0.05, 1.0) * (1.0 - smoothstep(0.7, len, t)) * (0.6 + 0.4 * sin(TAU * 3.0 * t))
				b[i] = (x - lp) * rip * env
		"pickup":
			_tone(b, 0.0, 0.12, 880.0, 0.5)
			_tone(b, 0.1, 0.18, 1320.0, 0.45)
		"click":
			_click(b, rng, 0.0, 2600.0, 1.0)
		"wind":
			var lp1 := 0.0
			var lp2 := 0.0
			var bp := [0.0, 0.0, 0.0, 0.0]
			var c := PackedFloat64Array()
			for i in b.size():
				var t := float(i) / RATE
				var x := rng.randf_range(-1.0, 1.0)
				lp1 += (x - lp1) * 0.025
				lp2 += (x - lp2) * 0.004
				if i % 64 == 0:
					c = _bandpass(520.0 + 240.0 * sin(TAU * t / len * 2.0), 6.0)
				var y := _bp_step(c, bp, x)
				var gust := 0.55 + 0.45 * sin(TAU * t / len) * sin(TAU * t / len * 3.0 + 1.0)
				b[i] = (lp1 * 4.0 + lp2 * 8.0) * gust + y * 0.25 * gust * gust
		"drone":
			var lp := 0.0
			for i in b.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.01
				var swell := 0.7 + 0.3 * sin(TAU * t / len)
				b[i] = (sin(TAU * 55.0 * t) + 0.8 * sin(TAU * 55.375 * t) + 0.35 * sin(TAU * 77.75 * t) * swell
						+ 0.18 * sin(TAU * 110.125 * t) + 0.1 * sin(TAU * 155.5 * t) * (1.0 - swell) + lp * 2.0) * swell
		"scream":
			_scream(b, rng, len)
			_far(b, 0.14)
		"howl":
			var ph := 0.0
			for i in b.size():
				var t := float(i) / RATE
				var f := 470.0 + 230.0 * sin(PI * minf(t / 2.4, 1.0)) - 60.0 * t + 8.0 * sin(TAU * 5.5 * t)
				ph += f / RATE
				var env := minf(t / 0.3, 1.0) * (1.0 - smoothstep(2.2, len, t))
				b[i] = (sin(TAU * ph) + 0.25 * sin(TAU * ph * 2.0) + 0.08 * sin(TAU * ph * 3.0)) * env
			_far(b, 0.18)
		"bell":
			for p: Vector3 in [Vector3(0.5, 0.7, 0.8), Vector3(1.0, 1.0, 1.4), Vector3(1.19, 0.6, 2.2),
					Vector3(1.5, 0.45, 2.6), Vector3(2.0, 0.5, 3.2), Vector3(2.52, 0.25, 4.5), Vector3(3.0, 0.2, 5.5)]:
				for i in b.size():
					var t := float(i) / RATE
					b[i] += sin(TAU * 196.0 * p.x * t) * p.y * exp(-t * p.z * 0.45) * minf(t / 0.004, 1.0)
			_far(b, 0.2)
		"metal_bang":
			_thump(b, 0.0, 90.0, 20.0, 1.0)
			for p: Vector2 in [Vector2(310.0, 0.5), Vector2(870.0, 0.35), Vector2(1490.0, 0.25), Vector2(2310.0, 0.15)]:
				for i in b.size():
					var t := float(i) / RATE
					b[i] += sin(TAU * p.x * t) * p.y * exp(-t * (4.0 + p.x / 500.0))
			_far(b, 0.16)
		"glass":
			for k in 26:
				var t0 := rng.randf_range(0.0, 0.35)
				var f := rng.randf_range(2800.0, 7500.0)
				var i0 := int(t0 * RATE)
				for j in int(0.25 * RATE):
					if i0 + j >= b.size():
						break
					var t := float(j) / RATE
					b[i0 + j] += sin(TAU * f * t) * exp(-t * rng.randf_range(15.0, 40.0)) * 0.3
			_tail(b, rng, 0.0, 0.5, 9.0, 0.6)
			_far(b, 0.1)
		"siren_far":
			var ph := 0.0
			for i in b.size():
				var t := float(i) / RATE
				var f := 650.0 + 450.0 * (0.5 - 0.5 * cos(TAU * t / 2.5))
				ph += f / RATE
				var env := minf(t / 0.5, 1.0) * (1.0 - smoothstep(4.2, len, t))
				b[i] = (sin(TAU * ph) + 0.3 * sin(TAU * ph * 2.0)) * env
			_far(b, 0.25)
		"whisper":
			var lp := 0.0
			var bp := [0.0, 0.0, 0.0, 0.0]
			var c := _bandpass(3200.0, 1.2)
			for i in b.size():
				var t := float(i) / RATE
				lp += (_bp_step(c, bp, rng.randf_range(-1.0, 1.0)) - lp) * 0.6
				var syll := pow(maxf(sin(TAU * (5.5 + 1.5 * sin(t * 3.0)) * t), 0.0), 2.0)
				b[i] = lp * syll * minf(t / 0.1, 1.0) * (1.0 - smoothstep(1.2, len, t))
		"rotor":
			var lp := 0.0
			for i in b.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
				var blade := pow(0.5 + 0.5 * cos(TAU * 11.0 * t), 12.0)      # 11 blade passes a second
				b[i] = lp * 3.0 * (0.25 + blade) + sin(TAU * 11.0 * t) * blade * 0.6 \
						+ sin(TAU * 1370.0 * t + 0.3 * sin(TAU * 2.0 * t)) * 0.06
		"radio":
			var lp := 0.0
			for i in b.size():
				var t := float(i) / RATE
				var x := rng.randf_range(-1.0, 1.0)
				lp += (x - lp) * 0.4
				b[i] = (x - lp) * 0.5 * (1.0 - smoothstep(0.0, 0.35, t)) + sin(TAU * 1050.0 * t) * 0.3 \
						* (1.0 if t > 0.38 and t < 0.55 else 0.0)
		"stinger":
			for f: float in [110.0, 116.5, 155.6, 164.8, 233.1]:
				for i in b.size():
					var t := float(i) / RATE
					var env := pow(minf(t / 0.9, 1.0), 2.0) * exp(-maxf(t - 0.9, 0.0) * 1.6)
					b[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * 0.4
			_tail(b, rng, 0.85, 1.6, 2.5, 0.5)
		"win", "lose":
			var chord := [261.6, 329.6, 392.0, 523.3] if name == "win" else [110.0, 130.8, 164.8, 103.8]
			for k in chord.size():
				var f: float = chord[k]
				for i in b.size():
					var t := float(i) / RATE - k * 0.12
					if t < 0.0:
						continue
					var env := minf(t / 0.4, 1.0) * (1.0 - smoothstep(2.0, len - 0.1, t))
					b[i] += (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t + 0.4)) * env * 0.35
	if loop:
		_seam(b, n)
	return _to_wav(b, loop)


## A gun's report: a burst of noise falling off at `decay` /s.
static func _crack(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, decay: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(0.12 * RATE):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		b[i0 + j] += rng.randf_range(-1.0, 1.0) * exp(-t * decay) * gain


## A low knock sliding down from `f` Hz.
static func _thump(b: PackedFloat32Array, start: float, f: float, decay: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(0.4 * RATE):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		b[i0 + j] += sin(TAU * (f - f * 0.6 * t) * t) * exp(-t * decay) * gain


## The echo of a shot off the buildings: low-passed noise dying away at `decay` /s.
static func _tail(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, decay: float,
		gain: float) -> void:
	var lp := 0.0
	var i0 := int(start * RATE)
	for j in int(length * RATE):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
		b[i0 + j] += lp * 2.5 * exp(-t * decay) * minf(t / 0.01, 1.0) * gain


## A dry mechanical click ringing at `f` Hz.
static func _click(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, f: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(0.05 * RATE):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		b[i0 + j] += (sin(TAU * f * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 180.0) * gain


static func _tone(b: PackedFloat32Array, start: float, length: float, f: float, gain: float) -> void:
	var i0 := int(start * RATE)
	for j in int(length * RATE):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		b[i0 + j] += sin(TAU * f * t) * minf(t / 0.005, 1.0) * exp(-t * 14.0) * gain


## A voice from `start`, `length` s: glottal pulses gliding from `f0` to `f1` Hz (jittered, with vocal fry `rasp`
## 0..1), shaped by three formants, and an aspiration noise.
static func _voice(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, f0: float, f1: float,
		formants: Array, rasp: float, gain: float) -> void:
	var c1 := _bandpass(formants[0], 5.0)
	var c2 := _bandpass(formants[1], 6.0)
	var c3 := _bandpass(formants[2], 8.0)
	var s1 := [0.0, 0.0, 0.0, 0.0]
	var s2 := [0.0, 0.0, 0.0, 0.0]
	var s3 := [0.0, 0.0, 0.0, 0.0]
	var ph := 0.0
	var fry := 1.0
	var i0 := int(start * RATE)
	var n := int(length * RATE)
	for j in n:
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		var u := t / length
		var f := lerpf(f0, f1, u) * (1.0 + 0.04 * sin(TAU * 4.5 * t) + rng.randf_range(-0.03, 0.03))
		ph += f / RATE
		if ph >= 1.0:
			ph -= 1.0
			fry = 1.0 - rasp * rng.randf() * 0.9           # every pulse a little weaker or stronger: a rattle
		var src := (1.0 - 2.0 * ph) * fry + rng.randf_range(-1.0, 1.0) * 0.25 * (0.3 + rasp)
		var y1 := _bp_step(c1, s1, src)
		var y2 := _bp_step(c2, s2, src)
		var y3 := _bp_step(c3, s3, src)
		var env := minf(u / 0.15, 1.0) * (1.0 - smoothstep(0.7, 1.0, u))
		b[i0 + j] += (y1 * 1.0 + y2 * 0.6 + y3 * 0.25) * env * gain * 3.0


## A woman screaming: a high voice with a wide vibrato rising then breaking down.
static func _scream(b: PackedFloat32Array, rng: RandomNumberGenerator, length: float) -> void:
	var c1 := _bandpass(1000.0, 4.0)
	var c2 := _bandpass(1450.0, 5.0)
	var c3 := _bandpass(2900.0, 6.0)
	var s1 := [0.0, 0.0, 0.0, 0.0]
	var s2 := [0.0, 0.0, 0.0, 0.0]
	var s3 := [0.0, 0.0, 0.0, 0.0]
	var ph := 0.0
	for i in mini(b.size(), int(1.9 * RATE)):
		var t := float(i) / RATE
		var f := (820.0 + 300.0 * sin(PI * minf(t / 1.2, 1.0)) - 250.0 * maxf(t - 1.2, 0.0)) \
				* (1.0 + 0.05 * sin(TAU * 6.5 * t))
		ph = fmod(ph + f / RATE, 1.0)
		var src := (1.0 - 2.0 * ph) + rng.randf_range(-1.0, 1.0) * 0.4
		var env := minf(t / 0.08, 1.0) * (1.0 - smoothstep(1.4, 1.9, t))
		b[i] += (_bp_step(c1, s1, src) + 0.8 * _bp_step(c2, s2, src) + 0.4 * _bp_step(c3, s3, src)) * env * 3.0


## Far away: low-passed (`k`: the filter's share per sample) and echoing off the buildings.
static func _far(b: PackedFloat32Array, k: float) -> void:
	var lp := 0.0
	for i in b.size():
		lp += (b[i] - lp) * k
		b[i] = lp
	var dry := b.duplicate()
	for e: Vector2 in [Vector2(0.11, 0.4), Vector2(0.23, 0.28), Vector2(0.37, 0.18), Vector2(0.55, 0.1)]:
		var d := int(e.x * RATE)
		for i in range(d, b.size()):
			b[i] += dry[i - d] * e.y


## RBJ band-pass (0 dB peak) at `f` Hz: b0, a1, a2 (a0 = 1, b1 = 0, b2 = -b0).
static func _bandpass(f: float, q: float) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var a := sin(w) / (2.0 * q)
	var a0 := 1.0 + a
	return PackedFloat64Array([a / a0, -2.0 * cos(w) / a0, (1.0 - a) / a0])


## One sample through band-pass `c`, its state `s` = [x1, x2, y1, y2].
static func _bp_step(c: PackedFloat64Array, s: Array, x: float) -> float:
	var y: float = c[0] * x - c[0] * s[1] - c[1] * s[2] - c[2] * s[3]
	s[1] = s[0]
	s[0] = x
	s[3] = s[2]
	s[2] = y
	return y


## A loop `n` samples long: what was made past its end cross-faded into its start, so it loops without a click.
static func _seam(b: PackedFloat32Array, n: int) -> void:
	var fade := b.size() - n
	for j in fade:
		var a := float(j) / fade
		b[j] = b[j] * a + b[n + j] * (1.0 - a)
	b.resize(n)


## 16-bit mono WAV, normalized to 0.8 of full scale.
static func _to_wav(b: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for x in b:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = b.size()
	return s
