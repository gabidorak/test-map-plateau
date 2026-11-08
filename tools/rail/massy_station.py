"""Massy-Palaiseau's station precinct rebuilt (2026-11-06): the footbridges at their real height, the halls, the line
18 station and the ground under them. build_rail.py calls build() and writes the result to rail.json `massy`;
patch_world.py repairs the ground (apply_repairs), opens the line 18 shaft (a stairwell zone) and drops the map's
own decks and halls this replaces; scripts/builder/massy_builder.gd draws it.

Why: the map pipeline took the footbridges' decks from OSM ways and the LiDAR (a deck sagging 4 m over the tracks,
the Atlantis walkway on the ground), cut the halls at 6.2 m over the rail (patch_world.over_tracks: floating boxes),
and the LiDAR (flown while the line 18 station was dug) left two pits 21 m deep where the station is and a 4 m hump
where it saw le Lien's main hall as ground.

What it decides, from tools/rail/osm_massy_station.json (fetch_osm.py --station) and the base heightmap:
- Repairs (`repairs`): the line 18 site levelled on a plane fitted to the ground round it; the hump under le Lien's
  hall taken off with a grey opening (a plane survives an opening, a hump narrower than the window does not); both
  eased into the ground over BLEND m inside their outline. patch_world.py draws them as `regrade` zones.
- The concourse level: every footbridge here is OSM `level=1` and they join, so one walking level for all,
  LEVEL1_STEPS steps of STEP_RISE above the forecourts (le Lien's stairs count 42, 43 and 48 steps; the Atlantis
  walkway's 40). Its structure leaves DECK_DEPTH under the floor: the clearance over the tracks is reported.
- The deck (`deck`): the union of le Lien's outline (OSM w417349802, the glazed footbridge with its halls), the
  historic footbridge (Passerelle Publique, OSM w554922069 + w1285665811, HIST_WIDTH wide) and its hall
  (w1285665815), the Atlantis bus station walkway (OSM man_made=bridge w1285665813, w1285665800, w1487139397), less
  the buildings kept beside it and the stairwells that come up through it.
- Its edges (`edges`): per segment of the deck's outline, glass walls (le Lien: up to the vault's springing or its
  halls' roofs), panelled walls (the historic footbridge), glass balustrades (the walkway), railings round
  stairwells, nothing where it meets a building; openings where a flight or a lift arrives.
- Roofs (`roofs`): le Lien's pointed glass vault on white ribs over its tube (OSM part w1286041252, roof:material
  glass, roof:shape round), flat grey roofs over its halls and the historic footbridge, the walkway's white canopy
  on portal frames (photos of the bus station).
- Flights (`flights`): every OSM step way between level 0 and level 1 (stairs and escalators, `conveying`), from the
  ground (or the RER B island under it) to the deck: its OSM step count where it has one, else the rise over
  STEP_RISE; lengthened at the bottom when OSM draws it shorter than its steps need, a landing halfway when longer.
- Lifts (`lifts`): OSM lift shafts between levels 0 and 1, glazed, up to the roofs.
- Piers (`piers`): under the deck's spines every PIER_STEP m or so, never within PIER_TRACK m of a track nor on a
  road (the buses drive under the walkway).
- Massy TGV (`tgv`, OSM w417349777, photos): the glazed gable over the forecourt under a tent roof, two masts with
  their stays, the canopies over the doors, the name and the clock; the map's box goes.
- The line 18 station (`l18`, OSM w1334489725; the tunnels' stop positions n9951185171 and n9951185172 give its axis):
  the surface building (curtain walls on brise-soleil fins, a roof rising from the south-west end to the north-east
  one, a white block at the high end, corten posts along the tracks) and under it, L18_DEPTH m down ("the Line 18
  runs some 23 meters underneath ground level", beta-architecture.com on the station's competition), the station
  box: two side platforms (one per direction) behind half-height platform doors, a mezzanine over the tracks reached
  from the hall through an open shaft (two flights and a landing; patch_world.py opens it in the ground as a
  stairwell zone whose floor is the mezzanine), stairs down to each platform, the tunnel mouths at both ends. The
  next patch runs the metro in it (Paris Metro line 18: 45 m trains, platforms for 60 m).
- The Atlantis bus station and the bus depot (`bus_station`): bus_station.py, bus_depot.py (their docstrings): its repairs come after
  these, its zones (quays, sidewalks, the depot, the lanes, the eased ground round them) before them; the flights land
  on its quays, the piers keep off its lanes, its fence runs straight along the RER side lane.
Assumed (no source): the side platforms, the box's sizes, the shaft's layout, the halls' heights."""
import json
import math

import numpy as np
import shapely
from shapely.geometry import LineString, MultiPolygon, Point, Polygon
from shapely.ops import nearest_points, unary_union

import railgeo as rg
from l93 import fwd

OSM_FILE = rg.TOOLS / "osm_massy_station.json"
STEP_RISE = 0.17                # m (build_rail.py STEP_RISE)
STEP_GOING = 0.30
LEVEL1_STEPS = 43               # le Lien's main stairs to the RER B islands (OSM w417349890 step_count 43)
DECK_DEPTH = 0.90               # m of structure under the walking surface; assumed
HIST_WIDTH = 4.5                # m, the historic footbridge's tube; assumed (photos: narrower than le Lien)
BLEND = 4.0                     # m over which a repair eases into the ground inside its outline
PIER_STEP = 24.0                # m between the piers along a spine, at most; assumed
PIER_MIN = 10.0                 # m between two piers at least
PIER_TRACK = 2.6                # m from a track centre a pier keeps clear of (gauge 1.75 m, its own half width)
PIER_SIZE = 0.9                 # m square
STAIR_WIDTH = 2.6               # m, stairs OSM gives no width for; assumed
ESCALATOR_WIDTH = 1.2           # m, an escalator with its balustrades
ESCALATOR_SLOPE = 30.0          # degrees, the usual escalator incline
STAIR_MIN = 1.2                 # m: the narrowest a stair is made to sit beside its neighbours
ESCALATOR_MIN = 1.0             # m: likewise an escalator (a 0.6 m step with its balustrades)
FLIGHT_GAP = 0.1                # m between two flights side by side
FLIGHT_MAX_STEPS = 25           # steps in one flight (French public stairs): more take a landing halfway
LANDING = 1.6                   # m, that landing
ESC_PLATE = 1.2                 # m, the flat landing plate at an escalator's foot
GAUGE_CLEAR = 1.9               # m: a flight's footprint (plus 0.2 m) keeps this clear of any track centre
LIFT_TOP = 3.2                  # m above the deck a lift shaft rises to
VAULT_SPRING = 2.8              # m above the deck: le Lien's side glazing, then its pointed vault
VAULT_RISE = 5.6                # m from the springing to the apex (photo of its Vilmorin end: ogive ~ as high as wide)
RIB_STEP = 4.5                  # m between the vault's white ribs
HALL_HEIGHT = 5.4               # m above the deck to le Lien's halls' flat roofs; assumed
HIST_HEIGHT = 3.2               # m above the deck to the historic footbridge's roof; assumed
CANOPY_HEIGHT = 4.2             # m above the deck to the walkway's canopy (photo of the bus station)
FRAME_STEP = 14.0               # m between its white portal frames (photo)
REPLACED_BUILDINGS = ["w417349802", "w1286041252", "w1534254611", "w1285665815", "w1334489725", "w417349777",
                      "w680235284", "r16476355"]       # the last two: Massy TGV's roof part and mezzanine floor
L18_STOPS = [(4321.7, 1275.3), (4365.6, 1332.6)]     # OSM n9951185171, n9951185172 (projected; refreshed from OSM)
L18_DEPTH = 22.0                # m from the hall's floor to the rail
L18_PLATFORM = 1.05             # m, platform above the rail; assumed (metro floors are ~1.05-1.10 m up)
L18_BOX = (42.0, 9.5)           # m: half length and half width of the station box inside its walls; assumed
L18_TRACK = 2.1                 # m from the axis to each track centre; assumed
L18_EDGE = 1.45                 # m from a track centre to the platform edge; assumed
L18_PLATFORMS = 36.0            # m either side of the centre (72 m: the 60 m trains with room); assumed
L18_MEZZ = (-14.0, 8.0, 6.6)    # mezzanine: along the axis from, to (m from the centre), its floor over the platforms
L18_CEILING = 10.0              # m, the box's ceiling over the platforms (3.4 m over the mezzanine)
L18_SHAFT = (-12.0, 6.0, 6.0)   # shaft: along the axis from, to, half width across
L18_ROOF = (8.0, 13.0)          # m: the surface hall's roof over its floor at the south-west and north-east ends
L18_END_BLOCK = 16.0            # m of white block at the high (north-east) end (photo)
TGV_EAVES = 11.0                # m: Massy TGV's hall walls over the forecourt; the photo gives ~2.5 storeys of glass
TGV_RIDGE = 19.0                # m: its tent roof's ridge
TGV_MAST = 30.0                 # m: the two masts at the front gable (photo: well above the roof)
TGV_CANOPY = (4.6, 6.5)         # m: the canopies over the doors, height and depth
TGV_PIT = 0.8                   # m under the forecourt's plane: the LiDAR's view into the covered TGV cutting
TGV_TRACK_CLEAR = 4.5           # m from a (surface) track the TGV repair keeps clear of: the trackbeds keep their level
YARD_STRIP = 2.0                # m: a yard track's ballast strip (yard.py STRIP, 1.9) and a little; a fill stops there


def log(*a):
    print(*a, flush=True)


def load() -> dict:
    d = json.loads(OSM_FILE.read_text(encoding="utf-8"))
    ways = {e["id"]: e for e in d["elements"] if e["type"] == "way" and "geometry" in e}
    nodes = {e["id"]: e for e in d["elements"] if e["type"] == "node"}
    return {"ways": ways, "nodes": nodes, "timestamp": d.get("osm3s", {}).get("timestamp_osm_base", "")}


def wpts(osm: dict, i: int) -> np.ndarray:
    return np.array([fwd(g["lat"], g["lon"]) for g in osm["ways"][i]["geometry"]])


def wpoly(osm: dict, i: int) -> Polygon:
    return Polygon(wpts(osm, i)).buffer(0)


def r3(p) -> list:
    return [[round(float(x), 3), round(float(y), 3)] for x, y in np.asarray(p)[:, :2]]


def ring(pg: Polygon) -> list:
    return r3(np.asarray(pg.exterior.coords)[:-1])


def polys(g) -> list:
    return [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05]


def mesh2d(pg: Polygon) -> dict:
    """A polygon for the builder: its rings (no closing point) and triangles (indices into the rings' concatenation;
    constrained Delaunay, as patch_world.ring_tris)."""
    from scipy.spatial import cKDTree
    pg = shapely.set_precision(pg, 0.001)
    rings = [np.asarray(pg.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in pg.interiors]
    flat = np.concatenate(rings)
    tree = cKDTree(flat)
    tris = []
    for t in shapely.constrained_delaunay_triangles(pg).geoms:
        d, ids = tree.query(np.asarray(t.exterior.coords)[:-1])
        if d.max() < 1e-3 and len(set(ids.tolist())) == 3:
            tris += [int(i) for i in ids]
    return {"rings": [r3(r) for r in rings], "tris": tris}


# ---------------------------------------------------------------- ground repairs

def grid_box(H: rg.Heights, bounds, pad: float):
    x0, y0, x1, y1 = bounds
    c0 = max(int((x0 - pad - H.ox) / H.cell), 0)
    c1 = min(int((x1 + pad - H.ox) / H.cell) + 1, H.w - 1)
    r0 = max(int((H.oy - (y1 + pad)) / H.cell), 0)
    r1 = min(int((H.oy - (y0 - pad)) / H.cell) + 1, H.h - 1)
    xs = H.ox + np.arange(c0, c1 + 1) * H.cell
    ys = H.oy - np.arange(r0, r1 + 1) * H.cell
    X, Y = np.meshgrid(xs, ys)
    return r0, r1, c0, c1, X, Y


def fit_rim_plane(H: rg.Heights, pg: Polygon) -> list:
    """Least-squares plane z = a + b (x - cx) + c (y - cy) through the ground on a ring 1-5 m outside pg, three times
    without the samples more than 0.4 m off it (a kerb, a wall foot)."""
    rim = pg.buffer(5.0).difference(pg.buffer(1.0))
    r0, r1, c0, c1, X, Y = grid_box(H, rim.bounds, 0.0)
    m = shapely.contains_xy(rim, X, Y)
    x, y = X[m], Y[m]
    z = H.data[r0:r1 + 1, c0:c1 + 1][m].astype(np.float64)
    cx, cy = pg.centroid.x, pg.centroid.y
    keep = np.ones(len(z), dtype=bool)
    coef = np.array([float(np.median(z)), 0.0, 0.0])
    for _ in range(3):
        A = np.c_[np.ones(keep.sum()), x[keep] - cx, y[keep] - cy]
        coef = np.linalg.lstsq(A, z[keep], rcond=None)[0]
        res = z - (coef[0] + coef[1] * (x - cx) + coef[2] * (y - cy))
        keep = np.abs(res) < 0.4
    return [round(float(cx), 3), round(float(cy), 3), round(float(coef[0]), 4), round(float(coef[1]), 6),
            round(float(coef[2]), 6)]


def apply_repairs(H: rg.Heights, repairs: list, data: np.ndarray = None) -> np.ndarray:
    """The heightmap samples with the repairs applied (a copy of H.data unless `data` is given: changed in place)."""
    from scipy.ndimage import grey_opening
    if data is None:
        data = H.data.copy()
    for rp in repairs:
        pg = Polygon(rp["ring"]).buffer(0)
        window = float(rp.get("window", 0.0))
        r0, r1, c0, c1, X, Y = grid_box(H, pg.bounds, window + 2.0)
        sub = data[r0:r1 + 1, c0:c1 + 1]
        inside = shapely.contains_xy(pg, X, Y)
        if not inside.any():
            continue
        if rp["method"] == "fill":
            # what lies under the plane raised up to it, the rest left: it meets the ground where they cross, so no
            # easing is needed and it may run up to a trackbed's edge
            cx, cy, a, b, c = rp["plane"]
            sub[inside] = np.maximum(sub[inside], a + b * (X[inside] - cx) + c * (Y[inside] - cy))
            continue
        if rp["method"] == "axis":
            # the Atlantis bus station's lanes and the bus hangar (bus_station.py): the height along an axis
            import bus_station
            sub[inside] = bus_station.axis_repair(rp, X[inside], Y[inside], sub[inside])
            continue
        d = shapely.distance(pg.exterior, shapely.points(X[inside], Y[inside]))
        w = np.clip(d / BLEND, 0.0, 1.0)
        w = w * w * (3 - 2 * w)
        if rp["method"] == "plane":
            cx, cy, a, b, c = rp["plane"]
            target = a + b * (X[inside] - cx) + c * (Y[inside] - cy)
        elif rp["method"] == "opening":
            k = int(round(window / H.cell)) | 1
            target = np.minimum(sub, grey_opening(sub, size=(k, k)))[inside]
        else:
            raise ValueError(rp["method"])
        sub[inside] = sub[inside] + (target - sub[inside]) * w
    return data


def repairs(osm: dict, H: rg.Heights) -> list:
    l18 = wpoly(osm, 1334489725).buffer(10.0, join_style=2)
    hall = Point(4440.0, 1296.0).buffer(24.0, 32)
    out = [{"id": "repair:l18", "method": "plane", "ring": ring(l18), "plane": fit_rim_plane(H, l18),
            "why": "the line 18 station's excavation the LiDAR saw (two pits ~21 m deep) and the site's spoil heaps"},
           {"id": "repair:lien-hall", "method": "opening", "window": 31.0, "ring": ring(hall),
            "why": "le Lien's main hall over the RER B islands, which the LiDAR kept as ground (a 4 m hump)"}]
    return out + tgv_repairs(osm, H)


def tgv_repairs(osm: dict, H: rg.Heights) -> list:
    """Massy TGV's hall and forecourt on the plane of the ground round them: the TGV line runs covered under them (OSM
    tunnel=yes) but the LiDAR saw into its cutting (a pit to -83 m under and north-west of the hall, down to the RER B's
    track 1). Two repairs on the plane fitted round the hall: the hall and 6 m round it levelled on it (its floor all
    on the plane, past the blend), clear of the surface tracks by TGV_TRACK_CLEAR; then the pit's samples more than
    TGV_PIT under the plane within 35 m (the part touching the hall: the street falling away to the east is real)
    filled up to it, up to the trackbed's edge (YARD_STRIP from the tracks: a fill needs no easing)."""
    hall = wpoly(osm, 417349777)
    core = hall.buffer(6.0, join_style=2)
    plane = fit_rim_plane(H, core)
    cx, cy, a, b, c = plane
    region = hall.buffer(35.0)
    r0, r1, c0, c1, X, Y = grid_box(H, region.bounds, 0.0)
    Z = H.data[r0:r1 + 1, c0:c1 + 1]
    m = shapely.contains_xy(region, X, Y) & (Z < a + b * (X - cx) + c * (Y - cy) - TGV_PIT)
    pit = unary_union(shapely.buffer(shapely.points(X[m], Y[m]), 0.6)).buffer(1.5).buffer(-1.0)
    pit = unary_union([p for p in polys(pit) if p.distance(core) < 1.0])
    rail_lines = [LineString(wpts(osm, i)) for i, w in osm["ways"].items()
                  if w.get("tags", {}).get("railway") in ("rail", "light_rail")
                  and w.get("tags", {}).get("tunnel") != "yes" and len(w["geometry"]) > 1]
    floor = unary_union([core] + [p.buffer(2.5) for p in polys(pit)]).buffer(1.0, join_style=2) \
        .buffer(-1.0, join_style=2).difference(unary_union([ln.buffer(TGV_TRACK_CLEAR) for ln in rail_lines]))
    floor = Polygon(max(polys(floor), key=lambda p: p.intersection(hall).area).exterior).simplify(0.8)
    fill = pit.buffer(1.5, join_style=2).difference(unary_union([ln.buffer(YARD_STRIP) for ln in rail_lines]))
    why = "Massy TGV's hall and forecourt over the covered TGV line: the LiDAR saw into its cutting (a pit to -83 m)"
    out = [{"id": "repair:tgv", "method": "plane", "ring": ring(floor), "plane": fit_rim_plane(H, floor), "why": why}]
    for k, p in enumerate(sorted(polys(fill), key=lambda p: -p.area)):
        if p.area > 2.0:
            out.append({"id": "repair:tgv-cutting" + ("" if k == 0 else "-%d" % k), "method": "fill",
                        "ring": ring(Polygon(p.exterior).simplify(0.5)), "plane": plane, "why": why})
    return out


# ---------------------------------------------------------------- the deck and its flights

def classify_steps(osm: dict) -> list:
    """OSM step ways (stairs, escalators) between the ground and level 1."""
    out = []
    for i, w in osm["ways"].items():
        t = w.get("tags", {})
        if t.get("highway") == "construction" and t.get("construction") == "steps":
            t = dict(t, highway="steps")         # the line 18 connection's escalators, opened with the line
        if t.get("highway") != "steps":
            continue
        lv = t.get("level", "")
        if lv not in ("0;1", "0;0.5;1"):
            continue
        p = wpts(osm, i)
        if len(p) < 2 or LineString(p).length < 3.0:
            continue
        out.append({"osm": i, "pts": p, "incline": t.get("incline", ""), "count": int(t["step_count"])
                    if t.get("step_count", "").isdigit() else None,
                    "escalator": t.get("conveying") in ("yes", "forward", "backward", "reversible")})
    return out


def ground_ref(steps: list, Hf) -> float:
    """The forecourts' level: the median ground at the feet of le Lien's counted stairs."""
    feet = []
    for s in steps:
        if s["count"] and not s["escalator"]:
            p = s["pts"]
            bottom = p[0] if s["incline"] != "down" else p[-1]
            feet.append(float(Hf.at(bottom[0], bottom[1])))
    return float(np.median(feet))


def _foot_z(p, Hf, islands) -> float:
    """The floor at a flight's foot: the raised island it stands on, else the ground."""
    z = float(Hf.at(p[0], p[1]))
    for isl in islands:
        if isl[0].contains(Point(p[0], p[1])):
            z = isl[1]
    return z


def _flight_shape(f: dict, level: float, Hf, islands: list) -> None:
    """Lays flight f out from its top (f["top_xy"]) back along f["d"], compact (OSM often draws the way longer, on
    along the floor it lands on): its steps from the rise (OSM's step count when it agrees), a landing halfway when
    more than FLIGHT_MAX_STEPS, an escalator's incline at ESCALATOR_SLOPE with a plate at its foot. Sets pts, zs,
    steps, need, bottom (its foot's floor, found again where the foot lands)."""
    top, d = f["top_xy"], f["d"]
    zb = _foot_z(top - d * 10.0, Hf, islands)
    for _ in range(3):                          # the foot moves with the rise: settle it
        rise = level - zb
        if f["escalator"]:
            n = max(int(round(rise / STEP_RISE)), 1)
            need = ESC_PLATE + rise / math.tan(math.radians(ESCALATOR_SLOPE))
        else:
            c = f["count"]
            n = c if c and abs(c * STEP_RISE - rise) < 2.5 else max(int(round(rise / STEP_RISE)), 1)
            need = n * STEP_GOING + (LANDING if n > FLIGHT_MAX_STEPS else 0.0)
        z_new = _foot_z(top - d * need, Hf, islands)
        if abs(z_new - zb) < 0.01:
            break
        zb = z_new
    bottom = top - d * need
    if f["escalator"]:
        pts, zs = [bottom, bottom + d * ESC_PLATE, top], [zb, zb, level]
    elif n > FLIGHT_MAX_STEPS:
        n1 = n // 2
        zm = zb + (level - zb) * n1 / n
        l0 = bottom + d * (n1 * STEP_GOING)
        l1 = l0 + d * LANDING
        pts, zs = [bottom, l0, l1, top], [zb, zm, zm, level]
    else:
        pts, zs = [bottom, top], [zb, level]
    f.update({"pts_xy": pts, "zs": zs, "steps": n, "need": need, "bottom": zb})


def _footprint(f: dict, extra: float = 0.0):
    return LineString([f["pts_xy"][0], f["pts_xy"][-1]]).buffer(f["width"] / 2 + extra, cap_style=2)


def build_flights(steps: list, deck, level: float, Hf, islands: list, tracks=None) -> tuple:
    """The flights from the ground to the deck at `level`: each its pts [bottom, (landing...), top] in a straight line,
    a height per point (zs), bottom and top z, width, steps, escalator; and the stairwell holes they need in the deck.
    - Each is laid out compact from its top (_flight_shape): OSM's way often runs on along the floor below, which was
      drawn as long landings (a 17 m glass-walled escalator foot along an RER B island).
    - Parallel neighbours (an escalator beside its stairs, OSM ~1.5-2 m apart) are set side by side, FLIGHT_GAP apart,
      narrowed down to STAIR_MIN / ESCALATOR_MIN first; two stair ways on one line are one stair.
    - Their footprints keep GAUGE_CLEAR (and 0.2 m) from every track centre (`tracks`): a flight in the way is shifted
      across (and, coming up through the deck, slid towards its top) by the least that clears; one that cannot be is
      left out (logged)."""
    edge = deck.exterior if deck.geom_type == "Polygon" else unary_union([p.exterior for p in deck.geoms])
    fl = []
    for s in steps:
        p = s["pts"]
        a, b = (p[0], p[-1]) if s["incline"] == "up" else (p[-1], p[0]) if s["incline"] == "down" else \
            ((p[0], p[-1]) if Point(p[-1]).distance(deck) < Point(p[0]).distance(deck) else (p[-1], p[0]))
        bottom, top = np.asarray(a, float), np.asarray(b, float)
        top_inside = deck.contains(Point(top))
        if not top_inside:
            q = nearest_points(edge, Point(top))[0]
            if q.distance(Point(top)) > 6.0:
                continue                        # not one of the deck's (the TGV station's own, the bus islands')
            top = np.array([q.x, q.y])
        d = top - bottom
        L = float(np.linalg.norm(d))
        if L < 1.0:
            continue
        d /= L
        # coming up from an RER B island: along it (OSM draws some across it, over the track beside it)
        for isl in islands:
            if isl[0].contains(Point(bottom)) and top_inside:
                ia, ib, _w = axis_of(isl[0])
                ax = (ib - ia) / np.linalg.norm(ib - ia)
                if abs(float(ax @ d)) < math.cos(math.radians(20.0)):
                    # its top over the island's spine, as far up the island as OSM put it
                    t2 = ia + ax * float((top - ia) @ ax)
                    if deck.buffer(-0.3).contains(Point(t2)):
                        d, top = (ax if ax @ d > 0 else -ax), t2
        f = {"osm": s["osm"], "escalator": s["escalator"], "count": s["count"], "d": d, "top_xy": top,
             "inside": top_inside, "width": ESCALATOR_WIDTH if s["escalator"] else STAIR_WIDTH}
        _flight_shape(f, level, Hf, islands)
        fl.append(f)
    dropped = []
    # one stair drawn twice (two ways on one line): keep the one with a step count, else the longer
    for i in range(len(fl)):
        for j in range(i + 1, len(fl)):
            a_, b_ = fl[i], fl[j]
            if a_.get("gone") or b_.get("gone") or a_["escalator"] != b_["escalator"] or a_["d"] @ b_["d"] < 0.97:
                continue
            n = np.array([-a_["d"][1], a_["d"][0]])
            if abs((b_["top_xy"] - a_["top_xy"]) @ n) < 0.6 and _footprint(a_).intersection(_footprint(b_)).area > \
                    0.5 * min(_footprint(a_).area, _footprint(b_).area):
                lose = b_ if (a_["count"] or 0, a_["need"]) >= (b_["count"] or 0, b_["need"]) else a_
                lose["gone"] = True
                dropped.append(("w%d" % lose["osm"], "the same stair as w%d" % (a_ if lose is b_ else b_)["osm"]))
    fl = [f for f in fl if not f.get("gone")]
    # parallel neighbours side by side: clusters of flights running the same way, overlapping
    parent = list(range(len(fl)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i in range(len(fl)):
        for j in range(i + 1, len(fl)):
            if fl[i]["d"] @ fl[j]["d"] > math.cos(math.radians(15.0)) and \
                    _footprint(fl[i]).intersects(_footprint(fl[j]).buffer(FLIGHT_GAP)):
                parent[root(i)] = root(j)
    groups = {}
    for i in range(len(fl)):
        groups.setdefault(root(i), []).append(fl[i])
    for g in groups.values():
        if len(g) < 2:
            continue
        D = np.mean([f["d"] for f in g], axis=0)
        D /= np.linalg.norm(D)
        N = np.array([-D[1], D[0]])
        g.sort(key=lambda f: float(((f["pts_xy"][0] + f["pts_xy"][-1]) / 2) @ N))
        lat = [float(((f["pts_xy"][0] + f["pts_xy"][-1]) / 2) @ N) for f in g]
        span = lat[-1] - lat[0]
        # narrow them towards their minimum widths as far as the room OSM gives (the spread of their lines) asks
        for f in g:
            f["width"] = ESCALATOR_WIDTH if f["escalator"] else STAIR_WIDTH
        need_w = lambda: sum(f["width"] for f in g) - (g[0]["width"] + g[-1]["width"]) / 2 + FLIGHT_GAP * (len(g) - 1)
        while need_w() > span + 0.01:
            wide = [f for f in g if f["width"] > (ESCALATOR_MIN if f["escalator"] else STAIR_MIN) + 0.01]
            if not wide:
                break
            for f in wide:
                f["width"] = round(max(f["width"] - 0.1, ESCALATOR_MIN if f["escalator"] else STAIR_MIN), 2)
        # then push them apart, keeping their middle
        pos = list(lat)
        for k in range(1, len(g)):
            pos[k] = max(pos[k], pos[k - 1] + (g[k - 1]["width"] + g[k]["width"]) / 2 + FLIGHT_GAP)
        shift = (sum(lat) - sum(pos)) / len(g)
        for f, p0, p1 in zip(g, lat, pos):
            mv = N * (p1 + shift - p0)
            if np.linalg.norm(mv) > 1e-3:
                _move(f, mv, edge, level, Hf, islands)
    # clear of the tracks
    if tracks is not None and not tracks.is_empty:
        for f in fl:
            f["clear"] = _footprint(f, 0.2).distance(tracks) >= GAUGE_CLEAR
        # the room taken: the flights already clear (those still in the way may go, they do not hold their spot)
        others = lambda f: unary_union([_footprint(o) for o in fl if o is not f and not o.get("gone") and o["clear"]])
        for f in sorted([f for f in fl if not f["clear"]], key=lambda f: -_footprint(f, 0.2).distance(tracks)):
            n = np.array([-f["d"][1], f["d"][0]])
            moves = [n * 0.0] + [n * s * k * 0.1 for k in range(1, 26) for s in (1, -1)]
            if f["inside"]:
                moves += [f["d"] * k * 0.5 for k in range(1, 9)]
            moves.sort(key=lambda m: float(np.linalg.norm(m)))
            w_min = ESCALATOR_MIN if f["escalator"] else STAIR_MIN
            widths = [f["width"]] + [w for w in np.arange(f["width"] - 0.2, w_min - 0.01, -0.2)] + [w_min]
            ok = False
            occupied = others(f)
            for w in widths:                    # the widest that fits, the least moved
                for mv in moves:
                    trial = dict(f, width=round(float(w), 2))
                    _move(trial, mv, edge, level, Hf, islands)
                    if trial["inside"] and not deck.buffer(-0.3).contains(Point(trial["top_xy"])):
                        continue
                    fp = _footprint(trial)
                    if _footprint(trial, 0.2).distance(tracks) >= GAUGE_CLEAR and fp.intersection(occupied).area < 0.05:
                        f.update(trial)
                        f["clear"] = ok = True
                        break
                if ok:
                    break
            if not ok:
                f["gone"] = True
                dropped.append(("w%d" % f["osm"], "no room clear of the tracks (%.2f m from one)" % (
                    _footprint(f, 0.2).distance(tracks))))
        fl = [f for f in fl if not f.get("gone")]
    for o, why in dropped:
        log("massy: flight %s left out: %s" % (o, why))
    flights, holes = [], []
    for f in fl:
        flights.append({"id": "flight:w%d" % f["osm"], "osm": "w%d" % f["osm"], "pts": r3(f["pts_xy"]),
                        "zs": [round(z, 3) for z in f["zs"]], "bottom": round(f["bottom"], 3), "top": round(level, 3),
                        "width": f["width"], "steps": f["steps"], "escalator": f["escalator"]})
        if f["inside"]:
            # the deck opens over the flight up to its top step, where the floor takes over (a lip left there stopped
            # the player a step short)
            holes.append(LineString([f["pts_xy"][0], f["pts_xy"][-1]]).buffer(f["width"] / 2 + 0.25, cap_style=2))
    return flights, holes


def _move(f: dict, mv, edge, level: float, Hf, islands: list) -> None:
    """Moves flight f by mv (map metres) and lays it out again: a top on the deck's edge stays on it (where the
    moved line meets the edge, else the nearest edge point)."""
    top = f["top_xy"] + mv
    if not f["inside"]:
        ray = LineString([top - f["d"] * 6.0, top + f["d"] * 6.0])
        hit = ray.intersection(edge)
        pts = [np.asarray(c) for g in getattr(hit, "geoms", [hit]) if not g.is_empty for c in g.coords]
        if pts:
            top = min(pts, key=lambda q: float(np.linalg.norm(q - top)))
        else:
            q = nearest_points(edge, Point(top))[0]
            top = np.array([q.x, q.y])
    f["top_xy"] = np.asarray(top, float)
    _flight_shape(f, level, Hf, islands)


def lifts(osm: dict, deck, level: float, Hf) -> list:
    out = []
    for i, w in osm["ways"].items():
        t = w.get("tags", {})
        if t.get("highway") != "elevator" or "1" not in t.get("level", "").split(";") or "0" not in t.get("level", "").split(";"):
            continue
        pg = wpoly(osm, i)
        if pg.area < 1.0 or pg.distance(deck) > 4.0:
            continue
        c = pg.centroid
        out.append({"id": "lift:w%d" % i, "osm": "w%d" % i, "ring": ring(pg.minimum_rotated_rectangle),
                    "bottom": round(float(Hf.at(c.x, c.y)), 3), "top": round(level + LIFT_TOP, 3)})
    return out


def edges(deck, parts: dict, kept, flights: list, lifts_: list, level: float) -> list:
    """Walls, balustrades and railings along the deck's outline: per run [kind, a, b, height]."""
    tops = []
    for f in flights:
        q = np.asarray(f["pts"][-1])
        tops.append((Point(q), f["width"] / 2 + 0.3))
    for lf in lifts_:
        tops.append((Polygon(lf["ring"]).centroid, 1.6))
    out = []
    rings = []
    for pg in polys(deck):
        rings.append((np.asarray(pg.exterior.coords), False))
        rings += [(np.asarray(h.coords), True) for h in pg.interiors]
    for pts, hole in rings:
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            L = float(np.linalg.norm(b - a))
            if L < 0.05:
                continue
            mid = Point((a + b) / 2)
            if kept is not None and mid.distance(kept) < 0.4:
                continue                        # the deck goes into a building there
            if hole:
                kind, h = "railing", 1.1
            else:
                owner = min(parts, key=lambda k_: parts[k_]["geom"].exterior.distance(mid))
                kind, h = parts[owner]["edge"], parts[owner]["edge_h"]
                if owner == "lien" and not parts["vault"]["geom"].buffer(0.6).contains(mid):
                    h = HALL_HEIGHT
            # cut the openings where a flight or a lift arrives
            ts = [0.0, L]
            cuts = []
            d = (b - a) / L
            for c, r in tops:
                t = float(np.dot(np.array([c.x, c.y]) - a, d))
                off = abs(float(np.cross(d, np.array([c.x, c.y]) - a)))
                if off < r + 0.6 and -r < t < L + r:
                    cuts.append((max(t - r, 0.0), min(t + r, L)))
            runs = [(0.0, L)]
            for c0, c1 in sorted(cuts):
                nxt = []
                for r0, r1 in runs:
                    if c1 <= r0 or c0 >= r1:
                        nxt.append((r0, r1))
                        continue
                    if c0 - r0 > 0.15:
                        nxt.append((r0, c0))
                    if r1 - c1 > 0.15:
                        nxt.append((c1, r1))
                runs = nxt
            for r0, r1 in runs:
                out.append([kind, r3([a + d * r0])[0], r3([a + d * r1])[0], round(h, 2)])
    return out


def axis_of(pg: Polygon) -> tuple:
    """The long axis of pg's minimum rotated rectangle: (end a, end b, width)."""
    c = np.asarray(pg.minimum_rotated_rectangle.exterior.coords)[:4]
    e = [np.linalg.norm(c[(k + 1) % 4] - c[k]) for k in range(4)]
    k = int(np.argmax(e))
    a = (c[(k + 3) % 4] + c[k]) / 2
    b = (c[(k + 1) % 4] + c[(k + 2) % 4]) / 2
    return a, b, float(min(e))


def piers(spines: list, tracks, roads, level: float, Hf, deck) -> list:
    """Pier pairs under the deck's spines: [x, y, ground z] each, every PIER_STEP m at most, never near a track or on
    a road."""
    out = []
    for a, b, half in spines:
        a, b = np.asarray(a), np.asarray(b)
        L = float(np.linalg.norm(b - a))
        d = (b - a) / L
        n = np.array([-d[1], d[0]])
        last = -PIER_STEP
        cand = []
        for t in np.arange(1.5, L - 1.4, 0.5):
            ok = True
            pts = [a + d * t + n * s * half for s in (-1, 1)]
            for q in pts:
                pq = Point(q)
                if tracks.distance(pq) < PIER_TRACK or roads.contains(pq) or not deck.buffer(-0.2).contains(pq):
                    ok = False
            cand.append((t, ok, pts))
        k = 0
        while k < len(cand):
            t = cand[k][0]
            # the furthest valid spot within PIER_STEP of the last pier (or the first valid one past it)
            best = None
            for t2, ok, pts in cand[k:]:
                if t2 - last > PIER_STEP:
                    break
                if ok and t2 - last >= PIER_MIN:
                    best = (t2, pts)
            if best is None:
                nxt = [c for c in cand[k:] if c[1] and c[0] - last >= PIER_MIN]
                if not nxt:
                    break
                best = (nxt[0][0], nxt[0][2])
            last = best[0]
            for q in best[1]:
                out.append([round(float(q[0]), 3), round(float(q[1]), 3), round(float(Hf.at(q[0], q[1])), 3)])
            k = next((j for j, c in enumerate(cand) if c[0] > last), len(cand))
    return out


# ---------------------------------------------------------------- Massy TGV

def tgv(osm: dict, Hf) -> dict:
    pg = wpoly(osm, 417349777)
    mrr = pg.minimum_rotated_rectangle
    c = np.asarray(mrr.exterior.coords)[:4]
    cen = np.asarray(pg.centroid.coords[0])
    # the front: the rectangle's side facing the forecourt (the photo's road, south-east of the hall)
    want = np.array([math.cos(math.radians(-40.0)), math.sin(math.radians(-40.0))])
    best = None
    for k in range(4):
        a, b = c[k], c[(k + 1) % 4]
        mid = (a + b) / 2
        out = mid - cen
        out /= np.linalg.norm(out)
        if best is None or out @ want > best[0]:
            best = (out @ want, k)
    k = best[1]
    corners = [c[(k + j) % 4] for j in range(4)]       # front left... as seen from the forecourt: a, b front, then back
    fa, fb = corners[0], corners[1]
    front_mid = (fa + fb) / 2
    outward = front_mid - cen
    outward /= np.linalg.norm(outward)
    g = float(Hf.at(*(front_mid + outward * 6.0)))
    # inside: its lifts (OSM, levels -1 to 1); outside under the forecourt's canopy: the ways down to the TGV
    # platforms (OSM step ways between levels -1 and 0; the TGV itself is not drawn: they end in the dark)
    lifts, down = [], []
    for i, w in osm["ways"].items():
        t = w.get("tags", {})
        lv = t.get("level", "").split(";")
        if "-1" not in lv or "0" not in lv:
            continue
        p = wpts(osm, i)
        if t.get("highway") == "elevator" and len(p) > 2 and pg.contains(Polygon(p).centroid):
            q = Polygon(p).centroid
            lifts.append({"osm": "w%d" % i, "ring": ring(Polygon(p).minimum_rotated_rectangle),
                          "floor": round(float(Hf.at(q.x, q.y)), 3)})
        elif t.get("highway") == "steps" and len(p) > 1 and LineString(p).distance(pg) < 40.0:
            top, bottom = (p[-1], p[0]) if t.get("incline") == "up" else (p[0], p[-1])
            d = (bottom - top) / max(np.linalg.norm(bottom - top), 1e-6)
            down.append({"osm": "w%d" % i, "top": r3([top])[0], "dir": [round(float(d[0]), 4), round(float(d[1]), 4)],
                         "width": ESCALATOR_WIDTH if t.get("conveying") else STAIR_WIDTH,
                         "escalator": bool(t.get("conveying")), "ground": round(float(Hf.at(top[0], top[1])), 3)})
    return {"id": "massy:tgv", "osm": "w417349777", "name": "Gare de Massy TGV",
            "corners": r3(corners), "ground": round(g, 3), "eaves": round(g + TGV_EAVES, 3),
            "ridge": round(g + TGV_RIDGE, 3), "mast": round(g + TGV_MAST, 3), "canopy": list(TGV_CANOPY),
            "low": round(float(min(Hf.at(q[0], q[1]) for q in np.asarray(pg.exterior.coords))), 3),
            "floor": [round(float(Hf.at(q[0], q[1])), 3) for q in corners],     # the floor at the four corners
            "lifts": lifts, "down": down}


# ---------------------------------------------------------------- line 18

def l18(osm: dict, Hf, lien) -> dict:
    pg = wpoly(osm, 1334489725)
    nodes = osm["nodes"]
    stops = [np.asarray(fwd(nodes[i]["lat"], nodes[i]["lon"])) for i in (9951185171, 9951185172) if i in nodes] \
        or [np.asarray(p) for p in L18_STOPS]
    c = (stops[0] + stops[1]) / 2
    u = stops[1] - stops[0]
    u /= np.linalg.norm(u)
    v = np.array([-u[1], u[0]])
    # the surface hall: the OSM outline along the axis, stopping short of le Lien
    a, b, width = axis_of(pg)
    if np.dot(b - a, u) < 0:
        a, b = b, a
    hall = pg.difference(lien.buffer(1.0)) if lien is not None else pg
    hall = max(polys(hall), key=lambda p: p.area)
    ha, hb, hw = axis_of(hall)
    if np.dot(hb - ha, u) < 0:
        ha, hb = hb, ha
    g = float(Hf.at(c[0], c[1]))
    z_rail = g - L18_DEPTH
    z_plat = z_rail + L18_PLATFORM
    z_mezz = z_plat + L18_MEZZ[2]
    to_map = lambda al, ac: (c + u * al + v * ac)
    s0, s1, sh = L18_SHAFT
    shaft = Polygon([to_map(s0, -sh), to_map(s1, -sh), to_map(s1, sh), to_map(s0, sh)])
    assert hall.buffer(-0.5).contains(shaft), "the shaft must open inside the surface hall"
    # the corten posts along the tracks' side of the hall (the side facing north-west, photo)
    n_side = v if np.dot(v, np.array([-1.0, 1.0])) > 0 else -v
    posts = []
    hl = float(np.linalg.norm(hb - ha))
    for t in np.arange(2.0, hl - 1.0, 3.0):
        q = ha + (hb - ha) / hl * t + n_side * (hw / 2 + 2.2)
        posts.append([round(float(q[0]), 3), round(float(q[1]), 3), round(float(Hf.at(q[0], q[1])), 3)])
    return {"id": "massy:l18", "osm": "w1334489725", "name": "Massy-Palaiseau (ligne 18)",
            "hall": {"ring": ring(hall), "a": r3([ha])[0], "b": r3([hb])[0], "width": round(hw, 3),
                     "floor": round(g, 3), "roof": [round(g + L18_ROOF[0], 3), round(g + L18_ROOF[1], 3)],
                     "end_block": L18_END_BLOCK, "track_side": r3([n_side])[0], "posts": posts},
            "frame": {"c": r3([c])[0], "u": [round(float(u[0]), 6), round(float(u[1]), 6)]},
            "rail": round(z_rail, 3), "platform": round(z_plat, 3), "mezzanine": round(z_mezz, 3),
            "ceiling": round(z_plat + L18_CEILING, 3),
            "box": list(L18_BOX), "track": L18_TRACK, "edge": L18_EDGE, "platforms": L18_PLATFORMS,
            "mezz": list(L18_MEZZ[:2]), "shaft": list(L18_SHAFT), "shaft_ring": ring(shaft),
            "ground": round(g, 3), "stops": r3(stops)}


def l18_zone(st: dict) -> dict:
    """The shaft as a stairwell zone for patch_world.py: the ground drops to the mezzanine's floor in it, and its
    walls (the patch's skirts) start at the box's ceiling all round (portals): under it the shaft's floor is part of
    the mezzanine, above it the shaft is a light well up to the hall."""
    rg_ = st["shaft_ring"]
    c = np.asarray(st["frame"]["c"])
    u = np.asarray(st["frame"]["u"])
    s0, s1, _ = st["shaft"]
    portals = [{"a": rg_[k], "b": rg_[(k + 1) % len(rg_)], "z_open": st["ceiling"]} for k in range(len(rg_))]
    return {"kind": "stairwell", "side": None, "source": "massy:l18-shaft", "polygons": [[rg_]],
            "axis": r3([c + u * s0, c + u * s1]), "axis_z": [st["mezzanine"], st["mezzanine"]], "portals": portals}


def l18_link(st: dict, deck, level: float) -> dict:
    """The stairs from le Lien down into the line 18 hall (the station is reached from the footbridges): from the
    deck's edge nearest the hall's high end, down the hall's axis to its floor."""
    hb = np.asarray(st["hall"]["b"])
    ha = np.asarray(st["hall"]["a"])
    d = (ha - hb) / np.linalg.norm(ha - hb)         # down the stairs: towards the low end
    # the top: where the hall's axis, carried on past its high end, meets the deck
    ray = LineString([hb, hb - d * 40.0])
    hit = ray.intersection(deck)
    if hit.is_empty:
        edge = deck.exterior if deck.geom_type == "Polygon" else unary_union([p.exterior for p in deck.geoms])
        q = nearest_points(edge, Point(hb))[0]
    else:
        q = min((Point(c) for g in getattr(hit, "geoms", [hit]) for c in g.coords), key=lambda c: c.distance(Point(hb)))
    top = np.array([q.x, q.y])
    rise = level - st["hall"]["floor"]
    n = int(round(rise / STEP_RISE))
    run = n * STEP_GOING
    half = run / 2
    l0 = top + d * (half + 1.6)                     # a landing halfway (1.6 m) between two flights
    l1 = top + d * half
    bottom = top + d * (run + 1.6)
    zm = st["hall"]["floor"] + rise / 2
    return {"id": "flight:l18-link", "osm": "", "pts": r3([bottom, l0, l1, top]),
            "zs": [st["hall"]["floor"], round(zm, 3), round(zm, 3), round(level, 3)], "bottom": st["hall"]["floor"],
            "top": round(level, 3), "width": 3.0, "steps": n, "escalator": False}


# ---------------------------------------------------------------- the Atlantis bus station

BUS_STATION = 1285904771        # OSM amenity=bus_station "Massy-Palaiseau Atlantis"
BUS_ISLANDS = [("Îlot A", [1534300499, 1413127082]), ("Îlot B", [1226991402]), ("Îlot C", [1226991401])]
BUS_KERB = 0.18                 # m: the islands' top over the bus lanes (French bus stop kerbs are 18-21 cm)
BUS_TRACK_CLEAR = 2.2           # m from a track centre an island keeps clear of
BUS_UNDERGROUND = 15.0          # m: a track running longer than this inside the bus station is under it (the TGV)
FENCE_OFFSET = 2.3              # m from the nearest track centre: the fence (outside the 1.75 m kinematic gauge)
FENCE_REACH = 9.0               # m from the bus station or a busway: where the fence runs
FENCE_GAP = 1.5                 # m kept free round a quay, a flight, a lift
FENCE_MIN = 3.0                 # m: shorter runs are left out
FENCE_HEIGHT = 2.0              # m, as the line's right-of-way fences (build_rail.py FENCE_HEIGHT)


def bus_area(osm: dict, tracks_xy: list) -> tuple:
    """(the bus station and its busways as an area, the tracks on the ground near it as a line union): a track
    running BUS_UNDERGROUND m inside the bus station is under it (the TGV line, in a tunnel there: yard.py leaves it
    out, a rail.json built before still has it)."""
    bs = wpoly(osm, BUS_STATION)
    ways = [LineString(wpts(osm, i)) for i, w in osm["ways"].items()
            if w.get("tags", {}).get("highway") == "busway" and len(w.get("geometry", [])) > 1]
    area = unary_union([bs] + [w.buffer(3.5) for w in ways if w.distance(bs) < 30.0])
    inner = bs.buffer(-3.0)
    near = area.buffer(60.0)
    tracks = []
    for tid, p, z in tracks_xy:
        if len(p) < 2:
            continue
        ln = LineString(p)
        if not ln.intersects(near) or ln.intersection(inner).length > BUS_UNDERGROUND:
            continue
        tracks.append(ln)
    return area, unary_union(tracks), unary_union(ways) if ways else None


def bus_islands(osm: dict, Hf, world: dict, tracks) -> list:
    """The bus station's islands (OSM highway=platform "Îlot A/B/C"): their outlines (Îlot A's two drawings
    together, with the pipeline's platform pieces mostly inside them), kept BUS_TRACK_CLEAR m off the tracks, their top
    BUS_KERB m over the lanes along their length (the ground across them, every 4 m, smoothed)."""
    near = wpoly(osm, BUS_STATION).buffer(40.0)
    plats = [Polygon(g["rings"][0], g["rings"][1:]).buffer(0) for g in world["ground"]
             if g["rings"] and g["kind"] == "platform" and Polygon(g["rings"][0]).intersects(near)]
    out = []
    for name, ids in BUS_ISLANDS:
        pg = unary_union([wpoly(osm, i) for i in ids if i in osm["ways"]])
        if pg.is_empty:
            continue
        for q in plats:
            if q.intersects(pg) and q.intersection(pg).area > 0.5 * q.area:
                pg = pg.union(q)
        if not tracks.is_empty:
            pg = pg.difference(tracks.buffer(BUS_TRACK_CLEAR))
        parts = sorted([p for p in polys(pg.buffer(0)) if p.area > 5.0], key=lambda p: -p.area)
        for k, p in enumerate(parts):
            p = shapely.set_precision(p, 0.001)
            a, b, w = axis_of(p)
            L = float(np.linalg.norm(b - a))
            d = (b - a) / L
            n = np.array([-d[1], d[0]])
            ts = np.linspace(0.0, L, max(int(L / 4.0) + 1, 2))
            zs = []
            for t in ts:
                c = a + d * t
                zs.append(float(np.median([Hf.at(*(c + n * s)) for s in np.linspace(-(w / 2 + 2.0), w / 2 + 2.0, 9)])))
            zs = np.convolve(np.pad(zs, 1, mode="edge"), np.ones(3) / 3.0, mode="valid")
            slug = name.split()[-1].lower() + ("" if k == 0 else str(k + 1))
            out.append({"id": "bus_island:%s" % slug, "name": name, "osm": ["w%d" % i for i in ids],
                        "ring": ring(p), "area": round(p.area, 1), "axis": r3([a + d * t for t in ts]),
                        "axis_z": [round(float(z) + BUS_KERB, 3) for z in zs],
                        "top": round(float(np.median(zs)) + BUS_KERB, 3)})
    return out


def bus_island_zones(isl: list) -> list:
    """The islands as zones for patch_world.py: raised quays (kind bus_island: concrete platform pieces, their top
    along the axis), taking the pipeline's raised bits and kerbs inside them into their own surface."""
    return [{"kind": "bus_island", "side": None, "source": "osm:" + i["osm"][0], "polygons": [[i["ring"]]],
             "axis": i["axis"], "axis_z": i["axis_z"], "portals": []} for i in isl]


def rer_fences(osm: dict, Hf, world: dict, tracks, area, busways, gaps) -> list:
    """The fence between the bus station and the tracks beside it (RATP welded mesh, FENCE_HEIGHT m): the outline
    FENCE_OFFSET m off the nearest track centre, where it faces the bus station's lanes and runs within FENCE_REACH m
    of them; open round every quay, flight, lift and pier (`gaps`), at the buildings, and where a path crosses the
    tracks on the ground. Polylines resampled every 2.5 m, for patch_world.py's world fences (prop_placer.gd)."""
    if tracks.is_empty:
        return []
    corridor = tracks.buffer(FENCE_OFFSET)
    reach = area.buffer(FENCE_REACH)
    core = busways if busways is not None else area
    bp = [Polygon(b["rings"][0]).buffer(0.3) for b in world["buildings"] if b.get("walls", True) and b["rings"]
          and Polygon(b["rings"][0]).intersects(reach)]
    xing = []
    for i, w in osm["ways"].items():
        t = w.get("tags", {})
        if not t.get("highway") or t.get("bridge") or t.get("tunnel") or t.get("layer", "0") not in ("0", ""):
            continue
        ln = LineString(wpts(osm, i))
        if ln.intersects(tracks) and ln.intersects(reach):
            x = ln.intersection(tracks)
            xing.append(x.buffer(2.0))
    hole = unary_union(list(gaps) + bp + xing)
    runs = []
    for p in polys(corridor):
        for r in [p.exterior]:                  # not the holes: wedges between diverging tracks
            c = rg.resample(np.asarray(r.coords), 0.5)
            keep = np.zeros(len(c), dtype=bool)
            for k in range(len(c)):
                q = c[k]
                if not reach.contains(Point(q)):
                    continue
                e = c[min(k + 1, len(c) - 1)] - c[max(k - 1, 0)]
                nl = np.array([-e[1], e[0]]) / max(np.linalg.norm(e), 1e-9)
                out = -nl if corridor.contains(Point(q + nl * 0.3)) else nl
                keep[k] = core.distance(Point(q + out * 2.0)) < core.distance(Point(q)) - 0.5
            k = 0
            while k < len(c):
                if not keep[k]:
                    k += 1
                    continue
                j = k
                while j + 1 < len(c) and keep[j + 1]:
                    j += 1
                if j > k:
                    runs.append(LineString(c[k:j + 1]))
                k = j + 1
    out = []
    for ln in runs:
        rest = ln.difference(hole) if not hole.is_empty else ln
        for part in getattr(rest, "geoms", [rest]):
            if part.is_empty or part.geom_type != "LineString" or part.length < FENCE_MIN:
                continue
            q = rg.resample(np.asarray(part.coords), 2.5)
            if np.linalg.norm(q[-1] - np.asarray(part.coords)[-1]) > 0.05:
                q = np.vstack([q, np.asarray(part.coords)[-1]])
            out.append({"id": "fence:massy:%d" % (len(out) + 1), "style": "mesh", "h": FENCE_HEIGHT, "pts": r3(q),
                        "z": [round(float(Hf.at(x, y)), 3) for x, y in q], "length": round(part.length, 1)})
    return out


# ---------------------------------------------------------------- all of it

def build(world: dict, H: rg.Heights, tracks_xy: list, islands: list) -> tuple:
    """(rail.json `massy`, zones to add: the line 18 shaft (stairwell) and the repairs (regrade)). `tracks_xy`: every
    track as (id, points, rail z per point): the alignment's two and the yard's; `islands`: (polygon, top z) of the
    raised platforms."""
    osm = load()
    reps = repairs(osm, H)
    # the Atlantis bus station and the bus hangar laid out again (bus_station.py): their ground repairs come last
    import bus_station as bst
    BP = bst.plan(H, tracks_xy)
    reps = reps + bst.repairs(BP)
    Hf = rg.Heights.__new__(rg.Heights)
    Hf.__dict__.update({k: v for k, v in H.__dict__.items() if not k.startswith("_nodes")})
    Hf.data = apply_repairs(H, reps)
    steps = classify_steps(osm)
    g0 = ground_ref(steps, Hf)
    level = g0 + LEVEL1_STEPS * STEP_RISE
    # the bus station's raised islands: the flights landing on them start from their top
    bus_zone, surf_tracks, busways = bus_area(osm, tracks_xy)
    islands = list(islands) + bst.island_tops(BP)
    # the deck's parts
    lien = wpoly(osm, 417349802)
    vault = wpoly(osm, 1286041252)
    hist_line = LineString(np.vstack([wpts(osm, 554922069), wpts(osm, 1285665811)[1:]]))
    hist = hist_line.buffer(HIST_WIDTH / 2, cap_style=2, join_style=2)
    hist_hall = wpoly(osm, 1285665815)
    atl = unary_union([wpoly(osm, i) for i in (1285665813, 1285665800, 1487139397)])
    parts = {"lien": {"geom": lien, "edge": "glass", "edge_h": VAULT_SPRING},
             "vault": {"geom": vault, "edge": "glass", "edge_h": VAULT_SPRING},
             "hist": {"geom": hist, "edge": "panel", "edge_h": HIST_HEIGHT},
             "hist_hall": {"geom": hist_hall, "edge": "panel", "edge_h": HIST_HEIGHT + 1.0},
             "atlantis": {"geom": atl.buffer(0.01).simplify(0.05) if atl.geom_type == "Polygon" else
                          max(polys(atl), key=lambda p: p.area), "edge": "balustrade", "edge_h": 1.2}}
    deck = unary_union([lien, hist, hist_hall, atl]).buffer(0.05, join_style=2).buffer(-0.05, join_style=2)
    # the buildings the deck runs into (kept: the RER B building, the RER C one...)
    replaced = {"osm:" + i for i in REPLACED_BUILDINGS}
    kept = []
    for b in world["buildings"]:
        if not b.get("walls", True) or not b["rings"]:
            continue
        base = b["id"].split("_rest")[0]
        if base in replaced:
            continue
        bp = Polygon(b["rings"][0]).buffer(0)
        if not bp.intersects(deck.buffer(0.5)):
            continue
        tiers = b.get("toy", {}).get("tiers", [])
        top = max([t["top"] for t in tiers] or [b["base_z"] + b["height"]])
        if top > level + 2.0:
            kept.append(bp)
    kept_u = unary_union(kept) if kept else None
    if kept_u is not None:
        deck = deck.difference(kept_u)
    flights, holes = build_flights(steps, deck, level, Hf, islands,
                                   unary_union([LineString(t[1]) for t in tracks_xy if len(t[1]) > 1]))
    if holes:
        deck = deck.difference(unary_union(holes))
    deck = unary_union([p for p in polys(deck) if p.area > 4.0])
    st = l18(osm, Hf, lien)
    flights.append(l18_link(st, deck, level))
    lifts_ = lifts(osm, deck, level, Hf)
    ed = edges(deck, parts, kept_u, flights, lifts_, level)
    # the clearance over the rails under the deck (its structure's underside to the rail top)
    tracks = unary_union([LineString(t[1]) for t in tracks_xy if len(t[1]) > 1])
    clear = None
    for tid, p, z in tracks_xy:
        if len(p) < 2:
            continue
        s = rg.cumlen(np.asarray(p))
        ln = LineString(p)
        over = ln.intersection(deck)
        for g in getattr(over, "geoms", [over]):
            if g.is_empty or g.geom_type != "LineString":
                continue
            for q in np.asarray(g.coords):
                c_ = level - DECK_DEPTH - float(np.interp(ln.project(Point(q)), s, z))
                if clear is None or c_ < clear[0]:
                    clear = (round(c_, 2), tid)
    roads = unary_union([Polygon(g["rings"][0], g["rings"][1:]).buffer(0) for g in world["ground"]
                         if g["rings"] and g["kind"] == "road" and Polygon(g["rings"][0]).intersects(deck.buffer(30))])
    va, vb, vw = axis_of(vault)
    spines = [(va, vb, vw / 2 - 0.6), (hist_line.coords[0], hist_line.coords[-1], HIST_WIDTH / 2 - 0.5)]
    for p in polys(atl):
        a, b, w = axis_of(p)
        spines.append((a, b, min(w / 2 - 0.5, 3.0)))
    pr = piers(spines, tracks, unary_union([roads, BP.m_lanes, BP.m_depot_hard]), level, Hf, deck)   # not on a bus lane
    # the fence between the bus station and the tracks, open at every quay and access
    fence_gaps = [isl[0].buffer(FENCE_GAP) for isl in islands]
    fence_gaps += [LineString(f["pts"]).buffer(f["width"] / 2 + FENCE_GAP, cap_style=2) for f in flights]
    fence_gaps += [Polygon(lf["ring"]).buffer(FENCE_GAP) for lf in lifts_]
    fence_gaps += [Point(p[0], p[1]).buffer(1.0) for p in pr]
    fences = bst.merge_fences(BP, Hf, rer_fences(osm, Hf, world, surf_tracks, bus_zone, busways, fence_gaps),
                              fence_gaps, world)
    roofs = {"vault": {"a": r3([va])[0], "b": r3([vb])[0], "width": round(vw, 3), "spring": round(level + VAULT_SPRING, 3),
                       "apex": round(level + VAULT_SPRING + VAULT_RISE, 3), "rib_step": RIB_STEP},
             # the halls' roofs reach into the vault until they meet its glass (no gap between them)
             "flat": [dict(mesh2d(p), z=round(level + HALL_HEIGHT, 3), kind="hall")
                      for p in polys(unary_union(polys(lien.difference(vault.buffer(0.3)))).buffer(2.5, join_style=2)
                                     .intersection(lien)) if p.area > 8.0]
                     + [dict(mesh2d(p), z=round(level + HIST_HEIGHT, 3), kind="hist")
                        for p in polys(hist.difference(hist_hall))]
                     + [dict(mesh2d(p), z=round(level + HIST_HEIGHT + 1.0, 3), kind="hist_hall")
                        for p in polys(hist_hall)],
             "canopy": [dict(mesh2d(p.buffer(1.2, join_style=2)), z=round(level + CANOPY_HEIGHT, 3),
                             a=r3([axis_of(p)[0]])[0], b=r3([axis_of(p)[1]])[0], width=round(axis_of(p)[2] + 2.4, 3))
                        for p in polys(atl)], "frame_step": FRAME_STEP}
    out = {"about": "tools/rail/massy_station.py: Massy-Palaiseau's footbridges, halls, line 18 station and ground "
                    "repairs (map coordinates; levels are absolute map z)",
           "osm_timestamp": osm["timestamp"], "ground": round(g0, 3), "level": round(level, 3),
           "deck_depth": DECK_DEPTH, "clearance": clear[0] if clear else None, "repairs": reps,
           "deck": [mesh2d(p) for p in polys(deck)],
           "edges": ed, "roofs": roofs, "flights": flights, "lifts": lifts_, "piers": pr, "pier_size": PIER_SIZE,
           "names": {"lien": "Passerelle « le Lien »", "hist": "Passerelle historique",
                     "atlantis": "Passerelle de la gare routière Atlantis"},
           # (and the OSM lift shafts the map drew as buildings: massy_builder.gd draws their glazed shafts there)
           "replaces": {"buildings": sorted(replaced | {"osm:" + lf["osm"] for lf in lifts_}),
                        "bridges_near": [ring(deck.buffer(8.0).convex_hull)]},
           "tgv": tgv(osm, Hf), "l18": st}
    # the shaft first, then the line 18 hall's concrete floor, its site's gravel (OSM still says a building site
    # there), le Lien's hall's repair keeping its ground; build_rail.py leaves each the ground the earlier ones did not
    zones = [l18_zone(st),
             {"kind": "regrade_floor", "side": None, "source": "massy:l18-hall", "polygons": [[st["hall"]["ring"]]]}]
    zones += [{"kind": "regrade_gravel" if rp["id"] == "repair:l18" else "regrade", "side": None, "source": rp["id"],
               "polygons": [[rp["ring"]]]} for rp in reps
               if not rp["id"].startswith("repair:bus-")]   # bus_station.zones() has its own
    # the bus station: its raised islands before the repairs (one runs under le Lien's hall's), its fence
    zones[2:2] = bst.zones(BP)
    out["bus_station"] = bst.finish(BP, Hf, world, flights, lifts_, pr, deck)
    out["fences"] = fences
    log("massy: bus station %s, %d fence runs between the bus station and the tracks (%.0f m)" % (
        bst.summary(BP, out["bus_station"]), len(fences), sum(f["length"] for f in fences)))
    log("massy: concourse at %.2f m (forecourts %.2f m + %d steps), %s, deck %.0f m², %d flights, %d lifts, %d piers, "
        "%d edge runs" % (level, g0, LEVEL1_STEPS, "%.2f m clear over the rails at least (%s)" % clear if clear else
                          "no track under the deck", deck.area, len(flights), len(lifts_), len(pr), len(ed)))
    log("massy: line 18 rail %.2f m, platforms %.2f m, mezzanine %.2f m (hall floor %.2f m)" % (
        st["rail"], st["platform"], st["mezzanine"], st["ground"]))
    return out, zones
