"""Puts the 4606 on the Atlantis bus station's new lanes (rail.json massy bus_station routes, bus_station.py):
godot/world/bus_routes.json, in place.

    .venv/Scripts/python tools/rail/bus_routes.py        (after build_rail.py; ~2 s; running it again changes nothing)
    [--rail=rail.json --routes=in.json --out=out.json]  (to try it on other files)

The bus routes come from the map pipeline (plateau/transit.py), which is not in this repository, so they are patched:
the 4606's two routes keep their way up to JOIN m outside the bus station's south-west end (s along the station's axis,
bus_station.py), and from there on into the station they take bus_station.paths(): out from the RER side lane
between Îlots C and B (where the buses coming in lay over; the bus depot beside the station is the bus job's,
bus_depot.py), the stop at Îlot B, the turnaround, the Massy side lane out (Christ de Saclay way); in along the RER
side lane to the terminus (the Massy-Palaiseau way). A cubic joins the two. Every per-point field (`v` the planned
speeds, `room`, `decks`) and every field along the route (`stops`, `lights`, `yields`, `turns`) is cut and shifted
with it; the new stretch gets its own (speeds from its curvature, the stop at Îlot B, the indicators at its turn).
The route's file is written with LF line ends (godot/world/*.json)."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bus_station as bst  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ROUTES = ROOT / "godot/world/bus_routes.json"
RAIL = ROOT / "godot/world/rail.json"
OUT, IN = "4606:2393305", "4606:2393303"     # Gare de Massy - Palaiseau -> Christ de Saclay, and back
JOIN = 13.0                     # m outside the bus station's south-west end the old way is kept up to
V_STATION = 8.0                 # m/s at most in the bus station (~30 km/h)
A_LAT = 1.2                     # m/s² round the curves
A_LONG = 0.8                    # m/s² speeding up and slowing down between the planned speeds
ROOM = 2.0                      # m to the kerb beside the bus in the station (route "room")


def resample(p: np.ndarray, step: float) -> np.ndarray:
    d = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
    s = np.arange(0.0, d[-1] + 1e-9, step)
    return np.c_[np.interp(s, d, p[:, 0]), np.interp(s, d, p[:, 1])]


def hermite(a, ta, b, tb, n=40) -> np.ndarray:
    """A cubic from a (heading ta) to b (heading tb)."""
    L = np.linalg.norm(b - a)
    u = np.linspace(0, 1, n)[:, None]
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    return h00 * a + h10 * ta * L + h01 * b + h11 * tb * L


def unit(v):
    return v / max(np.linalg.norm(v), 1e-9)


def speeds(p: np.ndarray, vmax: np.ndarray) -> np.ndarray:
    """Planned speeds along p (1 m apart): the curvature's, at most vmax."""
    n = len(p)
    v = vmax.copy()
    for i in range(2, n - 2):
        a, b, c = p[i - 2], p[i], p[i + 2]
        ab, bc, ac = np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(c - a)
        area2 = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
        if area2 > 1e-6:
            v[i] = min(v[i], math.sqrt(A_LAT * ab * bc * ac / (2 * area2)))
    return np.maximum(v, 2.5)


def smooth(v: list, step: float, lo: int, hi: int) -> None:
    """Speeds changing at A_LONG at most, from lo to hi and back (in place)."""
    for i in range(max(lo, 1), hi):
        v[i] = min(v[i], math.sqrt(v[i - 1] ** 2 + 2 * A_LONG * step))
    for i in range(hi - 2, lo - 1, -1):
        v[i] = min(v[i], math.sqrt(v[i + 1] ** 2 + 2 * A_LONG * step))


def runs(vals: list) -> list:
    out = []
    for x in vals:
        if out and out[-1][1] == x:
            out[-1][0] += 1
        else:
            out.append([1, x])
    return out


def unruns(r: list) -> list:
    return [x for n, x in r for _ in range(int(n))]


def frame_s(p) -> np.ndarray:
    return bst.st(np.asarray(p))[..., 0]


def patch_out(r: dict, B: dict) -> None:
    """The way out: the station's path, then the old way from JOIN m past the station's end."""
    step = float(r["step"])
    P = np.asarray(r["pts"], dtype=np.float64)
    s_join = bst.ENDS[0] - JOIN
    fs = frame_s(P)
    j = int(np.argmax(fs < s_join))            # the old way's first point past the join (south-west of it)
    head = np.asarray(B["routes"]["out"], dtype=np.float64)
    a, b = head[-1], P[j]
    blend = hermite(a, unit(head[-1] - head[-4]), b, unit(P[j + 3] - P[j]))
    new = resample(np.vstack([head, blend[1:-1], P[j:j + 1]]), step)
    n_new = len(new)                            # its last point is P[j]
    shift = (n_new - 1) - j
    pts = np.vstack([new[:-1], P[j:]])
    hs = frame_s(new)
    vmax = np.full(len(new), V_STATION)
    vmax[hs < bst.ENDS[0]] = float(r["v"][j])
    v_new = speeds(new, vmax).tolist()
    v = v_new[:-1] + list(r["v"][j:])
    smooth(v, step, 0, min(len(v), n_new + 150))
    room = unruns(r["room"])
    room = [ROOM] * (n_new - 1) + room[j:]
    _finish(r, pts, v, room, j, shift, B, out=True)


def patch_in(r: dict, B: dict) -> None:
    """The way in: the old way up to JOIN m before the station's end, then the station's path."""
    step = float(r["step"])
    P = np.asarray(r["pts"], dtype=np.float64)
    s_join = bst.ENDS[0] - JOIN
    fs = frame_s(P)
    j = len(P) - 1 - int(np.argmax(fs[::-1] < s_join))   # the old way's last point before the join
    tail = np.asarray(B["routes"]["in"], dtype=np.float64)
    a, b = P[j], tail[0]
    blend = hermite(a, unit(P[j] - P[j - 3]), b, unit(tail[3] - tail[0]))
    new = resample(np.vstack([P[j:j + 1], blend[1:-1], tail]), step)     # its first point is P[j]
    pts = np.vstack([P[:j], new])
    vmax = np.full(len(new), V_STATION)
    vmax[0] = float(r["v"][j])
    v_new = speeds(new, vmax).tolist()
    v = list(r["v"][:j]) + v_new
    v[-1] = min(v[-1], 2.5)
    smooth(v, step, max(0, j - 150), len(v))
    room = unruns(r["room"])
    room = room[:j] + [ROOM] * len(new)
    _finish(r, pts, v, room, j, 0, B, out=False)


def _finish(r: dict, pts, v, room, j: int, shift: int, B: dict, out: bool) -> None:
    """The fields along the route: the old ones on the kept way (shifted by `shift` m on the way out), the new
    stretch's own."""
    step = float(r["step"])
    keep = (lambda s: s >= j * step) if out else (lambda s: s <= j * step)
    for key in ("stops", "lights", "yields"):
        r[key] = [dict(e, s=round(float(e["s"]) + shift * step, 2)) for e in r.get(key, []) if keep(float(e["s"]))]
    r["turns"] = [[round(t[0] + shift * step, 1), round(t[1] + shift * step, 1), t[2]] for t in r.get("turns", [])
                  if (t[1] >= j * step if out else t[0] <= j * step)]
    if "decks" in r:
        r["decks"] = [[int(d[0]) + shift, d[1]] for d in r["decks"] if (int(d[0]) >= j if out else
                                                                       int(d[0]) + len(d[1]) <= j)]
    P = np.asarray(pts)
    seg = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]

    def s_of(q, lo=0, hi=None):
        hi = len(P) if hi is None else hi
        d = np.linalg.norm(P[lo:hi] - np.asarray(q)[:2], axis=1)
        return float(seg[lo + int(d.argmin())])

    R = B["routes"]
    n_head = len(P) - (len(r["pts"]) - j) if out else len(P)
    lo, hi = (0, n_head) if out else (j, len(P))
    if out:
        r["stops"].insert(0, {"s": round(s_of(R["stop"]["at"], lo, hi), 2), "name": R["stop"]["name"],
                              "pole": R["stop"]["pole"]})
        g = R.get("give_way")
        if g:
            r["yields"].insert(0, {"s": round(s_of(g["at"], lo, hi), 2), "x": g["centre"][0], "y": g["centre"][1],
                                   "stop": False, "why": "give_way", "r": 6.0, "arms": [g["arm"]]})
        new_turns = [[round(s_of(t["from"], lo, hi), 1), round(s_of(t["to"], lo, hi), 1), t["dir"]] for t in R["turns"]]
        r["turns"] = new_turns + r["turns"]
    r["pts"] = [[round(float(x), 2), round(float(y), 2)] for x, y in P]
    r["v"] = [math.ceil(float(x) * 10.0 - 1e-6) / 10.0 for x in v]     # up: running it again changes nothing
    r["room"] = runs([float(x) for x in room])
    r["length"] = float(len(P) - 1) * step
    assert len(r["v"]) == len(r["pts"]) == sum(n for n, _ in r["room"]), (len(r["v"]), len(r["pts"]))


def main() -> None:
    opt = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    rail = json.loads(Path(opt.get("rail", RAIL)).read_text(encoding="utf-8"))
    B = (rail["massy"] if "massy" in rail else rail).get("bus_station")
    if not B:
        sys.exit("rail.json has no massy bus_station: run build_rail.py first")
    data = json.loads(Path(opt.get("routes", ROUTES)).read_text(encoding="utf-8"))
    before = {k: (len(data["routes"][k]["pts"]), data["routes"][k]["length"]) for k in (OUT, IN)}
    patch_out(data["routes"][OUT], B)
    patch_in(data["routes"][IN], B)
    Path(opt.get("out", ROUTES)).write_bytes(json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    for k in (OUT, IN):
        r = data["routes"][k]
        print("%s: %d -> %d points, %.0f -> %.0f m; stops %s" % (k, before[k][0], len(r["pts"]), before[k][1],
                                                                r["length"], [(s["name"], s["s"]) for s in r["stops"][:2]]))


if __name__ == "__main__":
    main()
