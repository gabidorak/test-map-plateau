"""What the railway's lots change in the map's world (godot/lots/rerB/drop.json, godot/lots/massyPalaiseau/drop.json:
tools/common/world_edits.py has the keys), decided here from the map's own world and the railway's design, applied by
the game when the map is built (godot/scripts/builder/world_edits.gd), lot rerB's first:

rerB, the RER B line and its stations:
- the trees and props in its way (build_rail.py clearance: trees out, props off the trackbed and platforms moved
  beside or out), its right-of-way fences in;
- the wall-less canopies standing on its trackbed, platforms and stairs (OSM's footbridge stair roof, a slab at knee
  height over the track) out: the railway's builder draws its own;
- Lozère's station building as the photos show it (STATION_LOOK: rail_builder.gd adds the gabled roof);
- the buildings over the tracks (over_tracks()): a station hall or footbridge reaching into the trains' gauge keeps
  only what is above TRAIN_CLEARANCE, a hut on a yard track goes;
- the map's bridge decks of the footbridges the railway builds itself (Lozère's), the markings on its hard ground.
massyPalaiseau, Massy-Palaiseau's station, its bus station and bus depot (massy_station.py, bus_station.py):
- the bus station's lanes: props there moved onto the quays or out, the map's fences across them out, its kerbs cut
  back (the zones' own ground now);
- the fences between the bus station and the tracks in;
- the halls, footbridge boxes and line 18 / TGV buildings massy_builder.gd draws instead out, the kit modules on them
  (but those of a building kept there), the map's footbridge decks there;
- the bus depot's trees and hedge (bus_depot.py greenery) in;
- the bus station's and the depot car park's lamps (bus_station.py lamps) in, as the map's street lamps
  (lamp_station_props(): breakable like them, lit by night.gd like them).

    rerB, massy = make(world, rail)      (world: the map's own world.json, as the pipeline wrote it; rail: the railway's design, lots.load())
"""
import copy

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import railgeo as rg
import mapdata as md

# The station building as the photos show it (Wikimedia Commons, "Gare Lozère RER IdF Ligne B - Palaiseau (FR91) -
# 2026-01-17"): a cream rendered pavilion, brick quoins and window surrounds, tall ground-floor windows, a slate
# gabled roof; the pipeline's guess (a grey flat-roofed "campus" box from a photo colour of confidence 0.54) goes.
# building_builder.gd has no gables: the body stops at the eaves and rail_builder.gd draws the roof (it reads this
# building's `rail_roof`).
STATION_BUILDING = "osm:w71346991"
STATION_LOOK = {"wall": "#ece2c6", "accent": "#b4683f", "roof": "#5b616b",
                "eaves": 4.6,           # m above the base: a tall ground floor and attic windows (photos)
                "rise": 2.8,            # m from the eaves to the ridge (~40°, a usual slate pitch)
                "overhang": 0.35,       # m beyond the walls
                "g": 3.2, "f": 2.6,     # ground floor and floor heights (photos: tall arched ground-floor windows)
                "floors": 1, "ground": 0, "material": 0, "windows": 1, "top": 0}   # punched, plain, render, framed
GAUGE_HALF = 1.75              # m from a track centre (godot/tools/check_world.gd)
TRAIN_CLEARANCE = 6.2           # m above the rail where a building over the line may start (catenary, its supports)
HUT_AREA = 60.0                 # m²: a smaller building on a yard track goes (a cabin on the ballast)
LAMP_QUAY_T = -6.0              # m across the bus station: lamps beyond it stand on a quay (bus_station.py QUAY)
OWN_KINDS = ("trackbed", "platform", "stairwell")   # the line's own ground: wall-less canopies on it go


def restyle_station(b: dict) -> None:
    """STATION_LOOK on the station building: its tiers end at the eaves without a parapet, punched framed windows in
    cream render with brick accents; `rail_roof` tells rail_builder.gd the gabled roof to put on top."""
    L = STATION_LOOK
    top = b["base_z"] + L["eaves"]
    b["height"] = L["eaves"]
    b["heights"]["rail"] = L["eaves"] + L["rise"]
    b["height_src"] = "rail"
    b["roof"]["shape"] = "gabled"
    b["roof"]["color"] = L["roof"]
    b["facade"].update({"color": L["wall"], "accent": L["accent"], "color_src": "rail", "levels": 1.0})
    st = b["toy"]["style"]
    st.update({"group": "station", "floors": L["floors"], "ground": L["ground"], "material": L["material"],
               "top": L["top"], "windows": L["windows"], "wall": L["wall"], "accent": L["accent"], "g": L["g"],
               "f": L["f"], "levels": 1, "wall_src": "rail", "names": ["punched", "plain", "render", "plain"]})
    for t in b["toy"]["tiers"]:
        t["top"] = round(top, 3)
        t["parapet"] = 0.0
        t["roof"] = L["roof"]
    b["rail_roof"] = {"eaves": round(top, 3), "rise": L["rise"], "overhang": L["overhang"], "slate": L["roof"],
                      "wall": L["wall"], "accent": L["accent"]}


def over_tracks(buildings: list, rail: dict) -> tuple:
    """Walled buildings reaching into the trains' gauge: one standing over a track trains run on (the alignment's,
    the yard's mains), or a station hall or footbridge over any yard track, with its roof well above the trains (a
    station hall over the cutting, as at Palaiseau) keeps only what is above TRAIN_CLEARANCE, its tiers floating
    there; a small one on a yard track is dropped; the others are left (depot sheds the yard's tracks run into).
    Changes the raised ones in place; returns (raised ids, dropped ids)."""
    A = rg.Alignment(rail["alignment"])
    sp = rail["alignment"]["spacing"]
    th = A.heading
    n = np.c_[-np.sin(th), np.cos(th)]
    lines = [(LineString(A.pts - n * sp / 2), A.s, A.z), (LineString(A.pts + n * sp / 2), A.s, A.z)]
    trains = [True, True]                       # trains run on it (the alignment's tracks, the yard's mains)
    for t in rail.get("yard", {}).get("tracks", []):
        p = np.asarray(t["pts"])
        lines.append((LineString(p), md.cumlen(p), np.asarray(t["z"])))
        trains.append(bool(t["main"]))
    tree = shapely.STRtree([ln for ln, _, _ in lines])
    lifted, dropped = [], []
    for b in buildings:
        if not b.get("walls", True) or not b["rings"]:
            continue
        pg = Polygon(b["rings"][0]).buffer(0)
        hits = [k for k in tree.query(pg.buffer(GAUGE_HALF)) if lines[k][0].distance(pg) < GAUGE_HALF]
        if not hits:
            continue
        rail_z = max(float(np.interp(lines[k][0].project(pg.centroid), lines[k][1], lines[k][2])) for k in hits)
        tiers = b.get("toy", {}).get("tiers", [])
        top = max([t["top"] for t in tiers] or [b["base_z"] + b["height"]])
        over_trains = any(trains[k] for k in hits)
        hall = b.get("kind") == "train_station"   # a station hall or footbridge over the yard
        if top - rail_z > TRAIN_CLEARANCE + 2.0 and (over_trains or hall):
            z_min = rail_z + TRAIN_CLEARANCE
            new = []
            for t in tiers:
                if t["top"] <= z_min + 0.5:
                    continue
                if t["z0"] < z_min:
                    t["z0"] = round(z_min, 3)
                    t["floating"] = True
                new.append(t)
            b["toy"]["tiers"] = new
            b["min_height"] = round(z_min - b["base_z"], 3)
            lifted.append(b["id"])
        elif pg.area < HUT_AREA and any(k >= 2 for k in hits) and not over_trains:
            dropped.append(b["id"])
    return lifted, dropped


def _zone_union(rail: dict, keep) -> shapely.Geometry:
    g = unary_union([Polygon(p[0], p[1:]).buffer(0) for z in rail["zones"] if keep(z) for p in z["polygons"]])
    shapely.prepare(g)
    return g


def lamp_station_props(bst: dict) -> list:
    """The bus station's lamps ([x, y, z of the foot]) as street lamp props, their arm over the nearest lanes: the
    quays' (on their Massy side kerb, t > LAMP_QUAY_T) towards the Massy lane, the others (sidewalk, car park) back
    across towards the station. Each stands at its plan foot height ("z"): the heightmap rises towards the retaining
    walls behind the sidewalk."""
    o = np.array(bst["frame"]["o"], float)
    d = np.array(bst["frame"]["d"], float)
    d /= np.linalg.norm(d)
    n = np.array([-d[1], d[0]])                   # across, towards the tracks
    out = []
    for k, (x, y, z) in enumerate(bst["lamps"]):
        t = float((np.array([x, y]) - o) @ n)
        arm = -n if t > LAMP_QUAY_T else n
        out.append({"id": "prop:massy-lamp:%d" % (k + 1), "kind": "street_lamp", "model": "lamp_street",
                    "x": x, "y": y, "yaw": round(float(np.degrees(np.arctan2(arm[1], arm[0]))), 1), "z": z,
                    "src": "massy:bus-station", "info": {}})
    return out


def make(world: dict, rail: dict) -> tuple:
    """(rerB's edits, massyPalaiseau's edits), as world_edits.py keys. The decisions are taken in one pass over a copy
    of the world, in the order the game applies them, so that each sees what the others left."""
    w = copy.deepcopy({k: world[k] for k in ("trees", "props", "fences", "kerbs", "buildings", "building_modules",
                                             "bridges", "markings")})
    R, M = {}, {}
    # --- rerB: the trees and props in its way
    clear = rail["clearance"]
    R["trees_gone"] = [t["id"] for t in clear["trees"]]
    R["props_gone"] = [p["id"] for p in clear["props"] if p["action"] == "dropped"]
    R["props_moved"] = {p["id"]: p["to"] for p in clear["props"] if p["action"] == "moved"}
    # --- massyPalaiseau: the bus station's lanes
    M_ = rail.get("massy", {})
    bst = M_.get("bus_station")
    if bst:
        M["props_gone"] = [p["id"] for p in bst["props"] if p["action"] == "dropped"]
        M["props_moved"] = {p["id"]: p["to"] for p in bst["props"] if p["action"] == "moved"}
        M["fences_gone"] = sorted(set(bst["fences_gone"]))
        cut = unary_union([Polygon(r).buffer(0) for r in bst["clear"]])
        cuts = []
        for kb in w["kerbs"]:
            if len(kb["pts"]) < 2 or not LineString(kb["pts"]).intersects(cut):
                continue
            rest = LineString(kb["pts"]).difference(cut)
            runs = [[[round(x, 3), round(y, 3)] for x, y in part.coords] for part in getattr(rest, "geoms", [rest])
                    if part.geom_type == "LineString" and part.length > 0.3]
            cuts.append({"from": kb["pts"][0], "to": kb["pts"][-1], "runs": runs})
        M["kerbs_cut"] = cuts
    # --- the fences: the line's right-of-way ones, Massy-Palaiseau's between the bus station and the tracks
    fence = lambda f: {"style": f["style"], "h": f["h"], "height_src": "rail", "osm": "",
                       "pts": [[round(p[0], 3), round(p[1], 3)] for p in f["pts"]], "id": f["id"]}
    R["fences_add"] = [fence(f) for f in rail["fences"]]
    M["fences_add"] = [fence(f) for f in M_.get("fences", [])]
    # --- rerB: the wall-less canopies on its own ground, Lozère's station building
    own = _zone_union(rail, lambda z: z["kind"] in OWN_KINDS)
    gone_b, changed = [], {}
    for b in w["buildings"]:
        if not b.get("walls", True) and Polygon(b["rings"][0]).intersects(own):
            gone_b.append(b["id"])
        elif b["id"] == STATION_BUILDING:
            restyle_station(b)
            changed[b["id"]] = b
    R["buildings_gone"] = list(gone_b)
    w["buildings"] = [b for b in w["buildings"] if b["id"] not in set(gone_b)]
    # --- massyPalaiseau: the halls, boxes and buildings massy_builder.gd draws, their kit modules, the decks there
    if M_:
        rep = set(M_["replaces"]["buildings"])
        gone = [b for b in w["buildings"] if b["id"].split("_rest")[0] in rep]
        M["buildings_gone"] = [b["id"] for b in gone]
        w["buildings"] = [b for b in w["buildings"] if b["id"].split("_rest")[0] not in rep]
        fp = unary_union([Polygon(b["rings"][0]).buffer(1.0) for b in gone if b["rings"]])
        # (but not those of a building kept there: the old station building beside le Lien's end)
        fp = fp.difference(unary_union([Polygon(b["rings"][0]).buffer(0.3) for b in w["buildings"]
                                        if b["rings"] and Polygon(b["rings"][0]).intersects(fp)]))
        mods = [m for m in w["building_modules"] if fp.contains(Point(m["x"], m["y"]))]
        M["modules_gone"] = sorted({(m["m"], m["x"], m["y"], m["z"]) for m in mods})
        w["building_modules"] = [m for m in w["building_modules"] if not fp.contains(Point(m["x"], m["y"]))]
        near = unary_union([Polygon(r) for r in M_["replaces"]["bridges_near"]])
        M["bridges_gone"] = [b["id"] for b in w["bridges"] if b["kind"] != "road" and near.contains(
            Point(b["pts"][len(b["pts"]) // 2][0], b["pts"][len(b["pts"]) // 2][1]))]
        w["bridges"] = [b for b in w["bridges"] if b["id"] not in set(M["bridges_gone"])]
        g = bst.get("greenery", {}) if bst else {}
        arch = world["tree_archetypes"]
        M["trees_add"] = [t for t in g.get("trees", []) if t["arch"] in arch]
        M["hedges_add"] = g.get("hedges", [])
        M["props_add"] = lamp_station_props(bst) if bst else []
    # --- rerB: the buildings over the tracks
    lifted, dropped = over_tracks(w["buildings"], rail)
    for b in w["buildings"]:
        if b["id"] in lifted:
            changed[b["id"]] = b
    R["buildings_gone"] += dropped
    R["buildings"] = [changed[i] for i in sorted(changed) if i not in set(dropped)]
    # --- rerB: the map's decks of the footbridges it builds (Lozère's), the markings on its hard ground
    own_fb = {o for fb in rail.get("footbridges", []) for o in fb["osm"]}
    R["bridges_gone"] = [b["id"] for b in w["bridges"] if b["osm"] in own_fb]
    hard = _zone_union(rail, lambda z: bool(rg.hard_of(z)))
    cuts = []
    for mk in w["markings"]:
        v = np.asarray(mk["verts"], dtype=np.float64)
        t = np.asarray(mk["tris"], dtype=np.int64).reshape(-1, 3)
        if not len(t):
            continue
        c = v[t].mean(axis=1)
        keep = ~shapely.contains_xy(hard, c[:, 0], c[:, 1])
        if keep.all():
            continue
        used, inv = np.unique(t[keep].ravel(), return_inverse=True)
        cuts.append({"src": mk.get("src", ""), "first": mk["verts"][0], "verts": np.round(v[used], 3).tolist(),
                     "tris": inv.astype(int).tolist()})
    R["markings_cut"] = cuts
    return R, M
