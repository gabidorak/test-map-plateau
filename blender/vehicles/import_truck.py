"""Turns a ready-made truck model (FBX from a 3D model store; the files stay in ref/, not published) into a drivable
truck with the parts and cab file of the cars of import_car.py, so scripts/car.gd drives it and shows its cab view:
the Volvo FH16 tractor unit (Globetrotter cab, 4x2) of ref/volvo_fh16 ("VOLVO FH16.zip"), alone (<truck>.glb) and
with its curtain-sider semi-trailer as the rear section of an articulated vehicle (<truck>_trailer.glb).

blender -b --factory-startup -P blender/vehicles/import_truck.py -- [--truck=volvo_fh16] [--out_dir=godot/assets/cars]
                                                                    [--preview=data/review/cars]

The FBX is a tractor and a three-axle semi-trailer, 256 objects (3.1 million triangles) under a scaled group, at about
1:9.45 with the front along -X. Each object is moved into the frame of build_car.py (metres, z up, front = -Y, left =
+X, origin on the ground under the middle of the tractor's body box) and goes, face by face, to one of the parts car.gd
needs, picked by object name (lists per truck in TRUCKS) and, for objects that hold both sides, by the side of the face:
- "body", from which car.gd takes the collision box, so the outside mirrors and the roof aerials are objects of their
  own ("mirrors", "aerial");
- "steering" (the steering wheel; its origin at the hub, local Z up the column to the driver, +Y at 12 o'clock);
- the lamps car.gd switches: indicator_left / indicator_right (the top segment of each headlamp's "V", the side
  repeaters on the cab corners and the amber band of the rear lamps), brake_lights and reverse_lights (the red and
  the white band of the rear lamps: their lens is one textured piece, cut by its texture's u bands; its inner red band
  is the taillight). The headlamp projectors take the material "headlight", which car.gd lights at night, the "V"
  light guide "drl" (always lit);
- wheel_front_left ... wheel_rear_right (origin at the wheel centre; the rear ones are the twin tyres of a side);
- with the trailer, its parts are "trailer_body", trailer_wheel_1_left ... trailer_wheel_3_right (front to back, twin
  tyres) and its own trailer_indicator_left/right, trailer_brake_lights and trailer_reverse_lights (its rear lamps are
  textured like the tractor's); the json lists them as the rear section ("trailer") hinged at the fifth wheel
  ("hitch").
The V-Ray materials do not come through FBX, so every face takes one of build_car.py's materials (a few more are added
below) from its FBX material name, some objects a different one. The dense objects (tyres with their tread, the
grille, lettering, coiled air lines, seats) are decimated, so the tractor stays near the size of the other vehicles;
everything is shaded anew (smooth up to 35-40°, the paint's normals weighted by face area). The number plate texture
is a real-looking stock plate, the sun visor's "GLOBETROTTER" lettering and the curtains' hexagon print are textures:
all are left out (plain plates, plain black visor, plain curtains). So are the maker's name and mark (the front
emblem's lettering and ring, the lettering on the cab's back); the "FH" and "750" model badges stay, as plain chrome.
<truck>.json (next to the .glb) names the wheels, lamps and cab (driver and passenger seat and eye, steering wheel,
the size of the seated look-alikes and the cab camera's pitch) in glTF coordinates, like import_car.py's.
--preview renders front, rear, side and cab views (Cycles) to check the conversion."""
import contextlib
import io
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_car as bc      # noqa: E402  (palette, mat(), join, apply_modifiers)
import import_car as ic     # noqa: E402  (split by a face attribute, bounds)

ROOT = bc.ROOT

bc.MATERIALS.update({       # Volvo FH16
    "paint_volvo": ("#C8CBCE", 0.6, 0.3, 0.0),         # silver-white metallic, as the model's renders
    "chassis": ("#232426", 0.5, 0.55, 0.0),            # frame, tanks, suspension: satin black steel
    "hose_red": ("#A3221B", 0.0, 0.5, 0.0),            # the trailer's coiled air lines
    "hose_blue": ("#28508F", 0.0, 0.5, 0.0),
    "hose_yellow": ("#B88A2E", 0.0, 0.5, 0.0),
    "upholstery": ("#8A8072", 0.0, 0.85, 0.0),         # the bunk and the soft trims
    "accent_red": ("#A51E18", 0.0, 0.5, 0.0),
    "trailer_box": ("#BFC3C7", 0.3, 0.45, 0.0),         # the semi-trailer's frame, roof and rear doors
    "curtain": ("#AEB2B6", 0.0, 0.8, 0.0),              # its side curtains (PVC), plain
    "reflector_yellow": ("#E3B21C", 0.2, 0.3, 0.0),     # rear marker plates
})

# per truck: the FBX, its scale and turn into the car frame, then object names (the FBX's) per part or material
TRUCKS = {
    "volvo_fh16": {
        "fbx": "ref/volvo_fh16/export/VOLVO FH16.FBX",
        "scale": 9.45,              # its front tyres are then 1.03 m (315/70 R22.5), the cab 2.5 m wide
        "turn": 90.0,               # degrees about z: its front is along -X
        "tractor_end": -2.3,        # car-frame y before centring: objects reaching behind it are the trailer's
        "trailer_materials": ("truck_silver_dirt continer",),     # the trailer's front wall reaches over the tractor
        "materials": {
            "Material #2242457": "paint_volvo", "Material #2242460": "plastic_black",
            "Material #2242460S": "trim_black", "Material #2242396": "chassis", "Material #2242401": "chassis",
            "Material #2242397": "plastic_black", "Material #2242443": "tyre", "Material #2242444": "rim",
            "Material #2242445": "hub", "Material #2242446": "chrome", "Material #2242448": "chrome",
            "Material #2242447": "plate", "Material #2242449": "plastic_black", "Material #2242450": "underbody",
            "Material #2242483": "headlight", "Material #2242400": "hose_yellow", "Material #2241344": "dash",
            "Material #2234307": "dash", "METAL": "chrome", "Tyre": "tyre_wall", "Tyre1": "tyre",
            "Tyre.001": "tyre_wall", "head light black": "trim_black", "head light bump": "chrome",
            "head light white lightS": "drl", "glass head light": "lens", "glass head": "glass_rear",
            "glass_front_black": "glass_front", "color black MAT": "plastic_black", "color black gl": "trim_black",
            "13 - DefaultBB": "grille", "helix": "hose_red", "helix1": "hose_blue", "PLASTIC": "dash",
            "PLASTIC int": "dash", "leather2black": "trim", "leather2": "upholstery", "leather": "leather",
            "fabric": "seat_accent", "fabric_black": "seat", "plastic_interior": "dash", "plastic3": "dash",
            "05": "dash", "04": "trim_light", "010": "accent_red", "interior1": "seal",
            "benz_black_plastic_interior": "trim_black", "black_plastic_interior": "trim_black",
            "black_plastic": "dash", "int5": "alu", "int6": "trim_black", "silver_interior1": "alu",
            "silver_interior1.001": "alu", "silver_interior1.002": "alu", "int tag6": "chrome",
            "STEERING WEEL TAG": "trim_black", "KM": "screen", "MONITOR INT": "screen", "int mon": "screen",
            "(p)": "trim_light", "plan": "carpet", "16 - Default": "dash", "18 - Default": "mirror_glass",
        },
        # objects (all their faces) taking another material than their FBX material's
        "object_materials": {
            "Shape059": "grille", "Object670": "trim_black", "Object669": "trim_black", "Box179.001": None,
            "Object655": "rim", "Object654": "hub", "Cylinder229": "hub", "Object683": "headlight",
            "Shape059.001": "glass_side", "Box142.001": "glass_side", "Shape065": "trim_black",
            "Shape068": "trim_black", "Object618": "trim", "Box143": "headliner", "Object688": "headliner",
            "Object606": "headliner", "Box149": "plastic_black", "Object635": "plastic_black",
            "Plane217": "plastic_black", "Object634": "plastic_black", "Object630": "plastic_black",
            "Object694": "plastic_black", "Object631": "plastic_black", "Object693": "plastic_black",
            "Box178": "grille", "Cylinder243": "chassis", "Object664": "screen", "Line054": "carpet",
            "Object573": "carpet",
        },
        "wheels": {"front": ["Object576", "Tube055", "Cylinder222", "Cylinder229", "Cylinder228"],
                   "rear": ["Object657", "Object656", "Tube053", "Tube054", "Object655", "Object654"]},
        "steering": ["Object663", "Object661", "Object662", "Object658", "Object660", "Object659", "Shape048"],
        "steering_rim": "Object663",            # its plane gives the steering axis
        "mirrors": ["Box179.001"],
        "aerial": ["Line052.001", "Cylinder227"],
        "indicators": ["Object685", "Object679"],   # each holds both sides
        # the engine block in the dark behind the grille; the maker's name and mark (the front emblem's lettering and
        # ring, the lettering on the cab's back: the diagonal chrome bar across the grille stays)
        "drop": ["Box166", "Text001", "Tube001", "Tube002", "Text010"],
        # the rear lamps: one textured lens per side, its bands along u from the outer end: amber, red, white, red
        "rear_lamps": {"object": "Box186", "material": "truck_light",
                       "bands": [(0.278, "indicator", "indicator"), (0.556, "brake_lights", "brake"),
                                 (0.722, "reverse_lights", "reverse"), (9.0, "body", "taillight")]},
        # decimation: ratio per object; the others by size (see ratio())
        "ratios": {"Object576": 0.025, "Object656": 0.025, "Object657": 0.025, "Cylinder222": 0.08,
                   "Object655": 0.2, "Shape059": 0.1, "Helix005": 0.06, "Helix006": 0.06,
                   "Text009": 0.08, "Box178": 0.1, "Object680": 0.5, "Box141": 0.12},
        "cab": {"seat": (0.72, -7.55, 1.92), "eye": (-7.45, 2.70), "figure": 0.8, "eye_pitch": 0.1},
        # the semi-trailer (<truck>_trailer.glb): its own materials and objects, over the tractor's
        "trailer": {
            "materials": {"truck_silver_dirt continer": "trailer_box", "CONTINER": "curtain",
                          "truck_black_metal1": "chassis", "Material #2242404": "trailer_box", "truck": "chassis",
                          "truck_white_light": "lens", "truck_tagg": "reflector_yellow",
                          "truck_tagg_red": "reflector_red", "truck_orange_light": "taillight", "number": "plate",
                          "truck_light": "lens"},
            "object_materials": {"Object405": "rim", "Object409": "rim", "Object413": "rim", "Object404": "hub",
                                 "Object408": "hub", "Object412": "hub",
                                 "Cylinder247": {"Material #2242396": "alu"}},     # the rear doors' lock rods
            "wheels": ["Object402", "Object403", "Object406", "Object407", "Object410", "Object411", "Object405",
                       "Object409", "Object413", "Object404", "Object408", "Object412", "Tube044", "Tube047",
                       "Tube048", "Tube050", "Tube051", "Tube052"],
            "rear_lamps": {"object": "Box152", "material": "truck_light",
                           "bands": [(0.278, "indicator", "indicator"), (0.556, "brake_lights", "brake"),
                                     (0.722, "reverse_lights", "reverse"), (9.0, "body", "taillight")]},
            "hitch": (0.0, -3.65, 1.1),         # the fifth wheel's middle and top (car frame before centring)
            "ratios": {"Object402": 0.025, "Object403": 0.025, "Object406": 0.025, "Object407": 0.025,
                       "Object410": 0.025, "Object411": 0.025, "Object405": 0.2, "Object409": 0.2,
                       "Object413": 0.2, "Cylinder223": 0.15, "Box152": 0.15, "Box040": 0.25, "Box188": 0.15,
                       "Plane224": 1.0},
        },
    },
}
WHEEL_PARTS = ("tyre", "tyre_wall", "rim", "hub")
GROUPS = ["body", "steering", "mirrors", "aerial", "indicator_left", "indicator_right", "brake_lights",
          "reverse_lights", "wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right",
          "trailer_body", "trailer_indicator_left", "trailer_indicator_right", "trailer_brake_lights",
          "trailer_reverse_lights"] + [f"trailer_wheel_{k}_{s}" for k in (1, 2, 3) for s in ("left", "right")] + \
         ["hidden"]
LAMPS = ("indicator", "brake", "reverse")      # (the rear lamps' bands are kept whole: small, cut along their texture)


# ---------------------------------------------------------------- loading

class _Op:
    """Stands in for the FBX import operator (see import_car.py)."""
    def report(self, kind, msg):
        print("FBX", kind, msg)


def load(c: dict) -> dict:
    """The FBX's mesh objects in the car frame (before centring), by name, their transforms applied. They hang under a
    group empty scaled 1/1000: unparented first, or clearing their matrix would leave them scaled 1000 times."""
    from io_scene_fbx import import_fbx
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.cameras,
                 bpy.data.lights, bpy.data.worlds):
        for x in list(coll):            # a second build starts afresh (the FBX's material names stay free)
            coll.remove(x)
    with contextlib.redirect_stdout(io.StringIO()):
        import_fbx.load(_Op(), bpy.context, filepath=str(ROOT / c["fbx"]))
    bpy.context.view_layer.update()
    xf = Matrix.Scale(c["scale"], 4) @ Matrix.Rotation(math.radians(c["turn"]), 4, "Z")
    world = {o.name: o.matrix_world.copy() for o in bpy.data.objects}
    for o in bpy.data.objects:
        o.parent = None
    out = {}
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        o.data.transform(xf @ world[o.name])
        o.matrix_basis = Matrix.Identity(4)
        out[o.name] = o
    for m in list(bpy.data.materials):          # (renaming re-sorts the collection)
        m.name = "fbx " + m.name                # out of the way of the palette's
    return out


def fbx_names(o) -> list:
    return [m.name.removeprefix("fbx ") if m else "" for m in o.data.materials]


def is_tractor(o, c: dict) -> bool:
    return max(v.co.y for v in o.data.vertices) < c["tractor_end"] and \
        not any(n in c["trailer_materials"] for n in fbx_names(o))


# ---------------------------------------------------------------- faces: material and part

def faces(o, c: dict, axles=None) -> list:
    """(group, palette material) of each face of `o`; `axles`: for an object of the trailer, the y of its axles (front
    to back), else None."""
    me = o.data
    t = c["trailer"] if axles is not None else None
    names = fbx_names(o)
    mapping = c["materials"] | t["materials"] if t else c["materials"]
    over = (t or c)["object_materials"].get(o.name)
    mats = [(over.get(n) if isinstance(over, dict) else over) or mapping.get(n, "plastic_black") for n in names]
    n = o.name
    out = []
    lamp = (t or c)["rear_lamps"]
    uv = me.uv_layers.active.data if me.uv_layers else None
    wheel_side = {}
    wheels = t["wheels"] if t else c["wheels"]["front"] + c["wheels"]["rear"]
    if n in wheels:
        # both wheels of an axle in one object: the side of each loose piece; one across the middle is an axle
        bm = bmesh.new()
        bm.from_mesh(me)
        for i in ic.islands(bm, mats):
            s = "axle" if i.lo.x < -0.3 and i.hi.x > 0.3 else "left" if i.c.x > 0.0 else "right"
            for f in i.faces:
                wheel_side[f] = s
        bm.free()
    if t:
        y = sum(v.co.y for v in me.vertices) / len(me.vertices)
        axle = 1 + min(range(len(axles)), key=lambda k: abs(axles[k] - y))
    pre = "trailer_" if t else ""
    for p in me.polygons:
        m = mats[p.material_index]
        x = p.center.x
        side = "left" if x > 0.0 else "right"
        if n in c["drop"]:
            g = "hidden"
        elif wheel_side.get(p.index) == "axle":
            g, m = pre + "body", "chassis"
        elif wheel_side:
            g = f"trailer_wheel_{axle}_" if t else f"wheel_{'front' if n in c['wheels']['front'] else 'rear'}_"
            g += wheel_side[p.index]
            if m not in WHEEL_PARTS:
                m = "hub"
        elif t:
            g = "trailer_body"
        elif n in c["steering"]:
            g = "steering"
        elif n in c["mirrors"]:
            g = "mirrors"
        elif n in c["aerial"]:
            g = "aerial"
        elif n in c["indicators"]:
            g, m = "indicator_" + side, "indicator"
        else:
            g = "body"
        if n == lamp["object"] and names[p.material_index] == lamp["material"]:
            u = sum(uv[k].uv[0] for k in p.loop_indices) / p.loop_total
            g, m = next((g, m) for top, g, m in lamp["bands"] if u < top)
            g = pre + g + ("_" + side if g == "indicator" else "")
        out.append((g, m))
    return out


def assign(o, per_face: list) -> None:
    """Palette material slots per face and the face attribute "grp" (index in GROUPS)."""
    me = o.data
    names = sorted({m for _, m in per_face})
    me.materials.clear()                        # (resets every face's material index: computed before)
    for n in names:
        me.materials.append(bc.mat(n))
    idx = {n: k for k, n in enumerate(names)}
    me.polygons.foreach_set("material_index", [idx[m] for _, m in per_face])
    if "grp" in me.attributes:
        me.attributes.remove(me.attributes["grp"])
    me.attributes.new("grp", "INT", "FACE").data.foreach_set("value", [GROUPS.index(g) for g, _ in per_face])


DECIMATE = (200, 0.055)      # an object keeps up to this many triangles, and this share of the others


def ratio(o, c: dict) -> float:
    """Decimation of object `o`: its own, else DECIMATE (most objects are subdivision surfaces, many times denser
    than their shape needs)."""
    own = c["ratios"] | c["trailer"]["ratios"]
    if o.name in own:
        return own[o.name]
    t = ic.tris(o)
    keep, share = DECIMATE
    return 1.0 if t <= keep else max((keep + share * (t - keep)) / t, 0.03)


def rework(o, r: float, paint: bool) -> None:
    """Decimates `o` to the share `r` of its faces and shades it anew: smooth up to 40° (35° for the paint, whose
    normals then lean towards the larger faces)."""
    ic.select_only(o)
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    if r < 1.0:
        mod = o.modifiers.new("decimate", "DECIMATE")
        mod.ratio = r
        bc.apply_modifiers(o)
    o.data.polygons.foreach_set("use_smooth", [True] * len(o.data.polygons))
    o.data.set_sharp_from_angle(angle=math.radians(35 if paint else 40))
    if paint:
        wn = o.modifiers.new("weighted", "WEIGHTED_NORMAL")
        wn.mode = "FACE_AREA"
        wn.weight = 50
        wn.keep_sharp = True
        bc.apply_modifiers(o)


# ---------------------------------------------------------------- the steering wheel and the cab

def steering_frame(rim) -> Matrix:
    """Hub frame of the steering wheel from its rim: the axis is the normal of the rim's plane (towards the driver,
    +Y in the car frame), 12 o'clock up; origin at the middle of the rim."""
    pts = [v.co.copy() for v in rim.data.vertices]
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
    local = [rot.inverted() @ p for p in pts]
    llo, lhi = ic.bounds(local)
    hub = rot @ ((llo + lhi) * 0.5)
    print(f"steering wheel at {tuple(round(v, 3) for v in hub)}, axis {tuple(round(v, 3) for v in axis)}, "
          f"rim {lhi.x - llo.x:.3f} x {lhi.y - llo.y:.3f} m")
    return Matrix.Translation(hub) @ rot


# ---------------------------------------------------------------- build

def build(key: str, out_dir: Path, prev: str, semi: bool) -> None:
    """<key>.glb and .json: the tractor alone, or with its semi-trailer (`semi`: <key>_trailer.glb)."""
    c = TRUCKS[key]
    name = key + ("_trailer" if semi else "")
    objs = load(c)
    tractor = [o for o in objs.values() if is_tractor(o, c)]
    trailer = [o for o in objs.values() if o not in tractor] if semi else []
    for o in objs.values():
        if o not in tractor and o not in trailer:
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()             # (else the view layer still lists the removed ones, as None)
    print(f"{name}: {len(tractor)} tractor objects, {sum(ic.tris(o) for o in tractor)} triangles, "
          f"{len(trailer)} trailer objects, {sum(ic.tris(o) for o in trailer)} triangles")
    # the trailer's axles: the middles of its wheel objects, grouped
    axles = []
    for y in sorted(sum(v.co.y for v in o.data.vertices) / len(o.data.vertices)
                    for o in trailer if o.name in c["trailer"]["wheels"]):
        if not axles or y - axles[-1][-1] > 0.4:
            axles.append([])
        axles[-1].append(y)
    axles = [sum(a) / len(a) for a in axles]
    # every object's faces to their groups, each part decimated and shaded on its own
    parts = {g: [] for g in GROUPS}
    for o in tractor + trailer:
        r = ratio(o, c)
        src = o.name
        per = faces(o, c, axles if o in trailer else None)
        assign(o, per)
        for g in sorted({g for g, _ in per}, key=GROUPS.index):
            part = ic.split(o, "grp", lambda v, g=g: v == GROUPS.index(g))
            if part is None:
                continue
            if g != "hidden":
                paint = any(m and m.name.startswith("paint") for m in part.data.materials)
                textured = src in (c["rear_lamps"]["object"], c["trailer"]["rear_lamps"]["object"])
                rework(part, 1.0 if textured and any(k in g for k in LAMPS) else r, paint)
            part["src"] = src
            parts[g].append(part)
    for o in parts.pop("hidden"):
        bpy.data.objects.remove(o)
    rim = next(o for o in parts["steering"] if o["src"] == c["steering_rim"])
    st_xf = steering_frame(rim)
    out_objs = {}
    for g, lst in parts.items():
        if not lst:
            continue
        if len(lst) > 1:
            bc.join(lst[0], lst)
        o = lst[0]
        o.name = o.data.name = g
        if "grp" in o.data.attributes:
            o.data.attributes.remove(o.data.attributes["grp"])
        out_objs[g] = o
        o.data.validate()                       # (decimation leaves a few degenerate faces)
    # centre: across, between the tractor's wheels (the model's running gear sits 3.5 cm left of its cab); along, the
    # middle of the tractor's body box; the bottom of the tyres on the ground
    lo, hi = ic.bounds(v.co for v in out_objs["body"].data.vertices)
    wlo, whi = ic.bounds(v.co for g, o in out_objs.items() if g.startswith("wheel_") for v in o.data.vertices)
    shift = Matrix.Translation(Vector((-(wlo.x + whi.x) / 2, -(lo.y + hi.y) / 2, -wlo.z)))
    for o in out_objs.values():
        o.data.transform(shift)
    st_xf = shift @ st_xf
    # origins: wheels at their centre, the steering wheel at its hub
    hubs = {}
    for g, o in out_objs.items():
        if "wheel_" in g:
            wlo, whi = ic.bounds(v.co for v in o.data.vertices)
            hubs[g] = (wlo + whi) * 0.5
            o.data.transform(Matrix.Translation(-hubs[g]))
            o.location = hubs[g]
    st = out_objs["steering"]
    st.data.transform(st_xf.inverted())
    st.matrix_world = st_xf

    k = c["cab"]
    seat = shift @ Vector(k["seat"])
    eye = shift @ Vector((k["seat"][0], k["eye"][0], k["eye"][1]))
    print(f"driver seat {tuple(round(v, 3) for v in seat)}, eye {tuple(round(v, 3) for v in eye)}")

    out = out_dir / f"{name}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in out_objs.values())
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True,
                              export_texcoords=False)                 # untextured
    have = [g for g in GROUPS if g in out_objs]
    layout = {
        "wheels": [g for g in have if g.startswith("wheel_")],
        "indicators": {s: [g for g in have if g.endswith("indicator_" + s)] for s in ("left", "right")},
        "brake_lights": [g for g in have if g.endswith("brake_lights")],
        "reverse_lights": [g for g in have if g.endswith("reverse_lights")],
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
    if semi:
        layout["trailer"] = {"nodes": [g for g in have if g.startswith("trailer_")], "body": "trailer_body",
                             "wheels": [g for g in have if g.startswith("trailer_wheel_")]}
        hitch = shift @ Vector(c["trailer"]["hitch"])
        hitch.x = 0.0                           # on the tractor's middle line
        layout["hitch"] = bc.gd(hitch)
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    total = sum(ic.tris(o) for o in out_objs.values())
    print(f"{name}: {out} ({total} triangles: " + ", ".join(f"{n} {ic.tris(o)}" for n, o in out_objs.items()) + ")")
    blo, bhi = ic.bounds(v.co for g in ("body", "trailer_body") if g in out_objs for v in out_objs[g].data.vertices)
    print(f"body box {tuple(round(v, 3) for v in blo)} .. {tuple(round(v, 3) for v in bhi)}; wheels " +
          ", ".join(f"{n} {tuple(round(v, 3) for v in p)}" for n, p in sorted(hubs.items())))
    if prev:
        Path(prev).mkdir(parents=True, exist_ok=True)
        preview(str(Path(prev) / name), blo, bhi, eye, cab=not semi)


def preview(prefix: str, lo: Vector, hi: Vector, eye: Vector, cab: bool = True) -> None:
    """Cycles views of the truck (front and rear three-quarters, left side, the driver's view: `cab`)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.cycles.device = bc.gpu()
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    nt = world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.35
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    scene.collection.objects.link(sun)
    ground = bpy.data.objects.new("ground", bpy.data.meshes.new("ground"))
    ground.data.from_pydata([(-80, -80, 0), (80, -80, 0), (80, 80, 0), (-80, 80, 0)], [], [(0, 1, 2, 3)])
    ground.data.materials.append(bc.mat("underbody"))
    scene.collection.objects.link(ground)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    L = hi.y - lo.y
    mid = Vector((0.0, (lo.y + hi.y) / 2, hi.z * 0.45))
    views = [("front", mid + Vector((L * 0.9, -L * 1.15, hi.z * 0.3)), mid, 40),
             ("rear", mid + Vector((-L * 0.9, L * 1.15, hi.z * 0.45)), mid, 40),
             ("side", mid + Vector((L * 1.9, 0.0, hi.z * 0.05)), mid, 40)]
    if cab:
        views += [("cab", tuple(eye), (eye.x - 0.3, eye.y - 4.0, eye.z - 0.9), 14),
                  ("inside", (-0.9, eye.y + 0.55, eye.z + 0.1), (0.5, eye.y - 0.9, eye.z - 0.5), 16)]
    for suffix, pos, look, lens in views:
        cam.location = pos
        cam.data.lens = lens
        cam.data.clip_start = 0.02
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{suffix}.png"
        bpy.ops.render.render(write_still=True)
        print("preview", scene.render.filepath)
    bpy.data.objects.remove(ground)


def main() -> None:
    a = bc.args()
    for key in ([a["truck"]] if a.get("truck") else list(TRUCKS)):
        build(key, Path(a["out_dir"]), a["preview"], semi=False)
        if "trailer" in TRUCKS[key]:
            build(key, Path(a["out_dir"]), a["preview"], semi=True)


if __name__ == "__main__":
    main()
