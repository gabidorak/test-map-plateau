"""The railway's geometry for the rail tools (build_rail.py, lots.py...): the alignment read back from its plan,
the yard's ballast beds, the designed ground (earthworks, zones). The map's files and heights: tools/common/mapdata.py.

Alignment coordinates: s along the centreline from its west end, u across it (positive to the left of the west -> east
direction, i.e. to the north).
"""
import math

import numpy as np

from mapdata import ROOT, Heights, cumlen

TOOLS = ROOT / "tools" / "rail"


class Alignment:
    """The centreline as written in rerB's plan `alignment`: points, heading and rail level every `step` m; evaluates
    positions at (s, u) and projects map points onto (s, u)."""

    def __init__(self, a: dict):
        self.step = float(a["step"])
        self.pts = np.array(a["pts"], dtype=np.float64)
        self.heading = np.array(a["heading"], dtype=np.float64)
        self.z = np.array(a["z"], dtype=np.float64)
        self.length = float(a["length"])
        self.s = np.arange(len(self.pts)) * self.step

    def _i(self, s):
        f = np.clip(np.asarray(s, dtype=np.float64) / self.step, 0, len(self.pts) - 1.000001)
        i = np.floor(f).astype(int)
        return i, f - i

    def point(self, s, u=0.0):
        """Map (x, y) at distance s along the centreline, u to its left."""
        i, t = self._i(s)
        p = self.pts[i] * (1 - t)[..., None] + self.pts[i + 1] * t[..., None]
        th = self.heading[i] * (1 - t) + self.heading[i + 1] * t
        u = np.asarray(u, dtype=np.float64)
        return p + np.stack([-np.sin(th), np.cos(th)], axis=-1) * u[..., None]

    def theta(self, s):
        i, t = self._i(s)
        return self.heading[i] * (1 - t) + self.heading[i + 1] * t

    def level(self, s):
        """Rail level (inner rail top) at s."""
        i, t = self._i(s)
        return self.z[i] * (1 - t) + self.z[i + 1] * t

    def project(self, q, hint=None, window=60.0):
        """(s, u) of map points q (n, 2); `hint` (n,) narrows the search to +-window m."""
        q = np.atleast_2d(np.asarray(q, dtype=np.float64))
        out = np.zeros((len(q), 2))
        for k, p in enumerate(q):
            if hint is None:
                lo, hi = 0, len(self.pts) - 1
            else:
                lo = max(int((hint[k] - window) / self.step), 0)
                hi = min(int((hint[k] + window) / self.step), len(self.pts) - 1)
            seg = self.pts[lo:hi + 1]
            j = lo + int(np.argmin(np.einsum("ij,ij->i", seg - p, seg - p)))
            j = min(max(j, 1), len(self.pts) - 2)
            best = None
            for a in (j - 1, j):
                ab = self.pts[a + 1] - self.pts[a]
                t = np.clip(np.dot(p - self.pts[a], ab) / np.dot(ab, ab), 0.0, 1.0)
                c = self.pts[a] + ab * t
                d2 = np.dot(p - c, p - c)
                if best is None or d2 < best[0]:
                    side = np.sign(ab[0] * (p[1] - c[1]) - ab[1] * (p[0] - c[0]))
                    best = (d2, (a + t) * self.step, side * math.sqrt(d2))
            out[k] = best[1:]
        return out


class YardBed:
    """The ground under the yard tracks' ballast beds (rerB's plan yard `bed`: tools/rail/yard.py; rail_builder.gd draws
    each track's bed as a prism, its top SHOW under the sleepers' tops, like the alignment's): the patched ground in
    the "yard" zones may not rise above cap(x, y), DROP under the nearest bed top out to FLAT m from the track centre,
    then rising RISE per metre. The ground mesh is draped on 2 m nodes, so a node up to ~2.8 m off a track shapes the
    ground under its sleepers: with the ground kept as the LiDAR saw it (yard.py before 2026-11-07) it rose over the
    sleepers along 89 % of the yard and over the rails at 7 %."""

    REACH = 7.0                     # m: tracks further off do not cap a point (RISE * (REACH - FLAT) > any hump)

    def __init__(self, yard: dict):
        from scipy.spatial import cKDTree
        bed = yard.get("bed", {})
        self.drop, self.flat, self.rise = float(bed["drop"]), float(bed["flat"]), float(bed["rise"])
        below = float(bed["below_rail"])                # rail top -> bed top
        P, T, Hd = [], [], []
        for t in yard["tracks"]:
            pts, z, hd = np.asarray(t["pts"], dtype=np.float64), np.asarray(t["z"], dtype=np.float64), \
                np.asarray(t["heading"], dtype=np.float64)
            for a, b in t.get("bed", []):
                P.append(pts[a:b + 1])
                T.append(z[a:b + 1] - below)
                Hd.append(hd[a:b + 1])
        self.ok = bool(P)
        if self.ok:
            self.P, self.T, self.Hd = np.vstack(P), np.concatenate(T), np.concatenate(Hd)
            self.tree = cKDTree(self.P)

    def cap(self, x, y) -> np.ndarray:
        """Highest ground allowed at map points (arrays; +inf where no bed is within REACH)."""
        q = np.c_[np.atleast_1d(np.asarray(x, dtype=np.float64)), np.atleast_1d(np.asarray(y, dtype=np.float64))]
        out = np.full(len(q), np.inf)
        if not self.ok:
            return out
        for a in range(0, len(q), 20000):
            qq = q[a:a + 20000]
            dd, ii = self.tree.query(qq, k=48, distance_upper_bound=self.REACH)
            ok = np.isfinite(dd)
            ii = np.where(ok, ii, 0)
            v = qq[:, None, :] - self.P[ii]
            tx, ty = np.cos(self.Hd[ii]), np.sin(self.Hd[ii])
            along = np.abs(v[..., 0] * tx + v[..., 1] * ty)
            across = np.abs(v[..., 1] * tx - v[..., 0] * ty)
            d = np.sqrt(across ** 2 + np.maximum(along - 0.5, 0.0) ** 2)     # each point stands for its metre
            c = self.T[ii] - self.drop + np.maximum(d - self.flat, 0.0) * self.rise
            c[~ok] = np.inf
            out[a:a + 20000] = c.min(axis=1)
        return out


class Design:
    """The ground the railway shapes, from rerB's plan `earthworks` and the plans' `zones` (or the same in memory): z(s, u, p) is
    the designed height at map point p, which is at (s, u) on the alignment, or the existing ground `H` where the
    railway leaves it alone. Per side, each metre: kind 0, the formation then a straight slope from its edge (edge,
    level) to where it meets the ground (reach, top); kind 1, the formation up to a wall at its edge, then a landing from
    the wall's top out to reach, where it meets the ground (far); kind 2, a platform: the formation up to the platform wall (edge), the platform top
    (top) out to its back (reach), blended into the ground over BLEND_RUN when it is within BLEND_STEP of it. Zones
    (stairwells, the road's open trench, the yard's islands) override: their height runs along an axis; the yard's
    ballast strips keep the ground."""

    BLEND_STEP = 0.35
    BLEND_RUN = 2.0

    def __init__(self, ew: dict, A: Alignment, H: Heights, zones=()):
        self.ew = ew
        self.A = A
        self.H = H
        self.s0 = float(ew["s0"])
        self.step = float(ew["step"])
        self.F = np.asarray(ew["formation"], dtype=np.float64)
        self.cf = float(ew["crossfall"])
        self.sides = {k: {a: np.asarray(v, dtype=np.float64) for a, v in ew[k].items() if a != "why"}
                      for k in ("left", "right")}
        self.n = len(self.F)
        self.yard_bed = None            # YardBed: caps the "yard" zones' ground (patch_world.py sets it)
        self.zones = []
        for z in zones:
            self.add_zone(z)

    def add_zone(self, z: dict) -> None:
        from shapely.geometry import Polygon
        from shapely.prepared import prep
        polys = [Polygon(r[0], r[1:]) for r in z["polygons"]]
        axis = np.asarray(z["axis"], dtype=np.float64)
        self.zones.append((polys, [prep(p) for p in polys], axis, cumlen(axis), np.asarray(z["axis_z"], dtype=np.float64),
                           z))

    def zone_at(self, p) -> int:
        from shapely.geometry import Point
        q = Point(float(p[0]), float(p[1]))
        for k, (polys, prepared, *_rest) in enumerate(self.zones):
            if any(pp.contains(q) for pp in prepared):
                return k
        return -1

    def zone_z(self, k: int, p) -> float:
        polys, prepared, axis, d, az, _z = self.zones[k]
        best = None
        for a in range(len(axis) - 1):
            ab = axis[a + 1] - axis[a]
            t = float(np.clip(np.dot(np.asarray(p) - axis[a], ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0))
            c = axis[a] + ab * t
            d2 = float(np.dot(np.asarray(p) - c, np.asarray(p) - c))
            if best is None or d2 < best[0]:
                best = (d2, az[a] + (az[a + 1] - az[a]) * t)
        return best[1]

    def ground(self, p) -> float:
        return float(self.H.at(p[0], p[1]))

    def covers(self, s: float) -> bool:
        return self.s0 <= s <= self.s0 + (self.n - 1) * self.step

    def side_values(self, s: float, side: str, want: int = -1) -> tuple:
        """(kind, edge, level, reach, top, formation) at s, interpolated between the metres when their kind agrees;
        where it changes, the nearer metre's, or the one of kind `want` (a zone's plane reaches a little past its
        end: a platform's height stays the platform's there)."""
        f = (s - self.s0) / self.step
        j = int(np.clip(math.floor(f), 0, self.n - 2))
        t = float(np.clip(f - j, 0.0, 1.0))
        sd = self.sides[side]
        k0, k1 = int(sd["kind"][j]), int(sd["kind"][j + 1])
        F = self.F[j] * (1 - t) + self.F[j + 1] * t
        if k0 != k1:
            if want in (k0, k1):
                jj = j if k0 == want else j + 1
            else:
                jj = j if t < 0.5 else j + 1
            return (int(sd["kind"][jj]), sd["edge"][jj], sd["level"][jj], sd["reach"][jj], sd["top"][jj], F)
        lerp = lambda a: a[j] * (1 - t) + a[j + 1] * t
        return (k0, lerp(sd["edge"]), lerp(sd["level"]), lerp(sd["reach"]), lerp(sd["top"]), F)

    def landing_far(self, s: float, side: str, top: float, want: int = 1) -> float:
        """The ground height a wall's landing runs down (or up) to at its reach (`far`; older plans: flat)."""
        sd = self.sides[side]
        if "far" not in sd:
            return top
        f = (s - self.s0) / self.step
        j = int(np.clip(math.floor(f), 0, self.n - 2))
        t = float(np.clip(f - j, 0.0, 1.0))
        k0, k1 = int(sd["kind"][j]), int(sd["kind"][j + 1])
        if k0 != k1:
            jj = (j if k0 == want else j + 1) if want in (k0, k1) else (j if t < 0.5 else j + 1)
            return float(sd["far"][jj])
        return float(sd["far"][j] * (1 - t) + sd["far"][j + 1] * t)

    def z(self, s: float, u: float, p, zones=True):
        """Designed height at p (= alignment (s, u)), or None where the railway leaves the ground alone."""
        if zones and self.zones:
            k = self.zone_at(p)
            if k >= 0:
                return self.zone_z(k, p)
        if not self.covers(s):
            return None
        side = "left" if u >= 0 else "right"
        kind, edge, level, reach, top, F = self.side_values(s, side)
        a = abs(u)
        if a <= edge:
            return F - self.cf * a
        if kind == 0:
            if a > reach + 1e-9:
                return None
            return level + (top - level) * (a - edge) / max(reach - edge, 1e-6)
        if kind == 1:
            if a > reach + 1e-9:
                return None
            far = self.landing_far(s, side, top)
            return top + (far - top) * min(max((a - edge) / max(reach - edge, 1e-6), 0.0), 1.0)
        if kind == 2:
            if a <= reach:
                return top
            if a <= reach + self.BLEND_RUN:
                q = self.A.point(s, np.sign(u) * reach)
                tb = self.ground(q)
                if abs(tb - top) <= self.BLEND_STEP:
                    w = (a - reach) / self.BLEND_RUN
                    return top + (self.ground(p) - top) * w
            return None
        return None

    def z_or_ground(self, s: float, u: float, p) -> float:
        v = self.z(s, u, p)
        return self.ground(p) if v is None else v

    def zone_fn(self, zone: dict, s: float, u: float, p) -> float:
        """Height zone `zone` (the plans' zones) gives point p (= (s, u)), also a little outside it (the patch draws
        both sides of a cliff from their own zone); `None` zone: the existing ground."""
        if zone is None:
            return self.ground(p)
        kind = zone["kind"]
        # a yard track's ballast strip: the ground as it is (yard.py), under the ballast beds' cap (YardBed); a repair
        # (massy_station.py): the repaired ground this Design was given
        if kind == "yard" and self.yard_bed is not None:
            return min(self.ground(p), float(self.yard_bed.cap(p[0], p[1])[0]))
        if kind in ("yard", "regrade", "regrade_floor", "regrade_gravel"):
            return self.ground(p)
        if kind in ("stairwell", "road_trench", "island", "bus_island"):
            for k, z in enumerate(self.zones):
                if z[5] is zone:
                    return self.zone_z(k, p)
            self.add_zone(zone)
            return self.zone_z(len(self.zones) - 1, p)
        s = min(max(s, self.s0), self.s0 + (self.n - 1) * self.step)
        side = zone.get("side") or ("left" if u >= 0 else "right")
        want = {"slope": 0, "landing": 1, "platform": 2, "platform_blend": 2}.get(kind, -1)
        k_, edge, level, reach, top, F = self.side_values(s, side, want)
        a = abs(u)
        if kind == "trackbed":
            return F - self.cf * a
        if kind == "slope":
            w = min(max((a - edge) / max(reach - edge, 1e-6), 0.0), 1.0)
            return level + (top - level) * w
        if kind == "landing":
            far = self.landing_far(s, side, top, want)
            return top + (far - top) * min(max((a - edge) / max(reach - edge, 1e-6), 0.0), 1.0)
        if kind == "platform":
            return top
        if kind == "platform_blend":
            q = self.A.point(s, (1.0 if side == "left" else -1.0) * reach)
            tb = self.ground(q)
            if abs(tb - top) <= self.BLEND_STEP:
                w = min(max((a - reach) / self.BLEND_RUN, 0.0), 1.0)
                return top + (self.ground(p) - top) * w
            return self.ground(p)
        raise ValueError(kind)


def godot(x, y, z) -> list:
    """Map point -> Godot (x, z, -y), rounded to the millimetre (the plans are written in map coordinates; this is for
    the review only)."""
    return [round(x, 3), round(z, 3), round(-y, 3)]


# ---------------------------------------------------------------- the zones' ground (the plans' zones)

HARD = {"trackbed": ("railway", "ballast"), "platform": ("platform", "asphalt"), "stairwell": ("steps", "concrete"),
        "road_trench": ("road", "asphalt"), "island": ("platform", "asphalt"), "yard": ("railway", "ballast"),
        # Massy-Palaiseau's repaired ground with a ground of its own (massy_station.py): the line 18 hall's floor and
        # its site (OSM's building site, now the station's gravel)
        "regrade_floor": ("pedestrian", "concrete"), "regrade_gravel": ("landcover", "gravel"),
        # the Atlantis bus station's islands, raised to a bus kerb's height (massy_station.bus_islands)
        "bus_island": ("platform", "concrete")}
REGRADE = ("regrade", "regrade_floor", "regrade_gravel")    # zones whose height is the repaired ground
AXIS_KINDS = ("stairwell", "road_trench", "island", "bus_island")   # zones whose height runs along an axis
# zones that take the pipeline's raised pieces (and their kerbs, skirts, markings) inside them into their own surface:
# the bus islands, whose OSM outlines the pipeline had partly raised as platforms
ABSORB = ("bus_island",)


def hard_of(z: dict):
    """(piece kind, material) of zone z's new ground piece, None when it keeps the ground's (a regrade zone may name
    one: `piece`, bus_station.py), and whether it absorbs the pipeline's raised pieces (`absorb`)."""
    return tuple(z["piece"]) if z.get("piece") else HARD.get(z["kind"])


def absorbs(z: dict) -> bool:
    return z["kind"] in ABSORB or bool(z.get("absorb"))


def project(A: Alignment, x: np.ndarray, y: np.ndarray) -> tuple:
    """(s, u) of map points, vectorized: the centreline runs west -> east with x always increasing, so s starts from
    x and three Newton steps along the tangent finish it."""
    s = np.interp(x, A.pts[:, 0], A.s)
    for _ in range(4):
        P = A.point(s, np.zeros_like(s))
        th = A.theta(s)
        s = s + (x - P[:, 0]) * np.cos(th) + (y - P[:, 1]) * np.sin(th)
    P = A.point(s, np.zeros_like(s))
    th = A.theta(s)
    u = -(x - P[:, 0]) * np.sin(th) + (y - P[:, 1]) * np.cos(th)
    return s, u


def zone_heights(design: Design, zone: dict, s: np.ndarray, u: np.ndarray, x: np.ndarray, y: np.ndarray):
    """Vectorized railgeo.Design.zone_fn for many points of one zone."""
    kind = zone["kind"]
    if kind == "yard" and design.yard_bed is not None:     # under the yard tracks' ballast beds (yard.py)
        return np.minimum(design.H.at(x, y), design.yard_bed.cap(x, y))
    if kind == "yard" or kind in REGRADE:       # the yard's ballast strips keep the ground (tools/rail/yard.py), a
        return design.H.at(x, y)                # repair takes the repaired ground (design.H: massy_station.py)
    if kind in AXIS_KINDS:
        ax = np.asarray(zone["axis"], dtype=np.float64)
        az = np.asarray(zone["axis_z"], dtype=np.float64)
        best = np.full(len(x), np.inf)
        out = np.zeros(len(x))
        for a in range(len(ax) - 1):
            ab = ax[a + 1] - ax[a]
            t = np.clip(((x - ax[a, 0]) * ab[0] + (y - ax[a, 1]) * ab[1]) / max(ab @ ab, 1e-12), 0, 1)
            cx, cy = ax[a, 0] + ab[0] * t, ax[a, 1] + ab[1] * t
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            m = d2 < best
            best[m] = d2[m]
            out[m] = az[a] + (az[a + 1] - az[a]) * t[m]
        return out
    ew = design
    f = np.clip((s - ew.s0) / ew.step, 0, ew.n - 1.000001)
    j = np.floor(f).astype(int)
    t = f - j
    side = zone.get("side")
    sides = np.where(u >= 0, 0, 1) if side is None else np.full(len(u), 0 if side == "left" else 1)
    vals = {}
    for key in ("kind", "edge", "level", "reach", "top", "far"):
        if key == "far" and "far" not in ew.sides["left"]:
            vals["far"] = vals["top"]           # older plans: flat landings
            continue
        arr = np.stack([ew.sides["left"][key], ew.sides["right"][key]])
        a0, a1 = arr[sides, j], arr[sides, j + 1]
        same = ew.sides["left"]["kind"][j] == ew.sides["left"]["kind"][j + 1]
        same = np.where(sides == 0, same, ew.sides["right"]["kind"][j] == ew.sides["right"]["kind"][j + 1])
        vals[key] = np.where(same, a0 * (1 - t) + a1 * t, np.where(t < 0.5, a0, a1))
    F = ew.F[j] * (1 - t) + ew.F[j + 1] * t
    a = np.abs(u)
    if kind == "trackbed":
        return F - ew.cf * a
    if kind == "slope":
        w = np.clip((a - vals["edge"]) / np.maximum(vals["reach"] - vals["edge"], 1e-6), 0, 1)
        return vals["level"] + (vals["top"] - vals["level"]) * w
    if kind == "landing":
        w = np.clip((a - vals["edge"]) / np.maximum(vals["reach"] - vals["edge"], 1e-6), 0, 1)
        return vals["top"] + (vals["far"] - vals["top"]) * w
    if kind == "platform":
        return vals["top"]
    if kind == "platform_blend":
        sg = np.where(sides == 0, 1.0, -1.0)
        q = design.A.point(s, sg * vals["reach"])
        tb = design.H.at(q[:, 0], q[:, 1])
        g = design.H.at(x, y)
        w = np.clip((a - vals["reach"]) / design.BLEND_RUN, 0, 1)
        return np.where(np.abs(tb - vals["top"]) <= design.BLEND_STEP, vals["top"] + (g - vals["top"]) * w, g)
    raise ValueError(kind)
