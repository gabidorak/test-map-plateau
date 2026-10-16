"""Builds the RER B train cars: the renovated MI 79 (MI 79 R) of RATP and SNCF that runs on the B4 branch through
Lozère, as two car models, the cab car and the intermediate car (a unit is cab, intermediate, intermediate, cab
turned round; a train is two units).

blender -b --factory-startup -P blender/vehicles/build_train.py -- [--out=godot/assets/cars/mi79.glb]
                                                                    [--preview=data/review/mi79]

Sources: the MI 79 elevation drawings (motor car with cab and intermediate car: 26.00 m over the couplers, bogie
wheelbase 2.40 m, floor 1.19 m above the rail, four double doors a side, the window rhythm), French Wikipedia
"MI 79" (2.80 m wide, units of four cars 104.16 m long, all cars motored, renovated 2010-2016 as MI 79 R) and
photos of MI 79 R trains (Wikimedia Commons: at Lozère, Bourg-la-Reine, Aulnay-sous-Bois, Denfert-Rochereau; the
renovated interior). Livery: white body, anthracite window band and skirt, a magenta and a teal stripe beside each
door, anthracite front with the amber LED destination display, RATP and SNCF badges. Interior: grey floor, white
walls and ceiling, anise-green seat backs over navy patterned seats in facing bays of 2 + 2, steel grab poles, light
strips; the cars of a unit are joined by gangways (end doors open), the units are not.

Blender space: metres, z up, front = -Y, left = +X, origin on the rail level under the middle of the car (glTF/Godot:
front = +Z, left = +X). One glTF with, per model (prefix "cab_" or "mid_"), the objects scripts/train.gd uses: "body"
(shell and livery), "interior" (fittings, hidden beyond a short distance), "far" (a light shell for the distance, the
only mesh drawn there), "bogie_front"/"bogie_rear" (origin on the pivot, turned to the rail by train.gd), the door
leaves "door<i>_<l|r>_<a|b>" (a = the front leaf; they slide outside the body), "head_lamps" and "tail_lamps" (cab
car: lit by train.gd per direction), "cabin_lights", "display" (cab car: the destination panel train.gd letters),
"pantograph" (intermediate car). <out>.json gives train.gd each model's layout in glTF coordinates: length, bogies,
floor, walkable colliders (the door boxes tagged with their door), doors, interior box, gangways, cab seat and eye,
lamp and display frames.
--preview renders <prefix>_side.png, <prefix>_front.png and <prefix>_interior.png (Cycles)."""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FONTS = ["C:/Windows/Fonts/arialbd.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]

# body (m; drawings and Wikipedia, see the docstring)
CAR = 26.00                         # over the couplers
HALF = 12.80                        # body ends from the middle: 0.40 m between bodies for the couplers and gangway
HW = 2.80 / 2                       # half width
R_END = 0.10                        # plan corner radius at a car end
R_NOSE = 0.30                       # plan corner radius at the cab front
BOGIE_Y = 9.55                      # bogie pivots from the middle (drawings: 3.5-3.7 m from the car ends)
WHEELBASE = 2.40
WHEEL_R = 0.45                      # m (worn 0.90 m wheels; assumed)
FLOOR = 1.19                        # floor above the rail (drawings)
Z_SKIRT = 0.96                      # bottom of the body sides
Z_SILL = 2.05                       # side windows (drawings: from about the seated shoulder to the door tops)
Z_WTOP = 2.88
DOOR_W = 1.30                       # door opening (two leaves)
DOOR_TOP = FLOOR + 1.95
Z_EAVE = 3.52
Z_ROOF = 4.02
CEIL = FLOOR + 2.16                 # ceiling above the floor (2.16 m clear, as an RER car's)
WALL_T = 0.08                       # side walls (collision)
IN_HW = HW - WALL_T
GANGWAY_W = 0.80                    # end doors of a unit's cars (the passage), photos of the interior
GANGWAY_H = 1.95
CAB_DEPTH = 2.20                    # cab from the front face to the partition (drawings: the cab door at 1.8 m)
SEAT_W = 0.47                       # per seat, 2 + 2 abreast
PITCH = 1.70                        # facing bay: the two rows' backs this far apart
AISLE_HW = 0.32                     # half the aisle
STRIPE_W = 0.12                     # each of the magenta and teal stripes beside the doors (photos)
# per model: door centres (y, the front at -13), cab door, windows between the doors (drawings)
MODELS = {
    "cab": {"cab": True, "doors": [-8.90, -3.23, 3.58, 10.32], "cab_door": -11.21, "pantograph": False},
    "mid": {"cab": False, "doors": [-10.34, -3.45, 3.45, 10.34], "cab_door": None, "pantograph": True},
}
SMALL_W, LARGE_W, WIN_STEP = 0.77, 1.19, 1.36       # small / large window widths, centre spacing (drawings)

# name: base colour, metallic, roughness, (emission strength)
MATERIALS = {
    "paint_white": ("#F1F2F0", 0.0, 0.3, 0.0),
    "paint_dark": ("#3A3E45", 0.15, 0.4, 0.0),          # anthracite window band, skirt and front
    "paint_grey": ("#9DA3AA", 0.3, 0.45, 0.0),          # roof
    "stripe_magenta": ("#C8106E", 0.0, 0.35, 0.0),
    "stripe_teal": ("#14A39A", 0.0, 0.35, 0.0),
    "glass": ("#0E141A", 0.0, 0.06, 0.0),
    "windscreen": ("#18232D", 0.0, 0.04, 0.0),
    "frame_dark": ("#2A2D32", 0.2, 0.5, 0.0),
    "rubber": ("#1B1D20", 0.0, 0.85, 0.0),
    "steel": ("#7D838A", 0.7, 0.4, 0.0),
    "bogie": ("#2B2D30", 0.3, 0.7, 0.0),
    "wheel": ("#5A5E63", 0.8, 0.35, 0.0),
    "buffer": ("#C9A23A", 0.2, 0.5, 0.0),               # the yellow anti-climber pads (photos)
    "headlight": ("#EEF3F6", 0.2, 0.15, 0.6),
    "taillight": ("#C81E1E", 0.0, 0.3, 0.6),
    "display": ("#0B0D10", 0.0, 0.4, 0.0),
    "display_amber": ("#FF8C1A", 0.0, 0.5, 3.0),
    "logo_white": ("#FFFFFF", 0.0, 0.4, 0.0),
    "logo_teal": ("#14A39A", 0.0, 0.4, 0.0),
    "logo_red": ("#D7263D", 0.0, 0.4, 0.0),
    "floor": ("#6F757C", 0.0, 0.85, 0.0),
    "floor_edge": ("#F2C200", 0.0, 0.6, 0.0),
    "panel": ("#E4E6E8", 0.0, 0.5, 0.0),
    "ceiling": ("#F3F4F5", 0.0, 0.6, 0.0),
    "seat_green": ("#B7BA2C", 0.0, 0.9, 0.0),           # anise green backs (photos of the renovated interior)
    "seat_navy": ("#283068", 0.0, 0.95, 0.0),
    "seat_shell": ("#8E96A3", 0.3, 0.45, 0.0),
    "pole": ("#C9CED4", 0.85, 0.25, 0.0),
    "lamp_white": ("#FFFFFF", 0.0, 0.5, 2.5),
    "dash": ("#2A2D33", 0.0, 0.6, 0.0),
    "screen_green": ("#3DDC84", 0.0, 0.3, 1.5),
    "button_red": ("#D62828", 0.0, 0.35, 0.4),
}
ALPHA = {"glass": 0.75, "windscreen": 0.5}


def args() -> dict:
    out = {"out": str(ROOT / "godot" / "assets" / "cars" / "mi79.glb"), "preview": ""}
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


def join(target, objs: list) -> bpy.types.Object:
    bpy.context.view_layer.update()
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    return target


def named(objs: list, name: str) -> bpy.types.Object:
    """The parts joined into one object called `name`, its origin left where the first part's was."""
    o = join(objs[0], objs)
    o.name = o.data.name = name
    return o


def box(name, centre, size, m, rot=None) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if rot is not None:
        bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    return new_obj(name, bm, [m], at=centre)


def bar(name, p0, p1, w, h, m) -> bpy.types.Object:
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    rot = d.to_track_quat("Y", "Z" if abs(d.normalized().z) < 0.9 else "X").to_matrix().to_4x4()
    return box(name, (p0 + p1) / 2, (w, d.length, h), m, rot)


def cylinder(name, centre, axis, r, depth, m, seg=16) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth)
    rot = Vector(axis).to_track_quat("Z", "Y" if abs(axis[1]) < 0.9 else "X").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    return new_obj(name, bm, [m], at=centre)


def pole(p0, p1, r=0.018) -> bpy.types.Object:
    p0, p1 = Vector(p0), Vector(p1)
    return cylinder("pole", (p0 + p1) / 2, tuple((p1 - p0).normalized()), r, (p1 - p0).length, "pole", 10)


_font = []


def text(s, size, m, depth=0.003) -> bpy.types.Object:
    """Text mesh in the local XY plane, baseline at y = 0 from x = 0, extruded towards +Z from 0."""
    if not _font:
        path = next((f for f in FONTS if Path(f).exists()), None)
        _font.append(bpy.data.fonts.load(path) if path else None)
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    if _font[0]:
        cu.font = _font[0]
    cu.size = size
    cu.extrude = depth / 2
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


def text_width(o) -> float:
    xs = [v.co.x for v in o.data.vertices]
    return max(xs) if xs else 0.0


def on_face(o, side: str, a: float, z: float, off: float = 0.004, end: float = 0.0) -> bpy.types.Object:
    """Moves a part built in the local XY plane (facing +Z) onto a body face: `a` along the face (y on the sides, x
    at the ends), `end` the y of the end face."""
    if side == "left":
        rows = ((0, 0, 1, HW + off), (1, 0, 0, a), (0, 1, 0, z))
    elif side == "right":
        rows = ((0, 0, -1, -HW - off), (-1, 0, 0, a), (0, 1, 0, z))
    elif side == "front":
        rows = ((1, 0, 0, a), (0, 0, -1, end - off), (0, 1, 0, z))
    else:
        rows = ((-1, 0, 0, a), (0, 0, 1, end + off), (0, 1, 0, z))
    o.matrix_world = Matrix((*rows, (0, 0, 0, 1))) @ Matrix.Translation(o.location)
    return o


# ---------------------------------------------------------------- shapes

def outline(y0, y1, r0, r1, inset=0.0, splits=(), n=6, hw=HW) -> list:
    """Counter-clockwise (from above) rounded rectangle, front = y0, with extra points on the sides at `splits`.
    Returns [(Vector2, tag)], tag of the segment starting there: front, fcorner, side, rcorner, rear."""
    splits = [s for s in splits if y0 + r0 < s < y1 - r1]          # the same points at every inset (lofts)
    hw, y0, y1 = hw - inset, y0 + inset, y1 - inset
    r0, r1 = max(r0 - inset, 0.01), max(r1 - inset, 0.01)
    pts = []

    def arc(cx, cy, r, a0, tag):
        for i in range(n):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((Vector((cx + r * math.cos(a), cy + r * math.sin(a))), tag))

    arc(-hw + r0, y0 + r0, r0, 180, "fcorner")
    pts.append((Vector((-hw + r0, y0)), "front"))
    arc(hw - r0, y0 + r0, r0, 270, "fcorner")
    pts.append((Vector((hw, y0 + r0)), "side"))
    for y in sorted(splits):
        pts.append((Vector((hw, y)), "side"))
    arc(hw - r1, y1 - r1, r1, 0, "rcorner")
    pts.append((Vector((hw - r1, y1)), "rear"))
    arc(-hw + r1, y1 - r1, r1, 90, "rcorner")
    pts.append((Vector((-hw, y1 - r1)), "side"))
    for y in sorted(splits, reverse=True):
        pts.append((Vector((-hw, y)), "side"))
    return pts


def loft(name, rows, ring, face_mat, mats, top, bottom) -> bpy.types.Object:
    """Closed solid through outlines ring(inset) at heights rows = [(z, inset)]; face_mat(zc, tag, centre) names the
    material of each side face."""
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
            f.material_index = mats.index(face_mat(zc, tags[i], (a.co + b.co) / 2))
    bm.faces.new(list(reversed(rings[0]))).material_index = mats.index(bottom)
    bm.faces.new(rings[-1]).material_index = mats.index(top)
    return new_obj(name, bm, mats)


# ---------------------------------------------------------------- one car

class Car:
    """One car model: its doors, windows, cab, and the layout it registers for train.gd."""

    def __init__(self, kind: str):
        spec = MODELS[kind]
        self.kind = kind
        self.cab = spec["cab"]
        self.doors = spec["doors"]
        self.cab_door = spec["cab_door"]
        self.pantograph = spec["pantograph"]
        self.y0, self.y1 = -HALF, HALF
        self.colliders = []             # (centre, size, door key or None)
        gaps = [self.y0 + (CAB_DEPTH + 0.6 if self.cab else 0.0)] + [y for d in self.doors for y in (d - DOOR_W / 2 - 0.17, d + DOOR_W / 2 + 0.17)] + [self.y1]
        self.windows = []               # (y centre, width)
        for k in range(0, len(gaps), 2):
            a, b = gaps[k], gaps[k + 1]
            mid, span = (a + b) / 2, b - a
            if span > 3 * WIN_STEP:
                self.windows += [(mid - WIN_STEP, SMALL_W), (mid, LARGE_W), (mid + WIN_STEP, SMALL_W)]
            elif span > SMALL_W + 0.3:
                self.windows.append((mid, SMALL_W))

    def door_spans(self):
        return [(d - DOOR_W / 2, d + DOOR_W / 2) for d in self.doors]

    def splits(self):
        s = set()
        for a, b in self.door_spans():
            s |= {a - 0.06, a, b, b + 0.06, a - 0.06 - 2 * STRIPE_W, a - 0.06 - STRIPE_W}
        for y, w in self.windows:
            s |= {y - w / 2, y + w / 2}
        if self.cab:
            s |= {self.y0 + 0.5, self.cab_door - 0.4}
        return sorted(s)

    def ring(self, inset=0.0):
        return outline(self.y0, self.y1, R_NOSE if self.cab else R_END, R_END, inset, self.splits())

    def collide(self, lo, hi, door=None):
        lo, hi = Vector(lo), Vector(hi)
        self.colliders.append(((lo + hi) / 2, hi - lo, door))

    # ------------------------------------------------------------ body

    def body(self) -> bpy.types.Object:
        spans = self.door_spans()
        wins = self.windows

        def stripe(y):
            for a, _ in spans:
                if a - 0.06 - 2 * STRIPE_W <= y < a - 0.06 - STRIPE_W:
                    return "stripe_magenta"
                if a - 0.06 - STRIPE_W <= y < a - 0.06:
                    return "stripe_teal"
            return None

        def face_mat(zc, tag, c):
            if self.cab and tag in ("front", "fcorner"):
                if zc < FLOOR + 0.25:
                    return "paint_dark"
                if FLOOR + 1.05 < zc < Z_WTOP + 0.15:
                    return "windscreen"
                return "paint_dark" if zc < Z_EAVE else "paint_grey"
            if zc > Z_EAVE:
                return "paint_grey"
            if tag == "side":
                st = stripe(c.y)
                if st and zc > Z_SKIRT + 0.05:
                    return st
                if Z_SILL < zc < Z_WTOP and any(y - w / 2 <= c.y <= y + w / 2 for y, w in wins):
                    return "glass"
                if self.cab and Z_SILL - 0.25 < zc < Z_WTOP and self.y0 + 0.5 < c.y < self.cab_door - 0.4:
                    return "glass"          # the cab's side window, in front of the cab door
            if zc < Z_SKIRT + 0.22:
                return "paint_dark"
            if Z_SILL - 0.08 < zc < Z_WTOP + 0.08:
                return "paint_dark"         # the window band
            return "paint_white"

        rows = [(Z_SKIRT, 0.03), (Z_SKIRT + 0.04, 0.0), (Z_SKIRT + 0.22, 0.0), (FLOOR + 0.25, 0.0), (FLOOR + 1.05, 0.0),
                (Z_SILL - 0.08, 0.0), (Z_SILL, 0.0), (Z_WTOP, 0.0), (Z_WTOP + 0.08, 0.0), (Z_WTOP + 0.15, 0.0),
                (DOOR_TOP + 0.02, 0.0), (Z_EAVE, 0.0), (Z_EAVE + 0.2, 0.06), (Z_ROOF - 0.12, 0.28), (Z_ROOF, 0.55)]
        rows.sort()                         # the windscreen's bottom is inside the window band
        mats = ["paint_white", "paint_dark", "paint_grey", "stripe_magenta", "stripe_teal", "glass", "windscreen"]
        shell = loft(self.kind + "_body", rows, self.ring, face_mat, mats, top="paint_grey", bottom="paint_dark")
        # door openings in both sides, the gangway openings in the ends (not the cab's)
        bm = bmesh.new()
        bm.from_mesh(shell.data)

        def gone(f):
            c, n = f.calc_center_median(), f.normal
            if abs(n.x) > 0.5 and abs(c.x) > HW - 0.05 and c.z < DOOR_TOP and c.z > FLOOR - 0.02:
                return any(a < c.y < b for a, b in spans)
            return False
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if gone(f)], context="FACES")
        bm.to_mesh(shell.data)
        bm.free()
        parts = [shell]
        # door frames (dark), the rubber of the gangway ends, roof equipment, the underframe boxes
        for a, b in spans:
            for sx in (-1, 1):
                for y in (a - 0.03, b + 0.03):
                    parts.append(box("jamb", (sx * (HW - 0.01), y, (FLOOR + DOOR_TOP) / 2), (0.05, 0.06, DOOR_TOP - FLOOR), "frame_dark"))
                parts.append(box("head", (sx * (HW - 0.01), (a + b) / 2, DOOR_TOP + 0.02), (0.05, b - a + 0.12, 0.05), "frame_dark"))
                parts.append(box("step", (sx * (HW - 0.02), (a + b) / 2, FLOOR - 0.02), (0.08, b - a, 0.04), "steel"))
        if self.cab:                        # the cab doors (closed): their outline and window on both sides
            for sx in (-1, 1):
                for y in (self.cab_door - 0.32, self.cab_door + 0.32):
                    parts.append(box("cab_jamb", (sx * (HW + 0.004), y, (FLOOR + DOOR_TOP) / 2), (0.01, 0.03, DOOR_TOP - FLOOR), "frame_dark"))
                parts.append(box("cab_head", (sx * (HW + 0.004), self.cab_door, DOOR_TOP), (0.01, 0.67, 0.03), "frame_dark"))
                parts.append(box("cab_window", (sx * (HW + 0.004), self.cab_door, (Z_SILL + Z_WTOP) / 2), (0.01, 0.42, Z_WTOP - Z_SILL), "glass"))
                parts.append(box("cab_handle", (sx * (HW + 0.02), self.cab_door - 0.22, FLOOR + 1.0), (0.03, 0.03, 0.3), "steel"))
        ends = [self.y1] if self.cab else [self.y0, self.y1]
        for y in ends:
            sy = 1 if y > 0 else -1
            parts.append(box("gangway_frame", (0, y + sy * 0.10, FLOOR + GANGWAY_H / 2 + 0.1), (GANGWAY_W + 0.3, 0.2, GANGWAY_H + 0.3), "rubber"))
            parts.append(box("coupler", (0, y + sy * 0.12, 0.85), (0.3, 0.24, 0.2), "steel"))
        for k, y in enumerate((-6.0, 0.0, 6.0)):
            if self.pantograph and k == 0:
                continue
            parts.append(box("roof_unit", (0, y, Z_ROOF + 0.08), (1.6, 2.2, 0.16), "paint_grey"))
        for y in (-5.5, -1.5, 2.5, 6.0):
            parts.append(box("equipment", (0, y, Z_SKIRT - 0.25), (2.2, 2.6, 0.5), "bogie"))
        # side lettering: the car number under the window band near the end, "RER B" by the middle door
        number = "Z 8265" if self.cab else "Z 8266"         # an MI 79's (photos: 8265)
        for side, sx in (("left", 1), ("right", -1)):
            t = text(number, 0.09, "paint_dark")
            t.location = (-text_width(t) / 2, 0.0, 0.0)
            parts.append(on_face(t, side, (self.y1 - 1.2) * sx if side == "left" else -(self.y1 - 1.2) * sx, Z_SKIRT + 0.35))
        if self.cab:
            parts += self.front()
        return named(parts, self.kind + "_body")

    def front(self) -> list:
        """The cab front: anthracite mask with the windscreen (in the shell), destination display, lamps, badges,
        the buffer beam with its yellow pads and the coupler."""
        y0 = self.y0
        parts = []
        parts.append(box("beam", (0, y0 - 0.05, FLOOR - 0.05), (2 * HW - 0.2, 0.12, 0.45), "paint_dark"))
        for sx in (-1, 1):
            parts.append(box("pad", (sx * 0.95, y0 - 0.13, FLOOR - 0.05), (0.42, 0.06, 0.26), "buffer"))
        parts.append(box("coupler_head", (0, y0 - 0.25, 0.92), (0.32, 0.3, 0.26), "steel"))
        parts.append(box("frame", (0, y0 + 0.002, FLOOR + 0.62), (2 * HW - 0.35, 0.02, 0.04), "paint_white"))
        # the badges between the lamps: RATP (teal disc) and SNCF (red plate)
        parts.append(cylinder("ratp", (-0.18, y0 - 0.008, FLOOR + 0.42), (0, 1, 0), 0.08, 0.01, "logo_teal", 20))
        parts.append(box("sncf", (0.18, y0 - 0.008, FLOOR + 0.42), (0.22, 0.01, 0.1), "logo_red"))
        num = text("8265", 0.08, "logo_white")
        num.location = (-text_width(num) / 2, 0.0, 0.0)
        parts.append(on_face(num, "front", 1.05, FLOOR + 0.62, 0.012, y0))
        # wiper
        parts.append(bar("wiper", (0.75, y0 - 0.012, FLOOR + 1.12), (0.25, y0 - 0.012, FLOOR + 1.62), 0.025, 0.02, "frame_dark"))
        return parts

    def lamps(self) -> list:
        """Head lamps (white, outer pair) and tail lamps (red, inner pair) at the cab front, objects of their own."""
        y0 = self.y0
        head = [cylinder("head", (sx * 0.80, y0 - 0.012, FLOOR + 0.42), (0, 1, 0), 0.085, 0.02, "headlight", 20) for sx in (-1, 1)]
        tail = [cylinder("tail", (sx * 0.55, y0 - 0.012, FLOOR + 0.42), (0, 1, 0), 0.06, 0.02, "taillight", 20) for sx in (-1, 1)]
        return [named(head, self.kind + "_head_lamps"), named(tail, self.kind + "_tail_lamps")]

    def display(self) -> bpy.types.Object:
        """The destination display behind the top of the windscreen (train.gd letters it)."""
        o = box("display", (0.2, self.y0 + 0.06, Z_WTOP - 0.05), (1.5, 0.02, 0.2), "display")
        o.name = o.data.name = self.kind + "_display"
        return o

    def door_leaves(self) -> list:
        """Per door and side, the two leaves (white, a dark window; separate objects: train.gd slides them along the
        outside of the body), origin at the leaf centre, closed in the opening."""
        out = []
        zb, zt = FLOOR + 0.01, DOOR_TOP - 0.01
        lw, lh = DOOR_W / 2, zt - zb
        doors = [(i, y, DOOR_W) for i, y in enumerate(self.doors)]
        for i, yc, w in doors:
            for side, sx in (("l", 1), ("r", -1)):
                for s, tag in ((-1, "a"), (1, "b")):
                    parts = [box("leaf", (0, 0, 0), (0.04, lw - 0.01, lh), "paint_white"),
                             box("window", (sx * 0.021, 0, 0.35), (0.004, lw - 0.16, 0.85), "glass"),
                             box("seal", (0, -s * (lw / 2 - 0.005), 0), (0.05, 0.02, lh), "rubber")]
                    leaf = named(parts, f"{self.kind}_door{i}_{side}_{tag}")
                    leaf.location = (sx * (HW - 0.01), yc + s * lw / 2, (zb + zt) / 2)
                    out.append(leaf)
        return out

    # ------------------------------------------------------------ inside

    def interior(self) -> bpy.types.Object:
        """Floor, wall panels, ceiling and its light strips, the facing bays of seats, poles, the end walls with the
        gangway doors open, the cab (partition, desk, seat, controls); registers the walkable colliders."""
        parts = []
        y0, y1 = self.y0, self.y1
        cab_end = y0 + CAB_DEPTH if self.cab else y0
        parts.append(box("floor", (0, 0, FLOOR - 0.03), (2 * IN_HW, y1 - y0 - 0.1, 0.06), "floor"))
        for a, b in self.door_spans():
            for sx in (-1, 1):
                parts.append(box("nosing", (sx * (IN_HW - 0.05), (a + b) / 2, FLOOR + 0.002), (0.10, b - a, 0.006), "floor_edge"))
        parts.append(box("ceiling", (0, 0, CEIL + 0.01), (2 * IN_HW, y1 - y0 - 0.1, 0.02), "ceiling"))
        for sx in (-1, 1):
            parts.append(box("light", (sx * 0.55, (cab_end + y1) / 2, CEIL - 0.008), (0.14, y1 - cab_end - 0.6, 0.016), "lamp_white"))
        # wall panels between the doors (below the windows: the shell's glass is above)
        edges = [cab_end] + [y for a, b in self.door_spans() for y in (a - 0.05, b + 0.05)] + [y1 - 0.06]
        for sx in (-1, 1):
            for k in range(0, len(edges), 2):
                a, b = edges[k], edges[k + 1]
                if b - a < 0.05:
                    continue
                parts.append(box("panel", (sx * (IN_HW + 0.02), (a + b) / 2, (FLOOR + Z_SILL) / 2), (0.04, b - a, Z_SILL - FLOOR), "panel"))
                parts.append(box("panel_top", (sx * (IN_HW + 0.02), (a + b) / 2, (Z_WTOP + CEIL) / 2), (0.04, b - a, CEIL - Z_WTOP), "panel"))
                self.collide((sx * IN_HW - (0.0 if sx > 0 else WALL_T), a, FLOOR), (sx * IN_HW + (WALL_T if sx > 0 else 0.0), b, CEIL))
        # door boxes, closed while the doors are: tagged with their door and side
        for i, (a, b) in enumerate(self.door_spans()):
            for side, sx in (("l", 1), ("r", -1)):
                self.collide((sx * IN_HW - (0.0 if sx > 0 else WALL_T + 0.02), a, FLOOR), (sx * IN_HW + (WALL_T + 0.02 if sx > 0 else 0.0), b, DOOR_TOP), door=f"{i}_{side}")
                parts.append(pole((sx * (IN_HW - 0.12), a - 0.12, FLOOR), (sx * (IN_HW - 0.12), a - 0.12, CEIL)))
                parts.append(pole((sx * (IN_HW - 0.12), b + 0.12, FLOOR), (sx * (IN_HW - 0.12), b + 0.12, CEIL)))
        # facing bays between the doors and at the ends
        zones = []
        bounds = [cab_end + 0.15] + [y for a, b in self.door_spans() for y in (a - 0.35, b + 0.35)] + [y1 - 0.25]
        for k in range(0, len(bounds), 2):
            zones.append((bounds[k], bounds[k + 1]))
        for a, b in zones:
            n = max(1, int((b - a) // PITCH))
            start = (a + b) / 2 - n * PITCH / 2
            for j in range(n):
                ya, yb = start + j * PITCH, start + (j + 1) * PITCH
                for sx in (-1, 1):
                    parts += self.bay(sx, ya, yb)
        # centre poles in the vestibules and grab rails along the ceiling
        for a, b in self.door_spans():
            parts.append(pole((0, (a + b) / 2, FLOOR), (0, (a + b) / 2, CEIL)))
        for sx in (-1, 1):
            parts.append(pole((sx * (AISLE_HW + 0.05), cab_end + 0.3, FLOOR + 1.90), (sx * (AISLE_HW + 0.05), y1 - 0.3, FLOOR + 1.90), 0.016))
        # end walls with the gangway doorway (cab car: its rear only), the cab partition
        ends = [y1] if self.cab else [y0, y1]
        for y in ends:
            sy = 1 if y > 0 else -1
            wy = y - sy * 0.05
            side_w = IN_HW - GANGWAY_W / 2
            for sx in (-1, 1):
                parts.append(box("end_wall", (sx * (GANGWAY_W / 2 + side_w / 2), wy, (FLOOR + CEIL) / 2), (side_w, 0.06, CEIL - FLOOR), "panel"))
                self.collide((min(sx * GANGWAY_W / 2, sx * IN_HW), wy - 0.04, FLOOR), (max(sx * GANGWAY_W / 2, sx * IN_HW), wy + 0.04, CEIL))
            parts.append(box("end_head", (0, wy, (FLOOR + GANGWAY_H + CEIL) / 2), (GANGWAY_W, 0.06, CEIL - FLOOR - GANGWAY_H), "panel"))
            self.collide((-GANGWAY_W / 2, wy - 0.04, FLOOR + GANGWAY_H), (GANGWAY_W / 2, wy + 0.04, CEIL))
            for sx in (-1, 1):                  # the end door, open against the wall
                parts.append(box("end_door", (sx * (GANGWAY_W / 2 + 0.36), wy - sy * 0.05, FLOOR + 0.98), (0.7, 0.03, 1.92), "panel"))
        if self.cab:
            parts += self.cab_fittings()
        # floor and roof, the cab front closed
        self.collide((-HW, y0 if not self.cab else cab_end, FLOOR - 0.25), (HW, y1, FLOOR))
        self.collide((-HW, y0, CEIL), (HW, y1, CEIL + 0.3))
        return named(parts, self.kind + "_interior")

    def bay(self, sx, ya, yb) -> list:
        """A facing pair of two-seat benches on side sx between ya and yb (backs at both ends)."""
        parts = []
        x_in, x_out = sx * AISLE_HW, sx * IN_HW
        xc, w = (x_in + x_out) / 2, abs(x_out - x_in)
        for yb_, face in ((ya + 0.06, 1), (yb - 0.06, -1)):
            yc = yb_ + face * 0.24
            parts += [box("shell", (xc, yc, FLOOR + 0.40), (w - 0.02, 0.46, 0.05), "seat_shell"),
                      box("cushion", (xc, yc + face * 0.01, FLOOR + 0.45), (w - 0.05, 0.42, 0.06), "seat_navy"),
                      box("back", (xc, yb_ + face * 0.02, FLOOR + 0.80), (w - 0.04, 0.05, 0.64), "seat_navy"),
                      box("back_top", (xc, yb_ + face * 0.025, FLOOR + 1.02), (w - 0.04, 0.06, 0.22), "seat_green"),
                      box("pedestal", (xc, yc, FLOOR + 0.19), (0.1, 0.3, 0.38), "seat_shell")]
            parts.append(bar("grab", (x_in + sx * 0.02, yb_, FLOOR + 1.16), (x_in + sx * 0.02, yb_, FLOOR + 1.16), 0.03, 0.03, "pole")
                         if False else box("grab", (x_in + sx * 0.03, yb_, FLOOR + 1.15), (0.04, 0.04, 0.12), "pole"))
            self.collide((min(x_in, x_out), min(yb_, yc + face * 0.25), FLOOR), (max(x_in, x_out), max(yb_, yc + face * 0.25), FLOOR + 0.5))
            self.collide((min(x_in, x_out), yb_ - 0.04, FLOOR), (max(x_in, x_out), yb_ + 0.04, FLOOR + 1.14))
        return parts

    def cab_fittings(self) -> list:
        """Partition with its door (closed: the trains are driven by bots), desk, controls, driver seat."""
        y0 = self.y0
        py = y0 + CAB_DEPTH
        parts = [box("partition", (0, py, (FLOOR + CEIL) / 2), (2 * IN_HW, 0.06, CEIL - FLOOR), "panel"),
                 box("cab_door", (0.0, py - 0.035, FLOOR + 0.98), (0.7, 0.03, 1.9), "frame_dark"),
                 box("cab_window", (0.0, py - 0.052, FLOOR + 1.45), (0.4, 0.005, 0.5), "glass")]
        self.collide((-IN_HW, py - 0.05, FLOOR), (IN_HW, py + 0.05, CEIL))
        parts += [box("desk", (0.35, y0 + 0.55, FLOOR + 0.55), (1.9, 0.7, 1.1), "dash"),
                  box("desk_top", (0.35, y0 + 0.75, FLOOR + 1.12), (1.9, 0.5, 0.06), "dash"),
                  box("screen", (0.55, y0 + 0.72, FLOOR + 1.2), (0.3, 0.02, 0.18), "screen_green"),
                  box("controller", (0.95, y0 + 0.95, FLOOR + 1.15), (0.08, 0.2, 0.12), "frame_dark"),
                  box("button", (0.25, y0 + 0.8, FLOOR + 1.16), (0.05, 0.05, 0.02), "button_red"),
                  box("seat", (0.65, y0 + 1.45, FLOOR + 0.5), (0.5, 0.5, 0.1), "seat_navy"),
                  box("seat_back", (0.65, y0 + 1.72, FLOOR + 0.9), (0.5, 0.08, 0.7), "seat_navy"),
                  box("seat_base", (0.65, y0 + 1.45, FLOOR + 0.22), (0.3, 0.3, 0.44), "dash")]
        return parts

    def bogie(self, name, y) -> bpy.types.Object:
        """A bogie, origin on its pivot at the rail level: frame, four wheels, axle boxes, the traction motors' cases."""
        parts = [box("frame", (0, 0, WHEEL_R + 0.1), (2.2, WHEELBASE + 0.9, 0.3), "bogie")]
        for ay in (-WHEELBASE / 2, WHEELBASE / 2):
            for sx in (-1, 1):
                parts.append(cylinder("wheel", (sx * 0.72, ay, WHEEL_R), (1, 0, 0), WHEEL_R, 0.13, "wheel", 20))
                parts.append(box("axlebox", (sx * 0.95, ay, WHEEL_R), (0.22, 0.3, 0.28), "bogie"))
            parts.append(cylinder("motor", (0, ay * 0.55, WHEEL_R), (1, 0, 0), 0.28, 1.1, "bogie", 12))
        for sx in (-1, 1):
            parts.append(cylinder("spring", (sx * 1.0, 0, WHEEL_R + 0.38), (0, 0, 1), 0.16, 0.3, "rubber", 12))
        o = named(parts, name)
        o.location = (0, y, 0)
        return o

    def pantograph_obj(self) -> bpy.types.Object:
        """The pantograph (raised: 1,500 V DC, contact wire 5.25 m above the rail), on the intermediate cars."""
        y = -6.0
        parts = [box("base", (0, y, Z_ROOF + 0.06), (1.2, 1.4, 0.12), "steel")]
        top = 5.25 - 0.02
        knee = (0, y + 0.9, (Z_ROOF + top) / 2 + 0.1)
        for sx in (-1, 1):
            parts.append(bar("lower_arm", (sx * 0.35, y - 0.5, Z_ROOF + 0.12), (sx * 0.2, knee[1], knee[2]), 0.05, 0.05, "steel"))
            parts.append(bar("upper_arm", (sx * 0.2, knee[1], knee[2]), (sx * 0.1, y, top - 0.04), 0.04, 0.04, "steel"))
        parts.append(box("head", (0, y, top), (1.9, 0.12, 0.05), "steel"))
        o = named(parts, self.kind + "_pantograph")
        return o

    def far(self) -> bpy.types.Object:
        """A light shell for the distance: the livery's bands, windscreen, the doors as dark panels."""
        def face_mat(zc, tag, c):
            if self.cab and tag in ("front", "fcorner"):
                return "windscreen" if FLOOR + 1.05 < zc < Z_WTOP + 0.15 else "paint_dark"
            if zc > Z_EAVE:
                return "paint_grey"
            if zc < Z_SKIRT + 0.22 or Z_SILL - 0.08 < zc < Z_WTOP + 0.08:
                return "paint_dark"
            return "paint_white"
        rows = [(Z_SKIRT, 0.0), (Z_SKIRT + 0.22, 0.0), (Z_SILL - 0.08, 0.0), (Z_WTOP + 0.08, 0.0), (Z_EAVE, 0.0),
                (Z_ROOF, 0.4)]
        mats = ["paint_white", "paint_dark", "paint_grey", "windscreen"]
        o = loft(self.kind + "_far", rows, lambda i: outline(self.y0, self.y1, R_NOSE if self.cab else R_END, R_END, i, n=2),
                 face_mat, mats, top="paint_grey", bottom="paint_dark")
        parts = [o]
        for y in (-BOGIE_Y, BOGIE_Y):
            parts.append(box("bogie", (0, y, WHEEL_R), (2.0, WHEELBASE + 0.9, 2 * WHEEL_R), "bogie"))
        for d in self.doors:
            for sx in (-1, 1):
                parts.append(box("door", (sx * (HW + 0.005), d, (FLOOR + DOOR_TOP) / 2), (0.01, DOOR_W, DOOR_TOP - FLOOR), "paint_dark"))
        return named(parts, self.kind + "_far")

    def cabin_lights(self) -> bpy.types.Object:
        """Glowing strips train.gd swaps at night (one object: the cabin light frames are in the layout)."""
        cab_end = self.y0 + CAB_DEPTH if self.cab else self.y0
        parts = [box("strip", (sx * 0.55, (cab_end + self.y1) / 2, CEIL - 0.018), (0.1, self.y1 - cab_end - 0.8, 0.008), "lamp_white")
                 for sx in (-1, 1)]
        return named(parts, self.kind + "_cabin_lights")

    def layout(self, objs: dict) -> dict:
        def gd(v):
            return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]
        cab_end = self.y0 + CAB_DEPTH if self.cab else self.y0
        doors = {"left": [], "right": []}
        for i, d in enumerate(self.doors):
            for side, sx in (("l", 1), ("r", -1)):
                doors["left" if side == "l" else "right"].append({
                    "key": f"{i}_{side}", "leaves": [f"{self.kind}_door{i}_{side}_a", f"{self.kind}_door{i}_{side}_b"],
                    "center": gd((sx * HW, d, FLOOR)), "width": DOOR_W, "height": DOOR_TOP - FLOOR})
        out = {
            "length": CAR, "body": [round(-self.y1, 4), round(-self.y0, 4)], "width": 2 * HW,
            "bogies": [round(BOGIE_Y, 4), round(-BOGIE_Y, 4)], "wheelbase": WHEELBASE, "wheel_radius": WHEEL_R,
            "floor_y": FLOOR, "ceiling_y": CEIL, "door_top": DOOR_TOP,
            "interior": [gd((-IN_HW, self.y1, FLOOR - 0.3)), gd((IN_HW, cab_end, CEIL))],
            "colliders": [{"center": gd(c), "size": [round(s.x, 4), round(s.z, 4), round(s.y, 4)], **({"door": d} if d else {})}
                          for c, s, d in self.colliders],
            "doors": doors,
            "gangways": {"front": not self.cab, "rear": True, "width": GANGWAY_W, "height": GANGWAY_H},
            "nodes": {k: v.name for k, v in objs.items()},
            "hull": [gd((-HW, self.y1, Z_SKIRT)), gd((HW, self.y0, Z_EAVE))],
        }
        if self.cab:
            out["cab"] = {"seat": gd((0.65, self.y0 + 1.45, FLOOR + 0.55)), "eye": gd((0.65, self.y0 + 1.40, FLOOR + 1.70)),
                          "display": gd((0.2, self.y0 + 0.04, Z_WTOP - 0.05)),
                          "head": [gd((sx * 0.80, self.y0 - 0.03, FLOOR + 0.42)) for sx in (-1, 1)]}
        return out


# ---------------------------------------------------------------- main

def preview(prefix: str) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
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
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80)
    ground = new_obj("ground", bm, ["steel"])
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for suffix, pos, look in (("front", (9.0, -26.0, 3.0), (0, -12.0, 2.2)), ("side", (22.0, 2.0, 3.5), (0, 0, 2.2)),
                              ("interior", (0.0, 9.0, FLOOR + 1.65), (0.0, -6.0, FLOOR + 1.0))):
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
    exported = []
    layouts = {}
    for kind in ("cab", "mid"):
        car = Car(kind)
        objs = {"body": car.body(), "interior": car.interior(), "far": car.far(),
                "bogie_front": car.bogie(kind + "_bogie_front", -BOGIE_Y),
                "bogie_rear": car.bogie(kind + "_bogie_rear", BOGIE_Y), "cabin_lights": car.cabin_lights()}
        if car.cab:
            head, tail = car.lamps()
            objs["head_lamps"] = head
            objs["tail_lamps"] = tail
            objs["display"] = car.display()
        if car.pantograph:
            objs["pantograph"] = car.pantograph_obj()
        leaves = car.door_leaves()
        exported += list(objs.values()) + leaves
        layouts[kind] = car.layout(objs)
        # the preview shows the cab car in front of the intermediate one
        if kind == "mid":
            for o in list(objs.values()) + leaves:
                o.location.y += CAR
    out = Path(a["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    if a["preview"]:
        Path(a["preview"]).parent.mkdir(parents=True, exist_ok=True)
        for o in bpy.data.objects:
            o.hide_render = o.name.endswith("_far")
        preview(a["preview"])
    for o in exported:                      # back in place for the export
        if o.name.startswith("mid_"):
            o.location.y -= CAR
    for o in bpy.data.objects:
        o.select_set(o in exported)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True)
    layout = {"model": "MI 79 R", "unit": ["cab", "mid", "mid", "cab"], "car_length": CAR, **layouts}
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    for kind in ("cab", "mid"):
        objs = [o for o in exported if o.name.startswith(kind + "_")]
        near = sum(len(p.vertices) - 2 for o in objs if not o.name.endswith("_far") for p in o.data.polygons)
        far = sum(len(p.vertices) - 2 for o in objs if o.name.endswith("_far") for p in o.data.polygons)
        print(f"mi79 {kind}: {near} triangles near, {far} far, {len(layouts[kind]['colliders'])} colliders")
    print(f"mi79: {out}")


main()
