"""Round crowns: the common broadleaved park and street tree (lime, maple, plane, oak)."""
import math

from treelib import Blob, TreeSpec, Tube, branch, rng, shell, trunk_path


def _branches(z: float, n: int, length: float, r0: float, seed: int):
    r = rng(seed)
    return [branch((0, 0, z + r.uniform(-0.3, 0.3)), (math.cos(a), math.sin(a)), length * r.uniform(0.8, 1.1), r0, r0 * 0.5)
            for a in (2 * math.pi * k / n + r.uniform(-0.3, 0.3) for k in range(n))]


def variants():
    out = []
    # 0: classic cloud, 10 m, crown radius ~4 m
    r = rng(11)
    blobs = [Blob((0, 0, 6.4), 2.3)] + shell(r, (0, 0, 6.4), (2.5, 2.5, 2.2), 11, (1.2, 1.5), z_min=-0.55)
    out.append(TreeSpec("round_0", blobs, [Tube(trunk_path(5.6, 0.22, 0.12))] + _branches(3.7, 4, 1.7, 0.09, 1)))
    # 1: broad and flat (plane tree, chestnut): three big lobes
    r = rng(23)
    blobs = [Blob((0, 0, 6.2), 2.1, (1.25, 1.25, 0.85))]
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        blobs.append(Blob((math.cos(a) * 2.4, math.sin(a) * 2.4, 6.0 + r.uniform(-0.3, 0.4)), 1.7))
    blobs += shell(r, (0, 0, 6.3), (3.2, 3.2, 1.9), 10, (1.0, 1.3), z_min=-0.35)
    out.append(TreeSpec("round_1", blobs, [Tube(trunk_path(5.2, 0.25, 0.14, lean=(0.02, 0.0)))] + _branches(3.4, 3, 2.1, 0.1, 2)))
    # 2: twin leaders, lumpy and a little irregular
    r = rng(37)
    blobs = [Blob((-0.9, 0.3, 6.6), 1.8), Blob((1.1, -0.4, 6.0), 1.7)]
    blobs += shell(r, (-0.9, 0.3, 6.7), (2.1, 2.1, 1.9), 7, (1.1, 1.4), z_min=-0.4)
    blobs += shell(r, (1.1, -0.4, 6.1), (2.0, 2.0, 1.8), 6, (1.0, 1.35), z_min=-0.4)
    tubes = [Tube(trunk_path(3.3, 0.23, 0.17)),
             Tube([(0, 0, 3.0, 0.16), (-0.4, 0.15, 4.3, 0.12), (-0.8, 0.3, 5.8, 0.08)]),
             Tube([(0, 0, 3.0, 0.15), (0.5, -0.2, 4.2, 0.11), (1.0, -0.4, 5.4, 0.07)])]
    out.append(TreeSpec("round_2", blobs, tubes + _branches(3.3, 2, 1.4, 0.07, 3)))
    return out
