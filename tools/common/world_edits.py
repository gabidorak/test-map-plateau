"""A lot's changes to the map's world: what it takes out of world.json, moves and adds (its drop.json, written by its
tool, godot/lots/<lot>/drop.json). The game applies them when the map is built (godot/scripts/builder/world_edits.gd,
from builder/lots.gd drop(), in the lots' order); apply() here does the same, for the tools that read the world as it
is built (apply_lots(): every lot's, in the lots' order; the changes a lot's own code makes, its script's drop(),
are the game's only), and to check a tool's edits. Only the sections the world has are changed (a tool may read a few).

Keys, all optional, applied in this order:
    trees_gone [id], trees_add [tree], hedges_add [hedge]
    props_gone [id], props_moved {id: [x, y]}, props_lift {id: lift}, props_add [prop]
    fences_gone [id], fences_add [fence]
    kerbs_clear [ring]: the kerbs cut back out of these polygons (what is left under 0.3 m dropped)
    kerbs_cut [{"from": [x, y], "to": [x, y], "runs": [[[x, y]...]...]}]: the kerb running from -> to (its first and last
        points) replaced by these runs (none: gone)
    modules_clear [ring]: the kit modules standing inside them out; modules_gone [[m, x, y, z]]: those out
    buildings_gone [id] (and their name signs), buildings [building]: each replacing the building of its id
    bridges_gone [id]
    markings_cut [{"src", "first": [x, y], "verts", "tris"}]: the marking of that src whose first vertex is `first`
        replaced (no tris: gone)
Adds skip an id the world has already: applying them twice changes nothing.
"""
import json
from pathlib import Path

from mapdata import ROOT

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep

KERB_MIN = 0.3          # m: a kerb cut back shorter than this goes
LOTS = ROOT / "godot" / "lots"


def lots() -> list:
    """Every lot's declaration (godot/lots/*/lot.json), in the order the game takes them (godot/scripts/builder/lots.gd
    all(): each parent before its children, each level by "order")."""
    every = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(LOTS.glob("*/lot.json"))]
    out = []

    def level(parent):
        for lot in sorted([x for x in every if x.get("parent") == parent], key=lambda x: (x.get("order", 0), x["id"])):
            out.append(lot)
            level(lot["id"])
    level(None)
    return out


def apply_lots(world: dict) -> dict:
    """Every lot's drop.json applied to world, in the lots' order: the world as the map is built (but for what the
    lots' own code changes)."""
    for lot in lots():
        if lot.get("drop"):
            apply(world, load(ROOT / "godot" / lot["drop"].replace("res://", "")))
    return world


def load(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write(path: Path, edits: dict, about: str) -> None:
    """drop.json (LF, compact: the game reads it once per build)."""
    out = {"about": about}
    out.update({k: v for k, v in edits.items() if v})
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes((json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))


def _add(items: list, new: list) -> list:
    have = {i.get("id") for i in items}
    return items + [i for i in new if i.get("id") not in have]


def kerb_key(pts: list) -> tuple:
    return (float(pts[0][0]), float(pts[0][1]), float(pts[-1][0]), float(pts[-1][1]))


def marking_key(mk: dict) -> tuple:
    v = mk["verts"][0] if mk["verts"] else [0.0, 0.0]
    return (str(mk.get("src", "")), float(v[0]), float(v[1]))


def apply(world: dict, e: dict) -> dict:
    """The edits e applied to world, in place (and returned): to the sections it has."""
    if "trees" in world:
        gone = set(e.get("trees_gone", []))
        world["trees"] = _add([t for t in world["trees"] if t["id"] not in gone], e.get("trees_add", []))
    if "hedges" in world:
        world["hedges"] = _add(world["hedges"], e.get("hedges_add", []))
    if "props" in world:
        _props(world, e)
    if "fences" in world:
        gone = set(e.get("fences_gone", []))
        world["fences"] = _add([f for f in world["fences"] if f["id"] not in gone], e.get("fences_add", []))
    if "kerbs" in world:
        _kerbs(world, e)
    if "building_modules" in world:
        _modules(world, e)
    if "buildings" in world:
        gone = set(e.get("buildings_gone", []))
        swap = {b["id"]: b for b in e.get("buildings", [])}
        world["buildings"] = [swap.get(b["id"], b) for b in world["buildings"] if b["id"] not in gone]
        if gone and "building_signs" in world:      # (their name signs with them)
            world["building_signs"] = [s for s in world["building_signs"]
                                       if "osm:" + str(s.get("building", "")) not in gone]
    if "bridges" in world:
        gone = set(e.get("bridges_gone", []))
        world["bridges"] = [b for b in world["bridges"] if b["id"] not in gone]
    if "markings" in world:
        _markings(world, e)
    return world


def _props(world: dict, e: dict) -> None:
    gone = set(e.get("props_gone", []))
    moved, lift = e.get("props_moved", {}), e.get("props_lift", {})
    props = []
    for p in world["props"]:
        if p["id"] in gone:
            continue
        if p["id"] in moved or p["id"] in lift:
            p = dict(p)
            if p["id"] in moved:
                p["x"], p["y"] = moved[p["id"]]
            if p["id"] in lift:
                p["lift"] = lift[p["id"]]
        props.append(p)
    world["props"] = _add(props, e.get("props_add", []))


def _kerbs(world: dict, e: dict) -> None:
    if e.get("kerbs_clear"):
        cut = unary_union([Polygon(r).buffer(0) for r in e["kerbs_clear"]])
        kerbs = []
        for kb in world["kerbs"]:
            if len(kb["pts"]) < 2 or not LineString(kb["pts"]).intersects(cut):
                kerbs.append(kb)
                continue
            rest = LineString(kb["pts"]).difference(cut)
            for part in getattr(rest, "geoms", [rest]):
                if part.geom_type == "LineString" and part.length > KERB_MIN:
                    kerbs.append(dict(kb, pts=[[round(x, 3), round(y, 3)] for x, y in part.coords]))
        world["kerbs"] = kerbs
    if e.get("kerbs_cut"):
        cuts = {(float(c["from"][0]), float(c["from"][1]), float(c["to"][0]), float(c["to"][1])): c["runs"]
                for c in e["kerbs_cut"]}
        kerbs = []
        for kb in world["kerbs"]:
            runs = cuts.get(kerb_key(kb["pts"])) if kb["pts"] else None
            if runs is None:
                kerbs.append(kb)
            else:
                kerbs += [dict(kb, pts=r) for r in runs]
        world["kerbs"] = kerbs


def _modules(world: dict, e: dict) -> None:
    if e.get("modules_clear"):
        clear = prep(unary_union([Polygon(r).buffer(0) for r in e["modules_clear"]]))
        world["building_modules"] = [m for m in world["building_modules"] if not clear.contains(Point(m["x"], m["y"]))]
    if e.get("modules_gone"):
        gone = {tuple(k) for k in e["modules_gone"]}
        world["building_modules"] = [m for m in world["building_modules"]
                                     if (m["m"], m["x"], m["y"], m["z"]) not in gone]


def _markings(world: dict, e: dict) -> None:
    if e.get("markings_cut"):
        cuts = {(c["src"], float(c["first"][0]), float(c["first"][1])): c for c in e["markings_cut"]}
        marks = []
        for mk in world["markings"]:
            c = cuts.get(marking_key(mk))
            if c is None:
                marks.append(mk)
            elif c["tris"]:
                marks.append(dict(mk, verts=c["verts"], tris=c["tris"]))
        world["markings"] = marks
