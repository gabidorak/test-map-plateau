extends Node3D
## A car showroom built into the world by scripts/builder/interior_builder.gd (world/interiors.json), at runtime: the
## display cars on their podiums are real, drivable vehicles that game.gd parks at start on the host (or solo, or the
## dedicated server) through stock(), and again after the in-game menu clears the map; the cars on the turntables (which
## turn) and the gold statues are models only. Its salesman (scripts/salesman.gd) greets the local player, follows them
## around the showroom and sells them the car they look at; each peer of a LAN game has its own.
## Coordinates exported by the builder are Godot world coordinates, except `outline` (map x east, y north).

const Car = preload("res://scripts/car.gd")
const Salesman = preload("res://scripts/salesman.gd")
const TURN_SPEED := 0.25                    # rad/s, the turntables
const ACTIVE_RANGE := 250.0                 # m from the camera beyond which the turntables and the salesman rest
const GOLD := Color(1.0, 0.78, 0.36)

@export var dealer := ""
@export var floor_y := 0.0
@export var ceiling_y := 0.0
@export var outline := PackedVector2Array() # the glass walls, map coordinates
@export var cars: Array = []                # display cars: {model, xf (podium top), label, price, pitch}
@export var statues: Array = []             # gold models: {model, xf}
@export var turntables: Array = []          # {model, node (the turning disc, a child), top (disc height)}
@export var obstacles := PackedVector3Array()   # (x, z, radius) the salesman walks around; radius < 0: a doorway
@export var salesman_xf := Transform3D.IDENTITY

var game: Node                              # game.gd, which sets it
var parked: Array = []                      # per display car: the vehicle game.gd parked for it (host side)
var salesman: Salesman
var _discs: Array[Node3D] = []


func _ready() -> void:
	add_to_group("showroom")
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD
	gold.metallic = 1.0
	gold.roughness = 0.16
	for s: Dictionary in statues:
		var m := display_model(s["model"], gold)
		m.transform = s["xf"]
		add_child(m)
	for t: Dictionary in turntables:
		var disc := get_node(String(t["node"])) as Node3D
		var m := display_model(t["model"])
		m.position.y = float(t["top"])
		disc.add_child(m)
		_discs.append(disc)
	salesman = Salesman.new()
	salesman.name = "Salesman"
	salesman.showroom = self
	add_child(salesman)
	salesman.global_transform = salesman_xf


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(salesman_xf.origin) > ACTIVE_RANGE:
		return
	for d in _discs:
		d.rotate_y(TURN_SPEED * delta)


## Parks the display cars missing from their podiums (never parked, or cleared off the map): game.gd, host side.
func stock(g: Node, pacer: RefCounted = null) -> void:
	game = g
	parked.resize(cars.size())
	for k in cars.size():
		if is_instance_valid(parked[k]) and parked[k] in g.cars:
			continue
		var c: Dictionary = cars[k]
		parked[k] = g.park_vehicle(c["model"], c["xf"])
		if pacer and pacer.due():           # scripts/pacer.gd: a game starting under the loading overlay
			await pacer.wait()


## True when `p` (Godot) is in the showroom: inside its glass walls, between its floor and ceiling.
func is_inside(p: Vector3) -> bool:
	return p.y > floor_y - 1.0 and p.y < ceiling_y and Geometry2D.is_point_in_polygon(Vector2(p.x, -p.z), outline)


## The display car spot within `r` m of `p` (Godot, horizontally), nearest first, or -1.
func spot_near(p: Vector3, r: float) -> int:
	var best := -1
	for k in cars.size():
		var o: Vector3 = (cars[k]["xf"] as Transform3D).origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < r:
			r = d
			best = k
	return best


## The vehicle standing on display spot `k` (any peer's copy), or null: it may be out on a test drive.
func car_on_spot(k: int) -> Node3D:
	if game == null:
		return null
	var o: Vector3 = (cars[k]["xf"] as Transform3D).origin
	for car: Car in game.cars:
		if is_instance_valid(car) and car.model_name == cars[k]["model"] and \
				Vector2(car.global_position.x - o.x, car.global_position.z - o.z).length() < 2.5:
			return car
	return null


## A vehicle model only (no physics): its meshes in a holder, the wheels' bottom on y = 0 and centred, every
## surface in `override` when given (the gold statues).
static func display_model(model: String, override: Material = null) -> Node3D:
	var spec: Dictionary = Car.SPECS[model]
	var holder := Node3D.new()
	holder.name = "Display_" + model.replace("-", "_")
	var m: Node3D = load("res://assets/cars/" + spec.get("file", model + ".glb")).instantiate()
	m.scale = Vector3.ONE * float(spec.get("scale", 1.5))
	holder.add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var p := mi.get_parent()
		while p != holder:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var bb := xf * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
		if override:
			mi.material_override = override
	m.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return holder
