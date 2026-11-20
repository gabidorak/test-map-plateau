extends "res://scripts/street_kit.gd"
## The commissariat's grounds drawn (lot sousPrefecture, commissariat_plan.gd: in the building's frame, on its plane):
## the sidewalk along the boulevard (its kerb, its bateau at the car park's way out, its trees' grates); the police's
## car park in asphalt (its bays' lines, the arrows of its loop: in along the north row, round the
## turning circle, out along the south row), the courtyard's paths and the apron at the tip in concrete blocks, flush
## with the lawns. Collision: their tops and edges. (The fence, the lift gates, the hedge, the trees and the benches
## are map records: sous_prefecture.gd.)

const Plan = preload("res://lots/sousPrefecture/commissariat_plan.gd")
const FLUSH := 0.03                         # m: the paths over the ground


func _init() -> void:
	super("CommissariatGrounds", {"type": "lot", "lot": "sousPrefecture", "name": "Commissariat : ses abords",
			"about": "the police's car park, the courtyard's paths"}, Plan)


func build(meshes: bool) -> Node3D:
	_sidewalk()
	_surface(Plan.carpark(), ASPHALT_UP, "street_asphalt")
	for p: PackedVector2Array in Plan.paved():
		_surface(p, FLUSH, "street_pavers")
	_marks()
	return commit(meshes)


## The sidewalk along the boulevard, from its kerb (Plan.KERB_LINE) to the facade and the car park's fence (x 0), as
## the street kit's: the granite kerb (its top, its face down to the road, the gutter at its foot), concrete blocks,
## KERB high, lowered across its gaps (the car park's way out: the bateau, in the drive's concrete; its ends) over
## RAMP m; its face down to the lawn and the car park along the fence; a grate round each of its trees.
func _sidewalk() -> void:
	var ys := []
	var y := Plan.SIDEWALK_Y.x
	while y < Plan.SIDEWALK_Y.y:
		ys.append(y)
		y += 1.0
	ys.append(Plan.SIDEWALK_Y.y)
	for k: Vector2 in Plan.KERB_LINE:
		ys.append(k.y)
	for g: Vector2 in Plan.sidewalk_gaps():
		ys.append_array([g.x - Plan.RAMP, g.x, g.y, g.y + Plan.RAMP])
	ys = ys.filter(func(v: float) -> bool: return v >= Plan.SIDEWALK_Y.x and v <= Plan.SIDEWALK_Y.y)
	ys.sort()
	var gaps := Plan.sidewalk_gaps()
	for i in ys.size() - 1:
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		if y1 - y0 < 0.01:
			continue
		var h0 := Plan.sidewalk_lift(y0)
		var h1 := Plan.sidewalk_lift(y1)
		var k0 := Vector2(Plan.kerb_x(y0), y0)
		var k1 := Vector2(Plan.kerb_x(y1), y1)
		var d := (k1 - k0).normalized()
		var out := Vector2(-d.y, d.x)                        # (west, to the road)
		var e0 := k0 - out * KERB_TOP
		var e1 := k1 - out * KERB_TOP
		var top := [p3(k0.x, k0.y, h0), p3(k1.x, k1.y, h1), p3(e1.x, e1.y, h1), p3(e0.x, e0.y, h0)]
		var body := [top[3], top[2], p3(0.0, y1, h1), p3(0.0, y0, h0)]
		var front := [p3(k0.x, k0.y, -0.25), p3(k1.x, k1.y, -0.25), top[1], top[0]]
		var mid := (y0 + y1) * 0.5
		var bateau: Vector2 = gaps[1]
		var drive := bateau.x < mid and mid < bateau.y
		quad("kerb_top", top[0], top[1], top[2], top[3], Vector3.UP)
		quad("street_drive" if drive else "street_pavers", body[0], body[1], body[2], body[3], Vector3.UP)
		quad("kerb_face", front[0], front[1], front[2], front[3], nrm(out))
		for q: Array in [top, body, front]:
			faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		var g := out * GUTTER
		quad("gutter", p3(k0.x, k0.y, 0.012), p3(k1.x, k1.y, 0.012), p3(k1.x + g.x, k1.y + g.y, 0.012),
				p3(k0.x + g.x, k0.y + g.y, 0.012), Vector3.UP)
		if y0 >= Plan.NORTH_Y - 0.01:                        # (past the building: its face to the east)
			quad("kerb_face", p3(0.0, y0, -0.03), p3(0.0, y1, -0.03), body[2], body[3], nrm(Vector2(1, 0)))
	for e: Array in [[Plan.SIDEWALK_Y.x, Vector2(0, -1)], [Plan.SIDEWALK_Y.y, Vector2(0, 1)]]:   # its ends
		var ye: float = e[0]
		var h := Plan.sidewalk_lift(ye)
		var kx := Plan.kerb_x(ye)
		quad("kerb_face", p3(kx, ye, -0.03), p3(0.0, ye, -0.03), p3(0.0, ye, h), p3(kx, ye, h), nrm(e[1]))
	for ty: float in Plan.STREET_TREES:                      # the trees' grates
		var c := Vector2(Plan.tree_x(ty), ty)
		var h := Plan.sidewalk_lift(ty) + 0.012
		var r := Plan.GRATE * 0.5
		quad("iron", p3(c.x - r, c.y - r, h), p3(c.x + r, c.y - r, h), p3(c.x + r, c.y + r, h), p3(c.x - r, c.y + r, h),
				Vector3.UP)


## Polygon `poly` (local) h over the ground (the plane: its triangles lie on it), its edges down to the ground.
func _surface(poly: PackedVector2Array, h: float, m: String) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("commissariat grounds: a polygon of %d points not triangulated" % poly.size())
	for i in range(0, idx.size(), 3):
		var a := p3(poly[idx[i]].x, poly[idx[i]].y, h)
		var b := p3(poly[idx[i + 1]].x, poly[idx[i + 1]].y, h)
		var c := p3(poly[idx[i + 2]].x, poly[idx[i + 2]].y, h)
		tri(m, a, b, c, Vector3.UP)
		faces.append_array(PackedVector3Array([a, b, c]))
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var u := poly[i]
		var w := poly[(i + 1) % poly.size()]
		var d := (w - u).normalized()
		var out := Vector2(-d.y, d.x) if cw else Vector2(d.y, -d.x)
		quad("kerb_face", p3(u.x, u.y, -0.03), p3(w.x, w.y, -0.03), p3(w.x, w.y, h), p3(u.x, u.y, h), nrm(out))


## The bays' lines (between them and at their back), the loop's arrows.
func _marks() -> void:
	for row: Vector2 in [Plan.BAYS_S, Plan.BAYS_N]:
		for k in 6:
			var x := Plan.BAYS_X + Plan.BAY_W * k
			line(Vector2(x, row.x), Vector2(x, row.y), 0.12)
		var back := row.x if row == Plan.BAYS_S else row.y
		line(Vector2(Plan.BAYS_X, back), Vector2(Plan.BAYS_X + Plan.BAY_W * 5, back), 0.12)
	var aisle := (Plan.BAYS_S.y + Plan.BAYS_N.x) * 0.5
	arrow(Vector2(8.0, aisle + 1.5), EAST)
	arrow(Vector2(15.0, aisle - 1.5), WEST)
