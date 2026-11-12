extends RefCounted
## Lots: each change made to the map (a building replaced, a garden redone, a villa built) is one lot,
## data/lots/<id>.json, that ties its three phases together:
##   "terraform"  its zones, applied first (builder/terraform.gd): files of data/terraform/ (tools/terraform.py), or a
##                script whose static terraform_zones() makes them from its design (the villa's court)
##   "script"     its own code: drop(world) takes out of the map what it replaces (when the map is built,
##                builder/world_builder.gd); its node is made in the game (game.gd), held by game's member "node"
##   "paint"      a script whose repaint() paints the ground in its grounds (builder/ground_builder.gd)
##   "restyle"    restyled buildings' specs (data/restyle/<slug>.json, scripts/restyle/): their drop, paint and node
##   "parent"     the lot it is part of (a block's own lot, whose plan the block's lots share): it comes after its
##                parent, its terraforming on the parent's, where the parent's script's child_weight(x, y) lets it
##                (inside the block, not under its streets)
## The order: parents first, then their children (each level by "order"); every lot's terraforming, one zone on the
## other in that order, then their drops, then the map's own builds, then (in the game) their nodes.
## The railway's lots (the RER B line, Massy-Palaiseau, the bus depot, the Logements de l'X) are not lots yet: their
## designed ground is patched into the map by tools/rail/patch_world.py (rail.json); see LOTS.md.
## No preloads (terraform.gd and the restyled buildings' specs read it): the lots' scripts are loaded by path.

const DIR := "res://data/lots/"
const RESTYLE := "res://scripts/restyle/restyle.gd"
const LOT_FAR := "res://scripts/builder/lot_far.gd"

static var _lots: Array = []


## Every lot: each parent before its children, each level in its "order".
static func all() -> Array:
	if _lots.is_empty() and DirAccess.dir_exists_absolute(DIR):
		var found := {}
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".json"):
				var l: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
				if l is Dictionary:
					found[str(l["id"])] = l
		for l: Dictionary in found.values():
			if l.has("parent") and not found.has(str(l["parent"])):
				push_error("lot %s: no parent lot %s" % [l["id"], l["parent"]])
				l.erase("parent")
		_add_level(found.values(), "")
	return _lots


static func _add_level(lots: Array, parent: String) -> void:
	var level := lots.filter(func(l: Dictionary) -> bool: return str(l.get("parent", "")) == parent)
	level.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	for l: Dictionary in level:
		_lots.append(l)
		_add_level(lots, str(l["id"]))


## The lot `id` ({} if none).
static func lot(id: String) -> Dictionary:
	for l: Dictionary in all():
		if l["id"] == id:
			return l
	return {}


## The terraforming the lots name, in order: [name (a file of data/terraform/, or a script), where it may act (its
## lot's parent's child_weight(x, y), a Callable; none for a lot with no parent)].
static func terraform_entries() -> Array:
	var out := []
	for l: Dictionary in all():
		var clip := Callable()
		var p := lot(str(l.get("parent", "")))
		if p.has("script") and load(str(p["script"])).has_method("child_weight"):
			clip = Callable(load(str(p["script"])), "child_weight")
		for name: String in l.get("terraform", []):
			out.append([name, clip])
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


## In the game: each lot's node (game's member "node"), then the restyled buildings'; all streamed like the map's
## buildings (builder/lot_far.gd: their far versions).
static func spawn(game: Node) -> void:
	var nodes := []
	for lot: Dictionary in all():
		if lot.has("node"):
			var n: Node = load(str(lot["script"])).new()
			if "game" in n:
				n.set("game", game)
			game.set(str(lot["node"]), n)
			game.add_child(n)
			nodes.append(n)
	if not restyle_slugs().is_empty():
		var r: Node = load(RESTYLE).new()
		game.set("restyle", r)
		game.add_child(r)
		nodes.append(r)
	var root: Node = game.get("world_root")
	var streamer: Node = root.get_node_or_null("Streamer") if root else null
	if streamer and DisplayServer.get_name() != "headless":
		for n: Node in nodes:
			load(LOT_FAR).stream(n, streamer)
