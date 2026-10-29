"""Stunt spots of PTA Online (godot/scripts/online/stunts.gd, ONLINE_MILESTONES.md O6): godot/world/stunts.json.

    .venv/bin/python tools/online/stunts.py [--plot=/tmp/stunts.png] [--all]
    godot --headless --fixed-fps 60 --path godot --script res://tools/test_stunts.gd -- --trial

Named jumps: taking off from one (in the air at least its `air_min` s) pays a big reward the first time for an account,
a small one after that, less and less each time within an hour (the pay is in godot/data/jobs.json "stunts").

- Terrain jumps: a car (a point on the ground, as fast as SPEEDS) is run along every OSM road, track and path both ways
  over the game's own ground (world/heightmap.*.f32, sampled 1 m apart as the terrain collision is), smoothed over a
  wheelbase. Where the ground falls away faster than the car does, it takes off; the flight is followed until it lands.
  A jump counts when the car is in the air at least AIR_MIN s at the lower speed that launches it, with a straight
  enough run-up (RUN_UP m within RUN_UP_TURN), inside the walkable area, and nothing in the way: not on or near a bridge (the deck is the road
  there, the heightmap the ground below), a tunnel, steps, water or a building under the flight. The best per
  SPACING m is kept, then the BEST_COUNT best on the map: candidates ("tried": false).
- Then the game tries them (tools/test_stunts.gd --trial: a sedan driven off each for real, kerbs, decks and all) and
  keeps those it really flies off, with what it measured ("tried": true).
- Hand-placed spots (HAND): named by hand, on a road the scan doesn't find a launch on (a crest it judges too soft, a
  ramp of the map that isn't a road).

Each spot: id (the road's OSM id + "j" + its index along the way, so a rebuilt map keeps it while the road stays), name,
take-off point (x, y map coordinates: x east, y north), yaw (degrees, 0 = north, turning east: the way to drive it),
radius (m round the take-off point the jump may start in), speed (km/h it was found at), air (s of flight found at that
speed), air_min (s the game asks for), length (m of flight), src ("terrain" or "hand"), tried."""
import json
import math
import sys
from pathlib import Path

import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
WORLD_DIR = ROOT / "godot/world"
WORLD = WORLD_DIR / "world.json"
ROADS = ROOT / "data/interim/massy/roads.json"   # the merged map's roads (the west boxes included)
OUT = WORLD_DIR / "stunts.json"

G = 9.81
SPEEDS = [16.0, 22.0, 28.0]             # m/s tried, lowest first (58, 79, 101 km/h)
STEP = 1.0                              # m between samples along a way
SMOOTH = 2.5                            # m: heights averaged over this (a car's wheelbase rides over smaller bumps)
LIFT = 0.25                             # m above the ground the flight must get to count as a take-off
AIR_MIN = 0.55                          # s in the air at the speed that launches it
RUN_UP = 40.0                           # m of run-up before the take-off...
RUN_UP_TURN = 30.0                      # ...turning less than this (degrees)
SPACING = 120.0                         # m between two spots
BEST_COUNT = 40                         # candidates for the game to try (tools/test_stunts.gd --trial)
CLEAR_BRIDGE = 8.0                      # m from a bridge's edges
KINDS = {"road", "track", "path", "cycleway", "footway", "pedestrian"}
SKIP_HIGHWAYS = {"steps", "platform", "corridor", "elevator"}
RADIUS = 7.0                            # m round the take-off point (the game's tolerance)
TAKE_OFF_SLOPE = -0.08                  # the ground at the take-off no steeper down than this (a lip, not a cliff edge)
RUN_UP_SLOPE = 0.2                      # the run-up no steeper than this anywhere (up or down)
MAX_DROP = 3.0                          # m the landing may be below the take-off (more breaks the car)
PLAY_INSIDE = 15.0                      # m inside the walkable area (meta.playable_area) take-off and landing are

# Hand-placed spots: [osm way, name, (x, y) take-off, yaw (degrees, 0 north), speed km/h]; empty for now (the scan finds
# enough). The game checks them as the terrain ones.
HAND: list = []


def args() -> dict:
    out = {"plot": "", "all": False}
    for a in sys.argv[1:]:
        if a.startswith("--plot="):
            out["plot"] = a.split("=", 1)[1]
        elif a == "--all":
            out["all"] = True
    return out


class Heights:
    """The terrain collision's heights (godot/scripts/builder/collision_builder.gd: every second heightmap sample, 1 m
    apart, two triangles a cell), sampled bilinearly (close enough at 1 m)."""

    def __init__(self, t: dict):
        raw = b"".join((WORLD_DIR / f).read_bytes() for f in t.get("parts", [t["file"]]))
        full = np.frombuffer(raw, dtype=np.float32).reshape(t["h"], t["w"])
        self.z = np.ascontiguousarray(full[::2, ::2])
        self.cell = t["cell"] * 2
        self.ox, self.oy = t["origin_xy"]

    def at(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        fx = (x - self.ox) / self.cell
        fy = (self.oy - y) / self.cell
        i = np.clip(np.floor(fx).astype(int), 0, self.z.shape[1] - 2)
        j = np.clip(np.floor(fy).astype(int), 0, self.z.shape[0] - 2)
        u = np.clip(fx - i, 0, 1)
        v = np.clip(fy - j, 0, 1)
        z = self.z
        return (z[j, i] * (1 - u) * (1 - v) + z[j, i + 1] * u * (1 - v) + z[j + 1, i] * (1 - u) * v
                + z[j + 1, i + 1] * u * v)


def ring_polygon(rings: list) -> Polygon | None:
    if not rings or len(rings[0]) < 3:
        return None
    p = Polygon(rings[0], [r for r in rings[1:] if len(r) >= 3])
    return p if p.is_valid else p.buffer(0)


def obstacles(w: dict) -> tuple:
    """(no take-off here: bridges and tunnels, prepared), (nothing under the flight: buildings, water, an STRtree)."""
    keep_out = []
    for b in w["bridges"]:
        if len(b["pts"]) >= 2:
            keep_out.append(LineString([p[:2] for p in b["pts"]]).buffer(b["width"] / 2 + CLEAR_BRIDGE))
    for g in w["ground"]:
        if g["kind"] in ("steps", "railway", "platform"):
            p = ring_polygon(g["rings"])
            if p is not None:
                keep_out.append(p.buffer(3.0))
    under = []
    for b in w["buildings"]:
        p = ring_polygon(b["rings"])
        if p is not None:
            under.append(p)
    for g in w["ground"]:
        if g["kind"] == "water":
            p = ring_polygon(g["rings"])
            if p is not None:
                under.append(p)
    tree = STRtree(keep_out)
    return tree, keep_out, STRtree(under), under


def resample(line: list) -> np.ndarray:
    ls = LineString(line)
    n = int(ls.length / STEP)
    if n < 10:
        return np.zeros((0, 2))
    return np.array([ls.interpolate(i * STEP).coords[0] for i in range(n + 1)])


def smooth(z: np.ndarray) -> np.ndarray:
    k = max(1, int(round(SMOOTH / STEP)))
    if z.size <= k:
        return z
    pad = np.pad(z, (k, k), mode="edge")
    c = np.cumsum(np.insert(pad, 0, 0.0))
    return (c[2 * k + 1:] - c[:-2 * k - 1]) / (2 * k + 1)


def flight(z: np.ndarray, i: int, v: float) -> tuple:
    """A car at `v` m/s along the samples, on the ground at `i` (its slope the ground's): (s in the air, m flown, top m
    over the ground) once it takes off there, or (0, 0, 0) when it stays on the ground."""
    if i < 1 or i >= z.size - 2:
        return 0.0, 0.0, 0.0
    slope = (z[i] - z[i - 1]) / STEP
    vz = v * slope / math.sqrt(1 + slope * slope)
    vh = v / math.sqrt(1 + slope * slope)
    dt = STEP / vh
    h = z[i]
    top = 0.0
    k = i
    t = 0.0
    while k < z.size - 1:
        k += 1
        t += dt
        h += vz * dt - 0.5 * G * dt * dt
        vz -= G * dt
        gap = h - z[k]
        if gap <= 0.0:
            break
        top = max(top, gap)
    else:
        return 0.0, 0.0, 0.0                 # still flying at the end of the way: not judged
    if top < LIFT or z[i] - z[k] > MAX_DROP or slope < TAKE_OFF_SLOPE:
        return 0.0, 0.0, 0.0
    return t, (k - i) * STEP, top


def heading_turn(pts: np.ndarray, a: int, b: int) -> float:
    """Degrees the way turns between samples a and b (most minus least heading)."""
    d = np.diff(pts[a:b + 1], axis=0)
    if len(d) < 2:
        return 0.0
    ang = np.unwrap(np.arctan2(d[:, 0], d[:, 1]))
    return math.degrees(ang.max() - ang.min())


def scan(roads: list, hm: Heights, w: dict) -> list:
    keep_tree, keep_geoms, under_tree, under_geoms = obstacles(w)
    play = prep(unary_union([Polygon(r) for r in w["meta"]["playable_area"]]).buffer(-PLAY_INSIDE))
    found = []
    for r in roads:
        tags = r["tags"]
        if r["kind"] not in KINDS or tags.get("highway") in SKIP_HIGHWAYS:
            continue
        if tags.get("bridge") or tags.get("tunnel") or tags.get("covered") == "yes" or tags.get("layer", "0") not in ("0", ""):
            continue
        pts0 = resample(r["line"])
        if len(pts0) == 0:
            continue
        for way, pts in (("+", pts0), ("-", pts0[::-1])):
            z = smooth(hm.at(pts[:, 0], pts[:, 1]))
            curv = np.zeros_like(z)
            curv[1:-1] = (z[2:] - 2 * z[1:-1] + z[:-2]) / (STEP * STEP)
            run = int(RUN_UP / STEP)
            for i in np.nonzero(curv < -G / SPEEDS[-1] ** 2)[0]:
                if i < run:
                    continue
                best = None
                for v in SPEEDS:
                    t, length, top = flight(z, int(i), v)
                    if t >= AIR_MIN:
                        best = (v, t, length, top)
                        break
                if best is None:
                    continue
                if heading_turn(pts, i - run, i) > RUN_UP_TURN:
                    continue
                if np.abs(np.diff(z[i - run:i + 1])).max() / STEP > RUN_UP_SLOPE:
                    continue
                if not play.contains(Point(pts[i])):
                    continue
                p = Point(pts[i])
                if any(keep_geoms[k].contains(p) for k in keep_tree.query(p)):
                    continue
                end = min(int(i + best[2] / STEP), len(pts) - 1)
                path = LineString([pts[i], pts[end]]) if end > i else p
                if not play.contains(Point(pts[end])):
                    continue
                if any(under_geoms[k].intersects(path) for k in under_tree.query(path)):
                    continue
                d = pts[min(i + 1, len(pts) - 1)] - pts[i - 1]
                index = int(i if way == "+" else len(pts) - 1 - i)
                found.append({"osm": r["id"], "index": index, "way": way, "name": tags.get("name", ""),
                              "highway": tags.get("highway", ""), "x": float(pts[i][0]), "y": float(pts[i][1]),
                              "yaw": math.degrees(math.atan2(d[0], d[1])) % 360.0, "speed": best[0], "air": best[1],
                              "length": best[2], "top": best[3]})
    return found


def pick(found: list, count: int) -> list:
    """The best per SPACING m (the longest flight at the lowest speed), then the `count` best."""
    found.sort(key=lambda f: (-f["air"] / f["speed"], f["osm"], f["index"]))
    kept = []
    for f in found:
        if all(math.hypot(f["x"] - k["x"], f["y"] - k["y"]) >= SPACING for k in kept):
            kept.append(f)
    return kept[:count]


def place_name(f: dict, labels: list) -> str:
    if f["name"]:
        return "%s jump" % f["name"]
    near = min(labels, key=lambda l: math.hypot(l[1] - f["x"], l[2] - f["y"])) if labels else None
    kind = {"track": "Track", "path": "Path", "cycleway": "Cycle path", "footway": "Footpath"}.get(f["highway"], "Lane")
    return "%s jump, %s" % (kind, near[0]) if near else "%s jump" % kind


def labels() -> list:
    path = WORLD_DIR / "map_labels.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out = []
    for l in data.get("labels", data if isinstance(data, list) else []):
        if isinstance(l, dict) and "name" in l and "x" in l and "y" in l:
            out.append((l["name"].replace("\n", " "), float(l["x"]), float(l["y"])))
    return out


def spot(f: dict, names: list) -> dict:
    return {"id": "%sj%d%s" % (f["osm"], f["index"], "" if f["way"] == "+" else "r"),
            "name": place_name(f, names), "x": round(f["x"], 1), "y": round(f["y"], 1), "yaw": round(f["yaw"], 1),
            "radius": RADIUS, "speed": round(f["speed"] * 3.6), "air": round(f["air"], 2),
            "air_min": round(max(0.4, min(f["air"] * 0.5, 0.8)), 2), "length": round(f["length"], 1),
            "src": "terrain", "tried": False}


def plot(spots: list, w: dict, path: str) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(22, 8))
    for g in w["ground"]:
        if g["kind"] == "road" and g["rings"]:
            r = np.array(g["rings"][0])
            ax.fill(r[:, 0], r[:, 1], color="#bbbbbb", lw=0)
    for s in spots:
        a = math.radians(s["yaw"])
        ax.arrow(s["x"], s["y"], 40 * math.sin(a), 40 * math.cos(a), width=8, color="#e0662a")
        ax.text(s["x"] + 15, s["y"] + 15, "%s %.1fs" % (s["name"], s["air"]), fontsize=7)
    ax.set_aspect("equal")
    fig.savefig(path, dpi=110, bbox_inches="tight")


def main() -> None:
    a = args()
    w = json.loads(WORLD.read_text())
    hm = Heights(w["terrain"])
    roads = json.loads(ROADS.read_text())
    found = scan(roads, hm, w)
    kept = pick(found, len(found) if a["all"] else BEST_COUNT)
    names = labels()
    spots = [spot(f, names) for f in kept]
    for i, (osm, name, xy, yaw, kmh) in enumerate(HAND):
        spots.append({"id": "%sh%d" % (osm, i), "name": name, "x": xy[0], "y": xy[1], "yaw": yaw, "radius": RADIUS,
                      "speed": kmh, "air": 0.0, "air_min": 0.4, "length": 0.0, "src": "hand", "tried": False})
    seen = {}
    for s in spots:                          # two spots of one name: number them
        seen[s["name"]] = seen.get(s["name"], 0) + 1
    count = {}
    for s in spots:
        if seen[s["name"]] > 1:
            count[s["name"]] = count.get(s["name"], 0) + 1
            s["name"] = "%s %d" % (s["name"], count[s["name"]])
    OUT.write_text(json.dumps({"schema": 1, "about": "PTA Online stunt spots: tools/online/stunts.py",
                               "spots": spots}, indent=1, ensure_ascii=False) + "\n")
    print("%d take-offs found, %d spots -> %s" % (len(found), len(spots), OUT.relative_to(ROOT)))
    for s in spots:
        print("  %-48s (%7.1f, %7.1f) yaw %5.1f  %3d km/h  %.2f s  %5.1f m" % (s["name"][:48], s["x"], s["y"], s["yaw"],
                                                                         s["speed"], s["air"], s["length"]))
    if a["plot"]:
        plot(spots, w, a["plot"])


if __name__ == "__main__":
    main()
