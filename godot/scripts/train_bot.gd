extends RefCounted
## Bot driver of an RER B train (scripts/train.gd) on the peer simulating it (one per train, scripts/train_traffic.gd).
## Traction and braking as an MI 79's (rail.json train: ACCEL 1.0 m/s² from rest, service braking 0.7 m/s², up to
## 1.1 m/s² when it must, emergency braking 1.15 m/s²; the rate of change of the acceleration limited to JERK for
## comfort), at the planned speed of its service (rail.json services v: the line speed, the curves' limits over the
## train's whole length, braking curves ahead of each slower stretch and to a terminus), and:
## - stops: at Lozère the front stops on the 8-car stopping mark (within STOP_TOLERANCE), the doors open on the platform
##   side after OPEN_DELAY, stay open `dwell` s (rail.json: 40 s) and as long as a player stands in a doorway, then the
##   door warning sounds (CHIME s) and they shut; a player stepping into a doorway meanwhile opens them again (the
##   bus's door hold) for HOLD_AGAIN s before the next warning. At a terminus stop (rail.json stops "terminus"; none
##   since the line runs on out of the map at both ends) and at the end of its route the train is `done`:
##   train_traffic.gd stows it.
## - signals: block signalling on its service's signals (rail.json services blocks): the block beyond a signal is
##   occupied while a train ahead has any of its length in it; the train then stops SIGNAL_MARGIN short of the signal,
##   and never runs closer than SIGNAL_MARGIN behind the tail of the train ahead.
## - people and vehicles on the track (the players on foot, every vehicle out; `obstacles`, within TRACK_HALF of the
##   track centre and level with it) up to LOOK m ahead: the horn as soon as it is less than HORN_AHEAD s away, the
##   brakes as hard as needed to stop short of it, emergency braking if the service brakes cannot; a 200 t train at
##   90 km/h needs ~270 m even then, so it may not stop in time (train_traffic.gd handles the knock).

const STOP_TOLERANCE := 0.3                 # m: the front this close to its mark, crawling, stops on it
const OPEN_DELAY := 1.0                     # s from the stop to the doors opening
const CHIME := 2.6                          # s of the door warning before they shut (vehicle_audio "train_doors")
const HOLD_AGAIN := 4.0                     # s the doors stay open after a player held them, before the next warning
const SIGNAL_MARGIN := 15.0                 # m short of a red signal (and of the tail of the train ahead)
const LOOK := 700.0                         # m ahead watched for people and vehicles on the track
const TRACK_HALF := 1.9                     # m either side of the track centre (GC kinematic gauge 1.645 m + margin)
const LEVEL := 3.0                          # m: something this far above or below the rails is not on them
const HORN_AHEAD := 12.0                    # s: the horn when something on the track is closer than this at the speed
const HORN_BLAST := 1.4                     # s per blast
const JERK := 1.2                           # m/s³, the acceleration's rate of change (comfort; ~0.5-1.5 in service)
const CREEP := 0.6                          # m/s, the last metres to the mark
const FRONT_REACH := 1.5                    # m from the front coupler to where the body hits something

var train: Node3D                           # scripts/train.gd
var service: Dictionary
var state := "run"                          # "run", "stopped" (at a stop, doors to open), "dwell", "closing", "done"
var stop_k := 0                             # the next stop (service stops)
var t := 0.0                                # s in this state
var accel := 1.0                            # m/s², rail.json train
var service_brake := 0.7
var max_brake := 1.1
var emergency_brake := 1.15
var a := 0.0                                # m/s², now
var emergency := false                      # braking at the emergency rate (an obstacle it cannot stop short of)
var obstacle := INF                         # m from the front to the nearest thing on the track ahead (tests)
var red_ahead := INF                        # m to the next red signal ahead (tests)
var stops_made := 0
var held := 0                               # times a player held the doors (tests)

var _v := PackedFloat32Array()              # planned speed, m/s per metre of route (the front)
var _stops: Array = []                      # [{s, side (1 left), dwell, terminus}]
var _blocks := PackedFloat32Array()
var _horn_t := 0.0
var _horn_on := false


func setup(tr: Node3D, svc: Dictionary, spec: Dictionary) -> void:
	train = tr
	service = svc
	accel = spec.get("accel", accel)
	service_brake = spec.get("service_brake", service_brake)
	max_brake = spec.get("max_service_brake", max_brake)
	emergency_brake = spec.get("emergency_brake", emergency_brake)
	for v in svc["v"]:
		_v.append(v)
	for s: Dictionary in svc["stops"]:
		_stops.append({"s": float(s["s"]["8"]), "side": 1 if s.get("side", "left") == "left" else -1,
				"dwell": float(s.get("dwell", 40.0)), "terminus": s.get("terminus", false), "name": s["name"]})
	for b in svc["blocks"]:
		_blocks.append(b)


## Starts a new trip from the service's start (front, speed).
func start() -> void:
	state = "run"
	stop_k = 0
	t = 0.0
	a = 0.0
	emergency = false
	train.front = service["start"]
	train.speed = service["start_speed"]
	train.set_doors(false)
	train.door_t = 0.0
	while stop_k < _stops.size() and _stops[stop_k]["s"] < train.front - 1.0:
		stop_k += 1


## Planned speed at route distance d.
func planned(d: float) -> float:
	return _v[clampi(int(d), 0, _v.size() - 1)]


## One tick: `ahead` the other trains of the service (train.gd), `obstacles` [route distance, lateral offset, level
## difference] of what is near the track (train_traffic.gd), `doorway` the global positions of the players who may
## hold the doors.
func drive(delta: float, ahead: Array, obstacles: Array, doorway: Array) -> void:
	t += delta
	var d: float = train.front
	var v: float = train.speed
	match state:
		"stopped":
			if t >= OPEN_DELAY:
				train.set_doors(true, _stops[stop_k]["side"])
				_set_state("dwell")
			return
		"dwell":
			if t >= _stops[stop_k]["dwell"] and not train.door_blocked(doorway):
				train.chime()
				_set_state("closing")
			return
		"closing":
			if train.door_blocked(doorway) and train.door_t > 0.0:
				train.set_doors(true, _stops[stop_k]["side"])
				held += 1
				_set_state("dwell")
				t = _stops[stop_k]["dwell"] - HOLD_AGAIN
				return
			if t >= CHIME:
				train.set_doors(false)
				if train.door_t <= 0.0:
					stop_k += 1
					_set_state("run")
			return
		"done":
			train.speed = 0.0
			return
	# running: the tightest of the planned speed and the distances it must stop short of
	var target := planned(d + 0.5)
	var need := 0.0                         # deceleration needed to stop short of the nearest constraint
	var mark := INF
	if stop_k < _stops.size():
		mark = _stops[stop_k]["s"] - d
	if mark < INF:
		need = maxf(need, v * v / (2.0 * maxf(mark, 0.05)))
		if mark < 3.0:
			target = minf(target, CREEP + mark * 0.5)
	red_ahead = INF
	var tail_gap := INF
	for o: Node3D in ahead:
		if o == train or o.stowed or o.front <= d:
			continue
		tail_gap = minf(tail_gap, o.front - o.length - d)
		for i in _blocks.size():
			var s0 := _blocks[i]
			var s1 := _blocks[i + 1] if i + 1 < _blocks.size() else INF
			if s0 > d and o.front - o.length < s1 and o.front > s0:
				red_ahead = minf(red_ahead, s0 - d)
	# each place it must stop short of caps the speed on the service braking curve to it (0 there: it stays stopped)
	if red_ahead < INF:
		need = maxf(need, v * v / (2.0 * maxf(red_ahead - SIGNAL_MARGIN, 0.05)))
		target = minf(target, sqrt(2.0 * service_brake * maxf(red_ahead - SIGNAL_MARGIN, 0.0)))
	if tail_gap < INF:
		need = maxf(need, v * v / (2.0 * maxf(tail_gap - SIGNAL_MARGIN, 0.05)))
		target = minf(target, sqrt(2.0 * service_brake * maxf(tail_gap - SIGNAL_MARGIN, 0.0)))
	obstacle = INF
	for ob: Array in obstacles:
		var gap: float = ob[0] - d - FRONT_REACH
		if gap > -2.0 and gap < LOOK and absf(ob[1]) < TRACK_HALF and absf(ob[2]) < LEVEL:
			obstacle = minf(obstacle, gap)
	var obstacle_need := 0.0
	if obstacle < INF:
		obstacle_need = v * v / (2.0 * maxf(obstacle - 4.0, 0.05))
		target = minf(target, sqrt(2.0 * service_brake * maxf(obstacle - 4.0, 0.0)))
		if obstacle < maxf(v * HORN_AHEAD, 40.0):
			_horn(delta, true)
		else:
			_horn(delta, false)
	else:
		_horn(delta, false)
	# the acceleration it wants, then limited by the jerk
	var want: float
	emergency = false
	if obstacle_need > max_brake:
		want = -emergency_brake            # physically honest: no more than the emergency brakes give
		emergency = true
	elif maxf(need, obstacle_need) >= service_brake * 0.85:
		want = -minf(maxf(need, obstacle_need), max_brake)
	elif v < target - 0.05:
		want = accel * clampf((target - v) / 1.5, 0.15, 1.0)
	elif v > target + 0.05:
		want = -minf(service_brake, (v - target) * 0.8 + 0.1)
	else:
		want = 0.0
	if emergency:
		a = want                            # the emergency brakes bite at once
	else:
		a = move_toward(a, want, JERK * delta)
	v = maxf(v + a * delta, 0.0)
	# at a crawl within half a metre of where it must hold (a red signal, the train ahead, an obstacle): stopped
	var hold := minf(minf(red_ahead - SIGNAL_MARGIN, tail_gap - SIGNAL_MARGIN), obstacle - 4.0)
	if hold < 0.5 and v < CREEP + 0.2:
		v = 0.0
	if v == 0.0 and a < 0.0:
		a = 0.0
	d += v * delta
	# on the mark (never put back if it ran past it: it stops where it is)
	if mark < INF and _stops[stop_k]["s"] - d <= STOP_TOLERANCE and v <= CREEP + 0.2:
		if absf(_stops[stop_k]["s"] - d) <= STOP_TOLERANCE:
			d = _stops[stop_k]["s"]
		v = 0.0
		a = 0.0
		stops_made += 1
		if _stops[stop_k]["terminus"]:
			_set_state("done")
		else:
			_set_state("stopped")
	if d >= float(service["end"]):
		_set_state("done")
	train.front = d
	train.speed = v
	train.traction = clampf(a / accel, 0.0, 1.0)
	train.braking = clampf(-a / max_brake, 0.0, 1.0)


func _set_state(s: String) -> void:
	state = s
	t = 0.0
	if s != "run":
		_horn(0.0, false)


## Horn blasts while `on`: HORN_BLAST s on, half that off.
func _horn(delta: float, on: bool) -> void:
	if not on:
		_horn_t = 0.0
		train.horn = false
		return
	_horn_t += delta
	var cycle := fmod(_horn_t, HORN_BLAST * 1.5)
	train.horn = cycle < HORN_BLAST


func is_done() -> bool:
	return state == "done"
