"""Downscales and packs the PBR texture maps of a ready-made car model for Godot; run by import_textured.py in the
pipeline's venv, which has Pillow (Blender writes JPEGs with chroma subsampling only, which would blur the packed
channels into each other and bend the normals).

.venv/bin/python -I blender/vehicles/car_textures.py <jobs.json>

jobs.json is a list of {"out", "size" (px, square), "quality", "rgb": source} (a colour map) or {..., "channels":
[red, green, blue]} (grey maps packed into one, e.g. glTF's occlusion-roughness-metallic), with "exact": true for
no chroma subsampling (normal and packed maps), and "patches": [[u, v, r], ...] to paint discs out (UV centre and
radius: each takes the median colour of the ring between 0.35 r and 0.94 r, e.g. a badge baked into the maps whose
geometry is gone; its outline at r stays). Lanczos resampling."""
import json
import sys

import numpy as np
from PIL import Image


def patch(im: Image.Image, patches: list) -> Image.Image:
    a = np.asarray(im).astype(np.float64)
    h, w = a.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    for u, v, r in patches:
        d = np.hypot(xs + 0.5 - u * w, ys + 0.5 - (1.0 - v) * h) / w     # in UV units
        ring = (d > 0.35 * r) & (d < 0.94 * r)
        fill = np.median(a[ring], axis=0)
        k = np.clip((r - d) * w / 1.5, 0.0, 1.0)[..., None]                 # 1.5 px soft edge
        a = a * (1.0 - k) + fill * k
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8))


def main() -> None:
    with open(sys.argv[1]) as f:
        jobs = json.load(f)
    for j in jobs:
        n = (j["size"], j["size"])
        if "rgb" in j:
            im = Image.open(j["rgb"]).convert("RGB").resize(n, Image.LANCZOS)
        else:
            im = Image.merge("RGB", [Image.open(p).convert("L").resize(n, Image.LANCZOS) for p in j["channels"]])
        if j.get("patches"):
            im = patch(im, j["patches"])
        im.save(j["out"], "JPEG", quality=j["quality"], subsampling=0 if j.get("exact") else 2, optimize=True)
        print("texture", j["out"], im.size)


main()
