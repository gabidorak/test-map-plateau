"""Builds the soft-toy street furniture models (milestone M6).

blender -b --factory-startup -P blender/props/build_props.py -- [--out godot/assets/props] [--only bench_back,sign_B1]
                                                                 [--preview data/review/<area>/prop_models.png]

Reads pipeline/props_catalog.toml for the models and sign faces the pipeline can place and fails if one has no
recipe. Builds them with toylib (bevelled parts, weighted normals, baked vertex AO) and exports one .glb per
recipe module (furniture, bins, equipment, barriers, signs) holding one mesh object per model, plus props.json:
size, bounds, colliders, anchors, view range and material slots of every model (the Godot builder reads it)."""
import json
import math
import sys
import time
import tomllib
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import barriers  # noqa: E402
import bins  # noqa: E402
import equipment  # noqa: E402
import furniture  # noqa: E402
import signs  # noqa: E402
import toylib  # noqa: E402

MODULES = {"furniture": furniture.MODELS, "bins": bins.MODELS, "equipment": equipment.MODELS, "barriers": barriers.MODELS}
FIXED = {"bus_shelter", "bus_pole", "bench_back", "bin_vigipirate", "traffic_light_car", "traffic_light_ped", "sign_pole"}


def args() -> dict:
    out = {"out": str(ROOT / "godot" / "assets" / "props"), "only": "", "preview": ""}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        k, _, v = a.partition("=")
        out[k.lstrip("-")] = v
    return out


def required(cat: dict) -> set:
    """Every model the pipeline can place (same rule as plateau/props.py catalog_models) and the fence pieces."""
    out = set(FIXED)
    for e in cat["prop"]:
        names = [e.get("model", ""), *e.get("model_on", {}).values()]
        for w in e.get("when", []):
            names += [w.get("model", ""), *w.get("model_on", {}).values()]
        out |= {n for n in names if n and not n.startswith("@")}
    for post, panel in barriers.FENCES.values():
        out |= {n for n in (post, panel) if n}
    return out


def clear_scene() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for item in list(coll):
            coll.remove(item)


def export(objs, path: Path) -> None:
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_materials="EXPORT",
                              export_image_format="NONE", export_yup=True, export_apply=False)


def preview(objs, path: Path) -> None:
    """Contact sheet: every model scaled to its cell on a wall of cells, three-quarter front view, workbench
    render with the baked colours (AO not shown)."""
    objs = sorted(objs, key=lambda o: (o.name.startswith("sign_"), o.name))
    cols = 14
    cell = 2.0
    for i, o in enumerate(objs):
        d = o.dimensions
        s = 1.6 / max(d.x, d.z, 1e-3)
        o.scale = (s, s, s)
        o.rotation_euler = (0, 0, math.radians(-30))
        o.location = ((i % cols) * cell, 0, -(i // cols) * cell - 0.8)
    rows = (len(objs) + cols - 1) // cols
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    w, h = cols * cell, rows * cell
    cam.data.ortho_scale = max(w, h * 1.6) * 1.02
    cam.location = (w / 2 - cell / 2, -40, -h / 2 + cell / 2 + 3.0)
    cam.rotation_euler = (math.radians(86), 0, 0)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_shadows = False
    scene.render.resolution_x = 2800
    scene.render.resolution_y = 1750
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    a = args()
    out = Path(a["out"])
    out.mkdir(parents=True, exist_ok=True)
    cat = tomllib.loads((ROOT / "pipeline" / "props_catalog.toml").read_text())
    need = required(cat)
    have = {n for models in MODULES.values() for n in models}
    missing = sorted(need - have)
    if missing:
        sys.exit(f"no recipe for models {missing}: add them to blender/props/*.py")
    only = [s for s in a["only"].split(",") if s]
    manifest = out / "props.json"
    old = json.loads(manifest.read_text()) if manifest.exists() and only else {"models": {}, "faces": {}}
    clear_scene()
    t0 = time.time()
    all_objs = []
    groups = {name: {n: fn for n, fn in models.items()} for name, models in MODULES.items()}
    groups["signs"] = {n: (lambda m=m: m) for n, m in signs.build_faces(cat["signs"]["faces"]).items()}
    if only:
        groups = {g: ms for g, ms in groups.items() if any(n in only for n in ms)}
    for group, models in groups.items():
        objs = []
        for name, fn in models.items():
            m = fn()
            assert m.name == name, (m.name, name)
            obj = toylib.finish(m)
            info = toylib.stats(obj, m)
            info["glb"] = f"{group}.glb"
            (old["faces"] if group == "signs" else old["models"])[name] = info
            objs.append(obj)
        export(objs, out / f"{group}.glb")
        all_objs += objs
        print(f"{group}: {len(objs)} models, {sum(len(o.data.polygons) for o in objs):,} triangles ({time.time() - t0:.0f} s)")
    manifest.write_text(json.dumps({
        "about": "Street furniture models built by blender/props/build_props.py. Blender model space: metres, z up, "
                 "origin on the ground, front -Y (Godot +Z after import). Colliders: box = centre + size, cyl = base "
                 "centre + radius + height. Faces: road sign faces, origin at the shape centre, back at y = +0.012.",
        "models": old["models"], "faces": old["faces"]}, indent=1))
    if a["preview"]:
        preview(all_objs, Path(a["preview"]))
    print(f"wrote {len(old['models'])} models and {len(old['faces'])} sign faces to {out} ({time.time() - t0:.0f} s)")


if __name__ == "__main__":
    main()
