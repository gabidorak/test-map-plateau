extends Node
## PTA Online's stunts (ONLINE_MILESTONES.md O6, ONLINE_MODE.md 5): a bonus layer on any vehicle, a child of the PTA
## Online mode (scripts/modes/online_mode.gd) on every peer, with its own RPCs. The host (the official server) judges
## them from the states it already gets of the players' vehicles, and pays through the accounts service (job "stunts",
## inside the jobs' hourly cap); the player's game only shows them.
## - Jumps: a vehicle in the air (all of its underside, front, middle and rear, AIR_LIFT m higher off the ground or the
##   water than it rides, moving) at least `air_min` s pays `air_per_s` a second once it lands. Not the planes (they
##   fly), nor the horse (it jumps at a key): their jumps pay only off a stunt spot.
## - Flips: the vehicle's turns about its own axes while in the air, counted once it lands on its wheels (upright
##   LAND_CHECK s after): a front flip or a backflip (nose over), a barrel roll (side over), doubled, tripled... A plane
##   flies loops (nose up, over the top, round) and rolls (over on its back and round), above PLANE_LOW m.
## - Near misses (as the bus job's), and top speed: `top_share` of the model's top speed held `top_hold` s.
## - Stunt spots (world/stunts.json, tools/online/stunts.py: named jumps found on the map's own ground): a jump taking
##   off within a spot's radius, its way, in the air at least its `air_min` s, pays `spot_first` the first time the
##   account does it (the accounts service remembers), `spot_again` after.
## - Each stunt pays less the more it was paid this last hour (`decay` per time the same kind, `spot_decay` the same
##   spot), so one ramp can't be farmed; a landing that crashes the vehicle (CRASH of its health), on its roof, or a flight
##   longer than AIR_MAX s pays nothing.
## - Checks against a patched game (ONLINE_MODE.md 6.1): a jump of over TELEPORT m in a tick or a speed over the
##   model's top speed: no stunts for VOID s, and the flight under way doesn't count.
## - Players on bus duty: their bus job pays the air time and near misses (scripts/online/bus_job.gd), not this.
## The player's game shows each stunt as it pays (top middle: its name, the details, the money, "first time!") and the
## spots on the maps (map_places). Played solo (the tools), the money is the mode's test_money and the cap the bus
## job's (solo_pay); PLATEAU_JOB_LOG=1 prints the log lines a dedicated server prints.

const Car = preload("res://scripts/car.gd")
const BusBot = preload("res://scripts/bus_bot.gd")
const BusJob = preload("res://scripts/online/bus_job.gd")
const Biplane = preload("res://scripts/plane.gd")
const Economy = preload("res://scripts/economy.gd")
const Water = preload("res://scripts/water.gd")
const UiStyle = preload("res://scripts/ui_style.gd")

const DATA := "res://data/jobs.json"
const SPOTS := "res://world/stunts.json"
const AIR_LIFT := 0.5                       # m higher off the ground than it rides: in the air
const TOUCH := 0.15                         # m: still on the ground (where a jump took off from)
const AIR_SPEED := 4.0                      # m/s at least
const AIR_MAX := 8.0                        # s: a longer flight is a fall (or a patched game), not a jump
const RIDE_SMOOTH := 0.05                   # per look, of the moving average of how high it rides
const LOOK_EVERY := 0.05                    # s between looks under the vehicles
const LAND_CHECK := 0.6                     # s after landing it must be on its wheels
const UPRIGHT := 0.6                        # its up within ~53° of the sky
const CRASH := 0.25                         # share of its health lost from take-off to LAND_CHECK: a crash landing
const TURN_SLACK := 1.0                     # rad short of a full turn that still counts as one (it lands on its wheels)
const SPOT_ANGLE := 0.64                    # cos of how far off a spot's way the take-off may go (50°)
const PLANE_LOW := 10.0                     # m off the ground a plane's loops and rolls count from
const TELEPORT := 25.0                      # m in a tick
const SPEED_MARGIN := 1.2                   # times the model's top speed...
const SPEED_SLACK := 3.0                    # ...+ this, m/s...
const TOO_FAST := 0.5                       # ...for this many s
const VOID := 5.0                           # s without stunts after either
const NEAR_SPEED := 8.0                     # near misses: as bus_job.gd's
const NEAR_REL := 8.0
const NEAR_GAP := 0.8
const NEAR_AGAIN := 10.0
const TOP_AGAIN := 0.7                      # share of the top speed to drop under before top speed counts again
const HOUR := 3600.0
const POP_TIME := 4.0                       # s a stunt stays on screen

var mode: Node                              # online_mode.gd, which makes this node
var pay := {}                               # data/jobs.json "stunts"
var cap := 30000                            # € an account may earn from jobs an hour (data/jobs.json "hour_cap")
var spots: Array = []                       # world/stunts.json "spots"
var rides := {}                             # host: peer -> Ride (the vehicle they drive)
var time := 0.0                             # host: s of physics since it started
var events: Array = []                      # host: [peer, kind, text, €, first] of every stunt paid (tests)
var _used := {}                             # host: account -> {kind or "spot:<id>": [times paid]}
var _solo_firsts := {}                      # played solo: spot ids done
var _hud: VBoxContainer


## A player at the wheel of a vehicle (host).
class Ride:
	var peer := 0
	var account := 0
	var username := ""
	var car_id := ""
	var last := Vector3.ZERO                # middle of the vehicle last tick
	var has_last := false
	var vel := Vector3.ZERO                 # m/s, Godot axes (from the positions: the server poses remote vehicles)
	var basis := Basis.IDENTITY             # its rotation last tick
	var fast_t := 0.0
	var void_t := 0.0                       # s left without stunts
	var look_t := 0.0
	var ride := NAN                         # m from its floor down to the ground on its wheels (moving average)
	var air := false
	var air_t := 0.0
	var take_off := Vector3.ZERO            # where it last touched the ground before taking off
	var touch := Vector3.ZERO               # where it last touched the ground
	var take_off_dir := Vector2.ZERO        # map x/y, the way it went
	var take_off_health := 0.0
	var pitch := 0.0                        # rad turned about its own x (nose over) since it left the ground...
	var roll := 0.0                         # ...and about its own z (side over)
	var inverted := false                   # ...been upside down meanwhile
	var nose_up := false                    # ...pointed up (a plane's loop)
	var landed := {}                        # a landing being checked: {"t", "air_t", "pitch", "roll", "spot", "health"}
	var near := {}                          # vehicle -> time it may count again
	var top_t := 0.0
	var top_armed := true
	var spoiled := false                    # the flight under way doesn't count (a teleport, too fast)


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if data is Dictionary and data.has("stunts"):
		pay = data["stunts"]
		cap = int(data["hour_cap"])
	else:
		push_error("No PTA Online stunt pay: %s missing" % DATA)
	if OS.get_environment("PLATEAU_JOB_CAP") != "":
		cap = int(OS.get_environment("PLATEAU_JOB_CAP"))
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPOTS)) if FileAccess.file_exists(SPOTS) else null
	if s is Dictionary:
		spots = s["spots"]
	multiplayer.peer_disconnected.connect(func(id: int) -> void: rides.erase(id))


func _exit_tree() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.queue_free()


## The spots on the maps: [name, "stunt", map xy].
func map_places() -> Array:
	return spots.map(func(s: Dictionary) -> Array: return [s["name"], "stunt", Vector2(s["x"], s["y"])])


# ---------------------------------------------------------------- host: watching

func _physics_process(delta: float) -> void:
	if mode == null or not mode.hosting:
		return
	time += delta
	var seen := {}
	for id: String in mode.vehicles:
		var car: Car = mode.car_of(id)
		if car == null or car.stowed:
			continue
		var peer := _driver(car)
		if peer == 0 or mode.bus_job.duties.has(peer):
			continue
		var acc: Dictionary = mode.account(peer)
		if acc.is_empty():
			continue
		var r: Ride = rides.get(peer)
		if r == null or r.car_id != id:
			r = Ride.new()
			r.peer = peer
			r.account = int(acc["account"])
			r.username = str(acc["username"])
			r.car_id = id
			r.basis = car.global_basis.orthonormalized()
			rides[peer] = r
		seen[peer] = true
		_tick(r, car, delta)
	for peer: int in rides.keys():
		if not seen.has(peer):
			rides.erase(peer)


func _tick(r: Ride, car: Car, delta: float) -> void:
	var mid := car.to_global(car.extents_center)
	r.void_t -= delta
	if r.has_last:
		var jump := mid - r.last
		var flat := Vector2(jump.x, jump.z).length()
		if flat > maxf(TELEPORT, car.max_speed * delta * 3.0):
			_cheat(r, "teleport", "a jump of %d m" % roundi(flat))
		else:
			r.vel = r.vel.lerp(jump / delta, 0.3)
			r.fast_t = r.fast_t + delta if flat / delta > car.max_speed * SPEED_MARGIN + SPEED_SLACK else 0.0
			if r.fast_t > TOO_FAST:
				r.fast_t = 0.0
				_cheat(r, "too fast", "%d km/h" % roundi(flat / delta * 3.6))
	r.last = mid
	r.has_last = true
	var b := car.global_basis.orthonormalized()
	var turn := (r.basis.inverse() * b).get_rotation_quaternion()   # this tick's turn, in the vehicle's frame
	var angle := turn.get_angle()
	if angle > 1e-5:
		var axis := turn.get_axis()
		if angle > PI:                      # the same turn, the short way round
			angle = TAU - angle
			axis = -axis
		r.pitch += axis.x * angle
		r.roll += axis.z * angle
	r.basis = b
	r.inverted = r.inverted or b.y.y < -0.3
	r.nose_up = r.nose_up or b.z.y > 0.7
	r.look_t -= delta
	if r.look_t <= 0.0:
		var dt := LOOK_EVERY - r.look_t
		r.look_t = LOOK_EVERY
		if car is Biplane:
			_look_plane(r, car)
		else:
			_look(r, car, mid, dt)
		_near_misses(r, car)
		_top_speed(r, car, dt)


## Air time, flips and spots of a vehicle on wheels (or hooves, or a hull), every LOOK_EVERY s.
func _look(r: Ride, car: Car, mid: Vector3, dt: float) -> void:
	var gap := ground_gap(car)
	var v := Vector2(r.vel.x, r.vel.z).length()
	if is_nan(r.ride) and gap < INF:
		r.ride = gap
	elif not r.air and gap < r.ride + AIR_LIFT:
		r.ride = lerpf(r.ride, gap, RIDE_SMOOTH)
	var up := gap < INF and gap > r.ride + AIR_LIFT and (v > AIR_SPEED or r.air)
	var touching := gap < r.ride + TOUCH
	if touching and not r.air and r.landed.is_empty():   # turns count from the last touch (a bounce keeps them)
		r.touch = mid
		r.pitch = 0.0
		r.roll = 0.0
		r.inverted = false
	if up and not r.air:                    # take-off
		r.air = true
		r.air_t = 0.0
		r.take_off = r.touch
		r.take_off_dir = Vector2(r.vel.x, -r.vel.z).normalized()
		r.take_off_health = car.health
		r.spoiled = r.void_t > 0.0
	elif up:
		r.air_t += dt
	elif r.air:                             # landing
		r.air = false
		if r.landed.is_empty():
			r.landed = {"t": 0.0, "air_t": r.air_t, "spot": _spot_at(r), "health": r.take_off_health,
					"spoiled": r.spoiled}
		else:                               # a bounce: one jump
			r.landed["t"] = 0.0
			r.landed["air_t"] += r.air_t
	if not r.air and not r.landed.is_empty():
		r.landed["t"] += dt
		if r.landed["t"] >= LAND_CHECK:
			_landed(r, car)


## The spot `r` took off from (within its radius, going its way), or {}.
func _spot_at(r: Ride) -> Dictionary:
	var p := Vector2(r.take_off.x, -r.take_off.z)
	for s: Dictionary in spots:
		var a := deg_to_rad(float(s["yaw"]))
		if p.distance_to(Vector2(s["x"], s["y"])) <= float(s["radius"]) \
				and r.take_off_dir.dot(Vector2(sin(a), cos(a))) > SPOT_ANGLE:
			return s
	return {}


## The landing of `r` checked LAND_CHECK s on: what the jump pays.
func _landed(r: Ride, car: Car) -> void:
	var l := r.landed
	r.landed = {}
	var air_t: float = l["air_t"]
	var spot: Dictionary = l["spot"]
	var pitch := r.pitch
	var roll := r.roll
	var flipped := r.inverted
	r.pitch = 0.0
	r.roll = 0.0
	r.inverted = false
	if l["spoiled"] or air_t > AIR_MAX:
		return
	var horse: bool = car.model_name == "horse"
	var counts_air := air_t >= float(pay["air_min"]) and not horse
	var counts_spot := not spot.is_empty() and air_t >= float(spot["air_min"])
	if not counts_air and not counts_spot:
		return
	var why := ""
	if car.broken or car.health < float(l["health"]) - CRASH * car.max_health:
		why = "crash landing"
	elif car.global_basis.y.normalized().y < UPRIGHT:
		why = "landed on its %s" % ("roof" if car.global_basis.y.y < 0.0 else "side")
	var parts := []                         # [kind, text, €]
	if counts_air:
		parts.append(["air", "Air %.1f s" % air_t, roundi(air_t * float(pay["air_per_s"]))])
	var turns_p := _turns(pitch) if flipped else 0
	var turns_r := _turns(roll) if flipped else 0
	if turns_p > 0:
		parts.append(["flip", _times(turns_p) + ("Front flip" if pitch > 0.0 else "Backflip"), turns_p * int(pay["flip"])])
	if turns_r > 0:
		parts.append(["flip", _times(turns_r) + "Barrel roll", turns_r * int(pay["flip"])])
	var title: String = spot["name"] if counts_spot else str(parts[-1][1]) if not parts.is_empty() else "Jump"
	if why != "":
		_log("%s: %s, %s (%.1f s in the air): nothing paid" % [r.username, title, why, air_t])
		mode.send_to(r.peer, self, "_c_stunt", [title, "%.1f s in the air · %s" % [air_t, why], 0, false, "crash"])
		return
	_award(r, title, parts, spot if counts_spot else {})


## Whole turns in `angle` rad (one short by TURN_SLACK still counts).
static func _turns(angle: float) -> int:
	return int(floor((absf(angle) + TURN_SLACK) / TAU))


static func _times(n: int) -> String:
	return ["", "", "Double ", "Triple ", "Quadruple "][n] if n < 5 else "%d× " % n


## A plane's loops and rolls, every LOOK_EVERY s.
func _look_plane(r: Ride, car: Car) -> void:
	var gap := ground_gap(car)
	if gap < PLANE_LOW and gap < INF or r.void_t > 0.0 or car.broken:
		r.pitch = 0.0
		r.roll = 0.0
		r.inverted = false
		r.nose_up = false
		return
	if absf(r.pitch) >= TAU and r.inverted and r.nose_up:
		r.pitch -= signf(r.pitch) * TAU
		r.inverted = false
		r.nose_up = false
		r.roll = 0.0
		_award(r, "Loop", [["loop", "Loop", int(pay["loop"])]], {})
	elif absf(r.roll) >= TAU and r.inverted:
		r.roll -= signf(r.roll) * TAU
		r.inverted = false
		r.pitch = 0.0
		_award(r, "Roll", [["roll", "Roll", int(pay["roll"])]], {})


func _near_misses(r: Ride, car: Car) -> void:
	var v := r.vel.length()
	if v < NEAR_SPEED or r.void_t > 0.0:
		return
	var mid := car.to_global(car.extents_center)
	var mine := []
	for c: Car in mode.game.cars:
		if c == car or not is_instance_valid(c) or c.stowed or r.near.get(c, 0.0) > time:
			continue
		if c.global_position.distance_to(mid) > 25.0:
			continue
		var cv: Vector2 = BusBot.velocity_of(c)
		if cv.length() < 2.0 or (Vector2(r.vel.x, -r.vel.z) - cv).length() < NEAR_REL:
			continue
		if mine.is_empty():
			mine = BusJob._rects(car)
		var g := BusJob._gap(mine, BusJob._rects(c))
		if g > 0.05 and g < NEAR_GAP:
			r.near[c] = time + NEAR_AGAIN
			_award(r, "Near miss", [["near_miss", "Near miss", int(pay["near_miss"])]], {})


func _top_speed(r: Ride, car: Car, dt: float) -> void:
	var v := r.vel.length()
	if v < car.max_speed * TOP_AGAIN:
		r.top_armed = true
	if v >= car.max_speed * float(pay["top_share"]) and r.top_armed and r.void_t <= 0.0:
		r.top_t += dt
		if r.top_t >= float(pay["top_hold"]):
			r.top_t = 0.0
			r.top_armed = false
			_award(r, "Top speed", [["top_speed", "Top speed %d km/h" % roundi(v * 3.6), int(pay["top_speed"])]], {})
	else:
		r.top_t = 0.0


func _cheat(r: Ride, kind: String, what: String) -> void:
	if r.void_t <= 0.0:
		_log("%s's %s: %s (%s), no stunts for %d s" % [r.username, r.car_id, kind, what, roundi(VOID)])
	r.void_t = VOID
	r.spoiled = true
	if not r.landed.is_empty():
		r.landed["spoiled"] = true
	r.near.clear()
	r.top_t = 0.0


# ---------------------------------------------------------------- host: paying

## How many times account `account` was paid for `key` this last hour (and forgets the older ones).
func used(account: int, key: String) -> int:
	var by: Dictionary = _used.get(account, {})
	var times: Array = by.get(key, [])
	while not times.is_empty() and time - float(times[0]) > HOUR:
		times.pop_front()
	return times.size()


func _use(account: int, key: String) -> void:
	if not _used.has(account):
		_used[account] = {}
	if not _used[account].has(key):
		_used[account][key] = []
	_used[account][key].append(time)


## Pays `r`'s player for a stunt: `parts` [kind, text, €] each less by `decay` per time its kind paid this hour, and spot
## `spot` (`spot_first` the first time, else `spot_again` less by `spot_decay` per time this hour).
func _award(r: Ride, title: String, parts: Array, spot: Dictionary) -> void:
	var decay := float(pay["decay"])
	var lines := []
	var amount := 0
	for p: Array in parts:
		var due := roundi(float(p[2]) * pow(decay, used(r.account, p[0])))
		if due >= int(pay["min_pay"]):
			_use(r.account, p[0])
			amount += due
		lines.append(str(p[1]))
	var once := ""
	var once_amount := 0
	if not spot.is_empty():
		var key := "spot:" + str(spot["id"])
		var again := roundi(float(pay["spot_again"]) * pow(float(pay["spot_decay"]), used(r.account, key)))
		_use(r.account, key)
		once = "stunt:" + str(spot["id"])
		once_amount = amount + int(pay["spot_first"])
		amount += again if again >= int(pay["min_pay"]) else 0
	var paid := 0
	var first := false
	var failed := false
	var wanted := amount
	if mode.game.economy.official:
		if amount > 0 or once != "":
			var res: Dictionary = await mode.game.economy.pay(r.account, amount, "%s (%s)" % [title, ", ".join(lines)]
					if not lines.is_empty() else title, "stunts", cap, once, once_amount)
			if res["ok"]:
				paid = int(res["data"].get("paid", 0))
				first = bool(res["data"].get("first", false))
			else:
				failed = true
				push_warning("Could not pay %s: %s" % [r.username, res["message"]])
	else:
		first = once != "" and not _solo_firsts.has(once)
		if first:
			wanted = once_amount
		paid = mode.bus_job.solo_pay(wanted) if wanted > 0 else 0
		if first and paid > 0:
			_solo_firsts[once] = true
		elif first:
			first = false
	if first:
		wanted = once_amount
	var note := "not paid: the accounts service didn't answer" if failed else "first time!" if first \
			else "hourly cap reached" if paid < wanted else "" if wanted > 0 else "paid enough for that this hour: try another"
	_log("%s: %s%s, %d € paid%s" % [r.username, title, " (%s)" % ", ".join(lines) if not lines.is_empty() and
			lines != [title] else "", paid, " (%s)" % note if note != "" else ""])
	events.append([r.peer, parts[0][0] if not parts.is_empty() else "spot", title, paid, first])
	mode.send_to(r.peer, self, "_c_stunt", [title, " · ".join(lines.filter(func(t: String) -> bool: return t != title)),
			paid, first, note])


func _log(text: String) -> void:
	if mode.game.net.dedicated or OS.get_environment("PLATEAU_JOB_LOG") == "1":
		print(text)


## Who drives `car`: a peer, 0 nobody (played solo: us when we do).
func _driver(car: Car) -> int:
	if mode.game.net.active:
		return int(mode.game.net.driver_of.get(car.net_id, 0))
	return mode.me() if mode.game.driving == car else 0


## m from `car`'s floor down to the ground, a deck or the water at its least, under its front, middle and rear (as the
## bus job's, BusJob._ground_gap, and the water too), INF when none of them finds anything within 8 m.
static func ground_gap(car: Car) -> float:
	var best := BusJob._ground_gap(car)
	for f: float in [-0.8, 0.0, 0.8]:
		var p := car.to_global(Vector3(car.extents_center.x, 0.0, car.extents_center.z + car.half_extents.z * f))
		var w := Water.surface_at(p)
		if not is_nan(w) and p.y - w < 8.0:
			best = minf(best, p.y - w)
	return best


# ---------------------------------------------------------------- the local player

func _build_hud() -> void:
	_hud = VBoxContainer.new()
	_hud.name = "Stunts"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_constant_override("separation", 6)
	mode.game.hud.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _process(delta: float) -> void:
	if _hud == null:
		return
	for p in _hud.get_children():
		p.set_meta("t", float(p.get_meta("t")) + delta)
		p.modulate.a = clampf((POP_TIME - float(p.get_meta("t"))) / 0.8, 0.0, 1.0)
		if float(p.get_meta("t")) > POP_TIME:
			p.queue_free()


## The stunts on screen (tests): one line each.
func hud_text() -> String:
	if _hud == null:
		return ""
	var out := []
	for p in _hud.get_children():
		if not p.is_queued_for_deletion():
			out.append(" | ".join(p.get_child(0).get_children().map(func(l: Label) -> String: return l.text)))
	return "\n".join(out)


# ---------------------------------------------------------------- messages

## A stunt of ours: `title` (the spot's or the stunt's name), `detail` (the rest), `amount` € paid, `first` (a spot's
## first time), `note` (why less or nothing: "crash" for a crash landing).
@rpc("authority", "call_remote", "reliable")
func _c_stunt(title: String, detail: String, amount: int, first: bool, note: String) -> void:
	if mode.game.mode == "server":
		return
	if _hud == null:
		_build_hud()
	var pop := PanelContainer.new()
	pop.add_theme_stylebox_override("panel", UiStyle.panel(0.62, 12, 10))
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	pop.add_child(box)
	var crash := note == "crash"
	box.add_child(UiStyle.label(title.to_upper(), 26, Color(1.0, 0.45, 0.4) if crash else Color(1.0, 0.82, 0.3)))
	if detail != "":
		box.add_child(UiStyle.label(detail, 17, Color.WHITE))
	if not crash:
		var money := UiStyle.label("+%s" % Economy.money(amount) + ("  ·  FIRST TIME!" if first else ""), 22 if first else 19,
				Color(0.55, 1.0, 0.5))
		box.add_child(money)
	if note != "" and note != "first time!":
		box.add_child(UiStyle.label(note, 15, UiStyle.TEXT_WARN))
	pop.set_meta("t", 0.0)
	_hud.add_child(pop)
	_hud.move_child(pop, 0)
	while _hud.get_child_count() > 3:
		_hud.get_child(_hud.get_child_count() - 1).free()
