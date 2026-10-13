"""Soft-toy prop kit (milestone M6): primitives and finishing shared by the recipes in blender/props/.

A recipe builds a Model from parts: rounded boxes, cylinders, spheres, tubes along a path, extruded outlines
and text, each with a palette colour (pipeline/palette.toml [props], or "#rrggbb") and a material slot.
`finish` joins the parts, applies weighted normals (flat faces stay flat, the bevels shade softly) and bakes
ambient occlusion per vertex (rays against the model, the ground and, for wall-mounted models, the wall).

Vertex COLOR = (toy colour in sRGB, ambient occlusion). Material slots, swapped for the toy prop shader by
the Godot builder (scripts/builder/prop_placer.gd):
  toy (opaque), tint (multiplied by the per-prop tint), glass (transparent), glow (lamp diffusers, ad panels),
  signal_car / signal_ped (traffic light lenses, lit by the shader's light cycle).
Model space: metres, z up, origin on the ground at the prop's foot, front = -Y (Blender's front view). Wall-
mounted models (Model(wall=True)) have their back on the plane y = 0 and extend towards -Y.
Colliders and anchors are in the same space; build_props.py writes them to props.json.
"""
from __future__ import annotations

import math
import tomllib
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
PALETTE = tomllib.loads((ROOT / "pipeline" / "palette.toml").read_text())["props"]
MATERIALS = ["toy", "tint", "glass", "glow", "signal_car", "signal_ped"]
AO_RAYS = 32
FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
SHARP = math.radians(30)            # edges sharper than this get the bevel


def rgb(c: str) -> tuple:
    h = PALETTE.get(c, c)
    if not h.startswith("#"):
        raise KeyError(f"unknown prop colour {c}")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def matrix(at=(0, 0, 0), rot=(0, 0, 0)) -> Matrix:
    """Rotation (degrees, XYZ Euler) then translation."""
    return Matrix.Translation(Vector(at)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()


def arc(cx, cy, r, a0, a1, n) -> list:
    """Points of a circular arc in a plane, angles in degrees."""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def circle(r, n=32, cx=0.0, cy=0.0, phase=0.0) -> list:
    return [(cx + r * math.cos(2 * math.pi * i / n + math.radians(phase)), cy + r * math.sin(2 * math.pi * i / n + math.radians(phase)))
            for i in range(n)]


def rounded_rect(w, h, r, n=4, cx=0.0, cy=0.0) -> list:
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    if r <= 0:
        return [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]
    pts = []
    for (x, y, a) in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        pts += arc(cx + x, cy + y, r, a, a + 90, n)
    return pts


def polygon_round(pts, r, n=3) -> list:
    """Convex polygon with rounded corners (fillet radius r), counter-clockwise points."""
    out = []
    k = len(pts)
    for i in range(k):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % k])
        a, b = (p0 - p1).normalized(), (p2 - p1).normalized()
        half = a.angle(b) / 2
        c = p1 + (a + b).normalized() * (r / math.sin(half))
        s, e = p1 + a * (r / math.tan(half)), p1 + b * (r / math.tan(half))
        v0, v1 = (s - c).normalized(), (e - c).normalized()
        out += [tuple(c + (v0 * (1 - t / n) + v1 * (t / n)).normalized() * r) for t in range(n + 1)]
    return out


class Model:
    def __init__(self, name: str, wall: bool = False, view_range: float = 150.0):
        self.name = name
        self.wall = wall
        self.view_range = view_range          # m, the Godot builder hides the prop beyond this
        self.parts: list = []                 # (mesh, rgb)
        self.colliders: list = []             # {"box": [cx, cy, cz, sx, sy, sz]} | {"cyl": [cx, cy, z0, r, h]}
        self.anchors: dict = {}               # named points / panels for the Godot builder
        self.info: dict = {}

    # ---------------------------------------------------------------- parts

    def _add(self, bm, color: str, mat: str, m: Matrix | None, bevel: float = 0.0, seg: int = 2, smooth: bool = True):
        if bevel > 0:
            edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > SHARP]
            if edges:
                bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=seg, profile=0.5,
                                affect="EDGES", clamp_overlap=True)
        if m is not None:
            bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        idx = MATERIALS.index(mat)
        for f in bm.faces:
            f.material_index = idx
            f.smooth = smooth
        me = bpy.data.meshes.new("part")
        bm.to_mesh(me)
        bm.free()
        self.parts.append((me, rgb(color)))
        return self

    def box(self, size, at=(0, 0, 0), color="anthracite", mat="toy", bevel=0.015, seg=2, rot=(0, 0, 0), base=False):
        """Rounded box of `size` (x, y, z) centred on `at` (base=True: `at` is the centre of its bottom face)."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if base:
            bmesh.ops.translate(bm, vec=Vector((0, 0, size[2] / 2)), verts=bm.verts)
        return self._add(bm, color, mat, matrix(at, rot), min(bevel, min(size) * 0.45), seg)

    def cyl(self, r, h, at=(0, 0, 0), color="anthracite", mat="toy", sides=16, bevel=0.008, r2=None, rot=(0, 0, 0), seg=2):
        """Cylinder (cone with top radius r2) standing on `at` along +z before the rotation."""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r,
                              radius2=r if r2 is None else r2, depth=h)
        bmesh.ops.translate(bm, vec=Vector((0, 0, h / 2)), verts=bm.verts)
        return self._add(bm, color, mat, matrix(at, rot), min(bevel, r * 0.45, (r2 or r) * 0.45, h * 0.3), seg)

    def sphere(self, r, at=(0, 0, 0), color="anthracite", mat="toy", seg=16, scale=(1, 1, 1), rot=(0, 0, 0)):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(seg // 2, 4), radius=r)
        bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
        return self._add(bm, color, mat, matrix(at, rot))

    def tube(self, pts, r, color="steel", mat="toy", sides=8, caps=True, at=(0, 0, 0), rot=(0, 0, 0)):
        """Round tube along a polyline of (x, y, z) points (parallel-transport frames, closed ends)."""
        bm = bmesh.new()
        P = [Vector(p) for p in pts]
        rings = []
        normal = None
        for i, p in enumerate(P):
            d = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
            if normal is None:
                normal = d.orthogonal().normalized()
            else:
                normal = (normal - d * normal.dot(d)).normalized()
            side = d.cross(normal)
            rings.append([bm.verts.new(p + (normal * math.cos(a) + side * math.sin(a)) * r)
                          for a in (2 * math.pi * k / sides for k in range(sides))])
        for a, b in zip(rings[:-1], rings[1:]):
            for k in range(sides):
                bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
        if caps:
            bm.faces.new(list(reversed(rings[0])))
            bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        return self._add(bm, color, mat, matrix(at, rot))

    def plate(self, outline, depth, at=(0, 0, 0), color="sign_white", mat="toy", rot=(0, 0, 0), bevel=0.0):
        """Outline of (x, z) points in the plane y = 0, extruded `depth` towards +Y, then moved to `at`."""
        bm = bmesh.new()
        verts = [bm.verts.new((x, 0.0, z)) for x, z in outline]
        face = bm.faces.new(verts)
        face.normal_update()
        if face.normal.y > 0:
            face.normal_flip()
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=Vector((0, depth, 0)), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        return self._add(bm, color, mat, matrix(at, rot), bevel, 1, smooth=False)

    def text(self, body: str, size: float, at=(0, 0, 0), color="sign_white", mat="toy", depth=0.004, rot=(0, 0, 0),
             align="CENTER"):
        """Text in the plane y = at.y facing -Y, centred on `at`."""
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.size = size
        cu.align_x = align
        cu.align_y = "CENTER"
        cu.extrude = depth / 2
        cu.resolution_u = 3
        if FONT.exists():
            cu.font = bpy.data.fonts.load(str(FONT), check_existing=True)
        obj = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(obj)
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        bpy.data.objects.remove(obj)
        bpy.data.curves.remove(cu)
        bm = bmesh.new()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(90), 4, "X"), verts=bm.verts)
        return self._add(bm, color, mat, matrix(at, rot), smooth=False)

    # ---------------------------------------------------------------- metadata

    def collide_box(self, size, at, base=False):
        z = at[2] + (size[2] / 2 if base else 0)
        self.colliders.append({"box": [round(at[0], 3), round(at[1], 3), round(z, 3), *[round(s, 3) for s in size]]})
        return self

    def collide_cyl(self, r, h, at=(0, 0, 0)):
        self.colliders.append({"cyl": [round(at[0], 3), round(at[1], 3), round(at[2], 3), round(r, 3), round(h, 3)]})
        return self

    def anchor(self, name: str, **values):
        self.anchors[name] = {k: (round(v, 3) if isinstance(v, float) else v) for k, v in values.items()}
        return self


# ---------------------------------------------------------------- finishing

def _material(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = {"glass": (0.7, 0.9, 1, 0.4), "glow": (1, 0.95, 0.8, 1)}.get(name, (0.6, 0.6, 0.6, 1))
    return m


def _hemisphere(n: int) -> list:
    out = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        u = (i + 0.5) / n
        r = math.sqrt(u)
        a = i * golden
        out.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(1 - u, 0)))))
    return out


def finish(m: Model) -> bpy.types.Object:
    """Joins the parts into one object: weighted normals, baked AO in COLOR.a, material slots."""
    bm = bmesh.new()
    col = bm.verts.layers.float_color.new("Color")
    for me, c in m.parts:
        n0 = len(bm.verts)
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        for v in bm.verts[n0:]:
            v[col] = (*c, 1.0)
        bpy.data.meshes.remove(me)
    m.parts = []
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    mesh = bpy.data.meshes.new(m.name)
    bm.to_mesh(mesh)
    bm.free()
    for name in MATERIALS:
        mesh.materials.append(_material(name))
    obj = bpy.data.objects.new(m.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    wn = obj.modifiers.new("weighted", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    obj.modifiers.clear()
    obj.data = baked
    bpy.data.meshes.remove(mesh)
    baked.name = m.name
    _bake_ao(obj, m.wall)
    return obj


def _bake_ao(obj, wall: bool) -> None:
    mesh = obj.data
    attr = mesh.color_attributes["Color"]
    mesh.color_attributes.active_color = attr
    idx = list(mesh.color_attributes).index(attr)
    mesh.color_attributes.active_color_index = idx
    mesh.color_attributes.render_color_index = idx
    co = [v.co.copy() for v in mesh.vertices]
    nrm = [v.normal.copy() for v in mesh.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    g = max((hi - lo).length, 2.0)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    quad = [bm.verts.new(p) for p in ((-g, -g, 0), (g, -g, 0), (g, g, 0), (-g, g, 0))]
    bm.faces.new(quad)
    if wall:
        quad = [bm.verts.new(p) for p in ((-g, 0.001, -1), (g, 0.001, -1), (g, 0.001, g), (-g, 0.001, g))]
        bm.faces.new(quad)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    dirs = _hemisphere(AO_RAYS)
    reach = max(min((hi - lo).length * 0.5, 1.5), 0.3)
    for i, (c, n) in enumerate(zip(co, nrm)):
        t = n.orthogonal().normalized()
        basis = Matrix((t, n.cross(t), n)).transposed()
        o = c + n * 0.003
        free = sum(1 for d in dirs if bvh.ray_cast(o, basis @ d, reach)[0] is None)
        r, gg, b, _ = attr.data[i].color
        attr.data[i].color = (r, gg, b, free / len(dirs))


def stats(obj, m: Model) -> dict:
    co = [v.co for v in obj.data.vertices]
    lo = [min(c[k] for c in co) for k in range(3)]
    hi = [max(c[k] for c in co) for k in range(3)]
    used = sorted({MATERIALS[p.material_index] for p in obj.data.polygons})
    return {"size": [round(hi[k] - lo[k], 3) for k in range(3)], "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi], "triangles": len(obj.data.polygons), "materials": used,
            "colliders": m.colliders, "anchors": m.anchors, "wall": m.wall, "range": m.view_range, **m.info}
