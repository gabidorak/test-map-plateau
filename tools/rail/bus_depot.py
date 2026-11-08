"""The bus depot by the Atlantis bus station at Massy-Palaiseau (v4, 2026-11-08) and the ground round it, laid out for
bus_station.py (its Plan builds a Depot; its zones, repairs and finish take the depot's). It replaces the brick hangar
of 2026-11-07 and the bus layover the map pipeline had there.

Thomas's plan (validated as "plan v4"): an open depot after Gent's bus station: one large thin flat roof on slender
inclined columns, no walls, over a flat floor; under it the drivers' walkway along the Avenue Carnot side, a passage
lane, three lanes of two 21 m bays lengthwise, the buses facing south-west (the way out); a ramp in at the north-east
from the Massy side lane of the bus station (its traffic runs south-west), widening to the roof's whole width; a ramp
out at the south-west, the roof's width narrowing down to the lane; a straight retaining wall along the lane; a car park
at the avenue's level at the south-west (two rows parallel to the avenue, a 6 m aisle, a dropped kerb from the avenue),
stairs down to the floor; a green 2 m welded-mesh fence round it all, open at the two ramps' feet and the car park's
entrance. Round it: the herringbone bus layover, its islands (OSM w1213444411..17), the diagonal footway (w887999966),
the busway from the avenue to the bus station (w1049745371) and the cycleway beside it (w1430094866) go; a new 3 m
north sidewalk on Avenue Carnot with a straight kerb, continuing the one east of it (w1225249189:left); Nouvelle Voie's
east sidewalk redone at a constant width down to the junction and round its corner into the avenue's; one planted
talus at the south-west between that sidewalk and the car park, from the bus lane to the junction; a planted talus at
the north-east between the ramp in and the avenue, the "Nous recrutons !" panel on it; a hedge and trees along the
avenue.

Frame: (u, v) = (s - S0, t - T0) of the bus station's frame (bus_station.py: s along the quays' axis to the north-east,
t across it towards the tracks): u along the roof to the north-east, v across it towards the bus lane; the roof is
u 0..ROOF[1], v ROOF[2]..ROOF[3]. The plan was drawn on the pipeline's map, where the Massy side lane ran ~6 m nearer
the avenue than the rebuilt bus station's (its kerb t = -9, its sidewalk's back t = -10.4): the parts tied to the lane
(the roof, the ramps, the wall) keep their place against the real sidewalk, the parts tied to the avenue against the
real avenue (its OSM centre line w1053477623 and kerbs), the green between them takes up the difference.

Levels: the floor FLOOR_Z (the plan: ~0.3 m under the avenue's mean level beside it, ~2 m over the bus lane); the
ramps from the lane's profile (bus_station Plan.z) to the floor with rounded vertical curves (VCURVE); the car park
on the avenue sidewalk's back; the sidewalks KERB over the road's edge (the map's LiDAR ground, smoothed along the
kerb), lowered to DROP at crossings and the car park's entrance; the green between them a harmonic surface (each
height the mean of its neighbours: the smoothest that meets every edge) with the hard parts' edges as its boundary,
GRASS_DROP under the floor and the ramps (a kerb), cut along the WING walls where the ground on one side stands far
higher than on the other (the car park over the ramp out, the avenue's level over the floor's corner). Where the green
stands higher than a hard part along an edge left free, a retaining wall (`walls`).
Assumed (no plan gives them): the levels and grades above, the widths, the roof's height and the columns' layout."""
import math

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import bus_station as bst
import railgeo as rg

S0, T0 = -49.78, -38.36         # the depot's frame in the bus station's: u = s - S0, v = t - T0
# the depot
FLOOR_Z = -70.8                 # m, the floor (plan v4)
ROOF = (0.0, 49.5, 5.5, 27.1)   # u0, u1, v0, v1 of the roof (plan v4: 49.5 x 21.6 m)
ROOF_UNDER = 6.0                # m from the floor to the roof's underside
ROOF_THICK = 0.45               # m at its middle; its edge bevelled to ROOF_EDGE over BEVEL
ROOF_EDGE = 0.12
BEVEL = 1.6
FLOOR_SE = 5.0                  # v of the floor's south-east edge (the walkway's)
WALKWAY = (5.0, 6.6)            # v: the drivers' walkway along it
PASSAGE = (6.6, 12.6)           # v: the passage lane (6 m), to go round parked buses
LANES = [(12.6, 17.1), (17.1, 21.6), (21.6, 26.1)]   # v: the three bus lanes
BAYS_U = [(2.5, 23.5), (26.0, 47.0)]                 # u: two 21 m bays per lane
COLUMNS_U = [1.6, 13.0, 24.75, 36.5, 47.9]          # u of the column pairs, along both long sides
COLUMN_V = (6.35, 26.9)         # v of the two rows (the walkway's edge, the margin by the wall)
STAIRS = (-2.2, 0.0, 5.0, 6.6)  # u0, u1, v0, v1: from the car park down to the walkway
TERMINAL = (3.2, 5.75)          # u, v: the bus job's terminal, on the walkway by the stairs, facing north-east
# the lane side
WALL_V = bst.WALK_OUT["c"] - T0     # v of the bus lane's sidewalk back: the retaining wall's face
EXIT_GAP = (-95.0, -75.0)       # s: the sidewalk opened at the ramp out's foot (bus_station.WALK)
ENTRY_GAP = (35.0, 61.0)        # s: and at the ramp in's
EXIT_FOOT = -25.7               # u: the ramp out reaches the lane's level here...
ENTRY_FOOT = 86.0               # ...and the ramp in leaves it here
VCURVE = 3.5                    # m: the ramps' rounded vertical curves
K_CORNER = (-23.2, 20.5)        # u, v: where the car park's wall to the ramp out ends (the ramp's foot 7.5 m wide)
ENTRY_SE = [(ROOF[1], FLOOR_SE), (78.0, 17.8), (93.3, 17.8)]   # the ramp in's south-east edge, to the old station
ENTRY_HOLD = -10.8               # t the ways in hold along the bulb, then (ENTRY_S: u from, to) ease onto the ramp
ENTRY_S = (97.0, 55.0)
ENTRY_KERB = 2.9                # m from the tightest way in to the curved kerb of the sidewalk at the building's foot
ENTRY_TAPER = 8.0               # m over which that kerb leaves the bulb's line
NE_EDGE = 91.1                  # u: the zone's north-east edge (the building site's), south of the old station
# the avenue (OSM w1053477623 centre: v = 0.205 u - 16.91 within 0.2 m from u -19 to 48; the south kerb 2.9 m off)
AV_SLOPE, AV_C = 0.205, -16.91
AV_HALF = 3.0                   # m from the centre line to the new north kerb
AV_EAST = [(71.1, -1.8), (115.7, -2.9)]   # the existing north kerb east of here (w1225249189:sidewalk:left)
AV_BEND = 30.0                  # m: the radius between the two
WALK_W = 3.0                    # m, the new sidewalks
EAST_WALK_W = 2.0               # m, the existing one they join
NV_KERB = 5.5                   # m from Nouvelle Voie's OSM centre (w1078673867) to its east kerb (the map's: 5.4-5.8)
NV_TIP = 21.0                   # v where its east sidewalk starts (the old one's north tip)
CORNER_R = 6.0                  # m: the kerb's radius round the junction's corner
KERB = 0.12                     # m: the map's raised kerbs
DROP = 0.03                     # m: its dropped kerbs
CROSSINGS = [(-34.9, -18.2), (-37.8, -15.3)]   # u, v: the zebra over Nouvelle Voie lands here (OSM w1035451149)
# the car park
PARK_SW = (-21.5, K_CORNER)     # its south-west side: from u on the sidewalk's back up to K_CORNER
PARK_ROWS = (0.3, 5.3, 11.3, 16.3)   # m from the sidewalk's back: row 1, the aisle, row 2
PARK_SPACE = 2.5                # m wide, 5 m deep
PARK_NE = 0.0                   # u: its north-east edge (the stairs' top beside it)
PARK_ENTRY = (-7.5, -2.5)       # u: its entrance from the avenue (a dropped kerb)
PARK_WALK = 2.5                 # m along its north-east edge to the stairs
# the green
GRASS_DROP = 0.12               # m: grass beside the floor and the ramps stands this much lower (a kerb)
BED_RISE = 0.12                 # m: the car park's planted bed over it
FENCE_H = 2.0                   # m (as the RATP's along the tracks)
LAMP_H = 6.0                    # m, the car park's lamp posts


# ---------------------------------------------------------------- frame

def m(u, v) -> np.ndarray:
    """Map point(s) of (u, v)."""
    return bst.xy(np.asarray(u, dtype=np.float64) + S0, np.asarray(v, dtype=np.float64) + T0)


def uv(p) -> np.ndarray:
    return bst.st(p) - np.array([S0, T0])


def to_map(g):
    return bst.to_xy(affinity.translate(g, S0, T0))


def to_uv(g):
    return affinity.translate(bst.to_st(g), -S0, -T0)


def polys(g) -> list:
    return [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05]


def r3(p) -> list:
    return [[round(float(a), 3) for a in q] for q in np.asarray(p)]


def ring(pg) -> list:
    return r3(np.asarray(pg.exterior.coords)[:-1])


def heading(du: float, dv: float) -> float:
    """Map degrees (from east, anticlockwise) of the frame's direction (du, dv)."""
    d = bst.D * du + bst.N * dv
    return math.degrees(math.atan2(d[1], d[0]))


def yaw(du: float, dv: float) -> float:
    """Garage yaw (0 north, clockwise) of the frame's direction (du, dv)."""
    d = bst.D * du + bst.N * dv
    return round(math.degrees(math.atan2(d[0], d[1])) % 360.0, 1)


def ramp_w(x, a: float, b: float, L: float):
    """0 at x <= a, 1 at x >= b, a constant grade between with parabolic vertical curves L long at both ends."""
    x = np.clip(np.asarray(x, dtype=np.float64), a, b)
    g = 1.0 / (b - a - L)
    lo = g * (x - a) ** 2 / (2 * L)
    mid = g * L / 2 + g * (x - a - L)
    hi = 1.0 - g * (b - x) ** 2 / (2 * L)
    return np.where(x < a + L, lo, np.where(x > b - L, hi, mid))


def cos_shift(a, b, n: int = None, step: float = 0.5) -> np.ndarray:
    """An S from point a to point b (u, v) along u: v eased by a half cosine."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    k = max(int(abs(b[0] - a[0]) / step), 2) if n is None else n
    u = np.linspace(a[0], b[0], k + 1)
    f = (1 - np.cos(np.pi * (u - a[0]) / (b[0] - a[0]))) / 2
    return np.c_[u, a[1] + (b[1] - a[1]) * f]


def smooth_profile(s, z, step: float = 6.0, weight: float = 8.0, keep_tol: float = 0.12) -> np.ndarray:
    """A piecewise linear least-squares fit of z along s (knots every `step` m), its grade changes damped, twice
    without the samples more than keep_tol off it (a parked car, a kerb in the LiDAR)."""
    s, z = np.asarray(s, dtype=float), np.asarray(z, dtype=float)
    ks = np.linspace(s[0], s[-1], max(int((s[-1] - s[0]) / step), 1) + 1)
    A = np.zeros((len(s), len(ks)))
    k = np.clip(np.searchsorted(ks, s) - 1, 0, len(ks) - 2)
    f = (s - ks[k]) / (ks[k + 1] - ks[k])
    A[np.arange(len(s)), k] = 1 - f
    A[np.arange(len(s)), k + 1] = f
    D2 = np.zeros((max(len(ks) - 2, 0), len(ks)))
    for i in range(len(ks) - 2):
        D2[i, i:i + 3] = [1.0, -2.0, 1.0]
    keep = np.ones(len(s), dtype=bool)
    zk = None
    for _ in range(3):
        M = np.vstack([A[keep], D2 * weight])
        y = np.concatenate([z[keep], np.zeros(len(D2))])
        zk = np.linalg.lstsq(M, y, rcond=None)[0]
        keep = np.abs(A @ zk - z) < keep_tol
        if keep.sum() < len(ks):
            keep[:] = True
    return A @ zk


def offset_line(pts, d: float) -> np.ndarray:
    """The polyline `pts` (u, v) offset by d to its left (mitred: the inputs are smooth)."""
    p = np.asarray(pts, dtype=float)
    t = np.gradient(p, axis=0)
    t /= np.linalg.norm(t, axis=1)[:, None]
    return p + np.c_[-t[:, 1], t[:, 0]] * d


def chaikin(p, n: int = 3) -> np.ndarray:
    p = np.asarray(p, dtype=float)
    for _ in range(n):
        q = [p[0]]
        for a, b in zip(p[:-1], p[1:]):
            q += [0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b]
        q.append(p[-1])
        p = np.array(q)
    return p


def fillet(l1, l2, r: float, step: float = 0.5):
    """Two lines (point, direction) joined by an arc of radius r: (tangent point on l1, arc points, on l2)."""
    (p1, d1), (p2, d2) = l1, l2
    d1, d2 = np.asarray(d1, float) / np.linalg.norm(d1), np.asarray(d2, float) / np.linalg.norm(d2)
    A = np.c_[d1, -d2]
    t = np.linalg.solve(A, np.asarray(p2, float) - np.asarray(p1, float))
    x = np.asarray(p1, float) + d1 * t[0]                  # the corner
    ang = math.acos(float(np.clip(-d1 @ d2, -1, 1)))      # inside angle
    k = r / math.tan(ang / 2)
    a, b = x - d1 * k, x + d2 * k
    turn = 1.0 if (d1[0] * d2[1] - d1[1] * d2[0]) > 0 else -1.0
    c = a + np.array([-d1[1], d1[0]]) * r * turn
    a0 = math.atan2(a[1] - c[1], a[0] - c[0])
    a1 = math.atan2(b[1] - c[1], b[0] - c[0])
    da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
    n = max(int(abs(da) * r / step), 2)
    arc = np.array([c + r * np.array([math.cos(a0 + da * i / n), math.sin(a0 + da * i / n)]) for i in range(n + 1)])
    return a, arc, b


# ---------------------------------------------------------------- the layout

class Depot:
    """The depot and its surroundings in (u, v), their levels, and on the map."""

    def __init__(self, P, H: rg.Heights):
        self.P = P
        self.H = H
        self.lane_z = lambda u: P.z(np.asarray(u, dtype=float) + S0)
        self.kerb_v = lambda u: P.massy(np.asarray(u, dtype=float) + S0) - T0
        self.back_v = lambda u: P.walk_out(np.asarray(u, dtype=float) + S0) - T0
        self._kerbs()
        self._depot()
        self._park()
        self._green()
        self._grid()

    # -------- the avenue's and Nouvelle Voie's new sidewalks

    def _kerbs(self):
        """The kerb line from Nouvelle Voie's sidewalk's north tip round the junction's corner and along Avenue
        Carnot to the existing sidewalk, its road side's level, the sidewalk's back."""
        import massy_station as mst
        osm = mst.load()
        nv = uv(mst.wpts(osm, 1078673867))                   # Nouvelle Voie, north to south
        nv = chaikin(nv, 3)
        nv_k = offset_line(nv, NV_KERB)                      # its east kerb (left of the way south)
        # Avenue Carnot's straight kerb, then a bend onto the existing one east
        d_av = np.array([1.0, AV_SLOPE]) / math.hypot(1.0, AV_SLOPE)
        p_av = np.array([0.0, AV_C + AV_HALF * math.hypot(1.0, AV_SLOPE)])
        e0, e1 = np.array(AV_EAST[0]), np.array(AV_EAST[1])
        # the corner: the end of Nouvelle Voie's kerb (its last straight leg) onto the avenue's
        k_end = nv_k[-1]
        d_nv = nv_k[-1] - nv_k[-12]
        a, arc, b = fillet((k_end, d_nv), (p_av, d_av), CORNER_R)
        keep = [q for q in nv_k if (q - a) @ d_nv < -0.25 and q[1] < NV_TIP + 1.0]
        tip = np.array(keep[0])
        while tip[1] > NV_TIP and len(keep) > 1:          # from the old sidewalk's north tip
            keep.pop(0)
            tip = np.array(keep[0])
        a2, arc2, b2 = fillet((p_av, d_av), (e0, e1 - e0), AV_BEND)
        line = [*keep, a, *arc[1:-1], b]
        n = max(int(np.linalg.norm(a2 - b) / 2.0), 1)
        line += [b + (a2 - b) * i / n for i in range(1, n)]
        line += [a2, *arc2[1:-1], b2]
        n = max(int(np.linalg.norm(e0 - b2) / 2.0), 1)
        line += [b2 + (e0 - b2) * i / n for i in range(1, n + 1)]
        K = rg.resample(np.array(line), 1.0)
        if np.linalg.norm(K[-1] - e0) > 0.05:
            K = np.vstack([K, e0])
        self.kerb = K                                         # u, v: the sidewalk on its left
        self.kerb_a = a                                       # where the corner's arc starts (Nouvelle Voie side)
        self.kerb_b = b
        # the road's level just off the kerb, smoothed along it (the LiDAR's ground there: cars, kerbs)
        t = np.gradient(K, axis=0)
        t /= np.linalg.norm(t, axis=1)[:, None]
        nl = np.c_[-t[:, 1], t[:, 0]]
        road = K - nl * 0.6
        mp = m(road[:, 0], road[:, 1])
        z = np.asarray(self.H.at(mp[:, 0], mp[:, 1]), dtype=float)
        sk = rg.cumlen(K)
        z = smooth_profile(sk, z)
        # where it meets the existing kerb east: that sidewalk's own level (its kerb over the map's road there)
        h = np.full(len(K), KERB)
        for c in CROSSINGS:
            d = np.linalg.norm(K - np.array(c), axis=1)
            h = np.minimum(h, np.interp(d, [1.5, 2.5], [DROP, KERB]))
        # the car park's entrance: a dropped kerb the width of the entrance, eased over 1 m each side
        back0 = offset_line(K, WALK_W)
        pu = K[:, 0]
        on_av = sk > rg.cumlen(K)[np.argmin(np.linalg.norm(K - b, axis=1))]
        ent = (pu > PARK_ENTRY[0] - 1.0) & (pu < PARK_ENTRY[1] + 1.0) & on_av
        w = np.clip(np.minimum(pu - (PARK_ENTRY[0] - 1.0), (PARK_ENTRY[1] + 1.0) - pu), 0, 1)
        h = np.where(ent, KERB + (DROP - KERB) * w, h)
        self.kerb_road = z
        self.kerb_z = z + h
        self.kerb_s = sk
        # the sidewalk: WALK_W wide, narrowing to the existing one's EAST_WALK_W over its last 10 m
        wid = np.full(len(K), WALK_W)
        wid = np.where(pu > AV_EAST[0][0] - 10.0, WALK_W + (EAST_WALK_W - WALK_W) *
                       np.clip((pu - (AV_EAST[0][0] - 10.0)) / 10.0, 0, 1), wid)
        wid[on_av == False] = WALK_W  # noqa: E712
        back = K + nl * wid[:, None]
        self.walk_back = back
        self.walk = Polygon(np.r_[K, back[::-1]]).buffer(0)
        self.walk_on_av = on_av

    def av_back_v(self, u):
        """v of the avenue sidewalk's back at u (where it runs along the avenue)."""
        k = self.walk_on_av
        return np.interp(u, self.walk_back[k, 0], self.walk_back[k, 1])

    def walk_z(self, u, v):
        """The sidewalk's level at (u, v): its kerb's at the nearest point."""
        p = np.c_[np.atleast_1d(u), np.atleast_1d(v)]
        return bst.axis_z(self.kerb, self.kerb_z, p[:, 0], p[:, 1])

    # -------- the depot: floor, ramps

    def _depot(self):
        P = self.P
        self.floor = box(ROOF[0], FLOOR_SE, ROOF[1], WALL_V)
        g0, g1 = EXIT_GAP[0] - S0, EXIT_GAP[1] - S0
        uk = np.linspace(g0, g1, 12)
        kerb_out = np.c_[uk, self.kerb_v(uk)]
        self.exit = Polygon([(ROOF[0], WALKWAY[1]), (ROOF[0], WALL_V), (g1, WALL_V), *kerb_out[::-1],
                             (g0, WALL_V), K_CORNER, (STAIRS[0], WALKWAY[1])]).buffer(0)
        e0, e1 = ENTRY_GAP[0] - S0, ENTRY_GAP[1] - S0
        uk = np.linspace(e0, e1, 30)
        kerb_in = np.c_[uk, self.kerb_v(uk)]
        bld = [(93.2, 24.1), (106.5, 24.2), (e1, 24.3)]
        self.entry = Polygon([*ENTRY_SE, *bld, *kerb_in[::-1], (e0, WALL_V), (ROOF[1], WALL_V)]).buffer(0)
        self.stairs = box(STAIRS[0], STAIRS[2], STAIRS[1], STAIRS[3])
        self._entry_walk()
        self.entry = self.entry.difference(self.ne_walk).buffer(0)
        self.entry = max(polys(self.entry), key=lambda q: q.area)
        self.hard_depot = unary_union([self.floor, self.exit, self.entry])
        # profiles along u
        self.exit_u = (EXIT_FOOT, ROOF[0])
        self.entry_u = (ROOF[1], ENTRY_FOOT)

    def _entry_walk(self):
        """The sidewalk along the old station building's foot, from the bulb's sidewalk (bus_station.WALK) round a
        curved kerb into the ramp in, down to the north-east talus: the kerb ENTRY_KERB m inside the way in of the
        tightest bus (the one to the passage lane: an 18 m articulated bus's rear cuts in ~1.2 m on that curve)."""
        hold = ENTRY_HOLD - T0
        vc = (PASSAGE[0] + PASSAGE[1]) / 2
        u_a, u_b = ENTRY_S[0], ENTRY_S[1]
        bulb_u = ENTRY_GAP[1] - S0
        bulb_v = float(self.kerb_v(bulb_u + 0.5))
        us = np.arange(bulb_u, ENTRY_SE[1][0] - 2.0, -0.5)
        f = np.clip((u_a - us) / (u_a - u_b), 0, 1)
        path = hold + (vc - hold) * (1 - np.cos(np.pi * f)) / 2
        k = path - ENTRY_KERB
        ease = np.clip((bulb_u - us) / ENTRY_TAPER, 0, 1)
        ease = ease * ease * (3 - 2 * ease)
        k = bulb_v + (k - bulb_v) * ease                 # from the bulb's kerb, eased onto the curve
        keep = k > ENTRY_SE[1][1]
        last = int(np.argmin(keep)) if not keep.all() else len(k) - 1
        pts = np.c_[us[:last + 1], k[:last + 1]]
        pts[-1] = (np.interp(ENTRY_SE[1][1], k[last::-1][:2], us[last::-1][:2]) if last > 0 else us[last], ENTRY_SE[1][1])
        self.ne_kerb = pts
        self.ne_walk = Polygon([*pts, ENTRY_SE[2], (93.2, 24.1), (106.5, 24.2), (bulb_u, 24.3)]).buffer(0)
        self.ne_walk_z = self.ramp_z(pts[:, 0]) + bst.WALK_KERB

    def ramp_z(self, u):
        """The floor and the ramps' level at u (flat across)."""
        u = np.asarray(u, dtype=float)
        lz = self.lane_z(u)
        w_out = ramp_w(u, EXIT_FOOT, ROOF[0], VCURVE)
        w_in = 1.0 - ramp_w(u, ROOF[1], ENTRY_FOOT, VCURVE)
        w = np.where(u < (ROOF[0] + ROOF[1]) / 2, w_out, w_in)
        return lz + (FLOOR_Z - lz) * w

    # -------- the car park

    def _park(self):
        k = self.walk_on_av
        bu, bv = self.walk_back[k, 0], self.walk_back[k, 1]
        d = np.array([1.0, AV_SLOPE]) / math.hypot(1.0, AV_SLOPE)
        nrm = np.array([-d[1], d[0]])
        self.park_d, self.park_n = d, nrm
        b_sw = np.array([PARK_SW[0], float(self.av_back_v(PARK_SW[0]))])
        b_ne = np.array([PARK_NE, float(self.av_back_v(PARK_NE))])
        self.park_line = (b_sw, b_ne)
        back_pts = [(a, b) for a, b in zip(bu, bv) if PARK_SW[0] < a < PARK_NE]
        # all of it: from the sidewalk's back to the wall to the ramp out, its south-west side up to K_CORNER
        self.park_all = Polygon([b_sw, *back_pts, b_ne, (PARK_NE, STAIRS[2]), (STAIRS[0], STAIRS[2]),
                                 (STAIRS[0], WALKWAY[1]), K_CORNER]).buffer(0)
        # its asphalt: the rows and the aisle; behind the rows, up to the wall, a planted bed
        rear = PARK_ROWS[3] + 0.3
        band = Polygon([b_sw - d * 30 - nrm * 5, b_ne + d * 30 - nrm * 5, b_ne + d * 30 + nrm * rear,
                        b_sw - d * 30 + nrm * rear])
        self.park = unary_union(polys(self.park_all.intersection(band)))
        self.bed = self.park_all.difference(self.park).difference(self.stairs.buffer(0.01))
        self.bed = unary_union([p for p in polys(self.bed) if p.area > 2.0])
        # the spaces, 2.5 m along the rows from the walk to the stairs, none across the entrance
        self.spaces = []
        for row, (a, b) in enumerate([(PARK_ROWS[0], PARK_ROWS[1]), (PARK_ROWS[2], PARK_ROWS[3])]):
            x = PARK_NE - PARK_WALK
            while True:
                x0 = x - PARK_SPACE
                c0 = b_ne + d * ((x0 - b_ne[0]) / d[0])
                c1 = b_ne + d * ((x - b_ne[0]) / d[0])
                q = Polygon([c0 + nrm * a, c1 + nrm * a, c1 + nrm * b, c0 + nrm * b])
                if not self.park.buffer(0.05).contains(q):
                    break
                if not (row == 0 and x0 < PARK_ENTRY[1] and x > PARK_ENTRY[0]):
                    self.spaces.append(q)
                x = x0
        self.park_z = lambda u, v: self.walk_z(*self._on_back(u, v))

    def _on_back(self, u, v):
        """The point of the car park's sidewalk back line nearest (u, v)."""
        a, b = self.park_line
        p = np.c_[np.atleast_1d(u), np.atleast_1d(v)]
        e = b - a
        t = np.clip(((p - a) @ e) / (e @ e), 0, 1)
        q = a + t[:, None] * e - self.park_n * 0.05
        return q[:, 0], q[:, 1]

    # -------- the green and the zone's outline

    def _green(self):
        P = self.P
        av = self.walk
        # the fenced zone: from the avenue sidewalk's back to the lane's wall, from the car park's south-west side to
        # the north-east edge (and the old station's west face)
        k = self.walk_on_av
        bu, bv = self.walk_back[k, 0], self.walk_back[k, 1]
        sel = (bu > PARK_SW[0]) & (bu < NE_EDGE)
        back = list(zip(bu[sel], bv[sel]))
        b_sw = tuple(self.park_line[0])
        ne0 = (NE_EDGE, float(self.av_back_v(NE_EDGE)))
        self.zone = Polygon([b_sw, *back, ne0, (NE_EDGE, 12.0), (92.5, 12.0), (92.6, 13.5), (93.5, 13.5), (93.2, 24.1),
                             *list(self.entry.exterior.coords), ]).buffer(0)
        inner = Polygon([b_sw, *back, ne0, (NE_EDGE, 12.0), (92.5, 12.0), (92.6, 13.5), (93.5, 13.5), (93.3, 17.8),
                         *ENTRY_SE[::-1], (ROOF[0], FLOOR_SE), (PARK_NE, FLOOR_SE), (PARK_NE, STAIRS[2])]).buffer(0)
        self.green_se = inner.difference(self.park_all).difference(self.hard_depot).difference(self.stairs)
        self.green_se = unary_union([p for p in polys(self.green_se) if p.area > 1.0])
        # the south-west talus: between Nouvelle Voie's sidewalk, the avenue's, the car park, the ramp out's foot and
        # the bus lane's sidewalk (the old busway, cycleway, sidewalk loop and lawns there)
        g0 = EXIT_GAP[0] - S0
        top = [(u, float(self.back_v(u))) for u in np.linspace(-50.1, g0, 6)]
        nvb = self.walk_back[~k]
        nvb = nvb[nvb[:, 1] <= NV_TIP + 0.01]
        corner_b = self.walk_back[k][0]
        region = Polygon([*top[::-1], (-50.1, float(nvb[0][1])), *nvb, *[q for q in self.walk_back[k] if q[0] < b_sw[0]],
                          b_sw, K_CORNER, (g0, WALL_V)]).buffer(0)
        self.talus = region.difference(av).difference(self.park_all).difference(self.exit)
        self.talus = max(polys(self.talus), key=lambda p: p.area)
        self.green = unary_union([self.green_se, self.talus, self.bed])
        self.hard = unary_union([self.hard_depot, self.park, self.stairs, self.ne_walk])
        self.all = unary_union([self.hard, self.green, self.walk])

    # ---------------------------------------------------------------- levels

    def hard_z(self, u, v):
        """The designed level of the hard parts at (u, v) (NaN elsewhere): the floor, ramps, stairs' foot, car park,
        sidewalks; and the bus station's own lanes and sidewalk (bus_station.py)."""
        u, v = np.atleast_1d(np.asarray(u, float)), np.atleast_1d(np.asarray(v, float))
        out = np.full(len(u), np.nan)
        def inside(g):
            return shapely.contains_xy(g, u, v)
        st_walk = unary_union([to_uv(w) for w in self.P.m_walks])
        st_lane = to_uv(self.P.m_lanes)
        sz = self.lane_z(u)
        out = np.where(inside(st_lane), sz, out)
        out = np.where(inside(st_walk), sz + bst.WALK_KERB, out)
        out = np.where(inside(self.walk), self.walk_z(u, v), out)
        out = np.where(inside(self.ne_walk), bst.axis_z(self.ne_kerb, self.ne_walk_z, u, v), out)
        out = np.where(inside(self.park), self.park_z(u, v), out)
        out = np.where(inside(self.hard_depot) | inside(self.stairs), self.ramp_z(u), out)
        return out

    def _grid(self):
        """The green's harmonic surface on a 1 m grid over the whole area (map axes), with the hard parts' levels."""
        from scipy.sparse import coo_matrix
        from scipy.sparse.linalg import spsolve
        area = to_map(self.all.buffer(4.0))
        x0, y0, x1, y1 = area.bounds
        c = 1.0
        X, Y = np.meshgrid(np.arange(math.floor(x0), math.ceil(x1) + c, c), np.arange(math.ceil(y1), math.floor(y0) - c, -c))
        q = uv(np.c_[X.ravel(), Y.ravel()])
        u, v = q[:, 0], q[:, 1]
        soft = shapely.contains_xy(self.green, u, v)
        hz = self.hard_z(u, v)
        # beside the floor, the ramps and the stairs the grass stands a kerb lower
        near_depot = shapely.contains_xy(unary_union([self.hard_depot, self.stairs]), u, v)
        fixed = np.where(near_depot, hz - GRASS_DROP, hz)
        base = np.asarray(self.H.at(X.ravel(), Y.ravel()), dtype=float)
        fixed = np.where(np.isnan(fixed) & ~soft, base, fixed)
        # cuts: the grass meets these edges at a wall (its level free there)
        cuts = self.cuts()
        # along the walls under the green, the green at the wall's straight top line (wall_tops)
        for (a, b, za, zb) in self.wall_tops():
            e = b - a
            L2 = e @ e
            t = np.clip(((u - a[0]) * e[0] + (v - a[1]) * e[1]) / L2, 0, 1)
            d = np.hypot(u - (a[0] + e[0] * t), v - (a[1] + e[1] * t))
            on = soft & (d < 1.1)
            fixed = np.where(on, za + (zb - za) * t, fixed)
            soft = soft & ~on
        h, w = X.shape
        idx = -np.ones(len(u), dtype=int)
        idx[soft] = np.arange(soft.sum())
        rows, cols, vals = [], [], []
        rhs = np.zeros(soft.sum())
        diag = np.zeros(soft.sum())
        def cut_between(a, b):
            ok = np.zeros(len(a), dtype=bool)
            for (pa, pb) in cuts:
                e = pb - pa
                L2 = e @ e
                for p_, q_ in ((a, b),):
                    pass
                da = (u[a] - pa[0]) * e[1] - (v[a] - pa[1]) * e[0]
                db = (u[b] - pa[0]) * e[1] - (v[b] - pa[1]) * e[0]
                ta = ((u[a] - pa[0]) * e[0] + (v[a] - pa[1]) * e[1]) / L2
                tb = ((u[b] - pa[0]) * e[0] + (v[b] - pa[1]) * e[1]) / L2
                ok |= (np.sign(da) != np.sign(db)) & (np.maximum(ta, tb) > 0) & (np.minimum(ta, tb) < 1)
            return ok
        sidx = np.where(soft)[0]
        for di, dj in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            j, i = np.divmod(sidx, w)
            jj, ii = j + di, i + dj
            valid = (jj >= 0) & (jj < h) & (ii >= 0) & (ii < w)
            a = sidx[valid]
            b = jj[valid] * w + ii[valid]
            keep = ~cut_between(a, b)
            a, b = a[keep], b[keep]
            ka = idx[a]
            diag[ka] += 1.0
            sb = soft[b]
            rows += list(ka[sb]); cols += list(idx[b[sb]]); vals += [-1.0] * int(sb.sum())
            fb = ~sb & ~np.isnan(fixed[b])
            np.add.at(rhs, ka[fb], fixed[b[fb]])
            nb = ~sb & np.isnan(fixed[b])
            diag[ka[nb]] -= 1.0
        diag = np.maximum(diag, 1e-6)
        n = soft.sum()
        A = coo_matrix((np.r_[diag, vals], (np.r_[np.arange(n), rows], np.r_[np.arange(n), cols])), shape=(n, n)).tocsr()
        sol = spsolve(A, rhs)
        Z = fixed.copy()
        Z[soft] = sol
        Z = np.where(np.isnan(Z), base, Z)
        self.grid = {"x0": float(X[0, 0]), "y0": float(Y[0, 0]), "cell": c, "w": int(w), "h": int(h),
                     "z": Z.reshape(h, w)}
        self.grid_soft = soft.reshape(h, w)

    def wall_tops(self) -> list:
        """(u, v) segments of the walls the green stands over, with the green's (straight) level at both ends: the car
        park's bed over the ramp out (the car park's level), the talus over the ramp out's foot and the bus lane's
        sidewalk beside it (from the car park's level down to the old busway's end at Nouvelle Voie's top)."""
        g0 = EXIT_GAP[0] - S0
        k = np.array(K_CORNER, float)
        z_k = float(self.park_z(k[0] + 0.3, k[1] - 0.3)[0])
        z_st = float(self.park_z(STAIRS[0] - 0.3, WALKWAY[1] + 0.3)[0])
        stub = m(-51.5, 24.5)
        z_nv = float(self.H.at(stub[0], stub[1]))
        z_g0 = z_nv + (z_k - z_nv) * 0.35
        return [(np.array([STAIRS[0], WALKWAY[1]]), k, z_st, z_k), (k, np.array([g0, WALL_V]), z_k, z_g0),
                (np.array([g0, WALL_V]), np.array([-50.1, WALL_V]), z_g0, z_nv)]

    def cuts(self) -> list:
        """(u, v) segments the green meets at a wall: the ramp out's south-west edge (its foot dug into the slope),
        the bus lane's sidewalk back above the talus, the car park's bed over the ramp out, the floor's corner by the
        stairs, the old busway's end at Nouvelle Voie's top."""
        g0 = EXIT_GAP[0] - S0
        segs = [(K_CORNER, (g0, WALL_V)), ((-50.1, WALL_V), (g0, WALL_V)), ((STAIRS[0], WALKWAY[1]), K_CORNER),
                ((ROOF[0], FLOOR_SE), (12.0, FLOOR_SE)), ((-50.1, WALL_V), (-50.1, NV_TIP))]
        return [(np.array(a, float), np.array(b, float)) for a, b in segs]

    def surf(self, u, v):
        """The finished ground's level at (u, v): the hard parts', else the green's."""
        u, v = np.atleast_1d(np.asarray(u, float)), np.atleast_1d(np.asarray(v, float))
        hz = self.hard_z(u, v)
        p = m(u, v)
        G = self.grid
        fx = (p[:, 0] - G["x0"]) / G["cell"]
        fy = (G["y0"] - p[:, 1]) / G["cell"]
        i = np.clip(np.floor(fx).astype(int), 0, G["w"] - 2)
        j = np.clip(np.floor(fy).astype(int), 0, G["h"] - 2)
        a, b = fx - i, fy - j
        Z = G["z"]
        gz = (Z[j, i] * (1 - a) * (1 - b) + Z[j, i + 1] * a * (1 - b) + Z[j + 1, i] * (1 - a) * b + Z[j + 1, i + 1] * a * b)
        return np.where(np.isnan(hz), gz, hz)

    # ---------------------------------------------------------------- for patch_world.py

    def _axis_u(self, u0: float, u1: float, v: float, zf) -> tuple:
        us = np.arange(u0, u1 + 1e-6, 1.0)
        return r3(m(us, np.full(len(us), v))), [round(float(z), 3) for z in zf(us, np.full(len(us), v))]

    def zones(self) -> list:
        """Zones for patch_world.py (bus_station.zones puts them after its quays and sidewalks): the floor (concrete),
        the ramps (asphalt; flat across, their level along u), the stairs' foot, the car park (asphalt, the sidewalk
        back's level along it), the sidewalks (their kerb's level), the green (grass on the repaired ground: repair())."""
        out = []
        ramp = lambda u, v: self.ramp_z(u)
        g0 = EXIT_GAP[0] - S0 - 6.0
        e1 = ENTRY_GAP[1] - S0 + 6.0
        for g, piece, src, ax in [
                (self.floor, ["parking", "concrete"], "massy:bus-depot", self._axis_u(-1.0, ROOF[1] + 1.0, 16.0, ramp)),
                (self.stairs, ["pedestrian", "concrete"], "massy:bus-depot-stairs", self._axis_u(-4.0, 2.0, 5.8, ramp)),
                (self.exit, ["road", "asphalt"], "massy:bus-depot-out", self._axis_u(g0, 1.0, 16.0, ramp)),
                (self.entry, ["road", "asphalt"], "massy:bus-depot-in", self._axis_u(ROOF[1] - 1.0, e1, 16.0, ramp))]:
            out.append({"kind": "bus_island", "piece": piece, "side": None, "source": src,
                        "polygons": [[ring(q)] for q in polys(to_map(g))], "axis": ax[0], "axis_z": ax[1],
                        "portals": []})
        a, b = self.park_line
        n = int(np.linalg.norm(b - a) / 1.0) + 1
        pts = np.array([a + (b - a) * i / n for i in range(n + 1)]) - self.park_n * 0.05
        pz = self.walk_z(pts[:, 0], pts[:, 1])
        out.append({"kind": "bus_island", "piece": ["parking", "asphalt"], "side": None,
                    "source": "massy:bus-depot-park", "polygons": [[ring(q)] for q in polys(to_map(self.park))],
                    "axis": r3(m(pts[:, 0], pts[:, 1])), "axis_z": [round(float(z), 3) for z in pz], "portals": []})
        out.append({"kind": "bus_island", "piece": ["sidewalk", "concrete"], "side": None,
                    "source": "massy:bus-depot-walk", "polygons": [[ring(q)] for q in polys(to_map(self.walk))],
                    "axis": r3(m(self.kerb[:, 0], self.kerb[:, 1])),
                    "axis_z": [round(float(z), 3) for z in self.kerb_z], "portals": []})
        out.append({"kind": "bus_island", "piece": ["pedestrian", "concrete"], "side": None,
                    "source": "massy:bus-depot-walk-ne", "polygons": [[ring(q)] for q in polys(to_map(self.ne_walk))],
                    "axis": r3(m(self.ne_kerb[:, 0], self.ne_kerb[:, 1])),
                    "axis_z": [round(float(z), 3) for z in self.ne_walk_z], "portals": []})
        for g, src in [(self.talus, "massy:bus-depot-talus"), (self.green_se, "massy:bus-depot-green"),
                       (self.bed, "massy:bus-depot-bed")]:
            ps = polys(to_map(g))
            if ps:
                out.append({"kind": "regrade", "piece": ["landcover", "grass"], "absorb": True, "side": None,
                            "source": src, "polygons": [[ring(q)] + [r3(np.asarray(h.coords)[:-1]) for h in q.interiors]
                                                        for q in ps]})
        return out

    def repair(self) -> dict:
        """massy_station.apply_repairs' "axis" method with a grid (bus_station.axis_repair): the green's surface and,
        under the hard parts, their levels (the 2 m nodes a grass cell's height comes from), over the whole area."""
        G = self.grid
        area = max(polys(to_map(self.all.buffer(3.0))), key=lambda q: q.area)
        c = area.centroid.coords[0]
        return {"id": "repair:bus-depot", "method": "axis", "ring": ring(area), "core": [ring(area)],
                "axis": r3([c, c]), "axis_z": [FLOOR_Z, FLOOR_Z], "blend": 0.0,
                "grid": {"x0": round(G["x0"], 3), "y0": round(G["y0"], 3), "cell": G["cell"], "w": G["w"],
                         "h": G["h"], "z": [round(float(a), 2) for a in G["z"].ravel()]},
                "why": "the bus depot's green (a harmonic surface between the hard parts) and its levels"}

    # ---------------------------------------------------------------- for the builder

    def walls(self) -> list:
        """Retaining walls (bus_station.walls' format): along the bus lane (its sidewalk's level at the foot, the floor
        and ramps behind; a coping, the fence on it), between the ramp out and the car park (a parapet), along the ramp
        out's foot under the talus and the floor's corner by the stairs (where the green stands higher)."""
        out = []

        def run(a, b, low, high, parapet, step=1.0, min_h=0.06):
            a, b = np.asarray(a, float), np.asarray(b, float)
            e = (b - a) / np.linalg.norm(b - a)
            nl = np.array([-e[1], e[0]])
            k = max(int(np.linalg.norm(b - a) / step), 1)
            q = np.array([a + (b - a) * i / k for i in range(k + 1)])
            mid = q[len(q) // 2]
            if high(mid + nl * 0.7) < high(mid - nl * 0.7):
                nl = -nl
            lo = np.array([low(p - nl * 0.4) for p in q])
            hi = np.array([high(p + nl * 0.7) for p in q])
            okm = hi - lo > min_h
            i = 0
            while i < len(q):
                if not okm[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < len(q) and okm[j + 1]:
                    j += 1
                if j > i:
                    on = bst.D * nl[0] + bst.N * nl[1]
                    out.append({"pts": r3(m(q[i:j + 1, 0], q[i:j + 1, 1])), "out": r3([on])[0],
                                "foot": [round(float(x), 3) for x in lo[i:j + 1]],
                                "top": [round(float(x) + parapet, 3) for x in hi[i:j + 1]],
                                "ground": [round(float(x), 3) for x in hi[i:j + 1]]})
                i = j + 1
        f = lambda p: float(self.surf(p[0], p[1])[0])
        side = lambda p: float(self.lane_z(p[0])) + bst.WALK_KERB
        run((EXIT_GAP[1] - S0, WALL_V - 0.01), (ENTRY_GAP[0] - S0, WALL_V - 0.01), side, f, 0.12)
        run((ROOF[0], WALKWAY[1]), (STAIRS[0], WALKWAY[1]), f, f, 1.0)
        tops = self.wall_tops()

        def top_of(k):
            a, b, za, zb = tops[k]
            e = b - a
            return lambda p: za + (zb - za) * float(np.clip(((np.asarray(p) - a) @ e) / (e @ e), 0, 1))
        run((STAIRS[0], WALKWAY[1]), K_CORNER, f, top_of(0), 1.0)
        run(K_CORNER, (EXIT_GAP[0] - S0, WALL_V), f, top_of(1), 0.15, min_h=0.3)
        run((ROOF[0], FLOOR_SE), (12.0, FLOOR_SE), f, f, 0.12, min_h=0.3)
        return out

    def copings(self) -> list:
        """Kerb stones: the new sidewalks' and the floor's and ramp in's south-east edges over the grass (`left`: the
        raised side is on the left of the line)."""
        out = []

        def line(pts, z, left):
            q = m(pts[:, 0], pts[:, 1])
            out.append({"pts": [[round(float(a), 3), round(float(b), 3), round(float(c), 3)] for (a, b), c in zip(q, z)],
                        "closed": False, "left": left})
        line(self.kerb, self.kerb_z, True)
        line(self.ne_kerb, self.ne_walk_z, True)
        e = rg.resample(np.array([(ROOF[0], FLOOR_SE)] + ENTRY_SE), 1.0)
        line(e, self.ramp_z(e[:, 0]), True)
        return out

    def fences(self) -> list:
        """The green 2 m welded-mesh fence round the zone, open at the ramps' feet and the car park's entrance:
        polylines on the map with the ground's (or the wall's top) level per point."""
        runs = []

        def add(pts_uv, z=None):
            pts_uv = np.asarray(pts_uv, float)
            p = rg.resample(pts_uv, 2.5)
            if np.linalg.norm(p[-1] - pts_uv[-1]) > 0.05:
                p = np.vstack([p, pts_uv[-1]])
            zz = self.surf(p[:, 0], p[:, 1]) if z is None else z(p)
            runs.append({"pts": r3(m(p[:, 0], p[:, 1])), "z": [round(float(a), 3) for a in zz]})
        add([(EXIT_GAP[1] - S0, WALL_V - 0.2), (ENTRY_GAP[0] - S0, WALL_V - 0.2)], lambda p: self.ramp_z(p[:, 0]) + 0.12)
        k = self.walk_on_av
        bk = self.walk_back[k]
        nl = np.c_[-np.gradient(bk[:, 1]), np.gradient(bk[:, 0])]
        nl /= np.linalg.norm(nl, axis=1)[:, None]
        inner = bk + nl * 0.2
        for lo, hi in [(PARK_SW[0] + 0.2, PARK_ENTRY[0]), (PARK_ENTRY[1], NE_EDGE - 0.2)]:
            sel = (inner[:, 0] >= lo) & (inner[:, 0] <= hi)
            if sel.sum() > 1:
                add(inner[sel])
        add([(NE_EDGE - 0.2, float(self.av_back_v(NE_EDGE)) + 0.2), (NE_EDGE - 0.2, 12.2), (92.4, 12.2)])
        b_sw = self.park_line[0]
        add([(b_sw[0] + 0.15, b_sw[1] + 0.3), (K_CORNER[0] + 0.15, K_CORNER[1] - 0.2)],
            lambda p: self.park_z(p[:, 0], p[:, 1]))
        g0 = EXIT_GAP[0] - S0
        e = np.array([g0, WALL_V]) - np.array(K_CORNER)
        nl2 = np.array([e[1], -e[0]]) / np.linalg.norm(e)           # towards the talus
        add([np.array(K_CORNER) + nl2 * 0.3, np.array([g0, WALL_V]) + nl2 * 0.3])
        for k_, r in enumerate(runs):
            r["id"] = "fence:massy:depot:%d" % (k_ + 1)
        return runs

    def markings(self) -> tuple:
        """(paint triangles by colour on the map with their level, labels): the lanes, the bays' ends and numbers,
        "BUS", the arrows, the walkway's hatch and edge, the car park's spaces."""
        tris = {"white": [], "yellow": []}
        labels = []

        def quad(a, b, c, d, col="white"):
            tris[col] += [a, b, c, a, c, d]

        def strip(pts, w, col="white"):
            pts = np.asarray(pts, float)
            for p, q in zip(pts[:-1], pts[1:]):
                e = q - p
                L = np.linalg.norm(e)
                if L < 1e-6:
                    continue
                n = np.array([-e[1], e[0]]) / L * w / 2
                quad(p - n, q - n, q + n, p + n, col)

        def arrow(u, v, sign, col="white"):
            tail, head = u - sign * 2.5, u + sign * 2.5
            neck = head - sign * 1.4
            strip([(tail, v), (neck, v)], 0.18, col)
            tris[col] += [(neck, v - 0.45), (head, v), (neck, v + 0.45)]

        def label(text, u, v, du, dv, size, col="white"):
            p = m(u, v)
            labels.append({"text": text, "x": round(float(p[0]), 3), "y": round(float(p[1]), 3),
                           "z": round(float(self.surf(u, v)[0]) + 0.025, 3), "heading": round(heading(du, dv), 1),
                           "color": col, "size": size})
        u0, u1 = ROOF[0] + 0.3, ROOF[1] - 0.3
        for v in [PASSAGE[1]] + [b for _, b in LANES[:-1]]:
            strip([(u0, v), (u1, v)], 0.12)
        strip([(u0, WALKWAY[1]), (u1, WALKWAY[1])], 0.15, "yellow")
        for x in np.arange(u0 + 0.6, u1 - 1.4, 1.4):
            strip([(x, WALKWAY[0] + 0.15), (x + 1.2, WALKWAY[1] - 0.15)], 0.12, "yellow")
        nb = 1
        for (v0, v1) in LANES:
            vc = (v0 + v1) / 2
            for (a, b) in BAYS_U:
                for x in (a, b):
                    strip([(x, v0 + 0.3), (x, v1 - 0.3)], 0.15)
                label(str(nb), b - 2.0, vc, -1, 0, 2.2)
                label("BUS", (a + b) / 2 + 3.0, vc, -1, 0, 1.6, "yellow")
                arrow(a + 4.0, vc, -1)
                nb += 1
        for x in (40.0, 24.75, 9.0):
            arrow(x, (PASSAGE[0] + PASSAGE[1]) / 2, -1)
        for x, v in [(-10.0, 19.0), (-17.0, 24.5), (72.0, 23.0), (62.0, 17.0)]:
            arrow(x, v, -1)
        for q in self.spaces:
            c = np.asarray(q.exterior.coords)[:4]
            strip([c[0], c[3]], 0.1)
            strip([c[1], c[2]], 0.1)
        out = {}
        for col, tri in tris.items():
            if tri:
                a = np.asarray(tri, dtype=np.float64)
                p = m(a[:, 0], a[:, 1])
                z = self.surf(a[:, 0], a[:, 1]) + 0.02
                out[col] = [round(float(x), 2) for x in np.c_[p, z].ravel()]
        return out, labels

    def lamps(self) -> list:
        """The car park's lamp posts ([x, y, z of the foot], as bus_station's lamps)."""
        a, b = self.park_line
        out = []
        for f in (0.2, 0.62):
            q = a + (b - a) * f + self.park_n * (PARK_ROWS[3] + 1.0)
            if not self.bed.buffer(-0.3).contains(Point(q)):
                q = a + (b - a) * f + self.park_n * 0.15
            mp = m(q[0], q[1])
            out.append([round(float(mp[0]), 3), round(float(mp[1]), 3), round(float(self.surf(q[0], q[1])[0]), 3)])
        return out

    def greenery(self, archetypes: dict) -> dict:
        """Trees and hedges for world_builder.gd (added to world.json's at build time): a row along the avenue, trees
        on the talus, the car park's bed and the north-east talus, a hedge inside the fence along the avenue."""
        arch = [a for a in ("round", "oval", "broad", "cone") if a in archetypes] or list(archetypes)[:1]
        rng = np.random.default_rng(1808)
        trees, placed = [], []
        hard = self.hard_depot.buffer(0.5)

        def tree(p, g, h=None, r=None):
            h = float(h or rng.uniform(7.0, 11.0))
            r = float(r or h * rng.uniform(0.28, 0.36))
            if not g.buffer(-r * 0.7).contains(Point(p)) or hard.intersects(Point(p).buffer(r)):
                return
            if any(math.hypot(p[0] - q[0], p[1] - q[1]) < max(r, rq) * 1.6 for q, rq in placed):
                return
            placed.append((p, r))
            mp = m(p[0], p[1])
            a = arch[len(trees) % len(arch)]
            trees.append({"id": "tree:depot:%d" % (len(trees) + 1), "x": round(float(mp[0]), 2),
                          "y": round(float(mp[1]), 2), "h": round(h, 2), "r": round(r, 2), "arch": a,
                          "var": int(rng.integers(0, int(archetypes[a]))), "tint": "leaf", "src": "massy:bus-depot"})
        k = self.walk_on_av
        bk = self.walk_back[k]
        nl = np.c_[-np.gradient(bk[:, 1]), np.gradient(bk[:, 0])]
        nl /= np.linalg.norm(nl, axis=1)[:, None]
        for x in np.arange(4.0, NE_EDGE - 3.0, 8.5):
            i = int(np.argmin(np.abs(bk[:, 0] - x)))
            tree(tuple(bk[i] + nl[i] * 3.2), self.green_se, 7.5, 2.4)
        for g, step in [(self.talus, 7.0), (self.bed, 6.0), (self.green_se, 7.5)]:
            x0, y0, x1, y1 = g.bounds
            for x in np.arange(x0 + 2.0, x1, step):
                for y in np.arange(y0 + 2.0, y1, step):
                    tree((x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.5, 1.5)), g)
        hedges = []
        q = bk + nl * 1.1
        q = q[(q[:, 0] >= PARK_ENTRY[1] + 1.5) & (q[:, 0] <= NE_EDGE - 1.5)]
        q = np.array([p for p in q if self.green.buffer(-0.3).contains(Point(p))])
        if len(q) > 3:
            mp = m(q[::2, 0], q[::2, 1])
            hedges.append({"id": "hedge:depot:1", "pts": r3(mp), "h": 1.4, "w": 1.0, "tint": "spring",
                           "src": "massy:bus-depot", "height_src": "lidar"})
        return {"trees": trees, "hedges": hedges}

    def data(self) -> dict:
        """rail.json massy bus_station `depot`: what hangar_builder.gd draws (in the depot's frame: the bus station's
        (s, t) = (u + s0, v + t0)), the bus job's depot (garages.py), the buses' ways in and out (test_massy.gd)."""
        bays = []
        for bi in (0, 1):                                  # the south-west bays first (garages.gd takes the first free)
            for (v0, v1) in LANES:
                a, b = BAYS_U[bi]
                p = m((a + b) / 2, (v0 + v1) / 2)
                bays.append({"x": round(float(p[0]), 2), "y": round(float(p[1]), 2), "yaw": yaw(-1, 0), "w": 4.0,
                             "l": 20.5})
        tp = m(*TERMINAL)
        W = paths(self)
        g = lambda arr: r3(m(arr[:, 0], arr[:, 1]))
        z_top = float(self.park_z(STAIRS[0] - 0.3, (STAIRS[2] + STAIRS[3]) / 2)[0])
        pan = (70.0, float(self.av_back_v(70.0)) + 4.5)
        return {"s0": S0, "t0": T0, "floor": FLOOR_Z, "roof": list(ROOF), "roof_under": ROOF_UNDER,
                "roof_thick": ROOF_THICK, "roof_edge": ROOF_EDGE, "bevel": BEVEL, "walkway": list(WALKWAY),
                "passage": list(PASSAGE), "lanes": [list(x) for x in LANES], "bays_u": [list(x) for x in BAYS_U],
                "columns_u": COLUMNS_U, "columns_v": list(COLUMN_V),
                "stairs": {"u": [STAIRS[0], STAIRS[1]], "v": [STAIRS[2], STAIRS[3]], "top": round(z_top, 3),
                           "bottom": FLOOR_Z},
                "panel": {"u": pan[0], "v": pan[1], "z": round(float(self.surf(*pan)[0]), 3)},
                "signs": {"facade": "Hangar de la gare routière", "banner": "Nous recrutons !",
                          "line": "Conducteurs de bus : au terminal du dépôt"},
                "depot": {"terminal": {"x": round(float(tp[0]), 2), "y": round(float(tp[1]), 2), "yaw": yaw(1, 0)},
                          "bays": bays},
                "ramps": {"out": [EXIT_FOOT, ROOF[0]], "in": [ROOF[1], ENTRY_FOOT], "vcurve": VCURVE},
                "paths": {"out": [g(p) for p in W["out"]], "in": [g(p) for p in W["in"]]},
                "corners": r3(m([ROOF[0], ROOF[1], ROOF[1], ROOF[0]], [ROOF[2], ROOF[2], ROOF[3], ROOF[3]]))}

    def summary(self) -> str:
        us = np.arange(EXIT_FOOT, ROOF[0] + 1e-6, 0.5)
        go = np.max(np.abs(np.diff(self.ramp_z(us)))) / 0.5
        ui = np.arange(ROOF[1], ENTRY_FOOT + 1e-6, 0.5)
        gi = np.max(np.abs(np.diff(self.ramp_z(ui)))) / 0.5
        return ("depot: roof %.1f x %.1f m, floor %.2f m, ramp out %.1f m (%.2f m, %.1f %% at most), ramp in %.1f m "
                "(%.2f m, %.1f %% at most), %d bays, %d car park spaces" % (
                    ROOF[1] - ROOF[0], ROOF[3] - ROOF[2], FLOOR_Z, ROOF[0] - EXIT_FOOT,
                    FLOOR_Z - float(self.lane_z(EXIT_FOOT)), 100 * go, ENTRY_FOOT - ROOF[1],
                    FLOOR_Z - float(self.lane_z(ENTRY_FOOT)), 100 * gi, len(LANES) * len(BAYS_U), len(self.spaces)))

    # ---------------------------------------------------------------- on the map

    def map_parts(self) -> dict:
        return {"floor": to_map(self.floor), "exit": to_map(self.exit), "entry": to_map(self.entry),
                "park": to_map(self.park), "stairs": to_map(self.stairs), "walk": to_map(self.walk),
                "green_se": to_map(self.green_se), "talus": to_map(self.talus), "bed": to_map(self.bed)}


# ---------------------------------------------------------------- dev plot

def plot(D: Depot, path: str, canvas=None) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon as MP
    fig, ax = canvas if canvas else plt.subplots(figsize=(22, 13))
    def draw(g, **kw):
        for p in polys(g):
            ax.add_patch(MP(np.asarray(p.exterior.coords), **kw))
            for h in p.interiors:
                ax.add_patch(MP(np.asarray(h.coords), color="white", zorder=kw.get("zorder", 5)))
    draw(D.floor, color="#55555c", zorder=5)
    draw(D.exit, color="#6c6c74", zorder=5)
    draw(D.entry, color="#6c6c74", zorder=5)
    draw(D.park, color="#7b7b88", zorder=5)
    draw(D.stairs, color="#eee", zorder=6)
    draw(D.walk, color="#d5d5d8", ec="#333", zorder=5)
    draw(D.green_se, color="#8fd17a", ec="#3d8a2e", zorder=5, alpha=.8)
    draw(D.talus, color="#7cc46a", ec="#2f6e24", zorder=5, alpha=.8)
    draw(D.bed, color="#9fd88a", ec="#2f6e24", zorder=5, alpha=.8)
    for q in D.spaces:
        ax.add_patch(MP(np.asarray(q.exterior.coords), fill=False, ec="white", zorder=7))
    ax.plot(D.kerb[:, 0], D.kerb[:, 1], color="k", lw=2, zorder=8)
    ax.add_patch(MP([(ROOF[0], ROOF[2]), (ROOF[1], ROOF[2]), (ROOF[1], ROOF[3]), (ROOF[0], ROOF[3])], fill=False,
                    ec="#9b4fd9", lw=3, ls="--", zorder=9))
    for name, pth in paths(D).items():
        for p in pth:
            ax.plot(p[:, 0], p[:, 1], lw=1.2, zorder=10)
    # the station's lane lines
    us = np.linspace(-80, 130, 200)
    ax.plot(us, D.kerb_v(us), color="#000", lw=1, zorder=8)
    ax.plot(us, D.back_v(us), color="#555", lw=1, ls=":", zorder=8)
    ax.set_xlim(-80, 130); ax.set_ylim(-35, 40); ax.set_aspect("equal")
    fig.savefig(path, dpi=70, bbox_inches="tight")


# ---------------------------------------------------------------- the buses' ways

def paths(D: Depot) -> dict:
    """(u, v) polylines: "out" from each bay's north-east end down the ramp out onto the Massy side lane to the bus
    station's south-west end; "in" from the RER side lane round the turnaround, along the bulb, up the ramp in to each
    lane's north-east bay."""
    lane_m = bst.LANE_MASSY - T0
    outs = []
    for (v0, v1) in LANES:
        vc = (v0 + v1) / 2
        lat = lane_m - vc
        # the S's length: the bus clear of the sidewalk's ends at the gap (its path under WALL_V - 1.3 at the gap's
        # north-east end, over the kerb + 1.3 at its south-west end)
        fa = math.acos(1 - 2 * min((WALL_V - 1.3 - vc) / lat, 1.0)) / math.pi
        fb = math.acos(1 - 2 * min((D.kerb_v(EXIT_GAP[0] - S0) + 1.3 - vc) / lat, 1.0)) / math.pi
        L = min((EXIT_GAP[1] - EXIT_GAP[0]) / max(fb - fa, 1e-3), 70.0)
        ua = EXIT_GAP[1] - S0 + fa * L
        ub = ua - L
        for bu0, bu1 in BAYS_U:
            a = min(ua, bu1 + 0.5)
            p = np.vstack([np.c_[np.arange(bu1 + 1.0, a, -0.5), np.full(len(np.arange(bu1 + 1.0, a, -0.5)), vc)],
                           cos_shift((a, vc), (a - L, lane_m)),
                           np.c_[np.arange(a - L - 0.5, bst.ENDS[0] - S0, -0.5),
                                 np.full(len(np.arange(a - L - 0.5, bst.ENDS[0] - S0, -0.5)), lane_m)]])
            outs.append(p)
    ins = []
    loop = np.array(bst.LOOP) - np.array([S0, T0])
    stop = bst.STOP_POLE[1] + bst.STOP_AHEAD - S0
    rer = bst.LANE_OUT_STOP - T0
    head = np.vstack([np.c_[np.arange(stop - 10.0, stop + 2.0, 0.5), np.full(len(np.arange(stop - 10.0, stop + 2.0, 0.5)), rer)],
                      cos_shift((stop + 2.0, rer), (loop[0], loop[1] + bst.LOOP_R)),
                      bst._arc(loop, bst.LOOP_R, np.pi / 2, -np.pi / 2)])
    hold = ENTRY_HOLD - T0
    for (v0, v1) in [PASSAGE] + LANES:
        vc = (v0 + v1) / 2
        p = np.vstack([head, cos_shift((loop[0], loop[1] - bst.LOOP_R), (ENTRY_GAP[1] - S0 - 1.0, hold)),
                       np.c_[np.arange(ENTRY_GAP[1] - S0 - 1.5, 97.0, -0.5), np.full(len(np.arange(ENTRY_GAP[1] - S0 - 1.5, 97.0, -0.5)), hold)],
                       cos_shift((ENTRY_S[0], hold), (ENTRY_S[1], vc)),
                       np.c_[np.arange(54.5, BAYS_U[1][0], -0.5), np.full(len(np.arange(54.5, BAYS_U[1][0], -0.5)), vc)]])
        ins.append(p)
    return {"out": outs, "in": ins}
