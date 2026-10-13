"""Builds the building kit (milestone M7).

blender -b --factory-startup -P blender/building_kit/build_kit.py -- [--out godot/assets/building_kit]
                                                                     [--preview data/review/<area>/kit_models.png]

One .glb with one mesh object per module (blender/building_kit/kit.py) plus kit.json: size, bounds and material
slots of every module (the Godot building builder reads it). Same finishing as the street furniture (toylib:
bevels, weighted normals, baked vertex AO; COLOR = toy colour + AO)."""
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "props"))
import kit  # noqa: E402
import toylib  # noqa: E402
from build_props import args, clear_scene, export, preview  # noqa: E402


def main() -> None:
    a = args()
    out = Path(a["out"] if a["out"] != str(ROOT / "godot" / "assets" / "props") else ROOT / "godot" / "assets" / "building_kit")
    out.mkdir(parents=True, exist_ok=True)
    clear_scene()
    t0 = time.time()
    objs, models = [], {}
    for name, fn in kit.MODELS.items():
        m = fn()
        obj = toylib.finish(m)
        info = toylib.stats(obj, m)
        info["glb"] = "kit.glb"
        models[name] = info
        objs.append(obj)
    export(objs, out / "kit.glb")
    (out / "kit.json").write_text(json.dumps({
        "about": "Building kit modules built by blender/building_kit/build_kit.py. Blender model space: metres, z up, "
                 "front -Y (Godot +Z after import); wall modules have their back on y = 0. Stretched per instance.",
        "models": models}, indent=1))
    if a["preview"]:
        preview(objs, Path(a["preview"]))
    print(f"wrote {len(models)} modules, {sum(len(o.data.polygons) for o in objs):,} triangles to {out} ({time.time() - t0:.1f} s)")


main()
