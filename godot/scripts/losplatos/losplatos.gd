extends Node3D
## Losplatos Custom: the car repair and paint shop in place of building #758 (the LadHyX, osm:w71348311), Main/
## Losplatos in every game mode (game.gd). The map's building is left out of the world when it is built (drop,
## builder/world_builder.gd); the shop is drawn here at start (scripts/losplatos/losplatos_builder.gd) on its
## footprint, its roll-up door in the west facade facing the road. The door rolls up when a vehicle or a player comes
## within OPEN_REACH m of it (each peer for itself: the ones it sees), and down once no one is near; open, its
## collision goes. In the workshop, the service bay (in_bay) is where PTA Online repairs and paints a player's car
## (scripts/online/custom_shop.gd).

const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const Builder = preload("res://scripts/losplatos/losplatos_builder.gd")
const Marks = preload("res://scripts/race_marks.gd")
const GrassField = preload("res://scripts/grass_field.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const NAME := "Losplatos Custom"
const BUILDING_ID := "osm:w71348311"        # #758, Laboratoire d'Hydrodynamique de l'École polytechnique
## #758's footprint (map x east, y north): the kit modules on it go with it.
const FOOTPRINT := [Vector2(405.613, -171.427), Vector2(407.37, -135.709), Vector2(391.176, -134.924),
		Vector2(388.76, -139.491), Vector2(389.426, -170.63)]
## The shop set square to the street (the block's frame, scripts/ilot/ilot_plan.gd: its west facade WALK_W m back
## from the west road's kerb, its front sidewalk the block's sidewalk there).
const ORIGIN := Vector2(386.764, -169.478)   # the west facade's south end (the shop's frame)
const NORTH := Vector2(388.557, -138.379)    # its north end: the facade runs ORIGIN -> NORTH
const FLOOR_Z := 1.0                        # m, the workshop's floor at least (over the highest ground under it)
const OPEN_REACH := 10.0                    # m from the door's middle within which it opens
const OPEN_SPEED := 0.6                     # of the way a second
const CHECK_EVERY := 0.15

var game: Node                              # game.gd (null in the tools)
var frame: Transform3D                      # the shop's frame (global)
var floor_z := FLOOR_Z                      # m, its floor: over the map's ground under it
var shop: Node3D                            # what the builder made
var opening := 0.0                          # 0 shut .. 1 open
var _want := false
var _check_t := 0.0
var _slats: Array = []
var _door_shape: CollisionShape3D


## The world without #758 (builder/world_builder.gd, before the buildings are made): its building record, its name
## sign, the kit modules on its roof.
static func drop(world: Dictionary) -> void:
	WorldEdits.drop_buildings(world, [BUILDING_ID], WorldEdits.grown(PackedVector2Array(FOOTPRINT), 1.0))


## The shop's frame: x north along the west facade, y up, z east into it; its origin on the floor at the facade's
## south end.
static func shop_frame(z := FLOOR_Z) -> Transform3D:
	var d := (NORTH - ORIGIN).normalized()
	var inward := Vector2(d.y, -d.x)        # east
	return Transform3D(Basis(Vector3(d.x, 0, -d.y), Vector3.UP, Vector3(inward.x, 0, -inward.y)),
			Vector3(ORIGIN.x, z, -ORIGIN.y))


func _ready() -> void:
	name = "Losplatos"
	# the floor just over the map's ground under the shop (the old building's pad), the apron down to the road
	frame = shop_frame(0.0)
	var top := -INF
	for i in int(Builder.L) + 1:
		for j in int(Builder.W) + 1:
			var g := frame * Vector3(i, 0.0, j)
			top = maxf(top, Marks.ground(g.x, -g.z))
	floor_z = maxf(FLOOR_Z, top + 0.04)
	frame = shop_frame(floor_z)
	var f := frame
	var ground := func(x: float, z: float) -> float:
		var g := f * Vector3(x, 0.0, z)
		return Marks.ground(g.x, -g.z) - f.origin.y
	var gm: RefCounted = GroundMap.get_map()
	var road_ids := []
	if gm:
		for m: String in ["asphalt", "paint", "kerb"]:
			road_ids.append(gm.materials.find(m))
	var on_road := func(x: float, z: float) -> bool:
		var g := f * Vector3(x, 0.0, z)
		return gm != null and gm.material_at(g.x, -g.z) in road_ids
	shop = Builder.new().build(ground, on_road, DisplayServer.get_name() != "headless")   # (headless: collision only)
	shop.transform = frame
	add_child(shop)
	# no grass through the paving
	for r: Array in shop.get_meta("paved"):
		var poly := PackedVector2Array()
		for c: Vector2 in [Vector2(r[0] - 0.3, r[1] - 0.3), Vector2(r[2] + 0.3, r[1] - 0.3), Vector2(r[2] + 0.3, r[3] + 0.3),
				Vector2(r[0] - 0.3, r[3] + 0.3)]:
			var g := frame * Vector3(c.x, 0.0, c.y)
			poly.append(Vector2(g.x, -g.z))
		GrassField.keep_out.append(poly)
	_slats = shop.get_meta("slats")
	_door_shape = shop.get_meta("door_shape")


## The door's middle on the facade line (global).
func door_point() -> Vector3:
	return frame * (shop.get_meta("door") as Vector3)


## The service bay's middle on the floor (global).
func bay_point() -> Vector3:
	return frame * (shop.get_meta("bay") as Vector3)


## Where the maps mark it (map x, y): in front of the door.
func map_xy() -> Vector2:
	var p := frame * ((shop.get_meta("door") as Vector3) + Vector3(0, 0, -2.0))
	return Vector2(p.x, -p.z)


## Whether `p` (global) is in the service bay (a car's middle standing there).
func in_bay(p: Vector3) -> bool:
	var l := frame.affine_inverse() * p
	var bay: Vector3 = shop.get_meta("bay")
	var size: Vector2 = shop.get_meta("bay_size")
	return absf(l.x - bay.x) < size.x * 0.5 + 0.4 and absf(l.z - bay.z) < size.y * 0.5 + 0.6 and l.y > -1.0 and l.y < 2.5


## Whether `p` (global) is inside the workshop.
func in_workshop(p: Vector3) -> bool:
	var l := frame.affine_inverse() * p
	return l.x > Builder.HALL_X and l.x < Builder.L and l.z > 0.0 and l.z < Builder.W and l.y > -1.0 and l.y < Builder.H


func _physics_process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_want = _someone_near()
	var was := opening
	opening = move_toward(opening, 1.0 if _want else 0.0, OPEN_SPEED * delta)
	if opening != was or _slats.is_empty():
		_pose_door()


## Someone this peer sees within OPEN_REACH of the door: the player (on foot, driving, the fly camera aside), a
## vehicle, another player.
func _someone_near() -> bool:
	var d := door_point()
	var r2 := OPEN_REACH * OPEN_REACH
	if game == null:
		return false
	if game.mode != "" and game.mode != "server" and not game.flying:
		var me: Vector3 = game.driving.global_position if game.driving else game.player.global_position
		if me.distance_squared_to(d) < r2:
			return true
	for car: Node3D in game.cars:
		if is_instance_valid(car) and car.global_position.distance_squared_to(d) < r2:
			return true
	if game.net and game.net.active:
		for r: Node3D in game.net.avatars():
			if r.visible and r.global_position.distance_squared_to(d) < r2:
				return true
	return false


## The slats rolled up `opening` of the way: each rises with the roll, gone into the housing once over the opening.
func _pose_door() -> void:
	var h := Builder.DOOR.z / Builder.SLATS
	for k in _slats.size():
		var s: MeshInstance3D = _slats[k]
		var y := (k + 0.5) * h + opening * Builder.DOOR.z
		s.position.y = y
		s.visible = y - h * 0.5 < Builder.DOOR.z - 0.02
	if _door_shape:
		_door_shape.disabled = opening > 0.55

