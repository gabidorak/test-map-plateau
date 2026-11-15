extends Node
## The items' sounds (Main/Items/Audio): synthesized once, on worker threads at the game's start (make_bank), like
## Escape from Plateau's (scripts/escape/escape_audio.gd): no sound file to ship. A few players are pooled for the
## sounds in the world (play_at) and on the screen (play); the taser's crackle loops on the person tased (people_fx.gd).
## - "taser_shot": the darts' snap; "crackle": the current through them (a loop); "net_shot": the net gun's thump of
##   air; "net_land": a net falling; "reload": a cartridge pushed in; "empty": a dry click.

const RATE := 22050
const POOL_3D := 6
const POOL_UI := 3

static var _bank := {}
static var _tasks := {}
static var _mutex := Mutex.new()

var _p3d: Array[AudioStreamPlayer3D] = []
var _pui: Array[AudioStreamPlayer] = []
var _next3d := 0
var _nextui := 0


## Starts synthesizing every sound not made yet (each on its own worker thread).
static func make_bank() -> void:
	_mutex.lock()
	var todo := []
	for name: String in ["taser_shot", "crackle", "net_shot", "net_land", "reload", "empty"]:
		if not _bank.has(name) and not _tasks.has(name):
			todo.append(name)
	_mutex.unlock()
	for name: String in todo:
		var id := WorkerThreadPool.add_task(_make_one.bind(name), false, "items sound " + name)
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


func _ready() -> void:
	make_bank()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 120.0
		add_child(p)
		_p3d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pui.append(p)


## Plays `name` at `pos` (global), `db` louder or softer, `pitch` times.
func play_at(name: String, pos: Vector3, db := 0.0, pitch := 1.0) -> void:
	var s := sound(name)
	if s == null or not is_inside_tree():
		return
	var p := _p3d[_next3d]
	_next3d = (_next3d + 1) % _p3d.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


## Plays `name` on the screen (the player's own weapon).
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


# ---------------------------------------------------------------- synthesis

static func _synth(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var out := PackedFloat32Array()
	var loop := false
	match name:
		"taser_shot":
			out.resize(int(RATE * 0.32))
			for i in out.size():
				var t := float(i) / RATE
				var snap := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) + sin(TAU * 3100.0 * t) * exp(-t * 60.0) * 0.5
				out[i] = snap * 0.9 + _crackle_at(rng, t) * clampf((t - 0.02) * 20.0, 0.0, 1.0) * exp(-t * 6.0) * 0.6
		"crackle":
			out.resize(int(RATE * 0.8))
			for i in out.size():
				out[i] = _crackle_at(rng, float(i) / RATE) * 0.7
			loop = true
		"net_shot":
			out.resize(int(RATE * 0.45))
			var low := 0.0
			for i in out.size():
				var t := float(i) / RATE
				var f := lerpf(110.0, 45.0, minf(t / 0.18, 1.0))
				var thump := sin(TAU * f * t) * exp(-t * 14.0)
				low += (rng.randf_range(-1.0, 1.0) - low) * 0.12          # air rushing out, muffled
				out[i] = thump * 0.9 + low * exp(-t * 7.0) * 1.4
		"net_land":
			out.resize(int(RATE * 0.35))
			var low := 0.0
			for i in out.size():
				var t := float(i) / RATE
				low += (rng.randf_range(-1.0, 1.0) - low) * 0.25
				out[i] = low * sin(PI * t / 0.35) * 0.8
		"reload":
			out.resize(int(RATE * 0.36))
			for i in out.size():
				var t := float(i) / RATE
				out[i] = _click(t, 2300.0) * 0.7 + _click(t - 0.2, 3300.0) * 0.8 + rng.randf_range(-0.05, 0.05) * exp(-t * 20.0)
		"empty":
			out.resize(int(RATE * 0.12))
			for i in out.size():
				out[i] = _click(float(i) / RATE, 2800.0) * 0.6
	return _wav(out, loop)


## Electric crackle at `t` s: a buzz at the mains' pitch, its edges rough, and random sparks.
static func _crackle_at(rng: RandomNumberGenerator, t: float) -> float:
	var buzz := signf(sin(TAU * 50.0 * t)) * 0.25 + sin(TAU * 150.0 * t) * 0.15
	var spark := rng.randf_range(-1.0, 1.0) * (1.0 if rng.randf() < 0.035 else 0.18)
	return clampf(buzz * rng.randf_range(0.5, 1.0) + spark, -1.0, 1.0)


static func _click(t: float, f: float) -> float:
	if t < 0.0:
		return 0.0
	return sin(TAU * f * t) * exp(-t * 120.0)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
