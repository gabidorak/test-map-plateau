extends SceneTree
## net_codec.gd: states come back as they went, within its precision; what doesn't fit is refused, not read out of bounds.
## godot --headless --path godot --script res://tools/test_net_codec.gd

const NetCodec = preload("res://scripts/net_codec.gd")

var _fails := 0


func _init() -> void:
	seed(12)
	for k in 2000:
		_car(k)
		_player(k)
	_train()
	var car := NetCodec.car("1:1", [Transform3D(), Transform3D(), 0.0, 0.0, 0, 0, 100.0])
	_check(car.size() == NetCodec.CAR_MIN, "a vehicle in %d bytes" % car.size())
	_check(not NetCodec.fits(car.slice(0, 20), 0, NetCodec.CAR_MIN), "a cut entry does not fit")
	_check(not NetCodec.fits(PackedByteArray([1, 0]), 0, NetCodec.CAR_MIN), "nor one too short")
	print("%s: %d failed" % ["FAIL" if _fails else "ok", _fails])
	quit(1 if _fails else 0)


func _car(k: int) -> void:
	var xf := Transform3D(Basis.from_euler(Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))),
			Vector3(randf_range(-9000, 9000), randf_range(-200, 2000), randf_range(-9000, 9000)))
	var rear := Transform3D() if k % 2 == 0 else Transform3D(Basis.from_euler(Vector3(0, randf_range(-3, 3), 0.1)), xf.origin)
	var s := [xf, rear, randf_range(-1, 1), randf_range(-1, 1), randi() % 1024, randi() % 3 - 1, randf_range(0, 400)]
	if k % 3 == 0:
		s.append_array([Vector3(0.1, 0.2, 0.3), true])
	var b := NetCodec.car("%d:%d" % [randi(), k], s)
	var r := NetCodec.read_car(b, 0)
	_check(b[0] == b.size() and r.size() == s.size(), "vehicle entry size")
	_check((r[0].origin - xf.origin).length() < 0.01 and (r[1].origin - rear.origin).length() < 0.01, "vehicle position")
	_check(r[0].basis.get_rotation_quaternion().angle_to(xf.basis.get_rotation_quaternion()) < 0.002, "vehicle rotation")
	_check(absf(r[2] - s[2]) < 0.006 and absf(r[3] - s[3]) < 0.006 and absf(r[6] - s[6]) < 0.3, "steering, pedal, health")
	_check(r[4] == s[4] and r[5] == s[5], "flags, indicator")


func _player(k: int) -> void:
	var s := ["1:%d" % k if k % 2 else "", k % 2, Vector3(randf_range(-9000, 9000), 40, randf_range(-9000, 9000)),
			randf_range(-9, 9), k % 4]
	if k % 5 == 0:
		s.append_array([Vector3(1, 2, 3), false])
	var b := NetCodec.player(s)
	var r := NetCodec.read_player(b, 0)
	_check(b[0] == b.size() and r.size() == s.size() and r[0] == s[0] and r[1] == s[1] and r[4] == s[4], "player fields")
	_check((r[2] - s[2]).length() < 0.01 and absf(angle_difference(r[3], s[3])) < 0.001, "player pose")


func _train() -> void:
	var s := [12345.678, 27.5, 6, 0.5, 2, 0.75, -0.25]
	var r := NetCodec.read_train(NetCodec.train("train:3", 7, s), 0)
	_check(r[0] == "train:3" and r[1] == 7, "train id")
	_check(absf(r[2][0] - s[0]) < 0.01 and absf(r[2][1] - s[1]) < 0.01, "train position, speed")
	_check(r[2][2] == 6 and r[2][3] == 0.5 and r[2][4] == 2 and r[2][5] == 0.75 and r[2][6] == -0.25, "train switches")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
