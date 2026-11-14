extends RefCounted
## Line 18's master plan on the plateau: the lot ligne18 (lots/ligne18/lot.json), the parent of the line's lots
## (ligne18-viaduc, ligne18-polytechnique, ligne18-universite), which all read the line here. FROZEN in
## lots/ligne18/plan.json, made by godot/lots/ligne18/tool/build_plan.py (sources: ref/metro18/README.md, IDFM AVPm, SGP).
##
## Frame: map metres, x east, y north; z over the map origin's height, as the heightmap; Godot position (x, z, -y), a
## heading theta (radians, from +x towards +y) is rotation.y = theta. s: chainage, m along the axis from
## Massy-Palaiseau, westwards (towards Versailles); PK = s + plan()["pk_offset"]. The axis is straight through each
## station's zone. v: metres to the left of the axis (facing increasing s).
## A station's frame: u along the line (increasing s), v to its left, origin on the axis at the station's s; under a
## node at station_transform(id), Godot local (u, z - hall_z, -v).
##
## Who builds what (the joints):
## - ligne18-viaduc: the ramp (s_start to s_abutment: an embankment between retaining walls), the abutment, the spans
##   and the piers of piers() (never moved: they are placed clear of the roads), the deck outside the stations' zones,
##   its parapets; and the TRACKS along the whole line, through the stations too (rails' top at rail_z(s), track
##   centres at v = +-TRACK_V, the third rail on each track's inner side).
## - a station's lot: everything over its zone (u -45..45, zone_s): the deck there, its top at deck_top_z (= rail_z -
##   RAIL_OVER_DECK) under the tracks, the platforms (edge at v = +-PLATFORM_EDGE_V, top at platform_z), the station
##   building, its supports, and at each end (u = +-45) the support the viaduct's first span rests on (its top at
##   rail_z - SOFFIT_UNDER_RAIL - BEARING); its grounds, up to and including the roads round it.
## - both draw the deck's end faces with half_section(): they meet face to face at u = +-45 (s = zone_s).

const PATH := "res://lots/ligne18/plan.json"
const TRACK_V := 2.65                       # m: each track's centre off the axis (5.30 m between them)
const GAUGE := 1.435
const RAIL_OVER_DECK := 0.47                # m: the rails' top over the deck's top face
const SOFFIT_UNDER_RAIL := 1.78             # m: the soffit at the axis under the rails' top
const WALKWAY_OVER_RAIL := 0.96             # m: the spine's top (the evacuation walkway)
const DECK_HALF := 4.845                    # m: the deck's concrete (9.69 m)
const EDGE_HALF := 4.945                    # m: with its edge equipment (9.89 m)
const PARAPET_H := 1.50                     # m over the deck's top face
const BEARING := 0.30                       # m: a pier's head under the soffit
const HALF_ZONE := 45.0                     # m: a station's zone, u -45..45
const PLATFORM_EDGE_V := 4.00               # m: the platforms' edge off the axis
const PLATFORM_OVER_RAIL := 1.05
const CELL := 50.0                          # m: project()'s grid

static var _plan: Dictionary
static var _s := PackedFloat64Array()
static var _x := PackedFloat64Array()
static var _y := PackedFloat64Array()
static var _h := PackedFloat64Array()
static var _g := PackedFloat64Array()
static var _r := PackedFloat64Array()
static var _grid := {}


## The plan (lots/ligne18/plan.json): axis, piers, stations, viaduct, track.
static func plan() -> Dictionary:
	if _plan.is_empty():
		_plan = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		for a: Array in _plan["axis"]:
			_s.append(float(a[0]))
			_x.append(float(a[1]))
			_y.append(float(a[2]))
			_h.append(float(a[3]))
			_g.append(NAN if a[4] == null else float(a[4]))
			_r.append(NAN if a[5] == null else float(a[5]))
	return _plan


## The lot ligne18 removes nothing itself (its children do).
static func drop(_world: Dictionary) -> void:
	pass


static func _i(s: float) -> Array:
	plan()
	var step := _s[1] - _s[0]
	var f := clampf((s - _s[0]) / step, 0.0, float(_s.size() - 1) - 0.0001)
	var i := int(f)
	return [i, f - i]


## The axis's point at s (map x, y).
static func point(s: float) -> Vector2:
	var k := _i(s)
	var i: int = k[0]
	return Vector2(lerpf(_x[i], _x[i + 1], k[1]), lerpf(_y[i], _y[i + 1], k[1]))


## The axis's heading at s (radians from +x towards +y; Godot rotation.y).
static func heading(s: float) -> float:
	var k := _i(s)
	var i: int = k[0]
	return lerp_angle(_h[i], _h[i + 1], k[1])


## The axis's direction at s, and its left.
static func tangent(s: float) -> Vector2:
	return Vector2.from_angle(heading(s))


static func left(s: float) -> Vector2:
	var h := heading(s)
	return Vector2(-sin(h), cos(h))


## The map point s along the line, v to its left.
static func at(s: float, v := 0.0) -> Vector2:
	return point(s) + left(s) * v


## The rails' top at s (NAN where the plan has none: the tunnel).
static func rail_z(s: float) -> float:
	var k := _i(s)
	var i: int = k[0]
	return lerpf(_r[i], _r[i + 1], k[1])


## The ground at s on the axis when the plan was made (the heightmap, before any lot): to know, not to build on (the
## game's ground is the terraformed one).
static func plan_ground_z(s: float) -> float:
	var k := _i(s)
	var i: int = k[0]
	return lerpf(_g[i], _g[i + 1], k[1])


## The soffit at the axis at s.
static func soffit_z(s: float) -> float:
	return rail_z(s) - SOFFIT_UNDER_RAIL


## Godot position of the map point s along the line, v to its left, at height z.
static func godot_at(s: float, v: float, z: float) -> Vector3:
	var p := at(s, v)
	return Vector3(p.x, z, -p.y)


## The line's frame at s: origin on the axis at the rails' top, local +x along the line (increasing s), -z to its
## left (local (along, up, -v)).
static func frame(s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, heading(s)), godot_at(s, 0.0, rail_z(s)))


## (s, v) of map point p: s along the line, v to its left; Vector2(NAN, NAN) when p is over `within` m (<= CELL)
## from the axis.
static func project(p: Vector2, within := CELL) -> Vector2:
	plan()
	if _grid.is_empty():
		for i in _s.size() - 1:
			var a := Vector2(_x[i], _y[i])
			var b := Vector2(_x[i + 1], _y[i + 1])
			var lo := Vector2i(floori((minf(a.x, b.x) - CELL) / CELL), floori((minf(a.y, b.y) - CELL) / CELL))
			var hi := Vector2i(floori((maxf(a.x, b.x) + CELL) / CELL), floori((maxf(a.y, b.y) + CELL) / CELL))
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					var key := Vector2i(gx, gy)
					if not _grid.has(key):
						_grid[key] = PackedInt32Array()
					_grid[key].append(i)
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not _grid.has(key):
		return Vector2(NAN, NAN)
	var best := INF
	var out := Vector2(NAN, NAN)
	for i: int in _grid[key]:
		var a := Vector2(_x[i], _y[i])
		var b := Vector2(_x[i + 1], _y[i + 1])
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			out = Vector2(lerpf(_s[i], _s[i + 1], t), signf(ab.cross(p - a)) * d)
	return out if best <= within else Vector2(NAN, NAN)


## The deck's outline across, v >= 0 (mirror it for v < 0), z over the rails' top: the spine's top (the walkway), its
## side down to the deck's top face, the deck's edge, the soffit sloping down to the spine's foot, the axis.
static func half_section() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in plan()["viaduct"]["half_section_vz"]:
		out.append(Vector2(p[0], p[1]))
	return out


## The whole outline, closed (v, z over the rails' top): half_section() (the axis's top, out to +v, round to the
## axis's bottom), then its mirror back up the -v side.
static func section() -> PackedVector2Array:
	var h := half_section()
	var out := h.duplicate()
	for i in range(h.size() - 2, 0, -1):
		out.append(Vector2(-h[i].x, h[i].y))
	return out


## The piers (dictionaries: s, x, y, heading, type "double" | "single" | "abutment", ground_z (the plan's, to know),
## soffit_z, clear (false: it stands on a road or water, which its lot deals with), fixed ("long_span_start" ...)).
static func piers() -> Array:
	return plan()["piers"]


## A station: name, build, s, centre [x, y], heading, zone_s, zone_u, levels {hall_z, passerelle_z, rail_z,
## deck_top_z, platform_z, roof_max_z}, platforms {u, edge_v, width, over_rail}, osm_building ("osm:w..."),
## footprint_map / footprint_local (OSM's), footprint_extent_local.
static func station(id: String) -> Dictionary:
	return plan()["stations"][id]


## The stations built on the map (ids).
static func stations_built() -> Array:
	return plan()["stations"].keys().filter(func(k: String) -> bool: return bool(station(k)["build"]))


## A station's frame: origin on the axis at its centre at the hall's level, rotation.y its heading (local x = u,
## -z = v, y = z - hall_z).
static func station_transform(id: String) -> Transform3D:
	var st := station(id)
	var c := Vector2(st["centre"][0], st["centre"][1])
	return Transform3D(Basis(Vector3.UP, float(st["heading"])), Vector3(c.x, float(st["levels"]["hall_z"]), -c.y))


## A station's (u, v) on the map, and back.
static func station_to_map(id: String, u: float, v: float) -> Vector2:
	var st := station(id)
	var th := float(st["heading"])
	return Vector2(st["centre"][0], st["centre"][1]) + Vector2(u * cos(th) - v * sin(th), u * sin(th) + v * cos(th))


static func station_from_map(id: String, p: Vector2) -> Vector2:
	var st := station(id)
	var th := float(st["heading"])
	var d := p - Vector2(st["centre"][0], st["centre"][1])
	return Vector2(d.x * cos(th) + d.y * sin(th), -d.x * sin(th) + d.y * cos(th))
