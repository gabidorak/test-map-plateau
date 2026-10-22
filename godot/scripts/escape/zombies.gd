extends Node3D
## The zombies of Escape from Plateau (Main/Mode/Zombies on every peer; scripts/escape/zombie.gd is one of them).
## - The host (or the solo game, or the dedicated server) runs them. Some guard each survivor's hideout from the start
##   (spawn_guards); others climb out of the ground on the roads round the players, ROAM_MIN to ROAM_MAX m away and never
##   near the safehouse, more of them as dawn comes and the more players there are (ambient); the rescue
##   helicopter's take-off brings hordes (wave). Those farther than ACTIVE m from every player sleep (no thinking, not
##   sent), those beyond NEAR think every third tick, the roaming ones farther than FORGET m go away.
## - Senses (think): a zombie chases the nearest player within SIGHT m (further when their flashlight is on, when they
##   run, when they drive), keeps after them to LOSE m, ignores those knocked down or dead, walks to a noise it heard
##   (gunshots: noise()), else wanders round where it rose. A blow that lands hurts the player (escape_mode.gd
##   zombie_hit: on their own peer), or the vehicle they are in, then them once it is broken. A vehicle going faster than
##   RUN_OVER m/s through one kills it and throws it.
## - Hits come from the peer whose round or crowbar it was (hit()); kills and deaths go to everyone (_c_died).
## - The others get the awake zombies' poses SEND_RATE times a second, stamped with the host's clock (_c_states:
##   id, position, facing, state and kind), and make one on first sight; one not heard of for STALE s went to sleep or
##   away.

const Zombie = preload("res://scripts/escape/zombie.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Water = preload("res://scripts/water.gd")
const CAR_ROUTES := "res://world/car_routes.json"

const SEND_RATE := 10.0
const ACTIVE := 150.0                       # m from the nearest player: farther, asleep
const NEAR := 35.0                          # m: farther, it thinks and moves every third tick
const FORGET := 185.0                       # m: a roaming one this far from every player goes away
const ROAM_MIN := 42.0                      # m from every player a new one rises...
const ROAM_MAX := 100.0                     # ...and at most this far from one of them
const SAFE := 45.0                          # m round the safehouse where none rise
const AMBIENT := Vector2(8.0, 18.0)         # roaming zombies per player, at nightfall .. near dawn
const MAX_ZOMBIES := 110
const SIGHT := 30.0                         # m a zombie senses a player at
const LIGHT_SIGHT := 22.0                   # m more when their flashlight is on...
const RUN_HEARD := 14.0                     # ...when they run...
const ENGINE_HEARD := 25.0                  # ...when they drive
const LOSE := 60.0                          # m a chase goes on to
const NOISE_TIME := 4.0                     # s a noise draws them
const SEPARATION := 0.9                     # m: closer zombies push apart
const VEHICLE_DAMAGE := 6.0                 # health a swing takes off a vehicle
const RUN_OVER := 4.5                       # m/s
const STALE := 2.0                          # s
const RUNNER_SHARE := 0.2
const BRUTE_SHARE := 0.06

var mode: Node                              # escape_mode.gd
var hosting := false
var zombies := {}                           # id -> Zombie
var kills := 0                              # (host) killed this mission

var _next_id := 1
var _send_t := 0.0
var _spawn_t := 1.0
var _tick := 0
var _points := PackedVector2Array()         # map (x, y) of spots on the roads where zombies may rise
var _dirs := PackedVector2Array()           # the way's direction at each (unit, map frame)
var _grid := {}                             # Vector2i (64 m cells) -> PackedInt32Array of _points indices
var _noises: Array = []                     # [position, radius, s left]
var _sep := {}                              # this tick: Vector2i (2 m cells) -> Array of awake zombies
var _rng := RandomNumberGenerator.new()

static var _route_points := PackedVector2Array()     # every route point of car_routes.json, every ~12 m
static var _route_dirs := PackedVector2Array()       # the route's direction there


func _ready() -> void:
	_rng.randomize()


## The host's clock (zombie.gd plays remote ones back on it).
func clock() -> float:
	return mode.clock()


## This peer runs the zombies (solo, host, dedicated server).
func start_hosting() -> void:
	hosting = true
	if _route_points.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAR_ROUTES)) \
				if FileAccess.file_exists(CAR_ROUTES) else null
		if data is Dictionary:
			for id: String in data["routes"]:
				var pts: Array = data["routes"][id]["pts"]
				for i in range(0, pts.size() - 1, 6):
					var a := Vector2(pts[i][0], pts[i][1])
					_route_points.append(a)
					_route_dirs.append((Vector2(pts[i + 1][0], pts[i + 1][1]) - a).normalized())
	var box: Array = mode.campus
	_points = PackedVector2Array()
	_dirs = PackedVector2Array()
	_grid.clear()
	for k in _route_points.size():
		var p := _route_points[k]
		if p.x < box[0] or p.x > box[2] or p.y < box[1] or p.y > box[3]:
			continue
		var c := Vector2i(floori(p.x / 64.0), floori(p.y / 64.0))
		if not _grid.has(c):
			_grid[c] = PackedInt32Array()
		_grid[c].append(_points.size())
		_points.append(p)
		_dirs.append(_route_dirs[k])


## Spots on the campus's roads (map x, y), and the way's direction at each (escape_mode.gd parks vehicles there).
func road_points() -> PackedVector2Array:
	return _points


func road_dirs() -> PackedVector2Array:
	return _dirs


## Every zombie gone (a new mission).
func clear() -> void:
	for z: Zombie in zombies.values():
		z.queue_free()
	zombies.clear()
	_noises.clear()
	kills = 0


func alive_count() -> int:
	var n := 0
	for z: Zombie in zombies.values():
		if z.state != Zombie.DEAD:
			n += 1
	return n


## Host: a zombie of `kind` at `pos` (global), climbing out of the ground when `rising`.
func spawn(pos: Vector3, kind: int, rising: bool, is_guard := false) -> Zombie:
	var z := Zombie.new()
	z.setup(_next_id, kind, _next_id * 31 + 7, false)
	_next_id += 1
	z.guard = is_guard
	z.home = pos
	z.goal = pos
	z.audio = mode.audio
	z.state = Zombie.RISE if rising else Zombie.IDLE
	z.rotation.y = _rng.randf() * TAU
	add_child(z)
	z.global_position = pos
	zombies[z.zid] = z
	if rising and mode.audio:
		mode.audio.play_at("rise", pos + Vector3.UP, -2.0, _rng.randf_range(0.9, 1.1), 6.0, 50.0)
	return z


func _random_kind() -> int:
	var r := _rng.randf()
	return Zombie.BRUTE if r < BRUTE_SHARE else (Zombie.RUNNER if r < BRUTE_SHARE + RUNNER_SHARE else Zombie.SHAMBLER)


## Host: `per_spot` zombies standing round each of `spots` (global positions), between 4 and `spread` m off, a brute
## among them now and then.
func spawn_guards(spots: Array, per_spot: int, spread := 18.0) -> void:
	for c: Vector3 in spots:
		for k in per_spot:
			for attempt in 6:
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(4.0, spread)
				var g := _ground(Vector2(c.x + cos(a) * d, -c.z + sin(a) * d))
				if is_nan(g.y) or absf(g.y - c.y) > 3.0:
					continue
				spawn(g, Zombie.BRUTE if k == 0 and _rng.randf() < 0.35 else _random_kind(), false, true)
				break


## Host: `n` zombies rising round `centre` (global), 25 to 60 m off: the horde coming for the helicopter.
func wave(centre: Vector3, n: int) -> void:
	for k in n:
		for attempt in 8:
			var a := _rng.randf() * TAU
			var d := _rng.randf_range(25.0, 60.0)
			var g := _ground(Vector2(centre.x + cos(a) * d, -centre.z + sin(a) * d))
			if is_nan(g.y) or absf(g.y - centre.y) > 6.0:
				continue
			var z := spawn(g, _random_kind(), true)
			z.goal = centre
			z.home = centre
			break


## The ground (global) at map (x, y) (escape_mode.gd ground_at), all NAN when there is none or it is under water.
func _ground(xy: Vector2) -> Vector3:
	var p: Vector3 = mode.ground_at(xy)
	if is_nan(p.y) or Water.depth_at(p) > 0.2:
		return Vector3(NAN, NAN, NAN)
	return p


## Host: a noise at `pos` (a gunshot) drawing the zombies within `radius` m that chase nobody.
func noise(pos: Vector3, radius: float) -> void:
	if not hosting:
		return
	_noises.append([pos, radius, NOISE_TIME])
	for z: Zombie in zombies.values():
		if z.target == 0 and z.state in [Zombie.IDLE, Zombie.WALK] and z.global_position.distance_to(pos) < radius:
			z.goal = pos
			z.set_state(Zombie.WALK)


## Host: zombie `id` hit by `damage` along `dir` from player `peer`'s weapon (`head`: on the head, already counted in the
## damage). It turns on them; a kill goes to everyone.
func hit(id: int, damage: float, dir: Vector3, peer: int, melee := false) -> void:
	var z: Zombie = zombies.get(id)
	if z == null or z.state == Zombie.DEAD:
		return
	if z.take_hit(damage, dir, true):
		_kill(z, dir, Vector3.ZERO, peer)
		return
	if peer != 0 and mode.vitals.has(peer):
		z.target = peer
		if z.state in [Zombie.IDLE, Zombie.WALK]:
			z.set_state(Zombie.CHASE)
	if melee:
		z.velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 2.5


func _kill(z: Zombie, dir: Vector3, fling: Vector3, peer: int) -> void:
	kills += 1
	z.die(dir, fling)
	mode.zombie_killed(peer)
	mode.send_all(self, "_c_died", [z.zid, dir, fling])


@rpc("authority", "call_remote", "reliable")
func _c_died(id: int, dir: Vector3, fling: Vector3) -> void:
	var z: Zombie = zombies.get(id)
	if z:
		z.die(dir, fling)


@rpc("authority", "call_remote", "unreliable_ordered")
func _c_states(t: float, data: PackedFloat32Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(0, data.size() - 5, 6):
		var id := int(data[i])
		var packed := int(data[i + 5])
		var z: Zombie = zombies.get(id)
		if z == null:
			z = Zombie.new()
			z.setup(id, packed >> 4, id * 31 + 7, true)
			z.audio = mode.audio
			z.state = packed & 15
			add_child(z)
			zombies[id] = z
			if z.state == Zombie.RISE and mode.audio:
				mode.audio.play_at("rise", Vector3(data[i + 1], data[i + 2], data[i + 3]) + Vector3.UP, -2.0, 1.0, 6.0, 50.0)
		if z.state == Zombie.DEAD:
			continue
		z.last_seen = now
		z.push_state(t, Vector3(data[i + 1], data[i + 2], data[i + 3]), data[i + 4], packed & 15)


# ---------------------------------------------------------------- the host's tick

func _physics_process(delta: float) -> void:
	if not hosting:
		_drop_stale()
		return
	_tick += 1
	var targets: Array = mode.zombie_targets()
	for n: Array in _noises:
		n[2] -= delta
	_noises = _noises.filter(func(n: Array) -> bool: return n[2] > 0.0)
	_sep.clear()
	var gone := []
	for z: Zombie in zombies.values():
		if z.state == Zombie.DEAD:
			if z.gone():
				gone.append(z)
			continue
		var d := _nearest(z.global_position, targets)
		z.awake = d < ACTIVE
		if not z.guard and d > FORGET and z.target == 0:
			gone.append(z)
			continue
		if z.awake:
			var c := Vector2i(floori(z.global_position.x / 2.0), floori(z.global_position.z / 2.0))
			if not _sep.has(c):
				_sep[c] = []
			_sep[c].append(z)
	for z: Zombie in gone:
		zombies.erase(z.zid)
		z.queue_free()
	for z: Zombie in zombies.values():
		if not z.awake or z.state == Zombie.DEAD:
			continue
		if _nearest(z.global_position, targets) < NEAR:
			z.step(delta, self)
		elif (_tick + z.zid) % 3 == 0:
			z.step(delta * 3.0, self)
	_run_overs()
	if mode.phase_running():
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = 1.0
			_spawn_ambient(targets)
	_send_t += delta
	if _send_t >= 1.0 / SEND_RATE - 0.001:
		_send_t = 0.0
		_send_states()


## Remote: the zombies not heard of for STALE s (asleep, or gone) leave; dead ones once they have sunk.
func _drop_stale() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id: int in zombies.keys():
		var z: Zombie = zombies[id]
		if (z.state == Zombie.DEAD and z.gone()) or (z.state != Zombie.DEAD and now - z.last_seen > STALE):
			zombies.erase(id)
			z.queue_free()


## Distance (m) from `p` to the nearest of `targets` (INF when there is none).
func _nearest(p: Vector3, targets: Array) -> float:
	var best := INF
	for t: Dictionary in targets:
		if not t["dead"]:
			best = minf(best, p.distance_to(t["pos"]))
	return best


## Host: zombie `z` looks for a player to chase (see the header), else a noise, else wanders.
func think(z: Zombie) -> void:
	var targets: Array = mode.zombie_targets()
	var best: Dictionary = {}
	var best_d := INF
	for t: Dictionary in targets:
		if t["dead"] or t["down"]:
			continue
		var reach := SIGHT + (LIGHT_SIGHT if t["light"] else 0.0) + (RUN_HEARD if t["running"] else 0.0) \
				+ (ENGINE_HEARD if t["car"] != null else 0.0)
		if t["peer"] == z.target:
			reach = maxf(reach, LOSE)
		var d := z.global_position.distance_to(t["pos"])
		if d < reach and d < best_d:
			best = t
			best_d = d
	if not best.is_empty():
		z.target = best["peer"]
		if z.state in [Zombie.IDLE, Zombie.WALK]:
			z.set_state(Zombie.CHASE)
		return
	if z.target != 0:
		z.target = 0
		if z.state == Zombie.CHASE:
			z.set_state(Zombie.WALK)        # to where it last saw them (its goal)
		return
	for n: Array in _noises:
		if z.global_position.distance_to(n[0]) < n[1]:
			z.goal = n[0]
			z.set_state(Zombie.WALK)
			return
	if z.state == Zombie.IDLE and _rng.randf() < 0.2:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(3.0, 12.0)
		z.goal = z.home + Vector3(cos(a) * r, 0.0, sin(a) * r)
		z.set_state(Zombie.WALK)


## Where player `peer` is (global; the vehicle they are in), or null when they are not to be chased.
func target_pos(peer: int) -> Variant:
	for t: Dictionary in mode.zombie_targets():
		if t["peer"] == peer and not t["dead"] and not t["down"]:
			return t["pos"]
	return null


## How much further a zombie reaches player `peer`: the half width of the vehicle they are in.
func target_reach(peer: int) -> float:
	for t: Dictionary in mode.zombie_targets():
		if t["peer"] == peer and t["car"] != null:
			return (t["car"] as Node).half_extents.x + 0.4
	return 0.0


## A blow of `z` landed on player `peer`: on the vehicle they are in while it holds, else on them.
func swing_landed(z: Zombie, peer: int) -> void:
	var dmg: float = Zombie.KINDS[z.kind]["damage"] * _rng.randf_range(0.8, 1.2)
	for t: Dictionary in mode.zombie_targets():
		if t["peer"] != peer:
			continue
		var car: Node = t["car"]
		if car != null and is_instance_valid(car) and not car.broken:
			mode.game.net.hit_vehicle(car, VEHICLE_DAMAGE * (2.0 if z.kind == Zombie.BRUTE else 1.0))
			if mode.audio:
				mode.audio.play_at("hit_flesh", car.global_position + Vector3.UP, 0.0, 0.6, 8.0, 60.0)
		else:
			mode.zombie_hit(peer, dmg, z.global_position)
		return


## A push away from the zombies crowding `z` (this tick's awake ones).
func separation(z: Zombie) -> Vector3:
	var p := z.global_position
	var c := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
	var push := Vector3.ZERO
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for o: Zombie in _sep.get(c + Vector2i(dx, dz), []):
				if o == z:
					continue
				var d := p - o.global_position
				d.y = 0.0
				var l := d.length()
				if l < SEPARATION and l > 0.001:
					push += d / l * (SEPARATION - l) / SEPARATION
	return push * 1.2


## Host: vehicles going faster than RUN_OVER m/s kill the zombies in their way and throw them.
func _run_overs() -> void:
	for car: Node in mode.game.cars:
		if not is_instance_valid(car) or car.stowed:
			continue
		var v: Vector3 = car.linear_velocity
		if v.length() < RUN_OVER:
			continue
		var half: Vector3 = car.half_extents + Vector3(0.45, 0.0, 0.6)
		for z: Zombie in zombies.values():
			if z.state == Zombie.DEAD or z.global_position.distance_squared_to(car.global_position) > 100.0:
				continue
			var local: Vector3 = car.to_local(z.global_position) - car.extents_center
			if absf(local.x) < half.x and absf(local.z) < half.z and local.y > -1.5 and local.y < 3.0:
				var fling := v * 0.9 + Vector3.UP * (3.0 + v.length() * 0.15)
				_kill(z, v.normalized(), fling, mode.driver_of(car))
				mode.game.net.hit_vehicle(car, 1.5 if z.kind != Zombie.BRUTE else 8.0)
				if mode.audio:
					mode.audio.play_at("hit_flesh", z.global_position + Vector3.UP, 4.0, 0.8, 10.0, 80.0)


## Host: roaming zombies rise round the players until there are as many as dawn and the players' number call for.
func _spawn_ambient(targets: Array) -> void:
	var live: Array = targets.filter(func(t: Dictionary) -> bool: return not t["dead"])
	if live.is_empty() or zombies.size() >= MAX_ZOMBIES:
		return
	var roaming := 0
	for z: Zombie in zombies.values():
		if not z.guard and z.state != Zombie.DEAD:
			roaming += 1
	var wanted := int(lerpf(AMBIENT.x, AMBIENT.y, mode.dread_level()) * live.size() * mode.difficulty())
	if roaming >= wanted:
		return
	var who: Dictionary = live[_rng.randi() % live.size()]
	var p := _roam_spot(who["pos"], live)
	if is_nan(p.x):
		return
	var group := _rng.randi_range(1, 3)
	for k in group:
		var off := Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		var g := _ground(Vector2(p.x + off.x, -(p.z + off.z)))
		if not is_nan(g.y):
			spawn(g, _random_kind(), true)


## A road spot ROAM_MIN to ROAM_MAX m from `centre`, ROAM_MIN m from every live player and SAFE m from the safehouse
## (global; x NAN when none was found).
func _roam_spot(centre: Vector3, live: Array) -> Vector3:
	var c := Vector2i(floori(centre.x / 64.0), floori(-centre.z / 64.0))
	var safe: Vector3 = mode.safehouse_pos
	var ring := PackedInt32Array()                  # the road spots in the ring round `centre`, clear of the rest
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for i in _grid.get(c + Vector2i(dx, dy), PackedInt32Array()):
				var xy := _points[i]
				var flat := Vector2(xy.x - centre.x, -xy.y - centre.z).length()
				if flat < ROAM_MIN or flat > ROAM_MAX or Vector2(xy.x - safe.x, -xy.y - safe.z).length() < SAFE:
					continue
				var clear := true
				for t: Dictionary in live:
					var tp: Vector3 = t["pos"]
					if Vector2(xy.x - tp.x, -xy.y - tp.z).length() < ROAM_MIN:
						clear = false
						break
				if clear:
					ring.append(i)
	for attempt in mini(ring.size(), 6):
		var g := _ground(_points[ring[_rng.randi() % ring.size()]])
		if not is_nan(g.y) and absf(g.y - centre.y) < 25.0:
			return g
	return Vector3(NAN, NAN, NAN)


## Host: the awake zombies' poses for the others.
func _send_states() -> void:
	var data := PackedFloat32Array()
	for z: Zombie in zombies.values():
		if not z.awake or z.state == Zombie.DEAD:
			continue
		var p := z.global_position
		data.append_array([z.zid, p.x, p.y, p.z, z.rotation.y, z.state | (z.kind << 4)])
	mode.send_all(self, "_c_states", [mode.clock(), data])
