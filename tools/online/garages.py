"""Garages of PTA Online (godot/scripts/online/garages.gd, ONLINE_MODE.md 4): godot/world/garages.json.

    .venv/bin/python tools/online/garages.py [--plot=/tmp/garages.png] [--only=id,id]

The only places a player's vehicle appears online. Each garage is a row of spawn bays side by side and a terminal (E)
beside the row's first bay:
- public garages on OSM car parks, spread so one is never far on the campus (fewer along the Massy and west
  corridors); a "big" bay takes the long and wide vehicles (truck + trailer, biplane);
- the bus depot at Massy-Palaiseau station (buses only, bus drivers);
- the fire station at Polytechnique, building #1289 "SPIS" (osm:w1063984911, an open canopy 2.9 m high: the 3.1 m
  fire truck doesn't fit under it, so the bays are beside it), fire trucks only;
- Prestige Motors' delivery bays, by its main door (the shop, scripts/online/shop.gd: a vehicle bought there comes out
  on them; its terminal works as a public garage's).

Each garage names its car park by OSM id (or a point and a radius, for the depot and the fire station), so a rebuilt
map only needs this rerun. The bays are searched (position on a 1 m grid, heading every 5°, nearest the target first)
on paved ground (parking, roads, asphalt/concrete/paving) inside the car park, clear of buildings, trees, hedges,
fences, raised kerbs, street furniture, water, railways, the races' start circles and the bot buses' and cars' paths (so
the bots never meet a vehicle standing in a bay). The terminal stands beside the first bay, it and the spot in front of
it where the game puts players on paved ground clear of obstacles.

Positions are map coordinates (x east, y north; Godot = (x, height, -y)); yaw in degrees, 0 = facing north (+y), turning
towards east; heights come from the game's ground at run time. Check them in the game: tools/test_online_rules.gd."""
import json
import math
import sys
from pathlib import Path

from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.prepared import prep

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot/world/world.json"
BUS_ROUTES = ROOT / "godot/world/bus_routes.json"
CAR_ROUTES = ROOT / "godot/world/car_routes.json"
RACES = ROOT / "godot/world/races.json"
RAIL = ROOT / "godot/world/rail.json"
OUT = ROOT / "godot/world/garages.json"

# bay sizes (m, width x length): what fits is decided in the game from each vehicle's size
CAR = (3.4, 6.4)
BIG = (8.0, 20.0)
BUS = (4.0, 20.5)
TRUCK = (4.0, 11.0)

PAVED_KINDS = {"parking", "road", "pedestrian", "service"}
PAVED_MATERIALS = {"asphalt", "concrete", "paving", "sett"}
CLEAR = {"building": 1.0, "trunk": 1.1, "fence": 0.7, "kerb": 0.35, "route": 3.6, "water": 1.0, "rail": 4.0}
PROP_CLEAR = {"caravan": 4.0, "van": 3.5, "bus_shelter": 2.5, "shelter": 3.0, "awning": 2.5, "substation": 3.0,
              "water_tank": 2.0, "advertising": 1.5}
PROP_DEFAULT = 0.9
TERMINAL_OUT = 1.3                               # m from the first bay's side
TERMINAL_CLEAR = 0.6                             # m round the terminal
STAND = 1.5                                      # m in front of it, where the game puts a player (garages.gd STAND)

# id, name shown, kind, where: OSM ids of the car park, or (x, y, radius) to search round; target (x, y) the row
# is pulled to (None: the car park's middle); bays
GARAGES = [
    {"id": "telecom", "name": "Télécom Paris", "kind": "public", "osm": ["w648440416"], "bays": [CAR, CAR, CAR]},
    {"id": "ensae", "name": "ENSAE - C2N", "kind": "public", "osm": ["w1564824552"], "bays": [BIG, CAR, CAR, CAR]},
    {"id": "x-lake", "name": "Polytechnique - Lac", "kind": "public", "osm": ["w30025558"], "target": (860.0, 150.0),
     "bays": [BIG, CAR, CAR, CAR]},
    {"id": "x-hall", "name": "Polytechnique - Grand Hall", "kind": "public", "osm": ["w170525718"],
     "bays": [CAR, CAR, CAR]},
    {"id": "ensta", "name": "ENSTA Paris", "kind": "public", "osm": ["w198188346"], "bays": [CAR, CAR, CAR]},
    {"id": "le-guichet", "name": "Le Guichet", "kind": "public", "osm": ["w42231682"], "bays": [CAR, CAR, CAR]},
    {"id": "centrale", "name": "CentraleSupélec", "kind": "public", "osm": ["w48240404"], "bays": [CAR, CAR, CAR]},
    {"id": "massy-ouest", "name": "Massy - Les Champarts", "kind": "public", "osm": ["w218949739"],
     "bays": [BIG, CAR, CAR]},
    {"id": "massy", "name": "Massy-Palaiseau", "kind": "public", "osm": ["w26250186"], "bays": [CAR, CAR, CAR]},
    {"id": "bus-depot", "name": "Bus depot - Massy-Palaiseau", "kind": "depot", "near": (4378.0, 1188.0, 140.0),
     "bays": [BUS, BUS]},
    {"id": "fire-station", "name": "Fire station - Polytechnique", "kind": "fire", "near": (830.0, -151.0, 45.0),
     "bays": [TRUCK, TRUCK]},
    {"id": "prestige-motors", "name": "Prestige Motors", "kind": "shop", "near": (276.3, 18.0, 70.0),
     "target": (287.0, 15.0), "bays": [CAR, CAR, CAR]},
]


def args() -> dict:
    out = {"plot": "", "only": []}
    for a in sys.argv[1:]:
        if a.startswith("--plot="):
            out["plot"] = a.split("=", 1)[1]
        elif a.startswith("--only="):
            out["only"] = a.split("=", 1)[1].split(",")
    return out


def ring_polygon(rings: list) -> Polygon | None:
    if not rings or len(rings[0]) < 3:
        return None
    p = Polygon(rings[0], [r for r in rings[1:] if len(r) >= 3])
    return p if p.is_valid else p.buffer(0)


def load() -> dict:
    w = json.loads(WORLD.read_text())
    paved, parks, water, rails = [], {}, [], []
    for g in w["ground"]:
        p = ring_polygon(g["rings"])
        if p is None or p.is_empty:
            continue
        if g["kind"] == "water":
            water.append(p)
        if g["kind"] == "railway":
            rails.append(p)
        if g["kind"] in PAVED_KINDS or (g["material"] in PAVED_MATERIALS and g["kind"] not in ("building", "steps")):
            paved.append(p)
        if g["kind"] == "parking":
            for src in g["src"]:
                parks.setdefault(src.removeprefix("osm:"), []).append(p)
    obstacles = []                               # (geometry, kind) already buffered by its clearance
    for b in w["buildings"]:
        p = ring_polygon(b["rings"])
        if p is not None:
            obstacles.append(p.buffer(CLEAR["building"]))
    for t in w["trees"]:
        obstacles.append(Point(t["x"], t["y"]).buffer(CLEAR["trunk"]))
    for h in w["hedges"]:
        obstacles.append(LineString(h["pts"]).buffer(h["w"] * 0.5 + 0.5))
    for f in w["fences"]:
        obstacles.append(LineString(f["pts"]).buffer(CLEAR["fence"]))
    for k in w["kerbs"]:
        if k["kind"] == "raised" and len(k["pts"]) >= 2:
            obstacles.append(LineString(k["pts"]).buffer(CLEAR["kerb"]))
    for p in w["props"]:
        obstacles.append(Point(p["x"], p["y"]).buffer(PROP_CLEAR.get(p["kind"], PROP_DEFAULT)))
    for p in water:
        obstacles.append(p.buffer(CLEAR["water"]))
    for p in rails:
        obstacles.append(p.buffer(1.0))
    for s in json.loads(RAIL.read_text())["services"]:
        obstacles.append(LineString([(q[0], q[1]) for q in s["pts"]]).buffer(CLEAR["rail"]))
    for r in json.loads(RACES.read_text())["races"]:
        for key in ("start", "finish"):
            c = r.get(key)
            if c:
                obstacles.append(Point(c["x"], c["y"]).buffer(c["r"] + 2.0))
    routes = []
    for path in (BUS_ROUTES, CAR_ROUTES):
        for r in json.loads(path.read_text())["routes"].values():
            if len(r["pts"]) >= 2:
                routes.append(LineString([(p[0], p[1]) for p in r["pts"]]))
    return {"paved": paved, "parks": parks, "obstacles": obstacles, "routes": routes, "water": water}


def row_shapes(x: float, y: float, yaw: float, bays: list) -> list:
    """The bays of a row whose first bay's centre is at (x, y), facing `yaw` (deg, 0 north, clockwise): bays side by
    side towards the row's right (east when facing north), each its own rectangle."""
    out, offset = [], 0.0
    a = math.radians(yaw)
    fwd = (math.sin(a), math.cos(a))
    right = (fwd[1], -fwd[0])
    for i, (bw, bl) in enumerate(bays):
        if i > 0:
            offset += (bays[i - 1][0] + bw) * 0.5
        cx, cy = x + right[0] * offset, y + right[1] * offset
        r = box(-bw / 2, -bl / 2, bw / 2, bl / 2)
        r = affinity.rotate(r, -yaw, origin=(0, 0))
        out.append((affinity.translate(r, cx, cy), cx, cy))
    return out


def terminal_spot(x: float, y: float, yaw: float, bays: list) -> tuple:
    a = math.radians(yaw)
    fwd = (math.sin(a), math.cos(a))
    right = (fwd[1], -fwd[0])
    d = bays[0][0] * 0.5 + TERMINAL_OUT
    # beside the first bay, a little forward of its middle (where a player walks up from the aisle)
    along = bays[0][1] * 0.25
    tx, ty = x - right[0] * d + fwd[0] * along, y - right[1] * d + fwd[1] * along
    return tx, ty, (yaw + 90.0) % 360.0           # facing the bays (east of the terminal when the row faces north)


def place(g: dict, world: dict) -> dict | None:
    if "osm" in g:
        parts = [p for o in g["osm"] for p in world["parks"].get(o, [])]
        if not parts:
            print("%s: no car park %s on the map" % (g["id"], g["osm"]))
            return None
        lot = unary_union(parts)
        area = lot.buffer(3.0)
        target = g.get("target") or (lot.centroid.x, lot.centroid.y)
    else:
        cx, cy, r = g["near"]
        area = Point(cx, cy).buffer(r)
        target = g.get("target") or (cx, cy)
    paved = unary_union([p for p in world["paved"] if p.intersects(area)]).intersection(area)
    obst = unary_union([o for o in world["obstacles"] if o.intersects(area.buffer(5.0))])
    routes = unary_union([r for r in world["routes"] if r.intersects(area.buffer(5.0))])
    if not routes.is_empty:
        obst = obst.union(routes.buffer(CLEAR["route"]))
    free = paved.difference(obst)
    if free.is_empty:
        print("%s: no free paved ground" % g["id"])
        return None
    free_p = prep(free)
    near = area.buffer(10.0)
    clear_p = prep(unary_union([p for p in world["paved"] if p.intersects(near)]).intersection(near).difference(obst))
    bays = g["bays"]
    row_w = sum(b[0] for b in bays)
    reach = max(row_w, max(b[1] for b in bays)) * 0.5
    minx, miny, maxx, maxy = free.bounds
    cands = []
    for ix in range(int(minx), int(maxx) + 1):
        for iy in range(int(miny), int(maxy) + 1):
            cands.append((math.hypot(ix - target[0], iy - target[1]), float(ix), float(iy)))
    cands.sort()
    inner = free.buffer(-min(b[0] for b in bays) * 0.5 + 0.05)
    inner_p = prep(inner) if not inner.is_empty else None
    for d, x, y in cands:
        if inner_p is None or not inner_p.contains(Point(x, y)):
            continue
        for k in range(72):
            yaw = k * 5.0
            shapes = row_shapes(x, y, yaw, bays)
            if not all(free_p.contains(s[0]) for s in shapes):
                continue
            tx, ty, tyaw = terminal_spot(x, y, yaw, bays)
            a = math.radians(tyaw)
            sx, sy = tx - math.sin(a) * STAND, ty - math.cos(a) * STAND
            if not clear_p.contains(Point(tx, ty).buffer(TERMINAL_CLEAR)) or not clear_p.contains(Point(sx, sy).buffer(0.5)):
                continue
            return {
                "id": g["id"], "name": g["name"], "kind": g["kind"],
                "osm": g.get("osm", []),
                "terminal": {"x": round(tx, 2), "y": round(ty, 2), "yaw": round(tyaw, 1)},
                "bays": [{"x": round(cx, 2), "y": round(cy, 2), "yaw": round(yaw, 1), "w": b[0], "l": b[1]}
                         for (s, cx, cy), b in zip(shapes, bays)],
            }
        if d > reach + 400.0:
            break
    print("%s: no room for %d bays" % (g["id"], len(bays)))
    return None


def plot(path: str, world: dict, garages: list) -> None:
    """One tile per garage, 80 m across: paved ground grey, obstacles red, bot paths blue, bays green, terminal gold."""
    from PIL import Image, ImageDraw

    tile, span = 400, 80.0
    cols = 4
    rows = (len(garages) + cols - 1) // cols
    img = Image.new("RGB", (tile * cols, tile * rows), (30, 32, 36))
    d = ImageDraw.Draw(img)
    for i, g in enumerate(garages):
        ox, oy = (i % cols) * tile, (i // cols) * tile
        cx = sum(b["x"] for b in g["bays"]) / len(g["bays"])
        cy = sum(b["y"] for b in g["bays"]) / len(g["bays"])
        k = tile / span
        view = box(cx - span / 2, cy - span / 2, cx + span / 2, cy + span / 2)

        def px(x, y):
            return (ox + (x - cx + span / 2) * k, oy + (cy + span / 2 - y) * k)

        def poly(geom, fill=None, outline=None):
            for p in getattr(geom, "geoms", [geom]):
                if p.is_empty or p.geom_type != "Polygon":
                    continue
                d.polygon([px(*c) for c in p.exterior.coords], fill=fill, outline=outline)

        for p in world["paved"]:
            if p.intersects(view):
                poly(p.intersection(view), fill=(90, 92, 98))
        for o in world["obstacles"]:
            if o.intersects(view):
                poly(o.intersection(view), outline=(220, 70, 60))
        for r in world["routes"]:
            if r.intersects(view):
                seg = r.intersection(view)
                for s in getattr(seg, "geoms", [seg]):
                    if s.geom_type == "LineString":
                        d.line([px(*c) for c in s.coords], fill=(80, 150, 255), width=2)
        for (s, _x, _y) in row_shapes(g["bays"][0]["x"], g["bays"][0]["y"], g["bays"][0]["yaw"],
                                        [(b["w"], b["l"]) for b in g["bays"]]):
            poly(s, outline=(90, 230, 120))
        t = g["terminal"]
        tx, ty = px(t["x"], t["y"])
        d.ellipse([tx - 5, ty - 5, tx + 5, ty + 5], fill=(255, 200, 60))
        d.text((ox + 6, oy + 6), "%s (%s)" % (g["name"], g["kind"]), fill=(255, 255, 255))
        d.rectangle([ox, oy, ox + tile - 1, oy + tile - 1], outline=(0, 0, 0))
    img.save(path)
    print("plot -> %s" % path)


def main() -> None:
    opt = args()
    world = load()
    old = {g["id"]: g for g in json.loads(OUT.read_text())["garages"]} if OUT.exists() and opt["only"] else {}
    out = []
    for g in GARAGES:
        if opt["only"] and g["id"] not in opt["only"]:
            if g["id"] in old:
                out.append(old[g["id"]])
            continue
        done = place(g, world)
        if done is None:
            sys.exit(1)
        out.append(done)
        b = done["bays"][0]
        print("%-14s %-30s bays at (%.0f, %.0f) yaw %.0f" % (done["id"], done["name"], b["x"], b["y"], b["yaw"]))
    OUT.write_text(json.dumps({"schema": 1, "about": "PTA Online garages: tools/online/garages.py", "garages": out},
                              ensure_ascii=False, indent=1) + "\n")
    print("%d garages -> %s" % (len(out), OUT.relative_to(ROOT)))
    if opt["plot"]:
        plot(opt["plot"], world, out)


if __name__ == "__main__":
    main()
