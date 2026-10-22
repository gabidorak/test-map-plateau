"""Spots of the "Escape from Plateau" game mode (godot/scripts/escape/escape_mode.gd): godot/world/escape.json.

    .venv/bin/python tools/escape/escape_spots.py [--plot=/tmp/escape.png]

From godot/world/world.json (buildings, their name signs, trees, fences, props) and godot/world/interiors.json:
- safehouse: where the players start and come back after dying (the street in front of Télécom Paris, game.gd's
  spawn point);
- survivors: the pool of people hiding on the plateau (a round picks a few, spread out). Each waits in front of the
  door of a named building: its name sign's spot on the facade, HIDE_OUT m out from it, off every building. The car
  salesman of the showroom (interiors.json) waits inside it instead (the game puts him at the salesman's post);
- evac: where the rescue helicopter may wait (a round picks one): the clearest point near each candidate, with no
  building, tree, fence or street furniture within EVAC_CLEAR m;
- caches: where supplies may lie (the doorsteps of the other named buildings in the campus box).

Positions are map coordinates (x east, y north; Godot = (x, height, -y)); heights come from the game's own ground at
run time. Rerun after a rebuild that moves buildings, then check the spots in the game (tools/test_escape.gd)."""
import json
import math
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot/world/world.json"
INTERIORS = ROOT / "godot/world/interiors.json"
OUT = ROOT / "godot/world/escape.json"
CAMPUS = (-420.0, -1080.0, 1720.0, 620.0)        # x0, y0, x1, y1: where the mode is played
HIDE_OUT = 3.0                                   # m from the facade
EVAC_CLEAR = 15.0                                # m round the helicopter
EVAC_SEARCH = 70.0                               # m from a candidate searched for a clear point
EVAC_STEP = 2.5

SAFEHOUSE = {"name": "Télécom Paris", "x": -34.0, "y": 55.0, "yaw": 180.0, "r": 9.0}

# spot id -> building (OSM id of its name sign), who waits there, what they say when picked up
SURVIVORS = [
    ("gus", "w1079097172", "Léa, the barista of the GUS coffee shop",
     "I kept the espresso machine going all night. Get me out of here!"),
    ("c2n", "r9962706", "Inès, a nanotech researcher at the C2N",
     "They came through the clean room doors... Thank you, thank you!"),
    ("showroom", "w140538734", "Jean-Claude, the car salesman of Prestige Motors",
     "Finally, a customer! ...I mean: merci! Let us go, vite, vite!"),
    ("hacker-house", "w702423669", "Yanis, a student of the Hacker House",
     "My laptop died, then the zombies came. In that order, sadly."),
    ("grand-hall", "r11979092", "Mireille, the night guard of Polytechnique",
     "Thirty years of night shifts and now this. Carry me, my knees are done."),
    ("ensta", "r11096479", "Chloé, an ENSTA Paris student",
     "I hid in the robotics lab. The robots were the nice ones."),
    ("ensae", "r9921491", "Professor Dumont, a statistician at ENSAE",
     "The odds of you finding me were very low. I am delighted to be an outlier."),
    ("cea", "w167196565", "Karim, an engineer at CEA List",
     "It started in a lab near here. I will tell you everything... on the way."),
    ("edf", "r6250632", "Sophie, an intern at EDF",
     "The power went out at ten. I know, I know: keeping it on was my job."),
    ("lozere", "w71346991", "Bernard, the agent of Lozère station",
     "The last RER never came. Traffic disrupted, as usual... but zombies this time."),
    ("kley", "w1011010128", "Mateo, an exchange student",
     "Is this normal in France? Nobody said anything at orientation."),
    ("gym-ensta", "w176156006", "Coach Lefèvre, from the ENSTA gym",
     "I held them off with volleyballs. Go on, I'll carry the whistle."),
    ("turing", "w548438043", "Ada, an AI researcher at the Alan Turing building",
     "My model predicted this. Nobody read my paper."),
    ("sous-prefecture", "r20158551", "Gérard, a clerk at the sous-préfecture",
     "Is there a form for this? Form 28-B: evacuation by helicopter."),
    ("maisons-hotes", "w71355656", "Professor Sato, visiting from Kyoto",
     "I came for a conference. This was not the keynote I expected."),
    ("church", "w71355246", "Father Antoine, of Notre-Dame-de-la-Nativité",
     "I rang the bell all night. It only brought more of them."),
    ("alice-milliat", "w1473225811", "Nadia, a sprinter of the Alice Milliat centre",
     "I can run... I just twisted my ankle running from them."),
    ("manege", "w71348753", "Capucine, from the riding club",
     "The horses ran off at the first scream. Smart horses."),
    ("sirta", "w983529818", "Hugo, a meteorologist at the SIRTA observatory",
     "Fog, visibility eighty metres, and the dead walking. Not in my forecast."),
    ("chaufferie", "w71353719", "Rémi, the technician of the heating plant",
     "The boilers still work. The rest of the world, not so much."),
]

# evac id -> where, roughly (map x, y)
EVAC = [
    ("x-fields", "the Polytechnique sports fields", (1058.0, 234.0)),
    ("x-north", "the fields north of Polytechnique", (630.0, 520.0)),
    ("ensta-field", "the field by ENSTA Paris", (1445.0, -408.0)),
    ("x-east", "the east fields of Polytechnique", (1312.0, 44.0)),
    ("lake-parking", "the big parking by the Lac de l'X", (790.0, 166.0)),
]


def args() -> dict:
    out = {"plot": ""}
    for a in sys.argv[1:]:
        k, _, v = a.lstrip("-").partition("=")
        out[k] = v
    return out


def in_campus(x: float, y: float) -> bool:
    return CAMPUS[0] <= x <= CAMPUS[2] and CAMPUS[1] <= y <= CAMPUS[3]


def doorstep(sign: dict, footprint: Polygon, buildings: STRtree, polys: list) -> tuple | None:
    """(x, y, [outward unit vector]) HIDE_OUT m out from the facade at the sign, off every building; None when there
    is no room."""
    p = Point(sign["x"], sign["y"])
    ring = list(footprint.exterior.coords)
    best = None
    for a, b in zip(ring, ring[1:]):
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy)
        if n < 0.5:
            continue
        t = max(0.0, min(1.0, ((p.x - ax) * dx + (p.y - ay) * dy) / (n * n)))
        cx, cy = ax + dx * t, ay + dy * t
        d = math.hypot(p.x - cx, p.y - cy)
        if best is None or d < best[0]:
            best = (d, cx, cy, -dy / n, dx / n)
    if best is None:
        return None
    _, cx, cy, nx, ny = best
    if footprint.contains(Point(cx + nx * 0.5, cy + ny * 0.5)):
        nx, ny = -nx, -ny
    for out in (HIDE_OUT, HIDE_OUT + 1.5, HIDE_OUT + 3.0):
        q = Point(cx + nx * out, cy + ny * out)
        if not any(polys[i].buffer(0.6).contains(q) for i in buildings.query(q.buffer(1.0))):
            return round(q.x, 2), round(q.y, 2), [round(nx, 3), round(ny, 3)]
    return None


def plot(path: str, polys: list, out: dict) -> None:
    """Review map: the buildings grey, caches orange, survivors green, evac sites red (EVAC_CLEAR circles), the
    safehouse blue."""
    from PIL import Image, ImageDraw
    k = 0.6                                                     # px per m
    w, h = int((CAMPUS[2] - CAMPUS[0]) * k), int((CAMPUS[3] - CAMPUS[1]) * k)
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)

    def px(x, y):
        return (x - CAMPUS[0]) * k, (CAMPUS[3] - y) * k

    for poly in polys:
        if in_campus(poly.centroid.x, poly.centroid.y):
            d.polygon([px(x, y) for x, y in poly.exterior.coords], fill="#bbbbbb")
    for x, y in out["caches"]:
        cx, cy = px(x, y)
        d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill="orange")
    for s in out["survivors"]:
        cx, cy = px(s["x"], s["y"])
        d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill="green")
        d.text((cx + 5, cy - 5), s["id"], fill="darkgreen")
    for e in out["evac"]:
        cx, cy = px(e["x"], e["y"])
        r = EVAC_CLEAR * k
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline="red", width=2)
        d.text((cx + r, cy), e["id"], fill="red")
    sx, sy = px(SAFEHOUSE["x"], SAFEHOUSE["y"])
    d.rectangle([sx - 5, sy - 5, sx + 5, sy + 5], fill="blue")
    img.save(path)
    print("plot -> %s" % path)


def main() -> None:
    opt = args()
    world = json.loads(WORLD.read_text())
    interiors = json.loads(INTERIORS.read_text())
    footprints = {}
    polys = []
    for b in world["buildings"]:
        rings = b.get("rings") or []
        if not rings or len(rings[0]) < 3:
            continue
        poly = Polygon(rings[0], rings[1:]).buffer(0)
        if poly.is_empty:
            continue
        polys.append(poly)
        footprints[b["id"].split(":", 1)[1]] = poly
    buildings = STRtree(polys)
    signs = {}
    for s in world["building_signs"]:
        signs.setdefault(s["building"], s)

    survivors = []
    for spot, osm, who, line in SURVIVORS:
        entry = {"id": spot, "who": who, "line": line}
        if "osm:" + osm in interiors:                   # waits inside, at the salesman's post (game side)
            entry["interior"] = "osm:" + osm
        sign = signs.get(osm)
        if sign is None or osm not in footprints:
            print("no sign for %s (%s): skipped" % (spot, osm))
            continue
        step = doorstep(sign, footprints[osm], buildings, polys)
        if step is None:
            print("no room in front of %s: skipped" % spot)
            continue
        entry["place"] = interiors["osm:" + osm]["name"] if "interior" in entry else sign["text"]
        entry["x"], entry["y"], entry["out"] = step
        survivors.append(entry)

    obstacles = [Point(t["x"], t["y"]).buffer(max(float(t.get("r", 1.0)), 0.5)) for t in world["trees"]
                 if in_campus(t["x"], t["y"])]
    obstacles += [Point(p["x"], p["y"]).buffer(0.6) for p in world["props"] if in_campus(p["x"], p["y"])]
    from shapely.geometry import LineString
    obstacles += [LineString(f["pts"]).buffer(0.3) for f in world["fences"] if len(f["pts"]) > 1]
    obstacles += [poly for poly in polys if in_campus(poly.centroid.x, poly.centroid.y)]
    hedges = [LineString(h["pts"]).buffer(float(h.get("w", 1.0)) * 0.5) for h in world["hedges"] if len(h["pts"]) > 1]
    obstacles += hedges
    tree = STRtree(obstacles)

    evac = []
    for spot, name, (x0, y0) in EVAC:
        best = None
        k = int(EVAC_SEARCH / EVAC_STEP)
        for i in range(-k, k + 1):
            for j in range(-k, k + 1):
                x, y = x0 + i * EVAC_STEP, y0 + j * EVAC_STEP
                p = Point(x, y)
                near = [obstacles[n] for n in tree.query(p.buffer(EVAC_CLEAR))]
                if any(o.distance(p) < EVAC_CLEAR for o in near):
                    continue
                d = math.hypot(x - x0, y - y0)
                if best is None or d < best[0]:
                    best = (d, x, y)
        if best is None:
            print("no clear spot near %s: skipped" % spot)
            continue
        evac.append({"id": spot, "name": name, "x": round(best[1], 1), "y": round(best[2], 1), "r": 13.0})
        print("evac %-13s %.0f m from the candidate" % (spot, best[0]))

    used = {osm for _, osm, _, _ in SURVIVORS}
    caches = []
    for osm, sign in signs.items():
        if osm in used or osm not in footprints or not in_campus(sign["x"], sign["y"]):
            continue
        step = doorstep(sign, footprints[osm], buildings, polys)
        if step:
            caches.append([step[0], step[1]])

    out = {
        "schema": 1,
        "about": "Escape from Plateau spots: tools/escape/escape_spots.py from world.json (map x east, y north).",
        "campus": list(CAMPUS),
        "safehouse": SAFEHOUSE,
        "survivors": survivors,
        "evac": evac,
        "caches": caches,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
    print("%d survivors, %d evac sites, %d caches -> %s" % (len(survivors), len(evac), len(caches), OUT))
    if opt["plot"]:
        plot(opt["plot"], polys, out)


if __name__ == "__main__":
    main()
