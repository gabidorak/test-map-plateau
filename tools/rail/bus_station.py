"""The Atlantis bus station at Massy-Palaiseau laid out again (2026-11-07), and the bus depot beside it (bus_depot.py).
massy_station.py calls plan() (the ground: repairs and zones) and finish() (what the builder draws, the props, the
routes); its result is rail.json `massy` `bus_station`. patch_world.py draws the ground (the zones), moves and drops
the props, fences and kerbs in the way; scripts/builder/massy_builder.gd (and hangar_builder.gd) draw the rest;
tools/rail/bus_routes.py puts the 4606 on the new lanes; tools/online/garages.py puts the bus job's depot under the
depot's roof.

Why: the map pipeline had the bus station on the LiDAR's ground (bumps, a 2 m wavy wall from OSM's barrier=wall along
the avenue), the islands' outlines from OSM (ragged), lanes 5-6 m wide and a U-turn round Îlot B's tip of a ~6 m
radius that an 18 m bus could not make.

Layout, in a frame along the islands' common axis (s along it, north-east; t across it, + towards the tracks):
- the quays (Îlots A, B, C): one straight band QUAY across the axis, rounded noses, their top BUS_KERB over the lanes;
- the RER side lane between the quays and RER_KERB: two buses side by side (a bus at the quay and one passing);
- the Massy side lane between the quays and MASSY_KERB: a bus and a half; wider along Îlot B's north-east end
  (BULB) where the buses come out of the turnaround;
- a raised sidewalk WALK_KERB over the lanes along the Massy side, open where a road comes in;
- the turnaround (LOOP): round Îlot B's north-east nose, the buses' path LOOP_R from the nose's centre (an 18 m
  articulated bus turns within a 12.5 m outer radius, EU rules), the asphalt LOOP_PAVE round it;
- the fence FENCE_T from the axis between the RER side lane and the tracks (straight, outside the gauge);
- the ground: the lanes on one profile along the axis (a smoothed fit of the LiDAR, flat across), eased into the
  ground round them over BLEND (not across the tracks' ballast);
- markings: the RER side lane's middle line, its edge line, arrows, the stop bays (yellow zigzags and BUS) at every
  bus stop pole, zebra crossings over the Massy side lane, the hatched nose of Îlot C, the give-way line where the
  depot's ramps open the sidewalk;
- lamps along the quays and the sidewalk.
The bus depot (bus_depot.py, 2026-11-08: an open roof after Gent's bus station over a floor ~2 m over the lanes,
its ramps in at the north-east and out at the south-west from and to the Massy side lane, a car park, the
sidewalks and green round it) replaces the brick hangar of 2026-11-07 south-east of Îlot C.
Assumed: the widths (no plan of the bus station gives them; the photos show two buses side by side along the RER)."""
import math

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import railgeo as rg

ORIGIN = np.array([4355.109, 1150.884])     # the islands' common axis (a fit of OSM's Îlots A, B, C): a point...
HEADING = math.radians(49.817)              # ...and its heading (x east, y north), to the north-east
D = np.array([math.cos(HEADING), math.sin(HEADING)])
N = np.array([-D[1], D[0]])                 # across, towards the tracks

BUS_KERB = 0.18                 # m: the quays over the lanes (French bus stop kerbs are 18-21 cm)
WALK_KERB = 0.15                # m: the sidewalk over the lanes
QUAY = (-3.5, 4.0)              # t of the quays' kerbs (Massy side, RER side)
QUAYS = [("c", "Îlot C", -216.0, -10.0, [1226991401]), ("b", "Îlot B", 14.0, 81.0, [1226991402]),
         ("a", "Îlot A", 92.5, 222.0, [1534300499, 1413127082])]      # nose to nose along the axis
RER_KERB = 12.5                 # t: the RER side lane 8.5 m wide (two 2.55 m buses side by side with room)
MASSY_KERB = -9.0               # t: the Massy side lane 5.5 m wide
BULB = (40.0, 55.0, -12.4)      # the Massy side lane widened from s0 to s1 (and on to the turnaround) to this t
WALK = [(-228.0, -95.0), (-75.0, 35.0), (61.0, 82.0), (96.0, 220.0)]   # the sidewalk along the Massy side (s): open at
# the bus depot's ramps' feet (bus_depot.EXIT_GAP, ENTRY_GAP)
WALK_OUT = {"c": -10.4, "bulb": -13.6, "a": -12.4}   # t of its back: along Îlot C, by the turnaround, along Îlot A
ENDS = (-232.0, 236.0)          # s: the bus station's asphalt (the busways go on beyond)
SW_TAPER = (-216.0, 8.0)        # the RER side lane narrows to the busway (t) from Îlot C's nose to the south-west end
LOOP = (77.25, 0.25)            # the turnaround's centre: Îlot B's north-east nose
LOOP_R = 10.0                   # m: the buses' path round it
LOOP_PAVE = 12.6                # m: its asphalt
FENCE_T = 13.6                  # t of the fence between the RER side lane and the tracks
FENCE_TRACK = 2.3               # m from a track centre it keeps at least (outside the 1.75 m kinematic gauge)
BLEND = 4.0                     # m over which the bus station's ground eases into the ground round it
TRACK_CLEAR = 2.5               # m from a track centre the ground is not touched (the ballast strip, yard.py)
PROFILE_STEP = 40.0             # m between the knots of the lanes' profile
PROFILE_SMOOTH = 30.0           # weight of the profile's grade changes in its fit
LANE_IN = 6.0                   # t of the buses' path in along the RER side (at the quay: the terminus)
LANE_OUT_STOP = 5.6             # t of the buses' path out along Îlot B's RER side (the stop: the bus at the kerb)
LANE_MASSY = -6.25              # t of the buses' path along the Massy side lane
STOP_POLE = ("prop:3404", 36.0)  # the 4606's stop at Îlot B (its pole, OSM n12385438761) and where it goes along s
OUT_START = -4.0                # s where the way out starts (between Îlots C and B, clear of the terminus)
STOP_AHEAD = 11.0               # m: the stop's mark (where the bus's front stops) past its pole, as the pipeline's
WALL_STEP = 0.35                # m: ground standing this much higher beside a forecourt or the sidewalk gets a wall
PARAPET = 1.0                   # m: the walls' parapet over the higher ground
LAMP_STEP = 24.0                # m between the lamps along the quays and the sidewalk


# ---------------------------------------------------------------- frame

def xy(s, t) -> np.ndarray:
    s, t = np.asarray(s, dtype=np.float64), np.asarray(t, dtype=np.float64)
    return ORIGIN + s[..., None] * D + t[..., None] * N


def st(p) -> np.ndarray:
    q = np.asarray(p, dtype=np.float64)[..., :2] - ORIGIN
    return np.stack([q @ D, q @ N], axis=-1)


def to_xy(g):
    """A shapely geometry drawn in (s, t) put on the map."""
    return affinity.affine_transform(g, [D[0], N[0], D[1], N[1], ORIGIN[0], ORIGIN[1]])


def to_st(g):
    return affinity.affine_transform(g, [D[0], D[1], N[0], N[1], -ORIGIN @ D, -ORIGIN @ N])


def r3(p) -> list:
    return [[round(float(a), 3) for a in q] for q in np.asarray(p)]


def ring(pg) -> list:
    return r3(np.asarray(pg.exterior.coords)[:-1])


def polys(g) -> list:
    return [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05]


SEAM_TOL = 2e-3                 # m: a zone's outline this close to an earlier zone's runs on it (seams())


def seam_on(g, refs: list, tol: float = SEAM_TOL):
    """g with its outline put on the outlines of the polygons `refs` where it runs along them (within tol): its
    vertices there that are not theirs and lie on the line through their neighbours dropped, then theirs put in it
    (shapely.snap). The two then share the same vertices along their common edge."""
    ref = shapely.GeometryCollection(refs)
    edge = shapely.MultiLineString([r for p in refs for r in [p.exterior] + list(p.interiors)])
    shapely.prepare(edge)
    keep_pts = {tuple(c) for c in shapely.get_coordinates(ref).tolist()}

    def clean(c):
        c = np.asarray(c)[:-1]
        out = []
        for i, p in enumerate(c):
            q = out[-1] if out else c[i - 1]
            r = c[(i + 1) % len(c)]
            if tuple(p.tolist()) not in keep_pts and edge.distance(Point(p)) < tol:
                d = r - q
                L = float(np.hypot(d[0], d[1]))
                if L > 1e-9 and abs(d[0] * (p[1] - q[1]) - d[1] * (p[0] - q[0])) / L < tol * 0.5:
                    continue
            out.append(p)
        return out if len(out) >= 3 else c

    res = [Polygon(clean(p.exterior.coords), [clean(h.coords) for h in p.interiors]) for p in polys(g)]
    return shapely.snap(shapely.MultiPolygon(res) if len(res) != 1 else res[0], ref, tol)


def seams(zs: list) -> list:
    """Each zone's outline put on the earlier zones' where it runs along them (seam_on; patch_world.py: first wins).
    Where two zones met, the later one's vertices stood a fraction of a mm off the earlier one's edge (the lanes' Massy
    edge kept its 0.5 m samples where the sidewalks' simplified kerb line and the depot's ramps have none, then both were
    rounded to the mm): patch_world.py cut hair-thin slivers along those kerbs, ground edges used three times and
    cracks."""
    done = []
    for z in zs:
        g = unary_union([Polygon(p[0], p[1:]) for p in z["polygons"]])
        near = [p for q in done for p in polys(q) if p.distance(g) < SEAM_TOL]
        if near:
            g2 = seam_on(g, near)
            if g2.is_valid and abs(g2.area - g.area) < 1e-3 * max(g.area, 1.0) and len(polys(g2)) == len(polys(g)):
                z["polygons"] = _pg(polys(g2))
                g = g2
        done.append(g)
    return zs


# ---------------------------------------------------------------- the ground

def fit_profile(H: rg.Heights) -> tuple:
    """The lanes' level along the axis: a piecewise linear fit (knots every PROFILE_STEP m) of the LiDAR along both
    lanes, its grade changes damped, three times without the samples more than 0.25 m off it (a bus, a kerb)."""
    ks = np.arange(ENDS[0] - 8.0, ENDS[1] + 8.0 + 1e-6, PROFILE_STEP)
    ks[-1] = max(ks[-1], ENDS[1] + 8.0)
    ss = np.arange(ENDS[0], ENDS[1] + 1e-6, 2.0)
    S = np.concatenate([ss, ss])
    P = xy(S, np.concatenate([np.full(len(ss), 7.5), np.full(len(ss), -6.0)]))
    z = np.asarray(H.at(P[:, 0], P[:, 1]), dtype=np.float64)
    A = np.zeros((len(S), len(ks)))
    k = np.clip(np.searchsorted(ks, S) - 1, 0, len(ks) - 2)
    f = (S - ks[k]) / (ks[k + 1] - ks[k])
    A[np.arange(len(S)), k] = 1 - f
    A[np.arange(len(S)), k + 1] = f
    D2 = np.zeros((len(ks) - 2, len(ks)))
    for i in range(len(ks) - 2):
        D2[i, i:i + 3] = [1.0, -2.0, 1.0]
    keep = np.ones(len(S), dtype=bool)
    for _ in range(3):
        M = np.vstack([A[keep], D2 * PROFILE_SMOOTH])
        y = np.concatenate([z[keep], np.zeros(len(ks) - 2)])
        zk = np.linalg.lstsq(M, y, rcond=None)[0]
        keep = np.abs(A @ zk - z) < 0.25
    return ks, zk


class Plan:
    """The layout in (s, t) and on the map."""

    def __init__(self, H: rg.Heights, tracks_xy: list):
        self.ks, self.kz = fit_profile(H)
        lines = [LineString(p) for _, p, _ in tracks_xy if len(p) > 1]
        self.tracks = unary_union(lines) if lines else None
        near = to_xy(box(ENDS[0] - 30, -60, ENDS[1] + 30, 40))
        self.tracks_near = unary_union([ln for ln in lines if ln.intersects(near)]) if lines else None
        # quays
        hw = (QUAY[1] - QUAY[0]) / 2
        tc = (QUAY[1] + QUAY[0]) / 2
        self.quays = []
        for key, name, s0, s1, osm in QUAYS:
            g = LineString([(s0 + hw, tc), (s1 - hw, tc)]).buffer(hw, quad_segs=12)
            self.quays.append({"key": key, "name": name, "s0": s0, "s1": s1, "osm": osm, "st": g})
        quays = unary_union([q["st"] for q in self.quays])
        # the Massy side kerb and the sidewalk's back
        sp = np.arange(ENDS[0] - 10, ENDS[1] + 10.01, 0.5)
        self.massy = lambda s: np.interp(s, [BULB[0], BULB[1], 82.0, 96.0], [MASSY_KERB, BULB[2], BULB[2], MASSY_KERB])
        self.walk_out = lambda s: np.interp(s, [BULB[0], BULB[1], 82.0, 96.0],
                                            [WALK_OUT["c"], WALK_OUT["bulb"], WALK_OUT["bulb"], WALK_OUT["a"]])
        rer = np.interp(sp, [ENDS[0], SW_TAPER[0]], [SW_TAPER[1], RER_KERB])
        lanes = Polygon(np.r_[np.c_[sp, self.massy(sp)], np.c_[sp[::-1], rer[::-1]]]).intersection(
            box(ENDS[0], -30, ENDS[1], 30))
        loop = Point(LOOP).buffer(LOOP_PAVE, quad_segs=24)
        self.walks = []
        for s0, s1 in WALK:
            q = np.arange(s0, s1 + 1e-6, 0.5)
            q[-1] = s1
            g = Polygon(np.r_[np.c_[q, self.massy(q)], np.c_[q[::-1], self.walk_out(q[::-1])]]).buffer(0)
            g = g.difference(loop).simplify(0.01)
            # its ends at the depot's ramp out (bus_depot.EXIT_GAP): rounded on the lane's side (a quarter circle)
            for e, sg in ((s0, 1.0), (s1, -1.0)):
                if e in (WALK[0][1], WALK[1][0]):
                    k, b = float(self.massy(e)), float(self.walk_out(e))
                    r = k - b
                    c = Point(e + sg * r, b)
                    g = g.difference(box(min(e, e + sg * r), b, max(e, e + sg * r), k + 0.01).difference(
                        c.buffer(r, quad_segs=12)))
            g = max(polys(g), key=lambda p: p.area)
            mid = np.c_[q, (self.massy(q) + self.walk_out(q)) / 2]
            self.walks.append({"st": g, "axis": mid})
        walks = unary_union([w["st"] for w in self.walks])
        self.lanes = unary_union([lanes, loop]).difference(walks).difference(quays)
        self.lanes = unary_union([p for p in polys(self.lanes) if p.area > 4.0])
        self.apron = unary_union([self.lanes, quays, walks])
        # the eased ground round it, not behind the sidewalk (a wall there) nor over the depot (bus_depot.py)
        behind = unary_union([box(s0_, -80.0, s1_, -9.5) for s0_, s1_ in WALK])
        band = self.apron.buffer(BLEND).difference(self.apron).difference(behind)
        band = band.intersection(box(ENDS[0] - BLEND, -80, ENDS[1] + BLEND, FENCE_T + 0.6))
        self.band = band
        # on the map, clear of the tracks' ballast
        clear = self.tracks_near.buffer(TRACK_CLEAR) if self.tracks_near is not None and not self.tracks_near.is_empty \
            else Polygon()
        self.clear = clear
        m = lambda g: to_xy(g).difference(clear).buffer(0)
        self.m_quays = [m(q["st"]) for q in self.quays]
        self.m_walks = [m(w["st"]) for w in self.walks]
        self.m_lanes = m(self.lanes)
        self.m_apron = m(self.apron)
        self.m_all = self.m_apron
        # the bus depot and the ground round it (bus_depot.py; imported here: patch_world.py never loads it)
        import bus_depot
        self.depot = bus_depot.Depot(self, H)
        dep = self.depot
        self.m_depot = bus_depot.to_map(dep.all)
        self.m_depot_hard = bus_depot.to_map(unary_union([dep.hard, dep.walk]))
        self.band = self.band.difference(to_st(self.m_depot).buffer(0.5))
        self.m_band = m(self.band)

    def z(self, s):
        """The lanes' level at s along the axis."""
        return np.interp(s, self.ks, self.kz)

    def axis_line(self, s0: float, s1: float, t: float, lift: float, step: float = 4.0) -> tuple:
        q = np.arange(s0, s1 + 1e-6, step)
        if q[-1] < s1 - 1e-6:
            q = np.r_[q, s1]
        return xy(q, np.full(len(q), t)), self.z(q) + lift


# ---------------------------------------------------------------- repairs and zones

def axis_z(axis, az, x, y) -> np.ndarray:
    """The height at map points (x, y) of the nearest point of the axis polyline (heights az along it)."""
    ax = np.asarray(axis, dtype=np.float64)
    az = np.asarray(az, dtype=np.float64)
    best = np.full(len(x), np.inf)
    out = np.zeros(len(x))
    for a in range(len(ax) - 1):
        ab = ax[a + 1] - ax[a]
        t = np.clip(((x - ax[a, 0]) * ab[0] + (y - ax[a, 1]) * ab[1]) / max(ab @ ab, 1e-12), 0, 1)
        d2 = (x - ax[a, 0] - ab[0] * t) ** 2 + (y - ax[a, 1] - ab[1] * t) ** 2
        m = d2 < best
        best[m] = d2[m]
        out[m] = az[a] + (az[a + 1] - az[a]) * t[m]
    return out


def axis_repair(rp: dict, x, y, z) -> np.ndarray:
    """massy_station.apply_repairs' "axis" method: inside the core the axis' height, in the rest of the ring eased from
    it into the ground over `blend` m from the core."""
    if "grid" in rp:                                # bus_depot.py: a surface on a grid (bilinear), NaN-free
        G = rp["grid"]
        Z = np.asarray(G["z"], dtype=np.float64).reshape(int(G["h"]), int(G["w"]))
        fx = (np.asarray(x, dtype=np.float64) - G["x0"]) / G["cell"]
        fy = (G["y0"] - np.asarray(y, dtype=np.float64)) / G["cell"]
        i = np.clip(np.floor(fx).astype(int), 0, int(G["w"]) - 2)
        j = np.clip(np.floor(fy).astype(int), 0, int(G["h"]) - 2)
        a, b = np.clip(fx - i, 0, 1), np.clip(fy - j, 0, 1)
        target = (Z[j, i] * (1 - a) * (1 - b) + Z[j, i + 1] * a * (1 - b) + Z[j + 1, i] * (1 - a) * b
                  + Z[j + 1, i + 1] * a * b)
    else:
        target = axis_z(rp["axis"], rp["axis_z"], x, y)
    core = unary_union([Polygon(c).buffer(0) for c in rp["core"]]) if rp["core"] else Polygon()
    if core.is_empty:
        return z
    d = shapely.distance(core, shapely.points(x, y))
    blend = float(rp.get("blend", 0.0))
    w = np.where(d <= 1e-9, 1.0, 0.0) if blend <= 0 else np.clip(1.0 - d / blend, 0.0, 1.0)
    w = w * w * (3 - 2 * w)
    return z + (target - z) * w


def repairs(P: Plan) -> list:
    """For massy_station.apply_repairs (method "axis": the height along an axis polyline, at the nearest point of it;
    the core at that height, the rest of the ring eased into the ground over `blend` from the core): the lanes and
    quays on their profile, eased into the ground round them. Only where the ground goes on smoothly: where a zone
    meets the ground at a step (the sidewalk's back, the depot: their walls) the ground there stays
    as it was, so patch_world.py draws the step's far side on it."""
    ax, az = P.axis_line(ENDS[0] - BLEND - 2, ENDS[1] + BLEND + 2, 0.0, 0.0, 4.0)
    core_g = unary_union([P.m_lanes] + P.m_quays)
    core = [ring(p) for p in polys(core_g)]
    whole = unary_union([core_g, P.m_band])
    out = []
    for k, p in enumerate(polys(whole)):
        cores = [c for c in core if Polygon(c).intersects(p)]
        out.append({"id": "repair:bus-station" + ("" if k == 0 else "-%d" % (k + 1)), "method": "axis",
                    "ring": ring(p), "core": cores, "axis": r3(ax), "axis_z": [round(float(v), 3) for v in az],
                    "blend": BLEND, "why": "the Atlantis bus station's lanes on one profile, flat across"})
    return out + [P.depot.repair()]


def _pg(ps) -> list:
    return [[ring(p)] + [r3(np.asarray(h.coords)[:-1]) for h in p.interiors] for p in ps]


def zones(P: Plan) -> list:
    """Zones for patch_world.py, first wins: the quays and the sidewalks (raised), the depot's (bus_depot.py: its
    floor, ramps, car park, sidewalks and green), the lanes (asphalt), at heights along an axis (kind bus_island: exact
    on both sides of a step); the ground eased round the lanes (the repaired ground, material kept). `piece`: the ground
    piece a zone gets ([kind, material]); `absorb`: the pipeline's raised pieces, kerbs, markings and raised collision
    inside go (the bus_island kind always)."""
    out = []
    for q, g in zip(P.quays, P.m_quays):
        hw = (QUAY[1] - QUAY[0]) / 2
        ax, az = P.axis_line(q["s0"] + hw, q["s1"] - hw, (QUAY[0] + QUAY[1]) / 2, BUS_KERB, 4.0)
        for p in polys(g):
            out.append({"kind": "bus_island", "side": None, "source": "osm:w%d" % q["osm"][0], "polygons": [[ring(p)]],
                        "axis": r3(ax), "axis_z": [round(float(v), 3) for v in az], "portals": []})
    for k, (w, g) in enumerate(zip(P.walks, P.m_walks)):
        a = xy(w["axis"][::8, 0], w["axis"][::8, 1])
        az = P.z(w["axis"][::8, 0]) + WALK_KERB
        for p in polys(g):
            out.append({"kind": "bus_island", "piece": ["pedestrian", "concrete"], "side": None,
                        "source": "massy:bus-walk-%d" % (k + 1), "polygons": [[ring(p)]], "axis": r3(a),
                        "axis_z": [round(float(v), 3) for v in az], "portals": []})
    out += P.depot.zones()
    lanes_ax, lanes_az = P.axis_line(ENDS[0] - 8, ENDS[1] + 8, 0.0, 0.0, 4.0)
    ps = polys(P.m_lanes)
    if ps:
        out.append({"kind": "bus_island", "piece": ["road", "asphalt"], "side": None, "source": "massy:bus-station",
                    "polygons": _pg(ps), "axis": r3(lanes_ax), "axis_z": [round(float(v), 3) for v in lanes_az],
                    "portals": []})
    ps = polys(P.m_band)
    if ps:
        out.append({"kind": "regrade", "side": None, "source": "repair:bus-station", "polygons": _pg(ps)})
    return seams(out)


def plan(H: rg.Heights, tracks_xy: list) -> Plan:
    return Plan(H, tracks_xy)


def island_tops(P: Plan) -> list:
    """The quays as (polygon, top) pieces ~10 m long, for the flights landing on them (their top changes along them;
    massy_station.build_flights also turns a flight along the piece's long side: each piece is longer than wide)."""
    out = []
    for q, g in zip(P.quays, P.m_quays):
        cuts = list(np.arange(q["s0"], q["s1"] - 10.0, 10.0)) + [q["s1"]]
        for a, b in zip(cuts[:-1], cuts[1:]):
            piece = g.intersection(to_xy(box(a - 0.01, -20, b + 0.01, 20)))
            if not piece.is_empty:
                out.append((piece, float(P.z((a + b) / 2)) + BUS_KERB))
    return out


# ---------------------------------------------------------------- what the builder draws

def surface_z(P: Plan, s, t):
    """The finished ground's level at (s, t) on the lanes (not the raised quays and sidewalks)."""
    s, t = np.asarray(s, dtype=np.float64), np.asarray(t, dtype=np.float64)
    return P.z(s) + 0.0 * t

class Paint:
    """Road markings as triangles (s, t) of a colour, put on the map with the ground's level (+ LIFT)."""
    LIFT = 0.02

    def __init__(self, P: Plan):
        self.P = P
        self.tris = {"white": [], "yellow": []}

    def quad(self, a, b, c, d, col="white"):
        self.tris[col] += [a, b, c, a, c, d]

    def strip(self, pts, w, col="white"):
        pts = np.asarray(pts, dtype=np.float64)
        for p, q in zip(pts[:-1], pts[1:]):
            e = q - p
            L = np.linalg.norm(e)
            if L < 1e-6:
                continue
            n = np.array([-e[1], e[0]]) / L * w / 2
            self.quad(p - n, q - n, q + n, p + n, col)

    def dashes(self, s0, s1, t, dash, gap, w, col="white"):
        s = s0
        while s < s1 - 0.2:
            self.strip([(s, t), (min(s + dash, s1), t)], w, col)
            s += dash + gap

    def arrow(self, s, t, sign, col="white"):
        """A straight-ahead arrow 5 m long pointing along the axis (`sign` +1 north-east, -1 south-west)."""
        tail, head = s - sign * 2.5, s + sign * 2.5
        neck = head - sign * 1.4
        self.strip([(tail, t), (neck, t)], 0.18, col)
        self.tris[col] += [(neck, t - 0.45), (head, t), (neck, t + 0.45)]

    def zigzag(self, s0, s1, t_kerb, out, col="yellow"):
        """A bus stop's zigzag along a kerb at t_kerb, `out` the side of the lane (+1 or -1)."""
        n = max(int((s1 - s0) / 1.5), 2)
        ss = np.linspace(s0, s1, n + 1)
        ts = [t_kerb + out * (0.3 if k % 2 == 0 else 1.3) for k in range(n + 1)]
        self.strip(np.c_[ss, ts], 0.12, col)
        self.strip([(s0, t_kerb + out * 0.3), (s1, t_kerb + out * 0.3)], 0.10, col)

    def zebra(self, s, t0, t1, width=3.0):
        for t in np.arange(t0 + 0.4, t1 - 0.3, 1.0):
            self.quad((s - width / 2, t), (s + width / 2, t), (s + width / 2, t + 0.5), (s - width / 2, t + 0.5))

    def hatch(self, g, step=1.6, w=0.35):
        """Hatches 45° over polygon g (s, t) and its outline."""
        x0, y0, x1, y1 = g.bounds
        for c in np.arange(x0 - (y1 - y0), x1, step):
            ln = LineString([(c, y0), (c + (y1 - y0), y1)]).intersection(g)
            for part in getattr(ln, "geoms", [ln]):
                if part.geom_type == "LineString" and part.length > 0.3:
                    self.strip(np.asarray(part.coords), w)
        self.strip(np.asarray(g.exterior.coords), 0.15)

    def export(self) -> dict:
        out = {}
        for col, tri in self.tris.items():
            if not tri:
                continue
            a = np.asarray(tri, dtype=np.float64)
            p = xy(a[:, 0], a[:, 1])
            z = surface_z(self.P, a[:, 0], a[:, 1]) + self.LIFT
            out[col] = [round(float(v), 2) for v in np.c_[p, z].ravel()]
        return out


def stop_bays(P: Plan, props: list) -> list:
    """(s0, s1, side) of the stop bays: behind every bus stop pole by a quay's kerb (the buses' way: along the RER
    side north-east, along the Massy side south-west), from 8 m behind it to past the stop's mark, merged where
    they overlap."""
    bays = {+1: [], -1: []}
    for p in props:
        if p["kind"] != "bus_pole":
            continue
        s, t = st([p["x"], p["y"]])
        q = next((q for q in P.quays if q["s0"] - 2 < s < q["s1"] + 2), None)
        if q is None or not (QUAY[0] - 2.5 < t < QUAY[1] + 2.5):
            continue
        side = +1 if t > (QUAY[0] + QUAY[1]) / 2 else -1
        lo, hi = (s - 8.0, s + STOP_AHEAD + 2.0) if side > 0 else (s - STOP_AHEAD - 2.0, s + 8.0)
        lo, hi = max(lo, q["s0"] + 4.5), min(hi, q["s1"] - 4.5)
        if hi - lo > 8.0:
            bays[side].append([lo, hi])
    out = []
    for side, lst in bays.items():
        lst.sort()
        merged = []
        for b in lst:
            if merged and b[0] < merged[-1][1] + 2.0:
                merged[-1][1] = max(merged[-1][1], b[1])
            else:
                merged.append(list(b))
        out += [(a, b, side) for a, b in merged]
    return out


def markings(P: Plan, props: list) -> tuple:
    """(paint by colour, labels): the lanes' lines and arrows, the stop bays, zebras, the hatched nose, the
    hatched nose (the depot's own: bus_depot.py)."""
    pt = Paint(P)
    labels = []
    mid = (QUAY[1] + RER_KERB) / 2
    # the RER side lane: its middle (the quay's half, the passing half) and its edge line
    pt.dashes(-210.0, 48.0, mid, 3.0, 3.5, 0.15)
    pt.dashes(98.0, 214.0, mid, 3.0, 3.5, 0.15)
    pt.strip([(SW_TAPER[0], RER_KERB - 0.3), (ENDS[1] - 4.0, RER_KERB - 0.3)], 0.12)
    pt.strip([(ENDS[0] + 2.0, SW_TAPER[1] - 0.3), (SW_TAPER[0], RER_KERB - 0.3)], 0.12)
    # the Massy side lane's edge along the sidewalk
    for s0, s1 in WALK:
        q = np.arange(s0 + 1.0, s1 - 1.0 + 1e-6, 2.0)
        pt.strip(np.c_[q, P.massy(q) + 0.3], 0.12)
    # arrows
    for s in (-200.0, -150.0, -100.0, -50.0, 30.0, 110.0, 160.0, 205.0):
        pt.arrow(s, (QUAY[1] + mid) / 2 + 0.2, +1)
        pt.arrow(s + 8.0, (mid + RER_KERB) / 2 - 0.2, +1)
    for s in (200.0, 150.0, 100.0, 30.0, -40.0, -110.0, -170.0):
        pt.arrow(s, LANE_MASSY, -1)
    pt.arrow(66.0, (LANE_MASSY + BULB[2]) / 2, -1)
    # stop bays
    for s0, s1, side in stop_bays(P, props):
        t_k = QUAY[1] if side > 0 else QUAY[0]
        pt.zigzag(s0, s1, t_k, side)
        sm = (s0 + s1) / 2
        p = xy(sm, t_k + side * 2.4)
        labels.append({"text": "BUS", "x": round(float(p[0]), 3), "y": round(float(p[1]), 3),
                       "z": round(float(surface_z(P, sm, t_k + side * 2.4)) + Paint.LIFT + 0.005, 3),
                       "heading": round(math.degrees(math.atan2(D[1] * side, D[0] * side)), 1), "color": "yellow",
                       "size": 1.6})
    # zebra crossings over the Massy side lane, from the sidewalk to the quays
    for s in (-190.0, -125.0, -45.0, 25.0, 120.0, 180.0):
        pt.zebra(s, float(P.massy(s)), QUAY[0])
    # Îlot C's south-west nose: a hatched island ahead of it
    hw = (QUAY[1] - QUAY[0]) / 2
    c = QUAYS[0][2]
    tc = (QUAY[0] + QUAY[1]) / 2
    pt.hatch(Polygon([(c + 0.3, QUAY[0] + 0.3), (c - 12.0, tc), (c + 0.3, QUAY[1] - 0.3)])
             .difference(Point(c + hw, tc).buffer(hw + 0.3)))
    return pt.export(), labels


def copings(P: Plan) -> list:
    """The quays' and sidewalks' kerb stones: their outline (the sidewalks': their front) with the top's level."""
    out = []
    for g in P.m_quays:
        for p in polys(g):
            c = rg.resample(np.asarray(p.exterior.coords), 1.0)
            c = np.vstack([c, c[:1]])
            z = P.z(st(c)[:, 0]) + BUS_KERB
            out.append({"pts": [[round(float(a), 3), round(float(b), 3), round(float(zz), 3)]
                                for (a, b), zz in zip(c, z)], "closed": True})
    for w, gm in zip(P.walks, P.m_walks):
        ps = polys(gm)
        if not ps:
            continue
        g = to_st(unary_union(ps)).buffer(0.05)
        q = w["axis"]
        ss = np.arange(q[0, 0] + 0.2, q[-1, 0] - 0.2 + 1e-6, 1.0)
        ts = P.massy(ss)
        keep = np.array([g.contains(Point(a, b + 0.1)) for a, b in zip(ss, ts)])
        k = 0
        while k < len(ss):
            if not keep[k]:
                k += 1
                continue
            j = k
            while j + 1 < len(ss) and keep[j + 1]:
                j += 1
            if j > k:
                p = xy(ss[k:j + 1], ts[k:j + 1])
                z = P.z(ss[k:j + 1]) + WALK_KERB
                out.append({"pts": [[round(float(a), 3), round(float(b), 3), round(float(zz), 3)]
                                    for (a, b), zz in zip(p, z)], "closed": False})
            k = j + 1
    return out


def walls(P: Plan, Hf) -> list:
    """Retaining walls where the ground beside the lanes or the sidewalk stands WALL_STEP higher:
    polylines along the outline (just outside it), the foot (inside level) and the higher ground's level per point."""
    walks = unary_union(P.m_walks)
    area = P.m_all
    hang = P.m_depot_hard.buffer(1.0)               # the depot draws its own walls (bus_depot.py)
    out = []
    for r in [rr for g in polys(area) for rr in [g.exterior] + list(g.interiors)]:   # the bank inside: a hole
        c = rg.resample(np.asarray(r.coords), 1.0)
        n = len(c)
        if n < 3:
            continue
        rows = []
        for k in range(n):
            e = c[(k + 1) % n] - c[k - 1]
            nl = np.array([e[1], -e[0]]) / max(np.linalg.norm(e), 1e-9)
            if area.contains(Point(c[k] + nl * 0.3)):
                nl = -nl
            p = c[k]
            o = p + nl * 0.7
            i = p - nl * 0.4
            s_, t_ = st(i)
            zin = float(surface_z(P, s_, t_)) + (WALK_KERB if walks.contains(Point(i)) else 0.0)
            zout = float(Hf.at(o[0], o[1]))
            ok = zout - zin > WALL_STEP and not hang.contains(Point(p)) and \
                (P.tracks_near is None or P.tracks_near.distance(Point(p)) > TRACK_CLEAR + 0.5)
            rows.append((ok, p, nl, zin, zout))
        k = 0
        while k < n:
            if not rows[k][0]:
                k += 1
                continue
            j = k
            while j + 1 < n and rows[j + 1][0]:
                j += 1
            if j - k >= 2:
                pts = [rows[m][1] + rows[m][2] * 0.15 for m in range(k, j + 1)]
                out.append({"pts": r3(pts), "out": r3([rows[k][2]])[0],
                            "foot": [round(rows[m][3], 3) for m in range(k, j + 1)],
                            "top": [round(rows[m][4] + PARAPET, 3) for m in range(k, j + 1)],
                            "ground": [round(rows[m][4], 3) for m in range(k, j + 1)]})
            k = j + 1
    return out


def lamps(P: Plan, avoid) -> list:
    """Lamps along the quays (their Massy side edge) and the sidewalk, every LAMP_STEP m, not on a flight, lift, pier,
    under the deck or by a prop: [x, y, z of the foot]."""
    out = []
    for q in P.quays:
        for s in np.arange(q["s0"] + 8.0, q["s1"] - 7.0, LAMP_STEP):
            for ds in (0.0, 4.0, -4.0, 8.0):
                p = xy(s + ds, QUAY[0] + 0.7)
                if not avoid.contains(Point(p)):
                    out.append([round(float(p[0]), 3), round(float(p[1]), 3),
                                round(float(P.z(s + ds)) + BUS_KERB, 3)])
                    break
    for w in P.walks:
        q = w["axis"]
        for s in np.arange(q[0, 0] + 6.0, q[-1, 0] - 5.0, LAMP_STEP * 1.25):
            for ds in (0.0, 4.0, -4.0):
                t = float(P.walk_out(s + ds)) + 0.5
                p = xy(s + ds, t)
                if not avoid.contains(Point(p)):
                    out.append([round(float(p[0]), 3), round(float(p[1]), 3),
                                round(float(P.z(s + ds)) + WALK_KERB, 3)])
                    break
    return out


PROP_MARGIN = {"bus_shelter": 1.1, "bus_bench": 0.6, "bench": 0.6, "street_lamp": 0.5, "information": 0.6}


# removed at Thomas's request (jersey barriers)
EXTRA_DROPPED_PROPS = ["prop:3396", "prop:3397", "prop:3398", "prop:3339", "prop:3340", "prop:3341", "prop:3342"]


def move_props(P: Plan, world: dict) -> list:
    """The props on the new lanes and the depot's ground: onto the nearest quay or sidewalk within 5 m (by its kerb),
    else dropped. [{"id", "action" (moved, dropped), "to"}]."""
    from shapely.ops import nearest_points
    dw = bus_depot_walk(P)
    raised = [g for g in P.m_quays + P.m_walks + [dw] if not g.is_empty]
    is_quay = [True] * len(P.m_quays) + [False] * (len(P.m_walks) + 1)
    ground = unary_union([P.m_lanes, P.m_depot])
    out = []
    for p in world["props"]:
        pt = Point(p["x"], p["y"])
        if not ground.contains(pt) or any(g.contains(pt) for g in raised):
            continue
        best = None
        for k, g in enumerate(raised):
            d = g.distance(pt)
            if d < 5.0 and (best is None or d < best[0]):
                best = (d, k)
        if best is None:
            out.append({"id": p["id"], "action": "dropped", "why": "on the bus station's lanes"})
            continue
        g = raised[best[1]]
        if p["id"] == STOP_POLE[0]:             # the 4606's: by its stop's bay
            q = xy(STOP_POLE[1], QUAY[1] - 0.45)
            out.append({"id": p["id"], "action": "moved", "to": [round(float(q[0]), 3), round(float(q[1]), 3)],
                        "why": "by the 4606's stop bay"})
            continue
        inner = g.buffer(-PROP_MARGIN.get(p["kind"], 0.45))
        if inner.is_empty:
            inner = g
        q = nearest_points(inner, pt)[0]
        out.append({"id": p["id"], "action": "moved", "to": [round(q.x, 3), round(q.y, 3)],
                    "why": "onto the quay's kerb" if is_quay[best[1]] else "onto the sidewalk"})
    out = [o for o in out if o["id"] not in EXTRA_DROPPED_PROPS]
    return out + [{"id": i, "action": "dropped", "why": "removed at Thomas's request"} for i in EXTRA_DROPPED_PROPS]


def bus_depot_walk(P: Plan):
    import bus_depot
    return bus_depot.to_map(P.depot.walk)


# removed at Thomas's request
EXTRA_GONE_FENCES = ["fence:133", "fence:134", "fence:135"]


def gone_fences(P: Plan, world: dict) -> list:
    """The map's fences and walls across the new lanes, the depot's ground and the sidewalk (OSM's wall along the
    avenue)."""
    g = unary_union([P.m_lanes, P.m_depot] + P.m_walks).buffer(-0.1)
    gone = [f["id"] for f in world["fences"] if len(f["pts"]) > 1 and LineString(f["pts"]).intersects(g)]
    return gone + [i for i in EXTRA_GONE_FENCES if i not in gone]


# ---------------------------------------------------------------- the buses' paths

def _arc(c, r, a0, a1, step=0.5):
    n = max(int(abs(a1 - a0) * r / step), 2)
    a = np.linspace(a0, a1, n + 1)
    return np.c_[c[0] + r * np.cos(a), c[1] + r * np.sin(a)]


def _line(a, b, step=0.5):
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    n = max(int(np.linalg.norm(b - a) / step), 1)
    f = np.linspace(0, 1, n + 1)[:, None]
    return a + (b - a) * f


def _shift(s0, s1, t0, t1, step=0.5):
    """An S from (s0, t0) to (s1, t1) (a cosine)."""
    s = np.linspace(s0, s1, max(int(abs(s1 - s0) / step), 2) + 1)
    f = (1 - np.cos(np.pi * (s - s0) / (s1 - s0))) / 2
    return np.c_[s, t0 + (t1 - t0) * f]


def _join(*parts):
    out = [np.asarray(parts[0])]
    for p in parts[1:]:
        p = np.asarray(p)
        out.append(p[1:] if np.linalg.norm(p[0] - out[-1][-1]) < 1e-6 else p)
    return np.vstack(out)


def paths(P: Plan) -> dict:
    """The 4606's paths in (s, t), then on the map: out from the gap between Îlots C and B along the RER side lane
    (where the buses that came in lay over), the stop at Îlot B, round the turnaround, along the Massy side lane out to
    the south-west; in along the RER side lane to the terminus at Îlot C's north-east end. With the turn (indicators)
    and the stop, as map points (bus_routes.py measures them). The depot is the bus job's (bus_depot.py: its ways in and
    out, for the tests)."""
    loop = np.array(LOOP)
    stop = STOP_POLE[1] + STOP_AHEAD
    out = _join(_line((OUT_START, LANE_OUT_STOP), (stop + 2.0, LANE_OUT_STOP)),
                _shift(stop + 2.0, loop[0], LANE_OUT_STOP, loop[1] + LOOP_R),
                _arc(loop, LOOP_R, np.pi / 2, -np.pi / 2),
                _shift(loop[0], 47.0, loop[1] - LOOP_R, LANE_MASSY),
                _line((47.0, LANE_MASSY), (ENDS[0], LANE_MASSY)))
    inn = _line((ENDS[0], LANE_IN), (QUAYS[0][3] - 4.0, LANE_IN))
    turns = [{"from": r3([xy(stop + 3.0, LANE_OUT_STOP)])[0], "to": r3([xy(loop[0] - 8.0, loop[1] - LOOP_R)])[0],
              "dir": -1}]
    return {"out": r3(xy(out[:, 0], out[:, 1])), "in": r3(xy(inn[:, 0], inn[:, 1])),
            "stop": {"name": "Gare de Massy - Palaiseau", "pole": STOP_POLE[0],
                     "at": r3([xy(stop, LANE_OUT_STOP)])[0]},
            "turns": turns, "area": ring(to_xy(box(ENDS[0], -60.0, ENDS[1] + 10.0, FENCE_T)))}

def finish(P: Plan, Hf, world: dict, flights: list, lifts_: list, piers_: list, deck) -> dict:
    """rail.json massy `bus_station` (its fence comes from fence())."""
    props = move_props(P, world)
    moved = {p["id"]: p for p in props}
    final_props = []
    for p in world["props"]:
        m = moved.get(p["id"])
        if m is None:
            final_props.append(p)
        elif m["action"] == "moved":
            final_props.append(dict(p, x=m["to"][0], y=m["to"][1]))
    paint, labels = markings(P, final_props)
    dp = P.depot
    dpaint, dlabels = dp.markings()
    for col, a in dpaint.items():
        paint[col] = paint.get(col, []) + a
    labels += dlabels
    near = to_xy(box(ENDS[0] - 10, -60, ENDS[1] + 10, 20))
    avoid = unary_union([LineString(f["pts"]).buffer(f["width"] / 2 + 1.5, cap_style=2) for f in flights]
                        + [Polygon(lf["ring"]).buffer(1.5) for lf in lifts_]
                        + [Point(p[0], p[1]).buffer(1.6) for p in piers_]
                        + [Point(p["x"], p["y"]).buffer(1.8) for p in final_props if near.contains(Point(p["x"], p["y"]))]
                        + ([deck.buffer(1.0)] if deck is not None else []))
    return {"about": "tools/rail/bus_station.py: the Atlantis bus station's lanes, quays, markings and the bus "
                     "depot (bus_depot.py; map coordinates, absolute levels)",
            "frame": {"o": r3([ORIGIN])[0], "d": r3([D])[0]},
            "profile": {"s": [round(float(v), 2) for v in P.ks], "z": [round(float(v), 3) for v in P.kz]},
            "quays": [{"id": "bus_island:" + q["key"], "name": q["name"], "osm": ["w%d" % i for i in q["osm"]],
                       "s": [q["s0"], q["s1"]], "t": list(QUAY), "kerb": BUS_KERB} for q in P.quays],
            "lanes": {"rer": [QUAY[1], RER_KERB], "massy": [MASSY_KERB, QUAY[0]], "bulb": list(BULB),
                      "loop": {"c": r3([xy(*LOOP)])[0], "path_r": LOOP_R, "pave_r": LOOP_PAVE}},
            "markings": paint, "labels": labels, "copings": copings(P) + dp.copings(),
            "walls": walls(P, Hf) + dp.walls(), "lamps": lamps(P, avoid) + dp.lamps(), "props": props,
            "fences_gone": gone_fences(P, world),
            "clear": [ring(p) for p in polys(unary_union([P.m_lanes, P.m_depot] + P.m_walks + P.m_quays))],
            "routes": paths(P), "depot": dp.data(), "depot_fences": dp.fences(),
            "greenery": dp.greenery(world.get("tree_archetypes", {"round": 1}))}


def fence(P: Plan, Hf, gaps, world: dict) -> list:
    """The fence between the RER side lane and the tracks: straight at FENCE_T (FENCE_TRACK m off a track at least),
    open at the gaps (flights, lifts, piers) and buildings. For patch_world.py's world fences."""
    if P.tracks_near is None or P.tracks_near.is_empty:
        return []
    ln = to_xy(LineString([(ENDS[0] - 2.0, FENCE_T), (ENDS[1] + 2.0, FENCE_T)]))
    hole = unary_union(list(gaps) + [P.tracks_near.buffer(FENCE_TRACK)]
                       + [Polygon(b["rings"][0]).buffer(0.3) for b in world["buildings"]
                          if b.get("walls", True) and b["rings"] and Polygon(b["rings"][0]).intersects(ln.buffer(3))])
    rest = ln.difference(hole)
    out = []
    for part in getattr(rest, "geoms", [rest]):
        if part.is_empty or part.geom_type != "LineString" or part.length < 3.0:
            continue
        q = rg.resample(np.asarray(part.coords), 2.5)
        if np.linalg.norm(q[-1] - np.asarray(part.coords)[-1]) > 0.05:
            q = np.vstack([q, np.asarray(part.coords)[-1]])
        out.append({"id": "fence:massy:bus:%d" % (len(out) + 1), "style": "mesh", "h": 2.0, "pts": r3(q),
                    "z": [round(float(Hf.at(x, y)), 3) for x, y in q], "length": round(part.length, 1)})
    return out


def station_box():
    """The bus station's strip on the map: the other fences there give way to fence()."""
    return to_xy(box(ENDS[0] - 4.0, -60.0, ENDS[1] + 4.0, FENCE_T + 1.5))


def merge_fences(P: Plan, Hf, fences: list, gaps, world: dict) -> list:
    """massy_station.rer_fences' runs outside the bus station's strip, and fence() along it, numbered again."""
    strip = station_box()
    runs = []
    for f in fences:
        rest = LineString(f["pts"]).difference(strip)
        for part in getattr(rest, "geoms", [rest]):
            if part.is_empty or part.geom_type != "LineString" or part.length < 3.0:
                continue
            q = np.asarray(part.coords)
            runs.append(dict(f, pts=r3(q), z=[round(float(Hf.at(x, y)), 3) for x, y in q],
                             length=round(part.length, 1)))
    runs += fence(P, Hf, gaps, world)
    for k, f in enumerate(runs):
        f["id"] = "fence:massy:%d" % (k + 1)
    return runs


def summary(P: Plan, out: dict) -> str:
    return ("lanes %.1f m (RER side) and %.1f m (Massy side) on a profile from %.2f to %.2f m, quays %s, turnaround "
            "r %.1f m (asphalt %.1f m), %s, %d marking triangles, %d "
            "walls, %d lamps, props %d moved %d dropped, fences gone %s" % (
                RER_KERB - QUAY[1], QUAY[0] - MASSY_KERB, P.kz[0], P.kz[-1],
                ", ".join("%s %.0f m" % (q["name"], q["s1"] - q["s0"]) for q in P.quays), LOOP_R, LOOP_PAVE,
                P.depot.summary(),
                sum(len(v) // 9 for v in out["markings"].values()), len(out["walls"]), len(out["lamps"]),
                sum(p["action"] == "moved" for p in out["props"]), sum(p["action"] == "dropped" for p in out["props"]),
                ", ".join(out["fences_gone"]) or "none"))
