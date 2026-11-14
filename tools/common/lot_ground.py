"""A lot's own ground, as its tool designs it, for the game to draw (godot/scripts/builder/lot_ground.gd): its zones
(the polygons it owns or lays a surface on, each with its material or the map's) with their heights on grids, and its
terraforming (where it reshapes the map's ground round them, its repairs). Python designs, Godot draws: nothing of the
design is computed again in the game.

Grids: map metres, nodes every CELL m on the map's lattice (x = i * CELL, y = j * CELL), in tiles of TILE cells
(TILE + 1 nodes a side, row 0 north); each zone's (or repair's) tiles cover it and MARGIN m round it, its height
function evaluated there too (a zone draws its walls against its neighbours from both sides' heights). Heights are
stored in millimetres over their tile's lowest (int16), all tiles in one deflated file.

    write(out_dir, zones, height, repairs, about, palette)
    zones:   [{"id", "kind", "material" (a ground material, or None: the map's), "piece" (the kind of ground piece the
              game reads there: railway, platform, steps, road...; None: the material's usual one), "owned" (bool:
              the lot draws it and collides it, the map's ground cut out), "polygons": [[outer, holes...]...] (map
              rings), "wall" (the material of its walls where it meets another ground higher or lower: concrete by
              default), "snap" (m: where it meets the map's ground no further apart than this, its edge comes onto
              the map's ground instead of a wall: SNAP by default), "portals" ([{"a", "b", "z_open"}]: along a-b, where it is
              the lower side, its wall starts at z_open: a tunnel's or an underpass's mouth, a shaft over a box)}]
    height:  height(zone, x, y) -> z (numpy arrays of map points)
    repairs: [{"id", "ring": [[x, y]...], "height": f(x, y) -> z}]: the terraformed ground (all of it inside the ring),
             one grid each over its ring's box (MARGIN round it): [x0, y0 (its north-west node), w, h, z min, offset]
    palette: {material: colour} of the materials the lot brings that the map has not (the railway's ballast)
Writes out_dir/ground.json (the index) and out_dir/ground.bin.
"""
import json
import math
import zlib
from pathlib import Path

import numpy as np
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from shapely.prepared import prep

CELL = 1.0
TILE = 16
MARGIN = 1.5
N = TILE + 1
SNAP = 0.05             # m: a zone's edge comes onto the map's ground this close (a wall beyond)
WALL = "concrete"


def _tiles(g, margin: float) -> list:
    """The tiles (ti, tj) a geometry, grown by `margin`, touches."""
    gg = g.buffer(margin)
    pg = prep(gg)
    x0, y0, x1, y1 = gg.bounds
    side = TILE * CELL
    out = []
    for ti in range(math.floor(x0 / side), math.floor(x1 / side) + 1):
        for tj in range(math.floor(y0 / side), math.floor(y1 / side) + 1):
            if pg.intersects(box(ti * side, tj * side, (ti + 1) * side, (tj + 1) * side)):
                out.append((ti, tj))
    return out


def _nodes(ti: int, tj: int) -> tuple:
    """A tile's nodes (map x, y arrays, row 0 north: y decreasing)."""
    side = TILE * CELL
    xs = ti * side + np.arange(N) * CELL
    ys = (tj + 1) * side - np.arange(N) * CELL
    X, Y = np.meshgrid(xs, ys)
    return X.ravel(), Y.ravel()


def _grids(g, fn, blob: bytearray) -> list:
    """Heights fn(x, y) on the tiles round geometry g, appended to blob: [[ti, tj, z min, offset]...]."""
    out = []
    for ti, tj in _tiles(g, MARGIN):
        x, y = _nodes(ti, tj)
        z = np.asarray(fn(x, y), dtype=np.float64)
        z = np.where(np.isfinite(z), z, np.nanmin(z) if np.isfinite(z).any() else 0.0)
        lo = float(z.min())
        mm = np.clip(np.round((z - lo) * 1000.0), 0, 65535).astype("<u2")
        out.append([ti, tj, round(lo, 4), len(blob)])
        blob += mm.tobytes()
    return out


def write(out_dir: Path, zones: list, height, repairs=(), about: str = "", palette=None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    zs = []
    for z in zones:
        g = unary_union([Polygon(pg[0], pg[1:]).buffer(0) for pg in z["polygons"]])
        zs.append({"id": z["id"], "kind": z["kind"], "material": z.get("material"), "piece": z.get("piece"),
                   "owned": bool(z.get("owned", True)), "wall": z.get("wall") or WALL,
                   "snap": float(z.get("snap", SNAP)), "portals": z.get("portals") or [], "polygons": z["polygons"],
                   "tiles": _grids(g, lambda x, y, z=z: height(z, x, y), blob)})
    rs = []
    for rp in repairs:
        bx0, by0, bx1, by1 = Polygon(rp["ring"]).buffer(MARGIN).bounds
        x0, y0 = math.floor(bx0 / CELL) * CELL, math.ceil(by1 / CELL) * CELL      # (the north-west node)
        w = int(math.ceil((bx1 - x0) / CELL)) + 1
        h = int(math.ceil((y0 - by0) / CELL)) + 1
        X, Y = np.meshgrid(x0 + np.arange(w) * CELL, y0 - np.arange(h) * CELL)
        z = np.asarray(rp["height"](X.ravel(), Y.ravel()), dtype=np.float64)
        lo = float(z.min())
        rs.append({"id": rp["id"], "ring": rp["ring"], "grid": [x0, y0, w, h, round(lo, 4), len(blob)]})
        blob += np.clip(np.round((z - lo) * 1000.0), 0, 65535).astype("<u2").tobytes()
    raw = bytes(blob)
    (out_dir / "ground.bin").write_bytes(zlib.compress(raw, 9))
    index = {"about": about or "The lot's own ground (tools/common/lot_ground.py): its zones' and repairs' heights on "
                                "grids for godot/scripts/builder/lot_ground.gd.",
             "cell": CELL, "tile": TILE, "unit": 0.001, "file": "ground.bin", "raw": len(raw), "palette": palette or {},
             "zones": zs, "repairs": rs}
    (out_dir / "ground.json").write_bytes((json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
    return {"zones": len(zs), "repairs": len(rs), "tiles": len(raw) // (N * N * 2), "bytes": len(raw)}
