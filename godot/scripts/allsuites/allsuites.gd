extends Node3D
## All Suites Study Paris Saclay, the students' residence in place of building #184 (osm:w626590677), in every game
## mode (game.gd). The map's building is left out of the world when it is built (drop, builder/world_builder.gd); the
## residence is drawn here at start (scripts/allsuites/allsuites_builder.gd) on its footprint, after Thomas's photos
## (ref/proprietes/AllSuitesStudy/). Its ground floor is level with the highest ground along its street facades, so
## the sidewalk never covers its threshold.

const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const Builder = preload("res://scripts/allsuites/allsuites_builder.gd")
const Marks = preload("res://scripts/race_marks.gd")
const NAME := Builder.NAME
const BUILDING_ID := "osm:w626590677"       # #184
## #184's footprint (map x east, y north): the kit modules on it go with it.
const FOOTPRINT := [Vector2(-121.051, 0.689), Vector2(-120.145, 5.895), Vector2(-132.77, 8.169),
		Vector2(-141.511, -40.342), Vector2(-75.111, -52.546), Vector2(-66.309, -3.714), Vector2(-78.546, -1.599),
		Vector2(-79.682, -7.002), Vector2(-80.821, -6.824), Vector2(-81.277, -9.733), Vector2(-82.893, -9.505),
		Vector2(-88.218, -38.193), Vector2(-91.571, -37.28), Vector2(-91.166, -35.861), Vector2(-119.985, -30.554),
		Vector2(-120.435, -32.117), Vector2(-124.071, -31.491), Vector2(-119.161, -3.032), Vector2(-120.608, -2.773),
		Vector2(-120.327, 0.282)]
const ORIGIN := Vector2(-141.511, -40.342)  # the south facade's west end (the residence's frame)
const EAST := Vector2(-75.111, -52.546)     # its east end: the facade runs ORIGIN -> EAST
const FLOOR_UP := 0.03                      # m, the ground floor over the highest ground along the street

var frame: Transform3D                      # the residence's frame (global)
var floor_z := 0.0                          # m, its ground floor
var foot := 0.0                             # m, its masses' foot (in its frame: under the lowest ground round it)
var residence: Node3D                       # what the builder made


## The world without #184 (builder/world_builder.gd, before the buildings are made): its building record, its name
## sign, the kit modules on it.
static func drop(world: Dictionary) -> void:
	WorldEdits.drop_buildings(world, [BUILDING_ID], WorldEdits.grown(PackedVector2Array(FOOTPRINT), 1.0))


## The residence's frame: x east along the south facade, y up, z south (the plan's v north is -z); its origin on the
## ground floor at the south-west corner.
static func residence_frame(z := 0.0) -> Transform3D:
	var d := (EAST - ORIGIN).normalized()
	return Transform3D(Basis(Vector3(d.x, 0, -d.y), Vector3.UP, Vector3(d.y, 0, d.x)), Vector3(ORIGIN.x, z, -ORIGIN.y))


func _ready() -> void:
	name = "AllSuites"
	# the ground floor over the highest ground under the residence and along its street facades, its foot under
	# the lowest ground round it
	frame = residence_frame(0.0)
	var f0 := frame
	var at := func(u: float, v: float) -> float:
		var g := f0 * Vector3(u, 0.0, -v)
		return Marks.ground(g.x, -g.z)
	var top := -INF
	var low := INF
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(Builder.LEN, 0), Vector2(Builder.LEN, Builder.NORTH),
			Vector2(Builder.LEN - Builder.WING, Builder.NORTH), Vector2(Builder.LEN - Builder.WING, Builder.BAR),
			Vector2(Builder.WING, Builder.BAR), Vector2(Builder.WING, Builder.NORTH), Vector2(0, Builder.NORTH)])
	for i in 36:
		for j in 26:
			var p := Vector2(-1.5 + i * 2.0, -1.5 + j * 2.0)
			var inside := Geometry2D.is_point_in_polygon(p, outline)
			var near_street := p.y < 0.5 or ((p.x < 0.5 or p.x > Builder.LEN - 0.5) and p.y < Builder.BAR)
			var g: float = at.call(p.x, p.y)
			if inside or near_street:
				top = maxf(top, g)
			if inside or p.x < 0.0 or p.x > Builder.LEN or p.y < 0.0 or p.y > Builder.NORTH:
				low = minf(low, g)
	floor_z = top + FLOOR_UP
	frame = residence_frame(floor_z)
	var fz := floor_z
	var ground := func(u: float, v: float) -> float: return float(at.call(u, v)) - fz
	foot = low - floor_z - 0.6
	residence = Builder.new().build(ground, foot, DisplayServer.get_name() != "headless")   # (headless: collision only)
	residence.transform = frame
	add_child(residence)


## A point of the plan (u east along the south facade, v north, y up from the ground floor), global.
func at(u: float, y: float, v: float) -> Vector3:
	return frame * Vector3(u, y, -v)


## The map's ground under the plan's (u, v), in the residence's frame (from its ground floor).
func ground_at(u: float, v: float) -> float:
	var g := at(u, 0.0, v)
	return Marks.ground(g.x, -g.z) - floor_z
