"""Makes the textured marks of a ready-made truck from the maps of its archive; run by import_truck.py in the pipeline's
venv, which has Pillow and numpy (as car_textures.py for import_textured.py).

.venv/bin/python -I blender/vehicles/truck_textures.py <jobs.json>

jobs.json is a list of {"kind", "src", "out", "size": [w, h], "crop": [u0, v0, u1, v1] or null (the part of the map
the faces use, in UV: v up; their UVs are remapped onto the whole texture), "colours": [low, high] (hex)}:
- "lettering": light lettering on a dark ground (the sun visor's): upscaled with Lanczos, then the edges steepened
  (a smoothstep on the brightness), so the letters stay crisp although the source draws them 19 px high; PNG;
- "mask": a grey print on black (the curtains' hexagons) turned into the two colours; JPEG;
- "relief": a height map, dark lines raised (the tyre's sidewall lettering): the colour lifted a little on the raised
  parts and a normal map ("normal_out", OpenGL convention as glTF wants, PNG) from its slopes ("strength")."""
import json
import sys

import numpy as np
from PIL import Image, ImageFilter


def rgb(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def load(j: dict, size: tuple) -> np.ndarray:
    """The job's map (its crop), grey 0..1 at `size`."""
    im = Image.open(j["src"]).convert("L")
    if j.get("crop"):
        u0, v0, u1, v1 = j["crop"]
        w, h = im.size
        im = im.crop((round(u0 * w), round((1.0 - v1) * h), round(u1 * w), round((1.0 - v0) * h)))
    return np.asarray(im.resize(size, Image.LANCZOS)).astype(np.float64) / 255.0


def save(a: np.ndarray, out: str) -> None:
    im = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8))
    if out.endswith(".png"):
        im.save(out, "PNG", optimize=True)
    else:
        im.save(out, "JPEG", quality=90, subsampling=0, optimize=True)
    print("texture", out, im.size)


def main() -> None:
    with open(sys.argv[1]) as f:
        jobs = json.load(f)
    for j in jobs:
        size = tuple(j["size"])
        lo, hi = (rgb(c) for c in j["colours"])
        g = load(j, size)
        if j["kind"] == "lettering":
            t = np.clip((g - 0.25) / 0.5, 0.0, 1.0)
            k = t * t * (3.0 - 2.0 * t)
        elif j["kind"] == "mask":
            k = np.clip(g / max(np.percentile(g, 99.5), 1e-3), 0.0, 1.0)
        else:
            k = 1.0 - g                                     # dark lines: raised
        save(lo + (hi - lo) * k[..., None], j["out"])
        if j["kind"] == "relief":
            blur = Image.fromarray((k * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
            hgt = np.asarray(blur).astype(np.float64) / 255.0
            d_row, d_col = np.gradient(hgt)
            s = j.get("strength", 2.0)
            # image rows go down, the texture's v up: the slope along v is minus the slope along the rows
            n = np.dstack([-d_col * s, d_row * s, np.ones_like(hgt)])
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            save((n * 0.5 + 0.5) * 255.0, j["normal_out"])


main()
