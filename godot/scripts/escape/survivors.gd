extends Node3D
## The survivors of Escape from Plateau (Main/Mode/Survivors on every peer): people hiding in front of the doors of the
## plateau's buildings (world/escape.json, tools/escape/escape_spots.py; the car salesman inside his showroom), a
## lantern beside them. Too hurt or too scared to walk, they are carried:
## - E next to one picks them up onto the player's shoulders (not while carrying another, nor knocked down); the player
##   walks slower, cannot run or jump, and has a hand free for the pistol only;
## - G puts them down; G next to a vehicle sits them in it (seats(): a car takes 3, a van or truck 6, a bus 14, not the
##   planes, the horse or the jet-ski), and G next to a vehicle with survivors in it takes one out;
## - a carrier knocked down (or leaving the game) drops them where they are; a carrier in a vehicle keeps them;
## - carried into the rescue helicopter's circle, or brought there in a vehicle, they are rescued (escape_mode.gd).
## The host keeps their states (WAITING, CARRIED by a peer, SET_DOWN on the ground, IN_CAR, RESCUED) and sends every
## change to everyone; the others ask it (_h_*).

const Layers = preload("res://scripts/physics_layers.gd")
const Car = preload("res://scripts/car.gd")

enum { WAITING, CARRIED, SET_DOWN, IN_CAR, RESCUED }

const PICK_RANGE := 2.3                     # m from a survivor to pick them up
const WAVE_RANGE := 14.0                    # m: they wave at a player this near
const LANTERN := Color(1.0, 0.72, 0.38)
const SKIN := [Color(0.95, 0.78, 0.64), Color(0.78, 0.58, 0.42), Color(0.52, 0.36, 0.25), Color(0.9, 0.72, 0.58)]
const CLOTHES := [Color(0.2, 0.45, 0.75), Color(0.85, 0.75, 0.25), Color(0.75, 0.3, 0.45), Color(0.3, 0.6, 0.4),
		Color(0.9, 0.9, 0.88), Color(0.95, 0.5, 0.2)]

var mode: Node                              # escape_mode.gd
## per survivor: {"id", "who", "name", "line", "place", "state", "peer", "pos" (global), "car" (car_key), "node"}
var list: Array = []


func _process(delta: float) -> void:
	for s: Dictionary in list:
		_show(s, delta)


## Host: a new round's survivors, from escape.json rows with their "pos" (global) worked out.
func set_round(rows: Array) -> void:
	_clear()
	for r: Dictionary in rows:
		_add(r["id"], r["who"], r["line"], r["place"], r["pos"], WAITING, 0, "", r.get("yaw", 0.0))
	mode.send_all(self, "_c_all", [rows_for_net()])


## The survivors and their states for a newcomer (or a new round).
func rows_for_net() -> Array:
	var out := []
	for s: Dictionary in list:
		out.append([s["id"], s["who"], s["line"], s["place"], s["pos"], s["state"], s["peer"], s["car"],
				(s["node"] as Node3D).rotation.y])
	return out


@rpc("authority", "call_remote", "reliable")
func _c_all(rows: Array) -> void:
	_clear()
	for r: Array in rows:
		_add(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8])


func _clear() -> void:
	for s: Dictionary in list:
		(s["node"] as Node).queue_free()
	list.clear()


func _add(id: String, who: String, line: String, place: String, pos: Vector3, state: int, peer: int, car: String,
		yaw: float) -> void:
	var s := {"id": id, "who": who, "name": who.get_slice(",", 0), "line": line, "place": place, "state": state,
			"peer": peer, "pos": pos, "car": car}
	s["node"] = _figure(list.size(), s["name"])
	add_child(s["node"])
	(s["node"] as Node3D).global_position = pos
	(s["node"] as Node3D).rotation.y = yaw
	list.append(s)


func count(state: int) -> int:
	return list.filter(func(s: Dictionary) -> bool: return s["state"] == state).size()


## The survivor peer `peer` carries (index), or -1.
func carried_by(peer: int) -> int:
	for i in list.size():
		if list[i]["state"] == CARRIED and list[i]["peer"] == peer:
			return i
	return -1


## The survivor waiting or set down within PICK_RANGE of `p` (global), nearest first; -1 when none.
func pickable_near(p: Vector3) -> int:
	var best := -1
	var best_d := PICK_RANGE
	for i in list.size():
		var s: Dictionary = list[i]
		if s["state"] in [WAITING, SET_DOWN]:
			var d := p.distance_to(s["pos"])
			if d < best_d:
				best = i
				best_d = d
	return best


## How many survivors vehicle `car` takes.
static func seats(car: Node) -> int:
	var spec: Dictionary = Car.SPECS.get(car.model_name, {})
	if spec.get("plane", false) or spec.get("horse", false) or spec.get("jet_ski", false):
		return 0
	if (car.interior as AABB).size != Vector3.ZERO:
		return 14
	return 6 if (car.half_extents as Vector3).z > 3.0 else 3


## How many survivors sit in the vehicle of key `key` (escape_mode.gd car_key).
func in_car(key: String) -> int:
	return list.filter(func(s: Dictionary) -> bool: return s["state"] == IN_CAR and s["car"] == key).size()


# ---------------------------------------------------------------- requests (any peer -> host)

func request_pick(i: int) -> void:
	mode.to_host(self, "_h_pick", [i])


func request_set_down(pos: Vector3) -> void:
	mode.to_host(self, "_h_set_down", [pos])


func request_load(key: String) -> void:
	mode.to_host(self, "_h_load", [key])


func request_unload(key: String) -> void:
	mode.to_host(self, "_h_unload", [key])


@rpc("any_peer", "call_remote", "reliable")
func _h_pick(i: int) -> void:
	var peer: int = mode.sender()
	if i < 0 or i >= list.size() or list[i]["state"] not in [WAITING, SET_DOWN] or carried_by(peer) >= 0 \
			or not mode.is_up(peer):
		return
	var first: bool = list[i]["state"] == WAITING
	set_state(i, CARRIED, peer, list[i]["pos"], "")
	if first:
		mode.survivor_found(i, peer)


@rpc("any_peer", "call_remote", "reliable")
func _h_set_down(pos: Vector3) -> void:
	var i := carried_by(mode.sender())
	if i >= 0:
		set_state(i, SET_DOWN, 0, pos, "")


@rpc("any_peer", "call_remote", "reliable")
func _h_load(key: String) -> void:
	var peer: int = mode.sender()
	var i := carried_by(peer)
	var car: Node = mode.car_by_key(key)
	if i < 0 or car == null or in_car(key) >= seats(car):
		return
	set_state(i, IN_CAR, 0, car.global_position, key)
	mode.say(peer, "%s sits %s in the %s" % [mode.player_name(peer), list[i]["name"], Car.display_name(car.model_name).to_lower()])


@rpc("any_peer", "call_remote", "reliable")
func _h_unload(key: String) -> void:
	var peer: int = mode.sender()
	if carried_by(peer) >= 0 or not mode.is_up(peer):
		return
	for i in list.size():
		if list[i]["state"] == IN_CAR and list[i]["car"] == key:
			set_state(i, CARRIED, peer, list[i]["pos"], "")
			return


## Host: survivor i's new state, sent to everyone.
func set_state(i: int, state: int, peer: int, pos: Vector3, car: String) -> void:
	_apply(i, state, peer, pos, car)
	mode.send_all(self, "_c_set", [i, state, peer, pos, car])


@rpc("authority", "call_remote", "reliable")
func _c_set(i: int, state: int, peer: int, pos: Vector3, car: String) -> void:
	_apply(i, state, peer, pos, car)


func _apply(i: int, state: int, peer: int, pos: Vector3, car: String) -> void:
	if i < 0 or i >= list.size():
		return
	var s: Dictionary = list[i]
	var was: int = s["state"]
	s["state"] = state
	s["peer"] = peer
	s["pos"] = pos
	s["car"] = car
	if state == CARRIED and peer == mode.me() and mode.audio:
		mode.audio.play("pickup", -4.0)
		if was == WAITING and mode.hud:
			mode.hud.say_line(s["name"], s["line"])
	mode.survivors_changed()


## Host: what player `peer` carried, set down at `pos` (they were knocked down, or left).
func drop_from(peer: int, pos: Vector3) -> void:
	var i := carried_by(peer)
	if i >= 0:
		set_state(i, SET_DOWN, 0, pos, "")


## Host: the survivors in vehicle `key` set down beside it (it is gone).
func unload_all(key: String, pos: Vector3) -> void:
	for i in list.size():
		if list[i]["state"] == IN_CAR and list[i]["car"] == key:
			set_state(i, SET_DOWN, 0, pos + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), "")


## Host: those carried into, or brought in a vehicle into, the circle of `radius` m round `centre`: rescued. Returns
## their indices.
func rescue_in(centre: Vector3, radius: float) -> Array:
	var out := []
	for i in list.size():
		var s: Dictionary = list[i]
		var p: Variant = null
		if s["state"] == CARRIED:
			p = mode.peer_position(s["peer"])
		elif s["state"] == IN_CAR:
			var car: Node = mode.car_by_key(s["car"])
			p = car.global_position if car else null
		if p != null and Vector2((p as Vector3).x - centre.x, (p as Vector3).z - centre.z).length() < radius \
				and absf((p as Vector3).y - centre.y) < 6.0:
			set_state(i, RESCUED, s["peer"], centre, "")
			out.append(i)
	return out


# ---------------------------------------------------------------- looks

func _show(s: Dictionary, delta: float) -> void:
	var node: Node3D = s["node"]
	var state: int = s["state"]
	var lantern: Node3D = node.get_node("Lantern")
	lantern.visible = state == WAITING
	if state in [IN_CAR, RESCUED]:
		node.visible = false
		return
	if state == CARRIED:
		var body: Node3D = mode.body_of(s["peer"])
		node.visible = body != null and body.is_visible_in_tree()
		if node.visible:
			# over the shoulders, lying across them face down, the head on the carrier's right, the hips on the shoulder
			node.global_transform = body.global_transform * Transform3D(Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP),
					Vector3(-0.9, 1.5, 0.05))
			s["pos"] = body.global_position
		_pose(node, "carried", delta)
		return
	node.visible = true
	node.global_transform = Transform3D(node.global_basis.orthonormalized(), s["pos"])
	node.rotation.x = 0.0
	node.rotation.z = 0.0
	var waving := false
	var cam := get_viewport().get_camera_3d()
	if state == WAITING and cam:
		var me: Variant = mode.peer_position(mode.me())
		if me != null and (me as Vector3).distance_to(s["pos"]) < WAVE_RANGE:
			waving = true
			var d: Vector3 = (me as Vector3) - (s["pos"] as Vector3)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-d.x, -d.z), minf(delta * 3.0, 1.0))
	_pose(node, "wave" if waving else "sit", delta)
	var light := lantern.get_node("Light") as OmniLight3D
	light.light_energy = 1.4 + 0.25 * sin(Time.get_ticks_msec() / 90.0) * sin(Time.get_ticks_msec() / 37.0)


## Poses a figure: sitting (huddled on the ground), waving, or carried (limp).
func _pose(node: Node3D, how: String, _delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var rig: Node3D = node.get_node("Rig")
	var legs := [rig.get_node("LegL"), rig.get_node("LegR")]
	var arms := [rig.get_node("Hips/ArmL"), rig.get_node("Hips/ArmR")]
	var hips: Node3D = rig.get_node("Hips")
	match how:
		"sit":
			rig.position.y = -0.48
			hips.rotation.x = 0.35 + 0.03 * sin(t * 1.3)
			for l: Node3D in legs:
				l.rotation.x = -1.45
			(arms[0] as Node3D).rotation = Vector3(-0.9, 0.0, -0.4)
			(arms[1] as Node3D).rotation = Vector3(-0.9, 0.0, 0.4)
		"wave":
			rig.position.y = -0.48
			hips.rotation.x = 0.1
			for l: Node3D in legs:
				l.rotation.x = -1.45
			(arms[0] as Node3D).rotation = Vector3(-0.6, 0.0, -0.3)
			(arms[1] as Node3D).rotation = Vector3(0.0, 0.0, 2.6 + 0.4 * sin(t * 9.0))
		"carried":
			rig.position.y = 0.0
			hips.rotation.x = 0.0
			(legs[0] as Node3D).rotation.x = 0.15
			(legs[1] as Node3D).rotation.x = -0.1
			(arms[0] as Node3D).rotation = Vector3(0.2 * sin(t * 4.0), 0.0, 0.0)
			(arms[1] as Node3D).rotation = Vector3(-0.2 * sin(t * 4.0), 0.0, 0.0)


## A survivor figure: a toy person in bright clothes (the zombies' make, scripts/escape/zombie.gd, but alive), its name
## above, a lantern beside.
func _figure(k: int, label_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Survivor%d" % k
	var rig := Node3D.new()
	rig.name = "Rig"
	root.add_child(rig)
	var skin := _mat(SKIN[k % SKIN.size()])
	var shirt := _mat(CLOTHES[k % CLOTHES.size()])
	var trousers := _mat(Color(0.2, 0.22, 0.3))
	for side: Array in [["LegL", -1.0], ["LegR", 1.0]]:
		var hip := Node3D.new()
		hip.name = side[0]
		hip.position = Vector3(0.12 * side[1], 0.9, 0.0)
		rig.add_child(hip)
		_part(hip, _capsule(0.1, 0.9), trousers, Vector3(0.0, -0.44, 0.0))
	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0.0, 0.9, 0.0)
	rig.add_child(hips)
	_part(hips, _capsule(0.24, 0.8), shirt, Vector3(0.0, 0.33, 0.0))
	_part(hips, _sphere(0.17), skin, Vector3(0.0, 0.84, -0.02))
	_part(hips, _sphere(0.175), _mat(Color(0.25, 0.17, 0.1)), Vector3(0.0, 0.9, 0.03))     # hair
	for side: Array in [["ArmL", -1.0], ["ArmR", 1.0]]:
		var sh := Node3D.new()
		sh.name = side[0]
		sh.position = Vector3(0.29 * side[1], 0.6, 0.0)
		hips.add_child(sh)
		_part(sh, _capsule(0.075, 0.66), shirt, Vector3(0.0, -0.3, 0.0))
		_part(sh, _sphere(0.075), skin, Vector3(0.0, -0.64, 0.0))
	var label := Label3D.new()
	label.text = label_text
	label.position = Vector3(0.0, 1.75, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.001
	label.font_size = 26
	label.outline_size = 8
	label.modulate = Color(0.6, 1.0, 0.6)
	label.no_depth_test = false
	label.visibility_range_end = 30.0
	root.add_child(label)
	var lantern := Node3D.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.65, 0.0, 0.35)
	root.add_child(lantern)
	_part(lantern, _box(Vector3(0.18, 0.26, 0.18)), _mat(Color(0.15, 0.15, 0.15)), Vector3(0.0, 0.13, 0.0))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = LANTERN
	glass.emission_enabled = true
	glass.emission = LANTERN
	glass.emission_energy_multiplier = 3.0
	_part(lantern, _box(Vector3(0.12, 0.14, 0.12)), glass, Vector3(0.0, 0.15, 0.0))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = LANTERN
	light.light_energy = 1.4
	light.omni_range = 7.0
	light.position = Vector3(0.0, 0.4, 0.0)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 80.0
	light.distance_fade_length = 20.0
	lantern.add_child(light)
	return root


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 6
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
