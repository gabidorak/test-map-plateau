"""Oval crowns: taller than wide (young oaks, hornbeams, tall forest trees)."""
import math

from treelib import Blob, TreeSpec, Tube, branch, rng, shell, trunk_path


def variants():
    out = []
    # 0: stacked egg, 14 m, crown radius ~3.6 m
    r = rng(51)
    blobs = [Blob((0, 0, 7.4), 2.0), Blob((0, 0, 9.6), 1.9), Blob((0, 0, 11.4), 1.4)]
    blobs += shell(r, (0, 0, 9.0), (2.3, 2.3, 3.8), 14, (1.0, 1.3), z_min=-0.75)
    tubes = [Tube(trunk_path(9.0, 0.26, 0.1))]
    tubes += [branch((0, 0, 5.0 + k * 0.8), (math.cos(a), math.sin(a)), 1.5, 0.08, 0.04)
              for k, a in enumerate((0.3, 2.4, 4.4))]
    out.append(TreeSpec("oval_0", blobs, tubes))
    # 1: slimmer, lumpier flame
    r = rng(67)
    blobs = [Blob((0.2, 0, 6.8), 1.7), Blob((-0.1, 0.1, 8.8), 1.6), Blob((0.1, -0.1, 10.8), 1.3), Blob((0, 0, 12.2), 0.9)]
    blobs += shell(r, (0, 0, 9.2), (2.1, 2.1, 3.8), 12, (0.9, 1.25), z_min=-0.7, jitter=0.22)
    out.append(TreeSpec("oval_1", blobs, [Tube(trunk_path(10.0, 0.24, 0.09, lean=(0.0, 0.015)))]))
    return out
