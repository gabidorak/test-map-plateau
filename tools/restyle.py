#!/usr/bin/env python3
"""Restyled buildings: a building of the map redrawn with real facades by godot/scripts/restyle/restyle.gd, after a spec
in godot/data/restyle/<slug>.json. The method, for any large building (a school, a campus, offices):

  1. python3 tools/restyle.py init <num or osm id> <slug> [--preset <style>] [--no-site]
       the spec from the map: the footprint (with its courtyards), the roof's triangles, the height, the storeys, a style
       guessed from the map's (or a preset of the library), the paths of its grounds
     python3 tools/restyle.py site <slug> --area "x,y x,y ..."
       grounds alone (several buildings sharing them: give them --no-site)
     python3 tools/restyle.py px2map --pairs "px,py=mx,my ..." --pts "px,py ..."
       points of an aerial image (a screenshot) on the map: an affine fit on known points (buildings' corners, centres)
     python3 tools/restyle.py garden <slug> --image <aerial.png> --pairs "px,py=mx,my ..." [--meadow-px ...]
       its grounds read off an aerial image: trees, hedges, paths, lawn / meadow, the ground smoothed (restyle_garden.py)
  0. first ASK Thomas: is the ground flat (smooth / flat / natural)? the grass mown (everywhere, a meadow where)? the
     trees: from the aerial image, the map's plus the missing ones, or the map's? hedges and paths: from the image?
  2. edit the spec's "style" from photos (the fill of each storey, the bay, the frame, louvres, fins, ledges, a skin...)
     and its "site" (the grounds' outline, raised walks). New materials and styles: godot/data/restyle/_library.json
     ("materials", "styles" presets), new textures: godot/scripts/restyle/restyle_textures.gd, new kinds of storey: a
     method _fill_<type> in restyle.gd
  3. rebuild the map (godot --headless --path godot --script res://tools/build_world.gd): the map's building leaves it
  4. look: CAP_X/CAP_Y/CAP_R/CAP_OUT ... godot --path godot --script res://tools/capture_site.gd -- --online-test

The style's keys are described in restyle.gd.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "godot", "world", "world.json")
OUT = os.path.join(ROOT, "godot", "data", "restyle")
PATH_KINDS = {"path", "footway", "sidewalk", "pedestrian", "cycleway", "steps", "track", "bridleway"}


def r2(p):
    return [round(p[0], 2), round(p[1], 2)]


def inside(p, poly):
    x, y = p
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[i - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def paths_in(w, area):
    """The map's paths (ground pieces) with a point in the area."""
    out = []
    for piece in w["ground"]:
        if piece["kind"] not in PATH_KINDS or piece["material"] == "asphalt" or not piece["rings"]:
            continue
        ring = piece["rings"][0]
        if any(inside(p, area) for p in ring):
            out.append({"material": piece["material"], "kind": piece["kind"], "pts": [r2(p) for p in ring]})
    return out


def roof_of(rings):
    """The roof over the footprint (its courtyards open): points and triangles (constrained Delaunay)."""
    from shapely import Polygon, constrained_delaunay_triangles
    poly = Polygon(rings[0], rings[1:])
    pts, index, tris = [], {}, []
    for t in constrained_delaunay_triangles(poly).geoms:
        if not poly.contains(t.representative_point()):
            continue
        for p in list(t.exterior.coords)[:3]:
            key = (round(p[0], 2), round(p[1], 2))
            if key not in index:
                index[key] = len(pts)
                pts.append(list(key))
            tris.append(index[key])
    return pts, tris


def write(slug, spec, force):
    path = os.path.join(OUT, slug + ".json")
    if os.path.exists(path) and not force:
        sys.exit("%s exists (--force overwrites it)" % path)
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(dumps(spec))
    return path


def dumps(spec):
    """JSON, indented, its lists of numbers (points, triangles) on one line each."""
    txt = json.dumps(spec, ensure_ascii=False, indent=1)
    return re.sub(r"\[\s+([-\d.eE,\s]+?)\s+\]", lambda m: "[" + ", ".join(v.strip() for v in m.group(1).split(",")) + "]",
                  txt) + "\n"


def cmd_init(a, w):
    key = a.building.lstrip("#")
    found = [b for b in w["buildings"] if str(b.get("num")) == key or b["id"].split("_rest")[0] == key]
    if not found:
        sys.exit("no building %s in the map (dropped already? specs in %s leave it when the map is built)" % (a.building, OUT))
    base = found[0]["id"].split("_rest")[0]
    b = found[0]
    rings = [[r2(p) for p in ring] for ring in b["rings"]]
    roof_pts, roof_tris = roof_of(rings)
    hs = b.get("heights", {})
    height = float(a.height or hs.get("bdtopo") or b["height"])
    style = b["toy"]["style"]
    levels = int(a.storeys or b["facade"].get("levels") or style.get("levels") or max(1, round(height / 3.3)))
    g = min(max(float(style.get("g", 4.4)), 3.5), 5.0) if levels > 1 else height - 0.8   # (the map's can be odd)
    f = (height - g - 1.0) / max(1, levels - 1)
    curtain = "curtain" in style.get("names", [])
    xs = [p[0] for p in rings[0]]
    ys = [p[1] for p in rings[0]]
    m = a.margin
    box = [min(xs) - m, min(ys) - m, max(xs) + m, max(ys) + m]
    area = [[box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]]]
    st = {"preset": a.preset} if a.preset else {
        "fill": ["curtain"] * levels if curtain else ["punched"] * levels,
        "bay": 1.8 if curtain else 2.7,
        "inset": 0.3 if curtain else 0.0,
        "wall": b["facade"]["color"],
        "frame": {},
    }
    spec = {
        "name": b.get("name") or "#%s" % b.get("num"),
        "num": b.get("num"),
        "replace": [base],
        "height": round(height, 2),
        "storeys": [round(g, 2)] + [round(f, 2)] * (levels - 1),
        "style": st,
        "rings": rings,
        "roof": {"pts": roof_pts, "tris": roof_tris, "colour": b["roof"]["color"]},
        "site": {} if a.no_site else {"area": [r2(p) for p in area], "paths": paths_in(w, area), "walks": []},
    }
    path = write(a.slug, spec, a.force)
    print("%s: %s, %d storeys, %.1f m, %d ring(s), %d path(s)" % (path, spec["name"], levels, height, len(rings),
                                                                  len(spec["site"].get("paths", []))))


def cmd_site(a, w):
    area = [[float(v) for v in p.split(",")] for p in a.area.split()]
    spec = {"name": a.slug, "replace": [], "rings": [],
            "site": {"area": [r2(p) for p in area], "paths": paths_in(w, area), "walks": []}}
    path = write(a.slug, spec, a.force)
    print("%s: grounds, %d path(s)" % (path, len(spec["site"]["paths"])))


def cmd_roof(a, w):
    for slug in a.slugs:
        path = os.path.join(OUT, slug + ".json")
        spec = json.load(open(path, encoding="utf-8"))
        if not spec.get("rings"):
            continue
        spec["roof"]["pts"], spec["roof"]["tris"] = roof_of(spec["rings"])
        write(slug, spec, True)
        print("%s: roof of %d triangles" % (slug, len(spec["roof"]["tris"]) // 3))


def cmd_garden(a, w):
    import restyle_garden
    path = os.path.join(OUT, a.slug + ".json")
    spec = json.load(open(path, encoding="utf-8"))
    garden, paths, res = restyle_garden.read(spec, w, a.image, a.pairs, a.meadow_px, a.flatten, a.grass, a.dark,
                                             a.debug)
    spec["site"]["garden"] = garden
    spec["site"]["paths"] = (spec["site"].get("paths", []) if a.keep_map_paths else []) + paths
    write(a.slug, spec, True)
    print("%s: fit residuals %s m; %d trees, %d hedges, %d paths, %d meadow(s), ground %s (rms %s m)" % (
        a.slug, " ".join("%.2f" % r for r in res), len(garden["trees"]), len(garden["hedges"]), len(paths),
        len(garden["meadows"]), a.flatten, garden.get("flatten_rms", "-")))


def cmd_px2map(a):
    import numpy as np
    pairs = [p.split("=") for p in a.pairs.split()]
    px = np.array([[float(v) for v in s.split(",")] for s, _ in pairs])
    mp = np.array([[float(v) for v in t.split(",")] for _, t in pairs])
    A = np.c_[px, np.ones(len(px))]
    M, *_ = np.linalg.lstsq(A, mp, rcond=None)
    print("residuals (m):", " ".join("%.2f" % r for r in np.linalg.norm(A @ M - mp, axis=1)))
    pts = [[float(v) for v in p.split(",")] for p in a.pts.split()]
    print(" ".join("%.2f,%.2f" % tuple(np.r_[p, 1.0] @ M) for p in pts))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    ini = sub.add_parser("init", help="a building's spec from the map")
    ini.add_argument("building", help="its number (#996) or id (osm:r9921491)")
    ini.add_argument("slug")
    ini.add_argument("--preset", help="a style of the library (_library.json)")
    ini.add_argument("--height", type=float, help="m, ground floor to roof (default: the map's)")
    ini.add_argument("--storeys", type=int, help="how many (default: the map's)")
    ini.add_argument("--no-site", action="store_true", help="no grounds (another spec has them)")
    ini.add_argument("--margin", type=float, default=30.0, help="m round the footprint for the grounds (default 30)")
    ini.add_argument("--force", action="store_true", help="overwrite an existing spec")
    si = sub.add_parser("site", help="grounds alone, for several buildings")
    si.add_argument("slug")
    si.add_argument("--area", required=True, help='its outline, map points "x,y x,y ..."')
    si.add_argument("--force", action="store_true")
    ro = sub.add_parser("roof", help="a spec's roof again from its footprint")
    ro.add_argument("slugs", nargs="+")
    ga = sub.add_parser("garden", help="a spec's grounds read off an aerial image")
    ga.add_argument("slug")
    ga.add_argument("--image", required=True)
    ga.add_argument("--pairs", required=True, help='known points "px,py=mx,my ..." (3 or more)')
    ga.add_argument("--meadow-px", help='an outline "px,py ..." of meadow (tall grass); the rest is mown')
    ga.add_argument("--flatten", choices=["smooth", "flat", "none"], default="smooth")
    ga.add_argument("--grass", choices=["mowed", "meadow"], default="mowed", help="outside the meadows")
    ga.add_argument("--dark", type=float, default=0.43, help="canopy: brightness under this (default 0.43)")
    ga.add_argument("--keep-map-paths", action="store_true", help="the map's paths too")
    ga.add_argument("--debug", help="a PNG of what was read")
    px = sub.add_parser("px2map", help="aerial image points on the map (affine fit)")
    px.add_argument("--pairs", required=True, help='known points "px,py=mx,my ..." (3 or more)')
    px.add_argument("--pts", required=True, help='points to place "px,py ..."')
    a = ap.parse_args()
    if a.cmd == "px2map":
        cmd_px2map(a)
        return 0
    w = json.load(open(WORLD, encoding="utf-8"))
    {"init": cmd_init, "site": cmd_site, "roof": cmd_roof, "garden": cmd_garden}[a.cmd](a, w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
