"""Luxury car dealership in the Institut d'Optique building (OSM w140538734, "SupOptique", local x 193…356, y 17…113).

    .venv/bin/python tools/dealership/dealership_layout.py [--dry-run] [--plot=/tmp/dealership.png]

Writes the showroom layout into godot/world/interiors.json (read by godot/scripts/builder/building_builder.gd and
interior_builder.gd, so it survives pipeline rebuilds as long as the building keeps its OSM id), then run
build_world.gd. The layout is written below in the building's own frame: u along its south facade (−10.09° from
east, from the south-west corner), v across it (north-ish), in metres; headings are degrees from +u, counter-clockwise.

Floor plan (the building is a comb of wings):
  S   south hall   u 0…64.6,  v 0…20.4   supercar gallery: two rows of podiums along a red carpet, gold car statue
  W   west arm     u 0…25.6,  v 20…42    VIP lounge: bar, sofas, palms
  C   spine        u 74…95,   v 0…48     entrance hall: main car door, turntable centrepiece, reception, salesman
  E   south-east   u 104…161, v 0…20     exclusive wing
  N   north wing   u 0…91,    v 48…62    electric and family cars, north car door
  NE  block        u 95…134,  v 42…62    sales desks, trophy cabinet
S joins C only by a 2.85 m slot (u 64.6…74.2, v 18.2…21), so S and N have car doors of their own."""
import json
import math
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon, LineString

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot/world/world.json"
OUT = ROOT / "godot/world/interiors.json"
BUILDING = "osm:w140538734"

ORIGIN = (193.11, 44.973)       # south-west corner (ring vertex 4)
ANGLE = -10.0888                # degrees, the south facade from east

PODIUM = 3.0                    # m, display podium radius (interior_builder.gd draws it)

# display cars, drivable (game.gd parks them at start): model, u, v, heading, price, sales pitch
CARS = [
    # S hall, south row (facing the carpet at 45°) and north row
    ("bmw-m4", 10.0, 4.6, 45.0, "84 900 €", "The M4. Six cylinders in line, 431 horses, and it still parks at the boulangerie."),
    ("audi-r8", 24.0, 4.6, 45.0, "189 900 €", "The R8 V10. Mid-engined, ten cylinders... your neighbours will hear about it."),
    ("audi-rs6", 52.0, 4.6, 135.0, "129 500 €", "The RS6 Avant: a station wagon that outruns sports cars. With room for the dog."),
    ("sedan-sports", 10.0, 15.6, -45.0, "62 400 €", "This sports sedan: comfort on the A10, excitement on the N118."),
    ("suv-luxury", 24.0, 15.6, -45.0, "97 000 €", "Our luxury SUV. Heated seats, massage seats, and it climbs the Lozère hill without a sigh."),
    ("hatchback-sports", 52.0, 15.6, -135.0, "38 900 €", "The sports hatchback. Small, lively, and the insurance will not ruin you."),
    # spine: the turntable is a static display (below); C has the reception
    # E wing, one row facing the carpet
    ("gaz-tiger", 116.0, 7.4, 60.0, "on request", "The armoured Tiger. For the client who values... discretion. The roof hatch is an option."),
    ("audi-r8", 131.0, 7.4, 60.0, "199 900 €", "Another R8, the performance edition. Between us, it is the one I would take."),
    ("bmw-m4", 146.0, 7.4, 120.0, "91 500 €", "The M4 Competition. Carbon roof, carbon seats, carbon everything."),
    # N wing, one row facing the carpet
    ("renault-zoe", 12.0, 57.5, -60.0, "32 900 €", "The Zoe! Electric, silent, and you charge it at the RER station. Very tendance."),
    ("family-suv", 27.0, 57.5, -60.0, "41 200 €", "The family SUV. Seven airbags, a huge boot, and the kids will love the black roof."),
    ("compact-hatchback", 42.0, 57.5, -60.0, "24 500 €", "The compact hatchback. A first car? I can do you a very good price on it."),
    ("mercedes-1928", 104.0, 52.0, 200.0, "1 250 000 €", "A 1928 Mercedes tourer, fully restored. A collector's piece... the leather is original."),
]
TURNTABLES = [("mercedes-1928", 84.5, 14.0)]
STATUES = [("audi-r8", 38.0, 4.6, 90.0)]                    # gold car on a granite plinth
CARPETS = [                                                  # (u0, v0, u1, v1, width)
    (0.4, 10.1, 64.0, 10.1, 2.6),       # S hall, from the west car door
    (84.5, 0.4, 84.5, 9.4, 3.0),        # main door to the turntable
    (84.5, 18.6, 84.5, 27.6, 3.0),      # turntable to the reception
    (84.5, 35.2, 84.5, 55.0, 2.6),      # reception to the north wing
    (2.0, 52.0, 90.0, 52.0, 2.4),       # N wing
    (95.0, 15.6, 160.9, 15.6, 2.6),     # E wing, from the spine to the east door
    (69.4, 19.6, 74.6, 19.6, 1.6),      # the slot between S and C
]
COLUMNS = ([(u, v) for u in (17.0, 31.0, 45.0) for v in (7.3, 12.9)]
           + [(u, v) for u in (77.4, 91.6) for v in (7.0, 21.0, 35.0)]
           + [(u, v) for u in (123.5, 138.5) for v in (12.0,)]
           + [(u, 55.5) for u in (55.0, 70.0)] + [(115.0, 48.0), (115.0, 56.0)])
CHANDELIERS = [(84.5, 14.0), (31.0, 10.1), (12.0, 31.0), (131.0, 10.0), (60.0, 55.0)]
DOORS = [   # u, v, width; on the facade nearest to (u, v)
    (84.5, 0.0, 7.0),       # main door, south (cars)
    (0.0, 10.1, 6.0),       # S hall, west (cars)
    (66.0, 62.25, 6.0),     # N wing, north (cars, to the parking)
    (161.3, 15.6, 4.0),     # E wing, east
]
FURNITURE = [   # type, u, v, heading, extra
    ("reception", 84.5, 30.8, -90.0, {}),
    ("logo_wall", 84.5, 33.6, -90.0, {}),
    ("bar", 3.2, 31.5, 0.0, {"length": 14.0}),
    ("sofa", 13.0, 27.0, 90.0, {}), ("sofa", 13.0, 34.0, -90.0, {}), ("coffee_table", 13.0, 30.5, 0.0, {}),
    ("sofa", 21.0, 30.5, 180.0, {}),
    ("sofa", 13.0, 38.8, -90.0, {}), ("armchair", 9.5, 39.0, -60.0, {}), ("armchair", 16.5, 39.0, -120.0, {}),
    ("planter", 23.6, 22.2, 0.0, {}), ("planter", 23.6, 40.4, 0.0, {}), ("planter", 1.8, 22.2, 0.0, {}),
    ("planter", 1.8, 1.8, 0.0, {}), ("planter", 1.8, 18.6, 0.0, {}), ("planter", 62.8, 1.8, 0.0, {}),
    ("planter", 62.8, 16.4, 0.0, {}), ("planter", 76.2, 1.8, 0.0, {}), ("planter", 92.8, 1.8, 0.0, {}),
    ("planter", 159.4, 1.8, 0.0, {}), ("planter", 159.4, 18.6, 0.0, {}), ("planter", 106.0, 1.8, 0.0, {}),
    ("planter", 1.8, 60.5, 0.0, {}), ("planter", 92.8, 60.5, 0.0, {}), ("planter", 132.2, 60.5, 0.0, {}),
    ("desk", 104.0, 45.0, 90.0, {}), ("desk", 114.0, 44.5, 90.0, {}), ("desk", 124.0, 45.0, 90.0, {}),
    ("desk", 124.0, 57.5, -90.0, {}),
    ("trophy_cabinet", 132.6, 51.5, 180.0, {}),
    ("desk", 6.0, 65.0, -90.0, {}), ("desk", 16.0, 65.0, -90.0, {}), ("desk", 26.0, 65.0, -90.0, {}),
    ("trophy", 76.4, 44.0, 0.0, {}), ("trophy", 92.6, 44.0, 0.0, {}),
]
SALESMAN = (82.0, 27.4, -90.0)


def args() -> dict:
    out = {"dry-run": "", "plot": ""}
    for a in sys.argv[1:]:
        k, _, v = a.lstrip("-").partition("=")
        out[k] = v or "1"
    return out


def to_map(u: float, v: float) -> list:
    a = math.radians(ANGLE)
    return [round(ORIGIN[0] + u * math.cos(a) - v * math.sin(a), 3), round(ORIGIN[1] + u * math.sin(a) + v * math.cos(a), 3)]


def heading(h: float) -> float:
    return round((h + ANGLE) % 360.0, 2)


def layout() -> dict:
    return {
        "kind": "dealership",
        "name": "Prestige Motors",
        "sign": "PRESTIGE MOTORS",
        "floor": -0.95,                 # m, the showroom floor (above every ground sample under the building)
        "ceiling": 5.39,                # m, the showroom ceiling: the upper building starts there (a floor line)
        "glass_inset": 0.45,            # m, the glass walls behind the facade line, under the upper floors' overhang
        "frame": {"origin": list(ORIGIN), "angle": ANGLE},
        "style": {"wall": "#2c2f35", "accent": "#c9a043", "floors": 3, "ground": 0, "material": 3, "top": 0},
        "drop_modules": ["slat", "entrance_canopy"],     # the school's facade fins
        "doors": [{"at": to_map(u, v), "width": w} for u, v, w in DOORS],
        "cars": [{"model": m, "at": to_map(u, v), "yaw": heading(h), "price": p, "pitch": s} for m, u, v, h, p, s in CARS],
        "turntables": [{"model": m, "at": to_map(u, v)} for m, u, v in TURNTABLES],
        "statues": [{"model": m, "at": to_map(u, v), "yaw": heading(h)} for m, u, v, h in STATUES],
        "carpets": [{"a": to_map(u0, v0), "b": to_map(u1, v1), "width": w} for u0, v0, u1, v1, w in CARPETS],
        "columns": [to_map(u, v) for u, v in COLUMNS],
        "chandeliers": [to_map(u, v) for u, v in CHANDELIERS],
        "furniture": [dict({"type": t, "at": to_map(u, v), "yaw": heading(h)}, **x) for t, u, v, h, x in FURNITURE],
        "salesman": {"at": to_map(SALESMAN[0], SALESMAN[1]), "yaw": heading(SALESMAN[2])},
    }


FOOT = {"reception": (6.4, 1.6), "logo_wall": (7.0, 0.4), "sofa": (3.0, 1.1), "coffee_table": (2.2, 1.2),
        "armchair": (1.1, 1.1), "planter": (1.4, 1.4), "desk": (2.4, 1.4), "trophy_cabinet": (3.2, 0.8),
        "trophy": (1.2, 1.2)}


def check(spec: dict, ring: Polygon) -> list:
    """Problems: items outside the floor or overlapping (a car's podium, the furniture, the columns)."""
    inner = ring.buffer(-0.5)
    bad = []
    discs = [(Point(c["at"]).buffer(PODIUM + 0.3), "car " + c["model"]) for c in spec["cars"]]
    discs += [(Point(t["at"]).buffer(4.9), "turntable") for t in spec["turntables"]]
    discs += [(Point(s["at"]).buffer(3.6), "statue") for s in spec["statues"]]
    discs += [(Point(c).buffer(0.5), "column") for c in spec["columns"]]
    for f in spec["furniture"]:
        w, d = FOOT.get(f["type"], (f.get("length", 1.0), 1.0))
        r = math.radians(f["yaw"])
        ux, uy = math.cos(r), math.sin(r)
        cx, cy = f["at"]
        pts = [(cx + a * ux * d / 2 - b * uy * w / 2, cy + a * uy * d / 2 + b * ux * w / 2) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        discs.append((Polygon(pts), f["type"]))
    for g, name in discs:
        if not inner.contains(g):
            bad.append("%s at %s leaves the floor" % (name, [round(c, 1) for c in g.centroid.coords[0]]))
    for i, (g, a) in enumerate(discs):
        for h, b in discs[i + 1:]:
            if g.intersects(h) and g.intersection(h).area > 0.05:
                bad.append("%s and %s overlap at %s" % (a, b, [round(c, 1) for c in g.centroid.coords[0]]))
    for c in spec["carpets"]:
        line = LineString([c["a"], c["b"]])
        for g, name in discs:
            if name not in ("turntable",) and line.buffer(c["width"] / 2).intersects(g) and \
                    line.buffer(c["width"] / 2).intersection(g).area > 0.05 and name not in ("statue",):
                bad.append("carpet %s crosses %s" % ([round(x, 1) for x in c["a"]], name))
    return bad


def plot(path: str, spec: dict, ring: Polygon) -> None:
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = ring.bounds
    x0, y0, x1, y1 = x0 - 6, y0 - 6, x1 + 6, y1 + 6
    s = 8
    img = Image.new("RGB", (int((x1 - x0) * s), int((y1 - y0) * s)), "white")
    d = ImageDraw.Draw(img)
    f = lambda p: ((p[0] - x0) * s, (y1 - p[1]) * s)
    d.polygon([f(p) for p in ring.exterior.coords], fill=(245, 240, 228), outline=(0, 0, 0))
    for c in spec["carpets"]:
        g = LineString([c["a"], c["b"]]).buffer(c["width"] / 2, cap_style=2)
        d.polygon([f(p) for p in g.exterior.coords], fill=(180, 20, 30))
    for c in spec["cars"]:
        g = Point(c["at"]).buffer(PODIUM)
        d.polygon([f(p) for p in g.exterior.coords], outline=(200, 160, 50), fill=(255, 255, 255))
        r = math.radians(c["yaw"])
        d.line([f(c["at"]), f((c["at"][0] + 2.2 * math.cos(r), c["at"][1] + 2.2 * math.sin(r)))], fill=(0, 0, 200), width=3)
        d.text(f(c["at"]), c["model"], fill=(0, 0, 0))
    for t in spec["turntables"] + spec["statues"]:
        g = Point(t["at"]).buffer(3.6)
        d.polygon([f(p) for p in g.exterior.coords], outline=(200, 160, 50), fill=(230, 190, 60))
    for c in spec["columns"]:
        d.ellipse([f((c[0] - 0.4, c[1] + 0.4)), f((c[0] + 0.4, c[1] - 0.4))], fill=(200, 160, 50))
    for fu in spec["furniture"]:
        d.text(f(fu["at"]), fu["type"][:6], fill=(90, 60, 30))
        d.ellipse([f((fu["at"][0] - 0.5, fu["at"][1] + 0.5)), f((fu["at"][0] + 0.5, fu["at"][1] - 0.5))], fill=(90, 60, 30))
    for dr in spec["doors"]:
        d.ellipse([f((dr["at"][0] - 1, dr["at"][1] + 1)), f((dr["at"][0] + 1, dr["at"][1] - 1))], fill=(0, 160, 0))
    sm = spec["salesman"]["at"]
    d.ellipse([f((sm[0] - 0.5, sm[1] + 0.5)), f((sm[0] + 0.5, sm[1] - 0.5))], fill=(0, 0, 0))
    img.save(path)


def main() -> None:
    a = args()
    world = json.loads(WORLD.read_text())
    b = next(b for b in world["buildings"] if b["id"] == BUILDING)
    ring = Polygon(b["rings"][0])
    spec = layout()
    for p in check(spec, ring):
        print("warning:", p)
    if a["plot"]:
        plot(a["plot"], spec, ring)
    if a["dry-run"]:
        return
    out = json.loads(OUT.read_text()) if OUT.exists() else {}
    out[BUILDING] = spec
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print("wrote %s: %d cars, %d doors, %d furniture" % (OUT.relative_to(ROOT), len(spec["cars"]), len(spec["doors"]),
                                                        len(spec["furniture"])))


if __name__ == "__main__":
    main()
