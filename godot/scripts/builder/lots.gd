extends RefCounted
## Lots: each change made to the map (a building replaced, a garden redone, a villa built) is one lot, a folder
## lots/<id>/ with all of it: its declaration lot.json, its data (plan, ground, drop, terraforming, restyled specs), its
## scripts, its tool (tool/, Python, out of Godot's sight: .gdignore). lot.json ties its phases together:
##   "terraform"  its zones, applied first (builder/terraform.gd): files of its folder (terraform_<name>.json, made by
##                tools/terraform.py), or a
##                script whose static terraform_zones() makes them from its design (the villa's court)
##   "drop"       its changes to the map's world as its tool decided them (lots/<lot>/drop.json:
##                builder/world_edits.gd, tools/common/world_edits.py), applied when the map is built
##   "script"     its own code: drop(world), if it has one, takes out of the map what it replaces (when the map is built,
##                builder/world_builder.gd, after its "drop"); its node is made in the game (game.gd), held by game's
##                member "node"
##   "paint"      a script whose repaint() paints the ground in its grounds (builder/ground_builder.gd)
##                (its script's surface_boxes() and surface_at(): its surfaces in the map's ground the game reads, its
##                roads, paving, lawns, baked when the map is built: builder/ground_bake.gd)
##   "restyle"    restyled buildings' specs (<slug>.json in its folder, tools/restyle.py; scripts/restyle/): their drop,
##                paint and node
##   "parent"     the lot it is part of (a block's own lot, whose plan the block's lots share): it comes after its
##                parent, its terraforming on the parent's, where the parent's script's child_weight(x, y) lets it
##                (inside the block, not under its streets)
##   (ground)     its script's ground_owned(): polygons (map) where it owns the ground, steps and walls and all: the
##                map's ground mesh and terrain collision cut out there (builder/ground_cut.gd), the lot draws and
##                collides its own
##   "ground"     its own ground's data, lots/<lot>/ (builder/lot_ground.gd, made by its tool with
##                tools/common/lot_ground.py): its zones cut out of the map's ground and drawn on their heights, walls
##                and all, its repairs terraformed
##   "build"      a builder run when the map is built, with the map's own builds (its build(root, world, heights,
##                mesh_dir)): the railway's lots (their plans, ground and drop made by godot/lots/rerB/tool/)
##   "finished"   true: its node's builds and its restyled buildings are built into the map when the map is built
##                (builder/lot_bake.gd), and its node in the game takes them back (baked()) and only brings them to
##                life (a door, a terminal); unfinished, they are built at start, so a change needs no map rebuilt
## The order: parents first, then their children (each level by "order"); every lot's terraforming, one zone on the
## other in that order, then their drops, then the map's own builds, then (in the game) their nodes.
## The railway's lots (rerB, massyPalaiseau with its bus depot) and logementsX have no node: their "build" makes them
## when the map is built, their own ground ("ground") and their changes to the world ("drop") with it.
## No preloads (terraform.gd and the restyled buildings' specs read it): the lots' scripts are loaded by path.

const DIR := "res://lots/"
const RESTYLE := "res://scripts/restyle/restyle.gd"
const LOT_FAR := "res://scripts/builder/lot_far.gd"
const LOT_GROUND := "res://scripts/builder/lot_ground.gd"
const WORLD_EDITS := "res://scripts/builder/world_edits.gd"
const BAKED := "Lots"                       # the finished lots' builds in the map's scene: Lots/<id>(/<slug>)

static var _lots: Array = []
## While the map is built (builder/lot_bake.gd): the finished lots build their meshes, display or not.
static var baking := false


## Every lot: each parent before its children, each level in its "order".
static func all() -> Array:
	if _lots.is_empty() and DirAccess.dir_exists_absolute(DIR):
		var found := {}
		for d in DirAccess.get_directories_at(DIR):
			if FileAccess.file_exists(DIR + d + "/lot.json"):
				var l: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + d + "/lot.json"))
				if l is Dictionary:
					if str(l["id"]) != d:
						push_error("lots/%s/lot.json: its id is %s" % [d, l["id"]])
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


## Whether lot `l` is finished (its "finished": built into the map, builder/lot_bake.gd).
static func finished(l: Dictionary) -> bool:
	return bool(l.get("finished", false))


## Whether a lot's builders make meshes: with a display, or when the map is built; else (headless) collision only.
static func meshes() -> bool:
	return baking or DisplayServer.get_name() != "headless"


## Lot `id`'s builds as baked into the map (Lots/<id>; `name`: one of them, a restyled building's slug), or null: the
## lot not finished, or the map built before it was (then the lot builds them itself).
static func baked(game: Node, id: String, name := "") -> Node3D:
	if baking or game == null or not finished(lot(id)):
		return null
	var root: Node = game.get("world_root")
	var n: Node = root.get_node_or_null(NodePath("%s/%s" % [BAKED, id])) if root else null
	if n and name != "":
		n = n.get_node_or_null(NodePath(name))
	return n as Node3D


## Meta `key` of `n` naming nodes (a node, or an array of them), as nodes: when baked they are paths from `n`.
static func node_meta(n: Node, key: String) -> Variant:
	var v: Variant = n.get_meta(key)
	if v is NodePath:
		return n.get_node(v)
	if v is Array:
		return (v as Array).map(func(e: Variant) -> Variant: return n.get_node(e) if e is NodePath else e)
	return v


## The lot whose "restyle" names `slug` ({} if none).
static func restyle_lot(slug: String) -> Dictionary:
	for l: Dictionary in all():
		if slug in l.get("restyle", []):
			return l
	return {}


## Lot `id`'s folder.
static func dir_of(id: String) -> String:
	return DIR + id + "/"


## The lot `id` ({} if none).
static func lot(id: String) -> Dictionary:
	for l: Dictionary in all():
		if l["id"] == id:
			return l
	return {}


## The terraforming the lots name, in order: [name (a file of its folder, or a script), where it may act (its
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
		if l.has("ground"):                         # (its own ground's repairs: builder/lot_ground.gd)
			out.append([str(l["ground"]), clip])
	return out


## The ground the lots own (their scripts' ground_owned(), their "ground"'s owned zones: polygons on the map), cut
## out of the map's (ground_cut.gd).
static func owned_ground() -> Array:
	var out := []
	for lot: Dictionary in all():
		if lot.has("script") and load(str(lot["script"])).has_method("ground_owned"):
			out.append_array(load(str(lot["script"])).ground_owned())
		if lot.has("ground"):
			out.append_array(load(LOT_GROUND).of(str(lot["ground"])).owned())
	return out


## The lots' own grounds (their "ground": builder/lot_ground.gd), in the lots' order.
static func grounds() -> Array:
	return all().filter(func(l: Dictionary) -> bool: return l.has("ground")).map(
			func(l: Dictionary) -> RefCounted: return load(LOT_GROUND).of(str(l["ground"])))


## When the map is built: the owned zones' heights into the heightmap (builder/lot_ground.gd stamp()).
static func stamp_grounds(heights: PackedFloat32Array, t: Dictionary) -> int:
	var n := 0
	for g: RefCounted in grounds():
		n += g.stamp(heights, t)
	return n


## The restyled buildings' specs the lots name.
static func restyle_slugs() -> Array:
	var out := []
	for lot: Dictionary in all():
		out.append_array(lot.get("restyle", []))
	return out


## When the map is built: each lot's builder ("build"), in the lots' order; the first error stops them.
static func build(root: Node3D, world: Dictionary, heights: PackedFloat32Array, mesh_dir: String,
		shared: RefCounted = null) -> Error:
	for lot: Dictionary in all():                  # their own ground first (builder/lot_ground.gd)
		if lot.has("ground"):
			var t0 := Time.get_ticks_msec()
			var lost: float = load(LOT_GROUND).of(str(lot["ground"])).draw(root, world, mesh_dir,
					load("res://scripts/ground_map.gd").get_map(), shared, "LotGround_" + str(lot["id"]))
			print("lot %s: its own ground drawn (%d ms)" % [lot["id"], Time.get_ticks_msec() - t0])
			if lost > 0.01:
				push_warning("lot %s: %.2f m² of its own ground not drawn" % [lot["id"], lost])
	for lot: Dictionary in all():
		if lot.has("build"):
			var r: Variant = load(str(lot["build"])).new().build(root, world, heights, mesh_dir)
			if r is int and r != OK:
				push_error("lot %s: its build failed (%s)" % [lot["id"], error_string(r)])
				return r
	return OK


## When the map is built: what each lot replaces out of the world.
static func drop(world: Dictionary) -> void:
	for lot: Dictionary in all():
		if lot.has("drop"):
			load(WORLD_EDITS).apply_file(world, str(lot["drop"]))
		if lot.has("script") and load(str(lot["script"])).has_method("drop"):
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
