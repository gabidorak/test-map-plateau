extends RefCounted
## How one kind of weapon fires and looks: a script of scripts/items/weapons/ extends this one, data/items.json names it
## (`behaviour`) and scripts/items/items.gd BEHAVIOURS lists it. Its numbers (range, reload, stun...) are the item's row
## (`stats`); the inventory, the reloads and the host's checks are items.gd's, the stuns scripts/people/people.gd's.
## - model(): its toy model, along -Z, a "Muzzle" marker at the barrel's end (in the hand, first and third person).
## - fire(): our shot, from the muzzle toward the point aimed at: what it hit at once (a hitscan weapon), or the
##   projectile it launched (it reports its hit to items.gd later: net_shot.gd).
## - show_shot(): another player's shot, for show.

const ItemDb = preload("res://scripts/items/item_db.gd")
const Layers = preload("res://scripts/physics_layers.gd")

## What a shot stops at besides people: the ground, buildings, trees, street furniture, vehicles.
const WORLD_MASK := Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.VEHICLE_INSIDE
const PERSON_RADIUS := 0.42                 # m, a person's capsule for shots (a little generous)
const PERSON_HEIGHT := 1.8

var kind := ""
var stats := {}

static var _shared := {}


func setup(item_kind: String) -> void:
	kind = item_kind
	stats = ItemDb.get_item(item_kind)


func stat(key: String, fallback := 0.0) -> float:
	return float(stats.get(key, fallback))


func model() -> Node3D:
	var root := Node3D.new()
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	tip.position = Vector3(0.0, 0.0, -0.2)
	root.add_child(tip)
	return root


## Our shot from `muzzle` toward `aim` (global), `hands` (hands.gd) firing it as shot `no`: {"target": person id hit
## ("" none), "end": where it stopped} for a hitscan weapon; a projectile weapon launches it and returns {"end": aim}.
func fire(_hands: Node3D, _muzzle: Vector3, aim: Vector3, _no: int) -> Dictionary:
	return {"target": "", "end": aim}


## Another player's shot for show, under `parent` (Main/Items): person `shooter`'s, from `from` toward `to`, hitting
## person `target` ("" none).
func show_shot(_parent: Node, _shooter: String, _from: Vector3, _to: Vector3, _target: String) -> void:
	pass


## The first person standing on the segment `from` -> `to` (people.gd up_people), not `exclude`, and before the world:
## {"target": id, "point"} or {"target": "", "point": where it stops (the world, or `to`)}.
static func trace(space: PhysicsDirectSpaceState3D, people: Array, from: Vector3, to: Vector3, exclude: String) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := space.intersect_ray(q)
	var stop: Vector3 = hit["position"] if hit else to
	var stop_s := from.distance_to(stop) / maxf(from.distance_to(to), 1e-4)
	var best := ""
	var best_s := stop_s
	var best_p := stop
	for p: Node3D in people:
		if p.person_id == exclude:
			continue
		var feet := p.global_position
		var s := segment_capsule(from, to, feet + Vector3.UP * PERSON_RADIUS,
				feet + Vector3.UP * (PERSON_HEIGHT - PERSON_RADIUS), PERSON_RADIUS)
		if s >= 0.0 and s < best_s:
			best_s = s
			best = p.person_id
			best_p = from.lerp(to, s)
	return {"target": best, "point": best_p}


## Where along `a` -> `b` (0..1) it passes closest to the segment `c` -> `d`, if within `r` of it; -1 when not.
static func segment_capsule(a: Vector3, b: Vector3, c: Vector3, d: Vector3, r: float) -> float:
	var d1 := b - a
	var d2 := d - c
	var w := a - c
	var aa := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(w)
	if aa < 1e-9:
		return -1.0
	var cc := d1.dot(w)
	var bb := d1.dot(d2)
	var denom := aa * e - bb * bb
	var s := clampf((bb * f - cc * e) / denom, 0.0, 1.0) if denom > 1e-9 else 0.0
	var t := (bb * s + f) / e if e > 1e-9 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-cc / aa, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((bb - cc) / aa, 0.0, 1.0)
	return s if (a + d1 * s).distance_to(c + d2 * t) <= r else -1.0


# ---------------------------------------------------------------- toy parts (shared meshes and materials)

static func box_part(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var key := "box%s" % size
	if not _shared.has(key):
		var b := BoxMesh.new()
		b.size = size
		_shared[key] = b
	var mi := MeshInstance3D.new()
	mi.mesh = _shared[key]
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cylinder_part(parent: Node3D, radius: float, length: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var key := "cyl%.3f_%.3f" % [radius, length]
	if not _shared.has(key):
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = length
		c.radial_segments = 12
		c.rings = 1
		_shared[key] = c
	var mi := MeshInstance3D.new()
	mi.mesh = _shared[key]
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI * 0.5                # along Z
	parent.add_child(mi)
	return mi


static func mat(key: String, c: Color, rough := 0.6, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	if not _shared.has("mat_" + key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		_shared["mat_" + key] = m
	return _shared["mat_" + key]


static func muzzle(parent: Node3D, z: float, y := 0.0) -> void:
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	tip.position = Vector3(0.0, y, z)
	parent.add_child(tip)
