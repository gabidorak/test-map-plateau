extends RefCounted
## The game modes, in the welcome menu's order: id -> its title, a line about it, the solo button's text and the script
## game.gd makes Main/Mode from (extending scripts/modes/game_mode.gd). A new mode is a script and a row here.
## Scripts are loaded when a game starts, not preloaded: the tools preload game.gd before the autoloads exist.

const DEFAULT := "sandbox"
const LIST := {
	"sandbox": {
		"title": "Sandbox",
		"about": "The whole plateau to explore: drive, fly, race, ride the buses and the RER B.",
		"solo": "Explore solo",
		"script": "res://scripts/modes/sandbox_mode.gd",
	},
	"escape": {
		"title": "Escape from Plateau",
		"about": "Night, fog, and the dead walk the campus. Find the survivors, carry them to the rescue helicopter, " \
				+ "get out before dawn. Co-op, 1 to 8 players.",
		"solo": "Play solo",
		"script": "res://scripts/escape/escape_mode.gd",
	},
	"online": {
		"title": "PTA Online",
		"about": "The official server: your own garage, jobs and money.",
		"solo": "Play solo",
		"script": "res://scripts/modes/online_mode.gd",
		"menu": false,
	},
}
const ONLINE := "online"


static func ids() -> Array:
	return LIST.keys()


static func valid(id: String) -> bool:
	return LIST.has(id)


## The modes the welcome menu offers for solo and LAN games.
static func pickable() -> Array:
	return LIST.keys().filter(func(id: String) -> bool: return LIST[id].get("menu", true))


static func title(id: String) -> String:
	return LIST[id]["title"] if LIST.has(id) else id


static func about(id: String) -> String:
	return LIST[id]["about"] if LIST.has(id) else ""


static func solo_text(id: String) -> String:
	return LIST[id]["solo"] if LIST.has(id) else "Play solo"


## A new Main/Mode node for mode `id` (the default one for an unknown id).
static func make(id: String) -> Node:
	if not LIST.has(id):
		id = DEFAULT
	var node: Node = load(LIST[id]["script"]).new()
	node.name = "Mode"
	node.id = id
	return node
