"""The police helicopter (Car.SPECS "helicopter-police", scripts/helicopter.gd) from a ready-made model: "Eurocopter
ec135 Politia - High-poly" by solid3DDD (Sketchfab, CC BY 4.0: credited in godot/assets/cars/CREDITS.md), a glTF with
PBR textures, downloaded by the project owner into ref/vehicules/helicopterPolice/ (not published).

    .venv/Scripts/python.exe tools/vehicles/helicopter_police.py [--src ref/vehicules/helicopterPolice]
                                                                 [--out godot/assets/cars/ec135_police]

What it changes (the licence asks for the changes to be told):
- the glTF: its nodes named for scripts/helicopter.gd (rotor_main, rotor_tail: their pivots at the hubs; searchlight,
  the doors, body, glass...), the three extra UV sets dropped (copies of the first: Godot's materials read two at most),
  the buffer rewritten with what is left (one buffer view per accessor);
- the textures: 4096 px PNGs made JPEGs of 2048 px (colours, the body's normal map) or 1024 px (metal-roughness, the
  frame's and the cabin's normal maps): ~10 times less video memory;
- the livery (the body's colours, at full size before it is scaled down): its Romanian police markings made French.
  On each side the big "POLITIA" is split by the door's seam ("POL" on the door, "ITIA" behind it), the line under it
  ("UNITATEA SPECIALA DE AVIATIE") too; both are wiped (the glyphs found as dark blue blobs inside each island's box,
  the white paint put back) and written again in a geometric sans (Century Gothic, else DejaVu Sans), along the old
  lines (their slope and height measured from the old glyphs): "POL" + "ICE" in big letters, "UNITÉ" + "AÉRIENNE" under
  it, meeting at the seam as before. The two Romanian tricolours (blue, yellow, red) become French ones (blue, white,
  red). The lettering is mirrored on the left side's islands and upside down on the right side's (their UV layout):
  it is drawn upright, then flipped the same way.
"""
import argparse
import json
import shutil
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
NAMES = {
    "Sketchfab_model": "ec135", "Armature_27": "frame", "Bone_26": "parts",
    "Bone.001_1": "rotor_main", "blade_0": "rotor_main_blades",
    "Bone.002_3": "rotor_tail", "blade_tail_2": "rotor_tail_blades",
    "Bone.003_6": "searchlight", "spot_4": "searchlight_lamp", "spot_mirror_5": "searchlight_lens",
    "Bone.004_15": "door_front_left", "door_FL_13": "door_front_left_panel", "door_FL_glass_14": "door_front_left_glass",
    "Bone.005_9": "door_front_right", "door_FR_7": "door_front_right_panel", "door_FR_glass_8": "door_front_right_glass",
    "Bone.006_12": "door_rear_right", "door_RR_10": "door_rear_right_panel", "door_RR_glass_11": "door_rear_right_glass",
    "Bone.007_18": "door_rear_left", "door_RL_16": "door_rear_left_panel", "door_RL._glass_17": "door_rear_left_glass",
    "Bone.008_20": "turbine_left", "Bone.009_22": "turbine_right",
    "BODY_23": "body", "glass_24": "glass", "tail_lights_25": "tail_lights",
}
## texture -> (file written, size px, JPEG quality, full chroma)
TEXTURES = {
    "BODY_baseColor": ("body_base.jpg", 2048, 90, False),
    "BODY_normal": ("body_normal.jpg", 2048, 92, True),
    "BODY_metallicRoughness": ("body_mr.jpg", 1024, 92, True),
    "frame_baseColor": ("frame_base.jpg", 2048, 90, False),
    "frame_normal": ("frame_normal.jpg", 1024, 92, True),
    "frame_metallicRoughness": ("frame_mr.jpg", 1024, 92, True),
    "interior_baseColor": ("interior_base.jpg", 2048, 90, False),
    "interior_normal": ("interior_normal.jpg", 1024, 92, True),
    "interior_metallicRoughness": ("interior_mr.jpg", 1024, 92, True),
}
KEEP = ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0")

## The livery's text: per side, how its islands' lettering reads ("mirror_x": left to right is -x; "mirror_y": top
## to bottom is -y), and per island its box (full size texture px) and the new text (big, under it). "door" ends at
## the seam, "body" starts there.
SIDES = {
    "left": {"flip": "mirror_x", "islands": {
        "door": {"box": (580, 3070, 980, 3260), "big": "POL", "small": "UNITÉ"},
        "body": {"box": (140, 3092, 560, 3255), "big": "ICE", "small": "AÉRIENNE"}}},
    "right": {"flip": "mirror_y", "islands": {
        "door": {"box": (1180, 2720, 1560, 2890), "big": "POL", "small": "UNITÉ"},
        "body": {"box": (530, 2080, 950, 2260), "big": "ICE", "small": "AÉRIENNE"}}},
}
FLAGS = [(860, 3480, 1014, 3720), (2780, 3480, 2940, 3720)]     # the tricolours' boxes
FONTS_BIG = ["C:/Windows/Fonts/GOTHICB.TTF", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
FONTS_SMALL = ["C:/Windows/Fonts/GOTHIC.TTF", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
SMALL_TRACKING = 0.12                                           # extra space between the small letters, × size


# ---------------------------------------------------------------- the glTF

def rewrite_gltf(src: Path, out: Path) -> None:
    g = json.loads((src / "scene.gltf").read_text(encoding="utf-8"))
    data = (src / "scene.bin").read_bytes()
    for n in g["nodes"]:
        if n.get("name") in NAMES:
            n["name"] = NAMES[n["name"]]
    for m in g["materials"]:
        pbr = m.get("pbrMetallicRoughness", {})
        for info in [pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture"), m.get("normalTexture")]:
            if info:
                info.pop("texCoord", None)
    used = []
    for mesh in g["meshes"]:
        for p in mesh["primitives"]:
            p["attributes"] = {k: v for k, v in p["attributes"].items() if k in KEEP}
            used += list(p["attributes"].values()) + ([p["indices"]] if "indices" in p else [])
    sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    blob = bytearray()
    views = []
    remap = {}
    indices = {p["indices"] for mesh in g["meshes"] for p in mesh["primitives"] if "indices" in p}
    for old in sorted(set(used)):
        a = g["accessors"][old]
        bv = g["bufferViews"][a["bufferView"]]
        elem = sizes[a["componentType"]] * counts[a["type"]]
        stride = bv.get("byteStride", elem)
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        chunk = b"".join(data[start + i * stride:start + i * stride + elem] for i in range(a["count"])) \
            if stride != elem else data[start:start + elem * a["count"]]
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(chunk),
                      "target": 34963 if old in indices else 34962})
        blob += chunk
        a = dict(a)
        a["bufferView"] = len(views) - 1
        a.pop("byteOffset", None)
        remap[old] = len(remap)
        g.setdefault("_new_accessors", []).append(a)
    g["accessors"] = g.pop("_new_accessors")
    for mesh in g["meshes"]:
        for p in mesh["primitives"]:
            p["attributes"] = {k: remap[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = remap[p["indices"]]
    g["bufferViews"] = views
    g["buffers"] = [{"uri": "ec135_police.bin", "byteLength": len(blob)}]
    for img in g["images"]:
        name = Path(img["uri"]).stem
        img["uri"] = TEXTURES[name][0]
        img["mimeType"] = "image/jpeg"
    g["asset"]["extras"]["changes"] = "nodes renamed, extra UV sets dropped, textures scaled down, livery made " \
        "French (tools/vehicles/helicopter_police.py)"
    out.mkdir(parents=True, exist_ok=True)
    (out / "ec135_police.bin").write_bytes(bytes(blob))
    (out / "ec135_police.gltf").write_text(json.dumps(g, indent=1), encoding="utf-8")
    print("glTF: %d accessors, %.1f MB of buffer (was %.1f)" % (len(remap), len(blob) / 1e6, len(data) / 1e6))


# ---------------------------------------------------------------- the livery

def _font(paths: list, size: int) -> ImageFont.FreeTypeFont:
    for p in paths:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    raise SystemExit("none of these fonts here: %s" % paths)


def _to_reading(flip: str, x: float, y: float) -> tuple:
    return (-x, y) if flip == "mirror_x" else (x, -y)


def _glyphs(img: np.ndarray, box: tuple) -> list:
    """The lettering's blobs inside `box`: dark blue, not touching the box's edges (the livery's stripes and the
    islands' borders do): [(label mask in the box, slices)]."""
    x0, y0, x1, y1 = box
    c = img[y0:y1, x0:x1].astype(np.int32)
    navy = (c[..., 2] > c[..., 0] + 40) & (c[..., 2] > c[..., 1] + 30) & (c[..., 0] < 140)
    # with their blue-grey edges (the grey rivets have none of that blue)
    navy |= ndimage.binary_dilation(navy, iterations=2) & (c[..., 2] > c[..., 0] + 12) & (c.sum(axis=2) < 640)
    lab, _ = ndimage.label(navy)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None or (lab[sl] == i + 1).sum() < 3:
            continue                        # (slivers of a letter the seam cut count: they are wiped too)
        if sl[0].start == 0 or sl[1].start == 0 or sl[0].stop == y1 - y0 or sl[1].stop == x1 - x0:
            continue
        out.append((lab == i + 1, sl))
    return out


def _line(flip: str, box: tuple, blobs: list) -> dict:
    """The line `blobs` stand on, in the reading frame: its slope (from the blobs' bottoms), cap height, and where it
    starts and ends (reading x) with the baseline's reading y there."""
    x0, y0 = box[0], box[1]
    pts = []
    tops = []
    for _, sl in blobs:
        corners = [_to_reading(flip, x0 + x, y0 + y) for x in (sl[1].start, sl[1].stop) for y in (sl[0].start, sl[0].stop)]
        rx = [p[0] for p in corners]
        ry = [p[1] for p in corners]
        pts.append(((min(rx) + max(rx)) * 0.5, max(ry), min(rx), max(rx)))
        tops.append(max(ry) - min(ry))
    xs = np.array([p[0] for p in pts])
    ys = np.array([p[1] for p in pts])
    slope = float(np.polyfit(xs, ys, 1)[0]) if len(pts) > 2 and np.ptp(xs) > 10 else 0.0
    start = min(p[2] for p in pts)
    end = max(p[3] for p in pts)
    base = lambda x: float(np.median(ys - slope * xs) + slope * x)
    return {"slope": slope, "height": float(np.median(tops)), "start": (start, base(start)), "end": (end, base(end))}


def _text_coverage(text: str, font: ImageFont.FreeTypeFont, tracking: float) -> tuple:
    """`text` drawn upright as a coverage image (0..255), and its ink's box (left, top, right, bottom)."""
    pad = font.size
    w = int(font.getlength(text) + tracking * font.size * len(text)) + 2 * pad
    img = Image.new("L", (w, font.size * 2 + 2 * pad), 0)
    d = ImageDraw.Draw(img)
    x = pad
    for ch in text:
        d.text((x, pad), ch, font=font, fill=255)
        x += font.getlength(ch) + tracking * font.size
    return img, img.getbbox()


def _put_text(tex: np.ndarray, flip: str, text: str, fonts: list, line: dict, align: str, ink: np.ndarray,
              paint: np.ndarray, tracking: float, gap: bool = False) -> None:
    """Writes `text` on the texture along `line` (reading frame), its ink's end at the line's end (align "end": the
    door's part) or its start at the line's start ("start": the body's), as tall as the old letters, in `ink` over
    `paint`; only where there is paint (not the black between the UV islands). `gap`: a space before the line's end
    (the words meet at the seam: the islands touch on the model)."""
    size = 40
    probe = _font(fonts, size)
    cap = probe.getbbox("H")[3] - probe.getbbox("H")[1]
    font = _font(fonts, max(8, round(size * line["height"] / cap)))
    cov, bb = _text_coverage(text, font, tracking)
    anchor_img = (bb[2], bb[3]) if align == "end" else (bb[0], bb[3])
    anchor_tex_r = line["end"] if align == "end" else line["start"]
    if gap:
        space = font.getlength(" ") + tracking * font.size
        anchor_tex_r = (anchor_tex_r[0] - space, anchor_tex_r[1] - space * line["slope"])
    angle = np.degrees(np.arctan(line["slope"]))
    # turn about the anchor (PIL turns counter-clockwise for positive angles: the y axis points down)
    cov = cov.rotate(-angle, resample=Image.BICUBIC, center=anchor_img)
    arr = np.asarray(cov, dtype=np.float32) / 255.0
    h, w = arr.shape
    ys, xs = np.nonzero(arr > 0.0)
    for yy, xx in zip(ys, xs):
        rx = anchor_tex_r[0] + (xx - anchor_img[0])
        ry = anchor_tex_r[1] + (yy - anchor_img[1])
        tx, ty = (-rx, ry) if flip == "mirror_x" else (rx, -ry)
        tx = int(round(tx))
        ty = int(round(ty))
        if not (0 <= ty < tex.shape[0] and 0 <= tx < tex.shape[1]):
            continue
        if tex[ty, tx].astype(np.int32).sum() < 120:
            continue                        # (the black between islands)
        a = arr[yy, xx]
        tex[ty, tx] = np.clip(paint * (1.0 - a) + ink * a, 0, 255).astype(np.uint8)


def repaint(img: Image.Image) -> Image.Image:
    tex = np.array(img.convert("RGB"))
    for side in SIDES.values():
        flip = side["flip"]
        for isl in side["islands"].values():
            box = isl["box"]
            blobs = _glyphs(tex, box)
            big = [b for b in blobs if b[1][0].stop - b[1][0].start > 45]
            small = [b for b in blobs if 18 <= b[1][0].stop - b[1][0].start <= 45 and (b[0][b[1]]).sum() > 60]
            isl["lines"] = {"big": _line(flip, box, [b for b in big if (b[0][b[1]]).sum() > 300]),
                            "small": _line(flip, box, small)}
            x0, y0, x1, y1 = box
            sub = tex[y0:y1, x0:x1]
            mask = np.zeros(sub.shape[:2], bool)
            for m, _ in blobs:
                mask |= m
            core = ndimage.binary_erosion(mask, iterations=2)
            isl["ink"] = np.median(sub[core], axis=0) if core.any() else np.array([12.0, 18.0, 110.0])
            paint = sub[(~ndimage.binary_dilation(mask, iterations=4)) & (sub.astype(np.int32).sum(axis=2) > 600)]
            isl["paint"] = np.median(paint, axis=0)
            sub[ndimage.binary_dilation(mask, iterations=3)] = isl["paint"].astype(np.uint8)
        for key, isl in side["islands"].items():
            align = "end" if key == "door" else "start"
            _put_text(tex, flip, isl["big"], FONTS_BIG, isl["lines"]["big"], align, isl["ink"], isl["paint"], 0.02)
            _put_text(tex, flip, isl["small"], FONTS_SMALL, isl["lines"]["small"], align, isl["ink"], isl["paint"],
                      SMALL_TRACKING, gap=key == "door")
    for x0, y0, x1, y1 in FLAGS:            # Romanian yellow -> French white
        f = tex[y0:y1, x0:x1].astype(np.int32)
        yellow = (f[..., 0] > 150) & (f[..., 1] > 150) & (f[..., 2] < 140)
        f[yellow] = (244, 244, 244)
        tex[y0:y1, x0:x1] = f.astype(np.uint8)
    return Image.fromarray(tex)


# ---------------------------------------------------------------- textures

def textures(src: Path, out: Path) -> None:
    for name, (file, size, quality, full) in TEXTURES.items():
        img = Image.open(src / "textures" / (name + ".png")).convert("RGB")
        if name == "BODY_baseColor":
            img = repaint(img)
        img = img.resize((size, size), Image.LANCZOS)
        img.save(out / file, quality=quality, subsampling=0 if full else 2, optimize=True)
        print("%-28s -> %s (%d px, %.2f MB)" % (name, file, size, (out / file).stat().st_size / 1e6))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", default=str(ROOT / "ref/vehicules/helicopterPolice"))
    ap.add_argument("--out", default=str(ROOT / "godot/assets/cars/ec135_police"))
    ap.add_argument("--livery-only", help="write the repainted body texture (full size) to this PNG and stop")
    a = ap.parse_args()
    src = Path(a.src)
    if a.livery_only:
        repaint(Image.open(src / "textures/BODY_baseColor.png")).save(a.livery_only)
        return
    out = Path(a.out)
    rewrite_gltf(src, out)
    textures(src, out)
    lic = src / "license.txt"
    if lic.exists():
        shutil.copy(lic, out / "LICENSE.txt")


if __name__ == "__main__":
    main()
