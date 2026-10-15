"""Turns a ready-made car model (FBX, e.g. from a 3D model store; the files stay in ref/, not published) into a
drivable car with the same parts and cab file as the cars of build_car.py, so scripts/car.gd drives it and shows
its cab view: the Renault Zoe (2013) of ref/RENAULT_ZOE_2013.

blender -b --factory-startup -P blender/vehicles/import_car.py -- [--car=renault_zoe] [--out_dir=godot/assets/cars]
                                                                  [--preview=data/review/cars]

The FBX has the body (shell, glass, lamps, a simple cabin) as one mesh and the four wheels as another, in 3ds Max
millimetres. Both are moved into the frame of build_car.py (metres, z up, front = -Y, left = +X, origin on the
ground under the middle of the body), then split into the parts car.gd needs by their loose pieces ("islands"),
each picked by where it sits (boxes in that frame, per car in CARS):
- "body", from which car.gd takes the collision box, so the outside mirrors and the roof aerial are objects of
  their own ("mirrors", "aerial");
- "steering" (the steering wheel; its origin at the hub, local Z up the column to the driver, +Y at 12 o'clock);
- the lamps car.gd switches: indicator_left / indicator_right (the front amber bulbs and their reflectors, the mirror
  repeaters, the bottom band of the tail lamp lens) and brake_lights (the lens's middle band, the third brake lamp's
  lens); the headlight projectors take the material "headlight" and the lens's top band "taillight", which car.gd
  lights at night. car.gd swaps their materials for opaque ones, so the tail lamp's insides (behind layers of blue
  glass, which hid them when lit) and the third brake lamp's LEDs are dropped;
- wheel_front_left ... wheel_rear_right (origin at the wheel centre); the brake callipers go to the body.
The model's V-Ray materials do not come through FBX, so every piece takes one of build_car.py's materials (a few
more are added below) from its FBX material name, some pieces a different one by island (lamp reflectors, lenses,
seats, headliner). The very dense pieces (tyres, brake discs, lamp reflectors, LEDs) are decimated, so the car is
about the size of the build_car.py ones, and the paint panels are shaded anew (the model's normals show facets in
Godot). The number plate texture is a watermarked stock picture: the plates are plain.
--preview renders the same views as build_car.py."""
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
import build_car as bc     # noqa: E402  (palette, mat(), preview)

ROOT = bc.ROOT

bc.MATERIALS.update({
    "paint_celeste": ("#8FB4CF", 0.55, 0.28, 0.0),     # Renault "Bleu Céleste"
    "lens_red": ("#B0141E", 0.0, 0.04, 0.0),
    "lens_blue": ("#4F7FC4", 0.0, 0.05, 0.0),
    "reflector_red": ("#6E0A10", 0.0, 0.2, 0.0),
    "chrome_blue": ("#A8BCD2", 1.0, 0.15, 0.0),
    "badge_light": ("#62E8FA", 0.0, 0.2, 0.0),
})
bc.ALPHA.update({"lens_red": 0.5, "lens_blue": 0.35})

# a box: ((x0, y0, z0), (x1, y1, z1)) in the car frame; x boxes are for the left (+X) side and mirrored
CARS = {
    "renault_zoe": {
        "fbx": "ref/RENAULT_ZOE_2013/RENAULT_ZOE_2013_VRay.FBX",
        "body": "RENAULT_ZOE_2013", "wheels": "RENAULT_ZOE_2013_WHEELS",
        # FBX material -> palette material
        "materials": {
            "Carpaint Simple Ruby": "paint_celeste", "black": "plastic_black", "windowglass": "glass_side",
            "clearglass": "lens", "chrome": "chrome", "mattemetal": "alu", "orangeglass": "indicator",
            "mirror": "mirror_glass", "bluechrome": "chrome_blue", "blueglass": "lens_blue",
            "redglass": "reflector_red", "interior": "dash", "numberplate_black": "plastic_black",
            "numberplate_white": "plate", "number": "plate", "lightblue": "badge_light",
            "vray tire": "tyre", "vray rim": "rim_dark", "vray rim_second": "rim", "vray brakedisk": "disc",
        },
        "steering": ((0.12, -0.45, 0.79), (0.55, -0.22, 1.18)),
        "mirror": ((0.70, -0.88, 0.98), (1.05, -0.47, 1.22)),          # island centres
        "aerial": 1.6,                                                    # islands reaching above this
        "head_lamp": ((0.25, -2.0, 0.70), (0.80, -1.35, 0.95)),
        "tail_lamp": ((0.45, 1.40, 0.82), (0.85, 1.85, 1.12)),
        "chmsl": ((-0.20, 1.45, 1.38), (0.20, 1.65, 1.46)),              # third brake lamp, not mirrored
        "seats": ((-0.62, -0.45, 0.40), (0.62, 1.35, 1.40)),
        "cab": {"eye": (0.06, 1.33), "figure": 0.68, "eye_pitch": 0.1},  # driver's eye (y, z) above the seat
    },
}
DETAIL = {"chrome", "lens", "lens_blue", "lens_red", "indicator", "brake", "reflector_red", "headlight", "taillight",
          "mirror_glass", "alu", "chrome_blue"}       # materials of the pieces that may be decimated
WHEEL_RATIO = {"tyre": 0.2, "rim": 0.4, "disc": 0.15, "hub": 0.4}


# ---------------------------------------------------------------- loading

class _Op:
    """Stands in for the FBX import operator: the Ubuntu Blender 5.0 package's operator fails when called from a
    script (it reads self.files, which it no longer has), so its loader is called directly."""
    def report(self, kind, msg):
        print("FBX", kind, msg)


def load_fbx(path: Path) -> None:
    from io_scene_fbx import import_fbx
    with contextlib.redirect_stdout(io.StringIO()):     # a page per V-Ray texture map it cannot follow
        import_fbx.load(_Op(), bpy.context, filepath=str(path))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        o.parent = None
    for m in list(bpy.data.materials):          # (renaming re-sorts the collection)
        m.name = "fbx " + m.name                # out of the way of the palette's ("chrome")


def bounds(points) -> tuple:
    lo = Vector((math.inf,) * 3)
    hi = -lo
    for p in points:
        lo = Vector(map(min, lo, p))
        hi = Vector(map(max, hi, p))
    return lo, hi


# ---------------------------------------------------------------- islands

class Island:
    def __init__(self, faces, mats):
        self.faces = [f.index for f in faces]
        self.lo, self.hi = bounds(v.co for f in faces for v in f.verts)
        self.c = (self.lo + self.hi) * 0.5
        self.size = self.hi - self.lo
        self.tris = sum(len(f.verts) - 2 for f in faces)
        count = {}
        for f in faces:
            count[mats[f.material_index]] = count.get(mats[f.material_index], 0) + len(f.verts) - 2
        self.mat = max(count, key=count.get)        # palette material of most of its faces
        self.group = "body"
        self.remat = None                           # palette material for all its faces, None: by FBX material
        self.ratio = 1.0                            # decimation
        self.renormal = False                       # shaded anew: smooth by angle, normals weighted by face area
        self.bands = None                           # [(z below which, group, material)] per face instead


def islands(bm, mats) -> list:
    bm.faces.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        seen.add(f.index)
        stack, faces = [f], []
        while stack:
            g = stack.pop()
            faces.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(Island(faces, mats))
    return out


def inside(p, box, mirror=True) -> bool:
    """`p` in `box`; mirrored boxes also match on the right side (-X)."""
    lo, hi = box
    x = abs(p[0]) if mirror else p[0]
    return lo[0] <= x <= hi[0] and lo[1] <= p[1] <= hi[1] and lo[2] <= p[2] <= hi[2]


def side(isl) -> str:
    return "left" if isl.c.x > 0.0 else "right"


def classify(c: dict, isls: list) -> None:
    """Group and material of each island of the body."""
    st_lo, st_hi = c["steering"]
    for i in isls:
        if all(st_lo[k] <= i.lo[k] and i.hi[k] <= st_hi[k] for k in range(3)):
            i.group = "steering"
            i.remat = "leather" if i.mat == "dash" else None
        elif i.mat == "indicator":
            i.group = "indicator_" + side(i)
        elif inside(i.c, c["mirror"]):
            i.group = "mirrors"
        elif i.hi.z > c["aerial"] and i.size.x < 0.1 and i.size.y < 0.3:
            i.group = "aerial"
    for s in (1, -1):
        name = "left" if s > 0 else "right"
        on_side = [i for i in isls if i.c.x * s > 0 and i.group == "body"]
        # headlamp: the projector (lens, and the bowl behind it) lights up; the amber bulb's reflector blinks
        head = [i for i in on_side if inside(i.c, c["head_lamp"])]
        bulbs = [i for i in isls if i.group == "indicator_" + name and inside(i.c, c["head_lamp"])]
        for p in [i for i in head if i.mat == "lens" and i.tris > 1000]:
            p.remat = "headlight"
            for i in head:
                if i.mat == "chrome" and (i.c - p.c).xz.length < 0.05 and i.c.y > p.c.y:
                    i.remat = "headlight"
        for b in bulbs:
            for i in head:
                if i.mat == "chrome" and i.tris > 1000 and (i.c - b.c).length < 0.06:
                    i.group = "indicator_" + name
                    i.remat = "indicator"
        # tail lamp: three reflectors one above the other behind a clear lens (and layers of blue glass, which hide
        # them), bottom to top: indicator, brake, tail. The lens lights up instead, in three bands at their heights;
        # what is behind it goes.
        tail = [i for i in on_side if inside(i.c, c["tail_lamp"])]
        refl = sorted([i for i in tail if i.mat == "chrome" and i.tris >= 300 and max(i.size) < 0.17],
                      key=lambda i: i.c.z)
        lens = [i for i in tail if i.mat == "lens" and max(i.size) > 0.2]
        if len(refl) != 3 or len(lens) != 1:
            raise RuntimeError(f"tail lamp {name}: {len(refl)} reflectors, {len(lens)} lenses")
        lens = lens[0]
        lens.bands = [((refl[0].c.z + refl[1].c.z) / 2, "indicator_" + name, "indicator"),
                      ((refl[1].c.z + refl[2].c.z) / 2, "brake_lights", "brake"), (math.inf, "body", "taillight")]
        for i in tail:
            if i is not lens and all(lens.lo[k] - 0.01 <= i.lo[k] and i.hi[k] <= lens.hi[k] + 0.01 for k in range(3)):
                i.group = "hidden"
    for i in isls:
        # third brake lamp: its lens lights up, the LEDs behind it go
        if i.group == "body" and inside(i.c, c["chmsl"], mirror=False):
            if i.mat == "lens" and max(i.size) < 0.02 or i.mat == "chrome":
                i.group = "hidden"
            elif i.mat == "lens":
                i.group, i.remat = "brake_lights", "brake"
        if i.group == "body" and i.mat.startswith("paint"):
            i.renormal = True
        # cabin: seats, and the shell's headliner and carpet (per face, see interior_faces)
        if i.group == "body" and i.mat == "dash" and inside(i.c, c["seats"], mirror=False) \
                and i.size.x < 0.5 and i.size.y < 0.6 and i.tris >= 96:
            i.remat = "seat"
        mat = i.remat or i.mat
        if mat in DETAIL and i.group != "steering":
            if max(i.size) < 0.03 and i.tris > 150:
                i.ratio = max(0.08, 96 / i.tris)
            elif i.tris > 800:
                i.ratio = max(600, 0.1 * i.tris) / i.tris


def glass(bm, isls, mats) -> dict:
    """Windscreen, side and rear windows: the wide panes are the windscreen (front) and the rear window."""
    out = {}
    for i in isls:
        if i.mat == "glass_side" and i.size.x > 1.0:
            out[id(i)] = "glass_front" if i.c.y < 0.0 else "glass_rear"
    return out


# ---------------------------------------------------------------- building the parts

def set_faces(o, isls: list, face_mat) -> None:
    """Material slots from the palette per face (face_mat(island, face) -> name), and face attributes "grp" (index
    of the island's group in GROUPS) and "isl" (island index), carried through the splits."""
    me = o.data
    per_face = {}                               # face -> (material, group); before the slots go (and the indices)
    for i in isls:
        for f in i.faces:
            if i.bands:
                z = me.polygons[f].center.z
                per_face[f] = next((m, g) for top, g, m in i.bands if z < top)
            else:
                per_face[f] = (face_mat(i, f), i.group)
    names = sorted({m for m, _ in per_face.values()})
    me.materials.clear()
    for n in names:
        me.materials.append(bc.mat(n))
    idx = {n: k for k, n in enumerate(names)}
    mi = [0] * len(me.polygons)
    grp = [0] * len(me.polygons)
    isl = [0] * len(me.polygons)
    for k, i in enumerate(isls):
        for f in i.faces:
            mi[f] = idx[per_face[f][0]]
            grp[f] = GROUPS.index(per_face[f][1])
            isl[f] = k
    me.polygons.foreach_set("material_index", mi)
    me.attributes.new("grp", "INT", "FACE").data.foreach_set("value", grp)
    me.attributes.new("isl", "INT", "FACE").data.foreach_set("value", isl)


def select_only(o) -> None:
    for x in bpy.context.view_layer.objects:
        x.select_set(x == o)
    bpy.context.view_layer.objects.active = o


def split(o, attr: str, keep) -> bpy.types.Object | None:
    """Moves the faces of `o` whose attribute `attr` satisfies keep(value) into a new object, returned."""
    vals = [0] * len(o.data.polygons)
    o.data.attributes[attr].data.foreach_get("value", vals)
    sel = [bool(keep(v)) for v in vals]
    if not any(sel):
        return None
    if all(sel):
        return o
    select_only(o)
    before = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bm = bmesh.from_edit_mesh(o.data)
    bm.faces.ensure_lookup_table()
    for f, s in zip(bm.faces, sel):
        if s:
            f.select_set(True)
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    new = (set(bpy.data.objects) - before).pop()
    for x in (o, new):
        drop_unused_materials(x.data)
    return new


def drop_unused_materials(me) -> None:
    mi = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", mi)
    used = sorted(set(mi))
    mats = [me.materials[k] for k in used]
    remap = {k: n for n, k in enumerate(used)}
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", [remap[k] for k in mi])


def rework(o, isls: list) -> None:
    """Decimates the islands of `o` that have a ratio, and shades them and those to be renormalled anew (each on its
    own): smooth up to 40° (35° for the panels, whose normals then lean towards their larger faces). The model's own
    normals shade the paint in facets in Godot."""
    vals = [0] * len(o.data.polygons)
    o.data.attributes["isl"].data.foreach_get("value", vals)
    for k in sorted(set(vals)):
        if isls[k].ratio >= 1.0 and not isls[k].renormal:
            continue
        part = split(o, "isl", lambda v, k=k: v == k)
        if part is None:
            continue
        select_only(part)
        if part.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        if isls[k].ratio < 1.0:
            mod = part.modifiers.new("decimate", "DECIMATE")
            mod.ratio = isls[k].ratio
            bc.apply_modifiers(part)
        part.data.polygons.foreach_set("use_smooth", [True] * len(part.data.polygons))
        part.data.set_sharp_from_angle(angle=math.radians(35 if isls[k].renormal else 40))
        if isls[k].renormal:
            wn = part.modifiers.new("weighted", "WEIGHTED_NORMAL")
            wn.mode = "FACE_AREA"
            wn.weight = 50
            wn.keep_sharp = True
            bc.apply_modifiers(part)
        if part != o:
            bc.join(o, [o, part])


def tris(o) -> int:
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


GROUPS = ["body", "steering", "mirrors", "aerial", "indicator_left", "indicator_right", "brake_lights",
          "wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right", "hidden"]


def build(key: str, out_dir: Path, prev: str) -> None:
    c = CARS[key]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    load_fbx(ROOT / c["fbx"])
    body = bpy.data.objects[c["body"]]
    wheels = bpy.data.objects[c["wheels"]]
    # into the car frame: middle of the body box, the bottom of the tyres on the ground
    lo, hi = bounds(v.co for v in body.data.vertices)
    wlo, _ = bounds(v.co for v in wheels.data.vertices)
    shift = Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -wlo.z)))
    for o in (body, wheels):
        o.data.transform(shift)
    fbx_names = {o: [m.name.removeprefix("fbx ") if m else "" for m in o.data.materials] for o in (body, wheels)}
    pal = {o: [c["materials"].get(n, "plastic_black") for n in fbx_names[o]] for o in (body, wheels)}

    # body pieces
    bm = bmesh.new()
    bm.from_mesh(body.data)
    isls = islands(bm, pal[body])
    classify(c, isls)
    panes = glass(bm, isls, pal[body])
    bm.faces.ensure_lookup_table()
    centre = {f.index: f.calc_center_median() for f in bm.faces}
    normal = {f.index: f.normal.copy() for f in bm.faces}

    def body_mat(i, f):
        if i.remat:
            return i.remat
        if id(i) in panes:
            return panes[id(i)]
        m = pal[body][bm.faces[f].material_index]
        if m == "dash" and i.size.y > 2.0:        # the cabin shell: headliner over the heads, carpet on the floor
            if centre[f].z > 1.3 and abs(normal[f].z) > 0.3:
                return "headliner"
            if centre[f].z < 0.55 and abs(normal[f].z) > 0.6:
                return "carpet"
        return m
    set_faces(body, isls, body_mat)
    bm.free()

    # wheels: each piece to the wheel of its quarter, the callipers (they do not spin) to the body
    bm = bmesh.new()
    bm.from_mesh(wheels.data)
    wisl = islands(bm, pal[wheels])
    bm.free()
    tyres = [i for i in wisl if i.mat == "tyre" and i.size.z > 0.5]
    mid = sum((i.c for i in tyres), Vector()) / len(tyres)
    hubs = {}
    for i in wisl:
        stem = "front" if i.c.y < mid.y else "rear"
        i.group = f"wheel_{stem}_{'left' if i.c.x > mid.x else 'right'}"
        if i.mat == "alu":
            i.group, i.remat = "body", "caliper"
        elif i.mat in WHEEL_RATIO and i.tris > 800:
            i.ratio = WHEEL_RATIO[i.mat]
        elif i.mat == "plastic_black":
            i.remat = "hub"
            i.ratio = WHEEL_RATIO["hub"] if i.tris > 800 else 1.0
    for i in tyres:
        hubs[i.group] = i.c.copy()
    set_faces(wheels, wisl, lambda i, f: i.remat or pal[wheels][wheels.data.polygons[f].material_index])

    objs = {}
    for src, parts in ((body, isls), (wheels, wisl)):
        for g in reversed(GROUPS):
            o = split(src, "grp", lambda v, g=g: v == GROUPS.index(g))
            if o is None:
                continue
            rework(o, parts)
            if g in objs:
                bc.join(objs[g], [objs[g], o])
            else:
                o.name = o.data.name = g
                objs[g] = o
    for name, p in hubs.items():
        o = objs[name]
        o.data.transform(Matrix.Translation(-p))
        o.location = p
    # steering wheel: hub on the axis of the rim (the normal of its plane, towards the driver), 12 o'clock up
    st = objs["steering"]
    pts = [v.co.copy() for v in st.data.vertices]
    lo, hi = bounds(pts)
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
    llo, lhi = bounds(local)
    hub = rot @ Vector(((llo.x + lhi.x) / 2, (llo.y + lhi.y) / 2, (llo.z + lhi.z) / 2))
    xf = Matrix.Translation(hub) @ rot
    st.data.transform(xf.inverted())
    st.matrix_world = xf
    print(f"steering wheel at {tuple(round(v, 3) for v in hub)}, axis {tuple(round(v, 3) for v in axis)}, "
          f"rim {lhi.x - llo.x:.3f} x {lhi.y - llo.y:.3f} m")
    bpy.data.objects.remove(objs.pop("hidden"))
    for o in objs.values():
        for a in ("grp", "isl"):
            if a in o.data.attributes:
                o.data.attributes.remove(o.data.attributes[a])
    for o in list(bpy.data.objects):
        if o not in objs.values():
            bpy.data.objects.remove(o)

    # cab: the driver's seat (cushion top) and eye, mirrored for the passenger
    k = c["cab"]
    seat_isl = [i for i in isls if i.remat == "seat" and i.c.x > 0.1 and i.c.y < 0.2 and i.size.z < 0.3]
    cushion = max(seat_isl, key=lambda i: i.tris)
    seat = Vector((cushion.c.x, cushion.c.y, cushion.hi.z))
    eye = Vector((seat.x, k["eye"][0], k["eye"][1]))
    print(f"driver seat {tuple(round(v, 3) for v in seat)}, eye {tuple(round(v, 3) for v in eye)}")

    out = out_dir / f"{key}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True,
                              export_texcoords=False)                 # untextured
    wheel_names = [g for g in GROUPS if g.startswith("wheel_")]
    layout = {
        "wheels": wheel_names,
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
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    total = sum(tris(o) for o in objs.values())
    print(f"{key}: {out} ({total} triangles: " + ", ".join(f"{n} {tris(o)}" for n, o in objs.items()) + ")")
    blo, bhi = bounds(v.co for v in objs["body"].data.vertices)
    print(f"body box {tuple(round(v, 3) for v in blo)} .. {tuple(round(v, 3) for v in bhi)}; wheels " +
          ", ".join(f"{n} {tuple(round(v, 3) for v in p)}" for n, p in sorted(hubs.items())))
    if prev:
        Path(prev).mkdir(parents=True, exist_ok=True)
        bc.preview(str(Path(prev) / key), {"length": bhi.y - blo.y}, {"eye": eye})


def main() -> None:
    a = bc.args()
    for key in ([a["car"]] if a["car"] else list(CARS)):
        build(key, Path(a["out_dir"]), a["preview"])


main()
