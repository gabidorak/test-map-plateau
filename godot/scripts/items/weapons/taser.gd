extends "res://scripts/items/weapons/weapon.gd"
## The taser (data/items.json "taser"): its two darts fly too fast to see (a hitscan up to its `range`), trailing their
## wires (tether.gd) from the gun to whoever they hit, which stay for the stun; a miss leaves them a moment. A blue
## spark at the muzzle, the darts' snap.

const Tether = preload("res://scripts/items/weapons/tether.gd")

const MISS_WIRES := 0.7                     # s the wires of a miss stay


func model() -> Node3D:
	var root := Node3D.new()
	root.name = "Taser"
	var yellow := mat("taser_yellow", Color(0.95, 0.76, 0.12), 0.45)
	var black := mat("taser_black", Color(0.07, 0.07, 0.08), 0.6)
	var blue := mat("taser_blue", Color(0.35, 0.65, 1.0), 0.3, 0.0, 2.0)
	box_part(root, Vector3(0.045, 0.06, 0.17), yellow, Vector3(0.0, 0.02, -0.07))       # the body
	box_part(root, Vector3(0.05, 0.045, 0.05), black, Vector3(0.0, 0.025, -0.175))     # the cartridge
	var grip := box_part(root, Vector3(0.04, 0.11, 0.05), black, Vector3(0.0, -0.05, 0.0))
	grip.rotation.x = -0.2
	box_part(root, Vector3(0.012, 0.012, 0.012), blue, Vector3(0.0, -0.005, -0.2))     # the laser's eye
	muzzle(root, -0.205, 0.025)
	return root


func fire(hands: Node3D, muzzle_pos: Vector3, aim: Vector3, _no: int) -> Dictionary:
	var dir := (aim - muzzle_pos).normalized()
	var spread := stat("spread", 0.0)
	if spread > 0.0:
		dir = (dir + Vector3(randfn(0.0, spread), randfn(0.0, spread), randfn(0.0, spread))).normalized()
	var to := muzzle_pos + dir * stat("range", 10.0)
	var r: Dictionary = trace(hands.get_world_3d().direct_space_state, hands.people.up_people(), muzzle_pos, to,
			hands.people.my_id())
	var body: Node3D = null
	if r["target"] != "":
		var p: Node3D = hands.people.person(r["target"])
		body = p.person_body() if p else null
	_wires(hands, hands.muzzle_node(), muzzle_pos, body, r["point"], stat("stun", 3.0) if body else MISS_WIRES)
	hands.audio.play("taser_shot", -3.0, randf_range(0.95, 1.05))
	hands.flash(Color(0.45, 0.7, 1.0))
	return {"target": r["target"], "end": r["point"]}


## (The wires start where the shot left, the gun in their hand, and end on the body hit.)
func show_shot(parent: Node, _shooter: String, from: Vector3, to: Vector3, target: String) -> void:
	var body: Node3D = null
	if target != "":
		var p: Node3D = parent.people.person(target)
		body = p.person_body() if p else null
	_wires(parent, null, from, body, to, stat("stun", 3.0) if body else MISS_WIRES)
	parent.audio.play_at("taser_shot", from, -2.0, randf_range(0.95, 1.05))


func _wires(parent: Node, from_node: Node3D, from: Vector3, to_node: Node3D, to: Vector3, life: float) -> void:
	var t := Tether.new()
	t.name = "TaserWires"
	t.setup(from_node, from, to_node, to, life)
	parent.add_child(t)
