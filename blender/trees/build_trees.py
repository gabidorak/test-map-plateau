"""Builds the soft-toy tree models (milestone M5).

blender -b --factory-startup -P blender/trees/build_trees.py -- [--out godot/assets/trees] [--only round,sapling]
                                                                 [--preview data/review/<area>/tree_models.png]

One .glb per archetype holding `<archetype>_<variant>_lod<0..2>` meshes with the material slots
leaves / trunk / wood (the Godot builder swaps them for the toy foliage shader), plus models.json with
each model's reference height, crown radius and crown base so instances can be scaled to real trees.
The variant counts must match plateau/trees.py VARIANTS."""
import importlib
import json
import math
import sys
import time
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import treelib  # noqa: E402

ARCHETYPES = ["round", "oval", "columnar", "conifer", "weeping", "sapling"]


def args() -> dict:
    out = {"out": str(ROOT / "godot" / "assets" / "trees"), "only": "", "preview": ""}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        k, _, v = a.partition("=")
        out[k.lstrip("-")] = v
    return out


def clear_scene() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.metaballs, bpy.data.cameras, bpy.data.lights):
        for item in list(coll):
            coll.remove(item)


def export(objs, path: Path) -> None:
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_materials="EXPORT",
                              export_image_format="NONE", export_yup=True, export_apply=False)


def preview(models: dict, path: Path) -> None:
    """Contact sheet of all LOD0 models side by side (workbench render, vertex colours = AO)."""
    objs = [o for o in bpy.data.objects if o.name.endswith("_lod0")]
    x = 0.0
    for o in objs:
        r = models[o.name[:-5]]["radius"]
        o.location = (x + r, 0, 0)
        x += 2 * r + 1.5
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = x * 1.02
    cam.location = (x / 2, -60, 9)
    cam.rotation_euler = (math.radians(88), 0, 0)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (0.45, 0.75, 0.35)
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = False
    scene.render.resolution_x = 2400
    scene.render.resolution_y = max(int(2400 * 30 / x), 200)
    scene.render.filepath = str(path)
    for o in bpy.data.objects:
        o.hide_render = o.type == "MESH" and not o.name.endswith("_lod0")
    bpy.ops.render.render(write_still=True)


def main() -> None:
    a = args()
    out = Path(a["out"])
    out.mkdir(parents=True, exist_ok=True)
    only = [s for s in a["only"].split(",") if s]
    manifest = out / "models.json"
    models = json.loads(manifest.read_text())["models"] if manifest.exists() and only else {}
    clear_scene()
    mats = treelib.materials()
    t0 = time.time()
    for arch in ARCHETYPES:
        if only and arch not in only:
            continue
        specs = importlib.import_module(arch).variants()
        objs = []
        for v, spec in enumerate(specs):
            assert spec.name == f"{arch}_{v}", spec.name
            lods = [treelib.assemble(spec, lod, mats) for lod in range(3)]
            objs += lods
            info = treelib.stats(lods[0])
            info["archetype"] = arch
            info["variant"] = v
            info["lods"] = [len(o.data.polygons) for o in lods]
            models[spec.name] = info
            print(f"{spec.name}: {info} ({time.time() - t0:.0f} s)")
        export(objs, out / f"{arch}.glb")
    manifest.write_text(json.dumps({"about": "Reference sizes (m) of the tree models built by blender/trees/build_trees.py; "
                                    "instances are scaled by real height / height and crown radius / radius.",
                                    "lod_suffixes": ["_lod0", "_lod1", "_lod2"], "models": models}, indent=1))
    if a["preview"]:
        preview(models, Path(a["preview"]))
    print(f"wrote {len(models)} models to {out} ({time.time() - t0:.0f} s)")


main()
