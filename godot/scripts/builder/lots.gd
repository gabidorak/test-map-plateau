extends RefCounted
## Lots: each change made to the map (a building replaced, a garden redone, a villa built) is one lot,
## data/lots/<id>.json, that ties its three phases together:
##   "terraform"  its zones (data/terraform/<name>.json, tools/terraform.py), applied first: builder/terraform.gd
##   "script"     its own code: drop(world) takes out of the map what it replaces (when the map is built,
##                builder/world_builder.gd); its node is made in the game (game.gd), held by game's member "node"
##   "paint"      a script whose repaint() paints the ground in its grounds (builder/ground_builder.gd)
##   "restyle"    restyled buildings' specs (data/restyle/<slug>.json, scripts/restyle/): their drop, paint and node
## The order: every lot's terraforming, then their drops, then the map's own builds, then (in the game) their nodes.
## The railway's lots (the RER B line, Massy-Palaiseau, the bus depot, the Logements de l'X) are not lots yet: their
## designed ground is patched into the map by tools/rail/patch_world.py (rail.json); see LOTS.md.
## No preloads (terraform.gd and the restyled buildings' specs read it): the lots' scripts are loaded by path.

const DIR := "res://data/lots/"
const RESTYLE := "res://scripts/restyle/restyle.gd"

static var _lots: Array = []


## Every lot, in its "order".
static func all() -> Array:
	if _lots.is_empty() and DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".json"):
				var lot: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
				if lot is Dictionary:
					_lots.append(lot)
		_lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return _lots


## The terraforming files the lots name.
static func terraform_files() -> Array:
	var out := []
	for lot: Dictionary in all():
		out.append_array(lot.get("terraform", []))
	return out


## The restyled buildings' specs the lots name.
static func restyle_slugs() -> Array:
	var out := []
	for lot: Dictionary in all():
		out.append_array(lot.get("restyle", []))
	return out


## When the map is built: what each lot replaces out of the world.
static func drop(world: Dictionary) -> void:
	for lot: Dictionary in all():
		if lot.has("script"):
			load(str(lot["script"])).drop(world)
	if not restyle_slugs().is_empty():
		load(RESTYLE).drop(world)


## When the map is built: the ground's paint in the lots' grounds (a chunk's vertices; materials' ids and colours).
static func repaint(verts: PackedVector3Array, ids: PackedByteArray, colours: PackedColorArray, materials: Array,
		palette: Dictionary) -> Array:
	var rp := [ids, colours]
	for lot: Dictionary in all():
		if lot.has("paint"):
			rp = load(str(lot["paint"])).repaint(verts, rp[0], rp[1], materials, palette)
	if not restyle_slugs().is_empty():
		rp = load(RESTYLE).repaint(verts, rp[0], rp[1], materials, palette)
	return rp


## In the game: each lot's node (game's member "node"), then the restyled buildings'.
static func spawn(game: Node) -> void:
	for lot: Dictionary in all():
		if lot.has("node"):
			var n: Node = load(str(lot["script"])).new()
			if "game" in n:
				n.set("game", game)
			game.set(str(lot["node"]), n)
			game.add_child(n)
	if not restyle_slugs().is_empty():
		var r: Node = load(RESTYLE).new()
		game.set("restyle", r)
		game.add_child(r)
