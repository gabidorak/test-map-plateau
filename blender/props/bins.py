"""Bins and boxes: Vigipirate bag bin, containers, recycling columns, lockers, vending machines, post box.
Front = -Y, origin on the ground (wall models: back on y = 0)."""
import math

from toylib import Model


def bin_vigipirate() -> Model:
    """French "Vigipirate" bin: a hoop on a post holding a transparent (greenish) bag, with a lid ring."""
    m = Model("bin_vigipirate", view_range=120.0)
    m.cyl(0.035, 1.05, (0, 0.2, 0), "anthracite", sides=10, bevel=0.0)
    m.cyl(0.07, 0.04, (0, 0.2, 0), "anthracite", bevel=0.01)
    m.tube([(0.2 * math.cos(math.radians(a)), -0.02 + 0.2 * math.sin(math.radians(a)), 0.88) for a in range(0, 361, 20)],
           0.018, "anthracite", sides=8)
    m.box((0.04, 0.05, 0.08), (0, 0.18, 0.88), "anthracite", bevel=0.01)
    m.cyl(0.19, 0.5, (0, -0.02, 0.36), "bag", sides=18, r2=0.2, bevel=0.0)
    m.sphere(0.19, (0, -0.02, 0.37), "bag", seg=16, scale=(1, 1, 0.6))
    m.cyl(0.215, 0.05, (0, -0.02, 0.9), "anthracite", sides=20, r2=0.19, bevel=0.012)
    m.collide_cyl(0.22, 1.0, (0, 0, 0))
    return m


def waste_container() -> Model:
    """Four-wheel 1100 l container (grey body, darker lid)."""
    m = Model("waste_container")
    m.box((1.3, 0.95, 0.95), (0, 0, 0.18), "waste_bin", base=True, bevel=0.06, seg=3)
    m.box((1.36, 1.05, 0.1), (0, 0.02, 1.12), "dark", base=True, bevel=0.04, rot=(-4, 0, 0))
    m.box((1.0, 0.06, 0.06), (0, -0.52, 0.85), "dark", bevel=0.02)
    for x in (-0.5, 0.5):
        for y in (-0.35, 0.35):
            m.cyl(0.08, 0.06, (x - 0.03, y, 0.08), "rubber", rot=(0, 90, 0), sides=12, bevel=0.015)
    m.collide_box((1.35, 1.0, 1.2), (0, 0, 0), base=True)
    return m


def bin_underground() -> Model:
    """Underground waste container: steel column with a chute, on a concrete plate."""
    m = Model("bin_underground")
    m.box((1.5, 1.5, 0.04), (0, 0, -0.01), "concrete", base=True, bevel=0.01)
    m.box((0.62, 0.62, 1.15), (0, 0, 0.03), "waste_bin", base=True, bevel=0.06, seg=3)
    m.box((0.4, 0.04, 0.2), (0, -0.31, 0.85), "dark", bevel=0.02)
    m.cyl(0.33, 0.08, (0, 0, 1.18), "dark", sides=20, r2=0.25, bevel=0.02)
    m.collide_box((0.65, 0.65, 1.25), (0, 0, 0), base=True)
    return m


def recycling_column() -> Model:
    """Recycling "colonne": rounded column with a dome lid and lifting ring; body tinted by waste type."""
    m = Model("recycling_column", view_range=200.0)
    m.cyl(0.62, 1.35, (0, 0, 0.05), "white", "tint", sides=28, bevel=0.1, seg=3)
    m.cyl(0.58, 0.06, (0, 0, 0.0), "dark", sides=28, bevel=0.02)
    m.sphere(0.62, (0, 0, 1.35), "white", "tint", seg=28, scale=(1, 1, 0.38))
    m.tube([(0.12 * math.cos(math.radians(a)), 0.0, 1.76 + 0.12 * math.sin(math.radians(a))) for a in range(0, 361, 30)],
           0.025, "steel", sides=8)
    m.cyl(0.035, 0.12, (0, 0, 1.55), "steel", sides=8)
    for a in (-90, 0, 180):
        x, y = 0.6 * math.cos(math.radians(a)), 0.6 * math.sin(math.radians(a))
        m.cyl(0.11, 0.05, (x, y, 1.05), "dark", rot=(90, 0, a + 90), sides=16, bevel=0.01)
    m.collide_cyl(0.65, 1.7)
    return m


def recycling_underground() -> Model:
    m = Model("recycling_underground")
    m.box((1.5, 1.5, 0.04), (0, 0, -0.01), "concrete", base=True, bevel=0.01)
    m.cyl(0.32, 1.1, (0, 0, 0.03), "white", "tint", sides=20, bevel=0.06, seg=3)
    m.sphere(0.32, (0, 0, 1.12), "white", "tint", seg=20, scale=(1, 1, 0.4))
    m.cyl(0.12, 0.04, (0, -0.31, 0.85), "dark", rot=(90, 0, 0), sides=16, bevel=0.01)
    m.collide_cyl(0.34, 1.25)
    return m


def parcel_locker() -> Model:
    """Parcel locker against a wall: grid of doors and a screen (La Poste yellow sides)."""
    m = Model("parcel_locker", wall=True)
    m.box((2.0, 0.55, 1.95), (0, -0.28, 0), "la_poste", base=True, bevel=0.03)
    for i in range(5):
        for j in range(4):
            if i == 2 and j in (1, 2):
                continue
            m.box((0.36, 0.02, 0.42), (-0.8 + i * 0.4, -0.56, 0.12 + j * 0.45), "silver", base=True, bevel=0.01)
    m.box((0.36, 0.03, 0.4), (0, -0.565, 0.6), "dark", base=True, bevel=0.01)
    m.box((0.26, 0.01, 0.2), (0, -0.585, 0.75), "glow", "glow", base=True, bevel=0.0)
    m.collide_box((2.0, 0.56, 1.95), (0, -0.28, 0), base=True)
    return m


def vending_machine() -> Model:
    m = Model("vending_machine", wall=True)
    m.box((0.95, 0.8, 1.85), (0, -0.4, 0), "sign_red", base=True, bevel=0.03)
    m.box((0.6, 0.02, 1.2), (-0.12, -0.81, 0.45), "glass", "glass", base=True, bevel=0.0)
    m.box((0.58, 0.01, 1.18), (-0.12, -0.79, 0.46), "glow", "glow", base=True, bevel=0.0)
    m.box((0.2, 0.03, 0.5), (0.3, -0.81, 0.9), "dark", base=True, bevel=0.01)
    m.box((0.6, 0.04, 0.12), (-0.12, -0.81, 0.18), "dark", base=True, bevel=0.01)
    m.collide_box((0.95, 0.8, 1.85), (0, -0.4, 0), base=True)
    return m


def parking_meter() -> Model:
    """Horodateur: anthracite box on a short base with a screen and a little roof."""
    m = Model("parking_meter", wall=True)
    m.box((0.22, 0.18, 0.8), (0, -0.15, 0), "anthracite", base=True, bevel=0.02)
    m.box((0.42, 0.3, 0.75), (0, -0.15, 0.8), "anthracite", base=True, bevel=0.04, seg=3)
    m.box((0.2, 0.01, 0.13), (0, -0.305, 1.3), "glow", "glow", base=True, bevel=0.0)
    m.box((0.36, 0.02, 0.06), (0, -0.3, 1.0), "sign_blue", base=True, bevel=0.005)
    m.box((0.48, 0.36, 0.04), (0, -0.15, 1.55), "steel", base=True, bevel=0.015)
    m.collide_box((0.42, 0.3, 1.6), (0, -0.15, 0), base=True)
    return m


def post_box() -> Model:
    m = Model("post_box")
    m.cyl(0.05, 0.8, (0, 0, 0), "anthracite", sides=10, bevel=0.0)
    m.box((0.42, 0.32, 0.55), (0, 0, 0.78), "la_poste", base=True, bevel=0.05, seg=3)
    m.sphere(0.21, (0, 0, 1.31), "la_poste", seg=16, scale=(1, 0.76, 0.35))
    m.box((0.26, 0.02, 0.03), (0, -0.165, 1.15), "dark", bevel=0.008)
    m.box((0.2, 0.01, 0.12), (0, -0.165, 0.95), "sign_blue", base=True, bevel=0.0)
    m.collide_box((0.42, 0.32, 1.4), (0, 0, 0), base=True)
    return m


def grit_bin() -> Model:
    m = Model("grit_bin")
    m.box((0.85, 0.6, 0.6), (0, 0, 0), "safety", base=True, bevel=0.05, seg=3)
    m.box((0.9, 0.66, 0.08), (0, 0, 0.62), "safety", base=True, bevel=0.03, rot=(-8, 0, 0))
    m.box((0.4, 0.01, 0.12), (0, -0.305, 0.38), "dark", base=True, bevel=0.0)
    m.collide_box((0.9, 0.65, 0.72), (0, 0, 0), base=True)
    return m


MODELS = {f.__name__: f for f in (bin_vigipirate, waste_container, bin_underground, recycling_column,
                                  recycling_underground, parcel_locker, vending_machine, parking_meter, post_box, grit_bin)}
