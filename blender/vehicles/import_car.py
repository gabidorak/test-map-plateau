"""Turns a ready-made car model (FBX, or OBJ: see load_obj; e.g. from a 3D model store; the files stay in ref/, not published) into a
drivable car with the same parts and cab file as the cars of build_car.py, so scripts/car.gd drives it and shows
its cab view: the Renault Zoe (2013) of ref/RENAULT_ZOE_2013.

blender -b --factory-startup -P blender/vehicles/import_car.py -- [--car=renault_zoe] [--out_dir=godot/assets/cars]
                                                                  [--preview=data/review/cars]

The FBX has the body (shell, glass, lamps, a simple cabin) as one mesh and the four wheels as another, in 3ds Max
millimetres. Both are moved into the frame of build_car.py (metres, z up, front = -Y, left = +X, origin on the
ground under the middle of the body), then split into the parts car.gd needs by their loose pieces ("islands"),
each picked by where it sits (boxes in that frame, per car in CARS):
- "body", from which car.gd takes the collision box, so the outside mirrors and the roof aerial are objects of
  their own ("mirrors", "aerial");
- "steering" (the steering wheel; its origin at the hub, local Z up the column to the driver, +Y at 12 o'clock);
- the lamps car.gd switches: indicator_left / indicator_right (the front amber bulbs and their reflectors, the mirror
  repeaters, the bottom band of the tail lamp lens) and brake_lights (the lens's middle band, the third brake lamp's
  lens); the headlight projectors take the material "headlight" and the lens's top band "taillight", which car.gd
  lights at night. car.gd swaps their materials for opaque ones, so the tail lamp's insides (behind layers of blue
  glass, which hid them when lit) and the third brake lamp's LEDs are dropped;
- wheel_front_left ... wheel_rear_right (origin at the wheel centre); the brake callipers go to the body.
The model's V-Ray materials do not come through FBX, so every piece takes one of build_car.py's materials (a few
more are added below) from its FBX material name, some pieces a different one by island (lamp reflectors, lenses,
seats, headliner). The very dense pieces (tyres, brake discs, lamp reflectors, LEDs) are decimated, so the car is
about the size of the build_car.py ones, and the paint panels are shaded anew (the model's normals show facets in
Godot). The number plate texture is a watermarked stock picture: the plates are plain.
Other cars differ by options of their CARS entry: "body" and "wheels" may list several FBX objects (joined), "classify"
names their own island rules (the BMW M4's: classify_m4; its lamps also give "reverse_lights", which car.gd lights
while backing up), "wheel_ratio" their wheels' decimation, and their cab "seat" may be given. Loaded objects may be
reworked before they are joined (prepare: dropped, wire meshes turned into sheets, decimated, cut apart, lined on the
inside, a cabin fitted out with build_car.py's interior; the Audi RS6's, an OBJ without a cabin).
--preview renders the same views as build_car.py."""
import contextlib
import io
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_car as bc     # noqa: E402  (palette, mat(), preview)

ROOT = bc.ROOT

bc.MATERIALS.update({
    "paint_celeste": ("#8FB4CF", 0.55, 0.28, 0.0),     # Renault "Bleu Céleste"
    "lens_red": ("#B0141E", 0.0, 0.04, 0.0),
    "lens_blue": ("#4F7FC4", 0.0, 0.05, 0.0),
    "reflector_red": ("#6E0A10", 0.0, 0.2, 0.0),
    "chrome_blue": ("#A8BCD2", 1.0, 0.15, 0.0),
    "badge_light": ("#62E8FA", 0.0, 0.2, 0.0),
})
bc.ALPHA.update({"lens_red": 0.5, "lens_blue": 0.35})
bc.MATERIALS.update({                                  # BMW M4
    "paint_austin": ("#D9B51E", 0.55, 0.28, 0.0),      # "Austin Yellow", as the model came
    "paint_carbon": ("#17181B", 0.3, 0.3, 0.0),        # the carbon roof (clear-coated, hence "paint")
    "leather_light": ("#B3B0A9", 0.0, 0.6, 0.0),
    "headliner_dark": ("#3A3A3C", 0.0, 0.95, 0.0),
    "caliper_gold": ("#B08D3C", 0.6, 0.35, 0.0),       # carbon-ceramic brakes
})
bc.MATERIALS.update({                                  # Audi R8
    "paint_ara": ("#1D4F9E", 0.6, 0.26, 0.0),          # "Ara Blue Crystal", a launch colour of the 2016 R8
    "caliper_red": ("#A3161F", 0.3, 0.4, 0.0),
    "grille_mesh": ("#0B0C0D", 0.0, 0.8, 0.0),         # honeycomb, matte (decimated, it would glint)
    "lens_smoke": ("#3A1C20", 0.0, 0.04, 0.0),         # the tail lamps' dark lens
})
bc.ALPHA.update({"lens_smoke": 0.45})

# a box: ((x0, y0, z0), (x1, y1, z1)) in the car frame; x boxes are for the left (+X) side and mirrored
CARS = {
    "renault_zoe": {
        "fbx": "ref/RENAULT_ZOE_2013/RENAULT_ZOE_2013_VRay.FBX",
        "body": "RENAULT_ZOE_2013", "wheels": "RENAULT_ZOE_2013_WHEELS",
        # FBX material -> palette material
        "materials": {
            "Carpaint Simple Ruby": "paint_celeste", "black": "plastic_black", "windowglass": "glass_side",
            "clearglass": "lens", "chrome": "chrome", "mattemetal": "alu", "orangeglass": "indicator",
            "mirror": "mirror_glass", "bluechrome": "chrome_blue", "blueglass": "lens_blue",
            "redglass": "reflector_red", "interior": "dash", "numberplate_black": "plastic_black",
            "numberplate_white": "plate", "number": "plate", "lightblue": "badge_light",
            "vray tire": "tyre", "vray rim": "rim_dark", "vray rim_second": "rim", "vray brakedisk": "disc",
        },
        "steering": ((0.12, -0.45, 0.79), (0.55, -0.22, 1.18)),
        "mirror": ((0.70, -0.88, 0.98), (1.05, -0.47, 1.22)),          # island centres
        "aerial": 1.6,                                                    # islands reaching above this
        "head_lamp": ((0.25, -2.0, 0.70), (0.80, -1.35, 0.95)),
        "tail_lamp": ((0.45, 1.40, 0.82), (0.85, 1.85, 1.12)),
        "chmsl": ((-0.20, 1.45, 1.38), (0.20, 1.65, 1.46)),              # third brake lamp, not mirrored
        "seats": ((-0.62, -0.45, 0.40), (0.62, 1.35, 1.40)),
        "cab": {"eye": (0.06, 1.33), "figure": 0.68, "eye_pitch": 0.1},  # driver's eye (y, z) above the seat
    },
    # BMW M4 coupé (F82, 2015) of ref/BMW_M4_2015 ("BMW M4.zip", its LOW FBX: metres, already front = -Y): one object
    # per part (doors, lamps, interior, seats, steering wheel, wheels, brake callipers), so the lists are joined.
    # See classify_m4.
    "bmw_m4": {
        "fbx": "ref/BMW_M4_2015/2015_BMW_M4_FBX/2015_BMW_M4_LOW.fbx",
        "body": ["Body", "DoorLeft", "DoorRight", "Headlights", "Taillights", "Interior", "Seats", "SteeringWheel",
                 "BrakeFrLeft", "BrakeFrRight", "BrakeRearLeft", "BrakeRearRight"],     # the callipers do not spin
        "wheels": ["WheelFrLeft", "WheelFrRight", "WheelRearLeft", "WheelRearRight"],
        "classify": "classify_m4",
        "materials": {
            "CarPaint": "paint_austin", "Plastic": "plastic_black", "Chrome": "chrome", "Aluminum": "alu",
            "MetalDark": "trim_black", "BlackPlain": "seal", "GlassTextured": "glass_side", "GlassWinds": "glass_side",
            "GlassLights": "lens", "GlassIOR": "taillight", "GlassLightsBump": "reflector", "GlassAngelEyes": "drl",
            "GlassRed": "taillight", "GlassOrange": "indicator", "LampIllum": "headlight",
            # badges plain (no maker's marks; Logo*: the M stripes, see classify_m4), LogoDFS the plates too (blank)
            "LogoLtBlue": "seat_accent", "LogoBlue": "seat_accent", "LogoRed": "needle", "LogoDFS": "plate",
            "intPlasticDkPlain": "dash", "intPlasticDkBump": "trim", "intPlasticDkGlance": "trim_black",
            "intFabricGray": "headliner_dark", "intLeatherLt": "leather_light", "intCarpet": "carpet",
            "intCarbon": "trim_black", "intAlumuminum": "alu", "intPlasticSatelites": "grille",
            "intButtonsDFS": "dash", "intTextureDFS": "screen",
            "WheelTireBump": "tyre", "WheelAluminum": "rim", "WheelMetalDark": "rim_dark", "WheelBrakeDisk": "disc",
            "WheelLogo": "hub", "WheelMetalCaliper": "caliper_gold",
        },
        "wheel_ratio": {"rim_dark": 0.25, "tyre": 1.0},
        # boxes in the car frame (the FBX's y - 0.15)
        "steering": ((0.14, -0.58, 0.60), (0.545, -0.40, 1.08)),        # rim, spokes, hub; not the stalks, paddles
        "mirror": ((0.80, -0.76, 0.90), (1.05, -0.48, 1.10)),           # island centres
        "head_lamp": ((0.40, -2.21, 0.50), (0.84, -1.75, 0.74)),
        "tail_lamp": ((0.33, 1.84, 0.70), (0.84, 2.28, 0.98)),
        "tail_bands": (0.804, 0.875),           # the outer lens: indicator below, brake, taillight above
        "cabin_box": ((-0.75, -0.86, 0.30), (0.75, 1.36, 1.30)),
        "cab": {"seat": (0.383, 0.0, 0.39), "eye": (0.12, 1.08), "figure": 0.66, "eye_pitch": 0.1},
    },
    # Audi R8 V10 (2016) of ref/AUDI_R8_2016 ("audi r8.zip", its OBJ: millimetres, Y up, front +Z): one object per
    # part and a single placeholder material, so the "materials" map the objects (by_object). See classify_rules.
    "audi_r8": {
        "obj": "ref/AUDI_R8_2016/Audi-R8-2016-obj.obj", "scale": 0.001, "by_object": True,
        # wheels: the nuts, the discs (the callipers do not spin), the rims, the tyres
        "body": [f"Audi_R8_{n:03d}" for n in range(1, 41) if n not in (3, 4, 5, 6, 11, 12, 13, 14, 29, 30, 31, 32, 34,
                                                                         35, 36, 37)],
        "wheels": [f"Audi_R8_{n:03d}" for n in (3, 4, 5, 6, 11, 12, 13, 14, 29, 30, 31, 32, 34, 35, 36, 37)],
        "classify": "classify_rules",
        "materials": {f"Audi_R8_{n:03d}": m for n, m in (
            (1, "paint_ara"), (2, "plastic_black"), (3, "hub"), (4, "hub"), (5, "hub"), (6, "hub"),     # wheel nuts
            (7, "caliper_red"), (8, "caliper_red"), (9, "caliper_red"), (10, "caliper_red"),
            (11, "disc"), (12, "disc"), (13, "disc"), (14, "disc"),
            (15, "plastic_black"),              # grille surround, front intakes, splitter
            (16, "trim_black"), (17, "lens"),   # head lamp: housing and modules, inner lenses and light blade
            (18, "grille_mesh"),                # honeycomb meshes
            (19, "lens"),                       # head and tail lamp lenses
            (20, "dash"),                       # the cabin: a tub with the seats and the steering wheel
            (21, "chrome"),                     # the rings: dropped
            (22, "mirror_glass"), (23, "plastic_black"), (24, "plate"), (25, "plastic_black"),
            (26, "plastic_black"),              # diffuser, exhausts, tail lamp surrounds
            (27, "trim_black"), (28, "trim_black"),    # tail lamp chambers and light guides
            (29, "rim_dark"), (30, "rim_dark"), (31, "rim_dark"), (32, "rim_dark"),
            (33, "plastic_black"),              # under the mirrors, with the repeater's LEDs
            (34, "tyre"), (35, "tyre"), (36, "tyre"), (37, "tyre"),
            (38, "chrome"),                     # badges: dropped
            (39, "glass_side"), (40, "plastic_black"))},
        "wheel_ratio": {"tyre": 0.1, "rim_dark": 0.3, "disc": 0.15, "hub": 0.4},
        "wheel_drop": 0.02,                     # the discs' bolts and the rings on the centre caps
        "wheel_min_tris": 300,                  # (the wheel nuts are decimated too)
        # (first match wins; see classify_rules)
        "rules": [
            {"src": ["Audi_R8_021", "Audi_R8_038"], "group": "hidden"},                  # the rings, badges
            {"src": "Audi_R8_020", "box": ((0.18, -0.62, 0.62), (0.52, -0.46, 0.96)), "mirror": False,
             "group": "steering", "remat": "leather"},
            {"src": "Audi_R8_020", "box": ((0.2, -0.2, 0.5), (0.5, 0.1, 0.8)), "remat": "seat"},
            {"src": "Audi_R8_020", "box": ((0.25, -0.7, 0.6), (0.45, -0.6, 0.75)), "remat": "trim"},  # column
            {"src": "Audi_R8_033", "size": (0.0, 0.02), "group": "indicator", "remat": "indicator"},
            {"box": ((0.82, -0.66, 0.78), (1.05, -0.45, 0.95)), "group": "mirrors"},
            # head lamp: the slanted bar blinks, the light blade is a daytime light, the four modules light up
            {"src": ["Audi_R8_016", "Audi_R8_017"], "box": ((0.69, -1.80, 0.48), (0.72, -1.70, 0.56)),
             "group": "indicator", "remat": "indicator"},
            {"src": "Audi_R8_017", "size": (0.3, 1.0), "remat": "drl", "ratio": 0.4},
            {"src": ["Audi_R8_016", "Audi_R8_017"], "box": ((0.54, -1.89, 0.49), (0.80, -1.66, 0.535)),
             "size": (0.0, 0.2), "remat": "headlight"},
            {"src": "Audi_R8_019", "box": ((0.0, 1.5, 0.0), (1.0, 2.5, 2.0)), "remat": "lens_smoke", "ratio": 0.35},
            {"src": "Audi_R8_019", "ratio": 0.35},
            # tail lamp: the strip along the bottom blinks, the light guide along the top is the taillight, the
            # three outer chambers brake, the inner one reverses; the side marker reflects
            {"src": ["Audi_R8_027", "Audi_R8_028"], "box": ((0.4, 1.85, 0.68), (0.85, 2.05, 0.70)),
             "size": (0.4, 1.0), "group": "indicator", "remat": "indicator"},
            {"src": ["Audi_R8_027", "Audi_R8_028"], "box": ((0.5, 1.85, 0.72), (0.7, 2.05, 0.76)), "size": (0.4, 0.47),
             "tris": (0, 100), "remat": "taillight"},           # and the frames round the chambers
            {"src": "Audi_R8_028", "box": ((0.40, 1.85, 0.72), (0.80, 2.05, 0.78)), "tris": (0, 6),
             "remat": "taillight"},                             # the chambers' LED strips
            {"src": ["Audi_R8_027", "Audi_R8_028"], "box": ((0.40, 1.85, 0.72), (0.51, 2.05, 0.78)),
             "size": (0.0, 0.17), "group": "reverse_lights", "remat": "reverse"},
            {"src": ["Audi_R8_027", "Audi_R8_028"], "box": ((0.51, 1.85, 0.72), (0.80, 2.05, 0.78)),
             "size": (0.0, 0.17), "group": "brake_lights", "remat": "brake"},
            {"src": ["Audi_R8_027", "Audi_R8_028"], "box": ((0.80, 1.85, 0.70), (0.85, 1.90, 0.75)),
             "remat": "reflector_red"},
            # bodywork: the engine cover's inner pane (the engine bay is empty: else one sees into the cabin), wheel
            # arch liners, the floor, the exhaust tips
            {"src": "Audi_R8_039", "box": ((-0.6, 0.6, 0.9), (0.6, 1.7, 1.2)), "mirror": False, "tris": (0, 100),
             "remat": "underbody"},
            {"src": "Audi_R8_002", "size": (2.0, 9.0), "remat": "underbody"},
            {"src": "Audi_R8_002", "size": (0.7, 0.8), "box": ((0.6, -2.0, 0.0), (1.0, 2.0, 0.45)), "remat": "liner"},
            {"src": "Audi_R8_026", "box": ((0.55, 1.9, 0.2), (0.76, 2.05, 0.36)), "size": (0.0, 0.23),
             "remat": "chrome"},
            # the dense ones
            {"src": "Audi_R8_018", "tris": (10000, 10 ** 9), "ratio": 0.15},             # the front grille
            {"src": "Audi_R8_018", "tris": (800, 10000), "ratio": 0.3},
            {"src": "Audi_R8_040", "tris": (400, 10 ** 9), "ratio": 0.25},
            {"src": [f"Audi_R8_{n:03d}" for n in range(7, 11)], "ratio": 0.2},      # callipers
        ],
        "cab": {"seat": (0.343, -0.15, 0.39), "eye": (0.05, 1.08), "figure": 0.62, "eye_pitch": 0.12,
                # the "virtual cockpit" behind the wheel, in front of the dash face (y -0.69)
                "cluster": {"centre": (0.348, -0.655, 0.83), "size": (0.30, 0.11), "tilt": 12.0}},
    },
}
DETAIL = {"chrome", "lens", "lens_blue", "lens_red", "indicator", "brake", "reflector_red", "headlight", "taillight",
          "mirror_glass", "alu", "chrome_blue"}       # materials of the pieces that may be decimated
WHEEL_RATIO = {"tyre": 0.2, "rim": 0.4, "disc": 0.15, "hub": 0.4}

bc.MATERIALS.update({                                  # Audi RS6
    "paint_glacier": ("#E2E5E8", 0.35, 0.24, 0.0),     # "Glacier White", with black accents (the Star Wars theme)
    "caliper_crimson": ("#B0141C", 0.3, 0.4, 0.0),
})
RS6 = "Audi_RS6_Starwars_Hycade_{:03d}".format         # its OBJ's objects, by number
# Audi RS6 Avant "Starwars Hycade" (the Hycade wide-body kit) of ref/audi_rs6 ("audi RS6.zip", its OBJ: millimetres,
# Y up, front +Z, ~1M quads): one object per part, a placeholder material (by_object), no cabin but a tub and five
# seats, no steering wheel. prepare() replaces the honeycomb grilles (1.45M triangles of tiny rings) by sheets, thins
# the tyres and wheel nuts, cuts the outer tail lamp lens into its two bands, lines the single-skinned panels round
# the cabin on the inside and fits out the cabin (build_car.py's, for the model's tub and seats); classify_rules does
# the rest. The badges and the "Audi RS6" show plates are left out.
CARS["audi_rs6"] = {
    "obj": "ref/audi_rs6/Audi-RS6-Starwars-Hycade-2016-obj.obj", "scale": 0.001, "by_object": True,
    "drop": [RS6(n) for n in (53, 54, 64, 65)],         # rings badges, the tub and the seats
    "sheet": [RS6(66), RS6(67)],                       # the honeycomb of the grille and of the bumper intakes
    # tyres (103k triangles each), wheel nuts, the louvres behind the front wheels, exhaust tips, callipers, mirror
    # bases, rear wing
    "decimate": {**{RS6(n): 0.028 for n in (69, 73)}, **{RS6(n): 0.3 for n in (75, 77)}, RS6(80): 0.25,
                 RS6(30): 0.45, RS6(62): 0.5, RS6(76): 0.5, RS6(24): 0.4, RS6(37): 0.6},
    "split_z": {RS6(55): (0.935, 0.15)},               # tail lamp lenses taller than 0.15 m: upper / lower band
    "lining": {**{RS6(n): "trim" for n in (3, 6, 11, 12, 13, 16, 39, 40)},
               RS6(2): "headliner", RS6(5): "headliner"},
    "body": [RS6(n) for n in range(1, 81) if n not in (53, 54, 64, 65, 61, 74, 68, 71, 69, 73, 70, 72, 75, 77)]
            + ["fitted_cabin", "fitted_steering", "lining"],
    "wheels": [RS6(n) for n in (61, 74, 68, 71, 69, 73, 70, 72, 75, 77)],
    "classify": "classify_rules",
    "materials": {
        **{m: m for m in bc.MATERIALS}, **{"steering " + m: m for m in bc.MATERIALS},    # the fitted-out cabin
        **{RS6(n): m for ns, m in (
            ((6, 7, 8, 11, 12, 13, 14, 16, 31, 32), "paint_glacier"),   # bonnet, wings, doors, tailgate, bumper
            ((2, 3, 4, 5, 22, 34), "paint_black"),      # roof, its frame and spoiler, mirror caps, aerial
            ((1, 9, 10, 15, 17, 18, 19, 20, 21, 25, 26, 27, 28, 29, 33, 35, 37, 39, 40, 42, 43, 44, 45, 46, 47, 79,
              80), "trim_black"),                       # the kit: blades, splitter, skirts, diffuser, wing, louvres
            ((24, 38, 49, 52), "plastic_black"),        # mirror bases, wipers, scuttle
            ((23,), "mirror_glass"), ((36,), "glass_front"), ((41,), "glass_rear"), ((48, 50), "glass_side"),
            ((30,), "chrome"), ((59, 78), "plate"), ((60,), "lens"), ((62, 76), "caliper_crimson"),
            ((63,), "underbody"), ((66, 67), "grille"), ((51, 55, 56, 57, 58), "trim_black"),     # lamps: rules
            ((61, 74, 68, 71), "rim_dark"), ((69, 73), "tyre"), ((70, 72), "disc"), ((75, 77), "chrome"))
           for n in ns},
    },
    "wheel_ratio": {"tyre": 1.0, "rim_dark": 0.5, "disc": 1.0, "hub": 1.0},
    "rules": [
        {"src": ["steering " + m for m in ("leather", "trim_black", "alu")], "group": "steering"},
        {"src": [RS6(22), RS6(23), RS6(24)], "group": "mirrors"},
        {"src": RS6(34), "group": "aerial"},
        # head lamp (islands told apart by their sizes): the LED grids at the outer end go, the strip along the
        # bottom blinks, the "eyebrow" and the outer V are daytime lights, the bowl, the inner plate and the two
        # projectors light up, the rest is the black bezel
        {"src": RS6(51), "tris": (5000, 10 ** 9), "group": "hidden"},
        {"src": RS6(51), "tris": (690, 700), "group": "indicator", "remat": "indicator"},
        {"src": RS6(51), "tris": (230, 300), "remat": "drl"},
        {"src": RS6(51), "tris": (1900, 2000), "remat": "headlight", "ratio": 0.6},
        {"src": RS6(51), "tris": (650, 660), "remat": "headlight"},
        {"src": RS6(51), "tris": (105, 110), "remat": "headlight"},
        # tail lamp: the upper band brakes, the lower one and the light bar across the tailgate are taillights, the
        # strips in the slot between the bands blink (on the wing: on the tailgate the light bar runs in front of
        # them); the lower band on the tailgate also reverses (white over its taillight)
        {"src": RS6(55), "box": ((0.3, 2.0, 0.935), (0.9, 2.5, 1.1)), "group": "brake_lights", "remat": "brake"},
        {"src": RS6(55), "box": ((0.3, 2.3, 0.8), (0.62, 2.45, 0.935)), "group": "reverse_lights",
         "remat": "taillight"},
        {"src": RS6(55), "remat": "taillight"},
        {"src": [RS6(56), RS6(58)], "size": (1.0, 2.0), "remat": "taillight"},
        {"src": [RS6(57), RS6(58)], "box": ((0.3, 2.3, 0.9), (0.62, 2.45, 0.96)), "group": "hidden"},
        {"src": [RS6(56), RS6(57), RS6(58)], "group": "indicator", "remat": "indicator"},
        {"src": RS6(7), "size": (0.0, 0.3), "remat": "trim_black"},            # the bonnet's vents
        {"src": RS6(30), "ratio": 1.0},                                         # exhaust tips
    ],
    # the cabin fitted out by build_car.interior (its "cab" keys, in the OBJ's frame, which is the car's here)
    "cabin": {
        "floor": 0.43, "cowl": (-1.12, 0.99), "firewall": -1.12, "seat_x": 0.40, "seat_y": -0.20, "cushion": 0.60,
        "rear_y": 0.55, "rear_end": 2.15, "header": -0.30, "eye": (-0.16, 1.17),
        "steering": ((-0.62, 0.96), (0.0, 0.9, 0.44)), "shelf": (1.0, 2.1, 1.0),
        "wheel": {"x": 0.91, "w": 0.30, "axles": (-1.52, 1.415), "arch": 0.42},
        "side": [RS6(n) for n in (3, 6, 8, 11, 12, 14, 48, 50, 55)], "roof": [RS6(2), RS6(5)],
    },
    "cab": {"seat": (0.40, -0.20, 0.60), "eye": (-0.16, 1.17), "figure": 0.7, "eye_pitch": 0.12},
}


# ---------------------------------------------------------------- loading

class _Op:
    """Stands in for the FBX import operator: the Ubuntu Blender 5.0 package's operator fails when called from a
    script (it reads self.files, which it no longer has), so its loader is called directly."""
    def report(self, kind, msg):
        print("FBX", kind, msg)


def load_fbx(path: Path) -> None:
    from io_scene_fbx import import_fbx
    with contextlib.redirect_stdout(io.StringIO()):     # a page per V-Ray texture map it cannot follow
        import_fbx.load(_Op(), bpy.context, filepath=str(path))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        o.parent = None
    for m in list(bpy.data.materials):          # (renaming re-sorts the collection)
        m.name = "fbx " + m.name                # out of the way of the palette's ("chrome")


def merged(names) -> bpy.types.Object:
    """The FBX object `names`, or the objects of the list `names` joined into the first one."""
    if isinstance(names, str):
        return bpy.data.objects[names]
    objs = [bpy.data.objects[n] for n in names]
    bc.join(objs[0], objs)
    return objs[0]


def load_obj(path: Path, c: dict) -> None:
    """Loads an OBJ (no units: scaled by c["scale"]; Y up and front +Z, as 3ds Max writes them, unless c["obj_axes"]
    gives the importer's (forward, up)) the way load_fbx does: materials "fbx <name>". With c["by_object"] (exporters
    that write one placeholder material), each object's faces take a material named after the object instead, so the
    car's "materials" map its objects."""
    forward, up = c.get("obj_axes", ("NEGATIVE_Z", "Y"))
    bpy.ops.wm.obj_import(filepath=str(path), forward_axis=forward, up_axis=up, global_scale=c.get("scale", 1.0))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
            if c.get("by_object"):
                o.data.materials.clear()
                o.data.materials.append(bpy.data.materials.new("fbx " + o.name))
                o.data.polygons.foreach_set("material_index", [0] * len(o.data.polygons))
        o.parent = None
    for m in list(bpy.data.materials):          # (renaming re-sorts the collection)
        if not m.name.startswith("fbx "):
            m.name = "fbx " + m.name


def bounds(points) -> tuple:
    lo = Vector((math.inf,) * 3)
    hi = -lo
    for p in points:
        lo = Vector(map(min, lo, p))
        hi = Vector(map(max, hi, p))
    return lo, hi


# ---------------------------------------------------------------- islands

class Island:
    def __init__(self, faces, mats, names=None):
        self.faces = [f.index for f in faces]
        self.lo, self.hi = bounds(v.co for f in faces for v in f.verts)
        self.c = (self.lo + self.hi) * 0.5
        self.size = self.hi - self.lo
        self.tris = sum(len(f.verts) - 2 for f in faces)
        count = {}
        for f in faces:
            count[mats[f.material_index]] = count.get(mats[f.material_index], 0) + len(f.verts) - 2
        self.mat = max(count, key=count.get)        # palette material of most of its faces
        self.src = names[faces[0].material_index] if names else ""    # its source material (or object, by_object)
        self.group = "body"
        self.remat = None                           # palette material for all its faces, None: by FBX material
        self.ratio = 1.0                            # decimation
        self.renormal = False                       # shaded anew: smooth by angle, normals weighted by face area
        self.bands = None                           # [(z below which, group, material)] per face instead


def islands(bm, mats, names=None) -> list:
    bm.faces.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        seen.add(f.index)
        stack, faces = [f], []
        while stack:
            g = stack.pop()
            faces.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(Island(faces, mats, names))
    return out


def inside(p, box, mirror=True) -> bool:
    """`p` in `box`; mirrored boxes also match on the right side (-X)."""
    lo, hi = box
    x = abs(p[0]) if mirror else p[0]
    return lo[0] <= x <= hi[0] and lo[1] <= p[1] <= hi[1] and lo[2] <= p[2] <= hi[2]


def side(isl) -> str:
    return "left" if isl.c.x > 0.0 else "right"


def classify(c: dict, isls: list) -> None:
    """Group and material of each island of the body."""
    st_lo, st_hi = c["steering"]
    for i in isls:
        if all(st_lo[k] <= i.lo[k] and i.hi[k] <= st_hi[k] for k in range(3)):
            i.group = "steering"
            i.remat = "leather" if i.mat == "dash" else None
        elif i.mat == "indicator":
            i.group = "indicator_" + side(i)
        elif inside(i.c, c["mirror"]):
            i.group = "mirrors"
        elif i.hi.z > c["aerial"] and i.size.x < 0.1 and i.size.y < 0.3:
            i.group = "aerial"
    for s in (1, -1):
        name = "left" if s > 0 else "right"
        on_side = [i for i in isls if i.c.x * s > 0 and i.group == "body"]
        # headlamp: the projector (lens, and the bowl behind it) lights up; the amber bulb's reflector blinks
        head = [i for i in on_side if inside(i.c, c["head_lamp"])]
        bulbs = [i for i in isls if i.group == "indicator_" + name and inside(i.c, c["head_lamp"])]
        for p in [i for i in head if i.mat == "lens" and i.tris > 1000]:
            p.remat = "headlight"
            for i in head:
                if i.mat == "chrome" and (i.c - p.c).xz.length < 0.05 and i.c.y > p.c.y:
                    i.remat = "headlight"
        for b in bulbs:
            for i in head:
                if i.mat == "chrome" and i.tris > 1000 and (i.c - b.c).length < 0.06:
                    i.group = "indicator_" + name
                    i.remat = "indicator"
        # tail lamp: three reflectors one above the other behind a clear lens (and layers of blue glass, which hide
        # them), bottom to top: indicator, brake, tail. The lens lights up instead, in three bands at their heights;
        # what is behind it goes.
        tail = [i for i in on_side if inside(i.c, c["tail_lamp"])]
        refl = sorted([i for i in tail if i.mat == "chrome" and i.tris >= 300 and max(i.size) < 0.17],
                      key=lambda i: i.c.z)
        lens = [i for i in tail if i.mat == "lens" and max(i.size) > 0.2]
        if len(refl) != 3 or len(lens) != 1:
            raise RuntimeError(f"tail lamp {name}: {len(refl)} reflectors, {len(lens)} lenses")
        lens = lens[0]
        lens.bands = [((refl[0].c.z + refl[1].c.z) / 2, "indicator_" + name, "indicator"),
                      ((refl[1].c.z + refl[2].c.z) / 2, "brake_lights", "brake"), (math.inf, "body", "taillight")]
        for i in tail:
            if i is not lens and all(lens.lo[k] - 0.01 <= i.lo[k] and i.hi[k] <= lens.hi[k] + 0.01 for k in range(3)):
                i.group = "hidden"
    for i in isls:
        # third brake lamp: its lens lights up, the LEDs behind it go
        if i.group == "body" and inside(i.c, c["chmsl"], mirror=False):
            if i.mat == "lens" and max(i.size) < 0.02 or i.mat == "chrome":
                i.group = "hidden"
            elif i.mat == "lens":
                i.group, i.remat = "brake_lights", "brake"
        if i.group == "body" and i.mat.startswith("paint"):
            i.renormal = True
        # cabin: seats, and the shell's headliner and carpet (per face, see interior_faces)
        if i.group == "body" and i.mat == "dash" and inside(i.c, c["seats"], mirror=False) \
                and i.size.x < 0.5 and i.size.y < 0.6 and i.tris >= 96:
            i.remat = "seat"
        mat = i.remat or i.mat
        if mat in DETAIL and i.group != "steering":
            if max(i.size) < 0.03 and i.tris > 150:
                i.ratio = max(0.08, 96 / i.tris)
            elif i.tris > 800:
                i.ratio = max(600, 0.1 * i.tris) / i.tris


def glass(bm, isls, mats) -> dict:
    """Windscreen, side and rear windows: the wide panes are the windscreen (front) and the rear window."""
    out = {}
    for i in isls:
        if i.mat == "glass_side" and i.size.x > 1.0:
            out[id(i)] = "glass_front" if i.c.y < 0.0 else "glass_rear"
    return out


def classify_m4(c: dict, isls: list) -> None:
    """Group and material of each island of the BMW M4's body. Head lamp: the two projectors (their bulb discs and
    the bowls around them) light up, the angel eyes are always-on daytime lights, the "eyebrow" strip along the top
    and the slats at the outer end blink. Tail lamp: an outer lens on the wing and an inner one on the boot lid, red
    "L" light guides behind them; the outer lens lights in three bands (indicator, brake, taillight from the bottom),
    the inner one is a taillight with the clear reversing lamp in it; what is behind the lenses goes. The carbon roof
    and its shark-fin aerial (an object of its own) take the clear-coated carbon, the plates are blank, the badges
    plain, the red cluster needles glow."""
    st_lo, st_hi = c["steering"]
    for i in isls:
        if all(st_lo[k] <= i.lo[k] and i.hi[k] <= st_hi[k] for k in range(3)):
            i.group = "steering"
            i.remat = {"dash": "leather", "screen": "trim_black"}.get(i.mat)
        elif inside(i.c, c["mirror"]):
            i.group = "mirrors"
            i.remat = "mirror_glass" if i.mat == "chrome" and i.tris < 100 else None
        elif i.mat == "trim_black" and i.c.z > 1.28:
            i.remat = "paint_carbon"
            if i.size.x < 0.2 and i.size.y < 0.3:
                i.group = "aerial"
        elif i.mat == "plate" and max(i.size) < 0.3:
            i.remat = "trim_black"              # a round badge
        elif i.mat in ("needle", "seat_accent"):    # the M stripes, outside chrome; the red ones of the cluster glow
            if not inside(i.c, c["cabin_box"], mirror=False):
                i.remat = "chrome"
            elif i.c.y > -0.6:
                i.remat = "seat_accent"
    for s in (1, -1):
        name = "left" if s > 0 else "right"
        on_side = [i for i in isls if i.c.x * s > 0 and i.group == "body"]
        head = [i for i in on_side if inside(i.c, c["head_lamp"])]
        bulbs = [i for i in head if i.mat == "headlight"]
        if len(bulbs) != 2:
            raise RuntimeError(f"head lamp {name}: {len(bulbs)} projector bulbs")
        for i in head:
            if i.mat == "chrome" and i.size.z > 0.04 and i.size.x < 0.2 and i.size.y > 0.02 and \
                    any((i.c - b.c).xz.length < 0.03 and i.c.y > b.c.y for b in bulbs):
                i.remat = "headlight"           # the projector's bowl
            elif i.mat == "chrome" and i.tris == 6:
                i.remat = "headlight"           # the projector's cut-off fins
            elif i.mat == "indicator":
                i.group = "hidden"              # 6 mm bulbs
            elif i.mat == "reflector":
                i.group, i.remat = "indicator_" + name, "indicator"     # the eyebrow, the outer slats
        tail = [i for i in on_side if inside(i.c, c["tail_lamp"])]
        lenses = [i for i in tail if i.mat == "taillight" and i.tris > 200]
        rev = [i for i in tail if i.mat == "lens" and i.size.x > 0.08 and i.size.z < 0.04 and i.tris < 50]
        if len(lenses) != 2 or len(rev) != 1:
            raise RuntimeError(f"tail lamp {name}: {len(lenses)} lenses, {len(rev)} reversing lamps")
        outer = max(lenses, key=lambda i: abs(i.c.x))
        lo, hi = c["tail_bands"]
        outer.bands = [(lo, "indicator_" + name, "indicator"), (hi, "brake_lights", "brake"),
                       (math.inf, "body", "taillight")]
        rev[0].group, rev[0].remat = "reverse_lights", "reverse"
        for i in tail:
            if i in lenses or i is rev[0] or i.mat in ("paint_austin", "plastic_black", "trim_black"):
                continue
            if any(all(L.lo[k] - 0.01 <= i.lo[k] and i.hi[k] <= L.hi[k] + 0.01 for k in range(3)) for L in lenses):
                i.group = "hidden"
        # the rear bumper's reflector
        for i in on_side:
            if i.c.y > 1.9 and i.c.z < 0.6 and i.mat in ("taillight", "reflector"):
                i.remat = "reflector_red"
    for i in isls:
        mat = i.remat or i.mat
        if i.group == "body" and i.mat.startswith("paint"):
            i.renormal = True
        if i.group in ("steering", "hidden") or mat.startswith("paint") or mat.startswith("glass") \
                or mat in ("lens", "taillight", "plate"):
            continue
        # decimated (the LOW FBX is ~220k triangles): bolts and buttons, the honeycomb grilles, the callipers behind
        # the rims (their bolts go), the cabin a little more than the rest, the other dense pieces
        if mat == "rim":
            i.group = "hidden"
        elif max(i.size) < 0.03 and i.tris > 60:
            i.ratio = max(0.15, 40 / i.tris)
        elif i.tris > 3000 or mat == "caliper_gold":
            i.ratio = 0.25
        elif inside(i.c, c["cabin_box"], mirror=False) and i.tris > 150:
            i.ratio = max(100, 0.35 * i.tris) / i.tris
        elif i.tris > 250:
            i.ratio = max(150, 0.4 * i.tris) / i.tris


def classify_rules(c: dict, isls: list) -> None:
    """Group and material of each island of the body from the car's list of "rules" (the Audi R8's): each island takes
    the first rule it matches. A rule matches by "src" (its source material, or object with by_object; a name or a
    list), "box" (its centre in it; mirrored to the right side unless "mirror" is False), "mat" (palette material(s)
    from "materials"), "size" (min, max of its largest dimension) and "tris" (min, max), each when given, and sets
    "group" ("indicator" is the island's side's), "remat" and "ratio" (decimation; by default the small dense pieces
    of the DETAIL materials are, as classify does). The paint panels are shaded anew."""
    def matches(r, i):
        names = r.get("src", i.src)
        mats = r.get("mat", i.mat)
        lo, hi = r.get("size", (0.0, math.inf))
        t0, t1 = r.get("tris", (0, math.inf))
        return i.src in ([names] if isinstance(names, str) else names) \
            and i.mat in ([mats] if isinstance(mats, str) else mats) \
            and ("box" not in r or inside(i.c, r["box"], r.get("mirror", True))) \
            and lo <= max(i.size) <= hi and t0 <= i.tris <= t1
    for i in isls:
        r = next((r for r in c["rules"] if matches(r, i)), {})
        i.group = r.get("group", "body")
        if i.group == "indicator":
            i.group = "indicator_" + side(i)
        i.remat = r.get("remat")
        mat = i.remat or i.mat
        if "ratio" in r:
            i.ratio = r["ratio"]
        elif mat in DETAIL and i.group != "steering":
            if max(i.size) < 0.03 and i.tris > 150:
                i.ratio = max(0.08, 96 / i.tris)
            elif i.tris > 800:
                i.ratio = max(600, 0.1 * i.tris) / i.tris
        i.renormal = i.group == "body" and mat.startswith("paint")


# ---------------------------------------------------------------- reworking the loaded objects (the Audi RS6's)

def _points(o):
    import numpy as np
    a = np.empty(len(o.data.vertices) * 3)
    o.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def sheet(o, cell: float = 0.02) -> None:
    """Replaces the mesh of `o`, a wire mesh (a honeycomb: thousands of tiny rings, too many to keep and nothing a
    decimation keeps the look of), by a sheet through it: on each side of the car if it has a gap at x = 0, its points
    are binned in `cell` squares on their plane of best fit, the holes between the rings closed, and each square
    becomes a quad at the mean height of its points over that plane, facing away from the middle of the car."""
    import numpy as np
    pts = _points(o)
    parts = [pts[pts[:, 0] > 0.0], pts[pts[:, 0] < 0.0]] if np.abs(pts[:, 0]).min() > 0.05 else [pts]
    bm = bmesh.new()

    def grow(x):
        y = x.copy()
        y[1:] |= x[:-1]
        y[:-1] |= x[1:]
        y[:, 1:] |= x[:, :-1]
        y[:, :-1] |= x[:, 1:]
        return y
    for p in parts:
        m = p.mean(axis=0)
        u, v, n = np.linalg.svd(p - m, full_matrices=False)[2]
        a, b, h = (p - m) @ u, (p - m) @ v, (p - m) @ n
        ia = ((a - a.min()) / cell).astype(int) + 2         # a margin of 2 squares for the closing
        ib = ((b - b.min()) / cell).astype(int) + 2
        shape = (ia.max() + 3, ib.max() + 3)
        total, count = np.zeros(shape), np.zeros(shape)
        np.add.at(total, (ia, ib), h)
        np.add.at(count, (ia, ib), 1)
        known = count > 0
        height = np.where(known, total / np.maximum(count, 1), 0.0)
        filled = ~grow(~grow(known))
        while (filled & ~known).any():                      # the closed squares: heights of their neighbours
            s, k = np.zeros(shape), np.zeros(shape)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                s += np.roll(np.where(known, height, 0.0), d, (0, 1))
                k += np.roll(known, d, (0, 1))
            new = filled & ~known & (k > 0)
            height[new] = s[new] / k[new]
            known |= new
        ci, cj = np.nonzero(filled)
        ch, cn = np.zeros((shape[0] + 1, shape[1] + 1)), np.zeros((shape[0] + 1, shape[1] + 1))
        for di in (0, 1):
            for dj in (0, 1):
                np.add.at(ch, (ci + di, cj + dj), height[ci, cj])
                np.add.at(cn, (ci + di, cj + dj), 1)
        a0, b0 = a.min() - 2 * cell, b.min() - 2 * cell
        verts = {}

        def vert(i, j):
            if (i, j) not in verts:
                verts[(i, j)] = bm.verts.new(m + (a0 + i * cell) * u + (b0 + j * cell) * v + ch[i, j] / cn[i, j] * n)
            return verts[(i, j)]
        faces = [bm.faces.new((vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1))) for i, j in zip(ci, cj)]
        bm.normal_update()
        out = Vector((m[0], m[1], 0.0))
        if sum(f.normal.dot(out) for f in faces) < 0.0:
            bmesh.ops.reverse_faces(bm, faces=faces)
    me = bpy.data.meshes.new(o.data.name)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    for mat in o.data.materials:
        me.materials.append(mat)
    old, o.data = o.data, me
    bpy.data.meshes.remove(old)
    print(f"{o.name}: a sheet of {len(me.polygons)} quads for {len(pts)} points")


def lining(c: dict) -> None:
    """The inside of the single-skinned panels round the cabin (c["lining"]: object -> palette material): a copy of
    each, 12 mm in and facing the other way, so that the cabin is closed seen from inside or through the windows; one
    object, "lining"."""
    mats = sorted(set(c["lining"].values()))
    bm = bmesh.new()
    for name, mat in c["lining"].items():
        src = bmesh.new()
        src.from_mesh(bpy.data.objects[name].data)
        src.normal_update()
        middle = Vector((0.0, 0.3, 0.9))
        out = 1.0 if sum(f.normal.dot(f.calc_center_median() - middle) * f.calc_area() for f in src.faces) > 0 else -1.0
        for v in src.verts:
            v.co -= v.normal * (0.012 * out)
        if out > 0.0:
            bmesh.ops.reverse_faces(src, faces=src.faces[:])
        for f in src.faces:
            f.material_index = mats.index(mat)
        me = bpy.data.meshes.new("tmp")
        src.to_mesh(me)
        src.free()
        bm.from_mesh(me)                        # (appends)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new("lining")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(bc.mat(m))
    o = bpy.data.objects.new("lining", me)
    bpy.context.scene.collection.objects.link(o)


class ProxyShell:
    """What build_car.interior asks of a car's shell, measured on the imported panels: side_x(y, z) (the outermost |x|
    of the `side` objects' points in the 3 cm square round (y, z), or in the nearest square that has some) and
    f["z_top"](y) (the top of the `roof` objects there)."""

    def __init__(self, side, roof, cell=0.03):
        import numpy as np
        p = np.vstack([_points(bpy.data.objects[n]) for n in side])
        self.cell, self.y0, self.z0 = cell, p[:, 1].min(), p[:, 2].min()
        iy = ((p[:, 1] - self.y0) / cell).astype(int)
        iz = ((p[:, 2] - self.z0) / cell).astype(int)
        grid = np.full((iy.max() + 1, iz.max() + 1), -1.0)
        np.maximum.at(grid, (iy, iz), np.abs(p[:, 0]))
        self.cells, self.vals = np.argwhere(grid >= 0.0), grid[grid >= 0.0]
        self.roof = np.vstack([_points(bpy.data.objects[n]) for n in roof])
        self.f = {"z_top": self.z_top}

    def side_x(self, y, z):
        import numpy as np
        q = np.array([(y - self.y0) / self.cell - 0.5, (z - self.z0) / self.cell - 0.5])
        return float(self.vals[np.argmin(((self.cells - q) ** 2).sum(axis=1))])

    def z_top(self, y):
        import numpy as np
        d = np.abs(self.roof[:, 1] - y)
        near = self.roof[d < 0.05]
        return float(near[:, 2].max() if len(near) else self.roof[np.argmin(d), 2])


def fit_out(c: dict) -> None:
    """Fits out the cabin as build_car.py does (dashboard, cluster, console, door cards, seats, rear bench, parcel
    shelf, mirror, visors, pedals; steering column and wheel) after c["cabin"] (its "cab" keys and "wheel", in the
    loaded frame), in the shell of the loaded panels: objects "fitted_cabin" (palette materials) and "fitted_steering"
    (materials "steering <palette material>", for its rule)."""
    k = c["cabin"]
    spec = {"cab": k, "wheel": k["wheel"]}
    bc._parts.clear()
    bc.interior(spec, ProxyShell(k["side"], k["roof"]))
    bc.steering_column(spec)
    cabin = bc.finish("body")
    st = bc.steering_wheel(spec)
    for o, name in ((cabin, "fitted_cabin"), (st, "fitted_steering")):
        bc.apply_modifiers(o)
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.name = o.data.name = name
    for j, m in enumerate(list(st.data.materials)):
        copy = m.copy()
        copy.name = "steering " + m.name
        st.data.materials[j] = copy


def prepare(c: dict) -> None:
    """Reworks the loaded objects as the car asks, before they are joined: "drop" (objects left out), "sheet" (see
    sheet), "decimate" (object -> ratio), "split_z" (object -> (z, height): its pieces taller than `height` cut apart
    at z, so that the rules tell the two apart), "lining" (see lining) and "cabin" (see fit_out)."""
    for n in c.get("drop", []):
        bpy.data.objects.remove(bpy.data.objects[n])
    for n in c.get("sheet", []):
        sheet(bpy.data.objects[n])
    for n, r in c.get("decimate", {}).items():
        o = bpy.data.objects[n]
        o.modifiers.new("decimate", "DECIMATE").ratio = r
        bc.apply_modifiers(o)
    for n, (z, tall) in c.get("split_z", {}).items():
        o = bpy.data.objects[n]
        bm = bmesh.new()
        bm.from_mesh(o.data)
        cut = [bm.faces[f] for i in islands(bm, [m.name for m in o.data.materials] or [""]) if i.size.z > tall
               for f in i.faces if bm.faces[f].calc_center_median().z >= z]
        bmesh.ops.split(bm, geom=cut)
        bm.to_mesh(o.data)
        bm.free()
    if "lining" in c:
        lining(c)
    if "cabin" in c:
        fit_out(c)


# ---------------------------------------------------------------- building the parts

def set_faces(o, isls: list, face_mat) -> None:
    """Material slots from the palette per face (face_mat(island, face) -> name), and face attributes "grp" (index
    of the island's group in GROUPS) and "isl" (island index), carried through the splits."""
    me = o.data
    per_face = {}                               # face -> (material, group); before the slots go (and the indices)
    for i in isls:
        for f in i.faces:
            if i.bands:
                z = me.polygons[f].center.z
                per_face[f] = next((m, g) for top, g, m in i.bands if z < top)
            else:
                per_face[f] = (face_mat(i, f), i.group)
    names = sorted({m for m, _ in per_face.values()})
    me.materials.clear()
    for n in names:
        me.materials.append(bc.mat(n))
    idx = {n: k for k, n in enumerate(names)}
    mi = [0] * len(me.polygons)
    grp = [0] * len(me.polygons)
    isl = [0] * len(me.polygons)
    for k, i in enumerate(isls):
        for f in i.faces:
            mi[f] = idx[per_face[f][0]]
            grp[f] = GROUPS.index(per_face[f][1])
            isl[f] = k
    me.polygons.foreach_set("material_index", mi)
    me.attributes.new("grp", "INT", "FACE").data.foreach_set("value", grp)
    me.attributes.new("isl", "INT", "FACE").data.foreach_set("value", isl)


def select_only(o) -> None:
    for x in bpy.context.view_layer.objects:
        x.select_set(x == o)
    bpy.context.view_layer.objects.active = o


def split(o, attr: str, keep) -> bpy.types.Object | None:
    """Moves the faces of `o` whose attribute `attr` satisfies keep(value) into a new object, returned."""
    vals = [0] * len(o.data.polygons)
    o.data.attributes[attr].data.foreach_get("value", vals)
    sel = [bool(keep(v)) for v in vals]
    if not any(sel):
        return None
    if all(sel):
        return o
    select_only(o)
    before = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bm = bmesh.from_edit_mesh(o.data)
    bm.faces.ensure_lookup_table()
    for f, s in zip(bm.faces, sel):
        if s:
            f.select_set(True)
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    new = (set(bpy.data.objects) - before).pop()
    for x in (o, new):
        drop_unused_materials(x.data)
    return new


def drop_unused_materials(me) -> None:
    mi = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", mi)
    used = sorted(set(mi))
    mats = [me.materials[k] for k in used]
    remap = {k: n for n, k in enumerate(used)}
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", [remap[k] for k in mi])


def rework(o, isls: list) -> None:
    """Decimates the islands of `o` that have a ratio, and shades them and those to be renormalled anew (each on its
    own): smooth up to 40° (35° for the panels, whose normals then lean towards their larger faces). The model's own
    normals shade the paint in facets in Godot."""
    vals = [0] * len(o.data.polygons)
    o.data.attributes["isl"].data.foreach_get("value", vals)
    for k in sorted(set(vals)):
        if isls[k].ratio >= 1.0 and not isls[k].renormal:
            continue
        part = split(o, "isl", lambda v, k=k: v == k)
        if part is None:
            continue
        select_only(part)
        if part.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        if isls[k].ratio < 1.0:
            mod = part.modifiers.new("decimate", "DECIMATE")
            mod.ratio = isls[k].ratio
            bc.apply_modifiers(part)
        part.data.polygons.foreach_set("use_smooth", [True] * len(part.data.polygons))
        part.data.set_sharp_from_angle(angle=math.radians(35 if isls[k].renormal else 40))
        if isls[k].renormal:
            wn = part.modifiers.new("weighted", "WEIGHTED_NORMAL")
            wn.mode = "FACE_AREA"
            wn.weight = 50
            wn.keep_sharp = True
            bc.apply_modifiers(part)
        if part != o:
            bc.join(o, [o, part])


def cluster(k: dict) -> bpy.types.Object:
    """A digital instrument cluster for a cabin without one (k: "centre" of its screen in the car frame, "size" (width,
    height), "tilt" back from upright in degrees): a screen with two ring dials, their needles and a bar between them,
    in a binnacle under a visor, facing the driver (+Y), as build_car.py's; it has to show between the steering wheel's
    hub and the top of its rim."""
    c = Vector(k["centre"])
    w, h = k["size"]
    x, y, z = c
    bc.box("cluster", (x - w / 2 - 0.015, y - 0.05, z - h / 2 - 0.015), (x + w / 2 + 0.015, y - 0.004, z + h / 2 + 0.01),
           "dash", 0.01)
    bc.box("cluster", (x - w / 2 - 0.025, y - 0.08, z + h / 2 + 0.005), (x + w / 2 + 0.025, y + 0.05, z + h / 2 + 0.03),
           "dash", 0.01)
    bc.box("cluster", (x - w / 2, y - 0.006, z - h / 2), (x + w / 2, y, z + h / 2), "screen", 0.002)
    r = h * 0.36
    for gx in (x - w * 0.3, x + w * 0.3):
        ring = [(gx + r * math.cos(math.radians(a)), y + 0.003, z + r * math.sin(math.radians(a)))
                for a in range(-220, 41, 10)]
        bc.tube("cluster", ring, 0.0035, "gauge", 6)
        bc.box("cluster", (gx - 0.0025, y + 0.001, z - 0.004), (gx + 0.0025, y + 0.004, z + r * 0.8), "needle", 0.0)
    bc.box("cluster", (x - w * 0.12, y + 0.0005, z - h * 0.3), (x + w * 0.12, y + 0.003, z + h * 0.25), "screen_ui", 0.0)
    o = bc.finish("cluster")
    bc.apply_modifiers(o)
    o.data.transform(Matrix.Translation(c) @ Matrix.Rotation(math.radians(k.get("tilt", 0.0)), 4, "X")
                     @ Matrix.Translation(-c))
    return o


def tris(o) -> int:
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


GROUPS = ["body", "steering", "mirrors", "aerial", "indicator_left", "indicator_right", "brake_lights",
          "wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right", "reverse_lights", "hidden"]


def build(key: str, out_dir: Path, prev: str) -> None:
    c = CARS[key]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    if "obj" in c:
        load_obj(ROOT / c["obj"], c)
    else:
        load_fbx(ROOT / c["fbx"])
    prepare(c)
    body = merged(c["body"])
    wheels = merged(c["wheels"])
    # into the car frame: middle of the body box, the bottom of the tyres on the ground
    lo, hi = bounds(v.co for v in body.data.vertices)
    wlo, _ = bounds(v.co for v in wheels.data.vertices)
    shift = Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -wlo.z)))
    for o in (body, wheels):
        o.data.transform(shift)
    fbx_names = {o: [m.name.removeprefix("fbx ") if m else "" for m in o.data.materials] for o in (body, wheels)}
    pal = {o: [c["materials"].get(n, "plastic_black") for n in fbx_names[o]] for o in (body, wheels)}

    # body pieces
    bm = bmesh.new()
    bm.from_mesh(body.data)
    isls = islands(bm, pal[body], fbx_names[body])
    globals()[c.get("classify", "classify")](c, isls)       # per car: its lamps differ
    panes = glass(bm, isls, pal[body])
    bm.faces.ensure_lookup_table()
    centre = {f.index: f.calc_center_median() for f in bm.faces}
    normal = {f.index: f.normal.copy() for f in bm.faces}

    def body_mat(i, f):
        if i.remat:
            return i.remat
        if id(i) in panes:
            return panes[id(i)]
        m = pal[body][bm.faces[f].material_index]
        if m == "dash" and i.size.y > 2.0:        # the cabin shell: headliner over the heads, carpet on the floor
            if centre[f].z > 1.3 and abs(normal[f].z) > 0.3:
                return "headliner"
            if centre[f].z < 0.55 and abs(normal[f].z) > 0.6:
                return "carpet"
        return m
    set_faces(body, isls, body_mat)
    bm.free()

    # wheels: each piece to the wheel of its quarter, the callipers (they do not spin) to the body
    bm = bmesh.new()
    bm.from_mesh(wheels.data)
    wisl = islands(bm, pal[wheels])
    bm.free()
    tyres = [i for i in wisl if i.mat == "tyre" and i.size.z > 0.5]
    mid = sum((i.c for i in tyres), Vector()) / len(tyres)
    hubs = {}
    ratios = c.get("wheel_ratio", WHEEL_RATIO)
    for i in wisl:
        stem = "front" if i.c.y < mid.y else "rear"
        i.group = f"wheel_{stem}_{'left' if i.c.x > mid.x else 'right'}"
        if i.mat == "alu":
            i.group, i.remat = "body", "caliper"
        elif max(i.size) < c.get("wheel_drop", 0.0):         # bolts behind the rim, badges
            i.group = "hidden"
        elif i.mat in ratios and i.tris > c.get("wheel_min_tris", 800):
            i.ratio = ratios[i.mat]
        elif i.mat == "plastic_black":
            i.remat = "hub"
            i.ratio = ratios["hub"] if i.tris > 800 else 1.0
    for i in tyres:
        hubs[i.group] = i.c.copy()
    set_faces(wheels, wisl, lambda i, f: i.remat or pal[wheels][wheels.data.polygons[f].material_index])

    objs = {}
    for src, parts in ((body, isls), (wheels, wisl)):
        for g in reversed(GROUPS):
            o = split(src, "grp", lambda v, g=g: v == GROUPS.index(g))
            if o is None:
                continue
            rework(o, parts)
            if g in objs:
                bc.join(objs[g], [objs[g], o])
            else:
                o.name = o.data.name = g
                objs[g] = o
    for name, p in hubs.items():
        o = objs[name]
        o.data.transform(Matrix.Translation(-p))
        o.location = p
    # steering wheel: hub on the axis of the rim (the normal of its plane, towards the driver), 12 o'clock up
    st = objs["steering"]
    pts = [v.co.copy() for v in st.data.vertices]
    lo, hi = bounds(pts)
    mean = sum(pts, Vector()) / len(pts)
    cov = Matrix(((0,) * 3,) * 3)
    for p in pts:
        d = p - mean
        for a in range(3):
            for b in range(3):
                cov[a][b] += d[a] * d[b]
    axis = Vector((0.0, 1.0, 0.0))
    for _ in range(50):                             # smallest eigenvector: power iteration on the inverse
        axis = (cov.inverted() @ axis).normalized()
    if axis.y < 0.0:
        axis = -axis
    rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    local = [rot.inverted() @ p for p in pts]
    llo, lhi = bounds(local)
    hub = rot @ Vector(((llo.x + lhi.x) / 2, (llo.y + lhi.y) / 2, (llo.z + lhi.z) / 2))
    xf = Matrix.Translation(hub) @ rot
    st.data.transform(xf.inverted())
    st.matrix_world = xf
    print(f"steering wheel at {tuple(round(v, 3) for v in hub)}, axis {tuple(round(v, 3) for v in axis)}, "
          f"rim {lhi.x - llo.x:.3f} x {lhi.y - llo.y:.3f} m")
    if "hidden" in objs:
        bpy.data.objects.remove(objs.pop("hidden"))
    for o in objs.values():
        for a in ("grp", "isl"):
            if a in o.data.attributes:
                o.data.attributes.remove(o.data.attributes[a])
    for o in list(bpy.data.objects):
        if o not in objs.values():
            bpy.data.objects.remove(o)
    if "cluster" in c["cab"]:                   # the model's cabin has none
        bc.join(objs["body"], [objs["body"], cluster(c["cab"]["cluster"])])

    # cab: the driver's seat (cushion top) and eye, mirrored for the passenger
    k = c["cab"]
    if "seat" in k:                             # given (the seat is one piece with its back)
        seat = Vector(k["seat"])
    else:
        seat_isl = [i for i in isls if i.remat == "seat" and i.c.x > 0.1 and i.c.y < 0.2 and i.size.z < 0.3]
        cushion = max(seat_isl, key=lambda i: i.tris)
        seat = Vector((cushion.c.x, cushion.c.y, cushion.hi.z))
    eye = Vector((seat.x, k["eye"][0], k["eye"][1]))
    print(f"driver seat {tuple(round(v, 3) for v in seat)}, eye {tuple(round(v, 3) for v in eye)}")

    out = out_dir / f"{key}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_normals=True,
                              export_materials="EXPORT", export_yup=True, export_apply=True,
                              export_texcoords=False)                 # untextured
    wheel_names = [g for g in GROUPS if g.startswith("wheel_")]
    layout = {
        "wheels": wheel_names,
        "indicators": {"left": ["indicator_left"], "right": ["indicator_right"]},
        "brake_lights": ["brake_lights"],
        "cab": {
            "driver_seat": bc.gd(seat),
            "driver_eye": bc.gd(eye),
            "passenger_seat": bc.gd((-seat.x, seat.y, seat.z)),
            "passenger_eye": bc.gd((-eye.x, eye.y, eye.z)),
            "steering_wheel": "steering",
            "figure": k["figure"],
            "eye_pitch": k["eye_pitch"],
        },
    }
    if "reverse_lights" in objs:
        layout["reverse_lights"] = ["reverse_lights"]
    out.with_suffix(".json").write_text(json.dumps(layout, indent=1) + "\n")
    total = sum(tris(o) for o in objs.values())
    print(f"{key}: {out} ({total} triangles: " + ", ".join(f"{n} {tris(o)}" for n, o in objs.items()) + ")")
    blo, bhi = bounds(v.co for v in objs["body"].data.vertices)
    print(f"body box {tuple(round(v, 3) for v in blo)} .. {tuple(round(v, 3) for v in bhi)}; wheels " +
          ", ".join(f"{n} {tuple(round(v, 3) for v in p)}" for n, p in sorted(hubs.items())))
    if prev:
        Path(prev).mkdir(parents=True, exist_ok=True)
        bc.preview(str(Path(prev) / key), {"length": bhi.y - blo.y}, {"eye": eye})


def main() -> None:
    a = bc.args()
    for key in ([a["car"]] if a["car"] else list(CARS)):
        build(key, Path(a["out_dir"]), a["preview"])


if __name__ == "__main__":         # (import_truck.py imports its helpers)
    main()
