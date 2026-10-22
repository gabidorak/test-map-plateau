extends "res://scripts/modes/game_mode.gd"
## Escape from Plateau: a co-op survival night on the plateau (scripts/modes/modes.gd), 1 to 8 players.
## Something got out of the labs; the plateau is cut off and the dead walk the campus. A few survivors are still out
## there, hiding in front of the doors of the campus's buildings (world/escape.json, tools/escape/escape_spots.py):
## find them, carry them to Dragon 91, the Sécurité Civile helicopter waiting at one of the fields (scripts/escape/
## evac.gd), and get out before dawn.
## - The night (game.gd's night.gd in dread): thick murky fog, a dim moon, a power cut (most street lamps dead, a few
##   flickering, few windows lit), scary sounds in the fog (scripts/escape/escape_audio.gd). N does nothing; the
##   cameras see CAMERA_FAR m at most (the fog hides the rest).
## - No vehicle menu, no bots, no trains, no races, no showroom cars: CARS abandoned vehicles lie about the campus
##   (some damaged), the keys in them. They are fast, and run zombies over, but the zombies batter them, and the
##   people in them once they are broken.
## - Zombies (scripts/escape/zombies.gd), survivors (survivors.gd), supplies (loot.gd), the local player's weapons and kit
##   (arsenal.gd), the screen (escape_hud.gd).
## - Health: zombies' blows hurt; at 0 the player is knocked down: crawling, the pistol only, bleeding out over
##   BLEED_TIME s unless a teammate holds E by them (REVIVE_TIME s) or they get up with a medkit (Q held). Bled out,
##   they are dead: they watch a teammate until they come back at the safehouse RESPAWN_TIME s on, while the team has
##   lives left (LIVES + one per player). Everyone down or dead with no life left: the mission is lost.
## - Phases (the host's): the briefing (BRIEFING_TIME s), the rescue (until every survivor is rescued, or someone holds
##   E in the circle to call the helicopter early), the extraction (Dragon 91 lifts off LIFT_WAIT s on, hordes coming:
##   whoever is in its circle then escapes), then won (someone escaped) or lost. Dawn (DAWN s after nightfall) ends it
##   too: the helicopter leaves with whoever is in its circle. The host (or solo player) starts a new mission from the
##   in-game menu; a dedicated server starts one for the first player to join it empty, and RESTART_AFTER s after one
##   ends.
## - Network: the host (or the dedicated server) runs the mission, the zombies, the survivors and the supplies; each
##   player's peer its own health and weapons. Each player sends the host its state STATE_RATE times a second (vitals:
##   where they are, facing, health, knocked down or dead, flashlight, carrying, running, in a vehicle, weapon), which
##   the host passes on: the others show their flashlight's beam and their gun, knocked-down ones lying. Shots are
##   sent for show (tracers, flashes, sounds); hits on zombies go to the host; a zombie's blow goes to its victim's
##   peer. The mode's messages go only to welcomed players (send_all), never broadcast.

const Zombies = preload("res://scripts/escape/zombies.gd")
const Zombie = preload("res://scripts/escape/zombie.gd")
const Survivors = preload("res://scripts/escape/survivors.gd")
const Loot = preload("res://scripts/escape/loot.gd")
const Evac = preload("res://scripts/escape/evac.gd")
const Arsenal = preload("res://scripts/escape/arsenal.gd")
const EscapeHud = preload("res://scripts/escape/escape_hud.gd")
const EscapeAudio = preload("res://scripts/escape/escape_audio.gd")
const Car = preload("res://scripts/car.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Marks = preload("res://scripts/race_marks.gd")
const SPOTS := "res://world/escape.json"

enum { BRIEFING, RESCUE, EXTRACTION, WON, LOST }

const FLAG_DOWN := 1
const FLAG_DEAD := 2
const FLAG_LIGHT := 4
const FLAG_CARRY := 8
const FLAG_RUN := 16
const FLAG_AIM := 32
const FLAG_CAR := 64
const FLAG_ESCAPED := 128

const SURVIVORS := 5                        # per mission (PLATEAU_ESCAPE_SURVIVORS, --survivors=)
const SPREAD := 150.0                       # m at least between two survivors' hideouts (relaxed if need be)
const DAWN := 1800.0                        # s of night (PLATEAU_ESCAPE_DAWN, --dawn=)
const BRIEFING_TIME := 10.0
const LIFT_WAIT := 60.0                     # s from the call to the take-off
const WAVE_EVERY := 12.0                    # s between hordes during the extraction
const CALL_TIME := 2.5                      # s of E held in the circle to call the helicopter early
const MAX_HEALTH := 100.0
const BLEED_TIME := 40.0
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 2.3
const REVIVE_HEALTH := 35.0
const SELF_REVIVE_TIME := 4.0
const SELF_REVIVE_HEALTH := 50.0
const GIVE_UP_TIME := 1.5                   # s of Space held, knocked down, to give up
const RESPAWN_TIME := 15.0
const LIVES := 2                            # the team's, plus one per player
const STATE_RATE := 15.0
const NOISE_EVERY := 0.25                   # s between two noises sent to the host
const GUARDS := 7                           # zombies round each hideout (times the difficulty)
const CARS := 14                            # abandoned vehicles
const CARS_NEAR := 2                        # of them near the safehouse
const CAR_MODELS := ["sedan", "suv", "taxi", "van", "hatchback-sports", "compact-hatchback", "family-suv", "ambulance",
		"delivery", "police", "renault-zoe", "sedan-sports", "kaykit-hatchback", "suv"]
const BIG_MODELS := ["bus-idfm", "fire-truck", "gaz-tiger"]   # one of each, further out
const CAMERA_FAR := 320.0
const CARRY_SPEED := 0.72
const DOWN_SPEED := 0.16
const HEAL_SPEED := 0.6
const MAX_DAMAGE := 200.0                   # a hit claimed by a client is capped at this (host)
const RESTART_AFTER := 25.0                 # s after a mission's end a dedicated server starts the next one
const RESUPPLY := 36                        # rounds the safehouse tops a player's 9 mm up to...
const RESUPPLY_EVERY := 45.0                # ...at most this often (s), a bandage too if they have none

var hosting := false                        # this peer runs the mission (solo, host, dedicated server)
var spots := {}                             # escape.json
var campus: Array = [-420.0, -1080.0, 1720.0, 620.0]
var safehouse_pos := Vector3.ZERO
var safehouse_yaw := 0.0
var phase := BRIEFING
var phase_until := 0.0                      # on the game's clock: the briefing's end, the take-off
var dawn_at := 0.0                          # on the game's clock
var night_length := DAWN
var lives := 0
var evac_index := -1
var mission := 0                            # missions started (a new one resets the players)
var vitals := {}                            # peer -> {"pos", "yaw", "pitch", "health", "flags", "weapon", "car"}
var zombies: Zombies
var survivors: Survivors
var loot: Loot
var evac: Evac
var arsenal: Arsenal                        # the local player's (not on a dedicated server)
var hud: EscapeHud
var audio: EscapeAudio
var result := ""                            # why the mission ended (WON, LOST)
var assume_captured := false                # tests: the mouse counts as captured (a headless run has none)

# the local player
var health := MAX_HEALTH
var downed := false
var dead := false
var escaped := false
var bleed := 0.0
var respawn_at := -1.0                      # on the game's clock, -1: none coming (or no life left: no_life)
var no_life := false

# host
var _kills := {}                            # peer -> zombies killed this mission
var _rescuers := {}                         # peer -> survivors they found
var _respawning := {}                       # peer -> when they come back (game clock)
var _wave_t := 0.0
var _warned := 0                            # dawn warnings given (bits)
var _survivor_count := SURVIVORS
var _ended_at := 0.0                        # when the mission ended (game clock)

var _state_t := 0.0
var _noise_t := 0.0
var _revive_t := 0.0
var _revive_peer := 0
var _call_t := 0.0
var _self_t := 0.0
var _give_up_t := 0.0
var _targets: Array = []                    # zombie_targets(), this physics frame's
var _targets_frame := -1
var _gear := {}                             # peer -> their gear on their avatar (flashlight, gun)
var _spectate := 0                          # dead: the peer watched
var _spectator: Camera3D
var _rng := RandomNumberGenerator.new()
var _resupplied := -INF                     # when the safehouse last topped us up (game clock)


func allows(feature: String) -> bool:
	return feature not in ["debug_cars", "showrooms", "bot_traffic", "trains", "races", "vehicle_menu", "park_car",
			"clear_vehicles", "night_toggle", "inspect", "fly_camera"]


func _ready() -> void:
	_rng.randomize()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPOTS)) if FileAccess.file_exists(SPOTS) else null
	if data is Dictionary:
		spots = data
		campus = spots.get("campus", campus)
	var sh: Dictionary = spots.get("safehouse", {"x": game.spawn_xy.x, "y": game.spawn_xy.y, "yaw": game.spawn_yaw_deg})
	safehouse_pos = Vector3(sh["x"], Marks.ground(sh["x"], sh["y"]), -float(sh["y"]))
	safehouse_yaw = deg_to_rad(float(sh.get("yaw", 180.0)))
	var player_here: bool = game.mode != "server"
	if player_here:
		audio = EscapeAudio.new()
		audio.name = "Audio"
		add_child(audio)
		game.night.set_dread(true)
	zombies = Zombies.new()
	zombies.name = "Zombies"
	zombies.mode = self
	add_child(zombies)
	survivors = Survivors.new()
	survivors.name = "Survivors"
	survivors.mode = self
	add_child(survivors)
	loot = Loot.new()
	loot.name = "Loot"
	loot.mode = self
	add_child(loot)
	_build_safehouse(sh)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--survivors="):
			_survivor_count = int(a.get_slice("=", 1))
		elif a.begins_with("--dawn="):
			night_length = float(a.get_slice("=", 1))
	if OS.get_environment("PLATEAU_ESCAPE_SURVIVORS") != "":
		_survivor_count = int(OS.get_environment("PLATEAU_ESCAPE_SURVIVORS"))
	if OS.get_environment("PLATEAU_ESCAPE_DAWN") != "":
		night_length = float(OS.get_environment("PLATEAU_ESCAPE_DAWN"))
	_survivor_count = clampi(_survivor_count, 1, 12)


func _exit_tree() -> void:
	if game.night:
		game.night.set_dread(false)
	var p: CharacterBody3D = game.player
	if is_instance_valid(p):
		p.face_aim = false
		p.speed_scale = 1.0
		p.can_run = true
		p.can_jump = true
		if p.crawling:
			p.set_crawling(false)


func begin() -> void:
	hosting = game.mode in ["solo", "host", "server"]
	if game.mode != "server":
		var p: CharacterBody3D = game.player
		p.face_aim = true
		p.collide_with(Layers.ZOMBIE)
		arsenal = Arsenal.new()
		arsenal.name = "Arsenal"
		arsenal.mode = self
		arsenal.player = p
		add_child(arsenal)
		hud = EscapeHud.new()
		hud.mode = self
		game.hud.add_child(hud)
		_spectator = Camera3D.new()
		_spectator.name = "Spectator"
		_spectator.far = CAMERA_FAR
		_spectator.fov = 65.0
		add_child(_spectator)
		_to_safehouse()
		hud.show_title("ESCAPE FROM PLATEAU", "Night has fallen on the plateau. Loading the mission…", -1.0)
	if hosting:
		zombies.start_hosting()
		new_mission()
	game.toast("Escape from Plateau")


func host_actions() -> Array:
	return [["New mission", new_mission]] if hosting else []


func pause_info() -> String:
	var t := "Escape from Plateau: %d of %d survivors rescued" % [survivors.count(Survivors.RESCUED), survivors.list.size()]
	if phase in [RESCUE, BRIEFING]:
		t += ", dawn in %s" % _clock_text(dawn_at - clock())
	return t + ", %d %s left." % [lives, "life" if lives == 1 else "lives"]


# ---------------------------------------------------------------- the mission (host)

## Host: a new mission: survivors, the helicopter's field, supplies, abandoned vehicles, the zombies guarding the
## hideouts; everyone back at the safehouse with a fresh kit.
func new_mission() -> void:
	if not hosting:
		return
	mission += 1
	zombies.clear()
	game.remove_vehicles(game.cars.duplicate())
	var rows := _pick_survivors()
	survivors.set_round(rows)
	evac_index = _pick_evac()
	var hideouts := []
	for r: Dictionary in rows:
		hideouts.append(r["pos"])
	loot.scatter(_rng, hideouts, spots.get("caches", []), safehouse_pos)
	zombies.spawn_guards(hideouts, roundi(GUARDS * difficulty()))
	_park_cars()
	lives = LIVES + maxi(_player_peers().size(), 1)
	_kills.clear()
	_rescuers.clear()
	_respawning.clear()
	_warned = 0
	result = ""
	phase = BRIEFING
	phase_until = clock() + BRIEFING_TIME
	dawn_at = phase_until + night_length
	var row := _mission_row()
	_c_mission(row, true)
	send_all(self, "_c_mission", [row, true])


func _mission_row() -> Array:
	return [mission, evac_index, phase, phase_until, dawn_at, lives, night_length, result]


## A mission's state (`fresh`: it has just begun, or we have just joined: back to the safehouse, a fresh kit).
@rpc("authority", "call_remote", "reliable")
func _c_mission(row: Array, fresh: bool) -> void:
	mission = row[0]
	phase = row[2]
	phase_until = row[3]
	dawn_at = row[4]
	lives = row[5]
	night_length = row[6]
	result = row[7]
	if fresh or row[1] != evac_index or evac == null:       # (a new mission: a new helicopter, the last one flew off)
		evac_index = row[1]
		_make_evac()
	if fresh and arsenal:
		_reset_player()
		hud.show_title("ESCAPE FROM PLATEAU", _briefing(), BRIEFING_TIME)
		if audio:
			audio.play("radio", -4.0)
			audio.play("stinger", -8.0)


func _briefing() -> String:
	var e: Dictionary = _evac_spot()
	return ("Something got out of the labs. The plateau is cut off and the dead walk the campus.\n" +
			"%d survivors are hiding out there. Find them, carry them to Dragon 91, the rescue helicopter waiting at %s,\n" +
			"and get out before dawn. Stick together.") % [survivors.list.size(), e.get("name", "the fields")]


## Host: the round's survivors, SPREAD m apart where possible, with their hideouts' ground positions.
func _pick_survivors() -> Array:
	var pool: Array = spots.get("survivors", []).duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picked := []
	for spread: float in [SPREAD, SPREAD * 0.5, 0.0]:
		for s: Dictionary in pool:
			if picked.size() >= _survivor_count or s in picked:
				continue
			var ok := true
			for o: Dictionary in picked:
				if Vector2(s["x"] - o["x"], s["y"] - o["y"]).length() < spread:
					ok = false
			if ok:
				picked.append(s)
	var rows := []
	for s: Dictionary in picked:
		var pos := ground_at(Vector2(s["x"], s["y"]))
		var out: Array = s.get("out", [0.0, 1.0])
		var yaw := atan2(-float(out[0]), float(out[1]))        # looking out of the doorway (map y is -Z)
		if s.has("interior"):
			for room in game.get_tree().get_nodes_in_group("showroom"):
				pos = (room.salesman_xf as Transform3D).origin
				yaw = (room.salesman_xf as Transform3D).basis.get_euler().y
		rows.append({"id": s["id"], "who": s["who"], "line": s["line"], "place": s["place"], "pos": pos, "yaw": yaw})
	return rows


## Host: the helicopter's field: one of escape.json's, 400 m from the safehouse at least when it can.
func _pick_evac() -> int:
	var list: Array = spots.get("evac", [])
	if list.is_empty():
		return -1
	var far := []
	for i in list.size():
		if Vector2(list[i]["x"] - safehouse_pos.x, list[i]["y"] + safehouse_pos.z).length() > 400.0:
			far.append(i)
	return far[_rng.randi() % far.size()] if not far.is_empty() else _rng.randi() % list.size()


func _evac_spot() -> Dictionary:
	var list: Array = spots.get("evac", [])
	return list[evac_index] if evac_index >= 0 and evac_index < list.size() else {}


func _make_evac() -> void:
	if evac:
		evac.queue_free()
		evac = null
	var e := _evac_spot()
	if e.is_empty():
		return
	evac = Evac.new()
	evac.audio = audio
	evac.setup(e["x"], e["y"], fposmod(mission * 2.4 + evac_index * 1.3, TAU))    # facing the same way for everyone
	add_child(evac)


## Host: abandoned vehicles on the campus's roads, parked along them: CARS_NEAR near the safehouse, a bus, the fire
## truck and the armoured car further out; some damaged.
func _park_cars() -> void:
	var pts: PackedVector2Array = zombies.road_points()
	var dirs: PackedVector2Array = zombies.road_dirs()
	if pts.is_empty():
		return
	var safe := Vector2(safehouse_pos.x, -safehouse_pos.z)
	var placed: Array[Vector2] = []
	var models := []
	for k in CARS:
		models.append(CAR_MODELS[k % CAR_MODELS.size()])
	models.append_array(BIG_MODELS)
	for k in models.size():
		var model: String = models[k]
		var near := k < CARS_NEAR
		for attempt in 60:
			var i := _rng.randi() % pts.size()
			var p := pts[i]
			var d := p.distance_to(safe)
			if (near and (d > 90.0 or d < 20.0)) or (not near and d < 120.0):
				continue
			if model in BIG_MODELS and d < 350.0:
				continue
			var crowded := false
			for o in placed:
				if o.distance_to(p) < 45.0:
					crowded = true
			if crowded:
				continue
			var dir := dirs[i]
			var side := Vector2(dir.y, -dir.x)          # the right of the way
			var spot := p + side * 1.6
			var g := ground_at(spot)
			if is_nan(g.y):
				continue
			var gdir := Vector3(dir.x, 0.0, -dir.y)
			var xf := Transform3D(Basis(Vector3.UP, atan2(gdir.x, gdir.z) + (PI if _rng.randf() < 0.3 else 0.0)), g)
			var half: Vector3 = _half_of(model)
			if not _spot_free(xf, half):
				continue
			var car: Car = game.park_vehicle(model, xf)
			if car and _rng.randf() < 0.45:
				car.set_health(car.max_health * _rng.randf_range(0.35, 0.8), false)
			placed.append(p)
			break


## Half extents of `model` (a throwaway one, not added to the tree).
func _half_of(model: String) -> Vector3:
	var c: Car = game.new_vehicle(model)
	var h: Vector3 = c.half_extents
	c.free()
	return h


## True when a vehicle of `half` extents fits at `xf` (on the ground) clear of buildings, props, trees and vehicles.
func _spot_free(xf: Transform3D, half: Vector3) -> bool:
	if game._near_a_car(xf.origin, half.z + 1.0):
		return false
	var box := BoxShape3D.new()
	box.size = Vector3(half.x * 2.0 + 0.4, 2.0, half.z * 2.0 + 0.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	q.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 1.3)
	return game.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## The ground (global) at map `xy`: the ground map's height, refined by a ray from just above it (not a canopy or a
## bridge over it). y NAN where there is nothing.
func ground_at(xy: Vector2) -> Vector3:
	var h := Marks.ground(xy.x, xy.y)
	var y := WorldQuery.ground_y(game.get_world_3d(), xy.x, -xy.y, Layers.SOLID, h + 2.5)
	return Vector3(xy.x, y if not is_nan(y) else h, -xy.y)


func _process(delta: float) -> void:
	_shorten_cameras()
	if hosting:
		_run_mission(delta)
	if game.mode == "server" or arsenal == null:
		return
	_local_player(delta)
	_show_gear()
	if audio:
		audio.dread = _dread_here()
		audio.set_heartbeat(clampf(1.0 - health / 40.0, 0.0, 1.0) if not dead and not escaped else 0.0)


## The fog hides everything past CAMERA_FAR m: no camera draws further.
func _shorten_cameras() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.far > CAMERA_FAR:
		cam.far = CAMERA_FAR


## Host: the phases, the rescues, dawn, a wiped-out team.
func _run_mission(delta: float) -> void:
	var now := clock()
	match phase:
		WON, LOST:
			if game.mode == "server" and now - _ended_at > RESTART_AFTER:
				new_mission()
		BRIEFING:
			if now >= phase_until:
				_set_phase(RESCUE, 0.0)
				radio("Dragon 91 to all survivors: we are holding at %s. Bring everyone you find." % _evac_spot().get("name", "the field"))
		RESCUE, EXTRACTION:
			if evac:
				for i: int in survivors.rescue_in(evac.global_position, Evac.RADIUS):
					var s: Dictionary = survivors.list[i]
					radio("%s is aboard Dragon 91. %d of %d rescued." % [s["name"], survivors.count(Survivors.RESCUED),
							survivors.list.size()])
			if phase == RESCUE and survivors.count(Survivors.RESCUED) == survivors.list.size() and not survivors.list.is_empty():
				_start_extraction("Everyone is aboard!")
			if phase == EXTRACTION:
				_wave_t -= delta
				if _wave_t <= 0.0 and evac:
					_wave_t = WAVE_EVERY
					zombies.wave(evac.global_position, roundi(4 * difficulty()))
				if now >= phase_until:
					_lift_off("")
					return
			var left := dawn_at - now
			if phase == RESCUE:
				if left <= 300.0 and not _warned & 1:
					_warned |= 1
					radio("Dragon 91: five minutes to dawn. We leave at first light, with or without you.")
				elif left <= 60.0 and not _warned & 2:
					_warned |= 2
					radio("Dragon 91: one minute! Get to the helicopter!")
				if left <= 0.0:
					_lift_off("Dawn broke: Dragon 91 had to leave.")
					return
			_check_wipe()
			for peer: int in _respawning.keys():
				if now >= _respawning[peer]:
					_respawning.erase(peer)


func _set_phase(p: int, until: float) -> void:
	phase = p
	phase_until = until
	var row := _mission_row()
	_c_mission(row, false)
	send_all(self, "_c_mission", [row, false])


func _start_extraction(why: String) -> void:
	_wave_t = 4.0
	_set_phase(EXTRACTION, clock() + LIFT_WAIT)
	radio("%s Dragon 91 lifts off in %d seconds: everyone into the circle!" % [why, roundi(LIFT_WAIT)])
	send_all(self, "_c_stinger", [])
	_c_stinger()


@rpc("authority", "call_remote", "reliable")
func _c_stinger() -> void:
	if audio:
		audio.play("stinger", -2.0)


## Host: Dragon 91 leaves with whoever is in its circle (`why`: dawn forced it).
func _lift_off(why: String) -> void:
	var aboard := []
	for peer: int in vitals:
		var v: Dictionary = vitals[peer]
		if not v["flags"] & FLAG_DEAD and evac and evac.contains(v["pos"]):
			aboard.append(peer)
	var won := not aboard.is_empty()
	var rescued := survivors.count(Survivors.RESCUED)
	var total := survivors.list.size()
	var text := ""
	if won:
		text = "%s escaped the plateau with %d of %d survivors." % [", ".join(aboard.map(player_name)), rescued, total]
		if why != "":
			text = why + " " + text
	else:
		text = why if why != "" else "Dragon 91 left without anyone."
	_end(WON if won else LOST, text, aboard)


## Host: every player dead, no life left and nobody coming back: lost.
func _check_wipe() -> void:
	var peers := _player_peers()
	if peers.is_empty() or lives > 0 or not _respawning.is_empty():
		return
	for peer: int in peers:
		if not vitals.has(peer) or not vitals[peer]["flags"] & FLAG_DEAD:
			return
	_end(LOST, "Everyone is dead. The plateau belongs to the dead now.", [])


func _end(p: int, text: String, aboard: Array) -> void:
	phase = p
	result = text
	_ended_at = clock()
	var stats := "Zombies killed: %d · survivors rescued: %d of %d" % [zombies.kills, survivors.count(Survivors.RESCUED),
			survivors.list.size()]
	var row := _mission_row()
	_c_mission(row, false)
	send_all(self, "_c_mission", [row, false])
	_c_end(p == WON, text, aboard, stats)
	send_all(self, "_c_end", [p == WON, text, aboard, stats])


@rpc("authority", "call_remote", "reliable")
func _c_end(won: bool, text: String, aboard: Array, stats: String) -> void:
	if evac and won:
		evac.take_off()
	if game.mode == "server":
		print("Mission %s: %s %s" % ["won" if won else "lost", text, stats])
		return
	if me() in aboard:
		if game.driving:
			game.exit_car()
		elif game.riding:
			game.leave_ride()
		escaped = true
		_leave_world()
	var host_line := "Esc, then New mission, to play again." if hosting else "Waiting for the host to start a new mission."
	hud.show_title("YOU ESCAPED" if escaped else ("MISSION COMPLETE" if won else "MISSION FAILED"),
			"%s\n%s\n%s" % [text, stats, host_line], -1.0)
	if audio:
		audio.play("win" if won else "lose", -2.0)


## Host: something to tell everyone, over the radio (the squelch, a line in the chat and on the screen).
func radio(text: String) -> void:
	_c_radio(text)
	send_all(self, "_c_radio", [text])


@rpc("authority", "call_remote", "reliable")
func _c_radio(text: String) -> void:
	if game.mode == "server":
		print(text)
		return
	if hud:
		hud.subtitle("Radio · " + text, Color(1.0, 0.72, 0.45), 7.0)
	game.chat.add("Radio", Color(1.0, 0.6, 0.3), text)
	if audio:
		audio.play("radio", -6.0)


## Host: a line for everyone (a survivor sat in a vehicle...).
func say(_peer: int, text: String) -> void:
	_c_say(text)
	send_all(self, "_c_say", [text])


@rpc("authority", "call_remote", "reliable")
func _c_say(text: String) -> void:
	if game.mode != "server":
		game.toast(text)


## Host: player `peer` picked survivor i up for the first time.
func survivor_found(i: int, peer: int) -> void:
	_rescuers[peer] = int(_rescuers.get(peer, 0)) + 1
	var s: Dictionary = survivors.list[i]
	say(peer, "%s found %s!" % [player_name(peer), s["name"]])


func zombie_killed(peer: int) -> void:
	_kills[peer] = int(_kills.get(peer, 0)) + 1
	if peer == me() and hud:
		hud.hit_marker(true)
	elif peer != 0 and _player_peers().has(peer):
		send_to(peer, self, "_c_killed", [])


@rpc("authority", "call_remote", "reliable")
func _c_killed() -> void:
	if hud:
		hud.hit_marker(true)


func survivors_changed() -> void:
	pass


## 0 at nightfall .. 1 at dawn.
func dread_level() -> float:
	if night_length <= 0.0:
		return 1.0
	return clampf(1.0 - (dawn_at - clock()) / night_length, 0.0, 1.0)


## More players, more zombies.
func difficulty() -> float:
	return 1.0 + 0.35 * maxf(_player_peers().size() - 1, 0)


func phase_running() -> bool:
	return phase in [RESCUE, EXTRACTION]


# ---------------------------------------------------------------- players (host side)

## The players in the game (peer ids; not a dedicated server).
func _player_peers() -> Array:
	if not game.net.active:
		return [me()] if game.mode != "server" else []
	return game.net.players.keys()


## What the zombies may go for (zombies.gd), this physics frame: [{"peer", "pos", "car", "down", "dead", "light",
## "running"}].
func zombie_targets() -> Array:
	var f := Engine.get_physics_frames()
	if f == _targets_frame:
		return _targets
	_targets_frame = f
	_targets = []
	if phase not in [RESCUE, EXTRACTION, BRIEFING]:
		return _targets
	for peer: int in vitals:
		var v: Dictionary = vitals[peer]
		var flags: int = v["flags"]
		var car: Node = car_by_key(v["car"]) if v["car"] != "" else null
		if peer == me() and arsenal:            # our own player, as it is now
			flags = (FLAG_DOWN if downed else 0) | (FLAG_DEAD if dead else 0) | (FLAG_ESCAPED if escaped else 0) \
					| (flags & (FLAG_LIGHT | FLAG_RUN))
			var seat: Node = game.driving if game.driving else game.riding
			car = seat
		_targets.append({"peer": peer, "pos": car.global_position if car else peer_position(peer), "car": car,
				"down": flags & FLAG_DOWN != 0, "dead": flags & (FLAG_DEAD | FLAG_ESCAPED) != 0,
				"light": flags & FLAG_LIGHT != 0, "running": flags & FLAG_RUN != 0})
	return _targets


## Whether player `peer` stands (neither knocked down nor dead nor gone).
func is_up(peer: int) -> bool:
	if not vitals.has(peer):
		return peer == me() and not downed and not dead
	return vitals[peer]["flags"] & (FLAG_DOWN | FLAG_DEAD | FLAG_ESCAPED) == 0


## Where player `peer` is (global; the vehicle they are in), or null.
func peer_position(peer: int) -> Variant:
	if peer == me() and game.mode != "server":
		return _my_position()
	if vitals.has(peer):
		var car: Node = car_by_key(vitals[peer]["car"]) if vitals[peer]["car"] != "" else null
		return car.global_position if car else vitals[peer]["pos"]
	return null


## The body of player `peer` when it shows (a survivor rides on it), else null.
func body_of(peer: int) -> Node3D:
	if peer == me():
		var p: CharacterBody3D = game.player
		return p.get_node("Body") if p.visible and game.driving == null and game.riding == null else null
	var r: Node = game.net.avatar(peer)
	return r.body() if r and r.visible else null


func player_name(peer: int) -> String:
	return game.net.player_name(peer) if game.net.active else game.nickname


## Host: a zombie's blow on player `peer`, for `damage` from `from`.
func zombie_hit(peer: int, damage: float, from: Vector3) -> void:
	if peer == me() and game.mode != "server":
		_hurt(damage, from)
	else:
		send_to(peer, self, "_c_hurt", [damage, from])


@rpc("authority", "call_remote", "reliable")
func _c_hurt(damage: float, from: Vector3) -> void:
	_hurt(damage, from)


func _on_peer_left(peer: int) -> void:
	if hosting and vitals.has(peer):
		survivors.drop_from(peer, vitals[peer]["pos"])
	vitals.erase(peer)
	_respawning.erase(peer)
	if _gear.has(peer):
		if is_instance_valid(_gear[peer]):
			(_gear[peer] as Node).queue_free()
		_gear.erase(peer)


func player_registered(peer: int) -> void:
	if game.mode == "server" and game.net.players.size() == 1:
		new_mission()                       # the first one in: a fresh night (the last one went on empty)
		return
	send_to(peer, self, "_c_mission", [_mission_row(), true])
	send_to(peer, survivors, "_c_all", [survivors.rows_for_net()])
	send_to(peer, loot, "_c_all", [loot.rows_for_net()])
	lives += 1                              # one more player, one more life
	_set_phase(phase, phase_until)


# ---------------------------------------------------------------- states

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _h_state(pos: Vector3, yaw: float, pitch: float, hp: float, flags: int, weapon: String, car: String) -> void:
	var peer := sender()
	if not game.net.players.has(peer):
		return
	_store(peer, pos, yaw, pitch, hp, flags, weapon, car)
	for other: int in game.net.players:
		if other != peer and other != me():
			rpc_id(other, "_c_state", peer, pos, yaw, pitch, hp, flags, weapon, car)


@rpc("authority", "call_remote", "unreliable_ordered")
func _c_state(peer: int, pos: Vector3, yaw: float, pitch: float, hp: float, flags: int, weapon: String, car: String) -> void:
	_store(peer, pos, yaw, pitch, hp, flags, weapon, car)


func _store(peer: int, pos: Vector3, yaw: float, pitch: float, hp: float, flags: int, weapon: String, car: String) -> void:
	vitals[peer] = {"pos": pos, "yaw": yaw, "pitch": pitch, "health": hp, "flags": flags, "weapon": weapon, "car": car}


## Our state, now: in our own vitals, and to the host (which passes it on) or from the host to everyone.
func _send_state() -> void:
	var p: CharacterBody3D = game.player
	var flags := (FLAG_DOWN if downed else 0) | (FLAG_DEAD if dead else 0) | (FLAG_ESCAPED if escaped else 0) \
			| (FLAG_LIGHT if arsenal.light_on else 0) | (FLAG_CARRY if survivors.carried_by(me()) >= 0 else 0) \
			| (FLAG_RUN if p.active and Input.is_action_pressed("run") and p.velocity.length() > 5.0 else 0) \
			| (FLAG_AIM if arsenal.aiming else 0) | (FLAG_CAR if game.driving or game.riding else 0)
	var seat: Node = game.driving if game.driving else game.riding
	var car := car_key(seat) if seat else ""
	var pos := _my_position()
	var yaw: float = p.camera.global_rotation.y if p.camera else 0.0
	var pitch: float = p.view_pitch()
	_store(me(), pos, yaw, pitch, health, flags, arsenal.weapon, car)
	if not game.net.active:
		return
	if multiplayer.is_server():
		send_all(self, "_c_state", [me(), pos, yaw, pitch, health, flags, arsenal.weapon, car])
	else:
		rpc_id(1, "_h_state", pos, yaw, pitch, health, flags, arsenal.weapon, car)


func _my_position() -> Vector3:
	var seat: Node3D = game.driving if game.driving else game.riding
	return seat.global_position if seat else (game.player as Node3D).global_position


# ---------------------------------------------------------------- the local player

func _local_player(delta: float) -> void:
	var p: CharacterBody3D = game.player
	var carrying := survivors.carried_by(me()) >= 0
	var on_foot: bool = game.driving == null and game.riding == null and not game.flying
	p.speed_scale = DOWN_SPEED if downed else (CARRY_SPEED if carrying else (HEAL_SPEED if arsenal.heal_t > 0.0 else 1.0))
	p.can_run = not downed and not carrying
	p.can_jump = not downed and not carrying
	arsenal.one_hand = downed or carrying
	arsenal.active = on_foot and p.active and p.visible and not dead and not escaped and not game.ui_open() \
			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or assume_captured) and phase != BRIEFING
	arsenal.aiming = arsenal.active and Input.is_action_pressed("aim")
	if not arsenal.active:
		arsenal.trigger = false
	_state_t += delta
	if _state_t >= 1.0 / STATE_RATE:
		_state_t = 0.0
		_send_state()
	_noise_t -= delta
	if downed:
		bleed -= delta
		var medkit_held: bool = Input.is_action_pressed("heal") and arsenal.medkits > 0 and not game.ui_open()
		_self_t = _self_t + delta if medkit_held else 0.0
		if _self_t >= SELF_REVIVE_TIME and arsenal.use_medkit():
			_self_t = 0.0
			_get_up(SELF_REVIVE_HEALTH)
		var space_held: bool = Input.is_action_pressed("jump") and not game.ui_open()
		_give_up_t = _give_up_t + delta if space_held else 0.0
		if bleed <= 0.0 or _give_up_t >= GIVE_UP_TIME:
			_die()
	elif dead:
		_spectate_cam(delta)
		if respawn_at >= 0.0 and clock() >= respawn_at:
			_respawn()
	elif escaped:
		if evac:                            # watching Dragon 91 fly off with us
			var heli: Vector3 = evac.get_node("Helicopter").global_position
			var xf := Transform3D(Basis(), evac.global_position + Vector3(18.0, 6.0, 18.0)).looking_at(heli + Vector3.UP * 2.0)
			_spectator.global_transform = _spectator.global_transform.interpolate_with(xf, minf(delta * 2.0, 1.0))
	elif not escaped and on_foot and not game.ui_open():
		_revive_peer = _downed_near()
		_revive_t = _revive_t + delta if _revive_peer != 0 and Input.is_action_pressed("interact") else 0.0
		if _revive_t >= REVIVE_TIME:
			to_host(self, "_h_revive", [_revive_peer])
			_revive_t = 0.0
		_resupply()
		var calling := phase == RESCUE and evac != null and evac.contains(p.global_position) \
				and Input.is_action_pressed("interact") and _revive_peer == 0 and survivors.pickable_near(p.global_position) < 0
		_call_t = _call_t + delta if calling else 0.0
		if _call_t >= CALL_TIME:
			_call_t = 0.0
			to_host(self, "_h_call", [])


## In the safehouse's ring: the 9 mm rounds topped up to RESUPPLY, a bandage if none, every RESUPPLY_EVERY s at most
## (nobody runs dry for good).
func _resupply() -> void:
	var r: float = spots.get("safehouse", {}).get("r", 9.0)
	var here: Vector3 = (game.player as Node3D).global_position
	if here.distance_to(safehouse_pos) > r or clock() - _resupplied < RESUPPLY_EVERY:
		return
	var short := int(arsenal.reserve["ammo"]) < RESUPPLY or arsenal.bandages == 0
	if not short:
		return
	_resupplied = clock()
	arsenal.reserve["ammo"] = maxi(arsenal.reserve["ammo"], RESUPPLY)
	arsenal.bandages = maxi(arsenal.bandages, 1)
	game.toast("Resupplied at the safehouse")
	if audio:
		audio.play("pickup", -6.0)


## A downed teammate within REVIVE_RANGE (peer), or 0.
func _downed_near() -> int:
	var here: Vector3 = (game.player as Node3D).global_position
	for peer: int in vitals:
		if peer != me() and vitals[peer]["flags"] & FLAG_DOWN and here.distance_to(vitals[peer]["pos"]) < REVIVE_RANGE:
			return peer
	return 0


func _hurt(damage: float, from: Vector3) -> void:
	if dead or downed or escaped or arsenal == null or phase not in [RESCUE, EXTRACTION]:
		return
	health -= damage
	hud.hurt(damage)
	if audio:
		audio.play("hurt", -2.0, _rng.randf_range(0.9, 1.1))
	var p: CharacterBody3D = game.player
	p.kick(0.05, _rng.randf_range(-0.04, 0.04))
	var away: Vector3 = p.global_position - from
	p.push(Vector3(away.x, 0.0, away.z).normalized() * 2.0)
	if health <= 0.0:
		health = 0.0
		_go_down()


func _go_down() -> void:
	if game.driving:
		game.exit_car()
	elif game.riding:
		game.leave_ride()
	downed = true
	bleed = BLEED_TIME
	_self_t = 0.0
	_give_up_t = 0.0
	arsenal.heal_t = 0.0
	(game.player as CharacterBody3D).set_crawling(true)
	if arsenal.owned.has("pistol"):
		arsenal.select("pistol")
	to_host(self, "_h_vital", ["down", (game.player as Node3D).global_position])
	if audio:
		audio.play("stinger", -10.0)


func _get_up(hp: float) -> void:
	downed = false
	health = hp
	(game.player as CharacterBody3D).set_crawling(false)
	to_host(self, "_h_vital", ["up", (game.player as Node3D).global_position])


func _die() -> void:
	downed = false
	dead = true
	health = 0.0
	(game.player as CharacterBody3D).set_crawling(false)
	_leave_world()
	respawn_at = -1.0
	no_life = false
	_spectate = 0
	to_host(self, "_h_vital", ["dead", (game.player as Node3D).global_position])


## Out of the world (dead, or aboard the helicopter): the player hidden, the spectator's camera on.
func _leave_world() -> void:
	arsenal.light_on = false
	game.set_player_enabled(false)
	_spectator.global_transform = (game.player as CharacterBody3D).camera.global_transform
	_spectator.make_current()


func _respawn() -> void:
	dead = false
	respawn_at = -1.0
	health = MAX_HEALTH
	arsenal.reset(false)
	game.set_player_enabled(true)
	_to_safehouse()
	(game.player as CharacterBody3D).camera.make_current()
	to_host(self, "_h_vital", ["up", (game.player as Node3D).global_position])


## A new mission: alive, healed, a fresh kit, at the safehouse.
func _reset_player() -> void:
	var p: CharacterBody3D = game.player
	if game.driving:
		game.exit_car()
	elif game.riding:
		game.leave_ride()
	downed = false
	dead = false
	escaped = false
	no_life = false
	respawn_at = -1.0
	health = MAX_HEALTH
	if p.crawling:
		p.set_crawling(false)
	arsenal.reset(true)
	game.set_player_enabled(true)
	p.camera.make_current()
	_to_safehouse()


func _to_safehouse() -> void:
	var k := (me() * 7) % 5 - 2
	var at := safehouse_pos + Basis(Vector3.UP, safehouse_yaw) * Vector3(1.3 * k, 0.0, 0.0)
	var g := WorldQuery.ground_y(game.get_world_3d(), at.x, at.z, Layers.SOLID, at.y + 3.0)
	(game.player as CharacterBody3D).teleport(Vector3(at.x, (g if not is_nan(g) else at.y) + 0.1, at.z), safehouse_yaw)


## Host: a player's news (down, up, dead) and where they are.
@rpc("any_peer", "call_remote", "reliable")
func _h_vital(what: String, pos: Vector3) -> void:
	var peer := sender()
	match what:
		"down":
			survivors.drop_from(peer, pos)
			say(peer, "%s is down!" % player_name(peer))
		"dead":
			survivors.drop_from(peer, pos)
			if lives > 0 and phase_running():
				lives -= 1
				var at := clock() + RESPAWN_TIME
				_respawning[peer] = at
				send_to(peer, self, "_c_respawn", [at, lives])
				say(peer, "%s is dead. %d %s left." % [player_name(peer), lives, "life" if lives == 1 else "lives"])
			else:
				send_to(peer, self, "_c_respawn", [-1.0, lives])
				say(peer, "%s is dead." % player_name(peer))
			_set_phase(phase, phase_until)
	if vitals.has(peer):
		var v: Dictionary = vitals[peer]
		v["flags"] = (int(v["flags"]) & ~(FLAG_DOWN | FLAG_DEAD)) | (FLAG_DOWN if what == "down" else 0) \
				| (FLAG_DEAD if what == "dead" else 0)
		v["pos"] = pos


@rpc("authority", "call_remote", "reliable")
func _c_respawn(at: float, lives_left: int) -> void:
	lives = lives_left
	respawn_at = at
	no_life = at < 0.0


## Host: player `sender` helped `target` up.
@rpc("any_peer", "call_remote", "reliable")
func _h_revive(target: int) -> void:
	if not is_up(sender()) or not vitals.has(target) or not vitals[target]["flags"] & FLAG_DOWN:
		return
	say(target, "%s helped %s up" % [player_name(sender()), player_name(target)])
	send_to(target, self, "_c_revived", [])


@rpc("authority", "call_remote", "reliable")
func _c_revived() -> void:
	if downed:
		_get_up(REVIVE_HEALTH)


## Host: a player in the circle called Dragon 91 early.
@rpc("any_peer", "call_remote", "reliable")
func _h_call() -> void:
	if phase != RESCUE:
		return
	_start_extraction("%s called Dragon 91 with %d of %d survivors aboard." % [player_name(sender()),
			survivors.count(Survivors.RESCUED), survivors.list.size()])


## A bandage or medkit's health.
func heal(amount: float) -> void:
	if not downed and not dead:
		health = minf(health + amount, MAX_HEALTH)


## A supply taken (loot.gd: the host gave it to us).
func took(kind: String) -> void:
	if arsenal:
		var text := arsenal.give(kind)
		game.toast(text)
		if audio:
			audio.play("pickup", -6.0)


func wants(kind: String) -> bool:
	return arsenal != null and not dead and not downed and arsenal.wants(kind)


## Where the local player's feet are while they can pick things up (on foot, alive), else null.
func local_feet() -> Variant:
	if arsenal == null or dead or downed or escaped or game.driving or game.riding:
		return null
	return (game.player as Node3D).global_position


## Dead: watching a teammate who stands (from above and behind), else the safehouse.
func _spectate_cam(delta: float) -> void:
	var peers := vitals.keys().filter(func(q: int) -> bool: return q != me() and is_up(q))
	if not peers.has(_spectate):
		_spectate = peers[0] if not peers.is_empty() else 0
	var target: Vector3 = peer_position(_spectate) if _spectate != 0 else safehouse_pos
	var yaw: float = vitals[_spectate]["yaw"] if _spectate != 0 else safehouse_yaw
	var eye := target + Basis(Vector3.UP, yaw) * Vector3(0.0, 4.0, 7.0)
	var xf := Transform3D(Basis(), eye).looking_at(target + Vector3.UP * 1.2)
	_spectator.global_transform = _spectator.global_transform.interpolate_with(xf, minf(delta * 4.0, 1.0))


# ---------------------------------------------------------------- input

func handle_input(event: InputEvent) -> bool:
	if arsenal == null:
		return false
	var on_foot: bool = game.driving == null and game.riding == null
	if dead:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_next_spectated()
			return true
		return event.is_action_pressed("interact") or event.is_action_pressed("fire")
	if escaped:
		return event.is_action_pressed("interact")
	if on_foot:
		if event.is_action_pressed("fire") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or assume_captured):
			arsenal.press_fire()
			return true
		if event.is_action_released("fire"):
			arsenal.release_fire()
			return false
		for k in 4:
			if event.is_action_pressed("weapon_%d" % (k + 1)):
				arsenal.select(Arsenal.ORDER[k])
				return true
		if event.is_action_pressed("reload"):
			arsenal.reload()
			return true
		if event.is_action_pressed("heal"):
			if not downed:
				arsenal.heal(health, MAX_HEALTH)
			return true
		if event.is_action_pressed("drop"):
			_drop_key()
			return true
	if event.is_action_pressed("flashlight"):
		arsenal.toggle_light()
		return true
	if event.is_action_pressed("interact") and on_foot:
		if downed:
			return true
		var here: Vector3 = (game.player as Node3D).global_position
		if _downed_near() != 0:
			return true                     # held: helping them up (_local_player)
		var i := survivors.pickable_near(here)
		if i >= 0 and survivors.carried_by(me()) < 0:
			survivors.request_pick(i)
			return true
		if phase == RESCUE and evac and evac.contains(here):
			return true                     # held: calling the helicopter
	if downed and (event.is_action_pressed("jump") or event.is_action_pressed("exit_vehicle")):
		return true
	return false


## G: the survivor carried put down (or in the vehicle at hand, if it has room); none carried, one out of the vehicle at
## hand.
func _drop_key() -> void:
	if downed:
		return
	var car: Node = game.nearest_car()
	var carrying := survivors.carried_by(me()) >= 0
	if carrying:
		if car and survivors.in_car(car_key(car)) < Survivors.seats(car):
			survivors.request_load(car_key(car))
		else:
			if car and Survivors.seats(car) > 0:
				game.toast("No room left in the %s" % Car.display_name(car.model_name).to_lower())
			survivors.request_set_down((game.player as Node3D).global_position)
	elif car and survivors.in_car(car_key(car)) > 0:
		survivors.request_unload(car_key(car))


func _next_spectated() -> void:
	var peers := vitals.keys().filter(func(q: int) -> bool: return q != me() and is_up(q))
	if peers.is_empty():
		return
	var k := peers.find(_spectate)
	_spectate = peers[(k + 1) % peers.size()]


# ---------------------------------------------------------------- shots and hits

## A round of ours hit zombie `zid` (arsenal.gd): to the host.
func hit_zombie(zid: int, damage: float, dir: Vector3, melee: bool, _head: bool) -> void:
	if hud:
		hud.hit_marker(false)
	if hosting:
		zombies.hit(zid, damage, dir, me(), melee)
	else:
		rpc_id(1, "_h_hit", zid, damage, dir, melee)


@rpc("any_peer", "call_remote", "reliable")
func _h_hit(zid: int, damage: float, dir: Vector3, melee: bool) -> void:
	zombies.hit(zid, clampf(damage, 0.0, MAX_DAMAGE), dir, sender(), melee)


## A shot of ours at `pos`, heard `radius` m round: the zombies come.
func make_noise(pos: Vector3, radius: float) -> void:
	if _noise_t > 0.0:
		return
	_noise_t = NOISE_EVERY
	if hosting:
		zombies.noise(pos, radius)
	else:
		rpc_id(1, "_h_noise", pos, radius)


@rpc("any_peer", "call_remote", "unreliable")
func _h_noise(pos: Vector3, radius: float) -> void:
	zombies.noise(pos, clampf(radius, 0.0, 150.0))


## A shot of ours, for the others to see and hear.
func send_shot(weapon: String, from: Vector3, ends: PackedVector3Array) -> void:
	if not game.net.active:
		return
	if multiplayer.is_server():
		send_all(self, "_c_shot", [me(), weapon, from, ends])
	else:
		rpc_id(1, "_h_shot", weapon, from, ends)


@rpc("any_peer", "call_remote", "unreliable")
func _h_shot(weapon: String, from: Vector3, ends: PackedVector3Array) -> void:
	var peer := sender()
	for other: int in game.net.players:
		if other != peer and other != me():
			rpc_id(other, "_c_shot", peer, weapon, from, ends)
	_c_shot(peer, weapon, from, ends)


@rpc("authority", "call_remote", "unreliable")
func _c_shot(_peer: int, weapon: String, from: Vector3, ends: PackedVector3Array) -> void:
	if arsenal == null or not Arsenal.WEAPONS.has(weapon):
		return
	arsenal.tracers(from, ends)
	for e in ends:
		arsenal.impact(e, (from - e).normalized(), "dust")
	if audio:
		audio.play_at(Arsenal.WEAPONS[weapon].get("sound", "pistol"), from, 4.0, randf_range(0.95, 1.05), 25.0, 300.0)


## A round of an armed vehicle simulated here (the GAZ Tiger's roof gun) hit something: a zombie takes it.
func round_hit(collider: Object, _point: Vector3, velocity: Vector3) -> bool:
	if collider is Zombie:
		hit_zombie((collider as Zombie).zid, 40.0, velocity.normalized(), false, false)
		return true
	return false


# ---------------------------------------------------------------- the others' gear

## Each other player's flashlight beam and gun on their avatar, lying when knocked down.
func _show_gear() -> void:
	for peer: int in vitals:
		if peer == me():
			continue
		var r: Node = game.net.avatar(peer)
		if r == null:
			continue
		var v: Dictionary = vitals[peer]
		var gear: Node3D = _gear.get(peer)
		if gear == null or not is_instance_valid(gear):
			gear = _make_gear()
			r.body().add_child(gear)
			_gear[peer] = gear
		var flags: int = v["flags"]
		r.set_lying(flags & FLAG_DOWN != 0)
		var light: Node3D = gear.get_node("Light")
		light.visible = flags & FLAG_LIGHT != 0
		light.rotation.x = v["pitch"]
		for g: Node3D in gear.get_node("Guns").get_children():
			g.visible = String(g.name) == String(v["weapon"]).capitalize() and flags & FLAG_CAR == 0


func _make_gear() -> Node3D:
	var gear := Node3D.new()
	gear.name = "EscapeGear"
	var light := Node3D.new()
	light.name = "Light"
	light.position = Vector3(0.2, 1.45, -0.25)
	gear.add_child(light)
	var spot := SpotLight3D.new()
	spot.light_color = Arsenal.LIGHT_COLOR
	spot.light_energy = 6.0
	spot.spot_range = 36.0
	spot.spot_angle = 24.0
	spot.spot_angle_attenuation = 1.4
	light.add_child(spot)
	light.add_child(Arsenal.beam_cone(12.0, 2.4, 0.04))
	var guns := Node3D.new()
	guns.name = "Guns"
	gear.add_child(guns)
	for w: String in Arsenal.ORDER:
		var g := Arsenal.gun_model(w)
		g.position = Vector3(0.3, 1.12, -0.38)
		guns.add_child(g)
	return gear


# ---------------------------------------------------------------- the screen

func objective_text() -> String:
	var lines := PackedStringArray()
	var e: Dictionary = _evac_spot()
	lines.append("ESCAPE FROM PLATEAU")
	lines.append("Carry the survivors to Dragon 91 (%s)" % e.get("name", "?"))
	lines.append("Rescued %d / %d   ·   lives %d   ·   zombies about %d" % [survivors.count(Survivors.RESCUED),
			survivors.list.size(), lives, zombies.alive_count()])
	for s: Dictionary in survivors.list:
		var where := ""
		match int(s["state"]):
			Survivors.WAITING:
				where = "○ %s · hiding at %s" % [s["name"], s["place"]]
			Survivors.CARRIED:
				where = "● %s · carried by %s" % [s["name"], "you" if s["peer"] == me() else player_name(s["peer"])]
			Survivors.SET_DOWN:
				where = "○ %s · left on the ground" % s["name"]
			Survivors.IN_CAR:
				var car: Node = car_by_key(s["car"])
				where = "● %s · in the %s" % [s["name"], Car.display_name(car.model_name).to_lower() if car else "vehicle"]
			Survivors.RESCUED:
				where = "✔ %s · rescued" % s["name"]
		lines.append(where)
	return "\n".join(lines)


func timer_text() -> String:
	match phase:
		BRIEFING:
			return "Nightfall"
		RESCUE:
			return "Dawn in %s" % _clock_text(dawn_at - clock())
		EXTRACTION:
			return "DRAGON 91 LIFTS OFF IN %s · INTO THE CIRCLE!" % _clock_text(phase_until - clock())
	return ""


func _clock_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## What E (or G) would do here, for the screen.
func prompt_text() -> String:
	var k := _key_text
	if escaped:
		return ""
	if dead:
		if no_life:
			return "Dead · no lives left · click: watch another player"
		if respawn_at >= 0.0:
			return "Dead · back at the safehouse in %d s · click: watch another player" % maxi(ceili(respawn_at - clock()), 0)
		return "Dead"
	if downed:
		var t := "DOWN · crawl · pistol only · a teammate can help you up"
		if arsenal.medkits > 0:
			t += " · hold %s: get up with a medkit" % k.call("heal")
		return t + " · hold %s: give up" % k.call("jump")
	if game.driving or game.riding:
		var seat: Node = game.driving if game.driving else game.riding
		var n := survivors.in_car(car_key(seat))
		return "%d survivor%s aboard" % [n, "" if n == 1 else "s"] if n > 0 else ""
	var here: Vector3 = (game.player as Node3D).global_position
	if _downed_near() != 0:
		return "Hold %s: help %s up" % [k.call("interact"), player_name(_downed_near())]
	var carrying := survivors.carried_by(me())
	var car: Node = game.nearest_car()
	if carrying >= 0:
		var name: String = survivors.list[carrying]["name"]
		if car and Survivors.seats(car) > 0:
			return "%s: sit %s in the %s (%d/%d) · %s: drive with them" % [k.call("drop"), name,
					Car.display_name(car.model_name).to_lower(), survivors.in_car(car_key(car)), Survivors.seats(car),
					k.call("interact")]
		return "Carrying %s to Dragon 91 · %s: put them down" % [name, k.call("drop")]
	var i := survivors.pickable_near(here)
	if i >= 0:
		return "%s: pick %s up" % [k.call("interact"), survivors.list[i]["name"]]
	if car and survivors.in_car(car_key(car)) > 0:
		return "%s: take a survivor out of the %s" % [k.call("drop"), Car.display_name(car.model_name).to_lower()]
	if phase == RESCUE and evac and evac.contains(here):
		return "Hold %s: call Dragon 91 now (%d of %d survivors rescued)" % [k.call("interact"),
				survivors.count(Survivors.RESCUED), survivors.list.size()]
	return ""


## [what, 0..1] for the progress bar, or [].
func progress() -> Array:
	if _revive_t > 0.0:
		return ["Helping %s up…" % player_name(_revive_peer), _revive_t / REVIVE_TIME]
	if _self_t > 0.0:
		return ["Getting up…", _self_t / SELF_REVIVE_TIME]
	if _give_up_t > 0.0:
		return ["Giving up…", _give_up_t / GIVE_UP_TIME]
	if _call_t > 0.0:
		return ["Calling Dragon 91…", _call_t / CALL_TIME]
	if arsenal and arsenal.heal_t > 0.0:
		var total := Arsenal.MEDKIT_TIME if arsenal.heal_kind == "medkit" else Arsenal.BANDAGE_TIME
		return ["Medkit…" if arsenal.heal_kind == "medkit" else "Bandaging…", 1.0 - arsenal.heal_t / total]
	return []


## [position (global), colour, text] for the screen's markers.
func markers() -> Array:
	var out := []
	if escaped:
		return out
	var carrying := survivors.carried_by(me()) >= 0
	for s: Dictionary in survivors.list:
		if s["state"] in [Survivors.WAITING, Survivors.SET_DOWN]:
			out.append([(s["pos"] as Vector3) + Vector3.UP * 2.2, Color(0.45, 1.0, 0.5), s["name"]])
	if evac:
		out.append([evac.global_position + Vector3.UP * 4.0, Color(1.0, 0.6, 0.25) if not carrying \
				else Color(1.0, 0.85, 0.3), "Dragon 91"])
	var here: Vector3 = _my_position()
	if here.distance_to(safehouse_pos) > 40.0:
		out.append([safehouse_pos + Vector3.UP * 3.0, Color(0.45, 0.7, 1.0), "Safehouse"])
	for peer: int in vitals:
		if peer != me() and vitals[peer]["flags"] & FLAG_DOWN:
			out.append([(vitals[peer]["pos"] as Vector3) + Vector3.UP, Color(1.0, 0.3, 0.25), "✚ " + player_name(peer)])
	return out


## How close the zombies are, 0 .. 1 (the drone's swell).
func _dread_here() -> float:
	var here := _my_position()
	var near := 0.0
	for z: Zombie in zombies.zombies.values():
		if z.state != Zombie.DEAD:
			var d := here.distance_to(z.global_position)
			if d < 30.0:
				near += (30.0 - d) / 30.0
	return clampf(near / 4.0 + dread_level() * 0.3, 0.0, 1.0)


## The safehouse: a blue ring in front of Télécom Paris, its sign, a supply crate's light.
func _build_safehouse(sh: Dictionary) -> void:
	var ring := Marks.ring(sh["x"], sh["y"], float(sh.get("r", 9.0)), 0.6, Color(0.35, 0.65, 1.0), 1, true)
	add_child(ring)
	var label := Marks.sign_text(sh["x"], sh["y"], 5.5, "SAFEHOUSE", 48, Color(0.6, 0.8, 1.0))
	label.pixel_size = 0.006
	label.visibility_range_end = 90.0
	add_child(label)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.6, 0.75, 1.0)
	lamp.light_energy = 2.5
	lamp.omni_range = 14.0
	lamp.position = safehouse_pos + Vector3.UP * 3.0
	add_child(lamp)


# ---------------------------------------------------------------- messages

func clock() -> float:
	return game.net.clock()


func me() -> int:
	return game.net.me()


func sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else me()


func _key_text(action: String) -> String:
	var s := get_node_or_null("/root/Settings")
	return s.key_text(action) if s else action


## Calls `method` of `node` (this mode or one of its parts) on every welcomed player but us (host side).
func send_all(node: Node, method: StringName, args: Array) -> void:
	if not game.net.active:
		return
	for peer: int in game.net.players:
		if peer != me():
			node.callv("rpc_id", [peer, method] + args)


## Calls `method` of `node` on player `peer` (here when it is us).
func send_to(peer: int, node: Node, method: StringName, args: Array) -> void:
	if peer == me() or not game.net.active:
		if game.mode != "server":
			node.callv(method, args)
	elif game.net.players.has(peer):
		node.callv("rpc_id", [peer, method] + args)


## Calls `method` of `node` on the host (here when we host or play solo).
func to_host(node: Node, method: StringName, args: Array) -> void:
	if not game.net.active or multiplayer.is_server():
		node.callv(method, args)
	else:
		node.callv("rpc_id", [1, method] + args)


## A vehicle's key for the survivors in it: its network id, or (solo) its instance.
func car_key(car: Node) -> String:
	return car.net_id if car.net_id != "" else "local:%d" % car.get_instance_id()


func car_by_key(key: String) -> Node:
	if key == "":
		return null
	if not key.begins_with("local:"):
		return game.net.cars.get(key)
	for car: Node in game.cars:
		if is_instance_valid(car) and "local:%d" % car.get_instance_id() == key:
			return car
	return null


## The peer driving `car` (0: nobody).
func driver_of(car: Node) -> int:
	if game.net.active:
		return game.net.driver_of.get(car.net_id, 0)
	return me() if game.driving == car else 0


# ---------------------------------------------------------------- help

func walk_help(k: Callable) -> String:
	return ("ESCAPE · click: mouse · %s move · %s run · %s jump · left click fire · %s (held) aim · %s-%s weapons · " % [
			_keys(k, ["move_forward", "move_left", "move_back", "move_right"]), k.call("run"), k.call("jump"),
			k.call("aim"), k.call("weapon_1"), k.call("weapon_4")]) + ("%s reload · %s flashlight\n" % [k.call("reload"),
			k.call("flashlight")]) + ("%s bandage/medkit · %s pick up a survivor, help up a teammate, drive · " % [
			k.call("heal"), k.call("interact")]) + ("%s survivor down / into a vehicle / out of one · %s view" % [
			k.call("drop"), k.call("toggle_view")])


func extra_help(k: Callable) -> String:
	if game.driving or game.riding:
		return "%s flashlight · zombies batter the vehicle, then you once it is broken · run them over" % k.call("flashlight")
	return ""


static func _keys(k: Callable, actions: Array) -> String:
	var names := PackedStringArray()
	for a: String in actions:
		names.append(k.call(a))
	return "".join(names) if names.size() == 4 and names[0].length() == 1 else "/".join(names)
