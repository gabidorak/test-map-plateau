"""Conifers: soft stacked tiers (pines, firs, cedars). Used where OSM says leaf_type=needleleaved, or by override."""
import math

from treelib import Blob, TreeSpec, Tube, rng, trunk_path


def _tiers(r, height: float, radius: float, base: float, n: int, droop: float):
    blobs = []
    for i in range(n):
        t = i / n
        z = base + t * (height - base) * 0.92
        rr = radius * (1 - t) ** 0.85 + 0.55
        blobs.append(Blob((0, 0, z), rr * 0.8, (1.0, 1.0, 0.32)))     # flat skirt
        for k in range(6):
            a = 2 * math.pi * k / 6 + i * 0.7 + r.uniform(-0.2, 0.2)
            blobs.append(Blob((math.cos(a) * rr * 0.62, math.sin(a) * rr * 0.62, z - droop * rr), rr * 0.36, (1, 1, 0.7)))
    # spine up to a soft point, so the top tiers stay connected
    for k in range(6):
        t = k / 5
        blobs.append(Blob((0, 0, base + 0.3 + t * (height - base - 1.0)), 1.0 - 0.45 * t))
    blobs.append(Blob((0, 0, height - 0.8), 0.6, (1, 1, 1.6)))
    return blobs


def variants():
    out = []
    r = rng(101)
    out.append(TreeSpec("conifer_0", _tiers(r, 14.0, 3.4, 2.6, 6, 0.15), [Tube(trunk_path(12.5, 0.24, 0.08))], smooth=3))
    r = rng(113)
    out.append(TreeSpec("conifer_1", _tiers(r, 12.0, 2.6, 1.8, 7, 0.12), [Tube(trunk_path(11.0, 0.2, 0.07))], smooth=3))
    # 2: umbrella pine / cedar: flat-topped layers high on a bare trunk
    r = rng(127)
    blobs = []
    for z, rr in ((7.0, 3.4), (8.3, 3.0), (9.4, 2.2)):
        blobs.append(Blob((0, 0, z), rr, (1.0, 1.0, 0.38)))
        for k in range(6):
            a = 2 * math.pi * k / 6 + r.uniform(-0.3, 0.3)
            blobs.append(Blob((math.cos(a) * rr * 0.75, math.sin(a) * rr * 0.75, z + r.uniform(-0.2, 0.2)), rr * 0.42))
    out.append(TreeSpec("conifer_2", blobs, [Tube(trunk_path(8.5, 0.26, 0.12, lean=(0.03, 0.01)))]))
    return out
