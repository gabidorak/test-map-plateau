extends Node3D
## Lot baseNautique (data/lots/baseNautique.json): the boat hire on the Lac de l'X, on the gravel of the Cour des
## cérémonies by the south shore (Thomas's plan: ref/VendeurJetSki/). A kiosk with its counter (PTA Online's terminal:
## buy a jet-ski or hire one, scripts/online/boat_hire.gd), a floating pontoon into the lake, its slips (where a
## jet-ski bought or hired comes out: slips()), two of the base's jet-skis moored for show, flags, a lifebuoy, the price
## board, all on a wooden terrace fenced round (its gate on the esplanade), two palm trees and tables under parasols on
## it; a bin and a lamp by it (map props). Drawn at start (base_nautique_builder.gd) on the water's level as the game finds
## it; the ground is left as it is (the gravel).

const Builder = preload("res://scripts/baseNautique/base_nautique_builder.gd")
const NAME := "Base nautique du lac"
## Its grounds (map x, y): the map's trees and props in them go.
const SITE := Rect2(739.0, 187.0, 33.0, 42.0)

var game: Node                              # game.gd (null in the tools)
var built: Node3D                           # what the builder made


## The world without the map's trees and props on its grounds; its bin and lamp in.
static func drop(world: Dictionary) -> void:
	world["trees"] = world["trees"].filter(func(t: Dictionary) -> bool: return not SITE.has_point(Vector2(t["x"], t["y"])))
	world["props"] = world["props"].filter(func(p: Dictionary) -> bool: return not SITE.has_point(Vector2(p["x"], p["y"])))
	var k := 0
	for p: Array in [["bin_vigipirate", 752.3, 188.3, 0.0], ["lamp_path", 760.7, 199.2, 0.0], ["lamp_path", 747.0, 188.2, 0.0]]:
		world["props"].append({"id": "lot:baseNautique:prop:%d" % k, "kind": p[0], "model": p[0], "x": p[1], "y": p[2],
				"yaw": p[3], "lift": 0.0, "src": "lot"})
		k += 1


func _ready() -> void:
	name = "BaseNautique"
	built = Builder.new().build(DisplayServer.get_name() != "headless")
	add_child(built)


## The counter (global): PTA Online's terminal.
func terminal() -> Vector3:
	return built.get_meta("terminal")


## The slips by the pontoon (global transforms on the water, facing out into the lake): a jet-ski comes out on the
## first free one.
func slips() -> Array:
	return built.get_meta("slips")


## Its place on the maps (map x, y).
func map_xy() -> Vector2:
	var t := terminal()
	return Vector2(t.x, -t.z)
