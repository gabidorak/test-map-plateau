"""Shared helpers of the rail tools (build_rail.py, patch_world.py): paths, the pristine world files, the ground height
as the game draws it, polylines, and the railway alignment read back from rail.json.

Map coordinates everywhere: metres, x east, y north, z up, origin Télécom Paris (Lambert-93 641117.6, 6846184.3);
Godot = (x, z, -y). Alignment coordinates: s along the centreline from its west end, u across it (positive to the
left of the west -> east direction, i.e. to the north).

The pipeline's outputs in godot/world/ are patched in place by patch_world.py; the copies it started from live in
godot/world/base/ (BASE_FILES, committed: git stores identical files once, so they cost nothing in the history; the
folder has a .gdignore, so Godot neither imports nor exports it). world.json `meta.rail` stamps patched files.
"""
import json
import math
import shutil
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot" / "world"
BASE = WORLD / "base"
TOOLS = ROOT / "tools" / "rail"
RAIL_JSON = WORLD / "rail.json"
BASE_FILES = ["world.json", "heightmap.f32", "ground.bin", "ground_ids.bin", "ground_index.json"]


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def ensure_base() -> None:
    """godot/world/base/ holds the pipeline's files before the rail patch. When world.json carries no rail stamp, the
    files in godot/world/ are fresh pipeline outputs: they become the base (a rerun of the pipeline replaces it)."""
    meta = load_json(WORLD / "world.json")["meta"]
    if "rail" in meta:
        missing = [f for f in BASE_FILES if not (BASE / f).exists()]
        if missing:
            raise SystemExit("godot/world/ is patched (world.json meta.rail) but godot/world/base/ lacks %s" % missing)
        return
    BASE.mkdir(parents=True, exist_ok=True)
    (BASE / ".gdignore").write_text("")
    for f in BASE_FILES:
        shutil.copyfile(WORLD / f, BASE / f)
    print("godot/world/base/: the pipeline's files copied before patching")


class Heights:
    """The ground height as godot/scripts/ground_heights.gd draws it: heightmap samples every `mesh_cell` metres (the
    2 m grid nodes), planar inside the two triangles of each cell, diagonal south-west -> north-east. Also gives the
    raw 0.5 m samples (sample) for the LiDAR statistics."""

    def __init__(self, path: Path, terrain: dict, mesh_cell: float):
        self.w, self.h = int(terrain["w"]), int(terrain["h"])
        self.cell = float(terrain["cell"])
        self.ox, self.oy = float(terrain["origin_xy"][0]), float(terrain["origin_xy"][1])
        self.mesh_cell = float(mesh_cell)
        self.step = int(round(self.mesh_cell / self.cell))
        self.data = np.fromfile(path, dtype="<f4").reshape(self.h, self.w).astype(np.float64)

    def nodes(self, data=None) -> np.ndarray:
        """The node grid ground_heights.gd builds: (nh, nw), node (j, i) at x = ox + (i - 1) * mesh_cell,
        y = oy - (j - 1) * mesh_cell (one clamped node beyond each edge)."""
        d = self.data if data is None else data
        nw = (self.w - 1) // self.step + 4
        nh = (self.h - 1) // self.step + 4
        rows = np.clip((np.arange(nh) - 1) * self.step, 0, self.h - 1)
        cols = np.clip((np.arange(nw) - 1) * self.step, 0, self.w - 1)
        return d[np.ix_(rows, cols)]

    def at(self, x, y, nodes=None):
        """Drawn ground height at map (x, y) (arrays or scalars), as ground_heights.gd at()."""
        n = self.nodes() if nodes is None else nodes
        nh, nw = n.shape
        fx = (np.asarray(x, dtype=np.float64) - self.ox) / self.mesh_cell + 1.0
        fy = (self.oy - np.asarray(y, dtype=np.float64)) / self.mesh_cell + 1.0
        i = np.clip(np.floor(fx).astype(int), 0, nw - 2)
        j = np.clip(np.floor(fy).astype(int), 0, nh - 2)
        u = fx - i
        v = fy - j
        z00 = n[j, i]
        z10 = n[j, i + 1]
        z01 = n[j + 1, i]
        z11 = n[j + 1, i + 1]
        lo = z00 + u * (z10 - z00) + v * (z01 - z00)
        hi = z11 + (1.0 - u) * (z01 - z11) + (1.0 - v) * (z10 - z11)
        return np.where(u + v <= 1.0, lo, hi)

    def sample(self, x, y):
        """Bilinear height of the raw 0.5 m samples (LiDAR statistics, not what the game draws)."""
        fx = (np.asarray(x, dtype=np.float64) - self.ox) / self.cell
        fy = (self.oy - np.asarray(y, dtype=np.float64)) / self.cell
        i = np.clip(np.floor(fx).astype(int), 0, self.w - 2)
        j = np.clip(np.floor(fy).astype(int), 0, self.h - 2)
        u = np.clip(fx - i, 0, 1)
        v = np.clip(fy - j, 0, 1)
        d = self.data
        return (d[j, i] * (1 - u) * (1 - v) + d[j, i + 1] * u * (1 - v) + d[j + 1, i] * (1 - u) * v
                + d[j + 1, i + 1] * u * v)

    def inside(self, x, y, margin=0.0):
        x0 = self.ox + margin
        y1 = self.oy - margin
        x1 = self.ox + (self.w - 1) * self.cell - margin
        y0 = self.oy - (self.h - 1) * self.cell + margin
        return (np.asarray(x) >= x0) & (np.asarray(x) <= x1) & (np.asarray(y) >= y0) & (np.asarray(y) <= y1)


# ---------------------------------------------------------------- polylines

def cumlen(p: np.ndarray) -> np.ndarray:
    return np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]


def resample(p: np.ndarray, step: float) -> np.ndarray:
    d = cumlen(p)
    s = np.arange(0.0, d[-1], step)
    return np.c_[np.interp(s, d, p[:, 0]), np.interp(s, d, p[:, 1])]


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


class Design:
    """The ground the railway shapes, from rail.json `earthworks` and `zones` (or the same in memory): z(s, u, p) is
    the designed height at map point p, which is at (s, u) on the alignment, or the existing ground `H` where the
    railway leaves it alone. Per side, each metre: kind 0, the formation then a straight slope from its edge (edge,
    level) to where it meets the ground (reach, top); kind 1, the formation up to a wall at its edge, then a landing at
    the wall's top out to reach; kind 2, a platform: the formation up to the platform wall (edge), the platform top
    (top) out to its back (reach), blended into the ground over BLEND_RUN when it is within BLEND_STEP of it. Zones
    (stairwells, the road's open trench) override: their height runs along an axis."""

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

    def side_values(self, s: float, side: str) -> tuple:
        """(kind, edge, level, reach, top, formation) at s, interpolated between the metres when their kind agrees."""
        f = (s - self.s0) / self.step
        j = int(np.clip(math.floor(f), 0, self.n - 2))
        t = float(np.clip(f - j, 0.0, 1.0))
        sd = self.sides[side]
        k0, k1 = int(sd["kind"][j]), int(sd["kind"][j + 1])
        if k0 != k1:
            jj = j if t < 0.5 else j + 1
            return (int(sd["kind"][jj]), sd["edge"][jj], sd["level"][jj], sd["reach"][jj], sd["top"][jj], self.F[jj])
        lerp = lambda a: a[j] * (1 - t) + a[j + 1] * t
        return (k0, lerp(sd["edge"]), lerp(sd["level"]), lerp(sd["reach"]), lerp(sd["top"]), lerp(self.F))

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
            return top if a <= reach + 1e-9 else None
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


def godot(x, y, z) -> list:
    """Map point -> Godot (x, z, -y), rounded to the millimetre (rail.json is written in map coordinates; this is for
    the review only)."""
    return [round(x, 3), round(z, 3), round(-y, 3)]
