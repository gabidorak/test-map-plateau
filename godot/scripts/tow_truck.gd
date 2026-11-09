extends "res://scripts/car.gd"
## Losplatos Custom's tow truck (Car.SPECS "tow-truck"): the Volvo FH16 tractor (its model and cab) made a wrecker:
## a body behind the cab (side lockers, a deck, LOSPLATOS DÉPANNAGE on its sides), an amber light bar on the cab, a
## boom rising over the back, its cable and hook. The doors key (O) hooks the vehicle whose front (or back) end is by
## the hook: it is lifted by that end and hangs from the hook on a pivot (a PinJoint3D), rolling behind on its other
## wheels with its brakes off (car.gd towed); O again sets it down. hook_gate, when set (PTA Online,
## scripts/online/tow_job.gd), is asked first (the host hands the vehicle's simulation to the tow truck's driver);
## hooked / unhooked tell what happened. The light bar flashes while a vehicle is hooked.

signal hooked_car(car: Node3D)
signal unhooked_car(car: Node3D)

const HOOK_REACH := 2.6                     # m from the hook to a vehicle's end
const HOOK_HEIGHT := 0.75                   # m over the ground
const ATTACH_HEIGHT := 0.45                 # m over its ground, a towed vehicle's end
const FLASH := 0.8                          # s, the light bar's cycle

var towing: Node3D                          # the vehicle hooked (car.gd), or null
var hook_gate := Callable()                 # (car) -> nothing: asks before hooking (PTA Online), else hooks at once
var _hook_joint: PinJoint3D
var _hook_local := Vector3.ZERO             # the hook, in the truck's frame
var _bar_mat: StandardMaterial3D
var _bar_light: OmniLight3D
var _flash_t := 0.0
var _excepted: Array = []                   # [body, body] pairs not colliding while hooked (and a moment after)


func setup(model: String) -> void:
	super(model)
	name = "TowTruck"
	var ground := ground_y(self)
	var rear := extents_center.z - half_extents.z
	_hook_local = Vector3(0.0, ground + HOOK_HEIGHT, rear - 0.35)
	_build_wrecker(ground, rear)


## The wrecker's body, boom, cable, hook and light bar (meshes on the truck; its collision is the tractor's box).
func _build_wrecker(ground: float, rear: float) -> void:
	var white := _mat(Color("#eeeeea"), 0.4, 0.2)
	var navy := _mat(Color("#16213e"), 0.45, 0.2)
	var steel := _mat(Color("#2b2e33"), 0.4, 0.7)
	var yellow := _mat(Color("#f2c230"), 0.5, 0.1)
	var deck := ground + 1.15
	var front := extents_center.z + half_extents.z - 2.55          # behind the cab
	var hw := half_extents.x - 0.08
	# the deck and the side lockers
	_part(Vector3(hw * 2.0, 0.12, front - rear), Vector3(0, deck, (front + rear) * 0.5), steel)
	for side: float in [-1.0, 1.0]:
		_part(Vector3(0.5, 0.95, front - rear - 0.3), Vector3(side * (hw - 0.25), deck + 0.48, (front + rear) * 0.5 + 0.1), white)
		_part(Vector3(0.52, 0.12, front - rear - 0.3), Vector3(side * (hw - 0.25), deck + 0.06, (front + rear) * 0.5 + 0.1), navy)
		var label := Label3D.new()
		label.text = "LOSPLATOS\nDÉPANNAGE"
		label.font_size = 64
		label.pixel_size = 0.0045
		label.outline_size = 0
		label.modulate = Color("#16213e")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.transform = Transform3D(Basis(Vector3.UP, side * PI * 0.5),
				Vector3(side * (hw + 0.005), deck + 0.55, (front + rear) * 0.5 + 0.1))
		add_child(label)
	# the boom: a mast on the deck, the arm up and back over the hook, its ram, the cable and the hook
	var base := Vector3(0, deck + 0.1, front - 0.6)
	var tip := Vector3(0, deck + 2.0, _hook_local.z)
	_part(Vector3(0.5, 0.9, 0.5), base + Vector3(0, 0.45, 0), steel)
	_rod(base + Vector3(0, 0.8, 0), tip, 0.16, yellow)
	_rod(base + Vector3(0, 0.1, -0.5), base.lerp(tip, 0.55), 0.07, steel)
	_rod(tip, _hook_local + Vector3(0, 0.12, 0), 0.015, steel)
	_part(Vector3(0.12, 0.2, 0.06), _hook_local + Vector3(0, 0.05, 0), steel)
	_part(Vector3(1.6, 0.12, 0.25), Vector3(0, ground + 0.62, rear + 0.06), steel)      # the rear bar
	# the light bar on the cab
	_bar_mat = _mat(Color(1.0, 0.6, 0.1), 0.3, 0.0)
	_bar_mat.emission_enabled = true
	_bar_mat.emission = Color(1.0, 0.55, 0.05)
	_bar_mat.emission_energy_multiplier = 0.0
	var roof := extents_center.y + half_extents.y
	_part(Vector3(1.5, 0.14, 0.3), Vector3(0, roof + 0.04, extents_center.z + half_extents.z - 0.9), _bar_mat)
	_bar_light = OmniLight3D.new()
	_bar_light.light_color = Color(1.0, 0.6, 0.15)
	_bar_light.omni_range = 9.0
	_bar_light.light_energy = 0.0
	_bar_light.position = Vector3(0, roof + 0.3, extents_center.z + half_extents.z - 0.9)
	add_child(_bar_light)


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	add_child(mi)


## Where `car`'s wheels meet the ground, in its frame (its wheels' centres less their radius and suspension).
static func ground_y(car: Node3D) -> float:
	var y := INF
	for w in car.get_children():
		if w is VehicleWheel3D:
			y = minf(y, w.position.y - w.wheel_radius - w.wheel_rest_length)
	return y if y != INF else 0.0


## The hook, global.
func hook_point() -> Vector3:
	return global_transform * _hook_local


## A vehicle's end by the hook ([car, its end in its frame, true for its front]), or [] none: stopped, not this truck,
## the nearest within HOOK_REACH.
func hook_candidate(cars: Array) -> Array:
	var h := hook_point()
	var best := []
	var best_d := HOOK_REACH
	for c: Node3D in cars:
		if c == self or not is_instance_valid(c) or c.get("towed") or (c as RigidBody3D).linear_velocity.length() > 2.0:
			continue
		var he: Vector3 = c.half_extents
		var ce: Vector3 = c.extents_center
		var gy := ground_y(c)
		for front: bool in [true, false]:
			var end := Vector3(ce.x, gy + ATTACH_HEIGHT, ce.z + (he.z if front else -he.z))
			var d := (c.global_transform * end).distance_to(h)
			if d < best_d:
				best_d = d
				best = [c, end, front]
	return best


## O at the wheel: unhooks, or hooks the vehicle by the hook (through hook_gate when set).
func toggle_hook(cars: Array) -> String:
	if towing:
		unhook()
		return "unhooked"
	var c := hook_candidate(cars)
	if c.is_empty():
		return "none"
	if hook_gate.is_valid():
		hook_gate.call(c[0])
		return "asked"
	hook(c[0])
	return "hooked"


## Hooks `car` by its end nearest the hook: lifted there and pinned, the other wheels on the ground.
func hook(car: Node3D) -> bool:
	if towing or car == null or not is_instance_valid(car):
		return false
	var he: Vector3 = car.half_extents
	var ce: Vector3 = car.extents_center
	var gy := ground_y(car)
	var front_end := Vector3(ce.x, gy + ATTACH_HEIGHT, ce.z + he.z)
	var back_end := Vector3(ce.x, gy + ATTACH_HEIGHT, ce.z - he.z)
	var h := hook_point()
	var front: bool = (car.global_transform * front_end).distance_to(h) <= (car.global_transform * back_end).distance_to(h)
	var end := front_end if front else back_end
	# behind the truck, in line with it: its front towards the truck (hooked by the front) or away
	var b := global_transform.basis.orthonormalized()
	var cb := b if front else b.rotated(b.y, PI)
	car.global_transform = Transform3D(cb, h - cb * end)
	car.linear_velocity = linear_velocity
	car.angular_velocity = Vector3.ZERO
	car.set("towed", true)
	for a: PhysicsBody3D in bodies():
		for c: PhysicsBody3D in car.bodies():
			a.add_collision_exception_with(c)
			_excepted.append([a, c])
	_hook_joint = PinJoint3D.new()
	_hook_joint.name = "TowHook"
	add_child(_hook_joint)
	_hook_joint.global_position = h
	_hook_joint.node_a = _hook_joint.get_path_to(self)
	_hook_joint.node_b = _hook_joint.get_path_to(car)
	_hook_joint.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
	_hook_joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 0.0)
	towing = car
	hooked_car.emit(car)
	return true


## Sets the towed vehicle down where it is.
func unhook() -> void:
	if _hook_joint and is_instance_valid(_hook_joint):
		_hook_joint.queue_free()
	_hook_joint = null
	var car := towing
	towing = null
	if car and is_instance_valid(car):
		car.set("towed", false)
		unhooked_car.emit(car)
	var pairs := _excepted
	_excepted = []
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		for p: Array in pairs:
			if is_instance_valid(p[0]) and is_instance_valid(p[1]):
				(p[0] as PhysicsBody3D).remove_collision_exception_with(p[1]))


func _unhandled_input(event: InputEvent) -> void:
	if driving and controls and event.is_action_pressed("doors"):
		var game := get_parent()                # (game.gd: the vehicles are its children)
		var what := toggle_hook(game.cars if game and game.get("cars") != null else [])
		if what == "none" and game and game.has_method("toast"):
			game.toast("Back up to a vehicle: its front or back by the hook")
		get_viewport().set_input_as_handled()
		return
	super(event)


func _physics_process(delta: float) -> void:
	super(delta)
	if towing and not is_instance_valid(towing):
		towing = null
	if _hook_joint and towing == null:
		unhook()
	_flash_t = fmod(_flash_t + delta, FLASH)
	var on := towing != null and _flash_t < FLASH * 0.5
	_bar_mat.emission_energy_multiplier = 3.0 if on else (0.4 if towing else 0.0)
	_bar_light.light_energy = 1.4 if on else 0.0


func _exit_tree() -> void:
	if towing:
		unhook()
