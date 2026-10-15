"""Builds the realistic cars of the drivable vehicles: a compact five-door hatchback (proportions of a Renault Clio V),
a compact family SUV (proportions of a Peugeot 3008 II with its black "floating" roof), and the hatchback as a Police
nationale patrol car (the grey livery of 2021 on: a blue band over the arch on the viewer's left of each side and a
red one on the right, "POLICE NATIONALE" with a tricolour mark on the doors, bonnet and tailgate, a dotted reflective
line under the windows, reflective squares across the rear bumper; a blue LED light bar on the roof and blue flashers
in the grille). No brand badges on purpose.

blender -b --factory-startup -P blender/vehicles/build_car.py -- [--car=compact_hatchback|family_suv|police_hatchback]
                                                                 [--out_dir=godot/assets/cars] [--preview=data/review/cars]

Unlike the toy Kenney cars, these have real PBR materials and a fitted-out cabin seen through see-through glass, for
the cab view (scripts/car.gd): dashboard with a digital cluster and a centre touchscreen, air vents, centre console and
gear selector, door cards, sun visors, rear-view mirror, two front seats and a rear bench, and the steering wheel
("steering", spins about its local Z = glTF Y; a name ending in "_wheel" would become a VehicleWheel3D in Godot).
The body is one lofted shell: per station along the car, a cross-section from the side-view top line, beltline and
sill, and the plan-view widths at the shoulder and of the roof (or bonnet); its two ends are closed by rings shrinking
onto the middle of the end section (bumpers), bent back into a rounded nose and tail. Glazing, lamps, grilles, number
plates and panel seams are drawn on that shell: the planes bounding each of them are cut into it first (bisect), so
their outlines are straight and exact, then its faces take their material. The shell is then thickened inwards (the
cabin side is trim, the edges of the window openings black seals) and the wheel arches are cut out of it, with liners
behind them. Headlights sit 2 cm deep behind a clear lens.
Blender space: metres, z up, front = -Y, left = +X, origin on the ground under the middle of the car (glTF/Godot: front
= +Z, left = +X, as scripts/car.gd expects). Exports "body" (shell, glass, interior), the wheel objects
(wheel_front_left ... wheel_rear_right, origin at the wheel centre), "mirrors" (outside the body box, so they do not
widen the collision box), the lamps car.gd switches (indicator_left/right, brake_lights) and "steering". The
headlight and tail lamp surfaces use the materials "headlight" and "taillight", which car.gd lights at night.
The police car's livery is draped on the body: flat outlines (bands, lettering from a font, marks), cut into small
cells, each corner moved onto the shell along a ray and lifted 1.5 mm off it, cut at the door gaps. Its light bar is an
object of its own ("lightbar", so it does not raise the collision box), its blue lenses and grille flashers too
(beacon_left, beacon_right, beacon_grille_left, beacon_grille_right), which scripts/police_car.gd flashes.
<car>.json (next to the .glb) names them and gives the cab (driver and passenger seat and eye, steering wheel, the size
of the seated look-alikes and the cab camera's pitch) in glTF coordinates.
--preview renders <prefix>_<car>_front.png, _rear.png, _side.png and _cab.png (the driver's view; Cycles, a few
seconds each), and the police car's right side too (_side_right.png)."""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[2]

# name: base colour, metallic, roughness, (emission strength)
MATERIALS = {
    "paint_red": ("#9E1018", 0.55, 0.28, 0.0),
    "paint_blue": ("#1E3550", 0.55, 0.3, 0.0),
    "paint_black": ("#0B0C0E", 0.3, 0.22, 0.0),
    "paint_silver": ("#9A9FA6", 0.6, 0.3, 0.0),        # the Police nationale's grey
    # police livery films and the light bar's lenses (scripts/police_car.gd swaps "beacon" for lit / unlit blue)
    "livery_blue": ("#2B399E", 0.0, 0.38, 0.0),
    "livery_red": ("#D93A2C", 0.0, 0.38, 0.0),
    "livery_white": ("#EEF0F2", 0.0, 0.38, 0.0),
    "livery_navy": ("#1B1F2E", 0.0, 0.42, 0.0),        # lettering
    "reflector": ("#D3D7DC", 0.4, 0.25, 0.0),          # retroreflective dots
    "beacon": ("#1C3CC8", 0.0, 0.12, 0.0),
    "trim_black": ("#08090A", 0.1, 0.12, 0.0),         # piano black
    "plastic_black": ("#1A1B1D", 0.0, 0.72, 0.0),      # textured bumper / cladding plastic
    "grille": ("#0C0D0F", 0.2, 0.35, 0.0),
    "chrome": ("#D4D8DC", 1.0, 0.12, 0.0),
    "alu": ("#A9AEB4", 0.85, 0.32, 0.0),
    "seal": ("#111213", 0.0, 0.6, 0.0),
    "seam": ("#0A0A0B", 0.0, 0.7, 0.0),
    "underbody": ("#151617", 0.0, 0.85, 0.0),
    "liner": ("#121314", 0.0, 0.9, 0.0),
    "glass_front": ("#1C252B", 0.0, 0.03, 0.0),
    "glass_side": ("#141B20", 0.0, 0.03, 0.0),
    "glass_rear": ("#0C1013", 0.0, 0.03, 0.0),
    "lens": ("#E8EEF2", 0.0, 0.02, 0.0),
    "headlight": ("#C9CED3", 0.9, 0.18, 0.0),
    "drl": ("#F4F8FF", 0.0, 0.2, 2.5),
    "taillight": ("#5E070C", 0.0, 0.06, 0.0),
    "brake": ("#B0101A", 0.0, 0.1, 0.0),
    "indicator": ("#B8600E", 0.0, 0.12, 0.0),
    "reverse": ("#D8DADC", 0.0, 0.15, 0.0),
    "plate": ("#F2F2EE", 0.0, 0.45, 0.0),
    "plate_eu": ("#1A3C9C", 0.0, 0.45, 0.0),
    "mirror_glass": ("#B8C4CC", 1.0, 0.04, 0.0),
    "tyre": ("#19191A", 0.0, 0.88, 0.0),
    "tyre_wall": ("#202022", 0.0, 0.8, 0.0),
    "rim": ("#B9BEC3", 0.9, 0.25, 0.0),
    "rim_dark": ("#3A3D41", 0.8, 0.3, 0.0),
    "hub": ("#2C2E31", 0.6, 0.45, 0.0),
    "disc": ("#6E7175", 0.9, 0.4, 0.0),
    "caliper": ("#2A2B2D", 0.3, 0.5, 0.0),
    # cabin
    "dash": ("#1E1F21", 0.0, 0.75, 0.0),
    "trim": ("#3B3D41", 0.0, 0.7, 0.0),
    "trim_light": ("#8C8F93", 0.0, 0.65, 0.0),
    "headliner": ("#B9B6AF", 0.0, 0.95, 0.0),
    "carpet": ("#1B1B1C", 0.0, 1.0, 0.0),
    "seat": ("#2C2D30", 0.0, 0.92, 0.0),
    "seat_accent": ("#55585D", 0.0, 0.9, 0.0),
    "leather": ("#141415", 0.0, 0.55, 0.0),
    "screen": ("#0D1B2A", 0.0, 0.1, 0.9),
    "screen_ui": ("#57B4FF", 0.0, 0.2, 2.0),
    "gauge": ("#E9F2FF", 0.0, 0.3, 1.6),
    "needle": ("#FF3A20", 0.0, 0.3, 2.0),
}
ALPHA = {"glass_front": 0.22, "glass_side": 0.42, "glass_rear": 0.62, "lens": 0.12}    # see-through, both faces drawn
DOUBLE = {"liner"}                                                                     # both faces drawn, opaque

# ---------------------------------------------------------------- the two cars

SEG = {"bottom": 0, "rocker": 1, "side": 2, "shoulder": 3, "beltline": 4, "glass": 5, "rail": 6, "top": 7, "cap": 8}


def plane_x(x, keep_above):
    """Half-space bound by the plane x = const (left side; mirrored features flip it)."""
    return ((x, 0, 0), (-1 if keep_above else 1, 0, 0))


def plane_y(y, keep_above):
    return ((0, y, 0), (0, -1 if keep_above else 1, 0))


def plane_z(z, keep_above):
    return ((0, 0, z), (0, 0, -1 if keep_above else 1))


def line_yz(p1, p2, keep):
    """Half-space bound by the plane through side-view points p1, p2 (y, z) across the car, `keep` (y, z) inside."""
    d = (p2[0] - p1[0], p2[1] - p1[1])
    n = (0, d[1], -d[0])
    if n[1] * (keep[0] - p1[0]) + n[2] * (keep[1] - p1[1]) > 0:
        n = (0, -n[1], -n[2])
    return ((0, p1[0], p1[1]), n)


def line_xz(p1, p2, keep):
    """Half-space bound by the plane through front-view points p1, p2 (x, z) along the car, `keep` (x, z) inside."""
    d = (p2[0] - p1[0], p2[1] - p1[1])
    n = (d[1], 0, -d[0])
    if n[0] * (keep[0] - p1[0]) + n[2] * (keep[1] - p1[1]) > 0:
        n = (-n[0], 0, -n[2])
    return ((p1[0], 0, p1[1]), n)


def feat(m, x=None, y=None, z=None, planes=(), segs=None, mirror=True, obj=None, box=None):
    """A material region on the shell: inside all the half-spaces (x/y/z: (lo, hi) bounds, None = open; for a mirrored
    feature x is on the left, +X) and on the shell segments `segs` (None: any). `box` ((lo), (hi)) limits where its
    planes cut the shell (default: its x/y/z bounds, open ones unlimited). `obj`: its faces become their own object
    (obj_left / obj_right when mirrored)."""
    ps = list(planes)
    for axis, b, mk in (("x", x, plane_x), ("y", y, plane_y), ("z", z, plane_z)):
        if b is not None:
            if b[0] is not None:
                ps.append(mk(b[0], True))
            if b[1] is not None:
                ps.append(mk(b[1], False))
    if box is None:
        lo, hi = [-9.0, -9.0, -9.0], [9.0, 9.0, 9.0]
        for k, b in enumerate((x, y, z)):
            if b is not None:
                lo[k] = b[0] if b[0] is not None else -9.0
                hi[k] = b[1] if b[1] is not None else 9.0
        box = (lo, hi)
    return {"mat": m, "planes": ps, "segs": None if segs is None else {SEG[s] for s in segs}, "mirror": mirror,
            "obj": obj, "box": box}


def seams(y_lines, z0, z1, segs=("rocker", "side", "shoulder", "beltline"), w=0.005):
    """Vertical panel gaps at the given y (door shut lines)."""
    return [feat("seam", y=(y, y + w), z=(z0, z1), segs=segs) for y in y_lines]


HATCH_DOORS = (-0.842, 0.262, 0.985)        # door shut lines (y) of the hatchback
SUV_DOORS = (-0.842, 0.282, 1.07)

CARS = {
    "compact_hatchback": {
        "label": "compact hatchback",
        "paint": "paint_red",
        "length": 4.05,
        "wheel": {"r": 0.315, "w": 0.205, "rim_r": 0.216, "x": 0.772, "axles": (-1.20, 1.38), "arch": 0.36,
                  "rim": "rim", "spokes": 5},
        # side view (y, z) and plan view (y, half width) keys, interpolated monotonically
        "profile": {
            "z_top": [(-2.025, 0.72), (-1.98, 0.775), (-1.88, 0.815), (-1.60, 0.855), (-1.20, 0.89), (-0.95, 0.91),
                      (-0.88, 0.935), (-0.50, 1.17), (-0.13, 1.385), (0.0, 1.415), (0.3, 1.437), (0.8, 1.437),
                      (1.15, 1.42), (1.30, 1.395), (1.38, 1.36), (1.60, 1.205), (1.80, 1.06), (1.92, 1.0),
                      (2.025, 0.965)],
            "z_belt": [(-2.025, 0.68), (-1.98, 0.73), (-1.85, 0.78), (-1.40, 0.84), (-1.05, 0.87), (-0.88, 0.90),
                       (-0.40, 0.95), (0.30, 0.985), (0.90, 1.02), (1.30, 1.05), (1.55, 1.045), (1.80, 1.0),
                       (1.93, 0.955), (2.025, 0.925)],
            "w": [(-2.025, 0.52), (-2.005, 0.64), (-1.97, 0.73), (-1.90, 0.80), (-1.78, 0.856), (-1.60, 0.884), (-1.30, 0.895),
                  (0.0, 0.895), (1.30, 0.895), (1.70, 0.893), (1.88, 0.882), (1.97, 0.86), (2.0, 0.835),
                  (2.025, 0.78)],
            "w_top": [(-2.025, 0.42), (-1.95, 0.62), (-1.80, 0.73), (-1.30, 0.785), (-0.88, 0.77), (-0.13, 0.645),
                      (0.40, 0.61), (1.10, 0.60), (1.40, 0.60), (1.80, 0.69), (1.95, 0.73), (2.025, 0.69)],
            "z_bot": [(-2.025, 0.33), (-1.95, 0.25), (-1.78, 0.205), (-1.20, 0.195), (1.40, 0.195), (1.78, 0.22),
                      (1.97, 0.29), (2.025, 0.37)],
        },
        "shoulder": 0.11,           # shoulder (widest) this far under the beltline
        "tumble": 0.05,             # beltline this far in from the shoulder
        "nose": (0.30, 1.6, 0.47),  # ends bent back over this length: (ramp m, curvature, height of the leading point)
        "tail": (0.25, 0.7, 0.55),
        "features": [
            # glazing
            feat("glass_front", y=(-0.855, -0.14), segs=("top",)),
            feat("glass_side", y=(-0.76, 0.215), segs=("glass",)),
            feat("glass_side", y=(0.315, None), segs=("glass",),
                 planes=[line_yz((1.08, 1.04), (0.95, 1.38), (0.5, 1.2))], box=((-9, 0.2, 0.8), (9, 1.3, 1.5))),
            feat("plastic_black", y=(-0.89, -0.76), segs=("glass",)),          # mirror sail
            feat("trim_black", y=(0.215, 0.315), segs=("glass",)),             # B-pillar
            feat("glass_rear", y=(1.40, 1.80), segs=("top",)),
            # front: swept-back headlights (an L of daytime running lamp along the bottom and outer edge, the
            # indicator at the outer end), a slim grille with a chrome line, a wide lower intake, corner vents, plate
            feat("trim_black", x=(0.295, None), y=(None, -1.60),
                 planes=[line_xz((0.30, 0.728), (0.90, 0.815), (0.6, 0.6)), line_xz((0.30, 0.647), (0.90, 0.672), (0.6, 0.9))],
                 box=((0.2, -2.3, 0.55), (1.0, -1.5, 0.9))),
            feat("headlight", x=(0.305, None), y=(None, -1.61),
                 planes=[line_xz((0.30, 0.72), (0.90, 0.807), (0.6, 0.6)), line_xz((0.30, 0.655), (0.90, 0.68), (0.6, 0.9))],
                 box=((0.2, -2.3, 0.55), (1.0, -1.5, 0.9))),
            feat("drl", x=(0.33, None), y=(None, -1.62),
                 planes=[line_xz((0.30, 0.655), (0.90, 0.68), (0.6, 0.9)), line_xz((0.30, 0.669), (0.90, 0.694), (0.6, 0.6))],
                 box=((0.2, -2.3, 0.55), (1.0, -1.5, 0.9))),
            feat("drl", x=(0.33, 0.345), y=(None, -1.62), z=(0.655, 0.722), box=((0.2, -2.3, 0.55), (1.0, -1.5, 0.9))),
            feat("indicator", x=(0.66, None), y=(-1.85, -1.66), z=(0.70, 0.81), obj="indicator"),
            # C of running lamp down the bumper corners
            feat("trim_black", y=(None, -1.70), z=(0.47, 0.66),
                 planes=[line_xz((0.735, 0.66), (0.70, 0.47), (0.9, 0.55)), line_xz((0.785, 0.66), (0.75, 0.47), (0.6, 0.55))],
                 box=((0.55, -2.3, 0.4), (0.95, -1.5, 0.7))),
            feat("drl", y=(None, -1.70), z=(0.48, 0.655),
                 planes=[line_xz((0.745, 0.66), (0.71, 0.47), (0.9, 0.55)), line_xz((0.775, 0.66), (0.74, 0.47), (0.6, 0.55))],
                 box=((0.55, -2.3, 0.4), (0.95, -1.5, 0.7))),
            # big grille between the headlights, chrome along its top, wide lower intake, corner vents
            feat("grille", y=(None, -1.82), z=(0.50, 0.715), mirror=False,
                 planes=[line_xz((0.295, 0.715), (0.36, 0.50), (0.0, 0.6)), line_xz((-0.295, 0.715), (-0.36, 0.50), (0.0, 0.6))],
                 box=((-0.45, -2.3, 0.45), (0.45, -1.7, 0.8))),
            feat("chrome", x=(-0.295, 0.295), y=(None, -1.82), z=(0.706, 0.716), mirror=False,
                 box=((-0.4, -2.3, 0.6), (0.4, -1.7, 0.8))),
            feat("chrome", y=(None, -1.82), z=(0.50, 0.51), mirror=False,
                 planes=[line_xz((0.295, 0.715), (0.36, 0.50), (0.0, 0.6)), line_xz((-0.295, 0.715), (-0.36, 0.50), (0.0, 0.6))],
                 box=((-0.45, -2.3, 0.45), (0.45, -1.7, 0.8))),
            feat("grille", y=(None, -1.86), planes=[line_xz((0.62, 0.45), (0.52, 0.27), (0.0, 0.4)),
                                                     line_xz((-0.62, 0.45), (-0.52, 0.27), (0.0, 0.4))],
                 z=(0.27, 0.45), mirror=False, box=((-0.7, -2.3, 0.2), (0.7, -1.7, 0.6))),
            feat("plastic_black", x=(-0.58, 0.58), y=(None, -1.75), z=(None, 0.27), mirror=False,
                 box=((-0.6, -2.3, 0.0), (0.6, -1.6, 0.4))),
            feat("grille", x=(0.66, 0.82), y=(None, -1.80), z=(0.30, 0.42),
                 planes=[line_xz((0.66, 0.42), (0.70, 0.30), (0.8, 0.36))]),
            feat("plate", x=(-0.26, 0.26), y=(None, -1.90), z=(0.33, 0.44), mirror=False),
            feat("plate_eu", x=(0.22, 0.26), y=(None, -1.90), z=(0.33, 0.44), mirror=False),
            # rear: lamps wrapping round the corners (brake band inside, indicator inboard), plate, black lower bumper
            # with reflectors, reversing lamp
            feat("trim_black", x=(0.41, None), y=(1.78, None),
                 planes=[line_xz((0.42, 1.008), (0.90, 0.983), (0.6, 0.8)), line_xz((0.42, 0.842), (0.90, 0.822), (0.6, 1.0))],
                 box=((0.3, 1.6, 0.7), (1.0, 2.3, 1.1))),
            feat("taillight", x=(0.42, None), y=(1.79, None),
                 planes=[line_xz((0.42, 1.0), (0.90, 0.975), (0.6, 0.8)), line_xz((0.42, 0.85), (0.90, 0.83), (0.6, 1.0))],
                 box=((0.3, 1.6, 0.7), (1.0, 2.3, 1.1))),
            feat("brake", x=(0.50, None), y=(1.79, None),
                 planes=[line_xz((0.42, 0.925), (0.90, 0.90), (0.6, 0.8)), line_xz((0.42, 0.90), (0.90, 0.875), (0.6, 1.0))],
                 box=((0.3, 1.6, 0.7), (1.0, 2.3, 1.1)), obj="brake"),
            feat("indicator", x=(0.43, 0.49), y=(1.79, None), z=(0.86, 0.99), obj="indicator"),
            feat("plate", x=(-0.26, 0.26), y=(1.90, None), z=(0.70, 0.805), mirror=False),
            feat("plate_eu", x=(0.22, 0.26), y=(1.90, None), z=(0.70, 0.805), mirror=False),
            feat("plastic_black", y=(1.80, None), z=(None, 0.42), box=((-1, 1.6, 0), (1, 2.3, 0.5))),
            feat("taillight", x=(0.62, 0.80), y=(1.90, None), z=(0.34, 0.37)),
            feat("reverse", x=(0.20, 0.32), y=(1.95, None), z=(0.43, 0.47)),
            # bonnet and tailgate shut lines, door gaps
            feat("seam", y=(-1.875, -1.870), z=(0.70, None), segs=("top", "rail", "glass", "cap"), mirror=False,
                 box=((-1, -2.0, 0.6), (1, -1.7, 1.0))),
            feat("seam", x=(0.70, 0.705), y=(-1.875, -0.89), segs=("top", "rail", "glass")),
            feat("seam", x=(0.62, 0.625), y=(1.86, None), z=(0.60, 1.0)),
            feat("seam", x=(-0.625, 0.625), y=(1.86, None), z=(0.598, 0.603), mirror=False,
                 box=((-0.7, 1.8, 0.5), (0.7, 2.3, 0.7))),
            *seams(HATCH_DOORS, 0.23, 0.98),
            feat("underbody", segs=("bottom",), mirror=False),
        ],
        "doors": HATCH_DOORS,
        "mirror": {"y": -0.80, "z": 0.93, "paint": True},
        "handles": [(-0.18, -0.06), (0.71, 0.83)],
        "antenna": 0.95,            # shark fin this far from the tail
        "spoiler": 1.36,            # y of the roof spoiler
        "rear_wiper": True,
        "cab": {
            "floor": 0.30, "cowl": (-0.88, 0.935), "firewall": -1.02, "seat_x": 0.37, "seat_y": 0.06, "cushion": 0.50,
            "rear_y": 0.86, "rear_end": 1.86, "header": -0.14, "eye": (0.10, 1.20), "figure": 0.7, "eye_pitch": 0.18,
            "steering": ((-0.37, 0.87), (0.0, 0.88, 0.47)),
            "shelf": (1.20, 1.85, 0.97),
        },
    },
    "family_suv": {
        "label": "family SUV",
        "paint": "paint_blue",
        "roof": "paint_black",
        "length": 4.45,
        "wheel": {"r": 0.352, "w": 0.225, "rim_r": 0.229, "x": 0.792, "axles": (-1.33, 1.345), "arch": 0.40,
                  "rim": "rim_dark", "spokes": 10},
        "profile": {
            "z_top": [(-2.225, 0.88), (-2.16, 0.955), (-2.00, 1.005), (-1.60, 1.045), (-1.20, 1.07), (-0.95, 1.085),
                      (-0.87, 1.115), (-0.52, 1.36), (-0.20, 1.565), (-0.05, 1.61), (0.4, 1.63), (1.2, 1.625),
                      (1.70, 1.60), (1.86, 1.58), (1.95, 1.535), (2.10, 1.34), (2.18, 1.22), (2.225, 1.17)],
            "z_belt": [(-2.225, 0.83), (-2.16, 0.90), (-2.00, 0.955), (-1.50, 0.995), (-0.90, 1.03), (-0.40, 1.06),
                       (0.4, 1.09), (1.3, 1.12), (1.75, 1.14), (2.0, 1.135), (2.225, 1.11)],
            "w": [(-2.225, 0.67), (-2.19, 0.79), (-2.12, 0.855), (-1.98, 0.897), (-1.70, 0.916), (-1.30, 0.92),
                  (1.40, 0.92), (1.85, 0.915), (2.05, 0.895), (2.17, 0.85), (2.225, 0.77)],
            "w_top": [(-2.225, 0.58), (-2.12, 0.72), (-1.90, 0.78), (-1.30, 0.80), (-0.90, 0.79), (-0.10, 0.665),
                      (0.5, 0.645), (1.7, 0.635), (2.0, 0.665), (2.225, 0.665)],
            "z_bot": [(-2.225, 0.43), (-2.12, 0.34), (-1.95, 0.285), (-1.60, 0.265), (1.60, 0.265), (1.95, 0.31),
                      (2.15, 0.37), (2.225, 0.46)],
        },
        "shoulder": 0.13,
        "tumble": 0.04,
        "nose": (0.32, 1.5, 0.64),
        "tail": (0.25, 0.45, 0.66),
        "features": [
            # glazing, black pillars, chrome window line and the black "floating" roof
            feat("glass_front", y=(-0.855, -0.20), segs=("top",)),
            feat("glass_side", y=(-0.78, 0.235), segs=("glass",)),
            feat("glass_side", y=(0.335, 1.25), segs=("glass",)),
            feat("glass_rear", y=(1.28, None), segs=("glass",),
                 planes=[line_yz((1.86, 1.14), (1.70, 1.52), (1.5, 1.3))], box=((-9, 1.2, 1.0), (9, 2.0, 1.7))),
            feat("plastic_black", y=(-0.90, -0.78), segs=("glass",)),
            feat("trim_black", y=(0.235, 0.335), segs=("glass",)),
            feat("trim_black", y=(1.25, 1.28), segs=("glass",)),
            feat("chrome", y=(-0.78, 1.86), segs=("beltline",)),
            feat("paint_black", y=(-0.20, 1.98), segs=("top", "rail"), mirror=False),
            feat("paint_black", y=(-0.855, -0.20), segs=("rail",)),
            feat("paint_black", y=(1.28, None), segs=("glass",), planes=[line_yz((1.86, 1.14), (1.70, 1.52), (2.2, 1.3))],
                 box=((-9, 1.6, 1.0), (9, 2.3, 1.7))),
            feat("glass_rear", y=(1.98, 2.17), segs=("top",)),
            # front: slim headlights over a wide grille with chrome slats, DRL fangs, lower intake, skid plate, plate
            feat("headlight", x=(0.50, None), y=(None, -1.90),
                 planes=[line_xz((0.50, 0.84), (0.88, 0.875), (0.7, 0.95)), line_xz((0.50, 0.925), (0.88, 0.94), (0.7, 0.8))],
                 box=((0.4, -2.4, 0.75), (1.0, -1.7, 1.0))),
            feat("indicator", x=(0.80, None), y=(None, -1.90), z=(0.84, 0.95), obj="indicator"),
            feat("grille", x=(-0.50, 0.50), y=(None, -2.0), z=(0.60, 0.88), mirror=False, box=((-0.55, -2.4, 0.5), (0.55, -1.9, 0.95))),
            *[feat("chrome", x=(-0.47, 0.47), y=(None, -2.0), z=(z, z + 0.012), mirror=False,
                   box=((-0.55, -2.4, 0.5), (0.55, -1.9, 0.95))) for z in (0.645, 0.695, 0.745, 0.795, 0.845)],
            feat("drl", y=(None, -1.90), planes=[line_xz((0.70, 0.83), (0.66, 0.55), (0.8, 0.7)),
                                                  line_xz((0.735, 0.83), (0.695, 0.55), (0.6, 0.7))],
                 z=(0.55, 0.83), box=((0.55, -2.4, 0.5), (0.85, -1.8, 0.9))),
            feat("grille", x=(-0.58, 0.58), y=(None, -2.0), z=(0.42, 0.56), mirror=False),
            feat("plate", x=(-0.26, 0.26), y=(None, -2.0), z=(0.47, 0.58), mirror=False),
            feat("plate_eu", x=(0.22, 0.26), y=(None, -2.0), z=(0.47, 0.58), mirror=False),
            feat("alu", x=(-0.45, 0.45), y=(None, -1.95), z=(None, 0.42), mirror=False, box=((-0.5, -2.4, 0.2), (0.5, -1.8, 0.5))),
            # lower cladding all round, rear: claw lamps joined by a black band, plate, skid plate
            feat("plastic_black", z=(None, 0.43), segs=("rocker", "side", "cap"), mirror=False),
            feat("trim_black", x=(-0.50, 0.50), y=(2.05, None), z=(1.00, 1.08), mirror=False, box=((-0.6, 1.9, 0.9), (0.6, 2.4, 1.2))),
            feat("taillight", x=(0.50, None), y=(2.0, None), z=(0.98, 1.10)),
            feat("brake", x=(0.55, 0.80), y=(2.0, None), z=(1.035, 1.075), obj="brake"),
            feat("indicator", x=(0.50, 0.55), y=(2.0, None), z=(0.99, 1.09), obj="indicator"),
            feat("reverse", x=(0.80, None), y=(2.0, None), z=(0.99, 1.03)),
            feat("plate", x=(-0.26, 0.26), y=(2.05, None), z=(0.81, 0.92), mirror=False),
            feat("plate_eu", x=(0.22, 0.26), y=(2.05, None), z=(0.81, 0.92), mirror=False),
            feat("plastic_black", y=(1.95, None), z=(None, 0.62), mirror=False, box=((-1, 1.8, 0.0), (1, 2.4, 0.7))),
            feat("alu", x=(-0.45, 0.45), y=(2.05, None), z=(0.40, 0.48), mirror=False, box=((-0.5, 1.9, 0.3), (0.5, 2.4, 0.6))),
            # bonnet and tailgate shut lines, door gaps
            feat("seam", y=(-2.03, -2.025), z=(0.85, None), segs=("top", "rail", "glass", "cap"), mirror=False,
                 box=((-1, -2.2, 0.8), (1, -1.9, 1.1))),
            feat("seam", x=(0.72, 0.725), y=(-2.03, -0.88), segs=("top", "rail", "glass")),
            feat("seam", x=(0.64, 0.645), y=(1.98, None), z=(0.62, 1.14)),
            *seams(SUV_DOORS, 0.44, 1.07),
            feat("underbody", segs=("bottom",), mirror=False),
        ],
        "flares": True,             # black wheel arch flares
        "doors": SUV_DOORS,
        "mirror": {"y": -0.70, "z": 1.12, "paint": False},
        "handles": [(-0.20, -0.06), (0.77, 0.91)],
        "antenna": 0.75,
        "spoiler": 1.94,
        "rails": True,
        "cab": {
            "floor": 0.40, "cowl": (-0.87, 1.115), "firewall": -1.03, "seat_x": 0.38, "seat_y": 0.05, "cushion": 0.66,
            "rear_y": 0.92, "rear_end": 2.05, "header": -0.20, "eye": (0.10, 1.37), "figure": 0.72, "eye_pitch": 0.08,
            "steering": ((-0.435, 1.02), (0.0, 0.86, 0.51)),
            "shelf": (1.35, 2.02, 1.13),
        },
    },
}
# the hatchback as a Police nationale patrol car (livery of 2021 on, after photos of its 5008, Scenic and Duster)
CARS["police_hatchback"] = {
    **CARS["compact_hatchback"],
    "label": "police hatchback",
    "paint": "paint_silver",
    "police": {
        # bands over the wheel arches: gap over the arch, width at its outer end, flat top (z), end of the arch part
        # (degrees from the outer horizontal) and the pointed tip reaching this far towards the middle; lowest z at
        # the front and at the rear (the black lower bumper)
        "arch_gap": 0.03, "band": 0.15, "band_top": 0.80, "band_end": 125.0, "tip": 0.30, "band_bottom": (0.26, 0.44),
        "band_clear": [((-1.66, 0.60), (-1.48, 0.80))],    # the front band stays under this (the headlight)
        "side_text": (0.12, 0.665, 0.12),       # middle y of the lettering and mark, bottom z of POLICE, its height
        "bonnet_text": (-1.45, 0.11),           # y of the bottom of POLICE, its height
        "tail_text": (0.87, 0.06),              # z of the bottom of POLICE, its height
        "tail_arrows": (0.31, 0.62, 0.745, 0.04),   # inner and outer |x|, bottom z, height
        "tail_squares": (0.545, 0.03, 0.055),   # bottom z, size, spacing
        "dots": (-0.78, 1.30, 0.032, 0.022, 0.045),  # y range, depth under the beltline, size, spacing
        "bar": (0.03, 0.56, 0.22),              # light bar: middle y, half width, depth
        "grille": (0.17, 0.61),                 # grille flashers: |x|, z
    },
}


def args() -> dict:
    out = {"out_dir": str(ROOT / "godot" / "assets" / "cars"), "preview": "", "car": ""}
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        k, _, v = a.partition("=")
        out[k.lstrip("-")] = v
    return out


def srgb(h: str) -> tuple:
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def mat(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, metal, rough, emit = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = srgb(col)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = srgb(col)
        p.inputs["Emission Strength"].default_value = emit
    if name.startswith("paint"):
        p.inputs["Coat Weight"].default_value = 1.0
        p.inputs["Coat Roughness"].default_value = 0.04
    if name in ALPHA:
        p.inputs["Alpha"].default_value = ALPHA[name]
        m.surface_render_method = "BLENDED"
        m.use_backface_culling = False
    if name in DOUBLE:
        m.use_backface_culling = False
    m.diffuse_color = srgb(col)
    return m


# ---------------------------------------------------------------- small parts (world space, joined per object at the end)

_parts: dict = {}                   # object name -> [part objects]


def put(group: str, bm: bmesh.types.BMesh, m, bevel: float = 0.0, seg: int = 2) -> bpy.types.Object:
    """Adds the bmesh as a part of `group`, material `m` (a name, or a list of names indexed by the faces' material
    index), its sharp edges bevelled by `bevel`."""
    if bevel > 0.0:
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(30)]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=seg, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(group)
    bm.to_mesh(me)
    bm.free()
    for n in ([m] if isinstance(m, str) else m):
        me.materials.append(mat(n))
    o = bpy.data.objects.new(group, me)
    bpy.context.scene.collection.objects.link(o)
    _parts.setdefault(group, []).append(o)
    return o


def box(group, lo, hi, m, bevel=0.01, seg=2) -> None:
    """Box between corners lo and hi."""
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=hi - lo, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(lo + hi) / 2, verts=bm.verts)
    put(group, bm, m, min(bevel, min(hi - lo) * 0.45), seg)


def mirrored_box(group, lo, hi, m, bevel=0.01, seg=2) -> None:
    """The box on the left (+X, as given) and its mirror image on the right."""
    box(group, lo, hi, m, bevel, seg)
    box(group, (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2]), m, bevel, seg)


def oriented_box(group, centre, size, rot: Matrix, m, bevel=0.01, seg=2) -> None:
    """Box of `size` turned by `rot` (3x3) about its centre."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centre) @ rot.to_4x4(), verts=bm.verts)
    put(group, bm, m, min(bevel, min(size) * 0.45), seg)


def cyl(group, centre, axis, r, depth, m, seg=24, r2=None, bevel=0.0) -> None:
    """Cylinder (cone with end radius r2) centred on `centre` along `axis`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    a = Vector(axis).normalized()
    rot = a.to_track_quat("Z", "Y" if abs(a.y) < 0.9 else "X").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centre) @ rot, verts=bm.verts)
    put(group, bm, m, bevel)


def sphere(group, centre, r, m, scale=(1, 1, 1), seg=20) -> None:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    put(group, bm, m)


def tube(group, pts, r, m, sides=10, closed=False) -> None:
    """Round tube along a polyline (parallel-transport frames; closed ends, or a closed loop)."""
    bm = bmesh.new()
    P = [Vector(p) for p in pts]
    n = len(P)
    rings = []
    normal = None
    for i, p in enumerate(P):
        if closed:
            d = (P[(i + 1) % n] - P[i - 1]).normalized()
        else:
            d = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        normal = d.orthogonal().normalized() if normal is None else (normal - d * normal.dot(d)).normalized()
        side = d.cross(normal)
        rings.append([bm.verts.new(p + (normal * math.cos(a) + side * math.sin(a)) * r)
                      for a in (2 * math.pi * k / sides for k in range(sides))])
    pairs = list(zip(rings[:-1], rings[1:]))
    if closed:
        # the transported frame comes back turned: join the last ring to the first one at its closest vertex
        last, first = rings[-1], rings[0]
        shift = min(range(sides), key=lambda k: (last[0].co - first[k].co).length)
        pairs.append((last, first[shift:] + first[:shift]))
    for a, b in pairs:
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    put(group, bm, m)


def prism(group, profile, x0, x1, m, bevel=0.0, seg=2) -> None:
    """Side-view outline [(y, z)] extruded across from x0 to x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in profile]
    b = [bm.verts.new((x1, y, z)) for y, z in profile]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    put(group, bm, m, bevel, seg)


def mirrored_prism(group, profile, x0, x1, m, bevel=0.0, seg=2) -> None:
    prism(group, profile, x0, x1, m, bevel, seg)
    prism(group, profile, -x1, -x0, m, bevel, seg)


def join(target, objs: list) -> None:
    bpy.context.view_layer.update()
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()


def finish(group: str, origin=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    """Joins the parts of `group` into one object named after it, with its origin at `origin` and weighted normals
    (flat faces stay flat, the bevels shade softly; applied on export)."""
    objs = _parts.pop(group)
    target = objs[0]
    if len(objs) > 1:
        join(target, objs)
    target.name = group
    target.data.name = group
    target.data.transform(Matrix.Translation(-Vector(origin)))
    target.location = origin
    wn = target.modifiers.new("weighted", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    return target


def apply_modifiers(o: bpy.types.Object) -> None:
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    o.modifiers.clear()
    old = o.data
    o.data = me
    bpy.data.meshes.remove(old)


def carve(target: bpy.types.Object, cutters: list) -> None:
    """Cuts the cutter objects out of `target` (exact boolean; the cut faces take the cutter's material) and deletes
    them."""
    for c in cutters:
        mod = target.modifiers.new("cut", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        mod.object = c
    apply_modifiers(target)
    for c in cutters:
        bpy.data.objects.remove(c)


# ---------------------------------------------------------------- the lofted body shell

def pchip(pts):
    """Monotone cubic through the (x, y) keys (no overshoot between them); constant beyond the ends."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0.0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = max(k for k in range(n - 1) if xs[k] <= x)
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1]
                + (t3 - t2) * h[i] * m[i + 1])
    return f


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def catmull_rom(pts, counts):
    """Centripetal Catmull-Rom through the 2D points, counts[i] samples from pts[i] to pts[i+1]; the ends are
    continued mirrored across x = 0 (the section is symmetric). Returns the samples and each interval's segment index."""
    P = [Vector(p) for p in pts]
    ext = [Vector((-P[1].x, P[1].y))] + P + [Vector((-P[-2].x, P[-2].y))]
    out, seg = [P[0].copy()], []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]

        def tj(ti, a, b):
            return ti + max((b - a).length, 1e-6) ** 0.5
        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        for k in range(1, counts[i] + 1):
            t = t1 + (t2 - t1) * k / counts[i]
            a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
            a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
            a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
            b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
            b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
            out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
            seg.append(i)
    return out, seg


SECTION_SEGS = ["bottom", "bottom", "rocker", "side", "side", "shoulder", "beltline", "glass", "rail", "top", "top"]
SECTION_COUNTS = [3, 3, 2, 4, 4, 2, 1, 6, 2, 5, 4]
CAP = [(0.985, 0.010), (0.95, 0.022), (0.89, 0.031), (0.78, 0.038), (0.62, 0.043), (0.42, 0.046), (0.2, 0.047)]


class Shell:
    """The car's profiles: cross-sections along it and where its surface is."""

    def __init__(self, c: dict):
        self.c = c
        self.f = {k: pchip(v) for k, v in c["profile"].items()}
        self.yf = -c["length"] / 2
        self.yr = c["length"] / 2

    def params(self, y):
        f = self.f
        zbot, zbelt, w = f["z_bot"](y), f["z_belt"](y), f["w"](y)
        ztop = max(f["z_top"](y), zbelt + 0.03)
        wbelt = w - self.c["tumble"]
        wtop = min(f["w_top"](y), wbelt - 0.045)
        return zbot, zbelt, w, ztop, wbelt, wtop

    def section(self, y):
        """Left half of the cross-section at y, from the bottom centre up to the top centre: [(x, z)] and each
        interval's segment name."""
        zbot, zbelt, w, ztop, wbelt, wtop = self.params(y)
        g = ztop - zbelt
        d = min(0.07, 0.45 * g)
        zsh = zbelt - self.c["shoulder"]
        zr = zbot + 0.07
        pts = [(0.0, zbot), (w * 0.5, zbot), (w - 0.10, zbot + 0.004), (w - 0.03, zr), (w - 0.004, (zr + zsh) / 2),
               (w, zsh), (wbelt + 0.004, zbelt - 0.018), (wbelt, zbelt), (wtop + 0.035, ztop - d),
               (wtop, ztop - d * 0.45), (wtop * 0.5, ztop - d * 0.12), (0.0, ztop)]
        samples, seg = catmull_rom(pts, SECTION_COUNTS)
        return [(p.x, p.y) for p in samples], [SECTION_SEGS[i] for i in seg]

    def bend(self, y0, z):
        """y shift bending the ends back into a rounded nose and tail (y0: station before the shift)."""
        ramp, k, zl = self.c["nose"]
        wf = smoothstep(self.yf + ramp, self.yf, y0)
        zb, zt = self.f["z_bot"](self.yf), self.f["z_top"](self.yf)
        dy = wf * k * (min(max(z, zb), zt) - zl) ** 2
        ramp, k, zl = self.c["tail"]
        wr = smoothstep(self.yr - ramp, self.yr, y0)
        zb, zt = self.f["z_bot"](self.yr), self.f["z_top"](self.yr)
        return dy - wr * k * (min(max(z, zb), zt) - zl) ** 2

    def side_x(self, y, z):
        """x of the left outer surface at (y, z), going up the side (ignores the bend of the ends)."""
        pts, _ = self.section(y)
        for (x0, z0), (x1, z1) in zip(pts[2:], pts[3:]):
            if min(z0, z1) <= z <= max(z0, z1) and z1 != z0:
                return x0 + (x1 - x0) * (z - z0) / (z1 - z0)
        return pts[-1][0]

    def stations(self):
        ys = []
        y = self.yf
        while y < self.yr - 1e-6:
            ys.append(y)
            near = min(y - self.yf, self.yr - y)
            y += 0.012 if near < 0.06 else 0.022 if near < 0.16 else 0.045
        ys.append(self.yr)
        return ys


def build_shell(sh: Shell, names: list) -> bmesh.types.BMesh:
    """The closed shell: rings of the cross-section along the stations, the ends closed by shrinking rings. Faces
    carry their segment (int layer "seg") and side (+1 left, -1 right, 0 middle) and the default paint."""
    bm = bmesh.new()
    seg_l = bm.faces.layers.int.new("seg")
    side_l = bm.faces.layers.int.new("side")
    rings = []
    labels = None
    for y in sh.stations():
        pts, lab = sh.section(y)
        ring2d = list(reversed(pts)) + [(-x, z) for x, z in pts[1:-1]]
        if labels is None:
            n_half = len(lab)
            labels = [(SEG[lab[n_half - 1 - j]], 1) for j in range(n_half)] + [(SEG[lab[i]], -1) for i in range(n_half)]
        rings.append([(x, y, z, y) for x, z in ring2d])
    n = len(rings[0])

    def cap(ring, end_sign):
        y0 = ring[0][3]
        zb, zt = sh.f["z_bot"](y0), sh.f["z_top"](y0)
        zc = (zb + zt) / 2
        out = []
        for s, dy in CAP:
            out.append([(x * s, y0 + end_sign * dy, zc + (z - zc) * s, y0) for x, _, z, _ in ring])
        return out

    front = list(reversed(cap(rings[0], -1)))
    rear = cap(rings[-1], 1)
    allrings = front + rings + rear
    verts = [[bm.verts.new((x, y + sh.bend(y0, z), z)) for x, y, z, y0 in r] for r in allrings]
    paint = names.index(sh.c["paint"])
    nf = len(front)
    for i in range(len(verts) - 1):
        a, b = verts[i], verts[i + 1]
        in_cap = i < nf or i >= nf + len(rings) - 1
        for j in range(n):
            k = (j + 1) % n
            f = bm.faces.new((a[j], a[k], b[k], b[j]))
            f[seg_l] = SEG["cap"] if in_cap else labels[j][0]
            f[side_l] = labels[j][1]
            f.material_index = paint
    for ring, end_sign in ((verts[0], -1), (verts[-1], 1)):
        y0 = allrings[0][0][3] if end_sign < 0 else allrings[-1][0][3]
        zb, zt = sh.f["z_bot"](y0), sh.f["z_top"](y0)
        zc = (zb + zt) / 2
        tip_y = y0 + end_sign * 0.048
        c = bm.verts.new((0.0, tip_y + sh.bend(y0, zc), zc))
        for j in range(n):
            f = bm.faces.new((ring[j], ring[(j + 1) % n], c))
            f[seg_l] = SEG["cap"]
            f.material_index = paint
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    return bm


def mirrored(fe: dict) -> dict:
    planes = [((-p[0], p[1], p[2]), (-n[0], n[1], n[2])) for p, n in fe["planes"]]
    lo, hi = fe["box"]
    obj = fe["obj"] + "_right" if fe["obj"] else None
    return {**fe, "planes": planes, "box": ((-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])), "obj": obj}


def expanded_features(features: list) -> list:
    out = []
    for fe in features:
        if fe["mirror"]:
            out.append({**fe, "obj": fe["obj"] + "_left" if fe["obj"] else None})
            out.append(mirrored(fe))
        else:
            out.append(fe)
    return out


def in_box(c, box, margin=0.0) -> bool:
    lo, hi = box
    return all(lo[k] - margin <= c[k] <= hi[k] + margin for k in range(3))


def paint_features(bm, features: list, names: list) -> dict:
    """Cuts each feature's planes into the shell (near its box, on its segments) and gives the faces inside it its
    material (later features over earlier ones). Returns {face: object name} for the features with their own object."""
    seg_l = bm.faces.layers.int["seg"]
    for fe in features:
        for co, no in fe["planes"]:
            faces = [f for f in bm.faces if in_box(f.calc_center_median(), fe["box"], 0.05)
                     and (fe["segs"] is None or f[seg_l] in fe["segs"])]
            if not faces:
                continue
            edges = list({e for f in faces for e in f.edges})
            verts = list({v for f in faces for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, dist=1e-5, plane_co=co, plane_no=Vector(no).normalized())
    owner = {}
    for fe in features:
        mi = names.index(fe["mat"])
        for f in bm.faces:
            c = f.calc_center_median()
            if not in_box(c, fe["box"]) or (fe["segs"] is not None and f[seg_l] not in fe["segs"]):
                continue
            if all((c - Vector(co)).dot(Vector(no)) <= 1e-6 for co, no in fe["planes"]):
                f.material_index = mi
                if fe["obj"]:
                    owner[f] = fe["obj"]
                else:
                    owner.pop(f, None)
    return owner


def extract(bm, faces, delete=True) -> bmesh.types.BMesh:
    """A new bmesh with copies of `faces` (material indices kept), deleted from `bm` unless `delete` is false."""
    nb = bmesh.new()
    vmap = {}
    for f in faces:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = nb.verts.new(v.co)
            vs.append(vmap[v])
        nf = nb.faces.new(vs)
        nf.material_index = f.material_index
        nf.smooth = True
    if delete:
        bmesh.ops.delete(bm, geom=list(faces), context="FACES")
    return nb


def push(bm, d: float) -> None:
    """Moves the vertices along their normals by d."""
    bm.normal_update()
    moves = [(v, v.normal.copy()) for v in bm.verts]
    for v, n in moves:
        v.co += n * d


def body_shell(c: dict, sh: Shell) -> tuple:
    """The body shell (into "body"), its lamps, glazing and grilles. Returns the outer surface with its features
    painted, before anything is set back or thickened, for draping the livery on: (BVH tree, material name per face)."""
    names = [n for n in MATERIALS]
    bm = build_shell(sh, names)
    owner = paint_features(bm, expanded_features(c["features"]), names)
    bm.faces.index_update()
    surface = (BVHTree.FromBMesh(bm), [names[f.material_index] for f in bm.faces])
    idx = {n: i for i, n in enumerate(names)}
    glass = [f for f in bm.faces if names[f.material_index].startswith("glass")]
    heads = [f for f in bm.faces if f.material_index == idx["headlight"]]
    own = {}
    for f, o in owner.items():
        own.setdefault(o, []).append(f)
    # glazing: set 6 mm into the openings
    gb = extract(bm, glass)
    push(gb, -0.006)
    put("body", gb, names)
    # headlights: the lamp 2 cm deep behind a clear lens at the surface
    lb = extract(bm, heads)
    lens = lb.copy()
    for f in lens.faces:
        f.material_index = idx["lens"]
    push(lens, -0.002)
    put("body", lens, names)
    push(lb, -0.02)
    put("body", lb, names)
    for o, faces in own.items():
        put(o, extract(bm, faces), names)
    # grilles and intakes set 1.5 cm back (their edges come out as black seals with the thickness below)
    gr = extract(bm, [f for f in bm.faces if f.material_index == idx["grille"]])
    push(gr, -0.015)
    put("body", gr, names)
    # the rest thickened inwards: cabin side trim, black seals round the openings
    n = len(names)
    shell = put("_shell", bm, names)
    for _ in range(n):
        shell.data.materials.append(mat("trim"))
    for _ in range(n):
        shell.data.materials.append(mat("seal"))
    sol = shell.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.022
    sol.offset = -1.0
    sol.use_even_offset = True
    sol.use_rim = True
    sol.material_offset = n
    sol.material_offset_rim = 2 * n
    apply_modifiers(shell)
    # wheel arches cut out
    wh = c["wheel"]
    for y in wh["axles"]:
        for s in (1, -1):
            x = s * (sh.f["w"](y) - 0.04)
            cyl("_cut", (x, y, wh["r"] + 0.01), (1, 0, 0), wh["arch"], 0.62, "liner", 48)
    carve(shell, _parts.pop("_cut"))
    # headliner above the beltline inside
    me = shell.data
    me.materials.append(mat("headliner"))
    hl = len(me.materials) - 1
    for p in me.polygons:
        if n <= p.material_index < 2 * n:
            cz = p.center
            if cz.z > sh.f["z_belt"](cz.y) + 0.03 and p.normal.z < 0.3:
                p.material_index = hl
    _parts["_shell"].remove(shell)
    if not _parts["_shell"]:
        _parts.pop("_shell")
    _parts.setdefault("body", []).append(shell)
    return surface


def liners(c: dict, sh: Shell) -> None:
    """Wheel wells: a half drum behind each arch, closed on the inside."""
    wh = c["wheel"]
    r = wh["arch"] - 0.004
    zc = wh["r"] + 0.01
    for y in wh["axles"]:
        for s in (1, -1):
            x_out = s * (sh.f["w"](y) - 0.02)
            x_in = s * (wh["x"] - wh["w"] / 2 - 0.07)
            bm = bmesh.new()
            n = 24
            angs = [math.radians(-25 + 230 * k / n) for k in range(n + 1)]
            outer = [bm.verts.new((x_out, y + r * math.cos(a), zc + r * math.sin(a))) for a in angs]
            inner = [bm.verts.new((x_in, y + r * math.cos(a), zc + r * math.sin(a))) for a in angs]
            centre = bm.verts.new((x_in, y, zc - 0.05))
            for k in range(n):
                bm.faces.new((outer[k], outer[k + 1], inner[k + 1], inner[k]))
                bm.faces.new((inner[k], inner[k + 1], centre))
            put("body", bm, "liner")


def flares(c: dict, sh: Shell) -> None:
    """Black arch flares hugging the body round each wheel arch (the SUV's cladding)."""
    wh = c["wheel"]
    zc = wh["r"] + 0.01
    r0, r1 = wh["arch"], wh["arch"] + 0.065
    for y in wh["axles"]:
        for s in (1, -1):
            bm = bmesh.new()
            n = 30
            rows = []
            for k in range(n + 1):
                a = math.radians(-8 + 196 * k / n)
                row = []
                for r, off in ((r0, 0.0), (r0 + 0.01, 0.014), (r1 - 0.012, 0.016), (r1, 0.0)):
                    yy, zz = y + r * math.cos(a), zc + r * math.sin(a)
                    x = sh.side_x(yy, max(zz, sh.f["z_bot"](yy) + 0.01)) + off - 0.002
                    row.append(bm.verts.new((s * x, yy, zz)))
                rows.append(row)
            for k in range(n):
                for j in range(3):
                    bm.faces.new((rows[k][j], rows[k][j + 1], rows[k + 1][j + 1], rows[k + 1][j]))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            put("body", bm, "plastic_black")


# ---------------------------------------------------------------- outside fittings

def surface_point(sh: Shell, y, z, out=0.0, s=1):
    return Vector((s * (sh.side_x(y, z) + out), y, z))


def mirrors(c: dict, sh: Shell) -> None:
    """Door mirrors on the mirror sails: a black foot, an arm, a rounded housing with the glass on its back and the
    indicator repeater on its front."""
    mc = c["mirror"]
    y, z = mc["y"], mc["z"]
    cover = c["paint"] if mc["paint"] else "trim_black"

    def side_box(group, s, lo, hi, m, bevel=0.01, seg=2):
        if s < 0:
            lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
        box(group, lo, hi, m, bevel, seg)

    for s, side in ((1, "left"), (-1, "right")):
        bx = sh.side_x(y, z + 0.02)
        hx = bx + 0.15
        side_box("mirrors", s, (bx - 0.03, y - 0.05, z - 0.005), (bx + 0.05, y + 0.07, z + 0.045), "trim_black", 0.015)
        side_box("mirrors", s, (bx + 0.03, y - 0.02, z + 0.01), (hx - 0.05, y + 0.04, z + 0.04), "trim_black", 0.01)
        side_box("mirrors", s, (hx - 0.10, y - 0.045, z + 0.0), (hx + 0.10, y + 0.06, z + 0.125), cover, 0.042, 4)
        side_box("mirrors", s, (hx - 0.088, y + 0.058, z + 0.012), (hx + 0.088, y + 0.064, z + 0.113), "trim_black", 0.004)
        side_box("mirrors", s, (hx - 0.083, y + 0.063, z + 0.016), (hx + 0.083, y + 0.066, z + 0.109), "mirror_glass", 0.0)
        side_box(f"indicator_{side}", s, (hx + 0.03, y - 0.044, z + 0.012), (hx + 0.094, y - 0.02, z + 0.026), "indicator", 0.004)


def handles(c: dict, sh: Shell) -> None:
    """Door handles: a body-coloured grip over a black recess, under the beltline."""
    for y0, y1 in c["handles"]:
        z = sh.f["z_belt"]((y0 + y1) / 2) - 0.075
        for s in (1, -1):
            x0 = sh.side_x(y0, z)
            x1 = sh.side_x(y1, z)
            xo = max(x0, x1)
            lo, hi = (xo - 0.01, y0 - 0.01, z - 0.022), (xo + 0.004, y1 + 0.01, z + 0.022)
            if s < 0:
                lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
            box("body", lo, hi, "seam", 0.006)
            lo, hi = (xo - 0.005, y0, z - 0.014), (xo + 0.016, y1, z + 0.014)
            if s < 0:
                lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
            box("body", lo, hi, c["paint"], 0.01, 3)


def wipers(c: dict, sh: Shell) -> None:
    cy, cz = c["cab"]["cowl"]
    y1 = cy + 0.12
    z1 = sh.f["z_top"](y1) + 0.012
    for x0, x1 in ((0.55, -0.02), (-0.05, -0.62)):
        tube("body", [(x0, cy + 0.06, cz + 0.035), (x1, y1, z1)], 0.008, "trim_black", 6)
        cyl("body", (x0, cy + 0.04, cz + 0.02), (0, 0, 1), 0.016, 0.03, "trim_black", 12)


def roof_bits(c: dict, sh: Shell) -> None:
    """Shark-fin antenna at the back of the roof, a roof spoiler over the rear glass with the third brake lamp, the
    SUV's roof rails, rear wiper."""
    y = sh.yr - c["antenna"]
    z = sh.f["z_top"](y)
    prism("body", [(y - 0.10, z - 0.01), (y + 0.10, z - 0.01), (y + 0.09, z + 0.03), (y + 0.02, z + 0.065)], -0.025, 0.025,
          "trim_black", 0.012, 3)
    # spoiler over the rear glass
    ys = c["spoiler"]
    zs = sh.f["z_top"](ys)
    wt = sh.f["w_top"](ys)
    prism("body", [(ys - 0.06, zs - 0.005), (ys + 0.07, zs - 0.03), (ys + 0.08, zs - 0.01), (ys - 0.03, zs + 0.012)],
          -wt + 0.02, wt - 0.02, "trim_black" if c.get("roof") else c["paint"], 0.012, 3)
    box("brake_lights", (-0.12, ys + 0.06, zs - 0.03), (0.12, ys + 0.082, zs - 0.017), "brake", 0.004)
    if c.get("rails"):
        for s in (1, -1):
            pts = []
            for k in range(13):
                yy = -0.05 + (1.80 + 0.05) * k / 12
                pts.append((s * 0.56, yy, sh.f["z_top"](yy) + 0.035))
            tube("body", pts, 0.015, "alu", 8)
            for yy in (0.0, 1.75):
                box("body", (s * 0.56 - 0.02, yy - 0.04, sh.f["z_top"](yy) - 0.01),
                    (s * 0.56 + 0.02, yy + 0.04, sh.f["z_top"](yy) + 0.035), "trim_black", 0.01)
    # rear wiper on the rear glass
    if c.get("rear_wiper"):
        tube("body", [(0.0, 1.74, sh.f["z_top"](1.74) + 0.012), (0.35, 1.56, sh.f["z_top"](1.56) + 0.012)], 0.007,
             "trim_black", 6)


# ---------------------------------------------------------------- police livery and lights

FONTS = {   # the first one found, else Blender's built-in font
    "bold": ["/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
             "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "regular": ["/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
}
LIVERY = ["livery_blue", "livery_red", "livery_white", "livery_navy", "reflector"]   # decal material indices
DECAL_CELL = 0.02           # m: outlines are cut into cells this size, so that draped they follow the body's curves
DECAL_LIFT = 0.0015         # m off the paint


def flat(polys: list, m: str) -> bmesh.types.BMesh:
    """Flat mesh (z = 0) of the outlines [[(a, b), ...], ...] (concave ones too: bmesh's triangulate puts triangles
    across a concave arc), triangulated, livery material m."""
    bm = bmesh.new()
    for poly in polys:
        vs = [bm.verts.new((a, b, 0.0)) for a, b in poly]
        for tri in tessellate_polygon([[v.co for v in vs]]):
            f = bm.faces.new([vs[i] for i in tri])
            f.material_index = LIVERY.index(m)
    return bm


def add_flat(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, xf=None) -> None:
    """Copies the flat mesh `src` into `dst` (material indices kept), transformed by the 4x4 xf; frees src."""
    if xf is not None:
        bmesh.ops.transform(src, verts=src.verts[:], matrix=xf)
    me = bpy.data.meshes.new("flat")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)


def font(weight: str):
    for path in FONTS[weight]:
        if Path(path).exists():
            return bpy.data.fonts.load(path, check_existing=True)
    return None


def lettering(text: str, weight: str, height: float, m: str, width: float = 0.0) -> tuple:
    """`text` in capitals as a flat mesh reading along +x, the capitals `height` tall from y = 0 up, centred on x = 0,
    letter-spaced out to `width` if given; livery material m. Returns it and its width."""
    def make(spacing):
        cu = bpy.data.curves.new("lettering", "FONT")
        cu.body = text
        f = font(weight)
        if f:
            cu.font = f
        cu.space_character = spacing
        cu.resolution_u = 4
        ob = bpy.data.objects.new("lettering", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bm = bmesh.new()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        k = height / (max(ys) - min(ys))
        bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Scale(k, 4)
                            @ Matrix.Translation((-(min(xs) + max(xs)) / 2, -min(ys), 0.0)))
        return bm, (max(xs) - min(xs)) * k
    bm, w = make(1.0)
    if width:
        bm.free()
        bm2, w2 = make(2.0)
        bm2.free()
        bm, w = make(1.0 + (width - w) / (w2 - w))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.material_index = LIVERY.index(m)
    return bm, w


def badge(h: float) -> bmesh.types.BMesh:
    """POLICE (bold, h tall, from y = 0 up) over a letter-spaced NATIONALE as wide, and after them the tricolour mark:
    blue, white and red strokes leaning forwards, longer and longer down. Flat, reading along +x, centred on x = 0."""
    bm = bmesh.new()
    police, w = lettering("POLICE", "bold", h, "livery_navy")
    add_flat(bm, police)
    add_flat(bm, lettering("NATIONALE", "regular", 0.36 * h, "livery_navy", w)[0], Matrix.Translation((0.0, -0.62 * h, 0.0)))
    x0 = w / 2 + 0.3 * h
    tw = 0.22 * h                               # stroke width at the top
    for k, (m, bottom) in enumerate((("livery_blue", -0.05), ("livery_white", -0.38), ("livery_red", -0.72))):
        x = x0 + k * 0.27 * h
        top = 1.06 * h
        lean = 0.3 * (top - bottom * h)
        add_flat(bm, flat([[(x, top), (x + tw, top), (x + 0.75 * tw - 0.55 * lean, (top + bottom * h) / 2),
                            (x + 0.3 * tw - lean, bottom * h), (x - 0.5 * lean, (top + bottom * h) / 2)]], m))
    right = x0 + 2 * 0.27 * h + tw
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=(-(right - w / 2) / 2, 0.0, 0.0))
    return bm


def swoosh(ya: float, za: float, m: int, arch: float, p: dict) -> list:
    """Side-view outline [(y, z)] of the livery band over the wheel arch centred at (ya, za): along the arch from low
    on its outer side up over it, its top flat (p["band_top"]), ending in a point towards the middle of the car (m: +1
    the rear, -1 the front)."""
    ri = arch + p["arch_gap"]
    ro = ri + p["band"]
    zt = p["band_top"]

    def at(r, deg):
        a = math.radians(deg)
        return (ya - m * r * math.cos(a), za + r * math.sin(a))
    a1 = math.degrees(math.asin((zt - za) / ro))
    a0, a2 = -15.0, p["band_end"]
    inner = [at(ri, a0 + (a2 - a0) * k / 28) for k in range(29)]
    tip = (inner[-1][0] + m * p["tip"], zt)
    outer = [at(ro, a1 + (a0 - a1) * k / 20) for k in range(21)]
    return inner + [tip] + outer


def clip(bm: bmesh.types.BMesh, p1, p2, keep) -> None:
    """Keeps the part of the flat mesh on the side of the line through p1, p2 where `keep` is."""
    n = Vector((p2[1] - p1[1], p1[0] - p2[0], 0.0))
    if n.x * (keep[0] - p1[0]) + n.y * (keep[1] - p1[1]) > 0:
        n = -n
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=(p1[0], p1[1], 0.0),
                           plane_no=n, clear_outer=True)


def cut_gaps(bm: bmesh.types.BMesh, lines, w=0.005) -> None:
    """Cuts the strips a < x < a + w (the door gaps, x being the car's y) out of the flat mesh."""
    for a in lines:
        for x in (a, a + w):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=(x, 0.0, 0.0),
                                   plane_no=(1.0, 0.0, 0.0))
        dead = [f for f in bm.faces if a < f.calc_center_median().x < a + w]
        bmesh.ops.delete(bm, geom=dead, context="FACES")


def cells(bm: bmesh.types.BMesh, cell=DECAL_CELL) -> None:
    """Cuts the flat mesh into cells (and triangulates it), so that draped on the body it follows its curves."""
    for axis in (0, 1):
        vals = [v.co[axis] for v in bm.verts]
        k = math.floor(min(vals) / cell) + 1
        while k * cell < max(vals):
            co, no = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
            co[axis], no[axis] = k * cell, 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=co, plane_no=no)
            k += 1
    bmesh.ops.triangulate(bm, faces=bm.faces[:])


def drape(bm: bmesh.types.BMesh, surf: tuple, origin, direction, paint: set, what: str) -> None:
    """Moves each vertex (a, b) of the flat mesh onto the car: where the ray from origin(a, b) along `direction` first
    meets the outer shell, lifted DECAL_LIFT off it. Faces with a corner off the shell or on another material than
    `paint` (lamps, glass, plates) are dropped; the rest face the ray's origin."""
    bvh, mats = surf
    d = Vector(direction).normalized()
    off = set()
    for v in bm.verts:
        hit, nrm, i, _ = bvh.ray_cast(Vector(origin(v.co.x, v.co.y)), d)
        if hit is None or mats[i] not in paint:
            off.add(v)
            continue
        v.co = hit - nrm * DECAL_LIFT if nrm.dot(d) > 0 else hit + nrm * DECAL_LIFT
    dead = [f for f in bm.faces if any(v in off for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.dot(d) > 0])
    if dead:
        print(f"livery {what}: {len(dead)} cells off the paint dropped")


def police_livery(c: dict, sh: Shell, surf: tuple) -> None:
    """The Police nationale livery on the grey paint (into "body"). Each side: a blue band over the wheel arch on the
    viewer's left and a red one on the right (the front on the left side, the rear on the right), POLICE NATIONALE and
    the tricolour mark over the B-pillar, a dotted reflective line under the windows. The bonnet: POLICE NATIONALE read
    from the front. The tailgate: POLICE NATIONALE, a blue and a red arrow under the lamps, blue, white and red
    squares across the bumper. All cut at the door gaps."""
    p = c["police"]
    wh = c["wheel"]
    za = wh["r"] + 0.01                         # arch centre (that of the arch cutters)
    paint = {c["paint"], "seam"}
    yc, zt, h = p["side_text"]
    y0, y1, depth, size, step = p["dots"]
    for s, side in ((1, "left"), (-1, "right")):
        bm = bmesh.new()
        for ya, m, bottom in ((wh["axles"][0], 1, p["band_bottom"][0]), (wh["axles"][1], -1, p["band_bottom"][1])):
            band = flat([swoosh(ya, za, m, wh["arch"], p)], "livery_blue" if (m == 1) == (s == 1) else "livery_red")
            clip(band, (-9.0, bottom), (9.0, bottom), (0.0, 9.0))
            for line in p["band_clear"] if m == 1 else ():
                clip(band, line[0], line[1], (ya, za))
            add_flat(bm, band)
        # reading towards the viewer's right: the rear on the left side, the front on the right
        add_flat(bm, badge(h), Matrix.Translation((yc, zt, 0.0)) @ Matrix.Scale(s, 4, (1.0, 0.0, 0.0)))
        dots = []
        for k in range(int((y1 - y0) / step) + 1):
            y = y0 + k * step
            if all(abs(y - d - 0.0025) > size / 2 + 0.006 for d in c["doors"]):
                z = sh.f["z_belt"](y) - depth
                dots.append([(y - size / 2, z - size / 2), (y + size / 2, z - size / 2), (y + size / 2, z + size / 2),
                             (y - size / 2, z + size / 2)])
        add_flat(bm, flat(dots, "reflector"))
        cut_gaps(bm, c["doors"])
        cells(bm)
        drape(bm, surf, lambda a, b, s=s: (s * 3.0, a, b), (-s, 0.0, 0.0), paint, f"{side} side")
        put("body", bm, LIVERY)
    # bonnet, read from the front: the reading direction is the car's left (+X), up is towards the windscreen
    yb, hb = p["bonnet_text"]
    bm = badge(hb)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=(0.0, yb, 0.0))
    cells(bm)
    drape(bm, surf, lambda a, b: (a, b, 3.0), (0.0, 0.0, -1.0), paint, "bonnet")
    put("body", bm, LIVERY)
    # tailgate, read from behind: reading towards the car's right (-X); (a, b) = (x, z)
    zt, ht = p["tail_text"]
    bm = badge(ht)
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Translation((0.0, zt, 0.0)) @ Matrix.Scale(-1, 4, (1.0, 0.0, 0.0)))
    xi, xo, zb, ha = p["tail_arrows"]
    for s, m in ((1, "livery_blue"), (-1, "livery_red")):           # the viewer's left is the car's left
        add_flat(bm, flat([[(s * xo, zb), (s * (xi + 0.8 * ha), zb), (s * xi, zb + ha), (s * xo, zb + ha)]], m))
    zq, size, step = p["tail_squares"]
    for k in range(12):
        x = (5.5 - k) * step
        add_flat(bm, flat([[(x - size / 2, zq), (x + size / 2, zq), (x + size / 2, zq + size), (x - size / 2, zq + size)]],
                          ("livery_blue", "livery_white", "livery_red")[k // 4]))
    cells(bm)
    drape(bm, surf, lambda a, b: (a, 4.0, b), (0.0, -1.0, 0.0), paint, "tailgate")
    put("body", bm, LIVERY)


def light_bar(c: dict, sh: Shell, surf: tuple) -> None:
    """Blue LED light bar across the front of the roof on two feet ("lightbar"; its lenses beacon_left and
    beacon_right either side of a black middle) and two blue flashers in the grille (beacon_grille_left / _right)."""
    p = c["police"]
    yb, hw, depth = p["bar"]
    y0, y1 = yb - depth / 2, yb + depth / 2
    zb = max(sh.f["z_top"](y) for y in (y0, yb, y1)) + 0.032        # underside of the bar
    zr = min(sh.f["z_top"](y) for y in (y0, y1)) - 0.03             # feet sunk into the roof
    for s in (1, -1):
        x = s * (hw - 0.14)
        box("lightbar", (x - 0.025, y0 + 0.03, zr), (x + 0.025, y1 - 0.03, zb + 0.005), "plastic_black", 0.008)
    box("lightbar", (-hw, y0, zb), (hw, y1, zb + 0.022), "plastic_black", 0.01)
    box("lightbar", (-0.055, y0 + 0.008, zb + 0.015), (0.055, y1 - 0.008, zb + 0.068), "trim_black", 0.015)
    for s, side in ((1, "left"), (-1, "right")):
        lo, hi = (0.057, y0 + 0.006, zb + 0.016), (hw - 0.006, y1 - 0.006, zb + 0.072)
        if s < 0:
            lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
        box(f"beacon_{side}", lo, hi, "beacon", 0.022, 3)
    gx, gz = p["grille"]
    for s, side in ((1, "left"), (-1, "right")):
        y = surf[0].ray_cast(Vector((s * gx, -4.0, gz)), Vector((0.0, 1.0, 0.0)))[0].y     # the grille's face
        box(f"beacon_grille_{side}", (s * gx - 0.045, y + 0.004, gz - 0.012), (s * gx + 0.045, y + 0.014, gz + 0.012),
            "beacon", 0.004)


# ---------------------------------------------------------------- cabin

def interior(c: dict, sh: Shell) -> dict:
    """Floor, firewall, dashboard (cluster, touchscreen, vents, climate panel), centre console and gear selector, door
    cards, seats, rear bench, parcel shelf, rear-view mirror, sun visors and pedals. Returns the cab points (Blender)."""
    k = c["cab"]
    F = k["floor"]
    cy, cz = k["cowl"]
    fw = k["firewall"]
    dx, sy, cu = k["seat_x"], k["seat_y"], k["cushion"]
    wh = c["wheel"]

    def inner(y, z, gap=0.03):
        return sh.side_x(y, z) - 0.022 - gap

    # floor (kept clear of the rear wheel wells), firewall, footwell
    x_well = wh["x"] - wh["w"] / 2 - 0.08
    y_well = (wh["axles"][1] - wh["arch"] - 0.02, wh["axles"][1] + wh["arch"] + 0.02)
    xin = min(inner(y, F + 0.05) for y in (fw, 0.0, k["rear_end"] - 0.05))
    box("body", (-x_well, fw, F - 0.02), (x_well, k["rear_end"], F), "carpet", 0.0)
    mirrored_box("body", (x_well, fw, F - 0.02), (xin, y_well[0], F), "carpet", 0.0)
    box("body", (-xin, fw - 0.02, F), (xin, fw, cz - 0.05), "dash", 0.0)
    # dashboard: side profile across the cabin
    ins = min(inner(y, z) for y, z in ((cy + 0.05, cz - 0.02), (cy + 0.3, cz - 0.05), (cy + 0.3, cz - 0.3)))
    dash = [(fw, F + 0.12), (fw, cz - 0.05), (cy + 0.03, cz - 0.012), (cy + 0.20, cz + 0.012), (cy + 0.33, cz - 0.0),
            (cy + 0.40, cz - 0.05), (cy + 0.43, cz - 0.15), (cy + 0.40, cz - 0.32), (cy + 0.26, cz - 0.46),
            (cy + 0.08, F + 0.12)]
    prism("body", dash, -ins, ins, "dash", 0.025, 3)
    # brushed trim strip and vents across the face of the dash
    box("body", (-ins + 0.02, cy + 0.425, cz - 0.17), (ins - 0.02, cy + 0.435, cz - 0.155), "alu", 0.003)
    for x0 in (-ins + 0.06, -0.20, 0.08, ins - 0.18):
        box("body", (x0, cy + 0.41, cz - 0.13), (x0 + 0.12, cy + 0.432, cz - 0.07), "trim_black", 0.008)
        for j in range(4):
            zz = cz - 0.122 + j * 0.016
            box("body", (x0 + 0.01, cy + 0.425, zz), (x0 + 0.11, cy + 0.436, zz + 0.004), "alu", 0.0)
    # digital cluster in front of the dash face, seen between the steering wheel's hub and the top of its rim: two ring
    # dials and a bar between them, under a visor
    yc = cy + 0.43
    box("body", (dx - 0.17, yc - 0.05, cz - 0.065), (dx + 0.17, yc - 0.006, cz + 0.05), "dash", 0.012)
    box("body", (dx - 0.18, yc - 0.13, cz + 0.045), (dx + 0.18, yc + 0.03, cz + 0.075), "dash", 0.012)
    box("body", (dx - 0.16, yc - 0.007, cz - 0.05), (dx + 0.16, yc + 0.001, cz + 0.042), "screen", 0.003)
    for gx in (dx - 0.09, dx + 0.09):
        ring = [(gx + 0.034 * math.cos(math.radians(a)), yc + 0.004, cz - 0.004 + 0.034 * math.sin(math.radians(a)))
                for a in range(-220, 41, 10)]
        tube("body", ring, 0.004, "gauge", 6)
        box("body", (gx - 0.003, yc + 0.002, cz - 0.007), (gx + 0.003, yc + 0.005, cz + 0.025), "needle", 0.0)
    box("body", (dx - 0.04, yc + 0.001, cz - 0.03), (dx + 0.04, yc + 0.004, cz + 0.02), "screen_ui", 0.0)
    # centre touchscreen standing on the dash, climate panel under the vents
    rot = Matrix.Rotation(math.radians(-15), 3, "X")
    oriented_box("body", Vector((0.0, cy + 0.37, cz + 0.05)), Vector((0.26, 0.016, 0.16)), rot, "trim_black", 0.006)
    oriented_box("body", Vector((0.0, cy + 0.38, cz + 0.05)), Vector((0.235, 0.004, 0.14)), rot, "screen", 0.0)
    for j, (x0, w, h) in enumerate(((-0.10, 0.06, 0.05), (-0.03, 0.12, 0.02), (0.05, 0.05, 0.05))):
        oriented_box("body", Vector((x0 + w / 2, cy + 0.384, cz + 0.06 - j * 0.01)), Vector((w, 0.002, h)), rot,
                     "screen_ui", 0.0)
    box("body", (-0.15, cy + 0.39, cz - 0.30), (0.15, cy + 0.42, cz - 0.20), "trim_black", 0.01)
    for x in (-0.10, 0.0, 0.10):
        cyl("body", (x, cy + 0.425, cz - 0.25), (0, 1, 0), 0.022, 0.02, "alu", 16, bevel=0.003)
    # centre console with the gear selector and an armrest
    con = [(cy + 0.30, F), (cy + 0.30, cz - 0.42), (cy + 0.55, F + 0.30), (sy + 0.05, F + 0.26), (sy + 0.25, F + 0.30),
           (sy + 0.25, F)]
    prism("body", con, -0.105, 0.105, "trim", 0.02)
    box("body", (-0.085, sy - 0.18, F + 0.27), (0.085, sy + 0.25, F + 0.33), "leather", 0.03, 3)
    gy = cy + 0.62
    gz = F + 0.30
    cyl("body", (0.0, gy, gz + 0.03), (0, 0.15, 1), 0.03, 0.08, "trim_black", 16)
    sphere("body", (0.0, gy + 0.015, gz + 0.09), 0.035, "leather", (0.9, 1.1, 1.0), 16)
    box("body", (-0.07, gy - 0.10, gz - 0.005), (0.07, gy + 0.10, gz + 0.006), "trim_black", 0.008)
    for x in (-0.04, 0.04):
        cyl("body", (x, gy + 0.18, gz - 0.01), (0, 0, 1), 0.034, 0.02, "trim_black", 16)
    # door cards: armrest, pull, window switches, a handle
    for s in (1, -1):
        for y0, y1, front in ((cy + 0.35, sy + 0.15, True), (sy + 0.36, k["rear_y"] + 0.25, False)):
            z = cu + 0.13
            xi = min(inner(y0 + 0.05, z, 0.0), inner(y1 - 0.05, z, 0.0))
            lo, hi = (xi - 0.07, y0, z - 0.03), (xi + 0.005, y1, z + 0.01)
            if s < 0:
                lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
            box("body", lo, hi, "trim_light", 0.015)
            hz = cu + 0.33
            xh = inner(y0 + 0.08, hz, 0.0)
            lo, hi = (xh - 0.02, y0 + 0.03, hz - 0.015), (xh + 0.004, y0 + 0.13, hz + 0.015)
            if s < 0:
                lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
            box("body", lo, hi, "alu", 0.006)
            if front:
                lo, hi = (xi - 0.065, y1 - 0.20, z + 0.008), (xi - 0.02, y1 - 0.06, z + 0.016)
                if s < 0:
                    lo, hi = (-hi[0], lo[1], lo[2]), (-lo[0], hi[1], hi[2])
                box("body", lo, hi, "trim_black", 0.004)
    # front seats: cushion with side bolsters, reclined backrest, headrest on two posts
    for s in (1, -1):
        x = s * dx
        box("body", (x - 0.15, sy - 0.12, F), (x + 0.15, sy + 0.15, cu - 0.12), "trim_black", 0.01)    # runners
        box("body", (x - 0.23, sy - 0.25, cu - 0.11), (x + 0.23, sy + 0.24, cu - 0.01), "seat", 0.045, 3)
        box("body", (x - 0.15, sy - 0.24, cu - 0.03), (x + 0.15, sy + 0.20, cu), "seat_accent", 0.03, 3)
        for b in (-1, 1):
            box("body", (x + b * 0.20 - 0.045, sy - 0.22, cu - 0.08), (x + b * 0.20 + 0.045, sy + 0.24, cu + 0.04),
                "seat", 0.035, 3)
        back = [(sy + 0.20, cu - 0.06), (sy + 0.33, cu - 0.06), (sy + 0.43, cu + 0.56), (sy + 0.31, cu + 0.56)]
        prism("body", back, x - 0.24, x + 0.24, "seat", 0.05, 3)
        prism("body", [(sy + 0.19, cu + 0.02), (sy + 0.22, cu + 0.02), (sy + 0.31, cu + 0.52), (sy + 0.28, cu + 0.52)],
              x - 0.15, x + 0.15, "seat_accent", 0.012)
        for b in (-1, 1):
            prism("body", [(sy + 0.17, cu), (sy + 0.29, cu), (sy + 0.38, cu + 0.50), (sy + 0.26, cu + 0.50)],
                  x + b * 0.21 - 0.045, x + b * 0.21 + 0.045, "seat", 0.035, 3)
        for px in (x - 0.06, x + 0.06):
            tube("body", [(px, sy + 0.37, cu + 0.54), (px, sy + 0.385, cu + 0.62)], 0.006, "alu", 8)
        prism("body", [(sy + 0.34, cu + 0.60), (sy + 0.43, cu + 0.60), (sy + 0.45, cu + 0.77), (sy + 0.36, cu + 0.77)],
              x - 0.13, x + 0.13, "seat", 0.035, 3)
    # rear bench, its backrest and three headrests
    ry = k["rear_y"]
    rw = min(x_well - 0.01, inner(ry, cu, 0.02))
    box("body", (-rw, ry - 0.22, F), (rw, ry + 0.22, cu - 0.08), "trim_black", 0.0)
    box("body", (-rw, ry - 0.24, cu - 0.10), (rw, ry + 0.26, cu - 0.01), "seat", 0.05, 3)
    prism("body", [(ry + 0.22, cu - 0.06), (ry + 0.35, cu - 0.06), (ry + 0.45, cu + 0.52), (ry + 0.33, cu + 0.52)],
          -rw, rw, "seat", 0.05, 3)
    for x in (-rw + 0.22, 0.0, rw - 0.22):
        prism("body", [(ry + 0.36, cu + 0.55), (ry + 0.44, cu + 0.55), (ry + 0.46, cu + 0.68), (ry + 0.38, cu + 0.68)],
              x - 0.11, x + 0.11, "seat", 0.03, 3)
    # parcel shelf / luggage cover over the boot
    y0, y1, zs = k["shelf"]
    xs = min(inner(y0, zs, 0.0), inner(y1, zs, 0.0))
    box("body", (-xs, y0, zs - 0.012), (xs, y1, zs), "trim", 0.0)
    # rear-view mirror on the windscreen under the roof, sun visors folded up against the headliner
    ys = k["header"]                             # top of the windscreen
    zt = sh.f["z_top"](ys) - 0.035
    tube("body", [(0.0, ys - 0.02, zt), (0.0, ys + 0.02, zt - 0.06)], 0.008, "trim_black", 8)
    box("body", (-0.12, ys - 0.01, zt - 0.12), (0.12, ys + 0.04, zt - 0.05), "trim_black", 0.015)
    box("body", (-0.11, ys + 0.040, zt - 0.115), (0.11, ys + 0.042, zt - 0.055), "mirror_glass", 0.0)
    for s in (1, -1):
        x0, x1 = sorted((s * 0.06, s * 0.62))
        zv = sh.f["z_top"](ys + 0.10) - 0.045
        box("body", (x0, ys + 0.02, zv - 0.02), (x1, ys + 0.20, zv), "headliner", 0.01)
    # pedals in the driver's footwell
    for j, x in enumerate((dx + 0.12, dx - 0.02, dx - 0.15)):
        w = 0.05 if j != 1 else 0.09
        box("body", (x - w / 2, fw + 0.12, F + 0.08), (x + w / 2, fw + 0.14, F + 0.16), "alu", 0.005)
    return {"seat": Vector((dx, sy, cu)), "eye": Vector((dx, k["eye"][0], k["eye"][1]))}


def steering_wheel(c: dict) -> bpy.types.Object:
    """Leather rim, three spokes (3, 6 and 9 o'clock seen from the seat) with brushed inserts, airbag hub, around the
    local Z axis, tilted towards the driver; local +Y is 12 o'clock."""
    R = 0.183
    tube("steering", [(R * math.cos(2 * math.pi * k / 48), R * math.sin(2 * math.pi * k / 48), 0.0) for k in range(48)],
         0.018, "leather", 12, closed=True)
    cyl("steering", (0, -0.008, 0.012), (0, 0, 1), 0.068, 0.045, "leather", 28, bevel=0.012)
    cyl("steering", (0, -0.008, 0.036), (0, 0, 1), 0.052, 0.006, "trim_black", 28)
    for a in (0.0, 180.0):
        rot = Matrix.Rotation(math.radians(a), 3, "Z")
        oriented_box("steering", rot @ Vector((0.12, -0.012, 0.005)), Vector((0.13, 0.045, 0.016)), rot, "leather", 0.007)
        oriented_box("steering", rot @ Vector((0.11, -0.012, 0.0135)), Vector((0.07, 0.03, 0.003)), rot, "alu", 0.002)
    for x in (-0.03, 0.03):
        box("steering", (x - 0.012, -R + 0.01, -0.004), (x + 0.012, -0.05, 0.014), "leather", 0.006)
    rim = finish("steering")
    k = c["cab"]
    (yc, zc), axis = k["steering"]
    centre = Vector((k["seat_x"], yc, zc))
    rim.matrix_world = Matrix.Translation(centre) @ Vector(axis).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    return rim


def steering_column(c: dict) -> None:
    k = c["cab"]
    (yc, zc), axis = k["steering"]
    a = Vector(axis).normalized()
    centre = Vector((k["seat_x"], yc, zc))
    cyl("body", centre - a * 0.12, a, 0.04, 0.16, "dash", 16, r2=0.034)
    # stalks either side of the column
    for s in (1, -1):
        p = centre - a * 0.07
        tube("body", [p, p + Vector((s * 0.13, 0.0, 0.01))], 0.006, "trim_black", 6)


# ---------------------------------------------------------------- wheels

def wheel(c: dict, name: str, x: float, y: float) -> bpy.types.Object:
    """Lathed tyre round X (sidewall bulge, tread grooves), alloy rim (barrel, lip, spokes), hub cap, brake disc and
    calliper. Outer face towards +X on the left."""
    wh = c["wheel"]
    left = x > 0
    sgn = 1.0 if left else -1.0
    R, W, RR = wh["r"], wh["w"], wh["rim_r"]
    o = W / 2
    prof = [  # (radius, axial towards the outer face, material of the segment starting here)
        (RR - 0.015, -o + 0.015, "tyre_wall"), (RR + 0.01, -o - 0.004, "tyre_wall"), (R - 0.045, -o - 0.006, "tyre_wall"),
        (R - 0.012, -o + 0.006, "tyre"), (R, -o + 0.025, "tyre"), (R, -0.055, "tyre"), (R - 0.009, -0.052, "tyre"),
        (R - 0.009, -0.040, "tyre"), (R, -0.037, "tyre"), (R, -0.006, "tyre"), (R - 0.009, -0.003, "tyre"),
        (R - 0.009, 0.009, "tyre"), (R, 0.012, "tyre"), (R, 0.037, "tyre"), (R - 0.009, 0.040, "tyre"),
        (R - 0.009, 0.052, "tyre"), (R, 0.055, "tyre"), (R, o - 0.025, "tyre"), (R - 0.012, o - 0.006, "tyre_wall"),
        (R - 0.045, o + 0.006, "tyre_wall"), (RR + 0.01, o + 0.004, "rim"),
        # rim lip, then the dish down to the barrel and back across
        (RR + 0.004, o - 0.006, "rim"), (RR - 0.006, o - 0.012, "rim"), (RR - 0.02, o - 0.03, wh["rim"]),
        (RR - 0.02, -o + 0.02, "rim"), (RR - 0.015, -o + 0.015, "rim")]
    mats = ["tyre", "tyre_wall", "rim", "rim_dark", "hub", "disc", "caliper"]
    seg = 48
    bm = bmesh.new()
    rings = []
    for r, a, _ in prof:
        rings.append([bm.verts.new((sgn * a, r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg)))
                      for k in range(seg)])
    n = len(prof)
    for j in range(n):
        ra, rb = rings[j], rings[(j + 1) % n]
        mi = mats.index(prof[j][2])
        for k in range(seg):
            k1 = (k + 1) % seg
            f = bm.faces.new((ra[k], ra[k1], rb[k1], rb[k]))
            f.material_index = mi
            f.smooth = True
    # spokes: from the hub out to the dish, set back towards the rim (concave face)
    face_a = o - 0.03
    spokes = wh["spokes"]
    mi = mats.index(wh["rim"])
    for k in range(spokes):
        t = 2 * math.pi * k / spokes
        w0, w1 = (0.034, 0.03) if spokes <= 5 else (0.02, 0.016)
        r0, r1 = 0.055, RR - 0.018
        pts = []
        for r, w, a in ((r0, w0, face_a - 0.002), (r1, w1, face_a + 0.012)):
            for side in (-1, 1):
                for depth in (0.0, -0.028):
                    v = Vector((sgn * (a + depth), r, side * w / 2))
                    pts.append(Matrix.Rotation(t, 3, "X") @ v)
        vs = [bm.verts.new(p) for p in pts]
        # indices: [r][side][depth]
        q = lambda ri, si, di: vs[ri * 4 + si * 2 + di]
        for fs in ((q(0, 0, 0), q(1, 0, 0), q(1, 1, 0), q(0, 1, 0)), (q(0, 0, 1), q(0, 1, 1), q(1, 1, 1), q(1, 0, 1)),
                   (q(0, 0, 0), q(0, 0, 1), q(1, 0, 1), q(1, 0, 0)), (q(0, 1, 0), q(1, 1, 0), q(1, 1, 1), q(0, 1, 1)),
                   (q(1, 0, 0), q(1, 0, 1), q(1, 1, 1), q(1, 1, 0))):
            f = bm.faces.new(fs)
            f.material_index = mi
    # hub: a disc with five nuts and a centre cap
    hub = bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=0.07, radius2=0.062, depth=0.03)["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((sgn * (face_a - 0.012), 0, 0)) @ Matrix.Rotation(math.radians(90 * sgn), 4, "Y"),
                        verts=hub)
    for f in {f for v in hub for f in v.link_faces}:
        f.material_index = mi
    cap = bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.03, radius2=0.026, depth=0.012)["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((sgn * (face_a + 0.006), 0, 0)) @ Matrix.Rotation(math.radians(90 * sgn), 4, "Y"),
                        verts=cap)
    for f in {f for v in cap for f in v.link_faces}:
        f.material_index = mats.index("hub")
    for k in range(5):
        t = 2 * math.pi * (k + 0.5) / 5
        nut = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.009, radius2=0.009, depth=0.012)["verts"]
        bmesh.ops.transform(bm, matrix=Matrix.Translation((sgn * (face_a + 0.004), 0.045 * math.cos(t), 0.045 * math.sin(t)))
                            @ Matrix.Rotation(math.radians(90 * sgn), 4, "Y"), verts=nut)
        for f in {f for v in nut for f in v.link_faces}:
            f.material_index = mats.index("disc")
    # brake disc behind the spokes
    disc = bmesh.ops.create_cone(bm, cap_ends=True, segments=40, radius1=RR - 0.045, radius2=RR - 0.045, depth=0.024)["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((sgn * (face_a - 0.06), 0, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y"),
                        verts=disc)
    for f in {f for v in disc for f in v.link_faces}:
        f.material_index = mats.index("disc")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for nme in mats:
        me.materials.append(mat(nme))
    wo = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(wo)
    wo.location = (x, y, R)
    return wo


def calipers(c: dict) -> None:
    """Brake callipers, part of the body (they do not spin; the front ones do not steer either)."""
    wh = c["wheel"]
    RR = wh["rim_r"]
    for y in wh["axles"]:
        for s in (1, -1):
            x = s * (wh["x"] + wh["w"] / 2 - 0.03 - 0.06)
            a = math.radians(35)
            cy, cz = y + (RR - 0.06) * math.cos(a), wh["r"] + (RR - 0.06) * math.sin(a)
            oriented_box("body", Vector((x, cy, cz)), Vector((0.045, 0.06, 0.12)), Matrix.Rotation(-a, 3, "X"),
                         "caliper", 0.012)


# ---------------------------------------------------------------- main

def gd(v) -> list:
    """Blender point -> glTF/Godot (x, z, -y), rounded."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def gpu() -> str:
    """"GPU" when Cycles has an OptiX or CUDA device (the blender.org builds; distribution packages often have
    neither), else "CPU"."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        found = [d for d in prefs.devices if d.type == kind]
        if found:
            for d in prefs.devices:
                d.use = d.type == kind
            print("preview on", kind, found[0].name)
            return "GPU"
    return "CPU"


def preview(prefix: str, c: dict, cab: dict) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.device = gpu()
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    nt = world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.35
    scene.world = world
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun_data.angle = math.radians(2)
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    scene.collection.objects.link(sun)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    me = bpy.data.meshes.new("ground")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat("underbody"))
    ground = bpy.data.objects.new("ground", me)
    scene.collection.objects.link(ground)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    eye = cab["eye"]
    L = c["length"]
    views = [("front", (4.6, -5.6, 1.5), (0.0, -0.3, 0.65), 40),
             ("rear", (-4.4, 5.8, 1.9), (0.0, 0.4, 0.7), 40),
             ("side", (7.5, 0.0, 1.0), (0.0, 0.0, 0.75), 40),
             ("cab", tuple(eye), (eye.x - 0.25, eye.y - 4.0, eye.z - 0.55), 14),
             ("inside", (-1.6, 0.35, eye.z + 0.05), (0.2, -0.1, eye.z - 0.35), 18)]
    if c.get("police"):
        views += [("side_right", (-7.5, 0.0, 1.0), (0.0, 0.0, 0.75), 40),
                  ("bonnet", (0.0, -4.6, 2.6), (0.0, -1.3, 0.8), 40)]
    for suffix, pos, look, lens in views:
        cam.location = pos
        cam_data.type = "PERSP"
        cam_data.lens = lens
        cam_data.clip_start = 0.02
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{suffix}.png"
        bpy.ops.render.render(write_still=True)
        print("preview", scene.render.filepath)
    # straight front and rear views, to check the lamps and grilles
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.2
    for suffix, y in (("front_ortho", -L / 2 - 3.0), ("rear_ortho", L / 2 + 3.0)):
        cam.location = (0.0, y, 0.75)
        cam.rotation_euler = (Vector((0.0, 0.0, 0.75)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{suffix}.png"
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(ground)


def build(key: str, out_dir: Path, prev: str) -> None:
    c = CARS[key]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    _parts.clear()
    sh = Shell(c)
    surf = body_shell(c, sh)
    liners(c, sh)
    if c.get("flares"):
        flares(c, sh)
    handles(c, sh)
    wipers(c, sh)
    roof_bits(c, sh)
    calipers(c)
    cab = interior(c, sh)
    steering_column(c)
    mirrors(c, sh)
    groups = ["body", "mirrors", "indicator_left", "indicator_right", "brake_lights"]
    if c.get("police"):
        police_livery(c, sh, surf)
        light_bar(c, sh, surf)
        groups += ["lightbar", "beacon_left", "beacon_right", "beacon_grille_left", "beacon_grille_right"]
    objs = [finish(g) for g in groups]
    objs.append(steering_wheel(c))
    wheels = []
    wh = c["wheel"]
    for stem, y in zip(("front", "rear"), wh["axles"]):
        for side, x in (("left", wh["x"]), ("right", -wh["x"])):
            wheels.append(wheel(c, f"wheel_{stem}_{side}", x, y))
    objs += wheels
    out = out_dir / f"{key}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True)
    k = c["cab"]
    seat, eye = cab["seat"], cab["eye"]
    layout = {
        "wheels": [w.name for w in wheels],
        "indicators": {"left": ["indicator_left"], "right": ["indicator_right"]},
        "brake_lights": ["brake_lights"],
        "cab": {
            "driver_seat": gd(seat),
            "driver_eye": gd(eye),
            "passenger_seat": gd((-seat.x, seat.y, seat.z)),
            "passenger_eye": gd((-eye.x, eye.y, eye.z)),
            "steering_wheel": "steering",
            "figure": k["figure"],
            "eye_pitch": k["eye_pitch"],
        },
    }
    if c.get("police"):
        layout["beacons"] = {"left": ["beacon_left", "beacon_grille_left"], "right": ["beacon_right", "beacon_grille_right"]}
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.evaluated_get(deps).data.polygons)
    print(f"{key}: {out} ({tris} triangles)")
    if prev:
        Path(prev).mkdir(parents=True, exist_ok=True)
        preview(str(Path(prev) / key), c, cab)


def main() -> None:
    a = args()
    for key in ([a["car"]] if a["car"] else list(CARS)):
        build(key, Path(a["out_dir"]), a["preview"])


if __name__ == "__main__":    # blender/vehicles/import_car.py imports the palette
    main()
