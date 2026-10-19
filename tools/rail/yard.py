"""The station yard beyond the alignment (build_rail.py): where the two-track model with one centreline and a constant
track spacing stops fitting (Massy-Palaiseau: four platform tracks, the terminus tracks, the depot, the TGV line and
the RER C beside), every track is a line of its own.

- Tracks: the OSM railway tracks inside the map's ground (world.json meta.data_area) that the alignment does not
  carry, merged between switches into lines, resampled every metre and smoothed (OSM draws them in kinks); the RER B's
  tracks 1 and 2 continue the alignment's from its end (the first point is the alignment track's, the shape eases onto
  OSM's over BLEND m) and run on straight past the OSM data so that hidden trains can start there. Tracks running
  alongside the alignment (within ALONG m of its tracks: they would stand in its formation) are left out.
- Levels: the rail top, from the LiDAR ground along the track (its trackbed: the ballast top, as build_rail reads the
  alignment's), robustly smoothed; tracks 1 and 2 ease from the alignment's rail level at its end.
- Islands: OSM's platform multipolygons between two tracks (Massy-Palaiseau's two islands); the island between the
  tracks on either side over OSM's extent along them, its edges PLATFORM_EDGE from both track centres, its top
  PLATFORM_HEIGHT above the higher rail.
- Zones for patch_world.py: "yard" (the tracks' ballast strips: ground kept as it is, ballast material) and "island"
  (the raised platform: its own flat top along an axis)."""
import math

import numpy as np
from scipy.ndimage import gaussian_filter1d, median_filter

import railgeo as rg
from l93 import fwd

BLEND = 40.0                    # m over which tracks 1 and 2 ease from the alignment onto OSM's shape
ALONG = 7.0                     # m from the alignment's tracks within which another track is left out
SMOOTH = 4.0                    # m, Gaussian sigma of the track lines
LEVEL_SMOOTH = 12.0             # m, of the level profiles
HUMP = 0.35                     # m over the smooth fit of a level profile that is no trackbed (yard.level_profile)
STRIP = 1.9                     # m either side of a track centre: its ballast strip (the sleepers are 2.41 m long)
MIN_TRACK = 15.0                # m: shorter merged pieces are left out (switch stubs)


def way_line(w: dict) -> np.ndarray:
    return np.array([fwd(g["lat"], g["lon"]) for g in w["geometry"]])


def _merge(lines: list) -> list:
    """Lines (arrays) joined end to end where exactly two meet (shapely line_merge), as arrays."""
    from shapely.geometry import LineString
    from shapely.ops import linemerge
    merged = linemerge([LineString(p) for p in lines if len(p) > 1])
    return [np.asarray(g.coords) for g in getattr(merged, "geoms", [merged])]


def smooth_line(p: np.ndarray, sigma: float = SMOOTH, keep_ends: bool = True) -> np.ndarray:
    """p resampled every metre and Gaussian-smoothed (its ends held)."""
    q = rg.resample(p, 1.0)
    q = np.vstack([q, p[-1]]) if np.linalg.norm(q[-1] - p[-1]) > 0.05 else q
    if len(q) < 5:
        return q
    out = np.c_[gaussian_filter1d(q[:, 0], sigma, mode="nearest"), gaussian_filter1d(q[:, 1], sigma, mode="nearest")]
    if keep_ends:
        w = np.clip(np.minimum(np.arange(len(q)), np.arange(len(q))[::-1]) / (3 * sigma), 0, 1)[:, None]
        out = q + (out - q) * w
    return out


def headings(p: np.ndarray) -> np.ndarray:
    d = np.gradient(p, axis=0)
    return np.unwrap(np.arctan2(d[:, 1], d[:, 0]))


def level_profile(p: np.ndarray, H: rg.Heights, rail_above: float) -> np.ndarray:
    """Rail top along p: the median LiDAR ground across the track (+-0.6 m), robustly smoothed, plus rail_above."""
    h = headings(p)
    n = np.c_[-np.sin(h), np.cos(h)]
    us = np.linspace(-0.6, 0.6, 5)
    q = p[:, None, :] + n[:, None, :] * us[None, :, None]
    z = np.median(H.sample(q[..., 0].ravel(), q[..., 1].ravel()).reshape(len(p), -1), axis=1)
    z = median_filter(z, size=15, mode="nearest")
    # a railway has no humps: what stands above a smooth fit (a concourse over the tracks, a bridge the LiDAR ground
    # kept) is left out and filled from either side, three times over
    keep = np.ones(len(z), dtype=bool)
    for _ in range(3):
        idx = np.nonzero(keep)[0]
        fill = np.interp(np.arange(len(z)), idx, z[idx])
        fit = gaussian_filter1d(fill, 3 * LEVEL_SMOOTH, mode="nearest")
        keep = z - fit < HUMP
    idx = np.nonzero(keep)[0]
    z = np.interp(np.arange(len(z)), idx, z[idx])
    return gaussian_filter1d(z, LEVEL_SMOOTH, mode="nearest") + rail_above


def main_continuation(osm: dict, ref: str, A: rg.Alignment, u: float, rail_above: float, H: rg.Heights,
                      s_end: float) -> dict:
    """Track `ref` (1 or 2) from the alignment's end on: OSM's chained track from where it passes the alignment track's
    end point, eased onto from it, run on straight beyond the data (the hidden end)."""
    from build_rail import chain_track
    pts, ids = chain_track(osm, ref)
    p0 = A.point(s_end, u)
    th0 = float(A.theta(s_end))
    d = rg.cumlen(pts)
    k = int(np.argmin(np.linalg.norm(pts - p0, axis=1)))
    tail = pts[k:]
    tail = np.vstack([p0, tail[1:]]) if len(tail) > 1 else np.vstack([p0, p0 + [math.cos(th0), math.sin(th0)]])
    line = smooth_line(tail, keep_ends=False)
    line[0] = p0
    # ease from the alignment's tangent line onto OSM's shape over BLEND m
    t = np.arange(len(line), dtype=float)
    straight = p0 + np.c_[np.cos(th0) * t, np.sin(th0) * t]
    w = np.clip(t / BLEND, 0, 1)
    w = (w * w * (3 - 2 * w))[:, None]
    line = straight + (line - straight) * w
    # on straight past the data
    from build_rail import EXTEND_END
    end_th = math.atan2(*(line[-1] - line[-20])[::-1])
    ext = line[-1] + np.c_[np.cos(end_th), np.sin(end_th)] * np.arange(1.0, EXTEND_END + 1.0)[:, None]
    line = np.vstack([line, ext])
    z = level_profile(line, H, rail_above)
    z_end = float(A.level(s_end))
    wz = np.clip(np.arange(len(z)) / BLEND, 0, 1)
    z = z_end + (z - z_end) * (wz * wz * (3 - 2 * wz))      # from the alignment's rail level at its end
    return {"ref": ref, "osm": ids, "pts": line, "z": z, "heading": headings(line),
            "maxspeed": way_speeds(osm, line, ids), "rer": True, "main": True}


def way_speeds(osm: dict, line: np.ndarray, ids: list) -> np.ndarray:
    """km/h along `line`: the maxspeed of the nearest of the ways `ids` (the line speed where untagged)."""
    from build_rail import LINE_SPEED
    from shapely.geometry import LineString, Point
    from shapely.strtree import STRtree
    ws = [(LineString(way_line(osm["ways"][i])), float(osm["ways"][i].get("tags", {}).get("maxspeed", LINE_SPEED)))
          for i in ids if i in osm["ways"]]
    tree = STRtree([w[0] for w in ws])
    out = np.full(len(line), LINE_SPEED)
    for k in range(0, len(line)):
        j = int(tree.nearest(Point(line[k])))
        if ws[j][0].distance(Point(line[k])) < 6.0:
            out[k] = ws[j][1]
    return out


def build(osm: dict, A: rg.Alignment, spacing: float, rail_above: float, H: rg.Heights, data_area, main_ids: set,
          s_end: float, platform_edge: float, platform_height: float) -> dict:
    """The yard: tracks (the two main continuations first) and islands."""
    from shapely.geometry import LineString, Point, Polygon
    from shapely.ops import unary_union
    mains = [main_continuation(osm, "1", A, -spacing / 2, rail_above, H, s_end),
             main_continuation(osm, "2", A, spacing / 2, rail_above, H, s_end)]
    main_lines = unary_union([LineString(m["pts"]) for m in mains])
    al_tracks = unary_union([LineString(A.point(np.arange(0, s_end, 2.0), np.full(int(math.ceil(s_end / 2.0)), u)))
                             for u in (-spacing / 2, spacing / 2)])
    area = data_area.buffer(20.0)
    lines, osm_of = [], []
    for wid, w in osm["ways"].items():
        t = w.get("tags", {})
        if t.get("railway") not in ("rail", "light_rail") or wid in main_ids or "geometry" not in w:
            continue
        p = way_line(w)
        ln = LineString(p)
        if not ln.intersects(area):
            continue
        lines.append(p)
        osm_of.append(wid)
    tracks = []
    for p in _merge(lines):
        ln = LineString(p).intersection(area)
        for part in getattr(ln, "geoms", [ln]):
            if part.geom_type != "LineString" or part.length < MIN_TRACK:
                continue
            q = np.asarray(part.coords)
            sm = smooth_line(q)
            # alongside the alignment's tracks (in its formation) or over a main continuation: left out
            mid = LineString(sm)
            if mid.distance(al_tracks) < ALONG and LineString(sm).buffer(ALONG).intersection(al_tracks).length > 0.5 * mid.length:
                continue
            if mid.buffer(1.0).intersection(main_lines).length > 0.8 * mid.length:
                continue
            ids = [i for i, w in zip(osm_of, lines) if LineString(w).distance(mid) < 1.0 and
                   LineString(w).buffer(2.0).intersection(mid).length > 1.0]
            refs = {osm["ways"][i].get("tags", {}).get("railway:track_ref", "") for i in ids} - {""}
            rer = any(osm["ways"][i].get("tags", {}).get("name") == "Ligne de Sceaux" or "RER B" in
                      osm["ways"][i].get("tags", {}).get("name", "") or osm["ways"][i].get("tags", {}).get(
                          "railway:track_ref") in ("A", "B") for i in ids)
            tracks.append({"ref": ",".join(sorted(refs)), "osm": sorted(ids), "pts": sm,
                           "z": level_profile(sm, H, rail_above), "heading": headings(sm), "rer": rer,
                           "main": False})
    tracks = mains + tracks
    for k, tr in enumerate(tracks):
        tr["id"] = "yard:%s" % ("main" + tr["ref"] if tr["main"] else str(k))
    islands = build_islands(osm, tracks, platform_edge, platform_height, data_area)
    return {"tracks": tracks, "islands": islands, "s_start": s_end}


def build_islands(osm: dict, tracks: list, edge: float, height: float, data_area) -> list:
    """OSM's platform multipolygons standing between two yard tracks: the island between them, edges `edge` from
    both centres, over OSM's extent along them."""
    from shapely.geometry import LineString, Point, Polygon
    from shapely.ops import linemerge, polygonize, unary_union
    out = []
    lines = [LineString(t["pts"]) for t in tracks]
    for rid, r in osm.get("relations", {}).items():
        t = r.get("tags", {})
        if t.get("railway") != "platform" and t.get("public_transport") != "platform":
            continue
        outer = [LineString([fwd(g["lat"], g["lon"]) for g in m["geometry"]]) for m in r.get("members", [])
                 if m.get("role") == "outer" and m.get("type") == "way" and m.get("geometry")]
        if not outer:
            continue
        merged = unary_union(outer)
        polys = list(polygonize(merged if merged.geom_type == "LineString" else linemerge(merged)))
        if not polys:
            continue
        pg = max(polys, key=lambda g: g.area)
        if not pg.intersects(data_area):
            continue
        c = pg.representative_point()
        near = sorted(range(len(tracks)), key=lambda k: lines[k].distance(c))
        # the two nearest tracks on opposite sides of the island, both close to it
        a = near[0]
        ta = tracks[a]
        ka = int(np.argmin(np.linalg.norm(ta["pts"] - [c.x, c.y], axis=1)))
        na = np.array([-math.sin(ta["heading"][ka]), math.cos(ta["heading"][ka])])
        side_a = math.copysign(1.0, float(np.dot([c.x - ta["pts"][ka][0], c.y - ta["pts"][ka][1]], na)))
        b = None
        for k in near[1:6]:
            tb = tracks[k]
            kb = int(np.argmin(np.linalg.norm(tb["pts"] - [c.x, c.y], axis=1)))
            if lines[k].distance(c) > 15.0:
                break
            if math.copysign(1.0, float(np.dot([tb["pts"][kb][0] - c.x, tb["pts"][kb][1] - c.y], na))) == side_a:
                b = k
                break
        if b is None:
            continue
        # extent along track a: OSM's outline projected on it
        la = lines[a]
        ss = [la.project(Point(q)) for q in pg.exterior.coords]
        s0, s1 = min(ss), max(ss)
        sa = np.arange(s0, s1 + 0.01, 1.0)
        pa = np.array([la.interpolate(s).coords[0] for s in sa])
        ha = np.interp(sa, rg.cumlen(ta["pts"]), ta["heading"])
        nrm = np.c_[-np.sin(ha), np.cos(ha)] * side_a
        edge_a = pa + nrm * edge
        lb = lines[b]
        pb = np.array([lb.interpolate(lb.project(Point(q))).coords[0] for q in pa])
        tb = tracks[b]
        dirb = pa - pb
        dirb /= np.maximum(np.linalg.norm(dirb, axis=1, keepdims=True), 1e-9)
        edge_b = pb + dirb * edge
        ring = np.vstack([edge_a, edge_b[::-1]])
        isl = Polygon(ring).buffer(0)
        if isl.is_empty or isl.area < 50:
            continue
        za = np.interp(sa, rg.cumlen(ta["pts"]), ta["z"])
        zb = np.array([np.interp(lb.project(Point(q)), rg.cumlen(tb["pts"]), tb["z"]) for q in pb])
        top = float(np.median(np.maximum(za, zb))) + height
        spine = (edge_a + edge_b) / 2
        name = t.get("name", "")
        out.append({"id": "platform:%s:%d" % (name.lower().replace(" ", "-") or "island", len(out) + 1),
                    "osm": "r%d" % rid, "name": name, "tracks": [ta["id"], tb["id"]],
                    "refs": [ta["ref"], tb["ref"]], "ring": np.asarray(isl.exterior.coords)[:-1],
                    "edges": [{"track": ta["id"], "pts": edge_a}, {"track": tb["id"], "pts": edge_b}],
                    "spine": spine, "top": top, "length": float(s1 - s0),
                    "tags": {k: v for k, v in t.items() if k not in ("name", "type")}})
    return out


def zones(yard: dict, taken, data_area=None) -> list:
    """patch_world zones: the islands (axis zones: their flat top along the spine) and the tracks' ballast strips
    ("yard": the ground kept, ballast material), outside what the alignment's zones already take (`taken`)."""
    import shapely
    from shapely.geometry import LineString, Polygon
    from shapely.ops import unary_union
    out = []
    used = taken
    for isl in yard["islands"]:
        pg = shapely.set_precision(Polygon(isl["ring"]).buffer(0), 0.001)
        g = pg if used is None else shapely.set_precision(pg.difference(used), 0.001)
        used = pg if used is None else unary_union([used, pg])
        polys = [x for x in getattr(g, "geoms", [g]) if x.geom_type == "Polygon" and x.area > 0.05]
        if polys:
            out.append({"kind": "island", "side": None, "source": "osm:" + isl["osm"],
                        "polygons": [[np.asarray(p.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1]
                                                                            for h in p.interiors] for p in polys],
                        "axis": isl["spine"], "axis_z": np.full(len(isl["spine"]), isl["top"]), "portals": []})
    strips = unary_union([LineString(t["pts"]).buffer(STRIP, cap_style=2) for t in yard["tracks"]])
    if data_area is not None:                   # on the map's ground only (the mains run on past it, hidden)
        strips = strips.intersection(data_area)
    g = strips if used is None else strips.difference(used)
    g = shapely.set_precision(g, 0.001)
    polys = [x for x in getattr(g, "geoms", [g]) if x.geom_type == "Polygon" and x.area > 0.05]
    if polys:
        out.append({"kind": "yard", "side": None, "source": "rail",
                    "polygons": [[np.asarray(p.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in p.interiors]
                                 for p in polys]})
    return out
