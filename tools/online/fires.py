"""Fire spots of PTA Online's firefighter job (godot/scripts/online/fires.gd, ONLINE_MODE.md 5): godot/world/fires.json.

    .venv/bin/python tools/online/fires.py [--plot=/tmp/fires.png]

Where the server may light a fire (an alarm), within RADIUS m of the fire station and inside the playable area, each
one a fire truck can hose from a road: within REACH m of a bot bus or car path (roads the truck drives) with nothing
built in between (the water cannon throws ~60 m).
- building: the foot of a facade facing that road (one spot per facade side long enough, its middle); `yaw` the way
  the facade faces, `w` its width the flames take (at most W_MAX m);
- car: a parked car on fire in an OSM car park, off the bots' paths and away from the garages' bays (the game puts a
  burnt-out car there); `yaw` its heading; up to CARS_PER_LOT a car park;
- bin: a street bin (waste baskets, recycling, bus stop bins);
- grass, wood: a lawn or meadow (grass, tall grass) or a wood's floor (forest floor), SEED m apart at least: the game
  spreads them over the same ground at run time (scripts/ground_map.gd material_at).
A fire also spreads to the spots near it (fires.gd), so the facades of a building and the cars of a car park catch from
each other.

Each spot names what it burns by its source (OSM id, or the prop's source), so a rebuilt map only needs this rerun.
Positions are map coordinates (x east, y north; Godot = (x, height, -y)); yaw in degrees, 0 = north, turning east;
heights come from the game's ground at run time."""
import gc
import json
import math
import random
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot/world/world.json"
BUS_ROUTES = ROOT / "godot/world/bus_routes.json"
CAR_ROUTES = ROOT / "godot/world/car_routes.json"
GARAGES = ROOT / "godot/world/garages.json"
RACES = ROOT / "godot/world/races.json"
OUT = ROOT / "godot/world/fires.json"

STATION = (830.0, -151.0)                        # the fire station (garages.json "fire-station")
RADIUS = 2000.0                                  # m from it
REACH = 45.0                                     # m from a road (the truck on it, the cannon's reach to spare)
FACADE_MIN = 6.0                                 # m: a shorter facade side has no spot
W_MAX = 8.0                                      # m of facade a building fire takes
FACE = 0.35                                      # cos: the facade must face the road at least this much
CAR_STEP = 5.5                                   # m between the cars of a car park
CARS_PER_LOT = 6
CAR_CLEAR = {"route": 5.0, "building": 2.0, "tree": 2.0, "prop": 1.5, "garage": 20.0, "race": 6.0}
BINS = {"waste_basket", "recycling", "bus_bin", "waste_disposal"}
SEED = 45.0                                      # m between grass / wood seeds
GRASS = {"grass", "tall_grass"}
WOOD = {"forest_floor"}
PATCH_MIN = 400.0                                # m² of lawn or wood at least
EDGE_IN = 3.0                                    # m inside the patch's edge
KEEP = {"building": 1400, "car": 600, "bin": 500, "grass": 700, "wood": 300}   # at most, picked at random (seeded)


def args() -> dict:
    out = {"plot": ""}
    for a in sys.argv[1:]:
        if a.startswith("--plot="):
            out["plot"] = a.split("=", 1)[1]
    return out


def read_sections(path: Path, keys: tuple) -> dict:
    """Top-level `keys` of the big world.json: its values decoded one after the other, those not wanted dropped at
    once (json.loads of the whole file takes over 4 GB: its ground mesh index and building modules are most of it)."""
    text = path.read_text()
    dec = json.JSONDecoder()
    out = {}
    i = text.index("{") + 1
    while True:
        while text[i] in " \n\r\t,":
            i += 1
        if text[i] == "}":
            break
        key, i = dec.raw_decode(text, i)
        i = text.index(":", i) + 1
        while text[i] in " \n\r\t":
            i += 1
        value, i = dec.raw_decode(text, i)
        if key in keys:
            out[key] = value
        del value
    missing = [k for k in keys if k not in out]
    if missing:
        raise SystemExit("world.json has no %s" % ", ".join(missing))
    return out


def ring_polygon(rings: list) -> Polygon | None:
    if not rings or len(rings[0]) < 3:
        return None
    p = Polygon(rings[0], [r for r in rings[1:] if len(r) >= 3])
    return p if p.is_valid else p.buffer(0)


def yaw_of(dx: float, dy: float) -> float:
    """Degrees, 0 north, turning east."""
    return round(math.degrees(math.atan2(dx, dy)) % 360.0, 1)


class World:
    """Only what the spots need from world.json, which is freed as soon as it is read (the file is ~100 MB: the
    whole of it as Python objects takes several GB)."""

    def __init__(self) -> None:
        w = read_sections(WORLD, ("meta", "buildings", "ground", "trees", "props"))
        self.area = unary_union([Polygon(r) for r in w["meta"]["playable_area"]]).buffer(-10.0) \
            if "playable_area" in w["meta"] else None
        self.near = Point(*STATION).buffer(RADIUS)
        if self.area is not None:
            self.near = self.near.intersection(self.area)
        self.near_p = prep(self.near)
        zone = self.near.buffer(REACH)
        zone_p = prep(zone)
        self.buildings = []                      # (polygon, {"id", "name", "src", "walls"})
        for b in w["buildings"]:
            p = ring_polygon(b["rings"])
            if p is not None and not p.is_empty and zone_p.intersects(p):
                src = b["src"].get("osm", "") if isinstance(b.get("src"), dict) else ""
                self.buildings.append((p, {"id": b["id"], "name": b.get("name") or "", "src": src,
                                           "walls": b.get("walls", True)}))
        self.grounds = []                        # (polygon, {"kind", "material", "src"})
        for g in w["ground"]:
            if g["kind"] == "parking" or g["material"] in GRASS | WOOD:
                p = ring_polygon(g["rings"])
                if p is not None and not p.is_empty and self.near_p.intersects(p):
                    self.grounds.append((p, {"kind": g["kind"], "material": g["material"], "src": g.get("src", [])[:1]}))
        self.trees = [Point(t["x"], t["y"]) for t in w["trees"] if self.near_p.contains(Point(t["x"], t["y"]))]
        self.props = []                          # the props near (bins and the rest: obstacles for the cars)
        for q in w["props"]:
            if zone_p.contains(Point(q["x"], q["y"])):
                self.props.append({k: q[k] for k in ("id", "kind", "x", "y", "yaw", "osm", "info") if k in q})
        del w
        gc.collect()
        self.prop_pts = [Point(q["x"], q["y"]) for q in self.props]
        self.walls = STRtree([p for p, _b in self.buildings])
        self.routes = []
        for path in (BUS_ROUTES, CAR_ROUTES):
            for r in json.loads(path.read_text())["routes"].values():
                if len(r["pts"]) >= 2:
                    line = LineString([(q[0], q[1]) for q in r["pts"]])
                    if zone_p.intersects(line):
                        self.routes.append(line.simplify(0.3))
        # an index of the paths, not their union: the 65 paths overlap all along, and merging them (then buffering
        # the result) takes GBs
        self.road_index = STRtree(self.routes)
        avoid = []
        for g in json.loads(GARAGES.read_text())["garages"]:
            for b in g["bays"] + [g["terminal"]]:
                avoid.append(Point(b["x"], b["y"]).buffer(CAR_CLEAR["garage"]))
        for r in json.loads(RACES.read_text())["races"]:
            for key in ("start", "finish"):
                c = r.get(key)
                if c:
                    avoid.append(Point(c["x"], c["y"]).buffer(c["r"] + CAR_CLEAR["race"]))
        self.avoid = prep(unary_union(avoid))
        print("read: %d buildings, %d ground pieces, %d trees, %d props, %d bot paths" % (
            len(self.buildings), len(self.grounds), len(self.trees), len(self.props), len(self.routes)), flush=True)

    def road_point(self, p: Point) -> tuple:
        """(the nearest point of a bot path within REACH of `p`, metres), or (None, inf)."""
        best, best_d = None, math.inf
        for i in self.road_index.query(p.buffer(REACH)):
            line = self.routes[i]
            d = line.distance(p)
            if d < best_d:
                best, best_d = line.interpolate(line.project(p)), d
        return best, best_d

    def clear_line(self, a: Point, b: Point, skip: Polygon | None = None) -> bool:
        """Nothing built between a and b (but `skip`, the burning building itself)."""
        line = LineString([a, b])
        for i in self.walls.query(line):
            p = self.buildings[i][0]
            if p is not skip and p.buffer(-0.3).intersects(line):
                return False
        return True

    def reachable(self, p: Point, skip: Polygon | None = None) -> tuple:
        """(the road point the truck hoses `p` from, metres) when within REACH with a clear line, else (None, inf)."""
        if not self.near_p.contains(p):
            return None, math.inf
        r, d = self.road_point(p)
        if r is None or d > REACH or not self.clear_line(r, p, skip):
            return None, math.inf
        return r, d


def buildings(w: World) -> list:
    out = []
    for poly, b in w.buildings:
        if not b["walls"] or poly.geom_type != "Polygon":
            continue
        ring = list(poly.exterior.coords)
        ccw = poly.exterior.is_ccw
        for k in range(len(ring) - 1):
            (x0, y0), (x1, y1) = ring[k], ring[k + 1]
            length = math.hypot(x1 - x0, y1 - y0)
            if length < FACADE_MIN:
                continue
            ux, uy = (x1 - x0) / length, (y1 - y0) / length
            nx, ny = (uy, -ux) if ccw else (-uy, ux)          # outward
            mx, my = (x0 + x1) * 0.5, (y0 + y1) * 0.5
            out_p = Point(mx + nx * 1.0, my + ny * 1.0)
            if poly.contains(out_p):
                continue
            r, d = w.reachable(out_p, poly)
            if r is None:
                continue
            tx, ty = (r.x - out_p.x) / max(d, 0.01), (r.y - out_p.y) / max(d, 0.01)
            if d > 1.0 and tx * nx + ty * ny < FACE:
                continue
            osm = b["src"]
            out.append({"kind": "building", "x": round(mx + nx * 0.3, 2), "y": round(my + ny * 0.3, 2),
                        "yaw": yaw_of(nx, ny), "w": round(min(length - 1.0, W_MAX), 1),
                        "name": b["name"], "src": osm or str(b["id"]), "side": k})
    return out


def cars(w: World) -> list:
    out = []
    obst = [t.buffer(CAR_CLEAR["tree"]) for t in w.trees]
    obst += [p.buffer(CAR_CLEAR["prop"]) for p in w.prop_pts if w.near_p.contains(p)]
    obst += [p.buffer(CAR_CLEAR["building"]) for p, _b in w.buildings]
    obst += [r.buffer(CAR_CLEAR["route"]) for r in w.routes]
    tree = STRtree(obst)
    for poly, g in w.grounds:
        if g["kind"] != "parking" or poly.area < 120.0:
            continue
        rect = poly.minimum_rotated_rectangle
        c = list(rect.exterior.coords)
        e0 = (c[1][0] - c[0][0], c[1][1] - c[0][1])
        e1 = (c[2][0] - c[1][0], c[2][1] - c[1][1])
        along = e0 if math.hypot(*e0) >= math.hypot(*e1) else e1    # the lot's long side: cars park across it
        la = math.hypot(*along)
        ax, ay = along[0] / la, along[1] / la
        inner = poly.buffer(-2.2)
        if inner.is_empty:
            continue
        inner_p = prep(inner)
        minx, miny, maxx, maxy = inner.bounds
        picked = []
        cx, cy = inner.centroid.x, inner.centroid.y
        cands = []
        for ix in range(int((maxx - minx) / CAR_STEP) + 2):
            for iy in range(int((maxy - miny) / CAR_STEP) + 2):
                x, y = minx + ix * CAR_STEP, miny + iy * CAR_STEP
                cands.append((math.hypot(x - cx, y - cy), x, y))
        cands.sort()
        for _d, x, y in cands:
            p = Point(x, y)
            if not inner_p.contains(p) or w.avoid.contains(p):
                continue
            body = p.buffer(2.4)
            if any(obst[i].intersects(body) for i in tree.query(body)):
                continue
            if any(math.hypot(x - q[0], y - q[1]) < CAR_STEP for q in picked):
                continue
            r, _dist = w.reachable(p)
            if r is None:
                continue
            picked.append((x, y))
            src = g["src"][0].removeprefix("osm:") if g["src"] else ""
            out.append({"kind": "car", "x": round(x, 2), "y": round(y, 2), "yaw": yaw_of(-ay, ax), "name": "",
                        "src": src})
            if len(picked) >= CARS_PER_LOT:
                break
    return out


def bins(w: World) -> list:
    out = []
    for p, pt in zip(w.props, w.prop_pts):
        if p["kind"] not in BINS:
            continue
        r, _d = w.reachable(pt)
        if r is None:
            continue
        src = p.get("osm") or ("mapillary:" + p["info"]["mapillary"] if p.get("info", {}).get("mapillary") else p["id"])
        out.append({"kind": "bin", "x": round(p["x"], 2), "y": round(p["y"], 2), "yaw": round(float(p.get("yaw", 0.0)), 1),
                    "name": "", "src": src})
    return out


def patches(w: World, kind: str, materials: set) -> list:
    out = []
    taken = []
    for poly, g in w.grounds:
        if g["material"] not in materials or poly.area < PATCH_MIN:
            continue
        inner = poly.buffer(-EDGE_IN)
        if inner.is_empty:
            continue
        if not w.road_index.query(inner.buffer(REACH), predicate="intersects").size:
            continue
        inner_p = prep(inner)
        minx, miny, maxx, maxy = inner.bounds
        step = 6.0
        cands = []
        for ix in range(int((maxx - minx) / step) + 1):
            for iy in range(int((maxy - miny) / step) + 1):
                p = Point(minx + ix * step, miny + iy * step)
                if inner_p.contains(p):
                    cands.append(p)
        random.Random(len(out)).shuffle(cands)
        for p in cands:
            if any(math.hypot(p.x - q[0], p.y - q[1]) < SEED for q in taken):
                continue
            r, _d = w.reachable(p)
            if r is None:
                continue
            taken.append((p.x, p.y))
            src = g["src"][0].removeprefix("osm:") if g.get("src") else ""
            out.append({"kind": kind, "x": round(p.x, 2), "y": round(p.y, 2), "yaw": 0.0, "name": "", "src": src})
    return out


def plot(path: str, w: World, spots: list) -> None:
    from PIL import Image, ImageDraw

    size, span = 1600, RADIUS * 2.2
    k = size / span
    img = Image.new("RGB", (size, size), (30, 32, 36))
    d = ImageDraw.Draw(img)

    def px(x, y):
        return ((x - STATION[0]) * k + size / 2, (STATION[1] - y) * k + size / 2)

    for line in w.routes:
        d.line([px(*c) for c in line.coords], fill=(80, 90, 110), width=1)
    colours = {"building": (255, 90, 60), "car": (80, 160, 255), "bin": (240, 220, 80), "grass": (100, 220, 90),
               "wood": (30, 140, 60)}
    for s in spots:
        x, y = px(s["x"], s["y"])
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=colours[s["kind"]])
    x, y = px(*STATION)
    d.rectangle([x - 6, y - 6, x + 6, y + 6], outline=(255, 255, 255))
    img.save(path)
    print("plot -> %s" % path)


def main() -> None:
    opt = args()
    w = World()
    spots = []
    for kind, found in [("building", buildings(w)), ("car", cars(w)), ("bin", bins(w)),
                        ("grass", patches(w, "grass", GRASS)), ("wood", patches(w, "wood", WOOD))]:
        n = len(found)
        if n > KEEP[kind]:
            found = random.Random(kind).sample(found, KEEP[kind])
        found.sort(key=lambda s: (s["x"], s["y"]))
        print("%-8s %5d spots (%d found)" % (kind, len(found), n))
        spots += found
    for i, s in enumerate(spots):
        s["id"] = i + 1
    OUT.write_text(json.dumps({"schema": 1, "about": "PTA Online fire spots: tools/online/fires.py", "station": STATION,
                               "spots": spots}, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("%d spots -> %s (%d kB)" % (len(spots), OUT.relative_to(ROOT), OUT.stat().st_size // 1024))
    if opt["plot"]:
        plot(opt["plot"], w, spots)


if __name__ == "__main__":
    main()
