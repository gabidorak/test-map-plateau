"""Soft-toy tree kit (milestone M5): helpers shared by the archetype recipes in this folder.

A recipe returns a TreeSpec: crown blobs (metaball balls/ellipsoids), a trunk path with branches, and
optional wooden parts (sapling stakes). `build_models` turns each spec into three LOD meshes:
  metaballs -> mesh -> voxel remesh -> smooth -> decimate (soft blobby crowns),
  trunks as tapered tubes with a flared foot,
then bakes per-vertex data the toy shader reads (COLOR): r = ambient occlusion (ray-cast against the
tree and the ground), g = per-lump variation, b = height / tree height, a = part (1 leaves, 0 bark,
0.5 wood, 0.25 tie). Crown normals are blended with radial ones so crowns shade like soft balls.
Everything is built at real size in metres (z up); the Godot builder scales each instance from the
reference height and crown radius written to models.json.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PART_LEAVES, PART_BARK, PART_WOOD, PART_TIE = 1.0, 0.0, 0.5, 0.25
# triangles of the crown per LOD; trunk sides per LOD
LOD_CROWN_TRIS = (1600, 420, 110)
LOD_TRUNK_SIDES = (10, 6, 4)
AO_RAYS = 40
FIELD = 1.7                             # metaball field radius per visible radius (threshold 0.6, stiffness 2)


@dataclass
class Blob:
    co: tuple
    radius: float                       # visible radius of a lone blob (m)
    size: tuple = (1.0, 1.0, 1.0)       # ellipsoid stretch (x, y, z)
    stiffness: float = 2.0


@dataclass
class Tube:
    points: list                        # [(x, y, z, radius)] from the foot upwards
    part: float = PART_BARK
    branch: bool = False                # dropped from the coarser LODs


@dataclass
class TreeSpec:
    name: str
    blobs: list
    tubes: list
    voxel: float = 0.0                  # remesh voxel size (default: crown radius / 18)
    smooth: int = 4
    crown_tris: tuple = LOD_CROWN_TRIS
    extra: dict = field(default_factory=dict)


# ---------------------------------------------------------------- recipe helpers

def rng(seed: int) -> random.Random:
    return random.Random(seed)


def shell(r: random.Random, centre, radii, n: int, size: tuple, z_min: float = -0.3, jitter: float = 0.15):
    """n lumps spread over the upper part of an ellipsoid surface (Fibonacci sphere + jitter)."""
    cx, cy, cz = centre
    ax, ay, az = radii
    out = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - (i + 0.5) / n * (1 - z_min)
        rad = math.sqrt(max(1 - z * z, 0))
        a = i * golden + r.uniform(-0.4, 0.4)
        j = 1 + r.uniform(-jitter, jitter)
        s = r.uniform(size[0], size[1])
        out.append(Blob((cx + math.cos(a) * rad * ax * j, cy + math.sin(a) * rad * ay * j, cz + z * az * j), s))
    return out


def trunk_path(height: float, r0: float, r1: float, lean=(0.0, 0.0), steps: int = 6, flare: float = 1.6):
    """Tapered trunk from below the ground to `height`, flared at the foot, slightly leaning."""
    pts = [(0.0, 0.0, -0.3, r0 * flare)]
    for i in range(steps + 1):
        t = i / steps
        k = flare if t == 0 else 1.0 + (flare - 1.0) * max(0.0, 1 - t * 6) ** 2
        pts.append((lean[0] * t * t * height, lean[1] * t * t * height, t * height, (r0 + (r1 - r0) * t) * k))
    return pts


def branch(start, direction, length: float, r0: float, r1: float, rise: float = 0.35, steps: int = 3):
    sx, sy, sz = start
    dx, dy = direction
    n = math.hypot(dx, dy) or 1.0
    dx, dy = dx / n, dy / n
    pts = []
    for i in range(steps + 1):
        t = i / steps
        pts.append((sx + dx * length * t, sy + dy * length * t, sz + length * (rise * t + 0.25 * t * t), r0 + (r1 - r0) * t))
    return Tube(pts, branch=True)


# ---------------------------------------------------------------- mesh building

def _link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _evaluated_mesh(obj) -> bpy.types.Mesh:
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    return bpy.data.meshes.new_from_object(obj.evaluated_get(dg))


def crown_mesh(spec: TreeSpec, lod: int) -> bpy.types.Mesh:
    """Metaballs -> mesh -> voxel remesh -> smooth -> decimate to the LOD's triangle budget."""
    extent = max(max(abs(b.co[0]), abs(b.co[1])) + b.radius for b in spec.blobs)
    voxel = spec.voxel or extent / 18
    mb = bpy.data.metaballs.new(f"MB{spec.name}{lod}".replace("_", ""))
    mb.resolution = voxel * 0.8
    mb.render_resolution = voxel * 0.8
    mb.threshold = 0.6
    for b in spec.blobs:
        el = mb.elements.new(type="ELLIPSOID" if b.size != (1.0, 1.0, 1.0) else "BALL")
        el.co = b.co
        el.radius = b.radius * FIELD
        el.stiffness = b.stiffness
        if el.type == "ELLIPSOID":
            el.size_x, el.size_y, el.size_z = b.size
    mobj = _link(bpy.data.objects.new(mb.name, mb))
    raw = _evaluated_mesh(mobj)
    bpy.data.objects.remove(mobj)
    bpy.data.metaballs.remove(mb)

    obj = _link(bpy.data.objects.new(f"crown_{spec.name}_{lod}", raw))
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel * (1.0, 1.6, 2.6)[lod]
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations = spec.smooth
    sm.lambda_factor = 0.5
    sm.use_volume_preserve = True
    mesh = _evaluated_mesh(obj)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    target = spec.crown_tris[lod]
    obj.modifiers.clear()
    obj.data = mesh
    if tris > target:
        dec = obj.modifiers.new("decimate", "DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = target / tris
        dec.use_collapse_triangulate = True
        mesh = _evaluated_mesh(obj)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(raw)
    return mesh


def tube_into(bm: bmesh.types.BMesh, tube: Tube, sides: int) -> list:
    """Adds a tube (rings along the path, closed at the top) to bm; returns its faces."""
    pts = [Vector(p[:3]) for p in tube.points]
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))).normalized()
        up = d.cross(side).normalized()     # (side, up, d) right-handed: rings run CCW, faces point outward
        r = tube.points[i][3]
        rings.append([bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r)
                      for a in (2 * math.pi * k / sides for k in range(sides))])
    faces = []
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(sides):
            faces.append(bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k])))
    tip = bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * tube.points[-1][3])
    for k in range(sides):
        faces.append(bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip)))
    return faces


def assemble(spec: TreeSpec, lod: int, materials: dict) -> bpy.types.Object:
    """Crown + trunk + wooden parts of one LOD as one object with leaves/trunk/wood material slots."""
    crown = crown_mesh(spec, lod)
    bm = bmesh.new()
    bm.from_mesh(crown)
    bpy.data.meshes.remove(crown)
    part = bm.verts.layers.float.new("part")
    for v in bm.verts:
        v[part] = PART_LEAVES
    for f in bm.faces:
        f.material_index = 0
        f.smooth = True
    sides = LOD_TRUNK_SIDES[lod]
    for t in spec.tubes:
        if t.branch and lod > 0:
            continue
        faces = tube_into(bm, t, max(sides - (2 if t.part != PART_BARK or t.branch else 0), 3) if lod == 0 else sides)
        for f in faces:
            f.material_index = 1 if t.part == PART_BARK else 2
            f.smooth = True
            for v in f.verts:
                v[part] = t.part
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(f"{spec.name}_lod{lod}")
    bm.to_mesh(mesh)
    bm.free()
    for name in ("leaves", "trunk", "wood"):
        mesh.materials.append(materials[name])
    obj = _link(bpy.data.objects.new(f"{spec.name}_lod{lod}", mesh))
    bake_vertex_data(obj, spec)
    return obj


def bake_vertex_data(obj, spec: TreeSpec) -> None:
    """COLOR = (ambient occlusion, lump variation, height fraction, part) and soft crown normals."""
    mesh = obj.data
    part = [d.value for d in mesh.attributes["part"].data]
    co = [v.co.copy() for v in mesh.vertices]
    nrm = [v.normal.copy() for v in mesh.vertices]
    leaves = [i for i, p in enumerate(part) if p == PART_LEAVES]
    height = max(co[i].z for i in leaves) if leaves else max(c.z for c in co)
    # occluders: the tree itself + a ground disc
    bm = bmesh.new()
    bm.from_mesh(mesh)
    g = max(height, 6.0)
    quad = [bm.verts.new(p) for p in ((-g, -g, 0), (g, -g, 0), (g, g, 0), (-g, g, 0))]
    bm.faces.new(quad)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    dirs = _hemisphere(AO_RAYS)
    reach = max(height * 0.6, 1.0)
    # crown centre for radial normals
    if leaves:
        lo = Vector((min(co[i].x for i in leaves), min(co[i].y for i in leaves), min(co[i].z for i in leaves)))
        hi = Vector((max(co[i].x for i in leaves), max(co[i].y for i in leaves), max(co[i].z for i in leaves)))
        centre = (lo + hi) / 2
        half = (hi - lo) / 2
    lumps = [(Vector(b.co), b.radius, random.Random(k * 7919 + len(spec.name)).random()) for k, b in enumerate(spec.blobs)]
    colors = []
    normals = []
    for i, (c, n) in enumerate(zip(co, nrm)):
        basis = _basis(n)
        o = c + n * 0.02
        free = 0
        for d in dirs:
            if bvh.ray_cast(o, basis @ d, reach)[0] is None:
                free += 1
        ao = free / len(dirs)
        if part[i] == PART_LEAVES:
            # soft weighted lump id: each crown lump gets its own shade
            wsum, val = 0.0, 0.0
            for p, r, h in lumps:
                w = math.exp(-((c - p).length / max(r, 1e-3)) ** 2 * 2.0)
                wsum += w
                val += w * h
            lump = val / wsum if wsum > 1e-6 else 0.5
            radial = Vector(((c.x - centre.x) / max(half.x, 1e-3), (c.y - centre.y) / max(half.y, 1e-3),
                             (c.z - centre.z) / max(half.z, 1e-3))).normalized()
            n = (n * 0.45 + radial * 0.55).normalized()
        else:
            lump = 0.5
        colors.append((ao, lump, max(c.z, 0.0) / height, part[i]))
        normals.append(n)
    attr = mesh.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, col in enumerate(colors):
        attr.data[i].color = col
    mesh.color_attributes.active_color = attr
    mesh.attributes.remove(mesh.attributes["part"])
    mesh.normals_split_custom_set_from_vertices([tuple(n) for n in normals])


def _hemisphere(n: int) -> list:
    """Cosine-weighted directions around +z (deterministic)."""
    out = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        u = (i + 0.5) / n
        r = math.sqrt(u)
        a = i * golden
        out.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(1 - u, 0)))))
    return out


def _basis(n: Vector) -> Matrix:
    t = n.orthogonal().normalized()
    b = n.cross(t)
    return Matrix((t, b, n)).transposed()


def stats(obj) -> dict:
    """Reference sizes for the Godot builder: tree height, crown radius and crown base (m)."""
    mesh = obj.data
    col = mesh.color_attributes["Color"].data
    leaves = [v.co for v, c in zip(mesh.vertices, col) if c.color[3] == PART_LEAVES]
    trunk = sorted(math.hypot(v.co.x, v.co.y) for v, c in zip(mesh.vertices, col)
                   if c.color[3] == PART_BARK and 0.4 <= v.co.z <= 2.5 and math.hypot(v.co.x, v.co.y) < 1.0)
    return {
        "height": round(max(v.z for v in leaves), 3),
        "radius": round(max(math.hypot(v.x, v.y) for v in leaves), 3),
        "crown_base": round(min(v.z for v in leaves), 3),
        "trunk_radius": round(trunk[len(trunk) // 2] if trunk else 0.1, 3),
        "triangles": len(mesh.polygons),
    }


def materials() -> dict:
    out = {}
    for name, col in (("leaves", (0.33, 0.66, 0.25, 1)), ("trunk", (0.54, 0.42, 0.31, 1)), ("wood", (0.79, 0.64, 0.45, 1))):
        m = bpy.data.materials.new(name)
        m.diffuse_color = col
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = col
            bsdf.inputs["Roughness"].default_value = 0.9
        out[name] = m
    return out
