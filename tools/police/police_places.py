"""The police's places (scripts/police/police.gd): godot/data/police.json.

    .venv/Scripts/python.exe tools/police/police_places.py

- "heli_base": where the police helicopter stands when it is not flying: the clear spot nearest the sous-préfecture de
  Palaiseau (OSM r20158551, on the plateau) on paved ground or grass, with the room a helicopter needs (its footprint
  and rotor kept from the trees' crowns and the walls: tools/online/public_vehicles.py), off the bots' paths, away from
  line 18 (its viaduct and stations are lots, not in godot/world/: their master plan, godot/lots/ligne18/plan.json).
- "release": where an arrested player is let go: on the paved ground (a sidewalk, a car park) nearest the
  sous-préfecture, RELEASE_WALL m from its walls at least, clear of the street furniture and the trees, facing away from
  the building.
Positions are map coordinates (x east, y north); yaw in degrees, 0 = facing north, turning towards east. Rerun it when
the map changes (it reads godot/world/).
"""
import json
import math
import sys
from pathlib import Path

from shapely.geometry import LineString, Point
from shapely.ops import unary_union
from shapely.prepared import prep

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "online"))
import garages  # noqa: E402
import public_vehicles  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/data/police.json"
SOUS_PREFECTURE = "osm:r20158551"
REACH = 250.0                                   # m from the building the helicopter's spot is looked for
RELEASE_WALL = 3.0                              # m from the walls the release spot keeps
HELI = {"rotor": [3.95, 0.27], "body": [-7.6, 4.0, 1.6]}
GRASS = {"grass", "tall_grass"}
LINE18 = ROOT / "godot/lots/ligne18/plan.json"
LINE18_CLEAR = 12.0                             # m from line 18's axis kept clear: its deck (4.85 m), the trains...
STATION_CLEAR = 22.0                            # ...and along its stations


def line18() -> object:
    """Line 18 above the ground (its viaduct, its track at grade, its stations): the axis of its master plan, widened."""
    plan = json.loads(LINE18.read_text(encoding="utf-8"))
    col = {c: i for i, c in enumerate(plan["axis_columns"])}
    shapes, run = [], []
    for r in plan["axis"] + [None]:
        if r is not None and r[col["kind"]] != "tunnel":
            run.append((r[col["x"]], r[col["y"]]))
            continue
        if len(run) >= 2:
            shapes.append(LineString(run).buffer(LINE18_CLEAR))
        run = []
    for st in plan["stations"].values():
        s0, s1 = st["zone_s"]
        pts = [(r[col["x"]], r[col["y"]]) for r in plan["axis"] if s0 <= r[col["s"]] <= s1]
        if len(pts) >= 2:
            shapes.append(LineString(pts).buffer(STATION_CLEAR))
    return unary_union(shapes)


def main() -> None:
    raw = json.loads(garages.WORLD.read_text(encoding="utf-8"))
    world = garages.load()
    building = next(b for b in raw["buildings"] if b.get("id") == SOUS_PREFECTURE)
    walls = garages.ring_polygon(building["rings"])
    centre = walls.centroid
    area = walls.buffer(REACH)
    grass = [garages.ring_polygon(g["rings"]) for g in raw["ground"] if g.get("material") in GRASS]
    ground = unary_union([p for p in world["paved"] + [g for g in grass if g is not None] if p.intersects(area)])
    free = ground.intersection(area).difference(public_vehicles.obstacles(world, raw, area)).difference(line18())
    free_p = prep(free)
    base = None
    cands = sorted((math.hypot(x - centre.x, y - centre.y), float(x), float(y))
                   for x in range(int(area.bounds[0]), int(area.bounds[2]) + 1)
                   for y in range(int(area.bounds[1]), int(area.bounds[3]) + 1))
    for _, x, y in cands:
        if not free_p.contains(Point(x, y)):
            continue
        for k in range(24):
            if free_p.contains(public_vehicles.footprint(x, y, k * 15.0, HELI)):
                base = {"x": x, "y": y, "yaw": k * 15.0}
                break
        if base:
            break
    # the release spot: paved, clear of props and trees (garages.py's clearances), RELEASE_WALL m from the walls
    near = walls.buffer(80.0)
    paved = unary_union([p for p in world["paved"] if p.intersects(near)]).intersection(near)
    clear = prep(paved.difference(unary_union([o for o in world["obstacles"] if o.intersects(near)]))
                 .difference(walls.buffer(RELEASE_WALL)))
    release = None
    pts = sorted((walls.exterior.distance(Point(x, y)), float(x), float(y))
                 for x in range(int(near.bounds[0]), int(near.bounds[2]) + 1)
                 for y in range(int(near.bounds[1]), int(near.bounds[3]) + 1))
    for _, x, y in pts:
        if clear.contains(Point(x, y).buffer(0.8)):
            yaw = math.degrees(math.atan2(x - centre.x, y - centre.y)) % 360.0
            release = {"x": x, "y": y, "yaw": round(yaw, 1)}
            break
    print("heli base:", base, "  release:", release)
    OUT.write_text(json.dumps({
        "about": "The police's places (scripts/police/police.gd), made by tools/police/police_places.py: the "
                 "helicopter's base and where an arrested player is let go, by the sous-préfecture de Palaiseau. Map "
                 "coordinates (x east, y north), yaw degrees (0 north, clockwise).",
        "heli_base": base, "release": release}, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
