"""Street equipment: traffic lights, hydrant, cameras, information boards, charging station, poles and masts,
kiosks, billboards, sign poles. Front = -Y, origin on the ground (wall models: back on y = 0)."""
import math

from toylib import Model


def traffic_light_car() -> Model:
    """Car signal: anthracite pole, black head with three visored lenses facing the traffic (front)."""
    m = Model("traffic_light_car", view_range=300.0)
    m.cyl(0.1, 0.2, (0, 0, 0), "anthracite", bevel=0.02)
    m.cyl(0.055, 3.05, (0, 0, 0.1), "anthracite", sides=12, bevel=0.0)
    m.box((0.32, 0.22, 1.0), (0, -0.16, 2.15), "dark", base=True, bevel=0.04, seg=3)
    m.box((0.46, 0.03, 1.14), (0, -0.04, 2.08), "anthracite", base=True, bevel=0.02)
    for z, col in ((2.94, "signal_red"), (2.65, "signal_amber"), (2.36, "signal_green")):
        m.cyl(0.105, 0.02, (0, -0.27, z), col, "signal_car", rot=(90, 0, 0), sides=20, bevel=0.0)
        m.box((0.26, 0.12, 0.02), (0, -0.33, z + 0.12), "dark", bevel=0.005, rot=(-10, 0, 0))
    # small repeater at drivers' eye level, as on French signals
    m.box((0.14, 0.12, 0.4), (0, -0.1, 1.45), "dark", base=True, bevel=0.025)
    for z, col in ((1.75, "signal_red"), (1.62, "signal_amber"), (1.49, "signal_green")):
        m.cyl(0.04, 0.015, (0, -0.165, z), col, "signal_car", rot=(90, 0, 0), sides=12, bevel=0.0)
    m.collide_cyl(0.08, 3.1)
    return m


def traffic_light_ped() -> Model:
    """Pedestrian signal: pole, two-lens head (red man above green man) and a push button box."""
    m = Model("traffic_light_ped", view_range=250.0)
    m.cyl(0.09, 0.15, (0, 0, 0), "anthracite", bevel=0.02)
    m.cyl(0.05, 2.75, (0, 0, 0.1), "anthracite", sides=12, bevel=0.0)
    m.box((0.28, 0.18, 0.62), (0, -0.13, 2.05), "dark", base=True, bevel=0.035, seg=3)
    for z, col in ((2.51, "signal_red"), (2.2, "signal_green")):
        m.box((0.2, 0.02, 0.24), (0, -0.225, z - 0.12), col, "signal_ped", base=True, bevel=0.01)
        m.box((0.26, 0.1, 0.02), (0, -0.25, z + 0.14), "dark", bevel=0.005)
        # little man: head and body in black over the lens
        m.cyl(0.022, 0.01, (0, -0.237, z + 0.06), "sign_black", rot=(90, 0, 0), sides=10, bevel=0.0)
        m.box((0.05, 0.01, 0.1), (0, -0.237, z - 0.03), "sign_black", bevel=0.0)
    m.box((0.12, 0.1, 0.2), (0, -0.09, 1.0), "safety", base=True, bevel=0.02)
    m.cyl(0.025, 0.02, (0, -0.145, 1.1), "dark", rot=(90, 0, 0), sides=10, bevel=0.0)
    m.collide_cyl(0.07, 2.8)
    return m


def fire_hydrant() -> Model:
    """French red pillar hydrant: body, domed cap, two side outlets and a bigger front one."""
    m = Model("fire_hydrant")
    m.cyl(0.16, 0.06, (0, 0, -0.02), "red", sides=16, bevel=0.015)
    m.cyl(0.11, 0.72, (0, 0, 0.03), "red", sides=16, bevel=0.0)
    m.cyl(0.135, 0.06, (0, 0, 0.72), "red", sides=16, bevel=0.015)
    m.sphere(0.12, (0, 0, 0.78), "red", seg=16, scale=(1, 1, 0.7))
    m.cyl(0.03, 0.06, (0, 0, 0.84), "silver", sides=6, bevel=0.0)
    for a in (0, 180):
        m.cyl(0.045, 0.17, (0, 0, 0.5), "red", rot=(0, 90, a), sides=12, bevel=0.01)
        m.cyl(0.05, 0.03, (0.15 * math.cos(math.radians(a)), 0, 0.5), "silver", rot=(0, 90, a), sides=12, bevel=0.008)
    m.cyl(0.07, 0.19, (0, 0, 0.4), "red", rot=(90, 0, 0), sides=14, bevel=0.01)
    m.cyl(0.078, 0.03, (0, -0.17, 0.4), "silver", rot=(90, 0, 0), sides=14, bevel=0.008)
    m.collide_cyl(0.15, 0.9)
    return m


def cctv_pole() -> Model:
    m = Model("cctv_pole", view_range=250.0)
    m.cyl(0.09, 0.15, (0, 0, 0), "anthracite", bevel=0.02)
    m.cyl(0.055, 4.0, (0, 0, 0.1), "steel", sides=12, r2=0.04, bevel=0.0)
    m.tube([(0, 0, 3.85), (0, -0.25, 3.9), (0, -0.35, 3.85)], 0.025, "steel")
    m.box((0.13, 0.32, 0.13), (0, -0.42, 3.72), "white", bevel=0.03, rot=(-20, 0, 0))
    m.box((0.17, 0.36, 0.03), (0, -0.43, 3.81), "white", bevel=0.01, rot=(-20, 0, 0))
    m.cyl(0.04, 0.02, (0, -0.58, 3.66), "dark", rot=(70, 0, 0), sides=12, bevel=0.0)
    m.collide_cyl(0.08, 4.0)
    return m


def cctv_wall() -> Model:
    """Dome camera on a wall bracket at 3 m."""
    m = Model("cctv_wall", wall=True, view_range=150.0)
    m.box((0.12, 0.04, 0.16), (0, -0.02, 3.0), "white", bevel=0.01)
    m.tube([(0, -0.03, 3.0), (0, -0.22, 3.02)], 0.025, "white")
    m.cyl(0.09, 0.05, (0, -0.25, 2.97), "white", sides=16, bevel=0.015)
    m.sphere(0.07, (0, -0.25, 2.97), "dark", seg=12, scale=(1, 1, 0.8))
    return m


def info_board() -> Model:
    """Wooden information board with a little roof and a colourful map."""
    m = Model("info_board", view_range=200.0)
    for x in (-0.68, 0.68):
        m.box((0.1, 0.1, 2.15), (x, 0, 0), "wood_dark", base=True, bevel=0.02)
    m.box((1.3, 0.05, 0.85), (0, 0.0, 0.95), "wood", base=True, bevel=0.015)
    m.box((1.18, 0.01, 0.73), (0, -0.03, 1.01), "white", base=True, bevel=0.0)
    for x, z, w, h, c in ((-0.3, 1.12, 0.45, 0.3, "#9fd17a"), (0.2, 1.3, 0.5, 0.35, "#7cc4e8"), (0.32, 1.05, 0.3, 0.14, "#f2c230"),
                          (-0.35, 1.5, 0.35, 0.12, "#e98a6b")):
        m.box((w, 0.01, h), (x, -0.036, z), c, base=True, bevel=0.0)
    m.box((1.6, 0.4, 0.05), (0, 0.0, 2.1), "wood_dark", base=True, bevel=0.015, rot=(8, 0, 0))
    m.collide_box((1.5, 0.15, 2.2), (0, 0, 0), base=True)
    return m


def guidepost() -> Model:
    m = Model("guidepost", view_range=150.0)
    m.cyl(0.06, 2.3, (0, 0, 0), "wood_dark", sides=10, bevel=0.01)
    m.cyl(0.075, 0.06, (0, 0, 2.3), "wood_dark", r2=0.02, sides=10, bevel=0.0)
    for z, a in ((2.05, 20), (1.85, 130), (1.65, 250)):
        m.box((0.6, 0.03, 0.14), (0.3 * math.cos(math.radians(a)), 0.3 * math.sin(math.radians(a)), z), "white", rot=(0, 0, a), bevel=0.01)
        m.box((0.12, 0.035, 0.1), (0.52 * math.cos(math.radians(a)), 0.52 * math.sin(math.radians(a)), z), "sign_yellow", rot=(0, 0, a), bevel=0.005)
    m.collide_cyl(0.08, 2.3)
    return m


def route_marker() -> Model:
    m = Model("route_marker", view_range=100.0)
    m.box((0.1, 0.1, 1.2), (0, 0, 0), "wood", base=True, bevel=0.015)
    m.box((0.104, 0.104, 0.08), (0, 0, 1.0), "sign_yellow", base=True, bevel=0.005)
    m.box((0.104, 0.104, 0.05), (0, 0, 0.94), "sign_red", base=True, bevel=0.005)
    m.collide_cyl(0.07, 1.2)
    return m


def charging_station() -> Model:
    m = Model("charging_station", view_range=200.0)
    m.box((0.55, 0.32, 1.45), (0, 0, 0), "white", base=True, bevel=0.06, seg=3)
    m.box((0.06, 0.01, 0.9), (-0.18, -0.162, 0.3), "glow", "glow", base=True, bevel=0.0)
    m.box((0.22, 0.01, 0.16), (0.08, -0.162, 1.05), "dark", base=True, bevel=0.0)
    m.box((0.56, 0.33, 0.12), (0, 0, 0.0), "sign_green", base=True, bevel=0.02)
    m.tube([(0.2, -0.16, 0.8), (0.32, -0.25, 0.6), (0.3, -0.24, 0.35), (0.22, -0.17, 0.28)], 0.02, "dark")
    m.collide_box((0.56, 0.34, 1.45), (0, 0, 0), base=True)
    return m


def bike_repair() -> Model:
    m = Model("bike_repair")
    m.box((0.22, 0.22, 1.35), (0, 0, 0), "sign_blue", base=True, bevel=0.03)
    m.tube([(0, -0.1, 1.25), (0, -0.4, 1.38), (0, -0.55, 1.3)], 0.022, "steel")
    m.tube([(0, -0.1, 1.15), (0, -0.4, 1.28), (0, -0.55, 1.2)], 0.022, "steel")
    m.cyl(0.08, 0.35, (0.2, 0, 0), "anthracite", sides=12, bevel=0.01)
    m.collide_box((0.25, 0.25, 1.4), (0, 0, 0), base=True)
    return m


def _flagpole(name: str, bands: list) -> Model:
    m = Model(name, view_range=400.0)
    m.cyl(0.11, 0.2, (0, 0, 0), "concrete", bevel=0.03)
    m.cyl(0.05, 8.0, (0, 0, 0.15), "white", r2=0.03, sides=12, bevel=0.0)
    m.sphere(0.05, (0, 0, 8.15), "la_poste", seg=10)
    w = 1.2 / len(bands)
    for i, c in enumerate(bands):
        m.box((w, 0.02, 0.8), (0.05 + w / 2 + i * w, 0, 7.25), c, base=True, bevel=0.005)
    m.collide_cyl(0.1, 3.0)
    return m


def flagpole() -> Model:
    return _flagpole("flagpole", ["white"])


def flagpole_fr() -> Model:
    return _flagpole("flagpole_fr", ["#2e4fa8", "white", "#e1393b"])


def substation_kiosk() -> Model:
    """Enedis distribution substation: a small concrete cabin with grey-green doors and vents."""
    m = Model("substation_kiosk", view_range=400.0)
    m.box((2.5, 1.7, 2.15), (0, 0, 0), "enedis", base=True, bevel=0.05, seg=3)
    m.box((2.7, 1.9, 0.12), (0, 0, 2.15), "concrete", base=True, bevel=0.04, seg=3)
    for x in (-0.6, 0.6):
        m.box((0.95, 0.03, 1.8), (x, -0.86, 0.15), "#8ea889", base=True, bevel=0.015)
        for z in (1.55, 1.65, 1.75):
            m.box((0.6, 0.02, 0.03), (x, -0.88, z), "dark", base=True, bevel=0.0)
    m.box((0.3, 0.01, 0.3), (0, -0.88, 1.65), "safety", base=True, bevel=0.0, rot=(0, 45, 0))
    m.collide_box((2.5, 1.7, 2.27), (0, 0, 0), base=True)
    return m


def power_pole() -> Model:
    m = Model("power_pole", view_range=500.0)
    m.cyl(0.13, 9.0, (0, 0, 0), "wood_dark", r2=0.09, sides=12, bevel=0.01)
    m.box((1.6, 0.1, 0.1), (0, 0, 8.4), "wood_dark", bevel=0.015)
    for x in (-0.7, 0.0, 0.7):
        m.cyl(0.04, 0.18, (x, 0, 8.45), "white", sides=10, bevel=0.01)
    m.collide_cyl(0.14, 3.0)
    return m


def mast() -> Model:
    """Telecom mast: tapered steel pole, a platform and three antenna panels."""
    m = Model("mast", view_range=800.0)
    m.cyl(0.6, 0.4, (0, 0, -0.1), "concrete", bevel=0.05)
    m.cyl(0.35, 24.0, (0, 0, 0.2), "steel", r2=0.14, sides=16, bevel=0.0)
    m.cyl(0.9, 0.12, (0, 0, 21.0), "steel", sides=16, bevel=0.02)
    for a in (90, 210, 330):
        x, y = 0.7 * math.cos(math.radians(a)), 0.7 * math.sin(math.radians(a))
        m.box((0.32, 0.12, 2.0), (x, y, 21.6), "white", base=True, rot=(0, 0, a - 90), bevel=0.03)
    m.collide_cyl(0.4, 4.0)
    return m


def defibrillator() -> Model:
    """AED cabinet on a short post (green box with a white heart cross)."""
    m = Model("defibrillator", view_range=100.0)
    m.box((0.1, 0.1, 1.0), (0, 0.05, 0), "anthracite", base=True, bevel=0.015)
    m.box((0.42, 0.22, 0.5), (0, -0.05, 0.95), "sign_green", base=True, bevel=0.04, seg=3)
    m.box((0.18, 0.01, 0.05), (0, -0.165, 1.25), "white", bevel=0.0)
    m.box((0.05, 0.01, 0.18), (0, -0.165, 1.25), "white", bevel=0.0)
    m.collide_box((0.42, 0.3, 1.45), (0, 0, 0), base=True)
    return m


def billboard() -> Model:
    m = Model("billboard", view_range=400.0)
    for x in (-1.0, 1.0):
        m.box((0.16, 0.16, 1.2), (x, 0, 0), "anthracite", base=True, bevel=0.02)
    m.box((3.3, 0.3, 2.4), (0, 0, 1.1), "white", base=True, bevel=0.05, seg=3)
    for s in (-1, 1):
        m.box((3.0, 0.01, 2.1), (0, s * 0.152, 1.25), "glow", "glow", base=True, bevel=0.0)
    m.collide_box((3.3, 0.3, 3.5), (0, 0, 0), base=True)
    return m


def advert_column() -> Model:
    """Morris advertising column: dark green drum, lit poster band and a domed crown."""
    m = Model("advert_column", view_range=400.0)
    m.cyl(0.62, 0.3, (0, 0, 0), "#2f5a43", sides=28, bevel=0.04)
    m.cyl(0.55, 2.2, (0, 0, 0.3), "glow", "glow", sides=28, bevel=0.0)
    m.cyl(0.64, 0.2, (0, 0, 2.5), "#2f5a43", sides=28, bevel=0.04)
    m.sphere(0.6, (0, 0, 2.7), "#2f5a43", seg=24, scale=(1, 1, 0.5))
    m.sphere(0.1, (0, 0, 3.0), "#2f5a43", seg=12)
    m.collide_cyl(0.64, 3.0)
    return m


def assembly_sign() -> Model:
    """Emergency assembly point sign: green square with a white pictogram, on a post."""
    m = Model("assembly_sign", view_range=120.0)
    m.cyl(0.035, 2.3, (0, 0, 0), "steel", sides=10, bevel=0.0)
    m.box((0.5, 0.02, 0.5), (0, -0.05, 1.75), "sign_green", base=True, bevel=0.02)
    for a in (0, 90, 180, 270):
        x, z = 0.13 * math.cos(math.radians(a)), 0.13 * math.sin(math.radians(a))
        m.box((0.1, 0.01, 0.03), (x, -0.062, 2.0 + z), "white", rot=(0, -a, 0), bevel=0.0)
    m.cyl(0.04, 0.01, (0, -0.062, 2.0), "white", rot=(90, 0, 0), sides=10, bevel=0.0)
    m.collide_cyl(0.05, 2.3)
    return m


def sign_pole() -> Model:
    """Grey post that carries the sign faces (signs.py); the Godot builder stacks them from `top` down."""
    m = Model("sign_pole", view_range=250.0)
    m.cyl(0.06, 0.06, (0, 0, -0.02), "steel", bevel=0.015)
    m.cyl(0.032, 2.85, (0, 0, 0.0), "steel", sides=10, bevel=0.0)
    m.cyl(0.036, 0.03, (0, 0, 2.85), "steel", bevel=0.01)
    m.anchor("faces", top=2.85, gap=0.06, front=0.04)
    m.collide_cyl(0.05, 2.85)
    return m


MODELS = {f.__name__: f for f in (traffic_light_car, traffic_light_ped, fire_hydrant, cctv_pole, cctv_wall, info_board,
                                  guidepost, route_marker, charging_station, bike_repair, flagpole, flagpole_fr,
                                  substation_kiosk, power_pole, mast, defibrillator, billboard, advert_column,
                                  assembly_sign, sign_pole)}
