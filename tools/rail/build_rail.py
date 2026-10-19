"""Builds godot/world/rail.json, the RER B (Ligne de Sceaux, RATP, 1,500 V DC) across the map, from OpenStreetMap
(tools/rail/osm_rail.json, fetch_osm.py) and the LiDAR ground the pipeline drew (godot/world/base/heightmap.f32),
with review images in tools/rail/review/.

.venv/Scripts/python tools/rail/build_rail.py      (Linux/macOS: .venv/bin/python; ~1 min; numpy, shapely, Pillow)

Everything here is decided from data, by rule; patch_world.py then applies it to the map files and the Godot builders
draw it. Steps:
1. Tracks: the OSM ways of track 1 (south, westbound: French trains keep left) and track 2 (north, eastbound),
   chained west -> east; their midpoints give the centreline.
2. Horizontal alignment: straights, clothoids (transition curves, curvature linear in s) and circular arcs, fitted by
   least squares (Levenberg-Marquardt) to both OSM tracks at once, with one track spacing for the whole line. Curves are
   found on the OSM curvature, transitions are at least TRANSITION_MIN long; beyond the OSM data the line runs on
   straight (trains are hidden there).
3. Cant and speed per curve: the curve's speed limit from its radius, cant and cant deficiency, capped by the line
   speed (OSM maxspeed) and the speed signs OSM maps (TIV).
4. Vertical profile: LiDAR samples of the trackbed (median across the tracks per 5 m, structures and outliers
   rejected), a grade line through them (Douglas-Peucker breakpoints, least-squares heights) with parabolic vertical
   curves at the grade changes.
5. Cross-section and earthworks: the formation (ballast bed and cess paths) and, each metre and side, a side slope down
   (embankment) or up (cutting) to the LiDAR ground, or a retaining wall where the slope would reach a building, a road
   or a path.
6. Structures: the platforms of Gare de Lozère, the footbridges, the pedestrian underpasses, the covered road under
   the line (Place de la Gare de Lozère), fences.
7. Signals (OSM, with the track and direction they face), kilometre posts (OSM) and hectometre plates, the catenary
   (portals by rule, wires at real heights).
8. Services: per direction, the route along its track (points, planned speed per metre, the stop at Lozère, the
   signals facing it, the block sections), headways.
9. What the railway clears: trees and props in its way (patch_world.py removes or moves them).

rail.json (schema RAIL_SCHEMA; map coordinates, metres; s along the centreline from its west end, u across, positive
to the north; levels are absolute map z):
- alignment: elements [{type straight|clothoid|arc, s0, s1, k0, k1 (1/m, positive turning left)}], step, pts [[x, y]],
  heading [rad from east], z [rail level: top of the inner rail], length, curves [{s0, s1, radius, cant (mm),
  speed (km/h)}], spacing (between the track centres), cant [mm per step, signed: positive raises the north rails].
- profile: pvis [[s, z]], vertical [[s0, s1, radius]], grades [[s0, s1, per mille]], lidar [[s, z, used]].
- track: gauge, rail, pad, sleeper, ballast and formation dimensions.
- tracks: [{ref, side (+1 north, -1 south), offset (u of its centre), direction, osm ways, maxspeed}].
- earthworks: step, s0, sides {left|right: {edge [u of the formation edge], level [formation edge z], kind [0 slope,
  1 wall, 2 platform, 3 none], reach [u where the design meets the ground]}}; walls [{id, side, pts [[x, y]], top [z],
  bottom [z], kind}].
- platforms: [{id, track, side, s0, s1 (first and last metre: top [z] and back [u] per metre), ends (the platform runs
  half a metre beyond them, as the earthworks switch kind halfway between metres), edge, wall, coping, height}].
- footbridges, underpasses, road_tunnel, fences, station (entrances, furniture), signals, pk, catenary.
- services: [{id, track, direction, step, pts [[x, y, z]], heading, cant [rad], v [m/s per step for the front of the
  train], stops [{name, s (front, per train length), side}], signals [{id, s}], blocks, enter, exit, headway, phase}].
- clearance: trees and props removed or moved, with the reason.
"""
import json
import math
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import railgeo as rg  # noqa: E402
from l93 import fwd  # noqa: E402

RAIL_SCHEMA = 1

# ---------------------------------------------------------------- data and sources
# track (metres)
GAUGE = 1.435                   # standard gauge (OSM gauge=1435), between the rails' inner faces
RAIL_HEIGHT = 0.172             # 60E1 (UIC 60) rail: height 172 mm, head 72 mm, foot 150 mm, web 16.5 mm (EN 13674-1)
RAIL_HEAD = 0.072
RAIL_FOOT = 0.150
RAIL_WEB = 0.0165
PAD = 0.009                     # rail pad under the foot; assumed (studded pads are 9-10 mm)
SLEEPER = (2.41, 0.29, 0.22)    # M450 concrete monobloc sleeper: length, width at the rail seat, depth under the rail
                                # (French M450: 2.41 m, 0.29 m, 0.22 m, ~285 kg, per an Italian MITE comparison sheet)
SLEEPER_SPACING = 0.60          # 1,666 sleepers per km, the SNCF standard (techno-science.net "traverse")
BALLAST_DEPTH = 0.30            # under the sleeper; assumed (25-35 cm is usual on main lines)
BALLAST_SHOULDER = 0.40         # ballast beyond the sleeper ends; assumed
BALLAST_SLOPE = 1.5             # ballast shoulder slope, horizontal per vertical; assumed (3:2)
CESS = 1.0                      # walkway beyond the ballast toe, then a drain strip; assumed
DRAIN = 0.6
CROSSFALL = 0.04                # formation falls this much per metre from the centre to its edges; assumed
SIDE_SLOPE = 1.5                # earthwork side slopes, horizontal per vertical (3:2, embankments and cuttings)
WALL_MIN = 0.45                 # m: smaller steps at the formation edge are sloped even where room is short
WALL_RUN_MIN = 12.0             # m: shorter wall runs are dropped (or bridged when they nearly touch)
SLOPE_REACH = 25.0              # m beyond the formation edge a slope may run before a wall is preferred
# platforms (Gare de Lozère)
PLATFORM_HEIGHT = 1.15          # above the rail: RATP's RER A and B platforms are "nearly all at 1,150 mm"
                                # (fr.wikipedia "Quai de gare"); the MI 79 floor is at 1.198 m (sadur.org)
PLATFORM_EDGE = 1.65            # track centre to platform edge: the MI 79 is 2.80 m wide and its body swings ~0.09 m
                                # out at the ends and in at mid-car on the station's 478 m curve (18.5 m between
                                # bogies), so ~1.55 m is the least; 1.65 m is the usual French offset (prompt: 1.6-1.7)
PLATFORM_COPING = 0.30          # the edge coping overhangs the platform wall by this much; assumed (photos show a
                                # dark recess under the edge)
STEP_RISE = 0.17                # stair riser where OSM counts the steps; assumed (usual French public stair)
STEP_GOING = 0.30               # stair tread; assumed
# catenary (1,500 V DC, OSM electrified=contact_line, voltage=1500)
CONTACT_WIRE = 5.25             # m above the rail: "an average height of 5.25 m above the tracks" (RATP, ratp.fr,
                                # "Une nuit avec Johann, caténairiste")
CONTACT_WIRE_MIN = 4.90         # lowest under a low structure; assumed
SYSTEM_HEIGHT = 1.40            # messenger above the contact wire at the supports; assumed (1.5 kV compound catenary)
STAGGER = 0.20                  # contact wire zigzag either side of the track centre at the supports; assumed
SPAN_MAX = 60.0                 # longest span on straight track; assumed (usual 50-63 m)
WIRE_OFFSET_MAX = 0.40          # m the chord of a span may stray off the track centre in curves (sets the curve spans)
MAST_OFFSET = 3.10              # mast face from the outer track's centre on the open line; assumed (French minimum ~3 m)
PORTAL_HEIGHT = 7.30            # portal beam above the rail; assumed (above the messenger)
DROPPER_SPACING = 5.0           # assumed
# operation
LINE_SPEED = 90.0               # km/h (OSM maxspeed=90 on both tracks)
CANT_MAX = 160.0                # mm, SNCF maximum (160, exceptionally 180)
CANT_PRACTICAL = 0.7            # SNCF practice: cant ~7/10 of the theoretical (equilibrium) cant
CANT_DEFICIENCY_MAX = 150.0     # mm; assumed (SNCF admits high cant deficiencies on conventional lines)
CANT_GRADIENT_MAX = 2.5         # mm/m along a transition; assumed (EN 13803 order of magnitude)
TRAIN_LENGTHS = {"8": 208.32, "4": 104.16}   # MI 79: one unit of 4 cars is 104.16 m (en.wikipedia "MI 79")
EXTEND_END = 320.0              # m the line runs on straight beyond the OSM data at its north-east end (a westbound
                                # train starts there, hidden, front and back)
SERVICE_BRAKE = 0.7             # m/s², planned braking to a stop; assumed (comfortable, under the MI 79's 1.1 m/s²)
MAX_SERVICE_BRAKE = 1.1         # m/s², en.wikipedia "MI 79" infobox: deceleration 1.1 m/s² and 1.15 m/s²; the lower one...
EMERGENCY_BRAKE = 1.15          # ...for full service braking, the higher one for the emergency brake
ACCEL = 1.0                     # m/s², MI 79 (en.wikipedia "MI 79": acceleration 1 m/s²)
HEADWAY = 120.0                 # s per direction: the user's choice (real B4 service: every 10-15 min)
DWELL = 40.0                    # s planned at Lozère (the bots use 30-60 s)
TRANSITION_MIN = 20.0           # m, shortest transition curve the fit may use
CURVE_THRESHOLD = 1 / 2500.0    # 1/m: OSM stretches curving more than this become curves
# extent
X_WEST = -615.0                 # the alignment follows OSM from here (past Le Guichet, where the westbound trains end)...
X_EAST = 4030.0                 # ...to here, where the tracks start parting for Massy-Palaiseau's four platform tracks;
                                # from there on the station yard (yard.py terms: each track its own line) takes over
# the stations on the alignment (Lozère's platforms are OSM's outlines; the others have only nodes: side platforms by
# rule, see rule_platforms) and the yard's (Massy-Palaiseau: OSM's island outlines)
STATIONS = ["Lozère", "Palaiseau - Villebon", "Palaiseau", "Massy-Palaiseau"]
RULE_PLATFORM_WIDTH = 3.5       # m from the platform edge to its back where OSM draws no outline; assumed (LiDAR: the
                                # raised ground runs ~2-6 m out from the track centre at both stations)
RULE_PLATFORM_MARGIN = 5.0      # m beyond the trains' ends (both directions' 8-car trains stand on it)
REVIEW = rg.TOOLS / "review"


def log(*a):
    print(*a, flush=True)


DATA_AREA = None                # the map's ground (shapely, prepared): world.json meta.data_area, else its bounds box
OLD_BOX = (-250.0, -1110.0, 1810.0, 630.0)  # the first map's box: Lozère's structures (footbridge, road tunnel)


def set_data_area(world: dict) -> None:
    global DATA_AREA
    from shapely import prepare
    from shapely.geometry import Polygon, box
    rings = world["meta"].get("data_area")
    DATA_AREA = Polygon(rings[0], rings[1:]).buffer(0) if rings else box(*world["meta"]["bounds"])
    prepare(DATA_AREA)


def inside(x, y, margin: float = 0.0) -> np.ndarray:
    """Points (arrays) inside the map's ground, `margin` m in from its edge."""
    import shapely
    g = DATA_AREA if margin == 0 else DATA_AREA.buffer(-margin)
    return shapely.contains_xy(g, np.asarray(x, float), np.asarray(y, float))


# ---------------------------------------------------------------- 1. OSM

def load_osm() -> dict:
    """osm_rail.json, and under it osm_rail_massy.json (the line on to Massy-Palaiseau) when there: the first file's
    elements win, so the first stretch is built from exactly what it was."""
    d = rg.load_json(rg.TOOLS / "osm_rail.json")
    elements = {(e["type"], e["id"]): e for e in d["elements"]}
    stamps = [d.get("osm3s", {}).get("timestamp_osm_base", "")]
    if (rg.TOOLS / "osm_rail_massy.json").exists():
        m = rg.load_json(rg.TOOLS / "osm_rail_massy.json")
        for e in m["elements"]:
            elements.setdefault((e["type"], e["id"]), e)
        stamps.append(m.get("osm3s", {}).get("timestamp_osm_base", ""))
    ways = {i: e for (t, i), e in elements.items() if t == "way"}
    nodes = {i: e for (t, i), e in elements.items() if t == "node"}
    rels = {i: e for (t, i), e in elements.items() if t == "relation"}
    return {"ways": ways, "nodes": nodes, "relations": rels, "timestamp": " + ".join(x for x in stamps if x)}


def way_pts(w: dict) -> np.ndarray:
    return np.array([fwd(g["lat"], g["lon"]) for g in w["geometry"]])


def chain_track(osm: dict, ref: str) -> tuple:
    """The track's OSM ways chained into one polyline, oriented west -> east, and the way ids."""
    ws = [w for w in osm["ways"].values() if w.get("tags", {}).get("railway") == "rail"
          and w["tags"].get("name") == "Ligne de Sceaux" and w["tags"].get("railway:track_ref") == ref]
    segs = [(list(w["nodes"]), list(map(tuple, way_pts(w))), w["id"]) for w in ws]
    nodes, pts, ids = segs[0][0], segs[0][1], [segs[0][2]]
    rest = segs[1:]
    while rest:
        for k, (n, p, i) in enumerate(rest):
            if n[0] == nodes[-1]:
                nodes, pts = nodes + n[1:], pts + p[1:]
            elif n[-1] == nodes[-1]:
                nodes, pts = nodes + n[::-1][1:], pts + p[::-1][1:]
            elif n[-1] == nodes[0]:
                nodes, pts = n[:-1] + nodes, p[:-1] + pts
            elif n[0] == nodes[0]:
                nodes, pts = n[::-1][:-1] + nodes, p[::-1][:-1] + pts
            else:
                continue
            ids.append(i)
            rest.pop(k)
            break
        else:
            break                       # pieces not connected to the rest (none on this line)
    pts = np.array(pts)
    # keep the stretch running west -> east through the map (the tracks curve away beyond X_WEST / X_EAST)
    if pts[0, 0] > pts[-1, 0]:
        pts = pts[::-1]
    return pts, sorted(ids)


def crop_x(p: np.ndarray, x0: float, x1: float) -> np.ndarray:
    """The polyline between its first crossings of x = x0 and x = x1 (it runs west -> east there)."""
    d = rg.cumlen(p)
    fine = rg.resample(p, 0.25)
    keep = (fine[:, 0] >= x0) & (fine[:, 0] <= x1)
    idx = np.nonzero(keep)[0]
    return fine[idx[0]:idx[-1] + 1]


def nearest_on(p: np.ndarray, poly: np.ndarray) -> tuple:
    a = poly[:-1]
    ab = poly[1:] - a
    t = np.clip(np.einsum("ij,ij->i", p - a, ab) / np.einsum("ij,ij->i", ab, ab), 0, 1)
    q = a + ab * t[:, None]
    dd = np.linalg.norm(q - p, axis=1)
    k = int(np.argmin(dd))
    return q[k], dd[k]


# ---------------------------------------------------------------- 2. horizontal alignment

class Fit:
    """Least-squares fit of a railway alignment to the two OSM tracks. Parameters: start point, start heading, the
    track spacing, then per curve (in order): the straight before it (the first curve's start s instead), entry
    transition, arc and exit transition lengths, and the arc's curvature. The centreline is integrated from its
    curvature every STEP m."""

    STEP = 0.5
    WINDOW = 15.0                   # m around a point's first guess searched for its nearest fitted point

    def __init__(self, t1: np.ndarray, t2: np.ndarray, centre: np.ndarray):
        self.length = rg.cumlen(centre)[-1]
        self.centre = centre
        x0, x1 = centre[0, 0] + 3, centre[-1, 0] - 3
        self.obs = []
        for t in (t1, t2):
            o = rg.resample(t, 2.0)
            o = o[(o[:, 0] > x0) & (o[:, 0] < x1)]
            cs = rg.cumlen(centre)
            guess = np.array([cs[int(np.argmin(np.einsum("ij,ij->i", centre - q, centre - q)))] for q in o])
            self.obs.append((o, guess))

    def elements(self, p: np.ndarray) -> list:
        out = []
        s = None
        for i, (g, l1, la, l2, kc) in enumerate(p[4:].reshape(-1, 5)):
            s0 = g if i == 0 else s + abs(g)
            L1, La, L2 = TRANSITION_MIN + abs(l1), abs(la), TRANSITION_MIN + abs(l2)
            out.append((s0, L1, La, L2, kc))
            s = s0 + L1 + La + L2
        return out

    @staticmethod
    def kappa(s: np.ndarray, curves: list) -> np.ndarray:
        k = np.zeros_like(s)
        for s0, L1, La, L2, kc in curves:
            a, b = s0, s0 + L1
            e, f = b + La, b + La + L2
            k += np.where((s >= a) & (s < b), kc * (s - a) / L1, 0.0)
            k += np.where((s >= b) & (s < e), kc, 0.0)
            k += np.where((s >= e) & (s < f), kc * (f - s) / L2, 0.0)
        return k

    def path(self, p: np.ndarray, s_end=None, step=None) -> tuple:
        step = step or self.STEP
        s = np.arange(0.0, (s_end or self.length) + step * 0.5, step)
        k = self.kappa(s, self.elements(p))
        th = p[2] + np.r_[0.0, np.cumsum((k[1:] + k[:-1]) / 2 * step)]
        thm = (th[1:] + th[:-1]) / 2
        x = p[0] + np.r_[0.0, np.cumsum(np.cos(thm) * step)]
        y = p[1] + np.r_[0.0, np.cumsum(np.sin(thm) * step)]
        return s, np.c_[x, y], th, k

    def lateral(self, o: np.ndarray, guess: np.ndarray, T: np.ndarray) -> np.ndarray:
        """Signed distance (positive left) of points o from the polyline T sampled every STEP."""
        w = int(self.WINDOW / self.STEP)
        idx = (guess / self.STEP).astype(int)
        I = np.clip(idx[:, None] + np.arange(-w, w + 1)[None, :], 0, len(T) - 2)
        A, B = T[I], T[I + 1]
        AB = B - A
        t = np.clip(np.einsum("ijk,ijk->ij", o[:, None, :] - A, AB) / np.einsum("ijk,ijk->ij", AB, AB), 0, 1)
        Q = A + AB * t[..., None]
        D = np.linalg.norm(o[:, None, :] - Q, axis=2)
        j = np.argmin(D, axis=1)
        r = np.arange(len(o))
        q, ab = Q[r, j], AB[r, j]
        cross = ab[:, 0] * (o[:, 1] - q[:, 1]) - ab[:, 1] * (o[:, 0] - q[:, 0])
        return np.sign(cross) * D[r, j]

    def residuals(self, p: np.ndarray) -> np.ndarray:
        s, P, th, k = self.path(p)
        n = np.c_[-np.sin(th), np.cos(th)]
        T1, T2 = P - n * p[3] / 2, P + n * p[3] / 2
        return np.r_[self.lateral(*self.obs[0], T1), self.lateral(*self.obs[1], T2)]

    def solve(self, p: np.ndarray, iters=120, frozen=()) -> np.ndarray:
        """Levenberg-Marquardt; the parameters in `frozen` (indices) keep their value."""
        lam = 1e-2
        r = self.residuals(p)
        cost = r @ r
        stalled = 0
        free = [j for j in range(len(p)) if j not in frozen]
        for it in range(iters):
            J = np.zeros((len(r), len(p)))
            for j in free:
                h = 1e-6 if j == 2 else (1e-7 if j >= 4 and (j - 4) % 5 == 4 else 1e-3)
                pp = p.copy()
                pp[j] += h
                J[:, j] = (self.residuals(pp) - r) / h
            A, g = J.T @ J, J.T @ r
            improved = False
            while lam < 1e9:
                dp = np.zeros(len(p))
                Af, gf = A[np.ix_(free, free)], g[free]
                dp[free] = -np.linalg.solve(Af + lam * np.diag(np.diag(Af) + 1e-12), gf)
                rn = self.residuals(p + dp)
                if rn @ rn < cost:
                    gain = (cost - rn @ rn) / cost
                    p, r, cost = p + dp, rn, rn @ rn
                    lam = max(lam / 3, 1e-9)
                    improved = True
                    break
                lam *= 4
            stalled = stalled + 1 if not improved or gain < 1e-6 else 0
            if stalled >= 4:
                break
        return p


X_SECTIONS = [X_WEST, 2180.0, X_EAST]   # the alignment is fitted section by section: the first one is the first map's
                                        # (X_WEST to 2180, unchanged since), each next one from the previous one's end


def fit_alignment(t1: np.ndarray, t2: np.ndarray) -> dict:
    """The alignment section by section (X_SECTIONS: one fit over the whole line drifts into a poor local minimum
    with this many curves), each next section starting where the previous one ends, with its heading and spacing.
    Returns the sections' fits and the joined result (fit_section's keys, the stats over the map)."""
    secs = []
    for x0, x1 in zip(X_SECTIONS[:-1], X_SECTIONS[1:]):
        start = None
        if secs:
            prev = secs[-1]
            s_, P, th, k = prev["fit"].path(prev["p"])
            start = (P[-1], float(th[-1]), float(prev["p"][3]))
        secs.append(fit_section(t1, t2, x0, x1, start))
    return {"sections": secs, "stats": joined_stats(secs), "fit": secs[0]["fit"], "p": secs[0]["p"]}


def joined_stats(secs: list) -> dict:
    rb = np.concatenate([s["inbox"] for s in secs])
    out = {"rms": float(np.sqrt(rb @ rb / len(rb))), "max": float(np.abs(rb).max()),
           "p95": float(np.percentile(np.abs(rb), 95)), "all_max": max(s["stats"]["all_max"] for s in secs),
           "osm_spacing_median": secs[0]["stats"]["osm_spacing_median"]}
    log("alignment: %d sections, %d curves, OSM deviation in the map rms %.2f m, p95 %.2f m, max %.2f m"
        % (len(secs), sum(len(s["fit"].elements(s["p"])) for s in secs), out["rms"], out["p95"], out["max"]))
    return out


class SplineSection:
    """An alignment section as a smoothing spline through the OSM centreline (the line on to Massy has compound
    curves, radius changing within a bend, which one arc per curve cannot follow), pinned to the previous section's
    end and heading; the same calls as Fit (path, elements, length) for alignment_arrays. Its "curves" for the cant
    and speed rules come from the spline's curvature: each run beyond CURVE_THRESHOLD, its sharpest curvature, its
    transitions the stretches where the curvature climbs to and falls from 80 % of that."""

    SIGMA = 0.20                    # m, the OSM noise the spline smooths away (rms of the residuals it allows)
    PIN = 30.0                      # m of the previous section's tangent the spline is held to at its start

    def __init__(self, centre: np.ndarray, start):
        from scipy.interpolate import UnivariateSpline
        p0, th0 = np.asarray(start[0]), float(start[1])
        lead = p0 + np.c_[np.cos(th0), np.sin(th0)] * np.arange(-self.PIN, 0.0, 1.0)[:, None]
        pts = np.vstack([lead, centre])
        u = rg.cumlen(pts)
        w = np.ones(len(pts))
        w[:len(lead) + 1] = 20.0            # the tangent held, the joint exact
        self.u0 = u[len(lead)]
        smooth = len(pts) * self.SIGMA ** 2
        self.sx = UnivariateSpline(u, pts[:, 0], w=w, k=5, s=smooth)
        self.sy = UnivariateSpline(u, pts[:, 1], w=w, k=5, s=smooth)
        dense = np.arange(self.u0, u[-1], 0.25)
        q = np.c_[self.sx(dense), self.sy(dense)]
        q[0] = p0
        self.dense, self.du = dense, rg.cumlen(q)
        self.length = float(self.du[-1])
        self.q = q

    def path(self, p=None, s_end=None, step=1.0):
        s = np.arange(0.0, (s_end or self.length) + step * 0.5, step)
        s = s[s <= self.length + 1e-6]
        uu = np.interp(s, self.du, self.dense)
        P = np.c_[self.sx(uu), self.sy(uu)]
        P[0] = self.q[0]
        dx, dy = self.sx.derivative(1)(uu), self.sy.derivative(1)(uu)
        ddx, ddy = self.sx.derivative(2)(uu), self.sy.derivative(2)(uu)
        th = np.unwrap(np.arctan2(dy, dx))
        k = (dx * ddy - dy * ddx) / np.maximum((dx * dx + dy * dy) ** 1.5, 1e-9)
        return s, P, th, k

    def elements(self, p=None) -> list:
        s, P, th, k = self.path(step=1.0)
        ks = np.convolve(k, np.ones(9) / 9, mode="same")
        out = []
        on = np.abs(ks) > CURVE_THRESHOLD
        i = 0
        while i < len(on):
            if not on[i]:
                i += 1
                continue
            j = i
            while j < len(on) and on[j] and np.sign(ks[j]) == np.sign(ks[i]):
                j += 1
            if j - i >= 20:
                seg = ks[i:j]
                m = int(np.argmax(np.abs(seg)))
                kc = float(seg[m])
                hi = np.nonzero(np.abs(seg) >= 0.8 * abs(kc))[0]
                a, b = int(hi[0]), int(hi[-1])
                L1 = max(float(a), TRANSITION_MIN)
                L2 = max(float(j - i - 1 - b), TRANSITION_MIN)
                out.append((float(s[i]), L1, max(float(b - a), 0.0), L2, kc))
            i = j
        return out


def fit_section(t1: np.ndarray, t2: np.ndarray, x_from: float, x_to: float, start=None) -> dict:
    """Centreline from the two tracks between x_from and x_to, curves found on its curvature, then the least-squares
    fit; `start` (point, heading, spacing): the section begins there, as the previous one ends (those are kept)."""
    a1 = crop_x(t1, x_from, x_to)
    if start is not None:                   # begin at the previous section's end
        k = int(np.argmin(np.linalg.norm(a1 - start[0], axis=1)))
        a1 = a1[k:]
    r1 = rg.resample(a1, 1.0)
    mids, spacing = [], []
    for p in r1:
        q, dd = nearest_on(p[None, :], t2)
        mids.append((p + q) / 2)
        spacing.append(dd)
    centre = rg.resample(np.array(mids), 1.0)
    if start is not None:                   # a later section: the spline (compound curves), from the previous end
        sp = SplineSection(centre[1:], start)
        p = np.r_[start[0][0], start[0][1], start[1], start[2]]
        s_, P, th, k = sp.path()
        n = np.c_[-np.sin(th), np.cos(th)]
        res = []
        for t, sg in ((t1, -1.0), (t2, 1.0)):
            o = rg.resample(t, 2.0)
            o = o[(o[:, 0] > x_from + 3) & (o[:, 0] < x_to - 3)]
            T = P + n * sg * start[2] / 2
            from shapely.geometry import LineString, Point
            ln = LineString(T)
            res.append(np.array([ln.distance(Point(q)) for q in o]))
            res[-1] = res[-1][inside(o[:, 0], o[:, 1])]
        rb = np.concatenate(res)
        stats = {"rms": float(np.sqrt(rb @ rb / len(rb))), "max": float(np.abs(rb).max()),
                 "p95": float(np.percentile(np.abs(rb), 95)), "all_max": float(np.abs(rb).max()),
                 "osm_spacing_median": float(np.median(spacing))}
        log("alignment section x %.0f..%.0f: smoothing spline, %d curves, spacing %.3f m (the previous section's; "
            "OSM's median %.2f m), OSM deviation in the map rms %.2f m, p95 %.2f m, max %.2f m"
            % (x_from, x_to, len(sp.elements()), start[2], np.median(spacing), stats["rms"], stats["p95"], stats["max"]))
        return {"fit": sp, "p": p, "stats": stats, "inbox": rb}
    fit = Fit(t1, t2, centre)
    # first guess: curves where the smoothed OSM curvature passes CURVE_THRESHOLD
    d = np.diff(centre, axis=0)
    th = np.unwrap(np.arctan2(d[:, 1], d[:, 0]))
    W = 30
    k = np.array([np.polyfit(np.arange(b - a), th[a:b], 1)[0] if b - a > 4 else 0.0
                  for a, b in ((max(0, i - W), min(len(th), i + W + 1)) for i in range(len(th)))])
    runs = []
    sign = np.sign(k) * (np.abs(k) > CURVE_THRESHOLD)
    i = 0
    while i < len(sign):
        if sign[i] == 0:
            i += 1
            continue
        j = i
        while j < len(sign) and sign[j] == sign[i]:
            j += 1
        if runs and runs[-1][2] == sign[i] and i - runs[-1][1] < 10:
            runs[-1][1] = j
        else:
            runs.append([i, j, sign[i]])
        i = j
    # each curve first fitted alone to the OSM heading around it (its transitions, arc and curvature), so the global
    # fit starts close to the answer
    local = []
    for n_, (a, b, sg) in enumerate(runs):
        lo = 0 if n_ == 0 else (runs[n_ - 1][1] + a) // 2
        hi = len(th) if n_ == len(runs) - 1 else (b + runs[n_ + 1][0]) // 2
        local.append(_fit_curve(np.arange(lo, hi) + 0.5, th[lo:hi], a, b, float(np.median(k[a:b]))))
    guess = []
    prev_end = 0.0
    for n_, (s0, L1, La, L2, kc) in enumerate(local):
        L1, L2 = max(L1, TRANSITION_MIN + 0.5), max(L2, TRANSITION_MIN + 0.5)
        g = s0 if n_ == 0 else max(s0 - prev_end, 0.5)
        guess.append((g, L1 - TRANSITION_MIN, La, L2 - TRANSITION_MIN, kc))
        prev_end = (s0 if n_ == 0 else prev_end + g) + L1 + La + L2
    p = np.r_[centre[0, 0], centre[0, 1], th[0], float(np.median(spacing)), np.array(guess).ravel()]
    frozen = ()
    if start is not None:
        p[0], p[1], p[2], p[3] = start[0][0], start[0][1], start[1], start[2]
        frozen = (0, 1, 2, 3)
    t0 = time.time()
    p = fit.solve(p, frozen=frozen)
    r = fit.residuals(p)
    inbox = []
    for (o, _), rr in zip(fit.obs, np.split(r, [len(fit.obs[0][0])])):
        inbox.append(rr[inside(o[:, 0], o[:, 1])])
    rb = np.concatenate(inbox)
    stats = {"rms": float(np.sqrt(rb @ rb / len(rb))), "max": float(np.abs(rb).max()),
             "p95": float(np.percentile(np.abs(rb), 95)), "all_max": float(np.abs(r).max()),
             "osm_spacing_median": float(np.median(spacing))}
    log("alignment section x %.0f..%.0f: %d curves, spacing %.3f m, OSM deviation in the map rms %.2f m, p95 %.2f m, "
        "max %.2f m (%.0f s)" % (x_from, x_to, len(guess), p[3], stats["rms"], stats["p95"], stats["max"],
                                 time.time() - t0))
    return {"fit": fit, "p": p, "stats": stats, "inbox": rb}


def _fit_curve(s: np.ndarray, th: np.ndarray, a: int, b: int, kc: float) -> tuple:
    """One curve (entry transition, arc, exit transition) fitted to the heading th(s) around it: least squares on
    (heading before it, start, L1, La, L2, curvature). Returns (s0, L1, La, L2, kc)."""
    def model(q):
        th0, s0, L1, La, L2, k = q
        L1, La, L2 = abs(L1) + 1.0, abs(La), abs(L2) + 1.0
        x = s - s0
        out = np.where(x <= 0, 0.0, np.where(x <= L1, k * x * x / (2 * L1), 0.0))
        e = x - L1
        out = np.where((x > L1) & (e <= La), k * L1 / 2 + k * e, out)
        f = e - La
        out = np.where((e > La) & (f <= L2), k * L1 / 2 + k * La + k * (f - f * f / (2 * L2)), out)
        out = np.where(f > L2, k * (L1 / 2 + La + L2 / 2), out)
        return th0 + out
    q = np.array([th[0], a - 15.0, 30.0, max(b - a - 30.0, 5.0), 30.0, kc])
    lam = 1e-3
    r = model(q) - th
    for _ in range(200):
        J = np.zeros((len(s), 6))
        for j in range(6):
            h = 1e-6 if j in (0, 5) else 1e-3
            qq = q.copy()
            qq[j] += h
            J[:, j] = (model(qq) - th - r) / h
        A, g = J.T @ J, J.T @ r
        dq = -np.linalg.solve(A + lam * np.diag(np.diag(A) + 1e-12), g)
        rn = model(q + dq) - th
        if rn @ rn < r @ r:
            q, r, lam = q + dq, rn, lam / 3
            if np.abs(dq).max() < 1e-6:
                break
        else:
            lam *= 5
    th0, s0, L1, La, L2, k = q
    return (s0, abs(L1) + 1.0, abs(La), abs(L2) + 1.0, k)


def alignment_arrays(fa: dict, step=1.0) -> dict:
    """The fitted centreline every `step` m, the sections joined (each next one's s goes on from the previous one's
    end), with its elements (it ends at X_EAST: the yard carries on)."""
    S, Ps, Ths, Ks, curves = [], [], [], [], []
    base = 0.0
    for sec in fa["sections"]:
        fit, p = sec["fit"], sec["p"]
        s_, P_, th_, k_ = fit.path(p, s_end=fit.length, step=step)
        if S:
            s_, P_, th_, k_ = s_[1:], P_[1:], th_[1:], k_[1:]
        S.append(s_ + base)
        Ps.append(P_)
        Ths.append(th_)
        Ks.append(k_)
        curves += [(c[0] + base, *c[1:]) for c in fit.elements(p)]
        base += fit.length
    s, P, th, k = np.concatenate(S), np.concatenate(Ps), np.concatenate(Ths), np.concatenate(Ks)
    # every `step` m of the joined line exactly (each section's last sample falls short of its end)
    d = rg.cumlen(P)
    s = np.arange(0.0, d[-1] + 1e-9, step)
    P = np.c_[np.interp(s, d, P[:, 0]), np.interp(s, d, P[:, 1])]
    th, k = np.interp(s, d, np.unwrap(th)), np.interp(s, d, k)
    total = float(s[-1])
    els = []
    pos = 0.0
    for s0, L1, La, L2, kc in curves:
        if s0 > pos + 1e-6:
            els.append({"type": "straight", "s0": pos, "s1": s0, "k0": 0.0, "k1": 0.0})
        if s0 < 0:                      # the line starts inside its first curve
            pass
        els.append({"type": "clothoid", "s0": s0, "s1": s0 + L1, "k0": 0.0, "k1": kc})
        els.append({"type": "arc", "s0": s0 + L1, "s1": s0 + L1 + La, "k0": kc, "k1": kc})
        els.append({"type": "clothoid", "s0": s0 + L1 + La, "s1": s0 + L1 + La + L2, "k0": kc, "k1": 0.0})
        pos = s0 + L1 + La + L2
    if pos < total:
        els.append({"type": "straight", "s0": pos, "s1": float(s[-1]), "k0": 0.0, "k1": 0.0})
    els = [e for e in els if e["s1"] > 0.0]
    for e in els:
        e["s0"] = max(e["s0"], 0.0)
    return {"s": s, "pts": P, "heading": th, "kappa": k, "curves": curves, "elements": els,
            "spacing": float(fa["sections"][0]["p"][3])}


# ---------------------------------------------------------------- 3. cant and speed

def design_curves(al: dict, signs: list) -> list:
    """Per curve: radius, cant (mm) and speed limit (km/h). V = sqrt((D + I) R / 11.8) with the cant D limited by
    CANT_MAX and by the cant gradient over its shorter transition, I = CANT_DEFICIENCY_MAX; the practical cant is
    CANT_PRACTICAL of the equilibrium cant at that speed. Speed signs from OSM (`signs`: [{s0, s1, kmh}]) cap it."""
    out = []
    for s0, L1, La, L2, kc in al["curves"]:
        R = abs(1.0 / kc)
        d_max = math.floor(min(CANT_MAX, CANT_GRADIENT_MAX * min(L1, L2)) / 5.0) * 5.0
        v = math.sqrt((d_max + CANT_DEFICIENCY_MAX) * R / 11.8)
        v = min(LINE_SPEED, math.floor(v / 5.0) * 5.0)
        s1 = s0 + L1 + La + L2
        for sg in signs:
            if sg["s0"] < s1 and sg["s1"] > s0:
                v = min(v, sg["kmh"])
        d = min(d_max, round(CANT_PRACTICAL * 11.8 * v * v / R / 5.0) * 5.0)
        out.append({"s0": round(float(s0), 2), "s1": round(float(s1), 2), "entry": round(float(L1), 2),
                    "arc": round(float(La), 2), "exit": round(float(L2), 2), "radius": round(float(R), 1),
                    "turn": "left" if kc > 0 else "right", "cant": float(d), "speed": float(v),
                    "deficiency": round(float(11.8 * v * v / R - d), 1)})
    return out


def cant_profile(al: dict, curves: list) -> np.ndarray:
    """Cant (mm) every step: full on the arc, linear along the transitions; signed: positive raises the rails on the
    north (left) side, i.e. curves turning right (the outer rail is on the left)."""
    s = al["s"]
    c = np.zeros_like(s)
    for (s0, L1, La, L2, kc), cd in zip(al["curves"], curves):
        sign = -1.0 if kc > 0 else 1.0      # a left-hand curve raises the right (south) rails
        a, b, e, f = s0, s0 + L1, s0 + L1 + La, s0 + L1 + La + L2
        c += sign * cd["cant"] * np.clip(np.minimum((s - a) / L1, (f - s) / L2), 0.0, 1.0) * ((s >= a) & (s <= f))
    return c


# ---------------------------------------------------------------- 4. vertical profile

def lidar_profile(al: dict, H: rg.Heights, avoid: list) -> np.ndarray:
    """[s, z, used] every 5 m inside the map: the median LiDAR ground over +-2.6 m across the centreline (both tracks'
    ballast), not where a structure is (`avoid`: [(s0, s1)]), and not where it strays more than 0.25 m from a running
    median of its neighbours (dips, embankment edges)."""
    s, P, th = al["s"], al["pts"], al["heading"]
    n = np.c_[-np.sin(th), np.cos(th)]
    rows = []
    for k in range(0, len(s), 5):
        x, y = P[k]
        if not inside(x, y, 5.0):
            continue
        us = np.linspace(-2.6, 2.6, 11)
        a, b = max(k - 2, 0), min(k + 3, len(s))
        q = (P[a:b, None, :] + n[a:b, None, :] * us[None, :, None]).reshape(-1, 2)
        z = float(np.median(H.sample(q[:, 0], q[:, 1])))
        used = not any(s0 <= s[k] <= s1 for s0, s1 in avoid)
        rows.append([float(s[k]), z, used])
    rows = np.array(rows, dtype=np.float64)
    ok = rows[:, 2] > 0
    for _ in range(2):
        idx = np.nonzero(ok)[0]
        med = np.array([np.median(rows[idx[max(0, j - 4):j + 5], 1]) for j in range(len(idx))])
        bad = np.abs(rows[idx, 1] - med) > 0.25
        ok[idx[bad]] = False
    rows[:, 2] = ok
    return rows


def douglas_peucker(x: np.ndarray, y: np.ndarray, tol: float) -> list:
    keep = {0, len(x) - 1}
    stack = [(0, len(x) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        t = (x[a + 1:b] - x[a]) / (x[b] - x[a])
        d = np.abs(y[a + 1:b] - (y[a] + t * (y[b] - y[a])))
        j = int(np.argmax(d))
        if d[j] > tol:
            m = a + 1 + j
            keep.add(m)
            stack += [(a, m), (m, b)]
    return sorted(keep)


def fit_profile(samples: np.ndarray, length: float) -> dict:
    """Grade line through the used samples: breakpoints by Douglas-Peucker (0.15 m) on a smoothed profile, at least
    100 m apart, heights by least squares; then parabolic vertical curves (radius VERTICAL_R, less where two would
    overlap, never under VERTICAL_R_MIN). Levels are the ballast top (the LiDAR's trackbed)."""
    VERTICAL_R = 8000.0             # m; assumed (gentle)
    VERTICAL_R_MIN = 2835.0         # 0.35 V² at 90 km/h, the usual minimum vertical radius rule
    used = samples[samples[:, 2] > 0]
    sx, sz = used[:, 0], used[:, 1]
    sm = np.convolve(np.r_[[sz[0]] * 4, sz, [sz[-1]] * 4], np.ones(9) / 9, mode="valid")
    knots = douglas_peucker(sx, sm, 0.15)
    ks = [sx[knots[0]]]
    for j in knots[1:-1]:
        if sx[j] - ks[-1] >= 100.0 and sx[knots[-1]] - sx[j] >= 100.0:
            ks.append(sx[j])
    ks.append(sx[knots[-1]])
    ks = np.array(ks)
    # piecewise-linear least squares on the knot heights (hat basis)
    B = np.zeros((len(sx), len(ks)))
    for i in range(len(ks)):
        if i > 0:
            m = (sx >= ks[i - 1]) & (sx <= ks[i])
            B[m, i] = (sx[m] - ks[i - 1]) / (ks[i] - ks[i - 1])
        if i < len(ks) - 1:
            m = (sx >= ks[i]) & (sx < ks[i + 1])
            B[m, i] = (ks[i + 1] - sx[m]) / (ks[i + 1] - ks[i])
    kz = np.linalg.lstsq(B, sz, rcond=None)[0]
    # the grade line runs on at its end grades beyond the samples (out of the map)
    g0 = (kz[1] - kz[0]) / (ks[1] - ks[0])
    g1 = (kz[-1] - kz[-2]) / (ks[-1] - ks[-2])
    pvis = [[0.0, kz[0] - g0 * ks[0]]] + [[float(a), float(b)] for a, b in zip(ks, kz)] + \
        [[length, kz[-1] + g1 * (length - ks[-1])]]
    pvis = [pvis[0]] + pvis[2:-2] + [pvis[-1]] if len(pvis) > 4 else pvis
    # pvis[0] / pvis[-1] carry the end grades; the inner ones are the grade changes
    grades = [(pvis[i + 1][1] - pvis[i][1]) / (pvis[i + 1][0] - pvis[i][0]) for i in range(len(pvis) - 1)]
    vertical = []
    for i in range(1, len(pvis) - 1):
        dg = grades[i] - grades[i - 1]
        room = min(pvis[i][0] - pvis[i - 1][0], pvis[i + 1][0] - pvis[i][0])
        R = VERTICAL_R
        if abs(dg) > 1e-9:
            R = min(R, max(room / abs(dg), VERTICAL_R_MIN))     # half lengths fit within half the neighbours
        L = R * abs(dg)
        vertical.append([pvis[i][0] - L / 2, pvis[i][0] + L / 2, R])
    return {"pvis": pvis, "grades": grades, "vertical": vertical}


def profile_z(prof: dict, s: np.ndarray) -> np.ndarray:
    """Ballast-top level of the grade line with its vertical curves at s."""
    px = np.array([p[0] for p in prof["pvis"]])
    pz = np.array([p[1] for p in prof["pvis"]])
    z = np.interp(s, px, pz)
    g = prof["grades"]
    for i, (a, b, R) in enumerate(prof["vertical"]):
        L = b - a
        if L <= 0:
            continue
        g1, g2 = g[i], g[i + 1]
        m = (s > a) & (s < b)
        t = s[m] - a
        za = np.interp(a, px, pz)
        z[m] = za + g1 * t + (g2 - g1) * t * t / (2 * L)
    return z


# ---------------------------------------------------------------- 6. structures

def _way_len(p: np.ndarray) -> float:
    return float(rg.cumlen(p)[-1])


def section_dims() -> dict:
    """Cross-section of a track, relative to the rail level (inner rail top) on straight track."""
    sleeper_top = -(RAIL_HEIGHT + PAD)
    sleeper_bottom = sleeper_top - SLEEPER[2]
    formation = sleeper_bottom - BALLAST_DEPTH
    return {"rail_height": RAIL_HEIGHT, "pad": PAD, "sleeper_top": round(sleeper_top, 4),
            "sleeper_bottom": round(sleeper_bottom, 4), "formation": round(formation, 4)}


def ballast_toe(spacing: float) -> float:
    """|u| of the ballast toe of the double track on straight track: the outer sleeper end, the shoulder, the slope."""
    sec = section_dims()
    return spacing / 2 + SLEEPER[0] / 2 + BALLAST_SHOULDER + (sec["sleeper_top"] - sec["formation"]) * BALLAST_SLOPE


def osm_structures(osm: dict, A: rg.Alignment, H: rg.Heights) -> list:
    """The ways crossing the line on a bridge or in a tunnel (OSM bridge=yes / tunnel=yes highways crossing the
    centreline inside the map), grouped with the bridge/tunnel ways and the steps connected to them: footbridges,
    pedestrian underpasses and the road tunnel."""
    ways = osm["ways"]
    hw = {i: w for i, w in ways.items() if "highway" in w.get("tags", {})}
    node_ways = {}
    for i, w in hw.items():
        for n in w["nodes"]:
            node_ways.setdefault(n, []).append(i)
    pts = {i: way_pts(w) for i, w in hw.items()}
    su = {}
    for i, p in pts.items():
        su[i] = A.project(p)
    crossing = []
    for i, w in hw.items():
        t = w["tags"]
        if not (t.get("bridge") == "yes" or t.get("tunnel") == "yes"):
            continue
        s, u = su[i][:, 0], su[i][:, 1]
        x, y = pts[i][:, 0], pts[i][:, 1]
        in_old = np.any((x > OLD_BOX[0]) & (x < OLD_BOX[2]) & (y > OLD_BOX[1]) & (y < OLD_BOX[3]))
        # beyond the first box the bridges are world.json's (the map's bridge decks); only the tunnels are the line's
        if np.any(np.diff(np.sign(u)) != 0) and np.all(np.abs(u) < 60) and np.all((s > 1.0) & (s < A.length - 1.0)) \
                and np.any(inside(x, y)) and (in_old or t.get("tunnel") == "yes"):
            crossing.append(i)
    groups = []
    seen = set()
    for i in crossing:
        if i in seen:
            continue
        kind = "bridge" if ways[i]["tags"].get("bridge") == "yes" else "tunnel"
        members = {i}
        frontier = [i]
        while frontier:                 # the same structure: connected ways of the same kind
            j = frontier.pop()
            for n in ways[j]["nodes"]:
                for k in node_ways.get(n, []):
                    t = ways[k]["tags"]
                    same = (t.get("bridge") == "yes") if kind == "bridge" else (t.get("tunnel") == "yes")
                    if k not in members and same:
                        members.add(k)
                        frontier.append(k)
        seen |= members
        steps = set()
        landings = {}                   # steps way -> the short connector (< 4 m) between it and the structure
        for j in members:
            for n in ways[j]["nodes"]:
                for k in node_ways.get(n, []):
                    if k in members:
                        continue
                    if ways[k]["tags"].get("highway") == "steps":
                        steps.add(k)
                    elif _way_len(pts[k]) < 4.0:
                        for m in (ways[k]["nodes"][0], ways[k]["nodes"][-1]):
                            for st in node_ways.get(m, []):
                                if st not in members and ways[st]["tags"].get("highway") == "steps":
                                    steps.add(st)
                                    landings[st] = k
        road = any(ways[j]["tags"]["highway"] in ("tertiary", "secondary", "primary", "residential", "unclassified",
                                                   "service", "tertiary_link") for j in members)
        g = {"kind": "footbridge" if kind == "bridge" else ("road_tunnel" if road else "underpass"),
             "ways": sorted(members), "steps": sorted(steps), "landings": landings,
             "s": float(np.mean(su[i][:, 0][np.argsort(np.abs(su[i][:, 1]))[:2]]))}
        groups.append(g)
    groups.sort(key=lambda g: g["s"])
    for g in groups:
        ids = g["ways"] + g["steps"] + list(g["landings"].values())
        g["geom"] = {j: pts[j] for j in ids}
        g["tags"] = {j: ways[j]["tags"] for j in ids}
        g["nodes"] = {j: ways[j]["nodes"] for j in ids}
    return groups


def osm_platforms(osm: dict, A: rg.Alignment, spacing: float, cant_at) -> list:
    """The platforms (OSM railway=platform areas next to the line): the track they serve, their extent along it, the
    edge (PLATFORM_EDGE from the track centre), the back (the OSM outline's far side), the top (PLATFORM_HEIGHT above
    the platform-side rail, cant included) and the OSM furniture tags."""
    from shapely.geometry import LineString, Polygon
    out = []
    for w in osm["ways"].values():
        t = w.get("tags", {})
        if t.get("railway") != "platform":
            continue
        p = way_pts(w)
        su = A.project(p)
        if np.abs(su[:, 1]).min() > 15 or su[:, 0].min() > A.length - 1.0 or su[:, 0].max() < 1.0:
            continue
        side = 1.0 if np.median(su[:, 1]) > 0 else -1.0
        poly = Polygon(su)                      # in (s, u)
        s0, s1 = float(su[:, 0].min()), float(su[:, 0].max())
        ss = np.arange(math.ceil(s0), math.floor(s1) + 1.0)
        back = []
        for s in ss:
            cut = poly.intersection(LineString([(s, -40), (s, 40)]))
            us = [c[1] for g in getattr(cut, "geoms", [cut]) for c in getattr(g, "coords", [])]
            back.append(max(abs(u) for u in us) if us else 0.0)
        back = np.array(back)
        edge = spacing / 2 + PLATFORM_EDGE
        back = np.maximum(np.array([np.median(back[max(0, i - 3):i + 4]) for i in range(len(back))]), edge + 2.5)
        out.append({"id": "platform:" + ("north" if side > 0 else "south") if t.get("name", "") in ("", "Lozère")
                    else "platform:%s:%s" % (slug(t["name"]), "north" if side > 0 else "south"), "osm": "w%d" % w["id"],
                    "name": t.get("name", ""), "track": "2" if side > 0 else "1", "side": side,
                    "s0": float(ss[0]), "s1": float(ss[-1]), "ss": ss, "edge": edge, "wall": edge + PLATFORM_COPING,
                    "back_u": back, "tags": {k: v for k, v in t.items() if k not in ("name", "railway",
                                                                                      "public_transport")}})
    for p in out:
        ss, b = p["ss"], p["back_u"]
        p["back"] = (lambda ss=ss, b=b: (lambda s: float(np.interp(s, ss, b))))()
        side = p["side"]
        p["top"] = (lambda side=side: (lambda s: float(A.level(s) + max(side * cant_at(s), 0.0) / 1000.0
                                                       + PLATFORM_HEIGHT)))()
    out.sort(key=lambda p: -p["side"])
    return out


def slug(name: str) -> str:
    import re
    import unicodedata
    a = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", a.lower()).strip("-")


def stop_nodes(osm: dict) -> dict:
    """(station name, track ref) -> map point of OSM's stop position (railway=stop, ref 1 or 2)."""
    out = {}
    for nd in osm["nodes"].values():
        t = nd.get("tags", {})
        if t.get("railway") == "stop" and (t.get("ref") or t.get("local_ref")) in ("1", "2"):
            out[(t.get("name", ""), t.get("ref") or t.get("local_ref"))] = np.array(fwd(nd["lat"], nd["lon"]))
    return out


def rule_platforms(osm: dict, A: rg.Alignment, spacing: float, cant_at, have: list) -> list:
    """Side platforms where OSM maps a station on the alignment by nodes only (Palaiseau - Villebon, Palaiseau; the
    LiDAR shows raised ground outside both tracks there): both sides over the stretch both directions' 8-car trains
    stand on (their fronts at OSM's stop positions), RULE_PLATFORM_MARGIN beyond, the edge PLATFORM_EDGE out from the
    outer track, RULE_PLATFORM_WIDTH deep, furnished as a lit platform with shelters, benches and bins."""
    stops = stop_nodes(osm)
    named = {slug(p["name"]) for p in have}          # "Palaiseau-Villebon" outlines = station "Palaiseau - Villebon"
    out = []
    L8 = TRAIN_LENGTHS["8"]
    for name in STATIONS:
        if slug(name) in named or (name, "1") not in stops or (name, "2") not in stops:
            continue
        s1 = float(A.project(stops[(name, "1")][None, :])[0][0])      # westbound front: the train runs on east of it
        s2 = float(A.project(stops[(name, "2")][None, :])[0][0])      # eastbound front: the train runs on west of it
        if not (5.0 < s1 < A.length - 5.0 and 5.0 < s2 < A.length - 5.0):
            continue
        a = min(s1, s2 - L8) - RULE_PLATFORM_MARGIN
        b = max(s1 + L8, s2) + RULE_PLATFORM_MARGIN
        ss = np.arange(math.ceil(a), math.floor(b) + 1.0)
        edge = spacing / 2 + PLATFORM_EDGE
        for side in (1.0, -1.0):
            out.append({"id": "platform:%s:%s" % (slug(name), "north" if side > 0 else "south"), "osm": "",
                        "name": name, "track": "2" if side > 0 else "1", "side": side, "s0": float(ss[0]),
                        "s1": float(ss[-1]), "ss": ss, "edge": edge, "wall": edge + PLATFORM_COPING,
                        "back_u": np.full(len(ss), edge + RULE_PLATFORM_WIDTH),
                        "tags": {"lit": "yes", "shelter": "yes", "bench": "yes", "bin": "yes", "source": "rule"}})
    for p in out:
        ss, b = p["ss"], p["back_u"]
        p["back"] = (lambda ss=ss, b=b: (lambda s: float(np.interp(s, ss, b))))()
        side = p["side"]
        p["top"] = (lambda side=side: (lambda s: float(A.level(s) + max(side * cant_at(s), 0.0) / 1000.0
                                                       + PLATFORM_HEIGHT)))()
    return out


def cap_platform_backs(platforms: list, A: rg.Alignment, corridor) -> None:
    """A platform's back never reaches into a road, sidewalk or building (OSM's outline of the south platform runs
    into the bus terminus beside it): it stops 0.2 m short of the first one along the normal."""
    for p in platforms:
        b = p["back_u"].copy()
        for i, s in enumerate(p["ss"]):
            q = A.point(np.array([s, s]), np.array([p["side"] * (p["edge"] + 0.5), p["side"] * b[i]]))
            f, what = corridor.limit(q[0], q[1])
            if f < 1.0:
                b[i] = max(p["edge"] + 2.5, p["edge"] + 0.5 + f * (b[i] - p["edge"] - 0.5) - 0.2)
        b = np.array([np.min(b[max(0, i - 2):i + 3]) for i in range(len(b))])
        p["back_u"] = b
        p["back"] = (lambda ss=p["ss"], bb=b: (lambda s: float(np.interp(s, ss, bb))))()


class Corridor:
    """What the earthworks must stay clear of, as shapely geometry: buildings with walls, and the ground pieces people
    use (roads, sidewalks, paths, parkings, steps...), but not the railway's own stairs and paths (`ignore`)."""

    KINDS = ["road", "sidewalk", "parking", "pedestrian", "footway", "path", "cycleway", "steps", "traffic_island",
             "track", "playground", "pitch", "water", "running_track"]

    def __init__(self, world: dict, near, ignore):
        from shapely.geometry import Polygon
        from shapely.strtree import STRtree
        geoms, kinds = [], []
        for b in world["buildings"]:
            if not b.get("walls", True):
                continue                # canopies (the station's stair roof)
            pg = Polygon(b["rings"][0])
            if pg.is_valid and pg.intersects(near):
                geoms.append(pg.buffer(0.3))
                kinds.append("building " + b["id"])
        for k, g in enumerate(world["ground"]):
            if g["kind"] not in self.KINDS:
                continue
            pg = Polygon(g["rings"][0], g["rings"][1:]).buffer(0)
            if not pg.intersects(near):
                continue
            if g["kind"] in ("steps", "footway", "path") and pg.intersects(ignore):
                continue
            geoms.append(pg)
            kinds.append("%s ground:%d" % (g["kind"], k))
        self.geoms = geoms
        self.kinds = kinds
        self.tree = STRtree(geoms)

    def limit(self, a: np.ndarray, b: np.ndarray) -> tuple:
        """First hit along the segment a -> b (map points): (fraction, what) or (1.0, '')."""
        from shapely.geometry import LineString, Point
        ln = LineString([a, b])
        best = (1.0, "")
        for i in self.tree.query(ln):
            inter = ln.intersection(self.geoms[i])
            if inter.is_empty:
                continue
            f = min(ln.project(Point(c)) for g in getattr(inter, "geoms", [inter]) for c in g.coords) / ln.length
            if f < best[0]:
                best = (f, self.kinds[i])
        return best


def cess_caps(osm: dict, A: rg.Alignment) -> list:
    """OSM fences running along the line within 8 m of the centreline cap the formation there: [(side, s0, s1, u)]."""
    out = []
    for w in osm["ways"].values():
        if w.get("tags", {}).get("barrier") not in ("fence", "wall"):
            continue
        su = A.project(way_pts(w))
        for a, b in zip(su[:-1], su[1:]):
            if abs(a[1]) < 8 and abs(b[1]) < 8 and abs(b[0] - a[0]) > 3 and abs(a[1] - b[1]) < 1.5 \
                    and np.sign(a[1]) == np.sign(b[1]):
                out.append((float(np.sign(a[1])), float(min(a[0], b[0])), float(max(a[0], b[0])),
                            float(min(abs(a[1]), abs(b[1])) - 0.3)))
    return out


# ---------------------------------------------------------------- 5. earthworks

def _runs(mask: np.ndarray) -> list:
    out = []
    i = 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j < len(mask) and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def earthworks(al: dict, A: rg.Alignment, H: rg.Heights, corridor: Corridor, platforms: list, caps: list,
               spacing: float) -> dict:
    """Per metre and side inside the map: the formation edge, then a 3:2 slope to the LiDAR ground (embankment or
    cutting), or a retaining wall at the formation edge where the slope would run into a building, a road or a path,
    or would not meet the ground within SLOPE_REACH. Smaller steps than WALL_MIN are always sloped; wall runs shorter
    than WALL_RUN_MIN are sloped unless a building or road is right there, gaps under 6 m between walls are walled.
    Platforms take the place of the formation edge on their side."""
    sec = section_dims()
    s_all = al["s"]
    ins = np.nonzero(inside(al["pts"][:, 0], al["pts"][:, 1]))[0]
    k0, k1 = int(ins[0]), int(ins[-1])
    toe = ballast_toe(spacing)
    out = {"step": 1.0, "s0": float(s_all[k0]), "sides": {}, "walls": []}
    us_rel = np.arange(0.0, SLOPE_REACH + 0.01, 0.5)

    def slope_reach(s, sg, uf, ze):
        us = uf + us_rel
        q = A.point(np.full(len(us), s), sg * us)
        T = H.at(q[:, 0], q[:, 1])
        d0 = T[0] - ze
        slope = ze + np.sign(d0) * (us - uf) / SIDE_SLOPE
        meet = np.nonzero(np.sign(d0) * (T - slope) <= 0.0)[0]
        if abs(d0) < 0.03:
            return d0, uf, ze, q, us, T
        if len(meet):
            m = int(meet[0])
            if m == 0:
                return d0, uf, ze, q, us, T
            a_ = np.sign(d0) * (T[m - 1] - slope[m - 1])
            b_ = np.sign(d0) * (T[m] - slope[m])
            u_end = us[m - 1] + 0.5 * a_ / max(a_ - b_, 1e-9)
            return d0, u_end, float(np.interp(u_end, us, T)), q, us, T
        return d0, math.inf, float(T[-1]), q, us, T

    for side, sg in (("left", 1.0), ("right", -1.0)):
        n = k1 - k0 + 1
        edge, level, reach, top = np.zeros(n), np.zeros(n), np.zeros(n), np.zeros(n)
        kind = np.zeros(n, dtype=int)
        why = [""] * n
        for j in range(n):
            s = float(s_all[k0 + j])
            F0 = float(A.level(s)) + sec["formation"]
            pf = [p for p in platforms if p["side"] == sg and p["s0"] <= s <= p["s1"]]
            if pf:
                p = pf[0]
                kind[j] = 2
                edge[j] = p["wall"]
                level[j] = F0 - CROSSFALL * p["wall"]
                reach[j] = p["back"](s)
                top[j] = p["top"](s)
                continue
            uf = toe + CESS + DRAIN
            for cs, a, b, umax in caps:
                if cs == sg and a <= s <= b:
                    uf = min(uf, umax)
            # a building or road closer than the formation's edge: the formation stops short of it
            q0 = A.point(np.array([s, s]), np.array([sg * (toe - 0.5), sg * uf]))
            hit_f, hit_what = corridor.limit(q0[0], q0[1])
            if hit_f < 1.0:
                uf = min(uf, toe - 0.5 + hit_f * (uf - toe + 0.5) - 0.2)
            uf = max(uf, toe + 0.3)
            ze = F0 - CROSSFALL * uf
            edge[j], level[j] = uf, ze
            d0, u_end, z_end, q, us, T = slope_reach(s, sg, uf, ze)
            lim_f, lim_what = corridor.limit(q[0], q[-1])
            u_lim = uf + lim_f * SLOPE_REACH
            if abs(d0) < WALL_MIN or (u_end <= u_lim and u_end < uf + SLOPE_REACH):
                kind[j] = 0
                reach[j] = min(u_end, uf + SLOPE_REACH)
                top[j] = z_end if math.isfinite(u_end) else float(T[-1])
            else:
                kind[j] = 1
                reach[j] = uf + 1.5
                top[j] = float(np.interp(uf + 1.5, us, T))
                why[j] = lim_what if u_end > u_lim else "the ground keeps %s" % ("rising" if d0 > 0 else "falling")
        for a, b in _runs(kind == 1):
            if b - a >= WALL_RUN_MIN or any(why[j].startswith(("building", "road", "sidewalk")) for j in range(a, b)):
                continue
            for j in range(a, b):
                s = float(s_all[k0 + j])
                d0, u_end, z_end, q, us, T = slope_reach(s, sg, edge[j], level[j])
                kind[j] = 0
                reach[j] = min(u_end, edge[j] + SLOPE_REACH)
                top[j] = z_end if math.isfinite(u_end) else float(T[-1])
                why[j] = ""
        runs = _runs(kind == 1)
        for (a, b), (c, d) in zip(runs, runs[1:]):
            if c - b < 6 and all(kind[j] == 0 for j in range(b, c)):
                for j in range(b, c):
                    kind[j] = 1
                    reach[j] = edge[j] + 1.5
                    q = A.point(np.array([s_all[k0 + j]]), np.array([sg * reach[j]]))
                    top[j] = float(H.at(q[:, 0], q[:, 1])[0])
                    why[j] = why[b - 1]
        out["sides"][side] = {"edge": edge, "level": level, "kind": kind, "reach": reach, "top": top, "why": why}
        for a, b in _runs(kind == 1):
            ss = s_all[k0 + a:k0 + b]
            out["walls"].append({"side": side, "s0": float(ss[0]), "s1": float(ss[-1]),
                                 "pts": A.point(ss, sg * edge[a:b]), "u": edge[a:b].copy(),
                                 "bottom": np.minimum(level[a:b], top[a:b]), "top": np.maximum(level[a:b], top[a:b]),
                                 "cutting": top[a:b] > level[a:b],
                                 "why": sorted({why[j] for j in range(a, b) if why[j]})})
    return out


# ---------------------------------------------------------------- 6b. structure geometry

FOOTBRIDGE_WIDTH = 2.6          # deck between the railings; assumed (photos of the station's: ~3 m outside)
FOOTBRIDGE_DEPTH = 0.55         # deck structure under the walking surface; assumed
STAIR_WIDTH = 2.0               # stair flights; assumed (OSM gives none)
UNDERPASS_WIDTH = 3.0           # pedestrian underpasses, inside; assumed
UNDERPASS_HEADROOM = 2.50       # floor to ceiling; assumed
SLAB = 0.50                     # roof slab of the underpasses and the road tunnel under the formation; assumed
ROAD_WIDTH = 6.5                # the covered road inside its walls: two 3.0 m lanes and 0.25 m margins; assumed
ROAD_HEADROOM = 3.60            # OSM maxheight=3.5 (signed), plus the usual ~0.1 m margin
ROAD_GRADE_MAX = 0.08           # steepest grade of the covered road's ramps; assumed (urban road)
ELECTRICAL_CLEARANCE = 0.25     # m between the catenary and a structure; assumed (1.5 kV)


def footbridge(g: dict, A: rg.Alignment, design_z) -> dict:
    """Deck along the OSM bridge way(s), its level from the stairs (risers above their foot) and never under the
    catenary (contact wire at its lowest under a structure, the messenger close above it, the electrical clearance and
    the deck's depth); a stair flight along each OSM steps way, from its foot (the ground, or a platform) to the deck."""
    deck = [g["geom"][j] for j in g["ways"]]
    deck_pts = np.concatenate(deck)
    ends = {n for j in g["ways"] for n in (g["nodes"][j][0], g["nodes"][j][-1])}
    su = A.project(deck_pts)
    s_mid = float(np.mean(su[:, 0]))
    rail = float(A.level(s_mid))
    flights = []
    estimates = []
    for j in g["steps"]:
        p = g["geom"][j]
        nodes = g["nodes"][j]
        top_first = nodes[0] in ends
        foot = p[-1] if top_first else p[0]
        fs = A.project(foot[None, :])[0]
        z_foot = design_z(fs[0], fs[1], foot)
        count = int(g["tags"][j].get("step_count", 0) or 0)
        flights.append({"osm": "w%d" % j, "pts": (p if not top_first else p[::-1]), "foot": z_foot, "count": count})
        if count:
            estimates.append(z_foot + count * STEP_RISE)
    lowest = rail + CONTACT_WIRE_MIN + 0.30 + ELECTRICAL_CLEARANCE + FOOTBRIDGE_DEPTH
    z = max(float(np.median(estimates)) if estimates else lowest, lowest)
    out_flights = []
    for f in flights:
        rise = z - f["foot"]
        n = f["count"] if f["count"] and 0.13 <= rise / f["count"] <= 0.20 else max(1, round(rise / STEP_RISE))
        out_flights.append({"osm": f["osm"], "pts": f["pts"], "bottom": round(f["foot"], 3), "top": round(z, 3),
                            "steps": n, "riser": round(rise / n, 4), "going": round(_way_len(f["pts"]) / n, 3),
                            "osm_steps": f["count"], "width": STAIR_WIDTH})
    return {"id": "footbridge:%d" % g["ways"][0], "osm": ["w%d" % j for j in g["ways"]], "s": round(s_mid, 2),
            "deck": deck_pts, "level": round(z, 3), "width": FOOTBRIDGE_WIDTH, "depth": FOOTBRIDGE_DEPTH,
            "clearance": round(z - FOOTBRIDGE_DEPTH - rail, 3), "flights": out_flights,
            "from_steps": [round(e, 2) for e in estimates]}


def underpass(g: dict, A: rg.Alignment, design_z, platforms: list) -> dict:
    """A pedestrian underpass: the OSM tunnel ways are covered passages at one floor level; the OSM steps attached to
    them are open stairwells from the ground down to it; tunnel ways ending on a platform become stairs up to it. The
    floor: the stairwells' foot (risers below their top), never above what the formation over it allows (headroom
    and roof slab)."""
    ends = {}
    for j in g["ways"]:
        for n in (g["nodes"][j][0], g["nodes"][j][-1]):
            ends[n] = ends.get(n, 0) + 1
    crossing = max(g["ways"], key=lambda j: np.ptp(A.project(g["geom"][j])[:, 1]))
    sc = A.project(g["geom"][crossing])
    s_mid = float(np.mean(sc[:, 0]))
    rail = float(A.level(s_mid))
    formation = rail + section_dims()["formation"]
    ceiling_max = formation - SLAB
    estimates, wells = [], []
    member_nodes = {n for j in g["ways"] for n in g["nodes"][j]}
    for j in g["steps"]:
        p = g["geom"][j]
        nodes = g["nodes"][j]
        landing = g["landings"].get(j)
        low = member_nodes | (set(g["nodes"][landing]) if landing else set())
        bottom_first = nodes[0] in low
        top = p[-1] if bottom_first else p[0]
        ts = A.project(top[None, :])[0]
        z_top = design_z(ts[0], ts[1], top)
        count = int(g["tags"][j].get("step_count", 0) or 0)
        flight = p[::-1] if bottom_first else p
        land = None
        if landing:
            lp = g["geom"][landing]
            land = lp if np.linalg.norm(lp[0] - flight[-1]) < np.linalg.norm(lp[-1] - flight[-1]) else lp[::-1]
        wells.append({"osm": "w%d" % j, "pts": flight, "top": z_top, "count": count, "landing": land})
        estimates.append(z_top - (count or round(_way_len(p) / STEP_GOING)) * STEP_RISE)
    floor = min(float(np.median(estimates)) if estimates else ceiling_max - UNDERPASS_HEADROOM,
                ceiling_max - UNDERPASS_HEADROOM)
    passages, ramps = [], []
    for j in g["ways"]:
        p = g["geom"][j]
        su = A.project(p)
        on_platform = None
        for k, (s, u) in ((0, su[0]), (-1, su[-1])):
            for pf in platforms:
                if pf["s0"] - 6 <= s <= pf["s1"] and np.sign(u) == pf["side"] and abs(u) > pf["edge"] - 0.5 \
                        and ends.get(g["nodes"][j][k], 0) == 1:
                    on_platform = (k, pf)
        if on_platform:
            k, pf = on_platform
            q = p if k == -1 else p[::-1]           # from the passage up to the platform
            s_end = A.project(q[-1][None, :])[0][0]
            rise = pf["top"](min(max(s_end, pf["s0"]), pf["s1"])) - floor
            n = max(1, round(rise / STEP_RISE))
            ramps.append({"osm": "w%d" % j, "pts": q, "bottom": round(floor, 3), "top": round(floor + rise, 3),
                          "steps": n, "riser": round(rise / n, 4), "going": round(_way_len(q) / n, 3),
                          "platform": pf["id"], "width": STAIR_WIDTH})
        else:
            passages.append({"osm": "w%d" % j, "pts": p})
    flights = []
    for w in wells:
        rise = w["top"] - floor
        n = w["count"] if w["count"] and 0.13 <= rise / w["count"] <= 0.20 else max(1, round(rise / STEP_RISE))
        flights.append({"osm": w["osm"], "pts": w["pts"], "top": round(w["top"], 3), "bottom": round(floor, 3),
                        "steps": n, "riser": round(rise / n, 4), "going": round(_way_len(w["pts"]) / n, 3),
                        "osm_steps": w["count"], "width": STAIR_WIDTH,
                        "landing": w["landing"] if w["landing"] is not None else []})
    return {"id": "underpass:%d" % crossing, "osm": ["w%d" % j for j in g["ways"]], "s": round(s_mid, 2),
            "floor": round(floor, 3), "width": UNDERPASS_WIDTH, "headroom": UNDERPASS_HEADROOM, "slab": SLAB,
            "passages": passages, "stairwells": flights, "stairs_up": ramps,
            "from_steps": [round(e, 2) for e in estimates]}


def A_spacing(A: rg.Alignment) -> float:
    return A.spacing


def road_tunnel(g: dict, osm: dict, A: rg.Alignment, design_z, H: rg.Heights) -> dict:
    """The covered road (Place de la Gare de Lozère, OSM tunnel=yes along its whole length, maxheight 3.5): from the
    station square, under the parking strip along Boulevard de Palaiseau, the north platform's east end and both
    tracks, out to the junction with Rue Charles Péguy. Its profile: from the square's level down to where its roof
    fits under the formation, then up to the junction (the one-way link the OSM way continues into), grades at most
    ROAD_GRADE_MAX. Covered where the ground over it leaves room for the headroom and the roof slab; elsewhere an
    open trench (the portals between)."""
    main = max(g["ways"], key=lambda j: _way_len(g["geom"][j]))
    p = g["geom"][main]
    last = osm["ways"][main]["nodes"][-1]
    # continue into the link towards the junction (the OSM way stops where the links fork)
    link = None
    for w in osm["ways"].values():
        t = w.get("tags", {})
        if t.get("highway", "").endswith("_link") and w["nodes"][0] == last and t.get("oneway") == "yes":
            link = way_pts(w)
    if link is not None:
        p = np.concatenate([p, link[1:]])
    p = rg.resample(p, 1.0)
    t = rg.cumlen(p)
    su = A.project(p)
    surface = np.array([design_z(a, b, q) for (a, b), q in zip(su, p)])
    z0 = float(H.at(p[0, 0], p[0, 1]))
    z1 = float(H.at(p[-1, 0], p[-1, 1]))
    # lowest point: where the roof must pass under the formation (the crossing of the track centreline)
    k_cross = int(np.argmin(np.abs(su[:, 1])))
    need = surface - SLAB - ROAD_HEADROOM
    under = np.abs(su[:, 1]) < ballast_toe(A_spacing(A)) + CESS + DRAIN + 1.0
    z_low = float(need[under].min()) if under.any() else float(need[k_cross])
    k_low = int(np.nonzero(under)[0][np.argmin(need[under])]) if under.any() else k_cross
    road = np.interp(t, [0.0, t[k_low], t[-1]], [z0, z_low, z1])
    # under cover wherever the ground over it stands well above this first guess (the parking strip, the platform's
    # end, the line), within the grade limit
    must = under | ((surface - road) > 2.5)
    road = np.minimum(road, np.where(must, need, np.inf))
    # the grade limit lowers the neighbours of a point the cover pulled down (it never lifts the road back into it)
    for i in range(1, len(road)):
        road[i] = min(road[i], road[i - 1] + ROAD_GRADE_MAX * (t[i] - t[i - 1]))
    for i in range(len(road) - 2, -1, -1):
        road[i] = min(road[i], road[i + 1] + ROAD_GRADE_MAX * (t[i + 1] - t[i]))
    covered = (surface - road) >= ROAD_HEADROOM + SLAB - 0.01
    runs = _runs(covered)
    run = max(runs, key=lambda r: r[1] - r[0]) if runs else (k_low, k_low + 1)
    grades = np.diff(road) / np.diff(t)
    return {"id": "road_tunnel:%d" % main, "osm": ["w%d" % j for j in g["ways"]], "name":
            osm["ways"][main]["tags"].get("name", ""), "pts": p, "z": road, "width": ROAD_WIDTH,
            "headroom": ROAD_HEADROOM, "slab": SLAB, "covered": [round(float(t[run[0]]), 1), round(float(t[run[1] - 1]), 1)],
            "t": t, "surface": surface, "max_grade": round(float(np.abs(grades).max()) * 100, 1),
            "lowest": round(float(road.min()), 3), "maxheight": osm["ways"][main]["tags"].get("maxheight", "")}


# ---------------------------------------------------------------- 7. signals, kilometre posts, catenary

SIGNAL_OFFSET = 2.5             # signal mast from its track's centre; assumed
# OSM states -> what the game shows: FR:VL clear (green), FR:A warning (yellow), FR:S stop (red), FR:C carré (two
# reds), FR:R slow (two yellows, unused here)


def osm_signals(osm: dict, A: rg.Alignment, track_ways: dict, spacing: float) -> list:
    """Every OSM signal on the two tracks: kind, ref, track, the direction it faces (+1 eastbound trains, -1
    westbound), whether that is the track's normal direction, its states, its mast position (left of the trains it
    faces, as OSM's railway:signal:position=left says; counter-direction signals, whose left is the space between the
    tracks, stand on their track's outer side)."""
    out = []
    for n in osm["nodes"].values():
        t = n.get("tags", {})
        if t.get("railway") != "signal":
            continue
        p = np.array(fwd(n["lat"], n["lon"]))
        s, u = A.project(p[None, :])[0]
        if not (0.0 < s < A.length):
            continue
        track, way = None, None
        for ref, ids in track_ways.items():
            for wid in ids:
                if n["id"] in osm["ways"][wid]["nodes"]:
                    track, way = ref, osm["ways"][wid]
        if track is None:
            continue
        i = way["nodes"].index(n["id"])
        g = way["geometry"]
        a = np.array(fwd(g[max(i - 1, 0)]["lat"], g[max(i - 1, 0)]["lon"]))
        b = np.array(fwd(g[min(i + 1, len(g) - 1)]["lat"], g[min(i + 1, len(g) - 1)]["lon"]))
        th = float(A.theta(s))
        way_east = float(np.dot(b - a, [math.cos(th), math.sin(th)])) > 0
        forward = t.get("railway:signal:direction", "forward") == "forward"
        facing = 1 if way_east == forward else -1
        if "railway:signal:main" in t:
            kind = t["railway:signal:main"]
            states = t.get("railway:signal:main:states", "").split(";")
        elif "railway:signal:distant" in t:
            kind = "FR:A"
            states = t.get("railway:signal:distant:states", "").split(";")
        elif "railway:signal:speed_limit_distant" in t:
            kind = "FR:TIV-D"
            states = []
        else:
            kind, states = "unknown", []
        normal = (track == "2" and facing > 0) or (track == "1" and facing < 0)
        tu = spacing / 2 if track == "2" else -spacing / 2
        mast_u = tu + facing * SIGNAL_OFFSET if normal else tu + math.copysign(SIGNAL_OFFSET, tu)
        out.append({"id": "signal:%d" % n["id"], "osm": "n%d" % n["id"], "ref": t.get("ref", ""), "kind": kind,
                    "states": [x for x in states if x], "track": track, "facing": facing, "normal": normal,
                    "s": round(float(s), 2), "u": round(mast_u, 3),
                    "speed": int(t["railway:signal:speed_limit_distant:speed"])
                    if "railway:signal:speed_limit_distant:speed" in t else None,
                    "plate": t.get("railway:signal:main:plate", t.get("railway:signal:distant:plate", ""))})
    out.sort(key=lambda x: x["s"])
    return out


def pk_points(osm: dict, A: rg.Alignment) -> dict:
    """Kilometre posts (OSM railway=milestone, railway:position in km) and the line's PK at s (least squares through
    them: PK falls eastwards, the line's origin being Paris-Luxembourg... read from the posts, not assumed)."""
    rows, posts = [], []
    for n in osm["nodes"].values():
        t = n.get("tags", {})
        if t.get("railway") != "milestone" or "railway:position" not in t:
            continue
        p = np.array(fwd(n["lat"], n["lon"]))
        s, u = A.project(p[None, :])[0]
        if not (0.0 < s < A.length) or abs(u) > 5:
            continue
        km = float(t["railway:position"].replace(",", "."))
        rows.append((s, km))
        posts.append({"id": "pk:%d" % n["id"], "osm": "n%d" % n["id"], "s": round(float(s), 2),
                      "u": round(float(u) + math.copysign(1.0, u), 3), "km": km})
    rows = np.array(rows)
    b, a = np.polyfit(rows[:, 0], rows[:, 1], 1)
    return {"a": float(a), "b": float(b), "posts": sorted(posts, key=lambda x: x["s"])}


def rail_bridges(osm: dict, A: rg.Alignment, track_ids: list) -> list:
    """Where the line runs on a bridge beyond the first box (OSM bridge=yes on its tracks: short spans over a road or
    a path): [{s0, s1, osm}], both tracks' spans joined, half a metre more each end. The patch leaves the ground under
    them alone (the road goes on under) and the builder draws the deck."""
    spans = []
    for wid in track_ids:
        w = osm["ways"].get(wid)
        if w is None or w.get("tags", {}).get("bridge") not in ("yes", "viaduct"):
            continue
        p = way_pts(w)
        if np.all((p[:, 0] > OLD_BOX[0]) & (p[:, 0] < OLD_BOX[2]) & (p[:, 1] > OLD_BOX[1]) & (p[:, 1] < OLD_BOX[3])):
            continue                            # the first box's structures are its own (the covered road)
        su = A.project(p)
        su = su[np.abs(su[:, 1]) < 10.0]
        if not len(su) or su[:, 0].max() < 1.0 or su[:, 0].min() > A.length - 1.0:
            continue
        spans.append([float(su[:, 0].min()) - 0.5, float(su[:, 0].max()) + 0.5, "w%d" % wid])
    spans.sort()
    out = []
    for a, b, o in spans:
        if out and a <= out[-1]["s1"] + 1.0:
            out[-1]["s1"] = max(out[-1]["s1"], b)
            out[-1]["osm"].append(o)
        else:
            out.append({"s0": a, "s1": b, "osm": [o]})
    return out


def cut_spans(zs: list, A: rg.Alignment, spans: list) -> list:
    """The zones less the rail bridges' spans (|u| < 45 m): the ground there stays as it is."""
    import shapely
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    if not spans:
        return zs
    cuts = []
    for sp in spans:
        ss = np.arange(sp["s0"], sp["s1"] + 0.01, 0.5)
        cuts.append(Polygon(np.concatenate([A.point(ss, np.full(len(ss), 45.0)),
                                            A.point(ss[::-1], np.full(len(ss), -45.0))])).buffer(0))
    cut = unary_union(cuts)
    out = []
    for z in zs:
        g = unary_union([Polygon(pg[0], pg[1:]).buffer(0) for pg in z["polygons"]])
        if not g.intersects(cut):
            out.append(z)
            continue
        g = shapely.set_precision(g.difference(cut), 0.001)
        polys = [x for x in getattr(g, "geoms", [g]) if x.geom_type == "Polygon" and x.area > 0.05]
        if polys:
            out.append(dict(z, polygons=[[np.asarray(q.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1]
                                                                             for h in q.interiors] for q in polys]))
    return out


def bridge_decks(world: dict, A: rg.Alignment) -> list:
    """The map's bridge decks (world.json bridges, the pipeline's: roads and paths over the line beyond the first box)
    crossing the alignment: [(s, half width along the line, deck underside level, id)]."""
    out = []
    for b in world.get("bridges", []):
        p = np.asarray(b["pts"], dtype=np.float64)
        su = A.project(p[:, :2])
        for k in range(len(p) - 1):
            ua, ub = su[k, 1], su[k + 1, 1]
            if ua == 0 or np.sign(ua) == np.sign(ub) or not (1.0 < su[k, 0] < A.length - 1.0) or abs(ua - ub) > 40:
                continue
            t = ua / (ua - ub)
            s_x = su[k, 0] + (su[k + 1, 0] - su[k, 0]) * t
            z_x = p[k, 2] + (p[k + 1, 2] - p[k, 2]) * t
            depth = 0.9 if b.get("kind") == "road" else 0.45      # godot builder/bridge_builder.gd ROAD_DECK, PATH_DECK
            ang = abs(math.sin(math.atan2(p[k + 1, 1] - p[k, 1], p[k + 1, 0] - p[k, 0]) - float(A.theta(s_x))))
            half = (float(b["width"]) / 2 + 0.6) / max(ang, 0.3)
            out.append((float(s_x), half, float(z_x - depth), b["id"]))
    return out


def catenary(al: dict, A: rg.Alignment, design: rg.Design, platforms: list, structures: dict, spacing: float,
             pk: dict, decks: list = ()) -> dict:
    """Portals (two masts and a beam across both tracks, as at Gare de Lozère) by rule: spans up to SPAN_MAX on
    straight track and shorter in curves, where a span's chord may stray at most WIRE_OFFSET_MAX off the track
    (span <= 2 sqrt(2 R WIRE_OFFSET_MAX)); never over a footbridge deck, an underpass or the road tunnel, nor on a
    platform's stairs. Masts stand MAST_OFFSET out from the outer track on the open line, at the platform's back in
    the station. The contact wire zigzags STAGGER either side of each track (pulled outwards in curves), at
    CONTACT_WIRE above the rail, lower under a footbridge that leaves less room; the messenger hangs SYSTEM_HEIGHT
    above it at the supports. Hectometre plates (PK every 100 m) go on the masts."""
    s = al["s"]
    R = np.where(np.abs(al["kappa"]) > 1e-6, 1.0 / np.maximum(np.abs(al["kappa"]), 1e-9), np.inf)
    span_r = np.minimum(SPAN_MAX, 2.0 * np.sqrt(2.0 * R * WIRE_OFFSET_MAX))
    keep_out = []
    for fb in structures["footbridges"]:
        keep_out.append((fb["s"] - FOOTBRIDGE_WIDTH / 2 - 2.5, fb["s"] + FOOTBRIDGE_WIDTH / 2 + 2.5))
        for f in fb["flights"]:
            ss = A.project(f["pts"])[:, 0]
            keep_out.append((float(ss.min()) - 1.0, float(ss.max()) + 1.0))
    for up in structures["underpasses"]:
        for ps in up["passages"]:
            ss = A.project(ps["pts"])[:, 0]
            keep_out.append((float(ss.min()) - 3.0, float(ss.max()) + 3.0))
    rt = structures["road_tunnel"]
    if rt:
        su = A.project(rt["pts"])
        near = np.abs(su[:, 1]) < 8
        if near.any():
            keep_out.append((float(su[near, 0].min()) - 4.0, float(su[near, 0].max()) + 4.0))

    for sd, half, under, _id in decks:            # the map's bridges over the line: no portal under a deck
        keep_out.append((sd - half - 2.5, sd + half + 2.5))

    def allowed(x):
        return not any(a <= x <= b for a, b in keep_out)

    start = 0.0
    supports = [start]
    end = float(s[-1])
    while supports[-1] < end - 1.0:
        a = supports[-1]
        i0, i1 = int(a), min(int(a + SPAN_MAX) + 1, len(s) - 1)
        span = float(np.min(span_r[i0:i1 + 1]))
        x = min(a + span, end)
        while x > a + 15.0 and not allowed(x):
            x -= 1.0
        if not allowed(x):
            x = a + span
            while not allowed(x) and x < end:
                x += 1.0
        supports.append(float(x))
    deck_low = []
    for fb in structures["footbridges"]:
        deck_low.append((fb["s"], fb["level"] - fb["depth"]))
    deck_low += [(sd, under) for sd, half, under, _id in decks]
    out = []
    flip = 1.0
    for x in supports:
        if not (0 <= x <= end):
            continue
        rail = float(A.level(x))
        cw = CONTACT_WIRE
        for sd, under in deck_low:
            room = under - rail - ELECTRICAL_CLEARANCE - 0.30
            if room < cw + SYSTEM_HEIGHT:
                fade = np.clip(1.0 - (abs(x - sd) - 10.0) / 60.0, 0.0, 1.0)
                cw = min(cw, max(CONTACT_WIRE_MIN, min(cw, room)) * fade + cw * (1 - fade))
        system = SYSTEM_HEIGHT
        for sd, under in deck_low:
            if abs(x - sd) < 40.0:
                system = min(system, max(0.30, under - rail - ELECTRICAL_CLEARANCE - cw))
        masts = []
        for sg in (1.0, -1.0):
            pf = [p for p in platforms if p["side"] == sg and p["s0"] + 1 <= x <= p["s1"] - 1]
            mu = (pf[0]["back"](x) - 0.45) if pf else spacing / 2 + MAST_OFFSET
            q = A.point(x, sg * mu)
            masts.append([round(float(q[0]), 3), round(float(q[1]), 3), round(design.z_or_ground(x, sg * mu, q), 3),
                          round(sg * mu, 3)])
        k = int(round(x))
        kappa = float(al["kappa"][min(k, len(s) - 1)])
        wires = {}
        for track, tu in (("1", -spacing / 2), ("2", spacing / 2)):
            if abs(kappa) > 1e-5:
                # the chord between supports bows inwards: put the wire outside by half the sagitta
                prev_span = 50.0
                off = -math.copysign(min(prev_span ** 2 / (16.0 / abs(kappa)), WIRE_OFFSET_MAX), kappa)
                off += flip * min(STAGGER, max(0.0, WIRE_OFFSET_MAX - abs(off)))
            else:
                off = flip * STAGGER
            q = A.point(x, tu + off)
            wires[track] = [round(float(q[0]), 3), round(float(q[1]), 3), round(rail + cw, 3),
                            round(rail + cw + system, 3), round(tu + off, 3)]
        flip = -flip
        out.append({"s": round(x, 2), "masts": masts, "beam": round(rail + max(PORTAL_HEIGHT, cw + system + 0.6), 3),
                    "wires": wires})
    # hectometre plates on the masts nearest each 100 m of PK (the south mast)
    plates = []
    a, b = pk["a"], pk["b"]
    km_lo, km_hi = sorted([a + b * 0.0, a + b * end])
    for h in range(int(math.ceil(km_lo * 10)), int(math.floor(km_hi * 10)) + 1):
        sx = (h / 10.0 - a) / b
        j = int(np.argmin([abs(sp["s"] - sx) for sp in out]))
        if abs(out[j]["s"] - sx) < 30:
            plates.append({"support": j, "km": round(h / 10.0, 1)})
    return {"contact": CONTACT_WIRE, "contact_min": CONTACT_WIRE_MIN, "system": SYSTEM_HEIGHT, "stagger": STAGGER,
            "droppers": DROPPER_SPACING, "supports": out, "plates": plates}


# ---------------------------------------------------------------- 8. services

def speed_limits(al: dict, curves: list) -> np.ndarray:
    """km/h along the centreline: the line speed, the curves' limits over the whole curve (transitions included)."""
    v = np.full(len(al["s"]), LINE_SPEED)
    for c in curves:
        m = (al["s"] >= c["s0"]) & (al["s"] <= c["s1"])
        v[m] = np.minimum(v[m], c["speed"])
    return v


def track_route(al: dict, A: rg.Alignment, cant: np.ndarray, track: str, spacing: float, limits: np.ndarray) -> dict:
    """The track's centre every metre in its trains' direction (track 2 eastbound, track 1 westbound): points with
    the rail level (the track centre, half the cant above the inner rail), heading, cant angle (positive: the left
    rail, seen by the train, higher) and the centreline's s and speed limit there."""
    tu = spacing / 2 if track == "2" else -spacing / 2
    sc = np.arange(0.0, A.length, 0.25)
    P = A.point(sc, np.full(len(sc), tu))
    d = rg.cumlen(P)
    st = np.arange(0.0, d[-1], 1.0)
    s_c = np.interp(st, d, sc)
    pts = A.point(s_c, np.full(len(s_c), tu))
    D = np.interp(s_c, al["s"], cant) / 1000.0           # signed: positive raises the north rails
    z = A.level(s_c) + np.abs(D) / 2
    th = A.theta(s_c)
    roll = np.arcsin(np.clip(D / 1.5, -1, 1))            # rail heads ~1.5 m apart
    lim = np.interp(s_c, al["s"], limits)
    if track == "1":                                     # westbound: reversed, heading turned round
        pts, z, th, roll, lim, s_c = pts[::-1], z[::-1], th[::-1] + math.pi, -roll[::-1], lim[::-1], s_c[::-1]
    else:
        roll = roll                                      # eastbound: the north rails are on the left
    return {"pts": pts, "z": z, "heading": th, "roll": roll, "limit": lim, "s_centre": s_c}


def planned_speed(route: dict, length: float, end_stop: float = None) -> np.ndarray:
    """m/s for the front of the train every metre: the lowest limit over the train's length behind it (it may only
    speed up once its tail has left a slower stretch), braking at SERVICE_BRAKE ahead of every slower stretch, and to
    a stop at `end_stop` (route s) when the route ends at a station."""
    lim = route["limit"] / 3.6
    n = len(lim)
    L = int(math.ceil(length))
    v = np.array([lim[max(0, i - L):i + 1].min() for i in range(n)])
    if end_stop is not None:
        e = int(round(end_stop))
        v[e:] = 0.0
    for i in range(n - 2, -1, -1):
        v[i] = min(v[i], math.sqrt(v[i + 1] ** 2 + 2 * SERVICE_BRAKE * 1.0))
    return v


def run_time(v: np.ndarray, s_from: float, s_to: float, start_speed: float) -> float:
    """Seconds to drive from s_from (at start_speed) to a stop at s_to, accelerating at ACCEL under the planned speed
    and braking at SERVICE_BRAKE."""
    a, b = int(s_from), int(s_to)
    vv = v[a:b + 1].copy()
    vv[-1] = 0.0
    for i in range(len(vv) - 2, -1, -1):
        vv[i] = min(vv[i], math.sqrt(vv[i + 1] ** 2 + 2 * SERVICE_BRAKE))
    cur = start_speed
    t = 0.0
    for i in range(len(vv) - 1):
        nxt = min(vv[i + 1], math.sqrt(cur * cur + 2 * ACCEL))
        t += 2.0 / max(cur + nxt, 0.1)
        cur = nxt
    return t


# ---------------------------------------------------------------- 9. clearance

CLEAR_STRIP = 3.0               # m beyond the ballast toe kept free of trees (vegetation management strip); assumed
CROWN_GAP = 3.6                 # m from a track centre within which no crown may hang (car body 1.4 m, swing, the
                                # pantograph and catenary zone); assumed
FURNITURE_DUPLICATES = {"bench_back", "bench_flat", "bin_vigipirate", "lamp_path", "lamp_street", "info_board"}


def clearance(world: dict, A: rg.Alignment, design: rg.Design, zones_union, hard_union, spacing: float,
              platforms: list, yard_lines=None) -> dict:
    """Trees and props in the railway's way, decided by rule: trees whose trunk is on the reshaped ground or in the
    cleared strip, or whose crown hangs within CROWN_GAP of a track; props on the trackbed, the platforms or in a
    stairwell or the road's trench (`hard_union`; on a slope they just follow the new ground): furniture the platforms have their own of is dropped, the rest moved to the nearest free spot
    beside (or dropped if none within 15 m). Bus stops never move. Buildings are only reported."""
    from shapely.geometry import Point
    from shapely.prepared import prep
    zp = prep(zones_union)
    hp = prep(hard_union)
    from shapely.geometry import Polygon as _P
    from shapely.ops import unary_union as _u
    roads = prep(_u([_P(g["rings"][0], g["rings"][1:]).buffer(0) for g in world["ground"]
                     if g["kind"] == "road" and g["rings"]]))   # a moved prop never lands on a carriageway
    toe = ballast_toe(spacing)
    bx = zones_union.buffer(45.0).bounds
    near = lambda x, y: bx[0] < x < bx[2] and bx[1] < y < bx[3]
    trees = []
    for t in world["trees"]:
        if not near(t["x"], t["y"]):
            continue
        s, u = A.project(np.array([[t["x"], t["y"]]]))[0]
        on_line = 0 < s < A.length and abs(u) <= 40
        reason = ""
        if zp.contains(Point(t["x"], t["y"])):
            reason = "on the reshaped ground"
        elif on_line and abs(u) < toe + CLEAR_STRIP:
            reason = "in the cleared strip"
        elif on_line and abs(u) - float(t["r"]) < spacing / 2 + CROWN_GAP:
            reason = "crown over the tracks"
        elif yard_lines is not None and yard_lines.distance(Point(t["x"], t["y"])) - float(t["r"]) < CROWN_GAP:
            reason = "crown over a yard track"
        if reason:
            trees.append({"id": t["id"], "s": round(float(s), 1), "u": round(float(u), 1), "reason": reason})
    props, moved = [], []
    for p in world["props"]:
        if not near(p["x"], p["y"]):
            continue
        q = np.array([[p["x"], p["y"]]])
        s, u = A.project(q)[0]
        if not hp.contains(Point(p["x"], p["y"])):
            continue
        on_line = 0 < s < A.length and abs(u) <= 30
        model = p["model"]
        if model in ("bus_pole", "bus_shelter"):
            props.append({"id": p["id"], "osm": p.get("osm", ""), "model": model, "action": "kept", "reason": "bus stop"})
            continue
        if model in FURNITURE_DUPLICATES and on_line and any(pf["s0"] - 5 <= s <= pf["s1"] + 5 for pf in platforms):
            props.append({"id": p["id"], "osm": p.get("osm", ""), "model": model, "action": "dropped",
                          "reason": "the platform has its own (%s)" % model})
            continue
        # nearest free spot outwards (and along) off the railway's ground
        best = None
        for du in np.arange(0.5, 15.01, 0.5):
            for ds in (0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0):
                if on_line:
                    c = A.point(s + ds, u + math.copysign(du, u if u else 1.0))
                else:                           # in the yard: round the prop, outwards ring by ring
                    a = math.radians(ds * 45.0 + 22.5 * (du * 2 % 2))
                    c = np.array([p["x"] + du * math.cos(a), p["y"] + du * math.sin(a)])
                if hp.contains(Point(c[0], c[1]).buffer(0.4)) or hp.intersects(Point(c[0], c[1]).buffer(0.4)) \
                        or roads.intersects(Point(c[0], c[1]).buffer(0.3)):
                    continue
                if any(math.hypot(o["x"] - c[0], o["y"] - c[1]) < 1.0 for o in world["props"] if o is not p
                       and abs(o["x"] - c[0]) < 2 and abs(o["y"] - c[1]) < 2):
                    continue
                best = c
                break
            if best is not None:
                break
        if best is None:
            props.append({"id": p["id"], "osm": p.get("osm", ""), "model": model, "action": "dropped",
                          "reason": "no free spot within 15 m"})
        else:
            moved.append({"id": p["id"], "model": model, "to": [round(float(best[0]), 3), round(float(best[1]), 3)],
                          "reason": "on the railway's ground"})
            props.append({"id": p["id"], "model": model, "action": "moved",
                          "to": [round(float(best[0]), 3), round(float(best[1]), 3)], "reason": "on the railway's ground"})
    buildings = []
    for b in world["buildings"]:
        ring = np.array(b["rings"][0])
        if ring[:, 0].max() < bx[0] or ring[:, 0].min() > bx[2] or ring[:, 1].max() < bx[1] or ring[:, 1].min() > bx[3]:
            continue
        su = A.project(ring)
        if not np.any((su[:, 0] > 0) & (su[:, 0] < A.length)):
            continue
        dmin = float(np.min(np.abs(np.abs(su[:, 1]) - spacing / 2)))
        inside_tracks = bool(np.any(np.abs(su[:, 1]) < spacing / 2 + 1.7))
        if dmin < 6.0 or inside_tracks:
            buildings.append({"id": b["id"], "name": b.get("name") or "", "kind": b.get("kind", ""),
                              "walls": b.get("walls", True), "nearest_track": round(dmin, 2),
                              "in_gauge": inside_tracks})
    return {"trees": trees, "props": props, "buildings": buildings}


# ---------------------------------------------------------------- right-of-way fences

FENCE_HEIGHT = 2.0              # RATP-style welded mesh along the right of way; assumed (photos: green mesh panels)
RAILING_HEIGHT = 1.1            # platform back railings; assumed (photos: white bar railings)


def fences(ew: dict, A: rg.Alignment, world: dict, platforms: list, structures: dict, furniture_items: list) -> list:
    """Fences along the right of way, by rule, on both sides inside the map: beyond the slope (0.6 m past where it
    meets the ground), on top of a cutting wall, at the edge of the formation above an embankment wall, and railings
    along the platforms' backs; not where an OSM fence or wall already runs within 2.5 m alongside, and open at the
    stairs, stairwells, the road trench and the station's gates."""
    from shapely.geometry import LineString, Point
    from shapely.ops import unary_union
    existing = unary_union([LineString(f["pts"]).buffer(2.5) for f in world["fences"] if len(f["pts"]) > 1])
    gaps = []
    for fb in structures["footbridges"]:
        for f in fb["flights"]:
            gaps.append(LineString(np.asarray(f["pts"])).buffer(f["width"] / 2 + 0.8))
    for up in structures["underpasses"]:
        for f in up["stairwells"] + up["stairs_up"]:
            gaps.append(LineString(np.asarray(f["pts"])).buffer(f["width"] / 2 + 0.8))
    rt = structures["road_tunnel"]
    if rt:
        gaps.append(LineString(rt["pts"]).buffer(rt["width"] / 2 + 1.0))
    for it in furniture_items:
        if it["kind"] == "gates":
            gaps.append(Point(it["x"], it["y"]).buffer(3.5))
    gap = unary_union(gaps) if gaps else None
    s0, step = ew["s0"], ew["step"]
    n = len(ew["formation"])
    out = []
    for side, sg in (("left", 1.0), ("right", -1.0)):
        sd = ew[side]
        u = np.zeros(n)
        style = [""] * n
        for j in range(n):
            k = int(sd["kind"][j])
            if k == 0:
                u[j], style[j] = sd["reach"][j] + 0.6, "mesh"
            elif k == 1:
                cutting = sd["top"][j] > sd["level"][j]
                u[j], style[j] = (sd["edge"][j] + 0.3, "mesh") if cutting else (sd["edge"][j] - 0.25, "mesh")
            else:
                u[j], style[j] = sd["reach"][j] - 0.15, "bars"
        ss = s0 + np.arange(n) * step
        pts = A.point(ss, sg * u)
        keep = np.array([not existing.contains(Point(q)) and not (gap is not None and gap.contains(Point(q)))
                         for q in pts])
        # runs of one style, kept, at least 4 m long
        j = 0
        while j < n:
            if not keep[j]:
                j += 1
                continue
            k = j
            while k < n and keep[k] and style[k] == style[j]:
                k += 1
            if k - j >= 4:
                line = pts[j:k]
                # thin the points: one every 5 m on straight stretches is enough for panels
                idx = sorted(set(list(range(0, len(line), 5)) + [len(line) - 1]))
                out.append({"style": style[j], "h": FENCE_HEIGHT if style[j] == "mesh" else RAILING_HEIGHT,
                            "side": side, "s0": float(ss[j]), "s1": float(ss[k - 1]), "pts": line[idx]})
            j = k
    return out


# ---------------------------------------------------------------- station furniture

LAMP_SPACING = 20.0             # m along a platform; assumed (photos: double-head lamp posts at the back)
BOARD_SPACING = 50.0            # "Lozère" name boards; assumed
BENCH_SPACING = 40.0            # bench groups (three seats); assumed
SHELTER_LENGTH = 6.0            # assumed
SHELTER_DEPTH = 2.0


def furniture(platforms: list, A: rg.Alignment, world: dict, osm: dict, structures: dict, supports: list) -> dict:
    """The station's furniture, by rule from the OSM platform tags (shelter, bench, bin, lit, tactile_paving) and
    entrances: lamps, name boards, benches, bins, shelters (a canopy along a station building backing the platform,
    else two shelters), departure screens, track number boards, Navigo gates at the entrances."""
    from shapely.geometry import Polygon
    items = []
    stair_s = []
    for fb in structures["footbridges"]:
        for f in fb["flights"]:
            su = A.project(f["pts"])
            stair_s.append((float(su[:, 0].min()) - 1.5, float(su[:, 0].max()) + 1.5, float(np.sign(su[0, 1]))))
    for up in structures["underpasses"]:
        for f in up["stairs_up"]:
            su = A.project(f["pts"])
            stair_s.append((float(su[:, 0].min()) - 1.5, float(su[:, 0].max()) + 1.5, float(np.sign(su[-1, 1]))))
    mast_s = [(sp["s"], m[3]) for sp in supports for m in sp["masts"]]

    def free(s, side, pad=1.5):
        if any(a <= s <= b and sg == side for a, b, sg in stair_s):
            return False
        return not any(abs(ms - s) < pad and np.sign(mu) == side for ms, mu in mast_s)

    def place(kind, pf, s, du, extra=None):
        u = pf["side"] * (pf["back"](s) - du)
        q = A.point(s, u)
        yaw = float(A.theta(s)) + (-math.pi / 2 if pf["side"] > 0 else math.pi / 2)     # facing the track
        it = {"kind": kind, "platform": pf["id"], "s": round(s, 2), "u": round(float(u), 3),
              "x": round(float(q[0]), 3), "y": round(float(q[1]), 3), "z": round(pf["top"](s), 3),
              "yaw": round(math.degrees(yaw), 1)}
        if extra:
            it.update(extra)
        items.append(it)

    station_buildings = []
    for b in world["buildings"]:
        if b.get("kind") in ("train_station", "transportation") and b.get("walls", True):
            station_buildings.append(Polygon(b["rings"][0]))
    for pf in platforms:
        L = pf["s1"] - pf["s0"]
        tg = pf["tags"]
        if tg.get("lit") == "yes":
            s = pf["s0"] + 4.0
            while s < pf["s1"] - 2.0:
                ss = s
                while not free(ss, pf["side"]) and ss < s + 6:
                    ss += 1.0
                place("lamp", pf, ss, 0.5)
                s += LAMP_SPACING
        for k in range(int(L // BOARD_SPACING) + 1):
            s = pf["s0"] + 12.0 + k * BOARD_SPACING
            if s < pf["s1"] - 5 and free(s, pf["side"]):
                place("name_board", pf, s, 0.9, {"text": pf["name"],
                                                 "subtitle": "École Polytechnique" if pf["name"] == "Lozère" else ""})
        # a canopy along a station building at the platform's back, else two shelters
        canopy = None
        for bpoly in station_buildings:
            su = A.project(np.array(bpoly.exterior.coords))
            on_side = np.sign(np.median(su[:, 1])) == pf["side"]
            touches = np.min(np.abs(np.abs(su[:, 1]) - np.array([pf["back"](s) for s in su[:, 0]]))) < 3.0
            if on_side and touches and su[:, 0].max() > pf["s0"] and su[:, 0].min() < pf["s1"]:
                canopy = (max(float(su[:, 0].min()), pf["s0"]), min(float(su[:, 0].max()), pf["s1"]))
        shelters = []
        if tg.get("shelter") == "yes":
            if canopy:
                shelters.append(("canopy", canopy[0], canopy[1]))
            else:
                for f in (0.35, 0.65):
                    c = pf["s0"] + f * L
                    while not free(c, pf["side"], 3.5) and c < pf["s1"] - 10:
                        c += 2.0
                    shelters.append(("shelter", c - SHELTER_LENGTH / 2, c + SHELTER_LENGTH / 2))
        for kind, a, b in shelters:
            place(kind, pf, (a + b) / 2, 0.0, {"length": round(b - a, 2), "depth": SHELTER_DEPTH if kind == "shelter"
                                                   else 3.0})
        if tg.get("bench") == "yes":
            for kind, a, b in shelters:
                place("bench", pf, (a + b) / 2, 1.0, {"seats": 3})
            s = pf["s0"] + 25.0
            while s < pf["s1"] - 10:
                if free(s, pf["side"]) and not any(a - 3 <= s <= b + 3 for _, a, b in shelters):
                    place("bench", pf, s, 1.0, {"seats": 3})
                s += BENCH_SPACING
        if tg.get("bin") == "yes":
            s = pf["s0"] + 35.0
            while s < pf["s1"] - 5:
                if free(s, pf["side"], 1.0):
                    place("bin", pf, s, 0.6)
                s += BENCH_SPACING
        for f in (0.3, 0.7):
            s = pf["s0"] + f * L
            while not free(s, pf["side"]) and s < pf["s1"] - 5:
                s += 1.0
            place("departure_screen", pf, s, 1.6)
        for f in (0.04, 0.5, 0.96):
            s = pf["s0"] + f * L
            place("track_board", pf, s, 0.35, {"text": pf["track"]})
    # Navigo gates at the entrances (three gates across the way in, facing the platform)
    for n in osm["nodes"].values():
        t = n.get("tags", {})
        if t.get("railway") != "train_station_entrance":
            continue
        p = np.array(fwd(n["lat"], n["lon"]))
        s, u = A.project(p[None, :])[0]
        pf = [x for x in platforms if np.sign(u) == x["side"] and x["s0"] - 30 <= s <= x["s1"] + 30]
        if not pf or abs(u) > 20:
            continue
        pf = pf[0]
        sc = min(max(s, pf["s0"]), pf["s1"])
        target = A.point(sc, pf["side"] * (pf["back"](sc) - 1.0))
        d = target - p
        yaw = math.atan2(d[1], d[0])
        items.append({"kind": "gates", "platform": pf["id"], "name": t.get("name", ""), "ref": t.get("ref", ""),
                      "osm": "n%d" % n["id"], "x": round(float(p[0]), 3), "y": round(float(p[1]), 3),
                      "s": round(float(s), 2), "u": round(float(u), 3), "yaw": round(math.degrees(yaw), 1),
                      "count": 3})
    return {"items": items}


# ---------------------------------------------------------------- zones (what the patch reshapes)

def _portal(a: np.ndarray, b: np.ndarray, half: float, z_open: float) -> dict:
    """The segment across the end b of a trench or stairwell running a -> b (`half` either side), and the height of
    the opening's top there: the patch's ground wall along it starts at z_open, not at the bottom."""
    d = (np.asarray(b) - np.asarray(a))
    d = d / max(np.linalg.norm(d), 1e-9)
    n = np.array([-d[1], d[0]])
    return {"a": np.asarray(b) + n * half, "b": np.asarray(b) - n * half, "z_open": z_open}


def zones(ew: dict, A: rg.Alignment, platforms: list, structures: dict, design: rg.Design, sources: dict) -> tuple:
    """The ground the railway reshapes, as non-overlapping polygons with what they are: the trackbed (formation),
    platforms, slopes, wall landings, the platforms' blends, stairwells and the road's open trench. Stairwells and the
    trench carry their own heights (an axis); the others follow the earthworks. Returns (zones, union)."""
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    s0, step = ew["s0"], ew["step"]
    n = len(ew["formation"])
    ss = s0 + np.arange(n) * step
    raw = []

    def band(side, a, b, inner, outer):
        """The side's band from metre a to b - 1, held on half a metre further at each end: where the section changes
        kind the next band starts there (Design.side_values switches at the midpoint too), so no ground is left out."""
        sg = 1.0 if side == "left" else -1.0
        s_ = ss[a:b]
        i_ = inner[a:b]
        o_ = outer[a:b]
        if a > 0:
            s_, i_, o_ = np.r_[s_[0] - step / 2, s_], np.r_[i_[0], i_], np.r_[o_[0], o_]
        if b < n:
            s_, i_, o_ = np.r_[s_, s_[-1] + step / 2], np.r_[i_, i_[-1]], np.r_[o_, o_[-1]]
        p_in = A.point(s_, sg * i_)
        p_out = A.point(s_[::-1], sg * o_[::-1])
        pg = Polygon(np.concatenate([p_in, p_out])).buffer(0)
        return pg

    def edge_line(side):
        """The formation edge of a side, s and u: linear between the metres, a step halfway where the kind changes."""
        sd = ew[side]
        kind = np.asarray(sd["kind"])
        edge = np.asarray(sd["edge"], dtype=float)
        s_out, u_out = [ss[0]], [edge[0]]
        for j in range(1, n):
            if kind[j] != kind[j - 1]:
                s_out += [ss[j] - step / 2, ss[j] - step / 2]
                u_out += [edge[j - 1], edge[j]]
            s_out.append(ss[j])
            u_out.append(edge[j])
        return np.asarray(s_out), np.asarray(u_out)

    ls, le = edge_line("left")
    rs, re_ = edge_line("right")
    track = Polygon(np.concatenate([A.point(ls, le), A.point(rs[::-1], -re_[::-1])])).buffer(0)
    raw.append(("trackbed", None, track, None, sources["track"]))
    for side in ("left", "right"):
        sd = ew[side]
        kind = np.asarray(sd["kind"])
        for k_, name in ((0, "slope"), (1, "landing"), (2, "platform")):
            for a, b in _runs(kind == k_):
                edge = np.asarray(sd["edge"], dtype=float)
                reach = np.asarray(sd["reach"], dtype=float)
                outer = np.maximum(reach, edge + 0.05)
                src = ""
                if k_ == 2:             # the platform of that side over this run (one per station)
                    sg = 1.0 if side == "left" else -1.0
                    src = next((ps for psg, a0, a1, ps in sources["platform"]
                                if psg == sg and a0 <= ss[min(b - 1, n - 1)] and a1 >= ss[a]), "")
                raw.append((name, side, band(side, a, b, edge, outer), None, src))
                if k_ == 2:
                    raw.append(("platform_blend", side, band(side, a, b, reach, reach + rg.Design.BLEND_RUN), None,
                                ""))
    prio = {"stairwell": 0, "road_trench": 0, "platform": 1, "trackbed": 2, "platform_blend": 3, "landing": 4,
            "slope": 5}
    for up in structures["underpasses"]:
        for f in up["stairwells"]:
            from shapely.geometry import LineString
            p = np.asarray(f["pts"])
            d = rg.cumlen(p)
            az = f["top"] + (f["bottom"] - f["top"]) * d / max(d[-1], 1e-6)
            if len(f["landing"]):
                lp = np.asarray(f["landing"])[1:]
                p = np.concatenate([p, lp])
                az = np.concatenate([az, np.full(len(lp), f["bottom"])])
            pg = LineString(p).buffer(f["width"] / 2 + 0.25, cap_style=2)
            # the stairwell's low end opens into the covered passage: the ground's wall there starts above it
            portal = _portal(p[-2], p[-1], f["width"] / 2 + 0.25, f["bottom"] + up["headroom"])
            raw.append(("stairwell", None, pg, {"axis": p, "axis_z": az, "portals": [portal]}, "osm:" + f["osm"]))
        for f in up["stairs_up"]:
            # stairs from the passage up through the platform's end: an opening in the platform
            from shapely.geometry import LineString
            p = np.asarray(f["pts"])
            d = rg.cumlen(p)
            az = f["bottom"] + (f["top"] - f["bottom"]) * d / max(d[-1], 1e-6)
            pg = LineString(p).buffer(f["width"] / 2 + 0.25, cap_style=2)
            portal = _portal(p[1], p[0], f["width"] / 2 + 0.25, f["bottom"] + up["headroom"])
            raw.append(("stairwell", None, pg, {"axis": p, "axis_z": az, "portals": [portal]}, "osm:" + f["osm"]))
    rt = structures["road_tunnel"]
    if rt:
        from shapely.geometry import LineString
        t = rt["t"]
        a, b = rt["covered"]
        for lo, hi in ((0.0, a), (b, float(t[-1]))):
            m = (t >= lo - 0.5) & (t <= hi + 0.5)
            if m.sum() >= 2:
                pts = rt["pts"][m]
                pg = LineString(pts).buffer(rt["width"] / 2 + 0.3, cap_style=2)
                # the end towards the covered part is a tunnel portal: the ground's wall there starts above it
                if lo == 0.0:
                    portal = _portal(pts[-2], pts[-1], rt["width"] / 2 + 0.3, float(rt["z"][m][-1]) + rt["headroom"])
                else:
                    portal = _portal(pts[1], pts[0], rt["width"] / 2 + 0.3, float(rt["z"][m][0]) + rt["headroom"])
                raw.append(("road_trench", None, pg, {"axis": pts, "axis_z": rt["z"][m], "portals": [portal]},
                            "osm:" + rt["osm"][0]))
    raw.sort(key=lambda r: prio[r[0]])
    out = []
    taken = None
    import shapely
    for kind, side, pg, axis, src in raw:
        # on a 1 mm grid: the zones' shared outlines come out identical, no hair-thin slivers between them
        pg = shapely.set_precision(pg, 0.001)
        g = pg if taken is None else shapely.set_precision(pg.difference(taken), 0.001)
        if g.is_empty or g.area < 0.05:
            continue
        taken = pg if taken is None else unary_union([taken, pg])
        polys = [x for x in getattr(g, "geoms", [g]) if x.geom_type == "Polygon" and x.area > 0.05]
        if not polys:
            continue
        z = {"kind": kind, "side": side, "source": src,
             "polygons": [[np.asarray(p.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in p.interiors]
                          for p in polys]}
        if axis is not None:
            z["axis"] = axis["axis"]
            z["axis_z"] = axis["axis_z"]
            z["portals"] = axis.get("portals", [])
        out.append(z)
    return out, taken


# ---------------------------------------------------------------- output

def r3(a):
    """Lists of floats rounded to the millimetre, for rail.json."""
    if isinstance(a, np.ndarray):
        a = a.tolist()
    if isinstance(a, (list, tuple)):
        return [r3(x) for x in a]
    if isinstance(a, (float, np.floating)):
        return round(float(a), 3)
    if isinstance(a, np.integer):
        return int(a)
    if isinstance(a, np.bool_):
        return bool(a)
    if isinstance(a, dict):
        return {k: r3(v) for k, v in a.items() if not callable(v)}
    return a


def landing_spots(world: dict, route: np.ndarray, track_lines, rail_ground) -> dict:
    """Where a player riding a train off the map is put back (the user's rule): beside the line just inside the
    walkable area at each end (the eastbound route's first and last points 12 m inside it), off the railway's ground
    and out of buildings, on a sidewalk, path or road within 40 m if there is one, else on open ground (grass, dirt);
    never between the right-of-way fences (12 m from every track)."""
    import shapely
    from shapely.geometry import Point, Polygon, box
    from shapely.prepared import prep
    from shapely.strtree import STRtree
    rings = world["meta"].get("playable_area")
    play = Polygon(rings[0], rings[1:]) if rings else box(*world["meta"]["playable"])
    deep = play.buffer(-3.0)
    edge_in = shapely.contains_xy(play.buffer(-12.0), route[:, 0], route[:, 1])
    idx = np.nonzero(edge_in)[0]
    rp = prep(rail_ground)
    out = {}
    for end, k in (("west", int(idx[0])), ("east", int(idx[-1]))):
        c = route[k]
        polys, info = [], []
        for g in world["ground"]:
            ring = np.asarray(g["rings"][0])
            if np.min(np.hypot(ring[:, 0] - c[0], ring[:, 1] - c[1])) > 80:
                continue
            polys.append(Polygon(g["rings"][0], g["rings"][1:]).buffer(0))
            info.append((g["kind"], g["material"]))
        tree = STRtree(polys)
        best = None
        for dx in np.arange(-40.0, 40.01, 1.0):
            for dy in np.arange(-40.0, 40.01, 1.0):
                q = (float(c[0] + dx), float(c[1] + dy))
                pt = Point(q)
                if not deep.contains(pt) or rp.intersects(pt.buffer(1.5)):
                    continue
                if track_lines.distance(pt) < 12.0:
                    continue                    # outside the right-of-way fences, never between them
                hit = [i for i in tree.query(pt) if polys[i].contains(pt)]
                if not hit:
                    continue
                kind, mat = info[hit[0]]
                if kind in ("building", "water"):
                    continue
                paved = kind in ("sidewalk", "footway", "path", "pedestrian", "road", "parking", "cycleway")
                if not paved and mat not in ("grass", "tall_grass", "dirt", "gravel", "sand", "concrete", "asphalt"):
                    continue
                score = math.hypot(dx, dy) + (0.0 if paved else 20.0)
                if best is None or score < best[0]:
                    best = (score, q, kind, mat)
        if best:
            out[end] = {"x": round(best[1][0], 3), "y": round(best[1][1], 3), "ground": "%s %s" % best[2:],
                        "route": k}
    return out


def resample_route(parts: list) -> dict:
    """Route pieces (dicts of per-point arrays pts, z, heading, roll, limit, s_centre) joined and resampled every metre
    (the alignment's route and the yard track meet less than a metre apart)."""
    keys = ("z", "heading", "roll", "limit", "s_centre")
    pts = np.concatenate([p["pts"] for p in parts])
    vals = {k: np.concatenate([np.asarray(p[k], dtype=np.float64) for p in parts]) for k in keys}
    vals["heading"] = np.unwrap(vals["heading"])
    d = rg.cumlen(pts)
    keep = np.r_[True, np.diff(d) > 1e-6]
    pts, d = pts[keep], d[keep]
    vals = {k: v[keep] for k, v in vals.items()}
    st = np.arange(0.0, d[-1], 1.0)
    out = {"pts": np.c_[np.interp(st, d, pts[:, 0]), np.interp(st, d, pts[:, 1])]}
    for k, v in vals.items():
        out[k] = np.interp(st, d, v)
    return out


def yard_piece(tr: dict, s_start: float, reverse: bool) -> dict:
    """A yard track as a route piece (in its trains' direction): s_centre goes on from the alignment's end."""
    pts, z, th = np.asarray(tr["pts"]), np.asarray(tr["z"]), np.asarray(tr["heading"])
    lim = np.asarray(tr.get("maxspeed", np.full(len(pts), LINE_SPEED)), dtype=np.float64)
    sc = s_start + rg.cumlen(pts)
    if reverse:
        pts, z, th, lim, sc = pts[::-1], z[::-1], th[::-1] + math.pi, lim[::-1], sc[::-1]
    return {"pts": pts, "z": z, "heading": th, "roll": np.zeros(len(pts)), "limit": lim, "s_centre": sc}


def build_services(osm: dict, al: dict, A: rg.Alignment, cant: np.ndarray, spacing: float, limits: np.ndarray,
                   platforms: list, Y: dict, sigs: list, world: dict) -> list:
    """Per direction: its track's route on the alignment and on through the yard (track 2 eastbound, out past the
    map's north-east end; track 1 westbound, in from there), the stops at every station (the front on OSM's stop
    position; 4-car trains centred on the platform), the signals facing it, the block sections, where it enters and
    leaves the map, its departure phase (both directions meet at Lozère, as before)."""
    import shapely
    from scipy.spatial import cKDTree
    stops = stop_nodes(osm)
    for nd in osm["nodes"].values():                 # Le Guichet (west, the westbound trains' terminus)
        t = nd.get("tags", {})
        if t.get("railway") == "stop" and t.get("name") == "Le Guichet" and t.get("ref") in ("1", "2"):
            stops[("Le Guichet", t["ref"])] = np.array(fwd(nd["lat"], nd["lon"]))
    mains = {t["ref"]: t for t in Y["tracks"] if t["main"]}
    L8 = TRAIN_LENGTHS["8"]
    services = []
    for track, sid, direction in (("2", "B-east", "eastbound"), ("1", "B-west", "westbound")):
        r = track_route(al, A, cant, track, spacing, limits)
        piece = {"pts": r["pts"], "z": r["z"], "heading": r["heading"], "roll": r["roll"], "limit": r["limit"],
                 "s_centre": r["s_centre"]}
        yp = yard_piece(mains[track], A.length, reverse=direction == "westbound")
        R = resample_route([piece, yp] if direction == "eastbound" else [yp, piece])
        pts = R["pts"]
        kd = cKDTree(pts)
        sc = R["s_centre"]
        idx = np.arange(len(sc), dtype=np.float64)
        order = np.argsort(sc)
        to_route = lambda s, sc=sc, idx=idx, order=order: float(np.interp(s, sc[order], idx[order]))
        route = {"limit": R["limit"]}

        def at(p):                                   # route index nearest a map point
            return float(kd.query(np.asarray(p, dtype=np.float64))[1])

        stop_list = []
        for name in STATIONS:
            key = (name, track)
            if key not in stops:
                continue
            k8 = at(stops[key])
            if np.linalg.norm(pts[int(k8)] - stops[key]) > 30.0:
                continue
            # the platform beside this track there: one of the alignment's, or a yard island
            pf_id, c4, side = None, None, "left"
            for pf in platforms:
                if slug(pf["name"]) == slug(name) and pf["track"] == track:
                    pf_id = pf["id"]
                    c4 = 0.5 * (to_route(pf["s0"]) + to_route(pf["s1"]))
                    break
            if pf_id is None:
                for isl in Y["islands"]:
                    if slug(isl["name"]) == slug(name) and mains[track]["id"] in isl["tracks"]:
                        pf_id = isl["id"]
                        e = np.asarray(next(e["pts"] for e in isl["edges"] if e["track"] == mains[track]["id"]))
                        ks = sorted([at(e[0]), at(e[-1])])
                        c4 = 0.5 * (ks[0] + ks[1])
                        mid = e[len(e) // 2]
                        k = int(at(mid))
                        hd = np.array([math.cos(R["heading"][k]), math.sin(R["heading"][k])])
                        rel = mid - pts[k]
                        side = "left" if hd[0] * rel[1] - hd[1] * rel[0] > 0 else "right"
                        break
            if pf_id is None:
                continue
            stop_list.append({"name": name, "s": {"8": round(k8, 2), "4": round(c4 + TRAIN_LENGTHS["4"] / 2, 2)},
                              "side": side, "platform": pf_id, "dwell": DWELL})
        guichet = stops.get(("Le Guichet", track))
        guichet_s = at(guichet) if guichet is not None else None
        ins = shapely.contains_xy(DATA_AREA, pts[:, 0], pts[:, 1])     # on the map's ground (as the box was)
        in_idx = np.nonzero(ins)[0]
        r_in, r_out = int(in_idx[0]), int(in_idx[-1])
        if direction == "eastbound":
            start, start_speed = guichet_s, 0.0
            end = min(r_out + 15.0 + L8 + 5.0, len(pts) - 3.0)
            v = planned_speed(route, L8)
        else:
            start = max(r_in - 15.0, 0.0)
            end = guichet_s
            v = planned_speed(route, L8, end_stop=end)
            start_speed = float(v[int(start)])
            stop_list.append({"name": "Le Guichet", "s": {"8": round(guichet_s, 2)}, "side": "left", "terminus": True})
        stop_list.sort(key=lambda x: x["s"]["8"])
        # time from the start to the stop at Lozère, stopping on the way (the phase: both directions meet there)
        t_loz, cur, cur_v = 0.0, start, start_speed
        for st in stop_list:
            if st["s"]["8"] < cur:
                continue
            t_loz += run_time(v, cur, st["s"]["8"], cur_v)
            if st["name"] == "Lozère":
                break
            t_loz += st.get("dwell", DWELL)
            cur, cur_v = st["s"]["8"], 0.0
        n_route = int(math.ceil(end)) + 2
        facing = 1 if direction == "eastbound" else -1
        rsig = []
        for sg in sigs:
            if sg["facing"] == facing:
                rsig.append({"id": sg["id"], "ref": sg["ref"], "kind": sg["kind"], "s": round(to_route(sg["s"]), 2),
                             "normal": sg["normal"], "track": sg["track"]})
        rsig.sort(key=lambda x: x["s"])
        blocks = [x["s"] for x in rsig if x["normal"] and x["kind"] in ("FR:S", "FR:CARRE")]
        services.append({"id": sid, "track": track, "direction": direction, "step": 1.0,
                         "pts": np.c_[pts[:n_route], R["z"][:n_route]], "heading": R["heading"][:n_route],
                         "roll": R["roll"][:n_route], "v": v[:n_route], "s_centre": sc[:n_route],
                         "length": n_route - 1.0, "start": round(start, 2), "start_speed": round(start_speed, 2),
                         "end": round(end, 2), "enter": float(r_in), "exit": float(r_out) + L8,
                         "stops": stop_list, "origin": "Le Guichet" if direction == "eastbound" else None,
                         "signals": rsig, "blocks": blocks, "headway": HEADWAY, "run_to_lozere": round(t_loz, 1)})
    te = services[0]["run_to_lozere"]
    tw = services[1]["run_to_lozere"]
    services[0]["phase"] = 0.0
    services[1]["phase"] = round(((te + 20.0 - tw) % HEADWAY) / HEADWAY, 4)
    log("services: eastbound reaches Lozère %.0f s after leaving Le Guichet, westbound %.0f s after entering; "
        "westbound phase %.2f of the %d s headway (they meet in the station)" % (te, tw, services[1]["phase"], HEADWAY))
    for sv in services:
        log("  %s: %.0f m, stops %s" % (sv["id"], sv["length"], ", ".join("%s %s at %.0f (%s)" % (
            st["name"], st.get("platform", ""), st["s"]["8"], st["side"]) for st in sv["stops"])))
    return services


def drawn_range(pts) -> list:
    """[first, last] point index of a yard track on the map's ground (its longest run there): the builder draws that
    much (the main tracks run on past the data for the hidden trains)."""
    ins = inside(np.asarray(pts)[:, 0], np.asarray(pts)[:, 1])
    best, i = (0, -1), 0
    while i < len(ins):
        if ins[i]:
            j = i
            while j < len(ins) and ins[j]:
                j += 1
            if j - 1 - i > best[1] - best[0]:
                best = (i, j - 1)
            i = j
        else:
            i += 1
    return [int(best[0]), int(best[1])]


def island_furniture(Y: dict) -> list:
    """Furniture on the yard's islands, by rule as on the side platforms (lamps every LAMP_SPACING, name boards every
    BOARD_SPACING, a bench and a bin between): along each island's spine, facing its first track."""
    items = []
    for isl in Y["islands"]:
        spine = np.asarray(isl["spine"])
        d = rg.cumlen(spine)
        e = np.asarray(isl["edges"][0]["pts"])
        L = float(d[-1])

        def at(s):
            p = np.array([np.interp(s, d, spine[:, 0]), np.interp(s, d, spine[:, 1])])
            k = int(np.clip(np.searchsorted(d, s), 1, len(spine) - 1))
            t = spine[k] - spine[k - 1]
            q = e[min(k, len(e) - 1)]
            yaw = math.atan2(q[1] - p[1], q[0] - p[0])        # facing the first track's edge
            return p, math.degrees(yaw), t
        for kind, step, off, extra in (("lamp", LAMP_SPACING, 4.0, {}),
                                       ("name_board", BOARD_SPACING, 12.0, {"text": isl["name"], "subtitle": ""}),
                                       ("bench", BENCH_SPACING, 25.0, {"seats": 3}),
                                       ("bin", BENCH_SPACING, 35.0, {})):
            s = off
            while s < L - 4.0:
                p, yaw, _t = at(s)
                items.append({"kind": kind, "platform": isl["id"], "s": round(s, 2), "u": 0.0,
                              "x": round(float(p[0]), 3), "y": round(float(p[1]), 3), "z": round(isl["top"], 3),
                              "yaw": round(yaw, 1), **extra})
                s += step
        for f in (0.3, 0.7):
            p, yaw, _t = at(f * L)
            items.append({"kind": "departure_screen", "platform": isl["id"], "s": round(f * L, 2), "u": 0.0,
                          "x": round(float(p[0]), 3), "y": round(float(p[1]), 3), "z": round(isl["top"], 3),
                          "yaw": round(yaw, 1)})
    return items


def main() -> None:
    t_start = time.time()
    osm = load_osm()
    rg.ensure_base()
    world = rg.load_json(rg.BASE / "world.json")
    set_data_area(world)
    t1, ids1 = chain_track(osm, "1")
    t2, ids2 = chain_track(osm, "2")
    fa = fit_alignment(t1, t2)
    al = alignment_arrays(fa)
    spacing = al["spacing"]
    H = rg.Heights(rg.BASE, world["terrain"], world["ground_mesh"]["cell"])
    L = float(al["s"][-1])
    A0 = rg.Alignment({"step": 1.0, "pts": al["pts"], "heading": al["heading"], "z": np.zeros(len(al["s"])),
                       "length": L})
    sigs = osm_signals(osm, A0, {"1": ids1, "2": ids2}, spacing)
    # a TIV distant speed sign announces a limit over the next curve beyond it (in the direction it faces)
    signs = []
    for sg in sigs:
        if sg["kind"] == "FR:TIV-D" and sg["speed"]:
            ahead = [c for c in al["curves"] if (c[0] > sg["s"] if sg["facing"] > 0 else c[0] + sum(c[1:4]) < sg["s"])]
            if ahead:
                c = min(ahead, key=lambda c: abs((c[0] if sg["facing"] > 0 else c[0] + sum(c[1:4])) - sg["s"]))
                signs.append({"s0": c[0], "s1": c[0] + sum(c[1:4]), "kmh": float(sg["speed"]), "osm": sg["osm"]})
    curves = design_curves(al, signs)
    cant = cant_profile(al, curves)
    groups = osm_structures(osm, A0, H)
    avoid = [(g["s"] - 12.0, g["s"] + 12.0) for g in groups if g["kind"] != "footbridge"]
    samples = lidar_profile(al, H, avoid)
    prof = fit_profile(samples, L)
    ballast_top = profile_z(prof, al["s"])
    z_rail = ballast_top + RAIL_HEIGHT + PAD          # the LiDAR trackbed is the ballast / sleeper top
    err = samples[samples[:, 2] > 0, 1] - profile_z(prof, samples[samples[:, 2] > 0, 0])
    log("profile: %d grade changes, grades %s per mille, LiDAR deviation rms %.2f m max %.2f m (%d of %d samples)"
        % (len(prof["vertical"]), [round(g * 1000, 1) for g in prof["grades"]], math.sqrt(err @ err / len(err)),
           np.abs(err).max(), len(err), len(samples)))
    A = rg.Alignment({"step": 1.0, "pts": al["pts"], "heading": al["heading"], "z": z_rail, "length": L})
    A.spacing = spacing
    cant_at = lambda s: float(np.interp(s, al["s"], cant))
    platforms = osm_platforms(osm, A, spacing, cant_at)
    platforms += rule_platforms(osm, A, spacing, cant_at, platforms)
    caps = cess_caps(osm, A)
    groups = osm_structures(osm, A, H)
    from shapely.geometry import LineString
    from shapely.geometry import Polygon as _Pg
    from shapely.ops import unary_union
    in_map = inside(al["pts"][:, 0], al["pts"][:, 1])
    near = LineString(al["pts"][in_map]).buffer(SLOPE_REACH + 15.0)
    ignore = unary_union([LineString(p).buffer(1.5) for g in groups for p in g["geom"].values() if len(p) > 1])
    corridor = Corridor(world, near, ignore)
    cap_platform_backs(platforms, A, corridor)
    ew = earthworks(al, A, H, corridor, platforms, caps, spacing)
    k0 = int(round(ew["s0"]))
    n = len(ew["sides"]["left"]["edge"])
    ew_json = {"step": 1.0, "s0": ew["s0"], "crossfall": CROSSFALL,
               "formation": (z_rail[k0:k0 + n] + section_dims()["formation"]).tolist()}
    for side in ("left", "right"):
        sd = ew["sides"][side]
        ew_json[side] = {k: (v.tolist() if isinstance(v, np.ndarray) else v) for k, v in sd.items()}
    design = rg.Design(ew_json, A, H)
    structures = {"footbridges": [], "underpasses": [], "road_tunnel": None}
    for g in groups:
        if g["kind"] == "footbridge":
            structures["footbridges"].append(footbridge(g, A, lambda s, u, p: design.z_or_ground(s, u, p)))
        elif g["kind"] == "underpass":
            structures["underpasses"].append(underpass(g, A, lambda s, u, p: design.z_or_ground(s, u, p), platforms))
        else:
            structures["road_tunnel"] = road_tunnel(g, osm, A, lambda s, u, p: design.z_or_ground(s, u, p), H)
    longest = [max(ids, key=lambda i: _way_len(way_pts(osm["ways"][i]))) for ids in (ids1, ids2)]
    sources = {"track": "osm:w%d+w%d" % tuple(longest),
               "platform": [(p["side"], p["s0"], p["s1"], ("osm:" + p["osm"]) if p["osm"] else "rule:" + slug(p["name"]))
                            for p in platforms]}
    zs, zunion = zones(ew_json, A, platforms, structures, design, sources)
    spans = rail_bridges(osm, A, ids1 + ids2)
    zs = cut_spans(zs, A, spans)
    zunion = unary_union([_Pg(pg[0], pg[1:]) for z in zs for pg in z["polygons"]])
    log("rail bridges: %s" % ", ".join("s %.0f-%.0f (%s)" % (b["s0"], b["s1"], "+".join(b["osm"])) for b in spans))
    # the station yard beyond the alignment (Massy-Palaiseau): every track a line of its own, the islands
    import yard as yd
    Y = yd.build(osm, A, spacing, RAIL_HEIGHT + PAD, H, DATA_AREA, set(ids1) | set(ids2), A.length, PLATFORM_EDGE,
                 PLATFORM_HEIGHT)
    yz = yd.zones(Y, zunion, DATA_AREA)
    zs += yz
    zunion = unary_union([zunion] + [_Pg(pg[0], pg[1:]) for z in yz for pg in z["polygons"]])
    log("yard: %d tracks (%d of the RER B), %d islands (%s)" % (len(Y["tracks"]), sum(t["rer"] for t in Y["tracks"]),
                                                             len(Y["islands"]), ", ".join(i["id"] for i in Y["islands"])))
    # props on the islands ride up with them; elsewhere on the railway's hard ground they move off it
    hard = unary_union([_Pg(pg[0], pg[1:]) for z in zs if z["kind"] in ("trackbed", "platform", "stairwell",
                                                                         "road_trench", "yard") for pg in z["polygons"]])
    soft = unary_union([_Pg(pg[0], pg[1:]) for z in zs if z["kind"] != "platform_blend" for pg in z["polygons"]])
    for z in zs:
        if "axis" in z:
            design.add_zone(z)
    pk = pk_points(osm, A)
    # the map's bridge decks over the line, less the footbridges the line builds itself (Lozère's)
    own = {o for fb in structures["footbridges"] for o in fb["osm"]}
    decks = [d for d in bridge_decks(world, A) if next(b["osm"] for b in world["bridges"] if b["id"] == d[3]) not in own]
    cat = catenary(al, A, design, platforms, structures, spacing, pk, decks)
    furn = furniture(platforms, A, world, osm, structures, cat["supports"])
    furn["items"] += island_furniture(Y)
    yard_rer = unary_union([LineString(t["pts"]) for t in Y["tracks"] if t["rer"]])
    clear = clearance(world, A, design, soft, hard, spacing, platforms, yard_rer)
    row_fences = fences(ew_json, A, world, platforms, structures, furn["items"])
    fenced = unary_union([soft] + [LineString(f["pts"]).buffer(1.0) for f in row_fences])
    ss_all = np.arange(0.0, A.length, 2.0)
    track_lines = unary_union([LineString(A.point(ss_all, np.full(len(ss_all), u))) for u in (-spacing / 2, spacing / 2)]
                              + [LineString(t["pts"]) for t in Y["tracks"]])
    # services
    limits = speed_limits(al, curves)
    services = build_services(osm, al, A, cant, spacing, limits, platforms, Y, sigs, world)
    land = landing_spots(world, np.asarray(services[0]["pts"])[:, :2], track_lines, fenced)
    for st in structures["footbridges"]:
        log("footbridge %s at s %.0f: deck %.2f m (%.2f m over the rail; from the steps %s), flights %s"
            % (st["id"], st["s"], st["level"], st["clearance"], st["from_steps"],
               [(f["osm"], f["steps"], f["riser"]) for f in st["flights"]]))
    for st in structures["underpasses"]:
        log("underpass %s at s %.0f: floor %.2f m (from the steps %s), %d stairwells, %d stairs up to a platform"
            % (st["id"], st["s"], st["floor"], st["from_steps"], len(st["stairwells"]), len(st["stairs_up"])))
    rt = structures["road_tunnel"]
    if rt:
        log("road tunnel: %d m long, covered %s m along it, lowest %.2f m, steepest %.1f %%"
            % (rt["t"][-1], rt["covered"], rt["lowest"], rt["max_grade"]))
    log("platforms: %s" % ", ".join("%s %.0f-%.0f" % (p["id"], p["s0"], p["s1"]) for p in platforms))
    log("bridges over the line (the map's): %s" % ", ".join("%s at s %.0f, underside %.2f m over the rail"
                                                            % (d[3], d[0], d[2] - float(A.level(d[0]))) for d in decks))
    nw = {"left": 0, "right": 0}
    for w in ew["walls"]:
        nw[w["side"]] += w["s1"] - w["s0"] + 1
    log("earthworks: walls %s m, %d fences (%.0f m); clearance: %d trees, %d props (%s)"
        % (nw, len(row_fences), sum(_way_len(np.asarray(f["pts"])) for f in row_fences), len(clear["trees"]),
           len(clear["props"]),
           {a: sum(1 for p in clear["props"] if p["action"] == a) for a in ("dropped", "moved", "kept")}))
    box = world["meta"]["bounds"]
    rail = {
        "schema": RAIL_SCHEMA,
        "about": "RER B (Ligne de Sceaux) across the map: tools/rail/build_rail.py from OSM and the LiDAR ground; "
                 "map coordinates (x east, y north, z up, metres; Godot = (x, z, -y)); s along the centreline from "
                 "its west end, u across it (north positive). Schema: the docstring of build_rail.py.",
        "built_from": {"osm": "tools/rail/osm_rail.json + osm_rail_massy.json", "osm_timestamp": osm["timestamp"],
                       "lidar": "godot/world/base (heightmap)"},
        "box": box, "playable": world["meta"]["playable"],
        "playable_area": world["meta"].get("playable_area"),
        "fit": fa["stats"],
        "alignment": {"step": 1.0, "length": L, "spacing": spacing, "pts": al["pts"], "heading": al["heading"],
                      "z": z_rail, "cant": cant, "kappa": al["kappa"], "elements": al["elements"],
                      "curves": curves, "speed_signs": signs},
        "profile": {"pvis": prof["pvis"], "grades": [g * 1000 for g in prof["grades"]], "vertical": prof["vertical"],
                    "lidar": samples, "ballast_top_to_rail": RAIL_HEIGHT + PAD},
        "track": {"gauge": GAUGE, "rail": {"height": RAIL_HEIGHT, "head": RAIL_HEAD, "foot": RAIL_FOOT, "web": RAIL_WEB,
                                           "profile": "60E1 (UIC 60)"},
                  "pad": PAD, "sleeper": {"length": SLEEPER[0], "width": SLEEPER[1], "depth": SLEEPER[2],
                                          "spacing": SLEEPER_SPACING, "type": "M450 concrete monobloc"},
                  "ballast": {"depth": BALLAST_DEPTH, "shoulder": BALLAST_SHOULDER, "slope": BALLAST_SLOPE},
                  "cess": CESS, "drain": DRAIN, "section": section_dims(), "ballast_toe": ballast_toe(spacing)},
        "tracks": [{"ref": "1", "side": -1, "offset": -spacing / 2, "direction": "westbound", "osm": ids1,
                    "maxspeed": LINE_SPEED},
                   {"ref": "2", "side": 1, "offset": spacing / 2, "direction": "eastbound", "osm": ids2,
                    "maxspeed": LINE_SPEED}],
        "earthworks": dict(ew_json, walls=[{"id": "wall:%d" % i, "side": w["side"], "s0": w["s0"], "s1": w["s1"],
                                             "pts": w["pts"], "u": w["u"], "top": w["top"], "bottom": w["bottom"],
                                             "cutting": w["cutting"], "why": w["why"]}
                                            for i, w in enumerate(ew["walls"])]),
        "zones": [dict(z, id="zone:%d" % i) for i, z in enumerate(zs)],
        "platforms": [{"id": p["id"], "osm": p["osm"], "name": p["name"], "track": p["track"], "side": p["side"],
                       "s0": p["s0"], "s1": p["s1"], "ends": [p["s0"] - 0.5, p["s1"] + 0.5], "edge": p["edge"], "wall": p["wall"], "coping": PLATFORM_COPING,
                       "height": PLATFORM_HEIGHT, "back": p["back_u"],
                       "top": [p["top"](s) for s in p["ss"]], "tags": p["tags"]} for p in platforms],
        "rail_bridges": spans,
        "footbridges": structures["footbridges"],
        "underpasses": structures["underpasses"],
        "road_tunnel": {k: v for k, v in rt.items() if k not in ("surface",)} if rt else None,
        "station": {"name": "Lozère", "osm": "n5838690254", "furniture": furn["items"]},
        "stations": STATIONS,
        "yard": {"about": "tools/rail/yard.py: the tracks beyond the alignment (each its own line: points every metre, "
                          "rail top, heading; `main`: the RER B's tracks 1 and 2 going on from the alignment's end) and "
                          "the islands between them (ring, the platform edges along each track, top level)",
                 "s_start": Y["s_start"],
                 "tracks": [{"id": t["id"], "ref": t["ref"], "osm": t["osm"], "rer": t["rer"], "main": t["main"],
                             "pts": t["pts"], "z": t["z"], "heading": t["heading"], "drawn": drawn_range(t["pts"])}
                            for t in Y["tracks"]],
                 "islands": [{k: v for k, v in i.items()} for i in Y["islands"]]},
        "signals": sigs,
        "pk": pk,
        "catenary": cat,
        "services": services,
        "landing": land,
        "fences": [dict(f, id="fence:rail:%d" % (i + 1)) for i, f in enumerate(row_fences)],
        "clearance": clear,
        "train": {"model": "mi79", "cars": 8, "length": TRAIN_LENGTHS["8"], "accel": ACCEL,
                  "service_brake": SERVICE_BRAKE, "max_service_brake": MAX_SERVICE_BRAKE, "emergency_brake": EMERGENCY_BRAKE},
    }
    text = json.dumps(r3(rail), ensure_ascii=False, separators=(",", ":"))
    rg.RAIL_JSON.write_text(text + "\n", encoding="utf-8")
    log("wrote %s (%.1f MB) in %.0f s" % (rg.RAIL_JSON.relative_to(rg.ROOT), len(text) / 1e6, time.time() - t_start))
    import review
    review.draw(rail, world, H)


if __name__ == "__main__":
    main()
