extends Node
## Base of the game modes (scripts/modes/modes.gd lists them). game.gd makes the one being played as Main/Mode on every
## peer: the host's pick (the welcome menu, or --mode=ID), which clients get with the host's welcome (net.gd), so that
## a mode's RPCs have the same path everywhere. A mode:
## - says which of the game's features it keeps (allows: game.gd asks before parking the start cars, opening the
##   vehicle menu...);
## - hears when the game starts here (begin) and when a player joins (player_registered, host side); it goes with the
##   scene, or when another mode replaces it;
## - gets the keys and mouse before game.gd (handle_input), and a round of an armed vehicle that hit one of its things
##   (round_hit);
## - adds to the help lines (walk_help, extra_help) and to the in-game menu (pause_info, host_actions).
## The defaults keep everything as it was: scripts/modes/sandbox_mode.gd. A new mode is a script extending this one and
## a row in modes.gd.

var game: Node3D                            # game.gd, set before adding the mode
var id := ""                                # its key in modes.gd


## Whether the game's feature `feature` is on in this mode:
## "debug_cars" (the cars parked next to the player at start), "showrooms" (the dealership's display cars and its
## salesman), "bot_traffic" (bot buses and cars, and the host's switch for them), "trains" (the RER B), "races",
## "vehicle_menu" (U), "park_car" (C), "clear_vehicles" (the host's button), "night_toggle" (N, the settings page's
## time of day), "inspect" (F), "fly_camera" (F1).
func allows(_feature: String) -> bool:
	return true


## The game started here, the player in: game.mode says how ("solo", "host", "client" or "server").
func begin() -> void:
	pass


## Host: player `peer_id` was let in and has the players and vehicles (net.gd `registered`): send them the mode's state.
func player_registered(_peer_id: int) -> void:
	pass


## A key or mouse event while playing with no menu open, before game.gd's own handling: true when taken.
func handle_input(_event: InputEvent) -> bool:
	return false


## A round of an armed vehicle simulated here (game.gd _on_round_hit) hit `collider`: true when it was one of the mode's
## (game.gd then leaves it).
func round_hit(_collider: Object, _point: Vector3, _velocity: Vector3) -> bool:
	return false


## The help lines while walking, in place of game.gd's ("" keeps them). `k` names a key: k.call("jump").
func walk_help(_k: Callable) -> String:
	return ""


## Lines under game.gd's help, whatever the player does.
func extra_help(_k: Callable) -> String:
	return ""


## The in-game menu's line about this game ("" for game.gd's own).
func pause_info() -> String:
	return ""


## The host's (or solo player's) buttons in the in-game menu: [[text, Callable]].
func host_actions() -> Array:
	return []
