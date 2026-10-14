"""Builds the airport fire truck (a 6x6 crash tender on a heavy cab-over chassis, after ref/fire_truck.png) for the
drivable vehicles.

blender -b --factory-startup -P blender/vehicles/build_fire_truck.py -- [--out=godot/assets/cars/fire_truck.glb]
                                                                         [--preview=data/review/fire_truck]

Red cab and water tank body with a white stripe under the roof edge, white bumper, black grille and arches, three axles
of big off-road tyres (front steering, tandem rear), roller-shutter lockers, side ladder, roof hatch and hand rails,
blue beacons on the cab roof and in the grille, an amber beacon at the back, and the roof water cannon (a white
monitor with a long barrel) over the cab. Real PBR materials, like the bus (build_bus.py).
Blender space: metres, z up, front = -Y, left = +X, origin on the ground under the middle of the truck, which is also
its centre of mass (glTF/Godot: front = +Z, left = +X, as scripts/car.gd expects). Exports one "body" mesh, the wheel
objects (wheel_front_left ... wheel_rear_right, origin at the wheel centre), "mirrors" (outside the body box, so they do
not widen the collision box), the lamps scripts/fire_truck.gd lights (indicator_left/right, brake_lights,
beacon_left/right (blue), beacon_amber) and the water cannon: "monitor" turns about its local Y (glTF), its child
"monitor_barrel" pitches about its local X; at rest the barrel points straight ahead. <out>.json (next to the .glb)
names them and gives the nozzle tip in glTF coordinates.
--preview renders <prefix>_front.png and <prefix>_rear.png (Cycles, a few seconds each)."""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]

HW = 1.25                           # half width
FRONT, REAR = -4.50, 4.45           # cab front face, body rear face
WHEEL_R = 0.62                      # 14.00 R20 off-road tyres
WHEEL_W = 0.42
WHEEL_X = HW + 0.02 - WHEEL_W / 2   # outer tyre face just past the body side
RIM_R = 0.30
AXLES = (("front", -3.00), ("middle", 1.15), ("rear", 2.60))
ARCH = (0.70, 0.77)                 # black arches over the wheels: inner and outer radius
CAB = (-2.25, 1.30, 3.25)           # cab: rear y, bottom z, roof z
BODY = (-2.12, 1.40, 3.05)          # tank body: front y, bottom z, top z
LOCKER_Z = 0.55                     # lockers between the axles reach down to here
MONITOR = (-3.55, 3.30, 3.60)       # water cannon: y, base of the turning head, barrel pivot height
BARREL = 1.05                       # pivot to nozzle tip

# name: base colour, metallic, roughness, (emission strength)
MATERIALS = {
    "paint_red": ("#D7141A", 0.0, 0.42, 0.0),
    "paint_white": ("#F1F2F2", 0.0, 0.32, 0.0),
    "plastic_black": ("#17181A", 0.0, 0.65, 0.0),
    "chassis": ("#202124", 0.3, 0.6, 0.0),
    "grille": ("#0E0F11", 0.2, 0.5, 0.0),
    "chrome": ("#D9DDE1", 0.9, 0.18, 0.0),
    "alu": ("#B4B9BF", 0.5, 0.45, 0.0),
    "shutter": ("#9EA4AA", 0.3, 0.55, 0.0),
    "glass": ("#141C24", 0.0, 0.05, 0.0),
    "tyre": ("#1B1B1D", 0.0, 0.92, 0.0),
    "rim": ("#C3C7CC", 0.8, 0.3, 0.0),
    "hub": ("#4E5359", 0.6, 0.45, 0.0),
    "headlight": ("#E8EEF2", 0.2, 0.15, 0.6),
    "indicator": ("#FF8A00", 0.0, 0.3, 0.3),
    "brake": ("#8C1414", 0.0, 0.3, 0.2),
    "beacon_blue": ("#1F4FE0", 0.0, 0.2, 0.4),
    "beacon_amber": ("#FF9A10", 0.0, 0.2, 0.4),
    "monitor_white": ("#ECEDEE", 0.1, 0.35, 0.0),
    "nozzle": ("#8E959C", 0.8, 0.3, 0.0),
}


def args() -> dict:
    out = {"out": str(ROOT / "godot" / "assets" / "cars" / "fire_truck.glb"), "preview": ""}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        k, _, v = a.partition("=")
        out[k.lstrip("-")] = v
    return out


def srgb(h: str) -> tuple:
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def mat(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, metal, rough, emit = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = srgb(col)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = srgb(col)
        p.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = srgb(col)
    return m


# ---------------------------------------------------------------- parts (world space, joined per object at the end)

_parts: dict = {}                   # object name -> [part objects]


def put(group: str, bm: bmesh.types.BMesh, m: str, bevel: float = 0.0, seg: int = 2) -> None:
    """Adds the bmesh as a part of `group` with material `m`, its sharp edges bevelled by `bevel`."""
    if bevel > 0.0:
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(30)]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=seg, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(group)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(m))
    o = bpy.data.objects.new(group, me)
    bpy.context.scene.collection.objects.link(o)
    _parts.setdefault(group, []).append(o)


def box(group, lo, hi, m, bevel=0.02, seg=2) -> None:
    """Box between corners lo and hi."""
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=hi - lo, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(lo + hi) / 2, verts=bm.verts)
    put(group, bm, m, min(bevel, min(hi - lo) * 0.45), seg)


def side_box(group, s, lo, hi, m, bevel=0.02) -> None:
    """The box as given (for the left side, +X) when s > 0, else its mirror image on the right."""
    if s > 0:
        box(group, lo, hi, m, bevel)
    else:
        box(group, (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2]), m, bevel)


def mirrored_box(group, lo, hi, m, bevel=0.02) -> None:
    """The box on the left (+X, as given) and its mirror image on the right."""
    box(group, lo, hi, m, bevel)
    box(group, (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2]), m, bevel)


def cyl(group, centre, axis, r, depth, m, seg=24, r2=None, bevel=0.0) -> None:
    """Cylinder (cone with end radius r2) centred on `centre` along `axis`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    a = Vector(axis).normalized()
    rot = a.to_track_quat("Z", "Y" if abs(a.y) < 0.9 else "X").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centre) @ rot, verts=bm.verts)
    put(group, bm, m, bevel)


def sphere(group, centre, r, m, scale=(1, 1, 1), seg=20) -> None:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    put(group, bm, m)


def tube(group, pts, r, m, sides=10) -> None:
    """Round tube along a polyline (parallel-transport frames, closed ends)."""
    bm = bmesh.new()
    P = [Vector(p) for p in pts]
    rings = []
    normal = None
    for i, p in enumerate(P):
        d = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        normal = d.orthogonal().normalized() if normal is None else (normal - d * normal.dot(d)).normalized()
        side = d.cross(normal)
        rings.append([bm.verts.new(p + (normal * math.cos(a) + side * math.sin(a)) * r)
                      for a in (2 * math.pi * k / sides for k in range(sides))])
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    put(group, bm, m)


def prism(group, profile, x0, x1, m, bevel=0.0, seg=2) -> None:
    """Side-view outline [(y, z)] extruded across from x0 to x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in profile]
    b = [bm.verts.new((x1, y, z)) for y, z in profile]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    put(group, bm, m, bevel, seg)


def arch(group, y, x0, x1, m, a0=8.0, a1=172.0, n=16) -> None:
    """Black wheel arch over the wheel at y: a band between ARCH radii around the axle, from angle a0 to a1 (degrees,
    0 = towards the rear), across from x0 to x1."""
    prof = []
    for k in range(n + 1):
        t = math.radians(a0 + (a1 - a0) * k / n)
        prof.append((y + ARCH[1] * math.cos(t), WHEEL_R + ARCH[1] * math.sin(t)))
    for k in range(n, -1, -1):
        t = math.radians(a0 + (a1 - a0) * k / n)
        prof.append((y + ARCH[0] * math.cos(t), WHEEL_R + ARCH[0] * math.sin(t)))
    prism(group, prof, x0, x1, m)


def plate_on_slope(group, p0, p1, x_half, m, out=0.012, depth=0.01) -> None:
    """Thin plate across the truck on the sloped front face from side-view points p0 (bottom) to p1 (top), raised `out`
    off it (towards the front)."""
    d = Vector((0, p1[0] - p0[0], p1[1] - p0[1]))
    n = Vector((0, -d.z, d.y)).normalized()     # outward (towards -Y)
    if n.y > 0:
        n = -n
    bm = bmesh.new()
    corners = []
    for s in (0.0, 1.0):
        for x in (-x_half, x_half):
            corners.append(Vector((x, p0[0], p0[1])) + d * s + n * out)
    v = [bm.verts.new(c) for c in (corners[0], corners[1], corners[3], corners[2])]
    w = [bm.verts.new(c.co + n * depth) for c in v]
    bm.faces.new(v)
    bm.faces.new(list(reversed(w)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((v[i], v[j], w[j], w[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    put(group, bm, m)


# ---------------------------------------------------------------- the truck

def cab() -> None:
    y1, z0, z1 = CAB
    screen = ((FRONT, 2.05), (FRONT + 0.13, 3.10))      # windscreen bottom and top, raked back
    prism("body", [(FRONT, z0), (y1, z0), (y1, z1), (FRONT + 0.20, z1), screen[1], screen[0]], -HW, HW, "paint_red", 0.07, 3)
    # windscreen, its black surround, sun visor and wipers
    plate_on_slope("body", (FRONT - 0.002, 2.00), (FRONT + 0.135, 3.13), HW - 0.08, "plastic_black", out=0.004)
    plate_on_slope("body", (FRONT + 0.004, 2.08), (FRONT + 0.128, 3.04), HW - 0.14, "glass", out=0.012)
    box("body", (-HW + 0.05, FRONT - 0.10, 3.10), (HW - 0.05, FRONT + 0.22, 3.17), "plastic_black", 0.02)
    for x in (-0.55, 0.35):
        box("body", (x - 0.35, FRONT - 0.035, 2.05), (x + 0.35, FRONT - 0.01, 2.08), "plastic_black", 0.008)
    # grille: black panel with chrome slats and a badge bar over it
    box("body", (-0.95, FRONT - 0.02, 1.38), (0.95, FRONT + 0.05, 1.96), "grille", 0.02)
    for k in range(5):
        z = 1.45 + k * 0.11
        box("body", (-0.90, FRONT - 0.04, z), (0.90, FRONT - 0.01, z + 0.035), "chrome", 0.01)
    box("body", (-0.42, FRONT - 0.03, 1.98), (0.42, FRONT + 0.02, 2.02), "chrome", 0.01)
    # side windows, door handles and lines, steps behind the front wheel
    for s in (1, -1):
        x = s * (HW + 0.006)
        bm = bmesh.new()
        prof = [(FRONT + 0.25, 2.10), (-3.10, 2.10), (-3.10, 2.95), (FRONT + 0.32, 2.95)]
        v0 = [bm.verts.new((x, y, z)) for y, z in prof]
        v1 = [bm.verts.new((x + s * 0.01, y, z)) for y, z in prof]
        bm.faces.new(v0)
        bm.faces.new(list(reversed(v1)))
        for i in range(4):
            bm.faces.new((v0[i], v0[(i + 1) % 4], v1[(i + 1) % 4], v1[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        put("body", bm, "glass")
    mirrored_box("body", (HW - 0.01, -3.30, 1.95), (HW + 0.02, -3.12, 1.99), "plastic_black", 0.008)    # door handles
    for y in (FRONT + 0.22, -3.02):         # door shut lines
        mirrored_box("body", (HW - 0.002, y, 1.35), (HW + 0.006, y + 0.012, 3.0), "grille", 0.0)
    # under the cab: black lower front, corner blocks with the headlights, white bumper
    box("body", (-0.82, FRONT, 0.55), (0.82, CAB[0], z0 + 0.02), "plastic_black", 0.03)
    mirrored_box("body", (0.82, FRONT, 0.80), (HW, -3.80, z0 + 0.02), "plastic_black", 0.03)
    box("body", (-HW, FRONT - 0.13, 0.62), (HW, FRONT + 0.06, 1.02), "paint_white", 0.05)
    box("body", (-0.16, FRONT - 0.19, 0.70), (0.16, FRONT - 0.10, 0.82), "grille", 0.02)    # tow hook housing
    mirrored_box("body", (0.88, FRONT - 0.012, 1.06), (1.17, FRONT + 0.01, 1.24), "headlight", 0.01)
    for s in (1, -1):
        cyl("body", (s * 0.70, FRONT - 0.135, 0.90), (0, 1, 0), 0.055, 0.02, "headlight", 16)     # fog lamps
    for y in (AXLES[0][1],):
        arch("body", y, 0.80, HW + 0.03, "plastic_black", 8, 172)
        arch("body", y, -HW - 0.03, -0.80, "plastic_black", 8, 172)


def tank_body() -> None:
    y0, z0, z1 = BODY
    box("body", (-HW, y0, z0), (HW, REAR, z1), "paint_red", 0.09, 3)
    # white stripe under the roof edge (sides and back)
    mirrored_box("body", (HW - 0.01, y0 + 0.06, z1 - 0.27), (HW + 0.006, REAR - 0.06, z1 - 0.19), "paint_white", 0.0)
    box("body", (-HW + 0.06, REAR - 0.01, z1 - 0.27), (HW - 0.06, REAR + 0.006, z1 - 0.19), "paint_white", 0.0)
    # roller-shutter lockers: front of the body on both sides, and the back
    for s in (1, -1):
        side_box("body", s, (HW - 0.01, y0 + 0.12, 1.52), (HW + 0.014, -0.92, 2.70), "alu", 0.01)
        side_box("body", s, (HW - 0.01, y0 + 0.16, 1.56), (HW + 0.02, -0.96, 2.66), "shutter", 0.0)
        for k in range(18):
            z = 1.59 + k * 0.059
            side_box("body", s, (HW - 0.01, y0 + 0.16, z), (HW + 0.028, -0.96, z + 0.016), "alu", 0.0)
        side_box("body", s, (HW - 0.01, y0 + 0.16, 1.56), (HW + 0.042, -0.96, 1.62), "alu", 0.01)     # handle bar
        # louvred panel on the second bay
        side_box("body", s, (HW - 0.01, 0.10, 1.70), (HW + 0.016, 0.85, 2.45), "grille", 0.01)
        for k in range(8):
            z = 1.76 + k * 0.085
            side_box("body", s, (HW - 0.01, 0.13, z), (HW + 0.03, 0.82, z + 0.025), "alu", 0.0)
    box("body", (-0.95, REAR - 0.01, 1.55), (0.95, REAR + 0.014, 2.70), "alu", 0.01)
    box("body", (-0.91, REAR, 1.59), (0.91, REAR + 0.018, 2.66), "shutter", 0.0)
    for k in range(18):
        z = 1.62 + k * 0.058
        box("body", (-0.91, REAR, z), (0.91, REAR + 0.026, z + 0.016), "alu", 0.0)
    # lockers low between the axles and behind the tandem, with aluminium steps
    box("body", (-HW + 0.03, y0, LOCKER_Z), (HW - 0.03, AXLES[1][1] - ARCH[1] - 0.06, z0 + 0.05), "paint_red", 0.05)
    box("body", (-HW + 0.03, AXLES[2][1] + ARCH[1] + 0.06, 0.70), (HW - 0.03, REAR, z0 + 0.05), "paint_red", 0.05)
    mirrored_box("body", (HW - 0.06, y0 + 0.10, LOCKER_Z - 0.06), (HW + 0.03, AXLES[1][1] - ARCH[1] - 0.16, LOCKER_Z + 0.02), "alu", 0.01)
    for s in (1, -1):
        for ya, yb in ((y0 + 0.12, -0.75), (-0.70, AXLES[1][1] - ARCH[1] - 0.18)):
            side_box("body", s, (HW - 0.04, ya, LOCKER_Z + 0.08), (HW - 0.012, yb, z0 - 0.06), "grille", 0.0)
            side_box("body", s, (HW - 0.04, ya + 0.015, LOCKER_Z + 0.095), (HW - 0.008, yb - 0.015, z0 - 0.075), "paint_red", 0.012)
            yc = (ya + yb) / 2
            side_box("body", s, (HW - 0.02, yc - 0.12, z0 - 0.20), (HW + 0.012, yc + 0.12, z0 - 0.165), "alu", 0.008)
    # black arches and mud flaps over the tandem
    for _, y in AXLES[1:]:
        arch("body", y, 0.78, HW + 0.03, "plastic_black", 0, 180)
        arch("body", y, -HW - 0.03, -0.78, "plastic_black", 0, 180)
    mirrored_box("body", (0.80, AXLES[1][1] + ARCH[1] - 0.04, ARCH[1] + WHEEL_R - 0.08), (HW + 0.03, AXLES[2][1] - ARCH[1] + 0.04, z0 + 0.02), "plastic_black", 0.01)
    mirrored_box("body", (0.82, AXLES[2][1] + ARCH[1] + 0.01, 0.28), (HW, AXLES[2][1] + ARCH[1] + 0.03, 1.0), "plastic_black", 0.0)
    # side ladder (left), roof hatch, hand rails and amber beacon post
    for y in (-0.78, -0.40):
        box("body", (HW + 0.04, y - 0.02, 0.35), (HW + 0.08, y + 0.02, z1 + 0.15), "alu", 0.01)
    for k in range(9):
        z = 0.55 + k * 0.30
        box("body", (HW + 0.045, -0.78, z), (HW + 0.075, -0.40, z + 0.03), "alu", 0.008)
    box("body", (-0.92, y0 + 0.18, z1 - 0.02), (0.92, -0.55, z1 + 0.32), "shutter", 0.04)
    box("body", (-0.85, y0 + 0.25, z1 + 0.30), (0.85, -0.62, z1 + 0.34), "alu", 0.02)
    for s in (1, -1):
        x = s * (HW - 0.10)
        tube("body", [(x, -0.40, z1), (x, -0.40, z1 + 0.28), (x, REAR - 0.25, z1 + 0.28), (x, REAR - 0.25, z1)], 0.022, "alu")
        tube("body", [(x, 1.95, z1), (x, 1.95, z1 + 0.28)], 0.02, "alu")
    box("body", (0.95, REAR - 0.30, z1 - 0.01), (1.15, REAR - 0.10, z1 + 0.10), "plastic_black", 0.02)
    # rear: lamp clusters, number plate, bumper bar
    mirrored_box("body", (0.55, REAR - 0.01, 0.82), (1.15, REAR + 0.02, 1.22), "plastic_black", 0.015)
    box("body", (-0.26, REAR, 0.86), (0.26, REAR + 0.015, 0.98), "paint_white", 0.005)
    box("body", (-HW + 0.05, REAR - 0.05, 0.62), (HW - 0.05, REAR + 0.10, 0.74), "chassis", 0.02)


def chassis() -> None:
    mirrored_box("body", (0.42, FRONT + 0.25, 0.80), (0.52, REAR - 0.10, 1.12), "chassis", 0.01)
    for _, y in AXLES:
        cyl("body", (0, y, WHEEL_R), (1, 0, 0), 0.075, 2 * WHEEL_X - 0.3, "chassis", 12)
        sphere("body", (0, y, WHEEL_R + 0.02), 0.20, "chassis", (1.0, 0.8, 0.8), 14)
    box("body", (-0.40, -1.9, 0.62), (0.40, 3.2, 0.85), "chassis", 0.03)    # pump and pipework under the tank


def wheel(name: str, x: float, y: float) -> bpy.types.Object:
    """Lathed off-road wheel around X with chunky tread lugs: tyre, dished rim, hub, ring of rim holes. Outer face
    towards +X on the left."""
    left = x > 0
    o = WHEEL_W / 2
    sgn = 1.0 if left else -1.0
    R = WHEEL_R - 0.035                     # under the lugs
    prof = [  # (radius, axial towards the outer face, material of the segment starting here)
        (0.0, -o + 0.05, "hub"), (RIM_R, -o + 0.02, "tyre"), (R - 0.10, -o, "tyre"), (R - 0.03, -o + 0.03, "tyre"),
        (R, -o + 0.07, "tyre"), (R, o - 0.07, "tyre"), (R - 0.03, o - 0.03, "tyre"), (R - 0.10, o, "tyre"),
        (RIM_R, o - 0.02, "rim"), (RIM_R - 0.02, o - 0.04, "rim"), (0.20, o - 0.12, "rim"), (0.12, o - 0.12, "hub"),
        (0.11, o - 0.08, "hub"), (0.0, o - 0.08, "hub")]
    mats = ["tyre", "rim", "hub"]
    seg = 36
    bm = bmesh.new()
    rings = []
    for r, a, _ in prof:
        if r == 0.0:
            rings.append([bm.verts.new((sgn * a, 0.0, 0.0))])
        else:
            rings.append([bm.verts.new((sgn * a, r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg)))
                          for k in range(seg)])
    for j in range(len(prof) - 1):
        ra, rb = rings[j], rings[j + 1]
        mi = mats.index(prof[j][2])
        for k in range(seg):
            k1 = (k + 1) % seg
            if len(ra) == 1:
                f = bm.faces.new((ra[0], rb[k], rb[k1]))
            elif len(rb) == 1:
                f = bm.faces.new((ra[k], ra[k1], rb[0]))
            else:
                f = bm.faces.new((ra[k], ra[k1], rb[k1], rb[k]))
            f.material_index = mi
            f.smooth = True
    # tread: two staggered rows of lugs, angled like a chevron
    lugs = 22
    for k in range(lugs):
        for row in (0, 1):
            t = 2 * math.pi * (k + 0.5 * row) / lugs
            side = (row * 2 - 1) * 0.085
            lug = bmesh.ops.create_cube(bm, size=1.0)["verts"]
            bmesh.ops.scale(bm, vec=(0.17, 0.085, 0.06), verts=lug)
            bmesh.ops.rotate(bm, verts=lug, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(18 * (1 - 2 * row)), 4, "Z"))
            bmesh.ops.translate(bm, vec=(sgn * side, 0.0, R + 0.012), verts=lug)
            bmesh.ops.rotate(bm, verts=lug, cent=(0, 0, 0), matrix=Matrix.Rotation(t, 4, "X"))
            for f in {f for v in lug for f in v.link_faces}:
                f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in mats:
        me.materials.append(mat(n))
    wo = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(wo)
    wo.location = (x, y, WHEEL_R)
    holes = []
    for k in range(10):
        t = 2 * math.pi * (k + 0.5) / 10
        hb = bmesh.new()
        bmesh.ops.create_cone(hb, cap_ends=True, segments=12, radius1=0.028, radius2=0.028, depth=0.006)
        bmesh.ops.transform(hb, matrix=Matrix.Translation((sgn * (o - 0.118), 0.165 * math.cos(t), 0.165 * math.sin(t)))
                            @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=hb.verts)
        hm = bpy.data.meshes.new("hole")
        hb.to_mesh(hm)
        hb.free()
        hm.materials.append(mat("chassis"))
        ho = bpy.data.objects.new("hole", hm)
        bpy.context.scene.collection.objects.link(ho)
        ho.location = wo.location
        holes.append(ho)
    join(wo, [wo, *holes])
    wo.name = name
    return wo


def mirrors() -> None:
    for s in (1, -1):
        x = s * (HW + 0.24)
        tube("mirrors", [(s * (HW - 0.02), FRONT + 0.25, 2.92), (x, FRONT + 0.22, 2.98), (x, FRONT + 0.22, 2.30),
                         (s * (HW - 0.02), FRONT + 0.25, 2.30)], 0.018, "plastic_black")
        box("mirrors", (x - 0.05, FRONT + 0.14, 2.45), (x + 0.05, FRONT + 0.30, 2.93), "plastic_black", 0.03)
        box("mirrors", (x - 0.03, FRONT + 0.13, 2.48), (x + 0.03, FRONT + 0.14, 2.90), "chrome", 0.0)
        box("mirrors", (x - 0.05, FRONT + 0.14, 2.30), (x + 0.05, FRONT + 0.28, 2.42), "plastic_black", 0.02)


def lamps() -> None:
    for s, side in ((1, "left"), (-1, "right")):
        # indicators: bumper corners, cab sides, rear clusters
        side_box(f"indicator_{side}", s, (1.02, FRONT - 0.145, 0.78), (1.20, FRONT - 0.12, 0.90), "indicator", 0.01)
        side_box(f"indicator_{side}", s, (HW, -3.75, 1.42), (HW + 0.015, -3.62, 1.48), "indicator", 0.005)
        side_box(f"indicator_{side}", s, (0.60, REAR + 0.02, 1.08), (0.85, REAR + 0.035, 1.18), "indicator", 0.005)
        side_box("brake_lights", s, (0.88, REAR + 0.02, 0.86), (1.12, REAR + 0.035, 1.02), "brake", 0.005)
        side_box("body", s, (0.60, REAR + 0.02, 0.86), (0.85, REAR + 0.03, 1.02), "headlight", 0.005)   # reversing lamps
        # blue beacons: domes on the cab roof corners, flashers in the black lower front
        x = s * 0.98
        cyl("body", (x, FRONT + 0.42, CAB[2] + 0.03), (0, 0, 1), 0.13, 0.06, "plastic_black", 20)
        cyl(f"beacon_{side}", (x, FRONT + 0.42, CAB[2] + 0.13), (0, 0, 1), 0.11, 0.16, "beacon_blue", 20, r2=0.09)
        sphere(f"beacon_{side}", (x, FRONT + 0.42, CAB[2] + 0.21), 0.09, "beacon_blue", (1, 1, 0.6), 16)
        side_box(f"beacon_{side}", s, (0.30, FRONT - 0.012, 1.10), (0.62, FRONT + 0.01, 1.18), "beacon_blue", 0.01)
        side_box(f"beacon_{side}", s, (1.0, REAR + 0.005, BODY[2] - 0.12), (1.2, REAR + 0.03, BODY[2] - 0.04), "beacon_blue", 0.01)
    cyl("beacon_amber", (1.05, REAR - 0.20, BODY[2] + 0.18), (0, 0, 1), 0.10, 0.16, "beacon_amber", 20, r2=0.085)
    sphere("beacon_amber", (1.05, REAR - 0.20, BODY[2] + 0.26), 0.085, "beacon_amber", (1, 1, 0.6), 16)


def monitor() -> tuple:
    """Water cannon over the cab: a fixed pedestal (body), the turning head ("monitor", origin on the yaw axis) and
    the barrel ("monitor_barrel", its child, origin on the pitch axis). Returns them and the nozzle tip (world)."""
    y, zb, zp = MONITOR
    cyl("body", (0, y, CAB[2] + 0.03), (0, 0, 1), 0.24, 0.08, "plastic_black", 24)
    cyl("body", (0, y, (CAB[2] + zb) / 2 + 0.03), (0, 0, 1), 0.15, zb - CAB[2] - 0.02, "monitor_white", 24)
    # head: swivel drum, yoke cheeks with their motors, a hose elbow behind
    cyl("monitor", (0, y, zb + 0.06), (0, 0, 1), 0.17, 0.12, "monitor_white", 24, bevel=0.02)
    for s in (1, -1):
        side_box("monitor", s, (0.12, y - 0.14, zb + 0.08), (0.19, y + 0.16, zp + 0.13), "monitor_white", 0.04)
        cyl("monitor", (s * 0.25, y + 0.02, zp), (1, 0, 0), 0.075, 0.12, "nozzle", 16, bevel=0.01)
    tube("monitor", [(0, y + 0.10, zb + 0.10), (0, y + 0.22, zb + 0.18), (0, y + 0.18, zp - 0.02)], 0.07, "monitor_white", 14)
    # barrel: a thick pipe out of the yoke, then the thinner barrel and the nozzle with its black tip
    cyl("monitor_barrel", (0, y + 0.02, zp), (1, 0, 0), 0.10, 0.24, "monitor_white", 20)
    cyl("monitor_barrel", (0, y - 0.22, zp), (0, 1, 0), 0.085, 0.44, "monitor_white", 20, bevel=0.01)
    cyl("monitor_barrel", (0, y - 0.70, zp), (0, 1, 0), 0.055, 0.56, "monitor_white", 18)
    cyl("monitor_barrel", (0, y - 0.97, zp), (0, 1, 0), 0.075, 0.06, "nozzle", 18, bevel=0.01)
    cyl("monitor_barrel", (0, y - BARREL + 0.03, zp), (0, 1, 0), 0.07, 0.06, "plastic_black", 18, r2=0.05)
    box("monitor_barrel", (-0.025, y - 0.62, zp + 0.05), (0.025, y - 0.30, zp + 0.08), "nozzle", 0.008)   # handle
    return Vector((0, y - BARREL, zp))


def join(target, objs: list) -> None:
    bpy.context.view_layer.update()
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()


def finish(group: str, origin=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    """Joins the parts of `group` into one object named after it, with its origin at `origin` and weighted normals
    (flat faces stay flat, the bevels shade softly; applied on export)."""
    objs = _parts.pop(group)
    target = objs[0]
    if len(objs) > 1:
        join(target, objs)
    target.name = group
    target.data.name = group
    target.data.transform(Matrix.Translation(-Vector(origin)))
    target.location = origin
    wn = target.modifiers.new("weighted", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    return target


# ---------------------------------------------------------------- main

def gd(v) -> list:
    """Blender point -> glTF/Godot (x, z, -y), rounded."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def preview(prefix: str) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.7, 0.95, 1.0)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    scene.collection.objects.link(sun)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    me = bpy.data.meshes.new("ground")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat("chassis"))
    ground = bpy.data.objects.new("ground", me)
    scene.collection.objects.link(ground)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for suffix, pos, look in (("front", (9.5, -10.5, 2.2), (0.3, -1.0, 1.6)),
                              ("rear", (-9.0, 10.0, 3.2), (0, 0.8, 1.5))):
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{suffix}.png"
        bpy.ops.render.render(write_still=True)
        print("preview", scene.render.filepath)
    bpy.data.objects.remove(ground)


def main() -> None:
    a = args()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    cab()
    tank_body()
    chassis()
    mirrors()
    lamps()
    tip = monitor()
    objs = [finish(g) for g in ("body", "mirrors", "indicator_left", "indicator_right", "brake_lights", "beacon_left",
                                "beacon_right", "beacon_amber")]
    head = finish("monitor", (0.0, MONITOR[0], MONITOR[1]))
    barrel = finish("monitor_barrel", (0.0, MONITOR[0], MONITOR[2]))
    bpy.context.view_layer.update()
    barrel.parent = head
    barrel.matrix_parent_inverse = head.matrix_world.inverted()
    objs += [head, barrel]
    wheels = []
    for stem, y in AXLES:
        for side, x in (("left", WHEEL_X), ("right", -WHEEL_X)):
            wheels.append(wheel(f"wheel_{stem}_{side}", x, y))
    objs += wheels
    out = Path(a["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True)
    layout = {
        "wheels": [w.name for w in wheels],
        "indicators": {"left": ["indicator_left"], "right": ["indicator_right"]},
        "brake_lights": ["brake_lights"],
        "beacons": {"left": ["beacon_left"], "right": ["beacon_right"], "amber": ["beacon_amber"]},
        "monitor": "monitor",
        "barrel": "monitor_barrel",
        "nozzle": gd(tip),
    }
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print(f"fire truck: {out} ({tris} triangles)")
    if a["preview"]:
        Path(a["preview"]).parent.mkdir(parents=True, exist_ok=True)
        preview(a["preview"])


main()
