"""French road sign faces built from code (milestone M6): one model per code of pipeline/props_catalog.toml
[signs.faces] (plus family fallbacks). A face is a steel back plate with thin coloured layers stacked towards
the front (-Y): borders, fields, bars, text and simple pictograms. Origin at the centre of the sign shape,
back at y = +0.012; the Godot builder mounts the faces on sign_pole from its `faces` anchor down."""
import math
import re

from toylib import Model, circle, polygon_round, rounded_rect

LAYER = 0.002


def slug(code: str) -> str:
    return "sign_" + re.sub(r"[^A-Za-z0-9]+", "_", code.replace("FR:", "")).strip("_")


class Face:
    def __init__(self, code: str, size: float):
        self.m = Model(slug(code), view_range=220.0)
        self.s = size
        self.k = 0

    def back(self, outline):
        self.m.plate(outline, 0.012, (0, 0, 0), "steel")
        return self

    def shape(self, outline, color):
        self.k += 1
        self.m.plate(outline, LAYER, (0, -LAYER * self.k, 0), color)
        return self

    def text(self, body, size, color="sign_black", x=0.0, z=0.0):
        self.k += 1
        self.m.text(body, size, (x, -LAYER * self.k - LAYER / 2, z), color, depth=LAYER)
        return self

    def strip(self, a, b, w, color):
        """Thick line from a to b (x, z)."""
        dx, dz = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dz)
        ox, oz = -dz / n * w / 2, dx / n * w / 2
        return self.shape([(a[0] + ox, a[1] + oz), (a[0] - ox, a[1] - oz), (b[0] - ox, b[1] - oz), (b[0] + ox, b[1] + oz)], color)

    def disc(self, r, color, cx=0.0, cz=0.0, n=40):
        return self.shape(circle(r, n, cx, cz), color)

    def ring(self, r_out, r_in, color, inside, cx=0.0, cz=0.0):
        """Ring drawn as a disc and the inside colour over it (layers instead of holes)."""
        return self.disc(r_out, color, cx, cz).disc(r_in, inside, cx, cz)


# ---------------------------------------------------------------- outlines

def tri(side, down=False, scale=1.0, r=0.0):
    h = side * math.sqrt(3) / 2 * scale
    s = side * scale
    pts = [(-s / 2, h / 3), (0, -2 * h / 3), (s / 2, h / 3)] if down else [(-s / 2, -h / 3), (s / 2, -h / 3), (0, 2 * h / 3)]
    return polygon_round(pts, r * scale, 4) if r > 0 else pts


def octagon(across):
    R = across / 2 / math.cos(math.radians(22.5))
    return circle(R, 8, phase=22.5)


def diamond(side):
    return polygon_round([(0, -side / 2), (side / 2, 0), (0, side / 2), (-side / 2, 0)], side * 0.06, 3)


# ---------------------------------------------------------------- pictograms (unit u = sign size)

def bicycle(f: Face, u, color, bg, cz=0.0):
    r = 0.13 * u
    for cx in (-0.2 * u, 0.2 * u):
        f.ring(r, r * 0.72, color, bg, cx, cz - 0.05 * u)
    w = 0.035 * u
    p = {"rear": (-0.2 * u, cz - 0.05 * u), "front": (0.2 * u, cz - 0.05 * u), "crank": (-0.02 * u, cz - 0.05 * u),
         "seat": (-0.08 * u, cz + 0.12 * u), "bar": (0.15 * u, cz + 0.15 * u)}
    for a, b in (("rear", "crank"), ("crank", "seat"), ("seat", "rear"), ("seat", "bar"), ("crank", "bar"), ("bar", "front")):
        f.strip(p[a], p[b], w, color)
    f.strip((-0.13 * u, cz + 0.13 * u), (-0.03 * u, cz + 0.13 * u), w * 1.4, color)


def pedestrian(f: Face, u, color, cz=0.0):
    w = 0.06 * u
    f.disc(0.055 * u, color, 0.01 * u, cz + 0.2 * u, 16)
    f.strip((0.0, cz + 0.12 * u), (-0.02 * u, cz - 0.04 * u), w * 1.3, color)
    f.strip((-0.02 * u, cz - 0.04 * u), (-0.1 * u, cz - 0.2 * u), w, color)
    f.strip((-0.02 * u, cz - 0.04 * u), (0.08 * u, cz - 0.2 * u), w, color)
    f.strip((0.0, cz + 0.1 * u), (-0.1 * u, cz + 0.0), w * 0.8, color)
    f.strip((0.0, cz + 0.1 * u), (0.1 * u, cz + 0.02 * u), w * 0.8, color)


def car_back(f: Face, u, color, bg, cx=0.0, cz=0.0):
    f.shape(rounded_rect(0.26 * u, 0.14 * u, 0.04 * u, 3, cx, cz), color)
    f.shape(rounded_rect(0.18 * u, 0.1 * u, 0.03 * u, 3, cx, cz + 0.1 * u), color)
    f.shape(rounded_rect(0.13 * u, 0.05 * u, 0.015 * u, 2, cx, cz + 0.1 * u), bg)
    for s in (-1, 1):
        f.shape(rounded_rect(0.05 * u, 0.06 * u, 0.015 * u, 2, cx + s * 0.09 * u, cz - 0.09 * u), color)


def bus(f: Face, u, color, bg, cz=0.0):
    f.shape(rounded_rect(0.5 * u, 0.24 * u, 0.04 * u, 3, 0, cz), color)
    for k in range(4):
        f.shape(rounded_rect(0.08 * u, 0.07 * u, 0.012 * u, 2, -0.17 * u + k * 0.11 * u, cz + 0.04 * u), bg)
    for x in (-0.14 * u, 0.15 * u):
        f.disc(0.045 * u, bg, x, cz - 0.12 * u, 16)
        f.disc(0.03 * u, color, x, cz - 0.12 * u, 16)


def arrow_up(f: Face, u, color, cz=0.0):
    f.shape([(-0.06 * u, cz - 0.3 * u), (0.06 * u, cz - 0.3 * u), (0.06 * u, cz + 0.05 * u), (0.16 * u, cz + 0.05 * u),
             (0.0, cz + 0.3 * u), (-0.16 * u, cz + 0.05 * u), (-0.06 * u, cz + 0.05 * u)], color)


def left_turn(f: Face, u, color):
    w = 0.08 * u
    f.strip((0.08 * u, -0.25 * u), (0.08 * u, 0.02 * u), w, color)
    f.strip((0.12 * u, 0.02 * u), (-0.08 * u, 0.02 * u), w, color)
    f.shape([(-0.08 * u, 0.12 * u), (-0.2 * u, 0.02 * u), (-0.08 * u, -0.08 * u)], color)


def bump(f: Face, u, color, cz=0.0):
    f.strip((-0.22 * u, cz - 0.06 * u), (0.22 * u, cz - 0.06 * u), 0.04 * u, color)
    f.shape([(x * 0.11 * u, cz - 0.06 * u + z * 0.1 * u) for x, z in
             [(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(0, 181, 15)]], color)


# ---------------------------------------------------------------- designs

def warning(code, s, picto):
    """A family: white triangle with a red border, black pictogram."""
    f = Face(code, s)
    out = tri(s, r=0.07 * s)
    f.back(out).shape(out, "sign_red").shape(tri(s, scale=0.68, r=0.05 * s), "sign_white")
    picto(f, s * 0.55)
    return f


def give_way(code, s):
    f = Face(code, s)
    out = tri(s, True, r=0.07 * s)
    return f.back(out).shape(out, "sign_red").shape(tri(s, True, scale=0.6, r=0.04 * s), "sign_white")


def stop(code, s):
    f = Face(code, s)
    o = octagon(s)
    f.back(o).shape(o, "sign_white").shape(octagon(s * 0.92), "sign_red")
    return f.text("STOP", s * 0.3, "sign_white", z=-0.005 * s)


def prohibition(code, s, inner=None, field="sign_white"):
    """B family: red ring around a white (or blue) field."""
    f = Face(code, s)
    out = circle(s / 2, 40)
    f.back(out).ring(s / 2, s / 2 * (0.8 if field == "sign_blue" else 0.78), "sign_red", field)
    if inner:
        inner(f, s)
    return f


def mandatory(code, s, inner):
    f = Face(code, s)
    out = circle(s / 2, 40)
    f.back(out).disc(s / 2, "sign_white").disc(s / 2 * 0.95, "sign_blue")
    inner(f, s)
    return f


def info(code, s, inner=None):
    """C family: blue square with a thin white border."""
    f = Face(code, s)
    out = rounded_rect(s, s, s * 0.08, 4)
    f.back(out).shape(out, "sign_white").shape(rounded_rect(s * 0.92, s * 0.92, s * 0.06, 4), "sign_blue")
    if inner:
        inner(f, s)
    return f


def zone(code, s, inner, end=False):
    """B30/B52 zone panels: white rectangle with a grey border; `end` greys them and adds diagonal bars."""
    f = Face(code, s)
    w, h = s, s * 1.25
    out = rounded_rect(w, h, s * 0.06, 4)
    f.back(out).shape(out, "#8a9099").shape(rounded_rect(w * 0.94, h * 0.95, s * 0.05, 4), "sign_white")
    f.text("ZONE", s * 0.2, "#8a9099" if end else "sign_black", z=h * 0.33)
    inner(f, s, end)
    if end:
        for dx in (-0.08, 0.0, 0.08):
            f.strip((-w * 0.4 + dx * s, -h * 0.42), (w * 0.4 + dx * s, h * 0.22), s * 0.025, "sign_black")
    return f


def zone30(f: Face, s, end):
    col = "#8a9099" if end else "sign_red"
    f.ring(s * 0.3, s * 0.24, col, "sign_white", 0, -s * 0.08)
    f.text("30", s * 0.22, "#8a9099" if end else "sign_black", z=-s * 0.09)


def zone_meet(f: Face, s, end):
    f.shape(rounded_rect(s * 0.6, s * 0.6, s * 0.04, 3, 0, -s * 0.1), "#8a9099" if end else "sign_blue")
    pedestrian(f, s * 0.7, "sign_white", cz=-s * 0.08)


def town(code, s):
    f = Face(code, s)
    w, h = s, s * 0.45
    out = rounded_rect(w, h, s * 0.04, 3)
    f.back(out).shape(out, "sign_red").shape(rounded_rect(w * 0.93, h * 0.85, s * 0.03, 3), "sign_white")
    return f.text("PALAISEAU", s * 0.12, "sign_black")


def plate(code, s, label=""):
    f = Face(code, s)
    w, h = s, s * 0.45
    out = rounded_rect(w, h, s * 0.04, 3)
    f.back(out).shape(out, "sign_black").shape(rounded_rect(w * 0.94, h * 0.88, s * 0.03, 3), "sign_white")
    return f.text(label, s * 0.2, "sign_black") if label else f


def generic(code, s):
    f = Face(code, s)
    out = rounded_rect(s, s, s * 0.1, 4)
    return f.back(out).shape(out, "#8a9099").shape(rounded_rect(s * 0.92, s * 0.92, s * 0.08, 4), "sign_white")


def speed(value):
    return lambda f, s: f.text(value, s * (0.4 if len(value) < 3 else 0.3), "sign_black", z=-0.01 * s)


def red_diagonal(f: Face, s, both=False):
    r = s / 2 * 0.78
    a = r * math.cos(math.radians(45))
    f.strip((-a, a), (a, -a), s * 0.1, "sign_red")
    if both:
        f.strip((-a, -a), (a, a), s * 0.1, "sign_red")


def design(code: str, s: float) -> Face:
    m = re.match(r"FR:B14(?:\[(\d+)\])?$", code)
    if m:
        return prohibition(code, s, speed(m.group(1) or "30"))
    table = {
        "FR:AB4": lambda: stop(code, s),
        "FR:AB3a": lambda: give_way(code, s),
        "FR:AB1": lambda: warning(code, s, lambda f, u: (f.strip((-0.18 * u, -0.1 * u), (0.18 * u, 0.26 * u), 0.08 * u, "sign_black"),
                                                       f.strip((-0.18 * u, 0.26 * u), (0.18 * u, -0.1 * u), 0.08 * u, "sign_black"))),
        "FR:AB2": lambda: warning(code, s, lambda f, u: (f.strip((0, -0.14 * u), (0, 0.32 * u), 0.12 * u, "sign_black"),
                                                       f.strip((-0.2 * u, 0.1 * u), (0.2 * u, 0.1 * u), 0.05 * u, "sign_black"))),
        "FR:AB6": lambda: (lambda f: f.back(diamond(s)).shape(diamond(s), "sign_white").shape(diamond(s * 0.72), "sign_yellow"))(Face(code, s)),
        "FR:A2b": lambda: warning(code, s, lambda f, u: bump(f, u, "sign_black", cz=0.0)),
        "FR:A3b": lambda: warning(code, s, lambda f, u: (f.strip((-0.12 * u, -0.15 * u), (-0.12 * u, 0.35 * u), 0.05 * u, "sign_black"),
                                                       f.strip((0.16 * u, -0.15 * u), (0.16 * u, 0.05 * u), 0.05 * u, "sign_black"),
                                                       f.strip((0.16 * u, 0.05 * u), (0.04 * u, 0.2 * u), 0.05 * u, "sign_black"),
                                                       f.strip((0.04 * u, 0.2 * u), (0.04 * u, 0.35 * u), 0.05 * u, "sign_black"))),
        "FR:A13b": lambda: warning(code, s, lambda f, u: pedestrian(f, u, "sign_black", cz=0.03 * u)),
        "FR:A14": lambda: warning(code, s, lambda f, u: f.text("!", u * 0.55, "sign_black", z=0.06 * u)),
        "A": lambda: warning(code, s, lambda f, u: f.text("!", u * 0.55, "sign_black", z=0.06 * u)),
        "FR:B0": lambda: prohibition(code, s),
        "B": lambda: prohibition(code, s),
        "FR:B1": lambda: (lambda f: f.back(circle(s / 2, 40)).disc(s / 2, "sign_red").shape(
            rounded_rect(s * 0.64, s * 0.16, s * 0.02, 2), "sign_white"))(Face(code, s)),
        "FR:B2a": lambda: prohibition(code, s, lambda f, u: (left_turn(f, u, "sign_black"), red_diagonal(f, u))),
        "FR:B3": lambda: prohibition(code, s, lambda f, u: (car_back(f, u, "sign_red", "sign_white", -0.15 * u),
                                                          car_back(f, u, "sign_black", "sign_white", 0.15 * u))),
        "FR:B6a1": lambda: prohibition(code, s, lambda f, u: red_diagonal(f, u), "sign_blue"),
        "FR:B6d": lambda: prohibition(code, s, lambda f, u: red_diagonal(f, u, True), "sign_blue"),
        "FR:B9b": lambda: prohibition(code, s, lambda f, u: bicycle(f, u * 0.85, "sign_black", "sign_white")),
        "FR:B12": lambda: prohibition(code, s, lambda f, u: f.text("3,5m", u * 0.2, "sign_black")),
        "FR:B13": lambda: prohibition(code, s, lambda f, u: f.text("3,5t", u * 0.22, "sign_black")),
        "FR:B22a": lambda: mandatory(code, s, lambda f, u: bicycle(f, u * 0.9, "sign_white", "sign_blue")),
        "FR:B27a": lambda: mandatory(code, s, lambda f, u: bus(f, u * 0.9, "sign_white", "sign_blue")),
        "FR:B30": lambda: zone(code, s, zone30),
        "FR:B51": lambda: zone(code, s, zone30, end=True),
        "FR:B52": lambda: zone(code, s, zone_meet),
        "FR:B53": lambda: zone(code, s, zone_meet, end=True),
        "C": lambda: info(code, s),
        "FR:C1a": lambda: info(code, s, lambda f, u: f.text("P", u * 0.62, "sign_white", z=-0.02 * u)),
        "FR:C12": lambda: info(code, s, lambda f, u: arrow_up(f, u, "sign_white")),
        "FR:C13a": lambda: info(code, s, lambda f, u: (f.strip((0, -0.32 * u), (0, 0.18 * u), 0.14 * u, "sign_white"),
                                                     f.strip((-0.22 * u, 0.22 * u), (0.22 * u, 0.22 * u), 0.1 * u, "sign_red"))),
        "FR:C20a": lambda: info(code, s, lambda f, u: (f.shape(tri(u * 0.82, r=0.03 * u), "sign_white"),
                                                     [f.strip((x * u, -0.2 * u), (x * u + 0.03 * u, -0.2 * u), 0.04 * u, "sign_black")
                                                      for x in (-0.2, -0.1, 0.0, 0.1)],
                                                     pedestrian(f, u * 0.75, "sign_black", cz=0.0))),
        "FR:C27": lambda: info(code, s, lambda f, u: (f.shape(tri(u * 0.82, r=0.03 * u), "sign_white"),
                                                    bump(f, u * 0.75, "sign_black", cz=-0.08 * u))),
        "FR:C113": lambda: info(code, s, lambda f, u: bicycle(f, u, "sign_white", "sign_blue")),
        "FR:C114": lambda: info(code, s, lambda f, u: (bicycle(f, u, "sign_white", "sign_blue"),
                                                     f.strip((-0.36 * u, 0.36 * u), (0.36 * u, -0.36 * u), 0.08 * u, "sign_red"))),
        "FR:EB10": lambda: town(code, s),
        "EB": lambda: town(code, s),
        "FR:M6h": lambda: plate(code, s, "SAUF"),
        "M": lambda: plate(code, s),
        "generic": lambda: generic(code, s),
    }
    if code not in table:
        raise KeyError(f"no sign design for {code}: add one to blender/props/signs.py")
    return table[code]()


def build_faces(faces: dict) -> dict:
    """faces: catalog [signs.faces] {code: [size, priority]} -> {model name: Model}."""
    out = {}
    for code, (size, prio) in faces.items():
        f = design(code, float(size))
        f.m.info.update({"code": code, "priority": int(prio)})
        out[f.m.name] = f.m
    return out
