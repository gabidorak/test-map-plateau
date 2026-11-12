extends Node3D
## Lot superette258 (data/lots/superette258.json): the 25/8 supermarket ("open 25 hours a day, 8 days a week"), its
## filling station and its car park, in place of the SMAT (#813) and #851 and the sheds round them, on the block's
## master plan (scripts/ilot/ilot_plan.gd; its ground and public spaces are the block's own lot, ilot-001, its parent). Drawn at start
## (superette_builder.gd); no interior. The EV chargers, the waste containers and the lorries' barriers are map props.

const Plan = preload("res://scripts/ilot/ilot_plan.gd")
const WorldEdits = preload("res://scripts/builder/world_edits.gd")
const Builder = preload("res://scripts/superette/superette_builder.gd")
## The map's buildings it replaces: the SMAT (#813), #851, and the sheds #821, #825, #806, #829, #793, #792, #831.
const REPLACED := ["osm:w71344427", "osm:w71353621", "osm:w71343181", "osm:w71347453", "osm:w71350574",
		"osm:w71351750", "osm:w71352724", "osm:w71355510", "osm:w71356397"]
const SITE := Rect2(419.0, -177.0, 67.0, 93.0)      # its grounds, local (the kit modules standing in it go)

var game: Node


## The world without the buildings it replaces; its props in.
static func drop(world: Dictionary) -> void:
	var area := PackedVector2Array()
	for c: Vector2 in [SITE.position, Vector2(SITE.end.x, SITE.position.y), SITE.end, Vector2(SITE.position.x, SITE.end.y)]:
		area.append(Plan.to_map(c))
	WorldEdits.drop_buildings(world, REPLACED, area)
	var up := Builder.KERB                   # (on the forecourt's paving)
	var props := []                          # [model, u, v, yaw (where its front faces), scale, lift]
	for x: float in Builder.ev_bays():
		props.append(["charging_station", x, -172.55, 90.0, [1.0, 1.0], 0.0])
	for x: float in [469.6, 472.0, 474.4]:
		props.append(["waste_container", x, -98.6, 270.0, [1.0, 1.0], 0.0])
	props.append(["recycling_column", 476.6, -98.8, 270.0, [1.0, 1.0], 0.0])
	for r: Rect2 in [Plan.TRUCK_IN, Plan.TRUCK_OUT]:   # the lorries' barriers, an arm from each side
		var y := r.position.y + 1.0
		props.append(["lift_gate", r.position.x + 2.0, y, 270.0, [0.95, 1.0], 0.0])
		props.append(["lift_gate", r.end.x - 2.0, y, 90.0, [0.95, 1.0], 0.0])
	for p: Array in [[426.8, -133.4], [449.4, -133.4], [449.4, -171.6]]:
		props.append(["cctv_pole", p[0], p[1], 0.0, [1.0, 1.0], 0.0])
	props.append(["parcel_locker", 429.5, -122.6, 270.0, [1.0, 1.0], up])
	props.append(["vending_machine", 477.0, -122.6, 270.0, [1.0, 1.0], up])
	props.append(["gas_bottles", 471.0, -122.7, 270.0, [1.0, 1.0], up])
	var turn := rad_to_deg(Plan.ANGLE)       # (placed in the block's frame: turned onto the map)
	var k := 0
	for p: Array in props:
		var m := Plan.to_map(Vector2(p[1], p[2]))
		world["props"].append({"id": "lot:superette258:prop:%d" % k, "kind": p[0], "model": p[0], "x": m.x,
				"y": m.y, "yaw": fposmod(float(p[3]) + turn, 360.0), "lift": p[5], "scale": p[4], "src": "lot"})
		k += 1


func _ready() -> void:
	name = "Superette258"
	add_child(Builder.new().build(DisplayServer.get_name() != "headless"))
