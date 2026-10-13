extends SceneTree
## Headless checks for scripts/breakables.gd: a car rolling at 10 m/s into a thin tree bends it (trunk collider off,
## the tree tilted away) and keeps going, and the tree springs back up (collider on, upright again); a car rolling into
## a sign pole knocks it over (debris flying off, the pole and its faces hidden, collider off) and keeps going, and the
## pole comes back when restored; a car creeping into another sign pole stops against it; a car at speed knocks over
## a street lamp (its debris colliding along the whole pole), a lift gate, a fire hydrant, a bench and a bike rack; a
## broken hydrant gushes water until it is repaired a minute later, even in view.
## godot --headless --fixed-fps 60 --path godot --script res://tools/test_breakables.gd

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Car = preload("res://scripts/car.gd")
const Breakables = preload("res://scripts/breakables.gd")
const RUN := 15.0                           # m of run-up
const SPEED := 10.0                         # m/s

var _main: Node
var _breakables: Breakables
var _failures: PackedStringArray = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = false
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(30)
	_breakables = _main.breakables
	var trees: StaticBody3D = _main.get_node("Neighborhood/TreeCollision/Bendable")
	var props: StaticBody3D = _main.get_node("Neighborhood/PropCollision/Breakable")
	_check(trees.get_shape_owners().size() > 500 and props.get_shape_owners().size() > 300,
			"bendable trees and breakable props have their own bodies (%d trunks, %d prop shapes)" % [
			trees.get_shape_owners().size(), props.get_shape_owners().size()])
	var car := Car.new()
	car.setup("sedan")
	_main.add_child(car)
	await _tree_check(car, trees)
	await _sign_check(car, props)
	await _knock_check(car, props, "lamp_street", 0.11)
	await _knock_check(car, props, "lift_gate", 0.05)
	await _knock_check(car, props, "fire_hydrant", 0.15)
	await _knock_check(car, props, "bench_back", 0.25)
	await _knock_check(car, props, "bike_rack", 0.05)
	await _geyser_check(props)
	_finish()


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	for f in _failures:
		print("  ", f)
	quit(1 if _failures else 0)


# ---------------------------------------------------------------- trees

func _tree_check(car: Car, trees: StaticBody3D) -> void:
	var data: Resource = trees.data
	var p: Array = _main.world_root.get_meta("world")["playable"]
	var dir := Vector3.ZERO
	var k := -1
	for i in data.size():
		var b: Vector3 = data.base[i]
		if not Breakables.bends(data, i) or b.x < p[0] + 30 or b.x > p[2] - 30 or -b.z < p[1] + 30 or -b.z > p[3] - 30:
			continue
		dir = _free_run(car, b, maxf(data.trunk[i].x, 0.12))
		if dir != Vector3.ZERO:
			k = i
			break
	_check(k >= 0, "found a thin tree with a clear run-up")
	if k < 0:
		return
	var base: Vector3 = data.base[k]
	await _launch(car, base, dir, SPEED)
	var max_angle := 0.0
	var tilt_dir := 0.0
	var speeds := Vector2.ZERO                  # just before the tree bends, 10 frames later
	var frames_bent := -1
	for i in 300:
		var v := car.linear_velocity.length()
		await physics_frame
		var b: Dictionary = _breakables.bent.get(k, {})
		if b.is_empty():
			continue
		frames_bent += 1
		if frames_bent == 0:
			speeds.x = v
		elif frames_bent == 10:
			speeds.y = car.linear_velocity.length()
		if b["angle"] > max_angle:
			max_angle = b["angle"]
			var xf := _breakables.instance_transform(b["mmis"][0].multimesh, b["index"])
			tilt_dir = xf.basis.y.normalized().dot(dir)
		if frames_bent > 10 and car.to_local(base).z < -car.half_extents.z - 1.0:
			break
	_check(max_angle > 1.0 and tilt_dir > 0.5,
			"a car at %d m/s bends %s over (%.0f°, leaning %.2f along the way the car went)" % [SPEED, data.ids[k],
			rad_to_deg(max_angle), tilt_dir])
	_check(speeds.y > speeds.x * 0.9, "the car drives on over it (%.1f m/s before, %.1f m/s after)" % [speeds.x, speeds.y])
	var owner_id: int = trees.get_shape_owners()[0]
	for o in trees.get_shape_owners():
		if trees.tree_for_shape(trees.shape_owner_get_shape_index(o, 0)) == k:
			owner_id = o
	_check(_breakables.bent.has(k) and trees.is_shape_owner_disabled(owner_id), "its trunk collider is off while it is bent")
	var behind := -car.to_local(base).z - car.half_extents.z
	car.linear_velocity = Vector3.ZERO
	for i in 600:
		await physics_frame
		if not _breakables.bent.has(k):
			break
	var inst: Dictionary = _breakables._tree_instance(k)
	var up := _breakables.instance_transform(inst["mmis"][0].multimesh, inst["index"]).basis.y.normalized().y
	_check(not _breakables.bent.has(k) and not trees.is_shape_owner_disabled(owner_id) and up > 0.999,
			"once the car has passed it (%.1f m behind) it springs back up (up %.3f) and its trunk collides again" % [behind, up])


# ---------------------------------------------------------------- props

func _sign_check(car: Car, props: StaticBody3D) -> void:
	var data: Resource = props.data
	var found: Array[Array] = []                # [record, run-up direction]
	for k in data.size():
		var meta: Dictionary = data.describe(k)
		if meta.get("model") != "sign_pole" or meta.get("info", {}).get("faces", []).is_empty():
			continue
		var box: AABB = props.record_aabb(k)
		var dir := _free_run(car, Vector3(box.get_center().x, box.position.y, box.get_center().z), 0.06)
		if dir != Vector3.ZERO:
			found.append([k, dir])
			if found.size() == 2:
				break
	_check(found.size() == 2, "found two sign poles with a clear run-up")
	if found.size() < 2:
		return
	# creeping into one: it holds
	var k: int = found[1][0]
	var box: AABB = props.record_aabb(k)
	var dir: Vector3 = found[1][1]
	await _launch(car, Vector3(box.get_center().x, box.position.y, box.get_center().z), dir, 1.0, car.half_extents.z + 2.0)
	for i in 240:
		await physics_frame
		car.linear_velocity = dir * 1.0                 # pushing on
	var stopped_at: float = car.to_local(box.get_center()).z - car.half_extents.z
	_check(_breakables.debris.is_empty() and stopped_at < 0.6,
			"a car creeping at 1 m/s stops against %s (front %.2f m from it)" % [data.ids[k], stopped_at])

	k = found[0][0]
	box = props.record_aabb(k)
	var meta: Dictionary = data.describe(k)
	var spot := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	await _launch(car, spot, found[0][1], SPEED)
	var d: Dictionary = {}
	var speeds := Vector2.ZERO                  # just before the knock, 10 frames later
	var ahead := 0.0                            # furthest the debris got ahead of the spot
	for i in 120:
		var v := car.linear_velocity.length()
		await physics_frame
		if d.is_empty() and not _breakables.debris.is_empty():
			d = _breakables.debris[0]
			speeds.x = v
			await _frames(10)
			speeds.y = car.linear_velocity.length()
		if not d.is_empty():
			var shape: CollisionShape3D = d["body"].get_child(0)
			ahead = maxf(ahead, (shape.global_position - spot).dot(found[0][1]))
	_check(not d.is_empty() and d["record"] == k, "a car at %d m/s knocks %s over" % [SPEED, data.ids[k]])
	if d.is_empty():
		return
	var rb: RigidBody3D = d["body"]
	var tipped := rb.global_basis.y.y
	var faces: int = meta["info"]["faces"].size()
	var hidden := 0
	for h: Array in d["instances"]:
		if _breakables.instance_transform(h[0], h[1]).basis.determinant() == 0.0:
			hidden += 1
	_check(ahead > 2.0 and tipped < 0.7, "the pole flies off ahead of the car and falls over (up to %.1f m ahead, up %.2f)" % [
			ahead, tipped])
	_check(d["instances"].size() == 1 + faces and hidden == 1 + faces and rb.get_child_count() >= 2 + faces,
			"the pole and its %d sign face(s) are hidden in place and drawn on the debris (%d hidden)" % [faces, hidden])
	_check(speeds.y > speeds.x * 0.9, "the car drives on (%.1f m/s before, %.1f m/s after)" % [speeds.x, speeds.y])
	var owners_off := 0
	for o in props.get_shape_owners():
		if props.record_for_shape(props.shape_owner_get_shape_index(o, 0)) == k and props.is_shape_owner_disabled(o):
			owners_off += 1
	_check(owners_off > 0, "its collider is off")
	_breakables.restore(d)
	await _frames(2)
	var shown := 0
	for h: Array in d["instances"]:
		if (h[0] as MultiMesh).buffer.size() and _breakables.instance_transform(h[0], h[1]) == h[2]:
			shown += 1
	var owners_on := 0
	for o in props.get_shape_owners():
		if props.record_for_shape(props.shape_owner_get_shape_index(o, 0)) == k and not props.is_shape_owner_disabled(o):
			owners_on += 1
	_check(_breakables.debris.is_empty() and not is_instance_valid(rb) and shown == 1 + faces and owners_on == owners_off,
			"restored: back in place and solid, the debris gone")


## A car at SPEED knocks over a prop of `model` (collider radius about `r`) and drives on; the debris collides up to
## the top of the model.
func _knock_check(car: Car, props: StaticBody3D, model: String, r: float) -> void:
	var data: Resource = props.data
	var k := -1
	var dir := Vector3.ZERO
	for i in data.size():
		if data.describe(i).get("model") != model:
			continue
		var box: AABB = props.record_aabb(i)
		dir = _free_run(car, Vector3(box.get_center().x, box.position.y, box.get_center().z), r)
		if dir != Vector3.ZERO:
			k = i
			break
	_check(k >= 0, "found a %s with a clear run-up" % model)
	if k < 0:
		return
	var box: AABB = props.record_aabb(k)
	await _launch(car, Vector3(box.get_center().x, box.position.y, box.get_center().z), dir, SPEED)
	var d: Dictionary = {}
	var speeds := Vector2.ZERO
	for i in 120:
		var v := car.linear_velocity.length()
		await physics_frame
		for e: Dictionary in _breakables.debris:
			if e["record"] == k:
				d = e
		if not d.is_empty():
			speeds.x = v
			await _frames(10)
			speeds.y = car.linear_velocity.length()
			break
	var others := []
	for e: Dictionary in _breakables.debris:
		if e["record"] != k:
			others.append(data.ids[e["record"]])
	_check(not d.is_empty(), "a car at %d m/s knocks %s over (also broke %s)" % [SPEED, data.ids[k], others])
	if d.is_empty():
		return
	var rb: RigidBody3D = d["body"]
	var top := 0.0
	for c in rb.get_children():
		if c is CollisionShape3D:
			var shape: Shape3D = c.shape
			var h: float = shape.size.y if shape is BoxShape3D else shape.height
			top = maxf(top, c.position.y + h / 2.0)
	var height := Breakables._model_height(d["instances"][0])
	_check(top > height - 0.4, "its debris collides up to %.1f m (model %.1f m tall)" % [top, height])
	_check(speeds.y > speeds.x * 0.85, "the car drives on (%.1f m/s before, %.1f m/s after)" % [speeds.x, speeds.y])
	var spot := box.get_center()
	for i in 120:                               # the car well past the spot before it comes back
		await physics_frame
		if car.to_local(spot).z < -car.half_extents.z - 1.0:
			break
	car.linear_velocity = Vector3.ZERO          # not on into the next of a row (bike racks)
	car.angular_velocity = Vector3.ZERO
	await _frames(2)
	for e: Dictionary in _breakables.debris.duplicate():
		_breakables.restore(e)
	await _frames(2)
	_check(_breakables.debris.is_empty(), "restored")


## A broken fire hydrant has a geyser over its foot, which eases off and goes with the repair after REPAIR_AFTER s.
func _geyser_check(props: StaticBody3D) -> void:
	var data: Resource = props.data
	var k := Array(data.ids).find(_first_id(data, "fire_hydrant"))
	_check(k >= 0 and _breakables.break_prop(k, Vector3.FORWARD * 5.0), "a fire hydrant breaks")
	if k < 0 or _breakables.debris.is_empty():
		return
	var d: Dictionary = _breakables.debris[-1]
	var g: Node3D = d["geyser"]
	_check(is_instance_valid(g) and g.is_inside_tree() and g.global_position.distance_to(d["spot"]) < 0.01
			and g.get_child_count() >= 4, "it gushes water from its foot")
	await _frames(30)
	_check(_breakables.debris.has(d), "still broken after half a second")
	d["time"] -= Breakables.REPAIR_AFTER - 2.0      # a minute later, give or take a second
	await _frames(30)
	var jet: GPUParticles3D = g.get_node("jet")
	_check(_breakables.debris.has(d) and jet.amount_ratio < 0.5 and jet.amount_ratio > 0.0,
			"the water eases off before the repair (%.2f)" % jet.amount_ratio)
	await _frames(120)
	_check(not _breakables.debris.has(d) and not is_instance_valid(g), "repaired after a minute, the water off")


func _first_id(data: Resource, model: String) -> String:
	for i in data.size():
		if data.describe(i).get("model") == model:
			return data.ids[i]
	return ""


# ---------------------------------------------------------------- run-up

## Direction from which the car can roll RUN m straight into the object at `foot` (radius `r`) with nothing else
## in the way and the ground fairly flat, or ZERO.
func _free_run(car: Car, foot: Vector3, r: float) -> Vector3:
	var world := car.get_world_3d()
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(car.half_extents.x * 2.0 + 0.4, 1.0, car.half_extents.z * 2.0)
	q.shape = shape
	q.exclude = [car.get_rid()]
	q.collision_mask = Layers.BUILDINGS | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES
	for a in 16:
		var dir := Vector3(sin(TAU * a / 16.0), 0.0, cos(TAU * a / 16.0))
		var start := foot - dir * RUN
		var g := WorldQuery.ground_y(world, start.x, start.z, Layers.SOLID)
		if is_nan(g) or absf(g - foot.y) > 1.0:
			continue
		q.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(start.x, foot.y + 1.0, start.z))
		q.motion = dir * (RUN + 6.0)
		if world.direct_space_state.intersect_shape(q, 1):
			continue
		# the first thing in the way is the object itself (a wider box: nothing just beside it either)
		var free: float = world.direct_space_state.cast_motion(q)[0] * (RUN + 6.0)
		var at_object := RUN - car.half_extents.z - r
		if absf(free - at_object) < 0.3:
			return dir
	return Vector3.ZERO


## Puts the car `run` m before `foot`, heading along `dir`, and sets it rolling at `speed`.
func _launch(car: Car, foot: Vector3, dir: Vector3, speed: float, run := RUN) -> void:
	var start := foot - dir * run
	var g := WorldQuery.ground_y(car.get_world_3d(), start.x, start.z, Layers.SOLID)
	car.place(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(start.x, g + 0.2, start.z)))
	await _frames(40)
	car.linear_velocity = car.global_basis.z * speed
