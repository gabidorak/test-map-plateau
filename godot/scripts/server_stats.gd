extends Node
## Dedicated server, --stats: every EVERY s one line of JSON on stdout saying how the server copes, for
## tools/bench/ (the player capacity benchmark): the physics ticks done and how long the scripts took, the process's and
## its main thread's CPU, what went over the network, and the players, vehicles and traffic level then.

const EVERY := 5.0                          # s

var game: Node3D                            # game.gd
var _t := 0.0
var _start := 0                             # usec, this tick's scripts started
var _ticks := PackedFloat32Array()          # ms of script time, ticks of this window
var _frames_at := 0
var _cpu_at := [0, 0]                       # clock ticks: process, main thread
var _wall_at := 0
var _last_tick := 0
var _late_ticks := 0                        # ticks more than 1.5 intervals after the one before


## Marks the end of the tick's scripts (the Stats node itself runs before all of them).
class TickEnd extends Node:
	var stats: Node

	func _init() -> void:
		name = "StatsEnd"
		process_physics_priority = 1000000

	func _physics_process(_delta: float) -> void:
		stats.end_tick()


func _ready() -> void:
	process_physics_priority = -1000000
	var end := TickEnd.new()
	end.stats = self
	add_child(end)
	_frames_at = Engine.get_physics_frames()
	_cpu_at = _cpu()
	_wall_at = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_tick != 0 and now - _last_tick > 1500000.0 / Engine.physics_ticks_per_second:
		_late_ticks += 1
	_last_tick = now
	_start = now


func end_tick() -> void:
	_ticks.append((Time.get_ticks_usec() - _start) / 1000.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= EVERY:
		_t = 0.0
		_report()


func _report() -> void:
	var now := Time.get_ticks_usec()
	var wall := (now - _wall_at) / 1e6
	var cpu := _cpu()
	var hz := 100.0                         # USER_HZ
	var ticks := _ticks.duplicate()
	ticks.sort()
	var n := ticks.size()
	var sum := 0.0
	for x in ticks:
		sum += x
	var host: ENetConnection = (game.net.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	print("STATS " + JSON.stringify({
		"t": Time.get_unix_time_from_system(),
		"players": game.net.players.size(),
		"cars": game.net.cars.size(),
		"driven": game.net.driver_of.values().filter(func(d: int) -> bool: return d != 0).size(),
		"tps": (Engine.get_physics_frames() - _frames_at) / wall,
		"late_ticks": _late_ticks,
		"tick_ms_avg": sum / maxi(n, 1),
		"tick_ms_p50": ticks[n / 2] if n > 0 else 0.0,
		"tick_ms_p99": ticks[n * 99 / 100] if n > 0 else 0.0,
		"tick_ms_max": ticks[n - 1] if n > 0 else 0.0,
		"cpu": (cpu[0] - _cpu_at[0]) / hz / wall,
		"cpu_main": (cpu[1] - _cpu_at[1]) / hz / wall,
		"rss_mb": _rss_mb(),
		"sent_kb_s": host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / 1024.0 / wall,
		"recv_kb_s": host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / 1024.0 / wall,
		"sent_pkt_s": host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS) / wall,
		"recv_pkt_s": host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS) / wall,
		"traffic_level": game.traffic.load_level,
		"traffic_load": game.traffic.tick_load,
	}))
	_ticks.clear()
	_late_ticks = 0
	_frames_at = Engine.get_physics_frames()
	_cpu_at = cpu
	_wall_at = now


## utime + stime of the process and of its main thread, in clock ticks ([0, 0] where there is no /proc).
func _cpu() -> Array:
	var pid := OS.get_process_id()
	return [_stat_cpu("/proc/self/stat"), _stat_cpu("/proc/%d/task/%d/stat" % [pid, pid])]


func _stat_cpu(path: String) -> int:
	var f := _proc_line(path)
	var after := f.rfind(")")               # fields 14 and 15, counted past the name (which may hold spaces)
	if after < 0:
		return 0
	var parts := f.substr(after + 2).split(" ")
	return int(parts[11]) + int(parts[12])


func _rss_mb() -> float:
	var parts := _proc_line("/proc/self/statm").split(" ")
	return int(parts[1]) * 4096.0 / 1048576.0 if parts.size() > 1 else 0.0


## The first line of a /proc file (their length reads 0: get_file_as_string gives "").
func _proc_line(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_line() if f else ""
