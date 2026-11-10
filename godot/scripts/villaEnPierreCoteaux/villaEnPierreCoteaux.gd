extends Node3D
## Villa de charme: a stone manor in its walled grounds in place of buildings #628, #659, #671, #672 (and the shed #620),
## after Thomas's plan (ref/proprietes/Villa Luxe/, the plan of 2026-11-09): the house (scripts/villaEnPierreCoteaux/
## villaEnPierreCoteaux_house.gd) and its grounds (villaEnPierreCoteaux_site.gd: the stone wall, the wrought-iron gate on the road, the white gravel
## drive and forecourt, the terraces, the pool, the grotto fountain) are drawn at start in every game mode; its rooms
## (villaEnPierreCoteaux_interior.gd) only while the camera is near (built the first time it comes, hidden while it is far). The map's buildings, trees and props inside the wall are left
## out when the world is built (drop, builder/world_builder.gd), its ground painted lawn (repaint,
## builder/ground_builder.gd) and new trees planted (cypresses along the drive, olives, planes, magnolias).
## The gate swings open when someone allowed comes near it: anyone, unless a game mode says who (`allowed`: PTA
## Online, scripts/online/properties.gd: its owners and their visitors); the garage's doors rise for whoever comes to
## them from the grounds. A player not allowed found inside the wall is put back outside the gate.
## Frame: the house's: x east, y up from its ground floor, z south; its origin at the front facade's west end
## (map 264, -424): Godot x = 264 + x, z = 424 + z (no rotation).

const Kit = preload("res://scripts/build_kit.gd")
const SiteBuilder = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_site.gd")
const HouseBuilder = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_house.gd")
const InteriorBuilder = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_interior.gd")
const Marks = preload("res://scripts/race_marks.gd")
const GrassField = preload("res://scripts/grass_field.gd")

const Data = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_data.gd")
const NAME := Data.NAME
const ID := Data.ID
const ORIGIN := Data.ORIGIN
const W := Data.W
const D := Data.D
const PLINTH := Data.PLINTH
const WALL := Data.WALL
const GATE := Data.GATE
const GATE_HALF := Data.GATE_HALF
const LEAF := Data.LEAF
## The map's buildings that go (#659, #628, #620, #672, #671).
const DROP_IDS := ["osm:w71347352", "osm:w71348078", "osm:w71351288", "osm:w71355287", "osm:w820424278"]
const BELT := 11.0                          # m: the woodland kept along the inside of the wall...
const CLEAR := 7.0                          # ...but not within this of the drive, the gravel and the house
## New trees (map x, y): [kind, x, y]; kinds: cypress, olive, olive_small, plane, magnolia.
const NEW_TREES := [["cypress", 249.4, -373.1], ["cypress", 249.3, -363.9], ["cypress", 255.0, -373.0],
		["cypress", 257.7, -364.2], ["cypress", 261.6, -375.1], ["cypress", 264.4, -366.4], ["cypress", 267.3, -377.4],
		["cypress", 271.7, -369.3], ["cypress", 273.4, -380.8], ["cypress", 277.8, -372.7], ["cypress", 278.9, -384.4],
		["cypress", 284.1, -376.8], ["cypress", 283.7, -388.2], ["cypress", 290.2, -381.7], ["cypress", 287.4, -392.1],
		["cypress", 295.7, -388.0], ["olive", 284.0, -411.5], ["olive_small", 267.0, -422.2],
		["olive_small", 273.0, -422.2], ["olive_small", 295.0, -422.2], ["olive_small", 301.0, -422.2],
		["plane", 252.0, -438.0], ["plane", 318.0, -458.0], ["plane", 250.0, -462.0], ["plane", 322.0, -478.0],
		["plane", 256.0, -486.0], ["plane", 314.0, -488.0], ["plane", 240.0, -450.0], ["plane", 330.0, -446.0],
		["plane", 334.0, -463.0], ["plane", 262.0, -501.0], ["plane", 306.0, -501.0], ["plane", 246.0, -484.0],
		["magnolia", 272.0, -478.0], ["magnolia", 296.0, -478.0], ["magnolia", 268.0, -455.0],
		["magnolia", 300.0, -455.0], ["olive", 324.0, -394.0], ["olive", 329.0, -401.0], ["olive", 321.0, -386.0],
		["olive", 330.0, -389.0]]
const TREE_KINDS := {"cypress": ["columnar", 0, 11.0, 1.25, "pine_dark"], "olive": ["round", 1, 6.0, 3.2, "olive"],
		"olive_small": ["round", 1, 3.4, 1.4, "olive"], "plane": ["round", 0, 16.0, 6.5, "leaf"],
		"magnolia": ["round", 2, 7.0, 3.4, "blossom"], "screen_oak": ["round", 0, 14.0, 4.6, "deep"],
		"screen_pine": ["conifer", 1, 12.5, 3.0, "conifer"], "screen_tall": ["oval", 0, 15.5, 4.8, "leaf"]}
## The wall along the road (WALL's indexes, in order): a screen of trees planted inside it.
const ROAD_WALL := [32, 0, 1, 2, 3, 4, 5, 6, 7, 8]
const SCREEN_STEP := 6.5                    # m between the screen's trees along a row
const GATE_CLEAR := 10.0                    # m round the gate without trees
const GATE_REACH := 13.0                    # m from the gate's middle within which it opens
const GARAGE_REACH := 8.0                   # m from the garage doors' middle
const OPEN_SPEED := 0.45                    # of the way a second
const INTERIOR_NEAR := 75.0                 # m from the house's middle: its rooms are built...
const INTERIOR_FAR := 95.0                  # ...and dropped beyond this
const CHECK_EVERY := 0.15

var game: Node                              # game.gd (null in the tools)
var frame: Transform3D                      # the villa's frame (global)
var floor_y := 0.0                          # its ground floor (Godot y)
var site: Node3D                            # the grounds and the house's shell
var interior: Node3D                        # its rooms, while near
## Who may come in: (nothing) -> bool, asked for the local player; unset: anyone (outside PTA Online).
var allowed := Callable()
var gate_open := 0.0                        # 0 shut .. 1 open
var garage_open := 0.0
var _gate_want := false
var _garage_want := false
var _check_t := 0.0
var _leaves: Array = []                     # the gate's two leaves (pivots), their side (+1 / -1)
var _gate_shape: CollisionShape3D
var _garage_doors: Array = []
var _garage_shapes: Array = []
var _plaque: Label3D
var _wall_local := PackedVector2Array()     # the wall in the villa's frame (x, z)
var _kick_t := 0.0


# ---------------------------------------------------------------- the map (builder/world_builder.gd)

## The world without what stands inside the wall (before the buildings are made): the buildings (and their signs
## and roof modules), the trees but a belt along the wall, the props (an old gate); new trees in.
static func drop(world: Dictionary) -> void:
	var wall := PackedVector2Array(WALL)
	world["buildings"] = world["buildings"].filter(func(b: Dictionary) -> bool:
		return not (str(b["id"]).split("_rest")[0] in DROP_IDS))
	var osm := DROP_IDS.map(func(i: String) -> String: return i.trim_prefix("osm:"))
	world["building_signs"] = world["building_signs"].filter(func(s: Dictionary) -> bool:
		return not (str(s.get("building", "")) in osm))
	world["building_modules"] = world["building_modules"].filter(func(m: Dictionary) -> bool:
		return not Geometry2D.is_point_in_polygon(Vector2(m["x"], m["y"]), wall))
	world["props"] = world["props"].filter(func(p: Dictionary) -> bool:
		return not Geometry2D.is_point_in_polygon(Vector2(p["x"], p["y"]), wall))
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool:
		var p := Vector2(t["x"], t["y"])
		if p.distance_to(GATE) < GATE_CLEAR:
			return false                        # (none before the gate, inside or out)
		return not Geometry2D.is_point_in_polygon(p, wall) or _kept(p))
	var trees: Array = NEW_TREES + screen_trees()
	var fol: Dictionary = world["palette"]["foliage"]
	fol["blossom"] = "#e3a9bd"
	if not fol.has("pine_dark"):
		fol["pine_dark"] = "#24603f"
	var arch: Dictionary = world["tree_archetypes"]
	var k := 0
	for t: Array in trees:
		var kind: Array = TREE_KINDS[t[0]]
		if not arch.has(kind[0]):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = k * 7919 + 17
		var s := rng.randf_range(0.9, 1.12)
		world["trees"].append({"id": "villa:tree:%d" % k, "x": t[1], "y": t[2], "h": float(kind[2]) * s,
				"r": float(kind[3]) * s, "arch": kind[0], "var": mini(int(kind[1]), int(arch[kind[0]]) - 1),
				"tint": kind[4], "src": "villa"})
		k += 1


## The screen of trees inside the wall along the road (map x, y): two staggered rows, 3 and 7.5 m in from it, off
## the gate and the drive.
static func screen_trees() -> Array:
	var wall := PackedVector2Array(WALL)
	var gate := GATE
	var out := []
	var kinds := [["screen_oak", "screen_pine"], ["screen_tall", "screen_oak"]]
	for row in 2:
		var inset := 3.0 if row == 0 else 7.5
		var along := SCREEN_STEP * 0.5 * row
		var k := row
		for s in ROAD_WALL.size() - 1:
			var a := wall[ROAD_WALL[s]]
			var b := wall[ROAD_WALL[s + 1]]
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 2.0, wall):
				n = -n
			var length := a.distance_to(b)
			while along < length:
				var p := a + t * along + n * inset
				var l := to_local2(p)
				if p.distance_to(gate) > 11.0 and SiteBuilder.clearance(l) > 3.5 and Geometry2D.is_point_in_polygon(p, wall):
					out.append([kinds[row][k % 2], p.x, p.y])
					k += 1
				along += SCREEN_STEP
			along -= length
	return out


## A tree inside the wall kept: in the belt along it, away from what is built.
static func _kept(p: Vector2) -> bool:
	var wall := PackedVector2Array(WALL)
	var d := INF
	for i in wall.size():
		var a := wall[i]
		var b := wall[(i + 1) % wall.size()]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	if d > BELT:
		return false
	var l := to_local2(p)
	return SiteBuilder.clearance(l) > CLEAR


static func to_local2(m: Vector2) -> Vector2:
	return Data.to_local2(m)


static func to_map(l: Vector2) -> Vector2:
	return Data.to_map(l)


static func gate_local() -> Array:
	return Data.gate_local()


# ---------------------------------------------------------------- in the game

func _ready() -> void:
	name = "VillaEnPierreCoteaux"
	for p: Vector2 in WALL:
		_wall_local.append(to_local2(p))
	# the floor over the highest ground under the house
	var top := -INF
	for i in int(W / 2.0) + 1:
		for j in int(D / 2.0) + 1:
			var m := to_map(Vector2(i * 2.0, j * 2.0))
			top = maxf(top, Marks.ground(m.x, m.y))
	floor_y = top + PLINTH
	frame = Transform3D(Basis.IDENTITY, Vector3(ORIGIN.x, floor_y, -ORIGIN.y))
	var fy := floor_y
	var ground := func(x: float, z: float) -> float:
		var m := to_map(Vector2(x, z))
		return Marks.ground(m.x, m.y) - fy
	var meshes := DisplayServer.get_name() != "headless"
	site = SiteBuilder.new().build(ground, meshes)
	site.transform = frame
	add_child(site)
	var house: Node3D = HouseBuilder.new().build(meshes)
	house.transform = frame
	add_child(house)
	_leaves = site.get_meta("leaves")
	_gate_shape = site.get_meta("gate_shape")
	_plaque = site.get_meta("plaque")
	_garage_doors = house.get_meta("garage_doors")
	_garage_shapes = house.get_meta("garage_shapes")
	# the lawn's tufts inside the wall, none on what is built
	var lawn := PackedVector2Array(WALL)
	GrassField.lawns.append(lawn)
	GrassField.regrass.append(Vector3(GATE.x, GATE.y, Data.OLD_TRACK))
	for poly: PackedVector2Array in site.get_meta("paved"):
		var mp := PackedVector2Array()
		for p in poly:
			mp.append(to_map(p))
		GrassField.keep_out.append(mp)
	set_plaque("VILLA LUXE")


## The text on the gate's plaque (properties.gd: for sale, or whose it is).
func set_plaque(text: String) -> void:
	if _plaque:
		_plaque.text = text


## Where the plaque is, on the road side of the gate (global), and the way out (to the road, unit).
func plaque_point() -> Vector3:
	return frame * (site.get_meta("plaque_at") as Vector3)


func road_out() -> Vector3:
	var g := gate_local()
	var o: Vector2 = -(g[2] as Vector2)
	return Vector3(o.x, 0.0, o.y)


## The gate's middle (global, on the ground).
func gate_point() -> Vector3:
	var g := gate_local()
	var m := to_map(g[0])
	return Vector3(m.x, Marks.ground(m.x, m.y), -m.y)


## Where the maps mark it (map x, y): the gate.
func map_xy() -> Vector2:
	return GATE


## Whether `p` (global) is inside the wall.
func in_grounds(p: Vector3) -> bool:
	var l := frame.affine_inverse() * p
	return Geometry2D.is_point_in_polygon(Vector2(l.x, l.z), _wall_local)


## The garage's bays (global transforms, the cars' fronts towards +z of each: out of the doors) and its terminal.
func garage_bays() -> Array:
	var out := []
	for xf: Transform3D in HouseBuilder.garage_bays():
		out.append(frame * xf)
	return out


## Where a player arriving home stands (global) and faces: the forecourt before the steps.
func spawn_point() -> Array:
	var p := frame * Vector3(20.0, 0.0, -6.0)
	var m := Vector2(p.x, -p.z)
	return [Vector3(p.x, Marks.ground(m.x, m.y) + 0.2, p.z), Vector3(0, 0, 1)]


func _physics_process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_gate_want = _near(gate_point(), GATE_REACH, true)
		_garage_want = _near(frame * HouseBuilder.GARAGE_DOORS_MID, GARAGE_REACH, false)
		_interior_check()
		_kick_out(delta + CHECK_EVERY)
	var was := gate_open
	gate_open = move_toward(gate_open, 1.0 if _gate_want else 0.0, OPEN_SPEED * delta)
	if gate_open != was:
		_pose_gate()
	was = garage_open
	garage_open = move_toward(garage_open, 1.0 if _garage_want else 0.0, OPEN_SPEED * 1.3 * delta)
	if garage_open != was:
		_pose_garage()


func _restricted() -> bool:
	return allowed.is_valid()


func _me_allowed() -> bool:
	return not _restricted() or bool(allowed.call())


## Someone this peer sees, allowed in, within `reach` of `at`: the local player (on foot or at the wheel), the
## vehicles and other players (only when no game mode restricts the grounds, or for the garage: they are in).
func _near(at: Vector3, reach: float, gate: bool) -> bool:
	if game == null:
		return false
	var r2 := reach * reach
	if game.mode != "" and game.mode != "server" and not game.flying and _me_allowed():
		var me: Vector3 = game.driving.global_position if game.driving else game.player.global_position
		if me.distance_squared_to(at) < r2:
			return true
	if gate and _restricted():
		return false
	for car: Node3D in game.cars:
		if is_instance_valid(car) and car.global_position.distance_squared_to(at) < r2 and (not gate or in_grounds(car.global_position)):
			return true
	if game.net and game.net.active:
		for r: Node3D in game.net.avatars():
			if r.visible and r.global_position.distance_squared_to(at) < r2:
				return true
	return false


## The leaves swung `gate_open` of the way, into the grounds; open, the gate's collision goes.
func _pose_gate() -> void:
	var a := smoothstep(0.0, 1.0, gate_open) * deg_to_rad(96.0)
	for l: Array in _leaves:
		var pivot: Node3D = l[0]
		pivot.rotation.y = float(l[1]) * a + float(l[2])
	if _gate_shape:
		_gate_shape.disabled = gate_open > 0.6


func _pose_garage() -> void:
	var t := smoothstep(0.0, 1.0, garage_open)
	for d: Node3D in _garage_doors:
		d.position.y = float(d.get_meta("y0")) + t * HouseBuilder.GARAGE_DOOR_H
	for s: CollisionShape3D in _garage_shapes:
		s.disabled = garage_open > 0.5


## Opens (or shuts) the gate at once (the tools).
func set_gate(on: bool) -> void:
	_gate_want = on
	gate_open = 1.0 if on else 0.0
	_check_t = 1.0
	_pose_gate()


## The rooms built while the camera is near the house, dropped when it is far.
func _interior_check() -> void:
	if DisplayServer.get_name() == "headless" and interior == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(frame * Vector3(W * 0.5, 2.0, D * 0.5))
	if interior == null and d < INTERIOR_NEAR:
		build_interior()
	elif interior != null:
		# built once (it takes a moment), then only shown while near: nothing to draw from afar
		if interior.visible and d > INTERIOR_FAR:
			interior.visible = false
		elif not interior.visible and d < INTERIOR_NEAR:
			interior.visible = true


func build_interior() -> void:
	if interior:
		return
	interior = InteriorBuilder.new().build(DisplayServer.get_name() != "headless")
	interior.transform = frame
	add_child(interior)


## A player not allowed in, inside the wall (not flying): back outside the gate.
func _kick_out(dt: float) -> void:
	_kick_t -= dt
	if game == null or not _restricted() or _me_allowed() or game.flying or _kick_t > 0.0:
		return
	if game.mode == "" or game.mode == "server":
		return
	var me: Node3D = game.driving if game.driving else game.player
	if not in_grounds(me.global_position):
		return
	_kick_t = 1.0
	var g := gate_local()
	var out: Vector2 = (g[0] as Vector2) - (g[2] as Vector2) * 5.0
	var m := to_map(out)
	var at := Vector3(m.x, Marks.ground(m.x, m.y) + 0.3, -m.y)
	var face := road_out()
	if game.driving:
		var car: RigidBody3D = game.driving
		car.global_transform = Transform3D(Basis.looking_at(-face, Vector3.UP), at + Vector3(0, 0.4, 0))
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
	else:
		game.player.teleport(at, atan2(-face.x, -face.z))
	if game.has_method("toast"):
		game.toast("Private property: %s" % NAME)
