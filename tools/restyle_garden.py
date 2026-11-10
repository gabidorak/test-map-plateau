"""The grounds of a restyled spec read off an aerial image (tools/restyle.py garden): trees, hedges, paths, the lawn and
the meadow, the ground smoothed. The image (a Google Maps screenshot...) is put on the map by an affine fit on known
points ("px,py=mx,my", 3 or more: buildings' corners or centres); every pixel of the grounds is sorted by its colour:
  canopy  dark green, textured (trees; long thin patches: hedges)
  path    light grey, white, light beige
  ignored the map's buildings (their courtyards are read), the red of a drawn outline, roads and shadows (dark grey),
          water (the map's stays)
Trees: the peaks of the canopy's distance to its edge (a crown each, its radius that distance); hedges: their axis.
Paths: polygons (with their holes) and their triangles. The ground: a quadratic fitted to the map's LiDAR ground in the
grounds (bumps and pads ignored), "smooth"; or its median, "flat".
"""
import base64
import json
import os
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely import Polygon, MultiPolygon, box as sbox, unary_union, constrained_delaunay_triangles
from shapely.affinity import affine_transform

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD_DIR = os.path.join(ROOT, "godot", "world")


def fit(pairs):
    """Affine maps px -> map and map -> px from "px,py=mx,my ..." (least squares), the residuals, m per px."""
    pp = [p.split("=") for p in pairs.split()]
    px = np.array([[float(v) for v in s.split(",")] for s, _ in pp])
    mp = np.array([[float(v) for v in t.split(",")] for _, t in pp])
    A = np.c_[px, np.ones(len(px))]
    M, *_ = np.linalg.lstsq(A, mp, rcond=None)
    B = np.c_[mp, np.ones(len(mp))]
    Mi, *_ = np.linalg.lstsq(B, px, rcond=None)
    res = np.linalg.norm(A @ M - mp, axis=1)
    return M, Mi, res, float(np.sqrt(abs(np.linalg.det(M[:2]))))


def to_px(pts, Mi):
    return [tuple(np.r_[p, 1.0] @ Mi) for p in pts]


def shapely_px_to_map(g, M):
    # x' = a x + b y + xoff ; y' = d x + e y + yoff  (M rows: [x coeffs], [y coeffs], [offsets])
    return affine_transform(g, [M[0, 0], M[1, 0], M[0, 1], M[1, 1], M[2, 0], M[2, 1]])


def raster(size, rings_list, Mi):
    """A mask of the image: polygons (map rings: outer, then holes) filled, their holes open."""
    im = Image.new("L", size, 0)
    d = ImageDraw.Draw(im)
    for rings in rings_list:
        d.polygon(to_px(rings[0], Mi), fill=1)
        for h in rings[1:]:
            d.polygon(to_px(h, Mi), fill=0)
    return np.array(im, dtype=bool)


def hsv(img):
    mx = img.max(2)
    mn = img.min(2)
    c = mx - mn + 1e-6
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    h = np.where(mx == r, ((g - b) / c) % 6, np.where(mx == g, (b - r) / c + 2, (r - g) / c + 4)) * 60.0
    return h, c / (mx + 1e-6), mx


def mask_polys(mask, M, mpp, min_m2, simplify_m=0.35):
    """The mask's patches as map polygons (with holes), the small ones left out."""
    lab, n = ndi.label(mask)
    out = []
    for k, sl in enumerate(ndi.find_objects(lab), start=1):
        sub = lab[sl] == k
        if sub.sum() * mpp * mpp < min_m2:
            continue
        boxes = []
        for j in range(sub.shape[0]):
            row = sub[j]
            edges = np.flatnonzero(np.diff(np.r_[0, row.astype(np.int8), 0]))
            for x0, x1 in zip(edges[::2], edges[1::2]):
                boxes.append(sbox(sl[1].start + x0, sl[0].start + j, sl[1].start + x1, sl[0].start + j + 1))
        g = shapely_px_to_map(unary_union(boxes), M).simplify(simplify_m)
        for p in (g.geoms if isinstance(g, MultiPolygon) else [g]):
            if isinstance(p, Polygon) and p.area >= min_m2:
                out.append(p)
    return out


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


def ground_fit(area_poly, building_polys, mode):
    """The ground's surface in the grounds: coefficients of c0 + c1 u + c2 v + c3 u2 + c4 uv + c5 v2 (u, v: (x, y) -
    origin, in hundreds of m), fitted to the LiDAR ground off the buildings (outliers dropped); "flat": its median."""
    minx, miny, maxx, maxy = area_poly.bounds
    xs, ys, z = heights_grid((minx, miny, maxx, maxy))
    X, Y = np.meshgrid(xs, ys)
    im = Image.new("L", (len(xs), len(ys)), 0)
    d = ImageDraw.Draw(im)
    tx = lambda p: ((p[0] - xs[0]) / (xs[1] - xs[0]), (p[1] - ys[0]) / (ys[1] - ys[0]))
    d.polygon([tx(p) for p in area_poly.exterior.coords], fill=1)
    for b in building_polys:
        d.polygon([tx(p) for p in b.exterior.coords], fill=0)
    keep = np.array(im, dtype=bool)
    c = area_poly.centroid
    origin = [round(c.x, 2), round(c.y, 2)]
    u, v, h = (X[keep] - c.x) / 100.0, (Y[keep] - c.y) / 100.0, z[keep]
    if mode == "flat":
        return origin, [float(np.median(h)), 0, 0, 0, 0, 0], 0.0
    ok = np.ones(len(h), bool)
    for _ in range(4):
        A = np.c_[np.ones(ok.sum()), u[ok], v[ok], u[ok] ** 2, u[ok] * v[ok], v[ok] ** 2]
        coef, *_ = np.linalg.lstsq(A, h[ok], rcond=None)
        r = h - np.c_[np.ones(len(h)), u, v, u ** 2, u * v, v ** 2] @ coef
        mad = np.median(np.abs(r[ok])) + 1e-3
        ok = np.abs(r) < 3.0 * mad + 0.3
    return origin, [round(float(c), 4) for c in coef], float(np.sqrt(np.mean(r[ok] ** 2)))


def _b64(a):
    return base64.b64encode(zlib.compress(np.ascontiguousarray(a, np.uint8).tobytes(), 9)).decode()


def grid(area, meadows, paths, grass, blend, cell=1.0):
    """The game's lookups over the grounds, `cell` m, row 0 north (scripts/restyle/): the ground's kind (0 out, 1 lawn,
    2 meadow, 3 path) and the smoothing's weight (0..255: 0 at the outline, 255 from `blend` m in)."""
    minx, miny, maxx, maxy = Polygon(area).bounds
    gw, gh = int(np.ceil((maxx - minx) / cell)) + 1, int(np.ceil((maxy - miny) / cell)) + 1
    g = lambda pts: [((p[0] - minx) / cell, (maxy - p[1]) / cell) for p in pts]

    def mask(polys, holes=()):
        im = Image.new("L", (gw, gh), 0)
        d = ImageDraw.Draw(im)
        for q in polys:
            d.polygon(g(q), fill=1)
        for q in holes:
            d.polygon(g(q), fill=0)
        return np.array(im, dtype=bool)
    inside = mask([area])
    kind = np.where(inside, 2 if grass == "meadow" else 1, 0).astype(np.uint8)
    kind[mask(meadows) & inside] = 2
    on_path = np.zeros_like(inside)
    for pa in paths:
        on_path |= mask([pa["pts"]], pa.get("holes", []))
    kind[on_path & inside] = 3
    t = np.clip(ndi.distance_transform_edt(inside) * cell / blend, 0.0, 1.0)
    weight = np.round(t * t * (3.0 - 2.0 * t) * 255.0)
    return {"origin": [round(minx, 2), round(maxy, 2)], "cell": cell, "w": gw, "h": gh, "kind": _b64(kind),
            "weight": _b64(weight)}


def tris_of(p):
    """A polygon (holes kept) as a flat list of triangles' points (constrained Delaunay)."""
    out = []
    for t in constrained_delaunay_triangles(p).geoms:
        if p.contains(t.representative_point()):
            out.extend([[round(c[0], 2), round(c[1], 2)] for c in list(t.exterior.coords)[:3]])
    return out


def read(spec, world, image, pairs, meadow_px=None, flatten="smooth", grass="mowed", dark=0.43, debug=None):
    M, Mi, res, mpp = fit(pairs)
    img = np.asarray(Image.open(image).convert("RGB"), dtype=np.float32) / 255.0
    Hh, Ww = img.shape[:2]
    hue, sat, val = hsv(img)
    red = (img[..., 0] > 0.55) & (img[..., 1] < 0.35) & (img[..., 2] < 0.35)
    if red.sum() > 500:
        # the grounds: inside the red outline drawn on the image (the spec's area becomes it)
        inside = ndi.binary_fill_holes(ndi.binary_dilation(red, iterations=2)) & ~ndi.binary_dilation(red, iterations=4)
        best = max(mask_polys(inside, M, mpp, 100.0, 1.0), key=lambda q: q.area)
        spec["site"]["area"] = [[round(c[0], 2), round(c[1], 2)] for c in list(best.exterior.coords)[:-1]]
    area = spec["site"]["area"]
    area_poly = Polygon(area)
    inside = raster((Ww, Hh), [[area]], Mi)
    blds = []
    for b in world["buildings"]:
        ring = b["rings"][0]
        if Polygon(ring).intersects(area_poly):
            blds.append(b["rings"])
    braw = raster((Ww, Hh), blds, Mi)
    bmask = ndi.binary_dilation(braw, iterations=2)
    # the map's marks drawn on the image: red, pink, purple lines and pins
    marks = ndi.binary_dilation(red | (((hue > 280) | (hue < 15)) & (sat > 0.2) & (val > 0.45)), iterations=3)
    valid = inside & ~bmask & ~marks
    rough = np.sqrt(np.maximum(ndi.uniform_filter(val ** 2, 5) - ndi.uniform_filter(val, 5) ** 2, 0))   # (texture)
    # canopy: dark, green to blue-green (aerial tints); none within 6 m of a building (its shadow)
    shade = ndi.distance_transform_edt(~braw) * mpp < 6.0
    canopy = valid & (val < dark) & (sat > 0.16) & (hue >= 80) & (hue <= 235) & ~shade
    # paths: light and smooth (dry grass is light but rough)
    path = valid & (val > 0.66) & (sat < 0.14) & (rough < 0.12)
    canopy = ndi.binary_closing(ndi.binary_opening(canopy, iterations=1), iterations=1)
    # paths: their broken bits joined, text and specks dropped, the small holes in them (cars, signs) filled
    path = ndi.binary_opening(ndi.binary_closing(path, iterations=2), iterations=1)
    holes, nh = ndi.label(~path)
    sizes = ndi.sum(np.ones_like(holes), holes, range(1, nh + 1)) * mpp * mpp
    path |= np.isin(holes, np.flatnonzero(sizes < 25.0) + 1)
    # trees and hedges
    dist = ndi.distance_transform_edt(canopy)
    peaks = (dist == ndi.maximum_filter(dist, size=7)) & (dist >= 2.0)
    lab, n = ndi.label(canopy)
    trees, hedges = [], []
    for k, sl in enumerate(ndi.find_objects(lab), start=1):
        sub = lab[sl] == k
        area_m2 = sub.sum() * mpp * mpp
        if area_m2 < 4.0:
            continue
        yy, xx = np.nonzero(sub)
        pts = np.c_[xx + sl[1].start, yy + sl[0].start].astype(float)
        cov = np.cov(pts.T) if len(pts) > 2 else np.eye(2)
        ev, evec = np.linalg.eigh(cov)
        length = 4.0 * np.sqrt(max(ev[1], 1e-6)) * mpp
        thick = area_m2 / max(length, 1e-6)
        if length > 12.0 and thick < 4.5:
            ax = evec[:, 1]
            t = (pts - pts.mean(0)) @ ax
            nrm = np.array([-ax[1], ax[0]])
            line = []
            for b0 in np.arange(t.min(), t.max() + 1e-6, 3.0 / mpp):
                sel = (t >= b0) & (t < b0 + 3.0 / mpp)
                if sel.sum() >= 2:
                    c = pts[sel].mean(0)
                    line.append(np.r_[c, 1.0] @ M)
            if len(line) >= 2:
                hedges.append({"pts": [[round(float(p[0]), 2), round(float(p[1]), 2)] for p in line],
                               "w": round(float(np.clip(thick, 1.0, 3.0)), 2), "h": 1.8})
            continue
        cand = [(float(dist[y, x]), x, y) for y, x in zip(*np.nonzero(peaks[sl] & sub))]
        cand = [(d, x + sl[1].start, y + sl[0].start) for d, x, y in cand]
        if not cand:
            cy, cx = pts[:, 1].mean(), pts[:, 0].mean()
            cand = [(float(np.sqrt(len(pts) / np.pi)), cx, cy)]
        chosen = []
        for d, x, y in sorted(cand, reverse=True):
            if all(np.hypot(x - x2, y - y2) > 0.8 * (d + d2) for d2, x2, y2 in chosen):
                chosen.append((d, x, y))
        for d, x, y in chosen:
            m = np.r_[x, y, 1.0] @ M
            trees.append([round(float(m[0]), 2), round(float(m[1]), 2), round(float(np.clip(d * mpp, 1.2, 8.0)), 2)])
    # paths: polygons with their holes, and their triangles
    paths = []
    for p in mask_polys(path, M, mpp, 20.0, 0.5):
        tris = tris_of(p)
        paths.append({"material": "concrete", "kind": "garden",
                      "pts": [[round(c[0], 2), round(c[1], 2)] for c in list(p.exterior.coords)[:-1]],
                      "holes": [[[round(c[0], 2), round(c[1], 2)] for c in list(h.coords)[:-1]] for h in p.interiors],
                      "tris": tris})
    meadows = []
    if meadow_px:
        q = [tuple(float(v) for v in s.split(",")) for s in meadow_px.split()]
        meadows.append([[round(float(c[0]), 2), round(float(c[1]), 2)] for c in (np.c_[np.array(q), np.ones(len(q))] @ M)])
    if meadows:                                  # (no paths in the meadows: light bare ground there)
        mz = [Polygon(m) for m in meadows]
        paths = [p for p in paths if not any(m.contains(Polygon(p["pts"]).representative_point()) for m in mz)]
    garden = {"image": os.path.relpath(image, ROOT).replace("\\", "/"), "pairs": pairs, "grass": grass,
              "trees_mode": "replace", "hedges_mode": "replace", "trees": trees, "hedges": hedges, "meadows": meadows}
    if flatten != "none":
        origin, coef, rms = ground_fit(area_poly, [Polygon(r[0]) for r in blds], flatten)
        garden["flatten"] = {"mode": flatten, "poly": area, "origin": origin, "coef": coef, "blend": 8.0}
        garden["flatten_rms"] = round(rms, 2)
    garden["grid"] = grid(area, meadows, paths, grass, 8.0)
    if debug:
        dbg = (img * 0.35 * 255).astype(np.uint8)
        dbg[path] = [235, 235, 235]
        dbg[canopy] = [30, 110, 40]
        dbg[~valid] = (dbg[~valid] * 0.4).astype(np.uint8)
        im = Image.fromarray(dbg)
        d = ImageDraw.Draw(im)
        for x, y, r in trees:
            cx, cy = to_px([[x, y]], Mi)[0]
            rr = r / mpp
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(255, 60, 60))
        for hd in hedges:
            d.line(to_px(hd["pts"], Mi), fill=(255, 0, 255), width=3)
        for mz in meadows:
            d.polygon(to_px(mz, Mi), outline=(255, 220, 0))
        im.save(debug)
    return garden, paths, res
