extends Node
## PTA Online at the boat hire on the Lac de l'X (scripts/baseNautique/: the lot), Main/Mode/BoatHire under
## scripts/modes/online_mode.gd: its counter is the terminal of a garage of kind "lake", on the maps. There a player buys
## a jet-ski (it goes in their garage: data/prices.json, place "lake"), hires one (rentals: so many minutes for so much,
## shop.gd rent_for; the mode takes it back at the end, a minute's warning first) or gets their own out; any of them
## comes out on the first free slip by the pontoon (the garage's "slips"). Its terminal is the lot's self-service till
## on the counter ("own_terminal": no kiosk of the garages').

const GID := "base-nautique"                # its garage (mode.garages)

var mode: Node                              # scripts/modes/online_mode.gd


func _ready() -> void:
	var base: Node = mode.game.get("baseNautique") if mode and mode.game else null
	if base == null:
		return
	var g := {"id": GID, "name": base.NAME, "kind": "lake", "xy": base.map_xy(), "terminal": base.terminal(),
			"facing": Vector3.FORWARD, "bays": [], "slips": base.slips(), "own_terminal": true}
	mode.garages.list.append(g)
	mode.garages.by_id[GID] = g
