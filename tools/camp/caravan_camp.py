"""Caravan camp on the big parking lot east of Télécom Paris (OSM w730167662, local x 257…370, y −257…−140).

    .venv/bin/python tools/camp/caravan_camp.py [--seed=7] [--dry-run] [--plot=/tmp/camp.png]

Lays out caravans (blender/props/camp.py) across the six double-row bay strips and along the perimeter bays, each
pitch a caravan with, at random, its porch awning, garden table, washing line, gas bottles, generator, water tank,
barbecue and the family's van, then writes them as props "camp:N" (src "camp") into godot/world/world.json and
godot/world/base/world.json (the rail patch input), with their tint colours in palette.props and their models in
prop_models. Reruns replace the previous camp:* props, so it can be reapplied after a pipeline rebuild. Then run
build_world.gd.

Layout: a strip runs along the aisles (direction u); its caravans stand across it, drawbar to one aisle, door (on
the right of the drawbar) towards the gap where the awning goes. Every footprint (the model's collision boxes,
plus 0.25 m) must lie inside the lot's parking pieces and aisles and clear of the others."""
import json
import math

import numpy as np
import random
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon, box
from shapely.affinity import rotate, translate
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
WORLDS = [ROOT / "godot/world/world.json", ROOT / "godot/world/base/world.json"]
MODELS = json.loads((ROOT / "godot/assets/props/props.json").read_text())["models"]
LOT = "w730167662"
GATE = (354.6, -257.6)          # lift gate at the lot entrance: kept clear
GATE_CLEAR = 9.0
CLEAR = 0.25                    # m between footprints
FLAT = 0.3                      # m, most the ground may rise or fall under a footprint (berms line the lot)
# perimeter bays as their outer edge (from, to); the lot is on the left of from -> to
ARMS = [((266.7, -139.6), (256.6, -240.1)),        # west
        ((343.9, -153.0), (266.7, -139.6)),        # north
        ((362.3, -256.8), (370.1, -156.4))]        # east

TINTS = {
    "camp_blue": "#3d6fb6", "camp_red": "#c8433a", "camp_green": "#4f9a6a", "camp_grey": "#6b7480",
    "camp_brown": "#9a6a45", "camp_teal": "#2f8f94", "camp_gold": "#c79a3a",
    "awning_green": "#6f8f5a", "awning_blue": "#5279a8", "awning_beige": "#d8c9a3", "awning_grey": "#8d939a",
    "awning_red": "#b5554a", "awning_orange": "#d98a44",
    "retro_mint": "#8fc9b5", "retro_orange": "#e39b52", "retro_sky": "#88b6d8", "retro_red": "#d0645a",
    "van_white": "#f1f1ee", "van_silver": "#c4c8cc", "van_grey": "#7d838b", "van_blue": "#3c5d8c",
    "van_dark": "#3f4349",
}
STRIPE = ["camp_blue", "camp_red", "camp_green", "camp_grey", "camp_brown", "camp_teal", "camp_gold"]
AWNING = ["awning_green", "awning_blue", "awning_beige", "awning_grey", "awning_red", "awning_orange"]
RETRO = ["retro_mint", "retro_orange", "retro_sky", "retro_red"]
VAN = ["van_white"] * 4 + ["van_silver", "van_silver", "van_grey", "van_blue", "van_dark"]
KIND = {"caravan": "caravan", "caravan_twin": "caravan", "caravan_small": "caravan", "caravan_awning": "awning",
        "camp_van": "van", "camp_table": "garden_table", "washing_line": "washing_line", "water_tank": "water_tank",
        "generator": "generator", "gas_bottles": "gas_bottles", "camp_bbq": "barbecue"}
DOOR_Y = {"caravan": 0.55, "caravan_twin": 0.45, "caravan_small": -0.85}       # model y of the door middle


def args() -> dict:
    out = {"seed": "7", "dry-run": "", "plot": ""}
    for a in sys.argv[1:]:
        k, _, v = a.lstrip("-").partition("=")
        out[k] = v or "1"
    return out


def v2(a, b=None):
    return (a, b) if b is not None else a


def unit(deg):
    return (math.cos(math.radians(deg)), math.sin(math.radians(deg)))


class Placed:
    """A prop on the map: model, centre point of its model origin, yaw (map degrees of the model front, -Y)."""

    def __init__(self, model, x, y, yaw, tint=""):
        self.model, self.x, self.y, self.yaw, self.tint = model, x, y, yaw % 360.0, tint

    def to_map(self, bx, by):
        """Model point (Blender x, y) on the map: front f = yaw, Blender +X = left of f, Blender +Y = -f."""
        f = unit(self.yaw)
        left = (-f[1], f[0])
        return (self.x + bx * left[0] - by * f[0], self.y + bx * left[1] - by * f[1])

    def footprint(self, pad=CLEAR):
        lo, hi = MODELS[self.model]["min"], MODELS[self.model]["max"]
        local = box(lo[0] - pad, lo[1] - pad, hi[0] + pad, hi[1] + pad)
        # Blender (x, y) -> map: rotate so that -Y points along yaw: -Y is at -90 deg, turn by yaw + 90
        g = rotate(local, self.yaw + 90.0, origin=(0, 0))
        return translate(g, self.x, self.y)


class Camp:
    def __init__(self, allowed, rng, ground):
        self.allowed = allowed
        self.ground = ground
        self.rng = rng
        self.placed: list[Placed] = []
        self.shapes = []            # footprints (bounds + CLEAR), parallel to placed

    def flat(self, p: Placed) -> bool:
        fp = p.footprint(0.0)
        x0, y0, x1, y1 = fp.bounds
        zs = [self.ground(x, y) for x in np.linspace(x0, x1, max(2, int((x1 - x0) / 0.7) + 1))
              for y in np.linspace(y0, y1, max(2, int((y1 - y0) / 0.7) + 1)) if fp.buffer(0.01).contains(Point(x, y))]
        return not zs or max(zs) - min(zs) <= FLAT

    def fits(self, p: Placed, ignore=()) -> bool:
        fp = p.footprint()
        if not self.allowed.contains(p.footprint(0.0)) or not self.flat(p):
            return False
        return not any(fp.intersects(s) for s, q in zip(self.shapes, self.placed) if not any(q is i for i in ignore))

    def add(self, p: Placed, ignore=()) -> bool:
        """Places p when its footprint is in the lot and clear of the others (except `ignore`, by identity)."""
        if not self.fits(p, ignore):
            return False
        self.placed.append(p)
        self.shapes.append(p.footprint())
        return True

    def take(self, p: Placed, ignore=()) -> bool:
        """add() with only 0.1 m between the bounds (odds and ends of one pitch standing close together), none
        against `ignore` (a caravan's bounds hold its drawbar)."""
        fp = p.footprint(0.05)
        if not self.allowed.contains(p.footprint(0.0)) or not self.flat(p):
            return False
        if any(fp.intersects(q.footprint(0.05)) for q in self.placed if not any(q is i for i in ignore)):
            return False
        self.placed.append(p)
        self.shapes.append(p.footprint())
        return True

    # ------------------------------------------------------------ one family's pitch

    def family(self, model, cx, cy, front, awning: bool) -> Placed | None:
        """Caravan with its body centre at (cx, cy) and drawbar towards `front` (map degrees), then its
        awning, table and odds and ends around it. Returns the caravan or None when it does not fit."""
        rng = self.rng
        tint = rng.choice(RETRO if model == "caravan_small" else STRIPE)
        car = Placed(model, cx, cy, front + rng.uniform(-2.5, 2.5), tint)
        if not self.add(car):
            return None
        half_w = MODELS[model]["max"][0]
        hi = MODELS[model]["max"][1]
        body = MODELS[model]["colliders"][0]["box"]
        nose = body[1] - body[4] / 2                     # model y of the body front, the drawbar ahead of it
        door_y = DOOR_Y[model]
        aw = None
        if awning:
            # awning origin on the door-side wall (Blender -X), facing away from the caravan (front = right of f)
            ax, ay = car.to_map(-half_w - 0.02, door_y + rng.uniform(-0.2, 0.2))
            aw = Placed("caravan_awning", ax, ay, car.yaw - 90.0, rng.choice(AWNING))
            if not self.add(aw, ignore=(car,)):
                aw = None
        # garden table: under the awning or beside the door
        if rng.random() < 0.75:
            d = rng.uniform(1.15, 1.35) if aw else rng.uniform(1.6, 2.2)
            tx, ty = car.to_map(-half_w - d, door_y + rng.uniform(-0.5, 0.5) + (0 if aw else 1.4))
            t = Placed("camp_table", tx, ty, rng.uniform(0, 360))
            self.add(t, ignore=(car, aw)) if aw else self.add(t)
        # gas bottles by the drawbar, generator / water tank at the back, barbecue near the door
        if rng.random() < 0.5:
            gx, gy = car.to_map(rng.choice((-1, 1)) * 0.95, nose - 0.45 - rng.uniform(0, 0.2))
            self.take(Placed("gas_bottles", gx, gy, car.yaw + rng.uniform(-10, 10)), ignore=(car,))
        if rng.random() < 0.3:
            gx, gy = car.to_map(half_w + 0.5, hi - 0.8 - rng.uniform(0, 1.0))
            self.take(Placed("generator", gx, gy, car.yaw + rng.uniform(-20, 20)))
        if rng.random() < 0.3:
            end = door_y + 2.1 if aw else door_y + 0.4          # model y past the awning or the door step
            wx, wy = car.to_map(MODELS[model]["min"][0] - 0.65, max(end + 0.65, hi - 0.6))
            self.take(Placed("water_tank", wx, wy, car.yaw + 90 + rng.uniform(-4, 4)), ignore=(car,))
        if rng.random() < 0.35:
            bx, by = car.to_map(-half_w - (1.8 if aw else 1.0), door_y - (2.3 if aw else 1.4) - rng.uniform(0, 0.4))
            self.take(Placed("camp_bbq", bx, by, rng.uniform(0, 360)))
        return car

    def van(self, cx, cy, front) -> Placed | None:
        v = Placed("camp_van", cx, cy, front + self.rng.uniform(-3, 3), self.rng.choice(VAN))
        return v if self.add(v) else None

    # ------------------------------------------------------------ rows

    def strip(self, c, u_deg, length, depth):
        """Caravans across a bay strip centred on c, running along u_deg for `length`."""
        rng = self.rng
        u, n = unit(u_deg), unit(u_deg + 90)
        s = -length / 2 + 0.6
        side = rng.choice((-1, 1))
        while s < length / 2 - 2.0:
            r = rng.random()
            if r < 0.14:
                kind = "camp_van"
            elif r < 0.2 and s > -length / 2 + 4:
                kind = "washing_line"
            else:
                kind = rng.choices(["caravan", "caravan_twin", "caravan_small"], [0.45, 0.35, 0.2])[0]
            if rng.random() < 0.3:
                side = -side
            front = u_deg + 90 if side > 0 else u_deg - 90        # drawbar towards one aisle
            # the door (right of the drawbar) looks along +u when the drawbar points to +n
            door_ahead = side > 0
            if kind == "washing_line":
                p = (c[0] + u[0] * (s + 1.3), c[1] + u[1] * (s + 1.3))
                off = rng.uniform(-1.5, 1.5)
                if self.add(Placed("washing_line", p[0] + n[0] * off, p[1] + n[1] * off, rng.uniform(0, 90))):
                    s += 2.7
                else:
                    s += 0.5
                continue
            if kind == "camp_van":
                w = 2.4
                off = side * (depth / 2 - 2.95)          # nose near the aisle
                p = (c[0] + u[0] * (s + w / 2) + n[0] * off, c[1] + u[1] * (s + w / 2) + n[1] * off)
                if self.van(p[0], p[1], front):
                    s += w + rng.uniform(0.5, 1.2)
                else:
                    s += 0.5
                continue
            half_w = MODELS[kind]["max"][0] + 0.05
            awning = rng.random() < 0.65
            gap = 2.75 if awning else rng.uniform(1.2, 2.4)        # room on the door side
            lo, hi = MODELS[kind]["min"][1], MODELS[kind]["max"][1]
            # along n a model point y lands at off - side * y: centred on the strip, then pushed towards the
            # drawbar's aisle so that the drawbar overhangs it by up to 0.6 m
            push = max(0.0, min(0.8, depth / 2 + 0.6 - (hi - lo) / 2))
            off = side * ((lo + hi) / 2 + rng.uniform(0.0, push))
            at = s + (gap if not door_ahead else 0.0) + half_w
            p = (c[0] + u[0] * at + n[0] * off, c[1] + u[1] * at + n[1] * off)
            if self.family(kind, p[0], p[1], front, awning):
                s = at + half_w + (gap if door_ahead else 0.0) + rng.uniform(0.3, 0.9)
            else:
                s += 0.5

    def arm(self, a, b, depth_hint):
        """Caravans and vans parked along a perimeter bay row, door and awning towards the lot."""
        rng = self.rng
        L = math.dist(a, b)
        u_deg = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        u, n = unit(u_deg), unit(u_deg + 90)                     # n: into the lot
        s = 1.0
        while s < L - 3.0:
            kind = rng.choices(["caravan", "caravan_twin", "caravan_small", "camp_van"], [0.35, 0.25, 0.15, 0.25])[0]
            lo, hi = MODELS[kind]["min"][1], MODELS[kind]["max"][1]
            length = hi - lo
            # drawbar along +u or -u; the door (right of the drawbar) must face the lot (+n): drawbar along -u
            front = u_deg + 180
            centre_s = s - lo                                     # a model point y lands at centre_s + y
            if kind == "camp_van":
                front = rng.choice((u_deg, u_deg + 180))
                centre_s = s + length / 2
            awning = rng.random() < 0.6
            ok = None
            for back in (0.65, 1.4, 2.2, 3.0):                    # off the edge, clear of the berm
                back += MODELS[kind]["max"][0]
                p = (a[0] + u[0] * centre_s + n[0] * back, a[1] + u[1] * centre_s + n[1] * back)
                if math.dist(p, GATE) < GATE_CLEAR + length / 2:
                    break
                ok = self.van(p[0], p[1], front) if kind == "camp_van" else self.family(kind, p[0], p[1], front, awning)
                if ok:
                    break
            s += (length + rng.uniform(0.6, 1.6)) if ok else 0.7


def lot_geometry(world):
    parking = [Polygon(g["rings"][0], g["rings"][1:]) for g in world["ground"]
               if g["kind"] == "parking" and LOT in g["src"] and g["rings"]]
    lot = unary_union(parking)
    hull = lot.convex_hull
    road = [Polygon(g["rings"][0], g["rings"][1:]) for g in world["ground"]
            if g["kind"] == "road" and g["rings"] and Polygon(g["rings"][0]).intersects(hull)]
    aisles = unary_union([r.buffer(0).intersection(hull) for r in road])
    allowed = unary_union([lot, aisles]).buffer(0.05).difference(Point(GATE).buffer(GATE_CLEAR))
    strips = []
    for p in parking:
        r = p.minimum_rotated_rectangle
        c = list(r.exterior.coords)
        e = [(c[k + 1][0] - c[k][0], c[k + 1][1] - c[k][1]) for k in range(2)]
        lens = [math.hypot(*v) for v in e]
        k = 0 if lens[0] > lens[1] else 1
        if lens[k] > 60 and 8.0 < lens[1 - k] < 11.0 and p.area > 0.8 * r.area:
            ang = math.degrees(math.atan2(e[k][1], e[k][0]))
            ang = ang - 180 if ang > 90 else ang + 180 if ang < -90 else ang
            strips.append((p.centroid.coords[0], ang, lens[k], lens[1 - k]))
    return allowed, sorted(strips, key=lambda s: s[0][1])


def patch(world, props):
    world["props"] = [p for p in world["props"] if not str(p["id"]).startswith("camp:")] + props
    world["prop_models"] = sorted(set(world["prop_models"]) | {p["model"] for p in props})
    world["palette"]["props"].update(TINTS)


def plot(path, world, camp, allowed):
    from PIL import Image, ImageDraw
    x0, x1, y0, y1 = 245, 380, -270, -130
    S = 8
    img = Image.new("RGB", ((x1 - x0) * S, (y1 - y0) * S), (60, 110, 60))
    d = ImageDraw.Draw(img)

    def T(p):
        return ((p[0] - x0) * S, (y1 - p[1]) * S)
    for g in getattr(allowed, "geoms", [allowed]):
        d.polygon([T(p) for p in g.exterior.coords], fill=(110, 110, 120))
        for h in g.interiors:
            d.polygon([T(p) for p in h.coords], fill=(60, 110, 60))
    col = {"caravan": (245, 245, 235), "caravan_twin": (230, 230, 250), "caravan_small": (250, 220, 180),
           "caravan_awning": (120, 170, 100), "camp_van": (180, 190, 200), "camp_table": (255, 255, 255),
           "washing_line": (240, 120, 160), "water_tank": (200, 230, 250), "generator": (230, 180, 40),
           "gas_bottles": (60, 110, 220), "camp_bbq": (20, 20, 20)}
    for p in camp.placed:
        fp = p.footprint(0.0)
        for g in getattr(fp, "geoms", [fp]):
            d.polygon([T(q) for q in g.exterior.coords], fill=col[p.model], outline=(0, 0, 0))
        hx, hy = p.to_map(0, MODELS[p.model]["min"][1])
        d.line([T((p.x, p.y)), T((hx, hy))], fill=(255, 0, 0), width=2)
    img.save(path)


def main():
    a = args()
    rng = random.Random(int(a["seed"]))
    world = json.loads(WORLDS[0].read_text())
    allowed, strips = lot_geometry(world)
    t = world["terrain"]
    hm = np.fromfile(WORLDS[0].parent / t["file"], dtype=np.float32).reshape(t["h"], t["w"])

    def ground(x, y):
        c = (x - t["origin_xy"][0]) / t["cell"]
        r = (t["origin_xy"][1] - y) / t["cell"]
        return float(hm[min(max(round(r), 0), t["h"] - 1), min(max(round(c), 0), t["w"] - 1)])
    camp = Camp(allowed, rng, ground)
    for c, ang, length, depth in strips:
        camp.strip(c, ang, length, depth)
    for a_, b_ in ARMS:
        camp.arm(a_, b_, 6.0)
    props = []
    for i, p in enumerate(camp.placed, 1):
        q = {"id": f"camp:{i}", "kind": KIND[p.model], "model": p.model, "x": round(p.x, 3), "y": round(p.y, 3),
             "yaw": round(p.yaw, 1), "lift": 0.0, "src": "camp", "scale": [1.0, 1.0]}
        if p.tint:
            q["tint"] = p.tint
        props.append(q)
    counts = {}
    for p in props:
        counts[p["model"]] = counts.get(p["model"], 0) + 1
    print(f"{len(strips)} strips; {len(props)} props: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if a["plot"]:
        plot(a["plot"], world, camp, allowed)
    if a["dry-run"]:
        return
    for path in WORLDS:
        w = world if path == WORLDS[0] else json.loads(path.read_text())
        patch(w, props)
        end = "\n" if path.read_text().endswith("\n") else ""
        path.write_text(json.dumps(w, separators=(",", ":"), ensure_ascii=False) + end)
        print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
