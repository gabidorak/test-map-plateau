extends "res://scripts/items/weapons/weapon.gd"
## The net gun (data/items.json "net_gun"): a pump-action launcher whose shell throws a weighted net (net_shot.gd), seen
## flying, slower than a dart and dropping, that wraps whoever it catches within its range. A thump of air, the pump
## racked as it reloads (longer than the taser's).

const NetShot = preload("res://scripts/items/weapons/net_shot.gd")


func model() -> Node3D:
	var root := Node3D.new()
	root.name = "NetGun"
	var olive := mat("net_olive", Color(0.24, 0.29, 0.2), 0.7)
	var black := mat("net_black", Color(0.08, 0.08, 0.09), 0.5, 0.4)
	var orange := mat("net_orange", Color(0.92, 0.45, 0.14), 0.5)
	box_part(root, Vector3(0.055, 0.07, 0.42), black, Vector3(0.0, 0.02, -0.16))                  # the receiver, barrel
	cylinder_part(root, 0.05, 0.16, orange, Vector3(0.0, 0.02, -0.43))                           # the net canister
	box_part(root, Vector3(0.065, 0.055, 0.15), olive, Vector3(0.0, -0.025, -0.25))               # the pump
	box_part(root, Vector3(0.05, 0.1, 0.22), olive, Vector3(0.0, -0.03, 0.15))                    # the stock
	var grip := box_part(root, Vector3(0.04, 0.1, 0.045), black, Vector3(0.0, -0.06, 0.0))
	grip.rotation.x = -0.25
	muzzle(root, -0.52, 0.02)
	return root


func fire(hands: Node3D, muzzle_pos: Vector3, aim: Vector3, no: int) -> Dictionary:
	_launch(hands.items, muzzle_pos, aim - muzzle_pos, true, no, hands.people.my_id())
	hands.audio.play("net_shot", -1.0, randf_range(0.95, 1.05))
	return {"target": "", "end": aim}


func show_shot(parent: Node, shooter: String, from: Vector3, to: Vector3, _target: String) -> void:
	_launch(parent, from, to - from, false, 0, shooter)
	parent.audio.play_at("net_shot", from, 0.0, randf_range(0.95, 1.05))


func _launch(items: Node, from: Vector3, dir: Vector3, ours: bool, no: int, shooter: String) -> void:
	if dir.length_squared() < 1e-6:
		return
	var n := NetShot.new()
	n.name = "Net"
	n.setup(items, from, dir, stat("speed", 24.0), stat("gravity", 4.0), stat("range", 9.0), ours, no, shooter)
	items.add_child(n)
