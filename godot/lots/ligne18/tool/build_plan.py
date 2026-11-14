"""Line 18 (Grand Paris Express) on the plateau: its master plan in the map's frame, godot/lots/ligne18/plan.json,
which the line 18 lots share (lot ligne18 and its children; godot/lots/ligne18/ligne18_plan.gd reads it).

Run from the repository: .venv/Scripts/python.exe -I godot/lots/ligne18/tool/build_plan.py
Reads godot/lots/ligne18/tool/osm_ligne18.json (OpenStreetMap: the line's two tracks, the stations' buildings) and
godot/world/world.json with its heightmap (the ground; the roads, kept clear of the piers).

The plan is FROZEN once written (a rerun keeps the piers of the plan.json there, moving only those in the AI's car
and bus lanes; --replan lays them out afresh): the axis (straight through the stations), the rail's profile, the piers' places, the
stations' frames and levels. A rebuilt or extended map does not need it rerun (the piers follow the ground in the
game); rerun it only to change the line's design, then check every line 18 lot against it.

Frame: map metres, x east, y north (Lambert-93 minus 641117.6, 6846184.3); z = metres over the map origin's height
(157.731 m NGF), as the heightmap; Godot position = (x, z, -y), a heading theta (from +x towards +y) = rotation.y.
Chainage s: metres along the axis from the Massy-Palaiseau line 18 station, increasing westwards (towards Versailles),
as the official PK do (PK = s + k). Station frame: u along the line (increasing s), v to its left, origin on the axis.
Sources of the figures: ref/metro18/README.md (IDFM AVPm livret 3, SGP).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "common"))
from l93 import fwd                                 # noqa: E402

OUT = ROOT / "godot" / "lots" / "ligne18" / "plan.json"

# ---------------------------------------------------------------- the published figures
TRACK_V = 2.65            # m, each track's centre from the axis (5.30 m between them)
GAUGE = 1.435
DECK_HALF = 4.845         # m, the deck's concrete (9.69 m)
EDGE_HALF = 4.945         # m, with its edge equipment (9.89 m)
RAIL_OVER_DECK = 0.47     # m, the rail's top over the deck's top face
WALKWAY_OVER_RAIL = 0.96  # m, the spine's top (the evacuation walkway, at the train floor)
SPINE_HALF = 1.075        # m (2.15 m wide)
SPINE_H = 2.74            # m, the walkway's top to the soffit at the axis
EDGE_T = 0.40             # m, the deck's thickness at its edges
PARAPET_H = 1.50          # m over the deck's top face
SOFFIT_UNDER_RAIL = SPINE_H - WALKWAY_OVER_RAIL    # 1.78 m
SPAN = 35.0
PIER_ELL = (2.75, 1.10)   # m, each shaft of a double pier (along x across)
PIER_GAP = 3.50           # m between the shafts' centres
PIER1_ELL = (2.75, 1.50)  # a single shaft
FOOTING = 6.0             # m square, 1.50 m thick, its top 0.60 m under the ground
BEARING = 0.30            # m, the bearings between a pier's head and the soffit
SOFFIT_MEAN, SOFFIT_MIN = 8.0, 4.5
RAMP_CLEAR = 2.0          # m: the ramp's embankment ends (its abutment) where the soffit is this high over the ground
MAX_GRADE = 0.03
# the stations (aerial, AVPm): hall at the ground, the passerelle (level 1), the side platforms
HALF_ZONE = 45.0          # m: a station's own structure along the line, u -45..45 (the viaduct rests on its ends)
STRAIGHT_BLEND = 75.0     # m beyond it over which the axis eases back to OSM's
PASSERELLE_Z = 5.0
PLATFORM_Z = 10.40        # over the hall
PLATFORM_OVER_RAIL = 1.05
PLATFORM_L = 60.0
PLATFORM_EDGE_V = 4.00    # m from the axis (track 2.65 + car 1.25 + gap 0.10)
PLATFORM_W = 4.50
ROOF_Z = 20.1
PK = {"polytechnique": 13728.4, "universite": 15942.7, "christ_saclay": 18337.4}
CROSSINGS = [(13900, "Bd Gaspard Monge", 50), (15530, "RN 118", 58), (18560, "RD 36", 50)]   # PK, span m
STATIONS = {
    "polytechnique": {"name": "Polytechnique", "osm": 1063329861, "build": True},
    "universite": {"name": "Université Paris-Saclay", "osm": 1063329862, "build": True},
    "christ_saclay": {"name": "Christ de Saclay", "osm": 1340377199, "build": False},
}
# what a pier may not stand on (the map's ground kinds), and its clear footprint round its shafts
OBSTACLES = {"road", "cycleway", "traffic_island", "railway", "water", "building", "platform", "steps"}
FOOT_ALONG = PIER_ELL[0] / 2 + 1.0
FOOT_ACROSS = PIER_GAP / 2 + PIER_ELL[1] / 2 + 1.0
SHIFT_MAX = 12
CAR_HALF, BUS_HALF, ROUTE_CLEAR = 1.0, 1.3, 0.4   # m: the AI's vehicles' half widths, their clearance to a shaft
SPAN_RANGE = (20.0, 45.0)


def load(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def cumlen(pts):
    return np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])


def resample(pts, step):
    s = cumlen(pts)
    t = np.arange(0.0, s[-1] + 1e-9, step)
    return np.c_[np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], t


def chains(osm):
    """The two tracks, east to west: (points, kind of each, way ids)."""
    N = {e["id"]: e for e in osm["elements"] if e["type"] == "node"}
    xy = {}

    def P(n):
        if n not in xy:
            xy[n] = fwd(N[n]["lat"], N[n]["lon"])
        return xy[n]
    ways = []
    for e in osm["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or t.get("ref") != "18" or t.get("name") != "Ligne 18" or "service" in t:
            continue
        if t.get("railway") not in ("subway", "construction") or not all(n in N for n in e["nodes"]):
            continue
        pts = [P(n) for n in e["nodes"]]
        if min(p[0] for p in pts) > 4330 or max(p[0] for p in pts) < -4400:
            continue
        kind = "tunnel" if t.get("tunnel") == "yes" else "viaduc" if t.get("bridge") == "viaduct" else "sol"
        ways.append({"id": e["id"], "nodes": e["nodes"], "kind": kind})
    ends = {}
    for w in ways:
        for n in (w["nodes"][0], w["nodes"][-1]):
            ends.setdefault(n, []).append(w)
    starts = sorted(ways, key=lambda w: -max(P(w["nodes"][0])[0], P(w["nodes"][-1])[0]))[:2]
    out, used = [], set()
    for w0 in starts:
        nodes = list(w0["nodes"]) if P(w0["nodes"][0])[0] > P(w0["nodes"][-1])[0] else list(w0["nodes"][::-1])
        segs = [(w0, len(nodes))]
        used.add(w0["id"])
        while True:
            cand = [w for w in ends.get(nodes[-1], []) if w["id"] not in used]
            if not cand:
                break
            a, b = np.array(P(nodes[-2])), np.array(P(nodes[-1]))

            def turn(w):
                nn = w["nodes"] if w["nodes"][0] == nodes[-1] else w["nodes"][::-1]
                u, v = b - a, np.array(P(nn[1])) - b
                return -np.dot(u, v) / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-9)
            w = min(cand, key=turn)
            nn = w["nodes"] if w["nodes"][0] == nodes[-1] else w["nodes"][::-1]
            nodes += nn[1:]
            segs.append((w, len(nodes)))
            used.add(w["id"])
        kinds, i0 = [], 0
        for w, i1 in segs:
            kinds += [w["kind"]] * (i1 - i0)
            i0 = i1
        out.append((np.array([P(n) for n in nodes]), kinds, [w["id"] for w, _ in segs]))
    return out, P, N


def build_axis(tracks, step=5.0):
    """The axis: midway between the tracks, every `step` m; each point's kind (track A's)."""
    (A, ka, _), (B, _, _) = tracks
    a2, _ = resample(A, 2.0)
    b2, _ = resample(B, 0.5)
    mids = []
    for i in range(0, len(a2), 400):
        ch = a2[i:i + 400]
        d = np.hypot(ch[:, None, 0] - b2[None, :, 0], ch[:, None, 1] - b2[None, :, 1])
        mids.append((ch + b2[d.argmin(axis=1)]) / 2)
    axis, s = resample(np.concatenate(mids), step)
    kinds = [ka[int(np.argmin(np.hypot(A[:, 0] - p[0], A[:, 1] - p[1])))] for p in axis]
    return axis, s, kinds


def point_at(axis, s_axis, s):
    return np.array([np.interp(s, s_axis, axis[:, 0]), np.interp(s, s_axis, axis[:, 1])])


def heading_at(axis, s_axis, s, ds=10.0):
    a, b = point_at(axis, s_axis, s - ds), point_at(axis, s_axis, s + ds)
    return math.atan2(b[1] - a[1], b[0] - a[0])


def project(axis, s_axis, p):
    """(s, v: left of the axis) of map point p."""
    d = np.hypot(axis[:, 0] - p[0], axis[:, 1] - p[1])
    i = min(max(int(np.argmin(d)), 1), len(axis) - 2)
    best = None
    for j in (i - 1, i):
        a, b = axis[j], axis[j + 1]
        ab = b - a
        t = float(np.clip(np.dot(p - a, ab) / np.dot(ab, ab), 0, 1))
        q = a + t * ab
        dd = float(np.hypot(*(p - q)))
        if best is None or dd < best[0]:
            side = math.copysign(1.0, ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0]))
            best = (dd, s_axis[j] + t * (s_axis[j + 1] - s_axis[j]), side * dd)
    return best[1], best[2]


def to_local(p, c, th):
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (dx * math.cos(th) + dy * math.sin(th), -dx * math.sin(th) + dy * math.cos(th))


def to_map(u, v, c, th):
    return (c[0] + u * math.cos(th) - v * math.sin(th), c[1] + u * math.sin(th) + v * math.cos(th))


class Ground:
    def __init__(self, world):
        t = world["terrain"]
        self.w, self.h, self.cell = int(t["w"]), int(t["h"]), float(t["cell"])
        self.ox, self.oy = map(float, t["origin_xy"])
        names = t.get("parts") or [t["file"]]
        self.z = np.concatenate([np.fromfile(ROOT / "godot" / "world" / n, dtype="<f4") for n in names]).reshape(self.h, self.w)

    def at(self, x, y):
        fx, fy = (x - self.ox) / self.cell, (self.oy - y) / self.cell
        if not (0 <= fx < self.w - 1 and 0 <= fy < self.h - 1):
            return None
        i, j = int(fx), int(fy)
        u, v = fx - i, fy - j
        z = self.z
        return float(z[j, i] * (1 - u) * (1 - v) + z[j, i + 1] * u * (1 - v) + z[j + 1, i] * (1 - u) * v + z[j + 1, i + 1] * u * v)


def smooth(y, n):
    k = np.ones(n) / n
    pad = np.r_[np.full(n, y[0]), y, np.full(n, y[-1])]
    return np.convolve(pad, k, mode="same")[n:-n]


def routes():
    """The AI's car and bus routes (godot/world/car_routes.json, bus_routes.json): [(line, vehicle half width)]."""
    out = []
    cr = load(ROOT / "godot" / "world" / "car_routes.json")
    out += [(LineString(r["pts"]), CAR_HALF) for r in cr["routes"].values() if len(r["pts"]) > 1]

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "pts" and isinstance(v, list) and len(v) > 1 and isinstance(v[0], list):
                    out.append((LineString([q[:2] for q in v]), BUS_HALF))
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(load(ROOT / "godot" / "world" / "bus_routes.json"))
    return out


def obstacles(world, keep_out_ids):
    polys = []
    for g in world["ground"]:
        if g["kind"] not in OBSTACLES or not g.get("rings") or len(g["rings"][0]) < 3:
            continue
        src = g.get("src")
        srcs = src if isinstance(src, list) else [src]
        if g["kind"] == "building" and any(s in keep_out_ids for s in srcs):
            continue
        pg = Polygon(g["rings"][0], [r for r in g["rings"][1:] if len(r) >= 3]).buffer(0)
        if not pg.is_empty:
            polys.append(pg)
    for b in world["buildings"]:
        if str(b["id"]).split("_rest")[0] in keep_out_ids:
            continue
        for r in b.get("rings", [])[:1]:
            if len(r) >= 3:
                polys.append(Polygon(r).buffer(0))
    for k in world["kerbs"]:
        if k["kind"] == "raised" and len(k["pts"]) >= 2:
            polys.append(LineString(k["pts"]).buffer(0.3))
    for b in world["bridges"]:
        if len(b["pts"]) >= 2:
            polys.append(LineString([p[:2] for p in b["pts"]]).buffer(float(b.get("width") or 6.0) / 2))
    return unary_union(polys)


def amend(frozen, clear, free, shafts, lanes):
    """The frozen plan's piers kept where they are; only those whose shafts are in the AI's lanes are moved (<= 10 m,
    their spans >= 15 m) or made a single shaft, the least they can."""
    out = []
    for i, p in enumerate(frozen):
        q = {k: p[k] for k in ("s", "type", "moved") if k in p}
        if "fixed" in p:
            q["fixed"] = p["fixed"]
        s0, kind = float(p["s"]), p["type"]
        if kind != "abutment" and lanes.intersects(shafts(s0, kind)):
            lo = float(out[-1]["s"]) + 15 if out else s0 - 10
            hi = float(frozen[i + 1]["s"]) - 15 if i + 1 < len(frozen) else s0 + 10
            best = None
            for d in sorted(range(-10, 11), key=abs):
                s = s0 + d
                if not lo <= s <= hi:
                    continue
                k, level = clear(s)
                if best is None or (level, abs(d)) < (best[0], best[1]):
                    best = (level, abs(d), s, k)
            if best:
                q["s"], q["type"] = round(best[2], 1), best[3]
                q["moved"] = round(float(q.get("moved", 0.0)) + best[2] - s0, 1)
                print("pier %.1f in the AI's lanes: now %.1f %s" % (s0, best[2], best[3]))
        s, kind = float(q["s"]), q["type"]
        lane_free = kind == "abutment" or not lanes.intersects(shafts(s, kind))
        q["clear"] = kind == "abutment" or (free(s, kind) and lane_free)
        q["on_road"] = not q["clear"] and lane_free
        q["in_the_way"] = not lane_free
        out.append(q)
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    osm = load(Path(__file__).resolve().parent / "osm_ligne18.json")
    world = load(ROOT / "godot" / "world" / "world.json")
    meta = world["meta"]
    J = lambda v: json.loads(v) if isinstance(v, str) else v   # noqa: E731
    play = Polygon(J(meta["playable_area"])[0])
    ground = Ground(world)

    tracks, P, N = chains(osm)
    assert len(tracks) == 2, "expected two tracks"
    axis, s_axis, kinds = build_axis(tracks)
    W = {e["id"]: e for e in osm["elements"] if e["type"] == "way"}

    # ---- the stations: their OSM footprint's area centroid projected on the axis; the axis made straight through them
    st = {}
    for key, info in STATIONS.items():
        fp = np.array([P(n) for n in W[info["osm"]]["nodes"]])
        x0, y0, x1, y1 = fp[:-1, 0], fp[:-1, 1], fp[1:, 0], fp[1:, 1]
        cr = x0 * y1 - x1 * y0
        c = np.array([((x0 + x1) * cr).sum(), ((y0 + y1) * cr).sum()]) / (3 * cr.sum())
        s_c, _ = project(axis, s_axis, c)
        s_c = round(s_c, 1)
        st[key] = dict(info, footprint=fp, s=s_c, centre=point_at(axis, s_axis, s_c), heading=heading_at(axis, s_axis, s_c, 30.0))
    orig = axis.copy()
    for key, S in st.items():
        d = s_axis - S["s"]
        line = S["centre"] + np.c_[d * math.cos(S["heading"]), d * math.sin(S["heading"])]
        w = np.clip((np.abs(d) - HALF_ZONE) / STRAIGHT_BLEND, 0.0, 1.0)
        w = (w * w * (3 - 2 * w))[:, None]
        near = np.abs(d) <= HALF_ZONE + STRAIGHT_BLEND
        axis[near] = (line * (1 - w) + orig * w)[near]
        dev = np.hypot(*(axis - orig)[np.abs(d) <= HALF_ZONE].T).max()
        print("%-14s s %.1f centre (%.2f, %.2f) heading %.3f° (axis straightened: %.2f m off OSM's at most)" % (
            key, S["s"], *S["centre"], math.degrees(S["heading"]), dev))
    for S in st.values():
        S["ground"] = ground.at(*S["centre"])
        S["hall_z"] = round(S["ground"], 2) if S["ground"] is not None else None
        S["local"] = np.array([to_local(p, S["centre"], S["heading"]) for p in S["footprint"]])
        S["in_playable"] = bool(play.contains(Point(*S["centre"])))
    k_pk = PK["polytechnique"] - st["polytechnique"]["s"]

    # ---- the sections (OSM's kinds)
    sections = []
    for i, k in enumerate(kinds):
        if sections and sections[-1]["kind"] == k:
            sections[-1]["s1"] = float(s_axis[i])
        else:
            sections.append({"kind": k, "s0": float(s_axis[i]), "s1": float(s_axis[i])})
    via = [x for x in sections if x["kind"] == "viaduc"]
    s_v0, s_v1 = via[0]["s0"], via[-1]["s1"]

    # ---- the rail's profile (frozen): the plateau's level (800 m running median) + 8 m soffit; the stations' rails
    # level over +-HALF_ZONE at hall + 10.40 - 1.05; 4.50 m clear at least; the east ramp at 3 % from the ground;
    # grades <= 3 % (raised, never lowered); smoothed (vertical curves)
    gz = np.array([ground.at(*p) if ground.at(*p) is not None else np.nan for p in axis])
    valid = ~np.isnan(gz)
    g_fill = np.where(valid, gz, np.interp(s_axis, s_axis[valid], gz[valid]))
    win = np.lib.stride_tricks.sliding_window_view(np.pad(g_fill, 80, mode="edge"), 161)
    plateau = smooth(np.median(win, axis=1), 41)
    target = plateau + SOFFIT_MEAN + SOFFIT_UNDER_RAIL
    flat = np.zeros(len(axis), bool)
    for S in st.values():
        if S["hall_z"] is None:
            continue
        zr = S["hall_z"] + PLATFORM_Z - PLATFORM_OVER_RAIL
        d = np.abs(s_axis - S["s"])
        wgt = np.clip((250 - d) / 205, 0, 1)
        target = np.where(d <= HALF_ZONE + 5.0, zr, target * (1 - wgt) + zr * wgt)   # (+ a step: level up to the ends)
        flat |= d <= HALF_ZONE + 5.0
        S["rail_z"] = round(zr, 2)

    def constrain(t):
        t = np.maximum(t, g_fill + SOFFIT_MIN + SOFFIT_UNDER_RAIL)
        ramp = gz[np.searchsorted(s_axis, s_v0)] + 0.5 + MAX_GRADE * np.clip(s_axis - s_v0, 0, None)
        t = np.where(s_axis >= s_v0, np.minimum(t, ramp), t)
        t = np.where((s_axis < s_v0) | (s_axis > s_v1), g_fill + 0.5, t)
        ds = s_axis[1] - s_axis[0]
        for _ in range(4):
            for i in range(1, len(t)):
                t[i] = max(t[i], t[i - 1] - MAX_GRADE * ds)
            for i in range(len(t) - 2, -1, -1):
                t[i] = max(t[i], t[i + 1] - MAX_GRADE * ds)
        return t
    target = constrain(target)
    for _ in range(3):                               # vertical curves: smoothed, the stations kept level
        sm = smooth(target, 9)
        sm[flat] = target[flat]
        target = constrain(sm)
    for S in st.values():
        if S.get("rail_z") is not None:
            d = np.abs(s_axis - S["s"]) <= HALF_ZONE
            assert np.allclose(target[d], S["rail_z"], atol=0.005), "a station's rail was raised: %s" % S["name"]
    on_v = (s_axis >= s_v0) & (s_axis <= s_v1)
    rail = np.where(on_v, target, np.nan)
    sol = np.array([k == "sol" for k in kinds]) & valid
    rail[sol] = g_fill[sol] + 0.5
    ds = s_axis[1] - s_axis[0]
    ok = on_v[:-1] & on_v[1:] & valid[:-1] & valid[1:]
    grade = np.abs(np.diff(rail))[ok] / ds

    # ---- what is built of the viaduct: the ramp's embankment from s_v0 to its abutment, then the spans to where the
    # heightmap ends (its north edge, beyond the playable area: the deck seen from afar)
    soffit_clear = rail - SOFFIT_UNDER_RAIL - gz
    i0 = int(np.searchsorted(s_axis, s_v0))
    i_ab = i0 + int(np.argmax(soffit_clear[i0:] >= RAMP_CLEAR))
    s_abut = float(s_axis[i_ab])
    last = int(np.where(on_v & valid)[0].max())
    s_edge = float(s_axis[last])

    # ---- the piers: fixed points (the abutment, the stations' ends, the long spans' piers), spans spread evenly
    # (<= 35 m) between them, then each moved along the line (<= 12 m) off the roads, kerbs, buildings, water
    keep_out = {"osm:w%d" % S["osm"] for S in st.values()}
    pobs = prep(obstacles(world, keep_out))
    lanes = routes()
    lanes_union = unary_union([ln.buffer(half + ROUTE_CLEAR) for ln, half in lanes])
    plan_lanes = prep(lanes_union)

    def shafts(s, kind):
        """The pier's shafts' own rectangle (no margin): what the AI's vehicles must clear."""
        c = point_at(axis, s_axis, s)
        th = heading_at(axis, s_axis, s, 5.0)
        a = PIER_ELL[0] / 2
        b = PIER_GAP / 2 + PIER_ELL[1] / 2 if kind == "double" else PIER1_ELL[1] / 2
        return Polygon([to_map(u, v, c, th) for u, v in ((-a, -b), (a, -b), (a, b), (-a, b))])

    def free(s, kind):
        return not pobs.intersects(footprint(s, kind)) and not plan_lanes.intersects(shafts(s, kind))

    def footprint(s, kind="double"):
        c = point_at(axis, s_axis, s)
        th = heading_at(axis, s_axis, s, 5.0)
        a, b = (FOOT_ALONG, FOOT_ACROSS) if kind == "double" else (PIER1_ELL[0] / 2 + 1.0, PIER1_ELL[1] / 2 + 1.0)
        return Polygon([to_map(u, v, c, th) for u, v in ((-a, -b), (a, -b), (a, b), (-a, b))])

    def clear(s):
        """(the pier type at s, its level): 0 clear of everything (a double pier, else a single shaft); 1 on a road
        (it cannot be off it: the boulevard's piers) but its shafts clear of the AI's lanes (a single shaft first, it
        fits a median); 2 in the way."""
        for kind in ("double", "single"):
            if free(s, kind):
                return kind, 0
        for kind in ("single", "double"):
            if not plan_lanes.intersects(shafts(s, kind)):
                return kind, 1
        return "double", 2

    # the long spans: centred on the PK's crossing, the pair moved together (<= 15 m: the PK's calibration) off the
    # roads it spans
    long_spans = []
    for pk, name, span in CROSSINGS:
        c0 = pk - k_pk
        best = None
        for d in sorted(range(-15, 16), key=abs):
            ka, kb = clear(c0 + d - span / 2), clear(c0 + d + span / 2)
            score = ka[1] + kb[1]
            if best is None or score < best[0]:
                best = (score, d, ka, kb)
            if score == 0:
                break
        long_spans.append((round(c0 + best[1], 1), name, span, best[2], best[3]))
    fixed = [(s_abut, "abutment", None)]
    for S in st.values():
        if S["build"] and S["hall_z"] is not None:
            fixed += [(S["s"] - HALF_ZONE, "station_end", None), (S["s"] + HALF_ZONE, "station_end", None)]
    for c, name, span, ka, kb in long_spans:
        if c + span / 2 < s_edge:
            fixed += [(c - span / 2, "long_span_start", ka), (c + span / 2, "long_span_end", kb)]   # (kind, level)
    fixed.sort()
    nominal = []
    for (a, ka, _), (b, kb, _) in zip(fixed, fixed[1:]):
        if (ka, kb) == ("station_end", "station_end") and any(abs((a + b) / 2 - S["s"]) < 1 for S in st.values()):
            continue                                 # inside a station
        if (ka, kb) == ("long_span_start", "long_span_end"):
            continue                                 # the long span itself
        n = max(1, math.ceil((b - a) / SPAN - 1e-6))
        nominal += [a + (b - a) * k / n for k in range(1, n)]
    n_tail = int((s_edge - fixed[-1][0]) // SPAN)
    nominal += [fixed[-1][0] + SPAN * k for k in range(1, n_tail + 1)]
    nominal.sort()
    fixed_s = [f for f, _, _ in fixed]
    piers = []
    for s0 in nominal:
        prev = max([p["s"] for p in piers if p["s"] < s0] + [f for f in fixed_s if f < s0], default=s0 - SPAN)
        nxt = min([n for n in nominal if n > s0] + [f for f in fixed_s if f > s0], default=s0 + SPAN)
        best = None                              # (level, |shift|, s, kind): the best level, then the least move
        for d in sorted(range(-SHIFT_MAX, SHIFT_MAX + 1), key=abs):
            s = s0 + d
            if not (SPAN_RANGE[0] <= s - prev <= SPAN_RANGE[1] and SPAN_RANGE[0] <= nxt - s <= SPAN_RANGE[1] + SHIFT_MAX):
                continue
            kind, level = clear(s)
            if best is None or (level, abs(d)) < (best[0], best[1]):
                best = (level, abs(d), s, kind)
            if level == 0:
                break
        level, _, s, kind = best if best else (2, 0, s0, "double")
        piers.append({"s": round(s, 1), "type": kind, "clear": level == 0, "on_road": level == 1,
                      "in_the_way": level == 2, "moved": round(s - s0, 1)})
    for s, kind, pk in fixed:
        if kind == "abutment":
            piers.append({"s": round(s, 1), "type": "abutment", "clear": True, "on_road": False, "in_the_way": False,
                          "moved": 0.0, "fixed": kind})
        elif kind.startswith("long_span"):
            piers.append({"s": round(s, 1), "type": pk[0], "clear": pk[1] == 0, "on_road": pk[1] == 1,
                          "in_the_way": pk[1] == 2, "moved": 0.0, "fixed": kind})
    piers.sort(key=lambda p: p["s"])
    if OUT.exists() and "--replan" not in sys.argv:
        piers = amend(load(OUT)["piers"], clear, free, shafts, plan_lanes)
    for p in piers:
        c = point_at(axis, s_axis, p["s"])
        p["x"], p["y"] = round(float(c[0]), 3), round(float(c[1]), 3)
        p["heading"] = round(heading_at(axis, s_axis, p["s"], 5.0), 5)
        g = ground.at(*c)
        p["ground_z"] = round(g, 2) if g is not None else None
        p["soffit_z"] = round(float(np.interp(p["s"], s_axis, rail)) - SOFFIT_UNDER_RAIL, 2)
        p["in_playable"] = bool(play.contains(Point(*c)))
    piers = [p for p in piers if p["ground_z"] is not None and p["s"] <= s_edge]

    # deck over buildings (outside the stations): to know
    deck_hits = []
    for b in world["buildings"]:
        if str(b["id"]).split("_rest")[0] in keep_out or not b.get("rings"):
            continue
        pg = Polygon(b["rings"][0]).buffer(0)
        c = pg.centroid
        if c.x < -3400 or c.x > 4400:
            continue
        s_b, v_b = project(axis, s_axis, np.array([c.x, c.y]))
        if s_abut - 50 <= s_b <= s_edge and abs(v_b) < 60:
            band = LineString(axis[(s_axis >= s_b - 80) & (s_axis <= s_b + 80)]).buffer(EDGE_HALF + 1.0, cap_style=2)
            if band.intersects(pg):
                deck_hits.append({"id": b["id"], "num": b.get("num"), "s": round(s_b, 1), "height": b.get("height")})

    # ---- the plan
    def r(v, n=2):
        return None if v is None or (isinstance(v, float) and math.isnan(v)) else round(float(v), n)
    heads = [heading_at(axis, s_axis, s, 5.0) for s in s_axis]
    stations = {}
    for key, S in st.items():
        loc = S["local"]
        lv = None if S["hall_z"] is None else {
            "hall_z": S["hall_z"], "passerelle_z": r(S["hall_z"] + PASSERELLE_Z), "rail_z": S["rail_z"],
            "deck_top_z": r(S["rail_z"] - RAIL_OVER_DECK), "platform_z": r(S["hall_z"] + PLATFORM_Z),
            "roof_max_z": r(S["hall_z"] + ROOF_Z)}
        stations[key] = {
            "name": S["name"], "build": S["build"] and S["hall_z"] is not None, "pk": PK[key], "s": S["s"],
            "centre": [r(S["centre"][0], 3), r(S["centre"][1], 3)], "heading": r(S["heading"], 6),
            "heading_deg": r(math.degrees(S["heading"]), 3), "in_playable": S["in_playable"],
            "zone_s": [r(S["s"] - HALF_ZONE, 1), r(S["s"] + HALF_ZONE, 1)], "zone_u": [-HALF_ZONE, HALF_ZONE],
            "levels": lv,
            "platforms": {"u": [-PLATFORM_L / 2, PLATFORM_L / 2], "edge_v": PLATFORM_EDGE_V, "width": PLATFORM_W,
                          "over_rail": PLATFORM_OVER_RAIL},
            "osm_building": "osm:w%d" % S["osm"],
            "footprint_map": [[r(x), r(y)] for x, y in S["footprint"]],
            "footprint_local": [[r(u), r(v)] for u, v in loc],
            "footprint_extent_local": {"u": [r(loc[:, 0].min()), r(loc[:, 0].max())], "v": [r(loc[:, 1].min()), r(loc[:, 1].max())]},
        }
    half_section = [[0.0, WALKWAY_OVER_RAIL], [SPINE_HALF, WALKWAY_OVER_RAIL], [SPINE_HALF, -RAIL_OVER_DECK],
                    [DECK_HALF, -RAIL_OVER_DECK], [DECK_HALF, -RAIL_OVER_DECK - EDGE_T], [1.60, -SOFFIT_UNDER_RAIL],
                    [0.0, -SOFFIT_UNDER_RAIL]]
    out = {
        "about": "Line 18's master plan on the plateau (lot ligne18 and its children), FROZEN: made by "
                 "godot/lots/ligne18/tool/build_plan.py (OSM + the map's ground of 2026-11-13); sources: ref/metro18/README.md.",
        "frame": {"xy": "map metres, x east, y north (Lambert-93 minus 641117.6, 6846184.3)",
                  "z": "metres over the map origin's height (157.731 m NGF), as the heightmap",
                  "godot": "position (x, z, -y); heading theta (radians, from +x towards +y) = rotation.y",
                  "s": "chainage, m along the axis from Massy-Palaiseau, westwards; PK = s + %.1f" % k_pk,
                  "station_frame": "u along the line (increasing s, the heading), v to its left; origin on the axis "
                                   "at the station's s; Godot local (u, z - hall_z, -v) under a node at the centre, "
                                   "rotation.y = heading"},
        "pk_offset": r(k_pk, 1),
        "track": {"centre_v": [TRACK_V, -TRACK_V], "gauge": GAUGE, "rail_top": "rail_z(s), both tracks",
                  "third_rail": "on each track's inner side (towards the axis): the platforms' side stays clear"},
        "viaduct": {"half_section_vz": half_section,
                    "half_section_note": "the deck's outline, v >= 0 (mirror it), z over the rail's top: the spine "
                                         "(walkway at the train floor) between the tracks, the deck slab, its thin "
                                         "edges, the soffit sloping down to the spine's foot",
                    "deck_half": DECK_HALF, "edge_half": EDGE_HALF, "rail_over_deck": RAIL_OVER_DECK,
                    "walkway_over_rail": WALKWAY_OVER_RAIL, "spine_half": SPINE_HALF,
                    "soffit_under_rail": SOFFIT_UNDER_RAIL, "parapet_h": PARAPET_H, "span": SPAN,
                    "pier_double": {"ellipse": PIER_ELL, "centres_apart": PIER_GAP},
                    "pier_single": {"ellipse": PIER1_ELL}, "footing": FOOTING, "bearing": BEARING,
                    "s_start": r(s_v0, 1), "s_abutment": r(s_abut, 1), "s_edge": r(s_edge, 1),
                    "ramp_note": "s_start..s_abutment: the ramp, an embankment between retaining walls (the rail 0.5 m "
                                 "over the ground at s_start, 3 %); s_abutment..s_edge: spans on piers",
                    "long_spans": [{"s": s, "over": name, "span": span} for s, name, span, _, _ in long_spans],
                    "colour": "light concrete (very light grey); stainless cable guard rails"},
        "sections": [dict(x, s0=r(x["s0"], 1), s1=r(x["s1"], 1)) for x in sections],
        "axis_step": float(s_axis[1] - s_axis[0]),
        "axis_columns": ["s", "x", "y", "heading", "ground_z", "rail_z", "kind"],
        "axis": [[r(s, 1), r(p[0], 3), r(p[1], 3), r(h, 5), r(g), r(z, 3), k]
                 for s, p, h, g, z, k in zip(s_axis, axis, heads, gz, rail, kinds)],
        "piers": piers,
        "stations": stations,
        "deck_over_buildings": deck_hits,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes((json.dumps(out, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))

    print("viaduct s %.0f..%.0f (OSM), abutment %.0f, built to %.0f (the heightmap's edge); grade max %.2f %%" % (
        s_v0, s_v1, s_abut, s_edge, grade.max() * 100))
    for key, S in stations.items():
        print("%-14s %s" % (key, S["levels"]))
    print("piers: %d (%d moved off obstacles); on a road, clear of the lanes: %s; in the way: %s; others not clear: %s" % (
        len(piers), sum(1 for p in piers if p["moved"]), [(float(p["s"]), p["type"]) for p in piers if p["on_road"]],
        [float(p["s"]) for p in piers if p["in_the_way"]],
        [float(p["s"]) for p in piers if not p["clear"] and not p["on_road"] and not p["in_the_way"]]))
    hp = [(p["soffit_z"] - BEARING - p["ground_z"]) for p in piers]
    print("pier heights %.1f..%.1f m; deck over buildings: %s" % (min(hp), max(hp), [(h["id"], h["s"]) for h in deck_hits]))
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
