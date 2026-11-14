"""The map's files and geometry, for the tools (tools/rail/, tools/logements_x/, tools/ligne18/...): the paths, the
pipeline's world files, the heightmap, the ground height as the pipeline drew it, polylines.

Map coordinates everywhere: metres, x east, y north, z up, origin Télécom Paris (Lambert-93 641117.6, 6846184.3;
l93.py converts); Godot = (x, z, -y).

godot/world/ holds the map pipeline's outputs as it wrote them: nothing changes them, the lots (godot/data/lots/)
change the map when it is built. A script using this module puts tools/common/ on its path.
"""
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "godot" / "world"


def world_files(world: dict) -> list:
    """The files of a world: world.json, its heightmap (one file or its bands, terrain "parts"), the ground mesh (its
    chunks' files: ground.bin, ground.1.bin...), ground_ids.bin and ground_index.json."""
    t = world["terrain"]
    gm = world["ground_mesh"]
    ground = sorted({gm["file"]} | {c["file"] for c in gm["chunks"] if "file" in c})
    return ["world.json", *(t.get("parts") or [t["file"]]), *ground, "ground_ids.bin", "ground_index.json"]


def read_heightmap(world_dir: Path, terrain: dict) -> np.ndarray:
    """The heightmap of world.json `terrain` in world_dir, (h, w) float32 (its bands joined when split)."""
    names = terrain.get("parts") or [terrain["file"]]
    a = np.concatenate([np.fromfile(Path(world_dir) / n, dtype="<f4") for n in names])
    return a.reshape(int(terrain["h"]), int(terrain["w"]))


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class Heights:
    """The ground height as godot/scripts/ground_heights.gd draws it: heightmap samples every `mesh_cell` metres (the
    2 m grid nodes), planar inside the two triangles of each cell, diagonal south-west -> north-east. Also gives the
    raw 0.5 m samples (sample) for the LiDAR statistics."""

    def __init__(self, path: Path, terrain: dict, mesh_cell: float):
        """`path`: the world's folder (or a file in it: the heightmap is read as `terrain` names it)."""
        self.w, self.h = int(terrain["w"]), int(terrain["h"])
        self.cell = float(terrain["cell"])
        self.ox, self.oy = float(terrain["origin_xy"][0]), float(terrain["origin_xy"][1])
        self.mesh_cell = float(mesh_cell)
        self.step = int(round(self.mesh_cell / self.cell))
        path = Path(path)
        self.data = read_heightmap(path if path.is_dir() else path.parent, terrain).astype(np.float64)

    def nodes(self, data=None) -> np.ndarray:
        """The node grid ground_heights.gd builds: (nh, nw), node (j, i) at x = ox + (i - 1) * mesh_cell,
        y = oy - (j - 1) * mesh_cell (one clamped node beyond each edge)."""
        if data is None:                     # this heightmap's own grid: built once (per data array)
            if getattr(self, "_nodes_of", None) is not self.data:
                self._nodes_cache = self.nodes(self.data)
                self._nodes_of = self.data
            return self._nodes_cache
        d = data
        nw = (self.w - 1) // self.step + 4
        nh = (self.h - 1) // self.step + 4
        rows = np.clip((np.arange(nh) - 1) * self.step, 0, self.h - 1)
        cols = np.clip((np.arange(nw) - 1) * self.step, 0, self.w - 1)
        return d[np.ix_(rows, cols)]

    def at(self, x, y, nodes=None):
        """Drawn ground height at map (x, y) (arrays or scalars), as ground_heights.gd at()."""
        n = self.nodes() if nodes is None else nodes
        nh, nw = n.shape
        fx = (np.asarray(x, dtype=np.float64) - self.ox) / self.mesh_cell + 1.0
        fy = (self.oy - np.asarray(y, dtype=np.float64)) / self.mesh_cell + 1.0
        i = np.clip(np.floor(fx).astype(int), 0, nw - 2)
        j = np.clip(np.floor(fy).astype(int), 0, nh - 2)
        u = fx - i
        v = fy - j
        z00 = n[j, i]
        z10 = n[j, i + 1]
        z01 = n[j + 1, i]
        z11 = n[j + 1, i + 1]
        lo = z00 + u * (z10 - z00) + v * (z01 - z00)
        hi = z11 + (1.0 - u) * (z01 - z11) + (1.0 - v) * (z10 - z11)
        return np.where(u + v <= 1.0, lo, hi)

    def sample(self, x, y):
        """Bilinear height of the raw 0.5 m samples (LiDAR statistics, not what the game draws)."""
        fx = (np.asarray(x, dtype=np.float64) - self.ox) / self.cell
        fy = (self.oy - np.asarray(y, dtype=np.float64)) / self.cell
        i = np.clip(np.floor(fx).astype(int), 0, self.w - 2)
        j = np.clip(np.floor(fy).astype(int), 0, self.h - 2)
        u = np.clip(fx - i, 0, 1)
        v = np.clip(fy - j, 0, 1)
        d = self.data
        return (d[j, i] * (1 - u) * (1 - v) + d[j, i + 1] * u * (1 - v) + d[j + 1, i] * (1 - u) * v
                + d[j + 1, i + 1] * u * v)

    def inside(self, x, y, margin=0.0):
        x0 = self.ox + margin
        y1 = self.oy - margin
        x1 = self.ox + (self.w - 1) * self.cell - margin
        y0 = self.oy - (self.h - 1) * self.cell + margin
        return (np.asarray(x) >= x0) & (np.asarray(x) <= x1) & (np.asarray(y) >= y0) & (np.asarray(y) <= y1)


# ---------------------------------------------------------------- polylines

def cumlen(p: np.ndarray) -> np.ndarray:
    return np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]


def resample(p: np.ndarray, step: float) -> np.ndarray:
    d = cumlen(p)
    s = np.arange(0.0, d[-1], step)
    return np.c_[np.interp(s, d, p[:, 0]), np.interp(s, d, p[:, 1])]
