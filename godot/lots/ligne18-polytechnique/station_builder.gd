extends "res://scripts/build_kit.gd"
## Polytechnique's station drawn (lot ligne18-polytechnique; polytechnique_plan.gd: its shapes and levels), in the
## station's frame (Line.station_transform(): local (u, y, -v), y over the hall's floor), three cells (each a node:
## builder/lot_far.gd streams them):
## - deck(): the deck over the zone (u -45..45): the line's section() extruded (the tracks' bed at deck_top_z, the
##   spine, the soffit; its end faces section() exactly, face to face with the viaduct's), the two side platforms
##   (60 m, their edge at PLAT_V.x, their top at platform_z) on the deck widened under them, the platform screens
##   (glass, their doors framed), the balustrades over the hall, the landings of the stairs and lifts, the parapets
##   and the walkway's handrail beyond the platforms; the station's single elliptic piers (flared heads) under the
##   axis, the platforms' columns, and at u = +-45 the end supports the viaduct's first spans rest on (a cross-beam on
##   two shafts, its top at rail_z - SOFFIT_UNDER_RAIL - BEARING, the bearings on it);
## - hall(): the hall at the ground (its floor at hall_z, the opaque base under the glass: terracotta panels along the
##   north folds, the ends' doors to the passage under the deck), the white "Gare" box (ribbed steel sheet, its sign),
##   the terracotta east box, the shops building (1 000 m², square to the boulevard: glass on the forecourt, a wooden
##   roof deck), the porch of the main doors; level 1 (the mezzanines, the passerelle under the deck), the stairs and
##   escalators hall -> level 1 -> platforms on either side, the lifts;
## - envelope(): the origami: folded glass skirts from the base out to the zigzag eaves, the leaning gables (open for
##   the deck and the trains), the folded glass roof in white frames, the white steel trees holding it.
## Merged meshes (one per material), simple collision (boxes, ramps, the hall's floor as faces): a player walks from
## the forecourt through the porch, up the stairs to level 1 and on up to a platform.

const Plan = preload("res://lots/ligne18-polytechnique/polytechnique_plan.gd")
const Line = preload("res://lots/ligne18/ligne18_plan.gd")

const STEP_RISE := 0.18                     # m: a step's rise at most
const STAIR := Vector2(9.0, 11.0)           # |v| of the stairs' lane
const ESC := Vector2(11.6, 12.8)            # |v| of the escalators'
const MEZZ := Rect2(-6.0, 8.6, 14.0, 4.8)   # level 1 on either side (u, |v|)
const BRIDGE := Vector2(4.0, 8.0)           # u of the passerelle across under the deck
const FLIGHT_A := Vector2(16.7, 8.0)        # u: hall (bottom) -> level 1 (top)
const FLIGHT_B := Vector2(-6.0, -15.4)      # u: level 1 -> platforms
const LANDING := Rect2(-19.5, 8.6, 4.1, 4.8)    # at the platforms' level, where the stairs arrive
const LIFT := Rect2(-24.0, 9.4, 2.4, 2.4)   # (u, |v|) on either side
const COLUMNS_U := [-27.0, -13.5, 13.5, 27.0]
const COLUMN_V := 7.6
const GROUND_Y := Plan.FLAT - Plan.HALL_Z    # the ground round the station (the paving's top at 0)
const FOOT := 1.0                           # m: shafts into the ground
const TREE_V := 15.1                        # |v| of the steel trees

static var _ready_mats := false


func _init(cell: String) -> void:
	super(cell, {"type": "lot", "lot": "ligne18-polytechnique", "name": "Gare Polytechnique (ligne 18)",
			"about": "the station of line 18 on the plateau: %s" % cell.to_lower()})
	root.transform = Line.station_transform(Plan.ID)
	_materials()


# ---------------------------------------------------------------- the cells

## The deck, the platforms and the supports.
func deck(meshes: bool) -> Node3D:
	_deck_core()
	for side: float in [1.0, -1.0]:
		_platform(side)
		_screens(side)
	for su: float in [1.0, -1.0]:
		_end_support(su)
		_parapets(su)
	_handrail()
	for u: float in Plan.PIERS_U:
		_pier(u)
	for side: float in [1.0, -1.0]:
		for u: float in COLUMNS_U:
			ell("l18p_concrete", u, side * COLUMN_V, 0.3, 0.3, -0.2, 8.5)
			cb(u - 0.3, u + 0.3, side * COLUMN_V - 0.3, side * COLUMN_V + 0.3, -0.2, 8.5)
	return _done(meshes)


## The hall at the ground, its boxes, level 1, the stairs and lifts.
func hall(meshes: bool) -> Node3D:
	_floor()
	_base()
	_boxes()
	for side: float in [1.0, -1.0]:
		_level1(side)
		_flight(side, FLIGHT_A, 0.0, Plan.PASS_Y)
		_flight(side, FLIGHT_B, Plan.PASS_Y, Plan.PLAT_Y)
		_lift(side)
	_signs()
	return _done(meshes)


## The origami: skirts, gables, roof, its steel trees.
func envelope(meshes: bool) -> Node3D:
	for side: float in [1.0, -1.0]:
		_skirt(side)
		_trees(side)
	for east: bool in [true, false]:
		_gable(east)
	_roof()
	return _done(meshes)


func _done(meshes: bool) -> Node3D:
	var n := commit(meshes)
	for c in n.get_children():
		if c is MeshInstance3D and (c.name.contains("glass") or c.name.contains("screen")):
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


# ---------------------------------------------------------------- the deck

## The line's section() swept from u -45 to 45, its end faces the section exactly.
func _deck_core() -> void:
	var sec := Line.section()
	var cw := _signed_area(sec) < 0.0
	var h := Line.HALF_ZONE
	for i in sec.size():
		var a := sec[i]
		var b := sec[(i + 1) % sec.size()]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) if cw else Vector2(d.y, -d.x)      # (outward)
		var m := "l18p_walkway" if a.y > 0.9 and b.y > 0.9 else "l18p_concrete"
		quad(m, P(-h, a.x, Plan.RAIL_Y + a.y), P(h, a.x, Plan.RAIL_Y + a.y), P(h, b.x, Plan.RAIL_Y + b.y),
				P(-h, b.x, Plan.RAIL_Y + b.y), Vector3(0.0, n.y, -n.x))
	var idx := Geometry2D.triangulate_polygon(sec)
	for u: float in [-h, h]:
		for t in range(0, idx.size(), 3):
			var p := [sec[idx[t]], sec[idx[t + 1]], sec[idx[t + 2]]]
			tri("l18p_concrete", P(u, p[0].x, Plan.RAIL_Y + p[0].y), P(u, p[1].x, Plan.RAIL_Y + p[1].y),
					P(u, p[2].x, Plan.RAIL_Y + p[2].y), Vector3(signf(u), 0.0, 0.0))
	# its collision: the trackbed, the spine
	cb(-h, h, -Line.DECK_HALF, Line.DECK_HALF, Plan.RAIL_Y - 0.87, Plan.DECK_Y)
	cb(-h, h, -1.075, 1.075, Plan.DECK_Y, Plan.RAIL_Y + Line.WALKWAY_OVER_RAIL)


## A platform (side +1: south, v > 0): on the deck widened under it, its top at PLAT_Y; the landing of the stairs, the
## lift's footbridge.
func _platform(side: float) -> void:
	var u0 := -Plan.PLAT_U
	var u1 := Plan.PLAT_U
	var e := Plan.PLAT_V.x
	var bk := Plan.PLAT_V.y
	var under := Plan.RAIL_Y - 0.87                           # (the deck's edge underside)
	_block(u0, u1, side * e, side * Line.DECK_HALF, Plan.DECK_Y, Plan.PLAT_Y - 0.02)
	_block(u0, u1, side * Line.DECK_HALF, side * bk, under, Plan.PLAT_Y - 0.02)
	_top(u0, u1, side * e, side * (e + 0.12), "l18p_edge")
	_top(u0, u1, side * (e + 0.12), side * (e + 0.6), "l18p_tactile")
	_top(u0, u1, side * (e + 0.6), side * bk, "l18p_platform")
	var l := LANDING
	_block(l.position.x, l.end.x, side * l.position.y, side * l.end.y, Plan.PLAT_Y - 0.45, Plan.PLAT_Y - 0.02)
	_top(l.position.x, l.end.x, side * l.position.y, side * l.end.y, "l18p_platform")
	var f := Rect2(LIFT.position.x + 0.3, bk, LIFT.size.x - 0.6, LIFT.position.y - bk)
	_block(f.position.x, f.end.x, side * f.position.y, side * f.end.y, Plan.PLAT_Y - 0.4, Plan.PLAT_Y - 0.02)
	_top(f.position.x, f.end.x, side * f.position.y, side * f.end.y, "l18p_platform")
	cb(u0, u1, side * e, side * bk, Plan.PLAT_Y - 0.5, Plan.PLAT_Y)
	cb(l.position.x, l.end.x, side * l.position.y, side * l.end.y, Plan.PLAT_Y - 0.5, Plan.PLAT_Y)
	cb(f.position.x, f.end.x, side * f.position.y, side * f.end.y, Plan.PLAT_Y - 0.5, Plan.PLAT_Y)
	# the balustrade over the hall (open where the landing and the lift's footbridge meet it); the landing's own
	var y := Plan.PLAT_Y
	_balustrade(Vector2(u0, side * bk), Vector2(f.position.x, side * bk), y)
	_balustrade(Vector2(f.end.x, side * bk), Vector2(l.position.x, side * bk), y)
	_balustrade(Vector2(l.end.x, side * bk), Vector2(u1, side * bk), y)
	_balustrade(Vector2(f.position.x, side * f.position.y), Vector2(f.position.x, side * f.end.y), y)
	_balustrade(Vector2(f.end.x, side * f.position.y), Vector2(f.end.x, side * f.end.y), y)
	_balustrade(Vector2(l.position.x, side * l.end.y), Vector2(l.end.x, side * l.end.y), y)
	_balustrade(Vector2(l.position.x, side * l.position.y), Vector2(l.position.x, side * l.end.y), y)
	_balustrade(Vector2(l.end.x, side * (ESC.y + 0.1)), Vector2(l.end.x, side * l.end.y), y)
	_balustrade(Vector2(u0, side * e), Vector2(u0, side * bk), y)
	_balustrade(Vector2(u1, side * e), Vector2(u1, side * bk), y)


## The platform screens along the edge: glass panes between posts, the doors framed (four to a 15 m car), the header.
func _screens(side: float) -> void:
	var v := side * (Plan.PLAT_V.x + 0.06)
	var y0 := Plan.PLAT_Y
	var y1 := Plan.PLAT_Y + 2.15
	var u := -Plan.PLAT_U
	while u < Plan.PLAT_U - 0.01:
		var w := minf(1.875, Plan.PLAT_U - u)
		quad("glass", P(u, v, y0 + 0.05), P(u + w, v, y0 + 0.05), P(u + w, v, y1), P(u, v, y1), Vector3(0, 0, -side))
		var door := int(roundf((u + Plan.PLAT_U) / 1.875)) % 2 == 1
		bx("l18p_dark", u - (0.06 if door else 0.03), u + (0.06 if door else 0.03), v - 0.05, v + 0.05, y0, y1)
		u += w
	bx("l18p_dark", Plan.PLAT_U - 0.03, Plan.PLAT_U + 0.03, v - 0.05, v + 0.05, y0, y1)
	bx("l18p_dark", -Plan.PLAT_U, Plan.PLAT_U, v - 0.12, v + 0.12, y1, y1 + 0.42)      # the header (its lights, signs)
	bx("l18p_led", -Plan.PLAT_U, Plan.PLAT_U, v + side * 0.12, v + side * 0.125, y1 + 0.12, y1 + 0.18)
	cb(-Plan.PLAT_U, Plan.PLAT_U, v - 0.06, v + 0.06, y0, y1 + 0.42)
	for su: float in [1.0, -1.0]:                             # the platform's ends: glass screens
		var ue := su * Plan.PLAT_U
		quad("glass", P(ue, side * Plan.PLAT_V.x, y0), P(ue, side * Plan.PLAT_V.y, y0), P(ue, side * Plan.PLAT_V.y, y1),
				P(ue, side * Plan.PLAT_V.x, y1), Vector3(su, 0, 0))
		bx("l18p_dark", ue - 0.04, ue + 0.04, side * Plan.PLAT_V.x, side * Plan.PLAT_V.y, y1, y1 + 0.1)
		cb(ue - 0.05, ue + 0.05, side * Plan.PLAT_V.x, side * Plan.PLAT_V.y, y0, y1)
	for ub: float in [-22.5, -7.5, 7.5, 22.5]:               # benches along the back
		bx("l18p_steel", ub - 1.2, ub + 1.2, side * (Plan.PLAT_V.y - 0.65), side * (Plan.PLAT_V.y - 0.2), y0 + 0.42, y0 + 0.48)
		bx("l18p_dark", ub - 1.0, ub + 1.0, side * (Plan.PLAT_V.y - 0.55), side * (Plan.PLAT_V.y - 0.3), y0, y0 + 0.42)


## An end support (su +1: the west end, u = 45): two elliptic shafts, the cross-beam (its top at the plan's
## rail_z - SOFFIT_UNDER_RAIL - BEARING), the bearings of both decks on it.
func _end_support(su: float) -> void:
	var u := su * Plan.END_U
	var top := Plan.RAIL_Y - Line.SOFFIT_UNDER_RAIL - Line.BEARING
	var bottom := top - 1.4
	for v: float in [-2.2, 2.2]:
		ell("l18p_concrete", u, v, 1.0, 0.65, GROUND_Y - FOOT, bottom + 0.05)
		cb(u - 0.9, u + 0.9, v - 0.6, v + 0.6, GROUND_Y - FOOT, bottom)
	_block(u - 1.6, u + 1.6, -3.6, 3.6, bottom, top)
	cb(u - 1.6, u + 1.6, -3.6, 3.6, bottom, top)
	for du: float in [-0.75, 0.75]:
		for v: float in [-0.9, 0.9]:
			bx("l18p_bearing", u + du - 0.35, u + du + 0.35, v - 0.35, v + 0.35, top, top + Line.BEARING)


## The parapets beyond the platforms (u PLAT_U..45 at that end): posts, a top rail, cables; on both edges.
func _parapets(su: float) -> void:
	var y := Plan.DECK_Y
	for side: float in [1.0, -1.0]:
		var v := side * 4.8
		var u := su * Plan.PLAT_U
		var end := su * Line.HALF_ZONE
		while su * (end - u) > -0.01:
			bx("l18p_steel", u - 0.04, u + 0.04, v - 0.04, v + 0.04, y, y + Line.PARAPET_H)
			u += su * 1.5
		var a := P(su * Plan.PLAT_U, v, y + Line.PARAPET_H)
		var b := P(end, v, y + Line.PARAPET_H)
		rod("l18p_steel", a, b, 0.035, 6)
		for hc: float in [0.35, 0.7, 1.05]:
			rod("l18p_steel", P(su * Plan.PLAT_U, v, y + hc), P(end, v, y + hc), 0.008, 4)
		cb(minf(su * Plan.PLAT_U, end), maxf(su * Plan.PLAT_U, end), v - 0.05, v + 0.05, y, y + Line.PARAPET_H)
		bx("l18p_concrete", minf(su * Plan.PLAT_U, end), maxf(su * Plan.PLAT_U, end), side * 4.15, side * 4.7, y, y + 0.25)
		bx("l18p_fascia", minf(su * Plan.PLAT_U, end), maxf(su * Plan.PLAT_U, end), side * Line.DECK_HALF,   # (the viaduct's)
				side * Line.EDGE_HALF, Plan.RAIL_Y - 0.95, Plan.RAIL_Y - 0.40)


## The walkway's axial handrail along the spine.
func _handrail() -> void:
	var y := Plan.RAIL_Y + Line.WALKWAY_OVER_RAIL
	var u := -Line.HALF_ZONE + 1.0
	while u < Line.HALF_ZONE:
		bx("l18p_steel", u - 0.03, u + 0.03, -0.03, 0.03, y, y + 0.8)
		u += 2.0
	rod("l18p_steel", P(-Line.HALF_ZONE, 0.0, y + 0.8), P(Line.HALF_ZONE, 0.0, y + 0.8), 0.03, 6)


## A station pier under the axis: an elliptic shaft, its head flared to the soffit.
func _pier(u: float) -> void:
	var soffit := Plan.RAIL_Y - Line.SOFFIT_UNDER_RAIL
	ell("l18p_concrete", u, 0.0, 1.375, 0.75, GROUND_Y - FOOT, 4.8)
	ell("l18p_concrete", u, 0.0, 1.375, 0.75, 4.8, soffit, 1.9, 1.55)
	cb(u - 1.2, u + 1.2, -0.65, 0.65, GROUND_Y - FOOT, soffit)


# ---------------------------------------------------------------- the hall

## The hall's floor at hall_z (its collision as faces).
func _floor() -> void:
	var poly := Plan.hall_floor()
	var idx := Geometry2D.triangulate_polygon(poly)
	var faces := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		var a := P(poly[idx[t]].x, poly[idx[t]].y, 0.0)
		var b := P(poly[idx[t + 1]].x, poly[idx[t + 1]].y, 0.0)
		var c := P(poly[idx[t + 2]].x, poly[idx[t + 2]].y, 0.0)
		tri("l18p_floor", a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))
	col_faces(faces)


## The opaque base under the glass: terracotta panels along the north folds, the ends' walls with their doors (the
## passage under the deck open), the porch's doors and its canopy.
func _base() -> void:
	var h := Plan.BASE_H
	for k in Plan.FOLDS:
		var a := Plan.base_node(k, -1.0)
		var b := Plan.base_node(k + 1, -1.0)
		_wall_seg(a, b, 0.0, h, "l18p_terracotta", true)
	for east: bool in [true, false]:
		var u: float = Plan.U_BASE.x if east else Plan.U_BASE.y
		var out := -1.0 if east else 1.0
		for side: float in [1.0, -1.0]:
			_wall_seg(Vector2(u, side * Plan.PASSAGE_V), Vector2(u, side * Plan.V_IN), 0.0, h, "l18p_cladding", true)
			_doors(Vector2(u, side * 4.3), Vector2(u, side * Plan.PASSAGE_V), out)
		bx("l18p_white", u - 0.2, u + 0.2, -Plan.PASSAGE_V, Plan.PASSAGE_V, 3.0, h)
	_doors(Vector2(Plan.PORCH.x, Plan.DOOR_V), Vector2(Plan.PORCH.x + 1.6, Plan.DOOR_V), 0.0)
	_doors(Vector2(Plan.PORCH.y - 1.6, Plan.DOOR_V), Vector2(Plan.PORCH.y, Plan.DOOR_V), 0.0)
	bx("l18p_white", Plan.PORCH.x, Plan.PORCH.y, Plan.DOOR_V - 0.15, Plan.DOOR_V + 0.15, 3.0, h)
	_block(Plan.PORCH.x, Plan.PORCH.y, Plan.V_IN, Plan.WHITE_BOX.end.y, h, h + 0.35, "l18p_white")   # the canopy


## Glass doors from a to b (side panels: their collision), their transom.
func _doors(a: Vector2, b: Vector2, _out: float) -> void:
	quad("glass", P(a.x, a.y, 0.0), P(b.x, b.y, 0.0), P(b.x, b.y, 3.0), P(a.x, a.y, 3.0))
	var n := maxi(1, roundi(a.distance_to(b) / 1.4))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		bx("l18p_white", p.x - 0.05, p.x + 0.05, p.y - 0.05, p.y + 0.05, 0.0, 3.0)
	_col_seg(a, b, 0.0, 3.0, 0.1)


## The boxes: the white "Gare" box, the terracotta east box, the shops building.
func _boxes() -> void:
	var w := Plan.WHITE_BOX
	_prism(_rect(w), 0.0, Plan.WHITE_H, "l18p_cladding", "l18p_white")
	_shopfront(Vector2(w.end.x - 1.0, w.end.y), Vector2(w.position.x + 1.0, w.end.y), 0.3, 3.4, 1.8, w.get_center())
	var e := Plan.EAST_BOX
	_prism(_rect(e), 0.0, Plan.EAST_H, "l18p_terracotta", "l18p_white")
	var s := PackedVector2Array(Plan.SHOPS)
	_prism(s, 0.0, Plan.SHOPS_H, "l18p_cladding", "l18p_wood")
	var mid := Vector2(-10.0, 28.0)
	_shopfront(s[1], s[2], 0.0, Plan.SHOPS_H - 0.6, 1.5, mid)    # the west front, the south front on the forecourt
	_shopfront(s[2], s[3], 0.0, Plan.SHOPS_H - 0.6, 1.5, mid)
	for i in s.size():                                       # the roof's parapet
		var a := s[i]
		var b := s[(i + 1) % s.size()]
		_wall_seg(a, b, Plan.SHOPS_H, Plan.SHOPS_H + 0.6, "l18p_white", false)
	_block(-13.0, -9.5, 26.0, 29.5, Plan.SHOPS_H, Plan.SHOPS_H + 2.6, "l18p_white")   # the lift's head on the roof


## Glazing over a facade from a to b (u, v; its building's middle `inside`), from y0 to y1, mullions every `step`
## m, a transom at 4.2 m.
func _shopfront(a: Vector2, b: Vector2, y0: float, y1: float, step: float, inside: Vector2) -> void:
	var d := (b - a).normalized()
	var out := Vector2(d.y, -d.x)
	if out.dot((a + b) * 0.5 - inside) < 0.0:
		out = -out
	var o := out * 0.04
	quad("l18p_shopglass", P(a.x + o.x, a.y + o.y, y0), P(b.x + o.x, b.y + o.y, y0), P(b.x + o.x, b.y + o.y, y1),
			P(a.x + o.x, a.y + o.y, y1), Vector3(out.x, 0, -out.y))
	var n := maxi(1, roundi(a.distance_to(b) / step))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n) + out * 0.08
		bx("l18p_white", p.x - 0.06, p.x + 0.06, p.y - 0.06, p.y + 0.06, y0, y1)
	for y: float in [y0 + 0.02, minf(4.2, y1), y1]:
		var p := a + out * 0.08
		var q := b + out * 0.08
		rod("l18p_white", P(p.x, p.y, y), P(q.x, q.y, y), 0.07, 4)


## Level 1 on that side: the mezzanine, the passerelle across under the deck (once), their balustrades.
func _level1(side: float) -> void:
	var m := MEZZ
	var y := Plan.PASS_Y
	_block(m.position.x, m.end.x, side * m.position.y, side * m.end.y, y - 0.35, y - 0.02, "l18p_soffit")
	_top(m.position.x, m.end.x, side * m.position.y, side * m.end.y, "l18p_floor", y)
	cb(m.position.x, m.end.x, side * m.position.y, side * m.end.y, y - 0.35, y)
	if side > 0.0:
		var b := BRIDGE
		_block(b.x, b.y, -m.position.y, m.position.y, y - 0.35, y - 0.02, "l18p_soffit")
		_top(b.x, b.y, -m.position.y, m.position.y, "l18p_floor", y)
		cb(b.x, b.y, -m.position.y, m.position.y, y - 0.35, y)
		for u: float in [b.x, b.y]:
			_balustrade(Vector2(u, -m.position.y), Vector2(u, m.position.y), y)
	_balustrade(Vector2(m.position.x, side * m.end.y), Vector2(m.end.x, side * m.end.y), y)
	_balustrade(Vector2(m.position.x, side * m.position.y), Vector2(BRIDGE.x, side * m.position.y), y)
	_balustrade(Vector2(BRIDGE.y, side * m.position.y), Vector2(m.end.x, side * m.position.y), y)
	for u: float in [m.position.x, m.end.x]:                 # the ends, but where the flights arrive
		_balustrade(Vector2(u, side * m.position.y), Vector2(u, side * (STAIR.x - 0.05)), y)
		_balustrade(Vector2(u, side * (STAIR.y + 0.05)), Vector2(u, side * (ESC.x - 0.05)), y)
		_balustrade(Vector2(u, side * (ESC.y + 0.05)), Vector2(u, side * m.end.y), y)


## A flight from u0 (at y0) to u1 (at y1) on that side: the stair (its steps, stringers, balustrades: a ramp for
## the collision) and the escalator beside it.
func _flight(side: float, uu: Vector2, y0: float, y1: float) -> void:
	var n := ceili((y1 - y0) / STEP_RISE)
	var rise := (y1 - y0) / n
	var go := (uu.y - uu.x) / n                              # (signed: along u)
	var v0 := side * STAIR.x
	var v1 := side * STAIR.y
	for i in n:
		var ua := uu.x + go * i
		var ub := ua + go
		var top := y0 + rise * (i + 1)
		bx("l18p_floor", minf(ua, ub), maxf(ua, ub), minf(v0, v1), maxf(v0, v1), top - rise - 0.12, top)
	for v: float in [v0, v1]:                                # the stringers, the glass balustrades, the rails
		var o := signf(v - (v0 + v1) * 0.5) * 0.06
		quad("l18p_white", P(uu.x, v + o, y0 - 0.3), P(uu.y, v + o, y1 - 0.3), P(uu.y, v + o, y1 + 0.1), P(uu.x, v + o, y0 + 0.1))
		quad("glass", P(uu.x, v + o, y0 + 0.1), P(uu.y, v + o, y1 + 0.1), P(uu.y, v + o, y1 + 1.0), P(uu.x, v + o, y0 + 1.0))
		rod("l18p_steel", P(uu.x, v + o, y0 + 1.0), P(uu.y, v + o, y1 + 1.0), 0.03, 6)
		_col_ramp_side(uu, v + o, y0, y1)
	col_ramp(P(uu.x, (v0 + v1) * 0.5, y0), P(uu.y, (v0 + v1) * 0.5, y1), absf(v1 - v0))
	# the escalator: its truss, its steps' band, its handrails
	var e0 := side * ESC.x
	var e1 := side * ESC.y
	var em := (e0 + e1) * 0.5
	var corners := [P(uu.x, e0, y0 - 0.9), P(uu.y, e0, y1 - 0.9), P(uu.y, e1, y1 - 0.9), P(uu.x, e1, y0 - 0.9)]
	var tops := [P(uu.x, e0, y0 + 0.05), P(uu.y, e0, y1 + 0.05), P(uu.y, e1, y1 + 0.05), P(uu.x, e1, y0 + 0.05)]
	quad("l18p_steel", corners[0], corners[1], tops[1], tops[0], Vector3(0, 0, -signf(e0 - em)))
	quad("l18p_steel", corners[3], corners[2], tops[2], tops[3], Vector3(0, 0, -signf(e1 - em)))
	quad("l18p_steel", corners[0], corners[1], corners[2], corners[3], Vector3.DOWN)
	quad("l18p_escalator", tops[0], tops[1], tops[2], tops[3], Vector3.UP)
	for v: float in [e0, e1]:
		quad("glass", P(uu.x, v, y0 + 0.05), P(uu.y, v, y1 + 0.05), P(uu.y, v, y1 + 0.95), P(uu.x, v, y0 + 0.95))
		rod("l18p_rubber", P(uu.x, v, y0 + 1.0), P(uu.y, v, y1 + 1.0), 0.05, 6)
	col_ramp(P(uu.x, em, y0), P(uu.y, em, y1), absf(e1 - e0))


## A thin wall along a flight's side (collision), from the bottom's height to the top's.
func _col_ramp_side(uu: Vector2, v: float, y0: float, y1: float) -> void:
	var a := P(uu.x, v, y0 + 0.55)
	var b := P(uu.y, v, y1 + 0.55)
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	if up.y < 0.0:
		up = -up
	col_xf(Transform3D(Basis(side, up, along), (a + b) * 0.5), Vector3(0.06, 1.1, (b - a).length()))


## A lift on that side: its glass shaft from the hall to the platforms, its car.
func _lift(side: float) -> void:
	var l := LIFT
	var v0 := side * l.position.y
	var v1 := side * l.end.y
	var top := Plan.PLAT_Y + 2.8
	for c: Vector2 in [Vector2(l.position.x, v0), Vector2(l.end.x, v0), Vector2(l.position.x, v1), Vector2(l.end.x, v1)]:
		bx("l18p_white", c.x - 0.08, c.x + 0.08, c.y - 0.08, c.y + 0.08, 0.0, top)
	var pts := [Vector2(l.position.x, v0), Vector2(l.end.x, v0), Vector2(l.end.x, v1), Vector2(l.position.x, v1)]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		quad("glass", P(a.x, a.y, 0.0), P(b.x, b.y, 0.0), P(b.x, b.y, top), P(a.x, a.y, top))
	bx("l18p_white", l.position.x, l.end.x, minf(v0, v1), maxf(v0, v1), top, top + 0.3)
	bx("l18p_steel", l.position.x + 0.15, l.end.x - 0.15, minf(v0, v1) + 0.15, maxf(v0, v1) - 0.15, 2.6, 5.0)
	cb(l.position.x, l.end.x, minf(v0, v1), maxf(v0, v1), 0.0, top)


## The station's name on the white box's south face (and over the east doors).
func _signs() -> void:
	var w := Plan.WHITE_BOX
	var cu := w.get_center().x - 1.0
	var xf := Transform3D(Basis(Vector3.UP, PI), P(cu, w.end.y + 0.05, 8.4))
	var l := label("Polytechnique", xf, 96, 0.011, Color("#5d636b"))
	l.visibility_range_end = 300.0
	bx("l18p_dark", cu + 6.0, cu + 7.3, w.end.y, w.end.y + 0.06, 7.75, 9.05)     # the line's sign by it
	var m := label("M18", Transform3D(Basis(Vector3.UP, PI), P(cu + 6.65, w.end.y + 0.08, 8.4)), 64, 0.008,
			Color(0.95, 0.95, 0.95))
	m.visibility_range_end = 200.0
	var tu := 30.0                                           # the totem on the forecourt: the line's M, its 18
	var tv := 25.0
	bx("l18p_dark", tu - 0.45, tu + 0.45, tv - 0.3, tv + 0.3, 0.0, 4.6)
	cb(tu - 0.45, tu + 0.45, tv - 0.3, tv + 0.3, 0.0, 4.6)
	for f: Array in [[0.31, Basis(Vector3.UP, PI)], [-0.31, Basis.IDENTITY]]:   # (facing +v, -v)
		for t: Array in [["M", 4.05, 90], ["18", 3.45, 64]]:
			var tl := label(t[0], Transform3D(f[1], P(tu, tv + float(f[0]), t[1])), t[2], 0.006, Color(0.97, 0.97, 0.97))
			tl.visibility_range_end = 120.0
	var e := label("Polytechnique", Transform3D(Basis(Vector3.UP, -PI * 0.5), P(Plan.U_BASE.x - 0.25, 0.0, 3.25)), 64,
			0.012, Color(0.2, 0.2, 0.22))
	e.visibility_range_end = 150.0
	for side: float in [1.0, -1.0]:                          # on the platforms' headers
		for u: float in [-15.0, 15.0]:
			var v := side * (Plan.PLAT_V.x + 0.06 + 0.13)
			var b := Basis(Vector3.UP, 0.0 if side < 0.0 else PI)
			var t := label("Polytechnique", Transform3D(b, P(u, v, Plan.PLAT_Y + 2.36)), 48, 0.008, Color(0.95, 0.95, 0.95))
			t.visibility_range_end = 60.0


# ---------------------------------------------------------------- the envelope

## A long side's folded glass: from the base's zigzag to the eaves', its folds framed in white.
func _skirt(side: float) -> void:
	for k in Plan.FOLDS:
		var a := Plan.base_node(k, side)
		var b := Plan.base_node(k + 1, side)
		var ea := Plan.eave_node(k, side)
		var eb := Plan.eave_node(k + 1, side)
		var pa := P(a.x, a.y, Plan.BASE_H)
		var pb := P(b.x, b.y, Plan.BASE_H)
		var qa := P(ea.x, ea.y, ea.z)
		var qb := P(eb.x, eb.y, eb.z)
		quad("glass", pa, pb, qb, qa)
		rod("l18p_white", pa, pb, 0.08, 6)
		rod("l18p_white", qa, qb, 0.16, 6)
		rod("l18p_white", pa, qa, 0.1, 6)
		for t: float in [0.33, 0.66]:                        # transoms
			rod("l18p_white", pa.lerp(qa, t), pb.lerp(qb, t), 0.045, 4)
	var a := Plan.base_node(Plan.FOLDS, side)
	var e := Plan.eave_node(Plan.FOLDS, side)
	rod("l18p_white", P(a.x, a.y, Plan.BASE_H), P(e.x, e.y, e.z), 0.1, 6)


## A gable (east: true): the glass leaning out from the base to the roof's end, open where the deck and the trains
## pass, framed.
func _gable(east: bool) -> void:
	var k := Plan.FOLDS if east else 0
	var top := Plan.eave_node(k, 1.0)
	var c := Plan.centre_node(k)
	var outline := PackedVector2Array([Vector2(-Plan.V_IN, Plan.BASE_H), Vector2(Plan.V_IN, Plan.BASE_H),
			Vector2(top.y, top.z), Vector2(0.0, c.z), Vector2(-top.y, top.z)])
	var hole := PackedVector2Array([Vector2(-5.4, 0.0), Vector2(5.4, 0.0), Vector2(5.4, 14.2), Vector2(-5.4, 14.2)])
	var at := func(q: Vector2) -> Vector3: return P(Plan.gable_u(east, q.y), q.x, q.y)
	for piece: PackedVector2Array in Plan.subtract([outline], [hole]):
		var idx := Geometry2D.triangulate_polygon(piece)
		for t in range(0, idx.size(), 3):
			tri("glass", at.call(piece[idx[t]]), at.call(piece[idx[t + 1]]), at.call(piece[idx[t + 2]]),
					Vector3(-1.0 if east else 1.0, 0, 0))
	for v: float in [-12.6, -9.0, -5.4, 5.4, 9.0, 12.6]:     # mullions
		var y_top := c.z + (top.z - c.z) * absf(v) / top.y
		rod("l18p_white", at.call(Vector2(v, Plan.BASE_H)), at.call(Vector2(v, y_top)), 0.09, 6)
	for v: float in [-2.7, 0.0, 2.7]:                         # over the opening
		rod("l18p_white", at.call(Vector2(v, 14.2)), at.call(Vector2(v, c.z + (top.z - c.z) * absf(v) / top.y)), 0.07, 4)
	rod("l18p_white", at.call(Vector2(-5.5, 14.2)), at.call(Vector2(5.5, 14.2)), 0.16, 6)
	for y: float in [Plan.BASE_H, 8.0, 12.0]:                 # transoms (not across the opening)
		var w := Plan.V_IN + (top.y - Plan.V_IN) * (y - Plan.BASE_H) / (top.z - Plan.BASE_H)
		for s: float in [1.0, -1.0]:
			rod("l18p_white", at.call(Vector2(s * 5.4, y)), at.call(Vector2(s * w, y)), 0.07, 4)
	for s: float in [1.0, -1.0]:
		rod("l18p_white", at.call(Vector2(s * Plan.V_IN, Plan.BASE_H)), at.call(Vector2(s * top.y, top.z)), 0.12, 6)


## The roof: folded glass between the eaves and the axis (a fold line midway each side), its frames, its slats.
func _roof() -> void:
	for side: float in [1.0, -1.0]:
		for k in Plan.FOLDS:
			var c0 := Plan.centre_node(k)
			var c1 := Plan.centre_node(k + 1)
			var e0 := Plan.eave_node(k, side)
			var e1 := Plan.eave_node(k + 1, side)
			var m0 := _mid(c0, e0)
			var m1 := _mid(c1, e1)
			for strip: Array in [[c0, c1, m1, m0], [m0, m1, e1, e0]]:
				var q: Array = strip.map(func(p: Vector3) -> Vector3: return P(p.x, p.y, p.z))
				quad("l18p_roofglass", q[0], q[1], q[2], q[3])
				rod("l18p_white", q[0], q[3], 0.14, 6)          # the rafter across
				rod("l18p_white", q[0], q[2], 0.06, 4)          # the diagonal
				for t: float in [0.25, 0.5, 0.75]:               # the slats
					rod("l18p_white", (q[0] as Vector3).lerp(q[1], t), (q[3] as Vector3).lerp(q[2], t), 0.035, 4)
			rod("l18p_white", P(m0.x, m0.y, m0.z), P(m1.x, m1.y, m1.z), 0.1, 6)
			rod("l18p_white", P(e0.x, e0.y, e0.z), P(e1.x, e1.y, e1.z), 0.18, 6)
			if side > 0.0:
				rod("l18p_white", P(c0.x, c0.y, c0.z), P(c1.x, c1.y, c1.z), 0.12, 6)
		for k: int in [0, Plan.FOLDS]:
			var c := Plan.centre_node(k)
			var e := Plan.eave_node(k, side)
			var m := _mid(c, e)
			rod("l18p_white", P(c.x, c.y, c.z), P(m.x, m.y, m.z), 0.14, 6)
			rod("l18p_white", P(m.x, m.y, m.z), P(e.x, e.y, e.z), 0.14, 6)


static func _mid(c: Vector3, e: Vector3) -> Vector3:
	var m := (c + e) * 0.5
	return Vector3(m.x, m.y, m.z + 0.35)


## The white steel trees on that side: a trunk at each outer fold, four branches up to the roof.
func _trees(side: float) -> void:
	for k in range(1, Plan.FOLDS, 2):
		var u := Plan.base_node(k, side).x
		var v := side * TREE_V
		var fork := 12.4
		bx("l18p_white", u - 0.04, u + 0.04, v - 0.04, v + 0.04, 0.0, 0.01)
		rod("l18p_white", P(u, v, 0.0), P(u, v, fork), 0.24, 10)
		cb(u - 0.25, u + 0.25, v - 0.25, v + 0.25, 0.0, fork)
		for d: Vector2 in [Vector2(-2.6, -3.2), Vector2(2.6, -3.2), Vector2(-2.6, 2.6), Vector2(2.6, 2.6)]:
			var tu := u + d.x
			var tv := v + side * d.y
			rod("l18p_white", P(u, v, fork), P(tu, tv, Plan.roof_y(tu, tv) - 0.12), 0.11, 6)


# ---------------------------------------------------------------- helpers (station frame: u, v, y)

## The station's local point (u, v, y) in the node's frame.
static func P(u: float, v: float, y: float) -> Vector3:
	return Vector3(u, y, -v)


## A box over u0..u1, v0..v1, y0..y1 (any order).
func bx(m: String, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	box(m, minf(u0, u1), maxf(u0, u1), minf(y0, y1), maxf(y0, y1), -maxf(v0, v1), -minf(v0, v1))


## Its collision box.
func cb(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	col(minf(u0, u1), maxf(u0, u1), minf(y0, y1), maxf(y0, y1), -maxf(v0, v1), -minf(v0, v1))


## A concrete block (its top in `top_m`: none drawn where it is "").
func _block(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, m := "l18p_concrete") -> void:
	bx(m, u0, u1, v0, v1, y0, y1)


## A floor's finish over u0..u1, v0..v1 at y (PLAT_Y by default), facing up.
func _top(u0: float, u1: float, v0: float, v1: float, m: String, y := Plan.PLAT_Y) -> void:
	quad(m, P(u0, v0, y), P(u1, v0, y), P(u1, v1, y), P(u0, v1, y), Vector3.UP)


## A glass balustrade from a to b (u, v) on a floor at y: its glass, its rail; its collision (`open`: none).
func _balustrade(a: Vector2, b: Vector2, y: float, open := false) -> void:
	if a.distance_to(b) < 0.05:
		return
	quad("glass", P(a.x, a.y, y), P(b.x, b.y, y), P(b.x, b.y, y + 1.05), P(a.x, a.y, y + 1.05))
	rod("l18p_steel", P(a.x, a.y, y + 1.08), P(b.x, b.y, y + 1.08), 0.03, 6)
	bx("l18p_steel", a.x - 0.03, a.x + 0.03, a.y - 0.03, a.y + 0.03, y, y + 1.08)
	if not open:
		_col_seg(a, b, y, y + 1.1, 0.08)


## A wall from a to b (u, v), y0..y1, both faces (`col`: its collision).
func _wall_seg(a: Vector2, b: Vector2, y0: float, y1: float, m: String, with_col: bool) -> void:
	var d := (b - a).normalized()
	var n := Vector3(d.y, 0.0, d.x)                          # (Godot: the side (d.y, -d.x) in u, v)
	quad(m, P(a.x, a.y, y0), P(b.x, b.y, y0), P(b.x, b.y, y1), P(a.x, a.y, y1), n)
	quad(m, P(a.x, a.y, y0), P(b.x, b.y, y0), P(b.x, b.y, y1), P(a.x, a.y, y1), -n)
	if with_col:
		_col_seg(a, b, y0, y1, 0.2)


## A thin collision box along a -> b (u, v), y0..y1, `t` thick.
func _col_seg(a: Vector2, b: Vector2, y0: float, y1: float, t: float) -> void:
	var pa := P(a.x, a.y, 0.0)
	var pb := P(b.x, b.y, 0.0)
	var along := (pb - pa).normalized()
	var basis := Basis(along.cross(Vector3.UP).normalized(), Vector3.UP, along)
	col_xf(Transform3D(basis, (pa + pb) * 0.5 + Vector3(0, (y0 + y1) * 0.5, 0)), Vector3(t, y1 - y0, pa.distance_to(pb)))


## A prism over polygon `poly` (u, v), y0..y1: its walls in `side_m` (outward), its top in `top_m`; its collision.
func _prism(poly: PackedVector2Array, y0: float, y1: float, side_m: String, top_m: String) -> void:
	var ccw := _signed_area(poly) > 0.0
	var faces := PackedVector3Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var out := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		var q := [P(a.x, a.y, y0), P(b.x, b.y, y0), P(b.x, b.y, y1), P(a.x, a.y, y1)]
		quad(side_m, q[0], q[1], q[2], q[3], Vector3(out.x, 0.0, -out.y))
		faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var a := P(poly[idx[t]].x, poly[idx[t]].y, y1)
		var b := P(poly[idx[t + 1]].x, poly[idx[t + 1]].y, y1)
		var c := P(poly[idx[t + 2]].x, poly[idx[t + 2]].y, y1)
		tri(top_m, a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))
	col_faces(faces)


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## An elliptic frustum at (cu, cv) from y0 (radii ru, rv along u, v) to y1 (ru1, rv1: the same by default), its top
## capped.
func ell(m: String, cu: float, cv: float, ru: float, rv: float, y0: float, y1: float, ru1 := -1.0, rv1 := -1.0,
		seg := 20) -> void:
	var r1 := Vector2(ru if ru1 < 0.0 else ru1, rv if rv1 < 0.0 else rv1)
	for i in seg:
		var t0 := TAU * i / seg
		var t1 := TAU * (i + 1) / seg
		var a0 := Vector2(cos(t0) * ru, sin(t0) * rv)
		var a1 := Vector2(cos(t1) * ru, sin(t1) * rv)
		var b0 := Vector2(cos(t0) * r1.x, sin(t0) * r1.y)
		var b1 := Vector2(cos(t1) * r1.x, sin(t1) * r1.y)
		var nm := Vector2(cos((t0 + t1) * 0.5) / ru, sin((t0 + t1) * 0.5) / rv).normalized()
		quad(m, P(cu + a0.x, cv + a0.y, y0), P(cu + a1.x, cv + a1.y, y0), P(cu + b1.x, cv + b1.y, y1),
				P(cu + b0.x, cv + b0.y, y1), Vector3(nm.x, 0.0, -nm.y))
		tri(m, P(cu, cv, y1), P(cu + b0.x, cv + b0.y, y1), P(cu + b1.x, cv + b1.y, y1), Vector3.UP)


# ---------------------------------------------------------------- materials

static func _materials() -> void:
	if _ready_mats:
		return
	_ready_mats = true
	var plain := func(name: String, c: String, rough: float, metal: float) -> void:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c)
		m.roughness = rough
		m.metallic = metal
		add_material(name, m)
	for c: Array in [["l18p_concrete", "#d7d6d0"], ["l18p_walkway", "#bebdb6"], ["l18p_fascia", "#dddcd6"]]:
		var m := StandardMaterial3D.new()                    # (the viaduct's: its colours, its mottle, world triplanar)
		m.albedo_color = Color(c[1])
		m.roughness = 0.88
		m.albedo_texture = _mottle()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 9.0
		add_material(c[0], m)
	plain.call("l18p_bearing", "#3b3c3e", 0.6, 0.0)
	plain.call("l18p_white", "#f2f2ef", 0.35, 0.15)
	plain.call("l18p_soffit", "#e4e3de", 0.8, 0.0)
	plain.call("l18p_edge", "#eeece4", 0.6, 0.0)
	plain.call("l18p_tactile", "#9a9893", 0.9, 0.0)
	plain.call("l18p_dark", "#2c2e31", 0.5, 0.0)
	plain.call("l18p_steel", "#c9cdd1", 0.3, 0.6)
	plain.call("l18p_rubber", "#1d1e20", 0.6, 0.0)
	plain.call("l18p_escalator", "#4b4d50", 0.4, 0.5)
	plain.call("l18p_wood", "#a87b52", 0.8, 0.0)
	var sg := StandardMaterial3D.new()
	sg.albedo_color = Color("#7d96a5")
	sg.roughness = 0.08
	sg.metallic = 0.35
	sg.metallic_specular = 0.9
	add_material("l18p_shopglass", sg)
	var rg := StandardMaterial3D.new()
	rg.albedo_color = Color(0.92, 0.95, 0.97, 0.5)
	rg.roughness = 0.1
	rg.metallic_specular = 0.9
	rg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rg.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_material("l18p_roofglass", rg)
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(1.0, 0.97, 0.9)
	led.emission_enabled = true
	led.emission = Color(1.0, 0.92, 0.8)
	led.emission_energy_multiplier = 2.0
	add_material("l18p_led", led)
	add_material("l18p_cladding", _tex_mat(_ribs(Color("#f1f1ee"), Color("#d9d9d5")), 1.0 / 0.6, 0.45))
	add_material("l18p_terracotta", _tex_mat(_ribs(Color("#c4714a"), Color("#a65a38")), 1.0 / 0.6, 0.85))
	add_material("l18p_floor", _tex_mat(blocks(Color("#d9d8d3"), Color("#bdbcb7"), 61), 1.0 / 4.8, 0.55))
	add_material("l18p_platform", _tex_mat(blocks(Color("#cfcecb"), Color("#b3b2ae"), 62), 1.0 / 4.8, 0.6))


## Concrete's faint mottle (the viaduct's: a seamless noise, 0.93 .. 1.03).
static func _mottle() -> Texture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = 18
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	var src := fn.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var g := 0.93 + 0.10 * src.get_pixel(x, y).r
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Ribbed panels: vertical ribs (the texture spans its tile: four ribs), shaded on one side.
static func _ribs(base: Color, dark: Color) -> Image:
	var img := Image.create(32, 8, false, Image.FORMAT_RGB8)
	for x in 32:
		var k := x % 8
		var c := base if k < 5 else (dark if k < 7 else base.lightened(0.04))
		for y in 8:
			img.set_pixel(x, y, c)
	return img


static func _tex_mat(img: Image, scale: float, rough: float) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 8.0
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
