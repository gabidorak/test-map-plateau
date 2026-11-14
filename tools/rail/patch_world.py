"""Patches the map files in godot/world/ with the railway's ground (lots rerB and massyPalaiseau: their plans,
godot/data/<lot>/plan.json, tools/rail/build_rail.py, lots.py).

.venv/Scripts/python tools/rail/patch_world.py      (Linux/macOS: .venv/bin/python; ~2 min)

The map pipeline is not in this repository, so its outputs cannot be regenerated: this step patches them. It always
starts from the pipeline's files kept in godot/world/base/ (mapdata.ensure_base: a fresh pipeline output there is
taken as the new base), never from patched ones, so running it twice gives the same files. world.json gets
`meta.rail` (the base files' and the plans' SHA-1, the patch's version). What it changes, all consumers together
(the railway's changes to the world's trees, props, fences, kerbs, buildings and markings are its lots' own,
godot/data/<lot>/drop.json, applied by the game: tools/rail/drops.py):
- heightmap.f32: inside the railway's zones (the plans' zones: the trackbed, platforms, slopes, wall landings, the
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
  the ballast material and palette colour.
- Massy-Palaiseau (lot massyPalaiseau's plan, massy_station.py): the ground repaired where the LiDAR saw the line 18
  station's excavation and le Lien's hall (`regrade` zones: the repaired ground, the material kept), the line 18
  shaft opened down to the mezzanine (a stairwell zone). The Atlantis bus station and the bus hangar
  (bus_station.py): their zones (regrade zones with a ground piece of their own, `piece`, that take the pipeline's
  raised pieces, kerbs and markings in, `absorb`).
A report goes to tools/rail/review/patch.md.
"""
import gc
import hashlib
import json
import math
import multiprocessing
import os
import sys
import time
import zlib
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import polygonize, unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
import railgeo as rg  # noqa: E402
import mapdata as md  # noqa: E402

PATCH_VERSION = 7              # 3: Massy-Palaiseau's ground repairs, line 18 shaft and replaced decks and halls;
                               # 4: the yard's ground lowered under its tracks' ballast beds (railgeo.YardBed);
                               # 5: sites laid out after the pipeline (rail.json logements_x: apply_site);
                               # 6: none any more: the École polytechnique's new housing is lot logementsX;
                               # 7: from the lots' plans, the world's trees, props... their drop.json
BALLAST_COLOUR = "#8c8379"      # toy ballast: rust-stained crushed granite (photos of the station), lightened like the
                                # rest of the palette
SKIRT_COLOUR = "#c9c4b8"        # cliff skirts (mostly behind the railway's walls): the palette's concrete
CLIFF = 0.02                    # m: two zones meeting further apart than this make a cliff
KERB, PAINT = 18, 19            # pipeline material ids (ground_builder.gd MATERIALS)
OVERLAY = {KERB, PAINT}         # kerb stones, skirts and markings lie on the tiling (ballast, 20, is tiling)
FLAG_RAISED, FLAG_SIDE = 1, 2


def sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def plans_sha1() -> str:
    """The railway's lots' plans' SHA-1 (rerB's bytes, then massyPalaiseau's): godot/tools/check_world.gd checks it."""
    import lots
    return hashlib.sha1(lots.plan_path(lots.RER).read_bytes() + lots.plan_path(lots.MASSY).read_bytes()).hexdigest()


def log(*a):
    print(*a, flush=True)


def grid_window(x_axis: np.ndarray, y_axis: np.ndarray, geom) -> tuple:
    """The rows and columns (r0, r1, c0, c1) of a regular grid (x_axis rising along columns, y_axis falling along rows)
    that geom's bounds cover: a point outside them is never inside geom, so testing the window gives the same mask as
    testing the whole grid, in the time of the window."""
    x0, y0, x1, y1 = geom.bounds
    c0, c1 = np.searchsorted(x_axis, x0), np.searchsorted(x_axis, x1, side="right")
    r0, r1 = np.searchsorted(-y_axis, -y1), np.searchsorted(-y_axis, -y0, side="right")
    return r0, max(r1, r0), c0, max(c1, c0)


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
        self.hard = unary_union([g for g, z in zip(self.geoms, self.list) if rg.hard_of(z)])
        # the zones that take the pipeline's raised pieces into their own surface: its raised collision faces go too
        self.absorb = unary_union([g for g, z in zip(self.geoms, self.list) if rg.absorbs(z)])
        shapely.prepare(self.absorb)
        shapely.prepare(self.union)
        shapely.prepare(self.hard)
        # every zone's outline as short segments in one tree: a 2 m cell takes only the few near it (the yard's
        # zones have outlines of thousands of vertices: intersecting all of it per cell took most of an hour)
        segs, owner = [], []
        for k, g in enumerate(self.geoms):
            for ring in shapely.get_rings(shapely.get_parts(g)):
                c = shapely.get_coordinates(ring)
                segs += list(shapely.linestrings(np.stack([c[:-1], c[1:]], axis=1)))
                owner += [k] * (len(c) - 1)
        self.segs = np.array(segs, dtype=object)
        self.seg_owner = np.array(owner)
        self.seg_tree = shapely.STRtree(self.segs)

    def boundary_in(self, k: int, cell) -> shapely.Geometry:
        """Zone k's outline inside `cell` (a polygon): as zones.geoms[k].boundary.intersection(cell)."""
        hit = self.seg_tree.query(cell)
        hit = hit[self.seg_owner[hit] == k]
        if not len(hit):
            return shapely.LineString()
        return shapely.intersection(shapely.multilinestrings(self.segs[hit]), cell)

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

    def label_grid(self, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
        """label() on a regular grid (xs rising along columns, ys falling along rows), each zone tested only inside
        its own bounds: the same labels, without testing every zone against the whole grid."""
        lab = np.full(xs.shape, -1, dtype=np.int32)
        x_axis, y_axis = xs[0], ys[:, 0]
        for k, g in enumerate(self.geoms):
            x0, y0, x1, y1 = g.bounds
            c0, c1 = np.searchsorted(x_axis, x0), np.searchsorted(x_axis, x1, side="right")
            r0, r1 = np.searchsorted(-y_axis, -y1), np.searchsorted(-y_axis, -y0, side="right")
            if c1 <= c0 or r1 <= r0:
                continue
            sub = lab[r0:r1, c0:c1]
            free = sub == -1
            if not free.any():
                continue
            inside = np.zeros(sub.shape, dtype=bool)
            inside[free] = shapely.contains_xy(g, xs[r0:r1, c0:c1][free], ys[r0:r1, c0:c1][free])
            sub[inside] = k
        return lab

    def at(self, x: float, y: float) -> int:
        p = Point(x, y)
        for k, g in enumerate(self.geoms):
            if g.contains(p):
                return k
        return -1


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

    def __init__(self, H: md.Heights):
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
        absorb = [k for k in local if rg.absorbs(zones.list[k])]
        for t in ts:
            a, b, c = tri[t]
            m, f = int(cus[a, 0]), int(cus[a, 1])
            if absorb and (m in OVERLAY or f & FLAG_RAISED):
                cp = Point((X[a] + X[b] + X[c]) / 3, (Y[a] + Y[b] + Y[c]) / 3)
                if any(zones.geoms[k].contains(cp) for k in absorb):
                    if m not in OVERLAY:
                        surface.append(t)       # a raised piece inside: the zone's own surface now
                    continue                    # a kerb, skirt or marking inside: gone with it
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
            inter = zones.boundary_in(k, gpoly)
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
                s, u = rg.project(A, np.array([x]), np.array([y]))
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
            if zone is not None and rg.hard_of(zone):
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
            for k2, lst in edges.items():
                if len(lst) != 2 or lst[0][2] == lst[1][2]:
                    continue
                e0, e1 = lst
                # the yard strips' edges (their ground lowered under the ballast beds): a ballast step, not a kerb
                yardish = any(e[2] >= 0 and zones.list[e[2]]["kind"] == "yard" for e in lst)
                scol, scu = ctx["yard_skirt_attr" if yardish else "skirt_attr"]
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
        dz = ctx["H_new"].at(cf[:, 0], -cf[:, 2], ctx["nodes_new"]) - ctx["H_old"].at(cf[:, 0], -cf[:, 2], ctx["nodes_old"])
        cf[:, 1] += dz
        # inside a zone that took the raised pieces in (the bus station's quays, lanes...): the pipeline's raised
        # faces of those pieces (an old kerb's) go, the zone's ground is the terrain's (or the cliff cells' covers)
        if not ctx["zones"].absorb.is_empty:
            T3 = cf.reshape(-1, 3, 3)
            c = T3.mean(axis=1)
            keep = ~shapely.contains_xy(ctx["zones"].absorb, c[:, 0], -c[:, 2])
            cf = T3[keep].reshape(-1, 3)
    nd["colf"] = cf.astype(np.float32)
    return nd, cliffs, stats, rebuilt


_JOB = {}                      # the chunks' data and the context, inherited by the forked workers (never pickled)


def _rebuild_job(k: int) -> tuple:
    return rebuild_chunk(_JOB["datas"][k], _JOB["ctx"])


def rebuild_chunks(touched: list, datas: dict, ctx: dict) -> list:
    """rebuild_chunk() of every touched chunk, in `touched` order. The chunks are independent (rebuild_chunk only reads
    ctx), so they go to worker processes forked after ctx is built. PATCH_WORKERS sets their number (default: half the
    cores, at most 8: each worker holds a few hundred MB); 1 runs in this process."""
    n = int(os.environ.get("PATCH_WORKERS", min(8, max((os.cpu_count() or 2) // 2, 1))))
    n = min(n, len(touched))
    if n <= 1 or "fork" not in multiprocessing.get_all_start_methods():
        return [rebuild_chunk(datas[k], ctx) for k in touched]
    _JOB["datas"], _JOB["ctx"] = datas, ctx
    gc.collect()
    gc.freeze()                                 # keep the collector from touching (copying) the inherited pages
    try:
        with multiprocessing.get_context("fork").Pool(n) as pool:
            return list(pool.imap(_rebuild_job, touched, chunksize=1))
    finally:
        gc.unfreeze()
        _JOB.clear()


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


def fill_tiny_holes(chunks: dict, bounds: list, max_area: float = 1e-3) -> int:
    """Three unshared edges closing on themselves round under `max_area` m² are a sliver's place left empty: a
    triangle fills it, with the attributes and heights of its neighbours. Returns how many."""
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
            if area > max_area:
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


CRACK_SNAP = 1e-3               # m: an open edge's end this close to another open edge is a T-junction on it
CRACK_WELD = 5e-3               # m: open edges' ends this close are one point (a bowtie of near-collinear slivers)
CRACK_HOLE = 0.05               # m²: the largest three-edge hole filled at the end


def open_edges(chunks: dict, outline, owners=None) -> tuple:
    """The tiling edges used once, off the map's outline, in the `owners` chunks (the rest only close theirs):
    [(chunk, triangle, a, b, (x, y) of a, (x, y) of b)], and their ends {(x, y): height}."""
    rows = []
    for k, nd in chunks.items():
        T = nd["idx"].reshape(-1, 3)
        til = np.nonzero(~np.isin(nd["cus"][T[:, 0], 0], list(OVERLAY)))[0]
        if not len(til):
            continue
        P = nd["pos"].astype(np.float64)
        for e0, e1 in ((0, 1), (1, 2), (2, 0)):
            a, b = T[til, e0], T[til, e1]
            rows.append(np.column_stack([np.full(len(til), k), til, a, b, P[a, 0], -P[a, 2], P[b, 0], -P[b, 2]]))
    if not rows:
        return [], {}
    E = np.concatenate(rows)
    sw = (E[:, 4] > E[:, 6]) | ((E[:, 4] == E[:, 6]) & (E[:, 5] > E[:, 7]))
    key = np.where(sw[:, None], E[:, [6, 7, 4, 5]], E[:, [4, 5, 6, 7]])
    _, inv, n = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    E = E[n[inv.ravel()] == 1]
    if owners is not None:
        E = E[np.isin(E[:, 0], list(owners))]
    on_outline = (shapely.distance(outline, shapely.points(E[:, 4:6])) < 0.01) & \
                 (shapely.distance(outline, shapely.points(E[:, 6:8])) < 0.01)
    edges, ends = [], {}
    for r in E[~on_outline]:
        k, t, a, b = int(r[0]), int(r[1]), int(r[2]), int(r[3])
        pa, pb = (float(r[4]), float(r[5])), (float(r[6]), float(r[7]))
        edges.append((k, t, a, b, pa, pb))
        P = chunks[k]["pos"]
        ends[pa], ends[pb] = float(P[a, 1]), float(P[b, 1])
    return edges, ends


def split_open_t_junctions(chunks: dict, edges: list, ends: dict) -> int:
    """An open edge with other open edges' ends on it (within CRACK_SNAP; the earlier T-junction repair only looks
    near rebuilt cells and at 1e-4 m): its triangle becomes a fan through them, at their heights. Returns how many
    triangles were split."""
    vhash = {}
    for p in ends:
        vhash.setdefault((math.floor(p[0] / 0.5), math.floor(p[1] / 0.5)), []).append(p)
    adds = {}
    done = set()
    for k, t, a, b, (px, py), (qx, qy) in edges:
        if (k, t) in done:
            continue
        L = math.hypot(qx - px, qy - py)
        if L < 1e-6:
            continue
        on = []
        for hx in range(math.floor(min(px, qx) / 0.5) - 1, math.floor(max(px, qx) / 0.5) + 2):
            for hy in range(math.floor(min(py, qy) / 0.5) - 1, math.floor(max(py, qy) / 0.5) + 2):
                for (vx, vy) in vhash.get((hx, hy), ()):
                    u = ((vx - px) * (qx - px) + (vy - py) * (qy - py)) / (L * L)
                    if u * L <= 1e-4 or (1 - u) * L <= 1e-4:
                        continue
                    if abs((qx - px) * (vy - py) - (qy - py) * (vx - px)) / L < CRACK_SNAP:
                        on.append((u, vx, vy))
        if not on:
            continue
        nd = chunks[k]
        T = nd["idx"].reshape(-1, 3)
        c = [v for v in T[t] if v != a and v != b][0]
        new_p, new_tris = adds.setdefault(k, ([], []))
        fan = [a]
        for u, vx, vy in sorted(on):
            new_p.append((np.array([vx, ends[(vx, vy)], -vy]), a))
            fan.append(len(nd["pos"]) + len(new_p) - 1)
        fan.append(b)
        # the edge a -> b runs in the triangle's winding, so a -> v -> c keeps it
        T[t] = [fan[0], fan[1], c]
        new_tris += [[fan[i], fan[i + 1], c] for i in range(1, len(fan) - 1)]
        nd["idx"] = T.ravel()
        done.add((k, t))
    for k, (new_p, new_tris) in adds.items():
        nd = chunks[k]
        src = [s for _, s in new_p]
        nd["pos"] = np.concatenate([nd["pos"], np.array([p for p, _ in new_p], dtype=np.float32)])
        nd["nrm"] = np.concatenate([nd["nrm"], nd["nrm"][src]])
        nd["col"] = np.concatenate([nd["col"], nd["col"][src]])
        nd["cus"] = np.concatenate([nd["cus"], nd["cus"][src]])
        nd["idx"] = np.concatenate([nd["idx"], np.array(new_tris, dtype=np.int32).ravel()]).astype(np.int32)
    return len(done)


def weld_open_ends(chunks: dict, ends: dict, orig_xy: set) -> int:
    """Open edges' ends within CRACK_WELD of each other take one position (an original vertex's when one is): the
    near-collinear slivers of two materials then share their corners. Returns how many vertices moved."""
    pts = list(ends)
    grid = {}
    for n_, (x, y) in enumerate(pts):
        grid.setdefault((math.floor(x / CRACK_WELD), math.floor(y / CRACK_WELD)), []).append(n_)
    parent = list(range(len(pts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for (gx, gy), members in grid.items():
        cand = [j for dx in (-1, 0, 1) for dy in (-1, 0, 1) for j in grid.get((gx + dx, gy + dy), [])]
        for i in members:
            for j in cand:
                if j > i and abs(pts[j][0] - pts[i][0]) < CRACK_WELD and abs(pts[j][1] - pts[i][1]) < CRACK_WELD:
                    parent[find(j)] = find(i)
    groups = {}
    for i in range(len(pts)):
        groups.setdefault(find(i), []).append(pts[i])
    to = {}
    for g in groups.values():
        if len(g) < 2:
            continue
        orig = [p for p in g if (round(p[0], 9), round(p[1], 9)) in orig_xy]
        rep = orig[0] if orig else min(g)
        to.update({p: rep for p in g if p != rep})
    if not to:
        return 0
    moved = 0
    xs = np.array([p[0] for p in to])
    ys = np.array([p[1] for p in to])
    for nd in chunks.values():
        P = nd["pos"]
        if not len(P) or xs.max() < P[:, 0].min() - 1 or xs.min() > P[:, 0].max() + 1:
            continue
        cand = np.nonzero(np.isin(P[:, 0].astype(np.float64), xs) & np.isin(-P[:, 2].astype(np.float64), ys))[0]
        for v in cand:
            r = to.get((float(P[v, 0]), float(-P[v, 2])))
            if r is not None:
                P[v, 0], P[v, 2] = r[0], -r[1]
                moved += 1
    return moved


def fill_outline_notches(chunks: dict, edges: list, outline) -> int:
    """Two open edges p -> q -> r with p and r on the map's outline and q inside: a notch in the ground's edge (a
    sliver cut off at the outline); a triangle under CRACK_HOLE m² fills it. Returns how many."""
    at = {}
    for e in edges:
        at.setdefault(e[4], []).append(e)
        at.setdefault(e[5], []).append(e)
    on = lambda p: outline.distance(Point(p)) < 0.01
    filled = 0
    for q, es in at.items():
        if len(es) != 2 or on(q):
            continue
        (k, t, a, b, pa, pb), e2 = es
        p = pb if pa == q else pa
        r = e2[5] if e2[4] == q else e2[4]
        if p == r or not (on(p) and on(r)):
            continue
        if abs((p[0] - q[0]) * (r[1] - q[1]) - (r[0] - q[0]) * (p[1] - q[1])) / 2 > CRACK_HOLE:
            continue
        nd = chunks[k]
        P = nd["pos"]
        hits = np.nonzero((P[:, 0].astype(np.float64) == r[0]) & (-P[:, 2].astype(np.float64) == r[1]))[0]
        if len(hits):
            rv = int(hits[0])
        else:
            k2, _, a2, b2, pa2, _ = e2
            src = chunks[k2]["pos"][a2 if pa2 == r else b2]
            nd["pos"] = np.concatenate([P, np.array([[r[0], src[1], -r[1]]], dtype=np.float32)])
            for key in ("nrm", "col", "cus"):
                nd[key] = np.concatenate([nd[key], nd[key][a:a + 1]])
            rv = len(nd["pos"]) - 1
        tri3 = [a, b, rv]
        A3 = nd["pos"][tri3].astype(np.float64)
        if np.cross(A3[2] - A3[0], A3[1] - A3[0])[1] < 0:        # front faces up
            tri3 = [a, rv, b]
        nd["idx"] = np.concatenate([nd["idx"], np.array(tri3, dtype=np.int32)])
        filled += 1
    return filled


def close_cracks(chunks: dict, world: dict, orig_xy: set, outline=None, owners=None) -> tuple:
    """The last cracks the cuts leave (millimetres: bowties of near-collinear slivers, T-junctions just off an edge,
    a missed sliver's hole or notch in the outline): weld, split and fill until no open edge is left off the map's
    outline. `owners`: the chunks worked on; the others in `chunks` (a ring around them) only tell their open edges
    from the edges they share with it. Returns (splits, welded, filled, open edges left)."""
    m = world["meta"]
    if outline is None:
        outline = (Polygon(m["data_area"][0], m["data_area"][1:]) if m.get("data_area") else box(*m["bounds"])).boundary
    splits = welded = filled = 0
    for _ in range(4):
        edges, ends = open_edges(chunks, outline, owners)
        if not edges:
            return splits, welded, filled, 0
        n1 = weld_open_ends(chunks, ends, orig_xy)          # first: a bowtie's corners also lie on its edges
        if n1:
            for nd in chunks.values():
                drop_degenerate(nd)
        edges, ends = open_edges(chunks, outline, owners)
        n2 = split_open_t_junctions(chunks, edges, ends)
        n3 = fill_tiny_holes(chunks, m["bounds"], CRACK_HOLE)
        n3 += fill_outline_notches(chunks, open_edges(chunks, outline, owners)[0], outline)
        welded, splits, filled = welded + n1, splits + n2, filled + n3
        if n1 + n2 + n3 == 0:
            break
    return splits, welded, filled, len(open_edges(chunks, outline, owners)[0])


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
    """(rings without the closing point, triangle indices into their concatenation) of a polygon. The triangles'
    corners are matched to the ring vertices by the nearest one (within 0.1 mm): exact float keys missed some, and
    the triangles dropped left holes in the piece."""
    from scipy.spatial import cKDTree
    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in poly.interiors]
    flat = np.concatenate(rings)
    tree = cKDTree(flat)
    tris = []
    for t in shapely.constrained_delaunay_triangles(poly).geoms:
        d, ids = tree.query(np.asarray(t.exterior.coords)[:-1])
        if d.max() < 1e-4 and len(set(ids.tolist())) == 3:
            tris += [int(i) for i in ids]
    return [[[round(float(x), 3), round(float(y), 3)] for x, y in r] for r in rings], tris


def main() -> None:
    t0 = time.time()
    md.ensure_base()
    import lots
    rail = lots.load()
    world = md.load_json(md.BASE / "world.json")
    index = md.load_json(md.BASE / "ground_index.json")
    gm = world["ground_mesh"]
    H_old = md.Heights(md.BASE, world["terrain"], gm["cell"])
    A = rg.Alignment(rail["alignment"])
    # the ground the design follows: the base one, repaired at Massy-Palaiseau (massy_station.py: its `regrade` zones
    # take it, so do the yard's strips there)
    H_fix = H_old
    repairs = rail.get("massy", {}).get("repairs", [])
    if repairs:
        import massy_station as mst
        H_fix = md.Heights.__new__(md.Heights)
        H_fix.__dict__.update({k: v for k, v in H_old.__dict__.items() if not k.startswith("_nodes")})
        H_fix.data = mst.apply_repairs(H_old, repairs)
    design = rg.Design(rail["earthworks"], A, H_fix, [z for z in rail["zones"] if "axis" in z])
    if rail.get("yard", {}).get("bed"):
        design.yard_bed = rg.YardBed(rail["yard"])     # the yard's ground under its tracks' ballast beds
    zones = Zones(rail)
    grid = Grid(H_old)
    report = ["# Rail patch report", "", "Generated by tools/rail/patch_world.py from godot/world/base/ and "
              "the railway's lots' plans (godot/data/rerB/, godot/data/massyPalaiseau/).", ""]

    # --- heightmap
    x0, y0, x1, y1 = zones.union.bounds
    c0 = max(int((x0 - H_old.ox) / H_old.cell) - 2, 0)
    c1 = min(int((x1 - H_old.ox) / H_old.cell) + 3, H_old.w - 1)
    r0 = max(int((H_old.oy - y1) / H_old.cell) - 2, 0)
    r1 = min(int((H_old.oy - y0) / H_old.cell) + 3, H_old.h - 1)
    cc, rr = np.meshgrid(np.arange(c0, c1 + 1), np.arange(r0, r1 + 1))
    xs = H_old.ox + cc * H_old.cell
    ys = H_old.oy - rr * H_old.cell
    x_axis, y_axis = xs[0], ys[:, 0]
    lab = zones.label_grid(xs, ys)
    new = H_old.data.copy()
    changed = 0
    for k, z in enumerate(zones.list):
        m = lab == k
        if not m.any():
            continue
        x, y = xs[m], ys[m]
        s, u = rg.project(A, x, y)
        zz = rg.zone_heights(design, z, s, u, x, y)
        new[rr[m], cc[m]] = zz
        changed += int(m.sum())
    H_new = md.Heights(md.BASE, world["terrain"], gm["cell"])
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
        if not rg.hard_of(z):
            continue
        pk, mat = rg.hard_of(z)
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
    # the yard strips' steps: ballast-coloured, still kerb skirts (check_world.gd and the ground's hole check know
    # those lie over the surface)
    yard_skirt_attr = (srgb_col(BALLAST_COLOUR), np.array([KERB, FLAG_SIDE, 0, 0], dtype=np.uint8))

    # --- ground mesh
    files = {}                                  # ground.bin and its parts (a chunk's "file"), as read
    for c in gm["chunks"]:
        f = c.get("file", gm["file"])
        if f not in files:
            files[f] = (md.BASE / f).read_bytes()
    raw_all = {id(c): files[c.get("file", gm["file"])] for c in gm["chunks"]}
    orig_xy = set()
    ctx = {"grid": grid, "zones": zones, "design": design, "A": A, "H_new": H_new, "H_old": H_old,
           "nodes_new": H_new.nodes(), "nodes_old": H_old.nodes(), "snapper": Snapper(zones, grid),
           "orig_xy": orig_xy, "piece_attr": piece_attr, "skirt_attr": skirt_attr,
           "yard_skirt_attr": yard_skirt_attr}
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
    for k, (nd, cl, st, rb) in zip(touched, rebuild_chunks(touched, datas, ctx)):
        new_chunks[k] = nd
        all_cliffs |= cl
        all_rebuilt |= rb
        for a_, b_ in st.items():
            totals[a_] = totals.get(a_, 0) + b_
    log("ground mesh: %d chunks touched, %s" % (len(touched), totals))
    near = [k for k, (c, cb) in enumerate(chunks) if cb.buffer(4.0).intersects(zones.union)]
    # and every chunk bordering a rebuilt one: a vertex a rebuilt cell puts on their shared border splits theirs too
    rebuilt_boxes = shapely.union_all([chunks[k][1] for k in touched]).buffer(0.5) if touched else None
    if rebuilt_boxes is not None:
        near = sorted(set(near) | {k for k, (c, cb) in enumerate(chunks) if cb.intersects(rebuilt_boxes)})
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
    # with a ring of the chunks around them: the edges they share with it are no cracks
    near_boxes = shapely.union_all([chunks[k][1] for k in near]).buffer(0.5)
    ring = [k for k, (c, cb) in enumerate(chunks) if k not in new_chunks and cb.intersects(near_boxes)]
    for k in ring:
        new_chunks[k] = read_chunk(raw_all, chunks[k][0])
    cs, cw, cf, left = close_cracks({k: new_chunks[k] for k in list(near) + ring}, world, orig_xy, owners=set(near))
    log("ground mesh: last cracks: %d triangles split at a T-junction, %d vertices welded, %d holes filled, "
        "%d open edges left" % (cs, cw, cf, left))
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
        if len(blob) and len(blob) + len(comp) > md.PART_BYTES:
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
    for old in md.WORLD.glob(stem + ".*.bin"):
        old.unlink()
    for k, b in enumerate(blobs):
        (md.WORLD / (gm["file"] if k == 0 else "%s.%d.bin" % (stem, k))).write_bytes(bytes(b))

    # --- ground ids
    ids_info = index["ids"]
    ids = np.frombuffer(zlib.decompress((md.BASE / ids_info["file"]).read_bytes()), dtype="<u2").reshape(
        ids_info["h"], ids_info["w"]).copy()
    for k, pi in piece_of_zone.items():
        m = lab == k
        ids[rr[m], cc[m]] = pi + 1
    (md.WORLD / ids_info["file"]).write_bytes(zlib.compress(ids.astype("<u2").tobytes(), 9))
    md.write_heightmap(md.WORLD, world["terrain"], new)

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
        rest = shapely.make_valid(shapely.set_precision(pg.difference(cut), 0.001))
        parts = sorted([p for p in shapely.get_parts(rest) if p.geom_type == "Polygon" and p.area > 1e-3],
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
        r0, r1, c0, c1 = grid_window(x_axis, y_axis, p)
        w = (slice(r0, r1), slice(c0, c1))
        m = shapely.contains_xy(p, xs[w].ravel(), ys[w].ravel()).reshape(xs[w].shape) & (lab[w] < 0)
        ids[rr[w][m], cc[w][m]] = len(pieces)
    # the new pieces, in piece order
    m_ = world["meta"]
    ground_outline = Polygon(m_["data_area"][0], m_["data_area"][1:]) if m_.get("data_area") else box(*m_["bounds"])
    order = sorted(set(piece_of_zone.values()))
    new_entries = {}
    for pi in order:
        # on the map's ground only (the line leaves the west box's south edge aslant: its first strips poked out)
        geom = shapely.make_valid(shapely.set_precision(unary_union(hard_by_piece[pi]).intersection(ground_outline),
                                                        0.001))
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
            r0, r1, c0, c1 = grid_window(x_axis, y_axis, pg)
            w = (slice(r0, r1), slice(c0, c1))
            m = shapely.contains_xy(pg, xs[w].ravel(), ys[w].ravel()).reshape(xs[w].shape) & (ids[rr[w], cc[w]] == pi + 1)
            ids[rr[w][m], cc[w][m]] = k_new + 1
    assert all(id_map[pi] == pi for pi in order)
    world["ground"] = final_ground
    (md.WORLD / ids_info["file"]).write_bytes(zlib.compress(ids.astype("<u2").tobytes(), 9))
    report += ["## Ground pieces", "", "%d pieces of the partition cut by the railway's ground (%d split in two or "
               "more), %d new pieces:" % (touched_ground, len(split_parts), len(order)), ""]
    for pi in order:
        p = pieces[pi]
        report.append("- #%d %s (%s), from %s" % (id_map[pi], p[0], p[1], p[2]))
    report.append("")

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
    world["meta"]["rail"] = {"version": PATCH_VERSION, "plans": plans_sha1(),
                             "base": {f: sha1(md.BASE / f) for f in md.world_files(md.load_json(md.BASE / "world.json"))},
                             "tool": "tools/rail/patch_world.py"}
    index["pieces"] = final_pieces
    index["materials"] = mats
    index["palette"] = dict(index["palette"])
    index["palette"]["ground"] = palette
    index["cliffs"] = {"about": "2 m cells (node i, j as ground_heights.gd counts them) where the ground steps: the "
                                "height there is not the drawn one, so no grass tufts", "cells": sorted([list(c) for c in all_cliffs])}
    for g in world["ground"]:                   # nothing reads the pieces' triangles (the mesh is ground.bin): with the
        g.pop("tris", None)                     # west box they would take world.json past GitHub's 100 MB
    (md.WORLD / "world.json").write_text(json.dumps(world, ensure_ascii=False, separators=(",", ":")) + "\n",
                                         encoding="utf-8")
    (md.WORLD / "ground_index.json").write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n",
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
