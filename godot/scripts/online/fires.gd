extends Node
## PTA Online's fires (ONLINE_MILESTONES.md O7, ONLINE_MODE.md 5): a child of the PTA Online mode (scripts/modes/
## online_mode.gd) on every peer, with its own RPCs. The host (the official server) lights them, makes them grow and
## spread, judges the water on them and puts them out; every other peer draws them (scripts/fire_fx.gd) from its word.
## The firefighter job (scripts/online/fire_job.gd) says when and where to light one (an alarm) and pays for those put
## out (fire_out).
## - Spots: world/fires.json (tools/online/fires.py): building fronts, parked cars, bins, grass and woods a fire truck
##   can hose from a road, within 2 km of the fire station.
## - A fire starts at START heat and grows to 1 over its kind's `grow` s (not while it is being hosed). Burning at
##   SPREAD_HEAT or more for SPREAD_EVERY s, it lights a neighbour: the nearest spot of world/fires.json within its
##   kind's `spread` m not burning, or for grass and woods a point SPREAD_STEP m away on the same ground (grass, tall
##   grass, a wood's floor: scripts/ground_map.gd); at most ALARM_FIRES fires an alarm.
## - Water: every fire truck's jet as the host flies it (scripts/water_cannon.gd `splashed`: the host's own truck, and
##   its copies of the others' trucks posed from their states, so no peer says where its water went), a packet landing
##   within the fire (its kind's radius, over its height) takes 1 / (`water` × WaterCannon.RATE) of its heat: `water` s
##   of a whole jet on it put a fire at full heat out. Each packet counts for the truck's driver (as the job allows:
##   fire_job.counts), and whether it is their own truck.
## - A fire burning BURN_MAX s burns out (nothing paid); with nobody on duty, every fire dies down in CALM s.
## Peers get each fire as it starts (_c_fire), its heat 4 times a second when it changed (_c_heats), its end (_c_out),
## and all of them when they join (_c_all). Fire ids are the host's, counting up.
## The local player's game draws them (FireFx, within reach of the camera) and keeps `fires` for the HUD and the maps.

const FireFx = preload("res://scripts/fire_fx.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const Marks = preload("res://scripts/race_marks.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WaterCannon = preload("res://scripts/water_cannon.gd")
const Car = preload("res://scripts/car.gd")

const SPOTS := "res://world/fires.json"
## Per kind: its name, radius (m) and height (m) the water must land in, s of a whole jet that put it out at full heat,
## s it takes to grow from START to 1, m it spreads to.
const KINDS := {
	"bin": {"label": "Bin fire", "radius": 1.6, "height": 2.5, "water": 3.0, "grow": 40.0, "spread": 9.0},
	"car": {"label": "Car fire", "radius": 3.0, "height": 3.0, "water": 7.0, "grow": 60.0, "spread": 9.0},
	"building": {"label": "Building fire", "radius": 3.0, "height": 6.0, "water": 11.0, "grow": 90.0, "spread": 14.0},
	"grass": {"label": "Grass fire", "radius": 3.4, "height": 2.0, "water": 4.0, "grow": 30.0, "spread": 9.0},
	"wood": {"label": "Wood fire", "radius": 3.8, "height": 4.0, "water": 7.0, "grow": 50.0, "spread": 10.0},
}
const BURNABLE := ["grass", "tall_grass", "forest_floor"]   # ground materials grass and wood fires spread over
const START := 0.35                         # heat a fire starts at
const SPREAD_HEAT := 0.9
const SPREAD_EVERY := 45.0                  # s (PLATEAU_FIRE_SPREAD)
const SPREAD_STEP := Vector2(6.0, 9.0)      # m, grass and woods
const SPREAD_GAP := 4.5                     # m from any other fire
const ALARM_FIRES := 5                      # fires an alarm grows to at most
const BURN_MAX := 900.0                     # s
const CALM := 20.0                          # s a fire takes to die down with nobody on duty
const WATER_HOLD := 1.0                     # s after the last water a fire doesn't grow
const MARGIN := 1.5                         # m round a fire the water still counts
const HEATS_EVERY := 0.25                   # s between heat updates to the peers
const HEAT_STEP := 0.02                     # heat change worth sending
const AFTER := 600.0                        # s a spot doesn't burn again

var mode: Node                              # online_mode.gd, which makes this node
var spots: Array = []                       # world/fires.json "spots"
var fires := {}                             # id -> Fire (host: all of them; peers: as the host said)
var spread_every := SPREAD_EVERY
var _next_id := 1
var _spot_t := {}                           # host: spot id -> time it last burnt
var _time := 0.0
var _heats_t := 0.0
var _trucks := {}                           # host: fire trucks whose water we listen to
var _scan_t := 0.0
var _grid := {}                             # Vector2i 20 m cell -> [spot index] (spreading)
var _rng := RandomNumberGenerator.new()


## A fire (the host's, or a peer's copy).
class Fire:
	var id := 0
	var kind := "bin"
	var pos := Vector3.ZERO                 # Godot, on the ground at its foot
	var yaw := 0.0                          # rad: buildings: the way the facade faces (the fx's +Z)
	var width := 4.0                        # m, buildings
	var name := ""                          # the building's, or ""
	var spot := 0                           # world/fires.json id, 0 a spread point
	var alarm := 0                          # id of the fire the alarm started with (itself when it is one)
	var heat := START
	var sent := START                       # heat the peers last got
	var t := 0.0                            # s since it started
	var out := false
	var out_t := 0.0
	var wet_t := INF                        # s since the last water
	var spread_t := 0.0
	var water := {}                         # host: peer -> [packets, packets from their own truck]
	var first_water := -1.0                 # host: s after the start the first water came
	var quick := 0.0                        # host: s the response-time bonus allows (fire_job)
	var fx: Node3D                          # FireFx, peers

	func label() -> String:
		var l: String = KINDS[kind]["label"]
		return "%s · %s" % [l, name] if name != "" else l

	func xy() -> Vector2:
		return Vector2(pos.x, -pos.z)

	func info() -> Dictionary:
		return {"kind": kind, "pos": pos, "yaw": yaw, "w": width, "name": name, "alarm": alarm, "heat": heat, "t": t}


func _ready() -> void:
	_rng.randomize()
	if OS.get_environment("PLATEAU_FIRE_SPREAD") != "":
		spread_every = float(OS.get_environment("PLATEAU_FIRE_SPREAD"))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPOTS)) if FileAccess.file_exists(SPOTS) else null
	if data is Dictionary:
		spots = data["spots"]
	else:
		push_error("No PTA Online fire spots: %s missing" % SPOTS)
	for i in spots.size():
		var c := _cell(Vector2(spots[i]["x"], spots[i]["y"]))
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(i)


func _exit_tree() -> void:
	for f: Fire in fires.values():
		if f.fx and is_instance_valid(f.fx):
			f.fx.queue_free()


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))


## The fires burning now.
func burning() -> Array:
	return fires.values().filter(func(f: Fire) -> bool: return not f.out)


## The fires of alarm `alarm` still burning.
func of_alarm(alarm: int) -> Array:
	return burning().filter(func(f: Fire) -> bool: return f.alarm == alarm)


# ---------------------------------------------------------------- host: lighting

## Host: lights spot `spot` (a world/fires.json entry) as a new alarm, `quick` s allowed for the response-time bonus. The
## fire, or null when it can't (too near another).
func light(spot: Dictionary, quick: float) -> Fire:
	var p := Vector2(spot["x"], spot["y"])
	for f: Fire in burning():
		if f.xy().distance_to(p) < SPREAD_GAP:
			return null
	var f := _start(spot["kind"], p, deg_to_rad(float(spot.get("yaw", 0.0))), float(spot.get("w", 4.0)),
			str(spot.get("name", "")), int(spot["id"]), 0)
	f.quick = quick
	return f


## Whether spot `spot` may burn now: not lately, no fire within `gap` m (an alarm's: twice SPREAD_GAP), no vehicle on a
## car's spot.
func free_spot(spot: Dictionary, gap := SPREAD_GAP * 2.0) -> bool:
	if _time - float(_spot_t.get(int(spot["id"]), -INF)) < AFTER:
		return false
	var p := Vector2(spot["x"], spot["y"])
	for f: Fire in fires.values():
		if f.xy().distance_to(p) < gap:
			return false
	if spot["kind"] == "car":
		for c: Car in mode.game.cars:
			if is_instance_valid(c) and not c.stowed and Vector2(c.global_position.x, -c.global_position.z).distance_to(p) < 5.0:
				return false
	return true


func _start(kind: String, p: Vector2, yaw: float, width: float, place: String, spot: int, alarm: int) -> Fire:
	var f := Fire.new()
	f.id = _next_id
	_next_id += 1
	f.kind = kind
	f.pos = Vector3(p.x, _ground_y(p, kind == "building"), -p.y)
	f.yaw = yaw
	f.width = width
	f.name = place
	f.spot = spot
	f.alarm = alarm if alarm != 0 else f.id
	fires[f.id] = f
	if spot != 0:
		_spot_t[spot] = _time
	mode.send_all(self, "_c_fire", [f.id, f.info()])
	if mode.game.mode != "server":
		_show(f)
	_log("Fire %d (%s) lit at (%d, %d)%s" % [f.id, f.label(), roundi(p.x), roundi(p.y), "" if f.alarm == f.id
			else ", spread from alarm %d" % f.alarm])
	return f


## The ground's height (Godot y) under map point `p`: a ray down from a little over the drawn ground (under a building's
## eaves at its facade), the drawn ground when it finds nothing.
func _ground_y(p: Vector2, facade: bool) -> float:
	var g := Marks.ground(p.x, p.y)
	var space: PhysicsDirectSpaceState3D = mode.game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, g + (2.0 if facade else 6.0), -p.y),
			Vector3(p.x, g - 8.0, -p.y), Layers.SOLID)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else g


# ---------------------------------------------------------------- host: burning

func _physics_process(delta: float) -> void:
	if mode == null or not mode.hosting:
		return
	_time += delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_listen()
	var calm: bool = mode.fire_job.duties.is_empty()
	for f: Fire in fires.values():
		if f.out:
			f.out_t += delta
			if f.out_t > FireFx.STEAM + 1.0:
				_forget(f)
			continue
		f.t += delta
		f.wet_t += delta
		if calm:
			f.heat -= delta / CALM
			if f.heat <= 0.0:
				_end(f, "faded")
			continue
		if f.wet_t > WATER_HOLD:
			f.heat = minf(f.heat + delta * (1.0 - START) / float(KINDS[f.kind]["grow"]), 1.0)
		if f.t > BURN_MAX:
			_end(f, "burnt out")
			continue
		if f.heat >= SPREAD_HEAT:
			f.spread_t += delta
			if f.spread_t >= spread_every:
				f.spread_t = 0.0
				_spread(f)
		else:
			f.spread_t = 0.0
	_heats_t -= delta
	if _heats_t <= 0.0:
		_heats_t = HEATS_EVERY
		_send_heats()


## Lights a neighbour of `f` (its alarm short of ALARM_FIRES): the nearest free spot within its kind's reach, else for
## grass and woods a point SPREAD_STEP m away on burnable ground. The new fire, or null.
func _spread(f: Fire) -> Fire:
	if of_alarm(f.alarm).size() >= ALARM_FIRES:
		return null
	var reach: float = KINDS[f.kind]["spread"]
	var here := f.xy()
	var best := {}
	var best_d := INF
	var c := _cell(here)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for i: int in _grid.get(c + Vector2i(dx, dy), []):
				var s: Dictionary = spots[i]
				var d := here.distance_to(Vector2(s["x"], s["y"]))
				if d < reach and d < best_d and int(s["id"]) != f.spot and free_spot(s, SPREAD_GAP):
					best = s
					best_d = d
	if not best.is_empty():
		return _start(best["kind"], Vector2(best["x"], best["y"]), deg_to_rad(float(best.get("yaw", 0.0))),
				float(best.get("w", 4.0)), str(best.get("name", "")), int(best["id"]), f.alarm)
	if f.kind not in ["grass", "wood"]:
		return null
	var map: GroundMap = GroundMap.get_map()
	for k in 12:
		var a := _rng.randf() * TAU
		var p := here + Vector2(cos(a), sin(a)) * _rng.randf_range(SPREAD_STEP.x, SPREAD_STEP.y)
		var m := map.material_at(p.x, p.y) if map else -2
		if m == -1 or m >= 0 and map.materials[m] not in BURNABLE:
			continue
		var clear := true
		for o: Fire in burning():
			clear = clear and o.xy().distance_to(p) >= SPREAD_GAP
		if clear:
			return _start(f.kind, p, 0.0, 4.0, "", 0, f.alarm)
	return null


## Water lands at `point` from fire truck `truck`: on the fire it falls in, for its driver.
func _splashed(point: Vector3, truck: Car) -> void:
	if not is_instance_valid(truck):
		return
	var peer: int = mode.fire_job.driver(truck)
	if peer == 0 or not mode.fire_job.counts(peer):
		return
	var f := fire_at(point)
	if f == null:
		return
	var own := false
	var v: Dictionary = mode.vehicles.get(truck.net_id, {})
	var acc: Dictionary = mode.account(peer)
	if not v.is_empty() and not acc.is_empty():
		own = int(v.get("vehicle", 0)) > 0 and int(v.get("account", -1)) == int(acc["account"])
	water(f, peer, own, 1)


## The burning fire `point` (Godot) falls in (within its radius + MARGIN, over its height), the nearest, or null.
func fire_at(point: Vector3) -> Fire:
	var best: Fire = null
	var best_d := INF
	for f: Fire in fires.values():
		if f.out:
			continue
		var k: Dictionary = KINDS[f.kind]
		var rel := point - f.pos
		if rel.y < -1.5 or rel.y > float(k["height"]) + 2.0:
			continue
		var d := Vector2(rel.x, rel.z).length()
		if f.kind == "building":            # along the facade: its width
			var along := Vector3(cos(f.yaw), 0.0, sin(f.yaw))   # along the facade
			var side := absf(rel.dot(along))
			var out := rel.dot(Vector3(sin(f.yaw), 0.0, -cos(f.yaw)))
			d = Vector2(maxf(side - f.width * 0.5, 0.0), maxf(out, 0.0)).length()
		if d < float(k["radius"]) + MARGIN and d < best_d:
			best = f
			best_d = d
	return best


## Host: `packets` of water on `f` from player `peer`'s jet (`own`: their own truck): its heat down, and out at 0.
func water(f: Fire, peer: int, own: bool, packets: int) -> void:
	if f.out:
		return
	if f.first_water < 0.0:
		f.first_water = f.t
	f.wet_t = 0.0
	var w: Array = f.water.get(peer, [0, 0])
	w[0] += packets
	w[1] += packets if own else 0
	f.water[peer] = w
	f.heat -= packets / (float(KINDS[f.kind]["water"]) * WaterCannon.RATE)
	if f.heat <= 0.0:
		_end(f, "water")


## Host: fire `f` is over (`why`: "water" put out, "burnt out", "faded" nobody on duty, "gone").
func _end(f: Fire, why: String) -> void:
	f.heat = 0.0
	f.out = true
	f.out_t = 0.0
	mode.send_all(self, "_c_out", [f.id, why])
	if mode.game.mode != "server":
		_c_out(f.id, why)
	_log("Fire %d (%s) %s after %d s" % [f.id, f.label(), "put out" if why == "water" else why, roundi(f.t)])
	if why == "water":
		mode.fire_job.fire_out(f)


func _forget(f: Fire) -> void:
	if f.fx and is_instance_valid(f.fx):
		f.fx.queue_free()
	fires.erase(f.id)


## Host: puts every fire out at once, paying nothing (tests, the mode ending).
func clear() -> void:
	for f: Fire in fires.values():
		if not f.out:
			_end(f, "gone")


## Connects to the water of every fire truck on the map not listened to yet.
func _listen() -> void:
	for c: Car in mode.game.cars:
		if is_instance_valid(c) and c.has_method("sight_point") and not _trucks.has(c):
			_trucks[c] = true
			c.cannon.splashed.connect(_splashed.bind(c))
	for c: Object in _trucks.keys():
		if not is_instance_valid(c):
			_trucks.erase(c)


func _send_heats() -> void:
	var out := PackedFloat32Array()
	for f: Fire in fires.values():
		if not f.out and absf(f.heat - f.sent) >= HEAT_STEP:
			f.sent = f.heat
			out.append(f.id)
			out.append(f.heat)
			if f.fx:
				f.fx.set_heat(f.heat)
	if not out.is_empty():
		mode.send_all(self, "_c_heats", [out])


## Host: tells player `peer` (just joined) every fire burning.
func player_registered(peer: int) -> void:
	var all := []
	for f: Fire in burning():
		all.append([f.id, f.info()])
	mode.send_to(peer, self, "_c_all", [all])


func _log(text: String) -> void:
	if mode.game.net.dedicated or OS.get_environment("PLATEAU_JOB_LOG") == "1":
		print(text)


# ---------------------------------------------------------------- peers: drawing

func _show(f: Fire) -> void:
	var fx := FireFx.new()
	fx.name = "Fire_%d" % f.id
	fx.kind = f.kind
	fx.width = f.width
	fx.heat = f.heat
	fx.seed_ = f.id
	mode.game.add_child(fx)
	fx.global_transform = Transform3D(Basis(Vector3.UP, PI - f.yaw), f.pos)   # its +Z the way yaw says (0 north)
	f.fx = fx


func _copy(id: int, d: Dictionary) -> Fire:
	var f := Fire.new()
	f.id = id
	f.kind = d["kind"]
	f.pos = d["pos"]
	f.yaw = float(d["yaw"])
	f.width = float(d["w"])
	f.name = str(d["name"])
	f.alarm = int(d["alarm"])
	f.heat = float(d["heat"])
	f.t = float(d.get("t", 0.0))
	return f


func _process(delta: float) -> void:
	if mode == null or mode.hosting:
		return
	for f: Fire in fires.values():         # (the host's own copies are aged in _physics_process)
		if f.out:
			f.out_t += delta
			if f.out_t > FireFx.STEAM + 1.0:
				_forget(f)
		else:
			f.t += delta


# ---------------------------------------------------------------- messages

@rpc("authority", "call_remote", "reliable")
func _c_fire(id: int, d: Dictionary) -> void:
	if mode.game.mode == "server" or fires.has(id) or not KINDS.has(str(d.get("kind", ""))):
		return
	var f := _copy(id, d)
	fires[id] = f
	_show(f)


@rpc("authority", "call_remote", "reliable")
func _c_all(all: Array) -> void:
	for e: Array in all:
		_c_fire(int(e[0]), e[1])


@rpc("authority", "call_remote", "unreliable_ordered")
func _c_heats(data: PackedFloat32Array) -> void:
	for i in range(0, data.size() - 1, 2):
		var f: Fire = fires.get(int(data[i]))
		if f and not f.out:
			f.heat = data[i + 1]
			if f.fx:
				f.fx.set_heat(f.heat)


@rpc("authority", "call_remote", "reliable")
func _c_out(id: int, _why: String) -> void:
	var f: Fire = fires.get(id)
	if f == null:
		return
	f.out = true
	f.out_t = 0.0
	f.heat = 0.0
	if f.fx and is_instance_valid(f.fx):
		f.fx.put_out()
