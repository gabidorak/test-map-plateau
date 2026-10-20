"""Caravan camp: touring caravans (three sizes), their awning, a panel van, plastic garden set, rotary washing line,
water tank, generator, gas bottles and a kettle barbecue (the camp on the parking lot east of Télécom Paris, placed
by tools/camp/caravan_camp.py). Front = -Y (the drawbar of a caravan, the nose of the van), origin on the ground.
French caravans have their door on the right of the direction of travel, here the -X side."""
import math

import bmesh
from mathutils import Vector

from toylib import Model, matrix, rounded_rect

WINDOW = "#353b44"           # tinted acrylic caravan windows
FRAME = "#d9dbd8"            # window frames, seals
SKIRT = "#8c9198"            # lower body skirt of the caravans
TYRE = "rubber"


def round_corners(pts, radii, n=4) -> list:
    """Convex polygon with its own fillet radius at each corner (toylib.polygon_round with per-corner radii)."""
    out = []
    k = len(pts)
    for i in range(k):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % k])
        r = radii[i]
        if r <= 0:
            out.append(tuple(p1))
            continue
        a, b = (p0 - p1).normalized(), (p2 - p1).normalized()
        half = a.angle(b) / 2
        c = p1 + (a + b).normalized() * (r / math.sin(half))
        s, e = p1 + a * (r / math.tan(half)), p1 + b * (r / math.tan(half))
        v0, v1 = (s - c).normalized(), (e - c).normalized()
        out += [tuple(c + (v0 * (1 - t / n) + v1 * (t / n)).normalized() * r) for t in range(n + 1)]
    return out


def prism(m: Model, outline, width, color, mat="toy", at=(0, 0, 0), bevel=0.0, seg=2) -> Model:
    """Outline of (y, z) points extruded `width` across x, centred on x = 0, then moved to `at`."""
    bm = bmesh.new()
    a = [bm.verts.new((-width / 2, y, z)) for y, z in outline]
    b = [bm.verts.new((width / 2, y, z)) for y, z in outline]
    n = len(outline)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return m._add(bm, color, mat, matrix(at), bevel, seg)


def clip_band(outline, z0, z1) -> list:
    """The part of a convex (y, z) outline between heights z0 and z1 (Sutherland-Hodgman)."""
    def clip(pts, keep, cut):
        out = []
        for i in range(len(pts)):
            p, q = pts[i - 1], pts[i]
            if keep(q):
                if not keep(p):
                    out.append(cut(p, q))
                out.append(q)
            elif keep(p):
                out.append(cut(p, q))
        return out

    def at_z(z):
        return lambda p, q: (p[0] + (q[0] - p[0]) * (z - p[1]) / (q[1] - p[1]), z)
    pts = clip(list(outline), lambda p: p[1] >= z0, at_z(z0))
    return clip(pts, lambda p: p[1] <= z1, at_z(z1))


def inset(outline, d) -> list:
    """Convex outline pulled in by about d towards its centroid (decals that stay inside the body edges)."""
    cy = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    out = []
    for y, z in outline:
        v = Vector((y - cy, z - cz))
        out.append(tuple(Vector((cy, cz)) + v * max(v.length - d, 0.0) / max(v.length, 1e-6)))
    return out


def side_decal(m: Model, outline, half_w, color, mat="toy", t=0.012, sides=(-1, 1)) -> None:
    """A thin plate of the (y, z) outline on each body side wall at x = +-half_w."""
    for s in sides:
        prism(m, outline, t, color, mat, at=(s * (half_w + t / 2 - 0.003), 0, 0))


def side_window(m: Model, half_w, y, z, w, h, r=0.08, sides=(-1, 1), frame=FRAME) -> None:
    """Rounded tinted window centred on (y, z) of each side wall, in a light frame."""
    side_decal(m, rounded_rect(w + 0.08, h + 0.08, r + 0.04, 3, y, z), half_w, frame, sides=sides)
    side_decal(m, rounded_rect(w, h, r, 3, y, z), half_w + 0.01, WINDOW, sides=sides)


def wheel(m: Model, x, y, r, w, hub="silver") -> None:
    """Wheel on the x axis, outer face at x (sign = side)."""
    s = 1 if x > 0 else -1
    m.cyl(r, w, (x - s * w, y, r), TYRE, sides=14, bevel=0.03, rot=(0, s * 90, 0), seg=1)
    m.cyl(r * 0.62, 0.02, (x - s * 0.005, y, r), hub, sides=12, bevel=0.0, rot=(0, s * 90, 0))


def caravan_body(m: Model, outline, width, floor, axles, wheel_r, stripe, skirt_top, tint_top=None) -> None:
    """Shell, skirt, stripes, wheel arches and wheels, corner steadies shared by the caravans."""
    prism(m, outline, width, "white", bevel=0.05, seg=2)
    hw = width / 2
    side_decal(m, inset(clip_band(outline, floor - 0.01, skirt_top), 0.03), hw, SKIRT)
    z0, z1 = stripe
    side_decal(m, inset(clip_band(outline, z0, z1), 0.04), hw + 0.004, "white", "tint")
    if tint_top:
        side_decal(m, inset(clip_band(outline, *tint_top), 0.05), hw + 0.004, "white", "tint")
    for y in axles:
        arch = [(y + (wheel_r + 0.06) * math.cos(a), wheel_r + (wheel_r + 0.06) * math.sin(a))
                for a in (math.radians(d) for d in range(0, 181, 15))]
        side_decal(m, arch, hw + 0.008, "dark")
        for s in (-1, 1):
            wheel(m, s * (hw - 0.02), y, wheel_r, 0.2)
    ys = [p[0] for p in outline]
    for y in (min(ys) + 0.35, max(ys) - 0.3):
        for s in (-1, 1):
            m.box((0.06, 0.06, floor), (s * (hw - 0.25), y, 0), "silver", base=True, bevel=0.0)
            m.box((0.16, 0.16, 0.03), (s * (hw - 0.25), y, 0), "anthracite", base=True, bevel=0.0)
    m.box((width - 0.3, abs(max(ys) - min(ys)) - 0.4, 0.14), (0, (max(ys) + min(ys)) / 2, floor - 0.14), "dark",
          base=True, bevel=0.02)


def drawbar(m: Model, y_body, y_hitch, floor, cover="white") -> None:
    """A-frame drawbar from the body front to the hitch head, jockey wheel and a moulded front locker cover."""
    z = floor - 0.08
    for s in (-1, 1):
        m.tube([(s * 0.55, y_body + 0.3, z), (s * 0.12, y_hitch + 0.25, 0.42)], 0.045, "anthracite", sides=8)
    m.box((0.14, 0.4, 0.12), (0, y_hitch + 0.18, 0.37), "anthracite", base=True, bevel=0.03)
    m.sphere(0.07, (0, y_hitch, 0.45), "silver", seg=10, scale=(1, 1.3, 0.8))
    m.box((0.95, 0.75, 0.32), (0, y_body - 0.3, z), cover, base=True, bevel=0.12, seg=3)
    m.cyl(0.035, 0.5, (0.22, y_hitch + 0.55, 0.12), "silver", sides=10)
    m.cyl(0.09, 0.06, (0.22, y_hitch + 0.55, 0.09), TYRE, sides=12, bevel=0.015, rot=(0, 90, 0))
    m.cyl(0.05, 0.16, (0.22, y_hitch + 0.55, 0.62), "anthracite", sides=10, bevel=0.01)


def rear_end(m: Model, y_rear, width, floor, roof) -> None:
    """Lights, number plate and a window on the flat rear face (+Y)."""
    for s in (-1, 1):
        m.box((0.12, 0.03, 0.42), (s * (width / 2 - 0.12), y_rear + 0.01, floor + 0.12), "sign_red", base=True,
              bevel=0.012)
    m.box((0.52, 0.02, 0.11), (0, y_rear + 0.01, floor + 0.2), "sign_white", base=True, bevel=0.008)
    m.box((1.1, 0.03, 0.55), (0, y_rear + 0.005, roof - 1.15), FRAME, base=True, bevel=0.06, seg=3)
    m.box((1.0, 0.04, 0.47), (0, y_rear + 0.01, roof - 1.11), WINDOW, base=True, bevel=0.05, seg=3)


def caravan() -> Model:
    """Classic single-axle touring caravan, 5.8 m body (7.1 m with the drawbar), cream with a tinted stripe."""
    m = Model("caravan", view_range=350.0)
    W, F, R = 2.3, 0.42, 2.62
    out = round_corners([(-2.75, F), (2.9, F), (2.9, R - 0.02), (-2.45, R), (-2.95, 2.2), (-3.0, 1.1)],
                        [0.1, 0.1, 0.18, 0.4, 0.3, 0.25])
    caravan_body(m, out, W, F, [0.25], 0.3, (1.05, 1.22), 0.62)
    hw = W / 2
    side_window(m, hw, 1.75, 1.62, 1.05, 0.62)
    side_window(m, hw, -1.6, 1.62, 1.2, 0.62)
    side_window(m, hw, -0.2, 1.62, 0.8, 0.62, sides=(1,))
    # door on the -X side: frame, panel, small window, handle and a step
    side_decal(m, rounded_rect(0.68, 1.86, 0.08, 3, 0.55, 1.45), hw + 0.006, FRAME, sides=(-1,))
    side_decal(m, rounded_rect(0.6, 1.78, 0.06, 3, 0.55, 1.45), hw + 0.014, "white", sides=(-1,))
    side_window(m, hw + 0.02, 0.55, 1.95, 0.38, 0.45, r=0.06, sides=(-1,))
    m.box((0.04, 0.12, 0.04), (-hw - 0.03, 0.31, 1.3), "silver", bevel=0.01)
    m.box((0.36, 0.6, 0.05), (-hw - 0.2, 0.55, 0.22), "silver", base=True, bevel=0.015)
    m.box((0.05, 0.05, 0.22), (-hw - 0.2, 0.55, 0.0), "anthracite", base=True, bevel=0.01)
    # front window on the near-vertical nose, marker lamps, awning rail along the -X roof edge
    m.box((1.7, 0.04, 0.68), (0, -3.0, 1.33), FRAME, base=True, bevel=0.05, seg=3, rot=(-3, 0, 0))
    m.box((1.6, 0.05, 0.6), (0, -3.01, 1.37), WINDOW, base=True, bevel=0.05, seg=3, rot=(-3, 0, 0))
    for s in (-1, 1):
        m.box((0.1, 0.04, 0.06), (s * 0.95, -2.82, 0.6), "sign_white", bevel=0.01)
    m.box((0.04, 5.2, 0.05), (-hw - 0.01, 0.15, R - 0.17), "silver", bevel=0.01)
    rear_end(m, 2.9, W, F, R)
    for y in (-1.4, 1.2):
        m.box((0.42, 0.42, 0.1), (0, y, R - 0.01), FRAME, base=True, bevel=0.04, seg=3)
        m.box((0.32, 0.32, 0.08), (0, y, R + 0.05), WINDOW, base=True, bevel=0.03)
    drawbar(m, -2.85, -4.15, F)
    m.collide_box((W, 5.9, R), (0, -0.05, 0), base=True).collide_box((1.0, 1.25, 0.6), (0, -3.55, 0), base=True)
    return m


def caravan_twin() -> Model:
    """Big twin-axle caravan, 7.4 m body (8.9 m with the drawbar): panoramic front, grey skirt, silver trim, two
    tinted bands and a satellite dish."""
    m = Model("caravan_twin", view_range=350.0)
    W, F, R = 2.5, 0.45, 2.8
    out = round_corners([(-3.5, F), (3.7, F), (3.7, R - 0.02), (-3.2, R), (-3.75, 2.35), (-3.82, 1.15)],
                        [0.1, 0.1, 0.2, 0.5, 0.35, 0.3])
    caravan_body(m, out, W, F, [0.05, 0.95], 0.31, (0.98, 1.08), 0.86, tint_top=(1.14, 1.2))
    hw = W / 2
    side_decal(m, inset(clip_band(out, 2.36, 2.42), 0.06), hw + 0.004, "silver")
    side_window(m, hw, 2.6, 1.78, 1.25, 0.72)
    side_window(m, hw, -2.45, 1.78, 1.4, 0.72)
    side_window(m, hw, -0.9, 1.78, 0.9, 0.72, sides=(-1,))
    side_window(m, hw, 0.7, 1.78, 1.1, 0.72, sides=(1,))
    side_window(m, hw, -0.4, 1.78, 0.9, 0.72, sides=(1,))
    side_decal(m, rounded_rect(0.7, 1.95, 0.08, 3, 0.45, 1.5), hw + 0.006, FRAME, sides=(-1,))
    side_decal(m, rounded_rect(0.62, 1.87, 0.06, 3, 0.45, 1.5), hw + 0.014, "white", sides=(-1,))
    side_window(m, hw + 0.02, 0.45, 2.03, 0.4, 0.5, r=0.06, sides=(-1,))
    m.box((0.04, 0.12, 0.04), (-hw - 0.03, 0.2, 1.35), "silver", bevel=0.01)
    for z, w in ((0.24, 0.62), (0.0, 0.05)):
        m.box((0.4, w, 0.05 if z else 0.24), (-hw - 0.22, 0.45, z), "silver" if z else "anthracite", base=True,
              bevel=0.012)
    # panoramic front: dark panel with a wide window, chrome bar, lamps
    m.box((2.1, 0.04, 0.95), (0, -3.82, 1.3), "dark", base=True, bevel=0.08, seg=3, rot=(-3, 0, 0))
    m.box((1.95, 0.05, 0.75), (0, -3.83, 1.4), WINDOW, base=True, bevel=0.07, seg=3, rot=(-3, 0, 0))
    m.box((2.2, 0.05, 0.05), (0, -3.7, 0.92), "silver", bevel=0.02)
    for s in (-1, 1):
        m.box((0.18, 0.04, 0.07), (s * 1.0, -3.62, 0.66), "sign_white", bevel=0.015)
    m.box((0.04, 6.8, 0.05), (-hw - 0.01, 0.0, R - 0.17), "silver", bevel=0.01)
    rear_end(m, 3.7, W, F, R)
    for y in (-2.2, 2.0):
        m.box((0.45, 0.45, 0.1), (0, y, R - 0.01), FRAME, base=True, bevel=0.04, seg=3)
        m.box((0.35, 0.35, 0.08), (0, y, R + 0.05), WINDOW, base=True, bevel=0.03)
    # satellite dish on the roof
    m.cyl(0.03, 0.3, (0.55, 0.6, R), "silver", sides=8)
    m.cyl(0.24, 0.05, (0.55, 0.62, R + 0.3), "white", r2=0.27, sides=20, bevel=0.012, rot=(-55, 0, 0))
    m.tube([(0.55, 0.6, R + 0.32), (0.55, 0.35, R + 0.5)], 0.012, "anthracite", sides=6)
    drawbar(m, -3.6, -5.1, F, cover=SKIRT)
    m.collide_box((W, 7.6, R), (0, -0.05, 0), base=True).collide_box((1.0, 1.35, 0.6), (0, -4.45, 0), base=True)
    return m


def caravan_small() -> Model:
    """Small rounded vintage caravan, 3.8 m body (4.9 m with the drawbar): two-tone, tinted lower half."""
    m = Model("caravan_small", view_range=350.0)
    W, F = 2.0, 0.4
    out = round_corners([(-1.85, F), (1.9, F), (1.95, 1.6), (1.4, 2.18), (-1.3, 2.18), (-2.0, 1.55)],
                        [0.12, 0.15, 0.55, 0.45, 0.45, 0.55], n=6)
    prism(m, out, W, "#f5ecd8", bevel=0.06, seg=2)
    hw = W / 2
    side_decal(m, inset(clip_band(out, F - 0.01, 1.12), 0.03), hw, "white", "tint")
    side_decal(m, inset(clip_band(out, 1.12, 1.17), 0.06), hw + 0.004, "silver")
    arch = [(0.15 + 0.34 * math.cos(math.radians(d)), 0.28 + 0.34 * math.sin(math.radians(d))) for d in range(0, 181, 15)]
    side_decal(m, arch, hw + 0.008, "dark")
    for s in (-1, 1):
        wheel(m, s * (hw - 0.02), 0.15, 0.28, 0.18)
    side_window(m, hw, 1.05, 1.55, 0.8, 0.5, r=0.2)
    side_window(m, hw, -1.0, 1.55, 0.7, 0.5, r=0.2, sides=(1,))
    side_decal(m, rounded_rect(0.62, 1.55, 0.25, 4, -0.85, 1.25), hw + 0.006, "#f5ecd8", sides=(-1,))
    side_window(m, hw + 0.012, -0.85, 1.68, 0.36, 0.38, r=0.15, sides=(-1,))
    m.box((0.04, 0.1, 0.04), (-hw - 0.03, -1.05, 1.2), "silver", bevel=0.01)
    m.box((1.2, 0.08, 0.5), (0, -1.92, 1.42), FRAME, base=True, bevel=0.12, seg=3, rot=(-40, 0, 0))
    m.box((1.1, 0.09, 0.42), (0, -1.94, 1.45), WINDOW, base=True, bevel=0.1, seg=3, rot=(-40, 0, 0))
    rear_end(m, 1.88, W, F, 2.1)
    m.box((W - 0.3, 3.3, 0.12), (0, 0.0, F - 0.12), "dark", base=True, bevel=0.02)
    for y in (-1.5, 1.55):
        for s in (-1, 1):
            m.box((0.05, 0.05, F), (s * (hw - 0.2), y, 0), "silver", base=True, bevel=0.0)
    drawbar(m, -1.75, -3.0, F, cover="#f5ecd8")
    m.collide_box((W, 3.85, 2.2), (0, 0.0, 0), base=True).collide_box((0.9, 1.1, 0.55), (0, -2.45, 0), base=True)
    return m


def caravan_awning() -> Model:
    """Porch awning for the door side of a caravan: tinted canvas roof and side walls on steel poles, open front.
    Origin at the middle of the edge that meets the caravan wall, the awning stands on -Y."""
    m = Model("caravan_awning", view_range=300.0)
    L, D, H0, H1 = 3.6, 2.4, 2.38, 2.05
    slope = math.degrees(math.atan2(H0 - H1, D))
    m.box((L, D + 0.1, 0.04), (0, -D / 2, (H0 + H1) / 2), "white", "tint", bevel=0.015, rot=(-slope, 0, 0))
    m.box((L + 0.04, 0.03, 0.26), (0, -D - 0.02, H1 - 0.2), "white", "tint", base=True, bevel=0.01)
    for x in (-L / 2 + 0.3, 0, L / 2 - 0.3):
        m.box((0.18, 0.035, 0.22), (x, -D - 0.035, H1 - 0.18), "white", base=True, bevel=0.008)
    for s in (-1, 1):
        wall = [(0.0, 0.02), (-D, 0.02), (-D, H1 - 0.02), (0.0, H0 - 0.02)]
        prism(m, wall, 0.025, "white", "tint", at=(s * L / 2, 0, 0))
        prism(m, rounded_rect(1.0, 0.75, 0.1, 3, -D / 2 - 0.1, 1.45), 0.035, WINDOW, at=(s * L / 2, 0, 0))
        m.cyl(0.025, H1, (s * (L / 2 - 0.02), -D, 0), "steel", sides=8)
        m.tube([(s * (L / 2 - 0.02), -D, H1), (s * (L / 2 - 0.02), 0, H0)], 0.018, "steel", sides=6)
    m.cyl(0.025, H1, (0, -D, 0), "steel", sides=8)
    m.collide_box((L, D + 0.1, 0.06), (0, -D / 2, H1 + (H0 - H1) / 2 - 0.03), base=True)
    for s in (-1, 1):
        m.collide_box((0.04, D, 1.9), (s * L / 2, -D / 2, 0), base=True)
    m.collide_cyl(0.04, H1, (0, -D, 0))
    return m


def camp_van() -> Model:
    """Panel van (Master/Transit class), 5.5 m, body in the instance tint: the camp's tow vehicles."""
    m = Model("camp_van", view_range=350.0)
    W, F, R = 2.0, 0.42, 2.45
    out = round_corners([(-2.72, F), (2.75, F), (2.75, R), (-1.25, R), (-1.6, 2.28), (-2.35, 1.25), (-2.75, 1.05)],
                        [0.12, 0.08, 0.12, 0.25, 0.15, 0.25, 0.15])
    prism(m, out, W, "white", "tint", bevel=0.05)
    hw = W / 2
    side_decal(m, inset(clip_band(out, F - 0.01, 0.62), 0.02), hw, "dark")
    # windscreen (follows the slope between the roof and the bonnet), cab side windows
    ws = math.degrees(math.atan2(2.28 - 1.25, 2.35 - 1.6))
    m.box((W - 0.2, 0.04, 1.1), (0, -1.99, 1.775), WINDOW, bevel=0.04, rot=(ws - 90, 0, 0))
    for s in (-1, 1):
        side_decal(m, [(-1.95, 1.4), (-1.0, 1.4), (-1.0, 2.15), (-1.45, 2.15)], hw + 0.003, WINDOW, sides=(s,))
        m.box((0.18, 0.06, 0.24), (s * (hw + 0.1), -1.85, 1.62), "dark", base=True, bevel=0.02)
        m.box((0.03, 0.02, 1.4), (s * (hw + 0.005), -0.98, 0.7), "dark", base=True, bevel=0.0)
        m.box((0.03, 0.02, 1.7), (s * (hw + 0.005), 0.3, 0.6), "dark", base=True, bevel=0.0)
        m.box((0.32, 0.05, 0.16), (s * 0.68, -2.75, 1.0), "glow", "glow", bevel=0.03)
        m.box((0.12, 0.04, 0.4), (s * (hw - 0.1), 2.76, 1.1), "sign_red", base=True, bevel=0.012)
        for y in (-1.95, 1.75):
            wheel(m, s * (hw + 0.02), y, 0.36, 0.24)
            arch = [(y + 0.44 * math.cos(math.radians(d)), 0.36 + 0.44 * math.sin(math.radians(d))) for d in range(0, 181, 15)]
            side_decal(m, arch, hw + 0.002, "dark", sides=(s,))
    m.box((0.9, 0.05, 0.28), (0, -2.76, 0.72), "dark", base=True, bevel=0.03)
    m.box((W + 0.04, 0.16, 0.26), (0, -2.72, 0.38), "dark", base=True, bevel=0.06, seg=3)
    m.box((W + 0.04, 0.12, 0.24), (0, 2.75, 0.38), "dark", base=True, bevel=0.05, seg=3)
    m.box((0.52, 0.02, 0.11), (0, -2.81, 0.5), "sign_white", base=True, bevel=0.008)
    m.box((0.52, 0.02, 0.11), (0, 2.82, 0.75), "sign_white", base=True, bevel=0.008)
    m.box((0.02, 0.03, 1.75), (0, 2.76, 0.6), "dark", base=True, bevel=0.0)
    m.collide_box((W, 5.5, R), (0, 0.0, 0), base=True)
    return m


def plastic_chair(m: Model, x, y, face, color) -> None:
    """Monobloc garden chair at (x, y) looking towards `face` degrees (0 = -Y)."""
    rot = (0, 0, face)
    c, s = math.cos(math.radians(face)), math.sin(math.radians(face))

    def at(dx, dy, z):
        return (x + dx * c - dy * s, y + dx * s + dy * c, z)
    m.box((0.46, 0.44, 0.04), at(0, 0, 0.42), color, bevel=0.015, rot=rot)
    m.box((0.46, 0.04, 0.42), at(0, 0.23, 0.62), color, bevel=0.015, rot=(-10, 0, face))
    for dx in (-0.2, 0.2):
        for dy in (-0.19, 0.19):
            m.box((0.04, 0.04, 0.42), at(dx, dy, 0.0), color, base=True, bevel=0.0, rot=rot)
        m.box((0.04, 0.4, 0.03), at(dx, 0.0, 0.62), color, bevel=0.0, rot=rot)


def camp_table() -> Model:
    """Round white plastic garden table with four monobloc chairs."""
    m = Model("camp_table")
    m.cyl(0.48, 0.04, (0, 0, 0.7), "white", sides=24, bevel=0.015)
    for a in (45, 135, 225, 315):
        x, y = 0.3 * math.cos(math.radians(a)), 0.3 * math.sin(math.radians(a))
        m.box((0.04, 0.04, 0.72), (x, y, 0), "white", base=True, bevel=0.0)
    m.cyl(0.02, 0.4, (0, 0, 0.74), "silver", sides=8)
    for i, a in enumerate((0, 100, 185, 275)):
        x, y = 0.78 * math.sin(math.radians(a)), -0.78 * math.cos(math.radians(a))
        plastic_chair(m, x, y, a + 180, "white" if i % 2 else "#e9e6dc")
    m.collide_cyl(0.5, 0.75).collide_box((1.9, 1.9, 0.45), (0, 0, 0), base=True)
    return m


def washing_line() -> Model:
    """Rotary washing line with laundry hanging on it."""
    m = Model("washing_line")
    m.cyl(0.03, 1.85, (0, 0, 0), "steel", sides=10)
    m.cyl(0.06, 0.12, (0, 0, 1.55), "silver", sides=10, bevel=0.01)
    R, top = 1.05, 1.8
    arms = [math.radians(a) for a in (0, 90, 180, 270)]
    for a in arms:
        m.tube([(0, 0, 1.6), (R * math.cos(a), R * math.sin(a), top)], 0.012, "silver", sides=5)
    for r in (0.45, 0.75, 1.0):
        pts = [(r * math.cos(a), r * math.sin(a), 1.6 + (top - 1.6) * r / R) for a in arms + arms[:1]]
        m.tube(pts, 0.004, "white", sides=4)
    laundry = [("#e5534b", 0.4, 0.55), ("#4a7bd0", 0.35, 0.65), ("#ffffff", 0.9, 0.7), ("#f2c230", 0.3, 0.4),
               ("#7ac17a", 0.45, 0.6), ("#e98fb8", 0.3, 0.35), ("#ffffff", 0.5, 0.5), ("#3f4f6b", 0.35, 0.8)]
    k = 0
    for i, a in enumerate(arms):
        b = arms[(i + 1) % 4]
        for r in (0.75, 1.0) if i % 2 == 0 else (0.45, 1.0):
            color, w, h = laundry[k % len(laundry)]
            k += 1
            pa = Vector((r * math.cos(a), r * math.sin(a)))
            pb = Vector((r * math.cos(b), r * math.sin(b)))
            mid = (pa + pb) / 2
            yaw = math.degrees(math.atan2(pb.y - pa.y, pb.x - pa.x))
            z = 1.6 + (top - 1.6) * r / R - 0.01
            m.box((min(w, (pb - pa).length * 0.8), 0.015, h), (mid.x, mid.y, z - h), color, base=True, bevel=0.005,
                  rot=(0, 0, yaw))
    m.collide_cyl(0.05, 1.85)
    return m


def water_tank() -> Model:
    """1000 l IBC water tank: white tank in a steel cage on a pallet, tap at the front."""
    m = Model("water_tank")
    m.box((1.2, 1.0, 0.14), (0, 0, 0), "anthracite", base=True, bevel=0.02)
    m.box((1.1, 0.92, 0.98), (0, 0, 0.15), "#eceee6", base=True, bevel=0.1, seg=3)
    m.cyl(0.11, 0.06, (0, 0.1, 1.13), "anthracite", sides=14, bevel=0.01)
    for x in (-0.57, -0.29, 0.0, 0.29, 0.57):
        for y in (-0.48, 0.48):
            m.box((0.025, 0.025, 1.0), (x, y, 0.14), "silver", base=True, bevel=0.0)
    for y in (-0.19, 0.0, 0.19):
        for x in (-0.57, 0.57):
            m.box((0.025, 0.025, 1.0), (x, y, 0.14), "silver", base=True, bevel=0.0)
    for z in (0.5, 0.82, 1.13):
        for y in (-0.48, 0.48):
            m.box((1.16, 0.025, 0.025), (0, y, z), "silver", bevel=0.0)
        for x in (-0.57, 0.57):
            m.box((0.025, 0.98, 0.025), (x, 0, z), "silver", bevel=0.0)
    m.box((0.14, 0.12, 0.12), (0, -0.52, 0.22), "dark", base=True, bevel=0.02)
    m.collide_box((1.2, 1.0, 1.16), (0, 0, 0), base=True)
    return m


def generator() -> Model:
    """Open-frame petrol generator."""
    m = Model("generator")
    m.box((0.62, 0.45, 0.42), (0, 0, 0.04), "#d8a21e", base=True, bevel=0.06, seg=3)
    m.box((0.3, 0.3, 0.08), (0.1, 0, 0.46), "dark", base=True, bevel=0.03)
    m.cyl(0.06, 0.05, (0.1, 0, 0.53), "dark", sides=12, bevel=0.01)
    m.box((0.22, 0.02, 0.16), (-0.12, -0.23, 0.18), "dark", base=True, bevel=0.01)
    for s in (-1, 1):
        m.tube([(-0.36, s * 0.26, 0.0), (-0.36, s * 0.26, 0.56), (0.36, s * 0.26, 0.56), (0.36, s * 0.26, 0.0)],
               0.016, "dark", sides=6)
    m.collide_box((0.75, 0.55, 0.58), (0, 0, 0), base=True)
    return m


def gas_bottles() -> Model:
    """Two 13 kg gas bottles (butane blue, propane orange)."""
    m = Model("gas_bottles")
    for x, color in ((-0.17, "sign_blue"), (0.17, "#e8812a")):
        m.cyl(0.15, 0.5, (x, 0, 0.02), color, sides=18, bevel=0.06, seg=3)
        m.cyl(0.13, 0.03, (x, 0, 0.0), "dark", sides=18, bevel=0.008)
        m.cyl(0.08, 0.1, (x, 0, 0.5), color, sides=14, bevel=0.012)
        m.cyl(0.03, 0.06, (x, 0, 0.6), "silver", sides=8)
    m.collide_box((0.65, 0.32, 0.66), (0, 0, 0), base=True)
    return m


def camp_bbq() -> Model:
    """Kettle barbecue on three legs."""
    m = Model("camp_bbq")
    m.sphere(0.28, (0, 0, 0.72), "dark", seg=18, scale=(1, 1, 0.75))
    m.cyl(0.29, 0.03, (0, 0, 0.71), "silver", sides=18, bevel=0.008)
    m.cyl(0.04, 0.05, (0, 0, 0.92), "anthracite", sides=10, bevel=0.01)
    for a in (90, 210, 330):
        x, y = 0.3 * math.cos(math.radians(a)), 0.3 * math.sin(math.radians(a))
        m.tube([(x, y, 0.0), (x * 0.5, y * 0.5, 0.6)], 0.014, "silver", sides=6)
    m.collide_cyl(0.3, 0.95)
    return m


MODELS = {f.__name__: f for f in (caravan, caravan_twin, caravan_small, caravan_awning, camp_van, camp_table,
                                  washing_line, water_tank, generator, gas_bottles, camp_bbq)}
