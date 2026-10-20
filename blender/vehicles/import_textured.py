"""Turns a ready-made car model that comes with its own PBR textures (a set of maps per part) into a drivable car with
the parts and cab file of import_car.py's, so scripts/car.gd drives it and shows its cab view: the 1928 Mercedes
(an SSK-type tourer with its hood up) of ref/mercedes_1928 ("mercedes 1928.rar").

blender -b --factory-startup -P blender/vehicles/import_textured.py -- [--car=mercedes_1928]
                                                                       [--out_dir=godot/assets/cars] [--preview=dir]
                                                                       [--list=Glass,Salon]

The 3ds Max OBJ (no units, Y up) has one group per part (Body01, Wing, Salon ..., Wheel_F_L ...), each UV-mapped onto
its own texture set (Textures/<set>_Diffuse02: the metallic workflow's base colour, _Normal: OpenGL, _Roughness,
_Metallic, _AO). Its groups are scaled into the frame of build_car.py (metres, z up, front = -Y, left = +X, origin on
the ground under the middle of the car) and split into the parts car.gd needs, by group and, for a few, by loose piece
("island", picked by where it sits: boxes in that frame, per car in CARS):
- the four wheels (origin at the wheel centre; the spare wheels stay on the body);
- "steering" (origin at the hub, local Z up the column to the driver, +Y at 12 o'clock);
- the lamps, from the glass's flat lenses: the head lamps', the wing lamps' and the scuttle lamps' take the material
  "headlight" (car.gd lights them at night); the rear amber ones are indicator_left / indicator_right, the rear red
  ones light in two bands, brake_lights below and "taillight" above; the bulbs behind them go;
- "body", the rest; the number plates are blank ("plate"). Small detailed pieces can keep every triangle (CARS
  "keep": the maker's three-pointed stars, the bonnet mascot and the rear lamps' badges); CARS "drop" hides pieces,
  "patches" paints discs out of a set's maps (car_textures.py).
Each part keeps its set's textures, downscaled (CARS "sets": sizes) by car_textures.py in the pipeline's venv:
base colour, normal map and the glTF occlusion-roughness-metallic map. The painted sets are named paint_* (car.gd gives
them a clear coat); the glass is see-through. Each group is decimated (CARS "ratio"; the source has 570k triangles)
and shaded anew (smooth up to 40 degrees, normals weighted by face area).
Writes <out_dir>/<key>/: <key>.gltf + .bin (glTF with separate files: Blender exports the materials plain, then the
textures go into the .gltf, so the JPEGs are used as they are), the textures with their Godot .import settings
(VRAM compressed, mipmaps, normal maps as such), and <key>.json (wheels, lamps, cab, as import_car.py writes).
--list prints the islands of those groups in the car frame (for the boxes); --preview renders build_car.py's views."""
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_car as bc     # noqa: E402  (palette, mat(), join, preview)
import import_car as ic    # noqa: E402  (islands, set_faces, split)

ROOT = bc.ROOT
PYTHON = next((p for p in (ROOT / ".venv" / "bin" / "python", ROOT / ".venv" / "Scripts" / "python.exe") if p.exists()),
              Path("python3"))                  # the pipeline's venv, with Pillow and numpy (car_textures.py)

# boxes: ((x0, y0, z0), (x1, y1, z1)) in the car frame; mirrored to the right side (-X) unless said otherwise
CARS = {
    "mercedes_1928": {
        "obj": "ref/mercedes_1928/Mercedes_1928_OBJ.obj",
        "textures": "ref/mercedes_1928/Textures",
        "scale": 1 / 187,                   # the model's units: a 2.95 m wheelbase (Mercedes-Benz SSK), 0.88 m tyres
        "wheels": {"Wheel_F_L": "wheel_front_left", "Wheel_F_R": "wheel_front_right",
                   "Wheel_B_L": "wheel_rear_left", "Wheel_B_R": "wheel_rear_right"},
        "set_of": {"Wheel_F_L": "Wheel", "Wheel_F_R": "Wheel", "Wheel_B_L": "Wheel", "Wheel_B_R": "Wheel",
                   "Wheel_01": "Wheel", "Wheel_02": "Wheel"},          # other groups: their own set
        # texture set -> base colour, normal map, occlusion-roughness-metallic sizes (px; the sources are 1 to 4k)
        "sets": {"Body01": (2048, 1024, 1024), "Wing": (2048, 1024, 1024), "Salon": (2048, 1024, 1024),
                 "Body02": (1024, 512, 512), "Door": (1024, 512, 512), "Awning": (1024, 512, 512),
                 "Frame": (1024, 512, 512), "Wheel": (1024, 1024, 512), "Wire01": (1024, 512, 512),
                 "Wire02": (512, 256, 256), "Fore_Suspension": (512, 256, 256),
                 "Back_Suspension": (512, 256, 256), "Glass": (512, 256, 256)},
        "paint": ["Body01", "Wing", "Door"],            # the yellow panels: paint_* materials
        "glass": {"Glass": 0.25},                       # see-through sets: alpha
        "plain": {"Number": "plate"},                   # groups in a palette material (the plates: blank)
        # decimation per group (default 1); the steering wheel its own
        "ratio": {"Frame": 0.2, "Salon": 0.25, "Wing": 0.25, "Wire01": 0.2, "Body01": 0.4, "Awning": 0.3,
                  "Door": 0.3, "Fore_Suspension": 0.25, "Back_Suspension": 0.25, "Wire02": 0.25, "Body02": 0.5,
                  "Wheel_F_L": 0.2, "Wheel_F_R": 0.2, "Wheel_B_L": 0.2, "Wheel_B_R": 0.2,
                  "Wheel_01": 0.06, "Wheel_02": 0.06, "steering": 0.5},
        # islands inside keep every triangle (boxes not mirrored; decimated, small pieces lose their shape): the
        # three-pointed stars, the bonnet mascot (star and ring) and the badge between the lenses of each rear lamp
        # (a raised star, a ring and a disc with the star embossed)
        "keep": [("Body01", ((-0.08, -1.66, 1.24), (0.08, -1.60, 1.38))),
                 ("Frame", ((0.65, 1.72, 0.66), (0.742, 1.733, 0.75))),
                 ("Frame", ((-0.742, 1.72, 0.66), (-0.65, 1.733, 0.75)))],
        "steering": ("Salon", ((0.08, 0.15, 0.95), (0.48, 0.45, 1.40))),     # rim, spokes, hub (not mirrored)
        # lenses: the glass's islands under 3 cm deep along y and 5 to 30 cm across, by box
        "lenses": {"headlight": [((0.30, -2.05, 0.80), (0.80, -1.70, 1.25)),     # head lamps, wing lamps
                                 ((0.50, -0.15, 1.00), (0.75, 0.10, 1.35))],      # scuttle lamps
                   "indicator": [((0.70, 1.60, 0.55), (0.90, 1.90, 0.85))],
                   "brake": [((0.50, 1.60, 0.55), (0.70, 1.90, 0.85))]},
        "cab": {"seat": (0.78, 0.76), "eye": (0.72, 1.36), "figure": 0.6, "eye_pitch": 0.12},   # (y, z); x: the wheel's
    },
}
GLASS_LENS = (0.03, 0.05, 0.30)         # a lens: under this deep along y, between these across (m)


class Whole:
    """A whole group as one "island" for import_car.set_faces."""
    def __init__(self, o, group):
        self.faces = range(len(o.data.polygons))
        self.group = group
        self.remat = None
        self.bands = None


def load(c: dict) -> dict:
    """The OBJ's groups as objects (name -> object), in the car frame."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.wm.obj_import(filepath=str(ROOT / c["obj"]), use_split_groups=True, global_scale=c["scale"])
    bpy.context.view_layer.update()
    objs = {}
    for o in bpy.data.objects:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        objs[o.name] = o
    # middle of the whole car, the bottom of the tyres on the ground
    lo, hi = ic.bounds(v.co for o in objs.values() for v in o.data.vertices)
    wlo, _ = ic.bounds(v.co for g in c["wheels"] for v in objs[g].data.vertices)
    shift = Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -wlo.z)))
    for o in objs.values():
        o.data.transform(shift)
    return objs


def material_name(c: dict, tset: str) -> str:
    return ("paint_" if tset in c["paint"] else "") + tset.lower()


def textures(key: str, c: dict, folder: Path) -> dict:
    """Downscaled maps of each set into `folder` (car_textures.py); material name -> its files."""
    src = ROOT / c["textures"]
    jobs, out = [], {}
    for tset, (nb, nn, no) in c["sets"].items():
        f = {k: f"{tset.lower()}_{k}.jpg" for k in ("base", "normal", "orm")}
        n = len(jobs)
        jobs += [{"out": str(folder / f["base"]), "size": nb, "quality": 88, "rgb": str(src / f"{tset}_Diffuse02.jpg")},
                 {"out": str(folder / f["normal"]), "size": nn, "quality": 92, "exact": True,
                  "rgb": str(src / f"{tset}_Normal.jpg")},
                 {"out": str(folder / f["orm"]), "size": no, "quality": 90, "exact": True,
                  "channels": [str(src / f"{tset}_{m}.jpg") for m in ("AO", "Roughness", "Metallic")]}]
        for j in jobs[n:]:
            j["patches"] = c.get("patches", {}).get(tset, [])
        out[material_name(c, tset)] = dict(f, alpha=c["glass"].get(tset, 1.0))
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as t:
        json.dump(jobs, t)
    subprocess.run([str(PYTHON), "-I", str(Path(__file__).with_name("car_textures.py")), t.name], check=True)
    Path(t.name).unlink()
    for files in out.values():
        for k in ("base", "normal", "orm"):
            import_settings(folder / files[k], normal=k == "normal")
    return out


def import_settings(path: Path, normal: bool) -> None:
    """Godot's import settings of a texture: VRAM compressed with mipmaps (a 3D model's), a normal map as such. Godot
    completes the file when it imports the texture; an existing one is kept."""
    imp = path.with_name(path.name + ".import")
    if imp.exists():
        return
    imp.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\n'
                   f"compress/normal_map={1 if normal else 2}\nmipmaps/generate=true\n")


def materials(c: dict, folder: Path, files: dict) -> None:
    """A Blender material per texture set, textured for the previews (the glTF export leaves the textures out)."""
    for name, f in files.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        p = nt.nodes["Principled BSDF"]
        img = {k: bpy.data.images.load(str(folder / f[k])) for k in ("base", "normal", "orm")}
        for k in ("normal", "orm"):
            img[k].colorspace_settings.name = "Non-Color"
        node = {}
        for k in img:
            node[k] = nt.nodes.new("ShaderNodeTexImage")
            node[k].image = img[k]
        nt.links.new(node["base"].outputs["Color"], p.inputs["Base Color"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(node["normal"].outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(node["orm"].outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], p.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], p.inputs["Metallic"])
        if f["alpha"] < 1.0:
            p.inputs["Alpha"].default_value = f["alpha"]
            m.surface_render_method = "BLENDED"
        if name.startswith("paint"):
            p.inputs["Coat Weight"].default_value = 1.0
            p.inputs["Coat Roughness"].default_value = 0.04


def add_textures(gltf: Path, files: dict) -> None:
    """The textures of each textured material into the exported .gltf (Blender's exporter would re-encode them)."""
    g = json.loads(gltf.read_text())
    g["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]   # trilinear, repeat
    g["images"], g["textures"] = [], []
    index = {}

    def tex(name):
        if name not in index:
            index[name] = len(g["textures"])
            g["images"].append({"uri": name, "mimeType": "image/jpeg"})
            g["textures"].append({"sampler": 0, "source": len(g["images"]) - 1})
        return {"index": index[name]}
    for m in g["materials"]:
        f = files.get(m["name"])
        if f is None:
            continue
        m["pbrMetallicRoughness"] = {"baseColorTexture": tex(f["base"]), "baseColorFactor": [1, 1, 1, f["alpha"]],
                                     "metallicRoughnessTexture": tex(f["orm"]), "metallicFactor": 1.0,
                                     "roughnessFactor": 1.0}
        m["normalTexture"] = tex(f["normal"])
        m["occlusionTexture"] = tex(f["orm"])
        if f["alpha"] < 1.0:
            m["alphaMode"] = "BLEND"
    gltf.write_text(json.dumps(g, indent=1))


def lens_kind(c: dict, i) -> str | None:
    depth, small, big = GLASS_LENS
    if i.size.y >= depth or min(i.size.x, i.size.z) < small or max(i.size.x, i.size.z) > big:
        return None
    for kind, boxes in c["lenses"].items():
        if any(ic.inside(i.c, b) for b in boxes):
            return kind
    return None


def classify(c: dict, objs: dict, listing: list) -> dict:
    """Per group: the islands (or the whole group) with their part ("group"), material ("remat", None: the set's) and
    whether they keep every triangle ("keep": CARS "keep" boxes; CARS "drop" boxes hide them instead)."""
    per = {}
    st_src, (st_lo, st_hi) = c["steering"]
    drops, keeps = {}, {}
    for g, box in c.get("drop", []):
        drops.setdefault(g, []).append(box)
    for g, box in c.get("keep", []):
        keeps.setdefault(g, []).append(box)
    special = {"Glass", st_src} | set(drops) | set(keeps) | set(listing)

    def within(i, boxes):
        return any(all(lo[k] <= i.lo[k] and i.hi[k] <= hi[k] for k in range(3)) for lo, hi in boxes)
    for g, o in objs.items():
        if g not in special:
            per[g] = [Whole(o, c["wheels"].get(g, "body"))]
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        isls = ic.islands(bm, ["-"] * max(1, len(o.data.materials)))
        bm.free()
        for i in isls:
            i.group, i.remat = c["wheels"].get(g, "body"), None
            i.keep = within(i, keeps.get(g, []))
            if g == st_src and all(st_lo[k] <= i.lo[k] and i.hi[k] <= st_hi[k] for k in range(3)):
                i.group = "steering"
            elif within(i, drops.get(g, [])):
                i.group = "hidden"
        if g == "Glass":
            lenses = [(i, lens_kind(c, i)) for i in isls]
            boxes = [b for bs in c["lenses"].values() for b in bs]
            for i, kind in lenses:
                side = "left" if i.c.x > 0 else "right"
                if kind == "headlight":
                    i.remat = "headlight"
                elif kind == "indicator":
                    i.group, i.remat = "indicator_" + side, "indicator"
                elif kind == "brake":
                    i.bands = [(i.c.z, "brake_lights", "brake"), (math.inf, "body", "taillight")]
                elif any(ic.inside(i.c, b) for b in boxes) and max(i.size) < 0.12:
                    i.group = "hidden"                  # a bulb behind a lens
        if g in listing:
            print(f"== {g}: {len(isls)} islands")
            for i in sorted(isls, key=lambda i: (round(i.c.y, 1), i.c.x)):
                tag = i.remat or ("keep" if i.keep else "")
                print(f"  {i.group:16s} {tag:10s} tris {i.tris:6d} c ({i.c.x:6.3f}, {i.c.y:6.3f}, "
                      f"{i.c.z:6.3f}) size ({i.size.x:5.3f}, {i.size.y:5.3f}, {i.size.z:5.3f})")
        per[g] = isls
    return per


def shade(o, ratio: float) -> None:
    """Decimated by `ratio`, then smooth up to 40 degrees, normals weighted by face area (the OBJ's own normals do not
    survive the decimation)."""
    ic.select_only(o)
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    if ratio < 1.0:
        mod = o.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        bc.apply_modifiers(o)
    o.data.polygons.foreach_set("use_smooth", [True] * len(o.data.polygons))
    o.data.set_sharp_from_angle(angle=math.radians(40))
    wn = o.modifiers.new("weighted", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    bc.apply_modifiers(o)


def steering_frame(st) -> Vector:
    """Puts the steering wheel's origin at its hub, local Z along its axis towards the driver (the normal of the rim's
    plane: the least spread of its points), +Y at 12 o'clock. Returns the hub."""
    pts = [v.co.copy() for v in st.data.vertices]
    mean = sum(pts, Vector()) / len(pts)
    cov = Matrix(((0,) * 3,) * 3)
    for p in pts:
        d = p - mean
        for a in range(3):
            for b in range(3):
                cov[a][b] += d[a] * d[b]
    axis = Vector((0.0, 1.0, 0.0))
    for _ in range(50):                             # smallest eigenvector: power iteration on the inverse
        axis = (cov.inverted() @ axis).normalized()
    if axis.y < 0.0:
        axis = -axis
    rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    llo, lhi = ic.bounds(rot.inverted() @ p for p in pts)
    hub = rot @ ((llo + lhi) * 0.5)
    xf = Matrix.Translation(hub) @ rot
    st.data.transform(xf.inverted())
    st.matrix_world = xf
    print(f"steering wheel at {tuple(round(v, 3) for v in hub)}, axis {tuple(round(v, 3) for v in axis)}, "
          f"rim {lhi.x - llo.x:.3f} x {lhi.y - llo.y:.3f} m")
    return hub


def build(key: str, out_dir: Path, prev: str, listing: list) -> None:
    c = CARS[key]
    folder = out_dir / key
    folder.mkdir(parents=True, exist_ok=True)
    objs = load(c)
    files = textures(key, c, folder)
    materials(c, folder, files)
    per = classify(c, objs, listing)

    parts = {}                                      # part -> [pieces]
    for g, o in objs.items():
        tset = c["set_of"].get(g, g)
        own = c["plain"].get(g) or material_name(c, tset)
        ic.set_faces(o, per[g], lambda i, f, own=own: i.remat or own)
        for part in reversed(ic.GROUPS):
            piece = ic.split(o, "grp", lambda v, part=part: v == ic.GROUPS.index(part))
            if piece is None:
                continue
            if part == "hidden":
                bpy.data.objects.remove(piece)
                continue
            ratio = c["ratio"].get(part if part == "steering" else g, 1.0)
            kept = {k for k, i in enumerate(per[g]) if getattr(i, "keep", False)}
            whole = ic.split(piece, "isl", lambda v, kept=kept: v in kept) if kept else None
            if whole is not None:                   # those islands whole, the rest decimated
                shade(whole, 1.0)
                parts.setdefault(part, []).append(whole)
                print(f"  {g} -> {part}: {ic.tris(whole)} triangles kept whole")
                if whole is piece:
                    continue
            before = ic.tris(piece)
            shade(piece, 1.0 if part.startswith(("indicator", "brake")) else ratio)
            print(f"  {g} -> {part}: {before} -> {ic.tris(piece)} triangles")
            parts.setdefault(part, []).append(piece)
    out = {}
    for part, pieces in parts.items():
        o = pieces[0]
        if len(pieces) > 1:
            bc.join(o, pieces)
        o.name = o.data.name = part
        for a in ("grp", "isl"):
            if a in o.data.attributes:
                o.data.attributes.remove(o.data.attributes[a])
        out[part] = o
    hubs = {}
    for part in c["wheels"].values():
        o = out[part]
        lo, hi = ic.bounds(v.co for v in o.data.vertices)
        hubs[part] = (lo + hi) * 0.5
        o.data.transform(Matrix.Translation(-hubs[part]))
        o.location = hubs[part]
    hub = steering_frame(out["steering"])

    k = c["cab"]
    seat = Vector((hub.x, k["seat"][0], k["seat"][1]))
    eye = Vector((hub.x, k["eye"][0], k["eye"][1]))
    print(f"driver seat {tuple(round(v, 3) for v in seat)}, eye {tuple(round(v, 3) for v in eye)}")

    gltf = folder / f"{key}.gltf"
    for o in bpy.data.objects:
        o.select_set(o in out.values())
    bpy.ops.export_scene.gltf(filepath=str(gltf), export_format="GLTF_SEPARATE", use_selection=True,
                              export_normals=True, export_texcoords=True, export_materials="EXPORT",
                              export_image_format="NONE", export_yup=True, export_apply=True)
    add_textures(gltf, files)
    layout = {
        "wheels": list(c["wheels"].values()),
        "indicators": {"left": ["indicator_left"], "right": ["indicator_right"]},
        "brake_lights": ["brake_lights"],
        "cab": {
            "driver_seat": bc.gd(seat),
            "driver_eye": bc.gd(eye),
            "passenger_seat": bc.gd((-seat.x, seat.y, seat.z)),
            "passenger_eye": bc.gd((-eye.x, eye.y, eye.z)),
            "steering_wheel": "steering",
            "figure": k["figure"],
            "eye_pitch": k["eye_pitch"],
        },
    }
    (folder / f"{key}.json").write_text(json.dumps(layout, indent=1) + "\n")
    total = sum(ic.tris(o) for o in out.values())
    print(f"{key}: {gltf} ({total} triangles: " + ", ".join(f"{n} {ic.tris(o)}" for n, o in out.items()) + ")")
    blo, bhi = ic.bounds(v.co for v in out["body"].data.vertices)
    print(f"body box {tuple(round(v, 3) for v in blo)} .. {tuple(round(v, 3) for v in bhi)}; wheels " +
          ", ".join(f"{n} {tuple(round(v, 3) for v in p)}" for n, p in sorted(hubs.items())))
    if prev:
        Path(prev).mkdir(parents=True, exist_ok=True)
        bc.preview(str(Path(prev) / key), {"length": bhi.y - blo.y}, {"eye": eye})


def main() -> None:
    a = bc.args()
    listing = [g for g in a.get("list", "").split(",") if g]
    for key in ([a["car"]] if a["car"] else list(CARS)):
        build(key, Path(a["out_dir"]), a["preview"], listing)


if __name__ == "__main__":
    main()
