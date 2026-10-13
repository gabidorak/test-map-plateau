"""Columnar crowns: Lombardy poplars and fastigiate street trees in rows."""
import math

from treelib import Blob, TreeSpec, Tube, rng, trunk_path


def _stack(r, height: float, radius: float, base: float, n: int, lump: float):
    blobs = []
    for i in range(n):
        t = (i + 0.5) / n
        prof = (min(t / 0.3, 1.0) ** 0.5) * (1 - t) ** 0.55 * 1.35       # flame: full at a third, pointed top
        z = base + t * (height - base)
        rr = max(radius * prof, radius * 0.25)
        blobs.append(Blob((r.uniform(-0.1, 0.1) * radius, r.uniform(-0.1, 0.1) * radius, z), rr * 0.8))
        for k in range(3):
            a = r.uniform(0, 6.283)
            blobs.append(Blob((math.cos(a) * rr * 0.75, math.sin(a) * rr * 0.75, z + r.uniform(-0.4, 0.4)), rr * lump))
    return blobs


def variants():
    out = []
    r = rng(83)
    out.append(TreeSpec("columnar_0", _stack(r, 18.0, 2.3, 2.0, 9, 0.7), [Tube(trunk_path(14.0, 0.26, 0.08))]))
    r = rng(97)
    out.append(TreeSpec("columnar_1", _stack(r, 16.0, 2.0, 1.4, 8, 0.8), [Tube(trunk_path(12.0, 0.22, 0.07, lean=(0.01, 0.0)))]))
    return out
