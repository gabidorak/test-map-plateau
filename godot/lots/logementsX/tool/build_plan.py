"""Lot logementsX's design (the École polytechnique's new student housing): godot/lots/logementsX/plan.json and
drop.json, made by logements_x.py (its docstring: what it lays out, its sources) from the map's own ground
(godot/world/: world.json and its heightmap). The game reads the plan through
godot/lots/logementsX/logements_x_plan.gd: the lot's terraforming (its `repairs`), its surfaces (`zones`), its
builder's details; drop.json, its removals and additions to the world (tools/common/world_edits.py), through
builder/world_edits.gd.

Run from the repository: .venv/Scripts/python.exe -I godot/lots/logementsX/tool/build_plan.py   (then rebuild the map)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "common"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import mapdata as md  # noqa: E402
import world_edits  # noqa: E402
import logements_x as lx                          # noqa: E402

OUT = ROOT / "godot" / "lots" / "logementsX" / "plan.json"
DROP = OUT.parent / "drop.json"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    world = md.load_json(md.WORLD / "world.json")
    H = md.Heights(md.WORLD, world["terrain"], world["ground_mesh"]["cell"])
    data, zones = lx.build(world, H)
    data["zones"] = zones
    site = data.pop("site")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes((json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
    world_edits.write(DROP, site, "Lot logementsX's changes to the map's world: godot/lots/logementsX/tool/build_plan.py "
                      "(the construction site's fence and trees out, its trees and props in, the props on its sidewalk "
                      "lifted, the kerbs cut back, the kit modules on its plots out, the six placeholder blocks swapped "
                      "for its buildings); keys: tools/common/world_edits.py")
    print("wrote", OUT.relative_to(ROOT), "and", DROP.relative_to(ROOT))


if __name__ == "__main__":
    main()
