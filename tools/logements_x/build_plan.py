"""Lot logementsX's design (the École polytechnique's new student housing): godot/data/logementsX/plan.json, made by
logements_x.py (its docstring: what it lays out, its sources) from the map's own ground (godot/world/base/: world.json
and its heightmap), clear of the railway's zones (godot/world/rail.json). The game reads it through
godot/scripts/logementsX/logements_x_plan.gd: the lot's terraforming (its `repairs`), its removals and additions to the
world (`site`), its surfaces (`zones`), its builder's details.

Run from the repository: .venv/Scripts/python.exe -I tools/logements_x/build_plan.py   (then rebuild the map)
"""
import json
import sys
from pathlib import Path

from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "rail"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import railgeo as rg                              # noqa: E402
import logements_x as lx                          # noqa: E402

OUT = ROOT / "godot" / "data" / "logementsX" / "plan.json"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    rg.ensure_base()
    world = rg.load_json(rg.BASE / "world.json")
    H = rg.Heights(rg.BASE, world["terrain"], world["ground_mesh"]["cell"])
    rail = rg.load_json(rg.WORLD / "rail.json")
    taken = unary_union([Polygon(pg[0], pg[1:]) for z in rail["zones"] if not str(z.get("source", "")).startswith("logx:")
                         for pg in z["polygons"]])
    data, zones = lx.build(world, H, taken)
    data["zones"] = zones
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes((json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
