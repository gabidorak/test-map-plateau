"""Builds the Île-de-France Mobilités city buses (Iveco Urbanway CNG) for the drivable vehicles: the 12 m bus and the
18 m articulated bus.

blender -b --factory-startup -P blender/vehicles/build_bus.py -- [--model=12m|artic]
                                                                  [--out=godot/assets/cars/bus_idfm.glb]
                                                                  [--preview=data/review/bus_idfm]

Livery after ref/busidfm1.jpg and ref/busidfm2.jpeg: silver lower body, sky-blue front wrapping the corners and
the A-pillars, dark tinted flush glazing, blue line under the white roof, CNG tank fairing on the roof, glass doors on
the right, "îledeFrance mobilités" logos, amber destination display. Real PBR materials (not the toy prop
shader); the glazing is tinted see-through. Walkable interior: low floor, seats (pairs on the left, singles on the
right, rear bench), wheel housings, yellow grab poles with stop buttons, driver cab, Navigo validator, ceiling lights.
Blender space: metres, z up, front = -Y, left = +X, origin on the ground under the middle of the bus (glTF/Godot:
front = +Z, left = +X, as scripts/car.gd expects). Exports one "body" mesh, the wheel objects (wheel_front_left,
wheel_front_right, wheel_rear_left, wheel_rear_right) with their origin at the wheel centre, and the moving parts
scripts/car.gd animates: door leaves door<i>_a/b (sliding plug doors, a = front leaf), indicator_left/right, brake_lights,
steering (the steering wheel, spins about its local Z = glTF Y; a name ending in "_wheel" would become a
VehicleWheel3D in Godot's importer), and "mirrors" (outside the body box, so they do not widen the collision box). <out>.json (next to the .glb) gives car.gd the layout in glTF
coordinates: collision boxes (the door boxes tagged with their door), doors, interior box, floor height, driver seat,
eye and exit point.

The bus is described as sections (Section): rigid bodies with a plan extent, two ends and their fittings. The 12 m bus
is one section with a nose and a tail. The articulated bus (--model=artic, out bus_idfm_artic.glb, an Urbanway 18 m)
is a front section (nose and cab, front and middle axles, two doors) and a rear section (driven rear axle, two doors,
rear bench), both open at the joint onto a rubber flange, with a turntable plate in the floor over the hitch. The
layout's "trailer" lists the rear section's objects (body_rear, wheel_rear_*, door2/3 leaves, indicator_*_rear,
brake_lights), colliders, doors and interior, in its own frame (the same as the front's while the bus is straight);
"hitch" is the pivot, "bellows" the profile car.gd builds the bellows from at runtime so that it bends with the joint,
"turntable" the walkable floor disc over the hitch.
--preview renders <prefix>_front.png, <prefix>_rear.png and <prefix>_interior.png (Cycles, a few seconds each), with a
straight bellows for the articulated bus."""
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_BOOK = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

# body (m)
HW = 2.55 / 2                       # half width
RF, RR = 0.32, 0.22                 # plan corner radii, front and rear
RJ = 0.06                           # plan corner radius at an open end (articulation)
WHEEL_R = 0.48
ARCH_R = 0.56
Z_BOTTOM = 0.30                     # low floor skirt
Z_BELT = 1.45                       # bottom of the side glazing (about seated shoulder height, as on real city buses)
Z_SCREEN = 1.05                     # bottom of the windscreen, which comes down lower
Z_LINE = 2.74                       # blue line under the roof...
Z_WHITE = 2.82                      # ...then white
Z_SHOULDER = 2.95
Z_ROOF = 3.07
DOOR_TOP = 2.62
RAIL_H = 1.92                       # overhead grab rails, above the floor (clear of heads)
GLASS_T = 0.018                     # posts, sills and panels on the glazing go through it (no coplanar faces)
FLOOR_Z = 0.36                      # low floor, level with the door sills
CEIL_Z = 2.72
WALL_T = 0.07                       # side walls (collision); the inner panels sit 4 cm inside the skin
IN_HW = HW - WALL_T
WHEEL_W = {"front": 0.30, "rear": 0.55}
HOUSING_TOP = WHEEL_R + ARCH_R + 0.04
PAIR_X, SINGLE_X = IN_HW - 0.44, -(IN_HW - 0.22)      # seat centres: pairs on the left, singles on the right
SEAT_W = 0.44

# articulation (articulated bus): the front section ends at JOINT[0], the rear one starts at JOINT[1]; the flanges
# stick out FLANGE_T into the gap, the bellows spans the rest. Hitch: pivot of the joint, low under the turntable.
JOINT = (0.80, 1.70)
FLANGE_T = 0.05
HITCH = (1.25, 0.50)                # y, z
TURNTABLE_R = 0.95                  # visible plate; the walkable floor disc (collision) is larger
TURNTABLE_FLOOR_R = 1.15            # reaches the corners of both floors at any articulation angle
# bellows profile: ridges (rounded rectangle), valleys DEPTH inside; hangs a little below the skirt so that its
# valleys stay under the floor level inside
BELLOWS = {"half_width": HW - 0.025, "bottom": Z_BOTTOM - 0.06, "top": Z_ROOF - 0.03, "radius": 0.20, "depth": 0.07,
           "folds": 9}
JOINT_WALL_X = 1.05                 # inner face of the walls the player meets inside the bellows


@dataclass
class Section:
    """One rigid body of a bus: plan extent (front y0 < y1), ends and fittings, all y in Blender space. nose: the front
    end has the windscreen and the driver cab, else it is open onto the bellows; tail: the rear end has the lights and
    the rear window, else it is open onto the bellows."""
    name: str                       # body mesh
    y0: float
    y1: float
    nose: bool
    tail: bool
    axles: list                     # [(y, tyres "front" (single) | "rear" (twin), wheel object name stem)]
    doors: list                     # [(door number, centre y, width)] on the right
    posts: list                     # window posts
    logo_bays: dict                 # side: (start y, end y) of the window bay filled by the black logo panel
    seats: list                     # forward-facing [(x centre, y, seats wide)]; raised when y is an axle
    poles: dict                     # "left"/"right": y of the vertical poles with stop buttons on the aisle rails
    markers: list                   # amber side markers
    repeaters: list                 # side indicator repeaters [(y, z)]
    roof: list                      # [("cng" | "ac", start y, end y)]
    light: tuple                    # ceiling light strips: centre y, length
    text_y: float = None            # "véhicule 100% gaz naturel" in the white band, on both sides
    rest_y: float = None            # pushchair / wheelchair area with a padded rest on the left
    suffix: str = ""                # added to the names of the section's indicators
    colliders: list = field(default_factory=list)   # (centre, size, door index in self.doors or None)

    @property
    def rf(self):
        return RF if self.nose else RJ

    @property
    def rr(self):
        return RR if self.tail else RJ

    @property
    def blue_end(self):             # the blue front wraps the lower corners up to here
        return self.y0 + 0.60 if self.nose else -math.inf

    @property
    def pillar_end(self):           # blue A-pillar on the sides, behind the wrap-around windscreen
        return self.y0 + 0.50 if self.nose else -math.inf

    @property
    def cab(self):                  # driver cab: inner side x, partition y (front of it up to the dashboard)
        return 0.06, self.y0 + 1.64

    @property
    def driver(self):               # driver seat centre
        return 0.62, self.y0 + 1.30

    @property
    def validator(self):
        return -IN_HW + 0.16, self.y0 + 1.95

    @property
    def deck(self):                 # raised rear platform under the bench: start y, height
        return self.y1 - 1.1, 0.20

    @property
    def housings(self):             # wheel housings (inside): inner edge x (left side; mirrored on the right), y span
        return [(HW - 0.06 - WHEEL_W[k] - 0.05, a - ARCH_R - 0.06, a + ARCH_R + 0.06) for a, k, _ in self.axles]

    @property
    def door_spans(self):
        return [(yc - w / 2, yc + w / 2) for _, yc, w in self.doors]

    @property
    def splits(self):
        s = {y for a, b in self.door_spans for y in (a, b)} | {a + d for a, _, _ in self.axles for d in (-ARCH_R, ARCH_R)}
        if self.nose:
            s |= {self.blue_end, self.pillar_end}
        return sorted(s)

    def ring(self, inset=0.0, splits=None):
        return outline(HW, self.y0, self.y1, self.rf, self.rr, inset, self.splits if splits is None else splits)


BUS_12M = [Section(
    "body", -6.0, 6.0, nose=True, tail=True,
    axles=[(-3.25, "front", "wheel_front"), (2.65, "rear", "wheel_rear")],
    doors=[(0, -4.80, 1.15), (1, -0.15, 1.25), (2, 4.05, 1.2)],
    posts=[-4.2, -2.75, -1.3, 0.15, 1.6, 3.05, 4.5],
    logo_bays={"left": (-1.3, 0.15), "right": (1.6, 3.05)},
    seats=[(PAIR_X, y, 2) for y in (-3.25, -2.3, -1.5, 1.25, 2.65, 3.55, 4.35)]
    + [(SINGLE_X, y, 1) for y in (-3.25, -2.3, -1.5, 1.25, 2.65)],
    poles={"left": (-2.68, -0.75, 0.6, 3.05, 4.7), "right": (-2.68, 1.0, 3.05)},
    markers=[-4.7, -1.6, 1.4, 4.95], repeaters=[(-5.58, 0.62), (1.0, 0.45)],
    roof=[("cng", -4.7, 0.8), ("ac", 2.3, 4.5)], light=(0.3, 9.6), text_y=-2.4, rest_y=-0.15)]

# Urbanway 18 m: 2.8 m front overhang, axles 5.8 m apart, hitch 1.65 m behind the middle axle, driven rear axle
# 4.3 m behind the hitch; four doors
BUS_ARTIC = [
    Section(
        "body", -9.0, JOINT[0], nose=True, tail=False,
        axles=[(-6.2, "front", "wheel_front"), (-0.4, "rear", "wheel_middle")],
        doors=[(0, -7.80, 1.15), (1, -2.90, 1.25)],
        posts=[-7.2, -5.75, -4.3, -2.85, -1.4, 0.05],
        logo_bays={"left": (-4.3, -2.85), "right": (-1.4, 0.05)},
        seats=[(PAIR_X, y, 2) for y in (-6.2, -5.3, -4.5, -1.4, -0.4)] + [(SINGLE_X, y, 1) for y in (-6.2, -5.3, -4.5, -1.4, -0.4)],
        poles={"left": (-4.88, -3.9, -1.8, 0.4), "right": (-4.88, -1.8, 0.4)},
        markers=[-7.7, -4.6, -1.6], repeaters=[(-8.58, 0.62), (0.3, 0.45)],
        roof=[("cng", -7.7, -2.2), ("ac", -1.4, 0.3)], light=(-3.3, 7.8), text_y=-5.6, rest_y=-2.9),
    Section(
        "body_rear", JOINT[1], 9.0, nose=False, tail=True, suffix="_rear",
        axles=[(5.55, "rear", "wheel_rear")],
        doors=[(2, 2.60, 1.25), (3, 7.20, 1.2)],
        posts=[2.3, 3.75, 5.2, 6.65, 8.1],
        logo_bays={"left": (3.75, 5.2), "right": (3.75, 5.2)},
        seats=[(PAIR_X, y, 2) for y in (2.6, 3.4, 4.2, 5.55, 6.4, 7.2)] + [(SINGLE_X, y, 1) for y in (3.9, 4.7, 5.55)],
        poles={"left": (3.02, 4.7, 6.0, 7.7), "right": (4.32,)},
        markers=[2.2, 4.4, 8.3], repeaters=[(6.3, 0.45)],
        roof=[("cng", 2.4, 6.4)], light=(5.3, 6.6), text_y=5.4),
]
MODELS = {"12m": (BUS_12M, "bus_idfm"), "artic": (BUS_ARTIC, "bus_idfm_artic")}

# name: base colour, metallic, roughness, (emission strength)
MATERIALS = {
    "paint_silver": ("#B9BBBD", 0.55, 0.32, 0.0),
    "paint_blue": ("#4CA4E4", 0.05, 0.28, 0.0),
    "paint_white": ("#F2F4F5", 0.0, 0.32, 0.0),
    "glass": ("#0C1218", 0.0, 0.06, 0.0),
    "logo_panel": ("#0B0E12", 0.0, 0.25, 0.0),
    "windscreen": ("#18232D", 0.0, 0.04, 0.0),
    "plastic_grey": ("#9A9FA5", 0.1, 0.55, 0.0),
    "plastic_black": ("#16181B", 0.0, 0.65, 0.0),
    "frame_dark": ("#34383E", 0.2, 0.5, 0.0),
    "arch": ("#0E0F10", 0.0, 0.9, 0.0),
    "tyre": ("#1C1C1E", 0.0, 0.92, 0.0),
    "rim": ("#CDD1D6", 0.85, 0.28, 0.0),
    "hub": ("#55595F", 0.6, 0.45, 0.0),
    "logo_white": ("#FFFFFF", 0.0, 0.4, 0.0),
    "logo_sky": ("#7CC4EE", 0.0, 0.35, 0.0),
    "text_black": ("#1A1A1A", 0.0, 0.5, 0.0),
    "display_amber": ("#FFB020", 0.0, 0.5, 4.0),
    "headlight": ("#E8EEF2", 0.2, 0.15, 0.6),
    "taillight": ("#C81E1E", 0.0, 0.3, 0.8),
    "marker": ("#FF9A1A", 0.0, 0.3, 1.0),
    "plate": ("#F5F5F5", 0.0, 0.4, 0.0),
    "indicator": ("#FF8A00", 0.0, 0.3, 0.3),
    "brake": ("#8C1414", 0.0, 0.3, 0.2),
    "floor": ("#8A9097", 0.0, 0.85, 0.0),
    "floor_edge": ("#F2C200", 0.0, 0.6, 0.0),
    "panel": ("#D6DADF", 0.0, 0.5, 0.0),
    "ceiling": ("#EEF0F2", 0.0, 0.6, 0.0),
    "seat_fabric": ("#2B3C8F", 0.0, 0.95, 0.0),
    "seat_accent": ("#5DB2E8", 0.0, 0.9, 0.0),
    "seat_shell": ("#C4C9CF", 0.05, 0.45, 0.0),
    "pole": ("#F3C300", 0.35, 0.3, 0.0),
    "button_red": ("#D62828", 0.0, 0.35, 0.4),
    "lamp_white": ("#FFFFFF", 0.0, 0.5, 2.5),
    "dash": ("#2A2D33", 0.0, 0.6, 0.0),
    "validator": ("#8A919C", 0.2, 0.45, 0.0),
    "screen_green": ("#3DDC84", 0.0, 0.3, 1.5),
    "rubber": ("#1E2023", 0.0, 0.85, 0.0),
    "turntable": ("#6E747C", 0.6, 0.45, 0.0),
}
ALPHA = {"glass": 0.8, "windscreen": 0.5}       # dark tinted, interior faintly visible; both faces drawn


def args() -> dict:
    out = {"model": "12m", "out": "", "preview": ""}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        k, _, v = a.partition("=")
        out[k.lstrip("-")] = v
    if out["model"] not in MODELS:
        sys.exit(f"--model must be one of {', '.join(MODELS)}")
    if not out["out"]:
        out["out"] = str(ROOT / "godot" / "assets" / "cars" / (MODELS[out["model"]][1] + ".glb"))
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
    if name in ALPHA:
        p.inputs["Alpha"].default_value = ALPHA[name]
        m.surface_render_method = "BLENDED"
        m.use_backface_culling = False
    m.diffuse_color = srgb(col)
    return m


def new_obj(name: str, bm: bmesh.types.BMesh, mats: list, at=None) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in mats:
        me.materials.append(mat(n))
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if at is not None:
        o.location = at
    return o


# ---------------------------------------------------------------- shapes

def outline(hw, y0, y1, rf, rr, inset=0.0, splits=(), n=8) -> list:
    """Counter-clockwise (from above) rounded rectangle, front = y0. Returns [(Vector2, tag)], the tag of the
    segment starting at that point: front, fcorner, side, rcorner, rear. Same point count for any inset, so
    outlines at several heights can be lofted."""
    hw, y0, y1, rf, rr = hw - inset, y0 + inset, y1 - inset, rf - inset, rr - inset
    pts = []

    def arc(cx, cy, r, a0, tag):
        for i in range(n):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((Vector((cx + r * math.cos(a), cy + r * math.sin(a))), tag))

    arc(-hw + rf, y0 + rf, rf, 180, "fcorner")
    pts.append((Vector((-hw + rf, y0)), "front"))
    arc(hw - rf, y0 + rf, rf, 270, "fcorner")
    pts.append((Vector((hw, y0 + rf)), "side"))
    for y in sorted(splits):
        pts.append((Vector((hw, y)), "side"))
    arc(hw - rr, y1 - rr, rr, 0, "rcorner")
    pts.append((Vector((hw - rr, y1)), "rear"))
    arc(-hw + rr, y1 - rr, rr, 90, "rcorner")
    pts.append((Vector((-hw, y1 - rr)), "side"))
    for y in sorted(splits, reverse=True):
        pts.append((Vector((-hw, y)), "side"))
    return pts


def loft(name, rows, ring, face_mat, mats, top="paint_white", bottom="arch") -> bpy.types.Object:
    """Closed solid through outlines ring(inset) at heights rows = [(z, inset)]. face_mat(zc, tag, centre)
    names the material of each side face."""
    bm = bmesh.new()
    rings = []
    tags = None
    for z, inset in rows:
        pts = ring(inset)
        tags = [t for _, t in pts]
        rings.append([bm.verts.new((p.x, p.y, z)) for p, _ in pts])
    n = len(rings[0])
    for k in range(len(rings) - 1):
        zc = (rows[k][0] + rows[k + 1][0]) / 2
        for i in range(n):
            a, b = rings[k][i], rings[k][(i + 1) % n]
            f = bm.faces.new((a, b, rings[k + 1][(i + 1) % n], rings[k + 1][i]))
            c = (a.co + b.co) / 2
            f.material_index = mats.index(face_mat(zc, tags[i], c))
    bm.faces.new(list(reversed(rings[0]))).material_index = mats.index(bottom)
    bm.faces.new(rings[-1]).material_index = mats.index(top)
    return new_obj(name, bm, mats)


def strip(name, pts, keep, z0, z1, m) -> bpy.types.Object:
    """Vertical band along the outline segments whose midpoint passes keep(Vector2), outward facing."""
    bm = bmesh.new()
    n = len(pts)
    for i in range(n):
        p, q = pts[i][0], pts[(i + 1) % n][0]
        if not keep((p + q) / 2):
            continue
        vs = [bm.verts.new((p.x, p.y, z0)), bm.verts.new((q.x, q.y, z0)), bm.verts.new((q.x, q.y, z1)),
              bm.verts.new((p.x, p.y, z1))]
        bm.faces.new(vs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return new_obj(name, bm, [m])


def box(name, centre, size, m, rot=None) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if rot is not None:
        bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    return new_obj(name, bm, [m], at=centre)


def bar(name, p0, p1, w, h, m) -> bpy.types.Object:
    """Box of section w x h from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    rot = d.to_track_quat("Y", "Z" if abs(d.normalized().z) < 0.9 else "X").to_matrix().to_4x4()
    return box(name, (p0 + p1) / 2, (w, d.length, h), m, rot)


def cylinder(name, centre, axis, r, depth, m, seg=24) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth)
    rot = Vector(axis).to_track_quat("Z", "Y" if abs(axis[1]) < 0.9 else "X").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    return new_obj(name, bm, [m], at=centre)


def rounded_plate(name, w, h, r, depth, m) -> bpy.types.Object:
    """Rounded rectangle plate in the local XY plane (centred), depth along +Z from 0."""
    bm = bmesh.new()
    pts = [(p.x, p.y) for p, _ in outline(w / 2, -h / 2, h / 2, r, r, n=6)]
    lo = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    hi = [bm.verts.new((x, y, depth)) for x, y in pts]
    bm.faces.new(hi)
    bm.faces.new(list(reversed(lo)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, [m])


def section_ring(hw, z0, z1, r, n=6) -> list:
    """Rounded rectangle in a cross-section plane: [(x, z)], counter-clockwise seen from the front (-Y)."""
    return [(p.x, p.y) for p, _ in outline(hw, z0, z1, r, r, n=n)]


def frame_ring(name, y, depth, outer, inner, m) -> bpy.types.Object:
    """Flat frame across the bus between two rounded rectangles outer and inner = (half width, bottom, top, radius),
    from y to y + depth."""
    bm = bmesh.new()
    rings = []
    for hw, z0, z1, r in (outer, inner):
        pts = section_ring(hw, z0, z1, r)
        rings.append(([bm.verts.new((x, y, z)) for x, z in pts], [bm.verts.new((x, y + depth, z)) for x, z in pts]))
    (o0, o1), (i0, i1) = rings
    n = len(o0)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((o0[k], o0[j], i0[j], i0[k]))
        bm.faces.new((o1[k], i1[k], i1[j], o1[j]))
        bm.faces.new((o0[k], o1[k], o1[j], o0[j]))
        bm.faces.new((i0[k], i0[j], i1[j], i1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, [m])


_fonts = {}


def text(s, size, m, font=FONT_BOLD, depth=0.002) -> bpy.types.Object:
    """Text mesh in the local XY plane, baseline at y = 0 from x = 0, extruded towards +Z from 0."""
    if font not in _fonts:
        _fonts[font] = bpy.data.fonts.load(font)
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    cu.font = _fonts[font]
    cu.size = size
    cu.extrude = depth / 2
    cu.resolution_u = 3
    tmp = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    me.transform(Matrix.Translation((0, 0, depth / 2)))
    me.materials.clear()
    me.materials.append(mat(m))
    o = bpy.data.objects.new("txt_" + s[:12], me)
    bpy.context.scene.collection.objects.link(o)
    return o


def width(o) -> float:
    xs = [v.co.x for v in o.data.vertices]
    return max(xs) if xs else 0.0


def face(side: str, a: float, z: float, off: float = 0.004, end: float = 0.0) -> Matrix:
    """Frame on a body face: local X along the reading direction, Y up, Z out of the face. `a` is the
    position along the face (y on the sides, x at the front and the rear); `end` is the y of the front or rear face."""
    if side == "left":
        rows = ((0, 0, 1, HW + off), (1, 0, 0, a), (0, 1, 0, z))
    elif side == "right":
        rows = ((0, 0, -1, -HW - off), (-1, 0, 0, a), (0, 1, 0, z))
    elif side == "front":
        rows = ((1, 0, 0, a), (0, 0, -1, end - off), (0, 1, 0, z))
    else:
        rows = ((-1, 0, 0, a), (0, 0, 1, end + off), (0, 1, 0, z))
    return Matrix((*rows, (0, 0, 0, 1)))


def place(objs: list, frame: Matrix) -> list:
    """Moves parts built in a local frame (rotations baked in their meshes, offsets in .location) onto it."""
    for o in objs:
        o.matrix_world = frame @ Matrix.Translation(o.location)
    return objs


def join(target, objs: list) -> None:
    bpy.context.view_layer.update()
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()


# ---------------------------------------------------------------- livery pieces

def idfm_symbol(s: float, z0: float = 0.0) -> list:
    """The IDFM pictogram, simplified: sky-blue rounded square with a white figure, lower left corner at the
    origin, side s."""
    sq = rounded_plate("symbol", s, s, s * 0.18, 0.002, "logo_sky")
    sq.location = (s / 2, s / 2, z0)
    w = s * 0.11
    legs = [bar("sym_leg_a", (s * 0.30, s * 0.18, z0 + 0.004), (s * 0.52, s * 0.62, z0 + 0.004), w, 0.003, "logo_white"),
            bar("sym_leg_b", (s * 0.72, s * 0.18, z0 + 0.004), (s * 0.52, s * 0.62, z0 + 0.004), w, 0.003, "logo_white")]
    head = cylinder("sym_head", (s * 0.52, s * 0.78, z0 + 0.004), (0, 0, 1), s * 0.09, 0.003, "logo_white", 16)
    return [sq, *legs, head]


def logo(h: float, colour: str = "logo_white", symbol: bool = True) -> list:
    """'îledeFrance' (cap height ~h) with 'mobilités' under its end and the pictogram on the right, centred
    on x = 0, baseline of 'îledeFrance' at y = 0. Local XY plane, facing +Z."""
    parts = []
    x = 0.0
    for word, font in (("île", FONT_BOLD), ("de", FONT_BOOK), ("France", FONT_BOLD)):
        t = text(word, h * 1.35, colour, font)
        t.location.x = x
        x += width(t) + h * 0.02
        parts.append(t)
    wt = x
    mob = text("mobilités", h * 0.55, colour, FONT_BOOK)
    mob.location = (wt - width(mob), -h * 0.62, 0.0)
    parts.append(mob)
    total = wt
    if symbol:
        s = h * 1.55
        sym = idfm_symbol(s)
        for o in sym:
            o.location.x += wt + h * 0.2
            o.location.y += -h * 0.55
        parts += sym
        total = wt + h * 0.2 + s
    for o in parts:
        o.location.x -= total / 2
    return parts


def door_leaves(i: int, yc: float, w: float) -> list:
    """The two glass leaves of door i (separate objects: car.gd slides them open), origin at the leaf centre,
    closed position flush with the skin. Leaf a is the front one."""
    zb, zt = Z_BOTTOM + 0.03, DOOR_TOP - 0.01
    lw, lh = w / 2 - 0.01, zt - zb
    leaves = []
    for s, tag in ((-1, "a"), (1, "b")):
        parts = [box("stile", (0, sy * (lw / 2 - 0.03), 0), (0.04, 0.06, lh), "plastic_grey") for sy in (-1, 1)]
        parts += [box("rail", (0, 0, sz * (lh / 2 - 0.04)), (0.04, lw - 0.1, 0.08), "plastic_grey") for sz in (-1, 1)]
        parts.append(box("kick", (0, 0, -lh / 2 + 0.08 + 0.13), (0.035, lw - 0.1, 0.26), "paint_silver"))
        parts.append(box("glass", (0, 0, 0.09 + 0.08), (0.014, lw - 0.1, lh - 0.16 - 0.26 - 0.02), "glass"))
        parts.append(box("seal", (0, -s * (lw / 2 + 0.005), 0), (0.05, 0.02, lh), "plastic_black"))
        leaf = parts[0]
        join(leaf, parts)
        # the parts were placed around the origin, but the joined object kept the first stile's: move its
        # pivot back to the leaf centre so the leaf lands centred on the opening
        leaf.data.transform(Matrix.Translation(leaf.location))
        leaf.location = (0, 0, 0)
        leaf.name = leaf.data.name = f"door{i}_{tag}"
        leaf.location = (-HW - 0.01, yc + s * (lw / 2 + 0.005), (zb + zt) / 2)
        leaves.append(leaf)
    return leaves


def indicators(s: Section) -> list:
    """Amber turn signals, one object per side (front on the bumper, side repeaters, rear above the tail lights),
    and the brake lights; car.gd swaps their material when they are lit."""
    objs = []
    for side, sx in (("left", 1), ("right", -1)):
        parts = []
        if s.nose:
            front = rounded_plate("ind_front", 0.24, 0.07, 0.03, 0.012, "indicator")
            front.matrix_world = face("front", sx * 0.80, 0.50, 0.016, s.y0)
            parts.append(front)
        if s.tail:
            parts.append(box("ind_rear", (sx * 0.88, s.y1 + 0.012, 1.34), (0.20, 0.03, 0.14), "indicator"))
        parts += [box("ind_side", (sx * (HW + 0.008), y, z), (0.02, 0.14, 0.06), "indicator") for y, z in s.repeaters]
        join(parts[0], parts)
        parts[0].name = parts[0].data.name = f"indicator_{side}{s.suffix}"
        objs.append(parts[0])
    if s.tail:
        brake = [box("brake", (sx * 0.88, s.y1 + 0.022, 0.80), (0.16, 0.02, 0.20), "brake") for sx in (-1, 1)]
        join(brake[0], brake)
        brake[0].name = brake[0].data.name = "brake_lights"
        objs.append(brake[0])
    return objs


def steering_wheel(s: Section) -> bpy.types.Object:
    """Rim, three spokes (3, 6 and 9 o'clock seen from the seat) and hub around the local Z axis, tilted towards the
    driver; local +Y is 12 o'clock, +X the driver's right. Light spokes and hub and a yellow band at 12 o'clock on the
    dark rim, so the cab view (car.gd) shows it turning."""
    bm = bmesh.new()
    seg, tube_seg, R, r = 48, 8, 0.24, 0.024
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c, d = Vector((math.cos(a), math.sin(a), 0)), Vector((0, 0, 1))
        rings.append([bm.verts.new(c * (R + r * math.cos(2 * math.pi * k / tube_seg)) + d * r * math.sin(2 * math.pi * k / tube_seg))
                      for k in range(tube_seg)])
    for i in range(seg):
        band = abs((i + 0.5) / seg * 360 - 90) < 12
        for k in range(tube_seg):
            a, b = rings[i], rings[(i + 1) % seg]
            f = bm.faces.new((a[k], b[k], b[(k + 1) % tube_seg], a[(k + 1) % tube_seg]))
            f.material_index = 1 if band else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim = new_obj("steering", bm, ["plastic_black", "pole"])
    parts = [rim, cylinder("hub", (0, 0, 0.012), (0, 0, 1), 0.075, 0.05, "plastic_grey"),
             cylinder("hub_cap", (0, 0, 0.04), (0, 0, 1), 0.045, 0.012, "logo_sky")]
    for a in (0, 180, 270):
        t = math.radians(a)
        parts.append(bar("spoke", (0, 0, 0.01), (R * math.cos(t), R * math.sin(t), 0), 0.045, 0.016, "plastic_grey"))
    join(rim, parts)
    rim.name = rim.data.name = "steering"
    axis = Vector((0, 0.55, 0.84)).normalized()        # up, leaning back towards the driver
    rim.matrix_world = Matrix.Translation((s.driver[0], s.cab[1] - 0.95, 1.16)) @ axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return rim


def mirrors(s: Section) -> bpy.types.Object:
    """The "rabbit ear" mirrors, an object of their own: outside the body box, so they do not widen the collision box."""
    y0 = s.y0
    parts = []
    for sx in (-1, 1):
        p0 = (sx * (HW - 0.10), y0 + 0.05, 2.62)
        p1 = (sx * (HW + 0.12), y0 - 0.42, 2.55)
        p2 = (sx * (HW + 0.12), y0 - 0.45, 2.05)
        parts.append(bar("mirror_arm", p0, p1, 0.05, 0.05, "plastic_black"))
        parts.append(bar("mirror_arm", p1, p2, 0.05, 0.05, "plastic_black"))
        parts.append(box("mirror", (sx * (HW + 0.12), y0 - 0.45, 1.88), (0.22, 0.08, 0.38), "plastic_black"))
    join(parts[0], parts)
    parts[0].name = parts[0].data.name = "mirrors"
    return parts[0]


def inner_skin(name, s: Section, profile, keep, m) -> bpy.types.Object:
    """Faces along the body outline between consecutive (inset, z) profile points, turned towards the cabin;
    keep(Vector2 midpoint, tag) selects the outline segments."""
    bm = bmesh.new()
    rings = [s.ring(inset) for inset, _ in profile]
    n = len(rings[0])
    for i in range(n):
        p, q = rings[0][i][0], rings[0][(i + 1) % n][0]
        if not keep((p + q) / 2, rings[0][i][1]):
            continue
        for k in range(len(profile) - 1):
            (za, zb) = profile[k][1], profile[k + 1][1]
            a0, a1 = rings[k][i][0], rings[k][(i + 1) % n][0]
            b0, b1 = rings[k + 1][i][0], rings[k + 1][(i + 1) % n][0]
            vs = [bm.verts.new((a0.x, a0.y, za)), bm.verts.new((a1.x, a1.y, za)), bm.verts.new((b1.x, b1.y, zb)),
                  bm.verts.new((b0.x, b0.y, zb))]
            f = bm.faces.new(vs)
            f.normal_update()
            c = f.calc_center_median()
            towards = Vector((0, min(max(c.y, s.y0 + 1.5), s.y1 - 1.5), 1.7)) - c
            if f.normal.dot(towards) < 0:
                f.normal_flip()
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return new_obj(name, bm, [m])


def cut(o, cutter) -> None:
    mod = o.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    mod.object = cutter
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter)


def collide(s: Section, lo, hi, door=None) -> None:
    """Registers a walkable-hull box of section s (written to the .json)."""
    lo, hi = Vector(lo), Vector(hi)
    s.colliders.append(((lo + hi) / 2, hi - lo, door))


def seat(s: Section, x, y, n) -> list:
    """Forward-facing seat block (n seats wide) centred on x, cushion centred on y; on a podium when y is an axle
    (over a wheel housing). Registers its collider."""
    raised = y in [a for a, _, _ in s.axles]
    w = n * SEAT_W
    base = HOUSING_TOP - 0.38 if raised else FLOOR_Z
    parts = []
    if raised:      # podium from the aisle to the wheel housing (which carries the outer part)
        xin = min(h[0] for h in s.housings if h[1] < y < h[2]) - 0.03
        a, b = abs(x) - w / 2 - 0.02, xin
        pc = math.copysign((a + b) / 2, x)
        parts.append(box("podium", (pc, y + 0.02, (FLOOR_Z - 0.03 + base) / 2), (b - a, 0.62, base - FLOOR_Z + 0.03), "panel"))
        parts.append(box("podium_edge", (pc, y - 0.29, base - 0.01), (b - a + 0.01, 0.03, 0.025), "floor_edge"))
    for k in range(n):
        sx = x + (k - (n - 1) / 2) * SEAT_W
        parts += [
            box("seat_shell", (sx, y, base + 0.40), (SEAT_W - 0.04, 0.44, 0.06), "seat_shell"),
            box("cushion", (sx, y - 0.01, base + 0.45), (SEAT_W - 0.07, 0.40, 0.05), "seat_fabric"),
            box("back_shell", (sx, y + 0.24, base + 0.75), (SEAT_W - 0.04, 0.05, 0.66), "seat_shell"),
            box("back", (sx, y + 0.21, base + 0.74), (SEAT_W - 0.07, 0.03, 0.56), "seat_fabric"),
            box("headrest", (sx, y + 0.20, base + 0.98), (SEAT_W - 0.085, 0.045, 0.10), "seat_accent"),
        ]
    if not raised:
        parts.append(box("pedestal", (x, y + 0.05, base + 0.37 / 2), (0.08, 0.30, 0.37), "seat_shell"))
    aisle = x - w / 2 + 0.03 if x > 0 else x + w / 2 - 0.03
    parts.append(box("grab", (aisle, y + 0.25, base + 1.10), (0.035, 0.035, 0.12), "pole"))
    collide(s, (x - w / 2, y - 0.24, FLOOR_Z), (x + w / 2, y + 0.28, base + 1.08))
    return parts


def pole(p0, p1, r=0.019) -> bpy.types.Object:
    p0, p1 = Vector(p0), Vector(p1)
    return cylinder("pole", (p0 + p1) / 2, tuple((p1 - p0).normalized()), r, (p1 - p0).length, "pole", 12)


def interior(s: Section) -> list:
    """Floor, inner panels, ceiling, wheel housings, door jambs, seats, poles, cab, validator and lights. Fills
    s.colliders with the walkable layout."""
    parts = []
    doors = s.door_spans
    y0, y1 = s.y0, s.y1

    # floor slab (yellow nosing at the doors), cut around the wheels
    floor = loft("floor", [(Z_BOTTOM + 0.005, 0.03), (FLOOR_Z, 0.03)], lambda i: outline(HW, y0, y1, s.rf, s.rr, i),
                 lambda *a: "floor", ["floor", "arch"], top="floor", bottom="arch")
    for xin, ya, yb in s.housings:
        for sx in (-1, 1):
            x0 = xin - 0.015                # under the housing's inner wall, off the wheel-well end cap
            cut(floor, box("floor_cut", (sx * (x0 + HW + 1.0) / 2, (ya + yb) / 2, 0.3),
                           (HW + 1.0 - x0, yb - ya, 1.0), "floor"))
    parts.append(floor)
    for a, b in doors:
        parts.append(box("nosing", (-HW + 0.06, (a + b) / 2, FLOOR_Z - 0.022), (0.13, b - a, 0.056), "floor_edge"))
        parts.append(box("nosing_line", (-HW + 0.20, (a + b) / 2, FLOOR_Z + 0.002), (0.05, b - a, 0.006), "floor_edge"))

    # inner panels up to the window sills (open at the doors), sill caps, ceiling with light strips
    def panel_keep(c, tag):     # not across the doors, the wheel housings (own panels), the windscreen nor open ends
        if tag in ("front", "fcorner") or (not s.tail and tag in ("rear", "rcorner")):
            return False
        if abs(c.x) > HW - 0.05 and any(ya < c.y < yb for _, ya, yb in s.housings):
            return False
        return not (c.x < 0 and abs(c.x) > HW - 0.05 and any(a - 0.01 < c.y < b + 0.01 for a, b in doors))
    parts.append(inner_skin("panel", s, [(0.0, Z_BELT), (0.04, Z_BELT), (0.04, FLOOR_Z)], panel_keep, "panel"))
    ceiling = loft("ceiling", [(CEIL_Z, 0.004), (CEIL_Z + 0.02, 0.004)], lambda i: outline(HW, y0, y1, s.rf, s.rr, i),
                   lambda *a: "ceiling", ["ceiling"], top="ceiling", bottom="ceiling")
    parts.append(ceiling)
    for sx in (-1, 1):
        parts.append(box("light", (sx * 0.62, s.light[0], CEIL_Z - 0.008), (0.12, s.light[1], 0.016), "lamp_white"))

    # door jambs, headers and poles
    for a, b in doors:
        for y in (a, b):
            parts.append(box("jamb", (-HW + 0.04, y, (FLOOR_Z + CEIL_Z) / 2), (0.09, 0.05, CEIL_Z - FLOOR_Z), "frame_dark"))
            yp = y - 0.08 if y == a else y + 0.08         # beside the opening, not in it
            parts.append(pole((-HW + 0.14, yp, FLOOR_Z), (-HW + 0.14, yp, CEIL_Z)))
        parts.append(box("header", (-HW + 0.0475, (a + b) / 2, (DOOR_TOP + CEIL_Z) / 2), (0.065, b - a, CEIL_Z - DOOR_TOP), "panel"))

    # wheel housings
    for xin, ya, yb in s.housings:
        for sx in (-1, 1):
            x0, x1 = xin - 0.03, HW - 0.04
            z0 = FLOOR_Z - 0.03             # sunk into the floor slab: no face on the floor plane
            housing = box("housing", (sx * (x0 + x1) / 2, (ya + yb) / 2, (z0 + HOUSING_TOP) / 2),
                          (x1 - x0, yb - ya, HOUSING_TOP - z0), "panel")
            # hollow it where the wheel turns (same cylinder as the arch pocket)
            cut(housing, cylinder("arch_cut", (sx * (xin + HW + 0.5) / 2, (ya + yb) / 2, WHEEL_R), (1, 0, 0), ARCH_R,
                                  HW + 0.5 - xin, "arch", 40))
            parts.append(housing)
            collide(s, (min(sx * x0, sx * x1), ya, FLOOR_Z), (max(sx * x0, sx * x1), yb, HOUSING_TOP))

    # seats, rear deck and bench
    for x, y, n in s.seats:
        parts += seat(s, x, y, n)
    if s.tail:
        y0d, hd = s.deck
        parts.append(box("deck", (0, (y0d + y1 - 0.12) / 2, FLOOR_Z + hd / 2), (2 * IN_HW, y1 - 0.12 - y0d, hd), "floor"))
        parts.append(box("deck_edge", (0, y0d + 0.01, FLOOR_Z + hd - 0.01), (2 * IN_HW - 0.01, 0.04, 0.026), "floor_edge"))
        collide(s, (-IN_HW, y0d, FLOOR_Z), (IN_HW, y1, FLOOR_Z + hd))
        bench_y = y1 - 0.5
        for k in range(5):
            sx = (k - 2) * SEAT_W
            base = FLOOR_Z + hd
            parts += [box("seat_shell", (sx, bench_y, base + 0.40), (SEAT_W - 0.04, 0.44, 0.06), "seat_shell"),
                      box("cushion", (sx, bench_y - 0.01, base + 0.45), (SEAT_W - 0.07, 0.40, 0.05), "seat_fabric"),
                      box("back", (sx, bench_y + 0.23, base + 0.74), (SEAT_W - 0.07, 0.04, 0.56), "seat_fabric"),
                      box("headrest", (sx, bench_y + 0.215, base + 0.98), (SEAT_W - 0.085, 0.05, 0.10), "seat_accent")]
        parts.append(box("bench_base", (0, bench_y + 0.02, FLOOR_Z + hd + 0.19), (5 * SEAT_W, 0.42, 0.38), "seat_shell"))
        collide(s, (-5 * SEAT_W / 2, bench_y - 0.24, FLOOR_Z), (5 * SEAT_W / 2, y1, FLOOR_Z + hd + 1.08))

    # pushchair / wheelchair area opposite the middle door: padded rest
    if s.rest_y is not None:
        parts.append(box("rest", (IN_HW - 0.06, s.rest_y, 0.95), (0.10, 1.1, 0.30), "seat_accent"))
        parts.append(box("rest_bar", (IN_HW - 0.14, s.rest_y, 1.18), (0.035, 1.2, 0.035), "pole"))

    # grab rails along the aisle, vertical poles with stop buttons
    rail_l, rail_r = PAIR_X - SEAT_W + 0.02, SINGLE_X + SEAT_W / 2 + 0.02
    rail_z = FLOOR_Z + RAIL_H
    ra = s.cab[1] + 0.1 if s.nose else y0 + 0.1
    rb = s.deck[0] - 0.05 if s.tail else y1 - 0.1
    for x in (rail_l, rail_r):
        parts.append(pole((x, ra, rail_z), (x, rb, rail_z)))
    for x, ys in ((rail_l, s.poles["left"]), (rail_r, s.poles["right"])):
        for y in ys:
            parts.append(pole((x, y, FLOOR_Z), (x, y, CEIL_Z)))
            parts.append(cylinder("stop_btn", (x - math.copysign(0.025, x), y, FLOOR_Z + 1.3), (1, 0, 0), 0.028, 0.03,
                                  "button_red", 12))

    # driver cab: dashboards, partition with glass top, cab door, seat; validator by the front door
    if s.nose:
        cab = s.cab
        parts.append(box("dash", ((cab[0] + HW - 0.1) / 2, y0 + 0.42, (FLOOR_Z + 1.12) / 2), (HW - 0.1 - cab[0], 0.66, 1.12 - FLOOR_Z), "dash"))
        parts.append(box("dash_r", (-(HW - 0.12) / 2, y0 + 0.30, (FLOOR_Z + 1.02) / 2), (HW - 0.12, 0.42, 1.02 - FLOOR_Z), "dash"))
        parts.append(box("dash_screen", (s.driver[0], y0 + 0.75, 1.13), (0.36, 0.02, 0.12), "screen_green"))
        parts.append(bar("column", (s.driver[0], y0 + 0.70, 0.95), (s.driver[0], cab[1] - 0.95, 1.14), 0.07, 0.07, "dash"))
        parts.append(box("partition", ((cab[0] + IN_HW) / 2, cab[1], (FLOOR_Z + 1.25) / 2), (IN_HW - cab[0], 0.05, 1.25 - FLOOR_Z), "panel"))
        parts.append(box("partition_glass", ((cab[0] + IN_HW) / 2 - 0.005, cab[1], 1.605), (IN_HW - cab[0] - 0.02, 0.015, 0.69), "glass"))
        door_a = y0 + 0.75                  # cab door, from the dashboard to the partition
        parts.append(box("cab_door", (cab[0], (cab[1] + door_a) / 2, (FLOOR_Z + 1.15) / 2), (0.04, cab[1] - door_a, 1.15 - FLOOR_Z), "panel"))
        parts.append(box("cab_rail", (cab[0], (cab[1] + door_a) / 2, 1.17), (0.05, cab[1] - door_a, 0.04), "pole"))
        dx, dy = s.driver
        parts += [box("driver_seat", (dx, dy, FLOOR_Z + 0.42), (0.5, 0.48, 0.10), "seat_fabric"),
                  box("driver_back", (dx, dy + 0.26, FLOOR_Z + 0.85), (0.5, 0.10, 0.80), "seat_fabric"),
                  box("driver_base", (dx, dy, FLOOR_Z + 0.18), (0.30, 0.30, 0.36), "dash")]
        collide(s, (cab[0] - 0.03, y0, FLOOR_Z), (HW, cab[1] + 0.03, 1.95))
        collide(s, (-HW, y0, FLOOR_Z), (0.0, y0 + 0.51, 1.02))
        vx, vy = s.validator
        parts += [box("validator_post", (vx, vy, (FLOOR_Z + 1.05) / 2), (0.08, 0.08, 1.05 - FLOOR_Z), "validator"),
                  box("validator", (vx + 0.02, vy, 1.15), (0.18, 0.12, 0.24), "validator"),
                  box("validator_screen", (vx + 0.112, vy, 1.18), (0.005, 0.08, 0.06), "screen_green")]
        collide(s, (vx - 0.1, vy - 0.08, FLOOR_Z), (vx + 0.12, vy + 0.08, 1.3))

    # walls, floor and roof; open ends have no end wall (the bellows walls are car.gd's)
    collide(s, (-HW, y0 + 0.05 if s.nose else y0, Z_BOTTOM), (HW, y1, FLOOR_Z))
    collide(s, (-HW, y0, CEIL_Z), (HW, y1, 3.40))
    wall0 = y0 + 0.2 if s.nose else y0
    collide(s, (IN_HW, wall0, FLOOR_Z), (HW, y1, CEIL_Z))
    if s.nose:
        collide(s, (-HW, y0, FLOOR_Z), (HW, y0 + 0.12, CEIL_Z))
    if s.tail:
        collide(s, (-HW, y1 - 0.1, FLOOR_Z), (HW, y1, CEIL_Z))
    edges = [wall0] + [y for a, b in doors for y in (a, b)] + [y1]
    for k in range(0, len(edges), 2):
        collide(s, (-HW, edges[k], FLOOR_Z), (-IN_HW, edges[k + 1], CEIL_Z))
    for i, (a, b) in enumerate(doors):
        collide(s, (-HW, a, FLOOR_Z), (-IN_HW + 0.02, b, DOOR_TOP), door=i)
    return parts


# ---------------------------------------------------------------- body

def flange(y: float, depth: float) -> bpy.types.Object:
    """Black rubber frame around an open section end, which the bellows is mounted on, from y to y + depth."""
    outer = (HW + 0.012, BELLOWS["bottom"] - 0.01, Z_ROOF + 0.005, 0.14)
    inner = (HW - 0.16, Z_BOTTOM + 0.0, Z_ROOF - 0.16, 0.12)
    return frame_ring("flange", y, depth, outer, inner, "rubber")


def body(s: Section) -> bpy.types.Object:
    y0, y1 = s.y0, s.y1
    blue_end, pillar_end = s.blue_end, s.pillar_end

    def face_mat(zc, tag, c):
        if s.nose and zc < Z_LINE and zc > Z_SCREEN and tag in ("front", "fcorner"):
            return "windscreen"
        if zc < Z_BELT:
            return "paint_blue" if c.y < blue_end else "paint_silver"
        if zc < Z_LINE:
            return "paint_blue" if c.y < pillar_end else "glass"
        return "paint_blue" if zc < Z_WHITE else "paint_white"

    rows = [(Z_BOTTOM, 0.05), (Z_BOTTOM + 0.06, 0.0), (Z_SCREEN, 0.0), (Z_BELT, 0.0), (DOOR_TOP, 0.0), (Z_LINE, 0.0), (Z_WHITE, 0.0),
            (Z_SHOULDER, 0.0), (3.01, 0.02), (3.045, 0.055), (Z_ROOF, 0.11)]
    mats = ["paint_silver", "paint_blue", "paint_white", "glass", "windscreen", "arch"]
    shell = loft(s.name, rows, s.ring, face_mat, mats)

    # wheel arches: one pocket per wheel, up to the wheel housing (a cut through the whole width would leave
    # its far face standing across the aisle)
    for xin, ya, yb in s.housings:
        for sx in (-1, 1):
            x0 = xin + 0.01                 # 1 cm short of the housing cavity's end (no coplanar caps)
            cut(shell, cylinder("arch_cut", (sx * (x0 + HW + 0.5) / 2, (ya + yb) / 2, WHEEL_R), (1, 0, 0), ARCH_R,
                                HW + 0.5 - x0, "arch", 40))
    # door openings in the right side, and the open ends at the joint (the flange covers the cut edge)
    bm = bmesh.new()
    bm.from_mesh(shell.data)

    def gone(f):
        c, n = f.calc_center_median(), f.normal
        if not s.nose and c.y < y0 + 0.1 and n.y < -0.1:
            return True
        if not s.tail and c.y > y1 - 0.1 and n.y > 0.1:
            return True
        return n.x < -0.5 and c.x < -HW + 0.06 and c.z < DOOR_TOP and any(yc - w / 2 < c.y < yc + w / 2 for _, yc, w in s.doors)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if gone(f)], context="FACES")
    bm.to_mesh(shell.data)
    bm.free()

    parts = [shell]
    pts = outline(HW, y0, y1, s.rf, s.rr, -0.012, s.splits)
    # dark trim line along the lower panels (not over the arches nor the doors)
    arches = [(a - ARCH_R - 0.02, a + ARCH_R + 0.02) for a, _, _ in s.axles]
    doors = s.door_spans

    def trim(p):
        if abs(p.x) < HW or p.y < blue_end or any(a < p.y < b for a, b in arches):
            return False
        return p.x > 0 or not any(a < p.y < b for a, b in doors)
    parts.append(strip("trim", pts, trim, 0.97, 1.0, "frame_dark"))
    if s.tail:
        parts.append(strip("rear_bumper", pts, lambda p: p.y > y1 - 0.12, Z_BOTTOM - 0.01, 0.50, "plastic_grey"))
    # window posts
    for y in s.posts:
        for sx in (-1, 1):
            if sx < 0 and any(a - 0.1 < y < b + 0.1 for a, b in doors):
                continue
            parts.append(box("post", (sx * (HW - 0.001), y, (Z_BELT + Z_LINE) / 2), (GLASS_T, 0.07, Z_LINE - Z_BELT), "frame_dark"))
    # sills, open at the doors on the right
    y_start = pillar_end if s.nose else y0 + 0.03
    y_end = y1 - s.rr if s.tail else y1 - 0.03
    for sx in (-1, 1):
        edges = [y_start] + ([y for a, b in doors for y in (a, b)] if sx < 0 else []) + [y_end]
        for k in range(0, len(edges), 2):
            parts.append(box("sill", (sx * (HW - 0.001), (edges[k] + edges[k + 1]) / 2, Z_BELT + 0.02),
                             (GLASS_T, edges[k + 1] - edges[k], 0.04), "frame_dark"))
    if s.nose:
        # front: grey bumper wrapping the corners, black intake, headlights, badge, logo and number
        parts.append(strip("bumper", pts, lambda p: p.y < y0 + 0.70, Z_BOTTOM - 0.01, 0.55, "plastic_grey"))
        parts.append(box("intake", (0, y0 - 0.02, 0.43), (1.1, 0.02, 0.14), "plastic_black"))
        for sx in (-1, 1):
            plate = rounded_plate("lamp_housing", 0.30, 0.20, 0.06, 0.01, "plastic_grey")
            plate.matrix_world = face("front", sx * 0.80, 0.72, 0.012, y0)
            parts.append(plate)
            for dx in (-0.075, 0.075):
                lens = cylinder("headlight", (sx * 0.80 + dx, y0 - 0.026, 0.72), (0, 1, 0), 0.055, 0.012, "headlight")
                parts.append(lens)
        badge = rounded_plate("badge", 0.82, 0.14, 0.05, 0.01, "plastic_black")
        badge.matrix_world = face("front", 0.0, 0.93, end=y0)
        parts.append(badge)
        iveco = text("IVECO", 0.095, "logo_white")
        iveco.location = (-width(iveco) / 2, -0.035, 0.0)
        parts += place([iveco], face("front", 0.0, 0.93, 0.016, y0))
        parts += place(logo(0.055), face("front", -0.33, 0.70, end=y0))
        num = text("211018", 0.075, "logo_white")
        num.location = (-width(num) / 2, 0.0, 0.0)
        parts += place([num], face("front", 0.25, 0.60, end=y0))
        # destination display and wipers on the windscreen
        disp = rounded_plate("display", 1.80, 0.24, 0.03, 0.008, "plastic_black")
        disp.matrix_world = face("front", 0.0, 2.60, end=y0)
        parts.append(disp)
        parts += place(logo(0.075, "display_amber", symbol=False), face("front", 0.0, 2.585, 0.012, y0))
        for sx in (-1, 1):
            parts.append(bar("wiper", (sx * 0.95, y0 - 0.015, 1.12), (sx * 0.25, y0 - 0.015, 1.55), 0.025, 0.02, "plastic_black"))

    # sides: logos, "100% gaz naturel", doors, side markers
    for side, (a, b) in s.logo_bays.items():
        sx = 1 if side == "left" else -1
        parts.append(box("logo_panel", (sx * (HW + 0.001), (a + b) / 2, (Z_BELT + Z_LINE) / 2 + 0.01), (GLASS_T + 0.008, b - a - 0.07, Z_LINE - Z_BELT - 0.04),
                         "logo_panel"))
        parts += place(logo(0.10), face(side, (a + b) / 2, 1.98, 0.016))
    if s.text_y is not None:
        for side in ("left", "right"):
            t = text("véhicule 100% gaz naturel", 0.085, "text_black")
            t.location.x = -width(t) / 2
            parts += place([t], face(side, s.text_y, 2.855))
    parts += interior(s)
    for y in s.markers:
        for sx in (-1, 1):
            if sx < 0 and any(abs(y - yc) < w / 2 + 0.1 for _, yc, w in s.doors):
                continue
            parts.append(box("marker", (sx * (HW + 0.006), y, 0.45), (0.02, 0.10, 0.05), "marker"))

    if s.tail:
        # rear: lights, plate, logo under the rear window
        for sx in (-1, 1):
            parts.append(box("taillight", (sx * 0.88, y1 + 0.01, 0.95), (0.20, 0.03, 0.62), "taillight"))
        parts.append(box("plate", (0, y1 + 0.01, 0.48), (0.52, 0.02, 0.11), "plate"))
        plate_txt = text("GZ-211-RF", 0.065, "text_black")
        plate_txt.location.x = -width(plate_txt) / 2
        parts += place([plate_txt], face("rear", 0.0, 0.455, 0.02, y1))
        parts += place(logo(0.10), face("rear", 0.0, 1.12, end=y1))

    # roof: CNG tank fairings and air conditioning
    for kind, a, b in s.roof:
        if kind == "cng":
            parts.append(loft("cng", [(Z_ROOF - 0.01, 0.0), (3.30, 0.0), (3.37, 0.06), (3.40, 0.16)],
                              lambda i, a=a, b=b: outline(1.05, a, b, 0.35, 0.35, i), lambda *x: "paint_white", ["paint_white"],
                              top="paint_white", bottom="paint_white"))
        else:
            parts.append(loft("ac", [(Z_ROOF - 0.01, 0.0), (3.24, 0.0), (3.30, 0.08)],
                              lambda i, a=a, b=b: outline(0.90, a, b, 0.25, 0.25, i), lambda *x: "paint_white", ["paint_white"],
                              top="paint_white", bottom="paint_white"))

    # articulation: rubber flanges on the open ends; the turntable plate (on the front section) over the hitch
    if not s.nose:
        parts.append(flange(y0 - FLANGE_T, FLANGE_T))
    if not s.tail:
        parts.append(flange(y1, FLANGE_T))
        parts.append(cylinder("turntable_ring", (0, HITCH[0], FLOOR_Z + 0.003), (0, 0, 1), TURNTABLE_R + 0.04, 0.006, "rubber", 48))
        parts.append(cylinder("turntable", (0, HITCH[0], FLOOR_Z + 0.006), (0, 0, 1), TURNTABLE_R, 0.010, "turntable", 48))
        for k in range(7):                  # anti-slip ribs
            yr = HITCH[0] + (k - 3) * 0.24
            half = math.sqrt(max(TURNTABLE_R ** 2 - (yr - HITCH[0]) ** 2, 0.0)) - 0.08
            parts.append(box("rib", (0, yr, FLOOR_Z + 0.012), (2 * half, 0.03, 0.004), "plastic_grey"))

    join(shell, parts)
    shell.name = s.name
    shell.data.name = s.name
    return shell


# ---------------------------------------------------------------- wheels

def wheel(name: str, x: float, y: float, w: float, left: bool) -> bpy.types.Object:
    """Lathed wheel around X: tyre, dished rim, hub, ring of rim holes. Outer face towards +X on the left."""
    o = w / 2
    dish = 0.05 if w < 0.4 else 0.12
    prof = [  # (radius, axial towards the outer face, material of the segment starting here)
        (0.0, -o + 0.03, "hub"), (0.30, -o, "tyre"), (0.42, -o, "tyre"), (0.465, -o + 0.03, "tyre"),
        (WHEEL_R, -o + 0.07, "tyre"), (WHEEL_R, o - 0.07, "tyre"), (0.465, o - 0.03, "tyre"), (0.42, o, "tyre"),
        (0.30, o, "rim"), (0.285, o - 0.02, "rim"), (0.20, o - dish, "rim"), (0.11, o - dish, "hub"),
        (0.10, o - dish + 0.03, "hub"), (0.0, o - dish + 0.03, "hub")]
    mats = ["tyre", "rim", "hub"]
    seg = 32
    bm = bmesh.new()
    sgn = 1.0 if left else -1.0
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
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    wo = new_obj(name, bm, mats, at=(x, y, WHEEL_R))
    holes = []
    for k in range(8):
        t = 2 * math.pi * (k + 0.5) / 8
        holes.append(cylinder("hole", (x + sgn * (o - dish + 0.002), y + 0.155 * math.cos(t), WHEEL_R + 0.155 * math.sin(t)),
                              (1, 0, 0), 0.032, 0.004, "arch", 12))
    join(wo, [wo, *holes])
    wo.name = name
    return wo


# ---------------------------------------------------------------- main

def gd(v) -> list:
    """Blender point -> glTF/Godot (x, z, -y), rounded."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def bellows_preview(y0: float, y1: float) -> bpy.types.Object:
    """Straight bellows between the flanges, for the preview renders only (car.gd builds the real one, bending)."""
    b = BELLOWS
    n = 2 * b["folds"]
    bm = bmesh.new()
    rings = []
    for k in range(n + 1):
        i = 0.0 if k % 2 == 0 else b["depth"]
        y = y0 + (y1 - y0) * k / n
        rings.append([bm.verts.new((x, y, z)) for x, z in
                      section_ring(b["half_width"] - i, b["bottom"] + i, b["top"] - i, b["radius"] - i)])
    m = len(rings[0])
    for k in range(n):
        for j in range(m):
            bm.faces.new((rings[k][j], rings[k][(j + 1) % m], rings[k + 1][(j + 1) % m], rings[k + 1][j]))
    return new_obj("bellows_preview", bm, ["rubber"])


def preview(prefix: str, length: float) -> None:
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
    ground = new_obj("ground", bm, ["plastic_grey"])
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    k = length / 12.0                       # camera distances scale with the bus
    for suffix, pos, look in (("front", (10.5 * k, -12.5 * k, 2.0 * k), (0.6, -2.0 * k, 1.4)),
                              ("rear", (-10.5 * k, 11.0 * k, 2.6 * k), (0, 0.5 * k, 1.4)),
                              ("interior", (-0.2, length / 2 - 1.4, 1.95), (0.1, -length / 2 + 2.0, 1.2))):
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{suffix}.png"
        bpy.ops.render.render(write_still=True)
        print("preview", scene.render.filepath)
    bpy.data.objects.remove(ground)


def section_layout(s: Section, interior_y: tuple, door_infos: list) -> dict:
    """Interior box (y span), colliders and doors of a section, in glTF coordinates."""
    return {
        "interior": [gd((-HW, interior_y[1], FLOOR_Z - 0.3)), gd((HW, interior_y[0], CEIL_Z))],
        "colliders": [{"center": gd(c), "size": [sz.x, sz.z, sz.y], **({"door": d} if d is not None else {})}
                      for c, sz, d in s.colliders],
        "doors": door_infos,
    }


def main() -> None:
    a = args()
    sections, _ = MODELS[a["model"]]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    objs, per_section, doors = [], [], []
    for s in sections:
        own = [body(s)]
        for y, kind, stem in s.axles:
            w = WHEEL_W[kind]
            own.append(wheel(f"{stem}_left", HW - 0.06 - w / 2, y, w, True))
            own.append(wheel(f"{stem}_right", -(HW - 0.06 - w / 2), y, w, False))
        door_infos = []
        for i, yc, w in s.doors:
            leaves = door_leaves(i, yc, w)
            own += leaves
            door_infos.append({"leaves": [o.name for o in leaves], "center": gd((-HW, yc, (Z_BOTTOM + DOOR_TOP) / 2)), "width": w})
        own += indicators(s)
        if s.nose:
            own.append(steering_wheel(s))
            own.append(mirrors(s))
        objs += own
        per_section.append(own)
        doors.append(door_infos)
    out = Path(a["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True)
    front = sections[0]
    lamps = [o.name for own in per_section for o in own]
    # the interiors overlap by 0.6 m past the hitch: wherever the player stands in the bent bellows, one of the
    # two sections carries them
    split = (HITCH[0] + 0.6, HITCH[0] - 0.6) if len(sections) > 1 else (front.y1, None)
    dx, dy = front.driver
    layout = {
        "floor_y": FLOOR_Z,
        **section_layout(front, (front.y0, split[0]), doors[0]),
        "driver_seat": gd((dx, dy, FLOOR_Z + 0.47)),
        "driver_eye": gd((dx, dy - 0.05, FLOOR_Z + 1.45)),
        "driver_exit": gd((-0.45, dy, FLOOR_Z + 0.05)),
        "indicators": {side: [n for n in lamps if n.startswith("indicator_" + side)] for side in ("left", "right")},
        "brake_lights": ["brake_lights"],
        "steering_wheel": "steering",
    }
    if len(sections) > 1:
        rear = sections[1]
        layout["trailer"] = {
            "nodes": [o.name for o in per_section[1]],
            "body": rear.name,
            "wheels": [f"{stem}_{side}" for _, _, stem in rear.axles for side in ("left", "right")],
            **section_layout(rear, (split[1], rear.y1), doors[1]),
        }
        b = BELLOWS
        layout["hitch"] = gd((0.0, HITCH[0], HITCH[1]))
        layout["bellows"] = {"front": round(-(JOINT[0] + FLANGE_T), 4), "rear": round(-(JOINT[1] - FLANGE_T), 4),
                             "half_width": round(b["half_width"], 4), "bottom": round(b["bottom"], 4), "top": round(b["top"], 4),
                             "radius": b["radius"], "depth": b["depth"], "folds": b["folds"],
                             "wall_x": JOINT_WALL_X, "ceiling": CEIL_Z}
        layout["turntable"] = {"center": gd((0.0, HITCH[0], (Z_BOTTOM + FLOOR_Z) / 2)), "radius": TURNTABLE_FLOOR_R,
                               "height": round(FLOOR_Z - Z_BOTTOM, 4)}
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print(f"bus: {out} ({tris} triangles, {sum(len(s.colliders) for s in sections)} colliders)")
    if a["preview"]:
        Path(a["preview"]).parent.mkdir(parents=True, exist_ok=True)
        if len(sections) > 1:
            bellows_preview(JOINT[0] + FLANGE_T, JOINT[1] - FLANGE_T)
        preview(a["preview"], sections[-1].y1 - sections[0].y0)


main()
