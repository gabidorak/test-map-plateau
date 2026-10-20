"""Review images of the railway, written by build_rail.py into tools/rail/review/ (Pillow):
- rail.png: the line in three strips over the toy ground map (the pipeline's ground pieces in their palette colours,
  buildings, trees): the reshaped zones (trackbed, platforms, slopes, wall landings, stairwells, the road's open
  trench), retaining walls (red), tracks, structures, signals, catenary portals, trees removed (red crosses), props
  moved (blue arrows) or dropped (red squares);
- station.png: Gare de Lozère at 0.12 m per pixel, same layers; station_<name>.png the stations on to Massy-Palaiseau;
- rail_massy.png: the line on to Massy-Palaiseau (per 700 m) and the station yard there;
- profile.png: long section along the line, x east: the LiDAR trackbed samples (grey: rejected), the rail level
  designed, the ground 8 m either side of the centreline, grade breaks and structures;
- sections.png: cross-sections every 100 m inside the map: LiDAR ground (grey) and the designed ground (black),
  rails, walls.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import railgeo as rg

ZONE_COLOURS = {"trackbed": (120, 112, 104), "platform": (70, 74, 82), "slope": (196, 170, 120),
                "landing": (170, 150, 120), "platform_blend": (150, 150, 140), "stairwell": (230, 120, 40),
                "road_trench": (240, 160, 40), "island": (60, 64, 110), "yard": (140, 120, 104)}


def _font(size):
    for f in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _hex(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def _light(c, k=0.55):
    return tuple(int(255 - (255 - v) * k) for v in c)


class Plan:
    def __init__(self, x0, x1, y0, y1, res):
        self.x0, self.x1, self.y0, self.y1, self.res = x0, x1, y0, y1, res
        self.img = Image.new("RGB", (int((x1 - x0) / res), int((y1 - y0) / res)), (255, 255, 255))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def P(self, p):
        return ((p[0] - self.x0) / self.res, (self.y1 - p[1]) / self.res)

    def visible(self, pts):
        pts = np.asarray(pts)
        return not (pts[:, 0].max() < self.x0 or pts[:, 0].min() > self.x1 or pts[:, 1].max() < self.y0
                    or pts[:, 1].min() > self.y1)


def _draw_plan(pl: Plan, rail: dict, world: dict, removed: set, font):
    d = pl.d
    pal = world["palette"]["ground"]
    for g in world["ground"]:
        ring = g["rings"][0]
        if not pl.visible(ring):
            continue
        col = _light(_hex(pal.get(g["material"], "#909090")), 0.5)
        d.polygon([pl.P(p) for p in ring], fill=col)
        for h in g["rings"][1:]:
            d.polygon([pl.P(p) for p in h], fill=(255, 255, 255))
    for b in world["buildings"]:
        ring = b["rings"][0]
        if pl.visible(ring):
            d.polygon([pl.P(p) for p in ring], fill=(205, 198, 220), outline=(120, 110, 140))
    for z in rail["zones"]:
        col = ZONE_COLOURS.get(z["kind"], (200, 0, 200))
        for poly in z["polygons"]:
            if pl.visible(poly[0]):
                d.polygon([pl.P(p) for p in poly[0]], fill=col + (150,), outline=col + (255,))
                for h in poly[1:]:
                    d.polygon([pl.P(p) for p in h], fill=(255, 255, 255, 120))
    for w in rail["earthworks"]["walls"]:
        if pl.visible(w["pts"]):
            d.line([pl.P(p) for p in w["pts"]], fill=(220, 20, 20), width=max(2, int(0.6 / pl.res)))
    for f in world["fences"]:
        if pl.visible(f["pts"]):
            d.line([pl.P(p) for p in f["pts"]], fill=(200, 0, 200), width=1)
    for t in world["trees"]:
        if pl.x0 < t["x"] < pl.x1 and pl.y0 < t["y"] < pl.y1:
            c = pl.P((t["x"], t["y"]))
            if t["id"] in removed:
                r = 3
                d.line([(c[0] - r, c[1] - r), (c[0] + r, c[1] + r)], fill=(230, 0, 0), width=2)
                d.line([(c[0] - r, c[1] + r), (c[0] + r, c[1] - r)], fill=(230, 0, 0), width=2)
            else:
                r = t["r"] / pl.res
                d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=(40, 120, 40, 160))
    A = rg.Alignment(rail["alignment"])
    for t in rail.get("yard", {}).get("tracks", []):        # the yard's tracks (tools/rail/yard.py)
        pts = np.asarray(t["pts"])
        if pl.visible(pts):
            d.line([pl.P(q) for q in pts[::2]], fill=(20, 20, 20) if t["rer"] else (90, 90, 90),
                   width=2 if t["main"] else 1)
    sp = rail["alignment"]["spacing"]
    for off in (-sp / 2, sp / 2):
        for gauge in (-0.7175, 0.7175):
            pts = A.point(A.s, np.full(len(A.s), off + gauge))
            d.line([pl.P(p) for p in pts], fill=(30, 30, 30), width=1)
    for fb in rail["footbridges"]:
        d.line([pl.P(p) for p in fb["deck"]], fill=(0, 190, 230), width=max(3, int(fb["width"] / pl.res)))
        for f in fb["flights"]:
            d.line([pl.P(p) for p in f["pts"]], fill=(0, 140, 200), width=max(2, int(f["width"] / pl.res)))
    for up in rail["underpasses"]:
        for p in up["passages"]:
            d.line([pl.P(q) for q in p["pts"]], fill=(240, 120, 0, 200), width=max(2, int(up["width"] / pl.res)))
        for f in up["stairwells"] + up["stairs_up"]:
            d.line([pl.P(q) for q in f["pts"]], fill=(180, 60, 0), width=max(2, int(f["width"] / pl.res)))
    rt = rail["road_tunnel"]
    if rt:
        t = np.asarray(rt["t"])
        a, b = rt["covered"]
        pts = np.asarray(rt["pts"])
        cov = (t >= a) & (t <= b)
        d.line([pl.P(p) for p in pts[cov]], fill=(255, 140, 0, 120), width=max(3, int(rt["width"] / pl.res)))
        d.line([pl.P(p) for p in pts], fill=(120, 60, 0), width=1)
    for s in rail["catenary"]["supports"]:
        m = s["masts"]
        if pl.visible([m[0][:2], m[1][:2]]):
            d.line([pl.P(m[0][:2]), pl.P(m[1][:2])], fill=(90, 90, 160, 200), width=1)
            for q in m:
                c = pl.P(q[:2])
                d.rectangle([c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2], fill=(60, 60, 140))
    for sg in rail["signals"]:
        q = A.point(sg["s"], sg["u"])
        if pl.x0 < q[0] < pl.x1 and pl.y0 < q[1] < pl.y1:
            c = pl.P(q)
            col = {"FR:S": (220, 0, 0), "FR:CARRE": (160, 0, 120), "FR:A": (230, 170, 0)}.get(sg["kind"], (90, 90, 90))
            d.ellipse([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], fill=col, outline=(0, 0, 0))
            d.text((c[0] + 5, c[1] - 6), "%s %s%s" % (sg["kind"].replace("FR:", ""), sg["ref"], ">" if sg["facing"] > 0
                                                         else "<"), fill=(0, 0, 0), font=font)
    for it in rail["station"]["furniture"]:
        if pl.x0 < it["x"] < pl.x1 and pl.y0 < it["y"] < pl.y1:
            c = pl.P((it["x"], it["y"]))
            d.ellipse([c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2], fill=(0, 90, 160))
    props = {p["id"]: p for p in world["props"]}
    for c in rail["clearance"]["props"]:
        p = props.get(c["id"])
        if p is None or not (pl.x0 < p["x"] < pl.x1 and pl.y0 < p["y"] < pl.y1):
            continue
        a = pl.P((p["x"], p["y"]))
        if c["action"] == "moved":
            b = pl.P(c["to"])
            d.line([a, b], fill=(0, 60, 230), width=2)
            d.ellipse([b[0] - 3, b[1] - 3, b[0] + 3, b[1] + 3], fill=(0, 60, 230))
        elif c["action"] == "dropped":
            d.rectangle([a[0] - 3, a[1] - 3, a[0] + 3, a[1] + 3], outline=(230, 0, 0), width=2)
    for end, q in rail["landing"].items():
        if pl.x0 < q["x"] < pl.x1:
            c = pl.P((q["x"], q["y"]))
            d.polygon([(c[0], c[1] - 7), (c[0] - 5, c[1] + 4), (c[0] + 5, c[1] + 4)], fill=(0, 170, 0))
    step = 50 if pl.res > 0.2 else 10
    for gx in range(int(math.ceil(pl.x0 / step)) * step, int(pl.x1) + 1, step):
        d.line([pl.P((gx, pl.y0)), pl.P((gx, pl.y1))], fill=(0, 0, 0, 40))
        d.text(pl.P((gx + 0.5, pl.y1 - 0.5)), str(gx), fill=(0, 0, 0), font=font)
    for gy in range(int(math.ceil(pl.y0 / step)) * step, int(pl.y1) + 1, step):
        d.line([pl.P((pl.x0, gy)), pl.P((pl.x1, gy))], fill=(0, 0, 0, 40))
        d.text(pl.P((pl.x0 + 0.5, gy + 0.5)), str(gy), fill=(0, 0, 0), font=font)


def draw(rail: dict, world: dict, H) -> None:
    out = rg.TOOLS / "review"
    out.mkdir(parents=True, exist_ok=True)
    font = _font(13)
    removed = {t["id"] for t in rail["clearance"]["trees"]}
    # the line in three strips
    strips = [(-260.0, 440.0), (430.0, 1130.0), (1120.0, 1820.0)]
    A = rg.Alignment(rail["alignment"])
    res = 0.4
    tiles = []
    for x0, x1 in strips:
        m = (A.pts[:, 0] > x0) & (A.pts[:, 0] < x1)
        yc = float(np.mean(A.pts[m, 1]))
        pl = Plan(x0, x1, yc - 70.0, yc + 70.0, res)
        _draw_plan(pl, rail, world, removed, font)
        tiles.append(pl.img)
    img = Image.new("RGB", (max(t.width for t in tiles), sum(t.height for t in tiles) + 10 * len(tiles)), (255, 255, 255))
    y = 0
    for t in tiles:
        img.paste(t, (0, y))
        y += t.height + 10
    img.save(out / "rail.png")
    # the line on to Massy (2026-10-18): per 700 m of alignment, its box; then the yard
    tiles = []
    for s0 in range(2600, int(A.length), 700):
        m = (A.s >= s0) & (A.s < s0 + 700)
        p = A.pts[m]
        pl = Plan(float(p[:, 0].min()) - 60, float(p[:, 0].max()) + 60, float(p[:, 1].min()) - 60,
                  float(p[:, 1].max()) + 60, 0.5)
        _draw_plan(pl, rail, world, removed, font)
        tiles.append(pl.img)
    pl = Plan(4000.0, 4800.0, 850.0, 1700.0, 0.6)
    _draw_plan(pl, rail, world, removed, font)
    tiles.append(pl.img)
    row_w = sum(t.width for t in tiles) + 10 * len(tiles)
    img = Image.new("RGB", (row_w, max(t.height for t in tiles)), (255, 255, 255))
    x = 0
    for t in tiles:
        img.paste(t, (x, 0))
        x += t.width + 10
    img.save(out / "rail_massy.png")
    pl = Plan(790.0, 1110.0, -900.0, -760.0, 0.12)
    _draw_plan(pl, rail, world, removed, _font(14))
    pl.img.save(out / "station.png")
    for name, box_ in (("palaiseau_villebon", (2690.0, 2860.0, -760.0, -420.0)), ("palaiseau", (3240.0, 3520.0, 190.0, 560.0)),
                       ("massy_palaiseau", (4250.0, 4620.0, 1100.0, 1480.0))):
        pl = Plan(*box_, 0.2)
        _draw_plan(pl, rail, world, removed, _font(14))
        pl.img.save(out / ("station_%s.png" % name))
    _profile(rail, H, out / "profile.png", font)
    _sections(rail, H, out / "sections.png", font)
    print("review: %s" % ", ".join(str((out / f).relative_to(rg.ROOT)) for f in ("rail.png", "rail_massy.png", "station.png",
                                                                                  "profile.png", "sections.png")))


def _profile(rail: dict, H, path, font):
    A = rg.Alignment(rail["alignment"])
    box = rail["box"]
    m = (A.pts[:, 0] > box[0]) & (A.pts[:, 0] < box[2])
    s = A.s[m]
    x = A.pts[m, 0]
    W, Hh = 2400, 700
    z_rail = A.z[m]
    gl = H.at(*A.point(s, np.full(len(s), 8.0)).T)
    gr = H.at(*A.point(s, np.full(len(s), -8.0)).T)
    lid = np.asarray(rail["profile"]["lidar"])
    zmin = float(min(z_rail.min(), gl.min(), gr.min())) - 1.0
    zmax = float(max(z_rail.max(), gl.max(), gr.max())) + 1.0
    img = Image.new("RGB", (W, Hh), (255, 255, 255))
    d = ImageDraw.Draw(img, "RGBA")
    X = lambda v: 60 + (v - box[0]) / (box[2] - box[0]) * (W - 80)
    Z = lambda v: Hh - 40 - (v - zmin) / (zmax - zmin) * (Hh - 80)
    for zz in range(int(math.ceil(zmin)), int(zmax) + 1):
        d.line([(60, Z(zz)), (W - 20, Z(zz))], fill=(0, 0, 0, 25))
        d.text((5, Z(zz) - 7), "%d" % zz, fill=(0, 0, 0), font=font)
    for xx in range(int(math.ceil(box[0] / 100)) * 100, int(box[2]) + 1, 100):
        d.line([(X(xx), 40), (X(xx), Hh - 40)], fill=(0, 0, 0, 25))
        d.text((X(xx) - 12, Hh - 30), "x %d" % xx, fill=(0, 0, 0), font=font)
    d.line([(X(a), Z(b)) for a, b in zip(x, gl)], fill=(80, 160, 80), width=1)
    d.line([(X(a), Z(b)) for a, b in zip(x, gr)], fill=(160, 110, 60), width=1)
    for row in lid:
        q = A.point(row[0], 0.0)
        c = (X(q[0]), Z(row[1] + rail["profile"]["ballast_top_to_rail"]))
        d.ellipse([c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2], fill=(40, 40, 40) if row[2] > 0 else (190, 190, 190))
    d.line([(X(a), Z(b)) for a, b in zip(x, z_rail)], fill=(220, 0, 0), width=2)
    for p, g in zip(rail["profile"]["pvis"][1:-1], rail["profile"]["grades"][1:]):
        q = A.point(p[0], 0.0)
        if box[0] < q[0] < box[2]:
            d.line([(X(q[0]), Z(p[1]) - 30), (X(q[0]), Z(p[1]) + 30)], fill=(220, 0, 0))
            d.text((X(q[0]) + 3, Z(p[1]) - 44), "%+.1f‰" % g, fill=(200, 0, 0), font=font)
    for kind, items in (("footbridge", rail["footbridges"]), ("underpass", rail["underpasses"])):
        for it in items:
            q = A.point(it["s"], 0.0)
            d.text((X(q[0]) - 20, 10), kind, fill=(0, 100, 180), font=font)
            d.line([(X(q[0]), 25), (X(q[0]), Hh - 40)], fill=(0, 100, 180, 80))
    for p in rail["platforms"]:
        a, b = A.point(p["s0"], 0.0)[0], A.point(p["s1"], 0.0)[0]
        d.rectangle([X(a), 30, X(b), 36], fill=(60, 60, 70))
        d.text((X(a), 38), p["id"], fill=(0, 0, 0), font=font)
    d.text((70, Hh - 18), "red: rail level designed · dots: LiDAR trackbed (+ballast top to rail; grey rejected) · "
           "green: ground 8 m north · brown: 8 m south", fill=(0, 0, 0), font=font)
    img.save(path)


def _sections(rail: dict, H, path, font):
    A = rg.Alignment(rail["alignment"])
    ew = rail["earthworks"]
    design = rg.Design(ew, A, H, [z for z in rail["zones"] if "axis" in z])
    box = rail["box"]
    ss = [s for s in range(int(ew["s0"]) + 50, int(ew["s0"]) + len(ew["formation"]) - 1, 100)]
    cols = 4
    cw, ch = 520, 220
    rows = math.ceil(len(ss) / cols)
    img = Image.new("RGB", (cols * cw, rows * ch), (255, 255, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for k, s in enumerate(ss):
        ox, oy = (k % cols) * cw, (k // cols) * ch
        us = np.arange(-25.0, 25.01, 0.25)
        q = A.point(np.full(len(us), float(s)), us)
        g0 = H.at(q[:, 0], q[:, 1])
        g1 = np.array([design.z_or_ground(float(s), float(u), p) for u, p in zip(us, q)])
        zr = float(A.level(s))
        zc = zr - 1.0
        sc = 9.0
        X = lambda u: ox + cw / 2 + u * sc
        Z = lambda z: oy + ch / 2 - (z - zc) * sc
        d.line([(X(u), Z(z)) for u, z in zip(us, g0)], fill=(170, 170, 170), width=1)
        d.line([(X(u), Z(z)) for u, z in zip(us, g1)], fill=(0, 0, 0), width=2)
        sp = rail["alignment"]["spacing"]
        for off in (-sp / 2, sp / 2):
            for gg in (-0.7175, 0.7175):
                d.rectangle([X(off + gg) - 1, Z(zr) - 1, X(off + gg) + 1, Z(zr) + 1], fill=(220, 0, 0))
        x = A.point(float(s), 0.0)
        d.text((ox + 5, oy + 5), "s %d (x %.0f) N ->" % (s, x[0]), fill=(0, 0, 0), font=font)
        d.rectangle([ox, oy, ox + cw - 1, oy + ch - 1], outline=(200, 200, 200))
    img.save(path)
