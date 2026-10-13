"""Saplings: young trees with a wooden stake (unmatched OSM trees, gaps in tree rows)."""
import math

from treelib import PART_TIE, PART_WOOD, Blob, TreeSpec, Tube, rng, shell, trunk_path


def variants():
    out = []
    # 0: one stake and a tie
    r = rng(151)
    blobs = [Blob((0, 0, 2.45), 0.6)] + shell(r, (0, 0, 2.5), (0.5, 0.5, 0.45), 7, (0.32, 0.42), z_min=-0.4)
    tubes = [Tube(trunk_path(2.3, 0.045, 0.03, flare=1.2, steps=4)),
             Tube([(0.16, 0, -0.3, 0.035), (0.16, 0, 1.75, 0.035)], PART_WOOD),
             Tube([(0.0, 0, 1.45, 0.025), (0.16, 0, 1.45, 0.025)], PART_TIE)]
    out.append(TreeSpec("sapling_0", blobs, tubes, voxel=0.07, smooth=8, crown_tris=(700, 220, 70)))
    # 1: two stakes with a crossbar (street plantings)
    r = rng(163)
    blobs = [Blob((0, 0, 2.6), 0.55, (1, 1, 1.25))] + shell(r, (0, 0, 2.7), (0.42, 0.42, 0.6), 8, (0.28, 0.38), z_min=-0.5)
    tubes = [Tube(trunk_path(2.5, 0.05, 0.03, flare=1.2, steps=4))]
    for s in (-1, 1):
        tubes.append(Tube([(0.0, s * 0.22, -0.3, 0.035), (0.0, s * 0.22, 1.6, 0.035)], PART_WOOD))
    tubes.append(Tube([(0.0, -0.26, 1.3, 0.03), (0.0, 0.26, 1.3, 0.03)], PART_WOOD))
    tubes.append(Tube([(0.0, -0.05, 1.1, 0.02), (0.0, 0.05, 1.1, 0.02)], PART_TIE))
    out.append(TreeSpec("sapling_1", blobs, tubes, voxel=0.07, smooth=8, crown_tris=(700, 220, 70)))
    return out
