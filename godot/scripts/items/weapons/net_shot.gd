extends Node3D
## A net in flight (net_gun.gd fires it, on the shooter's peer and, for show, on the others'): it opens as it leaves
## the gun, flies at the gun's speed, dropping a little, and catches the first person standing in its way (Weapon.trace:
## a ray for the world, the people's capsules) within the gun's range; past it, its weights pull it down. On the
## shooter's peer (`hits`) a person caught goes to items.gd (net_landed), which tells the host; the net then goes, the
## one wrapped round them (people_fx.gd) taking its place. On the ground it lies flat a moment, then goes.
## One ray and a few capsule tests per physics tick while it flies (a second or so).

const Weapon = preload("res://scripts/items/weapons/weapon.gd")
const Fx = preload("res://scripts/people/people_fx.gd")

const OPEN_TIME := 0.25                     # s to open fully
const LIE := 1.6                            # s on the ground
const LIFE := 3.0                           # s at most

var items: Node                             # items.gd
var no := 0                                 # the shot's number (items.gd)
var hits := false                           # ours: a person caught counts
var exclude := ""                           # the shooter's person id

var _vel := Vector3.ZERO
var _gravity := 4.0
var _range := 9.0
var _travel := 0.0
var _t := 0.0
var _landed := false
var _model: Node3D


func setup(items_node: Node, from: Vector3, dir: Vector3, speed: float, gravity: float, reach: float, ours: bool,
		shot_no: int, shooter: String) -> void:
	items = items_node
	_vel = dir.normalized() * speed
	_gravity = gravity
	_range = reach
	hits = ours
	no = shot_no
	exclude = shooter
	top_level = true
	_model = Fx.flying_net()
	_model.scale = Vector3.ONE * 0.3
	add_child(_model)
	position = from


func _physics_process(delta: float) -> void:
	_t += delta
	if _landed:
		if _t > LIE:
			queue_free()
		return
	if _t > LIFE:
		queue_free()
		return
	var from := global_position
	_vel.y -= (_gravity if _travel < _range else _gravity * 5.0) * delta
	var to := from + _vel * delta
	var people: Array = items.people.up_people() if _travel < _range + 0.5 else []
	var r: Dictionary = Weapon.trace(get_world_3d().direct_space_state, people, from, to, exclude)
	if r["target"] != "":
		if hits:
			items.net_landed(no, r["target"])
		queue_free()
		return
	var stop: Vector3 = r["point"]
	if stop.distance_to(to) > 0.01:          # the world
		_landed = true
		_t = 0.0
		global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), stop + Vector3.UP * 0.05)
		_model.scale = Vector3.ONE
		items.audio.play_at("net_land", stop, -6.0)
		return
	_travel += from.distance_to(to)
	var open := clampf(_t / OPEN_TIME, 0.0, 1.0)
	global_transform = Transform3D(Basis.looking_at(_vel, Vector3.UP if absf(_vel.normalized().y) < 0.95 else Vector3.FORWARD)
			.rotated(_vel.normalized(), _t * 7.0), to)
	_model.scale = Vector3.ONE * lerpf(0.3, 1.1, open * (2.0 - open))
