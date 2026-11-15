extends RefCounted
## What the bots see (scripts/traffic/traffic.gd refreshes it first thing every physics tick, update(); its bots,
## scripts/traffic/bus_bot.gd, and the RER B's look at it): the vehicles out, the people on foot and the emergency
## vehicles, as of this tick, on grids of CELL m cells so that a look around goes only through what is near.
## - Vehicles: every vehicle out (game.gd cars, not stowed): its footprint centre (`pos`), velocity (`vel`, BusBot
##   velocity_of: a gliding bot is frozen, yet it moves), heading (`fwd`) and half length (`reach`); its footprint
##   (footprint()) is made once a tick, for the first bot that looks at it. near() lists those about a point.
## - Emergency vehicles: those with their siren on (car.gd `siren`: the fire truck's, the police car's), `sirens`: a
##   short list every bot goes through (bus_bot.gd makes way for them).
## - Walkers: the nodes of the group GROUP that walk on the map now (shown, and their walking() true when they have one:
##   the player, scripts/player.gd, and the other players, scripts/remote_player.gd; a pedestrian to come joins the
##   group), with their height (one on a bridge is not on the road under it) and a velocity from where they were the tick
##   before (a jump of more than WALK_MAX m/s is a teleport: still). walkers_near() lists those about a point (all of
##   them while they are a few: SCAN_MAX).
## Positions are pipeline x/y (x east, y north; Godot = (x, -z)).

const BusBot = preload("res://scripts/traffic/bus_bot.gd")

const GROUP := "walkers"                    # the group of the people on foot the bots look out for
const WALK_MAX := 12.0                      # m/s: moved faster than this since the last tick, a walker was teleported
const SCAN_MAX := 12                        # walkers up to this many are all gone through, not looked up on the grid
const CELL := 50.0                          # m, the grids' cells
const CELL_KEY := 65536                     # grid key: x cell * CELL_KEY + y cell

# the vehicles out
var cars: Array = []
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var fwd := PackedVector2Array()
var reach := PackedFloat32Array()
var reach_max := 0.0                        # the longest half length among them
var sirens := PackedInt32Array()            # indices of those with their siren on
# the walkers
var walkers: Array = []
var walker_pos := PackedVector2Array()
var walker_y := PackedFloat32Array()        # their feet's height (Godot y)
var walker_vel := PackedVector2Array()

var _feet: Array = []                       # the vehicles' footprints (footprint()), null until a bot looks at one
var _cells := {}                            # grid key -> Array of vehicle indices
var _walker_cells := {}                     # grid key -> Array of walker indices
var _last := {}                             # walker -> where it was at the last update (velocities)


## This tick's view: `vehicles` (game.gd cars), the walkers of `tree`'s GROUP, `delta` s after the last update.
func update(tree: SceneTree, vehicles: Array, delta: float) -> void:
	cars.clear()
	pos.clear()
	vel.clear()
	fwd.clear()
	reach.clear()
	sirens.clear()
	reach_max = 0.0
	_cells.clear()
	for c: Node3D in vehicles:
		if c.stowed:
			continue
		var xf: Transform3D = c.global_transform
		var p := BusBot.flat(xf * c.extents_center)
		_file(_cells, p, cars.size())
		if c.siren:
			sirens.append(cars.size())
		cars.append(c)
		pos.append(p)
		vel.append(BusBot.velocity_of(c))
		fwd.append(BusBot.flat(xf.basis.z).normalized())
		reach.append(c.half_extents.z)
		reach_max = maxf(reach_max, c.half_extents.z)
	_feet.clear()
	_feet.resize(cars.size())
	_update_walkers(tree, delta)


func _update_walkers(tree: SceneTree, delta: float) -> void:
	walkers.clear()
	walker_pos.clear()
	walker_y.clear()
	walker_vel.clear()
	_walker_cells.clear()
	var seen := {}
	for n: Node in tree.get_nodes_in_group(GROUP):
		var w := n as Node3D
		if w == null or not w.is_visible_in_tree() or (w.has_method("walking") and not w.walking()):
			continue
		var p := BusBot.flat(w.global_position)
		var v := Vector2.ZERO
		if _last.has(w) and delta > 0.0:
			v = (p - _last[w]) / delta
			if v.length() > WALK_MAX:
				v = Vector2.ZERO
		seen[w] = p
		_file(_walker_cells, p, walkers.size())
		walkers.append(w)
		walker_pos.append(p)
		walker_y.append(w.global_position.y)
		walker_vel.append(v)
	_last = seen


static func _file(cells: Dictionary, p: Vector2, index: int) -> void:
	var key := floori(p.x / CELL) * CELL_KEY + floori(p.y / CELL)
	var cell: Array = cells.get(key, [])
	if cell.is_empty():
		cells[key] = cell
	cell.append(index)


## Indices of the vehicles whose footprint centre may be within `r` m of `p` (pipeline x/y): those in the grid cells the
## square around it touches.
func near(p: Vector2, r: float) -> Array:
	return _query(_cells, p, r)


## Indices of the walkers who may be within `r` m of `p`, likewise (all of them while they are SCAN_MAX or fewer).
func walkers_near(p: Vector2, r: float) -> Array:
	if walkers.size() <= SCAN_MAX:
		return range(walkers.size())
	return _query(_walker_cells, p, r)


static func _query(cells: Dictionary, p: Vector2, r: float) -> Array:
	var out := []
	if cells.is_empty():
		return out
	for x in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
		for y in range(floori((p.y - r) / CELL), floori((p.y + r) / CELL) + 1):
			var cell: Variant = cells.get(x * CELL_KEY + y)
			if cell != null:
				out.append_array(cell)
	return out


## Footprint of vehicle k (BusBot.footprint), made once per tick however many bots look at it.
func footprint(k: int) -> PackedVector2Array:
	if _feet[k] == null:
		_feet[k] = BusBot.footprint(cars[k])
	return _feet[k]


## Forgets everything (the bots stopped).
func clear() -> void:
	cars.clear()
	pos.clear()
	vel.clear()
	fwd.clear()
	reach.clear()
	sirens.clear()
	reach_max = 0.0
	_feet.clear()
	_cells.clear()
	walkers.clear()
	walker_pos.clear()
	walker_y.clear()
	walker_vel.clear()
	_walker_cells.clear()
	_last.clear()
