"""The École polytechnique's new student housing (2026-11-08): lot S3.2 of the ZAC du quartier de l'École
polytechnique, on the Boulevard des Maréchaux, Palaiseau (around map x 785, y -339). The map pipeline had it as the
building site it was (a fenced construction ground, a gravel lot, six 12 m placeholder blocks from OSM); build_rail.py
calls build() and writes what it returns to rail.json `logements_x`; patch_world.py consumes it like any site (its
zones, its repair, apply_site: props, trees, fences, kerbs, kit modules, the six buildings restyled) and
scripts/builder/logements_x_builder.gd draws the details.

Sources: Thomas's annotated top view and eight photos (ref/logementsX/), AMOES's project sheet ("300 logements
étudiants, ZAC du quartier de l'École polytechnique": CDC Habitat, Dietrich | Untertrifaller, 6 plots RDC to R+5,
an underground car park under plots 4-6, green roof terraces, wood-frame facades), PSS-archi #82587 (R+5, roof at
19.80 m, 312 dwellings on 6 plots, 9 974 m² of floor, a 18 246 m² site), EPA Paris-Saclay (2017: 250 car parking
spaces for the École on the lot).

What it lays out (map metres):
- the six plots on OSM's footprints (w1338308393..98, 19.8 x 19.6 m squares turned -3.9°): ground floor 4.0 m, five
  floors of 3.0 m, a 0.9 m parapet (19.8 m): the world.json masses become a white concrete ground floor core (one
  corner cut out under the overhang: the bike shelter and the entrance porch, facing the promenade) and a floating
  upper body in the photos' khaki ribbed metal panels with a green roof; logements_x_builder.gd adds the projecting
  white slab bands, the white window surrounds, the windows, the ground floor glazing, the bike shelter's mesh and
  red hoops, the roof plant;
- the car park on the west strip (the gravel lot, OSM w1564824552): four rows of 90° bays (2.5 x 5 m) on two 6 m
  aisles, cross aisles at both ends, planted islands with a tree every ten bays, a planted border with trees all
  round, one entrance from the boulevard (a dropped kerb), street lamps; flat (a plane, 0.2 % along it);
- the gardens (the blue zone): a 3 m promenade winding between the plots from the car park to the east path, 2 m
  paths to the zebra on the boulevard, the ring residences' paths and the plots' entrances, small squares with benches
  and bins, light bollards along them, tall path lamps at the junctions; lawns with young staked trees (mulch rings),
  the LiDAR's poplars kept, a few limestone boulders; gravel strips at the plots' feet; one smooth ground (a harmonic
  surface between the car park, the sidewalk, the plots' pads and the ground round the site: the building site's
  spoil heaps gone);
- the boulevard's north sidewalk from the junction to the east path: a smooth kerb (a least-squares fit of the road's
  edge, its kerb extension at x 676 gone), 3.0 m wide, 0.12 m kerb, dropped (0.03 m) at the two zebras, the car park's
  entrance and the corner; street trees where the plots leave room; the recycling containers on a pad by it.
Assumed: the paths' layout (no landscape plan was found), the windows' rhythm (from the photos), the plots' numbers
(the photos show "22" on one), the car park's layout."""
import math

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import railgeo as rg

PLOTS = [("osm:w1338308398", "17"), ("osm:w1338308397", "18"), ("osm:w1338308396", "19"),
         ("osm:w1338308395", "20"), ("osm:w1338308393", "21"), ("osm:w1338308394", "22")]
FENCE_OSM = "w1156882390"       # the building site's fence (its outline is the site's)
LOT_OSM = "w1564824552"         # the gravel lot: the car park
PATH_EAST_OSM = "w30024847"     # the concrete path along the site's east side (OSM), kept
# the plots (photos, PSS-archi: R+5, 19.80 m)
GROUND_H = 4.0                  # m, the ground floor (to the first floor's level)
FLOOR_H = 3.0
FLOORS = 5
HEIGHT = 19.8                   # to the parapet's top
PARAPET = 0.9
WALL = "#a99f7a"                # the khaki / champagne ribbed metal panels (photos: #b9ac80 in sun, #9e9a87 shaded)
WHITE = "#ebe8e0"               # the slab bands, surrounds and ground floor concrete
SEDUM = "#7a9a48"               # the green roofs (AMOES: toitures-terrasses végétalisées)
RECESS = (9.0, 4.6)             # m: the corner cut out of the ground floor (along the entrance face, into the plot)
CORE_IN = 0.25                  # m the ground floor stands back from the bands' line
PAD_OUT = 1.5                   # m round a plot where the ground is the plot's pad level
GRAVEL = 0.6                    # m, the gravel strip at the plots' feet (photo)
# the sidewalk
KERB = 0.12
DROP = 0.03
WALK_W = 3.0
WALK_X = (647.9, 884.5)         # x of its ends: the corner's lowered kerb (kept), the east path
EDGE_SKIP = (669.0, 689.0)      # x: the kerb extension the smooth kerb leaves out
DROPS = [(647.9, 649.4), (769.2, 775.6), (880.9, 884.5)]   # the zebras' landings (n9686953114, n218228965, n14024511254)
RAMP = 1.5                      # m from a dropped kerb to a full one
# the car park: (a, b) from the lot's south-west corner, a along its long side (north), b across (east)
CP_O = np.array([641.746, -333.429])
CP_D = np.array([0.0518, 0.99866]) / np.linalg.norm([0.0518, 0.99866])
CP_N = np.array([CP_D[1], -CP_D[0]])
ROWS = [(0.6, 5.6), (11.6, 16.6), (16.6, 21.6), (27.6, 32.6)]   # b of the bay rows (the middle two back to back)
AISLES = [(5.6, 11.6), (21.6, 27.6)]
CP_A = (0.0, 107.5)             # a of the rows; cross aisles 6 m beyond both ends
ISLANDS = [(5.0, 7.5), (32.5, 35.0), (60.0, 62.5), (87.5, 90.0)]   # a: planted islands (a tree), across every row
BAY = 2.5
CP_B = (0.6, 32.6)
CP_GREEN_B = 36.0               # b of the car park's planted border's east edge
THROAT_B = (21.6, 27.6)         # the entrance from the boulevard: the east aisle's line
CP_Z = (0.86, 1.08)             # its level at a = -6 and a = 113.5 (a plane along it, flat across)


def r3(p) -> list:
    return [[round(float(a), 3) for a in q] for q in np.asarray(p)]


def polys(g) -> list:
    return [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05]


def pg_rings(p) -> list:
    return [r3(np.asarray(p.exterior.coords)[:-1])] + [r3(np.asarray(h.coords)[:-1]) for h in p.interiors]


def snap(g):
    return shapely.make_valid(shapely.set_precision(g, 0.001))


def chaikin(p, n: int = 4) -> np.ndarray:
    p = np.asarray(p, dtype=float)
    for _ in range(n):
        q = [p[0]]
        for a, b in zip(p[:-1], p[1:]):
            q += [0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b]
        q.append(p[-1])
        p = np.array(q)
    return p


def cp_xy(a, b) -> np.ndarray:
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    return CP_O + np.multiply.outer(a, CP_D) + np.multiply.outer(b, CP_N)


def cp_ab(p) -> np.ndarray:
    d = np.asarray(p, dtype=float) - CP_O
    return np.stack([d @ CP_D, d @ CP_N], axis=-1)


def cp_box(a0, a1, b0, b1) -> Polygon:
    return Polygon(cp_xy([a0, a0, a1, a1], [b0, b1, b1, b0]))


def cp_z(a):
    a = np.clip(np.asarray(a, dtype=float), -6.0, CP_A[1] + 6.0)
    return CP_Z[0] + (CP_Z[1] - CP_Z[0]) * (a + 6.0) / (CP_A[1] + 12.0)


def ramp(x, lo: float, hi: float, drops) -> np.ndarray:
    """hi along x, lo on the dropped stretches, linear over RAMP m on either side."""
    x = np.asarray(x, dtype=float)
    w = np.ones(len(x))
    for a, b in drops:
        d = np.maximum(a - x, x - b)            # < 0 inside the stretch
        w = np.minimum(w, np.clip(d / RAMP, 0.0, 1.0))
    return lo + (hi - lo) * w


def smooth_fit(x, y, step: float, weight: float) -> np.ndarray:
    """Least-squares fit of y(x), piecewise linear on knots every `step` m, its curvature damped."""
    ks = np.linspace(x[0], x[-1], max(int((x[-1] - x[0]) / step), 1) + 1)
    k = np.clip(np.searchsorted(ks, x) - 1, 0, len(ks) - 2)
    f = (x - ks[k]) / (ks[k + 1] - ks[k])
    A = np.zeros((len(x), len(ks)))
    A[np.arange(len(x)), k] = 1 - f
    A[np.arange(len(x)), k + 1] = f
    D2 = np.zeros((len(ks) - 2, len(ks)))
    for i in range(len(ks) - 2):
        D2[i, i:i + 3] = [1.0, -2.0, 1.0]
    sol = np.linalg.lstsq(np.vstack([A, D2 * weight]), np.concatenate([y, np.zeros(len(D2))]), rcond=None)[0]
    return lambda xq: np.interp(xq, ks, sol)


# ---------------------------------------------------------------- the paths (map points, smoothed)

PROMENADE = [(674.6, -329.0), (684.0, -328.4), (700.0, -327.6), (714.0, -327.8), (728.0, -329.0), (739.5, -331.0),
             (746.5, -337.0), (751.0, -345.5), (759.0, -350.4), (770.0, -350.6), (778.5, -347.0), (783.5, -340.5),
             (791.0, -336.2), (802.0, -334.6), (816.0, -334.8), (830.0, -335.8), (845.0, -336.4), (860.0, -336.8),
             (874.0, -337.4), (885.5, -337.8)]
PATHS = [   # (points, width)
    ([(772.6, -363.0), (772.2, -358.5), (770.4, -354.5), (770.0, -350.6)], 2.4),         # the mid zebra
    ([(759.6, -320.4), (754.0, -322.0), (747.6, -325.5), (743.4, -330.5), (742.0, -333.0)], 2.0),   # ring stub w...
    ([(813.6, -296.5), (816.5, -304.0), (818.0, -314.0), (817.2, -324.0), (816.0, -334.8)], 2.0),   # the north peak
    ([(714.0, -327.8), (716.8, -320.0), (719.4, -313.0), (723.6, -306.6)], 2.0),           # the ring's west path
    ([(816.0, -334.8), (817.4, -343.0), (818.6, -352.0), (818.8, -361.5)], 2.0),           # the containers, south
    ([(730.0, -329.0), (727.0, -336.0)], 2.0),          # plot entrances: filled in by the plots' own (see _entries)
]
SQUARES = [(684.6, -328.4, 3.0), (714.0, -327.8, 3.2), (742.6, -333.0, 3.2), (770.0, -350.6, 3.4), (816.0, -334.8, 3.4),
           (860.0, -336.8, 3.0)]    # small squares on the promenade (x, y, radius): benches and a bin


class Site:
    def __init__(self, world: dict, H: rg.Heights, taken=None):
        self.W = world
        self.H = H
        self.taken = taken if taken is not None else Polygon()
        G = world["ground"]
        self.roads = unary_union([Polygon(g["rings"][0], g["rings"][1:]).buffer(0) for g in G if g["kind"] == "road"
                                  and g["rings"] and _bb(g).intersects(box(630, -390, 900, -330))])
        fence = next(f for f in world["fences"] if f["osm"] == FENCE_OSM)
        self.fence_id = fence["id"]
        self.F = Polygon(fence["pts"]).buffer(0)
        self.plots = []
        bmap = {b["id"]: b for b in world["buildings"]}
        for pid, num in PLOTS:
            b = bmap[pid]
            self.plots.append({"id": pid, "num": num, "b": b, "ring": np.asarray(b["rings"][0], dtype=float),
                               "pg": Polygon(b["rings"][0])})
        self._kerb()
        self._select()
        self._carpark()
        self._plots()
        self._paths()
        self._partition()
        self._grid()

    # ---------------------------------------------------------------- the boulevard's kerb and sidewalk

    def _kerb(self):
        """The road's north edge (rays from the north), fitted smoothly; the sidewalk WALK_W behind it."""
        xs = np.arange(WALK_X[0] - 6.0, WALK_X[1] + 6.01, 1.0)
        ys = []
        for x in xs:
            ln = LineString([(x, -335.0), (x, -385.0)]).intersection(self.roads)
            tops = [max(c[1] for c in g.coords) for g in getattr(ln, "geoms", [ln]) if not g.is_empty]
            ys.append(max(tops) if tops else np.nan)
        ys = np.asarray(ys)
        ok = ~np.isnan(ys) & ((xs < EDGE_SKIP[0]) | (xs > EDGE_SKIP[1]))
        fit = smooth_fit(xs[ok], ys[ok], 10.0, 6.0)
        self.edge_dev = float(np.nanmax(np.abs(fit(xs[ok]) - ys[ok])))
        x = np.arange(WALK_X[0] - 1.0, WALK_X[1] + 1.001, 0.5)
        K = np.c_[x, fit(x)]
        t = np.gradient(K, axis=0)
        t /= np.linalg.norm(t, axis=1)[:, None]
        n = np.c_[-t[:, 1], t[:, 0]]                    # to the north (the kerb runs west -> east)
        self.K, self.Kn = K, n
        z_edge = self.H.at(K[:, 0] - n[:, 0] * 0.3, K[:, 1] - n[:, 1] * 0.3)
        self.z_road = smooth_fit(x, z_edge, 6.0, 4.0)(x)
        self.z_walk = self.z_road + ramp(x, DROP, KERB, DROPS + [self.throat_x()])
        back = K + n * WALK_W
        cut0 = _halfplane(K[2], t[2], +1)               # east of the perpendicular at WALK_X[0]
        cut1 = _halfplane(K[-3], t[-3], -1)             # west of the one at WALK_X[1]
        band = Polygon(np.r_[K, back[::-1]]).buffer(0).intersection(cut0).intersection(cut1)
        east = [g for g in self.W["ground"] if g["kind"] == "path" and g["rings"] and _bb(g).intersects(
            box(880, -372, 890, -360))]
        self.east_path = unary_union([Polygon(g["rings"][0], g["rings"][1:]).buffer(0) for g in east])
        self.walk = snap(band.difference(self.east_path).difference(self.taken))
        south = Polygon(np.r_[K, (K - n * 1.5)[::-1]]).buffer(0).intersection(cut0).intersection(cut1)
        self.roadfill = snap(south.difference(self.roads).difference(self.east_path).difference(self.taken))
        self.back = back

    def throat_x(self) -> tuple:
        p = cp_xy([-14.0, -14.0], [THROAT_B[0] - 1.5, THROAT_B[1] + 1.5])
        return (float(p[0][0]), float(p[1][0]))

    def walk_z_at(self, p) -> np.ndarray:
        """The sidewalk's level at map points (the nearest kerb point's)."""
        p = np.atleast_2d(np.asarray(p, dtype=float))
        d = ((p[:, None, :] - self.K[None, :, :]) ** 2).sum(-1)
        return self.z_walk[np.argmin(d, axis=1)]

    # ---------------------------------------------------------------- the site's extent

    def _select(self):
        """The base ground pieces the site takes whole: inside the fence (the building site, the lot, the plots), the
        strips round it up to the ring residences' paths, the west road's verge and the boulevard, the old sidewalk
        along the boulevard; less what other zones took."""
        Fb = self.F.buffer(4.0)
        shapely.prepare(Fb)
        K_line = LineString(self.K)
        take = []
        for gi, g in enumerate(self.W["ground"]):
            if not g["rings"] or not _bb(g).intersects(Fb):
                continue
            pg = Polygon(g["rings"][0], g["rings"][1:]).buffer(0)
            if pg.is_empty or pg.area < 0.01:
                continue
            k, m = g["kind"], g["material"]
            if k in ("road", "path", "footway", "cycleway", "pedestrian", "platform", "railway", "steps"):
                continue
            if k == "sidewalk":
                continue                                  # the old one along the boulevard: below
            if k == "building" and not any(pl["pg"].buffer(0.5).contains(pg) for pl in self.plots):
                continue
            inside = pg.intersection(Fb).area / pg.area
            if m == "asphalt" and k == "landcover" and not (pg.area < 100 and K_line.distance(pg) < 8.0):
                continue                                  # the ring residences' paths
            if inside > 0.7:
                take.append(gi)
        self.take = take
        site = unary_union([Polygon(self.W["ground"][i]["rings"][0], self.W["ground"][i]["rings"][1:]).buffer(0)
                            for i in take])
        # the old sidewalk along the boulevard (the sidewalk pieces' part east of the corner, within 6 m of the kerb)
        old = [Polygon(g["rings"][0], g["rings"][1:]).buffer(0) for g in self.W["ground"] if g["kind"] == "sidewalk"
               and g["rings"] and _bb(g).intersects(box(645, -370, 780, -340))]
        reach = Polygon(np.r_[self.K - self.Kn * 1.5, (self.K + self.Kn * 6.5)[::-1]]).buffer(0)
        reach = reach.intersection(_halfplane(self.K[2], self.K[3] - self.K[2], +1))
        self.old_walk = snap(unary_union(old).intersection(reach))
        s = unary_union([site, self.old_walk, self.walk, self.roadfill]).difference(self.taken)
        # no pinholes where the pieces' outlines and the sidewalk's nearly meet
        s = unary_union([Polygon(p.exterior, [h for h in p.interiors if Polygon(h).area > 1.0]) for p in polys(s)])
        # 1 mm beyond the pieces' outlines before the snap to the mm: the pieces it takes leave no hair-thin rests
        self.site = snap(s.buffer(0.001, join_style=2).difference(self.taken))

    # ---------------------------------------------------------------- the car park

    def _carpark(self):
        rows = unary_union([cp_box(CP_A[0], CP_A[1], b0, b1) for b0, b1 in ROWS])
        aisles = unary_union([cp_box(CP_A[0] - 6.0, CP_A[1] + 6.0, b0, b1) for b0, b1 in AISLES])
        cross = unary_union([cp_box(CP_A[0] - 6.0, CP_A[0], CP_B[0], CP_B[1]),
                             cp_box(CP_A[1], CP_A[1] + 6.0, CP_B[0], CP_B[1])])
        body = unary_union([rows, aisles, cross])
        body = body.buffer(-3.0, join_style=1).buffer(3.0, join_style=1)      # rounded outer corners
        # the entrance: the east aisle's line down to the sidewalk, flared at its mouth
        mouth = Polygon(np.r_[cp_xy([-6.0, -6.0], [THROAT_B[1], THROAT_B[0]]),
                              cp_xy([-18.0, -18.0], [THROAT_B[0] - 2.0, THROAT_B[1] + 2.0])])
        throat = mouth.buffer(1.5, join_style=1).buffer(-1.5, join_style=1).union(mouth)
        throat = throat.difference(self.walk).intersection(Polygon(np.r_[self.back, [[self.back[-1][0], -300.0],
                                                                                      [self.back[0][0], -300.0]]]))
        isl = unary_union([cp_box(a0, a1, b0, b1) for a0, a1 in ISLANDS for b0, b1 in [ROWS[0], (ROWS[1][0], ROWS[2][1]),
                                                                                        ROWS[3]]])
        # the promenade's way in: the east row's first island is a paved passage
        self.passage = snap(cp_box(ISLANDS[0][0], ISLANDS[0][1], ROWS[3][0], CP_GREEN_B))
        isl = isl.difference(cp_box(ISLANDS[0][0], ISLANDS[0][1], ROWS[3][0] - 0.01, CP_GREEN_B + 1))
        self.islands = [p for p in polys(isl)]
        self.cp_asphalt = snap(unary_union([body, throat]).difference(isl).difference(self.passage).intersection(
            self.site))
        self.cp_area = snap(cp_box(-20.0, 140.0, -8.0, CP_GREEN_B).intersection(self.site))
        # bays: (a0, row index) of each, its centre and heading (towards the aisle)
        bays = []
        groups = [(CP_A[0], ISLANDS[0][0])] + [(ISLANDS[i][1], ISLANDS[i + 1][0]) for i in range(len(ISLANDS) - 1)] + \
            [(ISLANDS[-1][1], CP_A[1])]
        for ri, (b0, b1) in enumerate(ROWS):
            for g0, g1 in groups:
                n = int(round((g1 - g0) / BAY))
                for k in range(n):
                    bays.append((g0 + k * BAY, ri))
        self.bays = bays

    def bay_lines(self) -> list:
        """The bays' white lines (a0, b0, a1, b1, width): their sides, and the line between the back-to-back rows."""
        out = []
        groups = [(CP_A[0], ISLANDS[0][0])] + [(ISLANDS[i][1], ISLANDS[i + 1][0]) for i in range(len(ISLANDS) - 1)] + \
            [(ISLANDS[-1][1], CP_A[1])]
        for ri, (b0, b1) in enumerate(ROWS):
            for g0, g1 in groups:
                n = int(round((g1 - g0) / BAY))
                for k in range(n + 1):
                    a = g0 + k * BAY
                    out.append((a, b0, a, b1, 0.12))
        for g0, g1 in groups:                   # the line between the back-to-back rows
            out.append((g0, ROWS[1][1], g1, ROWS[1][1], 0.12))
        return out

    # ---------------------------------------------------------------- the plots

    def _plots(self):
        """Each plot's frame, its entrance corner (the one nearest the promenade), the recess cut out of its ground
        floor there (the bike shelter, then the porch), its pad."""
        prom = LineString(chaikin(PROMENADE))
        for pl in self.plots:
            R = pl["ring"]
            c = R.mean(axis=0)
            pl["c"] = c
            # the corner nearest the promenade; the entrance face: of its two faces the one more facing it
            dists = [prom.distance(Point(p)) for p in R]
            k = int(np.argmin(dists))
            prev, nxt = R[k - 1], R[(k + 1) % 4]
            q = np.asarray(prom.interpolate(prom.project(Point(R[k]))).coords[0])
            to = q - R[k]
            e_next = (nxt - R[k]) / np.linalg.norm(nxt - R[k])
            e_prev = (prev - R[k]) / np.linalg.norm(prev - R[k])
            # the face along which the recess runs: the one whose outward normal looks most towards the promenade
            out_next = np.array([e_next[1], -e_next[0]])       # CCW ring: outward is right of k -> k+1
            out_prev = np.array([-e_prev[1], e_prev[0]])
            along_next = float(out_next @ to) >= float(out_prev @ to)
            pl["corner"] = k
            pl["along_next"] = along_next
            ea, eb = (e_next, e_prev) if along_next else (e_prev, e_next)    # along the entrance face, into the plot
            pl["ea"], pl["eb"] = ea, eb
            P = R[k]
            rec = Polygon([P, P + ea * RECESS[0], P + ea * RECESS[0] + eb * RECESS[1], P + eb * RECESS[1]])
            pl["recess"] = rec
            core = pl["pg"].difference(rec)
            pl["core"] = core.buffer(-CORE_IN, join_style=2)      # the ground floor under the slab bands
            pl["door"] = P + ea * (RECESS[0] - 1.6) + eb * RECESS[1]          # on the porch's inner wall
            pl["apron"] = P + ea * (RECESS[0] - 1.6) - np.array([ea[1], -ea[0]]) * 0.0

    # ---------------------------------------------------------------- the paths

    def _paths(self):
        parts, lines = [], []
        prom = chaikin(PROMENADE)
        lines.append((prom, 3.0, "promenade"))
        for pts, w in PATHS[:-1]:
            lines.append((chaikin(pts, 3), w, "path"))
        # to each plot's porch: from the promenade's nearest point, eased in
        P = LineString(prom)
        for pl in self.plots:
            k = pl["corner"]
            P0 = pl["ring"][k]
            mid = P0 + pl["ea"] * (RECESS[0] - 2.0)
            outn = -pl["eb"]
            door_out = mid + outn * 1.5
            q = np.asarray(P.interpolate(P.project(Point(door_out))).coords[0])
            if np.linalg.norm(q - door_out) < 1.5:
                pts = [mid + pl["eb"] * 1.0, door_out]
            else:
                pts = [mid + pl["eb"] * 1.0, door_out, door_out + outn * min(2.5, np.linalg.norm(q - door_out) * 0.4), q]
            lines.append((chaikin(pts, 3), 2.2, "entry"))
        self.lines = lines
        g = unary_union([LineString(p).buffer(w / 2, cap_style=1, join_style=1, quad_segs=12) for p, w, _ in lines] +
                        [Point(x, y).buffer(r, quad_segs=16) for x, y, r in SQUARES])
        # the containers' pad by the sidewalk
        pad_c = np.array([819.0, -362.8])
        kn = self.Kn[np.argmin(np.abs(self.K[:, 0] - pad_c[0]))]
        kt = np.array([kn[1], -kn[0]])
        self.bins_pad = Polygon([pad_c + kt * 4.0 - kn * 1.6, pad_c - kt * 4.0 - kn * 1.6, pad_c - kt * 4.0 + kn * 1.4,
                                 pad_c + kt * 4.0 + kn * 1.4])
        g = unary_union([g, self.bins_pad, self.passage])
        self.paths_g = g

    # ---------------------------------------------------------------- the partition

    def _partition(self):
        S = self.site
        walk = snap(self.walk.intersection(S))
        road = snap(self.roadfill.intersection(S).difference(walk))
        hard = unary_union([walk, road])
        cp = snap(self.cp_asphalt.difference(hard))
        plots = snap(unary_union([pl["core"] for pl in self.plots]).intersection(S).difference(hard))
        fore = snap(unary_union([pl["recess"] for pl in self.plots]).intersection(S).difference(hard))
        taken = unary_union([hard, cp, plots, fore])
        paths = snap(self.paths_g.intersection(S).difference(taken))
        taken = unary_union([taken, paths])
        feet = unary_union([pl["pg"].buffer(GRAVEL, join_style=2) for pl in self.plots])
        gravel = snap(feet.intersection(S).difference(taken))
        taken = unary_union([taken, gravel])
        lawn = snap(S.difference(taken))
        self.parts = {"walk": walk, "road": road, "parking": cp, "plots": plots, "forecourt": fore, "paths": paths,
                      "gravel": gravel, "lawn": lawn}

    # ---------------------------------------------------------------- the ground

    def _grid(self):
        """The finished ground on a 1 m grid on the 2 m nodes' lattice: fixed on the car park (its plane), the
        sidewalk (the road's level near the kerb, the sidewalk's behind: patch_world.py draws each side of the kerb
        from the nodes on its side), the road, the plots' pads and round the site (the ground as it is); the rest
        (lawns, paths) a harmonic surface between them."""
        from scipy.sparse import coo_matrix
        from scipy.sparse.linalg import spsolve
        H = self.H
        ox = H.ox - H.mesh_cell                          # node lattice: ox + (i - 1) * mesh_cell
        oy = H.oy + H.mesh_cell
        x0, y0, x1, y1 = self.site.buffer(4.0).bounds
        x0 = ox + 2.0 * math.floor((x0 - ox) / 2.0)
        y1 = oy - 2.0 * math.floor((oy - y1) / 2.0)
        xs = np.arange(x0, x1 + 2.0, 1.0)
        ys = np.arange(y1, y0 - 2.0, -1.0)
        X, Y = np.meshgrid(xs, ys)
        x, y = X.ravel(), Y.ravel()
        base = np.asarray(H.at(x, y), dtype=float)
        inside = shapely.contains_xy(self.site, x, y)
        fixed = np.where(inside, np.nan, base)
        P = self.parts
        on_walk = shapely.contains_xy(P["walk"].buffer(0.01), x, y)
        if on_walk.any():
            pts = np.c_[x[on_walk], y[on_walk]]
            d = ((pts[:, None, :] - self.K[None, :, :]) ** 2).sum(-1)
            j = np.argmin(d, axis=1)
            near = np.sqrt(d[np.arange(len(j)), j]) < WALK_W / 2
            fixed[on_walk] = np.where(near, self.z_road[j], self.z_walk[j])
        on_road = shapely.contains_xy(P["road"].buffer(0.01), x, y)
        fixed[on_road] = base[on_road]
        ab = cp_ab(np.c_[x, y])
        on_cp = shapely.contains_xy(P["parking"].buffer(0.3), x, y) & ~on_walk
        zc = cp_z(ab[:, 0])
        # the entrance: from the dropped sidewalk at its mouth up to the car park's level at a = -6
        a_back = float(cp_ab(self.back[np.argmin(np.abs(self.back[:, 0] - self.throat_x()[0] - 3.0))])[0])
        z_mouth = float(np.mean(self.z_walk[(self.K[:, 0] > self.throat_x()[0]) & (self.K[:, 0] < self.throat_x()[1])]))
        t = np.clip((ab[:, 0] - a_back) / (-6.0 - a_back), 0.0, 1.0)
        zc = np.where(ab[:, 0] < -6.0, z_mouth + (cp_z(-6.0) - z_mouth) * t, zc)
        fixed[on_cp] = zc[on_cp]
        self.z_mouth = z_mouth

        def solve(fx):
            soft = np.isnan(fx)
            h, w = X.shape
            idx = -np.ones(len(x), dtype=int)
            idx[soft] = np.arange(soft.sum())
            rows, cols, vals = [], [], []
            rhs = np.zeros(soft.sum())
            diag = np.zeros(soft.sum())
            sidx = np.where(soft)[0]
            for di, dj in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                j, i = np.divmod(sidx, w)
                jj, ii = j + di, i + dj
                ok = (jj >= 0) & (jj < h) & (ii >= 0) & (ii < w)
                a = sidx[ok]
                b = jj[ok] * w + ii[ok]
                ka = idx[a]
                diag[ka] += 1.0
                sb = soft[b]
                rows += list(ka[sb]); cols += list(idx[b[sb]]); vals += [-1.0] * int(sb.sum())
                np.add.at(rhs, ka[~sb], fx[b[~sb]])
            n = soft.sum()
            A = coo_matrix((np.r_[diag, vals], (np.r_[np.arange(n), rows], np.r_[np.arange(n), cols])),
                           shape=(n, n)).tocsr()
            out = fx.copy()
            out[soft] = spsolve(A, rhs)
            return out

        first = solve(fixed)
        for pl in self.plots:
            m = shapely.contains_xy(pl["pg"], x, y)
            pl["zp"] = round(float(np.mean(first[m])), 2)
            pad = shapely.contains_xy(pl["pg"].buffer(PAD_OUT, join_style=2), x, y) & np.isnan(fixed)
            fixed[pad] = pl["zp"]
        Z = solve(fixed)
        self.grid = {"x0": float(xs[0]), "y0": float(ys[0]), "cell": 1.0, "w": len(xs), "h": len(ys),
                     "z": Z.reshape(X.shape)}

    def surf(self, x, y) -> np.ndarray:
        """The finished ground at map points, as patch_world.py will draw it (the 2 m nodes of the repaired
        heightmap, bilinear; the sidewalk's own level on it)."""
        G = self.grid
        x, y = np.atleast_1d(np.asarray(x, float)), np.atleast_1d(np.asarray(y, float))
        fx = (x - G["x0"]) / G["cell"]
        fy = (G["y0"] - y) / G["cell"]
        i = np.clip(np.floor(fx / 2).astype(int) * 2, 0, G["w"] - 3)
        j = np.clip(np.floor(fy / 2).astype(int) * 2, 0, G["h"] - 3)
        a, b = (fx - i) / 2, (fy - j) / 2
        Z = G["z"]
        z = Z[j, i] * (1 - a) * (1 - b) + Z[j, i + 2] * a * (1 - b) + Z[j + 2, i] * (1 - a) * b + Z[j + 2, i + 2] * a * b
        on = shapely.contains_xy(self.parts["walk"], x, y)
        if on.any():
            z[on] = self.walk_z_at(np.c_[x[on], y[on]])
        return z

    # ---------------------------------------------------------------- for patch_world.py

    def zones(self) -> list:
        """Zones (patch_world.py; all take the pipeline's raised pieces, kerbs and markings in: `absorb`): the
        sidewalk at its kerb's level along it (bus_island: the kerb a step); the rest on the repaired ground
        (regrade: one surface), each with its ground piece."""
        out = []
        ax = self.K[::2]
        az = self.z_walk[::2]
        for p in polys(self.parts["walk"]):
            out.append({"kind": "bus_island", "piece": ["sidewalk", "concrete"], "absorb": True, "side": None,
                        "source": "logx:sidewalk", "polygons": [pg_rings(p)], "axis": r3(ax),
                        "axis_z": [round(float(v), 3) for v in az], "portals": []})
        for key, piece, src in [("road", ["road", "asphalt"], "logx:road"),
                                ("parking", ["parking", "asphalt"], "logx:parking"),
                                ("plots", ["building", "building"], "logx:plots"),
                                ("forecourt", ["pedestrian", "concrete"], "logx:forecourt"),
                                ("paths", ["path", "concrete"], "logx:paths"),
                                ("gravel", ["landcover", "gravel"], "logx:gravel"),
                                ("lawn", ["landcover", "grass"], "logx:lawn")]:
            ps = polys(self.parts[key])
            if ps:
                out.append({"kind": "regrade", "piece": piece, "absorb": True, "side": None, "source": src,
                            "polygons": [pg_rings(p) for p in ps]})
        return out

    def repair(self) -> dict:
        """massy_station.apply_repairs' "axis" method with a grid (bus_station.axis_repair): the finished ground over
        the site (the ground as it is round it)."""
        G = self.grid
        area = max(polys(self.site.buffer(1.0)), key=lambda q: q.area)
        c = area.centroid.coords[0]
        return {"id": "repair:logements-x", "method": "axis", "ring": r3(np.asarray(area.exterior.coords)[:-1]),
                "core": [r3(np.asarray(area.exterior.coords)[:-1])], "axis": r3([c, c]), "axis_z": [0.0, 0.0],
                "blend": 0.0, "grid": {"x0": round(G["x0"], 3), "y0": round(G["y0"], 3), "cell": G["cell"],
                                       "w": G["w"], "h": G["h"], "z": [round(float(a), 3) for a in G["z"].ravel()]},
                "why": "the École polytechnique's new housing: its car park, gardens and sidewalk on one smooth ground"}


    # ---------------------------------------------------------------- the ground after the patch

    def ground_after(self, x, y) -> np.ndarray:
        """The height ground_heights.gd will give (props, trees): the patched heightmap's 2 m nodes, bilinear: on the
        sidewalk its level, in the other zones the repaired ground, elsewhere as it was."""
        G = self.grid
        x, y = np.atleast_1d(np.asarray(x, float)), np.atleast_1d(np.asarray(y, float))
        fx = (x - G["x0"]) / 2.0
        fy = (G["y0"] - y) / 2.0
        i = np.clip(np.floor(fx).astype(int), 0, (G["w"] - 3) // 2)
        j = np.clip(np.floor(fy).astype(int), 0, (G["h"] - 3) // 2)
        a, b = fx - i, fy - j
        out = np.zeros(len(x))
        for di, dj, wgt in ((0, 0, (1 - a) * (1 - b)), (1, 0, a * (1 - b)), (0, 1, (1 - a) * b), (1, 1, a * b)):
            nx = G["x0"] + (i + di) * 2.0
            ny = G["y0"] - (j + dj) * 2.0
            z = G["z"][(j + dj) * 2, (i + di) * 2]
            on = shapely.contains_xy(self.parts["walk"], nx, ny)
            if on.any():
                z = np.where(on, self.walk_z_at(np.c_[nx, ny]), z)
            out += z * wgt
        return out

    # ---------------------------------------------------------------- trees, props, furniture

    def furnish(self, world: dict) -> None:
        """Trees kept, gone and new; props moved, gone and new; the builder's bollards, boulders, mulch rings."""
        rng = np.random.default_rng(2026)
        P = self.parts
        paved = unary_union([P["walk"], P["road"], P["parking"], P["paths"], P["forecourt"], P["plots"],
                             P["gravel"]])
        shapely.prepare(paved)
        site = self.site
        kept, gone = [], []
        for t in world["trees"]:
            if not site.contains(Point(t["x"], t["y"])):
                continue
            if paved.buffer(0.6).contains(Point(t["x"], t["y"])):
                gone.append(t["id"])
            else:
                kept.append(t)
        new = []
        placed = [((t["x"], t["y"]), float(t["r"])) for t in kept] + \
                 [((t["x"], t["y"]), float(t["r"])) for t in world["trees"] if Point(t["x"], t["y"]).distance(site) < 6
                  and not site.contains(Point(t["x"], t["y"]))]
        lawn = P["lawn"]
        shapely.prepare(lawn)

        def add(p, arch, h, r, tint, src, gap=1.0, clear=None, mulch=False):
            pt = Point(p)
            if not lawn.contains(pt):
                return False
            if clear is not None and paved.distance(pt) < clear:
                return False
            if any(math.hypot(p[0] - q[0], p[1] - q[1]) < (r + rq) * gap for q, rq in placed):
                return False
            placed.append((tuple(p), r))
            new.append({"id": "tree:logx:%d" % (len(new) + 1), "x": round(float(p[0]), 2), "y": round(float(p[1]), 2),
                        "h": round(float(h), 2), "r": round(float(r), 2), "arch": arch,
                        "var": int(rng.integers(0, int(world["tree_archetypes"][arch]))), "tint": tint,
                        "src": src})
            if mulch:
                self.mulch.append([round(float(p[0]), 2), round(float(p[1]), 2), round(0.55 + 0.1 * r, 2)])
            return True
        self.mulch = []
        # the car park: borders all round and the islands (established trees)
        def cp_tree(a, b, h=None):
            h = h or rng.uniform(8.5, 11.0)
            add(cp_xy(a, b), "round" if rng.random() < 0.6 else "oval", h, h * rng.uniform(0.3, 0.34),
                "leaf" if rng.random() < 0.6 else "spring", "logx:parking", gap=0.8, clear=0.9)
        for a in np.arange(-3.0, CP_A[1] + 9.0, 7.5):
            cp_tree(a, -1.6)
            if not (ISLANDS[0][0] - 2 < a < ISLANDS[0][1] + 2):
                cp_tree(a, 34.4)
        for b in (3.0, 10.0, 17.0, 31.5):
            cp_tree(-10.5, b)
        for b in (3.0, 10.0, 17.0, 24.0):
            cp_tree(CP_A[1] + 9.5, b)
        for a0, a1 in ISLANDS:
            a = (a0 + a1) / 2
            cp_tree(a, (ROWS[0][0] + ROWS[0][1]) / 2)
            cp_tree(a, ROWS[1][0] + 2.5)
            cp_tree(a, ROWS[2][1] - 2.5)
            if a0 != ISLANDS[0][0]:
                cp_tree(a, (ROWS[3][0] + ROWS[3][1]) / 2)
        # street trees behind the sidewalk where the plots leave room
        for x in np.arange(652.0, WALK_X[1] - 4.0, 9.0):
            k = int(np.argmin(np.abs(self.back[:, 0] - x)))
            p = self.back[k] + self.Kn[k] * 1.7
            if any(pl["pg"].distance(Point(p)) < 4.0 for pl in self.plots):
                continue
            add(p, "round", 7.5, 2.3, "leaf", "logx:street", gap=0.9, clear=1.0)
        # the squares: a tree behind the benches
        for x, y, r in SQUARES:
            for ang in np.arange(0, 360, 30):
                q = (x + (r + 3.0) * math.cos(math.radians(ang)), y + (r + 3.0) * math.sin(math.radians(ang)))
                if add(q, "round", rng.uniform(6.5, 8.0), 2.4, "spring", "logx:garden", gap=1.0, clear=1.6):
                    break
        # the gardens: young staked trees over the lawns (photos), a few already taller
        x0, y0, x1, y1 = lawn.bounds
        cand = np.c_[rng.uniform(x0, x1, 6000), rng.uniform(y0, y1, 6000)]
        far_cp = cp_ab(cand)[:, 1] > CP_GREEN_B + 1.0
        for p in cand[far_cp]:
            if len([t for t in new if t["src"] == "logx:garden"]) >= 120:
                break
            if any(pl["pg"].distance(Point(p)) < 4.5 for pl in self.plots):
                continue
            tall = rng.random() < 0.15
            h = rng.uniform(6.0, 8.0) if tall else rng.uniform(3.4, 5.4)
            r = h * rng.uniform(0.28, 0.33)
            add(p, "round" if tall else "sapling", h, r, ["spring", "leaf", "lime", "golden", "copper"][
                int(rng.choice(5, p=[0.4, 0.33, 0.15, 0.09, 0.03]))], "logx:garden", gap=1.9, clear=1.8,
                mulch=not tall)
        self.trees_kept = [t["id"] for t in kept]
        self.trees_gone = gone
        self.trees_new = new
        # props: those in the site onto the new sidewalk (lamps, hydrant, guideposts) or kept on the lawn
        moved, dropped, lifts = {}, [], {}
        for p in world["props"]:
            pt = Point(p["x"], p["y"])
            if not site.buffer(0.5).contains(pt):
                continue
            if p["model"] in ("lamp_street", "lamp_path") and LineString(self.K).distance(pt) < 9.0:
                k = int(np.argmin(np.hypot(self.K[:, 0] - p["x"], self.K[:, 1] - p["y"])))
                q = self.K[k] + self.Kn[k] * 0.7
                moved[p["id"]] = [round(float(q[0]), 3), round(float(q[1]), 3)]
                pt = Point(q)
            elif P["walk"].contains(pt) or P["lawn"].contains(pt):
                pass
            elif paved.contains(pt) and p["model"] in ("guidepost",):
                pass
            elif not P["lawn"].contains(pt) and not P["walk"].contains(pt):
                dropped.append(p["id"])
                continue
            if P["walk"].buffer(0.05).contains(pt):
                lifts[p["id"]] = round(float(self.walk_z_at([pt.x, pt.y])[0] - self.ground_after(pt.x, pt.y)[0]), 3)
        self.props_moved, self.props_dropped, self.props_lift = moved, dropped, lifts
        props = []

        def prop(model, p, yaw, kind, **kw):
            q = {"id": "prop:logx:%d" % (len(props) + 1), "kind": kind, "model": model, "x": round(float(p[0]), 3),
                 "y": round(float(p[1]), 3), "yaw": round(float(yaw) % 360.0, 1), "lift": 0.0, "src": "logx"}
            q.update(kw)
            props.append(q)
        # benches and bins on the squares' edges, facing in, where no path opens; a path lamp beside
        for x, y, r in SQUARES:
            free = [ang for ang in range(0, 360, 10) if not self.paths_g.buffer(-0.05).contains(
                Point(x + (r + 0.9) * math.cos(math.radians(ang)), y + (r + 0.9) * math.sin(math.radians(ang))))
                and lawn.contains(Point(x + (r + 0.9) * math.cos(math.radians(ang)),
                                        y + (r + 0.9) * math.sin(math.radians(ang))))]
            if not free:
                continue
            # the middles of the free arcs
            arcs, cur = [], [free[0]]
            for a in free[1:]:
                if a - cur[-1] == 10:
                    cur.append(a)
                else:
                    arcs.append(cur)
                    cur = [a]
            arcs.append(cur)
            if len(arcs) > 1 and arcs[0][0] == 0 and arcs[-1][-1] == 350:
                arcs[0] = arcs[-1] + [a + 360 for a in arcs[0]]
                arcs.pop()
            arcs = sorted([a for a in arcs if len(a) >= 5], key=len, reverse=True)[:2]
            for n, arc in enumerate(arcs):
                ang = math.radians(arc[len(arc) // 2])
                c = np.array([x + (r - 0.55) * math.cos(ang), y + (r - 0.55) * math.sin(ang)])
                prop("bench_back", c, math.degrees(ang) + 180.0, "bench")
                if n == 0:
                    tg = np.array([-math.sin(ang), math.cos(ang)])
                    prop("bin_vigipirate", c + tg * 1.45 + np.array([math.cos(ang), math.sin(ang)]) * 0.25,
                         math.degrees(ang) + 180.0, "waste_basket")
                    lp = np.array([x + (r + 0.7) * math.cos(ang - 0.5), y + (r + 0.7) * math.sin(ang - 0.5)])
                    if lawn.contains(Point(lp)):
                        prop("lamp_path", lp, math.degrees(ang) + 180.0, "street_lamp")
        # path lamps along the promenade (every ~26 m, alternating sides)
        prom = LineString(chaikin(PROMENADE))
        for k, s in enumerate(np.arange(14.0, prom.length - 6.0, 26.0)):
            a = np.asarray(prom.interpolate(s).coords[0])
            b = np.asarray(prom.interpolate(s + 0.5).coords[0])
            t = (b - a) / np.linalg.norm(b - a)
            n = np.array([-t[1], t[0]]) * (1 if k % 2 else -1)
            q = a + n * 2.1
            if lawn.contains(Point(q)) and all(math.hypot(q[0] - pp["x"], q[1] - pp["y"]) > 6.0 for pp in props):
                prop("lamp_path", q, math.degrees(math.atan2(-n[1], -n[0])), "street_lamp")
        # the car park's lamps: on the borders and in the middle islands, the arm over the aisles
        for a0, a1 in [(-3.0, -3.0)] + ISLANDS[1:] + [(CP_A[1] + 3.0, CP_A[1] + 3.0)]:
            a = (a0 + a1) / 2
            for b, yaw_dir in [(-0.5, 1), (33.9, -1)]:
                q = cp_xy(a, b)
                if lawn.contains(Point(q)):
                    prop("lamp_street", q, math.degrees(math.atan2(*(CP_N * yaw_dir)[::-1])), "street_lamp")
        for a0, a1 in ISLANDS[1:]:
            q = cp_xy((a0 + a1) / 2, (ROWS[1][0] + ROWS[2][1]) / 2)
            prop("lamp_street", q, math.degrees(math.atan2(CP_N[1], CP_N[0])), "street_lamp")
        # the recycling containers on their pad by the sidewalk (photo), facing it
        c = np.asarray(self.bins_pad.centroid.coords[0])
        k = int(np.argmin(np.abs(self.K[:, 0] - c[0])))
        kt = np.array([self.Kn[k][1], -self.Kn[k][0]])
        for d, tint in ((-2.4, "glass_bin"), (0.0, "plastic_bin"), (2.4, "plastic_bin")):
            prop("recycling_underground", c + kt * d, math.degrees(math.atan2(-self.Kn[k][1], -self.Kn[k][0])),
                 "recycling", tint=tint, tags={"location": "underground"})
        self.props_new = props
        # light bollards along the paths (dark grey, ~1 m: photos), every ~9-10 m, alternating sides
        bol = []
        for pts, w, kind in self.lines:
            if kind == "entry":
                continue
            ln = LineString(pts)
            step = 9.0 if kind == "promenade" else 10.0
            for k, s in enumerate(np.arange(3.0, ln.length - 2.0, step)):
                a = np.asarray(ln.interpolate(s).coords[0])
                b = np.asarray(ln.interpolate(min(s + 0.5, ln.length)).coords[0])
                t = (b - a) / max(np.linalg.norm(b - a), 1e-6)
                n = np.array([-t[1], t[0]]) * (1 if k % 2 else -1)
                q = a + n * (w / 2 + 0.35)
                if not lawn.contains(Point(q)) or self.paths_g.distance(Point(q)) < 0.25:
                    continue
                if any(math.hypot(q[0] - pp["x"], q[1] - pp["y"]) < 2.5 for pp in props):
                    continue
                if any(math.hypot(q[0] - bx, q[1] - by) < 3.5 for bx, by in bol):
                    continue
                bol.append((round(float(q[0]), 2), round(float(q[1]), 2)))
        self.bollards = [list(b) for b in bol]
        # limestone boulders in pairs and threes by the squares and path bends (photo)
        rocks = []
        for x, y, r in SQUARES[1:]:
            for ang in rng.permutation(np.arange(0, 360, 15))[:24]:
                q = np.array([x + (r + 1.2) * math.cos(math.radians(ang)), y + (r + 1.2) * math.sin(math.radians(ang))])
                if lawn.contains(Point(q).buffer(0.6)) and self.paths_g.distance(Point(q)) > 0.5 and \
                        all(math.hypot(q[0] - t["x"], q[1] - t["y"]) > 1.5 for t in new):
                    for j in range(int(rng.integers(2, 4))):
                        o = q + rng.uniform(-0.7, 0.7, 2)
                        rocks.append([round(float(o[0]), 2), round(float(o[1]), 2), round(float(rng.uniform(0, 180)), 1),
                                      round(float(rng.uniform(0.6, 1.1)), 2), round(float(rng.uniform(0.35, 0.6)), 2),
                                      round(float(rng.uniform(0.3, 0.45)), 2)])
                    break
        self.rocks = rocks

    # ---------------------------------------------------------------- the plots in world.json

    def buildings(self) -> list:
        """The six plots as world.json buildings (patch_world.apply_site swaps them in): a white concrete ground floor
        core (the recess cut out) and a floating upper body in the khaki panels with a green roof; the builder adds
        the rest."""
        import copy
        out = []
        for pl in self.plots:
            b = copy.deepcopy(pl["b"])
            zp = pl["zp"]
            sq = _ccw(pl["ring"])
            core = _ccw(np.asarray(pl["core"].exterior.coords)[:-1])
            body_style = {"group": "residential", "floors": 0, "ground": 0, "material": 5, "top": 0, "wall": WALL,
                          "accent": WHITE, "g": GROUND_H, "f": FLOOR_H, "levels": FLOORS + 1, "bay": 0.42,
                          "seed": int(pl["num"]), "wall_src": "logx", "windows": 0,
                          "names": ["blind", "plain", "panels", "plain"]}
            ground_style = dict(body_style, material=4, wall=WHITE, bay=3.0, names=["blind", "plain", "concrete", "plain"])
            runs = []
            body = _tier(sq, zp + GROUND_H - 0.3, zp + HEIGHT, PARAPET, 0.3, SEDUM, True, runs, 0)
            body["green"] = True
            ground = _tier(core, zp - 0.6, zp + GROUND_H - 0.3, 0.0, 0.0, "#d5d2ca", False, runs, 1)
            b.update({"name": "Logements élèves %s" % pl["num"], "kind": "dormitory", "base_z": zp, "foot_z": zp - 0.6,
                      "height": HEIGHT, "min_height": 0.0, "height_src": "logx", "pillars": []})
            b["heights"] = dict(b.get("heights", {}), logx=HEIGHT)
            b["roof"] = {"shape": "flat", "color": SEDUM, "tris": b["roof"]["tris"]}
            b["facade"] = {"color": WALL, "color_src": "logx", "accent": WHITE, "levels": float(FLOORS + 1)}
            b["toy"] = {"style": body_style, "styles": [body_style, ground_style], "tiers": [ground, body],
                        "runs": runs, "passages": []}
            out.append(b)
        return out

    # ---------------------------------------------------------------- rail.json `logements_x`

    def data(self, world: dict) -> dict:
        self.furnish(world)
        P = self.parts
        kerb_on = [[round(float(p[0]), 3), round(float(p[1]), 3), round(float(z), 3)]
                   for p, z in zip(self.K, self.z_walk)]
        # the car park's kerb stones: round its asphalt (not where it meets the sidewalk) and its islands, flush
        cps = []
        walk_b = P["walk"].buffer(0.3)
        for p in polys(P["parking"]):
            for ring in [p.exterior] + list(p.interiors):
                ln = LineString(ring.coords).difference(walk_b).difference(self.passage.buffer(0.05))
                for part in getattr(ln, "geoms", [ln]):
                    if part.geom_type == "LineString" and part.length > 0.5:
                        q = np.asarray(part.segmentize(1.0).coords)
                        z = self.surf(q[:, 0], q[:, 1])
                        cps.append(r3(np.c_[q, z]))
        # markings: the bays' lines (triangles just over the car park), the throat's give-way line
        tri = []
        for a0, b0, a1, b1, w in self.bay_lines():
            A = np.array([a0, b0]); B = np.array([a1, b1])
            d = (B - A) / np.linalg.norm(B - A)
            n = np.array([-d[1], d[0]]) * w / 2
            q = [A - n, B - n, B + n, A + n]
            pts = cp_xy([v[0] for v in q], [v[1] for v in q])
            z = self.surf(pts[:, 0], pts[:, 1]) + 0.012
            P3 = np.c_[pts, z]
            for t in ((0, 1, 2), (0, 2, 3)):
                for i in t:
                    tri += [round(float(v), 3) for v in P3[i]]
        plots = []
        for pl in self.plots:
            plots.append({"id": pl["id"], "num": pl["num"], "ring": r3(_ccw(pl["ring"])), "zp": pl["zp"],
                          "corner": int(np.argmin([np.hypot(*(q - pl["ring"][pl["corner"]]))
                                                   for q in _ccw(pl["ring"])])),
                          "ea": r3([pl["ea"]])[0], "eb": r3([pl["eb"]])[0], "recess": list(RECESS),
                          "core_in": CORE_IN, "core": r3(_ccw(np.asarray(pl["core"].exterior.coords)[:-1]))})
        return {
            "about": "tools/rail/logements_x.py: the École polytechnique's new student housing (lot S3.2), its car "
                     "park, gardens and the boulevard's north sidewalk; zones in rail.json zones (logx:*), the ground "
                     "in `repairs`, world.json changes in `site` (patch_world.apply_site), the details for "
                     "scripts/builder/logements_x_builder.gd",
            "repairs": [self.repair()],
            "site": {"fences_gone": [self.fence_id], "clear": [r3(np.asarray(p.exterior.coords)[:-1])
                                                               for p in polys(self.site.buffer(0.3))],
                     "trees_gone": self.trees_gone, "trees_add": self.trees_new,
                     "props_moved": self.props_moved, "props_gone": self.props_dropped, "props_lift": self.props_lift,
                     "props_add": self.props_new, "buildings": self.buildings(),
                     "modules_clear": [r3(np.asarray(pl["pg"].buffer(1.5, join_style=2).exterior.coords)[:-1])
                                       for pl in self.plots]},
            "plots": plots,
            "dims": {"ground": GROUND_H, "floor": FLOOR_H, "floors": FLOORS, "height": HEIGHT, "parapet": PARAPET,
                     "wall": WALL, "white": WHITE, "sedum": SEDUM},
            "kerb": kerb_on,
            "copings": cps,
            "markings": {"white": tri},
            "bollards": self.bollards,
            "rocks": self.rocks,
            "mulch": self.mulch,
            "bays": len(self.bays),
            "lines": [{"kind": k, "w": w, "pts": r3(pts[::2] if len(pts) > 8 else pts)} for pts, w, k in self.lines],
            "car_park": {"o": r3([CP_O])[0], "d": r3([CP_D])[0], "a": [CP_A[0] - 6.0, CP_A[1] + 6.0],
                         "b": list(CP_B), "z": list(CP_Z), "rows": [list(r) for r in ROWS], "islands": [list(i) for i in ISLANDS]},
        }

    def summary(self) -> str:
        P = self.parts
        return ("logements X: site %.0f m², %d plots (pads %s m), car park %d bays (%.0f m²), paths %.0f m², lawns "
                "%.0f m², sidewalk %.0f m² (kerb within %.2f m of the road's edge), %d new trees (%d kept, %d gone), "
                "%d new props, %d moved, %d gone, %d bollards, %d boulders" % (
                    self.site.area, len(self.plots), ", ".join("%.2f" % pl["zp"] for pl in self.plots), len(self.bays),
                    P["parking"].area, P["paths"].area, P["lawn"].area, P["walk"].area, self.edge_dev,
                    len(self.trees_new), len(self.trees_kept), len(self.trees_gone), len(self.props_new),
                    len(self.props_moved), len(self.props_dropped), len(self.bollards), len(self.rocks)))


def build(world: dict, H: rg.Heights, taken=None) -> tuple:
    """(rail.json `logements_x`, its zones) for build_rail.py."""
    S = Site(world, H, taken)
    data = S.data(world)
    print(S.summary(), flush=True)
    return data, S.zones()


def _ccw(ring) -> np.ndarray:
    r = np.asarray(ring, dtype=float)
    a = 0.5 * np.sum(r[:, 0] * np.roll(r[:, 1], -1) - np.roll(r[:, 0], -1) * r[:, 1])
    return r if a > 0 else r[::-1]


def _tier(ring, z0: float, top: float, parapet: float, pwidth: float, roof: str, floating: bool, runs: list,
          style: int) -> dict:
    """A building_builder.gd tier for a CCW ring with sharp corners: mitred inward offsets, one facade run per edge
    (in `runs`, its style index), the cap triangulated."""
    r = np.asarray(ring, dtype=float)
    n = len(r)
    w, seg = [], []
    for i in range(n):
        a, p, b = r[i - 1], r[i], r[(i + 1) % n]
        e0 = (p - a) / np.linalg.norm(p - a)
        e1 = (b - p) / np.linalg.norm(b - p)
        n0 = np.array([-e0[1], e0[0]])                  # inward (left of a CCW ring)
        n1 = np.array([-e1[1], e1[0]])
        m = (n0 + n1) / (1.0 + float(n0 @ n1))
        w.append([round(float(m[0]), 4), round(float(m[1]), 4)])
        seg += [len(runs), 0.0]
        runs.append([round(float(np.linalg.norm(b - p)), 3), -1.0, 1.0, style])
    tris = []
    pg = Polygon(r)
    for t in shapely.constrained_delaunay_triangles(pg).geoms:
        idx = []
        for c in np.asarray(t.exterior.coords)[:-1]:
            idx.append(int(np.argmin(np.hypot(r[:, 0] - c[0], r[:, 1] - c[1]))))
        tris += idx
    return {"kind": "body", "z0": round(z0, 3), "top": round(top, 3), "parapet": parapet, "pwidth": pwidth,
            "bevel": 0.0, "roof": roof, "floating": floating, "rings": [r3(r)], "w": [w], "exp": [[1] * n],
            "seg": [seg], "cap": tris, "tris": list(tris)}


def _bb(g) -> Polygon:
    r = np.asarray(g["rings"][0], dtype=float)
    return box(r[:, 0].min(), r[:, 1].min(), r[:, 0].max(), r[:, 1].max())


def _halfplane(p, t, side: int, size: float = 500.0) -> Polygon:
    """The half plane on the `side` (+1: ahead, -1: behind) of the line through p across direction t."""
    t = np.asarray(t, float) / np.linalg.norm(t)
    n = np.array([-t[1], t[0]])
    p = np.asarray(p, float)
    a, b = p - n * size, p + n * size
    return Polygon([a, b, b + t * size * side, a + t * size * side])
