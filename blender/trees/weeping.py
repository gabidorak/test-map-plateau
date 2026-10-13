"""Weeping crowns: willows and weeping birches near the lakes and ponds."""
import math

from treelib import Blob, TreeSpec, Tube, branch, rng, trunk_path


def _curtains(r, n: int, ring: float, top: float, bottom: float, width: float):
    out = []
    for k in range(n):
        a = 2 * math.pi * k / n + r.uniform(-0.15, 0.15)
        x, y = math.cos(a) * ring, math.sin(a) * ring
        steps = 3
        for i in range(steps):
            t = i / (steps - 1)
            z = top - (top - bottom) * t
            out.append(Blob((x * (1 + 0.12 * t), y * (1 + 0.12 * t), z), width * (1 - 0.35 * t), (1.0, 1.0, 1.5)))
    return out


def variants():
    out = []
    r = rng(131)
    blobs = [Blob((0, 0, 7.4), 2.8, (1.25, 1.25, 0.8))] + _curtains(r, 9, 3.3, 6.6, 2.4, 1.15)
    tubes = [Tube(trunk_path(6.2, 0.26, 0.13, lean=(0.03, 0.0)))]
    tubes += [branch((0, 0, 4.6), (math.cos(a), math.sin(a)), 2.4, 0.09, 0.05, rise=0.5) for a in (0.5, 2.6, 4.6)]
    out.append(TreeSpec("weeping_0", blobs, tubes))
    r = rng(149)
    blobs = [Blob((0, 0, 6.6), 2.3, (1.15, 1.15, 0.9)), Blob((0.6, 0.3, 7.6), 1.6)] + _curtains(r, 8, 2.7, 5.8, 1.8, 1.0)
    out.append(TreeSpec("weeping_1", blobs, [Tube(trunk_path(5.4, 0.22, 0.11))]))
    return out
