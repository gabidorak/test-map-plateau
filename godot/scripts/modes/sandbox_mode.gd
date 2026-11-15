extends "res://scripts/modes/game_mode.gd"
## Sandbox: the plateau as it always was. Every feature on (the cars parked at start, bot traffic, the RER B, races,
## showrooms, the vehicle menu...), day or night as the player likes; nothing to win. The inventory (I) hands out every
## item for nothing (scripts/items/items.gd), like the vehicle menu every vehicle; no safe place.


func free_items() -> bool:
	return true
