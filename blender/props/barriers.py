"""Gates, barriers and fence pieces. Gates span the model's x axis (the Godot builder stretches x to the width
of the way); their leaves are drawn open so the way stays walkable. Fence panels are 2.5 m long and 1 m high
(stretched to the fence segment and height), posts 1 m high. Front = -Y, origin on the ground."""
import math

from toylib import Model

PANEL = 2.5


def _leaf(m: Model, hinge_x: float, width: float, height: float, open_deg: float, side: int, bars: int = 8):
    """Gate leaf hinged at x = hinge_x, swung open by open_deg towards +Y; side = +1 extends towards +x."""
    a = math.radians(open_deg)
    ux, uy = side * math.cos(a), math.sin(a)
    rot = math.degrees(math.atan2(uy, ux))
    cx, cy = hinge_x + ux * width / 2, uy * width / 2
    for z in (0.15, height - 0.05):
        m.box((width, 0.05, 0.05), (cx, cy, z), "anthracite", rot=(0, 0, rot), bevel=0.012)
    for k in range(bars + 1):
        t = k / bars
        m.box((0.03, 0.03, height - 0.15), (hinge_x + ux * width * t, uy * width * t, 0.12), "anthracite", base=True, bevel=0.0)
    m.collide_box((0.08, 0.08, height), (hinge_x + ux * width, uy * width, 0), base=True)


def gate() -> Model:
    """Vehicle gate 4 m: two posts and two barred leaves standing open."""
    m = Model("gate", view_range=250.0)
    for s in (-1, 1):
        m.box((0.14, 0.14, 1.75), (s * 2.07, 0, 0), "anthracite", base=True, bevel=0.02)
        m.sphere(0.08, (s * 2.07, 0, 1.78), "anthracite", seg=10)
        m.collide_box((0.16, 0.16, 1.8), (s * 2.07, 0, 0), base=True)
        _leaf(m, s * 2.0, 1.95, 1.5, 78, -s)
    m.info["span"] = 4.0
    return m


def gate_small() -> Model:
    """Pedestrian gate 1.2 m, open."""
    m = Model("gate_small", view_range=200.0)
    for s in (-1, 1):
        m.box((0.1, 0.1, 1.3), (s * 0.62, 0, 0), "anthracite", base=True, bevel=0.015)
        m.collide_box((0.12, 0.12, 1.3), (s * 0.62, 0, 0), base=True)
    _leaf(m, -0.57, 1.1, 1.1, 85, 1, bars=6)
    m.info["span"] = 1.2
    return m


def swing_gate() -> Model:
    """Single swinging bar gate 3.5 m (red and white), open along the verge."""
    m = Model("swing_gate", view_range=250.0)
    m.box((0.14, 0.14, 1.1), (-1.8, 0, 0), "anthracite", base=True, bevel=0.02)
    m.box((0.12, 0.12, 0.9), (1.8, 0, 0), "anthracite", base=True, bevel=0.02)
    for k in range(7):
        x = -1.75 + 0.5 * k + 0.25
        m.box((0.5, 0.08, 0.08), (-1.75 + 0.06, 0.25 + 0.5 * k, 0.95), "sign_red" if k % 2 else "white", bevel=0.01, rot=(0, 0, 90))
        del x
    m.collide_box((0.16, 0.16, 1.1), (-1.8, 0, 0), base=True)
    m.collide_box((0.14, 0.14, 0.9), (1.8, 0, 0), base=True)
    m.info["span"] = 3.5
    return m


def lift_gate() -> Model:
    """Barrier arm 4 m across the way (red and white) from a housing on the left post, closed."""
    m = Model("lift_gate", view_range=300.0)
    m.box((0.32, 0.32, 1.0), (-2.15, 0, 0), "white", base=True, bevel=0.04, seg=3)
    m.box((0.34, 0.34, 0.1), (-2.15, 0, 1.0), "sign_red", base=True, bevel=0.02)
    for k in range(8):
        m.box((0.5, 0.07, 0.07), (-1.75 + 0.5 * k, 0, 0.92), "sign_red" if k % 2 == 0 else "white", bevel=0.012)
    m.box((0.08, 0.08, 0.85), (2.1, 0, 0), "anthracite", base=True, bevel=0.015)
    m.collide_box((0.34, 0.34, 1.1), (-2.15, 0, 0), base=True)
    m.collide_box((4.0, 0.1, 0.12), (0.0, 0, 0.86), base=True)
    m.info["span"] = 4.0
    return m


def cycle_barrier() -> Model:
    """Staggered chicane of two U-bars (walk or wheel your bike through)."""
    m = Model("cycle_barrier", view_range=150.0)
    for x0, y in ((-1.0, -0.55), (-0.2, 0.55)):
        m.tube([(x0, y, -0.05), (x0, y, 0.9), (x0 + 0.1, y, 1.0), (x0 + 1.1, y, 1.0), (x0 + 1.2, y, 0.9), (x0 + 1.2, y, -0.05)],
               0.03, "white", sides=8)
        m.tube([(x0, y, 0.5), (x0 + 1.2, y, 0.5)], 0.025, "sign_red", sides=8)
        m.collide_box((1.25, 0.08, 1.0), (x0 + 0.6, y, 0), base=True)
    m.info["span"] = 2.0
    return m


def chain_posts() -> Model:
    m = Model("chain_posts", view_range=120.0)
    for s in (-1, 1):
        m.cyl(0.06, 0.8, (s * 1.5, 0, 0), "anthracite", sides=12, bevel=0.015)
        m.collide_cyl(0.08, 0.8, (s * 1.5, 0, 0))
    m.tube([(x, 0, 0.7 - 0.25 * (1 - (x / 1.5) ** 2)) for x in [i * 0.25 - 1.5 for i in range(13)]], 0.015, "sign_red", sides=6)
    m.info["span"] = 3.0
    return m


def turnstile() -> Model:
    m = Model("turnstile", view_range=120.0)
    m.box((0.3, 0.3, 1.0), (-0.45, 0, 0), "steel", base=True, bevel=0.04)
    m.cyl(0.05, 1.0, (0, 0, 0), "steel", sides=12, bevel=0.01)
    for a in (0, 120, 240):
        m.tube([(0, 0, 0.9), (0.42 * math.cos(math.radians(a)), 0.42 * math.sin(math.radians(a)), 0.75)], 0.022, "silver")
    m.collide_cyl(0.07, 1.0)
    m.collide_box((0.3, 0.3, 1.0), (-0.45, 0, 0), base=True)
    m.info["span"] = 1.0
    return m


def height_bar() -> Model:
    m = Model("height_bar", view_range=300.0)
    for s in (-1, 1):
        m.box((0.16, 0.16, 2.55), (s * 2.1, 0, 0), "anthracite", base=True, bevel=0.02)
        m.collide_box((0.18, 0.18, 2.55), (s * 2.1, 0, 0), base=True)
    for k in range(9):
        m.box((0.47, 0.12, 0.2), (-1.88 + 0.47 * k, 0, 2.35), "sign_red" if k % 2 == 0 else "white", base=True, bevel=0.015)
    m.info["span"] = 4.0
    return m


# ---------------------------------------------------------------- fences (stretched by the Godot builder)

def fence_post_bars() -> Model:
    m = Model("fence_post_bars", view_range=200.0)
    m.box((0.07, 0.07, 1.03), (0, 0, -0.03), "anthracite", base=True, bevel=0.012)
    return m


def fence_panel_bars() -> Model:
    """Steel railing: two rails and vertical bars every 12 cm."""
    m = Model("fence_panel_bars", view_range=200.0)
    for z in (0.08, 0.94):
        m.box((PANEL, 0.04, 0.04), (0, 0, z), "anthracite", bevel=0.008)
    n = int(PANEL / 0.12)
    for k in range(n):
        m.box((0.022, 0.022, 0.92), (-PANEL / 2 + (k + 0.5) * PANEL / n, 0, 0.05), "anthracite", base=True, bevel=0.0)
    return m


def fence_post_mesh() -> Model:
    m = Model("fence_post_mesh", view_range=200.0)
    m.cyl(0.03, 1.03, (0, 0, -0.03), "sign_green", sides=8, bevel=0.0)
    return m


def fence_panel_mesh() -> Model:
    """Chain-link mesh: a frame and a fine grid of green wires."""
    m = Model("fence_panel_mesh", view_range=200.0)
    for z in (0.03, 0.98):
        m.box((PANEL, 0.025, 0.025), (0, 0, z), "sign_green", bevel=0.0)
    for k in range(17):
        x = -PANEL / 2 + (k + 0.5) * PANEL / 17
        m.box((0.008, 0.008, 0.95), (x, 0, 0.03), "#3f7a55", base=True, bevel=0.0)
    for z in (0.22, 0.41, 0.6, 0.79):
        m.box((PANEL, 0.008, 0.008), (0, 0, z), "#3f7a55", bevel=0.0)
    return m


def fence_post_wood() -> Model:
    m = Model("fence_post_wood", view_range=200.0)
    m.box((0.1, 0.1, 1.06), (0, 0, -0.03), "wood_dark", base=True, bevel=0.015)
    return m


def fence_panel_wood() -> Model:
    """Picket fence: two rails and rounded pickets."""
    m = Model("fence_panel_wood", view_range=200.0)
    for z in (0.25, 0.75):
        m.box((PANEL, 0.03, 0.07), (0, 0.04, z), "wood_dark", bevel=0.01)
    n = 15
    for k in range(n):
        m.box((0.09, 0.02, 0.95), (-PANEL / 2 + (k + 0.5) * PANEL / n, 0.0, 0.03), "wood", base=True, bevel=0.012)
    return m


def wall_block() -> Model:
    """Garden wall piece 1 m long, 0.3 m thick, 1 m high with a coping (stretched along x and z)."""
    m = Model("wall_block", view_range=300.0)
    m.box((1.0, 0.3, 0.94), (0, 0, -0.02), "stone", base=True, bevel=0.0)
    m.box((1.0, 0.36, 0.08), (0, 0, 0.92), "concrete", base=True, bevel=0.0)
    return m


def guard_rail_post() -> Model:
    m = Model("guard_rail_post", view_range=200.0)
    m.box((0.1, 0.12, 0.75), (0, 0.05, -0.05), "steel", base=True, bevel=0.0)
    return m


def guard_rail_panel() -> Model:
    m = Model("guard_rail_panel", view_range=200.0)
    m.box((PANEL, 0.06, 0.12), (0, -0.04, 0.62), "silver", bevel=0.02)
    m.box((PANEL, 0.04, 0.08), (0, -0.04, 0.52), "steel", bevel=0.015)
    return m


MODELS = {f.__name__: f for f in (gate, gate_small, swing_gate, lift_gate, cycle_barrier, chain_posts, turnstile,
                                  height_bar, fence_post_bars, fence_panel_bars, fence_post_mesh, fence_panel_mesh,
                                  fence_post_wood, fence_panel_wood, wall_block, guard_rail_post, guard_rail_panel)}
FENCES = {"bars": ("fence_post_bars", "fence_panel_bars"), "mesh": ("fence_post_mesh", "fence_panel_mesh"),
          "wood": ("fence_post_wood", "fence_panel_wood"), "wall": ("", "wall_block"),
          "guard_rail": ("guard_rail_post", "guard_rail_panel")}
