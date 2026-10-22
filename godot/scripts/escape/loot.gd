extends Node3D
## Supplies lying about in Escape from Plateau (Main/Mode/Loot on every peer): small crates and weapons, floating and
## turning slowly, a glowing band in their colour and their name above when near. Walking over one takes it, if the
## player has room for it (arsenal.gd wants): ammunition, shotgun shells, bandages, medkits, flashlight batteries, the
## shotgun and the submachine gun (shells or rounds instead once owned).
## The host scatters them at the start of a mission (scatter): round each survivor's hideout, on the doorsteps of the
## campus's named buildings (world/escape.json "caches"), the weapons not too near the safehouse. Who takes what is
## the host's call (_h_take): the first to ask gets it, everyone sees it go.

## kind -> name, colour, chance among the caches' supplies
const KINDS := {
	"ammo": {"label": "Ammunition", "color": Color(1.0, 0.78, 0.25), "weight": 30.0},
	"shells": {"label": "Shotgun shells", "color": Color(0.95, 0.35, 0.2), "weight": 14.0},
	"bandage": {"label": "Bandage", "color": Color(0.95, 0.95, 0.92), "weight": 20.0},
	"medkit": {"label": "Medkit", "color": Color(1.0, 0.2, 0.2), "weight": 8.0},
	"battery": {"label": "Battery", "color": Color(0.35, 0.8, 1.0), "weight": 10.0},
	"shotgun": {"label": "Shotgun", "color": Color(0.75, 0.5, 0.28), "weight": 6.0},
	"smg": {"label": "Submachine gun", "color": Color(0.6, 0.65, 0.75), "weight": 5.0},
}
const TAKE_RANGE := 1.5                     # m
const CACHES := 46                          # supplies on the doorsteps per mission
const PER_HIDEOUT := 3                      # round each survivor's hideout
const WEAPONS_AWAY := 160.0                 # m from the safehouse at least, the shotguns and submachine guns
const LABEL_RANGE := 12.0

var mode: Node                              # escape_mode.gd
var items := {}                             # id -> {"kind", "pos" (global), "node"}

var _asked := {}                            # id -> when we last asked for it (our clock)
var _next_id := 1


## Host: a mission's supplies: PER_HIDEOUT round each of `hideouts` (global), CACHES among `caches` (map x, y), two
## shotguns and two submachine guns among them at least, away from `safehouse` (global).
func scatter(rng: RandomNumberGenerator, hideouts: Array, caches: Array, safehouse: Vector3) -> void:
	_clear()
	var rows := []
	for h: Vector3 in hideouts:
		for k in PER_HIDEOUT:
			var kind: String = ["ammo", "bandage", _pick(rng)][k]
			var a := rng.randf() * TAU
			var p := _ground(Vector2(h.x + cos(a) * rng.randf_range(2.0, 6.0), -h.z + sin(a) * rng.randf_range(2.0, 6.0)))
			if not is_nan(p.y):
				rows.append([_next_id, kind, p])
				_next_id += 1
	var pool := caches.duplicate()
	for i in range(pool.size() - 1, 0, -1):         # shuffled
		var j := rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var guns := ["shotgun", "smg", "shotgun", "smg"]
	var placed := 0
	for c: Array in pool:
		if placed >= CACHES:
			break
		var p := _ground(Vector2(c[0], c[1]))
		if is_nan(p.y):
			continue
		var kind := _pick(rng)
		var far := Vector2(p.x - safehouse.x, p.z - safehouse.z).length() > WEAPONS_AWAY
		if kind in ["shotgun", "smg"] and not far:
			kind = "ammo"
		elif not guns.is_empty() and far:
			kind = guns.pop_back()
		elif kind in guns:
			guns.erase(kind)
		rows.append([_next_id, kind, p])
		_next_id += 1
		placed += 1
	for r: Array in rows:
		_add(r[0], r[1], r[2])
	mode.send_all(self, "_c_all", [rows])


## Host: one supply of `kind` at `pos` (global): what a dead player leaves, the safehouse's.
func drop(kind: String, pos: Vector3) -> void:
	var id := _next_id
	_next_id += 1
	_add(id, kind, pos)
	mode.send_all(self, "_c_add", [id, kind, pos])


static func _pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in KINDS:
		total += KINDS[k]["weight"]
	var r := rng.randf() * total
	for k: String in KINDS:
		r -= KINDS[k]["weight"]
		if r <= 0.0:
			return k
	return "ammo"


## The ground (global) at map `xy`, a little over it (escape_mode.gd ground_at).
func _ground(xy: Vector2) -> Vector3:
	return mode.ground_at(xy) + Vector3.UP * 0.05


## Every supply, for a newcomer.
func rows_for_net() -> Array:
	var out := []
	for id: int in items:
		out.append([id, items[id]["kind"], items[id]["pos"]])
	return out


@rpc("authority", "call_remote", "reliable")
func _c_all(rows: Array) -> void:
	_clear()
	for r: Array in rows:
		_add(r[0], r[1], r[2])


@rpc("authority", "call_remote", "reliable")
func _c_add(id: int, kind: String, pos: Vector3) -> void:
	_add(id, kind, pos)


func _clear() -> void:
	for id: int in items:
		(items[id]["node"] as Node).queue_free()
	items.clear()
	_asked.clear()


func _add(id: int, kind: String, pos: Vector3) -> void:
	if items.has(id) or not KINDS.has(kind):
		return
	var node := _model(kind)
	add_child(node)
	node.global_position = pos
	items[id] = {"kind": kind, "pos": pos, "node": node}


@rpc("any_peer", "call_remote", "reliable")
func _h_take(id: int) -> void:
	if not items.has(id):
		return
	var peer: int = mode.sender()
	var kind: String = items[id]["kind"]
	_remove(id)
	mode.send_all(self, "_c_taken", [id, peer, kind])
	if peer == mode.me():
		mode.took(kind)
	else:
		mode.send_to(peer, self, "_c_yours", [kind])


@rpc("authority", "call_remote", "reliable")
func _c_taken(id: int, _peer: int, _kind: String) -> void:
	_remove(id)


@rpc("authority", "call_remote", "reliable")
func _c_yours(kind: String) -> void:
	mode.took(kind)


func _remove(id: int) -> void:
	if items.has(id):
		(items[id]["node"] as Node).queue_free()
		items.erase(id)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var me: Variant = mode.local_feet()
	var cam := get_viewport().get_camera_3d()
	for id: int in items:
		var it: Dictionary = items[id]
		var node: Node3D = it["node"]
		var model: Node3D = node.get_node("Model")
		model.rotation.y += delta * 0.8
		model.position.y = 0.35 + 0.06 * sin(t * 2.0 + id)
		if cam:
			(node.get_node("Label") as Label3D).visible = cam.global_position.distance_to(it["pos"]) < LABEL_RANGE
		if me != null and (me as Vector3).distance_to(it["pos"]) < TAKE_RANGE and mode.wants(it["kind"]) \
				and t - float(_asked.get(id, -10.0)) > 1.0:
			_asked[id] = t
			mode.to_host(self, "_h_take", [id])


## A supply's look: a crate (a long case for the weapons) with a glowing band, its name above.
func _model(kind: String) -> Node3D:
	var root := Node3D.new()
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var c: Color = KINDS[kind]["color"]
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.22, 0.24, 0.2) if kind not in ["bandage", "medkit"] else Color(0.92, 0.92, 0.9)
	body.roughness = 0.8
	var band := StandardMaterial3D.new()
	band.albedo_color = c
	band.emission_enabled = true
	band.emission = c
	band.emission_energy_multiplier = 1.6
	var long := kind in ["shotgun", "smg"]
	var size := Vector3(0.95, 0.14, 0.26) if long else Vector3(0.42, 0.26, 0.3)
	for part: Array in [[size, body], [Vector3(size.x * 1.02, size.y * 0.3, size.z * 1.02), band]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.material_override = part[1]
		mi.visibility_range_end = 70.0
		model.add_child(mi)
	if kind == "medkit" or kind == "bandage":          # a red cross on top
		for s: Vector3 in [Vector3(0.18, 0.02, 0.06), Vector3(0.06, 0.02, 0.18)]:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = s
			mi.mesh = box
			mi.material_override = band if kind == "medkit" else _red()
			mi.position.y = size.y * 0.5 + 0.01
			model.add_child(mi)
	var label := Label3D.new()
	label.name = "Label"
	label.text = KINDS[kind]["label"]
	label.position.y = 0.9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 24
	label.outline_size = 7
	label.modulate = c.lightened(0.3)
	label.visible = false
	root.add_child(label)
	return root


static func _red() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.1, 0.1)
	return m
