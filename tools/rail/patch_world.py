"""Patches the map files in godot/world/ with the railway of godot/world/rail.json (tools/rail/build_rail.py).

.venv/Scripts/python tools/rail/patch_world.py      (Linux/macOS: .venv/bin/python; ~2 min)

The map pipeline is not in this repository, so its outputs cannot be regenerated: this step patches them. It always
starts from the pipeline's files kept in godot/world/base/ (railgeo.ensure_base: a fresh pipeline output there is
taken as the new base), never from patched ones, so running it twice gives the same files. world.json gets
`meta.rail` (the base files' and rail.json's SHA-1, the patch's version). What it changes, all consumers together:
- heightmap.f32: inside the railway's zones (rail.json zones: the trackbed, platforms, slopes, wall landings, the
  platforms' blends, stairwells, the road's open trench) the designed ground (railgeo.Design); elsewhere untouched.
- ground.bin: every 2 m grid triangle a zone touches is cut again (the old triangles' edges and the zones' outlines
  noded together, faces triangulated, crossings of the grid lines computed once so neighbours share them exactly),
  draped on the new heights. Where two zones meet at different heights (a wall, a platform edge, a stairwell, the
  trench) the cell is a cliff: each side keeps its own plane and a vertical skirt (kerb material, side flag, as the
  pipeline's) closes the gap. The trackbed, platforms, stairwells and trench become new ground pieces (materials
  ballast, asphalt, concrete, asphalt); slopes and landings keep the ground they had. Raised sidewalks and kerbs are
  never cut (the zones keep clear of roads), only lifted with the ground.
- terrain collision: the height field cannot step, so its samples around cliff cells become holes
  (world.json ground_mesh.holes, read by collision_builder.gd) and the drawn triangles there become raised collision
  faces of their chunk (exact).
- ground_ids.bin, ground_index.json: the new pieces (the picker names them, grass never grows on them), the
  `ballast` material, the holes (GroundMap: no grass tufts in them).
- world.json: ground[] keeps its gap-free partition (the new pieces cut out of the old ones, triangulated again),
  the trees and props rail.json clears, the right-of-way fences, the ballast material and palette colour; wall-less
  station canopies standing on the trackbed or a platform (OSM's footbridge stair roof, a slab at knee height over
  the track) are left to the railway's builder; the station building takes its real look (STATION_LOOK: the body up
  to the eaves, rail_builder.gd adds the gabled roof).
A report goes to tools/rail/review/patch.md.
"""
import hashlib
import json
import math
import sys
import time
import zlib
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import polygonize, unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
import railgeo as rg  # noqa: E402

PATCH_VERSION = 2
HARD = {"trackbed": ("railway", "ballast"), "platform": ("platform", "asphalt"), "stairwell": ("steps", "concrete"),
        "road_trench": ("road", "asphalt")}
BALLAST_COLOUR = "#8c8379"      # toy ballast: rust-stained crushed granite (photos of the station), lightened like the
                                # rest of the palette
# The station building as the photos show it (Wikimedia Commons, "Gare Lozère RER IdF Ligne B - Palaiseau (FR91) -
# 2026-01-17"): a cream rendered pavilion, brick quoins and window surrounds, tall ground-floor windows, a slate
# gabled roof; the pipeline's guess (a grey flat-roofed "campus" box from a photo colour of confidence 0.54) goes.
# building_builder.gd has no gables: the body stops at the eaves and rail_builder.gd draws the roof (rail.json-free:
# it reads this building's `rail_roof`).
STATION_BUILDING = "osm:w71346991"
STATION_LOOK = {"wall": "#ece2c6", "accent": "#b4683f", "roof": "#5b616b",
                "eaves": 4.6,           # m above the base: a tall ground floor and attic windows (photos)
                "rise": 2.8,            # m from the eaves to the ridge (~40°, a usual slate pitch)
                "overhang": 0.35,       # m beyond the walls
                "g": 3.2, "f": 2.6,     # ground floor and floor heights (photos: tall arched ground-floor windows)
                "floors": 1, "ground": 0, "material": 0, "windows": 1, "top": 0}   # punched, plain, render, framed
SKIRT_COLOUR = "#c9c4b8"        # cliff skirts (mostly behind the railway's walls): the palette's concrete
CLIFF = 0.02                    # m: two zones meeting further apart than this make a cliff
KERB, PAINT = 18, 19            # pipeline material ids (ground_builder.gd MATERIALS)
OVERLAY = {KERB, PAINT}         # kerb stones, skirts and markings lie on the tiling (ballast, 20, is tiling)
FLAG_RAISED, FLAG_SIDE = 1, 2


def sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def restyle_station(b: dict) -> None:
    """STATION_LOOK on the station building: its tiers end at the eaves without a parapet, punched framed windows in
    cream render with brick accents; `rail_roof` tells rail_builder.gd the gabled roof to put on top."""
    L = STATION_LOOK
    top = b["base_z"] + L["eaves"]
    b["height"] = L["eaves"]
    b["heights"]["rail"] = L["eaves"] + L["rise"]
    b["height_src"] = "rail"
    b["roof"]["shape"] = "gabled"
    b["roof"]["color"] = L["roof"]
    b["facade"].update({"color": L["wall"], "accent": L["accent"], "color_src": "rail", "levels": 1.0})
    st = b["toy"]["style"]
    st.update({"group": "station", "floors": L["floors"], "ground": L["ground"], "material": L["material"],
               "top": L["top"], "windows": L["windows"], "wall": L["wall"], "accent": L["accent"], "g": L["g"],
               "f": L["f"], "levels": 1, "wall_src": "rail", "names": ["punched", "plain", "render", "plain"]})
    for t in b["toy"]["tiers"]:
        t["top"] = round(top, 3)
        t["parapet"] = 0.0
        t["roof"] = L["roof"]
    b["rail_roof"] = {"eaves": round(top, 3), "rise": L["rise"], "overhang": L["overhang"], "slate": L["roof"],
                      "wall": L["wall"], "accent": L["accent"]}


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- zones and heights

class Zones:
    def __init__(self, rail: dict):
        self.list = rail["zones"]
        self.geoms = []
        for z in self.list:
            g = unary_union([Polygon(p[0], p[1:]).buffer(0) for p in z["polygons"]])
            shapely.prepare(g)
            self.geoms.append(g)
        self.union = unary_union(self.geoms)
        self.hard = unary_union([g for g, z in zip(self.geoms, self.list) if z["kind"] in HARD])
        shapely.prepare(self.union)
        shapely.prepare(self.hard)

    def label(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        lab = np.full(x.shape, -1, dtype=np.int32)
        for k, g in enumerate(self.geoms):
            free = lab == -1
            if not free.any():
                break
            inside = np.zeros(x.shape, dtype=bool)
            inside[free] = shapely.contains_xy(g, x[free], y[free])
            lab[inside] = k
        return lab

    def at(self, x: float, y: float) -> int:
        p = Point(x, y)
        for k, g in enumerate(self.geoms):
            if g.contains(p):
                return k
        return -1


def project(A: rg.Alignment, x: np.ndarray, y: np.ndarray) -> tuple:
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


def zone_heights(design: rg.Design, zone: dict, s: np.ndarray, u: np.ndarray, x: np.ndarray, y: np.ndarray):
    """Vectorized railgeo.Design.zone_fn for many points of one zone."""
    kind = zone["kind"]
    if kind in ("stairwell", "road_trench"):
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
    for key in ("kind", "edge", "level", "reach", "top"):
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
    if kind in ("landing", "platform"):
        return vals["top"]
    if kind == "platform_blend":
        sg = np.where(sides == 0, 1.0, -1.0)
        q = design.A.point(s, sg * vals["reach"])
        tb = design.H.at(q[:, 0], q[:, 1])
        g = design.H.at(x, y)
        w = np.clip((a - vals["reach"]) / design.BLEND_RUN, 0, 1)
        return np.where(np.abs(tb - vals["top"]) <= design.BLEND_STEP, vals["top"] + (g - vals["top"]) * w, g)
    raise ValueError(kind)


# ---------------------------------------------------------------- ground.bin

def read_chunk(raw_all, c: dict) -> dict:
    """A chunk of ground.bin; raw_all: the file's bytes, or {id(chunk): its file's bytes} for a split ground mesh."""
    data = raw_all[id(c)] if isinstance(raw_all, dict) else raw_all
    raw = zlib.decompress(data[c["offset"]:c["offset"] + c["size"]])
    nv, ni, nc = c["nv"], c["ni"], c["nc"]
    o = 0
    out = {}
    for name, size, dt, sh in (("pos", nv * 12, "<f4", (nv, 3)), ("nrm", nv * 12, "<f4", (nv, 3)),
                               ("col", nv * 16, "<f4", (nv, 4)), ("cus", nv * 4, "u1", (nv, 4)),
                               ("idx", ni * 4, "<i4", (ni,)), ("colf", nc * 12, "<f4", (nc, 3))):
        out[name] = np.frombuffer(raw[o:o + size], dtype=dt).reshape(sh).copy()
        o += size
    return out


def write_chunk(d: dict) -> bytes:
    return b"".join([d["pos"].astype("<f4").tobytes(), d["nrm"].astype("<f4").tobytes(), d["col"].astype("<f4").tobytes(),
                     d["cus"].astype("u1").tobytes(), d["idx"].astype("<i4").tobytes(), d["colf"].astype("<f4").tobytes()])


class Grid:
    """The 2 m grid the ground mesh is cut on (ground_heights.gd): node (i, j) at x = ox + (i - 1) * cell,
    y = oy - (j - 1) * cell; each cell is split by its south-west -> north-east diagonal, the lower triangle (half 0)
    holding node (i, j)."""

    def __init__(self, H: rg.Heights):
        self.ox, self.oy, self.c = H.ox, H.oy, H.mesh_cell

    def cell_of(self, x: float, y: float) -> tuple:
        fx = (x - self.ox) / self.c + 1.0
        fy = (self.oy - y) / self.c + 1.0
        i, j = math.floor(fx), math.floor(fy)
        return i, j, 0 if (fx - i) + (fy - j) <= 1.0 else 1

    def node_xy(self, i: int, j: int) -> tuple:
        return self.ox + (i - 1) * self.c, self.oy - (j - 1) * self.c

    def tri(self, key: tuple) -> list:
        i, j, h = key
        n00, n10, n01, n11 = self.node_xy(i, j), self.node_xy(i + 1, j), self.node_xy(i, j + 1), self.node_xy(i + 1, j + 1)
        return [n00, n10, n01] if h == 0 else [n11, n01, n10]

    def crossings(self, a: np.ndarray, b: np.ndarray) -> list:
        """Points where segment a -> b crosses the grid lines (verticals, horizontals, diagonals x - y = const)."""
        out = []
        d = b - a
        for fam in range(3):
            if fam == 0:
                va, vb, base = a[0], b[0], self.ox
            elif fam == 1:
                va, vb, base = -a[1], -b[1], -self.oy
            else:
                va, vb, base = a[0] - a[1], b[0] - b[1], self.ox - self.oy
            if abs(vb - va) < 1e-12:
                continue
            k0 = math.ceil((min(va, vb) - base) / self.c)
            k1 = math.floor((max(va, vb) - base) / self.c)
            for k in range(k0, k1 + 1):
                t = (base + k * self.c - va) / (vb - va)
                if 0.0 <= t <= 1.0:
                    out.append((a[0] + d[0] * t, a[1] + d[1] * t))
        return out


class Snapper:
    """Grid-line crossings of every zone outline, computed once: a vertex the cut puts on a cell's edge is moved to
    the one it stands for, so both cells sharing that edge (and both chunks) get the same float."""

    def __init__(self, zones: Zones, grid: Grid):
        pts = []
        for g in zones.geoms:
            for poly in getattr(g, "geoms", [g]):
                for ring in [poly.exterior] + list(poly.interiors):
                    c = np.asarray(ring.coords)
                    for a, b in zip(c[:-1], c[1:]):
                        pts += grid.crossings(a, b)
        self.pts = np.array(pts) if pts else np.zeros((0, 2))
        self.hash = {}
        for k, (x, y) in enumerate(self.pts):
            self.hash.setdefault((round(x, 3), round(y, 3)), []).append(k)

    def snap(self, x: float, y: float):
        best = None
        for dx in (-0.001, 0.0, 0.001):
            for dy in (-0.001, 0.0, 0.001):
                for k in self.hash.get((round(x + dx, 3), round(y + dy, 3)), []):
                    d = abs(self.pts[k, 0] - x) + abs(self.pts[k, 1] - y)
                    if d < 1e-6 and (best is None or d < best[0]):
                        best = (d, k)
        return (float(self.pts[best[1], 0]), float(self.pts[best[1], 1])) if best else None


def _near_segment(p: np.ndarray, a: np.ndarray, b: np.ndarray, tol: float) -> bool:
    ab = b - a
    t = float(np.clip((p - a) @ ab / max(ab @ ab, 1e-12), -0.02, 1.02))
    return float(np.linalg.norm(p - (a + ab * t))) < tol


def on_cell_edge(poly: list, x: float, y: float) -> bool:
    for k in range(len(poly)):
        a, b = poly[k], poly[(k + 1) % len(poly)]
        ax, ay = a
        bx, by = b
        cr = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
        L = math.hypot(bx - ax, by - ay)
        if abs(cr) / L < 1e-7 and min(ax, bx) - 1e-7 <= x <= max(ax, bx) + 1e-7 \
                and min(ay, by) - 1e-7 <= y <= max(ay, by) + 1e-7:
            return True
    return False


def plane(tri: list, zs: list, x: float, y: float) -> float:
    (x0, y0), (x1, y1), (x2, y2) = tri
    det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    l1 = ((x - x0) * (y2 - y0) - (x2 - x0) * (y - y0)) / det
    l2 = ((x1 - x0) * (y - y0) - (x - x0) * (y1 - y0)) / det
    return zs[0] + l1 * (zs[1] - zs[0]) + l2 * (zs[2] - zs[0])


def rebuild_chunk(d: dict, ctx: dict) -> tuple:
    """Cuts and drapes again the grid triangles of this chunk the zones touch. Returns (new chunk arrays, cliff cells
    as set of (i, j), stats)."""
    grid, zones, design, A = ctx["grid"], ctx["zones"], ctx["design"], ctx["A"]
    pos = d["pos"].astype(np.float64)
    X, Y, Z = pos[:, 0], -pos[:, 2], pos[:, 1]
    tri = d["idx"].reshape(-1, 3)
    cus = d["cus"]
    cells = {}                                  # 2 m squares (both halves cut together: their diagonal is
    for t, (a, b, c) in enumerate(tri):         # then noded once, never twice)
        cx, cy = (X[a] + X[b] + X[c]) / 3, (Y[a] + Y[b] + Y[c]) / 3
        cells.setdefault(grid.cell_of(cx, cy)[:2], []).append(t)
    keep_tris = np.ones(len(tri), dtype=bool)
    out_v = []                                  # [x, y, z, colour(4), custom(4), normal or None]
    out_t = []                                  # [i0, i1, i2]
    vindex = {}
    cliffs = set()
    stats = {"cells": 0, "cliff_cells": 0, "skirts": 0, "raised_lifted": 0, "raised_in_cliff": 0}
    rebuilt = set()

    def vert(x, y, z, col, cu):
        key = (round(x, 6), round(y, 6), round(z, 5), tuple(np.round(col, 4)), tuple(int(v) for v in cu))
        k = vindex.get(key)
        if k is None:
            k = len(out_v)
            vindex[key] = k
            out_v.append([x, y, z, col, cu])
        return k

    for key, ts in cells.items():
        halves = [grid.tri(key + (0,)), grid.tri(key + (1,))]
        h0 = halves[0]
        sq = [h0[0], h0[1], halves[1][0], h0[2]]          # NW, NE, SE, SW
        gpoly = Polygon(sq)
        if not zones.union.intersects(gpoly) or zones.union.touches(gpoly):
            continue
        local = [k for k, g in enumerate(zones.geoms) if g.intersects(gpoly)]
        stats["cells"] += 1
        rebuilt.add(key)
        surface, raised, overlay = [], [], []     # the tiling (raised sidewalks kept whole) and what lies on it
        for t in ts:
            a, b, c = tri[t]
            m, f = int(cus[a, 0]), int(cus[a, 1])
            if m in OVERLAY:
                overlay.append(t)
            elif f & FLAG_RAISED:
                raised.append(t)
            else:
                surface.append(t)
        # noding: the old triangles' edges, the cell's outline and the zones' outlines inside it
        lines = [gpoly.exterior, LineString([h0[1], h0[2]])]
        tpolys = {}
        for t in surface + raised:
            a, b, c = tri[t]
            pg = Polygon([(X[a], Y[a]), (X[b], Y[b]), (X[c], Y[c])])
            if pg.area > 1e-10:
                lines.append(pg.exterior)
                if t in surface:
                    tpolys[t] = pg
        for k in local:
            inter = zones.geoms[k].boundary.intersection(gpoly)
            if not inter.is_empty:
                lines.append(inter)
        faces = list(polygonize(unary_union(lines)))
        raised_area = unary_union([Polygon([(X[tri[t][0]], Y[tri[t][0]]), (X[tri[t][1]], Y[tri[t][1]]),
                                            (X[tri[t][2]], Y[tri[t][2]])]) for t in raised]) if raised else None
        pieces = []                              # (face polygon, source triangle, zone index)
        for fpoly in faces:
            if fpoly.area < 1e-8:
                continue
            rp = fpoly.representative_point()
            if raised_area is not None and raised_area.contains(rp):
                continue
            src = None
            for t, pg in tpolys.items():
                if pg.covers(rp):
                    src = t
                    break
            if src is None:
                continue                         # outside every surface triangle (a raised piece's foot)
            zk = -1
            for k in local:
                if zones.geoms[k].contains(rp):
                    zk = k
                    break
            half = grid.cell_of(rp.x, rp.y)[2]
            pieces.append((fpoly, src, zk, half))
        # is it a cliff? two faces of different zones sharing a vertex at different heights
        fn_cache = {}

        def fz(zk, x, y):
            ck = (zk, round(x, 7), round(y, 7))
            if ck not in fn_cache:
                s, u = project(A, np.array([x]), np.array([y]))
                zone = zones.list[zk] if zk >= 0 else None
                fn_cache[ck] = design.zone_fn(zone, float(s[0]), float(u[0]), (x, y))
            return fn_cache[ck]

        verts_by_zone = {}
        for fpoly, src, zk, half in pieces:
            for x, y in fpoly.exterior.coords[:-1]:
                verts_by_zone.setdefault((round(x, 7), round(y, 7)), set()).add(zk)
        cliff = False
        for (x, y), zset in verts_by_zone.items():
            if len(zset) > 1:
                vals = [fz(zk, x, y) for zk in zset]
                if max(vals) - min(vals) > CLIFF:
                    cliff = True
                    break
        node_z = {}
        if cliff:
            cliffs.add(key)
            stats["cliff_cells"] += 1
        # faces -> triangles with their heights
        zeros_new = ctx["nodes_new"]
        for t in ts:
            keep_tris[t] = False
        tri_out = []                             # (pts [(x, y, z)], zone, src)
        for fpoly, src, zk, half in pieces:
            gtri = halves[half]
            for ttri in shapely.constrained_delaunay_triangles(fpoly).geoms:
                pts = []
                for x, y in ttri.exterior.coords[:-1]:
                    if on_cell_edge(sq, x, y) and (round(x, 9), round(y, 9)) not in ctx["orig_xy"]:
                        sn = ctx["snapper"].snap(x, y)
                        if sn:
                            x, y = sn
                    if cliff:
                        if (half, zk) not in node_z:
                            node_z[(half, zk)] = [fz(zk, nx, ny) for nx, ny in gtri]
                        z = plane(gtri, node_z[(half, zk)], x, y)
                    else:
                        z = float(ctx["H_new"].at(x, y, zeros_new))
                    pts.append((x, y, z))
                (x0, y0, _), (x1, y1, _), (x2, y2, _) = pts
                area2 = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
                if abs(area2) < 1e-10:
                    continue
                tri_out.append((pts, zk, src))
        # attributes: the old triangle's, or the zone's new piece
        for pts, zk, src in tri_out:
            a = tri[src][0]
            col = d["col"][a].astype(np.float64)
            cu = d["cus"][a].copy()
            zone = zones.list[zk] if zk >= 0 else None
            if zone is not None and zone["kind"] in HARD:
                col, cu = ctx["piece_attr"][zk]
            # Godot front faces are clockwise seen from above (map y flipped): keep the old winding's sense
            (x0, y0, _), (x1, y1, _), (x2, y2, _) = pts
            if (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0) > 0:     # counter-clockwise in map axes
                pts = [pts[0], pts[2], pts[1]]
            out_t.append([vert(*p, col, cu) for p in pts])
        # skirts between zones at different heights, facing the lower side
        if cliff:
            edges = {}
            for pts, zk, src in tri_out:
                cen = (sum(v[0] for v in pts) / 3, sum(v[1] for v in pts) / 3)
                for p, q in ((pts[0], pts[1]), (pts[1], pts[2]), (pts[2], pts[0])):
                    k2 = tuple(sorted([(round(p[0], 7), round(p[1], 7)), (round(q[0], 7), round(q[1], 7))]))
                    a_, b_ = (p, q) if (round(p[0], 7), round(p[1], 7)) == k2[0] else (q, p)
                    edges.setdefault(k2, []).append((a_, b_, zk, cen))
            scol, scu = ctx["skirt_attr"]
            for k2, lst in edges.items():
                if len(lst) != 2 or lst[0][2] == lst[1][2]:
                    continue
                e0, e1 = lst
                if max(abs(e0[0][2] - e1[0][2]), abs(e0[1][2] - e1[1][2])) < 0.005:
                    continue
                low, high = (e0, e1) if e0[0][2] + e0[1][2] < e1[0][2] + e1[1][2] else (e1, e0)
                stats["skirts"] += 1
                # a portal (tunnel, underpass mouth) on the low side's zone: the wall starts above its opening
                lowz = low[2]
                if lowz >= 0:
                    for pt in zones.list[lowz].get("portals", []):
                        pa, pb = np.asarray(pt["a"]), np.asarray(pt["b"])
                        if all(_near_segment(np.array(v[:2]), pa, pb, 0.35) for v in (low[0], low[1])):
                            zo = float(pt["z_open"])
                            low = (tuple(low[0][:2]) + (max(low[0][2], min(zo, high[0][2])),),
                                   tuple(low[1][:2]) + (max(low[1][2], min(zo, high[1][2])),), low[2], low[3])
                            stats["portal_skirts"] = stats.get("portal_skirts", 0) + 1
                            break
                if max(high[0][2] - low[0][2], high[1][2] - low[1][2]) < 0.005:
                    continue
                quad = [low[0], low[1], high[1], high[0]]
                mx, my = (low[0][0] + low[1][0]) / 2, (low[0][1] + low[1][1]) / 2
                want = np.array([low[3][0] - mx, 0.0, -(low[3][1] - my)])
                for tri3 in ((quad[0], quad[1], quad[2]), (quad[0], quad[2], quad[3])):
                    a3, b3, c3 = (np.array([v[0], v[2], -v[1]]) for v in tri3)
                    if np.linalg.norm(np.cross(c3 - a3, b3 - a3)) < 1e-9:
                        continue
                    if np.cross(c3 - a3, b3 - a3) @ want < 0:
                        tri3 = (tri3[0], tri3[2], tri3[1])
                    out_t.append([vert(*v, scol, scu) for v in tri3])
        # raised pieces, kerb stones, skirts and markings: kept, lifted with the surface under them (in a cliff cell
        # that is their own side's plane: outside the zones the old ground, so they stay)
        for t in raised + overlay:
            ids = []
            for v in tri[t]:
                x, y = X[v], Y[v]
                old = float(ctx["H_old"].at(x, y, ctx["nodes_old"]))
                if cliff:
                    zk = -1
                    pt = Point(x, y)
                    for k in local:
                        if zones.geoms[k].covers(pt):
                            zk = k
                            break
                    hv = grid.cell_of(x, y)[2] if grid.cell_of(x, y)[:2] == key else 0
                    if (hv, zk) not in node_z:
                        node_z[(hv, zk)] = [fz(zk, nx, ny) for nx, ny in halves[hv]]
                    dz = plane(halves[hv], node_z[(hv, zk)], x, y) - old
                else:
                    dz = float(ctx["H_new"].at(x, y, zeros_new)) - old
                ids.append(vert(x, y, Z[v] + dz, d["col"][v].astype(np.float64), d["cus"][v].copy()))
            out_t.append(ids)
            stats["raised_lifted"] += 1
            if cliff:
                stats["raised_in_cliff"] += 1
    # assemble: untouched triangles keep their vertices, new ones get theirs
    used = np.unique(tri[keep_tris].ravel()) if keep_tris.any() else np.zeros(0, dtype=int)
    remap = np.full(len(X), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    nv0 = len(used)
    pos_new = [d["pos"][used]]
    nrm_new = [d["nrm"][used]]
    col_new = [d["col"][used]]
    cus_new = [d["cus"][used]]
    idx_new = [remap[tri[keep_tris]].ravel()]
    if out_v:
        P = np.array([[v[0], v[2], -v[1]] for v in out_v], dtype=np.float64)
        T = np.array(out_t, dtype=np.int64)
        fn = np.cross(P[T[:, 2]] - P[T[:, 0]], P[T[:, 1]] - P[T[:, 0]])   # clockwise front faces: up for the ground
        N = np.zeros_like(P)
        for k in range(3):
            np.add.at(N, T[:, k], fn)
        L = np.linalg.norm(N, axis=1)
        N = N / np.maximum(L, 1e-12)[:, None]
        N[L < 1e-12] = [0.0, 1.0, 0.0]
        pos_new.append(P.astype(np.float32))
        nrm_new.append(N.astype(np.float32))
        col_new.append(np.array([v[3] for v in out_v], dtype=np.float32))
        cus_new.append(np.array([v[4] for v in out_v], dtype=np.uint8))
        idx_new.append((T + nv0).ravel())
    nd = {"pos": np.concatenate(pos_new), "nrm": np.concatenate(nrm_new), "col": np.concatenate(col_new),
          "cus": np.concatenate(cus_new), "idx": np.concatenate(idx_new).astype(np.int32)}
    # the raised collision faces: lifted with the ground (the pipeline's), later the hole covers are appended
    cf = d["colf"].astype(np.float64)
    if len(cf):
        dz = ctx["H_new"].at(cf[:, 0], -cf[:, 2], zeros_new) - ctx["H_old"].at(cf[:, 0], -cf[:, 2], ctx["nodes_old"])
        cf[:, 1] += dz
    nd["colf"] = cf.astype(np.float32)
    return nd, cliffs, stats, rebuilt


def repair_t_junctions(chunks: dict, grid: Grid, rebuilt: set) -> int:
    """A rebuilt cell may put a vertex on an edge it shares with a cell left alone (a zone grazing that cell): the
    neighbour's triangle is split there, across chunks too, its height taken along the edge (the surface does not
    move). Only the tiling triangles (not kerb stones, skirts, markings) count. Returns the number of edges split."""
    near = {(i + di, j + dj) for i, j in rebuilt for di in (-1, 0, 1) for dj in (-1, 0, 1)}
    vhash = {}
    for k, nd in chunks.items():
        P = nd["pos"].astype(np.float64)
        T = nd["idx"].reshape(-1, 3)
        tiling = ~np.isin(nd["cus"][T[:, 0], 0], list(OVERLAY))
        for v in np.unique(T[tiling].ravel()):
            x, y = P[v, 0], -P[v, 2]
            vhash.setdefault((math.floor(x / 0.5), math.floor(y / 0.5)), set()).add((float(x), float(y)))
    count = 0
    for k, nd in chunks.items():
        P = nd["pos"].astype(np.float64)
        T = [list(t) for t in nd["idx"].reshape(-1, 3)]
        extra_v = []                            # (position godot, normal, colour, custom)
        out = []
        changed = False
        queue = list(range(len(T)))
        tris = T
        depth = {}                              # splits behind a triangle: a sliver never splits forever
        while queue:
            t = queue.pop()
            a, b, c = tris[t]
            if int(nd["cus"][a, 0] if a < len(P) else extra_v[a - len(P)][3][0]) in OVERLAY:
                out.append(t)
                continue
            pts = [vpos(P, extra_v, v) for v in (a, b, c)]
            cx, cy = sum(p[0] for p in pts) / 3, -sum(p[2] for p in pts) / 3
            area2 = abs((pts[1][0] - pts[0][0]) * (pts[2][2] - pts[0][2]) - (pts[2][0] - pts[0][0]) * (pts[1][2] - pts[0][2]))
            if grid.cell_of(cx, cy)[:2] not in near or area2 < 1e-4 or depth.get(t, 0) >= 24:
                out.append(t)
                continue
            hit = None
            for e in range(3):
                p, q = pts[e], pts[(e + 1) % 3]
                px, py, qx, qy = p[0], -p[2], q[0], -q[2]
                L = math.hypot(qx - px, qy - py)
                if L < 1e-9:
                    continue
                for hx in range(math.floor(min(px, qx) / 0.5), math.floor(max(px, qx) / 0.5) + 1):
                    for hy in range(math.floor(min(py, qy) / 0.5), math.floor(max(py, qy) / 0.5) + 1):
                        for (vx, vy) in vhash.get((hx, hy), ()):
                            u = ((vx - px) * (qx - px) + (vy - py) * (qy - py)) / (L * L)
                            if u * L <= 1e-4 or (1 - u) * L <= 1e-4:
                                continue
                            # (positions are float32: ~6e-5 m apart this far from the origin)
                            if abs((qx - px) * (vy - py) - (qy - py) * (vx - px)) / L > 1e-4:
                                continue
                            o = pts[(e + 2) % 3]
                            if math.hypot(vx - o[0], vy + o[2]) < 1e-4:
                                continue                # the triangle's own corner (a sliver)
                            if hit is None or u < hit[1]:
                                hit = (e, u, vx, vy)
                if hit is not None and hit[0] == e:
                    break
            if hit is None:
                out.append(t)
                continue
            e, u, vx, vy = hit
            ids = [a, b, c]
            i0, i1, i2 = ids[e], ids[(e + 1) % 3], ids[(e + 2) % 3]
            p0, p1 = vpos(P, extra_v, i0), vpos(P, extra_v, i1)
            z = p0[1] + (p1[1] - p0[1]) * u
            src = i0
            nrm = vattr(nd, extra_v, src, "nrm")
            col = vattr(nd, extra_v, src, "col")
            cu = vattr(nd, extra_v, src, "cus")
            extra_v.append((np.array([vx, z, -vy]), nrm, col, cu))
            nv = len(P) + len(extra_v) - 1
            tris[t] = [i0, nv, i2]
            tris.append([nv, i1, i2])
            depth[t] = depth.get(t, 0) + 1
            depth[len(tris) - 1] = depth[t]
            queue += [t, len(tris) - 1]
            changed = True
            count += 1
        if changed:
            keep = sorted(set(out))
            idx = np.array([tris[t] for t in keep], dtype=np.int64)
            nd["pos"] = np.concatenate([nd["pos"], np.array([e[0] for e in extra_v], dtype=np.float32)])
            nd["nrm"] = np.concatenate([nd["nrm"], np.array([e[1] for e in extra_v], dtype=np.float32)])
            nd["col"] = np.concatenate([nd["col"], np.array([e[2] for e in extra_v], dtype=np.float32)])
            nd["cus"] = np.concatenate([nd["cus"], np.array([e[3] for e in extra_v], dtype=np.uint8)])
            nd["idx"] = idx.ravel().astype(np.int32)
    return count


WELD = 5e-4                     # m: vertices closer than this in plan are one (float32 is ~6e-5 m here)


def weld(chunks: dict, orig_xy: set) -> int:
    """Vertices the cuts left within WELD of each other in plan (a crossing next to an old vertex, two noded lines
    meeting almost at one point) take one position, the old vertex's when there is one, across chunks: else they
    leave hair-thin cracks. Returns how many moved."""
    pts = []
    for k, nd in chunks.items():
        P = nd["pos"]
        for v in range(len(P)):
            pts.append((float(P[v, 0]), float(-P[v, 2]), k, v))
    grid = {}
    for n_, (x, y, k, v) in enumerate(pts):
        grid.setdefault((math.floor(x / WELD), math.floor(y / WELD)), []).append(n_)
    parent = list(range(len(pts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for (gx, gy), members in grid.items():
        cand = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                cand += grid.get((gx + dx, gy + dy), [])
        for i in members:
            xi, yi = pts[i][0], pts[i][1]
            for j in cand:
                if j <= i:
                    continue
                if abs(pts[j][0] - xi) < WELD and abs(pts[j][1] - yi) < WELD and (pts[j][0], pts[j][1]) != (xi, yi):
                    a, b = find(i), find(j)
                    if a != b:
                        parent[b] = a
    groups = {}
    for i in range(len(pts)):
        groups.setdefault(find(i), []).append(i)
    moved = 0
    for g in groups.values():
        if len(g) < 2:
            continue
        posset = {(pts[i][0], pts[i][1]) for i in g}
        if len(posset) < 2:
            continue
        rep = None
        for i in g:
            if (round(pts[i][0], 9), round(pts[i][1], 9)) in orig_xy:
                rep = (pts[i][0], pts[i][1])
                break
        if rep is None:
            rep = min(posset)
        for i in g:
            x, y, k, v = pts[i]
            if (x, y) != rep:
                P = chunks[k]["pos"]
                P[v, 0] = rep[0]
                P[v, 2] = -rep[1]
                moved += 1
    return moved


def drop_degenerate(nd: dict) -> int:
    """Tiling triangles with no area (two corners on one spot after the cuts and splits) go: they would count an edge
    twice. Returns how many."""
    P = nd["pos"].astype(np.float64)
    T = nd["idx"].reshape(-1, 3)
    tiling = ~np.isin(nd["cus"][T[:, 0], 0], list(OVERLAY))
    a, b, c = P[T[:, 0]][:, [0, 2]], P[T[:, 1]][:, [0, 2]], P[T[:, 2]][:, [0, 2]]
    area2 = np.abs((b - a)[:, 0] * (c - a)[:, 1] - (b - a)[:, 1] * (c - a)[:, 0])
    same = (np.all(a == b, axis=1) | np.all(b == c, axis=1) | np.all(a == c, axis=1))
    bad = tiling & (same | (area2 < 1e-9))
    if bad.any():
        nd["idx"] = T[~bad].ravel().astype(np.int32)
    return int(bad.sum())


def drop_overlapping_slivers(nd: dict) -> int:
    """An edge three tiling triangles use means a sliver lies over its neighbours (three points almost in a line
    after the cuts): the thinnest of them (under 1e-4 m²) goes. Returns how many."""
    dropped = 0
    # exact duplicates first (the same three corners twice)
    P = nd["pos"]
    T = nd["idx"].reshape(-1, 3)
    seen = set()
    keep = np.ones(len(T), dtype=bool)
    for t in range(len(T)):
        if int(nd["cus"][T[t, 0], 0]) in OVERLAY:
            continue
        key = tuple(sorted((float(P[v, 0]), float(P[v, 2])) for v in T[t]))
        if key in seen:
            keep[t] = False
        seen.add(key)
    if not keep.all():
        dropped += int((~keep).sum())
        nd["idx"] = T[keep].ravel().astype(np.int32)
    for _ in range(64):
        P = nd["pos"]
        T = nd["idx"].reshape(-1, 3)
        tiling = np.nonzero(~np.isin(nd["cus"][T[:, 0], 0], list(OVERLAY)))[0]
        uses = {}
        for t in tiling:
            for a, b in ((T[t, 0], T[t, 1]), (T[t, 1], T[t, 2]), (T[t, 2], T[t, 0])):
                ka, kb = (float(P[a, 0]), float(P[a, 2])), (float(P[b, 0]), float(P[b, 2]))
                uses.setdefault((ka, kb) if ka < kb else (kb, ka), []).append(t)
        bad = set()
        for e, ts in uses.items():
            if len(ts) <= 2:
                continue
            areas = []
            for t in ts:
                a, b, c = P[T[t, 0]], P[T[t, 1]], P[T[t, 2]]
                areas.append((abs((b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2])) / 2, t))
            areas.sort()
            if areas[0][0] < 1e-4:
                bad.add(areas[0][1])
        if not bad:
            break
        keep = np.ones(len(T), dtype=bool)
        keep[list(bad)] = False
        nd["idx"] = T[keep].ravel().astype(np.int32)
        dropped += len(bad)
    return dropped


def fill_tiny_holes(chunks: dict, bounds: list) -> int:
    """Three unshared edges closing on themselves round under 1e-3 m² are a sliver's place left empty: a triangle
    fills it, with the attributes and heights of its neighbours. Returns how many."""
    owner = {}
    for k, nd in chunks.items():
        P = nd["pos"]
        T = nd["idx"].reshape(-1, 3)
        for t in range(len(T)):
            if int(nd["cus"][T[t, 0], 0]) in OVERLAY:
                continue
            for a, b in ((T[t, 0], T[t, 1]), (T[t, 1], T[t, 2]), (T[t, 2], T[t, 0])):
                ka, kb = (float(P[a, 0]), float(P[a, 2])), (float(P[b, 0]), float(P[b, 2]))
                e = (ka, kb) if ka < kb else (kb, ka)
                owner.setdefault(e, []).append((k, t, a, b))
    x0, y1, x1, y0 = bounds[0], -bounds[1], bounds[2], -bounds[3]   # Godot z = -y
    open_e = {}
    for e, lst in owner.items():
        if len(lst) != 1:
            continue
        (ax, az), (bx, bz) = e
        if (ax == bx and (abs(ax - x0) < 1e-3 or abs(ax - x1) < 1e-3)) or                 (az == bz and (abs(az - y0) < 1e-3 or abs(az - y1) < 1e-3)):
            continue
        open_e[e] = lst[0]
    nbr = {}
    for (p, q) in open_e:
        nbr.setdefault(p, set()).add(q)
        nbr.setdefault(q, set()).add(p)
    done = set()
    filled = 0
    for (p, q), (k, t, a, b) in open_e.items():
        for r in nbr.get(p, set()) & nbr.get(q, set()):
            key = tuple(sorted([p, q, r]))
            if key in done:
                continue
            area = abs((q[0] - p[0]) * (r[1] - p[1]) - (r[0] - p[0]) * (q[1] - p[1])) / 2
            if area > 1e-3:
                continue
            done.add(key)
            nd = chunks[k]
            P = nd["pos"]
            # the corner r: a vertex of this chunk there, else a copy of the owner's vertex a moved there
            rv = None
            for (pp, qq), (k2, t2, a2, b2) in open_e.items():
                for v in (a2, b2):
                    if k2 == k and (float(P[v, 0]), float(P[v, 2])) == r:
                        rv = v
            if rv is None:
                src = None
                for (pp, qq), (k2, t2, a2, b2) in open_e.items():
                    for v in (a2, b2):
                        if (float(chunks[k2]["pos"][v, 0]), float(chunks[k2]["pos"][v, 2])) == r:
                            src = chunks[k2]["pos"][v]
                newp = np.array([[r[0], src[1] if src is not None else P[a, 1], r[1]]], dtype=np.float32)
                nd["pos"] = np.concatenate([nd["pos"], newp])
                nd["nrm"] = np.concatenate([nd["nrm"], nd["nrm"][a:a + 1]])
                nd["col"] = np.concatenate([nd["col"], nd["col"][a:a + 1]])
                nd["cus"] = np.concatenate([nd["cus"], nd["cus"][a:a + 1]])
                rv = len(nd["pos"]) - 1
                P = nd["pos"]
            tri3 = [a, b, rv]
            A3 = P[tri3].astype(np.float64)
            if np.cross(A3[2] - A3[0], A3[1] - A3[0])[1] < 0:        # front faces up
                tri3 = [a, rv, b]
            nd["idx"] = np.concatenate([nd["idx"], np.array(tri3, dtype=np.int32)])
            filled += 1
    return filled


def vpos(P, extra_v, v):
    return P[v] if v < len(P) else extra_v[v - len(P)][0]


def vattr(nd, extra_v, v, key):
    n = len(nd["pos"])
    if v < n:
        return nd[key][v].copy()
    e = extra_v[v - n]
    return {"nrm": e[1], "col": e[2], "cus": e[3]}[key]


# ---------------------------------------------------------------- world.json

def ring_tris(poly: Polygon) -> tuple:
    """(rings without the closing point, triangle indices into their concatenation) of a polygon."""
    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in poly.interiors]
    flat = np.concatenate(rings)
    index = {(round(x, 6), round(y, 6)): k for k, (x, y) in enumerate(flat)}
    tris = []
    for t in shapely.constrained_delaunay_triangles(poly).geoms:
        ids = [index.get((round(x, 6), round(y, 6))) for x, y in t.exterior.coords[:-1]]
        if None not in ids:
            tris += ids
    return [[[round(float(x), 3), round(float(y), 3)] for x, y in r] for r in rings], tris


def main() -> None:
    t0 = time.time()
    rg.ensure_base()
    rail = rg.load_json(rg.RAIL_JSON)
    world = rg.load_json(rg.BASE / "world.json")
    index = rg.load_json(rg.BASE / "ground_index.json")
    gm = world["ground_mesh"]
    H_old = rg.Heights(rg.BASE, world["terrain"], gm["cell"])
    A = rg.Alignment(rail["alignment"])
    design = rg.Design(rail["earthworks"], A, H_old, [z for z in rail["zones"] if "axis" in z])
    zones = Zones(rail)
    grid = Grid(H_old)
    report = ["# Rail patch report", "", "Generated by tools/rail/patch_world.py from godot/world/base/ and "
              "godot/world/rail.json.", ""]

    # --- heightmap
    x0, y0, x1, y1 = zones.union.bounds
    c0 = max(int((x0 - H_old.ox) / H_old.cell) - 2, 0)
    c1 = min(int((x1 - H_old.ox) / H_old.cell) + 3, H_old.w - 1)
    r0 = max(int((H_old.oy - y1) / H_old.cell) - 2, 0)
    r1 = min(int((H_old.oy - y0) / H_old.cell) + 3, H_old.h - 1)
    cc, rr = np.meshgrid(np.arange(c0, c1 + 1), np.arange(r0, r1 + 1))
    xs = H_old.ox + cc * H_old.cell
    ys = H_old.oy - rr * H_old.cell
    lab = zones.label(xs.ravel(), ys.ravel()).reshape(xs.shape)
    new = H_old.data.copy()
    changed = 0
    for k, z in enumerate(zones.list):
        m = lab == k
        if not m.any():
            continue
        x, y = xs[m], ys[m]
        s, u = project(A, x, y)
        zz = zone_heights(design, z, s, u, x, y)
        new[rr[m], cc[m]] = zz
        changed += int(m.sum())
    H_new = rg.Heights(rg.BASE, world["terrain"], gm["cell"])
    H_new.data = new
    log("heightmap: %d samples in the railway's zones" % changed)
    report += ["## Heightmap", "", "%d samples (0.5 m) set to the designed ground in %d zones." % (changed,
                                                                                               len(zones.list)), ""]

    # --- pieces and materials
    mats = list(gm["materials"])
    if "ballast" not in mats:
        mats.append("ballast")
    palette = dict(world["palette"]["ground"])
    palette["ballast"] = BALLAST_COLOUR
    n0 = len(index["pieces"])
    pieces = [list(p) for p in index["pieces"]]
    piece_of_zone = {}
    key_piece = {}
    for k, z in enumerate(zones.list):
        if z["kind"] not in HARD:
            continue
        pk, mat = HARD[z["kind"]]
        key = (pk, z.get("source", ""), z.get("side"))
        if key not in key_piece:
            src = z.get("source", "") or "rail"
            key_piece[key] = len(pieces)
            pieces.append([pk, mat, src.split("+")[0], len(src.split("+"))])
        piece_of_zone[k] = key_piece[key]

    def srgb_col(hexc):
        c = rg_hex(hexc)
        return np.array([c[0], c[1], c[2], 1.0])
    piece_attr = {}
    for k, pi in piece_of_zone.items():
        pk, mat = pieces[pi][0], pieces[pi][1]
        col = srgb_col(palette[mat])
        cu = np.array([mats.index(mat), 0, (pi * 37) % 256, 0], dtype=np.uint8)
        piece_attr[k] = (col, cu)
    skirt_attr = (srgb_col(SKIRT_COLOUR), np.array([KERB, FLAG_SIDE, 0, 0], dtype=np.uint8))

    # --- ground mesh
    files = {}                                  # ground.bin and its parts (a chunk's "file"), as read
    for c in gm["chunks"]:
        f = c.get("file", gm["file"])
        if f not in files:
            files[f] = (rg.BASE / f).read_bytes()
    raw_all = {id(c): files[c.get("file", gm["file"])] for c in gm["chunks"]}
    orig_xy = set()
    ctx = {"grid": grid, "zones": zones, "design": design, "A": A, "H_new": H_new, "H_old": H_old,
           "nodes_new": H_new.nodes(), "nodes_old": H_old.nodes(), "snapper": Snapper(zones, grid),
           "orig_xy": orig_xy, "piece_attr": piece_attr, "skirt_attr": skirt_attr}
    chunks = []
    for c in gm["chunks"]:
        a = c["aabb"]
        cb = box(a[0], -(a[2] + a[5]), a[0] + a[3], -a[2])
        chunks.append((c, cb))
    touched = [k for k, (c, cb) in enumerate(chunks) if zones.union.intersects(cb.buffer(0.01))]
    # original vertex positions of the touched chunks (never snapped)
    datas = {}
    for k in touched:
        d = read_chunk(raw_all, chunks[k][0])
        datas[k] = d
        for x, yy in zip(d["pos"][:, 0].astype(np.float64), -d["pos"][:, 2].astype(np.float64)):
            orig_xy.add((round(x, 9), round(yy, 9)))
    all_cliffs = set()
    all_rebuilt = set()
    totals = {}
    new_chunks = {}
    for k in touched:
        nd, cl, st, rb = rebuild_chunk(datas[k], ctx)
        new_chunks[k] = nd
        all_cliffs |= cl
        all_rebuilt |= rb
        for a_, b_ in st.items():
            totals[a_] = totals.get(a_, 0) + b_
    log("ground mesh: %d chunks touched, %s" % (len(touched), totals))
    near = [k for k, (c, cb) in enumerate(chunks) if cb.buffer(4.0).intersects(zones.union)]
    for k in near:
        if k not in new_chunks:
            new_chunks[k] = read_chunk(raw_all, chunks[k][0])
    splits = 0
    for _ in range(4):                          # its own new vertices may need a neighbour split in turn
        n_ = repair_t_junctions({k: new_chunks[k] for k in near}, grid, all_rebuilt)
        splits += n_
        if n_ == 0:
            break
    welded = weld({k: new_chunks[k] for k in near}, orig_xy)
    dropped = sum(drop_degenerate(new_chunks[k]) for k in near)
    dropped += sum(drop_overlapping_slivers(new_chunks[k]) for k in near)
    for _ in range(2):
        if repair_t_junctions({k: new_chunks[k] for k in near}, grid, all_rebuilt) == 0:
            break
        dropped += sum(drop_degenerate(new_chunks[k]) for k in near)
        dropped += sum(drop_overlapping_slivers(new_chunks[k]) for k in near)
    filled = fill_tiny_holes({k: new_chunks[k] for k in near}, world["meta"]["bounds"])
    if filled:
        log("ground mesh: %d sub-millimetre holes left by slivers filled" % filled)
    log("ground mesh: %d triangle edges split where a neighbour put a vertex on them, %d vertices welded, "
        "%d slivers dropped" % (splits, welded, dropped))
    # cover the collision holes: every cell within one cell of a cliff cell gets raised collision faces
    cover = {(i + di, j + dj) for i, j in all_cliffs for di in (-1, 0, 1) for dj in (-1, 0, 1)}
    for k in near:
        nd = new_chunks[k]
        P = nd["pos"].astype(np.float64)
        T = nd["idx"].reshape(-1, 3)
        faces = []
        for t in T:
            m, f = int(nd["cus"][t[0], 0]), int(nd["cus"][t[0], 1])
            i, j, _ = grid.cell_of(P[t, 0].mean(), -P[t, 2].mean())
            if m in OVERLAY and not (m == KERB and f & FLAG_SIDE and (i, j) in all_cliffs):
                continue                         # kerb stones and markings: the pipeline's own collision is enough
            if (i, j) in cover:
                faces.append(P[t])
        if faces:
            nd["colf"] = np.concatenate([nd["colf"].astype(np.float64), np.concatenate(faces)]).astype(np.float32)
    # holes: collision samples (every second heightmap sample) inside or on the edge of a cliff cell
    holes = set()
    for i, j in all_cliffs:
        xa, ya = grid.node_xy(i, j)                 # north-west corner of the cell
        ca = int(round((xa - H_old.ox) / H_old.cell))
        ra = int(round((H_old.oy - ya) / H_old.cell))
        step = grid.c / H_old.cell
        for dr in range(0, int(step) + 1, 2):
            for dc in range(0, int(step) + 1, 2):
                r, c_ = ra + dr, ca + dc
                if 0 <= r < H_old.h and 0 <= c_ < H_old.w and r % 2 == 0 and c_ % 2 == 0:
                    holes.add((r, c_))
    log("collision: %d cliff cells, %d hole samples, %d cover cells" % (len(all_cliffs), len(holes), len(cover)))
    # write ground.bin (and ground.1.bin... past PART_BYTES, as the pipeline splits it)
    blob = bytearray()
    blobs = []
    total_bytes = 0
    chunk_meta = []
    tri_total = 0
    vert_total = 0
    col_total = 0
    for k, (c, cb) in enumerate(chunks):
        if k in new_chunks:
            nd = new_chunks[k]
            raw = write_chunk(nd)
            comp = zlib.compress(raw, 6)
            P = nd["pos"]
            aabb = [float(P[:, 0].min()), float(P[:, 1].min()), float(P[:, 2].min()),
                    float(np.ptp(P[:, 0])), float(np.ptp(P[:, 1])), float(np.ptp(P[:, 2]))] if len(P) else c["aabb"]
            nv, ni, nc = len(nd["pos"]), len(nd["idx"]), len(nd["colf"])
        else:
            comp = raw_all[id(c)][c["offset"]:c["offset"] + c["size"]]
            raw = None
            aabb, nv, ni, nc = c["aabb"], c["nv"], c["ni"], c["nc"]
        if len(blob) and len(blob) + len(comp) > rg.PART_BYTES:
            blobs.append(blob)
            blob = bytearray()
        m = dict(c)
        m.pop("file", None)
        m.update({"offset": len(blob), "size": len(comp), "nv": nv, "ni": ni, "nc": nc,
                  "raw": len(raw) if raw is not None else c["raw"],
                  "aabb": [round(v, 3) for v in aabb] if raw is not None else c["aabb"]})
        if blobs:
            m["file"] = "%s.%d.bin" % (Path(gm["file"]).stem, len(blobs))
        blob += comp
        total_bytes += len(comp)
        chunk_meta.append(m)
        tri_total += ni // 3
        vert_total += nv
        col_total += nc // 3
    blobs.append(blob)
    stem = Path(gm["file"]).stem
    for old in rg.WORLD.glob(stem + ".*.bin"):
        old.unlink()
    for k, b in enumerate(blobs):
        (rg.WORLD / (gm["file"] if k == 0 else "%s.%d.bin" % (stem, k))).write_bytes(bytes(b))

    # --- ground ids
    ids_info = index["ids"]
    ids = np.frombuffer(zlib.decompress((rg.BASE / ids_info["file"]).read_bytes()), dtype="<u2").reshape(
        ids_info["h"], ids_info["w"]).copy()
    for k, pi in piece_of_zone.items():
        m = lab == k
        ids[rr[m], cc[m]] = pi + 1
    (rg.WORLD / ids_info["file"]).write_bytes(zlib.compress(ids.astype("<u2").tobytes(), 9))
    rg.write_heightmap(rg.WORLD, world["terrain"], new)

    # --- world.json ground partition
    hard_by_piece = {}
    for k, pi in piece_of_zone.items():
        hard_by_piece.setdefault(pi, []).append(zones.geoms[k])
    cut = zones.hard
    touched_ground = 0
    split_parts = []
    for gi, g in enumerate(world["ground"]):
        ring = np.asarray(g["rings"][0])
        bb = box(ring[:, 0].min(), ring[:, 1].min(), ring[:, 0].max(), ring[:, 1].max())
        if not bb.intersects(cut):
            continue
        pg = Polygon(g["rings"][0], g["rings"][1:]).buffer(0)
        if not pg.intersects(cut) or pg.intersection(cut).area < 1e-4:
            continue
        rest = pg.difference(cut)
        parts = sorted([p for p in getattr(rest, "geoms", [rest]) if p.geom_type == "Polygon" and p.area > 1e-3],
                       key=lambda p: -p.area)
        touched_ground += 1
        if not parts:
            g["rings"], g["tris"] = [], []
            continue
        g["rings"], g["tris"] = ring_tris(parts[0])
        for p in parts[1:]:
            split_parts.append((gi, p))
    for gi, p in split_parts:
        g = world["ground"][gi]
        rings, tris = ring_tris(p)
        world["ground"].append({"kind": g["kind"], "material": g["material"], "src": g["src"], "rings": rings,
                                "tris": tris})
        pieces.append(list(index["pieces"][gi]))
        m = shapely.contains_xy(p, xs.ravel(), ys.ravel()).reshape(xs.shape) & (lab < 0)
        ids[rr[m], cc[m]] = len(pieces)
    # the new pieces, in piece order
    order = sorted(set(piece_of_zone.values()))
    new_entries = {}
    for pi in order:
        geom = unary_union(hard_by_piece[pi])
        polys = [p for p in getattr(geom, "geoms", [geom]) if p.geom_type == "Polygon" and p.area > 1e-3]
        pk, mat, src, nsrc = pieces[pi]
        entries = []
        for p in polys:
            rings, tris = ring_tris(p)
            entries.append({"kind": pk, "material": mat, "src": [src], "rings": rings, "tris": tris})
        new_entries[pi] = entries
    # ground[] and the pieces stay aligned: the base pieces, the new pieces (their first polygon), the parts of base
    # pieces the railway split off, then the new pieces' further polygons (each its own piece, its samples relabelled)
    ground = world["ground"]
    base_len = len(index["pieces"])
    final_ground = ground[:base_len]
    final_pieces = [list(p) for p in index["pieces"]]
    id_map = {}
    for pi in order:
        id_map[pi] = len(final_pieces)
        final_pieces.append(pieces[pi])
        final_ground.append(new_entries[pi][0] if new_entries[pi] else
                            {"kind": pieces[pi][0], "material": pieces[pi][1], "src": [pieces[pi][2]], "rings": [],
                             "tris": []})
    for (gi, p), entry in zip(split_parts, ground[base_len:]):
        final_pieces.append(list(index["pieces"][gi]))
        final_ground.append(entry)
    for pi in order:
        for e in new_entries[pi][1:]:
            k_new = len(final_pieces)
            final_pieces.append(list(pieces[pi]))
            final_ground.append(e)
            pg = Polygon(e["rings"][0], e["rings"][1:])
            m = shapely.contains_xy(pg, xs.ravel(), ys.ravel()).reshape(xs.shape) & (ids[rr, cc] == pi + 1)
            ids[rr[m], cc[m]] = k_new + 1
    assert all(id_map[pi] == pi for pi in order)
    world["ground"] = final_ground
    (rg.WORLD / ids_info["file"]).write_bytes(zlib.compress(ids.astype("<u2").tobytes(), 9))
    report += ["## Ground pieces", "", "%d pieces of the partition cut by the railway's ground (%d split in two or "
               "more), %d new pieces:" % (touched_ground, len(split_parts), len(order)), ""]
    for pi in order:
        p = pieces[pi]
        report.append("- #%d %s (%s), from %s" % (id_map[pi], p[0], p[1], p[2]))
    report.append("")

    # --- trees, props, fences, buildings
    clear = rail["clearance"]
    gone = {t["id"]: t for t in clear["trees"]}
    before = len(world["trees"])
    world["trees"] = [t for t in world["trees"] if t["id"] not in gone]
    acts = {p["id"]: p for p in clear["props"]}
    props = []
    for p in world["props"]:
        a = acts.get(p["id"])
        if a is None or a["action"] == "kept":
            props.append(p)
        elif a["action"] == "moved":
            q = dict(p)
            q["x"], q["y"] = a["to"]
            props.append(q)
    dropped = len(world["props"]) - len(props)
    world["props"] = props
    nf = 0
    for f in rail["fences"]:
        world["fences"].append({"style": f["style"], "h": f["h"], "height_src": "rail", "osm": "",
                                "pts": [[round(x, 3), round(y, 3)] for x, y in f["pts"]], "id": f["id"]})
        nf += 1
    canopies = []
    keep_b = []
    restyled = ""
    for b in world["buildings"]:
        if not b.get("walls", True) and Polygon(b["rings"][0]).intersects(zones.hard):
            canopies.append(b["id"])
            continue
        if b["id"] == STATION_BUILDING:
            restyle_station(b)
            restyled = b["id"]
        keep_b.append(b)
    world["buildings"] = keep_b
    report += ["## Trees, props, fences, buildings", "",
               "- trees removed: %d of %d (%s)" % (before - len(world["trees"]), before,
                                                   ", ".join("%s %d" % (r, sum(1 for t in clear["trees"] if t["reason"] == r))
                                                             for r in sorted({t["reason"] for t in clear["trees"]}))),
               "- props moved: %d, dropped: %d, kept on the railway's ground: %d" % (
                   sum(1 for p in clear["props"] if p["action"] == "moved"), dropped,
                   sum(1 for p in clear["props"] if p["action"] == "kept")),
               "- right-of-way fences added: %d" % nf,
               "- wall-less canopies left to the railway's builder: %s" % (", ".join(canopies) or "none"),
               "- station building restyled from the photos (cream render, brick, slate gabled roof): %s"
               % (restyled or "not found"), ""]
    for p in clear["props"]:
        report.append("  - %s %s: %s%s (%s)" % (p["id"], p["model"], p["action"],
                                               " to %s" % p["to"] if p.get("to") else "", p["reason"]))
    report += ["", "Buildings within 6 m of a track (kept; the formation stops short of them, walls where needed):", ""]
    for b in clear["buildings"]:
        report.append("- %s %s (%s): %.2f m from the nearest track centre%s" % (
            b["id"], b["name"], b["kind"], b["nearest_track"], ", IN THE GAUGE" if b["in_gauge"] else ""))
    # kerbs and markings crossing the railway's hard ground (none expected)
    bad_k = [k for k, kb in enumerate(world["kerbs"]) if len(kb["pts"]) > 1 and LineString(kb["pts"]).intersects(zones.hard)]
    report += ["", "Kerbs crossing the railway's ground: %d" % len(bad_k), ""]

    # --- world.json and ground_index.json
    gm2 = dict(gm)
    gm2["materials"] = mats
    gm2["chunks"] = chunk_meta
    gm2["holes"] = {"about": "terrain collision samples (heightmap row, column; every second one, 1 m apart) left out: "
                             "the ground steps there (tools/rail/patch_world.py), raised collision faces cover them",
                    "samples": sorted([list(h) for h in holes])}
    st = dict(gm.get("stats", {}))
    st.update({"triangles": tri_total, "vertices": vert_total, "collision_triangles": col_total, "bytes": total_bytes})
    gm2["stats"] = st
    world["ground_mesh"] = gm2
    world["ground_materials"] = [m for m in mats if m not in ("kerb", "paint")]
    world["palette"]["ground"] = palette
    # No date in the stamp: the same inputs give the same bytes.
    world["meta"]["rail"] = {"version": PATCH_VERSION, "rail_json": sha1(rg.RAIL_JSON),
                             "base": {f: sha1(rg.BASE / f) for f in rg.world_files(rg.load_json(rg.BASE / "world.json"))},
                             "tool": "tools/rail/patch_world.py"}
    index["pieces"] = final_pieces
    index["materials"] = mats
    index["palette"] = dict(index["palette"])
    index["palette"]["ground"] = palette
    index["cliffs"] = {"about": "2 m cells (node i, j as ground_heights.gd counts them) where the ground steps: the "
                                "height there is not the drawn one, so no grass tufts", "cells": sorted([list(c) for c in all_cliffs])}
    (rg.WORLD / "world.json").write_text(json.dumps(world, ensure_ascii=False, separators=(",", ":")) + "\n",
                                         encoding="utf-8")
    (rg.WORLD / "ground_index.json").write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n",
                                                encoding="utf-8")
    report += ["## Ground mesh", "", "- chunks rebuilt: %d; cells cut again: %d, of which cliffs: %d (%d skirts)" % (
        len(touched), totals.get("cells", 0), totals.get("cliff_cells", 0), totals.get("skirts", 0)),
        "- raised pieces lifted with the ground: %d triangles (%d in cliff cells)" % (
            totals.get("raised_lifted", 0), totals.get("raised_in_cliff", 0)),
        "- collision holes: %d samples, covered by raised faces over %d cells" % (len(holes), len(cover)), ""]
    (rg.TOOLS / "review" / "patch.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    log("patched godot/world/ in %.0f s (report: tools/rail/review/patch.md)" % (time.time() - t0))


def rg_hex(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


if __name__ == "__main__":
    main()
