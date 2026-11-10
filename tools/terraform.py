#!/usr/bin/env python3
"""Terraforming: zones where the map's ground is eased onto a surface, applied right after the map is read when it is
built (godot/scripts/builder/terraform.gd: the heightmap, so the collision, water, trees and props; the ground's mesh)
and to the heights read in the game. A zone: an outline (map x east, y north), a surface fitted to the LiDAR ground in
it (the buildings in it left out) and a weight grid (0 at the outline, full `blend` m in).

  python3 tools/terraform.py zone <name> --label forecourt --poly "x,y x,y ..." [--mode smooth|plane|flat]
                                         [--blend 8] [--level h] [--append]
      -> godot/data/terraform/<name>.json ("zones": one per label; --append keeps the others)
  modes: smooth a quadratic (bumps and pads ironed out, the lie of the land kept), plane a tilted plane, flat its
  median height (or --level)
"""
import argparse
import base64
import json
import os
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely import Polygon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD_DIR = os.path.join(ROOT, "godot", "world")
OUT = os.path.join(ROOT, "godot", "data", "terraform")


def _b64(a):
    return base64.b64encode(zlib.compress(np.ascontiguousarray(a, np.uint8).tobytes(), 9)).decode()


def heights_grid(box, step=4):
    """The map's heightmap over a map box, every `step` cells: (xs, ys, z)."""
    w = json.load(open(os.path.join(WORLD_DIR, "world.json"), encoding="utf-8"))["terrain"]
    W, H, cell = int(w["w"]), int(w["h"]), float(w["cell"])
    ox, oy = w["origin_xy"]
    parts = [np.memmap(os.path.join(WORLD_DIR, f), dtype=np.float32, mode="r") for f in w.get("parts", [w["file"]])]
    starts = np.cumsum([0] + [len(p) for p in parts])
    i0, i1 = int((box[0] - ox) / cell), int((box[2] - ox) / cell)
    j0, j1 = int((oy - box[3]) / cell), int((oy - box[1]) / cell)
    cols = np.arange(max(0, i0), min(W - 1, i1) + 1, step)
    rows = np.arange(max(0, j0), min(H - 1, j1) + 1, step)
    z = np.empty((len(rows), len(cols)), np.float32)
    for a, j in enumerate(rows):
        k = j * W + cols
        part = np.searchsorted(starts, k, side="right") - 1
        z[a] = [parts[p][kk - starts[p]] for p, kk in zip(part, k)]
    return ox + cols * cell, oy - rows * cell, z


def fit(poly, exclude, mode, step=4):
    """The surface over `poly` (map), `exclude` polygons left out: origin and the coefficients of
    c0 + c1 u + c2 v + c3 u2 + c4 uv + c5 v2 (u, v: (x, y) - origin, in hundreds of m); outliers dropped."""
    minx, miny, maxx, maxy = poly.bounds
    xs, ys, z = heights_grid((minx - 2, miny - 2, maxx + 2, maxy + 2), step)
    X, Y = np.meshgrid(xs, ys)
    im = Image.new("L", (len(xs), len(ys)), 0)
    d = ImageDraw.Draw(im)
    tx = lambda p: ((p[0] - xs[0]) / (xs[1] - xs[0]), (p[1] - ys[0]) / (ys[1] - ys[0]))
    d.polygon([tx(p) for p in poly.exterior.coords], fill=1)
    for e in exclude:
        d.polygon([tx(p) for p in e.exterior.coords], fill=0)
    keep = np.array(im, dtype=bool)
    c = poly.centroid
    origin = [round(c.x, 2), round(c.y, 2)]
    u, v, h = (X[keep] - c.x) / 100.0, (Y[keep] - c.y) / 100.0, z[keep]
    if mode == "flat":
        return origin, [round(float(np.median(h)), 4), 0, 0, 0, 0, 0], float(np.std(h))
    terms = (lambda u, v: np.c_[np.ones(len(u)), u, v, u ** 2, u * v, v ** 2]) if mode == "smooth" else \
        (lambda u, v: np.c_[np.ones(len(u)), u, v])
    ok = np.ones(len(h), bool)
    for _ in range(4):
        coef, *_ = np.linalg.lstsq(terms(u[ok], v[ok]), h[ok], rcond=None)
        r = h - terms(u, v) @ coef
        ok = np.abs(r) < 3.0 * (np.median(np.abs(r[ok])) + 1e-3) + 0.3
    coef = list(coef) + [0.0] * (6 - len(coef))
    return origin, [round(float(c), 4) for c in coef], float(np.sqrt(np.mean(r[ok] ** 2)))


def weights(poly, blend, cell=1.0):
    """The zone's weight grid: 0 at its outline, 255 from `blend` m in (smoothstep), row 0 north."""
    minx, miny, maxx, maxy = poly.bounds
    gw, gh = int(np.ceil((maxx - minx) / cell)) + 1, int(np.ceil((maxy - miny) / cell)) + 1
    im = Image.new("L", (gw, gh), 0)
    ImageDraw.Draw(im).polygon([((p[0] - minx) / cell, (maxy - p[1]) / cell) for p in poly.exterior.coords], fill=1)
    t = np.clip(ndi.distance_transform_edt(np.array(im, dtype=bool)) * cell / blend, 0.0, 1.0)
    return {"origin": [round(minx, 2), round(maxy, 2)], "cell": cell, "w": gw, "h": gh,
            "weight": _b64(np.round(t * t * (3.0 - 2.0 * t) * 255.0))}


def zone(poly_pts, mode="smooth", blend=8.0, exclude=(), level=None, label=""):
    """A terraforming zone (the game's format, scripts/builder/terraform.gd)."""
    poly = Polygon(poly_pts)
    origin, coef, rms = fit(poly, [Polygon(e) for e in exclude], mode)
    if level is not None:
        coef = [float(level), 0, 0, 0, 0, 0]
    return {"label": label, "mode": mode, "poly": [[round(p[0], 2), round(p[1], 2)] for p in poly_pts],
            "origin": origin, "coef": coef, "blend": blend, "rms": round(rms, 2), "grid": weights(poly, blend)}


def save(name, zones, append=False):
    """data/terraform/<name>.json: its zones (with `append`, the file's other labels kept)."""
    path = os.path.join(OUT, name + ".json")
    old = json.load(open(path, encoding="utf-8"))["zones"] if append and os.path.exists(path) else []
    labels = {z["label"] for z in zones}
    os.makedirs(OUT, exist_ok=True)
    data = {"about": "Terraforming zones (tools/terraform.py, applied by scripts/builder/terraform.gd).",
            "zones": [z for z in old if z["label"] not in labels] + zones}
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    z = sub.add_parser("zone", help="a zone of a terraforming file")
    z.add_argument("name")
    z.add_argument("--label", required=True)
    z.add_argument("--poly", required=True, help='its outline, map points "x,y x,y ..."')
    z.add_argument("--mode", choices=["smooth", "plane", "flat"], default="smooth")
    z.add_argument("--blend", type=float, default=8.0)
    z.add_argument("--level", type=float, help="flat: this height")
    z.add_argument("--append", action="store_true", help="keep the file's other zones")
    a = ap.parse_args()
    pts = [[float(v) for v in p.split(",")] for p in a.poly.split()]
    zn = zone(pts, a.mode, a.blend, level=a.level, label=a.label)
    print("%s: %s %s, rms %.2f m" % (save(a.name, [zn], a.append), a.label, a.mode, zn["rms"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
