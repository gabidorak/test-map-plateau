extends Node
## Light street objects that vehicles bend or knock over, like in Euro Truck Simulator 2. game.gd adds it to Main.
## - Thin trees (trunk up to BEND_TRUNK, BEND_HEIGHT tall at most; TreeCollision's "Bendable" body) bend away from
##   a vehicle that drives into them, stay flattened while it is over their foot, then spring back up with a wobble.
## - Sign poles, bus stop poles, route markers, guideposts, bollards and bin poles (BREAKABLE_PROPS;
##   PropCollision's "Breakable" body) snap off their foot and fly off as rigid debris on the DEBRIS layer. The
##   original comes back RESTORE_AFTER seconds later once the camera is RESTORE_DISTANCE from both it and the debris
##   (at once for the oldest when there are more than MAX_DEBRIS).
## Every physics frame each moving vehicle body (group "vehicles": scripts/car.gd and its rear section) sweeps its
## collision boxes LOOKAHEAD frames ahead along its velocity and looks for those objects on the BREAKABLE layer, so
## they give way before the solver stops the vehicle against them; the vehicle loses the momentum it gives them.
## Slower than BEND_SPEED / BREAK_SPEED they hold like any other obstacle.
## The models stay in their MultiMeshes (built by scripts/builder/vegetation_builder.gd and prop_placer.gd): a bent
## tree's instance is turned about its foot in its three LODs, a broken prop's instances are scaled to nothing while
## its debris draws one-instance copies of them. Those MultiMeshes are edited through a CPU copy of their buffer
## (reading one back from the GPU stalls; the headless renderer only keeps whole buffers), uploaded once per frame.

const Layers = preload("res://scripts/physics_layers.gd")
const VehicleAudio = preload("res://scripts/vehicle_audio.gd")
const CHUNK := 96.0                         # m, MultiMesh chunks of the trees and props (the builders' CHUNK)

## model -> debris mass (kg)
const BREAKABLE_PROPS := {"sign_pole": 15.0, "bus_pole": 25.0, "route_marker": 5.0, "guidepost": 20.0,
		"assembly_sign": 10.0, "bollard": 20.0, "bin_vigipirate": 12.0}
const BEND_TRUNK := 0.1                     # m, trunk radius up to which a tree bends (~1,700 of the 15,600)
const BEND_HEIGHT := 8.0                    # m
const BEND_SPEED := 0.5                     # m/s, slowest push that bends a tree
const BREAK_SPEED := 2.0                    # m/s (7 km/h), slowest knock that breaks a prop
const TREE_MASS := 30.0                     # kg, momentum a bent tree takes from the vehicle
const BEND_MAX := 1.3                       # rad, flattened under a vehicle
const BEND_STIFFNESS := 70.0                # 1/s², spring back up
const BEND_DAMPING := 7.0                   # 1/s: a couple of wobbles
const BEND_SQUASH := 0.2                    # flattened trees are this much shorter (less crown in the ground)
const UNDER_MARGIN := 0.3                   # m around a vehicle box within which a tree's foot is held down
const LOOKAHEAD := 2.0                      # physics frames of travel covered by the swept boxes
const SWEEP_MARGIN := 0.05                  # m added around the swept boxes
const RESTORE_AFTER := 20.0                 # s
const RESTORE_DISTANCE := 60.0              # m
const MAX_DEBRIS := 40

var world_root: Node3D
var bent := {}                              # tree index -> {mmis (3 LODs), index, rest, axis, angle, rate}
var debris: Array[Dictionary] = []          # {record, body, instances [[MultiMesh, index, transform]], spot, labels, time}

var _trees: StaticBody3D                    # TreeCollision/Bendable
var _props: StaticBody3D                    # PropCollision/Breakable
var _broken := {}                           # prop record -> true while its debris is out
var _query := PhysicsShapeQueryParameters3D.new()
var _box := BoxShape3D.new()
var _boxes: Array = []                      # this frame: [vehicle body, box global transform, box size]
var _clock := 0.0
var _buffers := {}                          # MultiMesh -> PackedFloat32Array, our copy of its instance buffer
var _dirty := {}                            # MultiMeshes to upload at the end of the frame


## True when tree k of `data` (VegetationData) bends under vehicles.
static func bends(data: Resource, k: int) -> bool:
	return data.trunk[k].x <= BEND_TRUNK and float(data.info[k].get_slice("|", 4)) <= BEND_HEIGHT


## True when props of `model` break.
static func breaks(model: String) -> bool:
	return BREAKABLE_PROPS.has(model)


func _ready() -> void:
	_query.shape = _box
	_query.collision_mask = Layers.BREAKABLE
	_trees = world_root.get_node_or_null("TreeCollision/Bendable")
	_props = world_root.get_node_or_null("PropCollision/Breakable")


func _physics_process(delta: float) -> void:
	_clock += delta
	_boxes.clear()
	for body: RigidBody3D in get_tree().get_nodes_in_group("vehicles"):
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs and not cs.disabled and cs.shape is BoxShape3D:
				_boxes.append([body, body.global_transform * cs.transform, (cs.shape as BoxShape3D).size])
	for b: Array in _boxes:
		_sweep(b[0], b[1], b[2], delta)
	_update_trees(delta)
	_restore_debris()
	_flush()


## Bends or breaks what the box (`xf`, `size`) of vehicle `body` reaches within LOOKAHEAD frames.
func _sweep(body: RigidBody3D, xf: Transform3D, size: Vector3, delta: float) -> void:
	if body.linear_velocity.length_squared() < BEND_SPEED * BEND_SPEED:
		return
	var travel := xf.basis.transposed() * body.linear_velocity * delta * LOOKAHEAD
	_box.size = size + travel.abs() + Vector3.ONE * SWEEP_MARGIN * 2.0
	_query.transform = xf.translated_local(travel / 2.0)
	for hit: Dictionary in body.get_world_3d().direct_space_state.intersect_shape(_query, 16):
		if hit["collider"] == _trees and _trees:
			_bend(body, _trees.tree_for_shape(hit["shape"]))
		elif hit["collider"] == _props and _props:
			_break(body, _props.record_for_shape(hit["shape"]))


# ---------------------------------------------------------------- trees

func _bend(body: RigidBody3D, k: int) -> void:
	if k < 0 or bent.has(k):
		return
	var base: Vector3 = _trees.data.base[k]
	var v := _velocity_at(body, base)
	var push := Vector3(v.x, 0.0, v.z)
	if push.length() < BEND_SPEED:
		return
	var b := _tree_instance(k)
	if b.is_empty():
		return
	_trees.set_solid(k, false)
	var dir := push.normalized()
	b["axis"] = Vector3.UP.cross(dir)
	b["angle"] = 0.0
	b["rate"] = minf(push.length(), 10.0)          # rad/s: the bumper pushes the trunk about 1 m up
	bent[k] = b
	body.apply_impulse(-push * TREE_MASS, base - body.global_position)
	_play("swish", base, linear_to_db(clampf(push.length() / 8.0, 0.3, 1.0)))


## The tree's instance in its chunk's three LOD MultiMeshes: {mmis, index, rest (chunk-local transform)}, or {}.
func _tree_instance(k: int) -> Dictionary:
	var data: Resource = _trees.data
	var base: Vector3 = data.base[k]
	var chunk := world_root.get_node_or_null("Vegetation/Trees/Chunk_%d_%d" % [floori(base.x / CHUNK),
			floori(-base.z / CHUNK)]) as Node3D
	if chunk == null:
		return {}
	var model: String = data.info[k].get_slice("|", 0)
	var mmis: Array[MultiMeshInstance3D] = []
	for lod in 3:
		var mmi := chunk.get_node_or_null("%s_lod%d" % [model, lod]) as MultiMeshInstance3D
		if mmi == null:
			return {}
		mmis.append(mmi)
	var local := base - chunk.position
	var i := _find_instance(mmis[0].multimesh, func(o: Vector3) -> bool: return o.distance_squared_to(local) < 1e-4)
	if i < 0:
		return {}
	# room for the tree lying flat in the culling box of the chunk
	var h := float(data.info[k].get_slice("|", 4))
	for mmi in mmis:
		mmi.custom_aabb = mmi.custom_aabb.merge(AABB(local - Vector3(h, 0.5, h), Vector3(2.0 * h, h + 1.0, 2.0 * h)))
	return {"mmis": mmis, "index": i, "rest": instance_transform(mmis[0].multimesh, i)}


## Springs every bent tree towards flat (its foot under a vehicle box) or upright; done ones get their trunk back.
func _update_trees(delta: float) -> void:
	for k: int in bent.keys():
		var b: Dictionary = bent[k]
		var pressed := _under_vehicle(_trees.data.base[k])
		var target := BEND_MAX if pressed else 0.0
		b["rate"] += (BEND_STIFFNESS * (target - b["angle"]) - BEND_DAMPING * b["rate"]) * delta
		b["angle"] = clampf(b["angle"] + b["rate"] * delta, -0.5, BEND_MAX)
		var rest: Transform3D = b["rest"]
		if not pressed and absf(b["angle"]) < 0.01 and absf(b["rate"]) < 0.05:
			_set_tree(b, rest)
			_trees.set_solid(k, true)
			bent.erase(k)
			continue
		var squash := 1.0 - BEND_SQUASH * clampf(b["angle"] / BEND_MAX, 0.0, 1.0)
		_set_tree(b, Transform3D(Basis(b["axis"], b["angle"]) * rest.basis * Basis.from_scale(Vector3(1.0, squash, 1.0)),
				rest.origin))


func _set_tree(b: Dictionary, xf: Transform3D) -> void:
	for mmi: MultiMeshInstance3D in b["mmis"]:
		_set_instance(mmi.multimesh, b["index"], xf)


## True when `p` (a tree foot, a prop spot) is under or right beside a vehicle box.
func _under_vehicle(p: Vector3) -> bool:
	for b: Array in _boxes:
		var local: Vector3 = (b[1] as Transform3D).affine_inverse() * p
		var half: Vector3 = b[2] / 2.0
		# the boxes start at the wheel centres: the ground is up to ~1.5 m below them
		if absf(local.x) < half.x + UNDER_MARGIN and absf(local.z) < half.z + UNDER_MARGIN \
				and local.y > -half.y - 1.5 and local.y < half.y:
			return true
	return false


# ---------------------------------------------------------------- props

func _break(body: RigidBody3D, k: int) -> void:
	if k < 0 or _broken.has(k):
		return
	var shapes: Array = _props.record_shapes(k)
	var hit: Vector3 = (shapes[0][1] as Transform3D).origin
	var v := _velocity_at(body, hit)
	var push := Vector3(v.x, 0.0, v.z)
	if push.length() < BREAK_SPEED:             # cheap test first: a vehicle may lean on it every frame
		return
	var meta: Dictionary = _props.data.describe(k)
	var mass: float = BREAKABLE_PROPS.get(meta.get("model", ""), 0.0)
	if mass <= 0.0:
		return
	var instances := _prop_instances(meta, _props.record_aabb(k))
	if instances.is_empty():
		return
	# the debris body sits on the prop's foot, upright
	var foot: Transform3D = instances[0][2]
	foot.basis = foot.basis.orthonormalized()
	var rb := RigidBody3D.new()
	rb.name = "Debris_" + String(meta["id"]).replace(":", "_")
	rb.mass = mass
	rb.continuous_cd = true                 # thin poles at speed
	rb.collision_layer = Layers.DEBRIS
	rb.collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.DEBRIS
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.2
	rb.physics_material_override = mat
	for s: Array in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = foot.affine_inverse() * (s[1] as Transform3D)
		rb.add_child(cs)
	var hidden := []
	for inst: Array in instances:
		var mm: MultiMesh = inst[0]
		var i: int = inst[1]
		var copy := MultiMesh.new()
		copy.transform_format = MultiMesh.TRANSFORM_3D
		copy.use_custom_data = mm.use_custom_data
		copy.mesh = mm.mesh
		copy.instance_count = 1
		copy.set_instance_transform(0, foot.affine_inverse() * (inst[2] as Transform3D))
		if mm.use_custom_data:
			copy.set_instance_custom_data(0, _instance_custom(mm, i))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = copy
		mmi.visibility_range_end = (inst[3] as MultiMeshInstance3D).visibility_range_end
		rb.add_child(mmi)
		var rest := instance_transform(mm, i)
		hidden.append([mm, i, rest])
		_set_instance(mm, i, Transform3D(Basis.from_scale(Vector3.ZERO), rest.origin))
	add_child(rb)
	rb.global_transform = foot
	# snapped off its foot: flies on a little faster than the bumper, tipping over away from it
	var dir := push.normalized()
	rb.linear_velocity = push * 1.15 + Vector3.UP * (1.0 + 0.08 * push.length())
	rb.angular_velocity = Vector3.UP.cross(dir) * clampf(push.length() / 1.5, 1.0, 12.0)
	# the bus stop name and line badges go with the pole
	var labels := world_root.get_node_or_null("Props/BusStops/" + String(meta["id"]).replace(":", "_")) as Node3D
	var labels_rest := Transform3D()
	if labels:
		labels_rest = labels.transform
		labels.reparent(rb, true)
	_props.set_solid(k, false)
	_broken[k] = true
	debris.append({"record": k, "body": rb, "instances": hidden, "spot": foot.origin, "labels": labels,
			"labels_rest": labels_rest, "time": _clock})
	body.apply_impulse(-push * mass, hit - body.global_position)
	_play("clang", hit, linear_to_db(clampf(push.length() / 10.0 * sqrt(mass / 15.0), 0.3, 1.0)))


## The prop's instances in the chunk MultiMeshes around it: [[MultiMesh, index, global transform, MultiMeshInstance3D]],
## its model first (foot inside the collider box `box`), then the faces of a sign pole (on its axis), or [].
func _prop_instances(meta: Dictionary, box: AABB) -> Array:
	var near := box.grow(0.05)
	var main := _find_props(meta["model"], box.get_center(), func(o: Vector3) -> bool:
		return o.x >= near.position.x and o.x <= near.end.x and o.z >= near.position.z and o.z <= near.end.z \
				and o.y >= box.position.y - 0.5 and o.y <= box.end.y, true)
	if main.is_empty():
		return []
	var foot: Vector3 = main[0][2].origin
	var faces := {}
	for face: String in meta.get("info", {}).get("faces", []):
		faces[face] = true
	for face: String in faces:
		main.append_array(_find_props(face, foot, func(o: Vector3) -> bool:
			return Vector2(o.x - foot.x, o.z - foot.z).length() < 0.35 and o.y > foot.y and o.y < foot.y + 4.0, false))
	return main


## Instances of prop `model` whose global origin passes `test`, in the chunk of `around` and its eight neighbours.
func _find_props(model: String, around: Vector3, test: Callable, first_only: bool) -> Array:
	var out := []
	var c := Vector2i(floori(around.x / CHUNK), floori(-around.z / CHUNK))
	for dx in [0, -1, 1]:
		for dy in [0, -1, 1]:
			var mmi := world_root.get_node_or_null("Props/Chunk_%d_%d/%s" % [c.x + dx, c.y + dy, model]) as MultiMeshInstance3D
			if mmi == null:
				continue
			var xf := mmi.global_transform
			var mm := mmi.multimesh
			var start := 0
			while true:
				var i := _find_instance(mm, func(o: Vector3) -> bool: return test.call(xf * o), start)
				if i < 0:
					break
				out.append([mm, i, xf * instance_transform(mm, i), mmi])
				if first_only:
					return out
				start = i + 1
	return out


## Brings back old debris's props once nobody is looking (or the oldest at once past MAX_DEBRIS).
func _restore_debris() -> void:
	var cam := get_viewport().get_camera_3d()
	for d: Dictionary in debris.duplicate():
		var over := debris.size() > MAX_DEBRIS and d == debris[0]
		if not over:
			if _clock - d["time"] < RESTORE_AFTER:
				continue
			if cam and (cam.global_position.distance_to(d["spot"]) < RESTORE_DISTANCE
					or cam.global_position.distance_to((d["body"] as Node3D).global_position) < RESTORE_DISTANCE):
				continue
		if _under_vehicle(d["spot"]):
			continue
		restore(d)


## Puts debris `d`'s prop back in place.
func restore(d: Dictionary) -> void:
	for h: Array in d["instances"]:
		_set_instance(h[0], h[1], h[2])
	var labels: Node3D = d["labels"]
	if labels:
		labels.reparent(world_root.get_node("Props/BusStops"), false)
		labels.transform = d["labels_rest"]
	(d["body"] as Node).queue_free()
	_props.set_solid(d["record"], true)
	_broken.erase(d["record"])
	debris.erase(d)
	_flush()


# ---------------------------------------------------------------- shared

## Index of the first instance from `start` whose origin (MultiMesh space) passes `test`, or -1.
func _find_instance(mm: MultiMesh, test: Callable, start := 0) -> int:
	var stride := _stride(mm)
	var buf := _buffer(mm)
	for i in range(start, mm.instance_count):
		var o := i * stride
		if test.call(Vector3(buf[o + 3], buf[o + 7], buf[o + 11])):
			return i
	return -1


## Transform of instance i of `mm` (MultiMesh space), as drawn now.
func instance_transform(mm: MultiMesh, i: int) -> Transform3D:
	var b := _buffer(mm)
	var o := i * _stride(mm)
	return Transform3D(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]),
			Vector3(b[o + 2], b[o + 6], b[o + 10]), Vector3(b[o + 3], b[o + 7], b[o + 11]))


func _instance_custom(mm: MultiMesh, i: int) -> Color:
	var b := _buffer(mm)
	var o := i * _stride(mm) + 12 + (4 if mm.use_colors else 0)
	return Color(b[o], b[o + 1], b[o + 2], b[o + 3])


func _set_instance(mm: MultiMesh, i: int, xf: Transform3D) -> void:
	var b := _buffer(mm)
	var o := i * _stride(mm)
	var x := xf.basis
	var values := [x.x.x, x.y.x, x.z.x, xf.origin.x, x.x.y, x.y.y, x.z.y, xf.origin.y, x.x.z, x.y.z, x.z.z, xf.origin.z]
	for j in 12:
		b[o + j] = values[j]
	_buffers[mm] = b
	_dirty[mm] = true


func _buffer(mm: MultiMesh) -> PackedFloat32Array:
	if not _buffers.has(mm):
		_buffers[mm] = mm.buffer
	return _buffers[mm]


static func _stride(mm: MultiMesh) -> int:
	return 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)


## Uploads the edited buffers.
func _flush() -> void:
	for mm: MultiMesh in _dirty:
		mm.buffer = _buffers[mm]
	_dirty.clear()


## Velocity of vehicle body `body` at global point `p`.
static func _velocity_at(body: RigidBody3D, p: Vector3) -> Vector3:
	return body.linear_velocity + body.angular_velocity.cross(p - body.global_transform * body.center_of_mass)


func _play(sound: String, at: Vector3, volume_db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = VehicleAudio.one_shot(sound)
	p.unit_size = 8.0
	p.max_distance = 80.0
	p.volume_db = volume_db
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
