extends Node3D
## Another player of a LAN game (scripts/net.gd moves it): the player's capsule and nose in their colour, with their
## nickname above the head. Hidden while they drive or sit in a passenger seat (the vehicle shows its driver and its
## passenger).
## The vehicles simulated here collide with it (a kinematic capsule on the REMOTE_PLAYER layer, frictionless so it
## does not hold back a car it stands on): they stop against it instead of driving through. Not the walkable vehicle
## the player stands in, nor one they walk in or out of through its open doors: there their own peer walks through
## its body box, as the local player does (update_collision).
## The bot drivers of the host look out for them on foot (scripts/traffic/perception.gd: the walkers, walking()).
## A person (scripts/people/person.gd): stunned, they lie on the ground; carried, over the carrier's
## shoulders (carry_on), whatever their own states say until they are put down.

const PlayerScene = preload("res://scenes/player.tscn")
const Layers = preload("res://scripts/physics_layers.gd")
const Perception = preload("res://scripts/traffic/perception.gd")
const Person = preload("res://scripts/people/person.gd")
const INSIDE_MARGIN := 0.15                 # m around a walkable interior: in the doorway, or only just left
const DOOR_MARGIN := 0.7                    # m around it while the doors are open: the step through the body box
const CAR_REACH := 40.0                     # m, no vehicle is longer: further off from its origin, it is not around their feet

var label: Label3D
var collider: AnimatableBody3D
var _body: Node3D
var _shape: CollisionShape3D
var _ignored := {}                          # vehicle (car.gd) -> true while its bodies do not collide with us
var _frame: Node3D                          # the vehicle section the player stands in (show_in), or null
var _local_pos := Vector3.ZERO              # feet in _frame's frame
var _local_yaw := 0.0                       # body facing relative to _frame's
var _color := Color.WHITE
var _seat: Node3D                           # the vehicle (car.gd) whose passenger seat they sit in, or null
var peer_id := 0                            # their peer (net.gd)
var person_id := ""                         # people.gd: "p:<peer>"
var _down := false                          # lying (set_down)
var _carry_body: Node3D                     # the body whose shoulders they lie over (carry_on), or null


func setup(nickname: String, color: Color, peer := 0) -> void:
	name = "Remote_" + nickname.validate_node_name()
	peer_id = peer
	person_id = "p:%d" % peer
	add_to_group(Perception.GROUP)
	add_to_group(Person.GROUP)
	# the same body as the local player (scenes/player.tscn)
	var p := PlayerScene.instantiate()
	_body = p.get_node("Body")
	p.remove_child(_body)
	_shape = p.get_node("CollisionShape3D")
	p.remove_child(_shape)
	p.free()
	add_child(_body)
	collider = AnimatableBody3D.new()
	collider.name = "Collider"
	collider.sync_to_physics = false        # teleported to each pose: no velocity to push what it touches
	collider.collision_layer = Layers.REMOTE_PLAYER
	collider.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.0
	collider.physics_material_override = mat
	_shape.disabled = true                  # until shown
	collider.add_child(_shape)
	add_child(collider)
	set_color(_body, color)
	_color = color
	label = Label3D.new()
	label.text = nickname
	label.position = Vector3(0.0, 2.15, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true                 # readable from afar, like in Roblox
	label.pixel_size = 0.0011
	label.font_size = 28
	label.outline_size = 8
	label.modulate = color.lightened(0.35)
	label.visibility_range_end = 150.0
	add_child(label)


## Body (feet at the origin) facing `body_yaw` (radians, the player's Body node rotation) at global transform `xf`.
func show_at(xf: Transform3D, body_yaw: float) -> void:
	_frame = null
	if _carry_body:
		return                              # (carried: where the carrier is)
	global_transform = xf
	_body.rotation.y = body_yaw


## Body with its feet at `pos` facing `body_yaw` (radians), both in the frame of vehicle section `frame` (car.gd or
## car_trailer.gd). Posed again on it each frame (_process): a vehicle simulated here moves in the physics step,
## after net.gd poses us, and would leave us behind by its last step.
func show_in(frame: Node3D, pos: Vector3, body_yaw: float) -> void:
	if _carry_body:
		return
	_frame = frame
	_local_pos = pos
	_local_yaw = body_yaw
	_follow_frame()


func _process(_delta: float) -> void:
	if _carry_body:
		_follow_carry_body()
	elif _frame:
		_follow_frame()


func _follow_frame() -> void:
	if not is_instance_valid(_frame):
		_frame = null
		return
	global_transform = Transform3D(Basis.IDENTITY, _frame.global_transform * _local_pos)
	_body.rotation.y = _local_yaw + _frame.global_rotation.y


## The vehicle section they stand in, or the vehicle whose passenger seat they sit in, or null.
func riding_in() -> Node3D:
	if is_instance_valid(_frame):
		return _frame
	return _seat if is_instance_valid(_seat) else null


## For the bots (scripts/traffic/perception.gd): walking on the map, not in a vehicle (its aisle or a seat).
func walking() -> bool:
	return riding_in() == null


## Sits the player in the passenger seat of `car` (car.gd, which shows them there) or nowhere (null).
func sit_in(car: Node3D) -> void:
	if car == _seat:
		return
	if is_instance_valid(_seat):
		_seat.show_passenger(false)
	_seat = car
	if car:
		car.show_passenger(true, _color)


## Collides (`on`) or not (hidden: driving) with the vehicles; never with `in_car`, the vehicle the player stands
## in (car.gd, or null), nor with a walkable one of `cars` whose interior their feet are in or by, or step through
## the open doors of.
func update_collision(on: bool, in_car: Node3D, cars: Array) -> void:
	on = on and _carry_body == null
	if _shape.disabled == on:
		_shape.disabled = not on
	if not on:
		return                              # (a shape switched off collides with nothing: drivers cost nothing here)
	var feet := global_position
	for car: Node3D in cars:
		var ignore: bool = car == in_car
		if not ignore and feet.distance_squared_to(car.global_position) < CAR_REACH * CAR_REACH:
			ignore = car.carrier_at(feet, INSIDE_MARGIN) != null \
					or (car.doors_open and car.carrier_at(feet, DOOR_MARGIN) != null)
		if ignore == _ignored.has(car):
			continue
		for b: PhysicsBody3D in car.bodies():
			if ignore:
				collider.add_collision_exception_with(b)
			else:
				collider.remove_collision_exception_with(b)
		if ignore:
			_ignored[car] = true
		else:
			_ignored.erase(car)


# ---------------------------------------------------------------- a person (scripts/people/person.gd)

## On the map, shown, standing: a shot may stun them.
func person_up() -> bool:
	return visible and riding_in() == null and not _down and _carry_body == null


func person_body() -> Node3D:
	return _body


func person_name() -> String:
	return label.text if label else "someone"


func person_carried() -> bool:
	return _carry_body != null


## Down on the ground (`on`) or up again.
func set_down(on: bool) -> void:
	_down = on
	set_lying(on)


## Over the shoulders of `body` (a person's body), or put down (null).
func carry_on(body: Node3D) -> void:
	_carry_body = body
	if body:
		_frame = null
		_shape.set_deferred("disabled", true)
		_follow_carry_body()
	else:
		_body.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) if _down else Basis(),
				Vector3(0.0, 0.33 if _down else 0.0, 0.0))
		label.position.y = 1.0 if _down else 2.15


## Put down at `pos` (their next states move them on).
func put_at(pos: Vector3) -> void:
	global_transform = Transform3D(Basis.IDENTITY, pos)


func _follow_carry_body() -> void:
	if not is_instance_valid(_carry_body) or not _carry_body.is_inside_tree():
		carry_on(null)
		return
	global_transform = Transform3D(Basis.IDENTITY, _carry_body.global_position)
	_body.global_transform = _carry_body.global_transform * Person.CARRY_POSE
	label.position.y = 2.4


## The body (feet at its origin: the capsule and nose), for what a game mode puts on it (scripts/escape/escape_mode.gd).
func body() -> Node3D:
	return _body


## Lying on the ground (`on`: knocked down, Escape from Plateau) or standing.
func set_lying(on: bool) -> void:
	_body.rotation.x = -PI * 0.5 if on else 0.0
	_body.position.y = 0.33 if on else 0.0
	label.position.y = 1.0 if on else 2.15


## True when the vehicle bodies of `car` (car.gd) pass through this player.
func ignores(car: Node3D) -> bool:
	return _ignored.has(car)


## Colours the capsule of a player's Body node (this one's, or the local player's).
static func set_color(body: Node3D, color: Color) -> void:
	var capsule := body.get_node("Capsule") as MeshInstance3D
	var mat := ((capsule.mesh as PrimitiveMesh).material as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = color
	capsule.material_override = mat
