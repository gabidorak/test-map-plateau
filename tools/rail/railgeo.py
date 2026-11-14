"""The railway's geometry for the rail tools (build_rail.py, patch_world.py...): the alignment read back from rail.json,
the yard's ballast beds, the designed ground (earthworks, zones). The map's files and heights: tools/common/mapdata.py.

Alignment coordinates: s along the centreline from its west end, u across it (positive to the left of the west -> east
direction, i.e. to the north).
"""
import math

import numpy as np

from mapdata import ROOT, WORLD, Heights, cumlen

TOOLS = ROOT / "tools" / "rail"
RAIL_JSON = WORLD / "rail.json"


class Alignment:
    """The centreline as written in rail.json `alignment`: points, heading and rail level every `step` m; evaluates
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
    """The ground under the yard tracks' ballast beds (rail.json yard `bed`: tools/rail/yard.py; rail_builder.gd draws
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
    """The ground the railway shapes, from rail.json `earthworks` and `zones` (or the same in memory): z(s, u, p) is
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
        """The ground height a wall's landing runs down (or up) to at its reach (`far`; older rail.json: flat)."""
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
        """Height zone `zone` (rail.json zones) gives point p (= (s, u)), also a little outside it (the patch draws
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
    """Map point -> Godot (x, z, -y), rounded to the millimetre (rail.json is written in map coordinates; this is for
    the review only)."""
    return [round(x, 3), round(z, 3), round(-y, 3)]
