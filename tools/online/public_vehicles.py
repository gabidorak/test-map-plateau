"""PTA Online's public vehicles (godot/scripts/online/public_vehicles.gd): godot/data/public_vehicles.json.

    .venv/Scripts/python.exe tools/online/public_vehicles.py [--plot=/tmp/public.png]

Vehicles of nobody's garage, parked at fixed places, that any player may take (the police helicopter on the big car park
of Polytechnique by the lake, until the game sells helicopters). Each one gets a spot found in its car park (OSM id) the
way tools/online/garages.py finds bays (on paved ground, clear of buildings, trees, fences, raised kerbs, street
furniture, water, the bots' paths and the races' start circles), but with the room a helicopter needs: its footprint
(the fuselage and tail boom) and its rotor's disc, kept from the trees' crowns and the buildings' walls by ROTOR_CLEAR,
and away from the garages' bays and terminals. The nearest spot to the car park's middle (or a target) wins.
Positions are map coordinates (x east, y north); yaw in degrees, 0 = facing north, turning towards east (garages.py's).
Rerun it when the map changes (it reads godot/world/: the map data, see README.md "Map data").
"""
import json
import math
import sys
from pathlib import Path

from shapely import affinity
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
from shapely.prepared import prep

sys.path.insert(0, str(Path(__file__).resolve().parent))
import garages  # noqa: E402  (its world loading, car parks and clearances)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/data/public_vehicles.json"
GARAGES = ROOT / "godot/world/garages.json"
ROTOR_CLEAR = 3.0                                 # m between the rotor's tips and a tree's crown or a wall
BAY_CLEAR = 3.0                                   # m from a garage's bay or terminal
ROUTE_CLEAR = 5.0                                 # m from a bot's path
VEHICLES = [
    {"id": "x-police-heli", "model": "helicopter-police", "name": "Polytechnique - Lac", "osm": ["w30025558"],
     # the helicopter (scripts/helicopter.gd): rotor disc radius and centre (car frame z), the fuselage's box
     "rotor": [3.95, 0.27], "body": [-7.6, 4.0, 1.6]},
]


def footprint(x: float, y: float, yaw: float, v: dict):
    """The ground a vehicle at (x, y) facing `yaw` covers: its rotor's disc (with ROTOR_CLEAR) and its fuselage."""
    r, rz = v["rotor"]
    z0, z1, hw = v["body"]
    shape = unary_union([Point(0.0, rz).buffer(r + ROTOR_CLEAR), box(-hw, z0 - 1.0, hw, z1 + 1.0)])
    return affinity.translate(affinity.rotate(shape, -yaw, origin=(0, 0)), x, y)


def obstacles(world: dict, raw: dict, area) -> object:
    near = area.buffer(30.0)
    out = [o for o in world["obstacles"] if o.intersects(near)]
    for t in raw["trees"]:                        # their crowns, not just their trunks
        p = Point(t["x"], t["y"])
        if p.distance(near) < 10.0:
            out.append(p.buffer(float(t.get("r", 2.0)) + 1.0))
    for b in raw["buildings"]:
        ring = garages.ring_polygon(b["rings"])
        if ring is not None and ring.distance(near) < 10.0:
            out.append(ring.buffer(ROTOR_CLEAR))
    for g in json.loads(GARAGES.read_text(encoding="utf-8"))["garages"]:
        for b in g["bays"]:
            s = affinity.rotate(box(-b["w"] / 2, -b["l"] / 2, b["w"] / 2, b["l"] / 2), -b["yaw"], origin=(0, 0))
            out.append(affinity.translate(s, b["x"], b["y"]).buffer(BAY_CLEAR))
        out.append(Point(g["terminal"]["x"], g["terminal"]["y"]).buffer(BAY_CLEAR + 1.0))
    routes = [r for r in world["routes"] if r.intersects(near)]
    if routes:
        out.append(unary_union(routes).buffer(ROUTE_CLEAR))
    return unary_union(out)


def place(v: dict, world: dict, raw: dict) -> dict | None:
    parts = [p for o in v["osm"] for p in world["parks"].get(o, [])]
    if not parts:
        print("%s: no car park %s on the map" % (v["id"], v["osm"]))
        return None
    lot = unary_union(parts)
    area = lot.buffer(2.0)
    paved = unary_union([p for p in world["paved"] if p.intersects(area)]).intersection(area)
    free = paved.difference(obstacles(world, raw, area))
    if free.is_empty:
        print("%s: no free paved ground" % v["id"])
        return None
    free_p = prep(free)
    target = v.get("target") or (lot.centroid.x, lot.centroid.y)
    minx, miny, maxx, maxy = free.bounds
    cands = sorted((math.hypot(ix - target[0], iy - target[1]), float(ix), float(iy))
                   for ix in range(int(minx), int(maxx) + 1) for iy in range(int(miny), int(maxy) + 1))
    for _, x, y in cands:
        if not free_p.contains(Point(x, y)):
            continue
        for k in range(24):
            yaw = k * 15.0
            if free_p.contains(footprint(x, y, yaw, v)):
                return {"id": v["id"], "model": v["model"], "name": v["name"], "x": x, "y": y, "yaw": yaw}
    print("%s: no room in %s" % (v["id"], v["osm"]))
    return None


def main() -> None:
    raw = json.loads(garages.WORLD.read_text(encoding="utf-8"))
    world = garages.load()
    out = [p for p in (place(v, world, raw) for v in VEHICLES) if p]
    for p in out:
        print("%s: %s at (%.0f, %.0f) facing %.0f°" % (p["id"], p["model"], p["x"], p["y"], p["yaw"]))
    OUT.write_text(json.dumps({
        "about": "PTA Online's public vehicles (scripts/online/public_vehicles.gd), made by "
                 "tools/online/public_vehicles.py: any player may take them; nobody's garage. x, y map coordinates "
                 "(x east, y north), yaw degrees (0 north, clockwise).",
        "vehicles": out}, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
